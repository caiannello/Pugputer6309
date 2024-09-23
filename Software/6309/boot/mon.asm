;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - ML Monitor 
; VERSION: 0.0.2
;    FILE: main.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
;  ML mon features:
; 
;    - Serial interface by default ( + video/kbd after boot )
;    - Simple memory inspection / edit / call / jump
;    - XMODEM file transfer / serial boot
;    - Catches illegal-instruction interrupt by default, or can be
;      redirected to a custom handler by a running application.
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
UT_GETC         EXTERN
LINBUF          EXTERN
V_RESET         EXTERN
RTC_SHOW        EXTERN
TMP8_0          EXTERN
TMP16_0         EXTERN
TMP8_1          EXTERN
TMP16_1         EXTERN
;------------------------------------------------------------------------------
; Stuff exported for use by other modules
;------------------------------------------------------------------------------
V_DZINST        EXPORT
V_SWI           EXPORT
V_CBRK          EXPORT
MON_ENTRY       EXPORT
NEW_CTX         EXPORT
;------------------------------------------------------------------------------
    SECT bss                ; Private variables - section address $0030
NEW_CTX         RMB  1      ; Set when theres a new break context to show
CTX_BUF         RMB  15     ; Most recent break context (register dump)
DUMP_ADRS       RMB  2      ; Start address used by hexdump display routine
EDUMP_ADRS      RMB  2      ; End address for hexdump display
TMP_KEY         RMB  1      ; holds monitor cli keystroke
SRECCHK         RMB  1      ; Running checksum of current SREC line
SRECBC          RMB  1      ; Bytecount of current SREC line
SRECBUF         RMB  32
    ENDSECT
;------------------------------------------------------------------------------
    SECT code               ; Section address  $F000 - $FF00

; Break types, used to label a break context for display

BC_SWI      EQU  $00        ; break code - software interrupt 
BC_DZINST   EQU  $01        ; divide by zero or illegal instruction
BC_CBRK     EQU  $02        ; control-c break
BS_SWI      FCC  "<SWI>"    ; break tag - normal (swi) break 
            FCB  0     
BS_DZINST   FCC  "<DZI>"    ; illegal instruction or divide by zero
            FCB  0                        
BS_CBRK     FCC  "<BRK>"    ; control-c break
            FCB  0       
; -----------------------------------------------------------------------------
; Interrupt Service Routines - Some are hard-coded in the interrupt vector 
; table at $fff0 and are not changable, but others are referenced by the RAM 
; jump table so other modules can insert handlers at runtime.
; -----------------------------------------------------------------------------

; built-in handler for illegal instruction / divide-by-zero (DZINST vector)

V_DZINST    LDA  #BC_DZINST
            JMP  SAVE_CTX

; built-in handler for breakpoint (SWI vector)

V_SWI       LDA  #BC_SWI
            JMP  SAVE_CTX

; handler for when BIOS receives a CONTROL-C

V_CBRK      LDA  #BC_CBRK   
            JMP  SAVE_CTX

; store break type and context, and jump to ML monitor.

SAVE_CTX    LDY  #CTX_BUF   ; Store break type as first byte
            STA  ,Y+        ; of break context buffer.
            LDE  #14        ; Unstack the context registers manually, since
CTXLOOP     PULS A          ; we're storing them rather than doing an RTI.
            STA  ,Y+
            DECE            ; Pop order: CC, A, B, E, F, DP, X, Y, U, PC
            BNE  CTXLOOP
            LDA  #1
            STA  NEW_CTX    ; Note we have a new register context to show,
            JMP  MON_ENTRY  ; and jump to ML monitor prompt.

; Entrypoint to ML Monitor

MON_ENTRY   LDA  NEW_CTX    ; Check if got a break context to show
            BEQ  MAINLOOP   ; If not, go to monitor mainloop.
            CLR  NEW_CTX
            JSR  SHOW_CTX   ; Show context.

; ML Monitor Mainloop
; todo: implement editor functions in bios, and use to implement
; a monitor CLI below.
MAINLOOP    ;JSR  con_svc    ; Console housekeeping service
            ;BEQ  ML_PAR     ; returns nonzero if we got something to do.

ML_GETKEY   JSR  UT_GETC    ; READ RX CHARACTER, IF ANY.
            BEQ  ML_GETKEY  ; LOOP UNTIL A CHARACTER IS RECEIVED.
            CMPA #CR        ; IF WE GET A CR, ECHO IT, FOLLOWED BY A LF.
            BNE  ML_ECHO
            JSR  UT_PUTC 
            LDA  #LF
ML_ECHO     STA  TMP_KEY    ; STASH PRESSED KEY FOR FURTHER CHECKING, THEN
            JSR  UT_PUTC    ; ECHO THE RECEIVED CHARACTER TO USER.
            LDA  TMP_KEY    ; DEPENDING ON KEY, MAYBE DO STUFF:
ML_K_TIL    CMPA #TILDE     ; '~': RUN RAM EXAMPLE PROGRAM, THEN BREAK.
            BNE  ML_K_DUMP
            JMP  V_RESET
ML_K_DUMP   CMPA #'.        ; '.': DUMP RAM $4000...$8000
            BNE  ML_K_TIM
            LDX  #$2000
            STX  DUMP_ADRS
            LDX  #$3000
            STX  EDUMP_ADRS
            JSR  HEXDUMP_BLOCK
ML_K_TIM    CMPA #'T        ; 'T': SHOW CURRENT TICKCOUNT
            BNE  ML_K_XFER
            JSR  RTC_SHOW
ML_K_XFER   CMPA #'X        ; 'X': Xfer S-Record file
            BNE  ML_END
            JSR  XFER
ML_END      BRA  MAINLOOP
; -----------------------------------------------------------------------------
; Receives a Motorola S-Record file to RAM. ESC to quit.
; -----------------------------------------------------------------------------
MSG_XFER    FCC  "Send S-Record now. Press . to run, ESC to quit."
            FCB  LF,CR,0
MSG_DOT     FCC  "Calling subroutine."
            FCB  LF,CR,0
MSG_EDOT    FCC  "Subroutine returned."
            FCB  LF,CR,0
MSG_BADREC  FCC  "<- Bad Rec"
            FCB  LF,CR,0
MSG_CR      FCB  LF,CR,0
MSG_XEND    FCC  "Ending Xfer mode."
            FCB  LF,CR,0
MSG_COMP    FCC  "Xfer complete."
            FCB  LF,CR,0

XFER        LDY  #MSG_XFER
            JSR  UT_PUTS
            LDX  #LINBUF
KLOOP       JSR  UT_GETC    ; READ RX CHARACTER, IF ANY.
            BEQ  KLOOP      ; LOOP UNTIL A CHARACTER IS RECEIVED.
            CMPA #ESCAPE
            BEQ  X_END
            CMPA #CR
            BEQ  GOTCR
            CMPA #'.
            BEQ  GOTDOT
            STA  ,X+        ; Add char to linbuf (non-esc, non-dot, non-cr)
            JMP  KLOOP      
X_END       LDY  #MSG_XEND
            JSR  UT_PUTS
            RTS             ; END XFER MODE, RETURN TO MONITOR
GOTDOT      LDY  #MSG_DOT   ; Say we're starting the subroutine.
            JSR  UT_PUTS
            JSR  $2000      ; Call sub
            LDY  #MSG_EDOT  ; Say the sub ended
            JSR  UT_PUTS
            RTS
GOTCR       LDA  #0         ; Null-terminate the input line
            STA  ,X+
            LDX  #LINBUF
            JSR  S_LEN      ; get line length in D
            CMPD #4
            BLT  ENDPARSE   ; trash line if length is less than 4.            
            STD  TMP16_0    ; store length in tmp val
            LDX  #LINBUF    ; trash lines not starting with "S1"
            LDA  ,X+
            CMPA #'S
            BNE  ENDPARSE
            LDA  ,X+
            CMPA #'9
            BEQ  GOT_SEOF
            CMPA #'1
            BNE  ENDPARSE
            LDX  #(LINBUF+2) ; point to byte-count octet
            CLRA
            STA  SRECCHK
            JSR  SRECREAD  ; get bytecount
            STA  SRECBC    ; stash it for later
            LDY  #SRECBUF
            LDB  SRECBC
OCTLOOP     JSR  SRECREAD  ; read in all srec octets and convert into bytes 
            STA  ,Y+
            DECB
            BNE  OCTLOOP
            LDA  SRECCHK
            CMPA #$FF
            BEQ  GOODLINE
BADLINE     LDX  #LINBUF   ; show address from bad record and err msg
            LDA  SRECBUF+0
            JSR  S_HEXA
            LDA  SRECBUF+1
            JSR  S_HEXA
            LDA  #0
            STA  ,X+
            LDY  #LINBUF
            JSR  UT_PUTS
            LDY  #MSG_BADREC
            JSR  UT_PUTS
            LDX  #LINBUF
            JMP  KLOOP
GOODLINE    LDY  SRECBUF   ; get dest address in y
            LDX  #(SRECBUF+2) ; get src address in x
            LDB  SRECBC    ; get len of bytes to write 
            DECB           ; (minus adrs and csum)
            DECB
            DECB
XWRLOOP     LDA  ,X+
            STA  ,Y+
            DECB
            BNE  XWRLOOP                       
ENDPARSE    LDX  #LINBUF
            JMP  KLOOP
GOT_SEOF    LDY  #MSG_COMP  ; say we got final record of srec file
            JSR  UT_PUTS
            LDX  #LINBUF
            JMP  KLOOP
; -----------------------------------------------------------------------------
; read next octet of srec line into A and update checksum
; -----------------------------------------------------------------------------
SRECREAD:
    PSHS B
    CLRA
    JSR  READHEXDIGIT
    LSLA
    LSLA
    LSLA
    LSLA
    JSR  READHEXDIGIT
    ; update checksum
    TFR  A,B
    ADDB SRECCHK
    STB  SRECCHK
    PULS B
    RTS            

; OR next nybble of srec line into reg A
READHEXDIGIT:
    PSHS B
    PSHS A          ; save A for later    
    LDA  ,X+
    SUBA #'0'       ; move ascii 0 down to binary 0
    BMI READHEX_ERR
    CMPA #9
    BLE READHEX_OK  ; 0-9 found
    SUBA #7         ; drop 'A' down to 10
    CMPA #$F
    BLE READHEX_OK
READHEX_ERR:
    PULS A
    PULS B
    RTS
READHEX_OK:
    STA TMP8_0      ; store 4-bit value in temp
    PULS A          ; restore old value
    ORA TMP8_0      ; or the hex value
    PULS B
    RTS               
; -----------------------------------------------------------------------------
; Show latest saved register context from a monitor break, e.g.:
; "...<BRK_TAG>                            "
; "  CC A  B  E  F  DP  X    Y    U    PC  "
; "  A5 00 0C 00 00 00 00A9 E07D FFFF 1008 "
; -----------------------------------------------------------------------------
CTX_HDR     FCB  LF,CR      ; BREAK REGISTER CONTEXT HEADER
            FCC  "  CC A  B  E  F  DP  X    Y    U    PC"
            FCB  LF,CR,0
SHOW_CTX    LDX  #LINBUF            
            LDY  #CTX_BUF    
            LDF  ,Y+        ; GET BREAK TYPE IN F
            BEQ  BT_SW
            CMPF #BC_CBRK
            BNE  BT_DZ
BT_CB       LDY  #BS_CBRK   ; CODE 2: CONTROL-C BREAK: <CBK>
            BRA  BT_HDR
BT_DZ       LDY  #BS_DZINST ; CODE 3: DIV 0 OR ILLEGAL INSTRUCTION BREAK <DZI>
            BRA  BT_HDR
BT_SW       LDY  #BS_SWI    ; CODE 0: SOFTWARE INTERRUPT 1 BREAK <SWI>
BT_HDR      JSR  S_CPY 
            LEAX ,-X        ; REMV NULL
            LDY  #CTX_HDR   ; e.g. "  CC A  B  E  F  DP  X    Y    U    PC "
            JSR  S_CPY      ;      "; A5 00 0C 00 00 00 00A9 E07D FFFF 1008"
            LEAX ,-X        ; REMV NULL
            LDA  #';        ; PRECEED EDITABLE REG VALUES WITH A ';'
            STA  ,X+
            LDY  #CTX_BUF+1    
            LDE  #6
CTX_BYTE    LDA  #SPACE     ; DO CC, A, B, E, F, DP
            STA  ,X+
            LDA  ,Y+
            JSR  S_HEXA  
            DECE
            BNE  CTX_BYTE
            LDE  #4
CTX_WORD    LDA  #SPACE     ; DO X, Y, U, PC  
            STA  ,X+
            LDA  ,Y+
            JSR  S_HEXA  
            LDA  ,Y+
            JSR  S_HEXA  
            DECE
            BNE  CTX_WORD
            JSR  S_EOL      ; ADD CR+LF+NULL TO OUTPUT STRING
            LDY  #LINBUF    ; context string
            JSR  UT_PUTS
            RTS             ; END REG CONTEXT PRINT 
;------------------------------------------------------------------------------
; PRINTS UP TO 16 BYTES OF MEMORY, STARTING AT DUMP_ADRS, AS HEX + ASCII, AND
; DUMP_ADRS IS INCREMENTED BY THE AMOUNT OF SHOWN. 
; IF DUMP_ADRS IS LESS THAN SIXTEEN LESS THAN EDUMP_ADRS, LESS BYTES ARE SHOWN,
; REPLACED BY SPACES.
;------------------------------------------------------------------------------
HEXDUMP_LINE:
            LDX  #LINBUF
            LDA  #'>        ; PUT '>' BEFORE ADDRESS
            STA  ,X+
            LDA  DUMP_ADRS  ; THEN 4-CHAR HEX ADDRESS
            JSR  S_HEXA  
            LDA  DUMP_ADRS+1
            JSR  S_HEXA  
            LDA  #32        ; THEN A SPACE,
            STA  ,X+
            LDY  DUMP_ADRS  ; GET STARTING ADDRESS IN Y
            LDE  #16        ; FOR 16 ITERATIONS
            LDU  #(LINBUF+1+5+16*3)  ; POINT U AT ASCII PART AFTER HEX CHARS
            LDA  #$A8       ; WHICH BEGINS WITH THIS AS A DELIMITER
            STA  ,U+
            LDF  #'.
HEXLOOP     CMPY EDUMP_ADRS ; IF PASS THE END DUMP ADRS, STOP SHOWING HEX
            BGE  NULLOOP
            LDA  ,Y+        ; GONNA SHOW A HEX OCTET  
            CMPA #32
            BGE  ASCIIOK
            STF  ,U+        ; SHOW ASCII NONPRINTABLES AS A DECIMAL POINT
            BRA  DONEASCII
ASCIIOK     STA  ,U+        ; ADD ASCII CHAR OR DEC TO LINE AT POS U
DONEASCII   JSR  S_HEXA      ; AT LINE POS X, ADD 2-CHAR HEX BYTE AND
            LDA  #32        ; A SPACE,
            STA  ,X+
            DECE            ; CHECK IF MORE BYTES TO DO
            BNE  HEXLOOP
            BRA  LINEDONE
NULLOOP     LDA  ,Y+        ; PAST EDUMP ADRS, SHOW NOTHING
            LDA  #32
            STA  ,U+        
            STA  ,X+
            STA  ,X+
            STA  ,X+
            DECE            ; CHECK IF MORE BYTES TO DO
            BNE  NULLOOP
LINEDONE    STY  DUMP_ADRS  ; LINE DONE. UPDATE DUMP POSITION TO NEXT ROW,
            LDA  #$A8       ; PUT END DELIMITER ON ASCII PART.
            STA  ,U+              
            TFR  U,X
            JSR  S_EOL      ; ADD CR+LF+NULL TO OUTPUT STRING
            LDY  #LINBUF    
            JSR  UT_PUTS    
            RTS
;------------------------------------------------------------------------------
; HEX+ASCII DUMP MEM FROM DUMP_ADRS THROUGH EDUMP_ADRS 
;------------------------------------------------------------------------------
HEXDUMP_BLOCK
            LDX  DUMP_ADRS
            CMPX EDUMP_ADRS
            BGE  DONE_BLOCK
            BSR  HEXDUMP_LINE
            BRA  HEXDUMP_BLOCK
DONE_BLOCK  RTS
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of mon.asm
;------------------------------------------------------------------------------
