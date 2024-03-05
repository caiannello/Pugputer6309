## 6309 CPU Card v2
```
3/1/2024 UPDATE:

Added a new v2 CPU card. It has the same HD63C09 clocked at 3.57 MHz, 32K Flash
ROM, and serial UART, but it adds 1 MB SRAM, expandable to 4 MB, and a real-
time clock interrupt.

Rather than a pin header connection to the backplane, this one uses a classic 
60-pin card-edge connector similar to a Nintendo Famicom cartridge.

Moved previous version to past_revs/ subfolder. 
```
![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Layout.png)

![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Schematic.png)

## Memory Map v2
```
  name      strt - end     size     notes
  ----      -----------    ----     -----
  MEM0      0000 - 3fff    16384    Mem sect 0 (a14 - a21 from bank reg. 0)
  MEM1      4000 - 7fff    16384    Mem sect 1 (a14 - a21 from bank reg. 1)
  MEM2      8000 - bfff    16384    Mem sect 2 (a14 - a21 from bank reg. 2)
  MEM3      c000 - efff    12288    Mem sect 3 (a14 - a21 from bank reg. 3)
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
  IO11      ffb0 - ffbf    16       W65C22 VIA (SD Card, SPI, KB, GPIO)
  SIO0      ffc0 - ffc3    4      
  SIO1      ffc4 - ffc7    4      
  SIO2      ffc8 - ffcb    4      
  SIO3      ffcc - ffcf    4      
  SIO4      ffd0 - ffd3    4        
  SIO5      ffd4 - ffd7    4        
  SIO6      ffd8 - ffdb    4        
  SIO7      ffdc - ffdf    4        
  SIO8      ffe0 - ffe3    4        Music Chip YMF262 (OPL3)
  SIO9      ffe4 - ffe7    4        Video Chip V9958
  SIO10     ffe8 - ffeb    4        Serial UART R65C51P2
  SIO11     ffec - ffef    4        Memory Bank Regs 0...3
  intvec    fff0 - ffff    16       Fixed ROM (interrupt vectors)
```
## Memory Paging Scheme
```
Two 74LS670 chips are added to the design which provide four writable bytes at
CPU addresses $ffec - $ffef. These act like dual-ported RAMs and enable each 
of the four 16KB sections of the CPU address space to be independently mapped a
different 16KB page of physical memory (up to 4MB.)

CPU Address lines A14 and A15 select which register is active, which then 
provides extended address bits E14...E21 to the system. These are combined with
CPU address bits A0...A13 to form the final 22-bit physical address.

The initial state of the registers is unknown on startup and must be 
initialized before any RAM access should occur. Initially, these are mapped to
the first four pages of physical memory by setting the bank registers as 
follows:

Sect   CPU Adrs    22-bit physical Adrs     Bank Reg (E21...E14)
0      $0000       %0000000000000000000000  $00
1      $4000       %0000000100000000000000  $01
2      $8000       %0000001000000000000000  $02
3      $c000       %0000001100000000000000  $03

```
## Expanded Memory
```
For memory addresses beyond the onboard 1 MB, one or more bits E20...E21 will 
be set. The PAL will not select onboard RAM and will instead set XMEM bus 
signal. This can be used to select memory expansions.
```
## Real-Time Interrupt - Notes
```
The real-time interupt causes an /NMI to happen at a rate of 16 Hz.

The /NMI input is edge-sensitive, unlike /IRQ which is level sensitive, so it
should be OK that the implementation will keep /NMI low for half the time, as
long as we dont someday need to share /NMI.

The /NMI ISR will simply count ticks, which is enough to allow tracking of
date and time. There's no battery backup, so current date and time must be
provided on each powerup, either manually or via network. 

There's a design decision to be made regarding timekeeping: Rollover. With 16
ticks per second, the count gets big fairly quickly. If we kept count as a 
16-bit value, it would roll over every 1.14 hours! (Not good enough for dates.)
A 32-bit counter would roll over every 8.5 years, which is better, but what if
we wanted a high-reliability hobbyist retrocomputer? A 64-bit counter would 
give us 365 million centuries! Aww yeah baby.

Despite the above rambles, date and time aren't even the main reason the 
real-time feature was added:

In the use-case I've been running up against with v0 is that when there is just
a CPU card being used with a serial terminal. A timer is needed to properly 
differentiate between certain key presses. For example, when escape is pressed,
a single 0x1b character is sent to the UART, but pressing cursor-up sends a 
sequence of three characters, starting with that same code: 0x1b, '[', 'A'. 
Most terminals use a timer to distinguish between single escape characters and
ANSI escape sequences. I didn't want to implement this timeout with a software
busy loop, so work began on CPU card rev 2. There's not enough room on the 
board for dedicated clock/timer chip such as the DS1287 or W65C22, so I went 
with this simpler option.
```
## Address Decoding Notes
```
These are thoughts about how to go about implementing the memory map on the 
system and programming the PAL. Some of this is implemented with discrete 
logic on the CPU card because the PAL doesnt have enough inputs to handle 
everything alone.

# Discrete combinatorial logic to help onboard PAL

hn3 = a15 & a14 & a13 & a12                # high adrs nybble == $f
hn2 = a11 & a10 & a9 & a8                  # next adrs nybble == $f
ssf = a7 & a6 & a5
hn1 = ssf & a4                             # next adrs nybble == $f

# Inputs to onboard PAL

eclk, r//w, hn3, hn2, hn1, ssf, e21, e20, e19, a3, a2

# Outputs from onboard PAL

/rd   = !eclk | !r//w                      # bus: memory read
/wr   = !eclk | r//w                       # bus: memory write
io    = hn3 & hn2 & !hn1                   # bus: IO select
xmem  = !hn3 & e20 | e21                   # bus: expansion mem select
/ram0 = hn3 | e20 | e21 | e19              # onboard: ram chip 0 select
/ram1 = hn3 | e20 | e21 | !e19             # onboard: ram chip 1 select
/rom  = !hn3 | hn2 & ( !hn2 | !hn1 )       # onboard: ROM select
/mapw = !io | !ssf | hn1 | !a3 | !a2       # onboard: bank reg. write
/uart = !io | !ssf | hn1 | !a3 | a2        # onboard: UART select

# outputs from PALs on other cards:

/v9958  = !io | !a7 | !a6 | !a5 | a4 | a3 | !a2   # ffe4 - ffe7  Video Card video chip
/opl3   = !io | !a7 | !a6 | !a5 | a4 | a3 | a2    # ffe0 - ffe3  Video Card music chip

/via    = !io | !a7 | a6 | !a5 | !a4       # ffb0 - ffbf  W65C22 Versatile Interface Adaptor
                                           # (SPI, I2C, SD card, KB, gamepad, wifi, etc.)
```
