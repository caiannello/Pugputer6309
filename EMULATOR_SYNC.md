# Changes the emulator needs

What bringing up the real hardware found that the emulator (`../Pugputer6309_Emulator`) didn't
have. Add to this list whenever a hardware fix or finding touches something the emulator also
has, and tick items off once they're synced.

Started 2026-11-07. It covers everything since the hardware bring-up began on 2026-11-06.

**The shared files are synced by `sync_emulator.py`,** at this repo's root. Each file is copied
from the repo where it's worked on:

- **From the emulator:** the BIOS sources (then the ROM is rebuilt here), and the release SD
  image, which is the emulator's own `mkdiskimg` output.
- **From here:** the video card's core, its firmware and the GAL files.

How to run it:

- `python sync_emulator.py` only reports what differs.
- `--apply` copies. It holds any file with uncommitted edits at the destination, so an edit
  made on the wrong side isn't lost.
- `--apply --force` copies anyway.
- `--build-emulator` rebuilds the emulator first.

This list is for everything else: behaviour, docs and fixes that need thought, not a copy.

**Status, 2026-11-07:** everything ticked below is in the emulator's working tree, but not yet
committed there. Its full build passes, with both test suites (`build_all.bat`). The new
release-style SD image (`mkdiskimg --add-dir demo/programs --sources .`) is copied here as
`Software/6309/sdcard/pugdisk.img`. Compared with the old one, only these differ:

- ASM, LINK and VGMPLAY: their sources and programs;
- VIDLIB, VIDGFX and VIDCARD.TXT;
- the demos that include VIDLIB (MANDEL, VIDGFX, VIDMOUSE, VIDTEXT, VIDTILES).

DOS and the other 67 files are byte-identical.

## 1. The 6309 CPU: LDQ and MULD flags

On a real HD6309, LDQ (every addressing mode, immediate too) and MULD set Z from bits 31-16 of
Q only, the A:B half. LDQ also leaves V unchanged; it doesn't clear it. The emulator used all
32 bits for Z and cleared V. Code that tests Z after LDQ therefore worked in the emulator and
failed on the real machine. Source: the 6809Decoder wiki's
[Undocumented 6309 Behaviours](https://github.com/hoglet67/6809Decoder/wiki/Undocumented-6309-Behaviours).

- [x] **The CPU model.**
  - `simulator/src/hd6309_opcodes.cpp`, LDQ in every mode (`$CD`, `$10DC`, `$10EC`, `$10FC`).
  - `simulator/src/hd6309_core.cpp`, `do_muld`.
  - The test `ldq_and_muld_set_z_from_the_high_word_only` in `test_native6309.cpp`.
- [x] **The assembler and linker.** Each place now tests D and W itself, for example
  `LDD x` / `ORD x+2`:
  - `asmlink/pa_expr.asm`: `AO_DIVIDE` (division by zero) and `AO_TRUTH`.
  - `asmlink/pa_insn.asm`: `IR_VAL` (an indexed operand's zero offset).
  - `asmlink/pa_dir.asm`: `IFC_KNOWN` (`IFEQ`/`IFNE`/`IFGT`/... of a value under $10000).
  - `asmlink/link.asm`: `AP_DIV`, `AP_MOD` and `AP_TRUTH`.

  This is what made ASM fail on the real machine. It gave "Division by zero" for any `/n` with n
  under $10000, then knock-on "Byte overflow" errors (BASICCOM.ASM). EDIT.ASM's one error came
  from DEFINES.D's `/512`. The IF directives were found once the emulator modelled the chip: the
  test that compares ASM's output with lwasm's caught them.
- [x] **`demo/programs/ASM/VGM/VGMPLAY.ASM`:** the clock checks, and `PB_LOOP`, which on the real
  machine read a data block shorter than 64 KB as commands.
- [x] **Rebuilt:** ASM.COM, LINK.COM and the disk images.
- **The check.** A scan of both repos finds no other LDQ or MULD whose flags reach a branch or a
  `PSHS CC`. The scan is kept in the emulator:
  `python simulator/tools/check_ldq_flags.py [folder ...]`. It prints nothing and exits 0 when
  clean, and on the unfixed sources it finds all 12 places. Run it again on new 6309 code, this
  repo's `Software/` too.

## 2. The video card's core (`vidcard/core/vc.c`, `vc.h`)

The source of truth is `Software/RP2350/video_misc/core/` here. The emulator's copy was
identical to this repo's before the bring-up, so copying it over lost nothing.

- [x] Copied (with the emulator's LF line endings):
  - **The faster renderer.** A cell, tile or byte at a time; pair tables for 4-bit sprites; a
    sprite table decoded into bands of 32 lines. It draws exactly the old picture.
  - **`vc_render_line_with()`**, with per-caller caches. `vc_render_line()` keeps a static cache,
    for the emulator's single thread.
  - **`vc_card.pal_gen`/`spr_gen`** (change counters), `vc_reset_bytes()`, and
    `VC_ATOMIC_FLAGS` (off in the emulator).
- [x] The emulator's video tests pass unchanged.

## 3. The video card's firmware (`vidcard/firmware/`)

- [x] **`src/` and `CMakeLists.txt` copied from `Software/RP2350/video_misc`.** The only
  difference is that CORE is `../core` there. Built from the emulator's tree, it gives a UF2
  byte-identical to this repo's `vidcard.uf2`.
- [x] Its README's status and file table updated. It now says this repo is where the firmware is
  worked on.
- [ ] **Undecided:** keep mirroring it, or replace the copy with a pointer to this repo.

## 4. The GAL (`vidcard/hardware/VIDCARD.PLD`)

- [x] Revision 02 copied, along with `VIDCARD.jed`. SDCS comes from the address alone; qualified
  with /IO, the card sometimes took an SD access for a video register's.

## 5. The video card's README (`vidcard/README.md`)

- [x] **"On the card":** why SD-select is no longer qualified with /IO.
- [x] **"Serving the bus":**
  - the data ports' short path;
  - sampling 44 ns after /CS falls;
  - the 64 KB queue, and that a program must watch "queue full";
  - a reset's immediate registers and the lazy restore of video memory.
- [x] **"Drawing the picture":** 8 line buffers, core 0 helping, and the caches.
- [x] **New "Clocks":** 336 MHz, HSTX from the retuned USB PLL, and the bus PIO divided back to
  252 MHz.
- [x] **"Mouse and keyboard":** in the firmware now. VBUS needs the bus's 5 V; key repeat and
  gamepads are still to come.
- [x] **"Limits, measured on the hardware"**, replacing "to confirm".

## 6. Demos

- [x] **VIDGFX's extra blinking half-spinner.** The spinner's second buffer moved from $14800 to
  $15400, in `vidcard/tools/vidgfx.template` and `make_vidgfx.py`, then VIDGFX.ASM was
  regenerated. A bitmap layer has no height, so the 240 rows under the buffer shown must be
  blank.
- [x] **The command queue.** `VIDLIB.ASM`'s `SENDCMD`, which every video demo uses, sends 64
  bytes at a time and waits while `STATUS` says "queue full". VIDGFX's page 1 sends about
  5.2 KB at once.

## 7. The video card's command queue, in the emulator

The emulator ran every drawing command the moment its last byte arrived, so `STATUS` was never
busy for long and never full. On the card the queue holds 64 KB, says full with 64 bytes or
fewer left, and loses bytes sent while full. Commands take real time: about 200 ns a pixel
(measured below), so a 320x240 CLEAR takes about 16 ms. A program that doesn't wait for
"busy" before reading or reusing video memory works in an instant emulator and goes wrong on
the hardware.

- [x] **The core counts each command's work** in `vc_card.work`: pixels, or bytes COPYed or
  FILLed. BLIT and CHAR count every pixel they look at.
- [x] **Measured on the hardware,** with the diag27 firmware, over VIDGFX (both pages), MANDEL
  and VIDDEMO:
  - about 0.45 us for any command;
  - about 180-250 ns a pixel drawn;
  - 188 ns a byte COPYed and 113 ns a byte FILLed;
  - 613 ns a pixel for BLIT from the PSRAM, and 97 ns a pixel for CHAR;
  - CLEAR up to 74 ms (640x480).

  The main loop's other work between batches is small: a mean of 3.6 us, at most 31 us.
- [x] **The emulator's `VideoDevice`** (`simulator/src/pugputer/video_device.cpp`):
  - a 64 KB queue: full at 64 left, and bytes lost when it's full;
  - each command takes its measured time (`command_cycles`), and the next one waits;
  - STATUS is busy while anything is queued or running;
  - CMDDONE comes at a command's end;
  - a reset drops the queue.

  A command's pixels are all there from its start, where the card's appear as it draws.
  `set_instant_commands(true)` gives the old behaviour, for tests.
- [x] **Tests:** `vidcard_device_commands_take_the_cards_time`, and
  `..._command_queue_fills_loses_and_is_dropped_by_a_reset`.
- [x] **What it found:**
  - **BASIC never waited for the card.** A `VPOKE` straight after a `GCLS` would land first
    and be cleared. Now `VCSET`, which every data-port statement goes through (VPOKE, VPEEK,
    PALETTE, SPRITE, TPRINT, SCREEN), waits until the drawing sent before it is done.
  - **The BASIC video and TILEKIT tests** checked the screen the moment a line or key was done.
    They now let the card finish drawing first, as a person would see it.
  - **TILEKIT already waits** (`WAITCMD`) before reusing memory a command may still read.
- [ ] Optional: audit TILEKIT and the demos for data-port accesses that don't wait.
- [ ] BASIC doesn't watch "queue full". Filling it would take something like a minute of
  `GCLS` in a tight loop (one byte each, 16 ms each to draw), so it's left as is.

## 8. Compatibility, next (suggestions)

- [ ] Check the CPU against the rest of the 6809Decoder wiki's "Undocumented 6309 Behaviours":
  - DAA's V;
  - H being left alone by ASL, ASR, CMP, NEG, SBC and SUB;
  - DIVD's and DIVQ's N after an overflow or a divide by zero;
  - TFM's Z when it ends abnormally;
  - MULD's extra 2 cycles for negative operands.
- [ ] The CPU card's 16 Hz NMI clock tick isn't emulated (the simulator README says so).

## Hardware-only notes (no emulator change; kept here for context)

- The OPL3 module puts out only about 50 mV p-p while a note plays. It's being looked at as an
  analog problem; the digital side works (timer test 0 → 192).
- About 4 data-port reads in 4096 still come back stale right after a reset.

## Still to do in this repo (not the emulator)

- Firmware: key repeat for USB keyboards (the emulator's README promises it).
- Firmware: gamepads (needs HID report-descriptor parsing).
- Test USB on the hardware. VBUS needs 5 V from the bus through a Schottky diode.
