## Introduction
--------------------------------------------------------------------------------
```
WELCOME TO THE PUGPUTER 6309 PROJECT !!!

The Pugputer is a little labor of love, made as a tribute to the 
early home computers of the 1980's.  

It is based on the Hitachi HD63C09 CPU- an upgraded licensed clone of the
venerable Motorola 6809, and uses vintage parts where appropriate. 
(Except RAM chips, which are plentiful and affordable these days, and a modern 
microcontroller to handle SD card and GPIO.)

Projects in the Hardware directory: 
  (Using CADSOFT EAGLE 4.16r2)

  6309 CPU Card v2 -    HD63C09P CPU, R65C51P2 UART, 1MB RAM, 32K ROM, RTC
                        (Mem expandable to 4MB) 
  Backplane v2 -        Five card slots, tombstone style 
  V9958 Video v2   -    Same graphics chip as the MSX 2+ home computer 
                        Optional OPL3 synthesizer module (YMF262)
  VIA_SD_PSUP v2        SD Card, SPI, I2C, ADC, parallel port, and power supply.

Projects in the Software Directory:  (All are work-in-progress, stay tuned.) 
  (Using LWTOOLS/LWASM 4.20 for the 6309 assembly stuff)

  6309 Extended Basic -   Microsoft, Grant Searle, Tom Circuit, and me
  Pugmon -                ML Monitor
  Pugboot -               Minimal bootloader
  Demos -                 graphics and sound examples in Assembly and BASIC
  Arduino UNO -           Allows an Uno to be connected to the Pugputer 
                          (via parallel IO card) to provide SD Card, SPI, 
                          PS/2 keyboard, and minimal (PWM) audio
  Teensy -                Same as above, but for Teensy 4.1 and LV parallel 
                          IO card

3D Models 
  (Using Trimble SketchUp MAKE 17.2.2555 for Windows 64-bit )
(Nice renders using Indigo Renderer by Glare Technologies)

```
## Youtube Channel

Once this project is further along, I plan on making some demo videos and putting them on my [youtube channel](https://www.youtube.com/appliedcryogenics). In the meantime, there's some older projects on there, so it may still be worth a browse. 

## Gallery

CPU Card v2
![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Layout.png)

The card in the middle in the below image is a prototype multifunction card. It comprises a Teensy 4.1 in a ZIF socket with a piggybacked audio card, connected to the backplane via the LV Parallel interface. The USB host connector of the Teensy is connected to the keyboard, but I hope to have some kind of USB hub, eventually. Also note, the backplane shown doesn't space the cards far enough to allow all five to be populated at once. This has since been corrected in the board design, and the total length is still shorter than the keyboard at 13.8 out of 14.125 inches.
![prototype](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Prototype_feb_2023.jpg)

Graphics from SquareSoft's Seiken Densetsu 3 for Super NES ([Source code](https://github.com/caiannello/Pugputer6309/blob/main/Software/6309/Demos/mana_tilemap.asm))
![mana](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Squaresoft%20Tilemap%20Seiken%20Densetsu%203.jpg)

([Board designs](https://github.com/caiannello/Pugputer6309/tree/main/Hardware))
![bottom](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/wedge_kb_bot.png)

Microsoft Extended BASIC for 6809, modified by Grant Searle, Tom Circuit, and me ([Source code](https://github.com/caiannello/Pugputer6309/tree/main/Software/6309/MS%20Extended%20BASIC))
![basic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Extended%20BASIC%20on%20VDP.jpg)

This one uses the library from the ancient [Motorola MC6839 FLOATING POINT ROM!](http://jefftranter.blogspot.com/2019/04/a-6809-single-board-computer-mc6839.html) ([Source code](https://github.com/caiannello/Pugputer6309/blob/main/Software/6309/Demos/mandelbrot.asm))
![mandelbrot](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Mandelbrot%20Demo.jpg)

[PugMon](https://github.com/caiannello/Pugputer6309/tree/main/Software/6309/Pugmon)
![pugmon](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Pugmon%20on%20both%20VDP%20and%20UART.jpg)

Still working on a nice enclosure.. (I wish I had taken shop class in high school!) ([SketchUp Models](https://github.com/caiannello/Pugputer6309/tree/main/3D_Models))
![case design](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/wedge_kb_model.png)
