/* The video card between the bus and the commands: the register copy the bus PIO reads
 * from, the bus accesses applied in order, and the queue of drawing commands.
 *
 * Who does what:
 * - core 0's bus interrupt (card_bus_event): every register access, as soon as it is
 *   made. Reads were already answered from the copy; here their side effects happen (a
 *   data port steps on, a key is taken). Writes are applied, except drawing commands,
 *   which go into a queue, and a reset, which waits for the main loop.
 * - core 0's main loop (card_poll): the commands, a share at a time, and resets.
 * - core 1 (card_begin_line): the beam, a line at a time: LINE, FRAME, the interrupt
 *   flags, vertical blank.
 * Whoever changes something a read would see refreshes its byte in the copy at once. */
#include "card.h"

#include "blockdev.h"
#include "bus.h"
#include "config.h"
#include "hardware/gpio.h"
#include "hardware/sync.h"

vc_card card;
uint8_t __attribute__((aligned(64))) regcopy[64];

/* The drawing commands, as bytes: the bus interrupt adds, the main loop takes. The
 * counters run free; their difference is what's waiting. */
#define CMDQ_SIZE 4096
#define CMDQ_FULL (CMDQ_SIZE - 64) /* STATUS says "queue full" from here */
static uint8_t cmdq[CMDQ_SIZE];
static volatile uint32_t cmdq_in, cmdq_out;
static volatile bool reset_waiting, system_reset;

static spin_lock_t *lock;

uint32_t copy_lock(void) { return spin_lock_blocking(lock); }
void copy_unlock(uint32_t saved) { spin_unlock(lock, saved); }

static uint32_t cmdq_waiting(void) { return cmdq_in - cmdq_out; }

/* STATUS: the core's (vertical blank, a command half sent, a key waiting), and busy
 * while commands are waiting or running, full when the queue nearly is. */
static uint8_t status_now(void) {
    uint8_t s = vc_read(&card, VC_STATUS);
    uint32_t n = cmdq_waiting();
    if (n) s |= VC_STATUS_BUSY;
    if (n >= CMDQ_FULL) s |= VC_STATUS_FULL;
    return s;
}

/* What a read of register r would return now, without its side effects. */
static uint8_t peek_reg(int r) {
    switch (r) {
    case VC_DATA0: return vc_peek(&card, card.addr[0]);
    case VC_DATA1: return vc_peek(&card, card.addr[1]);
    case VC_STATUS: return status_now();
    /* The mouse as it is now: the copy can't take a snapshot when X's high byte is read,
     * but it changes all four bytes together, which does the same for an LDD. */
    case VC_MOUSE_X_H: return (uint8_t)(card.mouse_x >> 8);
    case VC_MOUSE_X_L: return (uint8_t)card.mouse_x;
    case VC_MOUSE_Y_H: return (uint8_t)(card.mouse_y >> 8);
    case VC_MOUSE_Y_L: return (uint8_t)card.mouse_y;
    case VC_MOUSE_WHEEL: return (uint8_t)card.wheel;
    case VC_KEY: return card.keyq_len ? card.keyq[card.keyq_head][0] : 0;
    default: return vc_read(&card, (uint8_t)r); /* (the rest have no side effects) */
    }
}

static void refresh(int r) { regcopy[r] = peek_reg(r); }

/* A data port's registers: its address, step and data. */
static void refresh_port(int p) {
    int base = p ? VC_ADDR1_H : VC_ADDR0_H;
    for (int r = base; r < base + 6; ++r) refresh(r);
}

/* The registers that a command, a key or the interrupt flags can change. */
static void refresh_state(void) {
    refresh(VC_DATA0);
    refresh(VC_DATA1);
    refresh(VC_STATUS);
    refresh(VC_ISR);
    refresh(VC_KEY);
    refresh(VC_KEY_CHAR);
    gpio_put(PIN_IRQ, vc_irq(&card));
}

static void refresh_all(void) {
    for (int r = 0; r < VC_REGS; ++r) refresh(r);
    for (int r = VC_REGS; r < COPY_SD; ++r) regcopy[r] = 0xFF; /* nothing there */
    blockdev_refresh();
    gpio_put(PIN_IRQ, vc_irq(&card));
}

void card_init(void) {
    lock = spin_lock_instance((uint)spin_lock_claim_unused(true));
    gpio_init(PIN_IRQ);
    gpio_put(PIN_IRQ, 0);
    gpio_set_dir(PIN_IRQ, GPIO_OUT);
    vc_reset(&card);
    uint32_t s = copy_lock();
    refresh_all();
    copy_unlock(s);
}

bool card_bus_event(uint32_t e) {
    int r = EV_INDEX(e);
    uint8_t v = EV_DATA(e);
    if (r & 0x20) { /* $FFD8-$FFDB: the SD card (A0-A1) */
        blockdev_access(r & 3, EV_READ(e), v);
        return true;
    }
    uint32_t s = copy_lock();
    if (EV_READ(e)) {
        switch (r) {
        case VC_DATA0:
        case VC_DATA1:
            vc_read(&card, (uint8_t)r); /* the port steps on */
            refresh_port(r == VC_DATA1);
            break;
        case VC_MOUSE_X_H:  /* the snapshot */
        case VC_MOUSE_WHEEL: /* back to 0 */
        case VC_KEY:        /* the event taken: its character, and the next */
            vc_read(&card, (uint8_t)r);
            refresh_state();
            refresh(VC_MOUSE_WHEEL);
            break;
        default: break; /* no side effects */
        }
    } else if (r == VC_CMD) {
        if (cmdq_waiting() < CMDQ_SIZE) { /* (when full, the byte is lost: STATUS said so) */
            cmdq[cmdq_in & (CMDQ_SIZE - 1)] = v;
            ++cmdq_in;
        }
        refresh(VC_STATUS);
    } else if (r == VC_CTRL && (v & 0x80)) {
        /* A reset: the main loop does it, after the command it may be running; until then
         * the accesses that follow wait in the bus's ring, so none lands before it. */
        reset_waiting = true;
        copy_unlock(s);
        return false;
    } else {
        vc_write(&card, (uint8_t)r, v);
        if (r < VC_CTRL) {
            refresh_port(r >= VC_ADDR1_H);
            refresh(r >= VC_ADDR1_H ? VC_DATA0 : VC_DATA1); /* (it may have written there) */
        } else {
            refresh(r);
            refresh_state();
        }
    }
    copy_unlock(s);
    return true;
}

void card_system_reset(void) {
    system_reset = true;
    reset_waiting = true;
}

void card_poll(void) {
    if (reset_waiting) {
        if (system_reset) {
            system_reset = false;
            blockdev_reset();
        }
        cmdq_out = cmdq_in; /* commands sent before the reset: the reset clears them anyway */
        vc_reset(&card);
        uint32_t s = copy_lock();
        refresh_all();
        copy_unlock(s);
        reset_waiting = false;
        bus_resume();
    }
    /* A share of the commands (any one runs to its end), then the rest of the loop. */
    int n = 0;
    while (cmdq_waiting() && n++ < 256) {
        vc_write(&card, VC_CMD, cmdq[cmdq_out & (CMDQ_SIZE - 1)]);
        ++cmdq_out; /* (after: STATUS says busy while one runs) */
    }
    if (n) {
        uint32_t s = copy_lock();
        refresh_state();
        copy_unlock(s);
    }
}

void card_begin_line(uint16_t line) {
    uint32_t s = copy_lock();
    vc_begin_line(&card, line);
    regcopy[VC_LINE_H] = (uint8_t)(line >> 8);
    regcopy[VC_LINE_L] = (uint8_t)line;
    regcopy[VC_FRAME] = card.frame;
    regcopy[VC_STATUS] = status_now();
    regcopy[VC_ISR] = card.isr;
    gpio_put(PIN_IRQ, vc_irq(&card));
    copy_unlock(s);
}
