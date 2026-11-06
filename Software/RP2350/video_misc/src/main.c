/* The Pugputer 6309 video card's firmware, on an Olimex RP2350-PICO2-XXL: the card of
 * vidcard/core on the bus at $FF80-$FF9F, its picture out by DVI, and the Pugputer's SD
 * interface at $FFD8-$FFDB on the board's microSD card. See ../README.md.
 *
 * Core 0: the bus (an interrupt for every access), the drawing commands and the SD card.
 * Core 1: the picture. */
#include <stdio.h>

#include "blockdev.h"
#include "bus.h"
#include "card.h"
#include "config.h"
#include "dvi.h"
#include "hardware/clocks.h"
#include "hardware/gpio.h"
#include "hardware/psram.h"
#include "hardware/vreg.h"
#include "pico/multicore.h"
#include "pico/stdlib.h"

static void clocks_init(void) {
    vreg_set_voltage(CORE_VOLTAGE);
    sleep_ms(10);
    set_sys_clock_khz(SYS_CLOCK_KHZ, true);
    /* HSTX at half the system clock: 126 MHz */
    clock_configure_int_divider(clk_hstx, 0, CLOCKS_CLK_HSTX_CTRL_AUXSRC_VALUE_CLK_SYS, SYS_CLOCK_KHZ * 1000u, 2);
    /* The PSRAM's timing, for the new clock. */
    if (psram_is_available())
        psram_configure_params(PICO_DEFAULT_PSRAM_MAX_FREQ, PICO_DEFAULT_PSRAM_MAX_SELECT,
                               PICO_DEFAULT_PSRAM_MIN_DESELECT);
}

/* A line on the reset screen's text (80x30 in a 128-wide map), in gray on black. */
static void say(int row, const char *text) {
    uint8_t *cell = card.vram + VC_RESET_TEXT_MAP + (uint32_t)row * 128 * 4 + 4;
    for (; *text; ++text, cell += 4) cell[0] = (uint8_t)*text;
}

/* /RES fell: the Pugputer is being reset (not at power-on, when it's low from the start). */
static void on_reset(uint gpio, uint32_t events) {
    (void)gpio;
    (void)events;
#if VIDCARD_DIAG
    ++diag_pin_resets;
#endif
    card_system_reset();
}

#if VIDCARD_DIAG
/* Once a second, on the UART: how long it's been up, whether the picture is running
 * (FRAME counts), the resets (each one clears the screen), the pins as they are, what a
 * read of the ID/version and SD registers would get, and every register the CPU has
 * read (R) or written (W), with counts. A line on the screen too (row 3), so a black
 * screen with a picture running shows it. */
static void diag_report(uint32_t secs) {
    printf("[%lus] frame=%u pinres=%lu cardres=%lu /RES=%d /CS=%d R/W=%d copy:id=%02x ver=%02x sd=%02x %02x %02x %02x last=%05lx\n ",
           (unsigned long)secs, card.frame, (unsigned long)diag_pin_resets, (unsigned long)diag_card_resets,
           gpio_get(PIN_RESET), gpio_get(PIN_CS), gpio_get(PIN_RW), regcopy[VC_ID], regcopy[VC_VERSION],
           regcopy[COPY_SD], regcopy[COPY_SD + 1], regcopy[COPY_SD + 2], regcopy[COPY_SD + 3],
           (unsigned long)diag_last_event);
    int any = 0;
    for (int i = 0; i < 64; ++i) {
        if (diag_reads[i]) { printf(" R%02x:%lu", i, (unsigned long)diag_reads[i]); any = 1; }
        if (diag_writes[i]) { printf(" W%02x:%lu", i, (unsigned long)diag_writes[i]); any = 1; }
    }
    printf(any ? "\n" : " (no bus accesses yet)\n");
    printf("  index late: %lu (reads %lu, early = previous access's %lu); bits A0 %lu A1 %lu A2 %lu A3 %lu A4 %lu SD %lu\n",
           (unsigned long)diag_index_late, (unsigned long)diag_late_reads, (unsigned long)diag_late_prev,
           (unsigned long)diag_late_bit[0], (unsigned long)diag_late_bit[1], (unsigned long)diag_late_bit[2],
           (unsigned long)diag_late_bit[3], (unsigned long)diag_late_bit[4], (unsigned long)diag_late_bit[5]);
    if (secs == 1 || secs % 10 == 0) /* (the first ones, now and then) */
        for (uint32_t i = 0; i < diag_late_logged; ++i) {
            uint32_t e = diag_late_log[i][0];
            printf("    %c early %02lx late %02lx data %02lx, previous access %02lx\n", EV_READ(e) ? 'R' : 'W',
                   (unsigned long)EV_EARLY_INDEX(e), (unsigned long)EV_INDEX(e), (unsigned long)(e & 0xFF),
                   (unsigned long)diag_late_log[i][1]);
        }
    /* The picture: whether core 1 keeps up (a line has 31.7 us), and what row 1 holds. */
    char row1[13];
    for (int i = 0; i < 12; ++i) row1[i] = (char)card.vram[VC_RESET_TEXT_MAP + 128 * 4 + 4 + 4 * i];
    row1[12] = 0;
    printf("  lines drawn %lu, longest %lu us; row 1 \"%s\" color %u, DC_CTRL %02x\n",
           (unsigned long)diag_lines_drawn, (unsigned long)diag_render_us_max, row1,
           card.vram[VC_RESET_TEXT_MAP + 128 * 4 + 5], card.cfg[VC_DC_CTRL]);
    diag_render_us_max = 0;
    char line[80];
    snprintf(line, sizeof line, "diag %lus: frame %3u, resets pin %lu card %lu    ", (unsigned long)secs, card.frame,
             (unsigned long)diag_pin_resets, (unsigned long)diag_card_resets);
    say(3, line);
}
#endif

int main(void) {
    clocks_init();
    stdio_init_all(); /* UART0 on GPIO 0-1 (the UEXT connector), 115200 baud */
    gpio_init(PIN_LED);
    gpio_set_dir(PIN_LED, GPIO_OUT);

    card.psram = psram_is_available() ? (uint8_t *)PSRAM_ADDR : NULL;
    card_init();
    blockdev_init();
    bus_init(); /* the card answers from here; the SD card says BUSY until it's awake */
    multicore_launch_core1(dvi_run);
    blockdev_start();

    /* What it found, on the UART and on the screen (until a program resets the card). */
    char line[80];
    snprintf(line, sizeof line, "Pugputer 6309 video card: %lu MHz, PSRAM %u KB, SD card %s",
             (unsigned long)(clock_get_hz(clk_sys) / 1000000), (unsigned)(psram_get_size() / 1024),
             gpio_get(PIN_LED) ? "ready" : "not found");
    printf("\n%s\n", line);
    say(1, line);

    gpio_init(PIN_RESET);
    gpio_disable_pulls(PIN_RESET); /* (the divider sets its level) */
    gpio_set_irq_enabled_with_callback(PIN_RESET, GPIO_IRQ_EDGE_FALL, true, on_reset);

#if VIDCARD_DIAG
    uint32_t secs = 0, next = time_us_32() + 1000000;
#endif
    for (;;) {
        card_poll();
        blockdev_poll();
#if VIDCARD_DIAG
        if ((int32_t)(time_us_32() - next) >= 0) {
            next += 1000000;
            diag_report(++secs);
        }
#endif
    }
}
