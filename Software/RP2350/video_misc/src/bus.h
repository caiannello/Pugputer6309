/* The Pugputer's bus: the two state machines of bus.pio, their DMA, and the interrupt
 * that hands each access to card_bus_event(). */
#ifndef VIDCARD_FW_BUS_H
#define VIDCARD_FW_BUS_H

/* Sets it all up and turns the level shifters on: from here the card answers the CPU.
 * The register copy must be ready first (card_init). */
void bus_init(void);
/* Takes the accesses again after card_bus_event() asked to stop (a reset). */
void bus_resume(void);

#if VIDCARD_DIAG
#include <stdint.h>
/* Bring-up diagnostics (-DVIDCARD_DIAG=1): every access the card has seen, by register
 * index (0-31 video, 56-59 SD), reported once a second by main.c. */
extern volatile uint32_t diag_reads[64], diag_writes[64], diag_last_event;
extern volatile uint32_t diag_pin_resets, diag_card_resets;
/* Accesses whose index changed between /CS falling and just before it rose: the address
 * not yet settled as /CS fell (a read answered from the wrong register), or already on
 * its way to the next cycle's. */
extern volatile uint32_t diag_index_late;
/* Of those: how often each index bit (0-4 A0-A4, 5 SD-select) differed, how many were
 * reads, how many had the next access's index late, and the first 8 (the event, then the
 * previous access's index). */
/* Accesses whose index as /CS fell differed from the one taken 44 ns later (the one
 * used), and by which bits. */
extern volatile uint32_t diag_fall_diff, diag_fall_bit[6];
extern volatile uint32_t diag_late_bit[6], diag_late_reads, diag_late_next, diag_late_log[8][2], diag_late_logged;
#endif

#endif
