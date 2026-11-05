/* DVI out through HSTX, after the Pico SDK's hstx/dvi_out_hstx_encoder example: HSTX's
 * TMDS encoder turns RGB565 pixels into the three channels, two DMA channels take turns
 * feeding it a line at a time (the sync periods as raw control symbols, then the pixels),
 * and core 1 draws each line into one of two buffers while the other goes out.
 *
 * Lines are numbered as the card numbers them (vc.h): 0-479 shown, then 480-489 the
 * front porch, 490-491 vertical sync, 492-524 the back porch. */
#include "dvi.h"

#include "card.h"
#include "config.h"
#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "hardware/structs/bus_ctrl.h"
#include "hardware/structs/hstx_ctrl.h"
#include "hardware/structs/hstx_fifo.h"
#include "hardware/sync.h"

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

static uint16_t __attribute__((aligned(4))) pixels[2][H_ACTIVE];

static uint dma_ping, dma_pong;
static bool pong;
static uint16_t line;            /* the line whose transfer goes next */
static bool line_started;        /* a shown line: its syncs have gone, its pixels are next */
static volatile uint16_t beam;   /* the line the beam is on, for card_begin_line */
static volatile int16_t to_draw; /* a line to draw now (-1: none) */

/* A transfer has finished: the channel that did it is set up for the one after the
 * transfer now going (the two take turns). */
static void __isr dma_isr(void) {
    uint ch = pong ? dma_pong : dma_ping;
    dma_channel_hw_t *c = &dma_hw->ch[ch];
    dma_hw->intr = 1u << ch;
    pong = !pong;
    if (line >= V_ACTIVE) {
        bool vs = line >= V_SYNC_FIRST && line < V_SYNC_FIRST + V_SYNC;
        c->read_addr = (uintptr_t)(vs ? vsync_line : blank_line);
        c->transfer_count = 6;
        beam = line;
        if (line == V_TOTAL - 4) to_draw = 0; /* line 0, in good time */
        line = (uint16_t)((line + 1) % V_TOTAL);
    } else if (!line_started) {
        c->read_addr = (uintptr_t)active_line;
        c->transfer_count = count_of(active_line);
        beam = line;
        line_started = true;
    } else {
        /* Its pixels, drawn by now. The other buffer has just gone out: the next line
         * goes there. */
        c->read_addr = (uintptr_t)pixels[line & 1];
        c->transfer_count = H_ACTIVE / 2;
        if (line + 1 < V_ACTIVE) to_draw = (int16_t)(line + 1);
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

void dvi_run(void) {
    to_draw = -1;
    hstx_init();
    dma_init(); /* (here, so its interrupt is core 1's) */
    uint16_t done = beam;
    for (;;) {
        __wfe();
        /* The beam: every line it has reached, in order. */
        uint16_t now = beam;
        while (done != now) {
            done = (uint16_t)((done + 1) % V_TOTAL);
            card_begin_line(done);
        }
        /* The next line, into the buffer that isn't going out. */
        int16_t y = to_draw;
        if (y >= 0) {
            to_draw = -1;
            vc_render_line(&card, y, pixels[y & 1]);
        }
    }
}
