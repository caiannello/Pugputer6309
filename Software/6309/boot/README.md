# PugBoot - Minimal Bootloader v2
```
-------------------------------------------------------------------------------
This will be the firmware for the Rev 2 hardware. We have 32K of FLASH, but 
because I'm hoping to keep most of the CPU's address space dedicated to RAM, 
I'm leaving only 3840 bytes of the FLASH exposed, from $F000 to $FF00, to
contain the system firmware.
-------------------------------------------------------------------------------
Planned features:

  - Interrupt handler ISRs / stubs for all interrupts, reconfigurable via a
    jump table in RAM.

  - NMI handler which increments a 64-bit real-time counter in RAM
  
  - Buffered, interrupt-driven serial interface at 19200 baud

  - BIOS functions for IO, SD Card, date and time, and a way to plug 
    additional IO devices during boot for video and keyboard. (See notes)

  - Init VIA card, if present, and attempts boot from SD card.

  - If nothing is bootable, starts built-in ML monitor:

      ML mon features:

        - Serial interface by default ( + video/kbd after boot )
        - Simple memory inspection / edit / call / jump
        - XMODEM file transfer / serial boot
        - Catches illegal-instruction interrupt by default, or can be
          redirected to a custom handler by a running application.
-------------------------------------------------------------------------------
Notes:
  
  - Due to small flash size (3840 bytes) and large font size (2048 bytes) it's 
    not easy to include full text-mode video support in firmware. Besides that,
    a system may have a different video solution from the existing V9958 card.
    It may be possible to have v9958 support in firmware using a pared-down 
    font and/or data compression, but for now, the video driver will get 
    loaded into RAM during boot and then plugged-in to the BIOS. This will 
    enable video/keyboard support in the ML monitor in addition to the default
    serial interface.
-------------------------------------------------------------------------------
```
  
