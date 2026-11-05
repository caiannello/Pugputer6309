# Credits and third-party notices

The firmware and `core/` come from the
[Pugputer6309_Emulator](https://github.com/caiannello/Pugputer6309_Emulator) (MIT License,
Copyright (c) 2026 Craig Iannello).

## VileR -- The Ultimate Oldschool PC Font Pack

The video card's font (`core/vc_font.c`) is **ToshibaSat 8x16**, the code page 437 text font of
Toshiba's Satellite laptops, as recreated by **VileR** in **The Ultimate Oldschool PC Font Pack**
(<https://int10h.org/oldschool-pc-fonts/>), (c) 2016-2020 VileR. It is converted, unchanged, from
the pack's `Px437_ToshibaSat_8x16.ttf` into a table of bytes (by the emulator's
`vidcard/tools/font2c.py`), and is used under the **Creative Commons Attribution-ShareAlike 4.0
International License** (<https://creativecommons.org/licenses/by-sa/4.0/>). That license covers
the font alone: if you change the font and share it, share your version under the same license.

## Raspberry Pi -- Pico SDK

The firmware is built with the **Raspberry Pi Pico SDK** (BSD 3-Clause License), which is not
included here; `vidcard.uf2` contains parts of it.
