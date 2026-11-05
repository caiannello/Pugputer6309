/* The microSD card in SPI mode (the board wires it so: SPI1, see config.h), as the SD
 * Physical Layer Simplified Specification describes it. */
#include "sd.h"

#include "config.h"
#include "hardware/gpio.h"
#include "hardware/spi.h"
#include "pico/time.h"

static bool block_addressed; /* SDHC/SDXC: addressed by block, not by byte */

static uint8_t xfer(uint8_t out) {
    uint8_t in;
    spi_write_read_blocking(SD_SPI, &out, &in, 1);
    return in;
}

static void deselect(void) {
    gpio_put(PIN_SD_CS, 1);
    xfer(0xFF); /* (the card lets go of MISO on the next clock) */
}

/* Waits until the card stops holding MISO low (busy). */
static bool wait_ready(uint32_t ms) {
    absolute_time_t until = make_timeout_time_ms(ms);
    while (xfer(0xFF) != 0xFF)
        if (time_reached(until)) return false;
    return true;
}

/* A command, with the card selected; returns its R1 response (bit 7 set: none came).
 * The card stays selected, for what follows. */
static uint8_t command(uint8_t cmd, uint32_t arg) {
    gpio_put(PIN_SD_CS, 0);
    if (cmd != 0 && !wait_ready(500)) return 0xFF;
    uint8_t crc = cmd == 0 ? 0x95 : cmd == 8 ? 0x87 : 0x01; /* (the only ones checked) */
    uint8_t frame[6] = {(uint8_t)(0x40 | cmd), (uint8_t)(arg >> 24), (uint8_t)(arg >> 16), (uint8_t)(arg >> 8),
                        (uint8_t)arg, crc};
    spi_write_blocking(SD_SPI, frame, 6);
    uint8_t r1 = 0xFF;
    for (int i = 0; i < 10 && (r1 & 0x80); ++i) r1 = xfer(0xFF);
    return r1;
}

static uint8_t app_command(uint8_t cmd, uint32_t arg) {
    command(55, 0);
    deselect();
    return command(cmd, arg);
}

bool sd_init(void) {
    spi_init(SD_SPI, SD_SLOW_HZ);
    gpio_set_function(PIN_SD_SCK, GPIO_FUNC_SPI);
    gpio_set_function(PIN_SD_MOSI, GPIO_FUNC_SPI);
    gpio_set_function(PIN_SD_MISO, GPIO_FUNC_SPI);
    gpio_pull_up(PIN_SD_MISO);
    gpio_init(PIN_SD_CS);
    gpio_put(PIN_SD_CS, 1);
    gpio_set_dir(PIN_SD_CS, GPIO_OUT);

    /* At least 74 clocks with the card deselected, then CMD0: into SPI mode, idle. */
    for (int i = 0; i < 10; ++i) xfer(0xFF);
    uint8_t r1 = 0xFF;
    for (int i = 0; i < 10 && r1 != 0x01; ++i) {
        r1 = command(0, 0);
        deselect();
    }
    if (r1 != 0x01) return false;

    /* CMD8: a version 2 card echoes the check pattern (and may be SDHC). */
    bool v2 = false;
    r1 = command(8, 0x1AA);
    if (r1 == 0x01) {
        uint8_t r7[4];
        for (int i = 0; i < 4; ++i) r7[i] = xfer(0xFF);
        if ((r7[2] & 0x0F) != 0x01 || r7[3] != 0xAA) {
            deselect();
            return false; /* (it can't run at 3.3 V) */
        }
        v2 = true;
    }
    deselect();

    /* ACMD41 until the card has finished starting up (HCS: we can take SDHC). */
    absolute_time_t until = make_timeout_time_ms(1000);
    do {
        r1 = app_command(41, v2 ? 0x40000000u : 0);
        deselect();
        if (time_reached(until)) return false;
    } while (r1 != 0x00);

    block_addressed = false;
    if (v2) { /* CMD58: the OCR's CCS bit says how the card is addressed */
        if (command(58, 0) != 0x00) {
            deselect();
            return false;
        }
        uint8_t ocr[4];
        for (int i = 0; i < 4; ++i) ocr[i] = xfer(0xFF);
        deselect();
        block_addressed = (ocr[0] & 0x40) != 0;
    }
    if (!block_addressed) { /* CMD16: 512-byte blocks (SDSC) */
        r1 = command(16, 512);
        deselect();
        if (r1 != 0x00) return false;
    }
    spi_set_baudrate(SD_SPI, SD_FAST_HZ);
    return true;
}

bool sd_read(uint32_t block, uint8_t *buf) {
    if (command(17, block_addressed ? block : block * 512) != 0x00) {
        deselect();
        return false;
    }
    absolute_time_t until = make_timeout_time_ms(200);
    uint8_t token;
    while ((token = xfer(0xFF)) == 0xFF)
        if (time_reached(until)) break;
    if (token != 0xFE) { /* the data token, or an error token */
        deselect();
        return false;
    }
    spi_read_blocking(SD_SPI, 0xFF, buf, 512);
    xfer(0xFF); /* the CRC (not checked) */
    xfer(0xFF);
    deselect();
    return true;
}

bool sd_write(uint32_t block, const uint8_t *buf) {
    if (command(24, block_addressed ? block : block * 512) != 0x00) {
        deselect();
        return false;
    }
    xfer(0xFF);
    xfer(0xFE); /* the data token */
    spi_write_blocking(SD_SPI, buf, 512);
    xfer(0xFF); /* a CRC (not checked in SPI mode) */
    xfer(0xFF);
    uint8_t response = xfer(0xFF);
    bool ok = (response & 0x1F) == 0x05 && wait_ready(500); /* accepted, then written */
    deselect();
    return ok;
}
