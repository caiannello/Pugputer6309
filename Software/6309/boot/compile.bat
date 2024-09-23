..\..\bin\lwasm vdp.asm --format=obj --output=vdp.o --list=vdp.lst
..\..\bin\lwasm helpers.asm --format=obj --output=helpers.o --list=helpers.lst
..\..\bin\lwasm serio.asm --format=obj --output=serio.o --list=serio.lst
..\..\bin\lwasm mon.asm --format=obj --output=mon.o --list=mon.lst
..\..\bin\lwasm time.asm --format=obj --output=time.o --list=time.lst
..\..\bin\lwasm main.asm  --format=obj --output=main.o  --list=main.lst

..\..\bin\lwlink --format=srec --output=pugboot.s19 --map=pugboot.map --script=linker_script vdp.o helpers.o serio.o mon.o time.o main.o 
..\..\bin\srec_cat.exe pugboot.s19 -o pugboot.hex -Intel