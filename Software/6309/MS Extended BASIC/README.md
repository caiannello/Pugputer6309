```
-----------------------------------------------------------------------------
Microsoft Extended BASIC for 6809, 1982 release
Transcribed and stripped of Color-Computer specific stuff by Grant Searle, 
working from the book "Extended BASIC Unravelled", by Walter K. Zydhek.

In 2014, it was adapted by Tom Circuit to compile under lwtools 4.10.

In 2022-2023 this version has been expanded by Craig Iannello to support
the following additional hardware:

Rockwell  R65C51P2         Serial UART
Yamaha    V9958            Video Display Processor
Pugbutt   Mega-Multipass   Sound / SD Card / IO Card

target toolchain: lwtools lwasm ver 4.10 

NOTES:

Uses UART interface by default. To enable VDP output, 
type EXEC &HB000 , also, see demos.

!! The parallel interface is currently just a stub. !!
Eventually, it will provide SD card file open/load/save, keyboard, audio.

Authors' sites:

http://searle.x10host.com/6809/Simple6809.html
https://github.com/tomcircuit/hd6309sbc
https://github.com/caiannello/pugputer
https://youtube.com/appliedcryogenics

-----------------------------------------------------------------------------
```
