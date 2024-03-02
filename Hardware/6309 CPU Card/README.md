## 6309 CPU Card v2
![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Layout.png)
```

3/1/2024 UPDATE:

Added a new v2 CPU card. It has the same HD63C09 clocked at 3.57 MHz,
32K Flash ROM, and serial UART, but it adds 512k SRAM, expandable to
4 MB, and a real-time clock interrupt.

Also, rather than a pin header connection to the backplane, this one
uses a classic 60-pin card-edge connector similar to a Nintendo Famicom
cartridge.

Moved previous version to past_revs/ subfolder. 
```
## Memory Map v2
```
  name      strt - end     size     notes
  ----      -----------    ----     -----
  RAM0      0000 - 3fff    16384    RAM page 0 (a14 - a21 from bank reg. 0)
  RAM1      4000 - 7fff    16384    RAM page 1 (a14 - a21 from bank reg. 1)
  RAM2      8000 - bfff    16384    RAM page 2 (a14 - a21 from bank reg. 2)
  RAM3      c000 - efff    12288    RAM page 3 (a14 - a21 from bank reg. 3)
  ROM       f000 - feff    3840     Fixed ROM  (bootloader)
  IO0       ff00 - ff0f    16
  IO1       ff10 - ff1f    16
  IO2       ff20 - ff2f    16
  IO3       ff30 - ff3f    16
  IO4       ff40 - ff4f    16
  IO5       ff50 - ff5f    16
  IO6       ff60 - ff6f    16
  IO7       ff70 - ff7f    16
  IO8       ff80 - ff8f    16
  IO9       ff90 - ff9f    16
  IO10      ffa0 - ffaf    16
  IO11      ffb0 - ffbf    16       VIA
  SIO0      ffc0 - ffc3    4      
  SIO1      ffc4 - ffc7    4      
  SIO2      ffc8 - ffcb    4      
  SIO3      ffcc - ffcf    4      
  SIO4      ffd0 - ffd3    4        
  SIO5      ffd4 - ffd7    4        
  SIO6      ffd8 - ffdb    4        
  SIO7      ffdc - ffdf    4        
  SIO8      ffe0 - ffe3    4        OPL3
  SIO9      ffe4 - ffe7    4        V9958 VDP
  SIO10     ffe8 - ffeb    4        UART
  SIO11     ffec - ffef    4        MAPPER
  intvec    fff0 - ffff    16       Fixed ROM (interrupt vectors)
```
## Address Decoding stuff for the PAL
```
This is mostly just work-in-progress thoughts about how to go about
implementing the memoty map on the system and programming the PAL.
Some of this is implemented with discrete logic on the card because
the PAL doesnt have enough inputs to handle everything alone.

// combinatorial logic

hn3    = a15 & a14 & a13 & a12         # f...  implemented with discrete logic
hn2    = a11 & a10 & a9 & a8           # .f..  .||.
hn1    = a7 & a6 & a5 & a4             # ..f.  .||.
siol = a7 & a6 & !a5 & !a4             # ffc0 - ffcf implemented in PAL
siom = a7 & a6 & !a5 &  a4             # ffd0 - ffdf .||.
sioh = a7 & a6 &  a5 & !a4             # ffe0 - ffef .||.
hiadr  = a19 | a20 | a21               # true if address > onboard 512KB (discrete logic)

// Inputs to PAL:

hn3, hn2, hn1, hiadr, a7, a6, a5, a4, a3, a2

// Outputs from the PAL:

extram  = !hn3 & hiadr                                # for ram expansion card, connected to bus
io      = hn3 & hn2 & !hn1                            # for misc cards, connected to bus
/ram    = ! ( !hn3 & !hiadr )                         # 0000 - efff  (onboard chip select)
/rom    = ! (  hn3 & ( !hn2 | ( hn2 & hn1 ) ))        # f000 - feff, fff0 - ffff (onboard chip select)
/mapper = ! (  io & sioh & a3 &  a2 )                 # ffec - ffef (onboard chip select)
/uart   = ! (  io & sioh & a3 & !a2 )                 # ffe8 - ffeb (onboard chip select)

// outputs from pals on other cards:

/v9958  = ! (  io & sioh  & !a3 & a2 )              # ffe4 - ffe7  Video Card video chip
/opl3   = ! (  io & sioh  & !a3 & !a2 )             # ffe0 - ffe3  Video Card music chip

/via    = ! (  io & a7 & !a6 & a5 & a4 )            # ffb0 - ffbf  W65C22 Versatile Interface Adaptor (SD Card, keyboard, etc)

```
![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Schematic.png)

## Rambles About the Timer Feature
```
The real-time interupt causes an /IRQ to happen at a rate of 16 Hz.

This IRQ is shared with the UART, so the UART interrupt will happen
first and see that nothing serial happened to cause the interrupt,
so the the ISR will fall-through to a timer ISR. The timer ISR simply
counts ticks, which enables date and time to be tracked. There's no
battery backup though, so current data and time must be provided on
each powerup, either manually or via the network.

Date and time aren't the main reason the timer was added, though.

In the use case where there is just a CPU card being used with a
serial terminal, a timer is needed to properly differentiate between
certain key presses. For example, when Escape is pressed, a single
0x1b character is sent to the UART. Pressing cursor-up sends a
sequence of three characters, starting with the code for escape:
0x1b, '[', 'A'.  Most terminal emulators, even BASH, use a timer
to distinguish between single escape characters and ANSI escape
sequences. I hated the idea of implementing this timer with a
software busy loop, and there's not enough room on the CPU card for
dedicated clock/timer chips such as the DS1287 or W65C22 VIA, so
I went with something much more basic.
```
