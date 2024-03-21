;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - ML Monitor 
; VERSION: 0.0.2
;    FILE: main.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; A minimal BIOS (Basic Input / Output System) for use by Pugputer 
; applications. Functions are provided to input and output text and data from
; various devices. When devices like UARTs and Video cards are initialized,
; they register themselves with the BIOS, so when applications want to output
; text or input keystrokes, BIOS can coordinate whether to deal with a UART,
; video card, physical keyboard, file on SD card, or some simultaneous 
; combination of devices. (e.g. the BIOS PUTCHAR function may cause a 
; character to be output by both the UART and the video card, and GETCHAR
; may accept a key from both a dedicated keyboard or serial input)
;
; To invoke a BIOS function, an application places a function number into 
; reg A (list in defines.d), relevant args in other registers or memory
; locations, and then issues a SWI2 (Software interrupt 2) instruction, 
; which causes an interrupt to pass control to the BIOS ISR. 
;
; After the BIOS function is done. RTI instruction returns execution in the 
; caller.
; 
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; Global settings and definitions
;------------------------------------------------------------------------------
; Functions imported from other modules
;------------------------------------------------------------------------------
S_HEXA          EXTERN      ; string.asm
S_CPY           EXTERN
S_LEN           EXTERN
S_EOL           EXTERN
;------------------------------------------------------------------------------
; Functions exported for use by other modules
;------------------------------------------------------------------------------
V_SW2           EXPORT
;------------------------------------------------------------------------------
    SECT bss                ; Private variables - section address $0030
BIOS_TMP        RMB  1      ; Set when theres a new break context to show
    ENDSECT
;------------------------------------------------------------------------------
    SECT code               ; Section address  $F000 - $FF00

V_SW2       RTI             ; SOFTWARE INTERRUPT 2 - TODO: BIOS call

; BIOS Initialization

BIOS_INIT   RTS

; TODO: Abstraction of devices
; TODO: Abstraction of files

; Do we want an 80x26 console backing buffer or a text line history?


    ENDSECT
;------------------------------------------------------------------------------
; End of bios.asm
;------------------------------------------------------------------------------
