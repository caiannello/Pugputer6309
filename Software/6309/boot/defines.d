; -----------------------------------------------------------------------------
; BIOS Functions - function type codes passed in reg A when doing a BIOS call.
;
; Built-in file reference numbers:  0: NULL, 1:StdOut, 2:StdErr, 3-7: Reserved
; 
;
; -----------------------------------------------------------------------------
B_QUERY     equ  $00        ; fills out a structure of IO devices and open filerefs

B_OPEN      equ  $01        ; B: Device ref, E: flags (returns fileref or null in A, status in B)
B_CLOSE     equ  $02        ; B: fileref (returns status in A)

B_PUTC      equ  $10        ; B: Output fileref, E: The char
B_PUTS      equ  $11        ; B: Output fileref, Y: adrs of null-terminated string
B_PUT       equ  $12        ; B: Output fileref, X: adrs of bytes, Y: len

B_GETC      equ  $20        ; B: Input fileref (rets char in A, or carry-set if None)
B_GETS      equ  $21        ; B: Input fileref, X: buffer adrs, Y: buffer len. Returns strlen in X.
B_GET       equ  $22        ; B: Input fileref, X: buffer adrs, Y: req. len. Returns getlen in X.


; -----------------------------------------------------------------------------
; DEVICE ADDRESSES
; -----------------------------------------------------------------------------

; Serial

UT_DAT      equ  $F000      ; R65C51P2 UART DATA REGISTER (RD: RX, WR: TX)
UT_STA      equ  $F001      ; READ: UART STATUS REG, WRITE: UART RESET
UT_CMD      equ  $F002      ; COMMAND REG (IRQ ENABLE FOR TX/RX)
UT_CTL      equ  $F003      ; CONTROL REG (COMMS SETTINGS)

; -----------------------------------------------------------------------------
; MISC CONSTANTS
; -----------------------------------------------------------------------------

ESCAPE      equ  $1B        ; ASCII CODE FOR ESCAPE
LF          equ  $0A        ; LINE FEED
CR          equ  $0D        ; CARRIAGE RETURN
SPACE       equ  $20        
TILDE       equ  $7E

ESC_CTDN    equ   $40       ; countdown to await an ansi sequence
ESC_N       equ   $50       ; waitloop iterations per timeout tick
; -----------------------------------------------------------------------------
; ConDriver structure
;
; Devices usable as a console device (usable by conio.asm) are registered 
; using one of these structs. This strategy will hopefully eliminate the need
; for any device-specific stuff in the console driver by providing a uniform
; API for each device.
;
; The structure contains some function pointers and property fields for 
; common operations that a console might want to do with a device.
;
; Currently, there are two console-capable devices: the serial port (serio),
; and the video display processor (vidio). When their init functions are 
; called, and if init is successful, they build a ConDriver struct and then 
; register themselves with conio by calling con_register, passing the address 
; of the struct in X. 
;
; I expect the UART to be a standard feature which is always available as a 
; console while using Pugmon. The VDP driver will only register with conio
; if the video card is detected.
;
; Something I'm still noodling over is how to implement a driver for a 
; dedicated keyboard, for use when the VDP is the console of choice. I'm
; thinking of hanging one off the MCU thats handling SD card and is connected 
; via the parallel interface. I think there might need to be a reference to 
; it in the condriver struct for the VDP device?
;
; -----------------------------------------------------------------------------
ConDriver STRUCT
; property fields
bitfield    rmb  1          ; bit definitions below, in bf_* equates
; function pointers
chars_in    rmw  1          ; returns in reg A the num of keypresses waiting
getc        rmw  1          ; returns in reg A the latest keypress
putc        rmw  1          ; char in reg A output to device
cls         rmw  1          ; clear device screen and set cursor to 0,0
home        rmw  1          ; set cursor pos to 0,0
linehome    rmw  1          ; set cursor to beginnning of current line
gotoxy      rmw  1          ; set cursor x,y from regs A,B
cleareoln   rmw  1          ; clears any line text to the right of cursor
    ENDS
; -----------------------------------------------------------------------------
; meanings of bitfield bits in above driver struct
bf_enable   equ  1          ; bit 0: 1: device used by console  0: skipped
bf_cursor   equ  2          ; bit 1: 1: cursor visible          0: hidden
bf_insert   equ  4          ; bit 2: 1: text insert             0: overwrite
; -----------------------------------------------------------------------------
; END OF DEFINES.H
; -----------------------------------------------------------------------------
