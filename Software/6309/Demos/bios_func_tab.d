;------------------------------------------------------------------------------
; BIOS BIOS FUNCTION JUMP TABLE ADDRESSES AND COMMON CONSTANTS
;------------------------------------------------------------------------------
; ASCII CODES
ESC             EQU  $1B            ; ESCAPE
LF              EQU  $0A            ; LINE FEED
CR              EQU  $0D            ; CARRIAGE RETURN
NUL             EQU  $00            ; NULL
;------------------------------------------------------------------------------
FUNC_BASE       EQU  $FEA0          ; SEE 6309/BOOT/MAIN.ASM FOR DEFS
;------------------------------------------------------------------------------
BF_V_RESET      EQU  FUNC_BASE+0
BF_UT_GETC      EQU  FUNC_BASE+3
BF_UT_GETS      EQU  FUNC_BASE+6
BF_UT_PUTC      EQU  FUNC_BASE+9    ;
BF_UT_PUTS      EQU  FUNC_BASE+12
BF_UT_WAITTX    EQU  FUNC_BASE+15
BF_UT_CLRSCR    EQU  FUNC_BASE+18
BF_S_HEXA       EQU  FUNC_BASE+21   ; Convert Reg A to hex octet at X, X+=2
BF_S_EOL        EQU  FUNC_BASE+24   ; Put CR, LF, $00 at X, X+=3
BF_S_LEN        EQU  FUNC_BASE+27   ; Put len of string at X into Reg B
BF_S_CPY        EQU  FUNC_BASE+30   ; Copy string at Y to mem at X. X+=?
BF_RTC_GETTIX   EQU  FUNC_BASE+33   ; Get current system ticks to I64 at X.
BF_S_TOUPPER    EQU  FUNC_BASE+36   ; Make A uppercase if it is lowercase
BF_S_INTD       EQU  FUNC_BASE+39   ; Convert reg D to string at X, X+=?
BF_RTC_SETTIX   EQU  FUNC_BASE+42   ; Set current system ticks from I64 at X.
;------------------------------------------------------------------------------
