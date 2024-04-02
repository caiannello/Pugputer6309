// ----------------------------------------------------------------------------
//
//  MEGA MULTIPASS - Teensy 4.1 as a Retrocomputer Peripheral
//  
//  Project-wide definitions, settings, and includes.
//
// ----------------------------------------------------------------------------
#ifndef __DEFINES_H__
#define __DEFINES_H__
// ----------------------------------------------------------------------------
#include <stdint.h>
#include <Arduino.h>
// ----------------------------------------------------------------------------

// Serial debug logger --------------------------------------------------------

#define   SER_BAUD                  115200

// Parallel Bus Interface -----------------------------------------------------

// Handshake Lines

#define   PIN_CWR                   3
#define   PIN_CRD                   2
#define   PIN_UWR                   4
#define   PIN_URD                   5

// Parallel Interface Data IO lines (db0...db7)

#define   PIN_DB0                   28
#define   PIN_DB1                   29
#define   PIN_DB2                   30
#define   PIN_DB3                   31
#define   PIN_DB4                   32
#define   PIN_DB5                   33
#define   PIN_DB6                   34
#define   PIN_DB7                   35

// Message types

#define MSG_STATUS            0     // when sent: no payload, response: t_status
#define MSG_GET_DIR           0x10     // payload when sent: null-terminated path, or nothing.
                                    // text-format dir is returned in one or more MSG_DUMP messages.
#define MSG_DUMP              2     // payload is 4-byte address or byte idx,
                                    // followed by up to 512 bytes of data.
#define MSG_DUMPEND           3     // same as above, but denotes final dump msg of xfer
#define MSG_CHDIR             4     // payload: null-terminated path, or ".."
                                    // returns an ack or NAK
#define MSG_KBHIT             5     // payload is one or more kbdown & kbup codes 

#define MSG_NAK               253   // crc failed on prev message from you
#define MSG_ACK               254   // acknowledge
#define MSG_NCOMP             255   // couldnt comply with request

// Error flag bits that may be set in g_errors -------------------------------
#define   ERR_TX_BUF_FULL           1   // cpu not handling tx bytes fast enough
#define   ERR_RX_BUF_FULL           2   // not handling rx bytes fast enough
#define   ERR_PAR_HOST_NO_RESPONSE  4   // cpu isnt reading the bytes we sent

// ----------------------------------------------------------------------------
// GPIO PINS ALREADY IN USE FROM THE START:
// 0, 1               SERIAL DEBUG LOG
// 48,49,50,51,52,53,54   QSPI PSRAM and FLASH
// 42,43,44,45,46,47      SDIO

// 7, 8, 20, 21, 23       AUDIO DATA
// 18, 19                 AUDIO I2C CONTROL
// 15 (A1)                AUDIO optional VOLUME POT
// 6                      AUDIO optional PSRAM

// FREE GPIO PINS TO CHOOSE FROM
// 2,3,4,5,6,9  
// 10,11,12,13    (SPI0)
// 14,15,16,17,22
// 24,25,26,27,28,29,30,31,32
// 33,34,35,36,37,38,39,40,41
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
#endif
// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
