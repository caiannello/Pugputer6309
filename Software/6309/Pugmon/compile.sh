#!/bin/sh
#../../lwtools-4.17/lwasm/lwasm main.asm --format=ihex --output=pugmon.hex --map=pugmon.map --list=pugmon.lst

../../lwtools-4.20/lwasm/lwasm serio.asm --format=obj --output=serio.o --list=serio.lst
../../lwtools-4.20/lwasm/lwasm pario.asm --format=obj --output=pario.o --list=pario.lst
../../lwtools-4.20/lwasm/lwasm vidio.asm --format=obj --output=vidio.o --list=vidio.lst
../../lwtools-4.20/lwasm/lwasm conio.asm --format=obj --output=conio.o --list=conio.lst
../../lwtools-4.20/lwasm/lwasm main.asm  --format=obj --output=main.o  --list=main.lst

../../lwtools-4.20/lwlink/lwlink --format=srec --output=pugmon.s19 --map=pugmon.map --script=linker_script serio.o pario.o vidio.o conio.o main.o 
srec_cat pugmon.s19 -Motorola -o pugmon.hex -Intel
