/* The USB host: keyboards and mice, as the card's input (usbhost.c). */
#ifndef VIDCARD_FW_USBHOST_H
#define VIDCARD_FW_USBHOST_H

#include <stdbool.h>
#include <stdint.h>

/* On core 0: the host started (clk_usb must already be 48 MHz). */
void usbhost_init(void);
/* Core 0's main loop, every time round: what has come in. */
void usbhost_poll(void);

#if VIDCARD_DIAG
/* Devices attached now (not counting a hub), and the key events and mouse reports so far. */
extern volatile uint32_t diag_usb_devices, diag_usb_keys, diag_usb_mouse;
/* The last mouse to mount: its IDs, protocol, and report descriptor (the first bytes); its
 * reports' lengths, every bit seen set in each byte, and the last few reports. */
#define DIAG_MOUSE_DESC 96
#define DIAG_MOUSE_LOG 8
extern uint8_t diag_mouse_desc[DIAG_MOUSE_DESC];
extern uint16_t diag_mouse_desc_len, diag_mouse_vid, diag_mouse_pid;
extern uint8_t diag_mouse_proto, diag_mouse_len_min, diag_mouse_len_max, diag_mouse_seen[8];
extern uint8_t diag_mouse_log[DIAG_MOUSE_LOG][9]; /* length, then up to 8 bytes */
extern uint32_t diag_mouse_logged;
extern char diag_mouse_layout[80]; /* what its descriptor was read as */
/* Pad 0: its IDs and report descriptor, what that was read as, its reports so far, how long
 * they get, the bits that have changed in each byte, and the last few that differed. */
#define DIAG_PAD_DESC 160
#define DIAG_PAD_LOG 4
#define DIAG_PAD_BYTES 16
extern volatile uint32_t diag_usb_pad;
extern uint8_t diag_pad_desc[DIAG_PAD_DESC];
extern uint16_t diag_pad_desc_len, diag_pad_vid, diag_pad_pid;
extern uint8_t diag_pad_len_max, diag_pad_changed[DIAG_PAD_BYTES], diag_pad_log[DIAG_PAD_LOG][DIAG_PAD_BYTES + 1];
extern uint32_t diag_pad_logged;
extern char diag_pad_layout[140];
/* Each device attached (not hubs): its IDs and how many HID interfaces it has. */
#define DIAG_DEVS 4
typedef struct {
    uint8_t dev, hid;
    uint16_t vid, pid;
} diag_dev;
extern diag_dev diag_devs[DIAG_DEVS];
/* Pad 0's device, its speed (0 full, 1 low), whether a read was waiting just after it
 * mounted, and whether diag_pad_desc holds its configuration descriptor by now (3). */
extern uint8_t diag_pad_dev, diag_pad_idx, diag_pad_speed, diag_pad_armed0, diag_pad_cfg;
bool diag_pad_armed(void); /* a read is waiting at the pad now */
void diag_kbd_print(void);  /* each keyboard: IDs, protocol, report lengths, lights */
#endif

#endif
