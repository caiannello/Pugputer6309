#!/bin/sh

../../../bin/tools/lwtools-4.20/lwasm/lwasm helpers.asm --format=obj --output=helpers.o --list=helpers.lst
../../../bin/tools/lwtools-4.20/lwasm/lwasm serio.asm --format=obj --output=serio.o --list=serio.lst
../../../bin/tools/lwtools-4.20/lwasm/lwasm mon.asm --format=obj --output=mon.o --list=mon.lst
../../../bin/tools/lwtools-4.20/lwasm/lwasm time.asm --format=obj --output=time.o --list=time.lst
../../../bin/tools/lwtools-4.20/lwasm/lwasm main.asm  --format=obj --output=main.o  --list=main.lst

../../../bin/tools/lwtools-4.20/lwlink/lwlink --format=srec --output=pugboot.s19 --map=pugboot.map --script=linker_script helpers.o serio.o mon.o time.o main.o 
srec_cat pugboot.s19 -Motorola -o pugboot.hex -Intel
