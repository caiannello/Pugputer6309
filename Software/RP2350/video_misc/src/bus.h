/* The Pugputer's bus: the two state machines of bus.pio, their DMA, and the interrupt
 * that hands each access to card_bus_event(). */
#ifndef VIDCARD_FW_BUS_H
#define VIDCARD_FW_BUS_H

/* Sets it all up and turns the level shifters on: from here the card answers the CPU.
 * The register copy must be ready first (card_init). */
void bus_init(void);
/* Takes the accesses again after card_bus_event() asked to stop (a reset). */
void bus_resume(void);

#endif
