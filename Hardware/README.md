```
PUGPUTER 6309 - Hardware
-------------------------------------------------------------------------------
The schematics and board artwork for this project were created using
Cadsoft EAGLE v4.16r2 Professional, which is an older CAD tool available as
freeware (crippleware) for Linux, Windows, and OSX.

I would steer clear of newer versions of EAGLE. (Cadsoft was eventually 
bought-out by Autodesk, and they moved EAGLE to a money-grubbing, 
subscription-based business model. 

4.16r2 is old, but pretty nice, and it seems to still work well in Windows 10.

The freeware version of Eagle has limited board size and layercount, but all
boards are viewable, and I think all the boards except the backplane are small
enough to be editable.
-------------------------------------------------------------------------------

Projects in this directory:

6309 CPU Card V0      HD63C09P CPU, R65C51P2 UART, 64K RAM, 32K ROM
Backplane             Five card slots, end-to-end for flatness
V9958 Video Card      Same graphics chip as the MSX 2+ home computer
Parallel IO Card      IO at 5 Volts (Arduino Uno/Nano/Mega, etc.)
LV Parallel IO Card   IO at 3.3 Volts (Teensy 4.1, ESP32, Pi, etc.)
Multifunction Card    Adds SD card, sound, and GPIO. There's a version for
                      PI Pico, Teensy 4.1, and Atmega2560. All three
                      Are currently in the breadboard stage!!
                      
The parallel card is intened to allow microcontrollers such as Arduino to 
be hooked up to the Pugputer to provide SD card, keyboard, audio, and GPIO.
Relevant software for Arduino Uno and Teensy 4.1 are provided in the Software
directory of this repo.

-------------------------------------------------------------------------------
```
