#!/bin/sh

../../../bin/tools/lwtools-4.20/lwasm/lwasm serio.asm --format=obj --output=serio.o --list=serio.lst
../../../bin/tools/lwtools-4.20/lwasm/lwasm pario.asm --format=obj --output=pario.o --list=pario.lst
../../../bin/tools/lwtools-4.20/lwasm/lwasm vidio.asm --format=obj --output=vidio.o --list=vidio.lst
../../../bin/tools/lwtools-4.20/lwasm/lwasm conio.asm --format=obj --output=conio.o --list=conio.lst
../../../bin/tools/lwtools-4.20/lwasm/lwasm main.asm  --format=obj --output=main.o  --list=main.lst

../../../bin/tools/lwtools-4.20/lwlink/lwlink --format=srec --output=pugmon.s19 --map=pugmon.map --script=linker_script serio.o pario.o vidio.o conio.o main.o 
srec_cat pugmon.s19 -Motorola -o pugmon.hex -Intel


