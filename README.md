## Introduction

```
WELCOME TO THE PUGPUTER 6309 PROJECT !!!

The Pugputer is a little labor of love, made as a tribute to the 
early home computers of the 1980's.  

It is based on the wonderful Hitachi HD63C09 CPU- an upgraded licensed clone 
of the venerable Motorola 6809, and uses vintage parts where appropriate. 
(Except RAM chips, which are plentiful and affordable these days, and a modern 
microcontroller to handle SD card, audio, and GPIO.)

Projects in the Hardware directory: 
  (Using CADSOFT EAGLE 4.16r2)

  6309 CPU Card V0 -    HD63C09P CPU, R65C51P2 UART, 64K RAM, 32K ROM 
                        (Expanded memory is on the to-do list) 
  Backplane -           Five card slots end-to-end for flatness 
  V9958 Video Card -    Same graphics chip as the MSX 2+ home computer 
  Parallel IO Card -    5 Volts (Arduino Uno/Nano/Mega, etc.) 
  LV Parallel IO Card - 3.3 Volts (Teensy 4.1, ESP32, Pi, etc.)
  Multifunction card -  Combination parallel card and Atmega2560 with SD card, 
                        Audio, and GPIO

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

Graphics from SquareSoft's Seiken Densetsu 3 for Super NES (Source code is in software/6309/demos)
![mana](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Squaresoft%20Tilemap%20Seiken%20Densetsu%203.jpg)

![bottom](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/wedge_kb_bot.png)

Microsoft Extended BASIC for 6309, modified by Grant Searle, Tom Circuit, and me (Source code is in software/6309/BASIC)
![basic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Extended%20BASIC%20on%20VDP.jpg)

This one uses the library from the ancient [Motorola MC6839 FLOATING POINT ROM!](http://jefftranter.blogspot.com/2019/04/a-6809-single-board-computer-mc6839.html) (Source code is in software/6309/demos)
![mandelbrot](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Mandelbrot%20Demo.jpg)

![pugmon](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Pugmon%20on%20both%20VDP%20and%20UART.jpg)

Still working on a nice enclosure.. (I wish I had taken shop class in high school!)
![case design](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/wedge_kb_model.png)
