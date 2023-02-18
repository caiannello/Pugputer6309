```
Pugputer 6309 - Sofftware and Firmware
-------------------------------------------------------------------------------
The assembly projects in this directory are compiled using the very excellent
cross-toolchain LWTOOLS 4.20 in Linux. I believe there are builds of LWTOOLS 
for OSX and Windows as well.

The BASIC sources are for the included Extended BASIC intrpreter.
-------------------------------------------------------------------------------

Projects in this dirctory:

demos		Fun stuff for basic and assembler that shows off the graphics and 
			sound capabilities of the pugputer.

basic       Microsoft Extended BASIC 6809 (from 1982) which started out as the
			version for TRS-80 Color Computer, but was subsequently stripped
			of hardware-specific stuff by Grant Searle, modified to compile
			under lwasm by Tom Circuit, and extended to use the graphics, 
			sound, and IO hardware of the Pugputer.
            
pugboot  	lightweight bootloader and minimal BIOS

pugmon		work-in-progress machine code monitor, mini assembler, BIOS, and
            minimal OS for the pugputer.

-------------------------------------------------------------------------------
```
