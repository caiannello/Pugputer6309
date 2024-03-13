```
-------------------------------------------------------------------------------
PUGPUTER 6309 - Experiments connecting Pugputer to modern microcontrollers
-------------------------------------------------------------------------------

The software is far enough along to validate the functions of the parallel 
interface cards and MCU services such as SD card, audio, keyboard, etc.,
but the API for these services is not yet done, so they are not yet usable
by the pugputer. I hope to add file handling to BASIC, bootloader, and
Pugmon soon.

Arduino UNO	Allows an Uno to be connected to the Pugputer (via parallel IO
		card) to provide SD Card, SPI, PS/2 keyboard, and minimal (PWM)
		audio

Teensy 4.1	Allows a Teensy 4.1 to be connected to the Pugputer (via the
		LV Parallel IO card) to provide SD Card, SPI, USB, 
		USB Keyboard, real-time clock, GPIO, Gamepad connectors, 
		coprocessing, and professional-quality audio

-------------------------------------------------------------------------------
```
