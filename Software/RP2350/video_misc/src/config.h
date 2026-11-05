/* The card's pins and clocks: the Olimex RP2350-PICO2-XXL on the Pugputer's bus. The
 * wiring is described in ../../README.md, "On the card". */
#ifndef VIDCARD_FW_CONFIG_H
#define VIDCARD_FW_CONFIG_H

/* The system clock: 252 MHz, so that HSTX at half of it (126 MHz) is exactly five times
 * 640x480's 25.2 MHz pixel clock. The core voltage is raised a step for it. */
#define SYS_CLOCK_KHZ 252000
#define CORE_VOLTAGE VREG_VOLTAGE_1_15

/* DVI through HSTX, GPIO 12-19: D2+ D2- CK+ CK- D1+ D1- D0+ D0- (220 ohm each). */
#define PIN_DVI_FIRST 12

/* The Pugputer's bus, through two TXS0108E level shifters (16 channels); the PIO
 * that serves it has its GPIO window at 16-47. */
#define PIN_CS 32    /* /CS: the GAL's select, for $FF80-$FF9F and $FFD8-$FFDB, low only
                        while E or Q is high: its rising edge is when a write's data is
                        taken (the Pugputer's /WR is R/W itself, so it can't time that) */
#define PIN_D0 34    /* D0-D7: 34-41 */
#define PIN_A0 42    /* A0-A4: 42-46 */
#define PIN_SDSEL 47 /* the GAL's second output: high when $FFD8-$FFDB is selected */
#define PIN_RW 33    /* R/W, straight from the CPU: valid with the address */
#define PIN_IRQ 30   /* to the gate of a MOSFET that pulls the bus's /IRQ low: high = asserted */
#define PIN_RESET 29 /* the bus's /RES, through a 100K/200K divider: falls when the Pugputer resets */
#define PIN_BUS_OE 31 /* the level shifters' OE: pulled low (off) until the firmware is ready */
#define BUS_PIO_GPIO_BASE 16

/* The microSD (SPI1, as the board wires it) and the PSRAM's chip select (QMI CS1). */
#define SD_SPI spi1
#define PIN_SD_SCK 10
#define PIN_SD_MOSI 11
#define PIN_SD_MISO 24
#define PIN_SD_CS 9
#define SD_SLOW_HZ 400000     /* while the card starts up */
#define SD_FAST_HZ 25000000   /* afterwards (the most SPI mode allows) */

#define PIN_LED 25

/* Where the PSRAM appears: QMI's second chip select, through the XIP cache. */
#define PSRAM_ADDR 0x11000000u

#endif
