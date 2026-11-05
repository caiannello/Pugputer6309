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
    card_system_reset();
}

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

    for (;;) {
        card_poll();
        blockdev_poll();
    }
}
