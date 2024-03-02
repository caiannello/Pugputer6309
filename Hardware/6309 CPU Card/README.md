
![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Layout.png)
```

3/1/2024 UPDATE:

Added a new v2 CPU card. It has the same HD63C09 clocked at 3.57 MHz,
32K Flash ROM, and serial UART, but it adds 512k SRAM, up to 4 MB total
memory available via bank-switching, and a real-time clock interrupt.

Also, rather than a pin header connection to the backplane, this one
uses a classic 60-pin card-edge connector similar to a Nintendo Famicom
cartridge,


  New memory map

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

// combinatorial inputs

hn3    = a15 & a14 & a13 & a12         # f...
hn2    = a11 & a10 & a9 & a8           # .f..
hn1    = a7 & a6 & a5 & a4             # .f..

siol = a7 & a6 & !a5 & !a4             # ffc0 - ffcf
siom = a7 & a6 & !a5 &  a4             # ffd0 - ffdf
sioh = a7 & a6 &  a5 & !a4             # ffe0 - ffef

hiadr  = a19 | a20 | a21 # ram address beyond onboard 512 KB

// inputs to onboard PAL

hn3, hn2, hn1, hiadr, a7, a6, a5, a4, a3, a2

// required outputs on onboard pal

extram  = !hn3 & hiadr                                # out to bus
io      = hn3 & hn2 & !hn1                            # out to bus
/ram    = ! ( !hn3 & !hiadr )                         # 0000 - efff
/rom    = ! (  hn3 & ( !hn2 | ( hn2 & hn1 ) ))        # f000 - feff, fff0 - ffff
/mapper = ! (  io & sioh & a3 &  a2 )                 # ffec - ffef small
/uart   = ! (  io & sioh & a3 & !a2 )                 # ffe8 - ffeb small

// outputs on offboard pal(s)

/v9958  = ! (  io & sioh  & !a3 & a2 )              # ffe4 - ffe7 small
/opl3   = ! (  io & sioh  & !a3 & !a2 )             # ffe0 - ffe3 small

/via    = ! (  io & a7 & !a6 & a5 & a4 )            # ffb0 - ffbf large

OLD README --------------------------------------------------------------------

I have been using this first version, V0, for a while, and while it's been good 
enough to develop the software, it has some shortcomings I would like to address
soon:

-------------------------------------------------------------------------------

Problem 1:

Tha PLD used for address decoding only sees the 7 high-order address lines.. 
Which means that every individual peripheral takes up 512 bytes of precious 
address space! Currently, the PLD is programmed to enable peripherals according 
to this table:

0x0000 - 0x7FFF RAM
0x8000 - 0xEFFF ROM
0xF000 - 0xF7FF IO SPACE
	0xF000 UART
	0xF200 PARALLEL
	0xF400 VIDEO
	0xF600 RESERVED
0xF800 - 0xFFFF ROM

Problem 2:

Notice that the CPU has 16 address lines, A0...A15, but I renamed A12..A15 
into A20...A23, and then added eight (currently unused) address lines 
(A12...A19) to the bus connector. 

I did this because I intend to implement a memory banking scheme so the system 
can have much more than 64K of RAM and ROM. I intend to add some circuitry to 
subdivide the CPU address space into 16 pages, each 4KB in length, and provide 
a method for software to be able to relocate any page within a much larger 
24-bit (16 MB) address space.

Future plans to address these issues: -----------------------------------------

I want to find a way to get five more address lines involved in the instruction
decoding so that peripherals can occupy as few as 16 bytes each.  If I could 
do that, I would move the IO space to the range of 0xFF80-0xFFEF, for a total 
of 240 bytes dedicated to IO, freeing up 1.6KB of memory. 

I don't think the small PLD I'm currently using has enough logic in it to 
handle so many address lines, so I might need to change to a bigger one 
or use an FPGA instead. 

I also want to add a new peipheral to the next rev of CPU card to allow the 
memory paging and expanded memory, and I want to put 512K SRAM on the card 
instead of the 64K SRAM thats currently there.  I'm not yet decided on how 
to accomplish these goals. Originally, I was going to use a dual-port SRAM, 
but they are not cheap, and often they take up a lot of board space. I could 
instead use an off-the-shelf MMU, or even a tiny FPGA which incorporates 
the address decoding, banking logic, and maybe more.



```
![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Schematic.png)
