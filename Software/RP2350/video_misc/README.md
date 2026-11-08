# Video card firmware (RP2350)

The firmware of the Pico2_Video_Misc card (`../../../Hardware/Pico2_Video_Misc`), on its Olimex
RP2350-PICO2-XXL:

- **the video card** at `$FF80-$FF9F`: 640x480 at 60Hz out of the HDMI connector (DVI), text,
  bitmaps, three tile layers, sprites and drawing commands;
- **the SD card** at `$FFD8-$FFDB`: the board's microSD slot, as the block device the BIOS boots
  DOS from;
- **/IRQ** through the card's MOSFET (GPIO 30), when a program enables one of the card's
  interrupts (vertical blank, a line, drawing done, input). Nothing does at boot.

The YMF262 (OPL3) on the same card isn't the firmware's: the GAL selects it at `$FFE0-$FFE3`
and the CPU talks to it directly.

This is the firmware of the [Pugputer6309_Emulator](https://github.com/caiannello/Pugputer6309_Emulator)'s
`vidcard/firmware`, and `core/` is the emulator's `vidcard/core` -- the same C the emulator runs
for the card, so the machine and the emulator draw the same pictures. The registers, the drawing
commands and how it all works are in the emulator's
[vidcard/README.md](https://github.com/caiannello/Pugputer6309_Emulator/blob/main/vidcard/README.md)
("On the card" for the hardware side).

**Status (2026-11-07):**
- **Working on the hardware:** booting DOS from the SD card, and every video demo (VIDDEMO,
  VIDTEXT, VIDGFX, VIDTILES).
- **USB keyboards and mice** (TinyUSB host): working on the hardware (VIDMOUSE), each plugged in
  directly; a hub is next. Bus-powered devices need VBUS powered: a jumper from VSYS to VBUS
  (VSYS already comes from the bus through a Schottky diode).
- **Not in yet:** gamepads, and the repeat of a held key.

`vidcard.uf2` here is built and ready to flash.

## Files

| File | |
|---|---|
| `src/config.h` | the pins and clocks |
| `src/main.c` | start-up; core 0's main loop |
| `src/bus.pio`, `src/bus.c` | the bus: reads answered by PIO and DMA from a copy of the registers; every access logged by DMA for core 0's interrupt |
| `src/card.c` | the card between the bus, the drawing commands (a 64KB queue) and the beam; keeps the register copy up to date; puts video memory back after a reset |
| `src/dvi.c` | the picture: HSTX's TMDS encoder, two DMA channels, 8 line buffers; core 1 draws, and core 0 helps when lines run long |
| `src/usbhost.c`, `src/tusb_config.h` | USB host (TinyUSB): boot-protocol keyboards and mice, through a hub |
| `src/bench.c` | (diagnostic builds only, `VIDCARD_DIAG=1`) timings printed on the UART |
| `src/sd.c` | the microSD card in SPI mode (SDSC, SDHC and SDXC) |
| `src/blockdev.c` | the SD interface's registers, on `sd.c` |
| `core/` | the card itself (built here with `VC_ATOMIC_FLAGS`); `vc_font.c` is the font, see `NOTICE.md` |

## Pins

| GPIO | | GPIO | |
|---|---|---|---|
| 32 | /VCS: the GAL's select, low for `$FF80-$FF9F` and `$FFD8-$FFDB`, while E or Q is high | 42-46 | A0-A4 |
| 33 | R/W | 47 | SDCS: the GAL's, high for `$FFD8-$FFDB` |
| 34-41 | D0-D7 | 29 | /VRST: the bus's /RES through a 100K/200K divider; when it falls the card and the SD interface are reset |
| 30 | the IRLML6344's gate (10K to ground): high pulls the bus's /IRQ low | 31 | the level shifters' OE (10K to ground: off the bus until the firmware is running) |
| 12-19 | DVI: D2+ D2- CK+ CK- D1+ D1- D0+ D0- (220 ohm each) | 25 | the board's LED: lit while the SD card is ready, dark while it's busy |
| 8 | the PSRAM's chip select (on the board) | 9-11, 24 | the microSD, SPI1 (on the board) |
| 0-1 | UART0 on the UEXT connector: the firmware's messages, 115200 baud | | |

The card reads A0-A4 and SDCS as one 6-bit register number: 0-31 are the video card's registers,
56-59 the SD card's. /VCS times every access (the card answers a read as it falls and takes a
write's data as it rises, when E falls); the CPU card's /RD and /WR aren't used.

## Building

With VS Code's Raspberry Pi Pico extension (it installs the Pico SDK 2.3.1, the compiler and the
tools): open this folder, let the extension import it as a project, and build. Or by hand, from
this folder (the paths are where the extension puts things):

```
cmake -S . -B build -G Ninja -DPICO_SDK_PATH=%USERPROFILE%/.pico-sdk/sdk/2.3.1 ^
      -DPICO_TOOLCHAIN_PATH=%USERPROFILE%/.pico-sdk/toolchain/15_2_Rel1 ^
      -Dpicotool_DIR=%USERPROFILE%/.pico-sdk/picotool/2.3.1/picotool ^
      -Dpioasm_DIR=%USERPROFILE%/.pico-sdk/tools/2.3.1/pioasm
cmake --build build
```

That makes `build/vidcard.uf2` (and `.elf`, for a debugger). Everything runs from SRAM, copied
from flash at start (the bus interrupt and the picture can't wait on the flash).

## Flashing

Hold the board's BOOT button while plugging its USB into a PC (or while pressing RESET): it shows
up as a drive; copy `vidcard.uf2` onto it, and the board restarts with it. Or
`picotool load -x vidcard.uf2` with the board in BOOTSEL mode.

The board can stay on the card for this, with the Pugputer on or off: VSYS comes from the bus
through a Schottky diode, and the level shifters' 5V side is the bus's VCC, so with the Pugputer
off they're unpowered on that side and keep out of the bus.

A 3.3V serial adapter on the UEXT connector's UART (GPIO0 TX, GPIO1 RX, 115200 baud) shows what
the firmware says at start, e.g.

```
Pugputer 6309 video card: 336 MHz, PSRAM 8192 KB, SD card ready
```

The same line shows at the top of the screen at power-on, until a program resets the card.

## Trying it, step by step

1. **The picture alone:** the board on USB power, a display on the HDMI connector. The card's
   reset screen should show, with the line above at the top.
2. **The SD card alone:** a card in the slot; the LED lights when it has answered, and the UART
   says so.
3. **On the bus:** from the Pugputer's serial console, the BIOS's banner, then DOS's `/> ` prompt
   (booted from the SD card). `B_DQUERY` / BASIC's `SCREEN` find the card; then the demos in
   `/DEMO` (`VIDDEMO`, `VIDGFX`: a line interrupt every 8 lines; the VGM players: the OPL3).

## Limits, measured on the hardware

The system clock is 336MHz at 1.25V (`src/config.h`). A line takes 31.8us, about 10700 cycles.
VIDTILES' page 2 (three tile layers, 128 sprites) looks right with core 0 helping. The CPU's
fastest writes (`TFM`, one every 840ns) set how quickly core 0 must take a register write, so
the data ports take a short, lock-free path.
