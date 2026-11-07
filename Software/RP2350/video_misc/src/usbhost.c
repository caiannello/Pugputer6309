/* The USB host (TinyUSB) on the RP2350's own port: keyboards and mice, through a small
 * unpowered hub, as the card's input: vc_key(), vc_mouse_by() and vc_mouse_wheel(), as the
 * emulator's window gives them (card.c locks the copy for those). Each is asked for its
 * boot protocol, so its reports have a fixed form: a keyboard's the modifiers and up to six
 * keys held, a mouse's its buttons and movement (and the wheel, which most send too).
 * Gamepads report in a form of their own: not yet.
 *
 * The hub and the devices take their power from VBUS, which the card has to supply (the
 * board's VBUS is otherwise only fed by a PC, for flashing). Everything here runs in core
 * 0's main loop (tuh_task); TinyUSB's interrupt is under the bus's. */
#include "usbhost.h"

#include <string.h>

#include "card.h"
#include "tusb.h"

#if VIDCARD_DIAG
volatile uint32_t diag_usb_devices, diag_usb_keys, diag_usb_mouse;
#endif

/* Each keyboard's last report, to see what changed. */
#define KEYBOARDS 4
static struct {
    uint8_t dev, idx, used;
    uint8_t mods, keys[6];
} kbd[KEYBOARDS];

void usbhost_init(void) { tuh_init(BOARD_TUH_RHPORT); }

void usbhost_poll(void) { tuh_task(); }

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

static void key(uint8_t usage, int down) {
    card_key(usage, down != 0);
#if VIDCARD_DIAG
    ++diag_usb_keys;
#endif
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

/* A mouse's report: buttons, X, Y (and the wheel, if it sends one). */
static void mouse(const uint8_t *r, uint16_t len) {
    if (len < 3) return;
    card_mouse((int8_t)r[1], (int8_t)r[2], (uint8_t)(r[0] & 7), len >= 4 ? (int8_t)r[3] : 0);
#if VIDCARD_DIAG
    ++diag_usb_mouse;
#endif
}

void tuh_mount_cb(uint8_t dev) {
    (void)dev;
#if VIDCARD_DIAG
    ++diag_usb_devices;
#endif
}

void tuh_umount_cb(uint8_t dev) {
    (void)dev;
#if VIDCARD_DIAG
    --diag_usb_devices;
#endif
}

void tuh_hid_mount_cb(uint8_t dev, uint8_t idx, uint8_t const *desc, uint16_t len) {
    (void)desc;
    (void)len;
    uint8_t p = tuh_hid_interface_protocol(dev, idx);
    if (p == HID_ITF_PROTOCOL_KEYBOARD) kbd_slot(dev, idx, 1);
    if (p == HID_ITF_PROTOCOL_KEYBOARD || p == HID_ITF_PROTOCOL_MOUSE) tuh_hid_receive_report(dev, idx);
}

void tuh_hid_umount_cb(uint8_t dev, uint8_t idx) {
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
    else if (p == HID_ITF_PROTOCOL_MOUSE) mouse(report, len);
    tuh_hid_receive_report(dev, idx); /* (the next) */
}
