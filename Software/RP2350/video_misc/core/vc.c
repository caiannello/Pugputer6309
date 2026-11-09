/* The Pugputer 6309 video card: see vc.h and ../README.md. */
#include "vc.h"

#include <string.h>

#define VRAM_MASK (VC_VRAM_SIZE - 1)
#define PADMAP_END (VC_PADMAP_BASE + VC_PADMAPS * VC_PADMAP_SIZE - VC_CFG_BASE) /* (an offset in cfg) */

/* The interrupt flags are set by the beam (vc_begin_line), the commands and the input, and
 * cleared by the CPU. The card's firmware does those on two cores and in an interrupt
 * handler, so it builds this with VC_ATOMIC_FLAGS: each change is then one atomic step,
 * and none is lost to another made at the same moment. */
#ifdef VC_ATOMIC_FLAGS
/* A change counted (pal_gen, spr_gen: see vc_palette), after the change itself. */
#define BUMP(n) ((void)__atomic_fetch_add(&(n), 1u, __ATOMIC_SEQ_CST))
#define SET_FLAGS(c, f) ((void)__atomic_fetch_or(&(c)->isr, (uint8_t)(f), __ATOMIC_RELAXED))
#define CLEAR_FLAGS(c, f) ((void)__atomic_fetch_and(&(c)->isr, (uint8_t)~(f), __ATOMIC_RELAXED))
#else
#define BUMP(n) ((void)++*(volatile uint32_t *)&(n))
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
    if (a - VC_PAD_BASE < sizeof c->pads) return c->pads[a - VC_PAD_BASE];
    if (a - VC_CFG_BASE < VC_CFG_SIZE) return c->cfg[a - VC_CFG_BASE];
    if (a >= VC_PSRAM_BASE && c->psram) return c->psram[a - VC_PSRAM_BASE];
    return 0;
}

/* The sprite table's 128 entries are where the sprites' settings say (for vc_palette). */
static int in_sprite_table(const vc_card *c, uint32_t a) {
    uint32_t base = ((uint32_t)c->cfg[VC_SPR_BASE] << 16 | (uint32_t)c->cfg[VC_SPR_BASE + 1] << 8 |
                     c->cfg[VC_SPR_BASE + 2]) & (VC_VRAM_SIZE - 1);
    return ((a - base) & (VC_VRAM_SIZE - 1)) < 8u * 128u;
}

void vc_poke(vc_card *c, uint32_t a, uint8_t v) {
    a &= 0xFFFFFF;
    if (a < VC_VRAM_SIZE) {
        c->vram[a] = v;
        if (in_sprite_table(c, a)) BUMP(c->spr_gen); /* (after: see vc_palette) */
    } else if (a - VC_PAD_BASE < VC_PADMAP_BASE - VC_PAD_BASE) {
        /* (the pads and what each one is: read only) */
    } else if (a - VC_CFG_BASE < VC_CFG_SIZE) {
        uint32_t o = a - VC_CFG_BASE;
        c->cfg[o] = v;
        if (a >= VC_PAL_BASE) BUMP(c->pal_gen); /* (after: see vc_palette) */
        else if (o >= VC_SPR_CTRL && o < VC_SPR_BASE + 3) BUMP(c->spr_gen);
    }
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

/* Everything but the video memory: the settings, with xterm's palette, and the card's
 * state. Quick (the palette is worked out once), so a reset can be done at once. */
void vc_reset_state(vc_card *c) {
    static const uint8_t base16[16][3] = {
        {0, 0, 0},       {128, 0, 0},   {0, 128, 0},   {128, 128, 0},  {0, 0, 128},   {128, 0, 128},
        {0, 128, 128},   {192, 192, 192}, {128, 128, 128}, {255, 0, 0}, {0, 255, 0},   {255, 255, 0},
        {0, 0, 255},     {255, 0, 255}, {0, 255, 255}, {255, 255, 255}};
    static const uint8_t cube[6] = {0, 95, 135, 175, 215, 255};
    static uint8_t pal[2 * 256];
    static int pal_ready;
    uint8_t *cp = c->cfg + (VC_PAL_BASE - VC_CFG_BASE);
    int i;
    /* (What each pad is and the button maps stay: they are the hardware's, and PADMAP's.) */
    memset(c->cfg, 0, VC_PADID_BASE - VC_CFG_BASE);
    memset(c->cfg + PADMAP_END, 0, VC_CFG_SIZE - PADMAP_END);
    /* The palette: xterm's 256 colors, so text colors are the ones ANSI terminals use. */
    if (!pal_ready) {
        for (i = 0; i < 16; ++i) set_color(c, i, base16[i][0], base16[i][1], base16[i][2]);
        for (i = 0; i < 216; ++i) set_color(c, 16 + i, cube[i / 36], cube[i / 6 % 6], cube[i % 6]);
        for (i = 0; i < 24; ++i) set_color(c, 232 + i, 8 + 10 * i, 8 + 10 * i, 8 + 10 * i);
        memcpy(pal, cp, sizeof pal);
        pal_ready = 1;
    }
    memcpy(cp, pal, sizeof pal);
    /* An 80x30 text screen (a 128x32 map) on layer 0, in the font. */
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
    BUMP(c->pal_gen); /* (a new palette) */
    BUMP(c->spr_gen); /* (and sprites' settings) */
}

/* The video memory from a for n bytes as a reset leaves it: 0, but for the font and the
 * text screen's map, every cell a space in gray on black. */
void vc_reset_bytes(uint32_t a, uint8_t *dst, uint32_t n) {
    uint32_t end, s, e;
    if (a >= VC_VRAM_SIZE) return;
    if (n > VC_VRAM_SIZE - a) n = VC_VRAM_SIZE - a;
    end = a + n;
    memset(dst, 0, n);
    dst -= a; /* (indexed by address from here) */
    s = a > VC_RESET_FONT ? a : VC_RESET_FONT;
    e = end < VC_RESET_FONT + sizeof vc_font8x16 ? end : VC_RESET_FONT + (uint32_t)sizeof vc_font8x16;
    if (s < e) memcpy(dst + s, vc_font8x16 + (s - VC_RESET_FONT), e - s);
    s = a > VC_RESET_TEXT_MAP ? a : VC_RESET_TEXT_MAP;
    e = end < VC_RESET_TEXT_MAP + 128 * 32 * 4 ? end : VC_RESET_TEXT_MAP + 128 * 32 * 4;
    for (; s < e; ++s) { /* (the rest of each cell is 0) */
        uint32_t k = (s - VC_RESET_TEXT_MAP) & 3;
        if (k == 0 && s + 1 < e) {
            dst[s] = ' ';
            dst[s + 1] = 7;
            s += 3;
        } else if (k == 0) {
            dst[s] = ' ';
        } else if (k == 1) {
            dst[s] = 7;
        }
    }
}

void vc_reset_vram(vc_card *c, uint32_t a, uint32_t n) {
    if (a < VC_VRAM_SIZE) vc_reset_bytes(a, c->vram + a, n);
    BUMP(c->spr_gen); /* (the table may be in it) */
}

void vc_reset(vc_card *c) {
    vc_reset_state(c);
    vc_reset_vram(c, 0, VC_VRAM_SIZE);
}

/* ---- drawing ---- */

static void pset(vc_card *c, int x, int y, uint8_t col) {
    uint32_t bit, a;
    if (x < 0 || y < 0 || x >= c->t_w || y >= c->t_h) return;
    ++c->work;
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
        c->work += len;
        if (dst > src && dst < src + len) {
            for (k = len; k-- > 0;) vc_poke(c, dst + k, vc_peek(c, src + k));
        } else {
            for (k = 0; k < len; ++k) vc_poke(c, dst + k, vc_peek(c, src + k));
        }
        break;
    }
    case VC_C_FILL: {
        uint32_t dst = be24(p), len = be24(p + 3), k;
        c->work += len;
        for (k = 0; k < len; ++k) vc_poke(c, dst + k, p[6]);
        break;
    }
    case VC_C_BLIT: {
        uint32_t src = be24(p), stride = be16(p + 3);
        int w = s16(p + 5), h = s16(p + 7), transparent = p[13] & 1;
        uint32_t w0 = c->work;
        x = s16(p + 9); y = s16(p + 11);
        for (j = 0; j < h; ++j)
            for (i = 0; i < w; ++i) {
                uint8_t v = pget(c, src, stride, i, j, c->t_bpp);
                if (!(transparent && v == 0)) pset(c, x + i, y + j, v);
            }
        if (w > 0 && h > 0) c->work = w0 + (uint32_t)w * (uint32_t)h; /* (every pixel looked at) */
        break;
    }
    case VC_C_TRIANGLE: triangle(c, s16(p), s16(p + 2), s16(p + 4), s16(p + 6), s16(p + 8), s16(p + 10)); break;
    case VC_C_FONT:
        c->font = be24(p);
        c->font_h = p[3] ? p[3] : 16;
        break;
    case VC_C_CHAR: {
        uint32_t w0 = c->work;
        x = s16(p); y = s16(p + 2);
        for (j = 0; j < c->font_h; ++j) {
            uint8_t bits = vc_peek(c, c->font + (uint32_t)p[4] * c->font_h + (uint32_t)j);
            for (i = 0; i < 8; ++i)
                if (bits & (0x80 >> i)) pset(c, x + i, y + j, c->color);
        }
        c->work = w0 + 8u * c->font_h; /* (every pixel of the cell) */
        break;
    }
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

/* Pads known without being set up, as VC_PADMAP_SIZE-byte entries. */
#define NO VC_BTN_NONE
static const uint8_t k_pad_maps[][VC_PADMAP_SIZE] = {
    /* 8BitDo SN30 Pro, D-input (its buttons 3, 6 and 16 don't exist) */
    {0x2D, 0xC8, 0x60, 0x01, VC_BTN_EAST, VC_BTN_SOUTH, NO, VC_BTN_NORTH, VC_BTN_WEST, NO, VC_BTN_L, VC_BTN_R, VC_BTN_L2,
     VC_BTN_R2, VC_BTN_SELECT, VC_BTN_START, VC_BTN_HOME, VC_BTN_L3, VC_BTN_R3, NO},
};
#undef NO

/* The map for a pad with these IDs: the user's first, then the card's own. NULL: none. */
static const uint8_t *pad_map(const vc_card *c, const uint8_t *id) {
    const uint8_t *t = c->cfg + (VC_PADMAP_BASE - VC_CFG_BASE);
    size_t i;
    if (!(id[0] | id[1] | id[2] | id[3])) return NULL;
    for (i = 0; i < VC_PADMAPS; ++i, t += VC_PADMAP_SIZE)
        if (!memcmp(t, id, 4)) return t;
    for (i = 0; i < sizeof k_pad_maps / sizeof k_pad_maps[0]; ++i)
        if (!memcmp(k_pad_maps[i], id, 4)) return k_pad_maps[i];
    return NULL;
}

void vc_pad_id(vc_card *c, int n, uint16_t vid, uint16_t pid) {
    uint8_t *id;
    if (n < 0 || n >= VC_PADS) return;
    id = c->cfg + (VC_PADID_BASE - VC_CFG_BASE) + n * VC_PAD_SIZE;
    id[VC_PADID_VID_H] = (uint8_t)(vid >> 8);
    id[VC_PADID_VID_L] = (uint8_t)vid;
    id[VC_PADID_PID_H] = (uint8_t)(pid >> 8);
    id[VC_PADID_PID_L] = (uint8_t)pid;
}

void vc_pad(vc_card *c, int n, const uint8_t *state) {
    uint8_t next[VC_PAD_SIZE] = {0};
    uint8_t *p, *id;
    if (n < 0 || n >= VC_PADS) return;
    p = c->pads + n * VC_PAD_SIZE;
    id = c->cfg + (VC_PADID_BASE - VC_CFG_BASE) + n * VC_PAD_SIZE;
    if (state) {
        const uint8_t *map = pad_map(c, id);
        memcpy(next, state, VC_PAD_SIZE);
        next[VC_PAD_FLAGS] |= VC_PAD_CONNECTED;
        id[VC_PADID_RAW1] = state[VC_PAD_BTN1];
        id[VC_PADID_RAW2] = state[VC_PAD_BTN2];
        if (map) {
            unsigned raw = (unsigned)state[VC_PAD_BTN1] | (unsigned)state[VC_PAD_BTN2] << 8, out = 0;
            int i;
            for (i = 0; i < 16; ++i)
                if ((raw >> i & 1) && map[4 + i] < 16) out |= 1u << map[4 + i];
            next[VC_PAD_BTN1] = (uint8_t)out;
            next[VC_PAD_BTN2] = (uint8_t)(out >> 8);
            next[VC_PAD_FLAGS] |= VC_PAD_MAPPED;
        }
    } else {
        memset(id, 0, VC_PAD_SIZE);
    }
    if (memcmp(p, next, VC_PAD_SIZE)) {
        memcpy(p, next, VC_PAD_SIZE);
        SET_FLAGS(c, VC_IRQ_INPUT);
    }
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
            BUMP(c->spr_gen);
        }
    }
    if (line == c->irq_line) SET_FLAGS(c, VC_IRQ_LINE);
}

/* ---- the picture ----
 *
 * On the card a line has to be drawn in 31.7 us: 8000 clocks, and about as many
 * instructions. So it is drawn a character cell, a tile or a run of pixels at a time
 * rather than working out each pixel from scratch, and straight in colors: the first
 * layer that is on puts every pixel (the backdrop where it is transparent), and each
 * layer and sprite after it only the pixels that aren't transparent (index 0). */

#if defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define VC_BIG_ENDIAN 1
#else
#define VC_BIG_ENDIAN 0
#endif

#if defined(__GNUC__)
#define VC_INLINE static inline __attribute__((always_inline))
#define VC_NOINLINE static __attribute__((noinline))
#elif defined(_MSC_VER)
#define VC_INLINE static __forceinline
#define VC_NOINLINE static __declspec(noinline)
#else
#define VC_INLINE static inline
#define VC_NOINLINE static
#endif

/* Two pixels as one 32-bit word, the first at the lower address. */
#if VC_BIG_ENDIAN
#define PAIR(a, b) ((uint32_t)(a) << 16 | (uint32_t)(b))
#else
#define PAIR(a, b) ((uint32_t)(b) << 16 | (uint32_t)(a))
#endif

static const uint32_t k_px2[4] = {0, PAIR(0, 0xFFFF), PAIR(0xFFFF, 0), 0xFFFFFFFFu}; /* 2 bits, 2 pixels */

VC_INLINE uint32_t get32(const void *p) {
    uint32_t v;
    memcpy(&v, p, 4);
    return v;
}
VC_INLINE void put32(void *p, uint32_t v) { memcpy(p, &v, 4); }

/* One pixel of a layer (at its own resolution), as a color: unless it's transparent and
 * this isn't the base layer, which puts the backdrop there (pal[0]). */
VC_INLINE void put(uint16_t *out, const uint16_t *pal, int base, int scale, int lx, unsigned v) {
    if (base || v) {
        uint16_t col = pal[v];
        if (scale == 1) out[lx] = col;
        else put32(out + 2 * lx, PAIR(col, col));
    }
}

/* n pixels of one color (at a layer's resolution). */
VC_INLINE void fill(uint16_t *out, uint16_t col, int scale, int lx, int n) {
    int i;
    if (scale == 1) {
        for (i = 0; i < n; ++i) out[lx + i] = col;
    } else {
        uint32_t w = PAIR(col, col);
        for (i = 0; i < n; ++i) put32(out + 2 * (lx + i), w);
    }
}

/* A whole character cell: its 8 pixels, from the glyph's row. */
VC_INLINE void text_cell(uint16_t *out, const uint16_t *pal, int base, int scale, int lx, unsigned glyph,
                         unsigned fg, unsigned bg) {
    int fg_on = base || fg, bg_on = base || bg, i;
    uint16_t *d = out + scale * lx;
    if (fg_on && bg_on) {
        uint16_t cf = pal[fg], cb = pal[bg];
        if (scale == 1) {
            uint32_t b2 = PAIR(cb, cb), diff = PAIR(cf ^ cb, cf ^ cb);
            put32(d, b2 ^ (diff & k_px2[glyph >> 6]));
            put32(d + 2, b2 ^ (diff & k_px2[(glyph >> 4) & 3]));
            put32(d + 4, b2 ^ (diff & k_px2[(glyph >> 2) & 3]));
            put32(d + 6, b2 ^ (diff & k_px2[glyph & 3]));
        } else {
            uint32_t f2 = PAIR(cf, cf), b2 = PAIR(cb, cb);
            for (i = 0; i < 8; ++i) put32(d + 2 * i, (glyph >> (7 - i)) & 1 ? f2 : b2);
        }
    } else if (fg_on || bg_on) {
        /* Over what's below: only the pixels that show. */
        unsigned set = fg_on ? glyph : ~glyph & 0xFFu;
        uint16_t col = pal[fg_on ? fg : bg];
        uint32_t c2 = PAIR(col, col);
        if (!set) return;
        if (scale == 1) {
            for (i = 0; i < 4; ++i) {
                uint32_t m = k_px2[(set >> (6 - 2 * i)) & 3];
                if (m) put32(d + 2 * i, (get32(d + 2 * i) & ~m) | (c2 & m));
            }
        } else {
            for (i = 0; i < 8; ++i)
                if ((set >> (7 - i)) & 1) put32(d + 2 * i, c2);
        }
    }
}

/* Packed pixels (1, 2 or 4 bits) a byte at a time, by a table of their colors: ct[v] for
 * v = 1..15 (the palette entry v plus the layer's or tile's 16-color offset), ct[0] the
 * backdrop (shown only by the base layer: elsewhere 0 is see-through). */
VC_INLINE void make_ct(uint16_t *ct, const uint16_t *pal, int bpp, uint32_t pal16) {
    int v;
    ct[0] = pal[0];
    for (v = 1; v < 1 << bpp; ++v) ct[v] = pal[(pal16 + (uint32_t)v) & 0xFF];
}

VC_INLINE unsigned rev8(unsigned b) {
    b = (b & 0xF0) >> 4 | (b & 0x0F) << 4;
    b = (b & 0xCC) >> 2 | (b & 0x33) << 2;
    return (b & 0xAA) >> 1 | (b & 0x55) << 1;
}

/* 8 pixels from the bits of g (the first the top bit): cf where set, else cb (base) or
 * what's below. As a character cell is drawn. */
VC_INLINE void bits8(uint16_t *out, int base, int scale, int lx, unsigned g, uint16_t cf, uint16_t cb) {
    uint16_t *d = out + scale * lx;
    int i;
    if (base) {
        if (scale == 1) {
            uint32_t b2 = PAIR(cb, cb), diff = PAIR(cf ^ cb, cf ^ cb);
            put32(d, b2 ^ (diff & k_px2[g >> 6]));
            put32(d + 2, b2 ^ (diff & k_px2[(g >> 4) & 3]));
            put32(d + 4, b2 ^ (diff & k_px2[(g >> 2) & 3]));
            put32(d + 6, b2 ^ (diff & k_px2[g & 3]));
        } else {
            uint32_t f2 = PAIR(cf, cf), b2 = PAIR(cb, cb);
            for (i = 0; i < 8; ++i) put32(d + 2 * i, (g >> (7 - i)) & 1 ? f2 : b2);
        }
    } else if (g) {
        uint32_t c2 = PAIR(cf, cf);
        if (scale == 1) {
            for (i = 0; i < 4; ++i) {
                uint32_t m = k_px2[(g >> (6 - 2 * i)) & 3];
                if (m) put32(d + 2 * i, (get32(d + 2 * i) & ~m) | (c2 & m));
            }
        } else {
            for (i = 0; i < 8; ++i)
                if ((g >> (7 - i)) & 1) put32(d + 2 * i, c2);
        }
    }
}

/* The pixels of a bitmap's byte b (8 / bpp of them) from lx on. */
VC_INLINE void byte_px(uint16_t *out, const uint16_t *ct, int base, int scale, int lx, unsigned b, int bpp) {
    int per = 8 / bpp, j;
    unsigned mask = (1u << bpp) - 1;
    if (bpp == 1) {
        bits8(out, base, scale, lx, b, ct[1], ct[0]);
        return;
    }
    for (j = 0; j < per; ++j) {
        unsigned v = (b >> (8 - bpp - bpp * j)) & mask;
        if (base || v) {
            uint16_t col = ct[v];
            if (scale == 1) out[lx + j] = col;
            else put32(out + 2 * (lx + j), PAIR(col, col));
        }
    }
}

/* nb bytes of a bitmap's packed pixels from s, from lx on: four at a time where those
 * are all 0, and nothing (or the backdrop) for a 0 byte. */
VC_INLINE void packed_bytes(uint16_t *out, const uint16_t *ct, int base, int scale, int lx, const uint8_t *s,
                            int nb, int bpp) {
    int per = 8 / bpp, k = 0;
    while (k < nb) {
        if (k + 4 <= nb && !get32(s + k)) {
            if (base) fill(out, ct[0], scale, lx + per * k, 4 * per);
            k += 4;
            continue;
        }
        {
            unsigned b = s[k];
            if (b) byte_px(out, ct, base, scale, lx + per * k, b, bpp);
            else if (base) fill(out, ct[0], scale, lx + per * k, per);
        }
        ++k;
    }
}

/* A whole row of a tile of 1, 2 or 4 bits a pixel (nb bytes from s, flipped across or
 * not), from lx on: its colors straight from the palette (a tile's 16 can differ from the
 * last's, so a table of them would cost more than it saves), four bytes at a time where
 * those are all 0. */
VC_INLINE void tile_row(uint16_t *out, const uint16_t *pal, int base, int scale, int lx, const uint8_t *s,
                        int nb, int bpp, int flip, uint32_t pal16) {
    int per = 8 / bpp, k = 0, j;
    unsigned mask = (1u << bpp) - 1;
    uint16_t cf = pal[(pal16 + 1) & 0xFF]; /* (1 bit: its one color) */
    while (k < nb) {
        unsigned b;
        int at = lx + per * k;
        if (k + 4 <= nb && !get32(flip ? s + nb - 4 - k : s + k)) {
            if (base) fill(out, pal[0], scale, at, 4 * per);
            k += 4;
            continue;
        }
        b = s[flip ? nb - 1 - k : k];
        ++k;
        if (!b) {
            if (base) fill(out, pal[0], scale, at, per);
        } else if (bpp == 1) {
            bits8(out, base, scale, at, flip ? rev8(b) : b, cf, pal[0]);
        } else {
            for (j = 0; j < per; ++j) {
                unsigned v = (b >> (flip ? bpp * j : 8 - bpp - bpp * j)) & mask;
                put(out, pal, base, scale, at + j, v ? (pal16 + v) & 0xFF : 0);
            }
        }
    }
}

/* Which halves of a pair of pixels a byte of 4-bit pixels shows (made once). */
static uint32_t pair_mask[256];
static int pair_mask_made;

/* The pair table for 16-color set p (see vc_palette), made. */
VC_NOINLINE void make_pairs(vc_palette *cache, int p) { /* (out of the way: rare) */
    uint32_t *t = cache->pair[p];
    {
        const uint16_t *pal = cache->col + 16 * p;
        int hi, lo;
        for (hi = 0; hi < 16; ++hi)
            for (lo = 0; lo < 16; ++lo) t[hi * 16 + lo] = PAIR(hi ? pal[hi] : 0, lo ? pal[lo] : 0);
        cache->pair_epoch[p] = cache->epoch;
    }
    if (!pair_mask_made) { /* (both cores may: they make the same) */
        int b;
        for (b = 0; b < 256; ++b) pair_mask[b] = PAIR(b >> 4 ? 0xFFFF : 0, b & 15 ? 0xFFFF : 0);
        pair_mask_made = 1;
    }
}

/* The pair table for 16-color set p, made first if out of date. */
VC_INLINE const uint32_t *pair_table(vc_palette *cache, int p) {
    if (cache->pair_epoch[p] != cache->epoch || !pair_mask_made) make_pairs(cache, p);
    return cache->pair[p];
}

/* A whole row of a tile of 4 bits a pixel at 320x240 (nb bytes from s, flipped across or
 * not), from lx on: a byte, two pixels, four on the screen, at a time. Inlined for each
 * constant base and flip, so the loop itself tests only what the pixels make it. */
VC_INLINE void tile4_row(uint16_t *out, const uint16_t *pal, int base, int lx, const uint8_t *s, int nb, int flip,
                         uint32_t pal16) {
    const uint16_t *set = pal + pal16;
    uint16_t back = pal[0];
    int k;
    out += 2 * lx;
    for (k = 0; k < nb; ++k) {
        unsigned b = s[flip ? nb - 1 - k : k];
        unsigned p0 = flip ? b & 15 : b >> 4, p1 = flip ? b >> 4 : b & 15;
        if (base) {
            uint16_t c0 = p0 ? set[p0] : back, c1 = p1 ? set[p1] : back;
            put32(out + 4 * k, PAIR(c0, c0));
            put32(out + 4 * k + 2, PAIR(c1, c1));
        } else if (b) {
            if (p0) put32(out + 4 * k, PAIR(set[p0], set[p0]));
            if (p1) put32(out + 4 * k + 2, PAIR(set[p1], set[p1]));
        }
    }
}

/* The same at 640x480, from the pair table t: a byte's two pixels in one load and one
 * store, with no test for each pixel. (Base 1: the backdrop where see-through. Else what's
 * there stays there: read only for a byte with one pixel showing.) */
VC_INLINE void tile4_pairs(uint16_t *d, const uint32_t *t, uint16_t back, int base, const uint8_t *s, int nb, int flip) {
    uint32_t bk = PAIR(back, back);
    int k;
    for (k = 0; k < nb; ++k, d += 2) {
        unsigned b = s[flip ? nb - 1 - k : k];
        uint32_t m;
        if (!base && !b) continue;
        if (flip) b = (b >> 4 | b << 4) & 0xFF; /* (its pixels the other way round) */
        m = pair_mask[b];
        if (base) put32(d, (bk & ~m) | t[b]);
        else if (m == 0xFFFFFFFFu) put32(d, t[b]);
        else put32(d, (get32(d) & ~m) | t[b]);
    }
}

/* The whole tiles of a stretch of map of 4 or 8 bits a pixel: count cells from m (which
 * doesn't wrap), the first at lx. A map is mostly the same tile again, and mostly tiles with
 * nothing on this row, and the screen can have 120 of them a line (3 layers of 8x8), so what
 * a cell needs is worked out only when it differs from the last, and an empty row is
 * skipped whole. Returns how many it drew: fewer than count at a tile whose row would run
 * off the end of the memory (the caller's slower way takes that one). */
VC_INLINE int tile_run(const uint8_t *vram, vc_palette *cache, uint16_t *out, const uint16_t *pal, int base, int scale,
                       int bpp, int ts, int lx, const uint8_t *m, int count, uint32_t tilebase, int row_in_tile) {
    uint32_t row_bytes = (uint32_t)(ts * bpp / 8), tile_bytes = (uint32_t)ts * row_bytes, pal16 = 0, k;
    const uint8_t *s = vram;
    const uint32_t *pairs = 0;
    unsigned last = 0x10000u; /* (no entry is this) */
    int flip = 0, blank = 0, i;
    for (i = 0; i < count; ++i, m += 2, lx += ts) {
        unsigned e = (unsigned)be16(m);
        if (e != last) {
            int ty = e & 0x800 ? ts - 1 - row_in_tile : row_in_tile;
            uint32_t trow = (tilebase + (e & 0x3FF) * tile_bytes + (uint32_t)ty * row_bytes) & VRAM_MASK;
            if (trow > VC_VRAM_SIZE - row_bytes) return i;
            s = vram + trow;
            flip = (e & 0x400) != 0;
            pal16 = (e >> 12) * 16;
            if (bpp == 4 && scale == 1) pairs = pair_table(cache, (int)(e >> 12));
            last = e;
            blank = 1;
            for (k = 0; k < row_bytes; k += 4) {
                if (get32(s + k)) {
                    blank = 0;
                    break;
                }
            }
        }
        if (blank) {
            if (base) fill(out, pal[0], scale, lx, ts);
        } else if (bpp == 8) {
            const uint8_t *p = flip ? s + ts - 1 : s;
            int step = flip ? -1 : 1, j;
            for (j = 0; j < ts; ++j, p += step) put(out, pal, base, scale, lx + j, *p);
        } else if (scale == 1) {
            if (!flip) tile4_pairs(out + lx, pairs, pal[0], base, s, (int)row_bytes, 0);
            else tile4_pairs(out + lx, pairs, pal[0], base, s, (int)row_bytes, 1);
        } else if (!flip) {
            tile4_row(out, pal, base, lx, s, (int)row_bytes, 0, pal16);
        } else {
            tile4_row(out, pal, base, lx, s, (int)row_bytes, 1, pal16);
        }
    }
    return i;
}

/* One layer's line, in colors: every pixel (base 1), or only those that show (base 0). */
VC_INLINE void render_layer(const vc_card *c, vc_palette *cache, const uint8_t *l, int y, uint16_t *out,
                            const uint16_t *pal, int base) {
    int mode = l[VC_L_MODE], type = mode & 3, hires = (mode >> 2) & 1, big = (mode >> 5) & 1;
    int bpp = 1 << ((mode >> 3) & 3), scale = hires ? 1 : 2, width = VC_WIDTH / scale;
    int ly = y / scale, lx, i;
    uint32_t mapbase = be24(l + VC_L_MAPBASE), tilebase = be24(l + VC_L_TILEBASE);
    uint32_t vmask = (1u << bpp) - 1;
    int hs = s16(l + VC_L_HSCROLL), vs = s16(l + VC_L_VSCROLL);
    int mapw = 32 << (l[VC_L_MAP] & 3), maph = 32 << ((l[VC_L_MAP] >> 2) & 3);
    const uint8_t *vram = c->vram;
    if (type == VC_TEXT) {
        /* A cell is 4 bytes: the character, its color, its background (and one unused). */
        int fh = big ? 16 : 8, wmask = mapw * 8 - 1;
        int py = (ly + vs) & (maph * fh - 1), px = hs & wmask;
        uint32_t row = mapbase + 4u * (uint32_t)((py / fh) * mapw), gbase = tilebase + (uint32_t)(py % fh);
        lx = 0;
        if (!(px & 7) && (gbase & VRAM_MASK) <= VC_VRAM_SIZE - 1 - 255u * (uint32_t)fh) {
            /* Not scrolled within a cell, and the font doesn't wrap round the memory: the
             * cells by pointer, a run at a time up to the map's right edge (the screen is
             * whole cells across), where the run doesn't wrap either. */
            const uint8_t *gp = vram + (gbase & VRAM_MASK);
            while (lx < width) {
                int c0 = px >> 3, len = (width - lx) / 8, k;
                uint32_t a;
                const uint8_t *cp;
                if (len > mapw - c0) len = mapw - c0;
                a = (row + 4u * (uint32_t)c0) & VRAM_MASK;
                if (a > VC_VRAM_SIZE - 4u * (uint32_t)len) break; /* (the rest the general way) */
                cp = vram + a;
                for (k = 0; k < len; ++k, cp += 4, lx += 8) text_cell(out, pal, base, scale, lx, gp[cp[0] * fh], cp[1], cp[2]);
                px = (px + 8 * len) & wmask;
            }
        }
        while (lx < width) {
            uint32_t cell = row + 4u * (uint32_t)(px >> 3);
            unsigned ch = vram[cell & VRAM_MASK], fg = vram[(cell + 1) & VRAM_MASK], bg = vram[(cell + 2) & VRAM_MASK];
            unsigned glyph = vram[(gbase + ch * (uint32_t)fh) & VRAM_MASK];
            int b = px & 7, n = 8 - b;
            if (n > width - lx) n = width - lx;
            if (n == 8) {
                text_cell(out, pal, base, scale, lx, glyph, fg, bg);
            } else { /* a cell cut by the scroll or the screen's edge */
                for (i = 0; i < n; ++i) put(out, pal, base, scale, lx + i, (glyph >> (7 - b - i)) & 1 ? fg : bg);
            }
            lx += n;
            px = (px + n) & wmask;
        }
    } else if (type == VC_TILE) {
        /* A map entry is 16 bits: bits 0-9 the tile, 10 flip across, 11 flip down, 12-15
         * its 16 colors (below 8 bits per pixel). */
        int ts = big ? 16 : 8, shift = big ? 4 : 3, wmask = mapw * ts - 1;
        int py = (ly + vs) & (maph * ts - 1), px = hs & wmask, row_in_tile = py & (ts - 1);
        uint32_t row = mapbase + 2u * (uint32_t)((py / ts) * mapw), tile_bytes = (uint32_t)(ts * ts * bpp / 8);
        uint32_t row_bytes = (uint32_t)(ts * bpp / 8);
        lx = 0;
        while (lx < width) {
            if (bpp >= 4 && !(px & (ts - 1))) { /* whole tiles, as far as the map goes on */
                int cell = px >> shift, count = (width - lx) >> shift;
                uint32_t a = (row + 2u * (uint32_t)cell) & VRAM_MASK;
                if (count > mapw - cell) count = mapw - cell;
                if (count > 0 && a <= VC_VRAM_SIZE - 2u * (uint32_t)count) {
                    const uint8_t *m = vram + a;
                    int done;
                    if (bpp == 4) {
                        if (scale == 1) done = tile_run(vram, cache, out, pal, base, 1, 4, ts, lx, m, count, tilebase, row_in_tile);
                        else done = tile_run(vram, cache, out, pal, base, 2, 4, ts, lx, m, count, tilebase, row_in_tile);
                    } else {
                        if (scale == 1) done = tile_run(vram, cache, out, pal, base, 1, 8, ts, lx, m, count, tilebase, row_in_tile);
                        else done = tile_run(vram, cache, out, pal, base, 2, 8, ts, lx, m, count, tilebase, row_in_tile);
                    }
                    lx += done * ts;
                    px = (px + done * ts) & wmask;
                    if (done == count) continue;
                }
            }
            uint32_t e = be16(vram + ((row + 2u * (uint32_t)(px >> shift)) & VRAM_MASK));
            int flip = (e & 0x400) != 0, tx = px & (ts - 1), n = ts - tx;
            int ty = e & 0x800 ? ts - 1 - row_in_tile : row_in_tile;
            uint32_t pal16 = (e >> 12) * 16, trow = tilebase + (e & 0x3FF) * tile_bytes + (uint32_t)ty * row_bytes;
            const uint8_t *s = vram + (trow & VRAM_MASK);
            int whole = (trow & VRAM_MASK) <= VC_VRAM_SIZE - row_bytes; /* (none of it wraps) */
            if (n > width - lx) n = width - lx;
            if (n == ts && whole && bpp < 4) {
                if (bpp == 1) tile_row(out, pal, base, scale, lx, s, (int)row_bytes, 1, flip, pal16);
                else tile_row(out, pal, base, scale, lx, s, (int)row_bytes, 2, flip, pal16);
            } else {
                for (i = 0; i < n; ++i, ++tx) {
                    uint32_t bit = (uint32_t)(flip ? ts - 1 - tx : tx) * (uint32_t)bpp;
                    unsigned v = vram[(trow + bit / 8) & VRAM_MASK];
                    if (bpp != 8) {
                        v = v >> (8 - bpp - (bit & 7)) & vmask;
                        if (v) v = (pal16 + v) & 0xFF;
                    }
                    put(out, pal, base, scale, lx + i, v);
                }
            }
            lx += n;
            px = (px + n) & wmask;
        }
    } else {
        /* A bitmap (type 3 shows nothing): the pixels from x0 to x1 are on it. */
        int x0 = 0, x1 = 0;
        if (type == VC_BITMAP) {
            int stride = (int)be16(l + VC_L_STRIDE), py = ly + vs;
            if (py >= 0) {
                x0 = hs < 0 ? -hs : 0;
                x1 = stride * 8 / bpp - hs;
                if (x0 > width) x0 = width;
                if (x1 > width) x1 = width;
                if (x1 < x0) x1 = x0;
            }
            if (x0 < x1) {
                uint32_t row = mapbase + (uint32_t)py * (uint32_t)stride;
                if (bpp == 8) {
                    uint32_t a = row + (uint32_t)(x0 + hs);
                    if ((a & VRAM_MASK) <= VC_VRAM_SIZE - (uint32_t)(x1 - x0)) {
                        const uint8_t *s = vram + (a & VRAM_MASK);
                        int n = x1 - x0;
                        uint16_t *d = out + scale * x0;
                        if (base && scale == 1) {
                            for (i = 0; i < n; ++i) d[i] = pal[s[i]];
                        } else if (base) {
                            for (i = 0; i < n; ++i) {
                                uint16_t col = pal[s[i]];
                                put32(d + 2 * i, PAIR(col, col));
                            }
                        } else {
                            for (i = 0; i < n; ++i) put(d, pal, 0, scale, i, s[i]);
                        }
                    } else {
                        for (lx = x0; lx < x1; ++lx, ++a) put(out, pal, base, scale, lx, vram[a & VRAM_MASK]);
                    }
                } else {
                    uint32_t bit = (uint32_t)(x0 + hs) * (uint32_t)bpp, pal16 = (uint32_t)l[VC_L_PALOFS] * 16;
                    lx = x0;
                    if (!(bit & 7) && ((row + bit / 8) & VRAM_MASK) <= VC_VRAM_SIZE - (uint32_t)(x1 - x0)) {
                        /* (none of it wraps, and it starts on a byte) */
                        const uint8_t *s = vram + ((row + bit / 8) & VRAM_MASK);
                        uint16_t ct[16];
                        int nb = (x1 - x0) * bpp / 8; /* (whole bytes: the rest below) */
                        make_ct(ct, pal, bpp, pal16);
                        if (bpp == 1) packed_bytes(out, ct, base, scale, x0, s, nb, 1);
                        else if (bpp == 2) packed_bytes(out, ct, base, scale, x0, s, nb, 2);
                        else packed_bytes(out, ct, base, scale, x0, s, nb, 4);
                        lx = x0 + nb * 8 / bpp;
                        bit += (uint32_t)nb * 8;
                    }
                    for (; lx < x1; ++lx, bit += (uint32_t)bpp) {
                        unsigned v = vram[(row + bit / 8) & VRAM_MASK] >> (8 - bpp - (bit & 7)) & vmask;
                        if (v) v = (pal16 + v) & 0xFF;
                        put(out, pal, base, scale, lx, v);
                    }
                }
            }
        }
        if (base) { /* the backdrop around it */
            fill(out, pal[0], scale, 0, x0);
            fill(out, pal[0], scale, x1, width - x1);
        }
    }
}

/* A whole row of a sprite of 4 bits a pixel (nb bytes from s, flipped across or not) at
 * x: a byte, two pixels, at a time, none of a byte that is 0, and both in one store when
 * both show (hires). */
VC_INLINE void sprite4_row(uint16_t *out, const uint16_t *pal, int scale, int x, const uint8_t *s, int nb,
                           int flip, uint32_t pal16) {
    int k;
    for (k = 0; k < nb; ++k) {
        unsigned b = s[flip ? nb - 1 - k : k], p0, p1;
        int at = x + 2 * k;
        uint16_t c0, c1;
        if (!b) continue;
        p0 = flip ? b & 15 : b >> 4;
        p1 = flip ? b >> 4 : b & 15;
        c0 = pal[(pal16 + p0) & 0xFF];
        c1 = pal[(pal16 + p1) & 0xFF];
        if (scale == 1) {
            if (p0 && p1) put32(out + at, PAIR(c0, c1));
            else if (p0) out[at] = c0;
            else out[at + 1] = c1;
        } else {
            if (p0) put32(out + 2 * at, PAIR(c0, c0));
            if (p1) put32(out + 2 * at + 2, PAIR(c1, c1));
        }
    }
}

/* Pixels i0 to i1 of a row of a sprite of 8 bits a pixel (w wide, from s, flipped across or
 * not) at x. Inlined for each constant scale and flip. */
VC_INLINE void sprite8_row(uint16_t *out, const uint16_t *pal, int scale, int x, const uint8_t *s, int i0, int i1,
                           int w, int flip) {
    int i;
    for (i = i0; i < i1; ++i) {
        unsigned v = s[flip ? w - 1 - i : i];
        if (v) {
            uint16_t col = pal[v];
            if (scale == 1) out[x + i] = col;
            else put32(out + 2 * (x + i), PAIR(col, col));
        }
    }
}

/* A whole row of a hires 4-bit sprite (nb bytes from s, flipped across or not) at d: a
 * byte at a time, its two pixels from the pair table, over what's there where see-through
 * (no test for each pixel). */
VC_INLINE void sprite4_pairs(uint16_t *d, const uint32_t *t, const uint8_t *s, int nb, int flip) {
    int k;
    for (k = 0; k < nb; ++k, d += 2) {
        unsigned b = s[flip ? nb - 1 - k : k];
        if (!b) continue;
        if (flip) b = (b >> 4 | b << 4) & 0xFF; /* (its pixels the other way round) */
        put32(d, (get32(d) & ~pair_mask[b]) | t[b]);
    }
}

typedef struct {
    const struct vc_sprite *s;
    int row; /* which of its rows this line shows */
} line_sprite;

/* The sprite table, decoded, and its bands (see vc_palette). As the line's own scan did:
 * the first count entries, up to one that would run past the end of the memory; those of
 * priority 0 are off. */
static void decode_sprites(const vc_card *c, vc_palette *cache) {
    int count = c->cfg[VC_SPR_COUNT] > 128 ? 128 : c->cfg[VC_SPR_COUNT], i;
    uint32_t base = be24(c->cfg + VC_SPR_BASE);
    memset(cache->band_n, 0, sizeof cache->band_n);
    ++cache->decodes;
    for (i = 0; i < count; ++i) {
        uint32_t at = (base + 8u * (uint32_t)i) & VRAM_MASK;
        const uint8_t *a = c->vram + at;
        struct vc_sprite *s = &cache->spr[i];
        int top, h, b, b1;
        if (at > VC_VRAM_SIZE - 8) break;
        if ((a[6] >> 6) == 0) continue;
        top = s16(a + 4);
        h = 8 << ((a[6] >> 2) & 3);
        s->x = (int16_t)s16(a + 2);
        s->top = (int16_t)top;
        s->image = (uint16_t)be16(a);
        s->h = (uint8_t)h;
        s->w = (uint8_t)(8 << (a[6] & 3));
        s->a6 = a[6];
        s->a7 = a[7];
        if (top + h <= 0 || top >= VC_HEIGHT) continue; /* (on no line) */
        b1 = (top + h - 1 < VC_HEIGHT - 1 ? top + h - 1 : VC_HEIGHT - 1) >> 5;
        for (b = top < 0 ? 0 : top >> 5; b <= b1; ++b) cache->band[b][cache->band_n[b]++] = (uint8_t)i;
    }
}

/* The sprites of one priority (in front of layer prio - 1), over what's drawn. */
static void render_sprites(const vc_card *c, const line_sprite *list, int n, int prio, uint16_t *out,
                           vc_palette *cache) {
    const uint16_t *pal = cache->col;
    int hires = c->cfg[VC_SPR_CTRL] & 1, scale = hires ? 1 : 2, width = VC_WIDTH / scale;
    int k;
    for (k = n - 1; k >= 0; --k) { /* backwards: the lowest-numbered sprite ends up in front */
        const struct vc_sprite *sp = list[k].s;
        int w, x, bpp, i, i0, i1, flip;
        uint32_t img, rowbit, pal16;
        if ((sp->a6 >> 6) != prio) continue;
        w = sp->w;
        x = sp->x;
        bpp = sp->a7 & 0x80 ? 8 : 4;
        img = sp->image * 32u;
        flip = sp->a6 & 0x10;
        pal16 = (uint32_t)(sp->a7 & 15) * 16;
        rowbit = (uint32_t)(list[k].row * w) * (uint32_t)bpp;
        i0 = x < 0 ? -x : 0; /* (the part on the screen) */
        i1 = width - x < w ? width - x : w;
        if (bpp == 8 && ((img + rowbit / 8) & VRAM_MASK) <= VC_VRAM_SIZE - (uint32_t)w) {
            const uint8_t *s = c->vram + ((img + rowbit / 8) & VRAM_MASK); /* (none of it wraps) */
            if (scale == 1 && !flip) sprite8_row(out, pal, 1, x, s, i0, i1, w, 0);
            else if (scale == 1) sprite8_row(out, pal, 1, x, s, i0, i1, w, 1);
            else if (!flip) sprite8_row(out, pal, 2, x, s, i0, i1, w, 0);
            else sprite8_row(out, pal, 2, x, s, i0, i1, w, 1);
            continue;
        }
        if (bpp == 4 && ((img + rowbit / 8) & VRAM_MASK) <= VC_VRAM_SIZE - (uint32_t)w / 2) {
            const uint8_t *s = c->vram + ((img + rowbit / 8) & VRAM_MASK); /* (none of it wraps) */
            if (i0 == 0 && i1 == w) { /* (all of it on the screen) */
                if (scale == 1) {
                    const uint32_t *t = pair_table(cache, sp->a7 & 15);
                    if (!flip) sprite4_pairs(out + x, t, s, w / 2, 0);
                    else sprite4_pairs(out + x, t, s, w / 2, 1);
                } else if (!flip) sprite4_row(out, pal, 2, x, s, w / 2, 0, pal16);
                else sprite4_row(out, pal, 2, x, s, w / 2, 1, pal16);
                continue;
            }
            for (i = i0; i < i1; ++i) {
                int q = flip ? w - 1 - i : i;
                unsigned b = s[q >> 1], v = q & 1 ? b & 15 : b >> 4;
                if (v) {
                    uint16_t col = pal[(pal16 + v) & 0xFF];
                    if (scale == 1) out[x + i] = col;
                    else put32(out + 2 * (x + i), PAIR(col, col));
                }
            }
            continue;
        }
        for (i = i0; i < i1; ++i) {
            uint32_t bit = rowbit + (uint32_t)(flip ? w - 1 - i : i) * (uint32_t)bpp;
            unsigned v = c->vram[(img + bit / 8) & VRAM_MASK];
            if (bpp != 8) {
                v = v >> (4 - (bit & 7)) & 15;
                if (v) v = (pal16 + v) & 0xFF;
            }
            if (v) {
                uint16_t col = pal[v];
                if (scale == 1) out[x + i] = col;
                else put32(out + 2 * (x + i), PAIR(col, col));
            }
        }
    }
}

void vc_render_line(const vc_card *c, int y, uint16_t *out) {
    static vc_palette p; /* (too big for a stack; worked out again each time) */
    p.ready = 0;
    p.spr_ready = 0;
    vc_render_line_with(c, y, out, &p);
}

void vc_render_line_with(const vc_card *c, int y, uint16_t *out, vc_palette *cache) {
    uint16_t *pal = cache->col; /* the palette as RGB565, with 0 (transparent) the backdrop */
    line_sprite list[VC_MAX_LINE_SPRITES];
    int n = 0, layer, x, drawn = 0, prios = 0;
    uint8_t ctrl = c->cfg[VC_DC_CTRL];
    const uint8_t *p = c->cfg + (VC_PAL_BASE - VC_CFG_BASE);
    if (ctrl & 0x08) {
        /* The sprites on this line: the first VC_MAX_LINE_SPRITES in the table, from
         * those on its band (the table decoded again if it has changed: its count read
         * first, so a change made meanwhile is seen next line). */
        int sy = c->cfg[VC_SPR_CTRL] & 1 ? y : y / 2, j;
        uint32_t gen = *(const volatile uint32_t *)&c->spr_gen;
        const uint8_t *band;
        int bn;
        if (!cache->spr_ready || cache->spr_gen != gen) {
            decode_sprites(c, cache);
            cache->spr_gen = gen;
            cache->spr_ready = 1;
        }
        band = cache->band[sy >> 5];
        bn = cache->band_n[sy >> 5];
        for (j = 0; j < bn && n < VC_MAX_LINE_SPRITES; ++j) {
            const struct vc_sprite *s = &cache->spr[band[j]];
            int d = sy - s->top;
            if (d < 0 || d >= s->h) continue;
            list[n].s = s;
            list[n].row = s->a6 & 0x20 ? s->h - 1 - d : d;
            prios |= 1 << (s->a6 >> 6);
            ++n;
        }
        cache->sprites = n;
    }
    {
        /* The palette, if it has changed (its count read first: a change made while it's
         * worked out is seen next line). */
        uint32_t gen = *(const volatile uint32_t *)&c->pal_gen;
        uint8_t back = c->cfg[VC_DC_BACK];
        if (!cache->ready || cache->gen != gen) {
            for (x = 0; x < 256; x += 2) { /* (big-endian in the card's memory) */
                uint32_t w = get32(p + 2 * x);
#if !VC_BIG_ENDIAN
                w = (w & 0x00FF00FFu) << 8 | (w >> 8 & 0x00FF00FFu);
#endif
                put32(pal + x, w);
            }
            cache->raw0 = pal[0];
            cache->gen = gen;
            cache->ready = 1;
            if (!++cache->epoch) cache->epoch = 1; /* (the pair tables are out of date) */
        }
        pal[0] = back ? pal[back] : cache->raw0;
    }

    for (layer = 0; layer < 3; ++layer) {
        if (ctrl & (1 << layer)) {
            const uint8_t *l = c->cfg + VC_LAYER0 + VC_LAYER_SIZE * layer;
            if (drawn) render_layer(c, cache, l, y, out, pal, 0);
            else render_layer(c, cache, l, y, out, pal, 1);
            drawn = 1;
        }
        if (prios & (2 << layer)) { /* sprites in front of this layer */
            if (!drawn) fill(out, pal[0], 1, 0, VC_WIDTH);
            drawn = 1;
            render_sprites(c, list, n, layer + 1, out, cache);
        }
    }
    if (!drawn) fill(out, pal[0], 1, 0, VC_WIDTH);
}
