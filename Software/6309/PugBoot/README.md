# PugBoot - Minimal Bootloader
```
This will be the firmware for the Rev 2 hardware. We have 32K of FLASH,
but I'm hoping to keep most of the address space dedicated to RAM, leaving
only 3840 bytes of FLASH, from $F000 to $FF00, dedicated to firmware. 

The minimum features planned for this code are as follows:

  - If nothing is bootable, start ML monitor on with serial interface. 
     XMODEM code upload to RAM via ML monitor

  - Init VIA card, if present, and attempt to boot from SD card.

  -  Catch illegal instruction interrupt and drop into ML monitor or 
     some other handler if one is set by a running application.

  - NMI interrupt caught and increment a 64-bit counter for
    timekeeping.

  - Minimally initialze the video card, if present, and maybe show a
    simple splash screen.

    It's not likely to include a full text display in the firmware
    for use by the ML monitor, since just the font alone 2048 bytes.
    (Maybe a pared-down font and/or comprssion may allow it, but for
    now, I'm considering having the video driver load into RAM off
    the SD card at boot.)

  -  The ML monitor should be cabable of working via video as well as
     serial after boot.

```
  
