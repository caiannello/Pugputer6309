#!/bin/sh
# Deletes what compile.sh makes, except the ROM images (pugbios.s19, .hex and
# pugbios_rom.bin), which are kept in the repository ready to burn.
cd "$(dirname "$0")" || exit 1
rm -f *.lst *.map *.o
