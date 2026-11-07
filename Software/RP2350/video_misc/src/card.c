/* The video card between the bus and the commands: the register copy the bus PIO reads
 * from, the bus accesses applied in order, and the queue of drawing commands.
 *
 * Who does what:
 * - core 0's bus interrupt (card_bus_event): every register access, as soon as it is
 *   made. Reads were already answered from the copy; here their side effects happen (a
 *   data port steps on, a key is taken). Writes are applied, except drawing commands,
 *   which go into a queue. A reset is done there too, all but the video memory's 256KB
 *   (see below).
 * - core 0's main loop (card_poll): the commands, a share at a time, and the video memory
 *   after a reset.
 * - core 1 (card_begin_line): the beam, a line at a time: LINE, FRAME, the interrupt
 *   flags, vertical blank.
 * Whoever changes something a read would see refreshes its byte in the copy at once.
 *
 * A reset has to be over before the CPU's next access, a microsecond or two later: from
 * then on, its reads are answered from the copy, which must already be the reset card's.
 * (A program resets the card, then reads the font through a data port; or quits, and DOS
 * reads the SD card.) So the interrupt resets the registers and the settings, and marks
 * every 64-byte block of the video memory as still to be put back; the main loop puts
 * them back, a few at a time, and a block a data port reaches first is put back then.
 * The drawing commands wait until it's done. (The picture shows what was there for the
 * millisecond that takes.) */
#include "card.h"

#include <string.h>

#include "blockdev.h"
#include "bus.h"
#include "config.h"
#include "hardware/gpio.h"
#include "hardware/sync.h"

vc_card card;
uint8_t __attribute__((aligned(64))) regcopy[64];

/* The drawing commands, as bytes: the bus interrupt adds, the main loop takes. The
 * counters run free; their difference is what's waiting. */
#define CMDQ_SIZE 65536 /* (a program may send a page's worth in one go, without looking at
                         * STATUS: VIDGFX sends over 5KB, faster than the card can draw it) */
#define CMDQ_FULL (CMDQ_SIZE - 64) /* STATUS says "queue full" from here */
static uint8_t cmdq[CMDQ_SIZE];
static volatile uint32_t cmdq_in, cmdq_out;
static volatile bool reset_waiting, system_reset;
static volatile bool in_command; /* the main loop is running a command */

/* The video memory's blocks still to be put back after a reset. */
#define BLOCK_LOG2 6
#define BLOCKS (VC_VRAM_SIZE >> BLOCK_LOG2)
static uint32_t stale[BLOCKS / 32];
static uint32_t clear_next; /* the main loop's next one */
static volatile bool clearing;

static spin_lock_t *lock;

#if VIDCARD_DIAG
volatile uint32_t diag_stale_reads, diag_stale_clearing, diag_cmd_lost;
#endif

/* With interrupts off only once it's ours: spin_lock_blocking waits with them off, and
 * while core 1 has it (once a line, for the beam) that would hold the bus interrupt up
 * past a data port's next read (after a reset, when the main loop takes it again and
 * again: 75 of VIDTEXT's 4096 font reads went stale). */
uint32_t copy_lock(void) {
    for (;;) {
        uint32_t s = save_and_disable_interrupts();
        if (spin_try_lock_unsafe(lock)) return s;
        restore_interrupts(s);
    }
}
void copy_unlock(uint32_t saved) { spin_unlock(lock, saved); }

static uint32_t cmdq_waiting(void) { return cmdq_in - cmdq_out; }

/* The block of video memory address a is in, as the reset left it (with the copy locked). */
static void block_ready(uint32_t a) {
    uint32_t b = a >> BLOCK_LOG2, bit = 1u << (b & 31);
    if (stale[b >> 5] & bit) {
        stale[b >> 5] &= ~bit;
        vc_reset_vram(&card, b << BLOCK_LOG2, 1u << BLOCK_LOG2);
    }
}

/* Data port p's byte, about to be read or written. */
static void port_ready(int p) {
    uint32_t a = card.addr[p] & 0xFFFFFF;
    if (clearing && a < VC_VRAM_SIZE) block_ready(a);
}

/* A read of data port p (in the bus interrupt). The CPU may read it again a microsecond
 * later (LDA DATA0 / ORA DATA0), and that read is answered from the copy: so the byte it
 * gets goes there first, before anything else. Without the lock: only core 0 touches the
 * ports and the copy's port bytes, and the main loop's locked parts hold this off.
 * got: the byte the CPU was given (the diagnostics check it). */
static void data_read(int p, uint8_t got) {
    uint32_t was = card.addr[p], inc = (uint32_t)(int16_t)card.inc[p], a = (was + inc) & 0xFFFFFF;
    bool clr = clearing;
    card.addr[p] = a; /* (as vc_read steps it) */
    if (clr && a < VC_VRAM_SIZE) block_ready(a);
    regcopy[p ? VC_DATA1 : VC_DATA0] = a < VC_VRAM_SIZE ? card.vram[a] : vc_peek(&card, a);
    int r = p ? VC_ADDR1_H : VC_ADDR0_H; /* then its address (its step is the same) */
    regcopy[r] = (uint8_t)(a >> 16);
    regcopy[r + 1] = (uint8_t)(a >> 8);
    regcopy[r + 2] = (uint8_t)a;
    if (clr) { /* (and the block of the byte after, ready before it's wanted) */
        uint32_t n = (a + inc) & 0xFFFFFF;
        if (n < VC_VRAM_SIZE) block_ready(n);
    }
#if VIDCARD_DIAG
    if (got != vc_peek(&card, was)) { /* (the copy wasn't ready in time) */
        ++diag_stale_reads;
        if (clr) ++diag_stale_clearing;
    }
#else
    (void)got;
#endif
}

/* A write to data port p (in the bus interrupt): as quick as a read, the other way round.
 * A TFM writes one every 840 ns, and while the interrupt takes them core 0 can't draw: a
 * line it had begun waited out a whole sprite table (2KB, 1.8 ms) and went out late. So
 * without the lock (as data_read), only the copy's bytes that the write changes: the
 * port's byte and address, and the other port's byte if it is where this one wrote. */
static void data_write(int p, uint8_t v) {
    uint32_t a = card.addr[p], inc = (uint32_t)(int16_t)card.inc[p], n = (a + inc) & 0xFFFFFF;
    bool clr = clearing;
    if (clr && a < VC_VRAM_SIZE) block_ready(a);
    vc_poke(&card, a, v); /* (as vc_write does, then steps) */
    card.addr[p] = n;
    if (clr && n < VC_VRAM_SIZE) block_ready(n);
    regcopy[p ? VC_DATA1 : VC_DATA0] = n < VC_VRAM_SIZE ? card.vram[n] : vc_peek(&card, n);
    int r = p ? VC_ADDR1_H : VC_ADDR0_H;
    regcopy[r] = (uint8_t)(n >> 16);
    regcopy[r + 1] = (uint8_t)(n >> 8);
    regcopy[r + 2] = (uint8_t)n;
    if ((card.addr[!p] & 0xFFFFFF) == a) regcopy[p ? VC_DATA0 : VC_DATA1] = vc_peek(&card, a);
}

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
    case VC_DATA0: port_ready(0); return vc_peek(&card, card.addr[0]);
    case VC_DATA1: port_ready(1); return vc_peek(&card, card.addr[1]);
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

/* A reset, all but the video memory, which is marked to be put back (with the copy
 * locked). The commands sent before it are dropped: it would undo them anyway. */
static void reset_now(void) {
#if VIDCARD_DIAG
    ++diag_card_resets; /* (each one clears the screen) */
#endif
    cmdq_out = cmdq_in;
    vc_reset_state(&card);
    memset(stale, 0xFF, sizeof stale);
    clear_next = 0;
    clearing = true;
    refresh_all();
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
    if (EV_READ(e) && (r == VC_DATA0 || r == VC_DATA1)) { /* (the one in a hurry) */
        data_read(r == VC_DATA1, v);
        return true;
    }
    if (EV_READ(e) && r != VC_MOUSE_X_H && r != VC_MOUSE_WHEEL && r != VC_KEY)
        return true; /* (a read without side effects, such as a program polling ISR) */
    if (!EV_READ(e) && (r == VC_DATA0 || r == VC_DATA1)) { /* (the other one in a hurry) */
        data_write(r == VC_DATA1, v);
        return true;
    }
    uint32_t s = copy_lock();
    if (EV_READ(e)) {
        switch (r) {
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
#if VIDCARD_DIAG
        else ++diag_cmd_lost;
#endif
        refresh(VC_STATUS);
    } else if (r == VC_CTRL && (v & 0x80)) {
        if (in_command || reset_waiting) {
            /* A command is being drawn (or the Pugputer's reset is waiting): the main
             * loop resets the card after that. Until then the video card's accesses
             * that follow wait in the bus's ring, so none lands before it (the SD
             * card's go on: bus.c). */
            reset_waiting = true;
            copy_unlock(s);
            return false;
        }
        reset_now();
    } else {
        vc_write(&card, (uint8_t)r, v); /* (the data ports: data_write) */
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

bool card_waiting(void) { return reset_waiting || clearing; }

void card_reset(void) {
    uint32_t s = copy_lock();
    reset_now();
    copy_unlock(s);
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
        uint32_t s = copy_lock();
        reset_now();
        copy_unlock(s);
        reset_waiting = false;
        bus_resume();
    }
    if (clearing) {
        /* The video memory, a block at a time: built aside, then copied in with the copy
         * locked, which holds the bus interrupt up, so only for 16 words (it has well
         * under a microsecond to answer a data port's next read). One the interrupt
         * readied first is left alone (the CPU may have written there since). The
         * commands wait for all of it (they don't look whether a block is ready). */
        for (int k = 0; k < 16 && clear_next < BLOCKS; ++k, ++clear_next) {
            uint32_t b = clear_next, bit = 1u << (b & 31), at = b << BLOCK_LOG2;
            static uint32_t fresh[(1u << BLOCK_LOG2) / 4];
            if (!(stale[b >> 5] & bit)) continue;
            vc_reset_bytes(at, (uint8_t *)fresh, sizeof fresh);
            uint32_t s = copy_lock();
            if (stale[b >> 5] & bit) {
                uint32_t *d = (uint32_t *)(card.vram + at); /* (blocks are word-aligned) */
                for (int i = 0; i < (int)(sizeof fresh / 4); ++i) d[i] = fresh[i];
                stale[b >> 5] &= ~bit;
                __atomic_fetch_add(&card.spr_gen, 1u, __ATOMIC_SEQ_CST); /* (the sprite table may be in it: vc_palette) */
            }
            copy_unlock(s);
        }
        if (clear_next == BLOCKS) clearing = false;
        return;
    }
    /* A share of the commands (any one runs to its end), then the rest of the loop. */
    int n = 0;
    while (n < 256 && !reset_waiting) {
        in_command = true; /* (before it looks: a reset now waits for this one) */
        if (!cmdq_waiting() || clearing) { /* (or one came just before) */
            in_command = false;
            break;
        }
        vc_write(&card, VC_CMD, cmdq[cmdq_out & (CMDQ_SIZE - 1)]);
        ++cmdq_out; /* (after: STATUS says busy while one runs) */
        in_command = false;
        ++n;
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
