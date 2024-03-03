## Power, SD Card, GPIO
```
This card contains a W65C22 Versatile Interface Adaptor (VIA) which has some
timers, two 8-bit GPIO ports (PORTA and PORTB), and some handshaking lines.
PORTB is run through a voltage level-shifter to connect an SD Card interface
in slow (SPI) mode.
```
The SD card connections are based on work done in the awesome [Steckschwein project](https://www.steckschwein.de/hardware/).
```
PORTA is currently unused, but will be either brought out to an expansion header
or used to interface with a keyboard matrix and game controllers.

This board also has a barrel connector for supplying 12VDC to the system,
as well as voltage regulators to supply 5V and 3.3V to the system.
```
![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/VIA_SD_PSUP/Layout.png)

![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/VIA_SD_PSUP/Schematic.png)
