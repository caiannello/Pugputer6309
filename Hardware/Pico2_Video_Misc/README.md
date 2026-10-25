## RP2350B (Raspberry Pi Pico 2) Video Card

This is the video card implemented by the emulator, and it's hugely more performant than the V9958 predecessor,
and I've transplanted the OPL3 module to this card for sweet tunes, even though the RP2350B can probably
handle audio synth/output (over DVI) too. This card is based on an Olimex RP2350-PICO2-XXL, and a cheap 
HDMI breakout board off Amazon. (Going to need to get a real part 
number on that part eventually. Basically, pin 0, at the top-left is GND, and after that its HDMI pins 1 
through 19.

Since this olimex module has an SD card slot on it, and USB, I may as well try to shoehorn SD card functions,
as well as keyboard, mouse, gamepad, connections. No room for a 4-port hub and usb connectors at the moment..
maybe if I find some a wacky-sideways HDMI connector? I agree it feels like cheating to use a modern MCU 
to provide so many functions for the Pugputer 6309. Maybe someday there will be a discrete TTL logic version.

For a writeup on the current capabilities of this card, see [Pugputer6309_Emulator - Video card readme](https://github.com/caiannello/Pugputer6309_Emulator/tree/main/vidcard)

## Graphics Demos 
Supports 64-color 80x60 text, 640x480x16 bitmap, or 320x240x256 bitmap, tilemaps mode (3-layers), and sprites.

![VIDGFX.COM Demo](https://github.com/caiannello/Pugputer6309_Emulator/blob/main/media/vidgfx.png?raw=true)

### Graphics demo in BASIC
![Graphics in BASIC](https://github.com/caiannello/Pugputer6309_Emulator/blob/main/media/basicgfx.png?raw=true)

## Video Card Layout and Schematic

I know the DVI differential signals aren't equal-length, but I believe they'll suffice for 640x480. 
(The old version of CADSOFT EAGLE I use 4.16r2 has no easy way to serpentine the shorter traces, or indeed,
even report a trace's length. Maybe I'll whip out a ruler and do it manually at some point. :-)

![Layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Pico2_Video_Misc/layout.png)

![Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Pico2_Video_Misc/schematic.png)

