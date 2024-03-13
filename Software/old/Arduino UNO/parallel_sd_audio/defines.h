///////////////////////////////////////////////////////////////////////////////
// Project-wide settings and definitions
///////////////////////////////////////////////////////////////////////////////
#ifndef __DEFINES_H__
#define __DEFINES_H__
// ----------------------------------------------------------------------------
#include <stdint.h> // for data types such as uint8_t, int16_t, etc.
#include <Arduino.h>
// ----------------------------------------------------------------------------
#define DEBUG   // comment out if you dont want verbose serial debug log

extern char ts[32];   // general purpose temp string

// ----------------------------------------------------------------------------
// Serial debug logger --------------------------------------------------------
#define   SER_BAUD              115200
// SD card stuff --------------------------------------------------------------
// Uses the default (HW) SPI pins, plus the following chip select:
#define   SD_CS                 10
// Parallel bus interface -----------------------------------------------------
#define   PAR_BUF_SZ            256+11 //(512+11)// Max message buffer size
#define   PAR_CRC_POLY          0x8005  // CRC polynomial - IBM Bisync

// ARDUINO UNO CONNECTIONS
#define   PAR_PIN_CWR           2       // in - CPU write byte (active high)
#define   PAR_PIN_CRD           3       // in - CPU read byte (active low)
#define   PAR_PIN_URD           4       // out - MCU read byte (active low)
#define   PAR_PIN_UWR           5       // out - MCU write byte (active high)
#define   PAR_PIN_D0            A0      // I/O - Data bit 0
#define   PAR_PIN_D1            A1      // I/O - Data bit 1
#define   PAR_PIN_D2            A2      // I/O - Data bit 2
#define   PAR_PIN_D3            A3      // I/O - Data bit 3
#define   PAR_PIN_D4            A4      // I/O - Data bit 4
#define   PAR_PIN_D5            A5      // I/O - Data bit 5
#define   PAR_PIN_D6            6       // I/O - Data bit 6
#define   PAR_PIN_D7            7       // I/O - Data bit 7

/*
// TEENSY 4.1 CONNECTIONS
#define   PAR_PIN_CWR           2       // in - CPU write byte (active high)
#define   PAR_PIN_CRD           3       // in - CPU read byte (active low)
#define   PAR_PIN_UWR           4       // out - MCU write byte (active high)
#define   PAR_PIN_URD           5       // out - MCU read byte (active low)
#define   PAR_PIN_D0            28      // I/O - Data bit 0
#define   PAR_PIN_D1            29      // I/O - Data bit 1
#define   PAR_PIN_D2            30      // I/O - Data bit 2
#define   PAR_PIN_D3            31      // I/O - Data bit 3
#define   PAR_PIN_D4            32      // I/O - Data bit 4
#define   PAR_PIN_D5            33      // I/O - Data bit 5
#define   PAR_PIN_D6            34      // I/O - Data bit 6
#define   PAR_PIN_D7            35      // I/O - Data bit 7
*/

// Protocol - Message types ---------------------------------------------------
                                      // 0x00 - 0x0f : General messages -------
#define   PAR_MSG_ACK           0x00  // Acknowledge
#define   PAR_MSG_NAK           0x01  // Can't acknowledge (CRC error?)
#define   PAR_MSG_NCOMP         0x02  // Can't comply (Optional reason text
                                      // in payload.)
#define   PAR_MSG_STATUS        0x03  // Returns current t_status struct
                                      // 0x10 - 0x1f : SD Card messages -------
#define   PAR_MSG_GET_DIR       0x10  // Send current or specified dir
#define   PAR_MSG_CH_DIR        0x11  // Change to specified dir or '..'
#define   PAR_MSG_MAKE_DIR      0x12  // Create specified dir
#define   PAR_MSG_GET_FILE      0x13  // Transmit specified file from SD
#define   PAR_MSG_PUT_FILE      0x14  // Receive specified file to SD
#define   PAR_MSG_DEL           0x15  // Delete specified file or directory
#define   PAR_MSG_DUMP          0x16  // Used during file / dir transfer.
                                      // Each data payload starts with a
                                      // uint32_t file byte-index.
#define   PAR_MSG_DUMP_END      0x17  // Same as DUMP, but last part of file.
                                      // 0x20 - 0x2f : Keyboard messages ------
#define   PAR_MSG_KEYS_HIT      0x20  // payload is array of t_kb structs
// ----------------------------------------------------------------------------
// See pario.cpp for description of parallel port message protocol.
// ----------------------------------------------------------------------------
const uint16_t crc_tab16[256] PROGMEM = {  // crc polynomial = 0xA001
  0x0000,0xC0C1,0xC181,0x0140,0xC301,0x03C0,0x0280,0xC241,0xC601,0x06C0,0x0780,0xC741,0x0500,0xC5C1,0xC481,0x0440,
  0xCC01,0x0CC0,0x0D80,0xCD41,0x0F00,0xCFC1,0xCE81,0x0E40,0x0A00,0xCAC1,0xCB81,0x0B40,0xC901,0x09C0,0x0880,0xC841,
  0xD801,0x18C0,0x1980,0xD941,0x1B00,0xDBC1,0xDA81,0x1A40,0x1E00,0xDEC1,0xDF81,0x1F40,0xDD01,0x1DC0,0x1C80,0xDC41,
  0x1400,0xD4C1,0xD581,0x1540,0xD701,0x17C0,0x1680,0xD641,0xD201,0x12C0,0x1380,0xD341,0x1100,0xD1C1,0xD081,0x1040,
  0xF001,0x30C0,0x3180,0xF141,0x3300,0xF3C1,0xF281,0x3240,0x3600,0xF6C1,0xF781,0x3740,0xF501,0x35C0,0x3480,0xF441,
  0x3C00,0xFCC1,0xFD81,0x3D40,0xFF01,0x3FC0,0x3E80,0xFE41,0xFA01,0x3AC0,0x3B80,0xFB41,0x3900,0xF9C1,0xF881,0x3840,
  0x2800,0xE8C1,0xE981,0x2940,0xEB01,0x2BC0,0x2A80,0xEA41,0xEE01,0x2EC0,0x2F80,0xEF41,0x2D00,0xEDC1,0xEC81,0x2C40,
  0xE401,0x24C0,0x2580,0xE541,0x2700,0xE7C1,0xE681,0x2640,0x2200,0xE2C1,0xE381,0x2340,0xE101,0x21C0,0x2080,0xE041,
  0xA001,0x60C0,0x6180,0xA141,0x6300,0xA3C1,0xA281,0x6240,0x6600,0xA6C1,0xA781,0x6740,0xA501,0x65C0,0x6480,0xA441,
  0x6C00,0xACC1,0xAD81,0x6D40,0xAF01,0x6FC0,0x6E80,0xAE41,0xAA01,0x6AC0,0x6B80,0xAB41,0x6900,0xA9C1,0xA881,0x6840,
  0x7800,0xB8C1,0xB981,0x7940,0xBB01,0x7BC0,0x7A80,0xBA41,0xBE01,0x7EC0,0x7F80,0xBF41,0x7D00,0xBDC1,0xBC81,0x7C40,
  0xB401,0x74C0,0x7580,0xB541,0x7700,0xB7C1,0xB681,0x7640,0x7200,0xB2C1,0xB381,0x7340,0xB101,0x71C0,0x7080,0xB041,
  0x5000,0x90C1,0x9181,0x5140,0x9301,0x53C0,0x5280,0x9241,0x9601,0x56C0,0x5780,0x9741,0x5500,0x95C1,0x9481,0x5440,
  0x9C01,0x5CC0,0x5D80,0x9D41,0x5F00,0x9FC1,0x9E81,0x5E40,0x5A00,0x9AC1,0x9B81,0x5B40,0x9901,0x59C0,0x5880,0x9841,
  0x8801,0x48C0,0x4980,0x8941,0x4B00,0x8BC1,0x8A81,0x4A40,0x4E00,0x8EC1,0x8F81,0x4F40,0x8D01,0x4DC0,0x4C80,0x8C41,
  0x4400,0x84C1,0x8581,0x4540,0x8701,0x47C0,0x4680,0x8641,0x8201,0x42C0,0x4380,0x8341,0x4100,0x81C1,0x8081,0x4040, 
  };                                      
// ----------------------------------------------------------------------------
// Structure definitions
// ----------------------------------------------------------------------------
typedef struct {    // System status. Sent as payload of status message.
  uint8_t error_flags;  // no bits defined.. yet!
} t_status;

typedef struct {    // Specifies a keyboard down or up event.
  
} t_kb;
// ----------------------------------------------------------------------------
#endif
///////////////////////////////////////////////////////////////////////////////
// EOF
///////////////////////////////////////////////////////////////////////////////
