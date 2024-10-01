;------------------------------------------------------------------------------
; BIOS functions jump table
;------------------------------------------------------------------------------
FUNC_BASE       equ  $FEA0
;------------------------------------------------------------------------------
BF_V_RESET      equ  FUNC_BASE+0
BF_UT_GETC      equ  FUNC_BASE+3
BF_UT_GETS      equ  FUNC_BASE+6
BF_UT_PUTC      equ  FUNC_BASE+9
BF_UT_PUTS      equ  FUNC_BASE+12
BF_UT_WAITTX    equ  FUNC_BASE+15
BF_UT_CLRSCR    equ  FUNC_BASE+18
BF_S_HEXA       equ  FUNC_BASE+21	; Convert Reg A to hex octet at X, X+=2
BF_S_EOL        equ  FUNC_BASE+24   ; Put CR, LF, $00 at X, X+=3
BF_S_LEN        equ  FUNC_BASE+27   ; Put len of string at X into Reg B
BF_S_CPY        equ  FUNC_BASE+30   ; Copy string at Y to mem at X. X+=?
BF_RTC_GETTIX   equ  FUNC_BASE+33   ; Get current system ticks to I64 at X.
BF_S_TOUPPER    equ  FUNC_BASE+36   ; Make A uppercase if it is lowercase
BF_S_INTD       equ  FUNC_BASE+39   ; Convert reg D to string at X, X+=?
BF_RTC_SETTIX   equ  FUNC_BASE+42   ; Set current system ticks from I64 at X.
;------------------------------------------------------------------------------
