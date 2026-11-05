@echo off
rem Deletes what compile.bat makes, except the ROM images (pugbios.s19, .hex and
rem pugbios_rom.bin), which are kept in the repository ready to burn.
cd /d "%~dp0"
del /q *.lst 2>nul
del /q *.map 2>nul
del /q *.o 2>nul
