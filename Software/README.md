```
-------------------------------------------------------------------------------
PUGPUTER 6309 - Software and Firmware
-------------------------------------------------------------------------------

Note: All code, especially the parallel interface code, are works in progress.

The software is far enough along to validate the functions of the parallel 
interface cards and MCU services such as SD card, audio, keyboard, etc.,
but the API for these services is not yet done, so they are not yet usable
by the pugputer. I hope to add file handling to BASIC and Pugmon soon.


Contents

6309 		Extended Basic, bootloader, Pugmon, demos of sound and graphics

Arduino UNO	Allows an Uno to be connected to the Pugputer (via parallel IO
		card) to provide SD Card, SPI, PS/2 keyboard, and minimal (PWM)
		audio

Teensy 4.1	Allows a Teensy 4.1 to be connected to the Pugputer (via the
		LV Parallel IO card) to provide SD Card, SPI, USB, 
		USB Keyboard, real-time clock, GPIO, Gamepad connectors, 
		coprocessing, and professional-quality audio

-------------------------------------------------------------------------------
```
