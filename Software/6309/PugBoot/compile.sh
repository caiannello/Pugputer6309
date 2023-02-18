#!/bin/sh

../../lwtools-4.20/lwasm/lwasm string.asm --format=obj --output=string.o --list=string.lst
../../lwtools-4.20/lwasm/lwasm serio.asm --format=obj --output=serio.o --list=serio.lst
../../lwtools-4.20/lwasm/lwasm pario.asm --format=obj --output=pario.o --list=pario.lst
../../lwtools-4.20/lwasm/lwasm conio.asm --format=obj --output=conio.o --list=conio.lst
../../lwtools-4.20/lwasm/lwasm file.asm --format=obj --output=file.o --list=file.lst
../../lwtools-4.20/lwasm/lwasm main.asm  --format=obj --output=main.o  --list=main.lst

../../lwtools-4.20/lwlink/lwlink --format=srec --output=pugboot.s19 --map=pugboot.map --script=linker_script string.o serio.o pario.o conio.o file.o main.o 
srec_cat pugboot.s19 -Motorola -o pugboot.hex -Intel
