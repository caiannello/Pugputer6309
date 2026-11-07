/* The USB host: keyboards and mice, as the card's input (usbhost.c). */
#ifndef VIDCARD_FW_USBHOST_H
#define VIDCARD_FW_USBHOST_H

#include <stdint.h>

/* On core 0: the host started (clk_usb must already be 48 MHz). */
void usbhost_init(void);
/* Core 0's main loop, every time round: what has come in. */
void usbhost_poll(void);

#if VIDCARD_DIAG
/* Devices attached now (a hub counts), and the key events and mouse reports so far. */
extern volatile uint32_t diag_usb_devices, diag_usb_keys, diag_usb_mouse;
#endif

#endif
