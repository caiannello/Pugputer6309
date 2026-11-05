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

6309 		The BIOS and the SD card image (DOS, shell, BASIC, tools and
		demos, from the Pugputer6309_Emulator), and the older Extended
		Basic, bootloader, Pugmon, demos of sound and graphics

RP2350		RP2350 firmware: video_misc is the Pico2_Video_Misc card's
		(graphics over DVI, and the SD card the BIOS boots from)

Arduino UNO	Allows an Uno to be connected to the Pugputer (via parallel IO
		card) to provide SD Card, SPI, PS/2 keyboard, and minimal (PWM)
		audio

Teensy 4.1	Allows a Teensy 4.1 to be connected to the Pugputer (via the
		LV Parallel IO card) to provide SD Card, SPI, USB, 
		USB Keyboard, real-time clock, GPIO, Gamepad connectors, 
		coprocessing, and professional-quality audio

-------------------------------------------------------------------------------
```
