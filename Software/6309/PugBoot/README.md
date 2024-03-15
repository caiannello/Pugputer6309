# PugBoot - Minimal Bootloader

This will be the firmware for the Rev 2 hardware, with a goal to fit inside 3840 bytes of FLASH from $f000 to $f800. 

The minimum features planned for this code are as follows:
  ML monitor, via serial, if nothing is bootable
    XMODEM code upload via ML monitor
  Init VIA card, if present, and attempt to boot from SD card.
  Init the video card, if present, and maybe show a simple splash screen.

  
