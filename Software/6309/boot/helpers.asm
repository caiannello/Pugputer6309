;------------------------------------------------------------------------------
; PROJECT: PUGMON 
; VERSION: 0.0.1
;    FILE: helpers.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; General-purpose functions related to chars/strings, numbers and math, 
; data structures, etc. 
;
;------------------------------------------------------------------------------

    INCLUDE defines.d       ; Global settings and definitions

;------------------------------------------------------------------------------
; Functions exported for use by other modules
;------------------------------------------------------------------------------

; char fcns

C_ISPRINT   EXPORT          ; test if char in A is printable

; string fcns

S_HEXA      EXPORT          ; char to hex
S_INTD      EXPORT
S_CPY       EXPORT
S_LEN       EXPORT
S_EOL       EXPORT

; crc fcns
crc_tab_gen EXPORT
crc_init    EXPORT
crc_get     EXPORT
crc16_byte  EXPORT

;------------------------------------------------------------------------------
    SECT bss            ; Misc Vars used by helpers
TMP8        RMB  1
TMP16       RMW  1
CRC_TAB     RMB  512    ; crc-16 (xmodem) lookup table
CRC_VAL     RMB  2      ; crc-16 temp val and result
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
; CRC-16 / XMODEM routines ( polynomial: $1021, initial val: $0000 )
; -----------------------------------------------------------------------------
crc_tab_gen clre            ; generate crc lookup table (uses e,f,a,b,x)
tab_loop    tfr  e,a        ;   for e = 0 to 255:  (table index iterator e):
            clrb            ;     d = e
            ldf  #8         ;     for f = 8 to 1: (8-bits iterator f):
tab_inner   lsld            ;       d = d << 1
            bcc  skip_poly  ;       skip next op if carry clear
            ldx  #$1021     ;         d ^= polynomial
            eorr x,d
skip_poly   decf            ;       decrement f
            bne  tab_inner  ;       if f > 0 (bits left) do next f
            tfr  e,x
            std  CRC_TAB,x  ;     crc_table[e] = d
            ince            ;     increment e
            bne  tab_loop   ;     if e>0 (hasn't wrapped) do next e
            rts             ;   end
; -----------------------------------------------------------------------------
crc_init    pshs X          ; init CRC calculation
            ldx  #0         
            stx  CRC_VAL 
            puls X
            rts
; -----------------------------------------------------------------------------
crc_get     ldd  CRC_VAL    ; get final CRC result in D
            rts
; -----------------------------------------------------------------------------
crc16_byte  ldw  CRC_VAL    ; update CRC from A (uses a,e,f,x)
            eorr e,a        ; a ^= (CRC_VAL >> 8)
            tfr  a,x
            ldx  CRC_TAB,x  ; x = crc_table[a]
            tfr  f,e        ; crc_val <<= 8
            clrf
            eorr x,w        ; crc_val ^= x
            stw  CRC_VAL
            rts
;------------------------------------------------------------------------------
; Methods for working with the 16-byte circular buffer structure (in defines.d)
;
; circbuf     STRUCT          
; flags       rmb  1        ; flags (1: empty, 2: full, 4: overrun, 8: underrun)
; len         rmb  1        ; num of bytes in buf
; head        rmb  1        ; head (write index)
; tail        rmb  1        ; tail (read idx)
; buf         rmb  16       ; buffer
;             ENDS
;------------------------------------------------------------------------------

; init circ buf at adrs x

cbuf_init   pshs a
            lda  #0
            sta  circbuf.flags,x
            sta  circbuf.len,x
            sta  circbuf.head,x
            sta  circbuf.tail,x
            puls a
            rts

; return in B len of buf at X.
; if full, carry set.

cbuf_len    ldb  circbuf.len,x
            ; todo: set carry if full
            rts

; push byte in A onto buf at adrs X
; sets carry and overrun flag if fail.

cbuf_push   
            bsr  cbuf_len  ; check len
            bcc  do_cbpush ; if room, goto push
            ; set overrun flag
            ; set carry
            rts
do_cbpush   ; push
            rts

; pop byte from buf X to reg A
; sets carry and underrun flag if fail.

cbuf_pop
            bsr  cbuf_len  ; check len
            cmpb #0        ; is empty.
            bne  do_cbpop  ; not empty, goto pop
            ; set underrun flag
            ; set carry
            rts
do_cbpop    ; pop
            rts
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of helpers.asm
;------------------------------------------------------------------------------
