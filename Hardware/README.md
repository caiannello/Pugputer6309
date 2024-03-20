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
boards are viewable. Editing may be another story. TODO: Learn Kicad?
-------------------------------------------------------------------------------

Projects in this directory:

6309 CPU Card V2      HD63C09P CPU, R65C51P2 UART, 1MB RAM, 32K ROM, RTC
V9958 Video Card      Same graphics chip as the MSX 2+ home computer + OPL3
VIA_SD_PSUP           Power supply, W65C22 VIA, MCU, SD Card, SPI, I2C, etc.
Backplane             Five card slots, tombstone-style
RAM Expansion         Gives the Pugputer more memory than actual pugs. (3 MB)
all-in-one            Combines all of the above into one 11.3" x 3.5" board!
-------------------------------------------------------------------------------
```
## Wishlist
```
The V9958 Video Display Processor is starting to get more scarce, and the
price is up to $40+ a piece now, and rising. The kind folks on the MSX Facebook
Group have suggested the TN-VDP Tang Nano 20K project, which offers an FPGA-
based replacement of this chip.

I haven't put any hardware out yet, though, so I'm not married to the V9958.
I have a strong suspicion that a single Raspberry Pi Pico could replace both
the video card and the VIA card to provide graphics, sound, SD card, and
maybe even bring extra capabilities to the table like WLAN.

I have a Pimaroni "Pico Demo" board which does 15-bit RGB VGA, stereo sound,
and SD card! I expect I'd need to give up some of that color depth in order to
allocate an interface to the Pugputer bus. I don't know if the Pico has enough
oomph in its PIO's to handle video, I2S, SD Card, and bus transactions at
the same time, though. If someone has the know-how to weigh in on this
possibility and maybe sketch out a bus interface and some pseudocode, I would
be very grateful! I'm at caiannello at rhymes-with-moogle-pot-calm.  <3
```
![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Layout.png)
![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/6309%20CPU%20Card/CPU%20Card%20v2%20Schematic.png)

![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/VIA_SD_PSUP/Layout.png)
![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/VIA_SD_PSUP/Schematic.png)

![V9958 Layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/V9958%20Video%20Card%20Layout.png)
![V9958 Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/V9958%20Video%20Card%20Schematic.png)

![OPL3 Module](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/opl3_module_layout.png)

![OPL3 Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/opl3_module_schematic.png)

![3MB layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/RAM%20Expansion/layout.png)
![3MB schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/RAM%20Expansion/schematic.png)

![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Backplane/Backplane%20Layout.png)
![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Backplane/Backplane%20Schematic.png)
