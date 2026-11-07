/* DVI out through HSTX, after the Pico SDK's hstx/dvi_out_hstx_encoder example: HSTX's
 * TMDS encoder turns RGB565 pixels into the three channels, two DMA channels take turns
 * feeding it a line at a time (the sync periods as raw control symbols, then the pixels),
 * and the lines are drawn ahead of the beam, into eight buffers taken in turn.
 *
 * Who draws: core 1, every line it can. A line can take longer than the 31.7 us it has
 * (several layers and sprites): when core 1 couldn't keep up in the last frame, core 0
 * draws too (in an interrupt of the lowest priority, rung by core 1: under the bus's,
 * over the main loop), and lines are drawn up to seven ahead (else one): the cores get
 * ahead on the quick lines, for a run of slow ones (VIDTILES' row of 32 sprites, 16 lines
 * of them, each slower than the two cores' 63 us). Each core takes
 * the next line not yet taken, in order; one whose time has gone is skipped.
 *
 * Lines are numbered as the card numbers them (vc.h): 0-479 shown, then 480-489 the
 * front porch, 490-491 vertical sync, 492-524 the back porch. */
#include "dvi.h"

#include "blockdev.h"
#include "card.h"
#include "config.h"
#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "hardware/structs/bus_ctrl.h"
#include "hardware/structs/hstx_ctrl.h"
#include "hardware/structs/hstx_fifo.h"
#include "hardware/sync.h"
#include "hardware/timer.h"
#include "pico/multicore.h"

volatile uint32_t dvi_late_lines;

#if VIDCARD_DIAG
volatile uint32_t diag_render_us_max, diag_lines_drawn, diag_lines_core0, diag_help_frames;
volatile uint16_t diag_strip_us[30]; /* by 16 lines: the slowest drawn (either core) */
volatile uint8_t diag_strip_sprites[30]; /* and the most sprites on one */
volatile bool dvi_solo, dvi_park;
#endif

/* 640x480 at 60 Hz: 800 pixels a line, 525 lines; both syncs negative. */
#define H_FRONT 16
#define H_SYNC 96
#define H_BACK 48
#define H_ACTIVE 640
#define V_ACTIVE 480
#define V_FRONT 10
#define V_SYNC 2
#define V_TOTAL 525
#define V_SYNC_FIRST (V_ACTIVE + V_FRONT)

/* TMDS control symbols: channel 0 carries the syncs (bit 0 H, bit 1 V); high is idle. */
#define TMDS_CTRL_00 0x354u
#define TMDS_CTRL_01 0x0abu
#define TMDS_CTRL_10 0x154u
#define TMDS_CTRL_11 0x2abu
#define SYNC(ctrl0) ((ctrl0) | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20))
#define SYNC_V1_H1 SYNC(TMDS_CTRL_11)
#define SYNC_V1_H0 SYNC(TMDS_CTRL_10)
#define SYNC_V0_H1 SYNC(TMDS_CTRL_01)
#define SYNC_V0_H0 SYNC(TMDS_CTRL_00)

#define HSTX_CMD_RAW_REPEAT (0x1u << 12)
#define HSTX_CMD_TMDS (0x2u << 12)
#define HSTX_CMD_NOP (0xfu << 12)

static uint32_t blank_line[] = {
    HSTX_CMD_RAW_REPEAT | H_FRONT, SYNC_V1_H1,
    HSTX_CMD_RAW_REPEAT | H_SYNC, SYNC_V1_H0,
    HSTX_CMD_RAW_REPEAT | (H_BACK + H_ACTIVE), SYNC_V1_H1,
};
static uint32_t vsync_line[] = {
    HSTX_CMD_RAW_REPEAT | H_FRONT, SYNC_V0_H1,
    HSTX_CMD_RAW_REPEAT | H_SYNC, SYNC_V0_H0,
    HSTX_CMD_RAW_REPEAT | (H_BACK + H_ACTIVE), SYNC_V0_H1,
};
static uint32_t active_line[] = {
    HSTX_CMD_RAW_REPEAT | H_FRONT, SYNC_V1_H1, HSTX_CMD_NOP,
    HSTX_CMD_RAW_REPEAT | H_SYNC, SYNC_V1_H0, HSTX_CMD_NOP,
    HSTX_CMD_RAW_REPEAT | H_BACK, SYNC_V1_H1,
    HSTX_CMD_TMDS | H_ACTIVE, /* then the pixels */
};

#define BUFFERS 8 /* (a power of 2 that divides V_ACTIVE) */
static uint16_t __attribute__((aligned(4))) pixels[BUFFERS][H_ACTIVE];

static uint dma_ping, dma_pong;
static bool pong;
static uint16_t line;     /* the line whose transfer goes next */
static bool line_started; /* a shown line: its syncs have gone, its pixels are next */
static uint16_t beam = V_TOTAL - 1; /* the line whose transfer is going */

/* The lines to draw, numbered on from the first frame's line 0 (line n's buffer is n %
 * BUFFERS): base is this frame's line 0, lines before limit may be drawn (their buffers
 * are free), shown is the one going out now, and next the next to take. Changed with
 * the lock held (both cores take lines). drawn[b] is the line last drawn in buffer b. */
static spin_lock_t *draw_lock;
static uint32_t base = (uint32_t)-V_ACTIVE, limit, shown = (uint32_t)-1, next;
static volatile uint32_t drawn[BUFFERS];
static volatile bool help;            /* core 0 draws too, this frame */
static volatile uint32_t frame_worst; /* core 1's slowest line this frame (us) */
static uint bell;                     /* rings core 0 */
#define HELP_FROM_US 31               /* core 0 helps after a frame with a line this slow */
#define HELP_UNTIL_US 28              /* and stops after one with none (core 1 alone draws
                                       * a line ahead: up to 31.7 us, and a few to spare) */

/* The next line to draw, if there is one: its number, and its line on the screen. */
static bool take_line(uint32_t *n, int *y) {
    uint32_t s = spin_lock_blocking(draw_lock);
    uint32_t k = next;
    if ((int32_t)(k - shown) <= 0) k = shown + 1; /* (those have gone) */
    bool ok = (int32_t)(limit - k) > 0;
    if (ok) {
        next = k + 1;
        *n = k;
        *y = (int)(k - base);
    }
    spin_unlock(draw_lock, s);
    return ok;
}

static vc_palette palettes[2]; /* each core's */

static void draw(uint32_t n, int y) {
    vc_palette *p = &palettes[get_core_num()];
#if VIDCARD_DIAG
    uint32_t t0 = time_us_32();
#endif
    vc_render_line_with(&card, y, pixels[n % BUFFERS], p);
    drawn[n % BUFFERS] = n;
#if VIDCARD_DIAG
    uint32_t dt = time_us_32() - t0;
    if (dt > diag_strip_us[y >> 4]) diag_strip_us[y >> 4] = (uint16_t)dt; /* (a race between the cores: no matter) */
    p->sprites = card.cfg[VC_DC_CTRL] & 8 ? p->sprites : 0;
    if (p->sprites > diag_strip_sprites[y >> 4]) diag_strip_sprites[y >> 4] = (uint8_t)p->sprites;
#endif
}

#if VIDCARD_DIAG
uint32_t dvi_decodes(void) { return palettes[0].decodes + palettes[1].decodes; }
#endif

/* Core 0's part: lines while core 1 is behind. But not while its main loop has work the
 * CPU may be waiting on, whatever the picture: an SD card command, or a reset (DOS, as a
 * program quits, reads the SD card, and gives up if that takes too long). */
static void __isr help_isr(void) {
    multicore_doorbell_clear_current_core(bell);
    uint32_t n;
    int y;
#if VIDCARD_DIAG
    if (dvi_solo) return;
#endif
    while (help && !blockdev_waiting() && !card_waiting() && take_line(&n, &y)) {
        draw(n, y);
#if VIDCARD_DIAG
        ++diag_lines_core0;
#endif
    }
}

/* (with the lock held) */
static void set_limit(uint32_t s, uint32_t l) {
    shown = s;
    limit = l;
}

/* The transfer now going is line g's: the card's beam is there. */
static void beam_at(uint16_t g) {
    if (g != beam) {
        beam = g;
        card_begin_line(g);
    }
}

/* A transfer has finished: the channel that did it is set up for the one after the
 * transfer now going (the two take turns). The card's beam moves on here too. */
static void __isr dma_isr(void) {
    uint ch = pong ? dma_pong : dma_ping;
    dma_channel_hw_t *c = &dma_hw->ch[ch];
    dma_hw->intr = 1u << ch;
    pong = !pong;
    if (line >= V_ACTIVE) {
        bool vs = line >= V_SYNC_FIRST && line < V_SYNC_FIRST + V_SYNC;
        c->read_addr = (uintptr_t)(vs ? vsync_line : blank_line);
        c->transfer_count = 6;
        beam_at((uint16_t)((line + V_TOTAL - 1) % V_TOTAL));
        if (line == V_TOTAL - 4) {
            /* The next frame: its first lines, in good time. Core 0 helps with it if a
             * line of the last one was too slow for core 1. */
            uint32_t w = frame_worst;
            frame_worst = 0;
            help = help ? w >= HELP_UNTIL_US : w >= HELP_FROM_US;
#if VIDCARD_DIAG
            if (help) ++diag_help_frames;
#endif
            uint32_t s = spin_lock_blocking(draw_lock);
            base += V_ACTIVE;
            if ((int32_t)(next - base) < 0) next = base;
            set_limit(base - 1, base + (help ? BUFFERS : 1));
            spin_unlock(draw_lock, s);
            if (help) multicore_doorbell_set_other_core(bell);
        }
        line = (uint16_t)((line + 1) % V_TOTAL);
    } else if (!line_started) {
        c->read_addr = (uintptr_t)active_line;
        c->transfer_count = count_of(active_line);
        beam_at((uint16_t)((line + V_TOTAL - 1) % V_TOTAL)); /* (the line before's pixels) */
        line_started = true;
    } else {
        /* Its pixels, which should be drawn by now. The buffer before has just gone
         * out: the line BUFFERS - 1 on may be drawn there, when core 0 is helping; else
         * just the next (as near the beam as it can be, so a change the CPU makes on a
         * line interrupt shows where it would be expected: the line after next). */
        uint32_t n = base + line;
        c->read_addr = (uintptr_t)pixels[n % BUFFERS];
        c->transfer_count = H_ACTIVE / 2;
        beam_at(line); /* (its syncs) */
        if (drawn[n % BUFFERS] != n) ++dvi_late_lines;
        uint32_t ahead = help ? BUFFERS : 2;
        uint32_t l = line + ahead < V_ACTIVE ? n + ahead : base + V_ACTIVE;
        uint32_t s = spin_lock_blocking(draw_lock);
        set_limit(n, l);
        spin_unlock(draw_lock, s);
        if (help) multicore_doorbell_set_other_core(bell);
        line_started = false;
        line = (uint16_t)(line + 1);
    }
    __sev();
}

static void hstx_init(void) {
    /* RGB565, two pixels a word, the first in the low half: each channel takes its bits
     * from the top of an 8-bit field, after rotating right. */
    hstx_ctrl_hw->expand_tmds = 4u << HSTX_CTRL_EXPAND_TMDS_L2_NBITS_LSB |  /* red, 5 bits  */
                                8u << HSTX_CTRL_EXPAND_TMDS_L2_ROT_LSB |
                                5u << HSTX_CTRL_EXPAND_TMDS_L1_NBITS_LSB |  /* green, 6     */
                                3u << HSTX_CTRL_EXPAND_TMDS_L1_ROT_LSB |
                                4u << HSTX_CTRL_EXPAND_TMDS_L0_NBITS_LSB |  /* blue, 5      */
                                29u << HSTX_CTRL_EXPAND_TMDS_L0_ROT_LSB;
    hstx_ctrl_hw->expand_shift = 2u << HSTX_CTRL_EXPAND_SHIFT_ENC_N_SHIFTS_LSB |
                                 16u << HSTX_CTRL_EXPAND_SHIFT_ENC_SHIFT_LSB |
                                 1u << HSTX_CTRL_EXPAND_SHIFT_RAW_N_SHIFTS_LSB |
                                 0u << HSTX_CTRL_EXPAND_SHIFT_RAW_SHIFT_LSB;
    /* 10 bits a pixel, 2 a clock: 5 HSTX clocks (126 MHz) a pixel, 25.2 MHz. */
    hstx_ctrl_hw->csr = 0;
    hstx_ctrl_hw->csr = HSTX_CTRL_CSR_EXPAND_EN_BITS | 5u << HSTX_CTRL_CSR_CLKDIV_LSB |
                        5u << HSTX_CTRL_CSR_N_SHIFTS_LSB | 2u << HSTX_CTRL_CSR_SHIFT_LSB | HSTX_CTRL_CSR_EN_BITS;

    /* GPIO 12-19 are HSTX bits 0-7: D2+ D2- CK+ CK- D1+ D1- D0+ D0-. */
    hstx_ctrl_hw->bit[2] = HSTX_CTRL_BIT0_CLK_BITS;
    hstx_ctrl_hw->bit[3] = HSTX_CTRL_BIT0_CLK_BITS | HSTX_CTRL_BIT0_INV_BITS;
    static const int lane_bit[3] = {6, 4, 0}; /* D0, D1, D2 */
    for (uint lane = 0; lane < 3; ++lane) {
        uint32_t sel = (lane * 10) << HSTX_CTRL_BIT0_SEL_P_LSB | (lane * 10 + 1) << HSTX_CTRL_BIT0_SEL_N_LSB;
        hstx_ctrl_hw->bit[lane_bit[lane]] = sel;
        hstx_ctrl_hw->bit[lane_bit[lane] + 1] = sel | HSTX_CTRL_BIT0_INV_BITS;
    }
    for (uint p = PIN_DVI_FIRST; p < PIN_DVI_FIRST + 8; ++p) gpio_set_function(p, GPIO_FUNC_HSTX);
}

static void dma_init(void) {
    dma_ping = (uint)dma_claim_unused_channel(true);
    dma_pong = (uint)dma_claim_unused_channel(true);
    for (int i = 0; i < 2; ++i) {
        uint ch = i ? dma_pong : dma_ping;
        dma_channel_config c = dma_channel_get_default_config(ch);
        channel_config_set_chain_to(&c, i ? dma_ping : dma_pong);
        channel_config_set_dreq(&c, DREQ_HSTX);
        dma_channel_configure(ch, &c, &hstx_fifo_hw->fifo, blank_line, count_of(blank_line), false);
    }
    line = V_ACTIVE + 1; /* (the first two transfers are blank lines) */
    dma_hw->ints1 = (1u << dma_ping) | (1u << dma_pong);
    dma_hw->inte1 = (1u << dma_ping) | (1u << dma_pong);
    irq_set_exclusive_handler(DMA_IRQ_1, dma_isr);
    irq_set_priority(DMA_IRQ_1, 0);
    irq_set_enabled(DMA_IRQ_1, true);
    /* The DMA first on the bus: a late word is a glitch on the screen. */
    bus_ctrl_hw->priority = BUSCTRL_BUS_PRIORITY_DMA_W_BITS | BUSCTRL_BUS_PRIORITY_DMA_R_BITS;
    dma_channel_start(dma_ping);
}

void dvi_init(void) {
    draw_lock = spin_lock_instance((uint)spin_lock_claim_unused(true));
    bell = (uint)multicore_doorbell_claim_unused(0x3, true);
    for (int b = 0; b < BUFFERS; ++b) drawn[b] = (uint32_t)-1;
    /* core 0's part: under everything else */
    irq_set_exclusive_handler(multicore_doorbell_irq_num(bell), help_isr);
    irq_set_priority(multicore_doorbell_irq_num(bell), PICO_LOWEST_IRQ_PRIORITY);
    irq_set_enabled(multicore_doorbell_irq_num(bell), true);
}

void dvi_run(void) {
    hstx_init();
    dma_init(); /* (here, so its interrupt is core 1's) */
    for (;;) {
        uint32_t n;
        int y;
#if VIDCARD_DIAG
        if (dvi_park) { /* (bench.c: core 1 draws nothing for a moment) */
            __wfe();
            continue;
        }
#endif
        if (!take_line(&n, &y)) {
            __wfe(); /* (until the DMA's interrupt: SEV) */
            continue;
        }
        uint32_t t0 = time_us_32();
        draw(n, y);
        uint32_t dt = time_us_32() - t0;
        if (dt > frame_worst) frame_worst = dt;
#if VIDCARD_DIAG
        /* Diagnostic: how long a line takes to draw (it has 31.7 us). */
        if (dt > diag_render_us_max) diag_render_us_max = dt;
        ++diag_lines_drawn;
#endif
    }
}
