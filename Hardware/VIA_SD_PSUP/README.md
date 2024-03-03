## Power, SD Card, GPIO
```
This card contains a W65C22 Versatile Interface Adaptor (VIA) which has some
timers, two 8-bit GPIO ports (PORTA and PORTB), and some handshaking lines.
PORTB is run through level-shifters to connect to an ATMEGA328P MCU which
provides SPI, I2C, SPI SD Card, and misc analog/digital IO. Several of these
signals are brought out to a pin header which should allow connecting various
game controllers, sensors, PS/2 keyboards/mice, etc.

PORTA and its handshake lines are brought out to a separate pin header as
a ready-to-use parallel port.

This board also has a barrel connector for supplying 12VDC to the system,
as well as voltage regulators to supply 5V and 3.3V to the system.
```
![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/VIA_SD_PSUP/Layout.png)

![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/VIA_SD_PSUP/Schematic.png)
