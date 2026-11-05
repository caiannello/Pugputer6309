#!/bin/sh
# Builds the BIOS: pugbios.s19 (S-records at the CPU's addresses, $F000-$FFFF),
# pugbios.hex (the same ROM part, Intel hex) and pugbios_rom.bin (the whole 32K ROM chip, with the
# BIOS at $7000-$7FFF, where the CPU card's $F000-$FFFF reads it; the rest is $FF).
# (pugbios.s19 also has the BIOS's initial direct-page RAM at $0000-$005F, which isn't ROM:
# the .hex and .bin are cropped to $F000-$FFFF.)
#
# The tools: LWTOOLS 4.20's lwasm and lwlink, and SRecord's srec_cat, from the PATH (or set
# LWASM, LWLINK and SRECCAT yourself).
cd "$(dirname "$0")" || exit 1
LWASM=${LWASM:-lwasm}
LWLINK=${LWLINK:-lwlink}
SRECCAT=${SRECCAT:-srec_cat}

for m in helpers devio serio sdcard time loader banks main; do
    "$LWASM" $m.asm --6309 --format=obj --output=$m.o --list=$m.lst || exit 1
done

# main.o must be linked LAST: its bss (the system stack) must be the last thing placed, so
# EndOfVars is the true end of the BIOS's RAM.
"$LWLINK" --format=srec --output=pugbios.s19 --map=pugbios.map --script=linker_script \
    helpers.o devio.o serio.o sdcard.o time.o loader.o banks.o main.o || exit 1

"$SRECCAT" pugbios.s19 -Motorola -crop 0xF000 0x10000 -o pugbios.hex -Intel || exit 1
"$SRECCAT" pugbios.s19 -Motorola -crop 0xF000 0x10000 -offset -0x8000 -fill 0xFF 0x0000 0x8000 -o pugbios_rom.bin -Binary || exit 1
echo "Built pugbios.s19, pugbios.hex and pugbios_rom.bin."
