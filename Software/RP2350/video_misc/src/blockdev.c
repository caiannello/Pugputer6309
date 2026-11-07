/* The Pugputer's SD interface, as the emulator has it (simulator/src/pugputer/
 * sdcard_device.cpp), on the board's microSD card:
 *
 *   0-1  SD_LBA: the block number's low 16 bits (high byte first); writing it resets the
 *        cursor. SETHI (command 3) latches it as bits 31-16.
 *   2    SD_DATA: the 512-byte buffer, a byte at a time; the cursor stops at 511.
 *   3    SD_CMDSTA: write a command (1 read the block into the buffer, 2 write the buffer
 *        to the block, 3 SETHI); read the status (bit 0 BUSY, 1 CARD, 2 ERROR).
 *
 * A read takes the card about 0.3 ms; the CPU waits on BUSY meanwhile. A write is taken
 * at once (BUSY doesn't show) and written while the CPU gets on: SD cards may take up to
 * 250 ms over a write, as long as the BIOS waits before it gives up. Only one waits at a
 * time; another write, or a read, waits (BUSY) for it. If it can't be written, the next
 * command fails once, with ERROR. */
#include "blockdev.h"

#include <string.h>

#include "card.h"
#include "config.h"
#include "hardware/gpio.h"
#include "sd.h"

#define CMD_READ 1
#define CMD_WRITE 2
#define CMD_SETHI 3
#define ST_BUSY 0x01
#define ST_CARD 0x02
#define ST_ERROR 0x04
#define TRIES 3

static uint16_t lba, lba_hi, cursor;
static uint8_t buf[512];
static volatile bool card_ok, error, busy;
static volatile uint8_t pending; /* the command the main loop is to do (0: none) */
static uint32_t pending_block;

/* The write being written behind the CPU's back. */
static uint8_t later[512];
static uint32_t later_block;
static volatile bool later_waiting, later_failed;

void blockdev_refresh(void) {
    regcopy[COPY_SD + 0] = (uint8_t)(lba >> 8);
    regcopy[COPY_SD + 1] = (uint8_t)lba;
    regcopy[COPY_SD + 2] = buf[cursor];
    regcopy[COPY_SD + 3] = (uint8_t)((busy ? ST_BUSY : 0) | (card_ok ? ST_CARD : 0) | (error ? ST_ERROR : 0));
}

void blockdev_init(void) {
    busy = true; /* until the card is awake */
    uint32_t s = copy_lock();
    blockdev_refresh();
    copy_unlock(s);
}

void blockdev_start(void) {
    bool ok = sd_init();
    uint32_t s = copy_lock();
    card_ok = ok;
    if (!pending) busy = false; /* (a command already sent waits for blockdev_poll) */
    blockdev_refresh();
    copy_unlock(s);
    gpio_put(PIN_LED, ok);
}

void blockdev_reset(void) {
    uint32_t s = copy_lock();
    lba = lba_hi = cursor = 0;
    memset(buf, 0, sizeof buf);
    blockdev_refresh();
    copy_unlock(s);
}

/* A command from the CPU (in the bus interrupt, with the copy locked). */
static void command(uint8_t cmd) {
    error = false;
    cursor = 0;
    if (cmd == CMD_SETHI) {
        lba_hi = lba;
        return;
    }
    if (cmd != CMD_READ && cmd != CMD_WRITE) return;
    if (later_failed) { /* the last write didn't happen: say so now */
        later_failed = false;
        error = true;
        return;
    }
    uint32_t block = (uint32_t)lba_hi << 16 | lba;
    if (cmd == CMD_WRITE && card_ok && !busy && !later_waiting) {
        memcpy(later, buf, sizeof later); /* taken: written behind */
        later_block = block;
        later_waiting = true;
        return;
    }
    pending = cmd;
    pending_block = block;
    busy = true;
}

void blockdev_access(int reg, int read, uint8_t value) {
    uint32_t s = copy_lock();
    if (read) {
        if (reg == 2 && cursor < 511) ++cursor;
    } else {
        switch (reg) {
        case 0:
            lba = (uint16_t)((lba & 0x00FF) | value << 8);
            cursor = 0;
            break;
        case 1:
            lba = (uint16_t)((lba & 0xFF00) | value);
            cursor = 0;
            break;
        case 2:
            buf[cursor] = value;
            if (cursor < 511) ++cursor;
            break;
        default: command(value); break;
        }
    }
    blockdev_refresh();
    copy_unlock(s);
}

/* The card again, after a failure (it may have been taken out and put back). */
static bool card_again(void) {
    card_ok = sd_init();
    return card_ok;
}

static bool write_later(void) {
    bool ok = false;
    for (int i = 0; i < TRIES && !ok; ++i) ok = (card_ok || card_again()) && sd_write(later_block, later);
    if (!ok) later_failed = true;
    later_waiting = false;
    return ok;
}

bool blockdev_waiting(void) { return pending != 0; }

void blockdev_poll(void) {
    if (!pending) {
        if (later_waiting) {
            gpio_put(PIN_LED, 0);
            write_later();
            gpio_put(PIN_LED, card_ok);
        }
        return;
    }
    gpio_put(PIN_LED, 0);
    bool ok = card_ok || card_again();
    if (ok && later_waiting) ok = write_later(); /* first, in order */
    if (ok && pending == CMD_READ) {
        ok = false; /* (the CPU leaves the buffer alone while BUSY says so) */
        for (int i = 0; i < TRIES && !ok; ++i) ok = (card_ok || card_again()) && sd_read(pending_block, buf);
        if (!ok) memset(buf, 0, sizeof buf);
    } else if (ok) { /* a write: now there's room behind */
        memcpy(later, buf, sizeof later);
        later_block = pending_block;
        later_waiting = true;
    }
    uint32_t s = copy_lock();
    if (!ok) later_failed = false; /* (said now, by this command) */
    error = !ok;
    cursor = 0;
    pending = 0;
    busy = false;
    blockdev_refresh();
    copy_unlock(s);
    gpio_put(PIN_LED, card_ok);
}
