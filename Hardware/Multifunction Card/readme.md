# RASPBERRY PI PICO VERSION
(There's no firmware for this model yet.)

![Pico Schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Multifunction%20Card/pico_schematic.png)
![Pico Layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Multifunction%20Card/pico_layout.png)

# TEENSY VERSION
```
Currently in breadboard stange. It consists of the LV parallel 
interface card, available in the repo, connected to a 
Teensy 4.1 and sound board.

The Teensy 4.1 is connected to a parallel interface card with the 
following connections:

Parallel Card       Teensy Pin
-------------       ----------
VCC                 None
GND                 GND
+3V3                3v

CWR                 2
CRD                 3
UWR                 4
URD                 5

DB0                 28
DB1                 29
DB2                 30
DB3                 31
DB4                 32
DB5                 33
DB6                 34
DB7                 35

The partial firmware for the Teensy is an Arduino sketch provided
in /Software/Teensy 4.1/multipass

For information about the parallel interface signals and protocol,
see the README in the LV Parallel IO Card's directory.

```

