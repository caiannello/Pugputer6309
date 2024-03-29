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
; which passes control to the BIOS ISR. 
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
UT_PUTC         EXTERN
UT_PUTS         EXTERN

;------------------------------------------------------------------------------
; Functions exported for use by other modules
;------------------------------------------------------------------------------
V_SW2           EXPORT
BIOS_INIT       EXPORT
;------------------------------------------------------------------------------
    SECT bss                ; Private variables - section address $0030
BIOS_TMP_C       RMB  1     ; Set when theres a new break context to show
BIOS_TMP_W       RMB  2
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
; SOFTWARE INTERRUPT 2: BIOS call 
; Reg. A will specify fcn index, and other regs may specify other args.
;------------------------------------------------------------------------------
V_SW2       ; Get address of bios function indexed by A
            ; JSR to it            
            ;STB  BIOS_TMP_C
            ;TFR  A,B
            ;CLRA
            ;LSLD
            ;ADDD #B_FCN_TAB
            ;STD  BIOS_TMP_W
            ;LDB  BIOS_TMP_C
            ;JSR  [BIOS_TMP_W]
            RTI             ; End of bios ISR
;------------------------------------------------------------------------------
; BIOS_NYI - Called when an unimplemented BIOS function is requested
;------------------------------------------------------------------------------
BIOS_NYI   RTS
;------------------------------------------------------------------------------
; Called to register an IO device with the BIOS
;------------------------------------------------------------------------------
BIOS_REG_DEV 
            RTS
;------------------------------------------------------------------------------
; Called to de-register an IO device from the BIOS
;------------------------------------------------------------------------------
BIOS_DEREG_DEV  
            RTS
;------------------------------------------------------------------------------
; BIOS PUTC 
;------------------------------------------------------------------------------
BIOS_PUTC   TFR B,A
            JSR UT_PUTC
            RTS
;------------------------------------------------------------------------------
; BIOS_PUTS - Output to stdout the null-terminated string at X. 
;------------------------------------------------------------------------------
BIOS_PUTS   JSR  UT_PUTS
            RTS
;------------------------------------------------------------------------------
; BIOS Initialization
;------------------------------------------------------------------------------
BIOS_INIT   RTS
;------------------------------------------------------------------------------
; TODO: Abstraction of devices
; TODO: Abstraction of files
; Do we want an 80x26 console backing buffer or a text line history?
;------------------------------------------------------------------------------
; Jumptable of bios functions - used for lookup by index
;------------------------------------------------------------------------------
B_FCN_TAB   FDB  BIOS_NYI      ; B_DQUERY    - Get info about devices connected to the system
            FDB  BIOS_REG_DEV  ; B_REG_DEV   - Register a device with the BIOS
            FDB  BIOS_DEREG_DEV ; B_DEREG_DEV - De-register a device with the bios
            FDB  BIOS_NYI      ; B_FSTAT     - Get info about a device or file
            FDB  BIOS_NYI      ; B_FDIR      - Get a file directory
            FDB  BIOS_NYI      ; B_FOPEN     - B: Device ref, E: flags (returns fileref or null in A, status in B)
            FDB  BIOS_NYI      ; B_FCLOSE    - B: fileref (returns status in A)
            FDB  BIOS_NYI      ; B_FDELETE   - Delete a file
            FDB  BIOS_NYI      ; B_FMOVE     - Move or rename a file
            FDB  BIOS_PUTC     ; B_PUTC      - B: Output fileref, E: The char
            FDB  BIOS_PUTS     ; B_PUTS      - B: Output fileref, X: adrs of null-terminated string
            FDB  BIOS_NYI      ; B_PUT       - B: Output fileref, X: adrs of bytes, Y: len
            FDB  BIOS_NYI      ; B_GETC      - B: Input fileref (rets char in A, or carry-set if None)
            FDB  BIOS_NYI      ; B_GETS      - B: Input fileref, X: buffer adrs, Y: buffer len. Returns strlen in X.
            FDB  BIOS_NYI      ; B_GET       - B: Input fileref, X: buffer adrs, Y: req. len. Returns getlen in X.
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of bios.asm
;------------------------------------------------------------------------------
