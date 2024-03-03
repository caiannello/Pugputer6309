## V9958 Video Card

This is the same Yamaha graphics processor that is used in the MSX 2+ line of Japanese home computers. It is a descendant of the TI V9918 VDP which was used in the TI-99/4A home computer and the ColecoVision game console from the early 1980's. A CXA2075M composite encoder chip is used to provide S-video and composite outputs. The picture quality is decent, though there are some very faint 'jail bars' in composite mode.

## Video Card Layout and Schematic

![V9958 Layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/V9958%20Video%20Card%20Layout.png)

![V9958 Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/V9958%20Video%20Card%20Schematic.png)

## OPL3 Audio Module

There was some enough empty space on the video card to add this little music synthesizer module. The chips are one [Yamaha YMF262](https://www.polynominal.com/yamaha-opl3/) FM synthesizer, a YAC512 Stereo DAC, and an MC33074 buffer amplifier. There's not yet any example code for this module in the repo, but plenty of demos of the chip can be [found online](https://www.youtube.com/watch?v=GBQ2RzsHe1g). I tested a built-up module by hooking it to an Arduino, and playing some of my favorite VGM tunes, and it sounds very good to me.

![OPL3 Module](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/opl3_module_prototype.jpg)

![OPL3 Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/V9958%20Video%20Card/opl3_module_schematic.png)
