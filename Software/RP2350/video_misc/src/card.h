/* The card's state between the bus, the drawing commands and the picture. */
#ifndef VIDCARD_FW_CARD_H
#define VIDCARD_FW_CARD_H

#include <stdbool.h>
#include <stdint.h>

#include "vc.h"

/* The video card (vidcard/core), and its PSRAM if there is one. */
extern vc_card card;

/* The register copy the bus PIO answers reads from: 64 bytes, 64-byte aligned. Bytes
 * 0-31 are the video card's registers ($FF80-$FF9F); 32-63 are the SD-select half,
 * where $FFD8-$FFDB land at 56-59 (A0-A4 = $18-$1B). Each holds what a read would
 * return now; it is kept up to date as things change. */
#define COPY_SD 56
extern uint8_t regcopy[64];

/* A bus access, as bus_events reports it (see bus.pio). */
#define EV_DATA(e) ((uint8_t)(e))
#define EV_INDEX(e) (((e) >> 14) & 0x3F)
#define EV_READ(e) (((e) >> 20) & 1)
/* (diagnostics) the index just before /CS rose, and as it fell */
#define EV_LATE_INDEX(e) (((e) >> 8) & 0x3F)
#define EV_FALL_INDEX(e) (((e) >> 21) & 0x3F)

void card_init(void);
/* Core 0's bus interrupt: one access, in the order the CPU made them. Returns false to
 * stop taking them for now (a reset is waiting for the main loop). */
bool card_bus_event(uint32_t e);
/* Core 0's main loop: a reset if one is waiting, then a share of the queued drawing
 * commands. */
void card_poll(void);
/* The Pugputer is being reset (/RES fell): the card and the SD interface are put back as
 * they start, as the emulator does, by the main loop. Safe from an interrupt. */
void card_system_reset(void);
/* Core 1: the beam has reached `line` (0-524). */
void card_begin_line(uint16_t line);

/* Short critical sections around the register copy, from either core. */
uint32_t copy_lock(void);
void copy_unlock(uint32_t saved);

#endif
