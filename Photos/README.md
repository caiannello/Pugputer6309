![kb wedge](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Prototype_feb_2023.jpg)

```
The keyboard shown in the model can be found here:
https://smile.amazon.com/dp/B08B84VPN9

It is USB, so to use it with my project, I either have to use a 
microcontroller like Teensy, which has a USB host port, maybe find
some kind of adaptor, or I have to take the KB apart, hack out the 
electronics, and wire up the matrix directly. I am leaning towards
using the Teensy for the time being, and the included Teensy source
shows keypresses from connected USB keyboards.

A much easier way is to get a keyboard that has a PS/2 interface. That has
just two-open-drain signal lines, clock and data, similar to i2c. 
It's easy to interface PS/2 KB's to even the most minimal 
microcontrollers.
```
![backplane v2](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/backplane_v2.jpg)
![bottom](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/wedge_kb_bot.png)
![basic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Extended%20BASIC%20on%20VDP.jpg)
![mana](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Squaresoft%20Tilemap%20Seiken%20Densetsu%203.jpg)
![mandelbrot](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Mandelbrot%20Demo.jpg)
![pugmon](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Photos/Pugmon%20on%20both%20VDP%20and%20UART.jpg)
