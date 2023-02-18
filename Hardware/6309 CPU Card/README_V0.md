FORWARD -----------------------------------------------------------------------

I have been using this first version, V0, for a while, and while it's been good enough to develop the software, it has some shortcomings I would like to address soon:

-------------------------------------------------------------------------------

Problem 1:

Tha PLD used for instruction decoding only sees the 7 high-order address lines.. Which means that every individual peripheral takes up 512 bytes of precious address space! Currently, the PLD is programmed to enable peripherals according to this table:

0x0000 - 0x7FFF RAM
0x8000 - 0xEFFF ROM
0xF000 - 0xF7FF IO SPACE
	0xF000 UART
	0xF200 PARALLEL
	0xF400 VIDEO
	0xF600 RESERVED
0xF800 - 0xFFFF ROM

Problem 2:

Notice that the CPU has 16 address lines, A0...A15, but I renamed A12..A15 into A20...A23, and then added eight (currently unused) address lines (A12...A19) to the bus connector. 

I did this because I intend to implement a memory banking scheme so the system can have much more than 64K of RAM and ROM. I intend to add some circuitry to subdivide the CPU address space into 16 pages, each 4KB in length, and provide a method for software to be able to relocate any page within a much larger 24-bit (16 MB) address space.

Future plans to address these issues: -----------------------------------------

I want to find a way to get five more address lines involved in the instruction decoding so that peripherals can occupy as few as 16 bytes each.  If I could do that, I would move the IO space to the range of 0xFF80-0xFFEF, for a total of 240 bytes dedicated to IO, freeing up 1.6KB of memory. 

I don't think the small PLD I'm currently using has enough logic in it to handle so many address lines, so I might need to change to a bigger one or use an FPGA instead. 

I also want to add a new peipheral to the next rev of CPU card to allow the memory paging and expanded memory, and I want to put 512K SRAM on the card instead of the 64K SRAM thats currently there.  I'm not yet decided on how to accomplish these goals. Originally, I was going to use a dual-port SRAM, but they are not cheap, and often they take up a lot of board space. I could instead use an off-the-shelf MMU, or even a tiny FPGA which incorporates the address decoding, banking logic, and maybe more.

