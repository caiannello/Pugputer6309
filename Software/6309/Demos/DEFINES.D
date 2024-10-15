; -----------------------------------------------------------------------------
; IO DEVICE BASE ADDRESSES
; -----------------------------------------------------------------------------

BANK_BASE   EQU  $FFEC      : FFEC - FFEF: MEMORY BANK REGS 0...3 (BUILT-IN)
ACIA_BASE   EQU  $FFE8      ; FFE8 - FFEB: SERIAL UART R65C51P2 (BUILT-IN)
VDP_BASE    EQU  $FFE4      ; FFE4 - FFE7: VIDEO CHIP V9958
OPL3_BASE   EQU  $FFE0      ; FFE0 - FFE3: MUSIC CHIP YMF262 (OPL3)
VIA_BASE    EQU  $FFB0      ; FFB0 - FFBF: W65C22 VIA (SD CARD, SPI, KB, GPIO)

; V9958 VDP REGISTERS
VDAT        EQU  VDP_BASE+0 ; PORT 0: VRAM DATA (R/W)
VREG        EQU  VDP_BASE+1 ; PORT 1: STATUS REG (R), REGISTER/SETUP (W), VRAM ADDR (W)
VPAL        EQU  VDP_BASE+2 ; PORT 2: PALETTE REGISTERS (W)
VIND        EQU  VDP_BASE+3 ; PORT 3: REGISTER-INDIRECT ADDRESSING (W)

; MEMORY BANK REGISTERS 0..3 (BASE ADDRESS IN DEFINES.D)
; THESE ARE WRITE-ONLY, SO WE KEEP COPIES OF 1 THROUGH 3 IN 
; VARS IN MAIN.ASM: SBANK_1...SBANK_3

MBANK_0     EQU  BANK_BASE+0
MBANK_1     EQU  BANK_BASE+1
MBANK_2     EQU  BANK_BASE+2
MBANK_3     EQU  BANK_BASE+3
;------------------------------------------------------------------------------
; COMMON DEFINITIONS
;------------------------------------------------------------------------------
; ASCII CODES
ESC         EQU  $1B    ; ESCAPE
LF          EQU  $0A    ; LINE FEED
CR          EQU  $0D    ; CARRIAGE RETURN
NUL         EQU  $00    ; NULL
SPACE       EQU  $20
TILDE       EQU  $7E
;------------------------------------------------------------------------------
_DATE       STRUCT
YEAR        RMB  2      ; DATE AS INTEGERS
DAYYR       RMB  2
MON         RMB  1
DAYMON      RMB  1
HOUR        RMB  1
MIN         RMB  1
SEC         RMB  1
HUND        RMB  1
YEARBCD     RMB  2      ; DATE AS BCD
DAYYRBCD    RMB  2
MONBCD      RMB  1
DAYMONBCD   RMB  1
HOURBCD     RMB  1
MINBCD      RMB  1
SECBCD      RMB  1
HUNDBCD     RMB  1
            ENDS
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
