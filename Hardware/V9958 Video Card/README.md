## V9958 Video Card

This is the same Yamaha graphics processor that is used in the MSX 2+ line of home computers. It is a descendant of the TI V9918 VDP which was used in the TI-99/4A home computer and the ColecoVision game console from the early 1980's. A CXA2075M composite encoder chip is used to provide S-video and composite outputs. The picture quality is decent, though there are some very faint 'jail bars' in composite mode.

## Wishlist

The V9958 Video Display Processor is starting to get more scarce, and the price is up to $40+ a piece now, and rising. The kind folks on the MSX Facebook Group have suggested the TN-VDP Tang Nano 20K project, which offers an FPGA-based replacement of this chip. I haven't put any hardware out yet, though, so I'm not married to V9958 compatibility, and I have a strong suspicion that a single Raspberry Pi Pico W could replace both the video card and the VIA card and maybe do WLAN too?

I have a Pimaroni "Pico Demo" board which does 15-bit RGB VGA, stereo sound, and SD card! I think I'd need to give up some color depth in order to allocate a bus interface, but I don't know if the Pico has enough oomph in its PIO's to handle so many features at once? If someone has the know-how to weigh in on this possibility and is willing to sketch out a bus interface and some pseudocode, I would be very grateful! I'm at caiannello at rhymes-with-moogle-pot-calm.  <3

## Video Card Layout and Schematic

![V9958 Layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/V9958%20Video%20Card%20Layout.png)

![V9958 Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/V9958%20Video%20Card%20Schematic.png)

## OPL3 Audio Module

There's enough empty space on the video card to add this little music synthesizer module. The chips are one [Yamaha YMF262](https://www.polynominal.com/yamaha-opl3/) FM synthesizer, a YAC512 Stereo DAC, and an MC33074 buffer amplifier. There's not yet any example code for this module in the repo, but plenty of demos of the chip can be [found online](https://www.youtube.com/watch?v=GBQ2RzsHe1g). I tested a built-up module by hooking it to an Arduino, and playing some of my favorite VGM tunes, and it sounds very good to me.

![OPL3 Module](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/opl3_module_prototype.jpg)

![OPL3 Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/opl3_module_schematic.png)
