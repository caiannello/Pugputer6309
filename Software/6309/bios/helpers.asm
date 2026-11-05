;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: helpers.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; General-purpose functions: chars/strings, and the shared circular buffer
; used by the UART's RX and TX queues.
;------------------------------------------------------------------------------

    INCLUDE defines.d

;------------------------------------------------------------------------------
; Functions exported for use by other modules
;------------------------------------------------------------------------------
S_HEXA      EXPORT          ; byte to 2-char hex
S_CPY       EXPORT          ; copy null-terminated string
S_LEN       EXPORT          ; length of null-terminated string (not incl null)
S_EOL       EXPORT          ; append CR,LF,NULL

CBUF_INIT   EXPORT          ; init a circbuf instance
CBUF_PUT    EXPORT          ; push a byte (carry set if full)
CBUF_GET    EXPORT          ; pop a byte (carry set if empty)

;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
; COPY STRING AT Y, INCLUDING NULL TERMINATOR, TO X.
;------------------------------------------------------------------------------
S_CPY       LDA  ,Y+
            STA  ,X+
            BNE  S_CPY
            RTS
;------------------------------------------------------------------------------
; RETURN LENGTH OF STRING X, NOT COUNTING NULL TERMINATOR, IN REG D.
;------------------------------------------------------------------------------
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
            ADDA #7         ; ELSE ADD 7 SO AFTER ADDING '0' THE
                             ; CHARACTER WILL BE IN 'A'..'F'
AD30:       ADDA #'0        ; ADD ASCII 0 TO MAKE A CHARACTER
            ANDB #$0F       ; MASK OFF LOW DIGIT
            CMPB #9
            BLS AD3OLD      ; BRANCH IF LOW DIGIT IS DECIMAL
            ADDB #7
AD3OLD:     ADDB #'0
            STA ,X+         ; INSERT HEX CHARS INTO DEST STRING AT X
            STB ,X+         ; AND INCREMENT X
            RTS
;------------------------------------------------------------------------------
; Circular byte buffer (struct "circbuf" in defines.d: head,tail,count,buf).
; Shared by the UART RX and TX queues (and available to any future device
; driver that wants a ring buffer) so there's exactly one implementation to
; get right, rather than one hand-rolled copy per direction.
;
; None of these routines disable interrupts themselves -- callers that share
; a buffer with an ISR are responsible for that (see serio.asm).
;------------------------------------------------------------------------------

; init the circbuf instance at X

CBUF_INIT   PSHS A
            CLRA
            STA  circbuf.head,X
            STA  circbuf.tail,X
            STA  circbuf.count,X
            PULS A
            RTS

; push byte in A onto the circbuf instance at X.
; Returns carry set (buffer full, byte NOT stored) or carry clear (stored).
;
; Y is built as &buf[0] via constant-offset addressing first, then the
; head/tail index (0..SBUFSZ-1, always < 128) is applied as a B-accumulator
; offset. Splitting it this way keeps the accumulator offset itself always
; small and positive; folding the struct's buf-field offset into the same
; 8-bit accumulator value could exceed 127 and be misread as a negative
; offset by the CPU's signed accumulator-offset addressing mode.

CBUF_PUT    PSHS B,Y
            LDB  circbuf.count,X
            CMPB #SBUFSZ
            BHS  CBP_FULL
            LEAY circbuf.buf,X   ; Y = &buf[0]
            LDB  circbuf.head,X
            STA  B,Y             ; buf[head] = A
            INC  circbuf.head,X
            LDB  circbuf.head,X
            CMPB #SBUFSZ
            BLO  CBP_NOWRAP
            CLR  circbuf.head,X
CBP_NOWRAP  INC  circbuf.count,X
            ANDCC #$FE      ; carry clear: stored OK
            PULS B,Y,PC
CBP_FULL    ORCC #$01       ; carry set: full, byte discarded
            PULS B,Y,PC

; pop a byte from the circbuf instance at X into A.
; Returns carry set (buffer empty, A undefined) or carry clear (A valid).

CBUF_GET    PSHS B,Y
            LDB  circbuf.count,X
            BEQ  CBG_EMPTY
            LEAY circbuf.buf,X   ; Y = &buf[0]
            LDB  circbuf.tail,X
            LDA  B,Y             ; A = buf[tail]
            INC  circbuf.tail,X
            LDB  circbuf.tail,X
            CMPB #SBUFSZ
            BLO  CBG_NOWRAP
            CLR  circbuf.tail,X
CBG_NOWRAP  DEC  circbuf.count,X
            ANDCC #$FE      ; carry clear: A holds the byte
            PULS B,Y,PC
CBG_EMPTY   ORCC #$01       ; carry set: nothing to pop
            PULS B,Y,PC
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of helpers.asm
;------------------------------------------------------------------------------
