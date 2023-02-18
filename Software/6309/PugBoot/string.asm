;------------------------------------------------------------------------------
; PROJECT: PUGMON 
; VERSION: 0.0.1
;    FILE: string.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; Functions related to char/string formatting and manipulation.
;
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; Global settings and definitions
;------------------------------------------------------------------------------
; Functions exported for use by other modules
;------------------------------------------------------------------------------
C_ISPRINT   EXPORT          ; test if char in A is printable
S_HEXA      EXPORT
S_INTD      EXPORT
S_CPY       EXPORT
S_LEN       EXPORT
S_EOL       EXPORT
;------------------------------------------------------------------------------
; Misc Variables
;------------------------------------------------------------------------------
    SECT bss                
;------------------------------------------------------------------------------
TMP8        RMB  1
TMP16       RMW  1
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
; IF CHAR IN A IS UNIVERSALLY PRINTABLE, CARRY IS SET, ELSE IT IS CLEARED.
; IN STANDARD ASCII, CODES [32...126] ARE PRINTABLE, AND OTHERS ARE NOT.
; DIFFERENT CHARACTER SETS, SUCH AS VT-100, VDP, ARE NOT CONSIDERED.
;------------------------------------------------------------------------------
C_ISPRINT   CMPA #32
            BLO  NONPRINT
            CMPA #126
            BGT  NONPRINT
            ORCC #1         ; SET CARRY BIT
            RTS
NONPRINT    ANDCC #$FE      ; CLEAR CARRY BIT
            RTS    
;------------------------------------------------------------------------------
; COPY STRING AT Y, INCLUDING NULL TERMINATOR, TO X. 
;------------------------------------------------------------------------------
S_CPY       LDA  ,Y+        
            STA  ,X+
            BNE  S_CPY
            RTS    
;------------------------------------------------------------------------------
; RETURN LENGTH OF STRING X, NOT COUNTING NULL TERMINATOR, IN REG D.
; -----------------------------------------------------------------------------
S_LEN       PSHS X
SLENLOOP    LDA  ,X+
            BNE  SLENLOOP
            TFR  X,D
            SUBD #1
            SUBD ,S
            PULS X,PC
;------------------------------------------------------------------------------
; ADD CR+LF+NULL TO STRING X.
;------------------------------------------------------------------------------
S_EOL       LDA  #CR        
            STA  ,X+
            LDA  #LF
            STA  ,X+
            LDA  #0
            STA  ,X+
            RTS
;------------------------------------------------------------------------------
; CONVERTS INT VALUE IN D INTO A NULL-TERMINATED STRING AT X. 
; THE INPUT VAL IS LIMITED TO [-1280...1270]
;------------------------------------------------------------------------------
S_INTD      CLR  TMP8       ; CLEAR NEGATIVE FLAG BYTE
            STD  TMP16
            BPL  POSVAL     ; IF INTEGER IS POSITIVE, SKIP AHEAD.     
NEGVAL      LDA  #1
            STA  TMP8       ; NOTE THAT VALUE IS NEGATIVE,
            LDD  #0
            SUBD TMP16      ; AND MAKE IT POSITIVE.
            STD  TMP16
POSVAL      LDA  #0         ; PUSH NULL TERMINATOR ONTO STACK.
            PSHS A
            LDD  TMP16
DIVLOOP     DIVD #10        ; D/10 -> QUOTIENT IN B, REMAINDER IN A.
            ADDA #'0        ; CONVERT REMAINDER TO ASCII,
            PSHS A          ; AND PUSH CHAR ONTO STACK.
            LDA  #0         ; LET D = QUOTIENT
            CMPB #0
            BGT  DIVLOOP    ; REPEAT UNTIL D IS ZERO.
            LDA  TMP8 
            BEQ  UNSTACK
            LDA  #'-        ; PUSH NEGATIVE SIGN INTO THE STACK
            PSHS A
UNSTACK     PULS A          ; UNSTACK BYTES INTO THE DEST STRING,
            STA  ,X+
            BNE  UNSTACK    ; UNTIL WE'VE COPIED THE NULL-TERMINATOR.
            RTS     
;------------------------------------------------------------------------------
; CONVERTS INT VALUE IN Q INTO A NULL-TERMINATED STRING AT X. 
; THE INPUT VAL IS LIMITED TO [-327680...327670]
;------------------------------------------------------------------------------
S_INTQ      RTS              
;------------------------------------------------------------------------------
; CONVERTS REG A VAL INTO A 2-BYTE HEX STRING AT X. (NOT NULL-TERMINATED)
; BASED ON SUB FROM "6809 ASSEMBLY LANGUAGE SUBROUTINES" BY LANCE LEVENTHAL.
;------------------------------------------------------------------------------
S_HEXA      TFR  A,B        ; SAVE ORIGINAL BINARY VALUE
            LSRA            ; MOVE HIGH DIGIT TO LOW DIGIT
            LSRA
            LSRA
            LSRA
            CMPA #9
            BLS  AD30       ; BRANCH IF HIGH DIGIT IS DECIMAL
            ADDA #7         ; ELSE ADD 7 SO AFTER ADDING 'O' THE
                            ; CHARACTER WILL BE IN ‘'A'..'F'
AD30:       ADDA #'0        ; ADD ASCII O TO MAKE A CHARACTER
            ANDB #$0F       ; MASK OFF LOW DIGIT
            CMPB #9
            BLS AD3OLD      ; BRANCH IF LOW DIGIT IS DECIMAL
            ADDB #7         ; ELSE ADD 7 SO AFTER ADDING 'O! THE
                            ; CHARACTER WILL BE IN '‘A'..'F!
AD3OLD:     ADDB #'0        ; ADD ASCII O TO MAKE A CHARACTER
            STA ,X+         ; INSERT HEX BYTES INTO DEST STRING AT X
            STB ,X+         ; AND NCREMENT X
            RTS 
; -----------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; END OF STRING.ASM
;------------------------------------------------------------------------------
