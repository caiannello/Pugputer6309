/* Diagnostic (-DVIDCARD_DIAG=1): how long the picture's lines take to draw, on card
 * states like the demos' (VIDDEMO, VIDTEXT), timed by main.c once the Pugputer has booted
 * and printed on the UART. It takes the card over for a moment (the picture shows its
 * states meanwhile), and main.c resets the card after. A line has 31.7 us; with core 0
 * helping, two lines have 63.4 between the cores. (The times are core 0's, alone: core 1
 * draws the same states meanwhile, and core 0's help is off.) */
#include "bench.h"

#if VIDCARD_DIAG
#include <stdio.h>
#include <string.h>

#include "card.h"
#include "dvi.h"
#include "hardware/timer.h"

static uint16_t __attribute__((aligned(4))) line[VC_WIDTH];
#define pal (*dvi_bench_palette()) /* (kept, as the card keeps it: core 0's, idle meanwhile) */
static uint32_t rng = 1;
static uint32_t rnd(void) {
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}
static void put24(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 16);
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)v;
}
static uint8_t *layer(int n) { return card.cfg + VC_LAYER0 + VC_LAYER_SIZE * n; }

/* The slowest of lines y0 to y1, each drawn 16 times, in tenths of a microsecond. */
static uint32_t slowest(int y0, int y1) {
    uint32_t worst = 0;
    ++card.spr_gen; /* (the states are written straight into the memory) */
    for (int y = y0; y < y1; ++y) {
        uint32_t t = time_us_32();
        for (int k = 0; k < 16; ++k) vc_render_line_with(&card, y, line, &pal);
        t = (time_us_32() - t) * 10 / 16;
        if (t > worst) worst = t;
    }
    return worst;
}

/* As core 1 draws the same lines meanwhile (as when the two share them), and with core 1
 * stopped: what the cores cost each other, sharing the memory. */
static void timed(const char *what, int y0, int y1) {
    uint32_t both = slowest(y0, y1);
    dvi_park = true;
    busy_wait_us(200); /* (its line ends) */
    uint32_t alone = slowest(y0, y1);
    dvi_park = false;
    printf("  %-36s %3lu.%lu us  (alone %3lu.%lu)\n", what, (unsigned long)(both / 10), (unsigned long)(both % 10),
           (unsigned long)(alone / 10), (unsigned long)(alone % 10));
}

static void text_screen(void) {
    vc_reset(&card);
    for (int i = 0; i < 128 * 32; ++i) {
        uint8_t *cell = card.vram + VC_RESET_TEXT_MAP + 4 * i;
        cell[0] = (uint8_t)(32 + rnd() % 95);
        cell[1] = 7;
        cell[2] = 0;
    }
}

/* ---- The machine: cycles an instruction, by the core's cycle counter (DWT), for loops of
 * a fixed mix, run from three places: the SRAM that all the code runs from (0x2000xxxx),
 * the scratch bank X (0x2008xxxx: SRAM, but a bank of its own), and the same code's copy
 * in flash, through the XIP cache (0x1000xxxx: the core's code bus, not its system bus).
 * Whether a load or a store holds up the fetching of instructions shows there. */
#include "hardware/structs/qmi.h"
#include "hardware/sync.h"

#define DEMCR (*(volatile uint32_t *)0xE000EDFCu)
#define DWT_CTRL (*(volatile uint32_t *)0xE0001000u)
#define DWT_CYCCNT (*(volatile uint32_t *)0xE0001004u)

static uint32_t __attribute__((aligned(16))) cpu_data[64];

#define REP16(x) x x x x x x x x x x x x x x x x
/* 16 instructions a time round (and the loop's 2) */
#define CPU_LOOPS(sfx, attr)                                                                                     \
    static uint32_t attr __attribute__((noinline)) adds_##sfx(uint32_t n, uint32_t *p) {                        \
        uint32_t a = 0, b = 0, c = 0, d = 0;                                                                    \
        (void)p;                                                                                                \
        __asm volatile("1:\n" REP16("adds %0, %0, #1\n") "subs %4, %4, #1\n bne 1b\n"                           \
                       : "+l"(a), "+l"(b), "+l"(c), "+l"(d), "+l"(n));                                          \
        return a + b + c + d;                                                                                   \
    }                                                                                                           \
    static uint32_t attr __attribute__((noinline)) loads_##sfx(uint32_t n, uint32_t *p) {                       \
        uint32_t a = 0;                                                                                         \
        __asm volatile("1:\n" REP16("ldr %0, [%2, #4]\n") "subs %1, %1, #1\n bne 1b\n"                          \
                       : "+l"(a), "+l"(n) : "l"(p) : "memory");                                                 \
        return a;                                                                                               \
    }                                                                                                           \
    static uint32_t attr __attribute__((noinline)) mixed_##sfx(uint32_t n, uint32_t *p) {                       \
        uint32_t a = 0, b = 0;                                                                                  \
        __asm volatile("1:\n" REP16("ldr %0, [%3, #8]\n adds %1, %1, #1\n") "subs %2, %2, #1\n bne 1b\n"        \
                       : "+l"(a), "+l"(b), "+l"(n) : "l"(p) : "memory");                                        \
        return a + b;                                                                                           \
    }                                                                                                           \
    static uint32_t attr __attribute__((noinline)) uses_##sfx(uint32_t n, uint32_t *p) {                        \
        uint32_t a = 0;                                                                                         \
        __asm volatile("1:\n" REP16("ldr %0, [%2, #12]\n adds %0, %0, #1\n") "subs %1, %1, #1\n bne 1b\n"       \
                       : "+l"(a), "+l"(n) : "l"(p) : "memory");                                                 \
        return a;                                                                                               \
    }                                                                                                           \
    static uint32_t attr __attribute__((noinline)) stores_##sfx(uint32_t n, uint32_t *p) {                      \
        uint32_t a = 0;                                                                                         \
        __asm volatile("1:\n" REP16("str %0, [%2, #16]\n") "subs %1, %1, #1\n bne 1b\n"                         \
                       : "+l"(a), "+l"(n) : "l"(p) : "memory");                                                 \
        return a;                                                                                               \
    }                                                                                                           \
    static uint32_t attr __attribute__((noinline)) bytes_##sfx(uint32_t n, uint32_t *p) {                       \
        uint32_t a = 0, b = 0;                                                                                  \
        __asm volatile("1:\n" REP16("ldrb %0, [%3, #20]\n strh %0, [%3, #24]\n") "subs %2, %2, #1\n bne 1b\n"   \
                       : "+l"(a), "+l"(b), "+l"(n) : "l"(p) : "memory");                                        \
        return a + b;                                                                                           \
    }                                                                                                           \
    static uint32_t attr __attribute__((noinline)) branches_##sfx(uint32_t n, uint32_t *p) {                    \
        uint32_t a = 0;                                                                                         \
        (void)p;                                                                                                \
        __asm volatile("1:\n" REP16("cmp %0, #200\n bne 2f\n 2:\n") "subs %1, %1, #1\n bne 1b\n"                \
                       : "+l"(a), "+l"(n) : : "cc");                                                            \
        return a;                                                                                               \
    }

CPU_LOOPS(ram, )
CPU_LOOPS(scr, __attribute__((section(".scratch_x.cpubench"))))

typedef uint32_t (*cpu_loop)(uint32_t, uint32_t *);
extern char __ram_text_start__[], __ram_text_source__[];

/* A function's copy in flash (copy_to_ram: the code is copied from there at start). */
static cpu_loop in_flash(cpu_loop f) {
    return (cpu_loop)((uintptr_t)f - (uintptr_t)__ram_text_start__ + (uintptr_t)__ram_text_source__);
}

/* Cycles an instruction (in hundredths), interrupts off, the loop run once first. */
static uint32_t cpi(cpu_loop f, int per_round) {
    const uint32_t n = 200;
    uint32_t s = save_and_disable_interrupts();
    f(4, cpu_data);
    uint32_t t = DWT_CYCCNT;
    f(n, cpu_data);
    t = DWT_CYCCNT - t;
    restore_interrupts(s);
    return t * 100 / (n * (uint32_t)(per_round + 2));
}

static void cpu_row(const char *what, cpu_loop ram, cpu_loop scr, int per_round) {
    uint32_t a = cpi(ram, per_round), b = cpi(scr, per_round);
    /* (the SRAM's first: if the flash's hangs, they're out) */
    printf("  %-34s %lu.%02lu   %lu.%02lu", what, (unsigned long)(a / 100), (unsigned long)(a % 100),
           (unsigned long)(b / 100), (unsigned long)(b % 100));
    uint32_t c = cpi(in_flash(ram), per_round);
    printf("   %lu.%02lu\n", (unsigned long)(c / 100), (unsigned long)(c % 100));
}

static void cpu_bench(void) {
    DEMCR |= 1u << 24; /* (TRCENA: the DWT on) */
    DWT_CYCCNT = 0;
    DWT_CTRL |= 1u;    /* CYCCNTENA */
    /* The flash's clock to 56 MHz first (the boot left it for 150 MHz; nothing else reads
     * the flash after start), its read delay as the PSRAM's is worked out. */
    uint32_t tm = qmi_hw->m[0].timing;
    qmi_hw->m[0].timing = (tm & ~(QMI_M0_TIMING_CLKDIV_BITS | QMI_M0_TIMING_RXDELAY_BITS)) |
                          6u << QMI_M0_TIMING_CLKDIV_LSB | 6u << QMI_M0_TIMING_RXDELAY_LSB;
    dvi_park = true; /* (core 1 off the memory meanwhile) */
    busy_wait_us(200);
    printf("\nThe machine, cycles an instruction (code in: SRAM, scratch X, flash):\n");
    cpu_row("adds (no memory)", adds_ram, adds_scr, 16);
    cpu_row("loads", loads_ram, loads_scr, 16);
    cpu_row("a load, an add", mixed_ram, mixed_scr, 32);
    cpu_row("a load, an add of it", uses_ram, uses_scr, 32);
    cpu_row("stores", stores_ram, stores_scr, 16);
    cpu_row("a byte load, a halfword store", bytes_ram, bytes_scr, 32);
    cpu_row("a compare, a branch taken", branches_ram, branches_scr, 32);
    dvi_park = false;
}

void bench_run(void) {
    cpu_bench();
    dvi_solo = true;
    printf("\nDrawing a line (it has 31.7 us), the slowest:\n");
    text_screen();
    timed("the 80x30 text screen, full", 0, 480);

    /* VIDDEMO: a 320x240 bitmap (8 bits a pixel), 64x32 tiles (4 bits, 8x8) with one row
     * of beads, the text screen in front, 8 16x16 sprites (all on lines 100-115 here). */
    vc_reset(&card);
    card.cfg[VC_DC_CTRL] = 0x0F;
    card.cfg[VC_SPR_COUNT] = 8;
    uint8_t *l = layer(0);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_BITMAP | 0x18;
    l[VC_L_STRIDE] = 320 >> 8;
    l[VC_L_STRIDE + 1] = 320 & 255;
    for (int i = 0; i < 320 * 240; ++i) card.vram[i] = (uint8_t)(1 + rnd() % 255);
    l = layer(1);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TILE | 0x10;
    l[VC_L_MAP] = 1;
    put24(l + VC_L_MAPBASE, 0x14000);
    put24(l + VC_L_TILEBASE, 0x15000);
    for (int x = 0; x < 64; x += 2) {
        card.vram[0x14000 + (3 * 64 + x) * 2] = (uint8_t)((6 + (x / 2 & 7)) << 4);
        card.vram[0x14000 + (3 * 64 + x) * 2 + 1] = 1;
    }
    for (int i = 32; i < 64; ++i) card.vram[0x15000 + i] = (uint8_t)rnd();
    l = layer(2);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TEXT | 0x04 | 0x20;
    l[VC_L_MAP] = 2;
    put24(l + VC_L_MAPBASE, VC_RESET_TEXT_MAP);
    put24(l + VC_L_TILEBASE, VC_RESET_FONT);
    for (int i = 0; i < 26; ++i) {
        uint8_t *c = card.vram + VC_RESET_TEXT_MAP + (1 * 128 + 27 + i) * 4;
        c[0] = (uint8_t)('A' + i);
        c[1] = 231;
        c[2] = 16;
    }
    for (int i = 0; i < 8 * 256; ++i) card.vram[0x16000 + i] = (uint8_t)rnd();
    for (int s = 0; s < 8; ++s) {
        uint8_t *a = card.vram + VC_RESET_SPR_BASE + 8 * s;
        int img = 0x16000 / 32 + s * 8, x = 20 + 37 * s, y = 50;
        a[0] = (uint8_t)(img >> 8), a[1] = (uint8_t)img, a[2] = (uint8_t)(x >> 8), a[3] = (uint8_t)x;
        a[4] = (uint8_t)(y >> 8), a[5] = (uint8_t)y, a[6] = 0x05 | 0xC0, a[7] = 0x80;
    }
    timed("VIDDEMO, a plain line", 0, 40);
    for (int k = 0; k < 4; ++k) { /* (what it's made of) */
        static const char *const what[4] = {"  its bitmap alone", "  its tiles alone", "  its text alone",
                                            "  nothing (the backdrop)"};
        card.cfg[VC_DC_CTRL] = (uint8_t)(k < 3 ? 1 << k : 0);
        timed(what[k], 0, 40);
    }
    card.cfg[VC_DC_CTRL] = 0x0F;
    timed("VIDDEMO, the beads and the title", 48, 64);
    timed("VIDDEMO, 8 sprites on the line", 100, 116);

    /* VIDTEXT page 1: the text screen, full, under a 320x240 text layer, mostly empty. */
    text_screen();
    for (int i = 0; i < 128 * 32; ++i) card.vram[VC_RESET_TEXT_MAP + 4 * i + 2] = 16;
    card.cfg[VC_DC_CTRL] = 0x03;
    l = layer(1);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TEXT | 0x20;
    l[VC_L_MAP] = 1;
    put24(l + VC_L_MAPBASE, 0x30000);
    put24(l + VC_L_TILEBASE, VC_RESET_FONT);
    l[VC_L_HSCROLL + 1] = 3;
    memset(card.vram + 0x30000, 0, 64 * 32 * 4);
    for (int i = 0; i < 64; ++i) {
        uint8_t *c = card.vram + 0x30000 + (11 * 64 + i) * 4;
        c[0] = (uint8_t)('A' + i % 26);
        c[1] = (uint8_t)(196 + i);
    }
    timed("VIDTEXT 1, a plain line", 0, 40);
    timed("VIDTEXT 1, the marquee", 176, 208);

    /* VIDTEXT page 2: 80x60 cells of an 8x8 font, full, under the text screen (spaces on
     * see-through, but for a heading). */
    text_screen();
    card.cfg[VC_DC_CTRL] = 0x03;
    l = layer(0);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TEXT | 0x04;
    l[VC_L_MAP] = 2 | 4;
    put24(l + VC_L_MAPBASE, 0x20000);
    put24(l + VC_L_TILEBASE, 0x3E000);
    l[VC_L_VSCROLL + 1] = 5;
    for (int i = 0; i < 128 * 64; ++i) {
        uint8_t *c = card.vram + 0x20000 + 4 * i;
        c[0] = (uint8_t)(32 + rnd() % 95);
        c[1] = 196;
        c[2] = 0;
    }
    for (int i = 0; i < 2048; ++i) card.vram[0x3E000 + i] = (uint8_t)rnd();
    l = layer(1);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TEXT | 0x04 | 0x20;
    l[VC_L_MAP] = 2;
    put24(l + VC_L_MAPBASE, VC_RESET_TEXT_MAP);
    put24(l + VC_L_TILEBASE, VC_RESET_FONT);
    for (int i = 0; i < 128 * 32; ++i) card.vram[VC_RESET_TEXT_MAP + 4 * i + 2] = 0;
    for (int i = 0; i < 80; ++i) {
        uint8_t *c = card.vram + VC_RESET_TEXT_MAP + 4 * i;
        c[0] = (uint8_t)('A' + i % 26);
        c[1] = 231;
        c[2] = 18;
    }
    timed("VIDTEXT 2, the heading", 0, 16);
    timed("VIDTEXT 2, a plain line", 100, 140);

    /* The worst a layer can be: three full-screen 640x480 layers of 8x8 tiles, 4 bits a
     * pixel, none of it see-through, and 32 64-pixel sprites on the line. */
    vc_reset(&card);
    card.cfg[VC_DC_CTRL] = 0x0F;
    card.cfg[VC_SPR_CTRL] = 1;
    card.cfg[VC_SPR_COUNT] = 32;
    for (int n = 0; n < 3; ++n) {
        l = layer(n);
        memset(l, 0, 16);
        l[VC_L_MODE] = VC_TILE | 0x04 | 0x10;
        l[VC_L_MAP] = 1 | 4;
        put24(l + VC_L_MAPBASE, 0x10000u * (uint32_t)n);
        put24(l + VC_L_TILEBASE, 0x30000);
    }
    for (int i = 0; i < 3 * 0x10000; ++i) card.vram[i] = (uint8_t)rnd();
    for (int i = 0; i < 0x8000; ++i) card.vram[0x30000 + i] = (uint8_t)(rnd() | 0x11);
    for (int s = 0; s < 32; ++s) {
        uint8_t *a = card.vram + VC_RESET_SPR_BASE + 8 * s;
        int img = 0x30000 / 32, x = 18 * s, y = 200;
        a[0] = (uint8_t)(img >> 8), a[1] = (uint8_t)img, a[2] = (uint8_t)(x >> 8), a[3] = (uint8_t)x;
        a[4] = (uint8_t)(y >> 8), a[5] = (uint8_t)y, a[6] = 0x0F | 0xC0, a[7] = 0x80;
    }
    timed("3 solid tile layers, 32 sprites", 200, 216);

    /* VIDGFX page 1: a 640x480 bitmap of 4 bits a pixel, the text screen over it. */
    text_screen();
    for (int i = 0; i < 128 * 32; ++i) card.vram[VC_RESET_TEXT_MAP + 4 * i] = ' ';
    card.cfg[VC_DC_CTRL] = 0x05;
    l = layer(0);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_BITMAP | 0x04 | 0x10;
    l[VC_L_STRIDE + 1] = 64, l[VC_L_STRIDE] = 1; /* 320 */
    l[VC_L_PALOFS] = 1;
    for (int i = 0; i < 320 * 480; ++i) card.vram[i] = (uint8_t)rnd();
    l = layer(2);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TEXT | 0x04 | 0x20;
    l[VC_L_MAP] = 2;
    put24(l + VC_L_MAPBASE, VC_RESET_TEXT_MAP);
    put24(l + VC_L_TILEBASE, VC_RESET_FONT);
    timed("VIDGFX 1 (4-bit 640x480, text)", 0, 480);

    /* VIDGFX page 2: 320x240 of 8 bits, an 80x64 spinner of 2 bits, words of 1 bit at
     * 640x480 (a line of them). */
    vc_reset(&card);
    card.cfg[VC_DC_CTRL] = 0x07;
    card.cfg[VC_DC_BACK] = 128;
    l = layer(0);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_BITMAP | 0x18;
    l[VC_L_STRIDE] = 320 >> 8, l[VC_L_STRIDE + 1] = 320 & 255;
    for (int i = 0; i < 320 * 240; ++i) card.vram[i] = (uint8_t)(32 + rnd() % 64);
    l = layer(1);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_BITMAP | 0x08;
    put24(l + VC_L_MAPBASE, 0x14000);
    l[VC_L_HSCROLL] = 0xFF, l[VC_L_HSCROLL + 1] = (uint8_t)-20;
    l[VC_L_VSCROLL] = 0xFF, l[VC_L_VSCROLL + 1] = (uint8_t)-30;
    l[VC_L_STRIDE + 1] = 20;
    l[VC_L_PALOFS] = 7;
    for (int i = 0; i < 0x1000; ++i) card.vram[0x14000 + i] = (uint8_t)rnd();
    l = layer(2);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_BITMAP | 0x04;
    put24(l + VC_L_MAPBASE, 0x18000);
    l[VC_L_STRIDE + 1] = 80;
    l[VC_L_PALOFS] = 15;
    memset(card.vram + 0x18000, 0, 80 * 480);
    for (int i = 0; i < 80 * 16; ++i) card.vram[0x18000 + 80 * 200 + i] = (uint8_t)rnd();
    timed("VIDGFX 2, the spinner's lines", 60, 188);
    timed("VIDGFX 2, the words' lines", 200, 216);

    /* VIDTILES page 1, at 320x240: 16x16 tiles of 8 bits, 8x8 tiles of 2 bits, the text
     * screen, and its 6 sprites of 4 bits (16 to 64 pixels), all on the line here. */
    text_screen();
    for (int i = 0; i < 128 * 32; ++i) card.vram[VC_RESET_TEXT_MAP + 4 * i] = ' ';
    card.cfg[VC_DC_CTRL] = 0x0F;
    card.cfg[VC_DC_BACK] = 153;
    card.cfg[VC_SPR_CTRL] = 0;
    card.cfg[VC_SPR_COUNT] = 6;
    l = layer(0);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TILE | 0x18 | 0x20;
    l[VC_L_MAP] = 1;
    put24(l + VC_L_MAPBASE, 0x20000);
    put24(l + VC_L_TILEBASE, 0x21000);
    l = layer(1);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TILE | 0x08;
    l[VC_L_MAP] = 1;
    put24(l + VC_L_MAPBASE, 0x22000);
    put24(l + VC_L_TILEBASE, 0x23000);
    l = layer(2);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TEXT | 0x04 | 0x20;
    l[VC_L_MAP] = 2;
    put24(l + VC_L_MAPBASE, VC_RESET_TEXT_MAP);
    put24(l + VC_L_TILEBASE, VC_RESET_FONT);
    for (int i = 0; i < 64 * 32; ++i) { /* (half the entries a tile, half the empty one) */
        uint16_t e = rnd() % 2 ? (uint16_t)(1 + rnd() % 15) : 0;
        card.vram[0x20000 + 2 * i] = (uint8_t)(e >> 8), card.vram[0x20000 + 2 * i + 1] = (uint8_t)e;
        e = rnd() % 2 ? (uint16_t)((1 + rnd() % 15) | (rnd() & 0xF400)) : 0;
        card.vram[0x22000 + 2 * i] = (uint8_t)(e >> 8), card.vram[0x22000 + 2 * i + 1] = (uint8_t)e;
    }
    memset(card.vram + 0x21000, 0, 256);
    for (int i = 256; i < 16 * 256; ++i) card.vram[0x21000 + i] = (uint8_t)rnd();
    memset(card.vram + 0x23000, 0, 16);
    for (int i = 16; i < 16 * 16; ++i) card.vram[0x23000 + i] = (uint8_t)rnd();
    for (int i = 0; i < 0x2000; ++i) card.vram[0x24000 + i] = (uint8_t)(rnd() & rnd()); /* (a little see-through) */
    for (int s = 0; s < 6; ++s) {
        static const uint8_t size[6] = {0x05, 0x05, 0x00, 0x05, 0x0A, 0x0F}, flip[6] = {0, 0x30, 0, 0, 0x10, 0};
        uint8_t *a = card.vram + VC_RESET_SPR_BASE + 8 * s;
        int img = 0x24000 / 32 + 64 * s, x = 10 + 50 * s, y = 100;
        a[0] = (uint8_t)(img >> 8), a[1] = (uint8_t)img, a[2] = (uint8_t)(x >> 8), a[3] = (uint8_t)x;
        a[4] = (uint8_t)(y >> 8), a[5] = (uint8_t)y, a[6] = (uint8_t)(size[s] | flip[s] | (1 + s % 3) << 6), a[7] = 2;
    }
    timed("VIDTILES 1, a line without sprites", 0, 64);
    timed("VIDTILES 1, the 6 sprites' lines", 200, 216);

    /* VIDTILES page 2, at 640x480: 8x8 tiles of 1 bit, hires, the text screen, and 32
     * 16x16 sprites of 4 bits on the line (the most the card draws). */
    card.cfg[VC_DC_CTRL] = 0x0D;
    card.cfg[VC_DC_BACK] = 0;
    card.cfg[VC_SPR_CTRL] = 1;
    card.cfg[VC_SPR_COUNT] = 128; /* (the other 88 down the screen, as the rings are) */
    for (int s = 40; s < 128; ++s) {
        uint8_t *a = card.vram + VC_RESET_SPR_BASE + 8 * s;
        int img = 0x25000 / 32, x = (int)(rnd() % 600), y = (int)(rnd() % 440);
        if (y >= 280 && y < 320) y += 60; /* (off the row's lines) */
        a[0] = (uint8_t)(img >> 8), a[1] = (uint8_t)img, a[2] = (uint8_t)(x >> 8), a[3] = (uint8_t)x;
        a[4] = (uint8_t)(y >> 8), a[5] = (uint8_t)y, a[6] = 0x05 | 0xC0, a[7] = 3;
    }
    l = layer(0);
    memset(l, 0, 16);
    l[VC_L_MODE] = VC_TILE | 0x04;
    l[VC_L_MAP] = 2 | 4; /* 128x64 */
    put24(l + VC_L_MAPBASE, 0x20000);
    put24(l + VC_L_TILEBASE, 0x24000);
    l[VC_L_HSCROLL + 1] = 3;
    for (int i = 0; i < 128 * 64; ++i) {
        uint16_t e = (uint16_t)(rnd() % 4 | (rnd() & 0xF000));
        card.vram[0x20000 + 2 * i] = (uint8_t)(e >> 8), card.vram[0x20000 + 2 * i + 1] = (uint8_t)e;
    }
    memset(card.vram + 0x24000, 0, 8);
    for (int i = 8; i < 32; ++i) card.vram[0x24000 + i] = (uint8_t)(rnd() & rnd());
    for (int i = 0; i < 128; ++i) card.vram[0x25000 + i] = (uint8_t)(rnd() & rnd());
    for (int s = 0; s < 40; ++s) {
        uint8_t *a = card.vram + VC_RESET_SPR_BASE + 8 * s;
        int img = 0x25000 / 32, x = 16 * s, y = 300;
        a[0] = (uint8_t)(img >> 8), a[1] = (uint8_t)img, a[2] = (uint8_t)(x >> 8), a[3] = (uint8_t)x;
        a[4] = (uint8_t)(y >> 8), a[5] = (uint8_t)y, a[6] = 0x05 | 0xC0, a[7] = 3;
    }
    timed("VIDTILES 2, a line without sprites", 0, 64);
    timed("VIDTILES 2, 32 sprites on the line", 300, 316);
    printf("\n");
    vc_reset(&card);
    dvi_solo = false;
}
#endif
