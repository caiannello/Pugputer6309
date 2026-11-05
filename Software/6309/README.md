```
Pugputer 6309 - Software and Firmware
-------------------------------------------------------------------------------
The assembly projects in this directory are compiled using the very excellent
cross-toolchain LWTOOLS 4.20 in Linux. I believe there are builds of LWTOOLS 
for OSX and Windows as well.

The BASIC sources are for the included Extended BASIC intrpreter.
-------------------------------------------------------------------------------

Projects in this dirctory:

bios	The CPU card's BIOS (4K ROM at $F000): serial console, BIOS calls,
	RAM banking, the 16 Hz clock tick, and booting DOS from the SD card
	on the RP2350 video card. The same BIOS the Pugputer6309_Emulator
	runs; pugbios_rom.bin is ready to burn into the 32K ROM.

sdcard	pugdisk.img, the SD card: DOS and its shell, BASIC (with disk,
	graphics and error trapping), an editor, assembler and linker, and
	demos for the video card and the OPL3.

demos	Fun stuff for basic and assembler that shows off the graphics and 
	sound capabilities of the pugputer.

basic   Microsoft Extended BASIC 6809 (from 1982) which started out as the
	version for TRS-80 Color Computer, but was subsequently stripped
	of hardware-specific stuff by Grant Searle, modified to compile
	under lwasm by Tom Circuit, and extended to use the graphics, 
	sound, and IO hardware of the Pugputer. (Note: by default,
	this rev uses the UART only for output, but you can type
	EXEC &HB000 to switch to VDP output. Also, theres no 
	SD card support yet.
            
boot    minimal BIOS, bootloader, ML monitor (superseded by bios)

pugmon	work-in-progress machine code monitor, mini assembler, BIOS, and
        minimal OS for the pugputer. VDP and UART

-------------------------------------------------------------------------------
```
