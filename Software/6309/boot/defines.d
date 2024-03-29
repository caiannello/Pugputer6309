; -----------------------------------------------------------------------------
; IO DEVICE BASE ADDRESSES
; -----------------------------------------------------------------------------

BANK_BASE   equ  $FFEC      : ffec - ffef: Memory Bank Regs 0...3 (Built-in)
ACIA_BASE   equ  $FFE8      ; ffe8 - ffeb: Serial UART R65C51P2 (Built-in)
VDP_BASE    equ  $FFE4      ; ffe4 - ffe7: Video Chip V9958
OPL3_BASE   equ  $FFE0      ; ffe0 - ffe3: Music Chip YMF262 (OPL3)
VIA_BASE    equ  $FFB0      ; ffb0 - ffbf: W65C22 VIA (SD Card, SPI, KB, GPIO)

; UART registers (Base IO address is in defines.d)

UT_DAT      equ  ACIA_BASE+0  ; R65C51P2 UART DATA REGISTER (RD: RX, WR: TX)
UT_STA      equ  ACIA_BASE+1  ; READ: UART STATUS REG, WRITE: UART RESET
UT_CMD      equ  ACIA_BASE+2  ; COMMAND REG (IRQ ENABLE FOR TX/RX)
UT_CTL      equ  ACIA_BASE+3  ; CONTROL REG (COMMS SETTINGS)

SBUFSZ      equ  $7E        ; SIZE OF THE SERIAL INPUT / OUTPUT BUFFERS
SUARTCTL    equ  $1F        ; %0001 1111 = 19200 BAUD,
                            ;              EXTERNAL RECEIVER CLOCK,
                            ;              8 DATA BITS,
                            ;              1 STOP BIT.
SUARTCMD    equ  $09        ; %0000 1001 = ODD PARITY CHECK, BUT
                            ;              PARITY CHECK DISABLED.
                            ;              NORMAL RECEIVER MODE, NO ECHO.
                            ;              RTSB LOW, TX INTERRUPT DISABLED.
                            ;              IRQB RX INTERRUPT ENABLED.
                            ;              DATA TERMINAL READY, DTRB LOW.

; -----------------------------------------------------------------------------
; Built-in file reference numbers
; -----------------------------------------------------------------------------
F_NULL      equ  $00        ; NULL file
F_STDOUT    equ  $01        ; Standard text output
F_STDIN     equ  $02
F_STDERR    equ  $03        ; Standard error text output

; filerefs reserved for devices usable with console

F_UART      equ  $04        ; Optionally directed to stdout and/or stdin
F_VDP       equ  $05        ; Qptionally directed to stdout
F_VIA_KB    equ  $06        ; Optionally directed to stdin
; -----------------------------------------------------------------------------
; BIOS Functions - function type codes passed in reg A when doing a BIOS call.
; -----------------------------------------------------------------------------
B_DQUERY    equ  $00        ; Get info about devices connected to the system
B_REG_DEV   equ  $01        ; Register a device with the BIOS
B_DEREG_DEV equ  $02        ; De-register a device with the bios
B_FSTAT     equ  $03        ; Get info about a device or file
B_FDIR      equ  $04        ; Get a file directory
B_FOPEN     equ  $05        ; B: Device ref, E: flags (returns fileref or null in A, status in B)
B_FCLOSE    equ  $06        ; B: fileref (returns status in A)
B_FDELETE   equ  $07        ; Delete a file
B_FMOVE     equ  $08        ; Move or rename a file
B_PUTC      equ  $09        ; B: Output fileref, E: The char
B_PUTS      equ  $0A        ; B: Output fileref, X: adrs of null-terminated string
B_PUT       equ  $0B        ; B: Output fileref, X: adrs of bytes, Y: len
B_GETC      equ  $0C        ; B: Input fileref (rets char in A, or carry-set if None)
B_GETS      equ  $0D        ; B: Input fileref, X: buffer adrs, Y: buffer len. Returns strlen in X.
B_GET       equ  $0E        ; B: Input fileref, X: buffer adrs, Y: req. len. Returns getlen in X.
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
; Structure definitions
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; 16-byte circular buffer
; -----------------------------------------------------------------------------
circbuf     STRUCT          
flags       rmb  1          ; flags (1: empty, 2: full, 4: overrun, 8: underrun)
len         rmb  1          ; num of bytes in buf
head        rmb  1          ; head (write index)
tail        rmb  1          ; tail (read idx)
buf         rmb  16         ; buffer
            ENDS
; -----------------------------------------------------------------------------
; Doubly linked lists may someday be used to keep track of IO devices so they
; can more easilly be removed from the system.
; -----------------------------------------------------------------------------
dl_node     STRUCT          ; doubly-linked list node
prev        rmw  1          ; pointer to prev node, or NULL if none
next        rmw  1          ; pointer to next node, or NULL if none
member      rmw  1          ; pointer to member, or NULL if none
    ENDS
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
