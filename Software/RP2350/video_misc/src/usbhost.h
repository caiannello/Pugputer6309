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
/* The last mouse to mount: its IDs, protocol, and report descriptor (the first bytes); its
 * reports' lengths, every bit seen set in each byte, and the last few reports. */
#define DIAG_MOUSE_DESC 128
#define DIAG_MOUSE_LOG 8
extern uint8_t diag_mouse_desc[DIAG_MOUSE_DESC];
extern uint16_t diag_mouse_desc_len, diag_mouse_vid, diag_mouse_pid;
extern uint8_t diag_mouse_proto, diag_mouse_len_min, diag_mouse_len_max, diag_mouse_seen[8];
extern uint8_t diag_mouse_log[DIAG_MOUSE_LOG][9]; /* length, then up to 8 bytes */
extern uint32_t diag_mouse_logged;
#endif

#endif
