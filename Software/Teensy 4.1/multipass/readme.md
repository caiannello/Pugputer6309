///////////////////////////////////////////////////////////////////////////////
//
//  MEGA MULTIPASS - Teensy 4.1 as a Retrocomputer Peripheral
//  
//      This project allows the Teensy to be interfaced to 
//      classic retrocomputers to potentially provide 
//      several services:
//
//        * SD card file system
//        * Audio IN/OUT/SYNTH
//        * Misc IO (SPI, I2C, UART)
//        * Programmable Timers
//        * Coprocessor, math, crypto, etc.
//        * ???
//
//  Communications with the host system is via a bidirectional parallel 
//  interface attached to the computer's data bus. It uses a lightweight, 
//  message-based protocol with error-checking. 
//
// v0.0.1 by Craig Iannello 2023-1-1
//
///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
//
// Parallel bus interface and comms protocol
//
// The parallel interface is implemented with a couple 8-bit latches and
// a PLD, which intervene between the Teensy and the host CPU's data bus.
//
// One latch is for data sent from CPU to Teensy, and the other is for data
// sent from Teensy to CPU.
//
// In addition to eight bidirectional data lines, db0...db7, there are
// four handshake lines:
// 
//    CWR - CPU WRITE (Input,  Active High)
//    CRD - CPU READ  (Input,  Active Low)
//    UWR - MCU WRITE (Output, Active High)
//    URD - MCU READ  (Output, Active Low)
//
//    The function of these signals is further described below.
//
// CPU TRANSMIT (Not a closed loop)
//
// When the CPU writes a byte to the parallel card, the data is latched 
// in the transmit latch by a rising edge on the CWR line. The Teensy can
// see this signal, so it knows when a byte was written. The Teensy is
// configured to fire a pin-change interrupt on a rising edge of CWR.
// In the ISR (Interrupt handler), the Teensy will read out that byte:
// first it enables the transmit latch output by setting the URD line
// LOW, reads the value of signals db0...7db7, and finally, it sets URD
// back to HIGH.
//
// Currently, the CPU side is not made aware of a URD signal, but if we 
// ever wanted to make transmission be a closed-loop (flow-controlled) 
// operation, making the CPU aware of URD would be a good way. The Teensy 
// is nice and fast though, so hopefully it should have no trouble keeping 
// up with the reception of bytes from a vintage CPU anyway.
//
// CPU RECEIVE (Closed loop)
//
// The Teensy won't send bytes any faster than the CPU can read them. The 
// way this is accomplished is as follows:
//
// When the Teensy wants to write a byte, it presents the bits on db0...db7,
// and it brings the UWR signal HIGH. This latches the bits in the receive 
// latch, and it also begins an /IRQ state on the CPU side. 
//
// In the CPU's IRQ ISR, it does a read of the parallel port byte, which
// briefly causes a receive latch output enable signal (CRD) to go LOW.
//
// The Teensy sees that CRD signal, and it fires a different pin-change 
// interrupt on that falling edge. In the ISR, the Teensy returns it's UWR 
// line back to LOW, which ends the /IRQ state on the CPU side. Until that
// happens, the Teensy won't try to send any more bytes.
//
// COMMUNICATIONS PROTOCOL
//
// Bytes are sent through the interface as packets in the following format:
//
// 0xA5, 0x5A, u8 msg_type, u16 byte_cnt, u8 bytes[], u16 crc_ibm_bisync
//
// where 0xA5, 0x5A are single bytes, byte_cnt is the number of bytes that
// follow in the message, message types are described below, bytes are
// optional data payload, and CRC is a 16-bit CRC which uses a polynomial 
// of value 0x8005. (This poly was used by IBM in the 1960's for their 
// Bisync protocol.)
// 
// Not every message needs to have a data payload. In those cases, byte_cnt 
// will equal 2, and there will be no data bytes prior to the CRC. The 
// maximum payload size is 516 bytes. This is enough for 512-byte data with
// a 32-bit byte-address value. This is for use when, e.g. transferring a 
// file, in order to identify which part of the file is contained in the 
// message. There is currently no provision for sending multiple files 
// concurrently, but that might be accomplished by including some kind of 
// file ID value in the message too.
//
// Note that the vintage CPU that is currently being used in this project is
// an HD6309 which uses BIG-ENDIAN byte ordering, so this protocol does too.
// This means that an integer (16-bit, 32-bit value) is transmitted with 
// the most significant byte first. For example, a byte count value of 256
// would be sent as 0x01, 0x00. 
//
// Some other CPU's, including AVR and Intel x86, use LITTLE-ENDIAN byte-
// ordering, which is the opposite: the bytes of integers are stored with the
// the least significant byte first, e.g. a value 0x1234 would be stored 
// in memory and/or transmitted as 0x34 0x12. Historically, some ARM CPUs have 
// been BI-ENDIAN, which means it is configurable which byte ordering is used, 
// but in the Teensy, I expect it uses LITTLE-ENDIAN to maintain Arduino 
// compatibility.  For this reason, if working with integers in the Teensy 
// which have originated from the HD6309, including the CRC and byte_count of 
// a received message, byte swapping may be involved when casting part of a 
// byte array as an integer.
//
///////////////////////////////////////////////////////////////////////////////
