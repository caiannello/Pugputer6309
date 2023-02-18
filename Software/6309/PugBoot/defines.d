; -----------------------------------------------------------------------------
; DEVICE ADDRESSES
; -----------------------------------------------------------------------------

; Serial

UT_DAT      equ  $F000      ; R65C51P2 UART DATA REGISTER (RD: RX, WR: TX)
UT_STA      equ  $F001      ; READ: UART STATUS REG, WRITE: UART RESET
UT_CMD      equ  $F002      ; COMMAND REG (IRQ ENABLE FOR TX/RX)
UT_CTL      equ  $F003      ; CONTROL REG (COMMS SETTINGS)

; Parallel

PA_DAT      equ  $F200      ; PARALLEL I/O CARD DATA R/W

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
; PER-MODULE DEFINITIONS
; -----------------------------------------------------------------------------

; CONSOLE (conio.asm) ---------------------------------------------------------

CON_COLS    equ  80         ; Console text dimensions. The same size is used
CON_ROWS    equ  26         ; for both the VDP and UART console screens. They
							; share a common backing buffer.
CON_LINE_MAX_CHARS 	equ 255 ; max line input size in chars
CON_SCREEN_SIZE   	equ (CON_COLS*CON_ROWS)
CON_BUF_SIZE		equ (CON_SCREEN_SIZE+CON_LINE_MAX_CHARS)

; SERIAL PORT (serio.asm) -----------------------------------------------------

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

; PARALLEL PORT (pario.asm) ---------------------------------------------------

PBUFSZ      equ  528        ; SIZE OF THE PARALLEL INPUT / OUTPUT BUFFERS
							; PROTOCOL: A5, 5A, U8 MSG_TYPE, U16 BYTE_CNT, 
							; U8 PAYLOAD[], U16 CRC16.
							; MAX PAYLOAD SIZE IS 516 BYTES, USED IN FILE
							; TRANSFERS: 4-BYTE FILE IDX, 512-BYTE DATA.

; MESSAGE TYPES

; These are for talking to an MCU connected to the parallel port to provide
; SD Card, keyboard, audio, etc. For example Arduino sketches, See repo, 
; "Software/Arduino UNO" or "Software/Teensy 4.1" 

                               ; $00 - $0f : General messages -----------------

PAR_MSG_ACK           EQU $00  ; Acknowledge
PAR_MSG_NAK           EQU $01  ; Can't acknowledge (CRC error?)
PAR_MSG_NCOMP         EQU $02  ; Can't comply (Optional reason text in 
                               ; payload.)
PAR_MSG_STATUS        EQU $03  ; Returns current t_status struct

                               ; $10 - $1f : SD Card messages -----------------

PAR_MSG_GET_DIR       EQU $10  ; Send current or specified dir
PAR_MSG_CH_DIR        EQU $11  ; Change to specified dir or '..'
PAR_MSG_MAKE_DIR      EQU $12  ; Create specified dir
PAR_MSG_GET_FILE      EQU $13  ; Transmit specified file from SD
PAR_MSG_PUT_FILE      EQU $14  ; Receive specified file to SD
PAR_MSG_DEL           EQU $15  ; Delete specified file or directory
PAR_MSG_DUMP          EQU $16  ; Used during file / dir transfer.
                               ; Each data payload starts with a
                               ; uint32_t file byte-index.
PAR_MSG_DUMP_END      EQU $17  ; Same as DUMP, but last part of file.

                               ; $20 - $2f : Keyboard messages ----------------

PAR_MSG_KEYS_HIT      EQU $20  ; payload is array of t_kb structs

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
