/* TinyUSB, as the card uses it: a USB host on the RP2350's own port, for keyboards, mice
 * (and, later, gamepads) through a small hub. See usbhost.c. */
#ifndef VIDCARD_FW_TUSB_CONFIG_H
#define VIDCARD_FW_TUSB_CONFIG_H

#ifndef CFG_TUSB_OS
#define CFG_TUSB_OS OPT_OS_PICO
#endif
#define CFG_TUSB_DEBUG 0
#define CFG_TUH_MEM_SECTION
#define CFG_TUH_MEM_ALIGN __attribute__((aligned(4)))

#define CFG_TUH_ENABLED 1
#define BOARD_TUH_RHPORT 0
#define CFG_TUSB_RHPORT0_MODE OPT_MODE_HOST
#define CFG_TUH_MAX_SPEED OPT_MODE_FULL_SPEED

#define CFG_TUH_ENUMERATION_BUFSIZE 256
#define CFG_TUH_HUB 1         /* one hub */
#define CFG_TUH_DEVICE_MAX 5  /* it, and four devices on it */
#define CFG_TUH_ENDPOINT_MAX 8
#define CFG_TUH_HID 8         /* interfaces (a keyboard often has two) */
#define CFG_TUH_HID_EPIN_BUFSIZE 64
#define CFG_TUH_HID_EPOUT_BUFSIZE 64

#endif
