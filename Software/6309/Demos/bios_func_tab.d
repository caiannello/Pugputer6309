;------------------------------------------------------------------------------
; BIOS BIOS FUNCTION JUMP TABLE ADDRESSES
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
BF_S_HEXA       EQU  FUNC_BASE+21   ; CONVERT REG A TO HEX OCTET AT X, X+=2
BF_S_EOL        EQU  FUNC_BASE+24   ; PUT CR, LF, $00 AT X, X+=3
BF_S_LEN        EQU  FUNC_BASE+27   ; PUT LEN OF STRING AT X INTO REG B
BF_S_CPY        EQU  FUNC_BASE+30   ; COPY STRING AT Y TO MEM AT X. X+=?
BF_RTC_GETTIX   EQU  FUNC_BASE+33   ; GET CURRENT SYSTEM TICKS TO I64 AT X.
BF_S_TOUPPER    EQU  FUNC_BASE+36   ; MAKE A UPPERCASE IF IT IS LOWERCASE
BF_S_INTD       EQU  FUNC_BASE+39   ; CONVERT REG D TO STRING AT X, X+=?
BF_RTC_SETTIX   EQU  FUNC_BASE+42   ; SET CURRENT SYSTEM TICKS FROM I64 AT X.
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
