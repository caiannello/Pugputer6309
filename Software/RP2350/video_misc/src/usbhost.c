/* The USB host (TinyUSB) on the RP2350's own port: keyboards and mice, through a small
 * unpowered hub, as the card's input: vc_key(), vc_mouse_by() and vc_mouse_wheel(), as the
 * emulator's window gives them (card.c locks the copy for those). Each is asked for its
 * boot protocol, so its reports have a fixed form: a keyboard's the modifiers and up to six
 * keys held, a mouse's its buttons and movement. Boot reports have no wheel, so a mouse
 * whose report descriptor shows one is then moved to report protocol, and read by where
 * its descriptor says things are. That descriptor is fetched again once it's there: some
 * mice (Logitech's 046d:c077) describe a simpler report while in boot protocol than they
 * send in report protocol. Gamepads (generic HID ones) report in a form of their own, read
 * by the same means, and go to vc_pad().
 *
 * The hub and the devices take their power from VBUS, which the card has to supply (the
 * board's VBUS is otherwise only fed by a PC, for flashing). Everything here runs in core
 * 0's main loop (tuh_task); TinyUSB's interrupt is under the bus's. */
#include "usbhost.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "card.h"
#include "hardware/timer.h"
#include "tusb.h"

#if VIDCARD_DIAG
volatile uint32_t diag_usb_devices, diag_usb_keys, diag_usb_mouse;
uint8_t diag_mouse_desc[DIAG_MOUSE_DESC];
uint16_t diag_mouse_desc_len, diag_mouse_vid, diag_mouse_pid;
uint8_t diag_mouse_proto, diag_mouse_len_min, diag_mouse_len_max, diag_mouse_seen[8];
uint8_t diag_mouse_log[DIAG_MOUSE_LOG][9];
uint32_t diag_mouse_logged;
char diag_mouse_layout[80];
volatile uint32_t diag_usb_pad;
uint8_t diag_pad_desc[DIAG_PAD_DESC];
uint16_t diag_pad_desc_len, diag_pad_vid, diag_pad_pid;
uint8_t diag_pad_len_max, diag_pad_changed[DIAG_PAD_BYTES], diag_pad_log[DIAG_PAD_LOG][DIAG_PAD_BYTES + 1];
uint32_t diag_pad_logged;
char diag_pad_layout[140];
diag_dev diag_devs[DIAG_DEVS];
uint8_t diag_pad_dev, diag_pad_idx, diag_pad_speed, diag_pad_armed0, diag_pad_cfg;
#endif

/* Each keyboard's last report, to see what changed. */
#define KEYBOARDS 4
static struct {
    uint8_t dev, idx, used;
    uint8_t mods, keys[6];
} kbd[KEYBOARDS];

/* Where in a report something is: its first bit (after any report ID) and how many
 * (0: the report hasn't got one). */
typedef struct {
    uint16_t pos;
    uint8_t size;
} field;

/* What's still to be asked of a mouse with a wheel (see usbhost_poll). */
enum { STEP_NONE, STEP_REPORT, STEP_DESC, STEP_BOOT };

/* Each mouse with a wheel: where its report descriptor puts things. */
#define MICE 4
typedef struct {
    uint8_t dev, idx, used;
    uint8_t step;
    uint8_t in_report; /* it's in report protocol: read by the fields below */
    uint8_t gave_up;   /* its reports didn't match its descriptor: the boot form for good */
    uint8_t checked;   /* a report's length has been compared with the descriptor's */
    uint8_t id;        /* the report ID to read, or 0 if its reports have none */
    uint8_t bytes;     /* how long the descriptor says that report is, with any ID */
    uint16_t desc_len;
    field x, y, wheel, button[3];
} mouse_info;
static mouse_info mice[MICE];

/* A control with a range: a stick's axis, or a hat. */
typedef struct {
    field f;
    int32_t lo, hi;
} axis;

/* Each gamepad, by its number on the card: where its report descriptor puts things. */
#define PAD_BUTTONS 16
typedef struct {
    uint8_t dev, idx, used;
    uint8_t found, id; /* the report ID to read, or 0 if its reports have none */
    field button[PAD_BUTTONS];
    field dpad[4]; /* up, down, right, left, for the few pads that name them */
    axis x, y, z, rx, ry, rz, hat;
} pad_info;
static pad_info pads[VC_PADS];

/* The descriptor being fetched again (only one control transfer at a time, so one will do). */
static CFG_TUH_MEM_ALIGN uint8_t mouse_desc[CFG_TUH_ENUMERATION_BUFSIZE];

void usbhost_init(void) { tuh_init(BOARD_TUH_RHPORT); }

static int mouse_slot(uint8_t dev, uint8_t idx, int make) {
    for (int i = 0; i < MICE; ++i)
        if (mice[i].used && mice[i].dev == dev && mice[i].idx == idx) return i;
    if (!make) return -1;
    for (int i = 0; i < MICE; ++i)
        if (!mice[i].used) {
            memset(&mice[i], 0, sizeof mice[i]);
            mice[i].used = 1, mice[i].dev = dev, mice[i].idx = idx;
            return i;
        }
    return -1;
}

/* One field of an Input item in a report descriptor, as hid_walk finds them. */
typedef struct {
    uint32_t usage, app; /* its usage, and its top-level collection's (page << 16 | usage) */
    field f;
    uint8_t id;
    bool relative;
    int32_t lmin, lmax; /* its logical range */
} hid_item;
typedef void (*hid_cb)(void *ctx, const hid_item *it);

/* Each report ID's input bits so far (RAM is tight, and a device has only a few IDs: past
 * this many, the rest share the last entry and those reports would be misread). */
#define HID_IDS 16
static struct {
    uint8_t id;
    uint16_t bits;
} hid_ids[HID_IDS];
static int hid_nids;

static uint16_t *hid_bits(uint8_t id) {
    for (int i = 0; i < hid_nids; ++i)
        if (hid_ids[i].id == id) return &hid_ids[i].bits;
    if (hid_nids == HID_IDS) return &hid_ids[HID_IDS - 1].bits;
    hid_ids[hid_nids].id = id;
    hid_ids[hid_nids].bits = 0;
    return &hid_ids[hid_nids++].bits;
}

/* Calls cb for every variable data field of a report descriptor's Input items. */
static void hid_walk(const uint8_t *d, uint16_t len, hid_cb cb, void *ctx) {
    typedef struct {
        uint32_t page;
        uint8_t size, count, id;
        int32_t lmin, lmax;
        uint32_t lmax_raw;
    } globals;
    globals g = {0}, stack[4];
    int depth = 0, collections = 0;
    uint32_t usage[12], umin = 0, umax = 0, app = 0;
    int nusage = 0;
    hid_nids = 0;

    for (uint16_t i = 0; i < len;) {
        uint8_t b = d[i++];
        if (b == 0xFE) { /* a long item: none we want */
            if (i >= len) break;
            i = (uint16_t)(i + 2 + d[i]);
            continue;
        }
        uint8_t n = (uint8_t)((b & 3) == 3 ? 4 : b & 3), type = (b >> 2) & 3, tag = b >> 4;
        if (i + n > len) break;
        uint32_t v = 0;
        for (int k = 0; k < n; ++k) v |= (uint32_t)d[i + k] << (8 * k);
        i = (uint16_t)(i + n);
        int32_t sv = n == 1 ? (int8_t)v : n == 2 ? (int16_t)v : (int32_t)v;

        if (type == 1) { /* global */
            switch (tag) {
            case 0: g.page = v; break;
            case 1: g.lmin = sv; break;
            case 2: g.lmax = sv, g.lmax_raw = v; break;
            case 7: g.size = (uint8_t)v; break;
            case 8: g.id = (uint8_t)v; break;
            case 9: g.count = (uint8_t)v; break;
            case 10: if (depth < 4) stack[depth++] = g; break;
            case 11: if (depth) g = stack[--depth]; break;
            default: break;
            }
        } else if (type == 2) { /* local */
            if (tag == 0 && nusage < 12) usage[nusage++] = n == 4 ? v : (g.page << 16 | v);
            else if (tag == 1) umin = n == 4 ? v : (g.page << 16 | v);
            else if (tag == 2) umax = n == 4 ? v : (g.page << 16 | v);
        } else if (type == 0) { /* main: each ends the local items */
            if (tag == 10) { /* Collection */
                if (collections++ == 0 && v == 1) app = nusage ? usage[0] : 0;
            } else if (tag == 12) { /* End Collection */
                if (collections && --collections == 0) app = 0;
            } else if (tag == 8) { /* Input */
                uint16_t *bits = hid_bits(g.id);
                if (!(v & 1) && (v & 2))
                    for (int k = 0; k < g.count; ++k) {
                        hid_item it;
                        it.usage = k < nusage ? usage[k] : nusage ? usage[nusage - 1]
                                 : (umin + (uint32_t)k <= umax) ? umin + (uint32_t)k : 0;
                        it.app = app;
                        it.f.pos = (uint16_t)(*bits + k * g.size);
                        it.f.size = g.size;
                        it.id = g.id;
                        it.relative = (v & 4) != 0;
                        it.lmin = g.lmin;
                        /* (a sloppy pad's 25 FF means 255, not -1) */
                        it.lmax = g.lmax < g.lmin ? (int32_t)g.lmax_raw : g.lmax;
                        cb(ctx, &it);
                    }
                *bits = (uint16_t)(*bits + g.size * g.count);
            }
            nusage = 0, umin = umax = 0;
        }
    }
}

static void mouse_clear(mouse_info *m) {
    memset(&m->x, 0, sizeof m->x), memset(&m->y, 0, sizeof m->y);
    memset(&m->wheel, 0, sizeof m->wheel), memset(m->button, 0, sizeof m->button);
}

static void mouse_item(void *ctx, const hid_item *it) {
    mouse_info *m = ctx;
    /* Whichever report has X is the one; what came before it from another is not. */
    if (!m->x.size && it->id != m->id) mouse_clear(m), m->id = it->id;
    if (it->id != m->id) return;
    uint32_t u = it->usage;
    if (u >= 0x90001 && u <= 0x90003 && it->f.size == 1) m->button[u - 0x90001] = it->f;
    else if (it->f.size < 1 || it->f.size > 16 || !it->relative) return;
    else if (u == 0x10030) m->x = it->f;
    else if (u == 0x10031) m->y = it->f;
    else if (u == 0x10038) m->wheel = it->f;
}

/* A report descriptor, read for the mouse's X, Y, wheel and first three buttons. True if it
 * has relative X, Y and a wheel, all in one report. */
static bool parse_mouse(mouse_info *m, const uint8_t *d, uint16_t len) {
    m->id = 0;
    mouse_clear(m);
    hid_walk(d, len, mouse_item, m);
    m->bytes = (uint8_t)((*hid_bits(m->id) + 7) / 8 + (m->id ? 1 : 0));
    return m->x.size && m->y.size && m->wheel.size;
}

/* A gamepad's report descriptor: called a joystick or a gamepad at its top level. */
static void pad_item(void *ctx, const hid_item *it) {
    pad_info *p = ctx;
    if (it->app != 0x10004 && it->app != 0x10005) return;
    uint32_t u = it->usage;
    field *b = NULL;
    axis *a = NULL;
    if (u >= 0x90001 && u < 0x90001 + PAD_BUTTONS) b = &p->button[u - 0x90001];
    else if (u >= 0x10090 && u <= 0x10093) b = &p->dpad[u - 0x10090];
    else if (u == 0x10030) a = &p->x;
    else if (u == 0x10031) a = &p->y;
    else if (u == 0x10032) a = &p->z;
    else if (u == 0x10033) a = &p->rx;
    else if (u == 0x10034) a = &p->ry;
    else if (u == 0x10035) a = &p->rz;
    else if (u == 0x10039) a = &p->hat;
    else return;
    if (it->f.size < 1 || it->f.size > 16) return;
    if (!p->found) p->found = 1, p->id = it->id; /* (the first report with any of these) */
    if (it->id != p->id) return;
    if (b) *b = it->f;
    else a->f = it->f, a->lo = it->lmin, a->hi = it->lmax;
}

#if VIDCARD_DIAG
static void diag_layout(const mouse_info *m) {
    snprintf(diag_mouse_layout, sizeof diag_mouse_layout,
             "id %u, buttons at %u %u %u, x %u+%u, y %u+%u, wheel %u+%u, %u bytes", m->id, m->button[0].pos,
             m->button[1].pos, m->button[2].pos, m->x.pos, m->x.size, m->y.pos, m->y.size, m->wheel.pos,
             m->wheel.size, m->bytes);
}
#endif

static bool field_in_report(uint16_t len, uint16_t base, field f) {
    return f.size && (uint32_t)(base + f.pos + f.size - 1) / 8 < len;
}

/* One field of a report, as it stands (0 if the report stops short of it). */
static uint32_t field_bits(const uint8_t *r, uint16_t len, uint16_t base, field f) {
    if (!field_in_report(len, base, f)) return 0;
    uint32_t v = 0;
    for (int i = 0; i < f.size; ++i) {
        uint32_t bit = (uint32_t)(base + f.pos + i);
        v |= (uint32_t)((r[bit / 8] >> (bit & 7)) & 1) << i;
    }
    return v;
}

/* The same, sign-extended. */
static int report_field(const uint8_t *r, uint16_t len, uint16_t base, field f) {
    uint32_t v = field_bits(r, len, base, f);
    if (f.size <= 1) return (int)v;
    return (v & (1u << (f.size - 1))) ? (int)v - (1 << f.size) : (int)v;
}

/* A stick's axis as -127 to 127, 0 in the middle of its range. Values close to the middle
 * read 0: a stick left alone doesn't come back to exactly the centre, and a digital pad's
 * centre is often 127 of 0-255. */
static int8_t axis_value(const uint8_t *r, uint16_t len, uint16_t base, const axis *a) {
    if (!field_in_report(len, base, a->f)) return 0;
    int32_t lo = a->lo, hi = a->hi;
    if (hi <= lo) lo = 0, hi = (int32_t)((1ul << a->f.size) - 1); /* (no usable range given) */
    int32_t v = lo < 0 ? report_field(r, len, base, a->f) : (int32_t)field_bits(r, len, base, a->f);
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    int32_t n = ((v - lo) * 2 - (hi - lo)) * 127 / (hi - lo);
    return (int8_t)(n > -8 && n < 8 ? 0 : n);
}

/* The d-pad: a hat if it has one, the buttons if it names them, otherwise X and Y (many
 * simple pads' crosses are just those). */
static uint8_t pad_dpad(const pad_info *p, const uint8_t *r, uint16_t len, uint16_t base, int lx, int ly) {
    static const uint8_t dirs[8] = {
        VC_PAD_UP, VC_PAD_UP | VC_PAD_RIGHT, VC_PAD_RIGHT, VC_PAD_DOWN | VC_PAD_RIGHT,
        VC_PAD_DOWN, VC_PAD_DOWN | VC_PAD_LEFT, VC_PAD_LEFT, VC_PAD_UP | VC_PAD_LEFT};
    if (p->hat.f.size) {
        if (!field_in_report(len, base, p->hat.f)) return 0; /* (0 would be up) */
        int32_t lo = p->hat.lo, n = p->hat.hi - lo + 1;
        if (n <= 1) lo = 0, n = 8;
        int32_t i = (int32_t)field_bits(r, len, base, p->hat.f) - lo;
        if (n == 4) i *= 2; /* (four positions, a quarter turn apart) */
        return i >= 0 && i < 8 ? dirs[i] : 0; /* (outside the range: centred) */
    }
    if (p->dpad[0].size || p->dpad[1].size || p->dpad[2].size || p->dpad[3].size) {
        static const uint8_t bit[4] = {VC_PAD_UP, VC_PAD_DOWN, VC_PAD_RIGHT, VC_PAD_LEFT};
        uint8_t d = 0;
        for (int i = 0; i < 4; ++i)
            if (field_bits(r, len, base, p->dpad[i])) d |= bit[i];
        return d;
    }
    return (uint8_t)((ly <= -64 ? VC_PAD_UP : 0) | (ly >= 64 ? VC_PAD_DOWN : 0) | (lx <= -64 ? VC_PAD_LEFT : 0) |
                     (lx >= 64 ? VC_PAD_RIGHT : 0));
}

/* A gamepad's report, as the card's eight bytes. */
static void pad(int s, const uint8_t *r, uint16_t len) {
    const pad_info *p = &pads[s];
#if VIDCARD_DIAG
    if (s == 0) {
        uint8_t n = (uint8_t)(len > DIAG_PAD_BYTES ? DIAG_PAD_BYTES : len);
        const uint8_t *last = diag_pad_log[(diag_pad_logged + DIAG_PAD_LOG - 1) % DIAG_PAD_LOG];
        if (len > diag_pad_len_max) diag_pad_len_max = (uint8_t)(len > 255 ? 255 : len);
        if (!diag_pad_logged || last[0] != n || memcmp(last + 1, r, n)) { /* (only the ones that differ) */
            if (diag_pad_logged && last[0] == n)
                for (int i = 0; i < n; ++i) diag_pad_changed[i] |= (uint8_t)(last[i + 1] ^ r[i]);
            uint8_t *e = diag_pad_log[diag_pad_logged++ % DIAG_PAD_LOG];
            e[0] = n;
            memcpy(e + 1, r, n);
        }
        ++diag_usb_pad;
    }
#endif
    if (p->id && (!len || r[0] != p->id)) return; /* (another of its reports) */
    uint16_t base = p->id ? 8 : 0;
    uint8_t s8[VC_PAD_SIZE] = {0};
    int lx = axis_value(r, len, base, &p->x), ly = axis_value(r, len, base, &p->y);
    /* The right stick: Z and Rz on most pads; Rx and Ry where those aren't there. */
    s8[VC_PAD_LX] = (uint8_t)lx;
    s8[VC_PAD_LY] = (uint8_t)ly;
    s8[VC_PAD_RX] = (uint8_t)axis_value(r, len, base, p->z.f.size ? &p->z : &p->rx);
    s8[VC_PAD_RY] = (uint8_t)axis_value(r, len, base, p->rz.f.size ? &p->rz : &p->ry);
    s8[VC_PAD_DPAD] = pad_dpad(p, r, len, base, lx, ly);
    for (int i = 0; i < PAD_BUTTONS; ++i)
        if (field_bits(r, len, base, p->button[i])) s8[i < 8 ? VC_PAD_BTN1 : VC_PAD_BTN2] |= (uint8_t)(1u << (i & 7));
    card_pad(s, s8);
}

static int pad_slot(uint8_t dev, uint8_t idx) {
    for (int i = 0; i < VC_PADS; ++i)
        if (pads[i].used && pads[i].dev == dev && pads[i].idx == idx) return i;
    return -1;
}

/* A HID interface that isn't a boot keyboard or mouse: taken if its descriptor says it's a
 * gamepad, as the lowest pad number free. */
static void pad_mount(uint8_t dev, uint8_t idx, const uint8_t *desc, uint16_t len) {
    pad_info t;
    memset(&t, 0, sizeof t);
    if (desc) hid_walk(desc, len, pad_item, &t); /* (no desc: too long for TinyUSB to fetch) */
    if (!t.found) {
#if VIDCARD_DIAG
        if (!pads[0].used) { /* (the block a pad 0 would use, to show what this one was) */
            tuh_vid_pid_get(dev, &diag_pad_vid, &diag_pad_pid);
            diag_pad_desc_len = desc ? len : 0;
            if (desc) memcpy(diag_pad_desc, desc, len > DIAG_PAD_DESC ? DIAG_PAD_DESC : len);
            snprintf(diag_pad_layout, sizeof diag_pad_layout,
                     desc ? "not a gamepad: no joystick or gamepad collection with controls" : "descriptor too long to fetch");
        }
#endif
        return;
    }
    int s = 0;
    while (s < VC_PADS && pads[s].used) ++s;
    if (s == VC_PADS) return;
    t.dev = dev, t.idx = idx, t.used = 1;
    pads[s] = t;
    const uint8_t neutral[VC_PAD_SIZE] = {0};
    card_pad(s, neutral); /* (connected: its first report may be a while coming) */
#if VIDCARD_DIAG
    if (s == 0) {
        tuh_vid_pid_get(dev, &diag_pad_vid, &diag_pad_pid);
        diag_pad_desc_len = len;
        memcpy(diag_pad_desc, desc, len > DIAG_PAD_DESC ? DIAG_PAD_DESC : len);
        diag_pad_len_max = 0, diag_pad_logged = 0;
        memset(diag_pad_changed, 0, sizeof diag_pad_changed);
        int buttons = 0;
        for (int i = 0; i < PAD_BUTTONS; ++i) buttons += t.button[i].size != 0;
        snprintf(diag_pad_layout, sizeof diag_pad_layout,
                 "id %u, %d buttons (1 at %u), x %u+%u, y %u+%u, z %u+%u, rx %u+%u, ry %u+%u, rz %u+%u, hat %u+%u", t.id,
                 buttons, t.button[0].pos, t.x.f.pos, t.x.f.size, t.y.f.pos, t.y.f.size, t.z.f.pos, t.z.f.size,
                 t.rx.f.pos, t.rx.f.size, t.ry.f.pos, t.ry.f.size, t.rz.f.pos, t.rz.f.size, t.hat.f.pos, t.hat.f.size);
    }
#endif
    tuh_hid_receive_report(dev, idx);
#if VIDCARD_DIAG
    if (s == 0) {
        diag_pad_dev = dev, diag_pad_idx = idx, diag_pad_speed = (uint8_t)tuh_speed_get(dev);
        diag_pad_armed0 = !tuh_hid_receive_ready(dev, idx); /* (a read is waiting at the pad) */
        diag_pad_cfg = 1; /* (its configuration descriptor to be fetched: see usbhost_poll) */
    }
#endif
}

#if VIDCARD_DIAG
bool diag_pad_armed(void) { return diag_pad_dev && !tuh_hid_receive_ready(diag_pad_dev, diag_pad_idx); }

static void diag_cfg_done(tuh_xfer_t *x) {
    if (x->result != XFER_RESULT_SUCCESS || !diag_pad_dev) return;
    diag_pad_desc_len = (uint16_t)x->actual_len;
    memcpy(diag_pad_desc, mouse_desc, x->actual_len > DIAG_PAD_DESC ? DIAG_PAD_DESC : x->actual_len);
    diag_pad_cfg = 3;
}
#endif

static int kbd_slot(uint8_t dev, uint8_t idx, int make) {
    for (int i = 0; i < KEYBOARDS; ++i)
        if (kbd[i].used && kbd[i].dev == dev && kbd[i].idx == idx) return i;
    if (!make) return -1;
    for (int i = 0; i < KEYBOARDS; ++i)
        if (!kbd[i].used) {
            memset(&kbd[i], 0, sizeof kbd[i]);
            kbd[i].used = 1, kbd[i].dev = dev, kbd[i].idx = idx;
            return i;
        }
    return -1;
}

/* A held key repeats as on a PC: the last one pressed, after half a second, 30 times a
 * second (the keyboard itself only says it's still down). Not the modifiers or the locks. */
#define REPEAT_DELAY_US 500000
#define REPEAT_EVERY_US 33333
static uint8_t repeat_key;
static uint32_t repeat_at;

static void key(uint8_t usage, int down) {
    card_key(usage, down != 0);
#if VIDCARD_DIAG
    ++diag_usb_keys;
#endif
    if (!down) {
        if (usage == repeat_key) repeat_key = 0;
    } else if (usage < 0xE0 && usage != 0x39 && usage != 0x47 && usage != 0x53) { /* (Caps, Scroll, Num Lock) */
        repeat_key = usage;
        repeat_at = time_us_32() + REPEAT_DELAY_US;
    }
}

static int has(const uint8_t *keys, uint8_t k) {
    for (int i = 0; i < 6; ++i)
        if (keys[i] == k) return 1;
    return 0;
}

/* A keyboard's report: the keys let go of, then those pressed (modifiers first). */
static void keyboard(int s, const uint8_t *r, uint16_t len) {
    if (s < 0 || len < 8) return;
    const uint8_t mods = r[0], *keys = r + 2;
    if (keys[0] == 1) return; /* (too many keys held: "rollover", which says nothing) */
    uint8_t changed = (uint8_t)(mods ^ kbd[s].mods);
    for (int b = 0; b < 8; ++b)
        if (changed & (1u << b) && !(mods & (1u << b))) key((uint8_t)(0xE0 + b), 0);
    for (int i = 0; i < 6; ++i)
        if (kbd[s].keys[i] > 1 && !has(keys, kbd[s].keys[i])) key(kbd[s].keys[i], 0);
    for (int b = 0; b < 8; ++b)
        if (changed & (1u << b) && mods & (1u << b)) key((uint8_t)(0xE0 + b), 1);
    for (int i = 0; i < 6; ++i)
        if (keys[i] > 1 && !has(kbd[s].keys, keys[i])) key(keys[i], 1);
    kbd[s].mods = mods;
    memcpy(kbd[s].keys, keys, 6);
}

/* A mouse's report: by its descriptor if it's in report protocol, otherwise the boot form:
 * buttons, X, Y (and the wheel, if it sends one). */
static void mouse(mouse_info *m, const uint8_t *r, uint16_t len) {
#if VIDCARD_DIAG
    {
        uint8_t n = (uint8_t)(len > 8 ? 8 : len);
        if (!diag_mouse_len_min || len < diag_mouse_len_min) diag_mouse_len_min = (uint8_t)(len > 255 ? 255 : len);
        if (len > diag_mouse_len_max) diag_mouse_len_max = (uint8_t)(len > 255 ? 255 : len);
        for (int i = 0; i < n; ++i) diag_mouse_seen[i] |= r[i];
        uint8_t *e = diag_mouse_log[diag_mouse_logged++ % DIAG_MOUSE_LOG];
        e[0] = (uint8_t)(len > 255 ? 255 : len);
        memcpy(e + 1, r, n);
    }
#endif
    if (m && m->in_report) {
        if (m->id && (!len || r[0] != m->id)) return; /* (another of its reports) */
        if (!m->checked) {
            m->checked = 1;
            if (len != m->bytes) { /* not what it described: wrong movement is worse than no wheel */
#if VIDCARD_DIAG
                snprintf(diag_mouse_layout, sizeof diag_mouse_layout,
                         "reports are %u bytes, descriptor says %u: back to boot form", len, m->bytes);
#endif
                m->in_report = 0, m->step = STEP_BOOT;
                return;
            }
        }
        uint16_t base = m->id ? 8 : 0;
        uint8_t buttons = 0;
        for (int i = 0; i < 3; ++i)
            if (report_field(r, len, base, m->button[i])) buttons |= (uint8_t)(1u << i);
        card_mouse(report_field(r, len, base, m->x), report_field(r, len, base, m->y), buttons,
                   report_field(r, len, base, m->wheel));
    } else {
        if (len < 3) return;
        card_mouse((int8_t)r[1], (int8_t)r[2], (uint8_t)(r[0] & 7), len >= 4 ? (int8_t)r[3] : 0);
    }
#if VIDCARD_DIAG
    ++diag_usb_mouse;
#endif
}

void tuh_mount_cb(uint8_t dev) {
    (void)dev;
#if VIDCARD_DIAG
    ++diag_usb_devices;
    for (int i = 0; i < DIAG_DEVS; ++i)
        if (!diag_devs[i].dev) {
            diag_devs[i].dev = dev;
            diag_devs[i].hid = tuh_hid_itf_get_count(dev);
            tuh_vid_pid_get(dev, &diag_devs[i].vid, &diag_devs[i].pid);
            break;
        }
#endif
}

void tuh_umount_cb(uint8_t dev) {
    (void)dev;
#if VIDCARD_DIAG
    --diag_usb_devices;
    for (int i = 0; i < DIAG_DEVS; ++i)
        if (diag_devs[i].dev == dev) diag_devs[i].dev = 0;
#endif
}

void tuh_hid_mount_cb(uint8_t dev, uint8_t idx, uint8_t const *desc, uint16_t len) {
    (void)desc;
    (void)len;
    uint8_t p = tuh_hid_interface_protocol(dev, idx);
#if VIDCARD_DIAG
    if (p == HID_ITF_PROTOCOL_MOUSE) {
        tuh_vid_pid_get(dev, &diag_mouse_vid, &diag_mouse_pid);
        diag_mouse_proto = tuh_hid_get_protocol(dev, idx);
        diag_mouse_desc_len = desc ? len : 0;
        memcpy(diag_mouse_desc, desc, diag_mouse_desc_len > DIAG_MOUSE_DESC ? DIAG_MOUSE_DESC : diag_mouse_desc_len);
        diag_mouse_len_min = diag_mouse_len_max = 0;
        memset(diag_mouse_seen, 0, sizeof diag_mouse_seen);
        diag_mouse_logged = 0;
    }
#endif
    if (p == HID_ITF_PROTOCOL_KEYBOARD) {
        kbd_slot(dev, idx, 1);
        tuh_hid_receive_report(dev, idx);
    } else if (p == HID_ITF_PROTOCOL_MOUSE) {
        int s = mouse_slot(dev, idx, 1);
        if (s >= 0 && desc && parse_mouse(&mice[s], desc, len)) {
            mice[s].step = STEP_REPORT; /* (its reports start when that's all answered) */
            mice[s].desc_len = len;
#if VIDCARD_DIAG
            diag_layout(&mice[s]);
#endif
        } else {
#if VIDCARD_DIAG
            snprintf(diag_mouse_layout, sizeof diag_mouse_layout, "no wheel found: boot form");
#endif
            tuh_hid_receive_report(dev, idx);
        }
    } else if (p == HID_ITF_PROTOCOL_NONE) {
        pad_mount(dev, idx, desc, len);
    }
}

/* The answer to a change of protocol. In report protocol, its descriptor is asked for again;
 * if it refused, or this was the way back, it's the boot form from here on. */
void tuh_hid_set_protocol_complete_cb(uint8_t dev, uint8_t idx, uint8_t protocol) {
    int s = mouse_slot(dev, idx, 0);
    if (s < 0) return;
#if VIDCARD_DIAG
    diag_mouse_proto = protocol;
#endif
    if (protocol == HID_PROTOCOL_REPORT && !mice[s].gave_up) mice[s].step = STEP_DESC;
    else tuh_hid_receive_report(dev, idx);
}

/* The descriptor, as it is in report protocol. If that failed, what it said before is all
 * there is, and the first report's length will tell whether that was right. */
static void mouse_desc_done(tuh_xfer_t *x) {
    int s = (int)x->user_data;
    if (!mice[s].used || mice[s].dev != x->daddr) return; /* (unplugged meanwhile) */
    mouse_info t = mice[s];
    if (x->result == XFER_RESULT_SUCCESS && parse_mouse(&t, mouse_desc, (uint16_t)x->actual_len)) {
        mice[s] = t;
#if VIDCARD_DIAG
        diag_mouse_desc_len = (uint16_t)x->actual_len;
        memcpy(diag_mouse_desc, mouse_desc, diag_mouse_desc_len > DIAG_MOUSE_DESC ? DIAG_MOUSE_DESC : diag_mouse_desc_len);
        diag_layout(&mice[s]);
#endif
    }
    mice[s].in_report = 1;
    tuh_hid_receive_report(mice[s].dev, mice[s].idx);
}

static bool fetch_mouse_desc(int s) {
    tuh_itf_info_t info;
    if (!tuh_hid_itf_get_info(mice[s].dev, mice[s].idx, &info)) return false;
    return tuh_descriptor_get_hid_report(mice[s].dev, info.desc.bInterfaceNumber, HID_DESC_TYPE_REPORT, 0, mouse_desc,
                                         mice[s].desc_len, mouse_desc_done, (uintptr_t)s);
}

void usbhost_poll(void) {
    tuh_task();
    if (repeat_key && (int32_t)(time_us_32() - repeat_at) >= 0) {
        card_key_repeat(repeat_key);
        repeat_at = time_us_32() + REPEAT_EVERY_US;
#if VIDCARD_DIAG
        ++diag_usb_keys;
#endif
    }
#if VIDCARD_DIAG
    if (diag_pad_cfg == 1 &&
        tuh_descriptor_get_configuration(diag_pad_dev, 0, mouse_desc, sizeof mouse_desc, diag_cfg_done, 0))
        diag_pad_cfg = 2;
#endif
    /* Not from tuh_hid_mount_cb: the next interface's setup follows that straight away and
     * there's only one control transfer at a time, so these just try until it's free. */
    for (int i = 0; i < MICE; ++i) {
        mouse_info *m = &mice[i];
        if (!m->used) continue;
        if (m->step == STEP_REPORT) {
            if (tuh_hid_set_protocol(m->dev, m->idx, HID_PROTOCOL_REPORT)) m->step = STEP_NONE;
        } else if (m->step == STEP_DESC) {
            if (fetch_mouse_desc(i)) m->step = STEP_NONE;
        } else if (m->step == STEP_BOOT) {
            if (tuh_hid_set_protocol(m->dev, m->idx, HID_PROTOCOL_BOOT)) m->step = STEP_NONE, m->gave_up = 1;
        }
    }
}

void tuh_hid_umount_cb(uint8_t dev, uint8_t idx) {
    int m = mouse_slot(dev, idx, 0);
    if (m >= 0) mice[m].used = 0;
    int g = pad_slot(dev, idx);
    if (g >= 0) {
        pads[g].used = 0;
        card_pad(g, NULL);
#if VIDCARD_DIAG
        if (g == 0) diag_pad_dev = 0, diag_pad_cfg = 0;
#endif
    }
    int s = kbd_slot(dev, idx, 0);
    if (s < 0) return;
    /* unplugged with keys held: let go of them */
    for (int b = 0; b < 8; ++b)
        if (kbd[s].mods & (1u << b)) key((uint8_t)(0xE0 + b), 0);
    for (int i = 0; i < 6; ++i)
        if (kbd[s].keys[i] > 1) key(kbd[s].keys[i], 0);
    kbd[s].used = 0;
}

void tuh_hid_report_received_cb(uint8_t dev, uint8_t idx, uint8_t const *report, uint16_t len) {
    uint8_t p = tuh_hid_interface_protocol(dev, idx);
    if (p == HID_ITF_PROTOCOL_KEYBOARD) keyboard(kbd_slot(dev, idx, 0), report, len);
    else if (p == HID_ITF_PROTOCOL_MOUSE) {
        int s = mouse_slot(dev, idx, 0);
        mouse(s < 0 ? NULL : &mice[s], report, len);
        if (s >= 0 && mice[s].step == STEP_BOOT) return; /* (the next waits for its answer) */
    } else {
        int s = pad_slot(dev, idx);
        if (s >= 0) pad(s, report, len);
    }
    tuh_hid_receive_report(dev, idx); /* (the next) */
}
