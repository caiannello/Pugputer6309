#!/bin/sh
../../../bin/tools/lwtools-4.20/lwasm/lwasm mana_tilemap.asm --format=ihex --output=mana_tilemap.hex --map=mana_tilemap.map --list=mana_tilemap.list
../../../bin/tools/lwtools-4.20/lwasm/lwasm mandelbrot.asm --format=ihex --output=mandelbrot.hex --map=mandelbrot.map --list=mandelbrot.list
