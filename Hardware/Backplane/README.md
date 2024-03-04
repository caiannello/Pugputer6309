## Backplane v2
```
This is a backplane for use with Pugputer v2, based on card edge-connectors
instead of pin headers. It is 3.7" x 3.5".

The connectors are 0.1" pitch, 60-pins, which I think is the same as the
cartridge slot on the original Nintendo Famicom.

Because this connector is not keyed in any way, cards could be inserted
backwards, which would definitely be bad! For this reason, alignment marks
indicating Pin 1 are printed at Pin 1 on each slot as well as the cards
that plug into them.

The slots are spaced at 0.7", which is plenty of clearance for all currently
designed cards. If one card is taller than this, it can be placed in the
rightmost slot.

This backplane will cause the system to have a brick-like form factor
rather than the flattened all-in-one-keyboard design of v0, but the PCB
fabrication cost will be much cheaper since the layer count is halved.

If there is interest in keeping the design flat, I'm thinking of making a
backplane with right-angle card-edge connectors, but again, it might be
much more expensive to make.
```
![layout](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Backplane/Backplane%20Layout.png)

![schematic](https://raw.githubusercontent.com/caiannello/Pugputer6309/main/Hardware/Backplane/Backplane%20Schematic.png)
