/* The Pugputer's bus (bus.pio): reads answered from the register copy by DMA, every
 * access logged into a ring by DMA, and core 0's interrupt applying them in order. */
#include "bus.h"

#include "bus.pio.h"
#include "card.h"
#include "config.h"
#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "hardware/pio.h"
#include "hardware/timer.h"
#include "pico/time.h"

static const PIO pio = pio0;
static uint sm_read, sm_events;
static uint dma_index, dma_byte, dma_events;

/* The accesses, as bus_events reports them: a ring the DMA writes round and round. 4096
 * of them: room for the CPU's fastest (TFM, one every 840 ns) for over 3 ms, while a reset
 * runs or a long interrupt holds core 0 up. */
#define EVENTS_LOG2 14
#define EVENTS_COUNT ((1u << EVENTS_LOG2) / 4)
static uint32_t __attribute__((aligned(1u << EVENTS_LOG2))) events[EVENTS_COUNT];
static uint32_t events_next; /* the next one to take */
static volatile bool paused;
/* While the video card's accesses wait (paused), the SD interface's are taken anyway: it
 * is another device, and the CPU may be waiting on it (DOS, as a program quits). Each is
 * marked as it is taken, so it isn't taken again. */
#define EV_TAKEN 0x80000000u
static uint32_t sd_next; /* the next one to look at, while paused */

#if VIDCARD_DIAG
volatile uint32_t diag_reads[64], diag_writes[64], diag_last_event;
volatile uint32_t diag_pin_resets, diag_card_resets, diag_index_late;
volatile uint32_t diag_late_bit[6], diag_late_reads, diag_late_next, diag_late_log[8][2], diag_late_logged;
volatile uint32_t diag_fall_diff, diag_fall_bit[6];
static uint32_t diag_prev_index, diag_pending = 0xFF; /* (the last one's late index, if it differed) */
#endif

/* The event the DMA will write next. */
static uint32_t events_written(void) { return (dma_hw->ch[dma_events].write_addr - (uintptr_t)events) / 4; }

static void diag_event(uint32_t e) {
#if VIDCARD_DIAG
    if (EV_READ(e)) ++diag_reads[EV_INDEX(e)];
    else ++diag_writes[EV_INDEX(e)];
    diag_last_event = e;
    if (EV_FALL_INDEX(e) != EV_INDEX(e)) { /* (what taking it at once would have got) */
        uint32_t diff = EV_FALL_INDEX(e) ^ EV_INDEX(e);
        ++diag_fall_diff;
        for (int b = 0; b < 6; ++b)
            if (diff & (1u << b)) ++diag_fall_bit[b];
    }
    if (diag_pending == EV_INDEX(e)) ++diag_late_next;
    diag_pending = 0xFF;
    if (EV_LATE_INDEX(e) != EV_INDEX(e)) {
        /* Which bits, on what, and (with the next one) whether the late index was the
         * next access's. */
        uint32_t diff = EV_LATE_INDEX(e) ^ EV_INDEX(e);
        ++diag_index_late;
        for (int b = 0; b < 6; ++b)
            if (diff & (1u << b)) ++diag_late_bit[b];
        if (EV_READ(e)) ++diag_late_reads;
        diag_pending = EV_LATE_INDEX(e);
        if (diag_late_logged < 8) {
            diag_late_log[diag_late_logged][0] = e;
            diag_late_log[diag_late_logged][1] = diag_prev_index;
            ++diag_late_logged;
        }
    }
    diag_prev_index = EV_INDEX(e);
#else
    (void)e;
#endif
}

static void __isr bus_isr(void) {
    pio_interrupt_clear(pio, 0);
    while (!paused && events_next != events_written()) {
        uint32_t e = events[events_next];
        events_next = (events_next + 1) & (EVENTS_COUNT - 1);
        if (e & EV_TAKEN) continue;
        if (!card_bus_event(e)) {
            paused = true;
            sd_next = events_next;
        }
        diag_event(e); /* (after: the copy first) */
    }
    if (paused) {
        while (sd_next != events_written()) {
            uint32_t e = events[sd_next];
            if ((EV_INDEX(e) & 0x20) && !(e & EV_TAKEN)) {
                card_bus_event(e);
                diag_event(e);
                events[sd_next] = e | EV_TAKEN;
            }
            sd_next = (sd_next + 1) & (EVENTS_COUNT - 1);
        }
    }
}

void bus_resume(void) {
    paused = false;
    irq_set_pending(PIO0_IRQ_0); /* (the ones that waited) */
}

static void bus_pin(uint pin) {
    pio_gpio_init(pio, pin);
    gpio_disable_pulls(pin); /* (the TXS0108E's one-shots don't want them) */
}

void bus_init(void) {
    pio_set_gpio_base(pio, BUS_PIO_GPIO_BASE);
    uint at_read = pio_add_program(pio, &bus_read_program);
    uint at_events = pio_add_program(pio, &bus_events_program);
    sm_read = (uint)pio_claim_unused_sm(pio, true);
    sm_events = (uint)pio_claim_unused_sm(pio, true);

    for (uint p = PIN_D0; p < PIN_D0 + 8; ++p) bus_pin(p);
    for (uint p = PIN_A0; p < PIN_A0 + 5; ++p) bus_pin(p);
    bus_pin(PIN_SDSEL);
    bus_pin(PIN_CS);
    bus_pin(PIN_RW);

    /* bus_read: the index from A0 (6 pins), the byte out on D0-D7. */
    pio_sm_config c = bus_read_program_get_default_config(at_read);
    sm_config_set_in_pins(&c, PIN_A0);
    sm_config_set_out_pins(&c, PIN_D0, 8);
    sm_config_set_jmp_pin(&c, PIN_RW);
    sm_config_set_in_shift(&c, false, false, 32);
    sm_config_set_out_shift(&c, true, false, 32);
    pio_sm_init(pio, sm_read, at_read, &c);
    pio_sm_set_consecutive_pindirs(pio, sm_read, PIN_D0, 8, false);
    /* X = the register copy's address / 64 */
    pio_sm_put(pio, sm_read, (uint32_t)(uintptr_t)regcopy >> 6);
    pio_sm_exec(pio, sm_read, pio_encode_pull(false, true));
    pio_sm_exec(pio, sm_read, pio_encode_mov(pio_x, pio_osr));

    /* bus_events: R/W, data, index and SD-select from R/W (15 pins); waits on /CS. */
    c = bus_events_program_get_default_config(at_events);
    sm_config_set_in_pins(&c, PIN_RW);
    sm_config_set_jmp_pin(&c, PIN_CS);
    sm_config_set_in_shift(&c, false, false, 32);
    sm_config_set_out_shift(&c, true, false, 32);
    pio_sm_init(pio, sm_events, at_events, &c);
    /* Both at BUS_PIO_KHZ, whatever the system clock (the delays in bus.pio are counted
     * in its clocks; a fractional divider evens out within a system clock, 3 ns). */
    pio_sm_set_clkdiv(pio, sm_read, (float)SYS_CLOCK_KHZ / BUS_PIO_KHZ);
    pio_sm_set_clkdiv(pio, sm_events, (float)SYS_CLOCK_KHZ / BUS_PIO_KHZ);

    /* A read: the address bus_read pushes is written into dma_byte's read address, which
     * starts it: one byte from the copy into bus_read's TX FIFO. */
    dma_index = (uint)dma_claim_unused_channel(true);
    dma_byte = (uint)dma_claim_unused_channel(true);
    dma_channel_config d = dma_channel_get_default_config(dma_index);
    channel_config_set_transfer_data_size(&d, DMA_SIZE_32);
    channel_config_set_read_increment(&d, false);
    channel_config_set_write_increment(&d, false);
    channel_config_set_dreq(&d, pio_get_dreq(pio, sm_read, false));
    channel_config_set_high_priority(&d, true);
    dma_channel_configure(dma_index, &d, &dma_hw->ch[dma_byte].al3_read_addr_trig, &pio->rxf[sm_read],
                          dma_encode_endless_transfer_count(), false);
    d = dma_channel_get_default_config(dma_byte);
    channel_config_set_transfer_data_size(&d, DMA_SIZE_8);
    channel_config_set_read_increment(&d, false);
    channel_config_set_write_increment(&d, false);
    channel_config_set_high_priority(&d, true);
    dma_channel_configure(dma_byte, &d, &pio->txf[sm_read], regcopy, 1, false);

    /* Every access into the ring. */
    dma_events = (uint)dma_claim_unused_channel(true);
    d = dma_channel_get_default_config(dma_events);
    channel_config_set_transfer_data_size(&d, DMA_SIZE_32);
    channel_config_set_read_increment(&d, false);
    channel_config_set_write_increment(&d, true);
    channel_config_set_ring(&d, true, EVENTS_LOG2);
    channel_config_set_dreq(&d, pio_get_dreq(pio, sm_events, false));
    channel_config_set_high_priority(&d, true);
    dma_channel_configure(dma_events, &d, events, &pio->rxf[sm_events], dma_encode_endless_transfer_count(),
                          false);

    pio_set_irq0_source_enabled(pio, pis_interrupt0, true);
    irq_set_exclusive_handler(PIO0_IRQ_0, bus_isr);
    irq_set_priority(PIO0_IRQ_0, 0); /* (the highest) */
    irq_set_enabled(PIO0_IRQ_0, true);

    dma_channel_start(dma_index);
    dma_channel_start(dma_events);
#if BUS_DIAG == 1
    /* Diagnostic: everything runs, but the shifters stay off (the card stays off the bus). */
    pio_enable_sm_mask_in_sync(pio, (1u << sm_read) | (1u << sm_events));
    return;
#endif
    /* The level shifters on: the card is on the bus. Until now its side of them has been
     * floating, so the state machines start only once they're on, and between bus
     * cycles (/CS high, seen twice): their first access is then a whole one. (Started
     * with /CS floating, they took a stray write now and then at power-up.) */
    gpio_init(PIN_BUS_OE);
    gpio_set_dir(PIN_BUS_OE, GPIO_OUT);
    gpio_put(PIN_BUS_OE, 1);
    sleep_us(10);
    for (uint32_t t0 = time_us_32(); time_us_32() - t0 < 100000;) /* (not for ever: 0.1 s) */
        if (gpio_get(PIN_CS) && gpio_get(PIN_CS)) break;
#if BUS_DIAG == 2
    /* Diagnostic: listen only. The shifters go on, but bus_read never runs, so the card
     * never drives D0-D7. */
    pio_enable_sm_mask_in_sync(pio, 1u << sm_events);
#else
    pio_enable_sm_mask_in_sync(pio, (1u << sm_read) | (1u << sm_events));
#endif
}
