@echo off
rem Builds the BIOS: pugbios.s19 (S-records at the CPU's addresses, $F000-$FFFF),
rem pugbios.hex (the same ROM part, Intel hex) and pugbios_rom.bin (the whole 32K ROM chip, with the
rem BIOS at $7000-$7FFF, where the CPU card's $F000-$FFFF reads it; the rest is $FF).
rem (pugbios.s19 also has the BIOS's initial direct-page RAM at $0000-$005F, which isn't ROM:
rem the .hex and .bin are cropped to $F000-$FFFF.)
rem
rem The tools: LWTOOLS 4.20's lwasm and lwlink, and SRecord's srec_cat -- from ..\..\bin if
rem they're there, else from the PATH (or set LWASM, LWLINK and SRECCAT yourself).
setlocal
cd /d "%~dp0"
set "BIN=%~dp0..\..\bin"
if not defined LWASM if exist "%BIN%\lwasm.exe" set "LWASM=%BIN%\lwasm.exe"
if not defined LWLINK if exist "%BIN%\lwlink.exe" set "LWLINK=%BIN%\lwlink.exe"
if not defined SRECCAT if exist "%BIN%\srec_cat.exe" set "SRECCAT=%BIN%\srec_cat.exe"
if not defined LWASM set "LWASM=lwasm"
if not defined LWLINK set "LWLINK=lwlink"
if not defined SRECCAT set "SRECCAT=srec_cat"

"%LWASM%" helpers.asm --6309 --format=obj --output=helpers.o --list=helpers.lst || exit /b 1
"%LWASM%" devio.asm   --6309 --format=obj --output=devio.o   --list=devio.lst   || exit /b 1
"%LWASM%" serio.asm   --6309 --format=obj --output=serio.o   --list=serio.lst   || exit /b 1
"%LWASM%" sdcard.asm  --6309 --format=obj --output=sdcard.o  --list=sdcard.lst  || exit /b 1
"%LWASM%" time.asm    --6309 --format=obj --output=time.o    --list=time.lst    || exit /b 1
"%LWASM%" loader.asm  --6309 --format=obj --output=loader.o  --list=loader.lst  || exit /b 1
"%LWASM%" banks.asm   --6309 --format=obj --output=banks.o   --list=banks.lst   || exit /b 1
"%LWASM%" main.asm    --6309 --format=obj --output=main.o    --list=main.lst    || exit /b 1

rem main.o must be linked LAST: its bss (the system stack) must be the last thing placed, so
rem EndOfVars is the true end of the BIOS's RAM.
"%LWLINK%" --format=srec --output=pugbios.s19 --map=pugbios.map --script=linker_script helpers.o devio.o serio.o sdcard.o time.o loader.o banks.o main.o || exit /b 1

"%SRECCAT%" pugbios.s19 -Motorola -crop 0xF000 0x10000 -o pugbios.hex -Intel || exit /b 1
"%SRECCAT%" pugbios.s19 -Motorola -crop 0xF000 0x10000 -offset -0x8000 -fill 0xFF 0x0000 0x8000 -o pugbios_rom.bin -Binary || exit /b 1
echo Built pugbios.s19, pugbios.hex and pugbios_rom.bin.
exit /b 0
