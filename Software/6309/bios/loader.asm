;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: loader.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; The boot prompt: until there's SD card support, this is the only way to
; get a program into RAM. Receives a Motorola S-Record (S1/S9) transfer over
; the UART and runs it on '.'. This replaces the old ML monitor entirely --
; no register/breakpoint context, no hexdump -- just transfer-and-run. Talks
; to the UART directly via serio.asm (not through the generic BIOS device
; dispatch) since this is boot-time ROM code that already knows exactly
; which device it means.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
LOADER_START EXPORT
;------------------------------------------------------------------------------
UT_PUTS     EXTERN          ; serio.asm
UT_GETC     EXTERN
USER_RAM    EXTERN          ; main.asm: the start of RAM the BIOS doesn't own
S_LEN       EXTERN          ; helpers.asm
S_HEXA      EXTERN
;------------------------------------------------------------------------------
RUN_ADRS    equ  $2000      ; '.' JSRs here -- matches the old bootloader's
                             ; convention so existing example programs don't
                             ; need to change their load address.
;------------------------------------------------------------------------------
    SECT bss
;------------------------------------------------------------------------------
LINBUF      RMB  96         ; incoming S-record text line
SRECCHK     RMB  1          ; running checksum of the current S-record line
SRECBC      RMB  1          ; byte count of the current S-record line
SRECBUF     RMB  40         ; decoded binary: addr(2), data, checksum(1)
HEXTMP      RMB  1
SRECLEN     RMB  2          ; length of the line being parsed
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
MSG_PROMPT    FCC  "Send S-Record now. '.' to run, ESC to cancel."
              FCB  LF,CR,0
MSG_BADREC    FCC  " <- bad rec"
              FCB  LF,CR,0
MSG_CANCEL    FCC  "cancelled."
              FCB  LF,CR,0
MSG_COMPLETE  FCC  "transfer complete."
              FCB  LF,CR,0
MSG_RUN       FCC  "running..."
              FCB  LF,CR,0
;------------------------------------------------------------------------------
LOADER_START
            LDY  #MSG_PROMPT
            JSR  UT_PUTS
            LDX  #LINBUF
KLOOP       JSR  UT_GETC
            BCS  KLOOP          ; nothing yet -- keep polling
            CMPA #ESCAPE
            BEQ  L_CANCEL
            CMPA #CR
            BEQ  GOTCR
            CMPA #'.
            BEQ  GOTDOT
            CMPX #LINBUF+95     ; a full line buffer: drop the rest (the record
            BHS  KLOOP          ; then fails its checksum rather than overrunning)
            STA  ,X+
            BRA  KLOOP
L_CANCEL    LDY  #MSG_CANCEL
            JSR  UT_PUTS
            LDX  #LINBUF
            BRA  KLOOP
GOTDOT      LDY  #MSG_RUN
            JSR  UT_PUTS
            JSR  RUN_ADRS
            LDX  #LINBUF
            BRA  KLOOP
;------------------------------------------------------------------------------
; A full line has been accumulated -- parse it as an S1 (data) or S9 (end of
; file) record if it looks like one, otherwise silently discard the line.
;------------------------------------------------------------------------------
GOTCR       CLR  ,X
            LDX  #LINBUF
            JSR  S_LEN          ; D = length
            STD  SRECLEN
            CMPD #4
            LBLO ENDPARSE       ; too short to be a real record
            LDA  ,X+
            CMPA #'S
            LBNE ENDPARSE
            LDA  ,X+
            CMPA #'9
            LBEQ GOT_SEOF
            CMPA #'1
            LBNE ENDPARSE
            CLRA
            STA  SRECCHK
            JSR  SRECREAD       ; byte count octet
            STA  SRECBC
            CMPA #4             ; address + checksum + at least one data byte ...
            LBLO REJECT
            CMPA #40            ; ... and no more than SRECBUF holds
            LBHI REJECT
            CLRB                ; the line must be long enough to hold them all:
            TFR  A,B            ; "S1" + count digits + 2 hex digits per byte
            CLRA
            ASLD
            ADDD #4
            CMPD SRECLEN
            LBHI REJECT
            LDY  #SRECBUF
            LDB  SRECBC
OCTLOOP     JSR  SRECREAD
            STA  ,Y+
            DECB
            BNE  OCTLOOP
            LDA  SRECCHK
            CMPA #$FF
            BEQ  GOODLINE
BADLINE     LDX  #LINBUF        ; report the (possibly partial) address
            LDA  SRECBUF+0
            JSR  S_HEXA
            LDA  SRECBUF+1
            JSR  S_HEXA
            CLR  ,X
            LDY  #LINBUF
            JSR  UT_PUTS
            LDY  #MSG_BADREC
            JSR  UT_PUTS
            BRA  ENDPARSE
GOODLINE    LDY  SRECBUF        ; destination address
            CMPY <USER_RAM      ; never over the BIOS's own RAM ...
            LBLO REJECT
            CMPY #EXE_MAXTOP    ; ... nor the ROM / I/O registers
            LBHS REJECT
            LDB  SRECBC
            SUBB #3             ; minus address(2) and checksum(1): the data bytes
            LEAX B,Y
            CMPX #EXE_MAXTOP
            LBHI REJECT         ; (the data must end below the ROM)
            LDX  #(SRECBUF+2)   ; source: the data bytes just after the address
XWRLOOP     LDA  ,X+
            STA  ,Y+
            DECB
            BNE  XWRLOOP
ENDPARSE    LDX  #LINBUF
            LBRA KLOOP
REJECT      LDY  #MSG_BADREC    ; a record that can't be right (or can't be put where
            JSR  UT_PUTS        ; it says): say so, load nothing
            BRA  ENDPARSE
GOT_SEOF    LDY  #MSG_COMPLETE
            JSR  UT_PUTS
            LDX  #LINBUF
            LBRA KLOOP
;------------------------------------------------------------------------------
; Read the next two-hex-digit octet from the line at X into A, advancing X
; and folding the byte into the running S-record checksum.
;------------------------------------------------------------------------------
SRECREAD    PSHS B
            CLRA
            JSR  READHEXDIGIT
            LSLA
            LSLA
            LSLA
            LSLA
            JSR  READHEXDIGIT
            TFR  A,B
            ADDB SRECCHK
            STB  SRECCHK
            PULS B
            RTS
;------------------------------------------------------------------------------
; OR the next hex digit at X (advancing X) into the low nybble of A.
;------------------------------------------------------------------------------
READHEXDIGIT
            PSHS B
            PSHS A
            LDA  ,X+
            SUBA #'0
            BMI  READHEX_ERR
            CMPA #9
            BLE  READHEX_OK
            SUBA #7
            CMPA #10            ; (":" .. "@" are not digits)
            BLO  READHEX_ERR
            CMPA #$F
            BLE  READHEX_OK
READHEX_ERR PULS A
            PULS B
            RTS
READHEX_OK  STA  HEXTMP
            PULS A
            ORA  HEXTMP
            PULS B
            RTS
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of loader.asm
;------------------------------------------------------------------------------
