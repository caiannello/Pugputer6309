
;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - vdp experiment
; VERSION: 0.0.2
;    FILE: CONV_HICOLOR.ASM
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; EXPERIMENTING WITH THE V9958 HIGHCOLOR MODES.
;
; I WROTE A PYTHON UTILITY, CONV_YJK.PY, WHICH CONVERTS 256X212-SIZED 
; PNG FILES INTO HUFFMAN-CODED YJK BINARIES AS SEEN BELOW.
;
; ENCODED IMAGE FORMAT OUTPUT BY CONV_YJK.PY:
;   PACKED_HUFFMAN_CODE_TABLE       # SEE BELOW
;   Y:06b                           # INITIAL LUMA
;   J:06b                           # INITIAL CHROMA J
;   K:06b                           # INITIAL CHROMA K
;   FOR EACH FOUR PIXELS OF IMAGE:
;     ENCODED DELTA J
;     ENCODED DELTA K
;     ENCODED DELTA Y
;     ENCODED DELTA Y
;     ENCODED DELTA Y
;     ENCODED DELTA Y
;
; HUFFMAN TABLE FORMAT:
;   WORD16  N (NUM ROWS IN THIS TABLE)
;       ROW 0:
;           BITS[4]     L (LENGTH IN BITS OF FOLLOWING CODE)
;           BITS[L]     C (HUFFMAN CODE)
;           BITS[6]     S (SIGNED 6-BIT INTEGER REPRESENTED BY CODE)
;       ROW 1:
;           BITS[4]     DL  (LENGTH DIFFERENCE FROM PREVIOUS CODE LENGTH)
;           BITS[L+DL]  C   (HUFFMAN CODE)
;           BITS[6]     S   (SIGNED 6-BIT INTEGER REPRESENTED BY CODE)
;       ...
;       ROW (N-1):
;           BITS[4]     DL  (LENGTH DIFFERENCE FROM PREVIOUS CODE LENGTH)
;           BITS[L+DL]  C   (HUFFMAN CODE)
;           BITS[6]     S   (SIGNED 6-BIT INTEGER REPRESENTED BY CODE)
;
; ON STARTUP, THE TABLE IS PARSED INTO A BYTE-ALIGNED STRUCTURE, AT ADDRESS
; #CODETAB, FOR FASTER DECODING. IN THEORY, THERE SHOULD BE NO MORE THAN 64 
; CODES. IN THE FUTURE, IT MIGHT BE HELPFUL TO DEDICATE SOME CODES FOR USE 
; AS ESCAPE-SYMBOLS TO DO SOME RUN-LENGTH ENCODING OR SIMILAR.
; -----------------------------------------------------------------------------
    INCLUDE DEFINES.D           ; COMMON DEFINITIONS
    INCLUDE BIOS_FUNC_TAB.D     ; BIOS FCN JUMP TABLE AND CONSTANTS
;------------------------------------------------------------------------------
    ORG     $1000               ; BEGIN CODE & VARS
; -----------------------------------------------------------------------------
; PROGRAM ENTRYPOINT
; -----------------------------------------------------------------------------
ENTRYPOINT  
    JMP  VDP_INIT
; -----------------------------------------------------------------------------
; VARS
; -----------------------------------------------------------------------------
CODETAB         RMB (1+2+1)*64 ; BYTE-ALIGNED CODE TABLE FOR SPEED
ENDCODETAB              ; (CAN WE MAKE THIS FASTER USING DIRECT-PAGE?)

REM             RMB 1   ; HOLDS LATEST UNPROCESSED INPUT BITS
REMLEN          RMB 1   ; NUM BITS IN ABOVE
QCOUNT          RMB 2   ; MAIN DRAWLOOP ITERATION

YY              RMB 1   ; CURRENT (Y,J,K) VALUES
JJ              RMB 1
KK              RMB 1

KLO             RMB 1   ; PIECEWISE J,K FOR THE VDP
KHI             RMB 1
JLO             RMB 1
JHI             RMB 1

TCODELEN        RMB 1   ; HUFFMAN CODE LENGTH DURING INITIAL TABLE PARSE
TNUMROWS        RMB 1   ; NUM TABLE ROWS DURING INITIAL PARSE
TMP8            RMB 1

TSTART          RMB 8   ; START AND END TIMES FOR DURATION REPORT
TEND            RMB 8
SERBUF          RMB 8   ; SERIAL OUTPUT BUFFER FOR LOGGING
; -----------------------------------------------------------------------------
; CONSTS
; -----------------------------------------------------------------------------
VDP_SEQ     FCB $00,$87,$0E,$80,$08,$99,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$40
            FCB $00,$8E,$00,$40,$E5,$92,$00,$90
; -----------------------------------------------------------------------------
VDP_INIT:    
    LDX  #VDP_SEQ   ; SET 256 X 212 X YJK COLOR MODE
VDP_ILOOP
    LDA  ,X+
    STA  VREG
    CMPX #VDP_INIT
    BLO  VDP_ILOOP
    LDA  #$12       ; SET BG/BORDER (R,B,G) TODO: INCLUDE BG COLOR IN IMG DATA
    STA  VPAL
    LDA  #$00
    STA  VPAL    
    LDX  #TSTART    ; NOTE START TIME IN TICKS (16THS OF SECS)
    JSR  BF_RTC_GETTIX

    LDU  #HUFFIMG   ; START PARSING INPUT DATA AT #HUFFIMG.
    LDD  ,U++       ; TODO: MAKE THIS FIELD A BYTE, AND INCLUDE IMG (X,Y,W,H)
    STB  TNUMROWS   ; FIRST, NOTE NUMBER OF HUFFMAN TABLE ROWS.
    LDA  ,U+
    STA  REM        ; QUEUE UP THE NEXT 8 BITS OF INPUT,
    LDA  #8         ; AND NOTE LENGTH OF UNPROCESSED BITS.
    STA  REMLEN     ; (WE USE REM,REMLEN THROUGHOUT THE PROGRAM TO AID
                    ; BITWISE PROCESSING OF INPUT)
    LDA  #0         
    STA  TCODELEN   ; FOR BETTER DECODING SPEED, UNPACK THE HUFFMAN
    LDY  #CODETAB   ; TABLE TO BYTE-ALIGNED VALUES AT #CODETAB.
TBL_PARSE:
    LDE  #4
    JSR  GET_BITS   ; READ 4-BIT INCREASE IN CODE LENGTH
    STB  ,Y+        ; STORE IT IN CODETAB TABLE AS A UINT8
    ADDB TCODELEN   ; SUM TOTAL CODE LENGTH
    STB  TCODELEN
    TFR  B,E
    JSR  GET_BITS   ; READ IN THAT MANY BITS OF HUFFMAN CODE,
    STD  ,Y++       ; AND STORE IT IN CODETAB AS A UINT16
    LDE  #6
    JSR  GET_BITS   ; READ 6-BIT SIGNED DELTA
    JSR  SEX6       ; SIGN-EXTEND IT TO 8-BITS,
    STB  ,Y+        ; AND STORE IN CODETAB AS A UINT8
    DEC  TNUMROWS   ; COUNTDOWN TABLE ROWS
    BNE  TBL_PARSE  ; DO NEXT ROW, IF ANY.

INIT_YJK:           ; GET INITIAL VALUES OF Y,J, AND K.
    LDE  #6         ; (THE ENCODED DATA IS JUST CHANGES IN Y,J,K)
    JSR  GET_BITS
    JSR  SEX6       ; SIGN-EXTEND THE 6-BIT VALS TO 8-BITS
    STB  YY
    LDE  #6
    JSR  GET_BITS
    JSR  SEX6  
    STB  JJ
    LDE  #6
    JSR  GET_BITS
    JSR  SEX6  
    STB  KK

START_DRAWING:      ; WE ARE NOW AT THE ENCODED DATA.
    LDD  #13568     ; WE'LL PLOT (64 * 212) PIXEL-QUARTETS.
DRAWLOOP:    
    STD  QCOUNT
    BSR  DECODE     ; GET DJ
    ADDB JJ         ; J = J + DJ
    STB  JJ
    TFR  B,A        ; SPLIT J INTO 2 3-BIT WORDS
    ANDA #$7
    STA  JLO
    LSRB
    LSRB
    LSRB
    ANDB #$7
    STB  JHI
    BSR  DECODE     ; GET DK
    ADDB KK         ; K = K + DK
    STB  KK
    TFR  B,A        ; SPLIT K INTO 2 3-BIT WORDS
    ANDA #$7
    STA  KLO
    LSRB
    LSRB
    LSRB
    ANDB #$7
    STB  KHI
    LDX  #KLO       ; FOR EACH OF KLO,KHI,JLO,JHI:
PIXLOOP
    BSR  DECODE     ;     GET DY
    ADDB YY         ;     Y = Y + DY
    STB  YY
    LSLB
    LSLB
    LSLB
    ORB  ,X+        ;     PIXEL = (Y<<3) | JK_PIECE
    STB  VDAT       ;     SEND IT TO DISPLAY
    CMPX #(JHI+1)
    BLO  PIXLOOP    
    LDD  QCOUNT     ; PIXEL QUARTET COUNTDOWN
    DECD
    BNE  DRAWLOOP   ; LOOP UNTIL SCREEN FILLED.
    JMP  END_REPORT ; SHOW DECODE DURATION AND END PROGRAM.
; -----------------------------------------------------------------------------
; MATCH THE INPUT AT (U,REM,REMLEN) TO A HUF CODE, AND RETURN SIGNED BYTE 
; (DELTA) IN B. ON RETURN, (U,REM,REMLEN) ARE ADVANCED TO THE NEXT INPUT BIT.
; -----------------------------------------------------------------------------
DECODE:
    CLRD            ; CLEAR INPUT SHIFT-REGISTER
    LDF  REMLEN
    LDY  #CODETAB   ; POINT Y TO HUFFMAN CODE TABLE
DEC_LOOP:           ; PER EACH ROW OF CODE TABLE
    LDE  ,Y         ; NUM ADDL BITS OCCUPIED BY THIS CODE VS LAST ONE
    BEQ  COMPARE    ; IF WE HAVE ENOUGH INPUT BITS, GO TO COMPARISON.
SHLOOP:             ; LEFT-SHIFT IN E BITS OF INPUT INTO D
    TSTF
    BNE  GOTREM     ; HAVE BITS IN OUR LITTLE INPUT BUFFER BYTE?
    LDF  ,U+        ; READ ANOTHER BYTE INTO REM FROM INPUT AT U+
    STF  REM
    LDF  #8         ; REMLEN IS EIGHT BITS AGAIN.
GOTREM:
    LSL  REM        ; LEFT-SHIFT MSB FROM REM INTO LSB OF D
    ROLD
    DECF            ; REMLEN DECREASED
    DECE            ; NEEDED BITCOUNT DECREASED
    BNE  SHLOOP     ; KEEP SHIFTING  UNTIL NO BORE BITS NEEDED.
COMPARE:            ; COMPARE INPUT WORD TO HUFFMAN CODE.
    CMPD 1,Y        ; INWORD == CODE?
    BEQ  DEC_DONE   ; IF YES, WE'RE DONE.
    LEAY 4,Y        ; IF NOPE, TRY NEXT CODE OF TABLE.
    BRA  DEC_LOOP
DEC_DONE:
    STF  REMLEN
    LDB  3,Y        ; GET DECODED DELTA (SIGNED BYTE)
    RTS
; -----------------------------------------------------------------------------
; SIGN-EXTEND TO 8-BITS THE 6-BIT VALUE IN REG B
; -----------------------------------------------------------------------------
SEX6:
    STB  TMP8
    ANDB #$20
    BEQ  SEXDONE
    LDB  TMP8
    ORB  #$C0
    RTS
SEXDONE:
    LDB  TMP8
    RTS    
;------------------------------------------------------------------------------
; COPIES BITSTRING OF LEN. E FROM (U,REM,REMLEN) TO D, RIGHT-JUSTIFIED.
; ON RETURN, (U,REM,REMLEN) ARE ADVANCED TO NEXT BIT. 
;------------------------------------------------------------------------------
GET_BITS:
    CLRD            ; INIT DEST WORD
    LDF  REMLEN
GB_LOOP:
    TSTF
    BNE  GB_GOTREM
    LDF  ,U+
    STF  REM
    LDF  #8
GB_GOTREM:
    LSL  REM
    ROLD
    DECF    
    DECE    
    BNE  GB_LOOP
    STF  REMLEN
    RTS   
;------------------------------------------------------------------------------
; GIVEN I64'S AT X AND U, SUBTRACT U FROM X, LEAVING RESULT IN X.
;------------------------------------------------------------------------------
SUB64_XU:
    LDD  6,X
    SUBD 6,U
    STD  6,X
    LDD  4,X
    SBCD 4,U
    STD  4,X
    LDD  2,X
    SBCD 2,U
    STD  2,X
    LDD  0,X
    SBCD 0,U
    STD  0,X
    RTS
;------------------------------------------------------------------------------
; SHOW HOW LONG IT TOOK TO DECODE/DRAW THE IMAGE AND END THE PROGRAM.
;------------------------------------------------------------------------------
MSG_TOOK    FCB  LF,CR
            FCC  "*** Decode took "
            FCB  0
MSG_END     FCC  " ticks."
MSG_CR      FCB  LF,CR,LF,CR,0
; -----------------------------------------------------------------------------
END_REPORT
    LDX  #TEND          ; GET END TIME. 
    JSR  BF_RTC_GETTIX  
    LDU  #TSTART        ; CALC ELAPSED TICKS,
    JSR  SUB64_XU    
    LDY  #MSG_TOOK
    JSR  BF_UT_PUTS
    LDX  #SERBUF        ; AND PRINT IT OUT
    LDD  TEND+6
    JSR  BF_S_INTD      ; IN DECIMAL.
    LDA  #NUL
    STA  ,X+
    LDY  #SERBUF
    JSR  BF_UT_PUTS
    LDY  #MSG_END
    JSR  BF_UT_PUTS
    JSR  BF_UT_WAITTX
    RTS                 ; END OF PROGRAM
; -----------------------------------------------------------------------------
; ENCODED IMAGE AS OUTPUT BY CONV_YJK.PY
; -----------------------------------------------------------------------------
HUFFIMG:
    FCB $00,$1D,$18,$02,$7E,$2C,$12,$5F,$C0,$A0,$85,$2F,$41,$00,$C5,$1F
    FCB $80,$88,$41,$4D,$14,$53,$FD,$82,$78,$60,$4C,$74,$29,$D8,$E0,$9D
    FCB $10,$09,$C7,$20,$99,$92,$29,$94,$A0,$4C,$9B,$8A,$73,$F0,$09,$CD
    FCB $B0,$A7,$2F,$50,$4E,$51,$62,$9C,$91,$80,$9C,$8E,$80,$9C,$86,$02
    FCB $9C,$9C,$D1,$4E,$4D,$CC,$13,$93,$31,$33,$90,$3B,$6B,$6A,$6A,$FF
    FCB $37,$F2,$DC,$2F,$F2,$F1,$F6,$0E,$F9,$FC,$7B,$18,$F2,$F3,$C7,$BB
    FCB $9E,$62,$3D,$13,$37,$B2,$6F,$73,$FD,$FF,$FF,$7E,$4A,$4B,$26,$CF
    FCB $FF,$67,$FF,$E3,$FF,$FF,$FF,$DF,$FF,$3F,$FB,$DC,$FF,$FF,$FF,$72
    FCB $E7,$F7,$F8,$CF,$FF,$FF,$FF,$3F,$9F,$9C,$6F,$FB,$3F,$FF,$F8,$D3
    FCB $5C,$B6,$FF,$FD,$C9,$B7,$01,$5C,$BF,$19,$B3,$B9,$6F,$61,$EF,$2F
    FCB $0B,$F2,$EF,$C0,$7B,$35,$A5,$6A,$57,$FD,$FF,$FE,$CF,$FF,$FD,$F8
    FCB $D2,$58,$4E,$CF,$DF,$61,$FF,$FF,$FF,$FF,$DF,$CF,$BF,$FF,$DC,$6D
    FCB $52,$13,$FF,$F7,$8A,$3F,$3E,$FF,$EF,$CF,$FF,$CF,$F9,$FC,$FC,$F6
    FCB $CF,$FF,$EF,$FF,$AD,$49,$AC,$7D,$FF,$FF,$FF,$AD,$B9,$72,$5B,$3D
    FCB $BE,$3E,$32,$FC,$2C,$B7,$FF,$6B,$FB,$E6,$30,$47,$1A,$2E,$FF,$FF
    FCB $DB,$B2,$7F,$F6,$7B,$85,$75,$A3,$53,$66,$7F,$BE,$F9,$CF,$FF,$FF
    FCB $EF,$E7,$DF,$FF,$FD,$EE,$DB,$61,$05,$34,$83,$FF,$FF,$FF,$C7,$7F
    FCB $FF,$FF,$EC,$FE,$67,$FF,$FC,$FF,$FD,$FC,$FF,$E2,$93,$D1,$FB,$FF
    FCB $7F,$3F,$D2,$B9,$18,$DA,$B0,$57,$CE,$DF,$FE,$7D,$FE,$5E,$BF,$B7
    FCB $38,$C1,$1C,$6A,$56,$AF,$91,$FF,$BF,$9E,$DF,$87,$B8,$09,$F6,$BA
    FCB $9C,$B3,$FD,$F7,$3C,$FF,$FF,$FF,$7F,$3E,$FF,$FF,$EE,$F6,$DC,$C0
    FCB $A0,$D7,$48,$DF,$FF,$72,$E5,$C1,$DF,$DE,$7F,$FF,$FF,$9F,$CF,$FF
    FCB $9F,$FF,$FF,$FF,$D6,$A4,$F7,$7E,$EC,$78,$7F,$EF,$AD,$1B,$D4,$D4
    FCB $3D,$B0,$CB,$8F,$BF,$3E,$FE,$1B,$FF,$66,$E1,$D8,$C1,$1F,$53,$50
    FCB $C7,$FF,$FB,$F9,$FF,$DB,$FA,$E2,$7F,$37,$FF,$F7,$DD,$96,$46,$73
    FCB $FF,$FE,$FE,$7D,$FF,$FF,$DF,$75,$36,$6B,$26,$5B,$5D,$FF,$FD,$C9
    FCB $FF,$D5,$B8,$7F,$FF,$FF,$E5,$93,$FE,$FC,$3F,$FF,$FF,$FE,$B5,$27
    FCB $86,$DE,$7D,$FF,$D8,$F9,$D1,$ED,$B7,$FE,$7D,$FB,$FF,$FF,$0B,$EF
    FCB $93,$B7,$3E,$DA,$34,$A6,$D4,$36,$F7,$F3,$FF,$BF,$8F,$DC,$DB,$22
    FCB $30,$5B,$EF,$E7,$D5,$ED,$56,$82,$6A,$70,$95,$67,$F9,$F7,$FF,$CF
    FCB $BF,$FF,$FB,$FB,$AA,$4C,$FB,$DF,$9B,$D9,$D7,$FC,$FB,$DB,$B8,$65
    FCB $9F,$FE,$7F,$3F,$FF,$C7,$F3,$FF,$FF,$F8,$D3,$C2,$AD,$9F,$BC,$E7
    FCB $BF,$EB,$C6,$FF,$D9,$BD,$FF,$FF,$9F,$7B,$3B,$33,$F1,$FB,$12,$5D
    FCB $7B,$D4,$85,$FF,$3E,$F1,$9D,$F7,$F9,$2D,$62,$42,$83,$DF,$CF,$AB
    FCB $B6,$8A,$A4,$CA,$D1,$A3,$13,$20,$47,$E7,$DF,$FF,$3E,$FF,$FF,$EF
    FCB $FB,$9D,$9F,$FD,$DA,$B0,$AF,$FF,$9F,$57,$AB,$61,$39,$FC,$E7,$FF
    FCB $FF,$FF,$F7,$99,$FF,$FF,$14,$89,$BF,$FB,$FC,$EF,$64,$78,$E8,$D0
    FCB $FF,$3B,$77,$E1,$7B,$9F,$FD,$97,$67,$9F,$8F,$F4,$B3,$96,$D5,$EF
    FCB $9F,$7F,$FE,$FE,$4A,$DA,$D2,$1B,$3E,$EC,$FF,$65,$D4,$89,$A6,$68
    FCB $A9,$23,$13,$09,$88,$B7,$EF,$FF,$FF,$FF,$FF,$FF,$FB,$FF,$B0,$FB
    FCB $FF,$01,$DB,$72,$E0,$6F,$7F,$55,$4C,$7C,$86,$D6,$2E,$F0,$FB,$FB
    FCB $E7,$72,$6F,$FE,$71,$BF,$3E,$34,$55,$6F,$FB,$FE,$5F,$CB,$D5,$17
    FCB $9E,$16,$A7,$FC,$BC,$7F,$BE,$F3,$79,$32,$E7,$73,$B4,$86,$3E,$3A
    FCB $BD,$FF,$FF,$C7,$2F,$76,$6B,$47,$5E,$82,$45,$D8,$EC,$FF,$43,$6D
    FCB $33,$42,$89,$42,$D2,$12,$4C,$23,$12,$7F,$FF,$E7,$DF,$FF,$FF,$FF
    FCB $FF,$7F,$3F,$FB,$E7,$BF,$66,$71,$BF,$BE,$DB,$6E,$6D,$54,$92,$49
    FCB $6A,$9E,$3F,$EF,$3F,$B2,$32,$CB,$EF,$3F,$FE,$B5,$22,$77,$FF,$BD
    FCB $8C,$FF,$2F,$54,$5A,$5E,$EA,$5D,$57,$DC,$FF,$97,$BD,$9F,$79,$E5
    FCB $AF,$7F,$35,$8F,$B9,$D5,$DF,$E3,$1B,$D8,$16,$7F,$56,$25,$16,$27
    FCB $92,$59,$10,$5D,$D9,$FE,$86,$D3,$B4,$F2,$15,$31,$69,$0B,$5A,$64
    FCB $12,$7F,$FF,$B3,$FF,$FF,$FF,$8F,$FB,$8F,$FF,$FF,$FE,$DC,$D9,$9F
    FCB $CD,$F7,$F6,$F0,$B4,$D7,$5A,$D6,$97,$31,$DC,$BF,$3F,$CF,$BF,$FF
    FCB $FF,$EB,$52,$6B,$DF,$CB,$FE,$5B,$8F,$F6,$C8,$8C,$DD,$4A,$5D,$FB
    FCB $F8,$C8,$D8,$F5,$8D,$CB,$B8,$CF,$F2,$58,$EA,$95,$8E,$EC,$3D,$43
    FCB $BE,$73,$DF,$FC,$C5,$2C,$46,$28,$A9,$35,$38,$95,$1A,$BE,$7D,$10
    FCB $D0,$4C,$D0,$52,$AC,$16,$B5,$89,$F4,$C2,$4C,$E7,$FF,$FF,$FF,$FF
    FCB $FF,$FF,$DF,$FF,$FF,$FF,$77,$99,$FD,$9F,$EE,$E1,$6D,$05,$A4,$0C
    FCB $73,$EE,$5F,$FF,$87,$DF,$FF,$FF,$F4,$94,$9A,$F5,$7E,$FB,$93,$6C
    FCB $E5,$ED,$85,$69,$15,$29,$CB,$FF,$F0,$EF,$EF,$63,$9B,$39,$B2,$CC
    FCB $75,$62,$4D,$E3,$9C,$51,$6F,$BC,$CD,$FE,$7B,$5B,$5A,$31,$CB,$8E
    FCB $7B,$7F,$F6,$9A,$34,$E9,$12,$9A,$9C,$05,$AC,$13,$22,$36,$19,$FF
    FCB $FF,$7F,$3F,$F9,$F7,$F9,$ED,$FF,$FF,$BF,$F6,$7F,$38,$FF,$FD,$FC
    FCB $E7,$8E,$66,$F7,$FF,$FE,$7F,$FF,$FF,$F5,$A9,$3D,$63,$C7,$2F,$BE
    FCB $0D,$FE,$F8,$38,$B2,$DF,$6D,$6F,$23,$B6,$46,$0F,$77,$FE,$63,$CB
    FCB $D9,$18,$EF,$12,$F7,$F9,$D0,$7F,$E4,$7F,$EE,$44,$AB,$39,$EE,$7B
    FCB $7E,$FD,$A6,$89,$A9,$DA,$1A,$9C,$2B,$58,$D3,$84,$FB,$4F,$9F,$E7
    FCB $DF,$FF,$3F,$3F,$FF,$EF,$DF,$FF,$FD,$FD,$F7,$27,$39,$DF,$FD,$FC
    FCB $F0,$FF,$37,$BD,$FC,$F9,$3F,$FF,$FF,$F8,$A4,$F7,$78,$F6,$FF,$97
    FCB $23,$07,$B3,$C7,$9D,$8A,$2C,$B1,$63,$DB,$2A,$FF,$F1,$E6,$6F,$E3
    FCB $1D,$E2,$5E,$F9,$ED,$D4,$FF,$0F,$67,$D8,$B4,$66,$3D,$99,$CB,$DB
    FCB $F7,$EA,$4F,$09,$DA,$6A,$B6,$E0,$2D,$7A,$D3,$EA,$4C,$8B,$FF,$2C
    FCB $DF,$FF,$3E,$1E,$FF,$7F,$FB,$FF,$EF,$FF,$7E,$76,$67,$3D,$FF,$BF
    FCB $9C,$9E,$7E,$F7,$BF,$FE,$4E,$7F,$FF,$FF,$14,$9E,$EF,$FD,$F6,$38
    FCB $F5,$FB,$B6,$B2,$CA,$AB,$58,$ED,$BE,$00,$5D,$4D,$4B,$B5,$2F,$EC
    FCB $01,$EF,$CE,$FC,$BB,$94,$BB,$F3,$1A,$B6,$83,$76,$02,$4F,$86,$E3
    FCB $5A,$33,$3B,$6E,$1F,$BF,$EA,$36,$82,$6B,$4E,$D1,$3E,$E1,$58,$02
    FCB $7D,$A7,$D3,$F0,$7F,$FA,$B6,$EB,$AF,$9F,$FE,$7D,$F1,$D9,$78,$F7
    FCB $F3,$EF,$DF,$92,$E7,$CF,$7F,$EF,$E7,$3F,$3F,$EE,$DC,$FF,$93,$9F
    FCB $FF,$F7,$F5,$A9,$3D,$DF,$FB,$8E,$E7,$86,$ED,$B5,$97,$10,$AD,$1B
    FCB $63,$55,$77,$58,$EB,$A9,$A9,$9F,$F6,$4F,$F3,$7F,$18,$EE,$0B,$BB
    FCB $18,$5F,$40,$B4,$F2,$94,$45,$88,$D4,$BC,$91,$69,$05,$B3,$EF,$9F
    FCB $BF,$EA,$2E,$9D,$A6,$B4,$D4,$1F,$C2,$B0,$88,$DA,$34,$C0,$2D,$FF
    FCB $E8,$B4,$10,$46,$95,$7C,$F9,$F9,$FF,$F8,$DB,$1E,$F6,$4F,$BF,$BB
    FCB $93,$64,$FE,$5F,$F7,$F3,$33,$C7,$FE,$F7,$FF,$C9,$CF,$BF,$9F,$7F
    FCB $5A,$93,$DD,$FD,$F7,$25,$DB,$84,$DB,$86,$C5,$44,$6A,$B8,$16,$CB
    FCB $69,$50,$AA,$7F,$E4,$7F,$9D,$FF,$EC,$D2,$BF,$67,$D3,$4A,$09,$E6
    FCB $A3,$5A,$D3,$1A,$C0,$A4,$B9,$BE,$77,$73,$FB,$BF,$A8,$D4,$9D,$26
    FCB $B4,$4A,$B3,$85,$61,$11,$D6,$9C,$F1,$6C,$F7,$DA,$7A,$D3,$CD,$1A
    FCB $7C,$48,$83,$F3,$F3,$FF,$6C,$FD,$EF,$E7,$FE,$D5,$E1,$A0,$94,$FF
    FCB $8F,$F7,$F2,$7C,$FF,$F7,$BF,$FE,$4E,$7D,$FF,$F9,$EB,$41,$3D,$DF
    FCB $FD,$CF,$B7,$F1,$6A,$EF,$D8,$44,$94,$D6,$E1,$B5,$35,$DB,$B0,$2F
    FCB $78,$E1,$7B,$3F,$F3,$DE,$2E,$FB,$87,$A6,$DA,$6A,$2A,$87,$58,$94
    FCB $12,$49,$1D,$67,$EC,$FC,$2F,$6C,$BB,$FA,$06,$89,$3B,$44,$D1,$28
    FCB $97,$0A,$C1,$AD,$1C,$4E,$12,$62,$97,$C3,$6D,$3B,$A6,$A1,$46,$9F
    FCB $88,$E2,$DF,$87,$FF,$FF,$C6,$EF,$FF,$FF,$D5,$79,$75,$0B,$58,$FF
    FCB $2D,$FF,$F2,$7C,$DE,$7E,$F7,$66,$7F,$3F,$FF,$CF,$FD,$68,$27,$BB
    FCB $FD,$EF,$07,$EC,$F4,$9B,$7F,$E6,$B4,$28,$DE,$BD,$48,$0B,$6F,$B8
    FCB $EC,$3F,$1C,$FF,$EF,$3B,$C5,$F7,$E7,$A6,$8D,$3B,$42,$DE,$02,$CA
    FCB $D3,$08,$DA,$E3,$0C,$76,$7F,$64,$7D,$BF,$41,$76,$9E,$4D,$44,$A4
    FCB $14,$4B,$CA,$D7,$AD,$1C,$4F,$A7,$EB,$54,$D5,$DA,$24,$F2,$D1,$21
    FCB $13,$EA,$6B,$4C,$82,$5F,$FE,$79,$FF,$8D,$DF,$FF,$DE,$77,$B9,$DA
    FCB $24,$C1,$7F,$E3,$BF,$F9,$3E,$7F,$FB,$B7,$9F,$C3,$FF,$FF,$3C,$F8
    FCB $82,$7B,$BD,$9B,$FF,$B0,$CA,$A1,$65,$B9,$E0,$AA,$D7,$40,$BB,$63
    FCB $2C,$97,$DA,$09,$30,$2C,$EC,$1D,$D9,$8C,$D5,$AC,$79,$FE,$D1,$2D
    FCB $49,$DB,$6D,$58,$52,$91,$3F,$46,$9F,$C7,$CF,$BC,$B2,$5E,$DF,$A2
    FCB $5D,$A7,$48,$94,$A4,$1E,$FD,$62,$E5,$69,$44,$93,$8A,$D5,$94,$0B
    FCB $41,$12,$02,$0A,$6D,$25,$3A,$73,$A7,$08,$E7,$9F,$FF,$E7,$8D,$DE
    FCB $FF,$FF,$2F,$F7,$88,$96,$B9,$DF,$FF,$E2,$82,$7E,$67,$D5,$DF,$FF
    FCB $87,$E7,$DF,$87,$B7,$95,$A9,$3B,$EF,$FA,$48,$77,$49,$0C,$62,$DB
    FCB $98,$54,$A9,$E5,$C4,$92,$45,$AA,$CB,$B5,$B8,$ED,$AE,$B6,$CF,$FF
    FCB $FB,$F2,$AD,$67,$FF,$B4,$4B,$41,$3C,$AB,$7F,$5A,$E0,$94,$4C,$2E
    FCB $B7,$33,$EF,$B3,$DF,$F4,$D5,$D4,$99,$A0,$D4,$A7,$FD,$75,$EB,$17
    FCB $04,$C8,$2D,$4D,$82,$25,$D0,$52,$26,$D0,$53,$52,$DC,$4F,$A7,$32
    FCB $7E,$79,$FF,$FF,$F2,$EC,$6A,$7B,$DB,$DB,$98,$B5,$9F,$DB,$2B,$9D
    FCB $F7,$FF,$CC,$9F,$9F,$57,$7F,$FE,$1F,$FC,$3F,$F6,$E6,$B5,$27,$9C
    FCB $71,$51,$D2,$53,$D8,$37,$35,$D8,$A1,$60,$DA,$0E,$67,$58,$8E,$DA
    FCB $94,$FC,$14,$CD,$F6,$3F,$F3,$F3,$BE,$6A,$D2,$E7,$FD,$A6,$88,$93
    FCB $5D,$B7,$C5,$C0,$58,$2D,$30,$24,$AC,$9F,$F6,$77,$BF,$A6,$AD,$A2
    FCB $4F,$20,$D4,$A6,$37,$EB,$16,$C5,$8B,$94,$C8,$2D,$B3,$44,$29,$A9
    FCB $0B,$44,$A6,$C7,$12,$4E,$5A,$7C,$0F,$FF,$FF,$FD,$B2,$D4,$A5,$59
    FCB $6F,$79,$B4,$92,$59,$FE,$C9,$1F,$8D,$FF,$F3,$3F,$27,$DF,$77,$F3
    FCB $CF,$CF,$B3,$FF,$B3,$AD,$49,$E6,$0E,$37,$75,$DB,$EB,$BD,$D6,$32
    FCB $BA,$03,$AB,$3F,$5A,$31,$B6,$A7,$0E,$D0,$8D,$8C,$DF,$8F,$07,$C8
    FCB $EC,$7E,$E5,$3E,$67,$BF,$69,$B4,$F2,$6B,$B6,$F0,$1D,$60,$BA,$D6
    FCB $9F,$46,$A8,$76,$67,$D9,$7B,$7E,$82,$DA,$6A,$6A,$24,$14,$EF,$B0
    FCB $05,$EB,$17,$89,$C2,$4B,$53,$05,$27,$96,$DA,$91,$2D,$48,$94,$F2
    FCB $23,$4E,$74,$C5,$23,$FF,$F6,$FB,$98,$DA,$17,$B7,$EF,$7F,$B4,$96
    FCB $B1,$C5,$9F,$8C,$79,$77,$FF,$F1,$C3,$9F,$FD,$DF,$CE,$7F,$FE,$7D
    FCB $FC,$F1,$04,$1B,$B9,$7B,$2F,$02,$AB,$62,$F0,$6D,$EB,$61,$88,$41
    FCB $6B,$6D,$BD,$18,$EA,$52,$0E,$35,$BC,$BE,$C6,$B1,$45,$87,$6E,$37
    FCB $ED,$74,$80,$3D,$FB,$4D,$13,$C8,$9B,$6D,$F3,$80,$B0,$12,$46,$D1
    FCB $C2,$FF,$FE,$FE,$CA,$79,$74,$ED,$12,$26,$A7,$7F,$01,$6C,$58,$11
    FCB $1A,$61,$6A,$8D,$48,$96,$DA,$08,$A8,$20,$DC,$5D,$6B,$4E,$74,$C3
    FCB $46,$7F,$FD,$AB,$DA,$9A,$79,$49,$C5,$68,$1D,$FB,$6F,$FD,$95,$A9
    FCB $75,$A3,$59,$DC,$67,$67,$EF,$CD,$EF,$5F,$99,$FE,$DF,$CE,$7F,$FE
    FCB $7F,$FF,$88,$20,$DF,$F7,$1F,$60,$D5,$82,$D4,$17,$AA,$44,$86,$DB
    FCB $04,$86,$DB,$D6,$B2,$A4,$11,$57,$6C,$B2,$E3,$E5,$83,$5D,$F6,$0D
    FCB $DE,$C1,$27,$AE,$07,$6E,$9A,$B4,$D4,$D6,$EA,$7F,$1C,$69,$0B,$04
    FCB $FA,$92,$48,$8E,$30,$1F,$7F,$BB,$89,$AB,$69,$DA,$24,$14,$A7,$7F
    FCB $AC,$49,$D2,$09,$49,$38,$1E,$E8,$85,$34,$49,$A2,$94,$F0,$05,$A6
    FCB $13,$0D,$30,$7F,$BF,$68,$68,$22,$41,$B4,$12,$4F,$A4,$92,$07,$6F
    FCB $B9,$ED,$95,$13,$88,$D2,$5C,$6E,$73,$EF,$FB,$37,$EF,$F2,$61,$ED
    FCB $FF,$C9,$FF,$FF,$9F,$F1,$68,$26,$B6,$3F,$FB,$32,$AB,$61,$61,$ED
    FCB $D6,$12,$85,$62,$C6,$E5,$8B,$A9,$95,$3B,$8A,$50,$E5,$50,$05,$5C
    FCB $E3,$C7,$1B,$BA,$37,$26,$B6,$0F,$A6,$88,$93,$5B,$6D,$BC,$8E,$35
    FCB $82,$E8,$E2,$49,$0B,$7F,$8F,$FE,$EE,$27,$96,$D3,$A4,$10,$6A,$77
    FCB $B6,$56,$24,$C5,$80,$56,$9C,$F6,$2A,$D5,$6A,$4F,$22,$6A,$DD,$6B
    FCB $58,$27,$D3,$ED,$38,$3B,$F6,$5B,$41,$35,$A6,$A6,$AA,$BA,$34,$96
    FCB $8D,$24,$2B,$DB,$ED,$9F,$FF,$1D,$24,$92,$9F,$CF,$FE,$FF,$BE,$F1
    FCB $EF,$D6,$05,$FF,$F3,$F9,$FF,$FF,$73,$14,$9E,$FE,$C7,$D8,$77,$C1
    FCB $BB,$3A,$B1,$2E,$A5,$2D,$60,$DA,$D8,$B1,$F9,$AD,$AA,$D4,$85,$C6
    FCB $E2,$C6,$F9,$2D,$B5,$D8,$BD,$91,$B1,$F5,$30,$7D,$35,$6D,$13,$6D
    FCB $AB,$64,$C6,$B0,$04,$A5,$1A,$48,$D5,$EF,$F3,$FB,$89,$E1,$49,$D2
    FCB $0A,$52,$9D,$C7,$D7,$46,$E9,$04,$89,$92,$EE,$D8,$A4,$49,$E6,$D0
    FCB $B8,$B5,$AF,$46,$9F,$69,$90,$FF,$44,$34,$13,$C8,$90,$52,$9B,$17
    FCB $4C,$0B,$49,$24,$00,$BF,$F7,$DC,$E3,$94,$92,$03,$FF,$E7,$FF,$7E
    FCB $DF,$DB,$BC,$18,$04,$B9,$E7,$F3,$FF,$FE,$E6,$B5,$27,$71,$A9,$CE
    FCB $38,$C6,$3F,$5B,$66,$E5,$94,$AE,$D4,$2F,$A0,$05,$65,$42,$CC,$14
    FCB $A5,$2A,$BD,$6A,$DC,$54,$25,$07,$8B,$68,$3A,$4B,$CA,$94,$FF,$9F
    FCB $4F,$24,$A5,$36,$DA,$9F,$FD,$6B,$0A,$EB,$88,$D1,$A8,$E7,$DE,$6F
    FCB $B1,$3C,$B4,$13,$A4,$1B,$53,$B9,$60,$56,$C4,$A2,$C8,$9C,$F5,$46
    FCB $A7,$52,$79,$15,$BB,$82,$D7,$A3,$4C,$34,$C9,$2F,$B6,$9A,$27,$93
    FCB $54,$A6,$9B,$B5,$A4,$92,$49,$08,$D6,$88,$0B,$63,$BC,$73,$1E,$16
    FCB $44,$A9,$67,$CF,$FF,$CF,$BD,$5E,$DE,$F6,$A6,$F5,$8B,$5E,$B3,$3F
    FCB $CF,$FF,$FB,$9A,$D4,$9D,$F7,$F6,$F8,$6E,$77,$FC,$70,$79,$8A,$B8
    FCB $15,$B1,$49,$2C,$6C,$B5,$08,$6E,$B4,$04,$B5,$2A,$11,$57,$D6,$AF
    FCB $19,$BF,$FF,$E9,$E4,$74,$55,$35,$29,$FF,$D6,$2C,$71,$64,$4C,$22
    FCB $47,$8C,$61,$37,$B0,$7A,$78,$41,$3C,$89,$B5,$3B,$96,$11,$28,$B2
    FCB $11,$38,$6C,$B6,$DA,$24,$F2,$B7,$75,$8B,$0A,$D3,$0A,$4E,$63,$50
    FCB $EA,$4E,$D3,$68,$94,$F4,$38,$92,$D2,$48,$46,$B4,$40,$75,$35,$DB
    FCB $1C,$25,$E7,$AD,$74,$B0,$FF,$FC,$7C,$FF,$FD,$56,$ED,$4A,$B6,$CE
    FCB $2D,$6B,$5C,$9E,$47,$FF,$F9,$7E,$B5,$27,$9D,$B7,$3F,$FE,$47,$DB
    FCB $CF,$3F,$51,$20,$F2,$45,$DF,$6B,$68,$6E,$C3,$7C,$EE,$E3,$FC,$67
    FCB $DF,$D9,$D6,$9E,$49,$24,$CE,$EA,$43,$66,$CB,$5D,$66,$01,$4F,$A2
    FCB $5A,$FF,$92,$38,$1D,$3B,$5A,$24,$F2,$0D,$A0,$EE,$58,$14,$98,$B5
    FCB $84,$13,$0D,$95,$36,$D3,$A5,$3D,$D8,$56,$00,$98,$41,$39,$8D,$05
    FCB $B5,$27,$48,$20,$D4,$FA,$B0,$49,$69,$2D,$68,$C4,$50,$63,$78,$F6
    FCB $00,$AA,$FB,$35,$A5,$59,$3F,$FF,$FE,$7F,$FD,$F7,$6E,$DB,$6D,$DB
    FCB $00,$5A,$D6,$1E,$7D,$8E,$7F,$FA,$D4,$9D,$ED,$4C,$FF,$9F,$FF,$D6
    FCB $DE,$39,$1B,$B8,$31,$D6,$CC,$23,$59,$53,$77,$C1,$BF,$37,$FF,$FF
    FCB $1F,$EA,$5E,$92,$D3,$56,$D3,$CA,$6D,$4A,$77,$FC,$2B,$29,$6B,$A3
    FCB $45,$48,$76,$5A,$28,$D3,$EB,$AF,$94,$ED,$24,$D4,$D4,$1B,$41,$BC
    FCB $B0,$29,$31,$6B,$95,$89,$FC,$6D,$35,$A9,$35,$5E,$E0,$02,$E2,$7D
    FCB $49,$CD,$D3,$56,$A4,$CD,$4D,$A0,$AF,$EB,$5A,$42,$54,$91,$89,$A3
    FCB $72,$C2,$C7,$5B,$58,$AA,$CD,$9D,$75,$95,$FD,$FC,$FF,$F9,$FF,$FD
    FCB $F6,$D0,$55,$B7,$7B,$A4,$90,$B5,$87,$F1,$CF,$FF,$5A,$93,$BB,$B6
    FCB $7F,$DF,$FF,$E7,$C6,$15,$63,$D8,$93,$B5,$B1,$99,$58,$D0,$6B,$1A
    FCB $8F,$7F,$EC,$FF,$EF,$3D,$C6,$D6,$23,$1A,$6A,$DA,$6A,$94,$DB,$56
    FCB $37,$D8,$45,$D2,$EB,$49,$08,$B8,$CA,$24,$F3,$B4,$69,$81,$2E,$09
    FCB $D2,$49,$E4,$48,$3A,$0D,$FB,$00,$49,$89,$00,$02,$35,$35,$B5,$27
    FCB $7A,$2F,$6E,$10,$5C,$4C,$34,$C8,$50,$4F,$09,$DA,$0A,$D0,$7C,$E9
    FCB $0B,$12,$16,$8D,$68,$9D,$EE,$72,$0A,$58,$A0,$5B,$6C,$94,$9A,$CA
    FCB $FF,$D9,$FE,$7D,$9F,$FF,$F8,$EA,$BB,$6A,$55,$B6,$78,$B5,$A4,$BC
    FCB $3E,$F3,$FA,$D4,$9D,$DD,$E3,$D9,$BC,$EF,$DE,$19,$FD,$F6,$E2,$56
    FCB $33,$62,$ED,$AC,$B9,$76,$DA,$FD,$B9,$CB,$FE,$5F,$D8,$F5,$C4,$BA
    FCB $25,$B4,$48,$35,$35,$37,$B7,$64,$35,$D2,$3A,$D0,$59,$58,$ED,$35
    FCB $06,$34,$96,$9F,$49,$44,$A7,$68,$D3,$C8,$94,$E8,$2B,$EC,$01,$71
    FCB $6B,$17,$58,$92,$AB,$52,$6A,$6D,$4A,$1B,$F5,$E0,$BA,$D1,$B4,$E7
    FCB $14,$9D,$26,$AD,$05,$58,$8B,$C2,$24,$2E,$B5,$89,$2D,$13,$2F,$38
    FCB $11,$02,$C8,$D8,$62,$55,$93,$EF,$E7,$FC,$FF,$FF,$FF,$BE,$ED,$DB
    FCB $6A,$53,$B8,$62,$D6,$B5,$99,$CF,$EB,$41,$3B,$7A,$A3,$87,$7C,$EF
    FCB $E4,$EF,$D9,$F7,$A5,$AB,$A5,$F4,$1A,$C1,$84,$DA,$87,$FF,$F7,$9C
    FCB $AB,$1E,$BA,$D7,$77,$1A,$0B,$A9,$13,$53,$53,$7B,$6F,$86,$56,$BE
    FCB $31,$6D,$21,$D4,$9A,$83,$05,$89,$23,$41,$29,$4E,$D1,$A7,$90,$53
    FCB $A0,$AF,$B0,$58,$93,$12,$00,$05,$AA,$B6,$99,$A1,$57,$7C,$22,$C5
    FCB $B4,$86,$9C,$53,$A5,$21,$53,$71,$0F,$00,$5A,$D6,$2C,$A3,$5A,$6D
    FCB $9D,$AE,$D6,$35,$B7,$8C,$BC,$22,$EB,$27,$FF,$FF,$CF,$E7,$DF,$E7
    FCB $DF,$BE,$EA,$53,$6D,$F7,$80,$2D,$6B,$31,$F1,$82,$09,$DD,$E7,$D9
    FCB $67,$FB,$3C,$71,$F7,$FF,$5B,$05,$6B,$05,$DA,$95,$FE,$1C,$A9,$8C
    FCB $CD,$F6,$7E,$E7,$AD,$AE,$BE,$F4,$4B,$D3,$D5,$54,$D4,$EA,$DB,$C2
    FCB $52,$0F,$08,$B4,$16,$A4,$D4,$14,$B1,$75,$A3,$41,$25,$8A,$4F,$23
    FCB $44,$82,$9D,$05,$7F,$17,$4A,$2D,$6B,$02,$B5,$56,$9E,$4D,$55,$EF
    FCB $71,$6C,$16,$34,$FB,$11,$A7,$6A,$55,$4E,$F5,$7A,$D6,$B1,$6B,$21
    FCB $46,$B4,$DF,$D8,$56,$3B,$5B,$0A,$D0,$BC,$8B,$AC,$9F,$FF,$FC,$73
    FCB $F3,$EC,$F3,$ED,$FF,$EA,$DB,$B5,$36,$EF,$C5,$8B,$00,$2C,$AD,$04
    FCB $E8,$DF,$67,$70,$EF,$9F,$CB,$BD,$E3,$0F,$2A,$AD,$76,$BA,$9B,$3D
    FCB $91,$2B,$71,$AE,$D7,$55,$D4,$CF,$CE,$63,$60,$B4,$16,$7D,$05,$E9
    FCB $AA,$45,$75,$31,$4E,$FF,$5B,$4A,$BC,$21,$A8,$69,$AA,$71,$60,$9F
    FCB $50,$8C,$69,$E4,$93,$C8,$37,$41,$5F,$D6,$09,$44,$96,$12,$2A,$27
    FCB $68,$36,$AE,$C2,$2F,$02,$8D,$88,$29,$A8,$42,$FA,$BA,$D6,$BA,$D6
    FCB $12,$24,$B4,$F1,$B1,$61,$F5,$2D,$1D,$75,$24,$8A,$A7,$35,$D2,$D7
    FCB $FF,$FE,$7D,$E7,$3F,$3F,$F6,$F3,$DC,$55,$AD,$DB,$53,$76,$EF,$3D
    FCB $6B,$5A,$CD,$68,$27,$7B,$64,$B1,$FE,$58,$FF,$CB,$2C,$63,$B8,$5E
    FCB $2D,$41,$A9,$75,$30,$77,$A5,$17,$42,$2E,$56,$5D,$BB,$63,$B7,$EF
    FCB $C6,$45,$32,$C5,$8A,$48,$68,$94,$88,$6D,$A8,$42,$EC,$19,$14,$01
    FCB $AE,$11,$5A,$6A,$94,$56,$51,$A0,$92,$D6,$A4,$49,$22,$41,$BA,$0A
    FCB $DE,$02,$C4,$6D,$69,$12,$45,$34,$11,$29,$8A,$DE,$45,$D8,$13,$53
    FCB $54,$53,$F5,$62,$C5,$80,$2D,$80,$B5,$A6,$8C,$62,$C2,$E3,$04,$FA
    FCB $A2,$84,$4B,$6E,$45,$8B,$CF,$FF,$FE,$7F,$FF,$FE,$47,$BF,$3E,$A8
    FCB $BB,$76,$ED,$A9,$D4,$38,$DD,$64,$58,$92,$93,$D7,$9F,$79,$FF,$F7
    FCB $8E,$17,$B7,$07,$95,$AF,$75,$28,$E5,$58,$2E,$5A,$81,$78,$1B,$BB
    FCB $7B,$6F,$8A,$B7,$B8,$D4,$1C,$A9,$21,$74,$D4,$16,$DB,$62,$0E,$DE
    FCB $C0,$6B,$1A,$F5,$E1,$75,$20,$A6,$E2,$E9,$35,$AC,$A0,$B4,$D5,$55
    FCB $41,$5B,$C1,$60,$95,$69,$6B,$91,$4D,$3B,$6D,$8A,$DD,$AE,$B5,$E5
    FCB $6A,$78,$A6,$C4,$32,$36,$2C,$17,$59,$14,$02,$D6,$88,$D8,$16,$E6
    FCB $B4,$6D,$DD,$44,$F5,$A5,$D7,$FF,$DF,$CC,$FF,$FF,$FC,$BF,$FF,$15
    FCB $8B,$51,$7D,$B6,$83,$15,$2D,$DF,$13,$ED,$0B,$BC,$FF,$FC,$FF,$FD
    FCB $C7,$E6,$4E,$DB,$F3,$C5,$8A,$62,$85,$C1,$C8,$5B,$D4,$FB,$ED,$A0
    FCB $AF,$9B,$E1,$D2,$A3,$A7,$93,$52,$76,$D6,$A5,$5E,$DE,$35,$AF,$2B
    FCB $C2,$ED,$12,$9B,$62,$C5,$C4,$B5,$08,$95,$55,$05,$6E,$02,$C1,$2A
    FCB $49,$39,$2A,$53,$4D,$6E,$2B,$76,$B0,$5E,$17,$B6,$DB,$15,$33,$17
    FCB $AC,$59,$5A,$22,$92,$D2,$54,$53,$B1,$DC,$AE,$38,$FE,$0C,$5A,$7D
    FCB $BA,$FF,$FB,$F9,$CF,$67,$F0,$FF,$DF,$DB,$3B,$B5,$8C,$DD,$7A,$AE
    FCB $83,$FB,$B5,$34,$FB,$55,$DE,$7F,$9F,$BF,$9E,$FE,$78,$CC,$66,$DD
    FCB $B0,$9C,$6D,$C5,$B5,$8B,$AB,$ED,$EF,$D4,$EA,$63,$7D,$F1,$81,$19
    FCB $49,$65,$12,$6A,$36,$DC,$41,$4E,$EE,$E3,$5A,$ED,$75,$F1,$C6,$89
    FCB $55,$62,$C8,$96,$A5,$A2,$55,$42,$25,$6E,$B0,$58,$2C,$49,$6D,$86
    FCB $9E,$6D,$4F,$15,$BB,$58,$B3,$0B,$B6,$DB,$AD,$53,$35,$AD,$8B,$02
    FCB $B4,$40,$8D,$6B,$51,$4D,$B6,$3B,$17,$58,$B5,$0D,$05,$71,$21,$69
    FCB $52,$56,$7F,$F7,$F3,$FB,$0F,$F3,$CF,$BF,$14,$DC,$BB,$AF,$6F,$58
    FCB $3E,$A5,$4B,$DB,$A9,$30,$D1,$3D,$53,$76,$7D,$98,$7F,$EF,$FE,$7F
    FCB $EF,$E1,$ED,$AD,$C8,$B1,$25,$5B,$AA,$FE,$C6,$A6,$AC,$6D,$F3,$CA
    FCB $F1,$75,$8D,$68,$93,$51,$A1,$71,$4D,$5D,$4D,$C6,$B0,$EB,$31,$CA
    FCB $6A,$9A,$B1,$6B,$05,$8D,$01,$05,$54,$B4,$4A,$DD,$60,$B5,$8B,$12
    FCB $1B,$95,$26,$B6,$EA,$2F,$65,$60,$5A,$CB,$75,$3B,$AD,$4B,$EB,$8B
    FCB $EB,$0C,$44,$23,$4F,$B4,$94,$DA,$21,$51,$46,$B7,$13,$55,$41,$4E
    FCB $BA,$D1,$A6,$13,$E9,$7C,$FF,$EF,$E6,$D9,$87,$3E,$FC,$3D,$BF,$41
    FCB $B0,$1B,$D8,$16,$C2,$74,$18,$C9,$6F,$4F,$B4,$ED,$EF,$F6,$59,$F8
    FCB $7B,$FF,$67,$3F,$DF,$FC,$1E,$E0,$E4,$D6,$CD,$8A,$52,$0D,$F5,$BA
    FCB $19,$BF,$0C,$C2,$B4,$AB,$41,$75,$26,$A3,$4D,$15,$15,$53,$D4,$DC
    FCB $6B,$0E,$B9,$B8,$22,$41,$B6,$56,$02,$D6,$A7,$52,$A8,$08,$9E,$EB
    FCB $04,$97,$58,$B3,$E9,$AA,$6D,$BF,$D9,$5A,$F1,$C6,$F6,$F1,$6A,$06
    FCB $02,$C7,$09,$16,$9A,$98,$4A,$80,$ED,$05,$B8,$85,$A9,$68,$90,$55
    FCB $DF,$4A,$92,$49,$F4,$E1,$2F,$9F,$FD,$FF,$6E,$10,$C3,$FF,$6F,$2E
    FCB $EE,$A5,$6B,$18,$CB,$22,$A3,$70,$70,$17,$8A,$51,$4F,$A9,$33,$71
    FCB $BB,$FC,$DF,$9F,$67,$EC,$3D,$8F,$D9,$C6,$4E,$EF,$2E,$17,$29,$2D
    FCB $35,$4B,$52,$6A,$0D,$41,$01,$44,$16,$86,$5C,$C1,$2A,$4D,$56,$F4
    FCB $91,$27,$D0,$6D,$DD,$AB,$53,$B2,$B2,$5A,$E6,$E0,$89,$4D,$BC,$8B
    FCB $17,$D0,$55,$01,$13,$D8,$B1,$6B,$5B,$5A,$C3,$DA,$79,$B7,$6C,$EE
    FCB $BA,$C3,$6C,$6D,$9C,$58,$A3,$16,$B3,$F2,$B5,$A6,$A6,$2D,$43,$14
    FCB $D6,$C4,$14,$82,$08,$96,$A7,$8F,$89,$09,$2D,$1A,$70,$93,$39,$FF
    FCB $DF,$BE,$E1,$5F,$FE,$63,$B9,$52,$BE,$D5,$23,$59,$C6,$A9,$6F,$16
    FCB $2C,$9D,$A1,$49,$1A,$09,$CA,$B1,$D8,$F9,$F6,$67,$DF,$CF,$B7,$19
    FCB $1C,$EE,$7B,$FC,$C2,$EE,$96,$A4,$16,$A4,$F2,$0D,$4B,$0F,$01,$A4
    FCB $88,$02,$A0,$C2,$AE,$62,$7D,$12,$7D,$04,$1B,$6F,$54,$53,$77,$5A
    FCB $CD,$AD,$AF,$78,$A4,$1B,$79,$16,$0B,$D1,$2A,$A1,$12,$BD,$60,$92
    FCB $C4,$80,$A9,$D1,$20,$EA,$BE,$58,$45,$F8,$35,$6C,$AC,$5A,$8D,$62
    FCB $FB,$E5,$1A,$D3,$52,$AA,$3D,$01,$04,$91,$22,$52,$95,$F1,$F5,$A4
    FCB $25,$4F,$A7,$09,$33,$9F,$7F,$FB,$7B,$16,$BF,$FE,$F0,$ED,$B6,$E7
    FCB $7B,$5E,$D7,$14,$F8,$ED,$A4,$0B,$5E,$CD,$AA,$B4,$90,$4C,$B7,$79
    FCB $79,$7E,$7F,$FF,$FF,$1F,$E7,$FB,$E7,$07,$6C,$5C,$65,$A0,$B5,$22
    FCB $44,$A4,$08,$36,$B3,$16,$80,$0B,$5A,$0B,$B6,$3F,$17,$A4,$8D,$35
    FCB $3E,$D3,$D4,$1C,$B6,$21,$6F,$58,$6C,$D6,$D9,$14,$A5,$54,$D7,$D7
    FCB $58,$69,$B5,$08,$95,$C5,$8B,$5A,$DA,$C5,$8D,$E9,$E5,$6D,$FD,$C5
    FCB $B0,$61,$2D,$C7,$58,$2D,$EB,$02,$FB,$E2,$48,$23,$1A,$DD,$B4,$D4
    FCB $11,$2D,$05,$3D,$5E,$BF,$49,$62,$E9,$F4,$E1,$26,$7F,$B7,$39,$BF
    FCB $C0,$3E,$C6,$5E,$B8,$EA,$40,$7F,$B7,$C8,$1B,$71,$AB,$5A,$F5,$83
    FCB $66,$74,$90,$4E,$55,$DF,$37,$7C,$39,$F6,$FF,$F8,$3F,$E6,$C7,$E3
    FCB $9C,$6E,$4B,$97,$52,$4D,$48,$91,$21,$6C,$2B,$E3,$C0,$46,$88,$5E
    FCB $3D,$95,$C4,$E1,$A0,$8D,$A6,$B5,$2A,$CA,$85,$5D,$B2,$BE,$5A,$C6
    FCB $31,$4A,$55,$A8,$30,$16,$44,$D6,$A1,$12,$B8,$B5,$89,$2D,$A4,$1B
    FCB $6A,$4D,$7B,$71,$EC,$0A,$F0,$ED,$97,$5A,$EB,$70,$86,$FE,$D6,$8D
    FCB $12,$49,$29,$A2,$28,$93,$CD,$43,$7D,$5E,$BE,$2D,$25,$AE,$98,$4C
    FCB $2D,$53,$FD,$FB,$3F,$EB,$87,$D9,$49,$AB,$37,$45,$7F,$86,$FD,$78
    FCB $A5,$6D,$71,$9A,$C2,$D6,$E6,$D1,$A0,$9C,$AB,$B6,$5C,$3D,$CF,$FD
    FCB $FC,$FF,$FE,$7F,$EE,$19,$6F,$05,$5C,$1A,$4A,$52,$6A,$24,$2D,$C6
    FCB $B3,$B0,$94,$94,$41,$24,$03,$AC,$4F,$AD,$A9,$26,$82,$2A,$02,$8B
    FCB $14,$EF,$B5,$EC,$EB,$63,$1A,$0A,$B5,$04,$00,$1A,$D0,$41,$42,$0A
    FCB $F1,$6B,$49,$74,$A6,$A6,$9A,$A7,$1A,$8E,$30,$19,$25,$DC,$5B,$16
    FCB $4C,$20,$F8,$3B,$16,$9A,$98,$B5,$26,$A4,$9E,$44,$F6,$FD,$5E,$BE
    FCB $B1,$25,$AE,$9C,$27,$D6,$A3,$EC,$DE,$D4,$AD,$23,$DA,$92,$5A,$FE
    FCB $E2,$45,$F6,$82,$9E,$AA,$CC,$B8,$F3,$96,$F5,$B9,$2F,$58,$C7,$5D
    FCB $D3,$E8,$27,$25,$77,$97,$65,$F3,$79,$E5,$8F,$3F,$FE,$3F,$F1,$8C
    FCB $3B,$6C,$5E,$A9,$5D,$A4,$A4,$49,$AA,$42,$D5,$B5,$86,$F9,$84,$A7
    FCB $D3,$45,$C1,$69,$F4,$FA,$15,$2E,$A4,$DA,$0B,$57,$A9,$5C,$B9,$67
    FCB $18,$5A,$0A,$B5,$04,$AC,$DA,$4A,$41,$05,$A0,$A8,$C1,$69,$24,$34
    FCB $A6,$A6,$9E,$55,$96,$7B,$17,$64,$37,$60,$B6,$B3,$58,$1E,$F9,$7A
    FCB $E8,$24,$D1,$22,$41,$25,$29,$EA,$FA,$88,$D7,$62,$C4,$96,$BA,$70
    FCB $8D,$6A,$3F,$BB,$F3,$B1,$EA,$71,$75,$85,$51,$60,$F6,$A6,$DB,$B8
    FCB $0C,$2F,$C3,$AB,$0B,$F0,$D6,$31,$CD,$04,$68,$26,$77,$73,$76,$59
    FCB $8E,$E4,$BF,$39,$BF,$3B,$1F,$CE,$CB,$F8,$E4,$1B,$9A,$91,$A9,$35
    FCB $05,$2A,$D4,$EC,$23,$93,$6B,$5B,$89,$20,$02,$7D,$26,$98,$6E,$D6
    FCB $DA,$0A,$4D,$5B,$78,$A6,$F3,$60,$F7,$1A,$CB,$52,$AA,$51,$80,$03
    FCB $58,$9A,$80,$82,$8E,$B5,$A4,$91,$5B,$2A,$53,$4D,$76,$38,$DC,$8B
    FCB $B5,$D7,$D5,$6B,$5A,$D8,$6B,$0F,$BF,$BD,$1A,$9A,$91,$29,$4C,$6D
    FCB $83,$F1,$DA,$4C,$A8,$5A,$D6,$C1,$30,$8D,$26,$32,$F7,$97,$2E,$3E
    FCB $D5,$70,$22,$4E,$2F,$6D,$68,$28,$DB,$32,$E9,$71,$EE,$EC,$07,$98
    FCB $B6,$EB,$3F,$6A,$49,$04,$EA,$ED,$E7,$FF,$FE,$F9,$B3,$D9,$1A,$D6
    FCB $DB,$9B,$3E,$CE,$EB,$A0,$E9,$73,$DA,$48,$90,$52,$95,$53,$6E,$65
    FCB $46,$64,$86,$56,$9F,$52,$73,$9B,$B6,$A4,$11,$24,$DF,$55,$B9,$DA
    FCB $D9,$B1,$40,$34,$1D,$4A,$8C,$02,$B6,$B5,$A2,$44,$20,$FD,$69,$24
    FCB $96,$BE,$9A,$A6,$86,$CF,$7D,$65,$80,$46,$EB,$58,$C3,$02,$E6,$EF
    FCB $B2,$A1,$13,$6D,$B7,$35,$5E,$BB,$16,$CB,$16,$B5,$B0,$4C,$2D,$6D
    FCB $74,$0D,$6F,$EF,$C1,$BB,$76,$03,$05,$B8,$8E,$29,$A9,$53,$53,$21
    FCB $62,$DB,$5F,$2D,$02,$1D,$F5,$A4,$F6,$BB,$C6,$A6,$B4,$13,$CD,$EC
    FCB $BC,$3D,$FC,$EE,$C8,$D9,$0A,$81,$40,$93,$55,$9B,$2F,$F7,$95,$A9
    FCB $86,$2E,$F6,$20,$A5,$29,$05,$A9,$56,$DB,$C6,$BE,$4C,$C3,$A3,$50
    FCB $9F,$4F,$D6,$AB,$52,$93,$51,$B6,$F7,$76,$3F,$61,$B6,$05,$05,$54
    FCB $DD,$8B,$20,$D6,$B5,$27,$96,$83,$CA,$D2,$49,$7A,$F6,$9A,$A6,$AB
    FCB $8F,$B6,$0B,$35,$CC,$55,$6B,$06,$62,$CB,$E5,$BB,$BB,$68,$5B,$53
    FCB $19,$B1,$4F,$91,$7A,$EC,$5A,$C5,$51,$A3,$AD,$A5,$4D,$42,$C5,$AC
    FCB $AC,$7E,$BD,$5D,$D9,$0A,$D5,$00,$6D,$53,$6F,$C6,$05,$91,$C7,$75
    FCB $8B,$53,$F4,$8E,$E2,$97,$55,$C4,$13,$D7,$6C,$F3,$EF,$FB,$3F,$BD
    FCB $7B,$5E,$B0,$6D,$4A,$0D,$FF,$BC,$58,$F1,$B0,$6C,$5A,$84,$4D,$4D
    FCB $05,$A9,$4D,$B6,$F1,$AF,$93,$93,$2B,$E9,$27,$08,$D1,$0D,$4D,$35
    FCB $3E,$A6,$F7,$76,$2A,$3B,$0D,$B0,$28,$2A,$A6,$A1,$42,$E0,$B8,$BA
    FCB $79,$68,$28,$60,$B4,$92,$5D,$46,$82,$26,$DD,$D6,$F7,$50,$2E,$56
    FCB $71,$D2,$58,$3C,$9B,$C5,$BB,$A1,$75,$3A,$A8,$33,$B6,$0A,$78,$BA
    FCB $E3,$06,$B5,$8B,$40,$4C,$12,$2D,$A0,$D4,$D4,$45,$A4,$BF,$39,$71
    FCB $0E,$BB,$55,$62,$C7,$73,$53,$DC,$D7,$90,$7E,$A1,$71,$AA,$F4,$7A
    FCB $E8,$0D,$EE,$EB,$41,$36,$C6,$FB,$CF,$F3,$7E,$7F,$95,$1A,$4B,$1A
    FCB $95,$65,$E6,$FB,$82,$FB,$77,$32,$CA,$0A,$69,$A9,$35,$36,$29,$BD
    FCB $41,$95,$FC,$3E,$41,$30,$89,$1A,$DD,$12,$35,$5B,$6F,$7B,$67,$3D
    FCB $8C,$10,$42,$DA,$AC,$5C,$AE,$B0,$41,$68,$26,$92,$B4,$92,$5B,$63
    FCB $A2,$55,$B7,$8F,$75,$2C,$5C,$0C,$D4,$23,$27,$21,$7C,$6F,$55,$B6
    FCB $AA,$95,$ED,$F1,$BD,$6B,$0A,$D4,$6B,$5D,$68,$92,$49,$62,$C6,$96
    FCB $F6,$D5,$B4,$97,$FC,$B6,$76,$17,$4B,$AA,$C3,$57,$72,$71,$D6,$76
    FCB $A5,$AF,$6F,$D7,$51,$1B,$6A,$B9,$49,$04,$D7,$DF,$FF,$FE,$E1,$2F
    FCB $B9,$6A,$22,$C3,$A9,$47,$FE,$38,$36,$7D,$98,$32,$29,$12,$6A,$4A
    FCB $6A,$50,$AB,$B5,$18,$57,$F2,$6E,$30,$4F,$A1,$5A,$31,$4B,$6A,$75
    FCB $17,$62,$99,$FE,$D7,$88,$21,$6D,$43,$09,$5D,$75,$B5,$A0,$9E,$3A
    FCB $D1,$AC,$A8,$B4,$F6,$DD,$C5,$6C,$69,$04,$87,$14,$92,$44,$B3,$0B
    FCB $B6,$5E,$DA,$9A,$95,$EE,$29,$97,$7A,$D6,$B5,$B0,$50,$D6,$15,$A2
    FCB $46,$09,$03,$17,$3F,$EE,$E7,$5F,$3F,$15,$49,$A9,$FA,$C5,$2B,$35
    FCB $B9,$B4,$04,$B3,$D7,$40,$7D,$6D,$85,$B6,$D0,$54,$16,$8D,$A6,$7F
    FCB $FF,$7B,$3F,$9E,$FF,$2C,$C3,$B7,$37,$F9,$FD,$EC,$24,$DA,$DC,$A6
    FCB $A4,$9E,$53,$62,$9B,$B6,$DC,$B5,$CE,$BC,$BC,$62,$4E,$2D,$1D,$8A
    FCB $6D,$AE,$FA,$9C,$73,$D9,$88,$21,$6D,$56,$04,$00,$29,$20,$9B,$91
    FCB $24,$B5,$14,$11,$6A,$77,$1E,$C6,$92,$F2,$18,$29,$1A,$C6,$7C,$2E
    FCB $D8,$D9,$6A,$41,$07,$EE,$C7,$2F,$8B,$17,$2A,$5A,$C2,$02,$79,$3E
    FCB $00,$54,$8D,$81,$F9,$BD,$EB,$9F,$F5,$52,$6A,$BC,$5D,$B6,$72,$76
    FCB $C0,$0B,$14,$54,$0A,$F1,$ED,$B1,$05,$57,$13,$ED,$33,$BB,$9C,$DF
    FCB $64,$7C,$7F,$FC,$B3,$F3,$66,$FE,$3C,$1E,$DE,$2C,$06,$EC,$F4,$D4
    FCB $68,$22,$B6,$DB,$7A,$AF,$6B,$3C,$F6,$19,$C8,$92,$91,$8D,$A9,$6E
    FCB $E2,$AE,$6F,$1A,$DC,$41,$0B,$6A,$B0,$30,$5D,$74,$91,$29,$00,$AD
    FCB $25,$EA,$29,$E7,$A9,$DD,$6E,$E2,$96,$BC,$AC,$D6,$29,$3E,$39,$F9
    FCB $6F,$1B,$10,$52,$91,$6D,$7D,$EC,$BF,$48,$12,$2E,$BB,$1A,$C5,$A6
    FCB $A7,$E4,$0A,$36,$B1,$F7,$A9,$67,$6C,$27,$FD,$51,$EE,$B0,$B6,$EC
    FCB $E7,$C8,$17,$65,$40,$AC,$14,$F7,$28,$28,$E9,$F6,$9D,$5D,$B3,$01
    FCB $B9,$78,$F8,$FF,$C1,$F7,$98,$FF,$FF,$36,$3B,$85,$60,$EF,$B3,$4F
    FCB $23,$68,$95,$76,$AE,$ED,$D9,$39,$EC,$3B,$59,$28,$D0,$A4,$B6,$A5
    FCB $BB,$8A,$15,$2E,$F6,$B1,$88,$21,$6D,$B6,$13,$00,$12,$45,$45,$58
    FCB $B4,$8D,$43,$4F,$58,$A7,$65,$DD,$6D,$22,$25,$AA,$2E,$D3,$F7,$5C
    FCB $7D,$6E,$DF,$68,$90,$6A,$1F,$D9,$1D,$F0,$4A,$B5,$B5,$00,$71,$25
    FCB $A6,$A5,$00,$D1,$B0,$7D,$C6,$C2,$36,$13,$BF,$BB,$82,$AB,$14,$5C
    FCB $51,$9E,$48,$5E,$A2,$C8,$45,$29,$A1,$01,$B5,$59,$4F,$B4,$EB,$BF
    FCB $97,$97,$2D,$C7,$9C,$7F,$25,$F7,$19,$1F,$BC,$C7,$8E,$45,$82,$9E
    FCB $F7,$11,$23,$A0,$83,$51,$6D,$D5,$B6,$CC,$F2,$DA,$E6,$D7,$82,$D5
    FCB $AD,$61,$77,$63,$71,$43,$D4,$B3,$41,$0B,$6D,$C8,$58,$00,$92,$15
    FCB $35,$82,$CD,$42,$08,$85,$0A,$B6,$5B,$8B,$69,$62,$5A,$A2,$32,$93
    FCB $C8,$EE,$5B,$B6,$A4,$4A,$2E,$FE,$C8,$A7,$95,$AC,$D2,$81,$1C,$13
    FCB $E2,$6E,$12,$2D,$85,$BE,$13,$1B,$AC,$3B,$7E,$EE,$0E,$BB,$B8,$32
    FCB $EE,$B8,$CD,$77,$15,$EB,$96,$85,$A0,$D6,$2D,$5B,$65,$1A,$93,$AE
    FCB $DF,$FC,$3B,$1D,$FE,$58,$7F,$CF,$7F,$F9,$79,$DC,$AE,$0A,$DF,$E8
    FCB $92,$B5,$29,$04,$9D,$BA,$B6,$DB,$6C,$2B,$CB,$1E,$35,$F2,$C1,$8B
    FCB $A3,$77,$7B,$62,$8B,$1A,$FA,$90,$14,$DB,$E0,$DD,$60,$2D,$56,$D6
    FCB $B1,$7D,$01,$35,$D4,$B5,$54,$6D,$D6,$34,$B0,$98,$98,$15,$60,$2E
    FCB $DF,$AA,$A6,$D3,$6E,$3D,$DC,$D8,$AC,$29,$2F,$12,$61,$8C,$16,$98
    FCB $11,$6A,$3D,$64,$6A,$83,$14,$23,$06,$DE,$4D,$BF,$DC,$B8,$CB,$8B
    FCB $ED,$EB,$3C,$06,$AB,$EB,$1E,$A7,$AA,$B2,$DA,$9E,$27,$DA,$67,$DB
    FCB $C6,$59,$BC,$BF,$C3,$EF,$DF,$31,$FF,$9E,$C3,$F3,$5F,$76,$6F,$A0
    FCB $BD,$4A,$4D,$46,$ED,$8D,$EE,$DB,$63,$98,$D7,$7B,$0F,$03,$5B,$11
    FCB $BD,$B1,$A8,$51,$DA,$FA,$90,$1A,$9B,$E6,$C1,$71,$25,$45,$24,$4E
    FCB $80,$9A,$DB,$5A,$AA,$36,$EB,$1A,$4D,$70,$31,$30,$3B,$08,$F6,$ED
    FCB $A2,$42,$EF,$BE,$C6,$5D,$95,$82,$F0,$6B,$AF,$AD,$8B,$4E,$22,$06
    FCB $DB,$71,$71,$06,$BE,$E8,$EB,$BB,$F3,$7F,$F7,$CB,$15,$5A,$EF,$0F
    FCB $B2,$BB,$A8,$7A,$E8,$15,$69,$2A,$5D,$A9,$E2,$7D,$A6,$7D,$FB,$B3
    FCB $F1,$FE,$6F,$9F,$73,$F7,$CF,$E6,$59,$CC,$EF,$FE,$A1,$8D,$49,$E4
    FCB $FB,$77,$77,$75,$5B,$54,$31,$AE,$3B,$27,$20,$1B,$4F,$B5,$A9,$C5
    FCB $55,$1D,$AF,$10,$40,$53,$6F,$9B,$05,$C4,$95,$1A,$C9,$B5,$53,$6D
    FCB $8D,$B2,$EC,$0A,$DA,$EB,$D8,$B4,$67,$3B,$DE,$82,$6B,$DB,$8F,$F1
    FCB $DC,$6B,$05,$D7,$0D,$67,$16,$8A,$9C,$25,$14,$C6,$36,$E6,$2B,$51
    FCB $11,$8C,$EF,$CB,$73,$FB,$E5,$8A,$AC,$66,$BC,$F7,$37,$90,$68,$B7
    FCB $5A,$D4,$EF,$BB,$28,$DA,$67,$DF,$EF,$FF,$F1,$BF,$87,$D9,$B9,$E7
    FCB $FF,$73,$84,$F7,$FF,$66,$E9,$E4,$FA,$9B,$B7,$6E,$37,$6D,$DF,$6B
    FCB $23,$79,$CE,$B8,$68,$D6,$A6,$C6,$36,$3B,$3A,$91,$0A,$75,$2D,$B0
    FCB $A8,$17,$16,$CB,$48,$F5,$2A,$89,$DA,$4A,$6C,$6A,$2B,$94,$A4,$F4
    FCB $FA,$C7,$38,$ED,$0B,$4F,$31,$FF,$7F,$55,$80,$90,$B8,$B8,$38,$71
    FCB $24,$D5,$A7,$3B,$D8,$F6,$E3,$23,$14,$CA,$47,$37,$B9,$FF,$DF,$C8
    FCB $F1,$AD,$D7,$9F,$9B,$50,$5A,$D4,$DE,$46,$A2,$DB,$B3,$4F,$A9,$33
    FCB $C6,$3F,$7F,$D9,$78,$A6,$57,$F1,$CF,$BF,$C3,$F9,$BF,$80,$37,$EC
    FCB $FD,$FD,$35,$3E,$A6,$EC,$B6,$EF,$6D,$A9,$B6,$35,$C8,$C7,$2C,$F0
    FCB $17,$AD,$A3,$6C,$14,$F6,$CE,$D1,$0A,$6D,$4B,$6D,$7B,$02,$15,$DA
    FCB $C6,$68,$3A,$94,$EB,$53,$63,$52,$EB,$EB,$02,$38,$9F,$39,$7E,$82
    FCB $76,$DF,$64,$7F,$D8,$F5,$95,$AC,$8B,$97,$B9,$11,$A2,$46,$95,$E1
    FCB $BF,$35,$62,$EB,$FE,$EF,$9E,$E7,$7F,$97,$9E,$B5,$97,$F3,$A9,$E0
    FCB $DB,$ED,$75,$6E,$FE,$9F,$52,$74,$E3,$BE,$1E,$DB,$3F,$FF,$F3,$BF
    FCB $FF,$E1,$CF,$2C,$5B,$6C,$D9,$FF,$F4,$48,$DB,$6D,$05,$ED,$B7,$B8
    FCB $DA,$9B,$51,$5F,$3D,$93,$91,$75,$B1,$78,$AB,$B7,$ED,$12,$4A,$6D
    FCB $8A,$52,$CB,$21,$5D,$78,$32,$D1,$2B,$6D,$A4,$A7,$B5,$2C,$5D,$D6
    FCB $B9,$35,$A7,$FC,$7B,$A6,$A6,$F7,$EC,$77,$66,$E5,$6B,$05,$84,$5B
    FCB $A8,$8C,$8B,$46,$9A,$97,$62,$5D,$BF,$06,$01,$FF,$77,$E0,$3E,$D8
    FCB $E7,$EE,$2E,$AC,$59,$71,$93,$77,$EC,$6E,$D9,$67,$D8,$E8,$DA,$65
    FCB $0B,$6F,$87,$DB,$97,$8E,$7D,$FF,$FE,$72,$C6,$78,$F9,$89,$29,$CB
    FCB $FF,$FE,$82,$56,$E9,$A9,$3D,$EE,$DD,$56,$DB,$B9,$AF,$D9,$39,$81
    FCB $05,$D6,$AD,$DB,$7B,$44,$92,$9D,$8A,$41,$61,$18,$B9,$23,$2B,$A9
    FCB $05,$6A,$B4,$90,$51,$6A,$58,$B6,$0B,$2B,$6E,$24,$96,$CB,$76,$9E
    FCB $40,$60,$FD,$F8,$F7,$6B,$58,$B0,$09,$5D,$44,$15,$04,$91,$A7,$B8
    FCB $D6,$9F,$BB,$BE,$61,$3F,$EE,$F9,$EC,$F6,$7E,$96,$E3,$DA,$C1,$53
    FCB $9B,$BD,$4C,$5B,$DF,$67,$BD,$D1,$B4,$EA,$ED,$8F,$0E,$DB,$9E,$3E
    FCB $0F,$BC,$7E,$7F,$EE,$7F,$24,$01,$4F,$F7,$E3,$73,$B5,$ED,$A6,$A3
    FCB $B1,$BB,$DD,$B7,$55,$B7,$1A,$FD,$C7,$14,$BC,$17,$22,$D2,$50,$DD
    FCB $B7,$B4,$D4,$9A,$B5,$A9,$01,$64,$60,$66,$D7,$5D,$4A,$53,$6D,$B4
    FCB $90,$77,$52,$4B,$1A,$EB,$27,$11,$91,$8D,$A7,$6E,$ED,$98,$F7,$F6
    FCB $E0,$D2,$58,$0B,$72,$D6,$30,$AD,$11,$4A,$8D,$11,$05,$2D,$69,$37
    FCB $FE,$AA,$C3,$EF,$BF,$CF,$FD,$8F,$AD,$65,$51,$5D,$65,$55,$B2,$6D
    FCB $F6,$A0,$7E,$5B,$36,$FD,$3F,$4C,$B8,$D5,$D8,$0E,$DB,$3B,$D9,$3F
    FCB $C7,$0E,$37,$FF,$FC,$67,$58,$54,$E7,$FD,$F3,$A8,$DB,$4D,$4F,$8F
    FCB $7B,$7E,$DB,$A9,$4D,$8A,$5F,$C1,$EC,$33,$08,$92,$96,$37,$77,$68
    FCB $92,$6D,$C5,$28,$58,$C6,$10,$36,$B5,$2E,$83,$50,$D5,$52,$48,$AE
    FCB $29,$19,$09,$02,$C4,$73,$6D,$3A,$F7,$DE,$E6,$37,$C5,$AE,$B9,$17
    FCB $95,$60,$53,$E9,$E8,$B8,$A0,$2D,$75,$97,$EC,$A6,$A7,$C9,$1F,$FB
    FCB $B2,$7F,$F7,$C5,$BE,$E3,$80,$76,$0F,$B7,$AB,$DC,$FC,$DF,$68,$DA
    FCB $67,$2D,$8F,$8F,$DF,$BB,$21,$BE,$78,$F8,$FF,$D9,$9C,$DE,$B9,$76
    FCB $76,$3F,$E5,$DF,$D1,$26,$14,$3A,$BB,$F7,$75,$36,$A6,$A3,$1C,$2C
    FCB $67,$18,$4A,$36,$2C,$55,$ED,$A6,$AE,$AC,$52,$85,$91,$D7,$59,$D8
    FCB $A5,$D0,$6A,$1B,$6A,$5A,$2D,$8D,$19,$08,$15,$DA,$D6,$74,$13,$B7
    FCB $BF,$37,$8F,$75,$2C,$58,$2C,$0C,$95,$04,$94,$FA,$76,$2F,$6D,$64
    FCB $7A,$82,$B0,$A8,$AE,$33,$A1,$D2,$EC,$67,$63,$3D,$CF,$9E,$CE,$BA
    FCB $DE,$82,$D6,$FA,$BB,$DF,$F6,$63,$6C,$B4,$6D,$3A,$F6,$5E,$3E,$7D
    FCB $BF,$FE,$7D,$E5,$FC,$D9,$9F,$F5,$C7,$FB,$FE,$3E,$FE,$C4,$13,$ED
    FCB $8D,$05,$F7,$F7,$76,$A6,$DB,$65,$9E,$C8,$EC,$80,$94,$AE,$B5,$3D
    FCB $A7,$86,$F5,$B7,$5E,$60,$17,$75,$2E,$8A,$C6,$DA,$92,$45,$75,$A0
    FCB $8C,$6B,$02,$0B,$B5,$AE,$85,$A7,$6F,$FC,$BE,$3B,$8A,$5A,$C0,$59
    FCB $32,$3A,$C7,$E9,$F4,$F2,$C0,$6E,$17,$52,$09,$24,$2E,$33,$5B,$53
    FCB $F6,$BD,$77,$8C,$EC,$67,$72,$78,$FF,$CA,$DE,$A5,$AD,$ED,$F7,$36
    FCB $AF,$A9,$1D,$DC,$74,$9A,$75,$DC,$BF,$B8,$CB,$FF,$C7,$9C,$BF,$F6
    FCB $7B,$27,$EC,$AE,$3B,$3D,$FF,$7E,$E4,$75,$24,$DC,$44,$96,$3B,$EF
    FCB $BA,$9B,$6A,$D9,$F1,$91,$96,$04,$2B,$49,$5B,$69,$A3,$70,$76,$BC
    FCB $C9,$DF,$28,$36,$DB,$6A,$49,$57,$5A,$92,$21,$00,$5D,$AE,$D3,$AB
    FCB $7F,$EC,$E3,$14,$E2,$D4,$8C,$AE,$BC,$26,$A4,$AB,$42,$34,$92,$4D
    FCB $31,$C8,$3A,$28,$92,$D6,$76,$EA,$76,$D8,$64,$05,$8F,$3B,$3B,$33
    FCB $C7,$36,$E1,$36,$D2,$1D,$DF,$73,$7F,$EE,$D8,$F4,$6D,$3A,$C7,$7C
    FCB $EE,$D9,$73,$FF,$FF,$CB,$9F,$8E,$7B,$3E,$48,$FB,$5B,$67,$D5,$C6
    FCB $C6,$DA,$08,$92,$6F,$6B,$33,$8B,$3B,$BB,$6D,$55,$1D,$F6,$0A,$58
    FCB $E6,$57,$46,$A3,$68,$96,$AE,$28,$61,$E6,$6D,$91,$AA,$DA,$9B,$6B
    FCB $41,$B1,$6D,$3E,$C5,$98,$0B,$B1,$A7,$4E,$FF,$DC,$F7,$C1,$75,$D7
    FCB $90,$C1,$4B,$89,$27,$8A,$C5,$A1,$01,$4F,$AB,$44,$AA,$61,$69,$23
    FCB $DA,$9D,$DB,$54,$C2,$F1,$60,$06,$CF,$E7,$8E,$BB,$33,$6E,$30,$77
    FCB $7F,$DB,$0C,$BB,$B7,$E8,$DA,$75,$1B,$71,$47,$B0,$DF,$FF,$FF,$25
    FCB $F7,$9F,$E7,$FC,$92,$C1,$F6,$D9,$EC,$14,$82,$EA,$4D,$52,$25,$9D
    FCB $AE,$7F,$3A,$D6,$6D,$B5,$6C,$B7,$BB,$52,$D6,$33,$80,$8D,$CB,$45
    FCB $51,$8C,$B2,$0C,$25,$B8,$ED,$5B,$55,$4A,$14,$EB,$1A,$36,$25,$C5
    FCB $8B,$AA,$9D,$2B,$EC,$F7,$5B,$DD,$4B,$01,$60,$48,$CD,$80,$44,$69
    FCB $EA,$C2,$A1,$AE,$D5,$A9,$C4,$4D,$24,$C2,$D2,$5A,$B5,$37,$B6,$A8
    FCB $C9,$76,$B0,$A4,$90,$2B,$FE,$78,$A8,$1E,$35,$3A,$F9,$7D,$BC,$F3
    FCB $DB,$ED,$CA,$4A,$4E,$A3,$70,$7E,$D8,$6C,$7F,$F6,$79,$F6,$3C,$63
    FCB $87,$EC,$FC,$9D,$9F,$7F,$DD,$88,$97,$52,$6A,$08,$2D,$85,$4B,$9F
    FCB $9E,$EB,$2B,$5D,$95,$3D,$5B,$B6,$42,$D6,$C0,$49,$44,$A0,$2A,$31
    FCB $4B,$B2,$72,$6D,$8A,$B6,$F6,$D4,$C5,$2A,$92,$DA,$4A,$16,$40,$59
    FCB $52,$76,$87,$F9,$BC,$77,$14,$B5,$80,$BE,$40,$A9,$62,$83,$49,$3C
    FCB $91,$1C,$8E,$EA,$60,$35,$AE,$2E,$CB,$F6,$A4,$16,$DC,$1B,$22,$C4
    FCB $96,$CB,$FF,$E5,$DC,$58,$6E,$37,$FF,$6A,$B5,$9F,$2F,$EE,$EC,$A4
    FCB $A4,$EB,$1E,$3F,$76,$7D,$FF,$64,$2E,$5F,$CF,$CF,$FF,$E0,$6F,$E3
    FCB $67,$B6,$F4,$90,$5A,$08,$22,$52,$0B,$6E,$30,$EC,$2F,$C3,$E2,$4B
    FCB $8A,$75,$5E,$DE,$D7,$69,$65,$6D,$66,$A6,$E3,$1A,$EA,$32,$CA,$C7
    FCB $63,$6D,$BB,$6D,$4A,$14,$E9,$36,$8C,$12,$30,$5A,$7A,$A4,$1F,$F9
    FCB $7E,$EC,$5B,$48,$0A,$F2,$11,$55,$88,$1A,$49,$26,$92,$D9,$9B,$2C
    FCB $3B,$0B,$58,$C2,$EA,$41,$F0,$6E,$B5,$AD,$6C,$3F,$3E,$F1,$8E,$2E
    FCB $37,$72,$77,$DD,$DC,$39,$BE,$FE,$F4,$90,$4E,$F1,$E5,$E3,$6C,$FB
    FCB $F8,$7D,$F3,$FF,$E7,$BF,$95,$00,$CD,$CF,$1D,$EE,$74,$91,$2E,$9A
    FCB $9A,$D0,$1B,$E7,$19,$EF,$C0,$2E,$35,$AC,$6F,$7B,$1B,$DA,$C6,$03
    FCB $17,$EE,$6A,$2F,$16,$E4,$EC,$75,$35,$0D,$A9,$4E,$A6,$2D,$A9,$1A
    FCB $D6,$B0,$75,$A9,$3B,$BF,$FB,$1F,$BB,$16,$52,$0C,$86,$BB,$A4,$2D
    FCB $37,$5A,$D6,$87,$1B,$97,$3D,$77,$78,$44,$99,$60,$A5,$22,$D9,$B1
    FCB $25,$AF,$9F,$9F,$78,$C7,$58,$A4,$9E,$CF,$FE,$DD,$9F,$37,$BC,$B6
    FCB $F4,$9A,$77,$2D,$CF,$BB,$2F,$FF,$FF,$9F,$FF,$9F,$FF,$C9,$BB,$3D
    FCB $43,$6F,$ED,$6A,$5E,$9A,$D0,$B7,$6C,$F8,$75,$1E,$70,$38,$BB,$1F
    FCB $BA,$AA,$5C,$80,$01,$6A,$85,$43,$F3,$D7,$1B,$1A,$D0,$6A,$A9,$4A
    FCB $53,$2C,$06,$90,$90,$BB,$89,$D3,$BF,$3B,$8A,$DD,$49,$0B,$AE,$12
    FCB $B9,$BE,$8F,$46,$9D,$B4,$80,$7C,$76,$63,$DE,$39,$91,$21,$8D,$43
    FCB $6A,$50,$EB,$22,$E1,$F9,$CF,$BC,$07,$3B,$C6,$7F,$FF,$7D,$96,$FD
    FCB $9B,$7A,$D4,$9B,$EC,$EF,$B6,$BB,$1F,$FF,$FC,$EC,$FF,$9F,$FF,$EC
    FCB $2D,$A9,$6D,$AA,$89,$6F,$CF,$CB,$6D,$B6,$EE,$FD,$73,$57,$67,$C0
    FCB $98,$CA,$5E,$DB,$50,$C3,$5D,$61,$75,$2C,$15,$D9,$31,$AF,$B5,$A8
    FCB $41,$BB,$41,$4A,$77,$01,$A3,$12,$0A,$84,$F2,$1F,$CD,$B0,$43,$62
    FCB $93,$EB,$8B,$33,$25,$C6,$8F,$11,$A7,$61,$1E,$39,$8D,$FF,$9E,$69
    FCB $0C,$6A,$36,$EE,$02,$F3,$F9,$CF,$B9,$58,$FE,$FC,$FF,$EF,$1D,$56
    FCB $93,$79,$AB,$76,$52,$52,$6F,$71,$CB,$EF,$77,$3F,$FF,$CF,$FF,$9F
    FCB $FB,$2F,$52,$C6,$D0,$41,$6F,$BE,$F3,$33,$DB,$A9,$BE,$F6,$71,$5F
    FCB $EC,$D7,$C5,$BC,$34,$86,$DB,$6A,$06,$94,$17,$62,$80,$7E,$38,$C6
    FCB $BE,$C6,$21,$6B,$41,$05,$21,$64,$8D,$25,$AC,$2D,$04,$DE,$FD,$6D
    FCB $B8,$DB,$8B,$68,$E0,$04,$23,$DA,$35,$A2,$31,$68,$81,$9F,$9B,$76
    FCB $BE,$FB,$76,$5A,$F1,$EB,$15,$20,$25,$19,$19,$B3,$9F,$72,$B1,$DC
    FCB $6E,$4F,$F8,$EE,$D9,$F6,$F2,$2B,$71,$D6,$82,$6C,$CC,$DB,$D9,$6F
    FCB $FF,$FC,$EF,$FF,$FF,$5E,$FF,$68,$92,$53,$6D,$05,$FF,$F1,$9F,$9B
    FCB $D4,$DE,$D8,$F7,$B2,$7F,$70,$FC,$C8,$92,$E3,$6D,$55,$2D,$71,$78
    FCB $EB,$15,$67,$F9,$1D,$7A,$AA,$A0,$A5,$21,$AD,$C1,$AD,$18,$3B,$4F
    FCB $3E,$FB,$5A,$99,$6C,$8B,$B4,$80,$00,$E3,$74,$FD,$24,$F0,$C8,$A3
    FCB $D7,$6D,$A0,$B5,$36,$DD,$DE,$B7,$FD,$9C,$60,$F8,$B5,$44,$93,$E9
    FCB $51,$FB,$2C,$F3,$C8,$F6,$5C,$3F,$9E,$DD,$B6,$11,$B6,$18,$DB,$72
    FCB $2D,$04,$EF,$2B,$8F,$50,$F2,$A7,$FE,$F9,$3E,$FF,$F8,$7B,$FA,$96
    FCB $EA,$52,$09,$37,$B1,$F7,$F7,$F8,$73,$2D,$B6,$DF,$DB,$61,$8C,$DF
    FCB $19,$9E,$30,$A3,$23,$A9,$44,$0C,$1A,$C7,$64,$7E,$A5,$CB,$5A,$9B
    FCB $C4,$2A,$B6,$29,$4B,$2B,$5C,$4F,$6A,$B9,$DB,$10,$2E,$A4,$80,$2B
    FCB $AC,$0C,$6C,$D3,$F1,$1A,$7B,$DE,$A5,$29,$04,$9B,$75,$2F,$79,$72
    FCB $FE,$DF,$9E,$B5,$6E,$B4,$31,$68,$E9,$CC,$8F,$CE,$1C,$6F,$0F,$8A
    FCB $9F,$64,$F7,$BB,$79,$6E,$4B,$1B,$25,$68,$27,$59,$5C,$7A,$87,$65
    FCB $5F,$C7,$C6,$7D,$E7,$FE,$7B,$F6,$89,$25,$29,$B5,$2D,$FD,$F7,$F9
    FCB $EC,$99,$27,$6D,$B6,$FD,$8F,$B0,$DF,$9F,$F9,$AE,$B4,$8B,$15,$07
    FCB $06,$B1,$8F,$1F,$B0,$D8,$A6,$BA,$A8,$20,$D2,$4A,$35,$2D,$71,$48
    FCB $84,$F3,$5B,$76,$B7,$6C,$15,$71,$04,$60,$00,$10,$8D,$D6,$A4,$F8
    FCB $E2,$16,$A5,$22,$46,$DB,$6C,$39,$7B,$FE,$AF,$2F,$F3,$15,$6E,$B6
    FCB $05,$1B,$4C,$89,$89,$F3,$1F,$D6,$EF,$23,$96,$7F,$8E,$ED,$F8,$50
    FCB $91,$83,$6C,$2B,$41,$33,$24,$8F,$7D,$96,$F9,$F7,$CF,$64,$FF,$F1
    FCB $EC,$63,$41,$35,$68,$3D,$AD,$F7,$DF,$3F,$EC,$F3,$2B,$65,$BE,$DE
    FCB $DB,$EC,$9C,$FF,$E7,$07,$16,$90,$5C,$54,$D7,$63,$8B,$6F,$B9,$53
    FCB $10,$37,$6D,$A4,$F4,$6B,$41,$51,$63,$53,$49,$49,$E5,$35,$A9,$B0
    FCB $2D,$D6,$82,$55,$D6,$04,$0B,$62,$31,$01,$4A,$A8,$53,$76,$B7,$BF
    FCB $CB,$F7,$D8,$FF,$F3,$E2,$BD,$6D,$78,$BA,$72,$D2,$8B,$78,$38,$6E
    FCB $A5,$D9,$66,$A8,$4D,$FE,$FB,$53,$59,$0B,$77,$F6,$4A,$D4,$99,$49
    FCB $3E,$FB,$2A,$FF,$F8,$DE,$61,$1D,$B1,$93,$7A,$0B,$62,$08,$22,$49
    FCB $4E,$DF,$E7,$F3,$9E,$C8,$C1,$FB,$17,$BD,$DD,$DD,$B7,$26,$BF,$AB
    FCB $EB,$67,$66,$02,$35,$BB,$99,$AE,$C5,$A9,$E3,$55,$4A,$2A,$3A,$FA
    FCB $7D,$C4,$49,$FB,$B6,$B6,$89,$AD,$1A,$74,$9D,$B2,$CF,$75,$DA,$32
    FCB $B5,$84,$2D,$A9,$24,$9D,$A0,$DD,$43,$BE,$EE,$BD,$FE,$E3,$FB,$FF
    FCB $C6,$C6,$0C,$94,$A3,$5A,$EA,$4E,$58,$57,$EB,$7A,$EC,$B1,$B7,$23
    FCB $70,$3B,$9B,$57,$DB,$17,$F7,$1A,$0B,$2A,$5F,$5A,$93,$29,$27,$DF
    FCB $65,$5E,$7F,$1F,$9F,$ED,$97,$08,$E9,$A9,$5A,$08,$28,$56,$F7,$1F
    FCB $96,$7C,$CE,$33,$32,$F3,$DE,$DD,$DF,$6C,$B5,$9E,$FE,$71,$E6,$BD
    FCB $68,$FF,$1D,$7D,$6A,$B1,$B4,$15,$23,$26,$20,$92,$49,$1A,$15,$95
    FCB $16,$E2,$76,$99,$54,$65,$A9,$2A,$CC,$05,$E0,$5E,$B1,$A9,$F7,$63
    FCB $56,$3D,$B3,$F7,$D8,$FF,$FF,$C5,$75,$AF,$C5,$C8,$98,$14,$9C,$03
    FCB $38,$71,$FB,$B7,$02,$F0,$FF,$BF,$6E,$63,$3D,$B6,$ED,$28,$24,$A4
    FCB $E4,$A0,$E7,$6F,$A9,$65,$FF,$B6,$70,$FF,$EE,$3B,$97,$44,$8F,$41
    FCB $4A,$14,$DB,$BF,$8F,$24,$63,$FF,$C9,$99,$96,$6E,$DB,$B7,$76,$C6
    FCB $B9,$FF,$E5,$93,$1C,$12,$03,$BA,$43,$AD,$0B,$6A,$6A,$00,$B7,$5A
    FCB $96,$08,$D2,$87,$75,$27,$9A,$61,$4C,$6D,$39,$3A,$87,$BA,$91,$8B
    FCB $EB,$5A,$F8,$0C,$57,$F6,$DE,$DD,$D7,$6F,$BF,$1B,$FF,$FF,$7E,$B7
    FCB $81,$85,$7A,$C4,$E5,$D4,$B3,$5F,$7D,$FE,$3B,$C5,$DE,$B7,$CF,$BF
    FCB $7F,$A9,$78,$29,$96,$C8,$24,$A4,$E4,$82,$A6,$73,$6E,$0F,$DF,$1F
    FCB $C0,$7D,$FB,$CF,$DD,$49,$6D,$48,$24,$A6,$F6,$DB,$BF,$21,$FC,$B3
    FCB $FF,$9C,$67,$6A,$DF,$6D,$D9,$B0,$67,$FC,$51,$21,$E2,$EB,$5E,$EB
    FCB $5D,$88,$5A,$25,$D4,$90,$3B,$41,$A3,$12,$49,$19,$8F,$EA,$4E,$DA
    FCB $70,$A6,$31,$39,$38,$E9,$E7,$5A,$92,$20,$2D,$66,$A0,$6B,$FB,$7B
    FCB $6D,$8A,$7B,$3F,$7B,$9F,$FF,$F1,$DE,$30,$05,$E0,$CA,$E9,$C2,$62
    FCB $A5,$8C,$3A,$94,$61,$FB,$CA,$EA,$CF,$8C,$DF,$CB,$EE,$4B,$56,$EB
    FCB $C4,$91,$26,$5C,$54,$E1,$53,$9E,$77,$B6,$60,$3F,$F1,$BD,$9F,$6A
    FCB $5E,$D4,$89,$1B,$6D,$9B,$EE,$E3,$0C,$9C,$F3,$3B,$7F,$76,$5A,$87
    FCB $BE,$DD,$6E,$AD,$50,$E5,$82,$8C,$0E,$57,$17,$1C,$4A,$C4,$54,$54
    FCB $FB,$55,$50,$08,$9F,$46,$0E,$C9,$53,$6D,$68,$24,$3A,$9A,$65,$B1
    FCB $3B,$50,$B5,$24,$35,$AE,$B3,$1D,$AC,$B6,$DB,$50,$ED,$B1,$F6,$1B
    FCB $8F,$FF,$FE,$FB,$19,$8B,$00,$99,$06,$23,$4E,$72,$A5,$F3,$B4,$0C
    FCB $07,$F2,$EB,$AA,$BB,$E3,$EE,$3E,$7D,$CC,$53,$6B,$CB,$12,$41,$39
    FCB $58,$D8,$5C,$77,$23,$DB,$2C,$0F,$FF,$F6,$CF,$2F,$67,$68,$93,$EA
    FCB $6D,$DD,$FE,$EF,$0C,$26,$13,$FB,$E5,$DB,$55,$AD,$BB,$6F,$6C,$63
    FCB $6C,$79,$52,$CC,$67,$32,$04,$5E,$5A,$31,$D1,$29,$04,$C5,$A9,$00
    FCB $82,$CA,$D1,$8B,$AA,$52,$6A,$42,$D1,$AA,$B4,$06,$D0,$6E,$99,$A6
    FCB $8B,$68,$EB,$09,$8D,$D2,$B7,$6D,$B6,$37,$B1,$DE,$5F,$FF,$F3,$BD
    FCB $58,$40,$8B,$B2,$06,$02,$02,$64,$5A,$EC,$B0,$ED,$58,$42,$D8,$F7
    FCB $58,$A8,$3E,$DC,$C9,$BD,$FC,$ED,$B5,$85,$C5,$A0,$99,$5E,$D9,$C2
    FCB $FF,$9B,$37,$F3,$FE,$36,$E7,$2F,$FB,$44,$98,$6D,$B5,$3D,$D7,$8C
    FCB $DC,$14,$61,$33,$F1,$F8,$FA,$90,$6B,$6E,$DB,$BE,$DB,$B5,$AA,$D8
    FCB $A5,$90,$6B,$FC,$03,$58,$4B,$12,$88,$91,$2E,$DA,$80,$59,$A9,$4D
    FCB $25,$A7,$0B,$8B,$BD,$B6,$35,$2D,$8E,$D0,$40,$4E,$D3,$DB,$46,$92
    FCB $FE,$57,$DB,$63,$6D,$B1,$56,$E6,$F7,$8C,$2F,$FE,$37,$92,$01,$39
    FCB $99,$08,$29,$30,$9F,$0A,$8D,$90,$6F,$EC,$F6,$FA,$43,$FE,$DC,$C9
    FCB $EE,$EE,$BE,$36,$4D,$BA,$D0,$4C,$C6,$3D,$FA,$4A,$73,$EF,$33,$FF
    FCB $B7,$9F,$BC,$B8,$7A,$6A,$37,$6A,$A4,$FD,$44,$FC,$64,$E7,$1F,$DE
    FCB $73,$DD,$35,$5A,$87,$6E,$A1,$DA,$DD,$B7,$78,$B4,$11,$9F,$22,$E2
    FCB $C2,$3D,$2D,$35,$06,$04,$5A,$D0,$BB,$62,$4B,$4F,$AE,$2E,$E3,$FB
    FCB $57,$52,$90,$5A,$76,$9D,$D2,$68,$D7,$97,$16,$ED,$B6,$EA,$6D,$B5
    FCB $BB,$E7,$79,$CB,$F7,$E1,$26,$19,$CA,$F9,$C2,$9C,$2D,$04,$75,$FE
    FCB $37,$D9,$DC,$B3,$70,$DC,$42,$B3,$65,$D7,$7E,$2B,$D7,$FB,$64,$BA
    FCB $D1,$26,$76,$32,$E6,$37,$B3,$70,$E6,$3E,$3D,$B3,$7C,$E6,$E7,$D0
    FCB $4A,$ED,$04,$6A,$E3,$21,$F1,$FD,$9F,$FB,$3D,$CF,$D1,$21,$51,$D5
    FCB $EF,$56,$EB,$52,$9C,$52,$40,$59,$2B,$D6,$B0,$39,$A7,$91,$56,$B0
    FCB $46,$D0,$DC,$68,$D2,$16,$D2,$83,$1E,$7D,$A8,$74,$D5,$A7,$49,$D8
    FCB $BA,$47,$53,$59,$6B,$6D,$4A,$63,$57,$2F,$FE,$6F,$BF,$E1,$08,$79
    FCB $AF,$F0,$95,$BD,$38,$4F,$88,$19,$6D,$C7,$5D,$CD,$B9,$B0,$70,$9F
    FCB $6F,$CE,$5D,$CE,$7D,$F5,$2C,$38,$89,$32,$F6,$3C,$BD,$9F,$CF,$23
    FCB $FF,$78,$F7,$3F,$79,$96,$5D,$A2,$4F,$BE,$13,$E7,$FA,$BF,$F6,$C6
    FCB $DD,$CC,$F6,$89,$87,$7B,$76,$EF,$5A,$AA,$7D,$82,$DA,$F0,$C5,$AC
    FCB $84,$42,$9A,$A1,$24,$F9,$41,$F6,$56,$14,$48,$93,$22,$4B,$5F,$61
    FCB $F6,$F6,$9A,$B4,$E9,$11,$A5,$D6,$D8,$DB,$14,$A5,$36,$7C,$DF,$7B
    FCB $9E,$4C,$F0,$87,$0F,$9C,$E6,$2D,$0A,$70,$8C,$14,$5F,$A8,$1D,$76
    FCB $D7,$DB,$90,$1B,$C1,$FF,$BF,$0B,$E5,$E7,$FB,$3E,$B4,$49,$97,$6C
    FCB $18,$F3,$76,$73,$C9,$7F,$ED,$8E,$7F,$1F,$F3,$37,$41,$1D,$ED,$67
    FCB $DE,$3F,$B2,$DB,$55,$4A,$77,$66,$CF,$F2,$66,$FB,$6F,$B8,$D9,$6B
    FCB $53,$71,$40,$1C,$58,$BC,$04,$42,$0D,$69,$85,$6A,$24,$69,$54,$29
    FCB $A0,$99,$16,$8D,$7D,$B3,$DB,$BA,$91,$2D,$3B,$AA,$D2,$D7,$A0,$D4
    FCB $A5,$17,$73,$E6,$F1,$BE,$C0,$87,$93,$D7,$C9,$E5,$CF,$C1,$6A,$4C
    FCB $23,$22,$81,$E3,$6B,$D8,$EC,$BB,$32,$37,$74,$87,$FF,$F3,$7E,$CB
    FCB $C8,$77,$EC,$49,$04,$E5,$75,$73,$F7,$67,$F3,$EE,$1E,$DE,$41,$E3
    FCB $7B,$86,$36,$17,$52,$5E,$A4,$BD,$EC,$BB,$6A,$52,$87,$7D,$8C,$51
    FCB $FD,$CF,$27,$8F,$BF,$BE,$DE,$2B,$BB,$C0,$05,$86,$02,$0D,$54,$FB
    FCB $76,$4C,$48,$41,$8C,$A6,$04,$67,$6F,$1D,$ED,$B4,$D5,$A7,$AA,$75
    FCB $83,$50,$D4,$DF,$FF,$D6,$DB,$BE,$49,$33,$C2,$F9,$38,$E4,$99,$1E
    FCB $27,$02,$09,$48,$CD,$BE,$4D,$D8,$3C,$6E,$5B,$8B,$3C,$7C,$7F,$1B
    FCB $D8,$A4,$AC,$D8,$30,$F7,$AD,$04,$CB,$63,$BB,$35,$DF,$E5,$F7,$07
    FCB $FE,$71,$BE,$4B,$EE,$78,$C7,$67,$10,$4F,$DE,$AB,$6A,$52,$AA,$65
    FCB $AF,$7B,$DF,$E3,$3F,$9E,$46,$65,$B8,$EF,$DB,$A9,$CA,$DD,$9B,$01
    FCB $70,$05,$35,$41,$77,$29,$35,$AD,$13,$8A,$5A,$D2,$A3,$59,$BC,$7A
    FCB $AE,$D4,$89,$68,$9A,$B5,$B5,$36,$77,$87,$BC,$FE,$37,$CB,$F9,$75
    FCB $E6,$B8,$E4,$9F,$91,$36,$B4,$69,$F1,$96,$18,$C7,$C9,$7A,$8B,$37
    FCB $80,$E7,$E3,$F6,$B5,$6D,$73,$B9,$F9,$73,$ED,$AD,$04,$CE,$C7,$E4
    FCB $A4,$83,$BF,$31,$FF,$7F,$FC,$FF,$EE,$7F,$D9,$76,$82,$7C,$A9,$04
    FCB $42,$9F,$2F,$7B,$EE,$E7,$EC,$9C,$9F,$3F,$3E,$EF,$76,$37,$C5,$78
    FCB $C0,$30,$5A,$9A,$94,$B4,$B0,$A4,$93,$68,$9C,$ED,$12,$70,$9F,$5A
    FCB $32,$FE,$89,$12,$93,$C9,$C2,$0A,$41,$1D,$04,$4E,$BF,$FF,$C8,$76
    FCB $32,$3F,$C8,$F3,$6E,$B6,$4A,$CC,$E3,$EA,$9A,$D1,$23,$49,$24,$81
    FCB $95,$5F,$5B,$E4,$DB,$7F,$30,$DE,$C3,$97,$D8,$86,$B0,$FB,$32,$E7
    FCB $67,$B6,$B5,$26,$6E,$37,$C8,$D2,$53,$BF,$31,$FE,$37,$B8,$47,$FD
    FCB $CD,$E7,$FD,$9B,$69,$A8,$D4,$82,$A8,$25,$DD,$DF,$FF,$F3,$8D,$FD
    FCB $7E,$F3,$19,$C0,$EC,$DB,$6E,$F1,$5E,$92,$98,$1A,$D7,$41,$4A,$89
    FCB $15,$D2,$46,$89,$05,$39,$28,$2D,$49,$23,$13,$E8,$A9,$80,$7A,$76
    FCB $9E,$52,$09,$28,$A3,$A2,$45,$AF,$E7,$FC,$BF,$3E,$7E,$76,$B6,$5D
    FCB $6A,$F0,$17,$85,$CA,$2D,$68,$D6,$A5,$D2,$02,$5D,$B8,$3F,$36,$C5
    FCB $18,$BB,$F7,$C3,$8E,$6F,$D9,$E7,$E5,$CE,$CC,$78,$82,$72,$BF,$8E
    FCB $56,$D8,$FD,$E5,$DE,$7D,$E0,$FF,$C8,$F7,$37,$38,$82,$ED,$12,$08
    FCB $91,$AB,$6E,$5F,$7D,$E7,$E6,$66,$EE,$33,$E7,$F3,$39,$67,$B7,$6D
    FCB $8C,$EB,$42,$C0,$8B,$10,$52,$AB,$5D,$AD,$24,$FA,$26,$D5,$2A,$D2
    FCB $14,$92,$EA,$41,$04,$C5,$68,$C6,$9A,$89,$4E,$A4,$84,$FA,$93,$54
    FCB $EB,$CB,$7E,$7C,$F9,$1F,$E7,$7B,$5E,$3A,$D5,$E1,$00,$1F,$5A,$79
    FCB $24,$92,$DD,$48,$D2,$8C,$14,$59,$1C,$FD,$DE,$1F,$F9,$9B,$CF,$FE
    FCB $F3,$E6,$CC,$77,$1E,$92,$09,$CA,$EF,$FC,$15,$65,$E4,$BB,$9F,$FE
    FCB $E1,$EE,$59,$2F,$7D,$D3,$52,$52,$0A,$6A,$49,$FB,$6F,$CE,$F3,$99
    FCB $98,$36,$E7,$F9,$FE,$67,$9E,$3B,$B1,$DB,$2B,$55,$C1,$8B,$10,$6A
    FCB $8B,$5B,$A7,$08,$9D,$B9,$E9,$26,$A0,$9C,$EE,$83,$6D,$65,$3E,$B4
    FCB $D4,$56,$56,$B4,$69,$A8,$95,$AE,$77,$C5,$DF,$73,$9F,$3E,$6F,$FB
    FCB $5A,$9F,$5F,$5A,$ED,$D6,$8D,$69,$AB,$0C,$B5,$AC,$5C,$B6,$F6,$BE
    FCB $33,$DB,$C3,$38,$DD,$87,$E6,$CF,$EF,$23,$DE,$CA,$FB,$DC,$49,$04
    FCB $E5,$77,$FE,$24,$85,$FE,$CB,$CF,$3F,$EF,$9F,$66,$6E,$A1,$D4,$A4
    FCB $D4,$68,$9B,$B3,$BB,$FE,$5B,$99,$33,$E5,$CF,$F2,$39,$F9,$CF,$6F
    FCB $93,$71,$D9,$F5,$A2,$01,$4D,$EB,$4E,$14,$D4,$F0,$8B,$DA,$25,$53
    FCB $08,$54,$F0,$14,$9F,$41,$D5,$01,$24,$F2,$68,$57,$EB,$BC,$F3,$3E
    FCB $E3,$98,$D9,$2E,$3E,$C6,$DC,$5B,$80,$B4,$16,$8D,$65,$5F,$83,$29
    FCB $2E,$3B,$DA,$F2,$CE,$D9,$C8,$6A,$6C,$E0,$AA,$FF,$9C,$7E,$5C,$EC
    FCB $7D,$FF,$49,$04,$CB,$DF,$E4,$49,$0B,$DF,$CD,$FC,$FB,$EE,$1F,$F9
    FCB $BA,$24,$94,$82,$90,$40,$7D,$F7,$E6,$CF,$3C,$93,$72,$79,$FC,$7F
    FCB $9F,$64,$87,$B1,$5E,$4D,$BD,$D6,$A8,$29,$AB,$4C,$36,$AE,$05,$1B
    FCB $42,$ED,$A4,$85,$B1,$20,$41,$35,$31,$75,$56,$C4,$93,$B4,$08,$BF
    FCB $39,$F3,$9B,$25,$CF,$DF,$97,$D7,$7D,$68,$45,$A7,$C4,$40,$7E,$76
    FCB $D3,$15,$B3,$F9,$8D,$F1,$CF,$1A,$EA,$7B,$BD,$27,$27,$CF,$F9,$7B
    FCB $A0,$82,$38,$BD,$5C,$A0,$92,$24,$EE,$58,$F2,$5A,$35,$5B,$BD,$CE
    FCB $7F,$F7,$F3,$FF,$51,$B4,$48,$2D,$13,$53,$52,$FD,$FF,$E7,$3F,$2C
    FCB $26,$46,$73,$FE,$65,$F3,$FE,$4C,$DD,$B6,$D9,$32,$2B,$15,$53,$4A
    FCB $29,$46,$0B,$48,$52,$15,$02,$0B,$51,$8B,$1A,$79,$A3,$B1,$42,$49
    FCB $AB,$5A,$79,$46,$B9,$9C,$84,$FF,$3F,$8E,$17,$C7,$B1,$76,$5B,$43
    FCB $46,$92,$48,$83,$E4,$9A,$D7,$3E,$1E,$C6,$AE,$61,$1B,$51,$DD,$BE
    FCB $31,$22,$6E,$CE,$7F,$45,$69,$A2,$48,$E7,$77,$B6,$92,$93,$B3,$7F
    FCB $96,$8D,$56,$FF,$FF,$FF,$FF,$FF,$A0,$3A,$6A,$6A,$0B,$6D,$8F,$66
    FCB $B3,$BF,$3C,$EE,$13,$F3,$18,$7F,$27,$8F,$FF,$B3,$3E,$7B,$E7,$DE
    FCB $2A,$83,$5B,$14,$A0,$A4,$0B,$52,$16,$CB,$5E,$A1,$6A,$8A,$3D,$88
    FCB $D3,$35,$AD,$13,$EB,$33,$E2,$CC,$FC,$FC,$FF,$E6,$F1,$F6,$A6,$E0
    FCB $92,$25,$AD,$62,$D4,$70,$1A,$D2,$61,$F3,$FA,$8D,$B5,$86,$EA,$DD
    FCB $DB,$3C,$11,$FB,$AF,$FF,$A2,$45,$A3,$47,$DB,$F1,$45,$49,$20,$9D
    FCB $CB,$FC,$B4,$B6,$AF,$FF,$FF,$FF,$FF,$E8,$2D,$A9,$3C,$A4,$05,$3D
    FCB $E7,$CE,$7F,$9F,$92,$70,$C7,$9C,$CF,$FF,$BF,$79,$8C,$93,$EA,$76
    FCB $D8,$FA,$C1,$07,$63,$6B,$04,$FE,$82,$23,$63,$3B,$16,$84,$EE,$EB
    FCB $A7,$4B,$49,$DE,$B3,$C3,$92,$4F,$F3,$07,$FF,$1F,$DB,$53,$AB,$31
    FCB $C0,$4F,$A2,$49,$78,$E5,$26,$24,$59,$C1,$F6,$C8,$CF,$10,$57,$ED
    FCB $CE,$52,$5F,$75,$BC,$FE,$CB,$9C,$56,$EE,$D7,$49,$49,$97,$14,$FC
    FCB $5D,$A4,$5A,$03,$DF,$CF,$FF,$FF,$FE,$D4,$BB,$44,$82,$02,$9D,$AA
    FCB $5C,$FF,$EF,$9F,$95,$C9,$CD,$84,$9F,$73,$CF,$FD,$E6,$D7,$3D,$A9
    FCB $55,$5C,$8C,$6B,$58,$80,$A6,$29,$AC,$46,$69,$AD,$7B,$C7,$25,$4D
    FCB $9B,$06,$8D,$35,$34,$47,$C0,$9F,$C0,$F3,$FF,$9F,$BF,$36,$DA,$94
    FCB $DE,$C3,$8C,$94,$95,$16,$D2,$41,$24,$8D,$69,$F2,$C6,$F5,$B8,$D4
    FCB $1C,$9A,$0A,$B9,$65,$FB,$01,$20,$9F,$D8,$FC,$BE,$E2,$BF,$50,$B5
    FCB $A0,$99,$B3,$7F,$5E,$B5,$DA,$1B,$FF,$FF,$FF,$FF,$ED,$4B,$D4,$82
    FCB $02,$0D,$D9,$37,$7C,$DC,$FF,$E4,$85,$84,$C3,$FE,$F3,$9F,$F1,$D9
    FCB $B3,$41,$4A,$AA,$7C,$8A,$B1,$21,$4B,$53,$B6,$24,$8D,$06,$D0,$5C
    FCB $76,$0C,$D2,$45,$54,$D4,$B5,$D6,$9D,$E8,$F8,$7D,$7E,$4F,$3F,$F9
    FCB $FB,$ED,$B6,$DD,$BB,$72,$7C,$C3,$82,$34,$42,$49,$F4,$61,$D8,$F9
    FCB $95,$72,$4A,$0A,$FE,$37,$9F,$5A,$50,$CD,$F7,$7A,$FB,$ED,$D9,$1A
    FCB $8A,$D0,$4E,$D9,$FE,$6B,$4B,$41,$BD,$FF,$FF,$FF,$FF,$BB,$3A,$91
    FCB $23,$41,$4E,$E6,$3B,$DF,$67,$FF,$32,$49,$97,$98,$7B,$F1,$FE,$7B
    FCB $FB,$A0,$83,$BC,$E7,$AD,$15,$D2,$B4,$9B,$F4,$FD,$12,$94,$1A,$A0
    FCB $EB,$AC,$44,$3E,$DD,$75,$A7,$96,$27,$DC,$8E,$CA,$FF,$32,$5F,$FF
    FCB $FB,$6E,$DA,$BE,$3D,$DE,$C3,$C9,$C5,$A8,$04,$FA,$35,$27,$C1,$96
    FCB $32,$D6,$D4,$6B,$28,$86,$AF,$32,$DC,$FD,$A7,$E0,$4D,$D4,$DD,$27
    FCB $2C,$7F,$BE,$D4,$B1,$6A,$4C,$FF,$F3,$5A,$45,$4A,$76,$AF,$9F,$FF
    FCB $FF,$CB,$F9,$A2,$46,$D1,$2A,$AB,$C6,$7E,$FE,$F2,$65,$E7,$E4,$33
    FCB $FB,$CF,$F6,$7F,$D0,$40,$43,$FF,$57,$6B,$53,$D7,$69,$24,$A7,$AD
    FCB $68,$35,$2A,$45,$41,$85,$24,$18,$EE,$DD,$18,$F5,$A3,$DC,$7E,$BF
    FCB $FE,$7F,$BE,$E6,$D5,$77,$BD,$CD,$C6,$3F,$F8,$60,$E6,$8D,$4B,$4C
    FCB $27,$E2,$BC,$83,$1C,$A9,$05,$DF,$73,$DC,$DB,$1D,$62,$D2,$3E,$FC
    FCB $71,$C6,$F6,$5B,$F2,$B5,$26,$59,$FE,$69,$2C,$B4,$1D,$BF,$FF,$FF
    FCB $E6,$3B,$F7,$C4,$68,$23,$69,$DB,$53,$5B,$7B,$32,$D8,$FD,$F9,$97
    FCB $38,$4F,$9B,$FF,$F3,$DC,$FE,$D3,$50,$0B,$BC,$D6,$A6,$ED,$68,$5C
    FCB $74,$92,$5F,$A0,$ED,$56,$2D,$0A,$C6,$14,$93,$4B,$BA,$9D,$30,$B3
    FCB $59,$BA,$EF,$FE,$B7,$71,$8E,$ED,$F5,$AD,$AD,$76,$DB,$B7,$B6,$D9
    FCB $BF,$B0,$F7,$F2,$64,$5A,$86,$9F,$4E,$12,$64,$8C,$F8,$D3,$67,$63
    FCB $64,$EC,$9E,$F1,$24,$BD,$E3,$F3,$77,$B2,$AF,$B5,$AD,$A6,$59,$BF
    FCB $91,$6B,$E8,$28,$B7,$FF,$FF,$F9,$ED,$CE,$69,$2D,$A4,$89,$15,$A0
    FCB $B5,$3B,$67,$FF,$FB,$FF,$39,$37,$97,$E7,$F6,$4C,$3D,$4E,$D1,$54
    FCB $59,$E3,$6B,$41,$DC,$41,$B0,$60,$B4,$8D,$4D,$DA,$AC,$5A,$0D,$65
    FCB $60,$82,$8B,$DA,$86,$98,$59,$A4,$B6,$F5,$BF,$F7,$ED,$DF,$DB,$CA
    FCB $DC,$5A,$CE,$DD,$BB,$65,$B6,$FB,$09,$F6,$7F,$8B,$9A,$48,$D0,$4C
    FCB $23,$36,$72,$22,$54,$79,$79,$B7,$90,$5A,$1C,$5A,$53,$78,$FF,$DB
    FCB $2C,$6F,$38,$B4,$13,$3F,$D9,$9A,$D2,$ED,$0D,$DF,$FF,$FF,$FE,$F3
    FCB $AC,$49,$6E,$37,$52,$24,$68,$95,$6C,$7B,$BD,$9F,$E7,$7E,$4E,$4F
    FCB $CE,$FF,$F1,$45,$97,$52,$2D,$5C,$63,$DD,$6A,$76,$C4,$23,$B8,$09
    FCB $57,$75,$55,$8B,$41,$EB,$48,$A7,$6C,$CB,$16,$A4,$C5,$6C,$1D,$A0
    FCB $D6,$FE,$7B,$25,$FF,$F8,$F8,$B8,$90,$C5,$3B,$BB,$6D,$DB,$70,$1F
    FCB $C9,$FC,$D7,$11,$AA,$9C,$26,$01,$4C,$D6,$E8,$9D,$93,$6E,$77,$39
    FCB $78,$08,$C7,$E7,$B7,$6D,$A2,$49,$28,$35,$70,$B5,$A0,$9D,$77,$F0
    FCB $D6,$97,$A2,$DD,$FF,$FF,$FE,$5F,$C1,$A4,$94,$7F,$A0,$93,$41,$13
    FCB $51,$78,$3E,$FF,$FE,$76,$67,$E7,$EF,$36,$7B,$6D,$8D,$54,$53,$B2
    FCB $FB,$B5,$AA,$FB,$1B,$B6,$44,$B5,$B5,$76,$03,$6D,$A3,$41,$6D,$0E
    FCB $A5,$92,$A4,$62,$CF,$B6,$92,$90,$77,$0E,$D7,$0C,$BE,$AB,$18,$70
    FCB $70,$49,$6A,$DB,$ED,$BD,$DF,$76,$73,$E4,$2E,$09,$2B,$4E,$13,$85
    FCB $A8,$EB,$B4,$5B,$C2,$DC,$BB,$98,$3F,$28,$CF,$CD,$4A,$AA,$D4,$D1
    FCB $8C,$16,$F7,$2A,$5B,$4E,$8D,$BF,$0C,$47,$34,$1D,$5B,$F2,$F8,$FD
    FCB $9C,$7C,$E8,$EB,$9F,$EA,$36,$82,$96,$89,$DA,$96,$3F,$FF,$E4,$63
    FCB $FF,$EE,$7A,$FD,$5E,$55,$68,$29,$41,$EE,$EF,$ED,$6A,$79,$EE,$F0
    FCB $5B,$6B,$6D,$DE,$B7,$6C,$49,$34,$BC,$66,$54,$8C,$02,$BD,$D6,$8A
    FCB $A4,$1A,$FC,$63,$0B,$5C,$65,$BE,$5F,$33,$14,$B5,$D9,$B7,$DD,$EE
    FCB $EC,$3F,$84,$F0,$72,$9C,$24,$82,$70,$59,$68,$77,$01,$B6,$0F,$EE
    FCB $64,$1A,$4B,$F6,$B7,$68,$35,$3B,$A4,$C6,$24,$BF,$7B,$5A,$93,$31
    FCB $9F,$CD,$68,$C1,$DA,$0D,$5B,$F3,$FB,$FF,$F9,$AD,$2A,$FF,$FF,$75
    FCB $0D,$4A,$52,$09,$5E,$CF,$FF,$F6,$7F,$39,$EA,$FB,$3D,$A9,$48,$35
    FCB $B3,$ED,$F2,$F7,$57,$1A,$DC,$B6,$11,$6A,$ED,$BC,$78,$92,$6B,$DC
    FCB $FE,$A4,$6B,$5F,$59,$B5,$AB,$68,$2D,$4A,$66,$65,$46,$12,$F1,$BD
    FCB $99,$D9,$05,$B1,$B9,$7F,$7F,$7F,$72,$4F,$72,$B4,$6A,$4E,$74,$C6
    FCB $34,$4F,$6C,$85,$D8,$F5,$B7,$99,$06,$92,$FB,$8A,$6A,$41,$55,$91
    FCB $4B,$46,$C9,$F7,$AD,$49,$9E,$F9,$C3,$4F,$8B,$7A,$0D,$07,$77,$99
    FCB $FD,$F9,$EE,$B1,$26,$2F,$FF,$7B,$DF,$B6,$35,$36,$A5,$B6,$5A,$FF
    FCB $B3,$1E,$3F,$B3,$D4,$5F,$6D,$B6,$DB,$D6,$FF,$D8,$C6,$EF,$02,$DE
    FCB $56,$CA,$EC,$4D,$53,$3C,$30,$45,$FF,$6F,$B4,$62,$CB,$25,$AF,$EB
    FCB $41,$48,$37,$24,$67,$B9,$CD,$D9,$E7,$95,$A8,$2C,$BE,$3F,$DE,$FF
    FCB $CD,$F0,$12,$52,$D3,$22,$3A,$4D,$13,$8A,$73,$B1,$F9,$52,$E2,$82
    FCB $0D,$61,$9A,$0D,$49,$A2,$58,$D2,$59,$FD,$EA,$52,$DA,$7B,$EC,$E4
    FCB $11,$8B,$BA,$9A,$0A,$BB,$CF,$F2,$FC,$18,$B7,$8E,$2D,$7F,$F7,$7F
    FCB $FF,$77,$B5,$35,$2D,$DD,$AF,$77,$2F,$9D,$05,$A9,$B1,$57,$B2,$EC
    FCB $79,$1E,$30,$BD,$8D,$50,$61,$76,$1A,$DB,$36,$B4,$4A,$57,$9D,$45
    FCB $63,$6B,$BB,$15,$B0,$5C,$2D,$60,$E7,$C5,$6A,$44,$37,$2D,$67,$FC
    FCB $97,$DF,$E6,$B7,$01,$6F,$7B,$BB,$B7,$19,$8F,$31,$F8,$2D,$42,$49
    FCB $CB,$16,$D1,$39,$72,$37,$77,$83,$23,$32,$D6,$97,$8A,$45,$A9,$6D
    FCB $6E,$8D,$42,$EF,$F5,$5D,$6D,$3B,$EF,$E1,$04,$62,$EF,$6A,$44,$F6
    FCB $CE,$7B,$FD,$AC,$49,$6A,$6D,$DA,$D6,$B3,$FE,$F7,$FF,$EF,$FB,$FD
    FCB $76,$F9,$D0,$5E,$89,$04,$D5,$AB,$BB,$B6,$3B,$5D,$84,$1C,$DA,$F6
    FCB $AF,$0B,$FB,$02,$36,$6A,$11,$29,$0B,$5A,$81,$88,$23,$AE,$29,$71
    FCB $D6,$A7,$B0,$86,$B9,$FE,$3E,$D6,$A4,$4D,$D4,$07,$3C,$F3,$77,$FF
    FCB $85,$1A,$85,$F7,$76,$36,$FD,$E7,$BF,$21,$12,$4E,$11,$A4,$A4,$58
    FCB $DC,$EF,$A8,$92,$C9,$83,$5A,$57,$62,$95,$75,$24,$95,$88,$25,$FB
    FCB $FD,$6D,$33,$EF,$E0,$69,$F1,$76,$36,$A5,$21,$B6,$70,$B1,$B6,$6E
    FCB $92,$34,$9A,$16,$C5,$80,$F9,$E3,$B7,$BF,$BF,$97,$F8,$EC,$2A,$09
    FCB $74,$ED,$24,$13,$55,$51,$77,$DB,$C8,$0E,$07,$ED,$76,$E3,$9B,$F2
    FCB $A0,$0B,$6C,$A2,$5A,$26,$A6,$C5,$18,$82,$30,$8A,$58,$93,$6B,$BD
    FCB $8A,$E5,$79,$9E,$7C,$42,$82,$9C,$72,$C3,$9B,$EC,$67,$7F,$CA,$58
    FCB $90,$3E,$C7,$E3,$57,$DD,$D9,$80,$D6,$B4,$69,$84,$90,$41,$97,$86
    FCB $ED,$53,$01,$8C,$C1,$AD,$2B,$88,$06,$CE,$CD,$E7,$76,$5A,$4A,$4C
    FCB $FF,$F0,$D1,$AD,$7E,$A5,$34,$19,$7E,$FF,$35,$EB,$4F,$B5,$32,$1F
    FCB $BF,$8F,$DD,$FF,$F3,$7B,$FB,$22,$85,$1A,$93,$53,$C8,$D0,$7D,$BB
    FCB $DD,$F5,$80,$38,$13,$AA,$59,$1F,$79,$C7,$3A,$0C,$14,$82,$34,$14
    FCB $A7,$A8,$60,$89,$21,$63,$AD,$A4,$3C,$76,$B7,$6C,$03,$C3,$FE,$3D
    FCB $07,$55,$4C,$6B,$23,$FC,$BF,$FF,$EB,$64,$49,$26,$BB,$FE,$6F,$BE
    FCB $FE,$5A,$E8,$D3,$09,$20,$87,$6C,$9D,$D5,$C2,$6C,$BA,$E9,$24,$A3
    FCB $C6,$FF,$FC,$FC,$75,$A9,$32,$F9,$CF,$A3,$16,$32,$D4,$D1,$32,$FD
    FCB $FC,$49,$6B,$A4,$EA,$54,$39,$F7,$CD,$BF,$7F,$FE,$77,$7F,$78,$A1
    FCB $12,$4D,$3C,$85,$12,$DB,$BB,$BF,$E5,$60,$18,$77,$B8,$0C,$6F,$F3
    FCB $8A,$FA,$9A,$4D,$48,$23,$41,$4A,$7B,$18,$22,$46,$2D,$6A,$1A,$84
    FCB $76,$BD,$D6,$ED,$CC,$FC,$87,$8D,$ED,$A9,$DB,$DC,$D7,$FD,$F7,$F3
    FCB $CC,$29,$29,$25,$D9,$F3,$FF,$F9,$14,$24,$98,$04,$10,$72,$DA,$FF
    FCB $BF,$F2,$E2,$E9,$F6,$A3,$C5,$41,$F6,$B9,$76,$6C,$DA,$DA,$65,$F2
    FCB $5F,$29,$0B,$5E,$DB,$A9,$0D,$47,$96,$25,$5A,$D9,$74,$18,$B3,$9F
    FCB $FE,$DF,$BF,$FF,$FF,$BD,$9B,$69,$E4,$93,$B5,$6A,$1B,$BB,$DF,$2B
    FCB $1A,$E1,$2B,$8C,$F3,$7D,$8E,$77,$8A,$78,$B5,$16,$82,$91,$A0,$A6
    FCB $DB,$51,$04,$11,$D2,$1A,$D4,$8A,$92,$35,$23,$76,$2D,$4E,$E3,$72
    FCB $1F,$0E,$3B,$8E,$AB,$D4,$DB,$2B,$FF,$F7,$CB,$9B,$EB,$4A,$2D,$75
    FCB $B7,$CF,$F9,$F2,$20,$8D,$31,$D4,$A7,$DC,$FD,$4B,$96,$3E,$38,$09
    FCB $59,$78,$E3,$8D,$C3,$B9,$FD,$6D,$32,$FF,$F3,$48,$5D,$7B,$53,$68
    FCB $8F,$91,$7A,$51,$B3,$BF,$CF,$FF,$7F,$77,$FF,$FB,$3B,$E8,$2E,$D3
    FCB $53,$53,$52,$DB,$6F,$72,$F2,$00,$31,$80,$30,$E7,$F7,$7C,$E3,$E8
    FCB $3A,$D7,$51,$68,$9A,$48,$29,$D5,$64,$10,$48,$59,$5A,$91,$31,$25
    FCB $24,$95,$D7,$DD,$6A,$6A,$AE,$7F,$33,$FD,$5B,$6E,$D8,$FD,$AE,$7B
    FCB $B8,$DF,$92,$2D,$D6,$92,$D2,$7B,$FF,$E5,$6A,$D2,$4A,$A5,$AF,$B6
    FCB $DE,$CF,$B0,$F7,$FB,$8B,$5A,$F2,$EC,$7F,$70,$9A,$A6,$CE,$B6,$99
    FCB $DF,$FC,$D1,$8B,$61,$6D,$D0,$53,$65,$1C,$5F,$36,$7F,$7C,$FF,$EF
    FCB $EF,$7F,$FF,$F7,$DD,$12,$4D,$3B,$41,$A0,$BB,$DB,$B7,$33,$D6,$46
    FCB $60,$B0,$23,$1F,$B7,$FB,$DD,$D8,$85,$25,$EC,$A9,$05,$24,$83,$76
    FCB $D9,$05,$23,$AC,$AD,$04,$4C,$14,$92,$4B,$B5,$FB,$5B,$B6,$F0,$C3
    FCB $EC,$B3,$D4,$3B,$BA,$D4,$DE,$D7,$FF,$DB,$BF,$00,$EB,$5A,$4F,$21
    FCB $C1,$F8,$82,$34,$64,$7E,$D8,$A6,$5D,$8E,$2D,$77,$B7,$DF,$62,$D1
    FCB $99,$6C,$ED,$C7,$01,$B7,$A9,$70,$EB,$41,$33,$DC,$1E,$E6,$92,$D6
    FCB $B6,$5E,$E8,$36,$A4,$6B,$85,$FC,$F6,$5F,$3F,$FB,$FB,$DF,$F6,$6F
    FCB $FE,$D4,$9E,$46,$9D,$A9,$B7,$B3,$B7,$E6,$6B,$98,$C1,$70,$30,$7B
    FCB $BE,$D5,$6D,$D5,$82,$DD,$66,$D7,$41,$06,$92,$0A,$DD,$92,$82,$42
    FCB $C1,$68,$26,$B0,$69,$2C,$5C,$BD,$AD,$ED,$5C,$27,$FC,$66,$54,$A8
    FCB $38,$DD,$B2,$FB,$C6,$6F,$7B,$20,$02,$A3,$35,$A4,$D6,$BD,$6A,$AD
    FCB $24,$75,$11,$AE,$FA,$98,$AF,$B0,$89,$31,$0B,$71,$DF,$05,$A5,$9B
    FCB $E5,$BD,$5D,$66,$F3,$9A,$D0,$4C,$BB,$91,$DC,$D2,$5A,$D7,$FB,$AD
    FCB $D0,$46,$AF,$FB,$3F,$BF,$3F,$BD,$F7,$E0,$E3,$76,$6F,$EC,$B4,$13
    FCB $B4,$F2,$4A,$D9,$7B,$7E,$0E,$E8,$E6,$3A,$EB,$17,$8F,$BD,$4D,$42
    FCB $87,$57,$66,$56,$93,$9D,$8D,$05,$34,$90,$6F,$E6,$82,$42,$C1,$68
    FCB $22,$71,$A4,$02,$D7,$7C,$BD,$8A,$6E,$B9,$FF,$0F,$EC,$B7,$DC,$6D
    FCB $BF,$1F,$3E,$EF,$D6,$E7,$D2,$6B,$5A,$35,$AD,$49,$2C,$D4,$16,$77
    FCB $71,$BE,$F4,$67,$11,$5B,$83,$BC,$05,$AD,$9B,$FD,$DE,$31,$6F,$DE
    FCB $0C,$5A,$93,$2D,$DB,$37,$0D,$25,$AD,$7D,$F6,$65,$FF,$DC,$FD,$F3
    FCB $FD,$DF,$BF,$8F,$FF,$FA,$25,$B4,$13,$A6,$89,$2B,$B1,$DE,$F9,$14
    FCB $DD,$3E,$D7,$90,$AD,$64,$7E,$A4,$10,$52,$D1,$2D,$7E,$37,$2A,$58
    FCB $B2,$1D,$4B,$52,$0D,$A4,$89,$BF,$91,$49,$00,$0A,$41,$51,$4B,$0A
    FCB $D2,$8F,$37,$AD,$B6,$A3,$27,$67,$E7,$B3,$B1,$EA,$BB,$2F,$B3,$EF
    FCB $B2,$CF,$F5,$EB,$49,$38,$49,$04,$7E,$C9,$2F,$6E,$BA,$1D,$D2,$5F
    FCB $D3,$47,$83,$F5,$81,$DF,$26,$AF,$EB,$76,$7C,$75,$A9,$33,$BD,$9E
    FCB $74,$85,$AF,$FB,$AA,$73,$FB,$9F,$F6,$7F,$BB,$FD,$CD,$C7,$FB,$F6
    FCB $9A,$8D,$04,$ED,$55,$5B,$F7,$C7,$15,$BB,$12,$AD,$2C,$AC,$0D,$EA
    FCB $4D,$E2,$4B,$44,$B6,$87,$D8,$54,$2D,$7A,$CE,$AA,$0A,$6D,$25,$55
    FCB $64,$06,$82,$4B,$0D,$06,$81,$6B,$AF,$5C,$5B,$6B,$97,$5B,$76,$AE
    FCB $1E,$33,$E1,$D8,$FE,$5D,$EA,$B7,$32,$DC,$E7,$6F,$FE,$0B,$46,$A4
    FCB $C2,$60,$D4,$58,$5B,$2F,$A9,$E2,$C3,$DA,$05,$ED,$C5,$A4,$17,$AB
    FCB $03,$B6,$3C,$51,$70,$3F,$6B,$41,$33,$B3,$8F,$3A,$31,$67,$FD,$DE
    FCB $7F,$D9,$3E,$FF,$F6,$FF,$76,$65,$FF,$BE,$D0,$4F,$23,$4E,$DB,$6F
    FCB $77,$F0,$53,$6F,$98,$2D,$1A,$5B,$5C,$36,$D0,$51,$12,$34,$42,$0F
    FCB $BC,$06,$2C,$B5,$9D,$D3,$6D,$AD,$55,$77,$5E,$D1,$81,$6A,$A0,$C6
    FCB $48,$B9,$2B,$B2,$A5,$FB,$1B,$60,$FC,$FC,$97,$CB,$3D,$C6,$F7,$7F
    FCB $F9,$EF,$EF,$91,$6A,$13,$84,$C0,$28,$64,$FF,$6F,$81,$7A,$0B,$51
    FCB $56,$F1,$1A,$E7,$6D,$DA,$C5,$66,$74,$1A,$DE,$B3,$F6,$B5,$26,$6E
    FCB $37,$1C,$3A,$7C,$5F,$FE,$F7,$0F,$BD,$93,$EF,$FE,$EF,$F7,$F1,$8F
    FCB $FA,$05,$A9,$3A,$44,$92,$AD,$BB,$E2,$8D,$96,$F7,$25,$6B,$12,$4B
    FCB $5C,$B5,$37,$5E,$75,$26,$8E,$E3,$92,$D6,$B9,$5F,$52,$9A,$16,$D6
    FCB $EE,$D7,$0D,$49,$01,$AA,$83,$15,$90,$5A,$EA,$12,$8F,$5B,$7C,$6D
    FCB $F9,$9F,$F8,$C9,$DF,$C7,$B8,$DE,$EC,$F3,$F7,$CB,$E2,$96,$26,$44
    FCB $85,$13,$9A,$B3,$0B,$37,$DB,$28,$72,$8C,$7F,$07,$6C,$F9,$E8,$4C
    FCB $D7,$DE,$29,$32,$E7,$EE,$35,$A4,$B5,$FF,$EF,$B0,$FB,$F9,$F7,$FF
    FCB $7F,$DB,$F8,$FF,$E8,$96,$D4,$9D,$29,$12,$ED,$F7,$82,$AD,$B3,$F6
    FCB $40,$58,$0B,$85,$EB,$0B,$43,$1A,$08,$2C,$77,$50,$56,$35,$91,$AE
    FCB $34,$1D,$56,$D6,$AB,$B2,$1A,$96,$B9,$6A,$10,$51,$30,$AC,$2D,$27
    FCB $EB,$EE,$3B,$BE,$7C,$FE,$16,$0F,$FB,$F1,$EE,$5F,$FC,$DE,$DF,$63
    FCB $17,$06,$98,$4C,$11,$E2,$1C,$07,$F5,$C6,$D5,$B7,$3E,$DE,$B5,$AF
    FCB $77,$CC,$2D,$BB,$AF,$6E,$B9,$5A,$09,$97,$B3,$0F,$49,$AD,$67,$FD
    FCB $FF,$FF,$CF,$BF,$F7,$FE,$DF,$C7,$FE,$D3,$CB,$52,$76,$A5,$28,$77
    FCB $3F,$6E,$E3,$E0,$E0,$52,$00,$8C,$AE,$BD,$D0,$C4,$28,$8B,$D6,$C8
    FCB $BC,$23,$07,$45,$AA,$C1,$4D,$8A,$00,$2A,$09,$BA,$94,$3E,$0D,$61
    FCB $68,$DF,$AF,$BF,$BA,$DB,$C7,$CF,$C3,$6B,$DE,$E1,$E3,$FB,$BC,$BF
    FCB $7B,$0B,$8D,$BB,$60,$C4,$E1,$38,$2C,$60,$55,$2F,$35,$DD,$5D,$5E
    FCB $CC,$57,$5A,$C2,$A1,$92,$DF,$EE,$B8,$89,$D2,$69,$56,$A4,$CB,$E5
    FCB $6B,$6E,$80,$8C,$58,$F9,$F5,$7F,$FF,$CF,$BF,$FB,$37,$DF,$BF,$DF
    FCB $A9,$3C,$92,$74,$A5,$36,$DF,$3B,$9B,$EF,$26,$B0,$16,$11,$90,$D6
    FCB $FA,$2E,$AA,$8B,$60,$A0,$59,$C0,$65,$D1,$45,$3C,$77,$90,$B5,$0B
    FCB $9B,$A9,$47,$82,$97,$5D,$A4,$A1,$A9,$25,$8F,$67,$B5,$BB,$66,$4F
    FCB $F6,$64,$2E,$3F,$3F,$6F,$AE,$F7,$7F,$7B,$F5,$32,$A1,$69,$CB,$46
    FCB $5C,$36,$E1,$DB,$EF,$6A,$C1,$BF,$9B,$58,$B2,$D6,$50,$3E,$A8,$EB
    FCB $89,$BA,$32,$0A,$4C,$B9,$5A,$55,$20,$D4,$51,$8B,$5F,$FE,$FF,$FF
    FCB $E7,$DF,$FF,$7B,$FD,$FF,$57,$69,$DA,$6A,$34,$4A,$6E,$AC,$7D,$E3
    FCB $7C,$79,$8B,$02,$91,$90,$F3,$88,$8A,$1A,$9D,$C1,$80,$48,$0C,$B6
    FCB $8B,$6F,$15,$D8,$06,$C3,$B6,$35,$6F,$2D,$20,$23,$62,$2A,$3A,$5C
    FCB $BE,$37,$7E,$79,$EA,$90,$63,$C5,$FF,$E3,$DC,$DF,$77,$DE,$F6,$DB
    FCB $D8,$92,$72,$2B,$D8,$06,$A2,$5A,$AF,$C1,$AA,$6D,$DC,$FB,$12,$17
    FCB $36,$A1,$7A,$9F,$C5,$A2,$74,$82,$B5,$26,$5A,$D7,$58,$A3,$CC,$FF
    FCB $B1,$FF,$FF,$CF,$BF,$FE,$EF,$DF,$7F,$A0,$BB,$4D,$4F,$22,$5B,$55
    FCB $DC,$B1,$DD,$FE,$38,$15,$81,$AC,$84,$F9,$34,$D1,$AB,$6D,$CA,$D4
    FCB $2C,$D7,$17,$55,$E9,$B1,$EC,$6C,$B2,$1C,$3A,$99,$43,$7C,$A4,$57
    FCB $B6,$29,$04,$6E,$91,$0B,$C7,$77,$F3,$CD,$E0,$8D,$35,$21,$B5,$24
    FCB $AF,$5F,$DE,$EB,$2F,$BB,$EA,$DF,$D4,$EA,$49,$32,$27,$CD,$A5,$6B
    FCB $BD,$DB,$C6,$FD,$B3,$EF,$3B,$18,$BA,$D7,$0B,$50,$E5,$CB,$0A,$A1
    FCB $AD,$A7,$62,$DC,$6D,$7D,$99,$FF,$DF,$FF,$FF,$FF,$FF,$DF,$6F,$BF
    FCB $D1,$24,$D0,$4E,$D4,$85,$BB,$C7,$8D,$EC,$66,$F0,$0A,$C3,$16,$1C
    FCB $91,$9E,$9A,$29,$DB,$78,$2D,$40,$6B,$01,$A8,$DA,$6D,$F6,$59,$64
    FCB $0C,$F5,$32,$84,$57,$1A,$51,$78,$E2,$24,$90,$71,$6B,$0B,$FD,$AE
    FCB $FF,$36,$E0,$23,$4F,$08,$F9,$6D,$4D,$6A,$1D,$AF,$CF,$67,$7A,$BE
    FCB $C5,$AD,$8D,$3E,$90,$6D,$76,$5D,$DB,$C1,$BD,$EF,$20,$F1,$BF,$AD
    FCB $8B,$00,$6A,$93,$BB,$2D,$C5,$EB,$A2,$14,$F6,$1F,$CF,$FF,$FB,$FF
    FCB $FF,$FF,$EE,$FF,$7B,$23,$DA,$6A,$4A,$4E,$D4,$DB,$55,$EF,$B3,$F7
    FCB $E0,$12,$10,$AC,$F5,$92,$AE,$29,$10,$AB,$B5,$18,$B8,$48,$03,$66
    FCB $A4,$4D,$F6,$BB,$2F,$03,$3D,$4C,$AA,$37,$2D,$70,$23,$8A,$5A,$08
    FCB $6D,$21,$19,$83,$DD,$EE,$3C,$BC,$88,$D3,$44,$97,$A8,$B7,$5C,$76
    FCB $36,$EC,$7B,$CB,$AE,$94,$4B,$5A,$D8,$28,$FC,$6C,$DE,$D4,$77,$FF
    FCB $FF,$B3,$23,$62,$C5,$AD,$D5,$CB,$D4,$2C,$79,$A5,$4D,$BB,$A9,$2F
    FCB $F3,$FF,$FE,$FF,$B3,$EC,$FF,$EE,$DF,$CB,$DE,$36,$9E,$49,$3B,$44
    FCB $D5,$55,$93,$76,$3F,$D9,$02,$18,$01,$5F,$1A,$E6,$AC,$A0,$8A,$EC
    FCB $1B,$2B,$32,$45,$F6,$68,$20,$DF,$6B,$B2,$C8,$17,$F6,$15,$6A,$70
    FCB $AD,$86,$72,$82,$26,$34,$76,$24,$05,$FD,$DA,$DB,$9F,$0A,$6A,$C4
    FCB $62,$D5,$BE,$33,$39,$58,$92,$B6,$B6,$9D,$AF,$4F,$8E,$63,$92,$CC
    FCB $6F,$6E,$54,$F6,$17,$8D,$FC,$BE,$E0,$47,$95,$AC,$72,$DB,$F5,$83
    FCB $FA,$54,$F7,$76,$BC,$FF,$FF,$FE,$FF,$B3,$EC,$FF,$EE,$DF,$B3,$7C
    FCB $A9,$12,$79,$69,$E5,$36,$29,$98,$55,$DF,$78,$40,$C2,$B5,$8C,$AF
    FCB $2C,$3A,$A5,$A0,$8B,$D8,$C8,$2D,$E2,$DA,$CE,$CD,$12,$AD,$C6,$59
    FCB $64,$0F,$EA,$22,$B4,$2C,$04,$98,$59,$F4,$1A,$B4,$9B,$50,$92,$D6
    FCB $BB,$FB,$AD,$BB,$2F,$82,$81,$1A,$C4,$45,$FC,$CE,$94,$59,$F6,$84
    FCB $A4,$39,$D4,$BE,$EB,$DB,$B6,$A3,$BD,$B0,$B2,$37,$66,$31,$EE,$18
    FCB $CE,$B1,$64,$B6,$C7,$5F,$DC,$69,$51,$5A,$B5,$9F,$FF,$FF,$FB,$FE
    FCB $E7,$FF,$DF,$ED,$F6,$6C,$66,$82,$76,$9A,$20,$86,$2B,$B3,$67,$B8
    FCB $79,$5C,$58,$2E,$31,$92,$33,$8A,$75,$A2,$68,$0F,$77,$17,$5F,$58
    FCB $C3,$B3,$44,$AD,$F1,$F6,$56,$7F,$A8,$8A,$D5,$B0,$35,$95,$BF,$55
    FCB $4A,$8A,$B6,$24,$B5,$AC,$96,$FB,$DC,$6E,$45,$0B,$49,$25,$A2,$2F
    FCB $E5,$AF,$49,$7C,$FD,$9E,$E6,$E1,$B3,$BB,$A9,$46,$F1,$F7,$FC,$FB
    FCB $F3,$CF,$82,$D7,$06,$C1,$FF,$B1,$A5,$45,$6F,$5F,$FF,$FF,$FF,$7F
    FCB $FF,$FC,$BB,$E8,$19,$FF,$51,$69,$DA,$6A,$21,$4A,$22,$BB,$D9,$64
    FCB $F3,$AC,$58,$16,$1E,$06,$CC,$1B,$49,$A7,$74,$D3,$B5,$B0,$23,$D6
    FCB $35,$9D,$9A,$6B,$EF,$15,$2A,$58,$B3,$7F,$51,$14,$55,$6C,$0D,$64
    FCB $7E,$ED,$BA,$AE,$D2,$C5,$8B,$5F,$67,$BB,$B8,$21,$12,$4F,$88,$8E
    FCB $BB,$EC,$04,$76,$1E,$78,$C7,$ED,$CD,$82,$8E,$C5,$2B,$BC,$7D,$EA
    FCB $35,$FF,$7C,$F3,$92,$25,$9F,$FE,$CB,$4A,$8B,$FF,$FF,$FF,$FE,$FF
    FCB $FF,$FC,$6F,$F7,$F3,$E8,$97,$41,$33,$52,$9A,$BD,$F6,$6F,$CF,$5C
    FCB $16,$13,$6B,$85,$87,$5A,$A2,$D1,$A2,$89,$D2,$14,$4B,$F5,$B8,$46
    FCB $D6,$2D,$AF,$D9,$A6,$BB,$DB,$20,$DA,$EB,$37,$F6,$6C,$6A,$B6,$2C
    FCB $18,$30,$7D,$8E,$AA,$94,$36,$B7,$95,$AC,$90,$1E,$37,$60,$83,$16
    FCB $9C,$2D,$14,$CE,$ED,$74,$92,$B0,$CB,$67,$D9,$2D,$8C,$D6,$83,$6C
    FCB $ED,$F6,$7E,$C6,$A5,$B6,$79,$B8,$71,$B9,$C2,$B2,$BF,$3D,$4F,$0A
    FCB $3A,$6F,$7F,$FF,$FF,$FF,$7D,$9D,$9E,$E7,$DB,$DA,$FB,$FC,$74,$43
    FCB $4E,$D3,$CD,$BD,$FE,$FB,$0E,$C0,$5C,$20,$78,$11,$4B,$E2,$48,$51
    FCB $A5,$4F,$0A,$4E,$9D,$4B,$D8,$39,$9A,$51,$87,$65,$A2,$77,$B6,$33
    FCB $AC,$0F,$F5,$2F,$65,$5A,$BA,$F0,$07,$B7,$1E,$A4,$36,$B6,$F2,$71
    FCB $25,$85,$8D,$F1,$0D,$69,$85,$A2,$0E,$7B,$1A,$48,$DE,$1E,$A1,$98
    FCB $C9,$FD,$B7,$6A,$FF,$B3,$F7,$B1,$CB,$3D,$FC,$F3,$83,$48,$AF,$F9
    FCB $43,$50,$95,$1D,$37,$AB,$FF,$9F,$FF,$F7,$D9,$FF,$52,$FF,$6D,$D4
    FCB $BC,$FE,$36,$9A,$34,$CA,$86,$FB,$EF,$33,$92,$49,$05,$E5,$86,$78
    FCB $B4,$90,$46,$BD,$3A,$49,$3A,$41,$D9,$B0,$55,$6E,$02,$E4,$2E,$CD
    FCB $36,$DE,$D8,$CE,$B1,$7F,$F5,$1F,$56,$DE,$BC,$16,$3D,$B8,$C1,$4A
    FCB $55,$8E,$F7,$3A,$4B,$80,$BD,$BB,$6C,$49,$69,$26,$A3,$3B,$32,$B7
    FCB $4F,$F3,$EA,$87,$DE,$75,$E8,$6A,$57,$FB,$3B,$BB,$68,$23,$32,$F8
    FCB $FF,$9C,$93,$A5,$5B,$3E,$5E,$A6,$95,$1D,$37,$AB,$FF,$9F,$FF,$F7
    FCB $BF,$3E,$D8,$BD,$F6,$D4,$C0,$3D,$FB,$44,$26,$A6,$6E,$DF,$97,$3E
    FCB $45,$E5,$81,$C8,$5A,$E6,$B4,$01,$18,$B5,$57,$52,$74,$8D,$33,$7F
    FCB $B2,$CE,$0B,$25,$63,$DF,$4D,$DE,$E3,$F0,$0F,$F5,$1F,$7B,$63,$0E
    FCB $2E,$C7,$65,$D4,$29,$51,$56,$E0,$79,$95,$83,$B7,$5D,$62,$7D,$3C
    FCB $92,$CE,$56,$41,$49,$13,$ED,$35,$6B,$3F,$EE,$2E,$D5,$A9,$5F,$FF
    FCB $77,$69,$D2,$7D,$1F,$8F,$8A,$9F,$39,$E6,$52,$5E,$F0,$BF,$89,$53
    FCB $DD,$FF,$67,$FF,$E7,$DF,$7E,$5B,$6F,$4A,$3F,$52,$9D,$62,$F2,$AB
    FCB $D3,$34,$54,$D5,$7F,$9C,$E6,$C5,$C9,$59,$8C,$93,$E2,$48,$24,$8F
    FCB $77,$13,$C9,$D2,$48,$9E,$5E,$0C,$72,$2C,$93,$D9,$68,$B7,$B8,$FC
    FCB $17,$1F,$EA,$F3,$B6,$C6,$18,$03,$B3,$1B,$54,$41,$AD,$BB,$76,$1C
    FCB $E4,$EE,$05,$68,$D3,$C2,$35,$D7,$11,$9E,$33,$FD,$41,$3E,$F5,$41
    FCB $B7,$B5,$7F,$B3,$BA,$2C,$46,$FC,$44,$5A,$4D,$91,$B5,$F2,$73,$D2
    FCB $4B,$76,$1C,$BD,$74,$DF,$F9,$F7,$FF,$CF,$BF,$FD,$B6,$ED,$20,$ED
    FCB $A9,$5C,$5A,$CD,$5B,$44,$99,$50,$B7,$BC,$C9,$C3,$EB,$86,$60,$C9
    FCB $AD,$51,$24,$62,$BD,$46,$A4,$ED,$3C,$92,$BD,$F9,$1D,$75,$90,$3E
    FCB $A3,$4D,$D4,$C7,$5F,$E2,$FC,$F5,$3B,$06,$F6,$D6,$D8,$45,$83,$BE
    FCB $36,$CB,$52,$D4,$EF,$B9,$9C,$DA,$DB,$17,$01,$24,$4B,$11,$AD,$6D
    FCB $1C,$F3,$EC,$DE,$A5,$F3,$2E,$F6,$A1,$8D,$BF,$FD,$ED,$EB,$BE,$53
    FCB $C9,$8D,$FE,$EB,$F9,$65,$E8,$D6,$93,$DC,$E7,$A5,$4F,$77,$B3,$FF
    FCB $FF,$9F,$7F,$F7,$6A,$7A,$EB,$EA,$A9,$DC,$5A,$D7,$A1,$B4,$ED,$3C
    FCB $AB,$73,$98,$6F,$33,$0C,$6B,$C0,$7D,$6B,$41,$1A,$CD,$BE,$82,$F4
    FCB $49,$DA,$6A,$5F,$B9,$5B,$EB,$81,$27,$AB,$A6,$F6,$3A,$DF,$C5,$FF
    FCB $B5,$03,$5E,$F6,$D6,$A6,$0E,$B0,$F1,$8D,$4C,$DA,$DA,$9B,$8D,$F6
    FCB $11,$99,$73,$58,$B5,$02,$49,$C2,$4A,$5B,$3C,$EE,$A3,$9F,$3F,$B5
    FCB $0D,$96,$D5,$F3,$EF,$E3,$F5,$1F,$7E,$4F,$E7,$F5,$89,$7E,$7F,$48
    FCB $4F,$77,$73,$FE,$E7,$66,$7D,$FE,$EE,$DB,$70,$AC,$D0,$AA,$F1,$62
    FCB $5A,$B6,$9E,$44,$AD,$B7,$31,$CD,$9F,$2B,$93,$C8,$A1,$24,$96,$B7
    FCB $ED,$AA,$51,$2F,$4E,$90,$44,$97,$EC,$C6,$EB,$58,$4E,$4D,$45,$A2
    FCB $DE,$E3,$E2,$C3,$6F,$35,$16,$BB,$7B,$69,$29,$92,$B9,$E3,$DC,$15
    FCB $15,$41,$83,$6F,$E1,$8E,$37,$C1,$71,$62,$73,$A3,$41,$67,$79,$2E
    FCB $A5,$B9,$F3,$FB,$50,$DF,$6A,$F9,$F7,$FF,$FF,$BF,$8C,$FC,$FE,$BA
    FCB $3F,$9F,$E9,$09,$EE,$EE,$7D,$9D,$9E,$C9,$F7,$FB,$6F,$6D,$E4,$58
    FCB $D0,$B7,$C2,$91,$51,$A9,$35,$42,$27,$73,$3F,$73,$32,$1B,$8B,$5A
    FCB $4A,$47,$FE,$DB,$65,$A2,$5D,$04,$F3,$44,$BF,$FC,$B1,$60,$4E,$4D
    FCB $43,$A0,$EF,$75,$F8,$4F,$B2,$D0,$06,$B2,$D4,$3A,$D4,$A8,$0B,$CB
    FCB $8E,$3B,$49,$A8,$55,$B6,$3B,$7F,$33,$FE,$62,$D6,$92,$7D,$04,$E0
    FCB $EE,$65,$E3,$C7,$E7,$ED,$01,$5E,$DF,$FF,$FF,$FF,$7F,$3F,$FF,$0E
    FCB $B6,$B5,$9F,$FE,$8C,$4F,$77,$BD,$E7,$FF,$E7,$DF,$DB,$6D,$EF,$91
    FCB $6B,$44,$EA,$7C,$5D,$6B,$B3,$DD,$48,$94,$83,$3D,$85,$E7,$3C,$5A
    FCB $DA,$4B,$2B,$7E,$DD,$BB,$65,$D3,$51,$B4,$F2,$14,$0D,$9F,$66,$B0
    FCB $03,$D6,$6D,$58,$89,$DE,$EB,$7C,$03,$EC,$B4,$23,$5F,$7B,$5A,$9C
    FCB $26,$67,$36,$B1,$D4,$EA,$52,$D5,$76,$FC,$AC,$7F,$F1,$62,$C4,$FA
    FCB $09,$84,$66,$A9,$EC,$9E,$82,$F9,$FB,$55,$4F,$45,$A4,$77,$FF,$FF
    FCB $63,$15,$39,$FF,$F8,$75,$B1,$23,$FF,$D2,$13,$B3,$EF,$79,$FB,$3F
    FCB $3E,$FE,$D4,$AB,$DF,$2B,$5A,$D3,$58,$AF,$AE,$25,$9E,$AD,$FA,$95
    FCB $18,$B6,$8B,$1B,$02,$B5,$AE,$2A,$32,$3E,$DB,$1E,$EE,$D3,$C8,$D4
    FCB $9E,$75,$17,$9E,$C8,$2C,$AE,$70,$BA,$B1,$13,$BD,$D6,$F8,$07,$D9
    FCB $68,$46,$BE,$FA,$D4,$D9,$01,$AF,$38,$FA,$4E,$D5,$A8,$53,$6D,$8E
    FCB $CD,$60,$DB,$91,$C1,$60,$8D,$01,$38,$48,$14,$C3,$F3,$FF,$FD,$4E
    FCB $A7,$AA,$D7,$FE,$5F,$7F,$25,$DD,$95,$2E,$7E,$39,$E6,$3A,$32,$7F
    FCB $E9,$09,$D5,$77,$EF,$9F,$FF,$9F,$7E,$A6,$AB,$EF,$E2,$C4,$1D,$F8
    FCB $BD,$1E,$7F,$B1,$56,$E1,$F6,$78,$F3,$F7,$F6,$D8,$FE,$DD,$3B,$4F
    FCB $A6,$A0,$FD,$E7,$7D,$60,$04,$8D,$7B,$B6,$34,$1B,$8D,$D6,$F8,$01
    FCB $7B,$2D,$08,$D7,$EF,$5A,$9B,$80,$30,$9C,$15,$A5,$50,$DB,$62,$9A
    FCB $B1,$AB,$19,$2C,$1C,$B8,$02,$4A,$04,$C8,$2D,$44,$FC,$3E,$FF,$EA
    FCB $75,$6D,$D8,$3D,$9F,$EE,$6D,$77,$AB,$0B,$3E,$7B,$9C,$18,$C4,$B0
    FCB $B3,$F5,$89,$D6,$BF,$FF,$FF,$F3,$EF,$D4,$D4,$FD,$F2,$14,$26,$F8
    FCB $51,$E0,$FF,$77,$E6,$CF,$D9,$D9,$07,$D4,$EC,$DD,$FB,$B5,$27,$69
    FCB $F4,$D6,$EE,$CD,$76,$E4,$00,$33,$6B,$1E,$A6,$35,$3D,$DD,$6E,$30
    FCB $01,$F6,$68,$75,$BE,$F5,$A9,$B8,$19,$87,$5A,$05,$1D,$49,$36,$A7
    FCB $55,$AA,$2A,$DE,$1E,$5C,$D7,$83,$5D,$1A,$70,$92,$10,$F3,$3E,$FE
    FCB $6D,$56,$AB,$EF,$EC,$F1,$FE,$CD,$95,$63,$27,$F7,$99,$98,$E9,$10
    FCB $FF,$AC,$4E,$BE,$BE,$7F,$F7,$F3,$EF,$BB,$52,$BD,$F3,$1A,$A7,$EB
    FCB $D1,$C0,$7B,$FB,$B9,$FF,$FF,$C2,$F5,$36,$76,$F7,$2E,$82,$74,$8D
    FCB $35,$E5,$8E,$3B,$AE,$04,$16,$76,$71,$4D,$D4,$CB,$78,$CB,$16,$11
    FCB $EC,$B4,$5A,$C7,$EE,$B5,$5B,$16,$72,$4C,$51,$49,$30,$EA,$44,$D4
    FCB $EE,$D8,$A7,$54,$E0,$C7,$64,$06,$15,$82,$70,$92,$24,$83,$CC,$FB
    FCB $CB,$2D,$BB,$55,$F7,$F6,$5E,$7D,$E6,$5B,$E8,$91,$F9,$EF,$33,$1C
    FCB $C4,$A1,$FF,$5D,$3A,$F2,$BC,$FF,$EF,$E7,$DF,$6D,$A0,$FB,$F8,$0A
    FCB $B3,$39,$A3,$C1,$9E,$F7,$B3,$FF,$FF,$FB,$B7,$DF,$DB,$18,$D3,$53
    FCB $C8,$D0,$50,$F2,$D8,$ED,$64,$08,$B5,$9D,$5E,$2B,$6A,$51,$DC,$65
    FCB $8B,$0D,$BC,$D0,$D7,$67,$71,$56,$C0,$E7,$31,$C5,$A6,$43,$52,$6A
    FCB $94,$2A,$DA,$D0,$6D,$F7,$2C,$F9,$32,$B5,$D2,$49,$12,$73,$83,$C9
    FCB $FF,$96,$54,$DE,$A1,$B1,$BB,$96,$78,$E3,$F9,$76,$F1,$4B,$1F,$3F
    FCB $9F,$CC,$4A,$1F,$F5,$D3,$AA,$97,$21,$D9,$9F,$7F,$3E,$FD,$4D,$07
    FCB $D8,$E4,$DB,$99,$CD,$19,$3B,$FF,$F7,$FF,$FF,$EF,$6F,$7F,$75,$0C
    FCB $52,$79,$35,$1A,$AF,$8D,$C7,$8B,$AE,$02,$CF,$57,$8D,$DA,$95,$37
    FCB $19,$6B,$59,$DF,$94,$34,$9B,$7D,$D6,$AB,$75,$87,$84,$D5,$29,$CC
    FCB $93,$2A,$4D,$44,$B5,$2A,$C5,$2A,$EB,$6D,$EA,$9E,$4E,$0B,$04,$68
    FCB $27,$3A,$5D,$87,$FF,$2C,$A1,$76,$80,$FF,$EC,$FD,$CF,$67,$6F,$0F
    FCB $FF,$27,$BC,$C4,$A1,$FF,$58,$99,$CB,$E0,$6C,$9F,$7F,$FF,$EA,$68
    FCB $3D,$CC,$66,$FC,$F3,$4F,$E6,$FC,$7F,$FF,$7F,$3E,$F7,$B5,$6F,$DE
    FCB $A5,$BA,$24,$49,$A8,$EA,$C8,$DE,$D8,$B0,$59,$00,$F5,$7A,$D4,$EA
    FCB $68,$07,$6B,$65,$AC,$3F,$72,$84,$46,$85,$DD,$D6,$ED,$D6,$CF,$09
    FCB $38,$9C,$24,$82,$31,$B4,$4B,$4D,$41,$BD,$AA,$D6,$A7,$77,$8C,$64
    FCB $C0,$01,$24,$13,$E9,$C7,$61,$FF,$CB,$2A,$BB,$42,$85,$7F,$F3,$BF
    FCB $F6,$4A,$BC,$FF,$3F,$CB,$CB,$11,$D6,$3F,$6D,$62,$E9,$9E,$3F,$58
    FCB $D4,$D6,$4F,$FF,$FB,$EA,$6D,$B8,$5F,$DF,$CE,$C8,$8E,$1B,$F2,$FF
    FCB $FF,$F7,$F6,$DC,$77,$DC,$B7,$41,$7A,$6A,$08,$92,$6E,$0D,$DC,$20
    FCB $00,$70,$EA,$EB,$5A,$9A,$94,$D4,$0E,$E2,$8C,$5A,$FF,$72,$85,$69
    FCB $F4,$4F,$7B,$15,$75,$2E,$1C,$27,$C4,$FA,$34,$13,$05,$A8,$A6,$A2
    FCB $6A,$1B,$6D,$6A,$6E,$DE,$70,$BC,$05,$89,$28,$4E,$60,$AA,$67,$DE
    FCB $38,$DB,$76,$ED,$47,$6B,$2A,$73,$3E,$F6,$6D,$F0,$B3,$FB,$3E,$6E
    FCB $B6,$52,$8B,$DC,$A9,$62,$E9,$9F,$F0,$6D,$58,$01,$FF,$FD,$ED,$B5
    FCB $55,$01,$FD,$9F,$EC,$AD,$28,$77,$CF,$71,$FF,$3D,$BF,$6D,$C7,$BF
    FCB $BE,$82,$DD,$3C,$A4,$12,$6F,$BB,$B2,$2C,$05,$9F,$23,$51,$A7,$DA
    FCB $94,$83,$6A,$0B,$75,$CC,$0F,$DC,$A1,$49,$1B,$45,$BD,$AD,$57,$66
    FCB $72,$4D,$8B,$5A,$34,$13,$9C,$D9,$68,$93,$50,$1B,$6D,$6A,$AA,$F7
    FCB $2D,$7F,$80,$2D,$42,$64,$48,$15,$93,$EE,$5C,$74,$18,$DE,$F6,$D4
    FCB $97,$FB,$3F,$BE,$F3,$B6,$B8,$3F,$E5,$CE,$B7,$17,$AF,$75,$B0,$AE
    FCB $99,$F6,$F9,$A2,$58,$05,$7F,$FF,$DE,$DB,$55,$B0,$EE,$F1,$C3,$EB
    FCB $A4,$BF,$DF,$3D,$C7,$FC,$F6,$FB,$6E,$3E,$FE,$FA,$0B,$6A,$4D,$52
    FCB $09,$38,$EE,$D8,$00,$0B,$98,$CF,$7A,$31,$A1,$41,$55,$1B,$D7,$E0
    FCB $7B,$B3,$74,$91,$D1,$3B,$76,$B5,$5D,$99,$E6,$4C,$5A,$34,$13,$21
    FCB $F7,$52,$0B,$4F,$29,$B1,$B6,$F6,$D9,$99,$78,$0B,$62,$70,$9F,$05
    FCB $64,$FB,$97,$1B,$56,$DB,$F7,$DD,$C3,$B9,$EE,$FF,$99,$FE,$E7,$33
    FCB $19,$22,$57,$E6,$B1,$33,$FD,$96,$C1,$50,$5C,$9F,$7F,$BD,$B6,$DD
    FCB $86,$F6,$FC,$3D,$AE,$9F,$19,$FF,$FB,$9B,$FF,$BE,$ED,$43,$BC,$B7
    FCB $3D,$12,$DA,$08,$90,$52,$E5,$8D,$E0,$B2,$B0,$FB,$0E,$DA,$D3,$EA
    FCB $68,$08,$29,$B3,$7A,$E5,$8B,$3D,$D9,$A9,$A7,$D6,$2A,$22,$7D,$B7
    FCB $AD,$B3,$92,$78,$23,$41,$39,$8E,$FB,$52,$DA,$79,$07,$1B,$71,$4D
    FCB $BB,$99,$20,$2D,$AD,$39,$D2,$2A,$99,$F7,$1E,$36,$AB,$6F,$EF,$BC
    FCB $9E,$FB,$DE,$3F,$93,$FD,$9E,$72,$6D,$71,$2F,$F8,$27,$57,$2E,$5D
    FCB $6B,$52,$88,$D2,$E5,$FE,$6F,$41,$A1,$E0,$FF,$FF,$B5,$89,$86,$CF
    FCB $FF,$D9,$FB,$FD,$F7,$6A,$FF,$6E,$76,$89,$26,$82,$25,$28,$96,$5E
    FCB $00,$00,$46,$3F,$2D,$31,$52,$91,$54,$A6,$C2,$F5,$CB,$16,$7B,$B3
    FCB $6D,$3E,$B1,$6E,$9E,$53,$EE,$EB,$6E,$42,$6E,$41,$1A,$09,$CE,$97
    FCB $7E,$D7,$69,$A9,$AC,$6D,$C5,$36,$DF,$38,$03,$18,$92,$61,$3F,$50
    FCB $7F,$3B,$96,$D0,$BB,$FB,$EF,$86,$ED,$9D,$F1,$E7,$CF,$9B,$9F,$9F
    FCB $D6,$91,$F7,$AC,$4E,$C5,$3F,$17,$E3,$33,$E3,$BF,$DF,$41,$AB,$C1
    FCB $C7,$FF,$ED,$69,$27,$D4,$CF,$FF,$D9,$7F,$2F,$B7,$71,$DB,$FE,$FD
    FCB $D1,$25,$4D,$44,$D4,$76,$7A,$C0,$09,$CB,$F4,$C6,$B6,$83,$45,$52
    FCB $9B,$0B,$D2,$8E,$4E,$F9,$B5,$26,$01,$26,$22,$44,$AE,$EE,$B7,$64
    FCB $E6,$18,$B4,$13,$84,$FE,$7F,$E8,$94,$B4,$F2,$9C,$53,$6D,$EC,$92
    FCB $58,$C5,$AD,$39,$AA,$59,$FC,$DC,$8D,$48,$0D,$AB,$E7,$55,$85,$DE
    FCB $D7,$BE,$0D,$C7,$3F,$25,$FD,$76,$6C,$CA,$4B,$CB,$DD,$62,$77,$6E
    FCB $E0,$30,$65,$7F,$FD,$FE,$F1,$13,$57,$FE,$16,$37,$E0,$B4,$C5,$5F
    FCB $FF,$FF,$F7,$DD,$BB,$FB,$FE,$FD,$D1,$24,$D1,$20,$D4,$3D,$AD,$E0
    FCB $2C,$0F,$9E,$D3,$09,$36,$34,$4A,$44,$35,$36,$B2,$F5,$E3,$03,$B6
    FCB $E5,$6D,$A3,$04,$88,$9D,$29,$A8,$B7,$5B,$B2,$73,$24,$49,$04,$69
    FCB $C1,$FE,$E3,$A8,$52,$79,$06,$0D,$B7,$53,$C9,$2C,$2B,$13,$8A,$09
    FCB $C4,$F9,$DC,$8D,$05,$77,$EF,$D5,$6B,$D1,$5A,$09,$8F,$DC,$5B,$96
    FCB $CC,$F3,$8E,$F3,$C9,$5C,$1A,$FB,$DA,$C4,$EC,$B6,$E1,$0C,$FE,$7D
    FCB $FE,$F1,$13,$7F,$7F,$F7,$3A,$42,$D3,$EA,$7F,$FF,$FF,$F7,$DD,$B7
    FCB $FB,$EE,$3C,$6F,$44,$95,$35,$06,$F7,$61,$8B,$00,$F9,$AD,$B4,$69
    FCB $F1,$45,$48,$9A,$6D,$4D,$B5,$97,$6B,$83,$03,$B6,$E5,$2B,$48,$11
    FCB $E2,$6A,$6A,$99,$6E,$3F,$33,$92,$2D,$04,$93,$24,$1F,$CD,$FB,$4D
    FCB $44,$A5,$A9,$B6,$29,$BC,$9D,$C0,$48,$52,$73,$07,$C7,$CC,$68,$37
    FCB $6A,$2C,$FF,$BB,$B4,$48,$CC,$6D,$06,$52,$C7,$28,$25,$AE,$7B,$1F
    FCB $FC,$AE,$B3,$F4,$4B,$5A,$E9,$DC,$6A,$60,$EB,$5E,$78,$E7,$DF,$FC
    FCB $44,$D0,$F9,$FE,$E7,$13,$0D,$62,$9C,$FF,$FF,$FE,$FB,$B6,$FF,$7F
    FCB $DD,$DE,$82,$3A,$79,$0A,$8B,$71,$C5,$8B,$5C,$D8,$3D,$24,$12,$4C
    FCB $45,$0D,$A2,$52,$78,$6A,$B0,$B1,$A4,$E3,$05,$F6,$DC,$69,$8B,$01
    FCB $18,$CA,$66,$A5,$24,$DD,$8A,$F5,$E6,$CC,$16,$82,$D3,$98,$8F,$E6
    FCB $F7,$53,$53,$5A,$08,$9E,$DA,$AC,$CF,$82,$EA,$4C,$88,$CF,$2F,$98
    FCB $D4,$D4,$37,$7F,$9B,$DE,$FF,$B4,$D4,$A6,$1B,$2F,$4A,$16,$FC,$BE
    FCB $65,$CF,$96,$2E,$9B,$DE,$C5,$83,$E0,$5F,$61,$F7,$F1,$06,$A7,$CF
    FCB $F7,$B3,$46,$8C,$1A,$BF,$FF,$FF,$FE,$ED,$4F,$BB,$CE,$FE,$DE,$89
    FCB $1D,$3C,$AE,$D5,$80,$00,$1D,$C7,$5A,$48,$27,$06,$82,$DB,$41,$04
    FCB $D1,$AA,$D6,$3E,$B7,$C1,$71,$B6,$A8,$27,$F9,$46,$B5,$2C,$44,$9D
    FCB $A0,$93,$6D,$AD,$F9,$9B,$C8,$B5,$09,$CB,$83,$F9,$B8,$DA,$B6,$36
    FCB $89,$07,$6D,$B1,$B3,$F1,$7A,$61,$39,$CD,$C6,$F0,$C6,$D0,$EE,$F6
    FCB $F0,$B7,$BF,$EB,$B5,$47,$D6,$FC,$B2,$7E,$E7,$E3,$2D,$FC,$F5,$88
    FCB $3A,$DD,$B5,$99,$52,$96,$B5,$8D,$E4,$FD,$F8,$DA,$90,$FF,$9B,$8C
    FCB $D3,$EB,$05,$3F,$FF,$FF,$FD,$DE,$DB,$DF,$FB,$C7,$B7,$A2,$47,$4F
    FCB $2B,$A9,$C2,$04,$58,$33,$B1,$38,$5A,$01,$68,$16,$82,$08,$96,$D5
    FCB $67,$50,$B8,$E0,$76,$DC,$49,$2B,$94,$6B,$6B,$29,$9A,$09,$20,$DC
    FCB $7B,$AE,$7E,$62,$A9,$91,$18,$3F,$FB,$5B,$6A,$D9,$75,$28,$44,$A6
    FCB $80,$FB,$F0,$B4,$69,$C8,$9E,$3E,$71,$B4,$3B,$7D,$BC,$3B,$BB,$CC
    FCB $6D,$E3,$85,$CF,$92,$D9,$73,$E7,$F2,$EE,$38,$22,$8B,$6D,$42,$F2
    FCB $D5,$05,$C6,$5A,$EE,$67,$79,$52,$28,$FF,$EE,$32,$23,$01,$5F,$FF
    FCB $FF,$FF,$B7,$52,$B7,$F6,$72,$AD,$F4,$48,$DA,$6A,$9E,$DC,$20,$02
    FCB $E3,$8C,$A6,$16,$20,$6D,$05,$E8,$90,$4D,$5B,$6D,$AF,$A8,$5C,$70
    FCB $3B,$7D,$30,$55,$29,$24,$D2,$28,$90,$49,$3B,$55,$8F,$B2,$66,$E4
    FCB $55,$24,$E6,$07,$FF,$52,$DA,$BF,$E8,$24,$D1,$22,$40,$53,$DF,$85
    FCB $AD,$39,$14,$BE,$CC,$E3,$6A,$6E,$F8,$DA,$80,$BD,$BD,$42,$F1,$8A
    FCB $7F,$33,$FC,$CB,$CF,$3D,$26,$1B,$DF,$1A,$7A,$0D,$B5,$90,$68,$56
    FCB $EB,$6C,$E6,$0A,$AE,$0F,$B5,$29,$E7,$FB,$1B,$5A,$49,$F6,$CB,$FF
    FCB $FF,$FF,$EF,$6E,$DD,$CD,$FB,$FD,$5D,$04,$74,$F2,$94,$F7,$17,$16
    FCB $6B,$8C,$5A,$A9,$85,$96,$CD,$01,$D1,$20,$9A,$93,$6D,$AD,$EA,$12
    FCB $ED,$73,$B7,$A4,$8D,$8A,$22,$D2,$68,$CD,$12,$D3,$A4,$56,$5E,$C9
    FCB $9B,$91,$42,$D3,$98,$1F,$DF,$41,$77,$FF,$52,$EA,$44,$8B,$53,$EA
    FCB $70,$C4,$E5,$A7,$FE,$D7,$F9,$A0,$DD,$5E,$DA,$08,$FB,$2D,$CB,$5E
    FCB $56,$8A,$5C,$B5,$43,$D8,$4B,$66,$A5,$24,$06,$24,$D6,$5C,$B7,$2A
    FCB $4E,$85,$B7,$AF,$2A,$74,$9D,$FB,$5D,$B0,$64,$96,$B5,$5D,$59,$F6
    FCB $F9,$49,$3E,$29,$9F,$FF,$FF,$FF,$7B,$76,$DE,$5B,$FB,$CD,$5D,$04
    FCB $A9,$DA,$9F,$E2,$D6,$19,$1A,$D2,$41,$3E,$96,$DF,$6A,$2D,$04,$13
    FCB $C9,$36,$DA,$FB,$A5,$D8,$05,$D0,$74,$FA,$E9,$2B,$16,$B6,$92,$C6
    FCB $82,$4A,$4C,$DB,$EF,$5D,$93,$B9,$60,$9C,$B0,$57,$FD,$47,$C7,$7A
    FCB $97,$68,$26,$DA,$94,$FB,$9B,$5A,$64,$4C,$1D,$D6,$7D,$BA,$AA,$1B
    FCB $DB,$70,$FB,$E3,$32,$B4,$5B,$BE,$D7,$3B,$39,$D1,$74,$8C,$C4,$AB
    FCB $2F,$FA,$D4,$99,$8B,$52,$9A,$CB,$8D,$AC,$D5,$0B,$2A,$73,$67,$58
    FCB $A2,$EF,$FF,$88,$EB,$5B,$6C,$FF,$FF,$FF,$FE,$EE,$A5,$77,$FF,$77
    FCB $1A,$F4,$16,$A4,$F2,$9F,$91,$6B,$32,$35,$A6,$16,$A5,$FB,$ED,$0D
    FCB $A0,$A4,$D4,$6A,$6D,$96,$B5,$52,$EC,$25,$D5,$A6,$06,$B5,$10,$5A
    FCB $96,$8C,$A9,$26,$9A,$9D,$D8,$EE,$B6,$CE,$16,$5C,$4E,$64,$85,$7F
    FCB $E7,$A8,$7B,$BF,$44,$C4,$D5,$29,$EC,$EC,$4C,$89,$CF,$EC,$0F,$BE
    FCB $D0,$A1,$D0,$D2,$F7,$66,$39,$02,$85,$BA,$A8,$FB,$37,$F5,$E9,$E2
    FCB $D3,$FE,$6B,$5D,$67,$EC,$8A,$4C,$B4,$9B,$64,$7B,$AD,$5A,$96,$10
    FCB $6A,$ED,$85,$D6,$30,$B6,$FE,$3B,$A3,$5A,$D6,$2A,$FF,$FF,$FF,$FF
    FCB $77,$76,$AF,$EF,$EC,$54,$CA,$0B,$52,$79,$4F,$24,$5A,$E3,$5B,$12
    FCB $4F,$83,$FB,$DD,$0B,$A0,$A4,$D4,$FA,$9B,$63,$6B,$53,$4A,$59,$96
    FCB $3D,$3E,$35,$A8,$AE,$B6,$92,$45,$43,$A6,$68,$34,$9D,$D6,$AF,$87
    FCB $B8,$98,$4E,$05,$70,$BB,$1B,$B6,$CF,$F7,$B2,$89,$12,$1B,$CB,$13
    FCB $99,$3E,$6A,$AE,$7D,$FA,$14,$1E,$80,$2F,$1B,$EF,$9C,$49,$05,$17
    FCB $73,$19,$FE,$34,$ED,$24,$FD,$FD,$7A,$3C,$3F,$E2,$93,$38,$3C,$6E
    FCB $E5,$5D,$6C,$D6,$D4,$F7,$09,$58,$A3,$D4,$7D,$5A,$D1,$D6,$B7,$7F
    FCB $FF,$FF,$FF,$DD,$DD,$AB,$9B,$78,$35,$A9,$B9,$D0,$10,$4D,$54,$5F
    FCB $5E,$11,$6D,$3E,$96,$7E,$F7,$42,$EA,$41,$35,$1B,$55,$47,$B4,$BE
    FCB $47,$15,$11,$8D,$6A,$2B,$AD,$A7,$C2,$C7,$41,$3A,$52,$D5,$B1,$F8
    FCB $1D,$B8,$9F,$4E,$16,$A2,$31,$E8,$5B,$9F,$FB,$A9,$72,$E8,$44,$21
    FCB $69,$27,$CE,$C3,$FF,$DD,$48,$08,$6C,$CF,$B8,$5A,$F4,$90,$56,$EE
    FCB $BE,$E7,$FA,$74,$92,$33,$FA,$E2,$44,$FF,$C5,$26,$64,$6E,$37,$22
    FCB $9D,$AC,$6B,$96,$D5,$72,$62,$EA,$05,$2C,$56,$FB,$AD,$2D,$6B,$51
    FCB $FF,$FF,$FF,$FE,$EF,$6D,$5F,$1D,$CA,$DB,$6D,$9B,$52,$D4,$9E,$70
    FCB $C5,$94,$C3,$11,$9F,$FD,$BD,$B7,$8A,$44,$9E,$4F,$B5,$54,$3C,$69
    FCB $5E,$05,$EA,$AD,$1E,$B4,$45,$26,$BA,$7C,$32,$E9,$DA,$0B,$4D,$76
    FCB $B7,$67,$3B,$C4,$69,$91,$6A,$CD,$DA,$B7,$FF,$DE,$DE,$32,$2D,$C1
    FCB $C2,$6A,$59,$FF,$FA,$90,$A0,$5E,$7E,$E1,$12,$E8,$2B,$7C,$DE,$77
    FCB $54,$52,$33,$EF,$5B,$46,$B3,$FF,$C4,$13,$A1,$DC,$DE,$37,$CD,$71
    FCB $B6,$EF,$5F,$58,$D0,$0C,$37,$DD,$1D,$B1,$79,$3F,$FF,$FF,$FE,$EE
    FCB $ED,$F6,$6E,$6B,$53,$BF,$A8,$52,$6B,$83,$16,$98,$1A,$5D,$67,$B8
    FCB $F6,$DF,$77,$68,$93,$53,$ED,$56,$37,$D2,$6F,$25,$C5,$09,$2F,$49
    FCB $34,$12,$60,$92,$CF,$D4,$A4,$93,$A5,$2A,$37,$64,$CB,$71,$24,$E6
    FCB $5A,$19,$BA,$9E,$FF,$FF,$79,$FF,$80,$17,$AF,$FF,$97,$41,$4D,$EF
    FCB $E7,$70,$A4,$74,$15,$BF,$B9,$CD,$9F,$CD,$4E,$B4,$69,$4F,$FF,$A9
    FCB $3A,$F6,$5C,$2F,$6C,$86,$DA,$BC,$5B,$D6,$20,$F1,$AF,$34,$8E,$D5
    FCB $0C,$87,$FF,$FF,$F8,$F7,$77,$6F,$B0,$71,$2B,$6A,$7F,$D4,$34,$D6
    FCB $15,$AD,$3F,$3E,$72,$CB,$DB,$7D,$B6,$C4,$49,$A9,$F6,$80,$A2,$F1
    FCB $26,$DC,$8E,$54,$23,$34,$93,$45,$AD,$82,$49,$7F,$6A,$5A,$09,$D2
    FCB $A7,$70,$CA,$9C,$46,$99,$16,$84,$ED,$A8,$77,$B3,$FF,$7F,$FF,$17
    FCB $AE,$E2,$FF,$1E,$6E,$A6,$87,$7C,$DF,$AE,$B4,$9D,$D1,$3D,$B3,$E7
    FCB $FF,$FF,$2B,$48,$E7,$FF,$41,$3A,$F0,$70,$B6,$C6,$CA,$DE,$DB,$CA
    FCB $E5,$8D,$5E,$0E,$14,$66,$D4,$E7,$82,$FF,$FF,$1F,$F8,$F6,$ED,$DF
    FCB $70,$D2,$DA,$9B,$FE,$CA,$A9,$FC,$1B,$3F,$9E,$5E,$D5,$BD,$F4,$D4
    FCB $F2,$61,$AA,$A2,$E5,$2B,$7F,$89,$2A,$BC,$46,$8A,$B3,$11,$AF,$FD
    FCB $4B,$69,$A9,$E5,$06,$D8,$C8,$DE,$23,$4E,$61,$09,$DA,$9F,$7F,$FF
    FCB $BF,$D9,$1C,$7E,$0B,$58,$7F,$73,$75,$50,$7B,$FE,$DA,$EB,$12,$96
    FCB $D1,$5D,$C6,$6C,$FF,$F9,$FD,$24,$8F,$FF,$C5,$27,$4C,$B8,$E5,$B5
    FCB $4C,$07,$B5,$78,$07,$53,$F3,$85,$69,$46,$86,$3F,$16,$7F,$FC,$F7
    FCB $FE,$AD,$DD,$EE,$14,$BB,$53,$BF,$1B,$34,$61,$B7,$F8,$59,$BE,$ED
    FCB $EF,$F4,$49,$E4,$FA,$95,$51,$65,$A3,$62,$B6,$41,$1A,$B9,$46,$9B
    FCB $48,$71,$3E,$71,$50,$65,$A7,$69,$B5,$BB,$63,$3B,$C4,$FA,$64,$10
    FCB $9D,$A0,$CD,$FF,$FF,$7F,$84,$76,$C7,$2B,$AD,$73,$EE,$7A,$9B,$43
    FCB $7F,$1C,$C4,$97,$DB,$41,$BB,$3F,$F9,$70,$FC,$B1,$AD,$23,$FF,$F1
    FCB $49,$99,$1B,$7F,$6E,$62,$DB,$DB,$F5,$D7,$D4,$FF,$32,$B6,$96,$29
    FCB $86,$F1,$67,$F9,$FE,$D9,$FD,$DD,$8D,$B7,$82,$5D,$B5,$3B,$1C,$B6
    FCB $BA,$49,$4A,$9F,$F5,$11,$7F,$DA,$9E,$F7,$62,$93,$C9,$84,$14,$D8
    FCB $D4,$0D,$1B,$14,$ED,$71,$3F,$57,$D1,$A6,$AD,$63,$89,$F2,$AD,$EB
    FCB $6B,$2D,$3A,$AD,$13,$A8,$73,$78,$98,$4E,$71,$03,$75,$2B,$FF,$FF
    FCB $FB,$1F,$5B,$FF,$98,$40,$F9,$DB,$A0,$EA,$EE,$61,$12,$19,$6D,$07
    FCB $BB,$9F,$2F,$7A,$FF,$1D,$75,$AC,$FF,$FC,$52,$67,$2E,$CB,$DE,$5A
    FCB $C5,$3D,$E6,$B8,$A8,$EF,$65,$6A,$D7,$31,$BA,$F4,$94,$EB,$5C,$FF
    FCB $CD,$EC,$1E,$3D,$DD,$FB,$A5,$AD,$5B,$6A,$76,$7D,$8B,$48,$51,$B3
    FCB $D4,$32,$BF,$F6,$A7,$BE,$F6,$9E,$4F,$A0,$DB,$1A,$A3,$46,$C5,$3A
    FCB $96,$23,$2F,$E8,$D3,$52,$5D,$D6,$98,$A9,$8D,$80,$C3,$6A,$13,$34
    FCB $1B,$58,$E5,$B8,$9C,$27,$02,$8B,$75,$3F,$FF,$FF,$96,$3B,$9F,$FF
    FCB $EB,$5A,$FC,$F7,$6D,$0B,$EF,$82,$EB,$28,$25,$55,$4D,$DD,$9F,$F1
    FCB $FF,$2B,$75,$AE,$1F,$FF,$C5,$26,$66,$DF,$71,$C2,$D6,$DA,$8F,$5B
    FCB $23,$76,$FE,$2C,$43,$59,$7A,$9A,$D2,$AD,$6A,$70,$99,$FC,$BF,$9F
    FCB $77,$B6,$FD,$25,$95,$6D,$B5,$76,$DB,$5E,$B4,$63,$65,$ED,$A9,$B6
    FCB $B5,$AD,$2F,$F6,$A7,$BE,$FA,$6A,$34,$1A,$9E,$AC,$49,$94,$35,$A4
    FCB $BD,$4F,$29,$F4,$49,$0C,$62,$7D,$AB,$E1,$0E,$C6,$99,$A2,$61,$7B
    FCB $65,$39,$93,$E2,$8D,$43,$57,$6C,$FF,$FF,$B3,$D9,$FF,$F8,$B1,$71
    FCB $E7,$7D,$0A,$95,$6A,$8B,$16,$B9,$68,$25,$62,$0F,$B9,$BF,$FC,$FB
    FCB $5C,$4B,$0F,$FF,$F5,$27,$5B,$CB,$67,$06,$EE,$FC,$31,$DE,$F5,$E0
    FCB $DE,$BB,$54,$75,$A5,$8D,$D6,$B9,$FF,$E7,$F7,$EF,$B5,$71,$21,$9B
    FCB $B6,$DB,$F7,$11,$C2,$DB,$6E,$D5,$6F,$AD,$69,$FF,$FA,$9B,$B8,$DF
    FCB $4D,$4F,$A0,$D5,$74,$20,$93,$0E,$B8,$ED,$F5,$A3,$44,$B1,$A4,$C4
    FCB $90,$9F,$32,$36,$5A,$74,$9E,$0B,$FD,$39,$69,$8A,$B6,$A1,$BB,$1B
    FCB $3F,$FF,$FF,$FF,$FD,$C9,$02,$13,$F7,$52,$0D,$BD,$62,$45,$6D,$10
    FCB $95,$54,$2E,$DC,$FF,$E3,$0F,$65,$20,$9F,$FF,$E2,$93,$AB,$3B,$77
    FCB $D7,$B7,$7E,$1F,$7D,$D6,$65,$4B,$ED,$AB,$89,$02,$DF,$0C,$FF,$F3
    FCB $FE,$F7,$B5,$1A,$4B,$53,$3D,$4D,$DE,$CD,$18,$45,$36,$D9,$BB,$41
    FCB $B5,$AD,$6B,$5F,$FA,$9B,$BD,$BD,$A2,$4F,$B5,$2B,$A1,$05,$C3,$FE
    FCB $FA,$49,$20,$69,$F6,$36,$7F,$D7,$31,$D4,$9D,$31,$35,$F7,$69,$C9
    FCB $A9,$F5,$BD,$0D,$B7,$1B,$9F,$67,$FE,$CF,$FF,$F7,$0F,$49,$AE,$0F
    FCB $3D,$48,$21,$C1,$6B,$55,$88,$23,$35,$29,$ED,$9F,$DE,$79,$F2,$D4
    FCB $4A,$D2,$33,$FE,$29,$3A,$BF,$BF,$2F,$F6,$E1,$83,$6E,$EB,$0C,$51
    FCB $8E,$A7,$74,$96,$AA,$D9,$03,$27,$FE,$7F,$D8,$DE,$DA,$3C,$53,$0B
    FCB $D4,$DD,$EC,$A3,$5D,$76,$DB,$53,$2F,$6E,$82,$D6,$B5,$9F,$EA,$6E
    FCB $F7,$B1,$04,$6D,$13,$6C,$54,$AE,$03,$FE,$E5,$24,$90,$18,$8D,$8A
    FCB $26,$FE,$06,$31,$A9,$89,$9A,$6B,$8E,$A4,$E4,$11,$8F,$43,$53,$71
    FCB $E7,$FF,$F7,$F1,$9F,$FB,$9D,$92,$B4,$BE,$71,$4D,$37,$62,$D2,$F4
    FCB $42,$3D,$B4,$1E,$FF,$DE,$1F,$7F,$42,$87,$69,$35,$D6,$98,$59,$EC
    FCB $62,$93,$BB,$BD,$CB,$F0,$7D,$B0,$FD,$BC,$58,$6F,$83,$53,$B6,$B5
    FCB $B6,$16,$10,$6B,$87,$FC,$FF,$7D,$E0,$16,$AF,$EA,$6D,$F6,$23,$5D
    FCB $AE,$AD,$A9,$8D,$F2,$EB,$03,$FD,$B7,$76,$C7,$A0,$8E,$89,$56,$21
    FCB $05,$B8,$39,$F5,$45,$AD,$6A,$B4,$BC,$31,$FE,$B9,$F6,$D6,$A4,$CD
    FCB $3D,$1E,$9C,$82,$C7,$6A,$D4,$FB,$E7,$FF,$EF,$E2,$83,$EE,$7D,$E7
    FCB $5A,$D7,$E7,$A9,$A0,$A2,$B4,$71,$56,$89,$1A,$DD,$D0,$BB,$8F,$B9
    FCB $98,$AD,$FC,$9D,$8A,$42,$B5,$A7,$D6,$77,$8A,$4E,$87,$B6,$6C,$B2
    FCB $5E,$36,$7E,$D9,$6B,$0F,$76,$0D,$EE,$B1,$58,$E1,$92,$B5,$FE,$38
    FCB $FD,$9F,$E0,$F7,$FD,$AB,$B1,$1B,$AE,$D9,$7D,$4D,$B6,$67,$58,$CF
    FCB $3B,$76,$ED,$FA,$09,$54,$83,$6B,$53,$5D,$79,$CD,$82,$11,$1C,$55
    FCB $A3,$55,$B5,$AF,$5B,$2F,$AC,$7C,$D8,$DA,$66,$9E,$31,$39,$30,$BB
    FCB $52,$EA,$57,$2F,$1F,$FF,$BF,$D9,$CD,$CF,$B6,$7A,$E9,$2D,$C9,$DB
    FCB $52,$09,$45,$C7,$A9,$2B,$A9,$AA,$EF,$CB,$23,$1E,$85,$A4,$5F,$F3
    FCB $1D,$75,$AF,$ED,$8A,$4D,$7E,$CD,$EC,$78,$CD,$9F,$A8,$5F,$0E,$DE
    FCB $0A,$C7,$5A,$9B,$B2,$10,$68,$DA,$D6,$FF,$FC,$7F,$FF,$FF,$DA,$0A
    FCB $82,$30,$DB,$67,$B5,$2A,$D9,$07,$87,$0C,$DB,$B7,$6D,$85,$4B,$55
    FCB $13,$52,$4D,$82,$DC,$7A,$F6,$08,$A9,$2E,$29,$A4,$DC,$A3,$FE,$E4
    FCB $A2,$D2,$4B,$EE,$9D,$69,$DD,$39,$03,$6D,$EA,$AA,$75,$2F,$7F,$FE
    FCB $CF,$F9,$76,$4C,$6F,$EB,$89,$2A,$2C,$F6,$D4,$97,$9B,$EE,$D4,$D4
    FCB $85,$A3,$FF,$C6,$4B,$FF,$E3,$C9,$02,$6C,$14,$9D,$BB,$E6,$EC,$EF
    FCB $30,$79,$6D,$63,$55,$77,$1D,$F7,$09,$55,$8C,$D6,$C1,$A4,$2D,$6A
    FCB $FE,$3F,$FD,$D4,$E4,$0B,$CE,$A6,$A8,$8C,$AE,$DB,$FD,$A9,$DF,$7F
    FCB $5F,$AE,$4B,$7A,$9B,$73,$6B,$D1,$34,$12,$53,$05,$FF,$B2,$B4,$04
    FCB $7D,$55,$A8,$89,$0F,$FC,$71,$EC,$59,$FE,$89,$A7,$CB,$A9,$ED,$FF
    FCB $FF,$BF,$97,$2F,$E5,$FF,$2F,$E6,$BD,$6B,$3E,$D9,$CF,$EC,$52,$95
    FCB $53,$69,$6F,$F8,$C9,$7F,$FF,$F3,$65,$6B,$31,$49,$D5,$DB,$38,$7B
    FCB $E7,$EE,$E4,$C1,$B0,$BB,$7C,$EF,$76,$45,$C1,$49,$0B,$5A,$BF,$FF
    FCB $BE,$5A,$B3,$DD,$D7,$B9,$5B,$02,$DF,$F6,$A7,$77,$67,$E6,$2E,$DA
    FCB $5E,$DB,$57,$B5,$EA,$41,$04,$9B,$2B,$FE,$E0,$B4,$12,$3A,$96,$C5
    FCB $CF,$FF,$6F,$EC,$47,$3F,$E5,$D4,$F7,$FD,$FF,$DD,$9E,$CF,$F1,$8F
    FCB $73,$8A,$5F,$CA,$55,$E7,$BF,$E7,$62,$AA,$6A,$FC,$60,$E0,$DB,$3B
    FCB $FF,$FF,$9A,$B8,$B5,$85,$33,$B2,$FD,$9E,$3F,$64,$6E,$C2,$65,$C1
    FCB $EE,$F1,$CD,$DB,$05,$91,$8D,$85,$2B,$0F,$FD,$4C,$ED,$53,$07,$6E
    FCB $6E,$B2,$2F,$DE,$E3,$B6,$AB,$F6,$7C,$E6,$D6,$1B,$6D,$43,$D9,$D4
    FCB $A4,$68,$BA,$FD,$BE,$24,$B4,$49,$7B,$8B,$CF,$FF,$6C,$ED,$AD,$28
    FCB $3F,$3F,$53,$D5,$FE,$FF,$FB,$D8,$CF,$F3,$7B,$9F,$F0,$CA,$D7,$3D
    FCB $F6,$E6,$62,$85,$34,$37,$02,$2D,$AE,$DA,$9C,$77,$FF,$FF,$EC,$8C
    FCB $AC,$A7,$76,$7E,$FE,$71,$B7,$FC,$0E,$EC,$EE,$C9,$66,$F6,$C5,$AF
    FCB $35,$30,$11,$B8,$3F,$F1,$4A,$64,$F7,$ED,$C1,$DD,$82,$4B,$95,$59
    FCB $DB,$B5,$5F,$FF,$9F,$C2,$5B,$6F,$D7,$AE,$82,$49,$DB,$2B,$6E,$EF
    FCB $AD,$1A,$D0,$2D,$2B,$6B,$E7,$FF,$1B,$12,$D4,$A5,$AF,$3F,$F7,$6A
    FCB $DB,$6B,$DE,$DC,$3D,$A0,$B6,$65,$46,$79,$BD,$9F,$FC,$7D,$24,$83
    FCB $7B,$71,$B4,$8D,$05,$8C,$6D,$08,$C5,$C9,$52,$DA,$9A,$B9,$6E,$CF
    FCB $FF,$FF,$F0,$4D,$FF,$BF,$2F,$C1,$F6,$C3,$97,$8E,$F9,$1F,$78,$DA
    FCB $D6,$3E,$D4,$0B,$5A,$D5,$0F,$6E,$5B,$70,$DE,$F1,$B7,$37,$B5,$89
    FCB $24,$D7,$53,$9D,$BA,$95,$7F,$FF,$E3,$22,$D8,$36,$A7,$EB,$88,$DA
    FCB $0B,$4F,$20,$32,$EF,$C4,$6B,$5A,$85,$2D,$77,$F7,$1E,$77,$ED,$1C
    FCB $2F,$9F,$FB,$B5,$6D,$A0,$8F,$ED,$E7,$D8,$82,$57,$AB,$96,$B9,$BE
    FCB $39,$A9,$7F,$77,$58,$9F,$3E,$E5,$4A,$58,$EA,$58,$6D,$10,$97,$8F
    FCB $D4,$E8,$7E,$3F,$FF,$F6,$7F,$60,$8B,$F9,$7B,$3F,$DD,$8F,$5F,$8F
    FCB $DB,$E1,$FB,$83,$6B,$38,$DB,$02,$BC,$3D,$4A,$2C,$E3,$37,$BD,$BB
    FCB $39,$6B,$11,$EB,$A9,$C7,$BB,$6A,$BF,$FF,$FC,$8B,$60,$DA,$9F,$AE
    FCB $92,$EA,$5A,$09,$EB,$DD,$EE,$9F,$5C,$65,$71,$CB,$B8,$F3,$BF,$68
    FCB $E1,$FF,$FE,$F4,$37,$F7,$DE,$6F,$D4,$BF,$A1,$82,$08,$FB,$C3,$1B
    FCB $CF,$6F,$94,$69,$67,$51,$AB,$7A,$CF,$53,$4B,$3E,$EA,$74,$3F,$1F
    FCB $FF,$FF,$DF,$8B,$44,$F7,$99,$7D,$B3,$C6,$32,$E5,$FD,$87,$B7,$FE
    FCB $2F,$37,$1B,$C0,$AD,$81,$8A,$55,$83,$7D,$86,$D9,$77,$83,$D8,$8D
    FCB $76,$BB,$71,$DE,$A6,$AE,$FC,$F6,$7F,$84,$8D,$57,$6B,$49,$2D,$45
    FCB $3C,$A7,$14,$FA,$93,$E9,$66,$11,$47,$D8,$F8,$EE,$5D,$1C,$3F,$FF
    FCB $2D,$D4,$EF,$EF,$FF,$DD,$9B,$1F,$41,$1B,$C1,$F6,$6E,$1B,$D9,$E0
    FCB $8D,$D6,$6F,$A0,$D7,$90,$DE,$7D,$9B,$6D,$A1,$FF,$DF,$CB,$9F,$EE
    FCB $56,$26,$B8,$A7,$5D,$CD,$FC,$FB,$2F,$E6,$F8,$C7,$FD,$EB,$31,$DE
    FCB $F8,$5D,$2A,$CD,$6D,$07,$2D,$EE,$2E,$DB,$5D,$F7,$E3,$5A,$7F,$52
    FCB $EF,$1D,$ED,$A9,$B3,$F3,$7F,$E4,$E0,$D4,$EB,$6B,$48,$D9,$52,$6A
    FCB $9D,$BA,$7E,$D7,$C7,$09,$8F,$71,$E7,$7B,$D1,$C3,$FF,$F2,$D8,$82
    FCB $AE,$77,$F3,$7F,$EE,$CE,$CE,$5C,$F6,$75,$06,$E7,$D2,$2B,$39,$77
    FCB $75,$34,$67,$FE,$E6,$DB,$68,$59,$FF,$FF,$67,$F7,$B0,$5A,$6F,$78
    FCB $F9,$73,$EF,$9B,$E6,$EC,$8F,$99,$6D,$D6,$7D,$B0,$EF,$71,$6C,$4B
    FCB $B5,$1F,$BC,$2A,$6D,$7F,$65,$D3,$EC,$49,$B6,$BB,$96,$DF,$6D,$BF
    FCB $FC,$BF,$F9,$F6,$C4,$75,$CD,$EA,$4D,$6E,$E9,$2F,$2E,$38,$47,$2F
    FCB $F9,$DF,$74,$70,$FF,$FC,$BD,$05,$5C,$EF,$FD,$B8,$7B,$B3,$8F,$9F
    FCB $EC,$EA,$96,$33,$35,$AE,$B3,$F6,$A5,$60,$BE,$D7,$FB,$9A,$AD,$A1
    FCB $73,$FE,$E7,$B3,$FB,$EC,$5A,$2C,$77,$9E,$F7,$F2,$7E,$3E,$F1,$FB
    FCB $97,$C2,$76,$D8,$16,$DB,$82,$55,$AD,$F6,$3F,$DB,$2D,$FF,$73,$5A
    FCB $62,$5A,$99,$CB,$6F,$B6,$DB,$3F,$E5,$F1,$F2,$C8,$E9,$12,$7D,$49
    FCB $A6,$6B,$7D,$C7,$0D,$CF,$BE,$6F,$B1,$A3,$84,$7F,$FC,$BD,$48,$5C
    FCB $BB,$3F,$DE,$6F,$E7,$7C,$FF,$7F,$9F,$DC,$A5,$48,$B3,$6A,$56,$D2
    FCB $39,$3F,$52,$ED,$AA,$85,$55,$FF,$F6,$CC,$FF,$DF,$62,$D1,$47,$F1
    FCB $F7,$3E,$E7,$BF,$9B,$FC,$37,$1B,$27,$AA,$C8,$D8,$C8,$B3,$5D,$FF
    FCB $ED,$A9,$75,$1C,$F7,$88,$D2,$95,$36,$72,$DB,$1B,$6E,$EE,$C2,$E0
    FCB $FE,$33,$63,$2B,$6B,$59,$FE,$DB,$56,$BB,$1F,$73,$85,$53,$DD,$E7
    FCB $79,$A3,$98,$FF,$F9,$7B,$42,$D8,$CB,$FF,$FE,$F9,$76,$31,$D7,$15
    FCB $3E,$D8,$C7,$0B,$2F,$AE,$92,$4D,$98,$FB,$F8,$7F,$51,$75,$55,$52
    FCB $96,$6F,$E5,$A0,$69,$7F,$67,$B1,$62,$6F,$57,$25,$F6,$CF,$F8,$76
    FCB $E5,$85,$9B,$BC,$B0,$BD,$F0,$78,$DD,$6B,$75,$A5,$F1,$4E,$3A,$94
    FCB $A3,$97,$E3,$2B,$46,$03,$55,$99,$B6,$C6,$DB,$BF,$C7,$8F,$C7,$FF
    FCB $04,$8F,$E0,$AB,$ED,$D6,$AF,$63,$8B,$DC,$BE,$DE,$7F,$89,$4C,$7E
    FCB $77,$37,$B4,$2A,$FF,$FF,$DE,$EC,$2F,$18,$EB,$DB,$24,$B7,$DC,$8C
    FCB $2F,$1A,$D1,$D9,$FD,$5F,$59,$7B,$2C,$DA,$9E,$AF,$F4,$48,$44,$92
    FCB $41,$2A,$8F,$36,$5F,$8B,$44,$F7,$96,$7F,$1C,$71,$B2,$C7,$C7,$9B
    FCB $2F,$CD,$97,$3D,$F3,$62,$CC,$16,$6C,$1D,$8A,$44,$AB,$39,$7C,$1A
    FCB $E9,$2C,$5D,$4D,$F9,$6D,$C6,$DB,$7F,$37,$E3,$FF,$F9,$5A,$5F,$A8
    FCB $37,$D5,$05,$46,$E3,$8B,$DC,$BF,$6C,$3E,$62,$4F,$9D,$CE,$F3,$DA
    FCB $AA,$BF,$FB,$FF,$7B,$37,$FC,$DF,$38,$7B,$7D,$CF,$AD,$19,$FF,$76
    FCB $C8,$BB,$F3,$B6,$D5,$AB,$FB,$57,$35,$DD,$9E,$CF,$EB,$5A,$6F,$7F
    FCB $C7,$FC,$6E,$C8,$6F,$C7,$FD,$B1,$87,$B9,$D8,$E3,$AE,$16,$D6,$B1
    FCB $7A,$9A,$C5,$26,$8D,$F2,$F1,$F5,$8C,$5A,$56,$0D,$BE,$7B,$62,$AD
    FCB $BC,$F7,$B9,$CD,$FF,$91,$23,$8D,$00,$5B,$7D,$49,$3A,$A5,$5A,$8A
    FCB $E7,$F8,$A7,$9B,$AF,$48,$F3,$B9,$D8,$CF,$A2,$AB,$FF,$BF,$F5,$2E
    FCB $F7,$FB,$8E,$BF,$FC,$B9,$A9,$5A,$45,$C5,$A5,$36,$5E,$E6,$4F,$FB
    FCB $6D,$5A,$BF,$D9,$75,$2F,$B1,$9F,$FE,$B5,$A6,$F5,$65,$F9,$2E,$76
    FCB $6D,$D9,$3B,$CC,$6D,$C9,$DF,$D8,$78,$46,$DC,$22,$CC,$68,$98,$D9
    FCB $BF,$B8,$05,$69,$16,$BA,$AF,$CD,$B6,$2A,$DD,$CF,$63,$78,$C3,$7F
    FCB $E6,$92,$F1,$B8,$0A,$F5,$24,$DA,$A5,$B1,$95,$EF,$FD,$FF,$AD,$D1
    FCB $9D,$9E,$CF,$BE,$68,$54,$FF,$F7,$FF,$DF,$73,$AB,$87,$E6,$CB,$91
    FCB $BB,$3D,$62,$53,$EF,$F9,$9E,$CD,$B6,$AD,$5F,$7F,$1C,$DD,$9F,$FF
    FCB $5A,$D1,$3D,$53,$67,$1B,$67,$FF,$EC,$3D,$E7,$7C,$DF,$38,$DC,$2E
    FCB $6D,$9D,$24,$71,$04,$57,$67,$F2,$C1,$69,$38,$16,$55,$CF,$B6,$C6
    FCB $DB,$FE,$C1,$BB,$18,$6A,$3C,$CB,$11,$E3,$E2,$15,$9E,$DB,$DD,$D8
    FCB $63,$9C,$DE,$FE,$B6,$25,$C6,$7B,$9F,$FD,$55,$20,$7F,$DF,$F6,$7B
    FCB $B0,$E3,$7F,$F3,$B3,$F7,$ED,$75,$B4,$63,$CB,$F9,$8D,$9C,$72,$DB
    FCB $56,$AF,$FE,$E8,$92,$25,$9F,$7B,$E0,$B4,$DF,$97,$6E,$7F,$E3,$FD
    FCB $80,$C7,$73,$FF,$6C,$67,$3F,$79,$BE,$2D,$6C,$A2,$FF,$BC,$08,$B5
    FCB $F3,$14,$37,$CF,$B6,$C7,$77,$EF,$8F,$63,$0A,$83,$B3,$DD,$3F,$0F
    FCB $1B,$7D,$76,$DE,$EF,$01,$8A,$19,$9B,$DF,$75,$D2,$5F,$B9,$EC,$FF
    FCB $DB,$A9,$DF,$8F,$7F,$DF,$3B,$2F,$1B,$27,$EF,$C7,$CB,$D4,$93,$D7
    FCB $5A,$4F,$1F,$63,$6B,$AE,$EF,$3D,$DA,$B5,$7F,$FD,$9B,$B6,$BE,$EF
    FCB $52,$91,$8B,$5A,$2E,$A8,$E1,$78,$DF,$80,$ED,$B3,$70,$73,$FB,$F9
    FCB $C1,$DE,$FF,$D8,$40,$6A,$2C,$7F,$8C,$16,$B5,$FB,$CD,$B1,$F8,$39
    FCB $6D,$8A,$B5,$7F,$C7,$BC,$2A,$5F,$67,$2E,$8F,$5F,$9D,$5B,$05,$3E
    FCB $E3,$87,$7F,$8F,$7B,$75,$AD,$23,$DC,$F6,$7F,$EF,$52,$9F,$E3,$BF
    FCB $FF,$BB,$8F,$2C,$9C,$7F,$7E,$7D,$4B,$7A,$E2,$37,$FD,$D3,$69,$45
    FCB $8F,$2C,$76,$35,$6A,$FF,$EF,$E6,$F6,$55,$83,$8B,$11,$75,$4E,$5F
    FCB $6E,$61,$BE,$3D,$E7,$D9,$BE,$4B,$1D,$FC,$F3,$87,$63,$8F,$79,$16
    FCB $C5,$AF,$BB,$80,$DB,$9B,$FC,$B6,$C6,$DB,$1F,$FB,$71,$40,$32,$F9
    FCB $CB,$A5,$A5,$E6,$3D,$03,$DD,$FA,$EE,$F1,$5A,$36,$A8,$F7,$6B,$49
    FCB $7E,$F3,$D9,$FE,$CE,$A5,$2B,$F1,$DF,$FF,$DF,$1B,$36,$BB,$31,$DE
    FCB $5F,$3F,$B2,$B7,$47,$9F,$41,$05,$71,$25,$9A,$EE,$AA,$96,$D4,$54
    FCB $FC,$FB,$FF,$BC,$A9,$E9,$38,$B5,$A6,$F7,$2F,$C7,$FD,$F8,$5F,$79
    FCB $9D,$8F,$C2,$FB,$C7,$FF,$C9,$DA,$EB,$47,$B7,$27,$FB,$EC,$1A,$89
    FCB $7F,$8E,$A6,$0A,$DB,$FF,$1B,$B6,$03,$B3,$FF,$91,$3F,$E6,$3D,$09
    FCB $DD,$EC,$5D,$EC,$BD,$1B,$43,$DC,$8B,$5F,$FF,$DE,$7D,$9D,$4D,$0F
    FCB $FB,$FF,$E5,$F7,$66,$09,$29,$D8,$EF,$37,$CF,$F8,$E8,$C8,$FD,$48
    FCB $9F,$2B,$59,$58,$E8,$5A,$4D,$5A,$17,$26,$A5,$FF,$6E,$7D,$F2,$C5
    FCB $AD,$37,$1E,$F7,$2E,$7D,$F1,$D9,$E7,$9B,$DC,$FF,$2F,$B9,$F7,$39
    FCB $D2,$AD,$26,$7F,$FF,$DA,$8D,$92,$F3,$78,$A7,$1B,$B7,$F7,$8D,$F0
    FCB $1A,$8F,$F3,$9A,$7F,$CF,$DD,$4B,$77,$6C,$80,$ED,$AD,$04,$70,$68
    FCB $33,$D2,$75,$FF,$FE,$F3,$FF,$74,$5D,$FF,$72,$FF,$B9,$B8,$E0,$B1
    FCB $DB,$BF,$DF,$3F,$E3,$A4,$BD,$94,$1A,$94,$3C,$A8,$58,$B4,$B4,$DD
    FCB $3E,$D5,$A1,$67,$D1,$23,$FF,$BF,$3F,$EB,$5A,$78,$2F,$7B,$96,$7D
    FCB $D9,$BC,$F0,$63,$EE,$7F,$FE,$5F,$E5,$F2,$3F,$5A,$42,$F8,$FF,$1A
    FCB $ED,$BF,$63,$6E,$7F,$BC,$6E,$DB,$9B,$36,$F0,$05,$28,$E3,$1E,$59
    FCB $13,$FE,$7E,$C5,$5C,$AA,$6B,$BF,$A5,$DA,$0C,$EB,$49,$FF,$FF,$FF
    FCB $EC,$DD,$07,$B1,$FF,$DF,$FF,$76,$6B,$81,$BA,$B5,$77,$0B,$F3,$96
    FCB $B4,$BD,$A1,$6C,$B6,$EE,$EB,$49,$25,$20,$51,$DB,$AB,$FD,$04,$BF
    FCB $F9,$BF,$FA,$D6,$9E,$0B,$BC,$7D,$9F,$DD,$9F,$91,$C7,$B0,$77,$F3
    FCB $FF,$F3,$C6,$FE,$C5,$AD,$25,$9F,$FB,$65,$FF,$BE,$3B,$CD,$B9,$55
    FCB $B7,$D8,$7B,$B2,$0D,$FC,$FB,$22,$33,$9C,$DE,$F8,$A5,$68,$27,$0D
    FCB $E3,$59,$DA,$2F,$5A,$CF,$FF,$FF,$FE,$CD,$55,$2B,$8E,$77,$DF,$FF
    FCB $7F,$5C,$6B,$8D,$6D,$D4,$FF,$AB,$0F,$EB,$5E,$54,$AA,$9B,$3B,$2A
    FCB $6B,$2A,$0A,$7D,$DD,$5F,$DA,$92,$F6,$7C,$EF,$C7,$8B,$4D,$05,$7C
    FCB $DE,$3E,$CD,$CF,$73,$1B,$E1,$77,$E1,$8D,$FF,$9F,$79,$B8,$C1,$24
    FCB $BF,$6B,$2A,$FF,$FB,$C7,$F3,$53,$95,$5B,$67,$37,$EF,$9F,$FF,$78
    FCB $8D,$7C,$9E,$FE,$F5,$74,$BE,$7D,$A2,$EB,$59,$FF,$FF,$FF,$F6,$5D
    FCB $A9,$D9,$FD,$EF,$FF,$FE,$43,$59,$EA,$6A,$FE,$AC,$1C,$31,$26,$ED
    FCB $BB,$6C,$1B,$7B,$63,$B5,$AC,$4F,$AA,$EA,$FE,$DA,$FD,$E1,$EE,$3E
    FCB $28,$03
HUFFIMG_END:
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
