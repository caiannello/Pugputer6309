# The SD card

`pugdisk.img` is the Pugputer's disk: an 8MB FAT16 volume for the microSD slot on the video card
(Pico2_Video_Misc). At power-on the BIOS (`../bios`) reads its boot sector, loads DOS from its
reserved sectors and starts DOS's shell, `/CMD/SHELL.COM`, on the serial console.

It is the disk of the [Pugputer6309_Emulator](https://github.com/caiannello/Pugputer6309_Emulator)'s
binary release (`mkdiskimg --add-dir demo/programs --sources .`), so the machine starts with
what the emulator does.

## Writing it to a card

Any microSD card will do (SDSC, SDHC or SDXC: the firmware takes all three); only the first 8MB
are used. Write the image to the whole card, raw, from block 0:

- **Windows:** Win32 Disk Imager (pick `pugdisk.img`, the card's drive letter, *Write*), or
  balenaEtcher.
- **Linux / macOS:** `sudo dd if=pugdisk.img of=/dev/sdX bs=1M conv=fsync` (`/dev/sdX` the card
  itself, not a partition of it: check with `lsblk`, or `diskutil list` on a Mac, where it's
  `/dev/rdiskN` after `diskutil unmountDisk`).

The volume starts at block 0, with no partition table (a "superfloppy", like a floppy disk), so
the card shows up as one small 8MB drive. **If Windows offers to format it, say no** -- that
would replace the Pugputer's volume. Windows can usually read and write the files on it, but the
safest way to change the disk is from the Pugputer (or the emulator, then write the image again).

## What's on it

| Path | |
|---|---|
| `/CMD` | the shell (`SHELL.COM`), `BASIC.COM`, the editor `EDIT.COM`, the assembler and linker `ASM.COM` and `LINK.COM`, `HEXDUMP.COM`, `MOVE.COM`, the game kit `TILEKIT.COM` |
| `/DEMO` | `VIDDEMO`, `VIDTEXT`, `VIDTILES`, `VIDGFX`, `VIDMOUSE`, `MANDEL` (the video card); `VGMONKEY`, `VGXWINGF` and `VGMPLAY` with its songs (the OPL3) |
| `/BASIC` | BASIC programs (graphics, games, examples) |
| `/ASM` | the sources of the programs, for rebuilding them on the Pugputer with `ASM` and `LINK` |

The shell, DOS, BASIC and the tools are described in the emulator's README.

## Notices

- **BASIC** is a port of Microsoft's Extended Color BASIC for the 6809 ("(C) 1982 BY MICROSOFT"),
  with this project's changes; the original is understood to have been released into the public
  domain.
- **The music:** `VGMONKEY` and `VGXWINGF` play songs logged from classic PC games' OPL music --
  LeChuck's theme, by Michael Z. Land, from *The Secret of Monkey Island* (Lucasfilm Games, 1990),
  and "Death and Funeral" from *Star Wars: X-Wing* (LucasArts, 1993). `VGMPLAY`'s three short
  recordings were turned into OPL3 register writes by WAV2VGM: John F. Kennedy speaking, HAL 9000
  from *2001: A Space Odyssey* (MGM, 1968, voiced by Douglas Rain), and the "Wilhelm scream"
  (first heard in *Distant Drums*, Warner Bros., 1951). They remain the property of their
  composers, publishers and owners, and are included as short demonstrations of the hardware.
- **`MANDEL`** carries a copy of Motorola's MC6839 floating-point ROM ("COPYRIGHT (C) MOTOROLA
  1982"), the vintage library the program was written around; it remains Motorola's.
- **The video card's font** is VileR's ToshibaSat 8x16 (CC BY-SA 4.0): see
  `../../RP2350/video_misc/NOTICE.md`.
