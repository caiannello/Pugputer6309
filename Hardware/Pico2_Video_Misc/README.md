## RP2350B (Raspberry Pi Pico 2) Video Card

This is the video card implemented by the emulator, and it's hugely more performant than the V9958 predecessor. 
I have yet to add the OPL3 module to this card, but that will probably happen eventually. This card is based 
on an Olimex RP2350-PICO2-XXL, and a cheap HDMI breakout board off Amazon. (Going to need to get a real part 
number on that part eventually. Basically, pin 0, at the top-left is GND, and after that its HDMI pins 1 
through 19.

For a writeup on the current capabilities of this card, see [Pugputer6309_Emulator - Video card readme](https://github.com/caiannello/Pugputer6309_Emulator/tree/main/vidcard)

## Video Card Layout and Schematic

![Layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Pico2_Video_Misc/layout.png)

![Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Pico2_Video_Misc/schematic.png)

