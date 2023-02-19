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
just two-open-drain signal lines, clock and data, similar to I2C. 
It's easy to interface PS/2 to even the most minimal microcontroller.
```
