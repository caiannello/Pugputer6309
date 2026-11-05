/* The Pugputer 6309 video card: see vc.h and ../README.md. */
#include "vc.h"

#include <string.h>

#define VRAM_MASK (VC_VRAM_SIZE - 1)

/* The interrupt flags are set by the beam (vc_begin_line), the commands and the input, and
 * cleared by the CPU. The card's firmware does those on two cores and in an interrupt
 * handler, so it builds this with VC_ATOMIC_FLAGS: each change is then one atomic step,
 * and none is lost to another made at the same moment. */
#ifdef VC_ATOMIC_FLAGS
#define SET_FLAGS(c, f) ((void)__atomic_fetch_or(&(c)->isr, (uint8_t)(f), __ATOMIC_RELAXED))
#define CLEAR_FLAGS(c, f) ((void)__atomic_fetch_and(&(c)->isr, (uint8_t)~(f), __ATOMIC_RELAXED))
#else
#define SET_FLAGS(c, f) ((c)->isr |= (uint8_t)(f))
#define CLEAR_FLAGS(c, f) ((c)->isr &= (uint8_t)~(f))
#endif

/* Parameter bytes each command takes (after its opcode). */
static const uint8_t k_params[VC_C_COUNT] = {
    0,  /* NOP */
    10, /* TARGET */
    1,  /* COLOR */
    4,  /* PLOT */
    8,  /* LINE */
    8,  /* RECT */
    8,  /* FILLRECT */
    6,  /* CIRCLE */
    6,  /* DISC */
    0,  /* CLEAR */
    9,  /* COPY */
    7,  /* FILL */
    14, /* BLIT */
    12, /* TRIANGLE */
    4,  /* FONT */
    5,  /* CHAR */
};

static uint32_t be16(const uint8_t *p) { return (uint32_t)p[0] << 8 | p[1]; }
static uint32_t be24(const uint8_t *p) { return (uint32_t)p[0] << 16 | (uint32_t)p[1] << 8 | p[2]; }
static int s16(const uint8_t *p) { return (int16_t)(uint16_t)be16(p); }

/* ---- the address space ---- */

uint8_t vc_peek(const vc_card *c, uint32_t a) {
    a &= 0xFFFFFF;
    if (a < VC_VRAM_SIZE) return c->vram[a];
    if (a - VC_CFG_BASE < VC_CFG_SIZE) return c->cfg[a - VC_CFG_BASE];
    if (a >= VC_PSRAM_BASE && c->psram) return c->psram[a - VC_PSRAM_BASE];
    return 0;
}

void vc_poke(vc_card *c, uint32_t a, uint8_t v) {
    a &= 0xFFFFFF;
    if (a < VC_VRAM_SIZE) c->vram[a] = v;
    else if (a - VC_CFG_BASE < VC_CFG_SIZE) c->cfg[a - VC_CFG_BASE] = v;
    else if (a >= VC_PSRAM_BASE && c->psram) c->psram[a - VC_PSRAM_BASE] = v;
}

/* ---- reset ---- */

static void set_color(vc_card *c, int i, int r, int g, int b) {
    uint16_t p = (uint16_t)((r >> 3) << 11 | (g >> 2) << 5 | (b >> 3));
    c->cfg[VC_PAL_BASE - VC_CFG_BASE + 2 * i] = (uint8_t)(p >> 8);
    c->cfg[VC_PAL_BASE - VC_CFG_BASE + 2 * i + 1] = (uint8_t)p;
}

static void put24(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 16);
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)v;
}

void vc_reset(vc_card *c) {
    static const uint8_t base16[16][3] = {
        {0, 0, 0},       {128, 0, 0},   {0, 128, 0},   {128, 128, 0},  {0, 0, 128},   {128, 0, 128},
        {0, 128, 128},   {192, 192, 192}, {128, 128, 128}, {255, 0, 0}, {0, 255, 0},   {255, 255, 0},
        {0, 0, 255},     {255, 0, 255}, {0, 255, 255}, {255, 255, 255}};
    static const uint8_t cube[6] = {0, 95, 135, 175, 215, 255};
    int i;
    memset(c->vram, 0, sizeof c->vram);
    memset(c->cfg, 0, sizeof c->cfg);
    /* The palette: xterm's 256 colors, so text colors are the ones ANSI terminals use. */
    for (i = 0; i < 16; ++i) set_color(c, i, base16[i][0], base16[i][1], base16[i][2]);
    for (i = 0; i < 216; ++i) set_color(c, 16 + i, cube[i / 36], cube[i / 6 % 6], cube[i % 6]);
    for (i = 0; i < 24; ++i) set_color(c, 232 + i, 8 + 10 * i, 8 + 10 * i, 8 + 10 * i);
    /* The font, and an empty 80x30 text screen (a 128x32 map) on layer 0. */
    memcpy(c->vram + VC_RESET_FONT, vc_font8x16, sizeof vc_font8x16);
    for (i = 0; i < 128 * 32; ++i) {
        uint8_t *cell = c->vram + VC_RESET_TEXT_MAP + 4 * i;
        cell[0] = ' ';
        cell[1] = 7;
        cell[2] = 0;
        cell[3] = 0;
    }
    c->cfg[VC_DC_CTRL] = 0x01;
    c->cfg[VC_SPR_COUNT] = 128;
    put24(c->cfg + VC_SPR_BASE, VC_RESET_SPR_BASE);
    c->cfg[VC_LAYER0 + VC_L_MODE] = VC_TEXT | 0x04 | 0x20; /* hires, 8x16 font */
    c->cfg[VC_LAYER0 + VC_L_MAP] = 0x02;                   /* 128 x 32 */
    put24(c->cfg + VC_LAYER0 + VC_L_MAPBASE, VC_RESET_TEXT_MAP);
    put24(c->cfg + VC_LAYER0 + VC_L_TILEBASE, VC_RESET_FONT);
    c->addr[0] = c->addr[1] = 0;
    c->inc[0] = c->inc[1] = 1;
    c->ien = c->isr = 0;
    c->irq_line = 0;
    c->cmd_len = 0;
    c->t_addr = 0;
    c->t_stride = c->t_w = c->t_h = 0;
    c->t_bpp = 8;
    c->color = 15;
    c->font = VC_RESET_FONT;
    c->font_h = 16;
    c->in_ctrl = 0;
    c->wheel = 0;
    c->key_char = 0;
    c->keyq_head = c->keyq_len = 0;
}

/* ---- drawing ---- */

static void pset(vc_card *c, int x, int y, uint8_t col) {
    uint32_t bit, a;
    if (x < 0 || y < 0 || x >= c->t_w || y >= c->t_h) return;
    bit = (uint32_t)x * c->t_bpp;
    a = c->t_addr + (uint32_t)y * c->t_stride + bit / 8;
    if (c->t_bpp == 8) {
        vc_poke(c, a, col);
    } else {
        int shift = 8 - c->t_bpp - (int)(bit & 7);
        uint8_t mask = (uint8_t)(((1u << c->t_bpp) - 1) << shift);
        vc_poke(c, a, (uint8_t)((vc_peek(c, a) & ~mask) | ((col << shift) & mask)));
    }
}

static uint8_t pget(const vc_card *c, uint32_t base, uint32_t stride, int x, int y, int bpp) {
    uint32_t bit = (uint32_t)x * bpp;
    uint8_t b = vc_peek(c, base + (uint32_t)y * stride + bit / 8);
    if (bpp == 8) return b;
    return (uint8_t)(b >> (8 - bpp - (bit & 7)) & ((1u << bpp) - 1));
}

static void hline(vc_card *c, int x0, int x1, int y, uint8_t col) {
    int x;
    if (x0 > x1) { int t = x0; x0 = x1; x1 = t; }
    if (y < 0 || y >= c->t_h) return;
    if (x0 < 0) x0 = 0;
    if (x1 >= c->t_w) x1 = c->t_w - 1;
    for (x = x0; x <= x1; ++x) pset(c, x, y, col);
}

static void line(vc_card *c, int x0, int y0, int x1, int y1) {
    int dx = x1 > x0 ? x1 - x0 : x0 - x1, sx = x0 < x1 ? 1 : -1;
    int dy = y1 > y0 ? y0 - y1 : y1 - y0, sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    for (;;) {
        int e2 = 2 * err; /* (both tests on the error as it was) */
        pset(c, x0, y0, c->color);
        if (x0 == x1 && y0 == y1) break;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}

/* The midpoint circle: the outline, or (fill) the rows between its sides. */
static void circle(vc_card *c, int cx, int cy, int r, int fill) {
    int x = r, y = 0, err = 1 - r;
    if (r < 0) return;
    while (x >= y) {
        if (fill) {
            hline(c, cx - x, cx + x, cy + y, c->color);
            hline(c, cx - x, cx + x, cy - y, c->color);
            hline(c, cx - y, cx + y, cy + x, c->color);
            hline(c, cx - y, cx + y, cy - x, c->color);
        } else {
            pset(c, cx + x, cy + y, c->color); pset(c, cx - x, cy + y, c->color);
            pset(c, cx + x, cy - y, c->color); pset(c, cx - x, cy - y, c->color);
            pset(c, cx + y, cy + x, c->color); pset(c, cx - y, cy + x, c->color);
            pset(c, cx + y, cy - x, c->color); pset(c, cx - y, cy - x, c->color);
        }
        ++y;
        if (err < 0) {
            err += 2 * y + 1;
        } else {
            --x;
            err += 2 * (y - x) + 1;
        }
    }
}

/* x on the edge (xa,ya)-(xb,yb) at row y (ya <= y <= yb), rounded to nearest. */
static int edge_x(int xa, int ya, int xb, int yb, int y) {
    long long num;
    if (yb == ya) return xa;
    num = (long long)(y - ya) * (xb - xa) * 2 + (yb - ya);
    return xa + (int)((num >= 0 ? num : num - 2 * (yb - ya) + 1) / (2 * (yb - ya)));
}

static void triangle(vc_card *c, int x0, int y0, int x1, int y1, int x2, int y2) {
    int y, t;
    /* Sorted by y. */
    if (y1 < y0) { t = x0; x0 = x1; x1 = t; t = y0; y0 = y1; y1 = t; }
    if (y2 < y0) { t = x0; x0 = x2; x2 = t; t = y0; y0 = y2; y2 = t; }
    if (y2 < y1) { t = x1; x1 = x2; x2 = t; t = y1; y1 = y2; y2 = t; }
    for (y = y0 < 0 ? 0 : y0; y <= y2 && y < c->t_h; ++y) {
        int xa = edge_x(x0, y0, x2, y2, y);
        int xb = y < y1 ? edge_x(x0, y0, x1, y1, y) : edge_x(x1, y1, x2, y2, y);
        hline(c, xa, xb, y, c->color);
    }
}

static void run_command(vc_card *c) {
    const uint8_t *p = c->cmd + 1;
    int x, y, i, j;
    switch (c->cmd[0]) {
    case VC_C_TARGET:
        c->t_addr = be24(p);
        c->t_stride = (uint16_t)be16(p + 3);
        c->t_w = (uint16_t)be16(p + 5);
        c->t_h = (uint16_t)be16(p + 7);
        c->t_bpp = p[9];
        if (c->t_bpp != 1 && c->t_bpp != 2 && c->t_bpp != 4 && c->t_bpp != 8) {
            c->t_w = c->t_h = 0; /* not a depth the card draws: nothing is drawn */
            c->t_bpp = 8;
        }
        break;
    case VC_C_COLOR: c->color = p[0]; break;
    case VC_C_PLOT: pset(c, s16(p), s16(p + 2), c->color); break;
    case VC_C_LINE: line(c, s16(p), s16(p + 2), s16(p + 4), s16(p + 6)); break;
    case VC_C_RECT: {
        int w = s16(p + 4), h = s16(p + 6);
        x = s16(p); y = s16(p + 2);
        if (w <= 0 || h <= 0) break;
        hline(c, x, x + w - 1, y, c->color);
        hline(c, x, x + w - 1, y + h - 1, c->color);
        for (j = y + 1; j < y + h - 1; ++j) {
            pset(c, x, j, c->color);
            pset(c, x + w - 1, j, c->color);
        }
        break;
    }
    case VC_C_FILLRECT: {
        int w = s16(p + 4), h = s16(p + 6);
        x = s16(p); y = s16(p + 2);
        if (w <= 0 || h <= 0) break;
        for (j = y < 0 ? 0 : y; j < y + h && j < c->t_h; ++j) hline(c, x, x + w - 1, j, c->color);
        break;
    }
    case VC_C_CIRCLE: circle(c, s16(p), s16(p + 2), s16(p + 4), 0); break;
    case VC_C_DISC: circle(c, s16(p), s16(p + 2), s16(p + 4), 1); break;
    case VC_C_CLEAR:
        for (j = 0; j < c->t_h; ++j) hline(c, 0, c->t_w - 1, j, c->color);
        break;
    case VC_C_COPY: {
        uint32_t src = be24(p), dst = be24(p + 3), len = be24(p + 6), k;
        if (dst > src && dst < src + len) {
            for (k = len; k-- > 0;) vc_poke(c, dst + k, vc_peek(c, src + k));
        } else {
            for (k = 0; k < len; ++k) vc_poke(c, dst + k, vc_peek(c, src + k));
        }
        break;
    }
    case VC_C_FILL: {
        uint32_t dst = be24(p), len = be24(p + 3), k;
        for (k = 0; k < len; ++k) vc_poke(c, dst + k, p[6]);
        break;
    }
    case VC_C_BLIT: {
        uint32_t src = be24(p), stride = be16(p + 3);
        int w = s16(p + 5), h = s16(p + 7), transparent = p[13] & 1;
        x = s16(p + 9); y = s16(p + 11);
        for (j = 0; j < h; ++j)
            for (i = 0; i < w; ++i) {
                uint8_t v = pget(c, src, stride, i, j, c->t_bpp);
                if (!(transparent && v == 0)) pset(c, x + i, y + j, v);
            }
        break;
    }
    case VC_C_TRIANGLE: triangle(c, s16(p), s16(p + 2), s16(p + 4), s16(p + 6), s16(p + 8), s16(p + 10)); break;
    case VC_C_FONT:
        c->font = be24(p);
        c->font_h = p[3] ? p[3] : 16;
        break;
    case VC_C_CHAR:
        x = s16(p); y = s16(p + 2);
        for (j = 0; j < c->font_h; ++j) {
            uint8_t bits = vc_peek(c, c->font + (uint32_t)p[4] * c->font_h + (uint32_t)j);
            for (i = 0; i < 8; ++i)
                if (bits & (0x80 >> i)) pset(c, x + i, y + j, c->color);
        }
        break;
    default: break;
    }
}

static void command_byte(vc_card *c, uint8_t v) {
    uint8_t need;
    c->cmd[c->cmd_len++] = v;
    need = c->cmd[0] < VC_C_COUNT ? k_params[c->cmd[0]] : 0; /* an unknown opcode is one byte */
    if (c->cmd_len > need) {
        run_command(c);
        c->cmd_len = 0;
        SET_FLAGS(c, VC_IRQ_CMDDONE);
    }
}

/* ---- registers ---- */

static void step_port(vc_card *c, int p) { c->addr[p] = (c->addr[p] + (uint32_t)(int16_t)c->inc[p]) & 0xFFFFFF; }

uint8_t vc_read(vc_card *c, uint8_t reg) {
    uint8_t v;
    int p = (reg & 0x1F) >= VC_ADDR1_H;
    switch (reg & 0x1F) {
    case VC_ADDR0_H: case VC_ADDR1_H: return (uint8_t)(c->addr[p] >> 16);
    case VC_ADDR0_M: case VC_ADDR1_M: return (uint8_t)(c->addr[p] >> 8);
    case VC_ADDR0_L: case VC_ADDR1_L: return (uint8_t)c->addr[p];
    case VC_INC0_H: case VC_INC1_H: return (uint8_t)(c->inc[p] >> 8);
    case VC_INC0_L: case VC_INC1_L: return (uint8_t)c->inc[p];
    case VC_DATA0: case VC_DATA1:
        v = vc_peek(c, c->addr[p]);
        step_port(c, p);
        return v;
    case VC_STATUS:
        return (uint8_t)((c->line >= VC_HEIGHT ? VC_STATUS_VBLANK : 0) | (c->cmd_len ? VC_STATUS_BUSY : 0) |
                         (c->keyq_len ? VC_STATUS_KEY : 0));
    case VC_IEN: return c->ien;
    case VC_ISR: return c->isr;
    case VC_LINE_H: return (uint8_t)(c->line >> 8);
    case VC_LINE_L: return (uint8_t)c->line;
    case VC_FRAME: return c->frame;
    case VC_IN_CTRL: return c->in_ctrl;
    case VC_MOUSE_X_H:
        c->snap_x = c->mouse_x;
        c->snap_y = c->mouse_y;
        return (uint8_t)(c->snap_x >> 8);
    case VC_MOUSE_X_L: return (uint8_t)c->snap_x;
    case VC_MOUSE_Y_H: return (uint8_t)(c->snap_y >> 8);
    case VC_MOUSE_Y_L: return (uint8_t)c->snap_y;
    case VC_MOUSE_BTN: return c->buttons;
    case VC_MOUSE_WHEEL:
        v = (uint8_t)c->wheel;
        c->wheel = 0;
        return v;
    case VC_KEY:
        if (!c->keyq_len) {
            c->key_char = 0;
            return 0;
        }
        v = c->keyq[c->keyq_head][0];
        c->key_char = c->keyq[c->keyq_head][1];
        c->keyq_head = (uint8_t)((c->keyq_head + 1) % VC_KEY_QUEUE);
        --c->keyq_len;
        return v;
    case VC_KEY_CHAR: return c->key_char;
    case VC_KEY_MODS: return c->mods;
    case VC_ID: return 'V';
    case VC_VERSION: return 0x11;
    default: return 0;
    }
}

void vc_write(vc_card *c, uint8_t reg, uint8_t v) {
    int p = (reg & 0x1F) >= VC_ADDR1_H;
    switch (reg & 0x1F) {
    case VC_ADDR0_H: case VC_ADDR1_H: c->addr[p] = (c->addr[p] & 0x00FFFF) | (uint32_t)v << 16; break;
    case VC_ADDR0_M: case VC_ADDR1_M: c->addr[p] = (c->addr[p] & 0xFF00FF) | (uint32_t)v << 8; break;
    case VC_ADDR0_L: case VC_ADDR1_L: c->addr[p] = (c->addr[p] & 0xFFFF00) | v; break;
    case VC_INC0_H: case VC_INC1_H: c->inc[p] = (uint16_t)((c->inc[p] & 0x00FF) | v << 8); break;
    case VC_INC0_L: case VC_INC1_L: c->inc[p] = (uint16_t)((c->inc[p] & 0xFF00) | v); break;
    case VC_DATA0: case VC_DATA1:
        vc_poke(c, c->addr[p], v);
        step_port(c, p);
        break;
    case VC_CTRL:
        if (v & 0x80) vc_reset(c);
        break;
    case VC_IEN: c->ien = v & 0x0F; break;
    case VC_ISR: CLEAR_FLAGS(c, v); break;
    case VC_LINE_H: c->irq_line = (uint16_t)((c->irq_line & 0x00FF) | (v & 0x03) << 8); break;
    case VC_LINE_L: c->irq_line = (uint16_t)((c->irq_line & 0xFF00) | v); break;
    case VC_CMD: command_byte(c, v); break;
    case VC_IN_CTRL:
        c->in_ctrl = v & (VC_IN_POINTER | VC_IN_KEYS);
        if (v & VC_IN_FLUSH) c->keyq_head = c->keyq_len = 0;
        break;
    default: break;
    }
}

/* ---- input ---- */

void vc_mouse_to(vc_card *c, int x, int y, uint8_t buttons) {
    uint8_t b = (uint8_t)(0x80 | (buttons & 7));
    if (x < 0) x = 0;
    if (x > VC_WIDTH - 1) x = VC_WIDTH - 1;
    if (y < 0) y = 0;
    if (y > VC_HEIGHT - 1) y = VC_HEIGHT - 1;
    if (x != c->mouse_x || y != c->mouse_y || b != c->buttons) SET_FLAGS(c, VC_IRQ_INPUT);
    c->mouse_x = (uint16_t)x;
    c->mouse_y = (uint16_t)y;
    c->buttons = b;
}

void vc_mouse_by(vc_card *c, int dx, int dy, uint8_t buttons) {
    vc_mouse_to(c, c->mouse_x + dx, c->mouse_y + dy, buttons);
}

void vc_mouse_wheel(vc_card *c, int clicks) {
    int w = c->wheel + clicks;
    if (!clicks) return;
    c->wheel = (int8_t)(w > 127 ? 127 : w < -128 ? -128 : w);
    c->buttons |= 0x80;
    SET_FLAGS(c, VC_IRQ_INPUT);
}

/* The characters keys type on a US keyboard, by usage code from $04 (A) to $38 (/):
 * unshifted, then shifted. */
static const char k_keys[] = "abcdefghijklmnopqrstuvwxyz1234567890\r\x1b\b\t -=[]\\#;'`,./";
static const char k_shifted[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()\r\x1b\b\t _+{}|~:\"~<>?";
/* and the keypad's, $54 (/) to $63 (.) */
static const char k_keypad[] = "/*-+\r1234567890.";

static uint8_t key_char(const vc_card *c, uint8_t usage) {
    int shift = (c->mods & (VC_MOD_LSHIFT | VC_MOD_RSHIFT)) != 0;
    uint8_t ch = 0;
    if (usage >= 0x04 && usage <= 0x38) {
        if (usage <= 0x1D && c->caps_lock) shift = !shift; /* (letters only) */
        ch = (uint8_t)(shift ? k_shifted : k_keys)[usage - 0x04];
    } else if (usage >= 0x54 && usage <= 0x63) {
        ch = (uint8_t)k_keypad[usage - 0x54];
    } else if (usage == 0x4C) {
        ch = 0x7F; /* Delete */
    }
    if (ch >= 0x40 && ch < 0x7F && (c->mods & (VC_MOD_LCTRL | VC_MOD_RCTRL))) ch &= 0x1F; /* Ctrl+A is 1 ... */
    return ch;
}

void vc_key(vc_card *c, uint8_t usage, int down) {
    if (usage >= 0xE0 && usage <= 0xE7) {
        uint8_t bit = (uint8_t)(1u << (usage - 0xE0));
        c->mods = (uint8_t)(down ? c->mods | bit : c->mods & ~bit);
    } else if (usage == 0x39 && down) {
        c->caps_lock = !c->caps_lock;
    }
    if (!usage || c->keyq_len == VC_KEY_QUEUE) return; /* (full: the event is lost) */
    {
        uint8_t *e = c->keyq[(c->keyq_head + c->keyq_len) % VC_KEY_QUEUE];
        e[0] = usage;
        e[1] = (uint8_t)(key_char(c, usage) | (down ? 0 : 0x80));
        ++c->keyq_len;
    }
    SET_FLAGS(c, VC_IRQ_INPUT);
}

int vc_irq(const vc_card *c) { return (c->ien & c->isr) != 0; }

void vc_begin_line(vc_card *c, uint16_t line) {
    c->line = line;
    if (line == VC_HEIGHT) {
        SET_FLAGS(c, VC_IRQ_VSYNC);
        ++c->frame;
        if (c->in_ctrl & VC_IN_POINTER) { /* sprite 0 to the mouse, in the sprites' pixels */
            int hires = c->cfg[VC_SPR_CTRL] & 1;
            uint32_t a = be24(c->cfg + VC_SPR_BASE);
            uint16_t x = hires ? c->mouse_x : c->mouse_x / 2, y = hires ? c->mouse_y : c->mouse_y / 2;
            c->vram[(a + 2) & VRAM_MASK] = (uint8_t)(x >> 8);
            c->vram[(a + 3) & VRAM_MASK] = (uint8_t)x;
            c->vram[(a + 4) & VRAM_MASK] = (uint8_t)(y >> 8);
            c->vram[(a + 5) & VRAM_MASK] = (uint8_t)y;
        }
    }
    if (line == c->irq_line) SET_FLAGS(c, VC_IRQ_LINE);
}

/* ---- the picture ---- */

/* One layer's pixels on a line: palette indexes into idx[], 0 (transparent) left alone. */
static void render_layer(const vc_card *c, const uint8_t *l, int y, uint8_t *idx) {
    int mode = l[VC_L_MODE], type = mode & 3, hires = (mode >> 2) & 1, big = (mode >> 5) & 1;
    int bpp = 1 << ((mode >> 3) & 3), scale = hires ? 1 : 2, width = VC_WIDTH / scale;
    int ly = y / scale, lx;
    uint32_t mapbase = be24(l + VC_L_MAPBASE), tilebase = be24(l + VC_L_TILEBASE);
    int hs = s16(l + VC_L_HSCROLL), vs = s16(l + VC_L_VSCROLL);
    int mapw = 32 << (l[VC_L_MAP] & 3), maph = 32 << ((l[VC_L_MAP] >> 2) & 3);
    const uint8_t *vram = c->vram;
    for (lx = 0; lx < width; ++lx) {
        uint8_t v = 0;
        if (type == VC_TEXT) {
            int fh = big ? 16 : 8;
            int px = (lx + hs) & (mapw * 8 - 1), py = (ly + vs) & (maph * fh - 1);
            uint32_t cell = mapbase + 4u * (uint32_t)((py / fh) * mapw + px / 8);
            uint8_t ch = vram[cell & VRAM_MASK];
            uint8_t glyph = vram[(tilebase + (uint32_t)ch * fh + (uint32_t)(py % fh)) & VRAM_MASK];
            v = vram[(cell + ((glyph >> (7 - (px & 7))) & 1 ? 1 : 2)) & VRAM_MASK];
        } else if (type == VC_TILE) {
            int ts = big ? 16 : 8;
            int px = (lx + hs) & (mapw * ts - 1), py = (ly + vs) & (maph * ts - 1);
            uint32_t e = be16(vram + ((mapbase + 2u * (uint32_t)((py / ts) * mapw + px / ts)) & VRAM_MASK));
            int tx = px % ts, ty = py % ts, pal = (int)(e >> 12);
            uint32_t bit;
            uint8_t b;
            if (e & 0x400) tx = ts - 1 - tx;
            if (e & 0x800) ty = ts - 1 - ty;
            bit = (uint32_t)(ty * ts + tx) * bpp;
            b = vram[(tilebase + (e & 0x3FF) * (uint32_t)(ts * ts * bpp / 8) + bit / 8) & VRAM_MASK];
            if (bpp == 8) {
                v = b;
            } else {
                v = (uint8_t)(b >> (8 - bpp - (bit & 7)) & ((1u << bpp) - 1));
                if (v) v = (uint8_t)(pal * 16 + v);
            }
        } else if (type == VC_BITMAP) {
            int stride = (int)be16(l + VC_L_STRIDE), px = lx + hs, py = ly + vs;
            if (px >= 0 && py >= 0 && px < stride * 8 / bpp) {
                uint32_t bit = (uint32_t)px * bpp;
                uint8_t b = vram[(mapbase + (uint32_t)py * (uint32_t)stride + bit / 8) & VRAM_MASK];
                if (bpp == 8) {
                    v = b;
                } else {
                    v = (uint8_t)(b >> (8 - bpp - (bit & 7)) & ((1u << bpp) - 1));
                    if (v) v = (uint8_t)(l[VC_L_PALOFS] * 16 + v);
                }
            }
        }
        if (v) {
            if (scale == 1) {
                idx[lx] = v;
            } else {
                idx[2 * lx] = v;
                idx[2 * lx + 1] = v;
            }
        }
    }
}

typedef struct {
    const uint8_t *attr;
    int row; /* which of its rows this line shows */
} line_sprite;

static void render_sprites(const vc_card *c, const line_sprite *list, int n, int prio, uint8_t *idx) {
    int hires = c->cfg[VC_SPR_CTRL] & 1, scale = hires ? 1 : 2, width = VC_WIDTH / scale;
    int k;
    for (k = n - 1; k >= 0; --k) { /* backwards: the lowest-numbered sprite ends up in front */
        const uint8_t *a = list[k].attr;
        int w, x, bpp, i;
        uint32_t img;
        if ((a[6] >> 6) != prio) continue;
        w = 8 << (a[6] & 3);
        x = s16(a + 2);
        bpp = a[7] & 0x80 ? 8 : 4;
        img = be16(a) * 32u;
        for (i = 0; i < w; ++i) {
            int sx = x + i, col = a[6] & 0x10 ? w - 1 - i : i;
            uint32_t bit;
            uint8_t b, v;
            if (sx < 0 || sx >= width) continue;
            bit = (uint32_t)(list[k].row * w + col) * bpp;
            b = c->vram[(img + bit / 8) & VRAM_MASK];
            if (bpp == 8) {
                v = b;
            } else {
                v = (uint8_t)(b >> (4 - (bit & 7)) & 15);
                if (v) v = (uint8_t)((a[7] & 15) * 16 + v);
            }
            if (v) {
                if (scale == 1) {
                    idx[sx] = v;
                } else {
                    idx[2 * sx] = v;
                    idx[2 * sx + 1] = v;
                }
            }
        }
    }
}

void vc_render_line(const vc_card *c, int y, uint16_t *out) {
    uint8_t idx[VC_WIDTH];
    line_sprite list[VC_MAX_LINE_SPRITES];
    int n = 0, layer, x;
    uint8_t ctrl = c->cfg[VC_DC_CTRL];
    const uint8_t *pal = c->cfg + (VC_PAL_BASE - VC_CFG_BASE);
    memset(idx, 0, sizeof idx);
    if (ctrl & 0x08) {
        /* The sprites on this line: the first VC_MAX_LINE_SPRITES in the table. */
        int count = c->cfg[VC_SPR_COUNT] > 128 ? 128 : c->cfg[VC_SPR_COUNT];
        int sy = c->cfg[VC_SPR_CTRL] & 1 ? y : y / 2, i;
        uint32_t base = be24(c->cfg + VC_SPR_BASE);
        for (i = 0; i < count && n < VC_MAX_LINE_SPRITES; ++i) {
            const uint8_t *a = c->vram + ((base + 8u * (uint32_t)i) & VRAM_MASK);
            int top, h;
            if (((base + 8u * (uint32_t)i) & VRAM_MASK) > VC_VRAM_SIZE - 8) break;
            if ((a[6] >> 6) == 0) continue;
            top = s16(a + 4);
            h = 8 << ((a[6] >> 2) & 3);
            if (sy < top || sy >= top + h) continue;
            list[n].attr = a;
            list[n].row = a[6] & 0x20 ? h - 1 - (sy - top) : sy - top;
            ++n;
        }
    }
    for (layer = 0; layer < 3; ++layer) {
        if (ctrl & (1 << layer)) render_layer(c, c->cfg + VC_LAYER0 + VC_LAYER_SIZE * layer, y, idx);
        if (n) render_sprites(c, list, n, layer + 1, idx);
    }
    for (x = 0; x < VC_WIDTH; ++x) {
        uint8_t v = idx[x] ? idx[x] : c->cfg[VC_DC_BACK];
        out[x] = (uint16_t)(pal[2 * v] << 8 | pal[2 * v + 1]);
    }
}
