
;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - vdp experiment
; VERSION: 0.0.2
;    FILE: CONV_HICOLOR.ASM
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; SHOWS "SAD DANBO"! (ART NOT BY ME, I CANT FIND AUTHOR.) 
;
; EXPERIMENTING WITH THE V9958 HIGHCOLOR MODES.
;
; I WROTE A PYTHON UTILITY, CONV_YJK.PY, WHICH CONVERTS 256X212-SIZED 
; PNG FILES INTO HUFFMAN-CODED YJK BINARIES AS SEEN BELOW.
;
;------------------------------------------------------------------------------
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
MSG_END     FCC  " TICKS"
MSG_CR      FCB  LF,CR,LF,CR,0
; -----------------------------------------------------------------------------
VDP_SEQ     FCB $00,$87,$0E,$80,$08,$99,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$40
            FCB $00,$8E,$00,$40,$00,$90,$05,$92  
; -----------------------------------------------------------------------------        
VDP_GRAF7   
    LDX  #VDP_SEQ       ; SET 256 X 212 X YJK+YAE COLOR MODE
VDP_ILOOP7
    LDA  ,X+
    STA  VREG
    CMPX #VDP_GRAF7
    BLO  VDP_ILOOP7
    LDA  #$22       ; SET BG/BORDER (R,B,G)
    STA  VPAL
    LDA  #$02
    STA  VPAL

    RTS                 
; -----------------------------------------------------------------------------
SERBUF          RMB 32  ; SERIAL BUFFER FOR DEBUG LOGGING
TSTART          RMB 8   ; START AND END TIMES FOR DURATION REPORT
TEND            RMB 8
QCOUNT          RMB 2   ; DRAWING LOOP ITERATIONS
YY              RMB 1   ; CURRENT (Y,J,K) VALUES
JJ              RMB 1
KK              RMB 1
KLO             RMB 1   ; PIECEWISE J,K FOR THE VDP
KHI             RMB 1
JLO             RMB 1
JHI             RMB 1
TCODELEN        RMB 1   ; HUFFMAN CODE LENGTH DURING INITIAL TABLE PARSE
TNUMROWS        RMB 1   ; NUM TABLE ROWS DURING INITIAL PARSE
REM             RMB 1   ; HOLDS LATEST UNPROCESSED INPUT BITS
REMLEN          RMB 1   ; NUM BITS IN ABOVE
CODETAB         RMB (1+2+1)*64 ; BYTE-ALIGNED CODE TABLE FOR SPEED
ENDCODETAB              ; (PARSED FROM INITAL SECTION OF INPUT DATA)
TMP8            RMB 1
; -----------------------------------------------------------------------------
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
; -----------------------------------------------------------------------------
VDP_INIT:    
    JSR  VDP_GRAF7
    LDX  #TSTART    ; GET STARTING SYSTEM TIME IN 16THS OF SECS
    JSR  BF_RTC_GETTIX

    LDU  #HUFFIMG   ; START PARSING INPUT DATA.
    LDD  ,U++
    STB  TNUMROWS   ; FIRST, NOTE NUMBER OF HUFFMAN TABLE ROWS/
    LDA  ,U+
    STA  REM        ; QUEUE UP LATEST 8 BITS OF INPUT,
    LDA  #8         ; AND THE LENGTH OF UNPROCESSED BITS.
    STA  REMLEN

    LDA  #0         
    STA  TCODELEN   ; FOR BETTER DECODING SPEED,
    LDY  #CODETAB   ; UNPACK HUFF CODE TABLE TO BYTE-ALIGNED CODETAB
TBL_PARSE:    
    LDF  #4
    JSR  GET_BITS   ; READ 4-BIT INCREASE IN CODE LENGTH
    STB  ,Y+        ; STORE IT IN CODETAB TABLE AS A U8
    ADDB TCODELEN   ; SUM TOTAL CODE LENGTH
    STB  TCODELEN 
    TFR  B,F
    JSR  GET_BITS   ; READ IN THAT MANY BITS OF HUFFMAN CODE,
    STD  ,Y++       ; AND STORE IT IN CODETAB AS A U16
    LDF  #6
    JSR  GET_BITS   ; READ 6-BIT SIGNED DELTA
    JSR  SEX6       ; SIGN-EXTEND IT TO 8-BITS
    STB  ,Y+        ; STORE IN CODETAB AS A U16
    DEC  TNUMROWS   ; COUNTDOWN TABLE ROWS
    BNE  TBL_PARSE  ; DO NEXT ROW, IF ANY.

INIT_YJK:           ; GET INITIAL VALUES OF Y,J, AND K.
    LDF  #6         ; (THE ENCODED DATA IS JUST CHANGES IN Y,J,K)
    JSR  GET_BITS
    JSR  SEX6       ; SIGN-EXTEND THE 6-BIT VALS TO 8-BITS
    STB  YY
    LDF  #6
    JSR  GET_BITS
    JSR  SEX6  
    STB  JJ
    LDF  #6
    JSR  GET_BITS
    JSR  SEX6  
    STB  KK

START_DRAWING:      ; WE ARE NOW AT THE ENCODED DATA,
    LDD  #13568     ; AND WE'LL PLOT (64 * 212) PIXEL-QUARTETS.
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
    TFR  B,A        ; SPLIT J INTO 2 3-BIT WORDS
    ANDA #$7
    STA  KLO
    LSRB
    LSRB
    LSRB
    ANDB #$7
    STB  KHI

    LDX  #KLO       ; FOR EACH OF KLO,KHI,JLO,JHI
PIXLOOP
    BSR  DECODE     ; GET DY
    ADDB YY         ; Y = Y + DY
    STB  YY
    LSLB
    LSLB
    LSLB
    ORB  ,X+        ; PIXEL = (Y<<3) | JK_PIECE
    STB  VDAT       ; SEND IT TO DISPLAY
    CMPX #(JHI+1)
    BLO  PIXLOOP    

    LDD  QCOUNT     ; PIXEL QUARTET COUNTDOWN
    DECD
    BNE  DRAWLOOP   ; LOOP UNTIL SCREEN FILLED.

    JMP  END_REPORT ; SHOW DECODE DURATION AND END PROGRAM.
; -----------------------------------------------------------------------------
; MATCH THE HUFFMAN CODE AT (U,REM) AND RETURN SIGNED INT (DELTA) IN B.
; ON RETURN, (U,REM) WILL POINT TO THE NEXT INPUT BIT.
; -----------------------------------------------------------------------------
DECODE:
    CLRD            ; CLEAR INPUT SHIFT-REGISTER
    LDY  #CODETAB   ; POINT Y TO HUFFMAN CODE TABLE
DEC_LOOP:           ; PER EACH ROW OF CODE TABLE
    LDE  ,Y         ; NUM ADDL BITS OCCUPIED BY THIS CODE VS LAST ONE
    BEQ  COMPARE    ; IF WE HAVE ENOUGH INPUT BITS, GO TO COMPARISON.
SHLOOP:
    LDF  REMLEN
    BNE  GOTREM
    LDF  ,U+
    STF  REM
    LDF  #8
    STF  REMLEN
GOTREM:
    LSL  REM
    ROLD
    DEC REMLEN
    DECE
    BNE  SHLOOP
COMPARE:            ; COMPARE INPUT WORD TO HUFFMAN CODE.
    CMPD 1,Y        ; INWORD == CODE?
    BEQ  DEC_DONE
    LEAY 4,Y        ; NOPE, TRY NEXT CODE OF TABLE.
    CMPY #ENDCODETAB
    BEQ  DEC_FAIL   ; IF RAN OUT OF TABLE, THE DECODE FAILED!
    BRA  DEC_LOOP
DEC_DONE:
    LDB  3,Y        ; MATCH! GET SIGNED INT8) DELTA
    RTS
DEC_FAIL:  
    LDB  #0
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
; COPIES BITSTRING OF LEN. F FROM (U,REM) TO D, RIGHT-JUSTIFIED.
; U,REM ARE ADVANCED TO NEXT BIT.
;------------------------------------------------------------------------------
GET_BITS:
    CLRD            ; INIT DEST WORD
    LDE  REMLEN
GB_LOOP:
    TSTE
    BNE  GB_GOTREM
    LDE  ,U+
    STE  REM
    LDE  #8
GB_GOTREM:
    LSL  REM
    ROLD
    DECE    
    DECF    
    BNE  GB_LOOP
    STE  REMLEN
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
; CONVERTS VAL IN A TO HEX STRING AT Y. IT DOES INCREMENT Y, BUT DOESN'T 
; NULL-TERMINATE THE STRING. (I THINK I GOT THIS FROM L. LEVENTHAL'S BOOK.)
;------------------------------------------------------------------------------
S_HEXY:
    TFR  A,B        ; SAVE ORIGINAL BINARY VALUE
    LSRA            ; MOVE HIGH DIGIT TO LOW DIGIT
    LSRA
    LSRA
    LSRA
    CMPA #9
    BLS  AD30       ; BRANCH IF HIGH DIGIT IS DECIMAL
    ADDA #7         ; ELSE ADD 7 SO AFTER ADDING 'O' THE
                    ; CHARACTER WILL BE IN ‘'A'..'F'
AD30:
    ADDA #'0        ; ADD ASCII O TO MAKE A CHARACTER
    ANDB #$0F       ; MASK OFF LOW DIGIT
    CMPB #9
    BLS AD3OLD      ; BRANCH IF LOW DIGIT IS DECIMAL
    ADDB #7         ; ELSE ADD 7 SO AFTER ADDING 'O! THE
                    ; CHARACTER WILL BE IN '‘A'..'F!
AD3OLD:     
    ADDB #'0        ; ADD ASCII O TO MAKE A CHARACTER
    STA ,Y+         ; INSERT HEX BYTES INTO DEST STRING AT X
    STB ,Y+         ; AND NCREMENT X
    RTS
;------------------------------------------------------------------------------
; SHOW HOW LONG IT TOOK TO DECODE/DRAW THE IMAGE AND END THE PROGRAM.
;------------------------------------------------------------------------------
END_REPORT
    LDX  #TEND          ; GET END TIME. 
    JSR  BF_RTC_GETTIX  
    LDU  #TSTART        ; CALC ELAPSED TICKS,
    JSR  SUB64_XU
    LDY  #SERBUF        ; AND PRINT DURATION.
    LDE  #8
TIXLOOP:
    LDA  ,X+
    BSR  S_HEXY
    DECE
    BNE  TIXLOOP
    LDA  #NUL
    STA  ,Y+
    LDY  #SERBUF
    JSR  BF_UT_PUTS
    LDY  #MSG_END
    JSR  BF_UT_PUTS
    JSR  BF_UT_WAITTX
    RTS             ; END OF PROGRAM
; -----------------------------------------------------------------------------
; ENCODED IMAGE AS OUTPUT BY CONV_YJK.PY
; -----------------------------------------------------------------------------
HUFFIMG:
    FCB $00,$13,$18,$02,$02,$2F,$F2,$5F,$C0,$A0,$85,$3F,$41,$20,$C5,$17
    FCB $80,$84,$41,$46,$14,$10,$7B,$14,$78,$C0,$81,$E8,$10,$03,$92,$3B
    FCB $20,$11,$D7,$00,$8E,$79,$14,$71,$DC,$11,$C0,$90,$41,$0B,$F7,$FF
    FCB $FF,$FE,$FF,$FF,$E7,$FC,$EE,$7F,$B3,$FB,$B9,$FF,$B3,$9F,$30,$AA
    FCB $40,$CF,$23,$64,$38,$18,$1F,$BF,$0B,$21,$72,$1F,$7F,$2C,$84,$C3
    FCB $FF,$FF,$FF,$FF,$BF,$FF,$FF,$FF,$FF,$FF,$F7,$FF,$CE,$FF,$7E,$DD
    FCB $AD,$A6,$E9,$AD,$B8,$EE,$32,$F2,$D7,$BE,$EE,$DF,$FB,$FE,$FF,$FF
    FCB $8F,$FF,$FF,$FF,$DF,$FF,$3F,$E6,$E7,$B3,$FE,$CE,$FB,$E7,$FC,$B9
    FCB $FD,$53,$81,$03,$39,$07,$92,$CC,$C3,$FF,$E5,$CE,$C0,$E7,$8F,$DB
    FCB $01,$50,$3C,$CF,$FF,$FB,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$F7,$FF,$79
    FCB $79,$EF,$BA,$DB,$5B,$5C,$5A,$6B,$71,$BE,$D9,$66,$DB,$FE,$DD,$FD
    FCB $FF,$BF,$FF,$F8,$FF,$FF,$FF,$7F,$FF,$F3,$FE,$17,$8F,$B3,$EF,$CF
    FCB $BD,$CF,$FF,$E7,$2A,$F8,$4C,$24,$C0,$78,$6E,$4E,$73,$EE,$77,$EF
    FCB $26,$6C,$FF,$81,$50,$A8,$CF,$9C,$FF,$EF,$FF,$FF,$FF,$FF,$FF,$FF
    FCB $FF,$B7,$F3,$B3,$EF,$ED,$ED,$C6,$DA,$D7,$5A,$D6,$C1,$6D,$EF,$B0
    FCB $B7,$BB,$EF,$7F,$7F,$EF,$FF,$FE,$3F,$FF,$F7,$FF,$FF,$FC,$F3,$F3
    FCB $DB,$2C,$FB,$F3,$7B,$3F,$9F,$FC,$E4,$F8,$4C,$3E,$07,$03,$CF,$3E
    FCB $7F,$EB,$F7,$FC,$E7,$DF,$02,$A0,$52,$9C,$3C,$CF,$BF,$FF,$FF,$FF
    FCB $FF,$FF,$FF,$BF,$FD,$9C,$7F,$FE,$EF,$B7,$BB,$B6,$D6,$C5,$B5,$AE
    FCB $2D,$D8,$EF,$2D,$DF,$F7,$7B,$7E,$0F,$DF,$FF,$FC,$7F,$FF,$EF,$FF
    FCB $FF,$F9,$E7,$D9,$F7,$9F,$BE,$5D,$9F,$F9,$FF,$CC,$CE,$79,$93,$80
    FCB $72,$79,$0C,$DF,$3F,$DE,$ED,$E7,$F3,$FF,$30,$50,$40,$06,$67,$FF
    FCB $FF,$FF,$FF,$FF,$FF,$FF,$BF,$FD,$9C,$7F,$BF,$6F,$DF,$BB,$B6,$D7
    FCB $1A,$D6,$BD,$77,$BB,$72,$EF,$FD,$DF,$7F,$DF,$FF,$FF,$C7,$FF,$FF
    FCB $FF,$EF,$E7,$FE,$63,$B9,$7E,$7E,$FE,$3B,$3C,$FF,$FF,$93,$9C,$9C
    FCB $99,$C2,$72,$78,$79,$0F,$6C,$F7,$BB,$7F,$CF,$FF,$F2,$04,$14,$2A
    FCB $06,$CF,$FF,$FF,$FF,$FB,$FF,$F7,$FF,$85,$FF,$FF,$FA,$F7,$EE,$F7
    FCB $BA,$C6,$DB,$DA,$DA,$71,$BB,$1D,$B7,$DE,$3F,$EF,$BF,$EF,$FF,$FF
    FCB $E3,$FF,$FF,$FF,$F7,$FF,$CF,$E7,$EC,$FC,$DE,$FC,$BF,$9F,$FC,$F9
    FCB $39,$F6,$78,$64,$08,$78,$F2,$73,$CF,$FD,$FA,$DF,$9F,$73,$8F,$E7
    FCB $08,$0A,$22,$80,$73,$FF,$FF,$FF,$FD,$FF,$F3,$BF,$FF,$FF,$FF,$EB
    FCB $BB,$7D,$DA,$DF,$7B,$63,$8D,$B4,$E2,$F6,$A7,$6B,$6E,$FD,$FF,$79
    FCB $B9,$77,$FF,$FF,$F1,$FF,$FF,$FF,$FB,$F9,$FF,$F3,$FF,$B2,$6F,$7C
    FCB $DF,$CF,$FE,$AF,$CF,$F3,$F9,$24,$27,$39,$31,$C9,$F9,$FD,$FB,$7D
    FCB $D9,$DE,$7F,$60,$32,$60,$6A,$52,$85,$4F,$F1,$BF,$FF,$F3,$FF,$DF
    FCB $FB,$CF,$FF,$FF,$DF,$B7,$B6,$D7,$6D,$FD,$B7,$E1,$AD,$AC,$17,$72
    FCB $DB,$6D,$6B,$FF,$9B,$EE,$FF,$FF,$FF,$F8,$FF,$FF,$FF,$FD,$FF,$F3
    FCB $F3,$FF,$3E,$EC,$7E,$6F,$E7,$CF,$9C,$BF,$98,$F3,$F8,$55,$09,$9B
    FCB $C9,$CF,$3F,$CB,$B2,$DF,$6D,$9C,$3F,$FF,$87,$96,$A4,$94,$2A,$4F
    FCB $EE,$7F,$FF,$FF,$FB,$F3,$BC,$FF,$FF,$FD,$FB,$76,$DB,$5D,$6D,$F7
    FCB $7F,$3E,$B7,$1D,$B1,$BB,$5D,$B6,$C3,$BF,$F7,$7F,$FF,$FF,$FC,$7F
    FCB $FF,$FF,$FE,$FF,$F9,$F9,$FF,$9F,$6E,$6F,$E3,$3F,$E7,$F9,$FE,$7F
    FCB $1F,$21,$21,$99,$39,$72,$7C,$FF,$67,$6F,$EF,$FF,$9F,$7F,$26,$44
    FCB $94,$A1,$92,$67,$FB,$CF,$FF,$FE,$CF,$FF,$FF,$FF,$FE,$FD,$BB,$6B
    FCB $6B,$AD,$6B,$FB,$F0,$FB,$71,$DB,$16,$ED,$7B,$6E,$7F,$FB,$BF,$FF
    FCB $FF,$FE,$3F,$FD,$FC,$FF,$EF,$FF,$9F,$9E,$7F,$F7,$67,$B3,$B9,$FE
    FCB $7F,$97,$F0,$FF,$F8,$12,$40,$F7,$27,$27,$FE,$77,$36,$FE,$FF,$FF
    FCB $FF,$F2,$15,$29,$56,$04,$C8,$7F,$FF,$FF,$E3,$CF,$FE,$FF,$FF,$FF
    FCB $7D,$DB,$6D,$6B,$5A,$96,$B5,$BF,$BB,$03,$F7,$B7,$7B,$6D,$8D,$B7
    FCB $3E,$DF,$97,$FF,$FF,$FF,$E3,$FF,$FF,$FF,$F7,$FF,$CE,$7F,$FC,$FB
    FCB $FD,$97,$CF,$FF,$E6,$7D,$9F,$BF,$84,$30,$38,$7C,$CE,$79,$FC,$FE
    FCB $D6,$7A,$FB,$87,$FF,$F9,$CE,$0A,$20,$17,$0A,$A7,$FF,$FF,$FF,$9F
    FCB $7F,$FF,$FF,$BF,$BE,$DB,$6D,$AD,$6C,$5A,$DA,$E5,$F6,$11,$E5,$96
    FCB $DB,$ED,$B1,$B6,$E7,$DB,$D8,$5F,$FF,$FF,$FF,$8F,$FF,$7F,$FC,$FB
    FCB $FF,$FE,$4F,$FE,$7D,$FF,$BE,$7F,$FF,$99,$FF,$F7,$F0,$86,$13,$33
    FCB $99,$E7,$9F,$CF,$EF,$DB,$FB,$FF,$FC,$FC,$98,$60,$03,$00,$56,$7F
    FCB $FF,$FF,$FF,$FF,$FF,$FF,$BF,$BB,$B6,$ED,$6D,$36,$35,$B5,$EE,$CB
    FCB $86,$4B,$B6,$DC,$BB,$63,$77,$FE,$F7,$FF,$FF,$FF,$FE,$3F,$FD,$FF
    FCB $FF,$FF,$FF,$C9,$FF,$CF,$BF,$EF,$B3,$CB,$F3,$CC,$FE,$FF,$F8,$49
    FCB $0C,$9C,$E7,$99,$E7,$E5,$FD,$FB,$FD,$FF,$FF,$E7,$64,$84,$80,$D4
    FCB $02,$A1,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$ED,$B6,$BB,$5B,$58,$35
    FCB $B5,$BB,$7F,$9F,$BE,$DC,$6E,$F7,$79,$FE,$FB,$FC,$BF,$FF,$FF,$1F
    FCB $FF,$B9,$7F,$FF,$FF,$FF,$27,$FF,$FF,$EF,$D9,$FB,$33,$E6,$7F,$FF
    FCB $F9,$24,$9C,$33,$CF,$27,$CF,$EE,$77,$ED,$FB,$FD,$F8,$7F,$3F,$39
    FCB $02,$A1,$41,$24,$FF,$FF,$FF,$FF,$FF,$FE,$FF,$F6,$F6,$D6,$BA,$D6
    FCB $BE,$DB,$58,$36,$FF,$FD,$FD,$D6,$F9,$7E,$FE,$5C,$BD,$91,$FB,$FB
    FCB $FF,$EA,$7E,$FF,$FF,$FF,$FF,$FF,$E6,$7F,$FF,$B1,$F9,$BE,$E6,$7F
    FCB $99,$FF,$FF,$E4,$93,$30,$E6,$4F,$2E,$7C,$FF,$1A,$FE,$FD,$BF,$FE
    FCB $7F,$93,$F8,$00,$C5,$28,$02,$4F,$FF,$FF,$FF,$FF,$FF,$EF,$FE,$EB
    FCB $6D,$B5,$B5,$26,$B5,$ED,$DB,$DB,$70,$7F,$FD,$EE,$BD,$85,$FB,$FF
    FCB $FF,$97,$DC,$7B,$FF,$EA,$7E,$FF,$FF,$FF,$FF,$FF,$E6,$7F,$FB,$38
    FCB $DF,$3D,$FE,$7F,$93,$9F,$FF,$FC,$93,$39,$C2,$6E,$67,$3E,$77,$ED
    FCB $CE,$FF,$DD,$BC,$FE,$1E,$E7,$C0,$15,$05,$18,$45,$7F,$FF,$FF,$FF
    FCB $FF,$FF,$7F,$BD,$D7,$6D,$69,$B5,$26,$B6,$EF,$6F,$76,$CF,$73,$EF
    FCB $73,$7D,$FD,$FF,$FF,$CD,$EF,$EF,$FF,$A9,$FF,$EF,$FF,$FF,$FF,$FF
    FCB $99,$FF,$DF,$C7,$E7,$BE,$F9,$3E,$4E,$7F,$FF,$F8,$4C,$E7,$93,$33
    FCB $72,$7E,$5F,$FC,$6B,$FF,$7F,$DB,$3C,$FF,$38,$01,$A8,$51,$08,$AF
    FCB $FF,$FF,$FF,$FF,$FF,$EF,$FE,$EB,$B5,$AD,$36,$26,$9B,$FB,$8E,$DB
    FCB $97,$FF,$77,$9B,$EF,$FF,$BF,$9B,$D8,$FF,$FF,$BD,$95,$3F,$FD,$FF
    FCB $FF,$FF,$FF,$F2,$7F,$DF,$73,$3B,$9E,$FF,$9F,$CC,$CF,$FF,$FC,$61
    FCB $CE,$4E,$64,$E5,$E4,$FF,$CD,$F1,$BF,$BD,$DF,$CF,$B6,$79,$C3,$15
    FCB $70,$14,$A8,$02,$BF,$FF,$FF,$FF,$FF,$FF,$BF,$FB,$AE,$D6,$B4,$D8
    FCB $9A,$DB,$F7,$1D,$B7,$F7,$37,$BF,$2F,$DF,$FF,$7F,$2F,$B1,$FF,$DF
    FCB $C7,$80,$FB,$FD,$FF,$FF,$FF,$FF,$F2,$7F,$F7,$F9,$D9,$F7,$DE,$67
    FCB $CC,$CF,$CB,$37,$F9,$C2,$73,$CF,$26,$79,$72,$CB,$E7,$C6,$FF,$7D
    FCB $AF,$E7,$DE,$67,$E0,$06,$0A,$22,$8A,$A7,$FF,$FF,$FF,$FF,$FF,$DF
    FCB $FD,$D7,$6B,$5A,$6C,$4D,$6D,$DE,$FD,$B9,$7C,$1D,$DB,$DC,$FD,$FF
    FCB $FF,$DD,$9E,$FF,$EF,$E3,$E1,$EF,$FF,$DF,$FF,$FC,$FB,$F9,$3F,$F7
    FCB $FE,$6C,$FB,$FC,$FF,$3E,$1F,$3E,$FF,$98,$4C,$FC,$F9,$87,$8F,$F7
    FCB $27,$9B,$F6,$EF,$6F,$E7,$9F,$6C,$F0,$81,$82,$8A,$80,$54,$EF,$E7
    FCB $FF,$FF,$FF,$FF,$7F,$BD,$D7,$6B,$5A,$6C,$5A,$6D,$EF,$7E,$E7,$7E
    FCB $EF,$BC,$7F,$FF,$FF,$DD,$CD,$FF,$FF,$BF,$14,$FB,$FF,$F7,$FF,$FF
    FCB $FF,$F2,$77,$F2,$FF,$F3,$FB,$F9,$FF,$CD,$5C,$BE,$E7,$F9,$84,$FF
    FCB $27,$98,$79,$FB,$73,$CC,$BB,$2D,$DE,$DF,$FF,$3E,$CF,$24,$E0,$2A
    FCB $92,$80,$CF,$FF,$FF,$3F,$FF,$EF,$FF,$BE,$DB,$6D,$AD,$36,$2D,$6B
    FCB $71,$BE,$FF,$DB,$37,$67,$76,$FF,$F3,$FF,$DD,$FF,$FF,$FD,$F8,$A7
    FCB $FF,$7F,$BF,$FF,$FF,$FF,$93,$BD,$FF,$9F,$9E,$FF,$F9,$F3,$E1,$9D
    FCB $F7,$F3,$30,$CF,$E4,$F3,$0F,$B9,$EE,$79,$FF,$6B,$F6,$FF,$F9,$F6
    FCB $79,$27,$82,$A9,$28,$33,$9F,$E7,$F9,$FF,$FF,$7F,$FD,$EE,$DD,$AD
    FCB $69,$B1,$6B,$5B,$BB,$F2,$FE,$E5,$BB,$F7,$BF,$FC,$FF,$F7,$7F,$FF
    FCB $FF,$7E,$29,$FF,$DF,$EF,$E6,$FF,$2F,$FF,$E7,$7F,$1F,$9C,$FE,$FF
    FCB $F9,$FF,$C3,$25,$F7,$F3,$30,$CF,$E6,$4C,$F3,$BC,$EE,$72,$77,$ED
    FCB $7E,$DF,$FF,$3E,$CF,$33,$CA,$95,$52,$82,$C9,$9E,$7F,$E5,$F8,$7F
    FCB $EF,$FF,$B6,$F6,$C5,$AD,$69,$B1,$6B,$6C,$DE,$DC,$FB,$72,$ED,$FB
    FCB $DF,$FE,$7F,$FB,$BF,$FF,$FF,$BF,$14,$F1,$FB,$FE,$FE,$5F,$7C,$FF
    FCB $FC,$F7,$F1,$F9,$CB,$FF,$FF,$9F,$FC,$9C,$F6,$FC,$33,$27,$CE,$73
    FCB $C9,$9B,$CE,$E7,$E6,$FD,$BF,$6F,$F6,$73,$C9,$FE,$3E,$05,$42,$82
    FCB $4F,$FF,$F9,$39,$FF,$FF,$FF,$77,$6D,$6D,$AD,$34,$EA,$5A,$DB,$FE
    FCB $E7,$BB,$97,$6F,$DE,$FF,$F3,$FF,$DE,$FF,$FF,$FF,$F1,$9F,$E5,$F6
    FCB $FF,$BF,$FC,$FF,$E7,$FE,$FB,$AB,$37,$FF,$CF,$FF,$F9,$3C,$BF,$F2
    FCB $72,$7E,$7C,$CC,$F3,$E7,$E6,$F9,$7E,$DF,$EE,$36,$F2,$1C,$FE,$73
    FCB $E5,$A8,$50,$64,$FF,$FF,$3C,$C9,$FF,$FF,$F7,$76,$D6,$2D,$34,$D3
    FCB $D6,$EE,$CF,$F7,$2F,$1B,$77,$7D,$FF,$7E,$1F,$FD,$DF,$FF,$FF,$FF
    FCB $19,$DF,$FD,$FF,$2F,$BF,$CF,$F2,$7D,$FD,$FC,$B3,$FF,$F3,$FF,$FE
    FCB $1E,$0F,$BF,$93,$E7,$39,$F2,$73,$E7,$3F,$3F,$D9,$7B,$F6,$FD,$BC
    FCB $87,$3F,$9C,$F9,$60,$00,$4F,$CB,$F7,$E1,$90,$CF,$FF,$FF,$77,$6D
    FCB $75,$A6,$89,$38,$BF,$9E,$EF,$DB,$B2,$EF,$7E,$5F,$6F,$FF,$3F,$BF
    FCB $FF,$FF,$FF,$3E,$FF,$FD,$FF,$7F,$F3,$FF,$0F,$FD,$7F,$3F,$FF,$E7
    FCB $FF,$F2,$7C,$FB,$F8,$7F,$3F,$3F,$87,$92,$73,$F9,$7F,$FB,$7E,$D6
    FCB $6F,$98,$64,$3F,$CB,$F3,$93,$0F,$32,$FB,$F8,$30,$20,$4F,$FF,$FE
    FCB $F6,$DA,$C5,$A6,$89,$37,$70,$19,$BD,$B6,$E5,$B6,$3B,$EF,$CB,$ED
    FCB $FF,$E1,$7D,$FF,$FF,$FF,$FC,$FB,$FF,$E5,$F7,$DF,$F9,$E7,$C3,$DF
    FCB $D7,$F3,$FF,$FF,$F9,$F3,$9F,$CF,$BF,$93,$F3,$FE,$7C,$F3,$30,$CB
    FCB $F9,$9B,$F6,$FD,$AE,$5E,$71,$53,$3F,$E7,$E3,$F3,$93,$31,$BB,$BF
    FCB $83,$05,$04,$90,$FF,$FF,$DE,$B4,$EB,$5A,$25,$BB,$00,$EF,$AD,$6D
    FCB $82,$EF,$6F,$8F,$7F,$FD,$F1,$F7,$FF,$FF,$FF,$FF,$CF,$BF,$FE,$3F
    FCB $7F,$1E,$5F,$CE,$4F,$BF,$BF,$BF,$9F,$FC,$FF,$F3,$CF,$9F,$FF,$3F
    FCB $F9,$F9,$F3,$39,$33,$E7,$F6,$B3,$FF,$7C,$6F,$D4,$AC,$CF,$BC,$FC
    FCB $7F,$C9,$C3,$7B,$BB,$F2,$29,$40,$C3,$CE,$1F,$FD,$BD,$A6,$2D,$35
    FCB $B7,$61,$37,$7A,$D6,$B7,$AD,$D8,$FF,$EC,$FF,$7F,$F7,$FF,$DF,$CF
    FCB $FF,$F9,$F7,$FF,$CB,$EF,$E3,$CF,$FC,$CF,$BF,$BF,$BD,$E1,$FF,$FE
    FCB $73,$F9,$F3,$FF,$E7,$FF,$3F,$3F,$3F,$AA,$4F,$EE,$7F,$B7,$3F,$2D
    FCB $FA,$8C,$CF,$F9,$7E,$F3,$32,$73,$5E,$FB,$F3,$50,$15,$10,$F3,$FF
    FCB $DE,$ED,$DA,$D6,$DF,$36,$ED,$71,$6B,$5A,$F6,$F1,$BE,$77,$FF,$BE
    FCB $FF,$FF,$EF,$E7,$FF,$FF,$FF,$FD,$CF,$BF,$FE,$7F,$39,$F7,$F7,$F7
    FCB $BE,$79,$FF,$CE,$7F,$FC,$E4,$79,$7F,$FC,$CF,$99,$F7,$39,$39,$CB
    FCB $E3,$6C,$CE,$5F,$37,$E1,$CF,$FF,$CF,$CF,$9B,$CD,$FB,$B9,$F0,$15
    FCB $50,$79,$D9,$C3,$DE,$ED,$BB,$5D,$8F,$77,$6D,$71,$6B,$5B,$D6,$F1
    FCB $DE,$6F,$FF,$7E,$FF,$FF,$FF,$FF,$FB,$F8,$CF,$FF,$B9,$F7,$FF,$CF
    FCB $E7,$3E,$FE,$FE,$EE,$4F,$FF,$F9,$CF,$FF,$AB,$EC,$FF,$BF,$F9,$9C
    FCB $3F,$E6,$67,$FC,$FF,$B6,$4F,$CB,$F0,$F7,$39,$E7,$FC,$FC,$CE,$36
    FCB $FB,$7F,$90,$2A,$21,$86,$F2,$1E,$F7,$DB,$B6,$EE,$EC,$6D,$AE,$D6
    FCB $9B,$5C,$77,$BD,$D4,$3E,$DF,$8F,$7F,$FC,$EF,$FF,$FF,$F7,$F1,$9F
    FCB $FF,$73,$EF,$FF,$9F,$27,$FD,$FD,$FD,$B9,$FE,$7F,$F3,$F9,$FF,$57
    FCB $D9,$FF,$7F,$F9,$3C,$9F,$CF,$C9,$FF,$1B,$F3,$27,$F8,$E7,$FC,$BC
    FCB $FC,$DE,$67,$33,$DB,$F6,$FF,$21,$84,$56,$1B,$27,$F9,$7D,$DB,$6E
    FCB $EE,$ED,$AD,$71,$35,$B7,$BD,$DE,$E5,$FB,$F3,$7F,$EF,$33,$BF,$FF
    FCB $DF,$FF,$1C,$FD,$CF,$FF,$FB,$F9,$CF,$FF,$FE,$FE,$FF,$F9,$FF,$CE
    FCB $6E,$7F,$9C,$FD,$FF,$F0,$F7,$39,$3F,$3F,$F3,$FF,$E6,$4E,$CF,$F3
    FCB $FF,$DB,$3F,$39,$9F,$9F,$FE,$DF,$3E,$64,$A9,$80,$49,$9E,$37,$BF
    FCB $6E,$BB,$6D,$BB,$5A,$D3,$05,$DB,$BB,$F7,$72,$FD,$F9,$BF,$E3,$FF
    FCB $D9,$FB,$FF,$FF,$8F,$26,$FF,$FF,$FD,$FC,$F8,$7B,$1F,$7F,$FF,$FF
    FCB $FF,$FC,$E6,$E7,$FA,$B9,$FB,$7F,$F9,$F6,$1C,$9E,$7D,$9F,$9B,$B3
    FCB $F8,$73,$9F,$CB,$F9,$E3,$7F,$E4,$39,$FB,$CF,$FF,$8D,$FF,$31,$82
    FCB $82,$48,$7F,$1D,$BB,$B5,$DB,$5A,$D8,$B5,$AD,$97,$AE,$FB,$DD,$CB
    FCB $F7,$E5,$FF,$8F,$E7,$BF,$EF,$DF,$CE,$F3,$9F,$73,$FF,$FE,$FE,$7C
    FCB $3D,$8F,$BF,$FF,$DF,$3F,$FF,$CF,$E7,$FD,$5C,$FE,$FF,$FF,$D9,$33
    FCB $99,$F7,$3E,$7D,$EE,$72,$4C,$9D,$CD,$FC,$FB,$73,$F2,$1E,$F3,$39
    FCB $7F,$F8,$D7,$F3,$F0,$14,$A9,$36,$70,$F6,$EE,$D7,$5B,$5A,$D8,$B5
    FCB $AD,$9E,$FB,$BD,$EC,$6F,$DF,$9B,$FE,$3F,$9E,$FF,$BF,$7F,$3B,$CE
    FCB $7F,$1F,$BF,$9F,$7F,$F2,$AF,$BF,$BF,$FF,$FF,$FF,$FE,$7C,$E5,$FD
    FCB $5C,$FF,$FB,$FF,$E7,$3E,$7F,$33,$79,$F7,$79,$92,$64,$EE,$31,$FC
    FCB $FB,$73,$F8,$1E,$E7,$FF,$9F,$C6,$BF,$9F,$91,$4A,$61,$27,$93,$BD
    FCB $D6,$BA,$D6,$B5,$EB,$6F,$ED,$F7,$66,$EE,$EF,$BF,$37,$F3,$7F,$3D
    FCB $FF,$7E,$FF,$F8,$3C,$FE,$3F,$FF,$F7,$FF,$2A,$FB,$FB,$FF,$FF,$FF
    FCB $FF,$E7,$FF,$9E,$AE,$7F,$FF,$F7,$F3,$9F,$3E,$3F,$9C,$EF,$BC,$CC
    FCB $93,$3F,$DE,$76,$6D,$9F,$FC,$F0,$FF,$FF,$CD,$B3,$DF,$C8,$03,$08
    FCB $19,$E7,$DB,$5A,$EB,$5A,$6F,$6F,$BB,$BD,$BB,$07,$7B,$BE,$FC,$2F
    FCB $6C,$FF,$9D,$FF,$BF,$FF,$F8,$F3,$EE,$7F,$FF,$DF,$FC,$92,$FF,$BF
    FCB $FF,$FF,$FF,$FE,$7F,$F9,$E7,$23,$9F,$FF,$BF,$F3,$39,$FF,$99,$FC
    FCB $76,$CE,$67,$09,$9F,$7F,$79,$F2,$DF,$F3,$93,$FF,$F3,$35,$C7,$DF
    FCB $3C,$2C,$32,$48,$13,$76,$D6,$B1,$34,$DA,$FF,$DD,$BD,$B6,$F6,$58
    FCB $F7,$FC,$DE,$D9,$FF,$3B,$FF,$7F,$FF,$F1,$E4,$BF,$FF,$EF,$FF,$F3
    FCB $27,$BF,$7F,$FF,$FF,$FF,$3F,$FF,$E7,$3F,$99,$FE,$FF,$F7,$38,$7B
    FCB $9C,$E6,$7F,$F7,$3F,$30,$CF,$FF,$F8,$D7,$3F,$F3,$C9,$DF,$CF,$E7
    FCB $FB,$5F,$C9,$32,$47,$00,$21,$BB,$5A,$D6,$26,$B6,$FE,$F7,$6C,$B6
    FCB $B6,$DC,$CB,$BF,$E6,$F6,$C6,$43,$7F,$EF,$EF,$FF,$FE,$A7,$FF,$FF
    FCB $FB,$FF,$FE,$49,$F7,$DF,$FF,$FF,$F3,$FF,$FF,$FE,$73,$E7,$3F,$BF
    FCB $FD,$CE,$1E,$F3,$3F,$9E,$7D,$CF,$E4,$9F,$3F,$EF,$9E,$5B,$FE,$61
    FCB $96,$FB,$64,$C3,$37,$ED,$BF,$90,$E4,$38,$10,$9B,$AD,$6B,$AD,$36
    FCB $FE,$F7,$6C,$AD,$B6,$DE,$41,$DE,$FC,$DF,$8E,$37,$D9,$1F,$FD,$FF
    FCB $FF,$D4,$FF,$FF,$FF,$7F,$FF,$C9,$99,$7D,$FD,$FF,$F3,$FF,$FF,$FF
    FCB $F9,$FF,$57,$E7,$BF,$FE,$4F,$F6,$CE,$1F,$9E,$7D,$9F,$E7,$3A,$B9
    FCB $77,$B6,$67,$9B,$FF,$33,$F8,$FF,$03,$2D,$F6,$DF,$E4,$D9,$20,$40
    FCB $86,$F6,$D6,$EB,$4D,$BF,$7D,$76,$CA,$DD,$DE,$7B,$BF,$CD,$FF,$F2
    FCB $EC,$BF,$F7,$FF,$FF,$53,$F7,$F3,$FF,$BF,$FF,$E4,$E4,$DE,$FE,$FF
    FCB $F9,$FF,$FF,$FC,$FB,$9F,$F3,$E1,$EF,$FF,$93,$F9,$FF,$FE,$67,$D9
    FCB $FE,$7F,$0F,$FD,$CF,$9B,$67,$F3,$3F,$FF,$C0,$CF,$B5,$AF,$F8,$6C
    FCB $81,$80,$13,$76,$DA,$D8,$B4,$DB,$BB,$BD,$BB,$2D,$DF,$CD,$EE,$F6
    FCB $1B,$FF,$F1,$D9,$7F,$EF,$FF,$FE,$A7,$EF,$33,$7F,$FF,$BF,$9C,$F9
    FCB $3B,$BF,$BF,$FE,$7F,$FF,$FF,$F3,$67,$FC,$F8,$7B,$FF,$93,$FF,$CE
    FCB $FE,$7F,$3F,$3F,$F3,$C9,$FF,$79,$E6,$D9,$FE,$4F,$FF,$F0,$33,$DD
    FCB $6B,$FE,$4E,$02,$98,$49,$8F,$AD,$A6,$B1,$6B,$7B,$6D,$FB,$6C,$BD
    FCB $FF,$7B,$FB,$0B,$9D,$FF,$FF,$BF,$BF,$FF,$FA,$9F,$B3,$CD,$FF,$E3
    FCB $DF,$CE,$4C,$FF,$6F,$DF,$FF,$3F,$FF,$FF,$F9,$B3,$7F,$15,$F9,$EF
    FCB $FF,$73,$87,$E7,$FF,$FE,$7F,$3F,$F3,$33,$FB,$79,$39,$6E,$7F,$E7
    FCB $9F,$F9,$3C,$2E,$B7,$F7,$9C,$A8,$54,$3C,$EE,$DA,$D3,$8B,$6B,$BB
    FCB $6E,$37,$6C,$DE,$FF,$7B,$DF,$EC,$CB,$8F,$FF,$FF,$BF,$FF,$FA,$9E
    FCB $5F,$CD,$FE,$5F,$CB,$FE,$4C,$CF,$AD,$FB,$FF,$FF,$9F,$FF,$FC,$BC
    FCB $EF,$E1,$99,$FF,$FE,$F3,$3F,$9F,$FF,$F9,$FC,$FF,$CC,$F6,$E7,$F3
    FCB $CD,$CF,$FE,$5E,$79,$E1,$9F,$D6,$FE,$F3,$C1,$4A,$61,$CF,$5D,$B5
    FCB $A6,$0D,$6D,$ED,$BD,$BB,$9B,$FE,$DB,$FB,$D8,$5F,$FF,$FF,$FF,$BF
    FCB $FF,$FA,$9E,$5F,$CD,$FC,$FF,$F7,$E6,$66,$77,$5F,$DF,$FF,$FC,$FF
    FCB $FF,$E5,$F3,$7F,$0C,$CF,$FF,$E3,$7E,$1C,$FF,$FF,$F9,$FE,$E7,$39
    FCB $D9,$CE,$5F,$E6,$79,$6F,$FF,$E7,$3F,$C8,$7A,$DF,$DF,$38,$04,$20
    FCB $3D,$BB,$6B,$5E,$B6,$DE,$DD,$97,$BB,$FF,$B6,$FC,$77,$FF,$FF,$FF
    FCB $FF,$7F,$FF,$F5,$38,$F3,$9B,$DF,$33,$EF,$FB,$3C,$E7,$77,$F7,$FF
    FCB $FF,$FF,$F3,$FF,$FF,$3C,$E4,$FF,$FC,$DF,$CE,$7F,$3E,$FF,$19,$FD
    FCB $B3,$87,$F9,$9E,$D9,$F3,$2F,$9F,$FF,$CB,$61,$CE,$43,$D6,$FE,$FF
    FCB $81,$86,$1B,$6E,$D6,$D6,$AA,$ED,$BD,$B9,$77,$BF,$EF,$6F,$C7,$7F
    FCB $FF,$FF,$FF,$F7,$FF,$FF,$53,$9F,$CB,$EC,$C8,$7B,$5F,$FF,$33,$F7
    FCB $7F,$7F,$FF,$FF,$FF,$3F,$CD,$EC,$9F,$3E,$1F,$FB,$9C,$FF,$9F,$CF
    FCB $BF,$F3,$FF,$96,$FC,$39,$FF,$97,$92,$F8,$DF,$87,$F9,$67,$9F,$E7
    FCB $FB,$5F,$CC,$00,$FE,$D7,$B6,$D6,$5B,$F6,$EF,$DE,$FE,$DF,$7F,$1D
    FCB $FC,$7F,$FF,$FE,$FF,$FF,$FF,$14,$FB,$CF,$7C,$32,$C9,$75,$FF,$F3
    FCB $9D,$F7,$F7,$FF,$FF,$FF,$F3,$FF,$C7,$3F,$FE,$1E,$7D,$9E,$7F,$3F
    FCB $E7,$DF,$F9,$FF,$F6,$E7,$3F,$9F,$93,$36,$CE,$D9,$C3,$FC,$CF,$FC
    FCB $38,$DF,$B5,$FC,$E6,$6C,$2D,$BE,$DA,$CB,$BF,$77,$EF,$7B,$DF,$FF
    FCB $7B,$F9,$F7,$FF,$FF,$EF,$FF,$FC,$53,$EF,$2F,$F0,$CC,$96,$D7,$F7
    FCB $F3,$E7,$DF,$DF,$FF,$FF,$FF,$CF,$FE,$CB,$19,$FF,$99,$D5,$F9,$FF
    FCB $E7,$FC,$FF,$DB,$99,$F6,$FF,$CF,$F2,$7E,$4C,$DB,$3B,$73,$9E,$79
    FCB $3F,$F0,$F6,$CE,$DF,$FE,$1D,$ED,$E5,$DB,$DB,$FB,$BF,$BB,$ED,$BF
    FCB $BF,$3B,$E3,$3F,$7F,$FF,$FD,$FF,$FF,$D4,$F9,$F7,$F0,$CC,$C6,$D7
    FCB $F7,$F3,$FF,$BF,$FF,$FF,$FF,$FE,$63,$BF,$9E,$D9,$E7,$9C,$CE,$4F
    FCB $F3,$FF,$FF,$F8,$F9,$6D,$9F,$FF,$9F,$F3,$99,$33,$6C,$ED,$9E,$79
    FCB $F8,$7F,$FF,$CE,$DF,$FF,$2E,$B3,$79,$76,$FB,$FD,$ED,$EF,$DD,$BF
    FCB $FB,$B3,$66,$31,$FC,$DF,$FF,$F7,$FF,$FF,$53,$FF,$FF,$38,$1E,$D7
    FCB $FF,$FF,$FD,$FF,$FF,$FF,$FF,$F2,$5D,$FC,$F6,$CE,$1F,$F2,$7C,$3F
    FCB $3F,$EF,$E7,$E3,$FC,$B6,$CE,$FD,$F2,$7E,$4E,$64,$CD,$B3,$E6,$FC
    FCB $BF,$E7,$0F,$FF,$CB,$7F,$F8,$3A,$D9,$BE,$3B,$DD,$FE,$FB,$DD,$DE
    FCB $DF,$DF,$FE,$0E,$5B,$FB,$EC,$3F,$FB,$FF,$FF,$14,$FB,$FD,$FC,$E0
    FCB $AF,$6B,$FF,$FF,$FE,$FF,$FF,$FF,$FF,$F9,$1E,$BC,$D4,$FD,$9E,$7F
    FCB $C9,$F0,$CF,$FF,$BF,$9F,$CF,$78,$DB,$3B,$FF,$3F,$C9,$CC,$99,$B9
    FCB $EE,$77,$65,$FC,$27,$3F,$FF,$2D,$FD,$EE,$2A,$DB,$07,$7B,$BB,$9F
    FCB $7B,$EE,$ED,$EF,$7F,$7F,$FF,$FF,$9D,$FF,$FE,$FF,$FF,$C5,$3E,$FF
    FCB $7F,$38,$2B,$DA,$FF,$FF,$FF,$BF,$FF,$FF,$FF,$FE,$7D,$FF,$CF,$E7
    FCB $F9,$9C,$9F,$9F,$FB,$F9,$FE,$7B,$1B,$73,$BF,$F9,$FC,$E4,$E1,$CB
    FCB $9C,$79,$6F,$DF,$C3,$93,$FF,$F2,$DF,$F7,$83,$B6,$5D,$FB,$BF,$FB
    FCB $F7,$76,$F7,$1F,$DF,$BF,$FF,$F9,$DF,$FF,$EF,$FF,$FE,$A7,$FF,$BF
    FCB $9C,$15,$ED,$FF,$F7,$FF,$DF,$FF,$FF,$FF,$FF,$3E,$F1,$E3,$93,$FF
    FCB $CF,$38,$1F,$9F,$FB,$F8,$73,$37,$2D,$AD,$B3,$BF,$79,$9F,$73,$8A
    FCB $F2,$4F,$3B,$CB,$7E,$FE,$1E,$E7,$0F,$F8,$5F,$7D,$FB,$6F,$BC,$1D
    FCB $EF,$FB,$BF,$76,$BE,$CF,$DF,$BF,$FF,$FD,$F6,$1F,$FD,$FF,$FF,$D4
    FCB $FD,$FF,$F3,$82,$BD,$BF,$FE,$FF,$FB,$FF,$FF,$FF,$FF,$E7,$D7,$2D
    FCB $41,$42,$8F,$47,$A4,$63,$6F,$BF,$FD,$C9,$FE,$47,$B8,$67,$27,$8B
    FCB $EB,$41,$40,$B4,$5D,$BF,$F3,$FB,$CC,$3C,$0C,$79,$8F,$2F,$ED,$FF
    FCB $E1,$C9,$FF,$9F,$77,$BF,$6C,$BB,$FB,$FF,$BD,$FB,$B5,$F7,$F8,$FD
    FCB $FF,$FF,$EF,$C1,$FB,$2F,$8F,$FF,$F8,$FC,$FB,$F9,$E2,$8F,$FB,$7F
    FCB $7F,$FD,$FF,$FF,$FF,$FF,$F3,$EB,$96,$92,$81,$00,$B4,$7A,$91,$92
    FCB $24,$BE,$4F,$BB,$CE,$79,$EF,$3F,$EF,$F7,$D6,$8E,$5A,$24,$15,$D6
    FCB $FD,$F3,$FB,$CC,$2C,$84,$9E,$5B,$CF,$ED,$FF,$E1,$C9,$FF,$FB,$F7
    FCB $97,$6F,$BF,$BF,$7F,$EE,$F7,$6F,$73,$FF,$FF,$7E,$FF,$7E,$0F,$D9
    FCB $79,$1E,$FF,$F8,$FC,$FB,$F9,$C9,$8C,$3D,$BF,$BF,$FE,$FF,$FF,$FF
    FCB $FE,$7F,$F7,$1D,$08,$08,$C9,$21,$18,$8C,$29,$47,$6C,$F3,$FF,$F1
    FCB $FE,$DC,$FF,$FC,$BE,$8A,$D6,$89,$05,$05,$6E,$77,$2F,$EF,$18,$0C
    FCB $E4,$F2,$47,$CF,$DB,$F7,$F0,$E4,$FF,$CD,$DF,$7E,$EF,$BD,$FD,$FF
    FCB $7B,$FB,$DD,$FF,$FF,$FD,$FB,$FD,$F8,$3C,$BF,$97,$DF,$FF,$1F,$FF
    FCB $F9,$C9,$C8,$C7,$BF,$BF,$FE,$FF,$FF,$FF,$FE,$7D,$8F,$FD,$08,$0A
    FCB $10,$88,$45,$A3,$28,$48,$3F,$F1,$8B,$FF,$E7,$FF,$FF,$F9,$7B,$7D
    FCB $34,$74,$B4,$0A,$7B,$FF,$F3,$EC,$66,$4F,$0E,$F2,$1E,$FF,$7F,$39
    FCB $FC,$F3,$6F,$BB,$EF,$7D,$8F,$EF,$EF,$FB,$BD,$BF,$2F,$FF,$E7,$BD
    FCB $BF,$BF,$3F,$FF,$BF,$FF,$C7,$97,$BC,$F9,$CA,$BE,$C7,$DF,$FF,$FD
    FCB $FF,$FF,$FF,$FC,$FF,$EF,$D1,$81,$45,$25,$09,$24,$99,$52,$32,$8F
    FCB $FC,$FF,$FF,$F3,$FF,$BF,$FE,$3C,$41,$5B,$41,$41,$5A,$0B,$FF,$FE
    FCB $6C,$E4,$9C,$C7,$19,$FB,$3F,$FF,$3F,$23,$E6,$DB,$EE,$FB,$F7,$FF
    FCB $DF,$DF,$BD,$DB,$EC,$FF,$ED,$CF,$EC,$3D,$AF,$FF,$0F,$BE,$E0,$FB
    FCB $F8,$FD,$97,$9F,$39,$39,$DF,$7F,$FF,$F7,$FF,$FF,$FF,$F3,$EF,$EF
    FCB $D1,$94,$28,$12,$56,$21,$ED,$0A,$10,$9D,$9F,$FF,$E7,$DF,$B9,$FE
    FCB $CF,$BF,$BE,$9A,$0A,$39,$68,$9E,$DF,$23,$F7,$39,$21,$9B,$67,$3E
    FCB $CF,$FD,$B9,$86,$7E,$C1,$BB,$96,$F7,$77,$FF,$FB,$FB,$F7,$BB,$7D
    FCB $98,$FF,$B6,$7F,$CB,$2D,$FE,$FC,$3E,$FD,$FC,$DF,$1F,$FF,$F9,$99
    FCB $9D,$FB,$FF,$FF,$BF,$FF,$F9,$FF,$FF,$7F,$FA,$3D,$42,$51,$47,$E9
    FCB $24,$B5,$14,$60,$E7,$FF,$E3,$D9,$D9,$FF,$FF,$B9,$F7,$ED,$05,$A6
    FCB $82,$9D,$3B,$EF,$F7,$3C,$C0,$9B,$67,$3E,$CF,$FD,$B3,$84,$FE,$C1
    FCB $DB,$ED,$FB,$BF,$FF,$EF,$B7,$FD,$DB,$F3,$BF,$ED,$9F,$EC,$25,$DF
    FCB $FF,$FF,$F7,$FF,$71,$FF,$FF,$99,$99,$EF,$BF,$FF,$FB,$FF,$FF,$9F
    FCB $FF,$F7,$F7,$C4,$7A,$54,$8A,$8C,$EC,$46,$DA,$D1,$92,$24,$CF,$FC
    FCB $7E,$F9,$FF,$FF,$FD,$FE,$E9,$ED,$12,$0A,$0A,$DD,$8C,$BE,$E7,$21
    FCB $33,$6C,$FF,$CF,$B9,$CF,$E7,$F6,$17,$7B,$77,$DF,$B3,$FB,$EF,$B7
    FCB $EF,$7F,$DF,$B3,$ED,$9F,$EC,$3E,$FF,$FF,$FF,$FE,$FE,$2F,$FF,$FC
    FCB $9F,$98,$FD,$FF,$FF,$DF,$FF,$FC,$FF,$FF,$BF,$FD,$1E,$A1,$0E,$A2
    FCB $3E,$31,$2D,$24,$C4,$7E,$1F,$9F,$FF,$0F,$6F,$FD,$FE,$FF,$F3,$FA
    FCB $39,$5A,$24,$15,$D7,$73,$FE,$49,$31,$FF,$F9,$F9,$FF,$CF,$F8,$3B
    FCB $7D,$B7,$DE,$FC,$3B,$EE,$F6,$FD,$EF,$FB,$7E,$0F,$1B,$FF,$C3,$7B
    FCB $1F,$FC,$E5,$DF,$CB,$FF,$5F,$FE,$C6,$67,$D5,$FF,$DF,$FF,$FD,$FF
    FCB $FF,$CE,$6F,$FF,$7F,$FA,$3D,$4A,$4B,$50,$7F,$EC,$43,$4E,$29,$18
    FCB $F3,$FF,$E7,$FF,$F3,$E7,$FF,$E5,$F4,$1D,$68,$90,$50,$56,$F9,$E3
    FCB $CC,$98,$FF,$FC,$E7,$F6,$79,$F3,$CD,$BE,$ED,$EE,$FC,$FE,$F7,$7B
    FCB $BE,$F7,$FF,$F6,$F6,$7F,$FF,$FE,$CF,$FF,$FF,$FF,$B1,$AF,$FF,$06
    FCB $7F,$9F,$3E,$FF,$FF,$EF,$FF,$FE,$73,$65,$FF,$7F,$FA,$3D,$49,$2A
    FCB $28,$FF,$FD,$24,$B5,$B4,$7A,$B0,$CF,$B9,$67,$FF,$FF,$FF,$FF,$FD
    FCB $BC,$6B,$47,$2B,$41,$44,$EF,$9E,$43,$C7,$FF,$E6,$7C,$FE,$1F,$FF
    FCB $BE,$DB,$6D,$DE,$79,$2E,$FB,$BA,$F7,$FB,$FF,$F6,$FC,$FB,$FF,$FF
    FCB $FE,$7D,$FC,$3E,$C7,$DA,$DF,$FE,$79,$F3,$FF,$FF,$FF,$EF,$FF,$FE
    FCB $73,$EF,$FB,$FF,$D0,$09,$24,$A2,$7F,$FF,$AB,$52,$93,$48,$A1,$57
    FCB $9D,$E3,$3F,$FF,$FF,$FF,$FF,$FF,$62,$26,$D3,$40,$AD,$06,$E4,$72
    FCB $78,$DC,$FF,$CC,$C9,$DF,$87,$3D,$FF,$B6,$DB,$76,$F3,$99,$B7,$76
    FCB $FD,$ED,$F9,$BF,$F6,$FC,$3F,$F6,$FF,$F0,$FF,$EF,$FE,$4D,$EB,$5B
    FCB $E7,$E7,$FE,$7F,$FF,$FF,$FD,$FF,$FF,$CF,$C7,$F8,$EF,$FF,$40,$24
    FCB $84,$27,$FF,$FE,$EA,$42,$E2,$D1,$92,$03,$8D,$C6,$7F,$FF,$FF,$FF
    FCB $FF,$FF,$6F,$D1,$23,$95,$A0,$AE,$3E,$4F,$1F,$E7,$F3,$93,$3F,$F1
    FCB $BF,$FB,$ED,$AE,$37,$DE,$43,$6E,$DD,$EF,$BF,$DF,$CD,$ED,$F8,$7E
    FCB $3D,$BF,$9F,$E4,$7B,$FF,$E6,$77,$5A,$DF,$E6,$7F,$FF,$CC,$EF,$FF
    FCB $FD,$FF,$FF,$CF,$9F,$78,$FC,$77,$E8,$ED,$24,$21,$FF,$8E,$7D,$FA
    FCB $5A,$4B,$A3,$14,$B1,$D9,$3F,$FF,$FF,$FF,$FF,$70,$EF,$DE,$20,$B6
    FCB $89,$05,$A6,$E7,$E5,$FE,$7F,$30,$3B,$67,$FF,$F0,$FD,$B6,$F5,$BD
    FCB $B9,$9B,$B8,$EF,$5F,$EF,$BF,$9D,$DF,$FC,$DF,$66,$31,$FC,$FF,$ED
    FCB $F8,$7C,$FB,$45,$EF,$33,$FF,$FE,$73,$63,$37,$FF,$BF,$FF,$F9,$F3
    FCB $EE,$5D,$CF,$F4,$76,$92,$19,$3F,$FF,$EF,$F8,$84,$4C,$A4,$84,$3C
    FCB $CE,$37,$FF,$FF,$FF,$FD,$9C,$7F,$EB,$EB,$4D,$02,$B4,$4F,$79,$FF
    FCB $3F,$90,$38,$DF,$FE,$7E,$4B,$BB,$6B,$DB,$79,$F7,$BC,$6F,$BF,$B7
    FCB $FF,$7F,$BE,$F3,$FF,$FC,$F3,$1E,$FF,$FF,$93,$EB,$45,$7F,$33,$FF
    FCB $BF,$AB,$9F,$7F,$FF,$7F,$FC,$FF,$E7,$D9,$FF,$BE,$23,$B4,$92,$93
    FCB $FE,$3F,$DF,$FD,$24,$B5,$B4,$64,$82,$6D,$9F,$CF,$FF,$FF,$FF,$FF
    FCB $F7,$BF,$68,$16,$D0,$57,$5B,$3F,$9F,$E7,$0E,$67,$DF,$BF,$0F,$C6
    FCB $DB,$75,$BB,$3F,$77,$7D,$FF,$B5,$F8,$5F,$FB,$FD,$FC,$FF,$EE,$7F
    FCB $FF,$F9,$FC,$F6,$83,$BF,$33,$FF,$BF,$AB,$9E,$FF,$FF,$7F,$FC,$FF
    FCB $E7,$2F,$FF,$FA,$91,$DA,$94,$7E,$7B,$3B,$9E,$FF,$96,$92,$93,$01
    FCB $19,$53,$E3,$FF,$E1,$ED,$9B,$E3,$FB,$FB,$6F,$B6,$DA,$ED,$68,$2F
    FCB $07,$F7,$3F,$F3,$87,$33,$EC,$BF,$CF,$FB,$6B,$8D,$B7,$FE,$EF,$77
    FCB $FE,$D7,$FF,$FF,$F8,$3E,$D9,$FF,$E7,$FF,$FF,$FE,$4F,$68,$1D,$CC
    FCB $FF,$FD,$FD,$5C,$FB,$F9,$BF,$7F,$FC,$FF,$FC,$FF,$3C,$F5,$20,$04
    FCB $BF,$3F,$7F,$3F,$7F,$DB,$52,$1C,$4D,$24,$69,$FF,$DF,$FD,$FE,$DB
    FCB $DB,$EE,$DE,$EE,$DB,$6D,$EF,$45,$A3,$25,$7C,$BF,$CF,$F2,$73,$CD
    FCB $FF,$F3,$FD,$B6,$ED,$AE,$0F,$6D,$EF,$7E,$77,$FF,$F7,$FF,$EF,$E6
    FCB $6F,$E6,$6F,$C3,$76,$CF,$F8,$7D,$68,$1D,$F9,$9F,$7F,$FD,$53,$F7
    FCB $FF,$FB,$FF,$E7,$FF,$CE,$7F,$EA,$F4,$91,$E0,$79,$FF,$FE,$FE,$3F
    FCB $BD,$26,$D2,$5B,$21,$CE,$37,$EE,$F7,$77,$BE,$EE,$FB,$7F,$FD,$FD
    FCB $3D,$1E,$AA,$F3,$0F,$B1,$8D,$93,$33,$CF,$FF,$FE,$3F,$6E,$2D,$B7
    FCB $BD,$DE,$FF,$B7,$FF,$FF,$FD,$FF,$E1,$97,$F3,$C6,$FF,$FF,$FF,$0F
    FCB $AD,$1C,$FD,$9C,$FB,$FF,$EA,$CF,$73,$7F,$FB,$FF,$E7,$FF,$9E,$7F
    FCB $EA,$E2,$48,$F2,$79,$FF,$FE,$FB,$85,$FB,$D6,$C5,$26,$9B,$64,$EF
    FCB $FF,$FF,$FF,$CF,$FD,$B3,$F7,$A2,$04,$79,$6C,$F9,$E7,$FE,$4F,$9F
    FCB $FB,$CF,$F1,$DB,$8D,$6D,$F7,$6D,$F9,$7E,$FE,$7F,$1D,$B9,$9F,$FD
    FCB $B9,$87,$F8,$EC,$F2,$FF,$FC,$DF,$DA,$3A,$DF,$99,$F7,$F3,$E7,$FF
    FCB $FD,$FF,$FF,$D5,$F7,$19,$B3,$9F,$3D,$59,$49,$1F,$83,$CF,$FF,$FF
    FCB $F7,$FB,$AD,$75,$BB,$FE,$7F,$FF,$F9,$BF,$39,$BC,$BF,$7D,$D1,$09
    FCB $23,$79,$9F,$FF,$F1,$BC,$87,$D9,$FF,$9F,$77,$71,$6D,$78,$DF,$6F
    FCB $B7,$FF,$9E,$3F,$FE,$7F,$FB,$3C,$FF,$FF,$FE,$FF,$F9,$CB,$47,$1D
    FCB $DC,$FF,$9F,$FC,$FF,$FF,$BF,$FE,$7C,$FB,$FC,$F3,$E7,$12,$B8,$85
    FCB $1B,$CF,$FF,$FF,$FE,$FF,$74,$D7,$5B,$B9,$61,$FF,$FF,$9C,$B6,$33
    FCB $FF,$FF,$7B,$D1,$08,$C8,$7B,$9F,$97,$F3,$FE,$7C,$CF,$FF,$FB,$BB
    FCB $8B,$6D,$C7,$7B,$F6,$FC,$FB,$CF,$F3,$FF,$FF,$67,$FE,$7F,$F7,$FF
    FCB $FF,$FD,$A3,$8F,$DC,$CF,$FF,$F9,$FF,$FF,$7F,$FC,$F9,$FF,$D9,$E7
    FCB $CF,$4B,$A9,$24,$6E,$7F,$FF,$FF,$FD,$FE,$D3,$5D,$39,$FF,$FF,$FF
    FCB $39,$7B,$3F,$FF,$F7,$B8,$89,$48,$F5,$76,$7B,$9F,$F3,$EC,$F9,$E7
    FCB $FF,$FD,$ED,$C6,$B6,$FB,$FF,$6F,$CF,$3F,$FF,$FE,$5F,$F6,$7F,$FF
    FCB $FF,$67,$BF,$FF,$FA,$38,$FB,$F9,$FF,$FF,$FF,$FF,$FF,$FC,$F9,$8E
    FCB $F9,$FC,$F9,$E9,$46,$92,$91,$B3,$FF,$FF,$FF,$F7,$FB,$4D,$74,$E7
    FCB $FF,$CF,$FC,$79,$7F,$FF,$FC,$7B,$DD,$48,$84,$7A,$BB,$CC,$FB,$CF
    FCB $FE,$67,$DC,$FF,$F7,$9B,$7B,$6D,$EF,$DF,$FF,$E7,$FF,$FF,$FF,$FF
    FCB $FF,$FF,$FB,$F8,$FD,$FF,$FA,$38,$FB,$F9,$FF,$FF,$FF,$FF,$FF,$FC
    FCB $F9,$F7,$CF,$E7,$F3,$43,$D4,$A4,$24,$FF,$FF,$FF,$FE,$FB,$D3,$5B
    FCB $5C,$FF,$F9,$FF,$D9,$FF,$FF,$FC,$7B,$D8,$92,$25,$23,$1D,$67,$9C
    FCB $BF,$9F,$67,$E7,$3F,$FB,$EF,$DB,$8D,$BE,$FD,$FF,$FF,$3F,$BF,$97
    FCB $2F,$FF,$FE,$6F,$FD,$FF,$DC,$FB,$FF,$BD,$1D,$7F,$FF,$FF,$FF,$FF
    FCB $FF,$FF,$E7,$F9,$DE,$7F,$3E,$65,$0B,$D2,$10,$93,$FF,$FF,$9B,$FE
    FCB $FF,$69,$AD,$AC,$FF,$FF,$90,$BD,$B3,$FF,$FF,$FA,$97,$BB,$D1,$E8
    FCB $84,$33,$FD,$CE,$72,$FE,$7D,$9E,$7F,$F7,$BF,$77,$1B,$BF,$EF,$FF
    FCB $FE,$CD,$CF,$FF,$FB,$FF,$E3,$1F,$FB,$EE,$7F,$F7,$FF,$C4,$71,$F7
    FCB $FF,$FF,$FF,$FF,$3B,$FF,$FE,$63,$C6,$7F,$FE,$7C,$F4,$32,$90,$87
    FCB $3F,$FF,$FF,$FF,$7F,$74,$D6,$B6,$7F,$9F,$79,$FB,$CF,$FF,$FF,$E3
    FCB $D7,$71,$00,$98,$97,$B9,$CF,$B3,$CF,$B9,$FF,$3E,$FE,$3F,$77,$7D
    FCB $BF,$FF,$FB,$E7,$BF,$97,$37,$FF,$BF,$FB,$9F,$7F,$37,$BF,$FF,$FE
    FCB $CC,$47,$1F,$7F,$FF,$FF,$FF,$E6,$5F,$7F,$FC,$CF,$FF,$FF,$3E,$7A
    FCB $19,$48,$43,$99,$F7,$FF,$FE,$F2,$FD,$E9,$AD,$6C,$FF,$39,$BC,$BF
    FCB $FF,$FF,$3B,$DE,$6D,$7D,$48,$04,$C5,$4F,$F7,$39,$FF,$D9,$FF,$FF
    FCB $DF,$FD,$EF,$BE,$FB,$9F,$FF,$F7,$F2,$FF,$EF,$B9,$FF,$DF,$FD,$CF
    FCB $FF,$FB,$EF,$FD,$1D,$7F,$FF,$FF,$FF,$E6,$77,$EF,$E7,$36,$7F,$FF
    FCB $FC,$FF,$D1,$80,$50,$94,$C2,$FB,$FF,$FF,$9B,$DF,$74,$D6,$9C,$FF
    FCB $31,$FC,$BF,$FF,$F3,$EE,$3F,$ED,$7D,$24,$02,$62,$BD,$9E,$7D,$E7
    FCB $EF,$9F,$F2,$FF,$FB,$EF,$BE,$FF,$FB,$FF,$FF,$DF,$FB,$F8,$FD,$FF
    FCB $FF,$FF,$2F,$FE,$FF,$EF,$FD,$1D,$7F,$FF,$FF,$F9,$FC,$BF,$FF,$C6
    FCB $7F,$FF,$FF,$E7,$FE,$8C,$02,$54,$B9,$3E,$FF,$FF,$FE,$FE,$DA,$6B
    FCB $5C,$FF,$E4,$DC,$7F,$FF,$F9,$E3,$1E,$FD,$AF,$A3,$D1,$93,$87,$3F
    FCB $FB,$CF,$63,$9F,$FD,$FF,$BF,$FE,$FD,$FF,$F7,$FF,$7D,$CF,$BF,$97
    FCB $DF,$FF,$FF,$FF,$CB,$FC,$77,$FF,$7F,$E8,$EB,$FF,$FF,$FF,$CF,$E5
    FCB $F2,$EE,$73,$E7,$FF,$7F,$FC,$FF,$D1,$E5,$20,$56,$67,$DF,$FF,$FF
    FCB $DF,$DB,$4D,$6B,$9F,$E7,$0D,$ED,$9F,$FF,$DF,$CA,$97,$FD,$A7,$88
    FCB $04,$2B,$9E,$7F,$FF,$FF,$7F,$FE,$C7,$FF,$DF,$FD,$FF,$7F,$EF,$B9
    FCB $F7,$F2,$FB,$FF,$FF,$FF,$D9,$FB,$EC,$EC,$97,$FD,$FF,$D1,$D7,$FF
    FCB $FF,$FF,$9F,$8C,$79,$7C,$FF,$CF,$FF,$FB,$FF,$E7,$A3,$CA,$12,$AC
    FCB $CC,$B7,$FF,$FF,$F7,$F6,$B4,$4B,$72,$7E,$79,$FB,$CB,$FF,$EB,$D6
    FCB $B4,$92,$12,$5E,$DE,$E9,$E2,$38,$29,$73,$CF,$FE,$FF,$F8,$E3,$BF
    FCB $FF,$7F,$FF,$7F,$F7,$FF,$EF,$BF,$9B,$FF,$7F,$FE,$CF,$FD,$F9,$2D
    FCB $B3,$97,$2F,$E5,$DD,$FC,$A3,$AF,$FF,$FF,$FF,$33,$FF,$BF,$3F,$E7
    FCB $FF,$FD,$FF,$FF,$A3,$D4,$25,$15,$9F,$05,$9F,$7F,$FF,$DD,$F6,$B4
    FCB $D6,$E4,$FF,$97,$B6,$13,$FF,$F1,$35,$A6,$B6,$A4,$94,$85,$FE,$E9
    FCB $E9,$23,$B5,$2F,$FF,$FF,$F7,$FF,$FD,$FF,$FD,$FF,$FF,$7D,$FC,$DE
    FCB $FE,$6F,$C7,$FE,$FF,$FF,$FF,$DF,$73,$FD,$9C,$BF,$67,$77,$F2,$8E
    FCB $BF,$FF,$FF,$FC,$CF,$FE,$F9,$E7,$FF,$FD,$FF,$FF,$FC,$47,$82,$5A
    FCB $44,$FC,$7F,$BF,$FF,$EE,$FB,$4D,$35,$E4,$FC,$C1,$35,$B4,$D6,$24
    FCB $21,$FF,$CE,$D1,$26,$9F,$42,$A4,$8F,$DD,$3D,$19,$01,$59,$CD,$FB
    FCB $FF,$F7,$FF,$F6,$6F,$FF,$FE,$FF,$FE,$FF,$DF,$C7,$FF,$FE,$FE,$7F
    FCB $F7,$FB,$EE,$7F,$B3,$FC,$B7,$DF,$F2,$8E,$BF,$FF,$FF,$FE,$7F,$E7
    FCB $FF,$3E,$FF,$FF,$FF,$FF,$CA,$01,$42,$59,$39,$B6,$AF,$FF,$FF,$BD
    FCB $6F,$69,$A6,$E6,$7F,$E2,$25,$A6,$B1,$A4,$A4,$26,$7D,$FA,$D3,$5A
    FCB $F5,$21,$52,$BF,$7A,$7A,$01,$1A,$BF,$FB,$E3,$FF,$DF,$FF,$FF,$F7
    FCB $FF,$EF,$F1,$FF,$FF,$BF,$FF,$FF,$FF,$F8,$FF,$ED,$F7,$39,$ED,$FF
    FCB $97,$EF,$F8,$23,$AF,$7F,$FF,$FF,$E7,$FE,$7F,$F3,$EF,$FF,$9F,$7F
    FCB $E3,$E6,$80,$52,$95,$15,$FF,$FF,$FF,$F7,$B1,$B7,$AD,$69,$B9,$87
    FCB $DF,$68,$96,$99,$68,$54,$84,$FF,$7C,$44,$B5,$BA,$92,$42,$A7,$1B
    FCB $DE,$8A,$20,$12,$BF,$FF,$BF,$FE,$FF,$FF,$FF,$7F,$1F,$BF,$9F,$FF
    FCB $FE,$FF,$FF,$FF,$9D,$FF,$EC,$7E,$FE,$7F,$B7,$FF,$FD,$FF,$04,$75
    FCB $EF,$FF,$FE,$E7,$3F,$F9,$F3,$FF,$BF,$FE,$7D,$8C,$7C,$FF,$47,$6A
    FCB $4A,$07,$FF,$FF,$FF,$DF,$75,$BD,$6B,$5B,$C8,$7B,$7D,$A6,$B4,$C8
    FCB $85,$49,$7F,$DF,$A6,$DB,$52,$16,$90,$E3,$7B,$D3,$88,$05,$57,$FF
    FCB $F7,$FF,$DF,$FF,$FF,$EF,$E6,$FF,$F3,$FF,$FF,$7F,$DB,$9F,$FF,$85
    FCB $F8,$E5,$DF,$BC,$FF,$ED,$FF,$F2,$FB,$F8,$23,$A8,$FF,$BF,$F9,$7F
    FCB $3F,$F9,$F3,$FF,$BF,$E7,$FF,$FF,$C9,$A3,$B1,$50,$3F,$FC,$FB,$FF
    FCB $DF,$B5,$BD,$36,$DC,$E7,$B7,$D6,$B6,$E2,$49,$1F,$FF,$DE,$24,$B7
    FCB $EC,$EF,$45,$52,$3C,$BF,$DE,$C9,$63,$FF,$DF,$FF,$9B,$FF,$DF,$C7
    FCB $97,$9F,$FF,$97,$37,$EC,$EF,$E7,$7F,$F1,$FF,$7F,$3F,$FF,$7D,$FF
    FCB $7F,$7C,$11,$CE,$5F,$7F,$FF,$67,$9F,$FC,$FC,$FF,$FF,$FC,$FB,$3F
    FCB $E2,$B8,$80,$92,$4F,$8F,$9F,$FD,$FB,$F6,$B7,$6B,$6D,$CF,$F7,$EB
    FCB $6D,$88,$CD,$43,$FF,$FE,$4B,$1D,$FE,$F4,$54,$91,$B7,$FF,$FF,$EF
    FCB $BF,$8E,$3C,$FF,$EF,$FF,$7F,$CE,$71,$BF,$3E,$FE,$7D,$FC,$BE,$F6
    FCB $4F,$7C,$7F,$F1,$EF,$3D,$F2,$FF,$7D,$EF,$52,$06,$7F,$BF,$8E,$6F
    FCB $E7,$FF,$9E,$7F,$FF,$2F,$FF,$9F,$CC,$38,$80,$E4,$9F,$F7,$96,$47
    FCB $FE,$FD,$AD,$DA,$76,$E7,$FC,$F6,$D2,$62,$CF,$FE,$7E,$71,$B7,$FB
    FCB $D1,$50,$A5,$BF,$FF,$FF,$7F,$FF,$FE,$7D,$BF,$EC,$C7,$3F,$F2,$37
    FCB $FF,$FE,$77,$7F,$0B,$FF,$BE,$F8,$F7,$9F,$77,$9C,$7C,$F7,$7F,$1E
    FCB $EA,$45,$EF,$FF,$FF,$CF,$FF,$CE,$5F,$CF,$FE,$F3,$B3,$FE,$AF,$56
    FCB $68,$FE,$49,$FF,$79,$F6,$33,$EF,$DA,$DD,$A7,$6E,$7F,$87,$1B,$FF
    FCB $FF,$0F,$F8,$DB,$FB,$C4,$54,$26,$FF,$FF,$FF,$DF,$79,$E6,$CF,$FB
    FCB $FF,$F3,$7B,$3C,$CC,$7F,$1B,$DC,$EE,$B7,$DA,$8C,$BF,$F7,$EC,$7C
    FCB $E7,$77,$3F,$78,$FF,$7F,$DE,$92,$2F,$FF,$FF,$2F,$E7,$DE,$67,$FC
    FCB $BF,$FE,$7D,$E7,$FA,$BD,$5F,$47,$F2,$4F,$3F,$C7,$FD,$FB,$DE,$B7
    FCB $5A,$ED,$CF,$FF,$3F,$FF,$3F,$F1,$FB,$FE,$F1,$05,$A1,$3F,$FF,$FF
    FCB $F9,$BF,$E7,$8D,$F7,$3F,$FF,$EF,$E6,$6C,$FF,$FD,$FB,$BD,$E1,$9F
    FCB $EE,$F6,$F6,$07,$F7,$E7,$EF,$FE,$EF,$FE,$92,$7B,$CF,$7F,$FF,$3F
    FCB $E7,$DE,$7F,$9F,$F2,$FF,$FF,$33,$B5,$12,$D1,$FC,$93,$CF,$FF,$FB
    FCB $F7,$DD,$35,$D6,$BE,$79,$F7,$9F,$FF,$3F,$3E,$FD,$FD,$DE,$A4,$E9
    FCB $77,$CD,$F7,$3F,$FF,$CF,$BF,$9F,$6F,$E7,$DF,$F7,$C9,$2F,$FF,$FF
    FCB $77,$EF,$93,$FE,$F7,$FF,$FF,$BC,$FE,$F7,$98,$FD,$F7,$49,$7F,$FF
    FCB $97,$FF,$3F,$9F,$FF,$F6,$7F,$E7,$DC,$67,$F3,$D5,$ED,$1E,$30,$3F
    FCB $3F,$31,$FF,$7E,$FB,$A6,$BA,$6F,$9E,$7D,$9F,$FF,$F8,$E1,$FF,$B7
    FCB $EE,$F5,$22,$A5,$FF,$FE,$FF,$F9,$FF,$DF,$87,$EF,$B6,$7F,$66,$FF
    FCB $39,$F7,$FF,$F7,$7F,$F9,$9B,$2E,$FF,$EF,$E6,$FC,$FB,$EF,$9B,$B2
    FCB $77,$52,$CF,$FF,$FE,$5F,$CF,$FE,$CF,$F8,$7B,$67,$FF,$FF,$E6,$35
    FCB $63,$5A,$3C,$27,$39,$8F,$3D,$B2,$E7,$DF,$75,$B6,$9E,$DE,$7F,$E7
    FCB $F8,$7B,$7E,$1F,$FB,$7E,$EF,$49,$13,$57,$FF,$FF,$FF,$9F,$7F,$B3
    FCB $0B,$EF,$DE,$71,$FF,$EF,$3E,$FF,$F8,$FD,$FF,$9F,$FD,$FD,$FC,$EF
    FCB $FF,$3D,$FF,$FF,$7D,$D2,$7C,$FB,$67,$9F,$73,$FF,$FF,$E7,$D9,$FF
    FCB $FF,$FF,$F9,$FD,$68,$03,$2A,$27,$FC,$FF,$EF,$DE,$F4,$D6,$D3,$FC
    FCB $CF,$B9,$FF,$FF,$E1,$FF,$B7,$DB,$F4,$28,$99,$BC,$F3,$7F,$97,$F3
    FCB $EF,$E3,$92,$FB,$7F,$31,$DF,$FF,$FF,$FF,$FF,$FF,$FE,$FF,$FF,$7F
    FCB $F7,$FC,$E5,$DF,$3F,$FB,$EE,$A7,$3F,$CF,$B3,$FF,$FF,$E7,$E7,$1B
    FCB $FF,$FF,$FF,$C7,$67,$9E,$8C,$56,$52,$20,$CF,$CF,$FE,$FD,$EF,$4D
    FCB $6B,$5F,$9E,$78,$F2,$FE,$FD,$32,$A3,$0F,$FD,$BD,$DF,$12,$4F,$ED
    FCB $CE,$3F,$FD,$9F,$EC,$3D,$FF,$F1,$DE,$E7,$EE,$7F,$FF,$DF,$CF,$FF
    FCB $FC,$EE,$FF,$EF,$73,$97,$DF,$CE,$6E,$CB,$F9,$F7,$BD,$5F,$FF,$3F
    FCB $FF,$F1,$D9,$FF,$9F,$FF,$E7,$DF,$EF,$3F,$FE,$A3,$6D,$1E,$A3,$0F
    FCB $CF,$BF,$FD,$EF,$4D,$6B,$5C,$EC,$CF,$B3,$FE,$B7,$A6,$D4,$09,$61
    FCB $F7,$EF,$63,$7C,$49,$13,$FE,$71,$FF,$F9,$7F,$FF,$7F,$FF,$7C,$FB
    FCB $F8,$5E,$CF,$F7,$FE,$5F,$CE,$E0,$6E,$DB,$F9,$7D,$CF,$BE,$3F,$E7
    FCB $FB,$F9,$DD,$FD,$5C,$FF,$FF,$37,$FF,$FF,$FC,$FF,$FF,$CB,$FF,$79
    FCB $FF,$F0,$F4,$7A,$97,$05,$7E,$7F,$F7,$EF,$7A,$6B,$4D,$CD,$99,$F7
    FCB $9F,$E9,$BA,$D7,$56,$92,$98,$7F,$FE,$EB,$EA,$52,$6F,$F3,$C7,$FF
    FCB $E3,$DF,$CB,$97,$BF,$9E,$FF,$FF,$9F,$7C,$FB,$FF,$FF,$3B,$C0,$ED
    FCB $AF,$E5,$F7,$9F,$6E,$63,$F9,$8F,$BF,$97,$F7,$EA,$F3,$FC,$DF,$FF
    FCB $FF,$FF,$CF,$3E,$F9,$BF,$FB,$F3,$FF,$F3,$D0,$EB,$28,$CA,$3F,$F3
    FCB $DB,$E6,$DD,$A6,$B5,$BF,$9F,$E1,$8D,$B3,$A2,$5A,$D7,$A4,$44,$A1
    FCB $FF,$F7,$AF,$A9,$49,$FE,$CF,$BF,$FF,$FF,$73,$FF,$BE,$77,$FF,$FC
    FCB $FB,$FF,$F7,$3F,$37,$1F,$C3,$DB,$7F,$EF,$31,$FD,$FF,$F3,$FB,$F9
    FCB $6F,$FE,$AF,$3E,$CF,$FF,$FF,$FF,$F8,$7F,$ED,$E7,$F9,$63,$B9,$FF
    FCB $FC,$F5,$6D,$D1,$EA,$57,$3F,$FA,$F0,$95,$BB,$44,$B4,$F9,$3F,$E7
    FCB $2B,$F6,$B6,$9C,$14,$12,$7F,$FE,$F5,$F4,$85,$FF,$8E,$DF,$FF,$FF
    FCB $7F,$FF,$C6,$76,$3F,$FF,$F8,$FB,$F9,$BF,$3C,$F7,$FB,$99,$7E,$E7
    FCB $BD,$CB,$FB,$FF,$D9,$9F,$B9,$1D,$EC,$F5,$1F,$FB,$3F,$FF,$FF,$FF
    FCB $F2,$39,$F6,$F9,$FF,$FF,$FF,$FC,$F3,$B6,$8F,$21,$50,$3F,$F4,$D7
    FCB $A6,$8F,$14,$D3,$B4,$D6,$9F,$27,$FC,$38,$DF,$1E,$65,$DF,$FF,$F7
    FCB $D6,$E2,$85,$9F,$FB,$EE,$72,$DF,$C7,$EF,$FF,$DC,$FF,$FF,$FF,$F7
    FCB $F8,$F3,$F2,$FF,$EF,$CF,$DF,$71,$E6,$3B,$DF,$B9,$BC,$93,$EF,$BF
    FCB $9F,$0F,$F2,$FF,$FF,$FF,$FE,$79,$8E,$DF,$CF,$B3,$FF,$EC,$FF,$F9
    FCB $D9,$F4,$AE,$08,$CA,$F7,$F4,$4B,$B4,$14,$92,$52,$B5,$AD,$6B,$F9
    FCB $FF,$0F,$6E,$4D,$F2,$CD,$FB,$0F,$5B,$F5,$B8,$A1,$66,$C3,$ED,$DE
    FCB $1C,$FD,$F7,$BF,$EF,$F3,$FF,$FF,$FF,$DD,$F9,$86,$6C,$7B,$FD,$FF
    FCB $FF,$BF,$D9,$7F,$C7,$9B,$CE,$7D,$FF,$3B,$F3,$F3,$FE,$31,$97,$B3
    FCB $FF,$FF,$08,$ED,$FF,$FE,$7F,$97,$2F,$FF,$9D,$9F,$3B,$A3,$D4,$1F
    FCB $E8,$29,$B4,$16,$A4,$65,$24,$53,$44,$DF,$27,$FC,$23,$FC,$EF,$BC
    FCB $CB,$DB,$F7,$ED,$6C,$15,$67,$B6,$7D,$F0,$C0,$CB,$7B,$B6,$FB,$FF
    FCB $9F,$FF,$FF,$FF,$6F,$D8,$73,$FF,$DF,$DF,$3F,$72,$FB,$9F,$6E,$65
    FCB $F6,$7E,$71,$FB,$CE,$FC,$3C,$FE,$5F,$FF,$DE,$7B,$3F,$CF,$BF,$FC
    FCB $FB,$25,$D9,$FF,$FF,$F0,$7F,$ED,$18,$85,$47,$A0,$A6,$D0,$2D,$24
    FCB $2A,$43,$6B,$4D,$BF,$9C,$FF,$F3,$18,$F8,$F7,$FF,$FB,$F6,$B6,$00
    FCB $BF,$CC,$DB,$EA,$54,$05,$1E,$B5,$B6,$EB,$7B,$FF,$9F,$FF,$FF,$FF
    FCB $BB,$FF,$3E,$3C,$FB,$DF,$9B,$BF,$FF,$EF,$CF,$F3,$EF,$31,$E7,$7D
    FCB $D9,$87,$E7,$1C,$7F,$FF,$7F,$F3,$FF,$FF,$FF,$FC,$DE,$7F,$FF,$9F
    FCB $EE,$7D,$0E,$C1,$0A,$4E,$34,$14,$C4,$14,$D0,$A4,$A4,$AD,$34,$D7
    FCB $F9,$CF,$FF,$FC,$FB,$1F,$FF,$EF,$B1,$37,$23,$CF,$FF,$D2,$50,$41
    FCB $5E,$9A,$6D,$ED,$BD,$F1,$9F,$FF,$FF,$DF,$9F,$7D,$FF,$F2,$E6,$6F
    FCB $79,$2D,$BF,$DE,$63,$3D,$CF,$8F,$2F,$FF,$9B,$BE,$3C,$CF,$39,$DF
    FCB $7F,$07,$DF,$FC,$FF,$FF,$FF,$FF,$3F,$FF,$79,$FF,$9B,$F1,$8A,$ED
    FCB $A3,$D4,$74,$4B,$AD,$62,$42,$56,$9A,$6F,$19,$8E,$E7,$3F,$FF,$FF
    FCB $FF,$FB,$7E,$9C,$C7,$CF,$FF,$A9,$28,$0A,$F6,$9A,$EF,$6D,$FF,$F2
    FCB $FF,$EC,$64,$DE,$E7,$EF,$DF,$76,$67,$9C,$F7,$B6,$3B,$8C,$F3,$F2
    FCB $EF,$33,$FD,$FF,$F3,$DD,$DF,$C5,$70,$F6,$C7,$FF,$FF,$FF,$3F,$FF
    FCB $F3,$EF,$F9,$CB,$C6,$6F,$73,$FB,$86,$EC,$E7,$B4,$7A,$9A,$AD,$37
    FCB $4D,$89,$0A,$16,$B4,$DF,$9F,$79,$9F,$7F,$3F,$B3,$7F,$F8,$B7,$35
    FCB $E7,$FF,$FE,$C5,$25,$22,$A5,$D3,$5B,$BD,$FB,$96,$7B,$EF,$FC,$F7
    FCB $E7,$BF,$EF,$7D,$CC,$7C,$C8,$FF,$6D,$B8,$67,$3F,$D9,$9F,$7D,$EF
    FCB $91,$CE,$EF,$7F,$15,$E7,$DF,$FF,$FF,$FE,$7F,$FB,$E6,$7D,$FF,$2F
    FCB $F3,$EE,$72,$FF,$67,$F9,$F4,$22,$6B,$43,$E9,$AD,$0A,$8D,$6D,$35
    FCB $FC,$F3,$EE,$5F,$38,$FD,$8C,$DF,$07,$20,$FB,$BF,$FD,$FF,$EE,$A5
    FCB $49,$FB,$4D,$F9,$ED,$9F,$BB,$F1,$FF,$FF,$38,$FD,$FD,$DD,$E3,$E6
    FCB $7F,$F6,$EE,$19,$CF,$BE,$7B,$3F,$7D,$9D,$D8,$FF,$F7,$89,$79,$F7
    FCB $FF,$FF,$FF,$3F,$CB,$EF,$33,$EF,$C2,$FB,$F2,$6F,$F2,$FF,$FF,$D4
    FCB $6D,$DA,$D1,$08,$50,$A9,$4D,$AA,$ED,$6D,$6F,$E7,$FE,$7D,$B9,$FE
    FCB $CB,$B6,$C4,$2A,$BC,$D8,$FF,$F7,$DF,$F3,$72,$E4,$1C,$6D,$F2,$F3
    FCB $EC,$7B,$BE,$5F,$F3,$EC,$F1,$FB,$FF,$7B,$BF,$CF,$F3,$6F,$87,$FB
    FCB $DE,$4E,$FF,$8F,$1F,$DF,$B3,$F7,$82,$43,$BE,$3F,$FF,$9F,$7F,$CF
    FCB $FD,$CF,$FF,$0B,$EE,$3F,$F9,$FF,$2F,$FF,$FD,$19,$56,$E9,$AD,$AD
    FCB $6D,$08,$85,$5C,$B5,$D6,$BF,$9F,$E3,$FD,$B3,$BB,$BB,$6D,$CA,$84
    FCB $78,$37,$F1,$FF,$1D,$FF,$C9,$6E,$5E,$FF,$6F,$87,$2C,$FB,$DF,$FF
    FCB $BE,$7F,$CD,$EF,$EF,$B9,$7D,$9E,$7F,$DD,$E6,$6F,$EF,$E3,$C7,$D8
    FCB $5C,$DE,$FF,$8C,$07,$8E,$A9,$DF,$8F,$D9,$FF,$FF,$3F,$FB,$CF,$FC
    FCB $67,$DC,$7F,$FF,$FC,$DF,$E7,$EC,$47,$A5,$6C,$AE,$D6,$B5,$D6,$A4
    FCB $85,$5D,$75,$B6,$73,$FC,$B6,$FB,$B7,$B7,$FF,$B0,$47,$AB,$F7,$FF
    FCB $9D,$9F,$9E,$EE,$3E,$5E,$DB,$E7,$20,$3D,$B6,$7F,$7F,$BE,$7F,$FB
    FCB $FD,$FF,$7F,$3F,$FE,$3E,$F2,$F7,$F7,$9F,$EF,$61,$CB,$FE,$5E,$30
    FCB $73,$AB,$BF,$EF,$F3,$FF,$C7,$99,$BF,$BF,$9C,$FB,$FF,$FB,$3F,$FF
    FCB $FF,$F0,$CA,$3C,$DF,$1B,$5A,$0A,$DA,$62,$49,$03,$58,$DB,$39,$ED
    FCB $ED,$B7,$EF,$E6,$7F,$6B,$04,$64,$A7,$B7,$F9,$8E,$E7,$27,$63,$B0
    FCB $7F,$7B,$6E,$E0,$4D,$BF,$9C,$BB,$7F,$7F,$F3,$F7,$DE,$F3,$9D,$F9
    FCB $BC,$F7,$DC,$73,$63,$E5,$F7,$F2,$FF,$9D,$F7,$99,$8C,$6F,$18,$AF
    FCB $FE,$FC,$CD,$FF,$E6,$6F,$FD,$F9,$CF,$BF,$FF,$B3,$FF,$FF,$FF,$E6
    FCB $80,$4B,$C7,$B6,$81,$5A,$69,$E5,$21,$67,$ED,$B7,$BB,$30,$CF,$30
    FCB $CE,$F5,$A6,$C4,$29,$4F,$BE,$C9,$F9,$F3,$3E,$CB,$FB,$B6,$DE,$CF
    FCB $3D,$E0,$1B,$DB,$DF,$7F,$F2,$FD,$F8,$FE,$7F,$EC,$F2,$FF,$DE,$77
    FCB $37,$EF,$C3,$77,$67,$7F,$3F,$6A,$AE,$DC,$C4,$BF,$FD,$F3,$97,$FF
    FCB $F9,$FF,$7F,$99,$FF,$DF,$FF,$FF,$FF,$E7,$DC,$D1,$DA,$53,$EE,$D0
    FCB $28,$93,$4D,$F8,$76,$F7,$E2,$83,$03,$3F,$3B,$1F,$D6,$9B,$14,$95
    FCB $CD,$FF,$24,$B3,$CF,$CB,$EF,$DD,$DE,$FF,$C8,$FA,$A1,$BD,$ED,$DF
    FCB $BF,$E3,$BD,$9F,$CE,$7F,$BF,$CB,$FF,$FE,$E7,$F7,$E1,$D6,$FF,$7C
    FCB $0E,$DE,$57,$6F,$C4,$3F,$F9,$BC,$FB,$3D,$FF,$CD,$9E,$FF,$39,$E3
    FCB $C7,$FB,$FF,$FF,$FF,$9C,$FA,$01,$23,$0B,$B6,$8E,$53,$44,$B7,$5B
    FCB $FD,$C9,$EA,$49,$4A,$E4,$C3,$F2,$F6,$F6,$D3,$75,$28,$5F,$BE,$7E
    FCB $A2,$7E,$FF,$F7,$66,$6D,$DD,$FE,$66,$EA,$86,$BF,$77,$BE,$FF,$3D
    FCB $FF,$3F,$C0,$AE,$ED,$F0,$F7,$FF,$EE,$7F,$76,$13,$6B,$BF,$0C,$0E
    FCB $EB,$ED,$77,$BC,$46,$67,$F9,$B8,$7B,$66,$5B,$FF,$F3,$EF,$E6,$0C
    FCB $FF,$FD,$BF,$FF,$FF,$3B,$93,$E8,$04,$89,$37,$68,$E5,$12,$0A,$ED
    FCB $7F,$D9,$AB,$D2,$42,$92,$BE,$7E,$7D,$ED,$ED,$A7,$D2,$16,$C7,$73
    FCB $EE,$28,$CB,$C7,$BF,$EF,$9F,$7B,$FE,$77,$D5,$CA,$F6,$7D,$BF,$FF
    FCB $8F,$D9,$9D,$C0,$55,$B6,$DB,$7C,$92,$F3,$BD,$BB,$93,$F7,$36,$5A
    FCB $F6,$61,$A8,$36,$EB,$B1,$BB,$7B,$88,$DF,$FF,$B0,$E3,$F2,$DF,$FF
    FCB $CF,$FF,$8A,$79,$7C,$FB,$6F,$FC,$EF,$F3,$EC,$A8,$66,$80,$50,$6F
    FCB $B6,$81,$4D,$02,$DD,$BF,$DC,$86,$29,$0A,$94,$7C,$FF,$FE,$DE,$B4
    FCB $52,$A5,$2D,$DF,$F7,$20,$AF,$BE,$EE,$FF,$CC,$3D,$B7,$E1,$C7,$73
    FCB $F7,$97,$DB,$FE,$7D,$DF,$E1,$36,$15,$0D,$6D,$B6,$F9,$2A,$3D,$BB
    FCB $B6,$FE,$7F,$CE,$EE,$D9,$86,$A2,$ED,$77,$FF,$5E,$21,$FF,$FF,$3E
    FCB $F3,$BF,$FF,$9B,$97,$57,$6A,$55,$9A,$E4,$7F,$6D,$D9,$E7,$BF,$9F
    FCB $65,$43,$34,$02,$82,$3B,$B6,$81,$44,$81,$7E,$FB,$B3,$09,$52,$15
    FCB $25,$C9,$D9,$92,$FB,$6F,$69,$BD,$21,$3F,$FD,$DC,$09,$BD,$BB,$7D
    FCB $9F,$0E,$7D,$E0,$76,$EE,$FF,$FF,$DE,$33,$BF,$CB,$EF,$3E,$02,$AD
    FCB $6D,$BB,$F2,$28,$F6,$EF,$7B,$FF,$BC,$EF,$7E,$30,$C3,$6E,$DF,$0B
    FCB $B6,$E2,$1F,$FF,$F2,$5D,$E7,$BF,$19,$F6,$66,$C3,$71,$4F,$D9,$36
    FCB $75,$B6,$FC,$FF,$F3,$37,$86,$50,$0A,$54,$BD,$B5,$A0,$53,$44,$BD
    FCB $BE,$F6,$61,$29,$23,$24,$A9,$B9,$FF,$EE,$FB,$6B,$65,$4A,$44,$EC
    FCB $FD,$F0,$CD,$ED,$DA,$FE,$79,$E7,$FE,$1C,$6F,$EF,$BB,$FB,$F9,$C7
    FCB $05,$7B,$6D,$B2,$E0,$42,$DB,$6F,$7F,$2A,$23,$B7,$FF,$BD,$F8,$FF
    FCB $ED,$97,$CB,$FF,$CF,$6F,$A5,$E7,$FC,$FB,$F9,$DF,$CE,$FE,$63,$0D
    FCB $C5,$37,$2E,$4B,$36,$B7,$7F,$3F,$E7,$DF,$A8,$C1,$00,$A2,$5E,$DA
    FCB $68,$14,$D3,$6F,$7E,$C7,$C9,$14,$8C,$A4,$BE,$7F,$FE,$FE,$D3,$70
    FCB $52,$27,$73,$37,$27,$F7,$76,$DF,$F9,$E5,$CB,$CC,$0E,$DB,$FF,$DB
    FCB $6F,$FC,$FF,$15,$1E,$BB,$F0,$4A,$F5,$BB,$BF,$BC,$86,$F9,$FD,$8D
    FCB $EF,$3F,$97,$C6,$EE,$59,$61,$7D,$FB,$E2,$4E,$7F,$3E,$CB,$EF,$3F
    FCB $E7,$F9,$F8,$F8,$A6,$E5,$C9,$66,$D6,$EF,$FF,$CF,$FF,$A8,$C5,$20
    FCB $15,$37,$BA,$0A,$0A,$6B,$BB,$7D,$BB,$35,$18,$A4,$2A,$4B,$E7,$FF
    FCB $F8,$FA,$6B,$C1,$13,$E6,$6E,$49,$DF,$6E,$DF,$BE,$17,$DB,$E0,$70
    FCB $E3,$BD,$9E,$DA,$D7,$8F,$39,$C7,$24,$ED,$EF,$A9,$55,$EB,$66,$DB
    FCB $3E,$39,$79,$0B,$FB,$73,$FF,$9B,$B3,$73,$1D,$B2,$F2,$F1,$D9,$A5
    FCB $61,$F7,$F3,$1B,$7E,$5F,$8A,$C6,$D9,$CF,$7F,$72,$E6,$66,$5D,$BD
    FCB $FF,$F9,$37,$B3,$A4,$0E,$92,$3D,$53,$7B,$68,$28,$96,$F6,$B5,$8E
    FCB $E3,$33,$2A,$42,$A4,$BE,$7C,$FB,$F1,$F5,$AC,$71,$05,$F2,$07,$B8
    FCB $7B,$EF,$77,$6C,$95,$5D,$B6,$BC,$00,$C9,$BB,$CF,$BB,$5B,$7D,$F9
    FCB $FC,$FF,$8F,$C5,$09,$EB,$0D,$AD,$FC,$1C,$BF,$0B,$DD,$EE,$19,$BD
    FCB $83,$E6,$E6,$4A,$EE,$D9,$7C,$B2,$29,$C3,$C7,$BF,$FD,$FE,$7C,$61
    FCB $F7,$BF,$DC,$2C,$E6,$71,$DB,$DF,$67,$FF,$19,$FA,$41,$69,$23,$D5
    FCB $37,$B6,$82,$89,$6F,$B7,$76,$F3,$57,$14,$92,$95,$F3,$E7,$F7,$97
    FCB $AD,$63,$D0,$5E,$75,$17,$F3,$37,$2F,$B6,$D9,$05,$5D,$B5,$B7,$80
    FCB $67,$F7,$0F,$6E,$B7,$DB,$FF,$CC,$FF,$CF,$D7,$B5,$1B,$5B,$F9,$23
    FCB $7E,$7B,$BF,$9C,$D9,$F7,$67,$9F,$6D,$FC,$75,$00,$57,$7F,$3F,$DE
    FCB $6F,$FB,$98,$73,$F7,$BB,$FC,$FC,$06,$7D,$B7,$DF,$3F,$F2,$F9,$29
    FCB $1D,$48,$F5,$1D,$BB,$5A,$24,$DD,$EF,$D3,$6C,$56,$0E,$29,$25,$2B
    FCB $E7,$B3,$F7,$CB,$8B,$5F,$68,$2F,$3A,$8B,$DE,$43,$77,$F1,$BE,$D4
    FCB $0F,$6B,$5F,$81,$F3,$B7,$50,$CD,$6E,$EF,$BF,$B6,$79,$CD,$F0,$ED
    FCB $DF,$51,$B6,$DF,$E7,$BC,$3F,$F7,$F2,$E7,$FF,$FE,$5F,$6F,$D4,$12
    FCB $BD,$E7,$DF,$FF,$FF,$FC,$F9,$BF,$7F,$FC,$92,$EE,$3F,$DF,$3F,$FE
    FCB $7C,$A1,$3A,$91,$94,$77,$B4,$D3,$4D,$7E,$EF,$4F,$51,$9E,$A5,$29
    FCB $5F,$3D,$9F,$DF,$F6,$FD,$02,$F9,$85,$EF,$33,$7F,$BB,$E5,$45,$C6
    FCB $B5,$BB,$81,$F3,$DB,$50,$E5,$6F,$FE,$6D,$6F,$8F,$B0,$B9,$0E,$DF
    FCB $C3,$6E,$FB,$72,$0F,$CF,$73,$DF,$06,$C5,$7D,$E3,$DC,$79,$1E,$D9
    FCB $75,$16,$57,$1F,$7F,$EC,$9F,$FE,$E7,$39,$F6,$DF,$9F,$CC,$FB,$FE
    FCB $F3,$FF,$FF,$CE,$84,$20,$8C,$A3,$B7,$68,$9A,$6D,$F6,$F6,$9C,$48
    FCB $75,$7A,$85,$2B,$E6,$5F,$FB,$FE,$E5,$D0,$2B,$3E,$7D,$EA,$91,$BE
    FCB $FF,$96,$07,$69,$A6,$FC,$E3,$30,$76,$59,$B7,$3E,$1E,$D7,$B7,$E4
    FCB $F8,$3D,$FF,$FF,$B6,$E7,$F1,$98,$E6,$EF,$CB,$02,$7D,$B8,$FF,$DF
    FCB $67,$50,$DE,$BA,$9F,$EF,$E7,$FF,$1D,$BC,$E7,$3B,$BB,$33,$FC,$64
    FCB $DB,$9B,$F9,$FD,$F2,$3F,$9D,$08,$41,$19,$47,$5B,$B4,$4D,$D8,$EB
    FCB $7A,$D6,$52,$3F,$8A,$15,$F3,$3F,$F7,$3E,$B8,$3A,$05,$60,$F3,$BB
    FCB $C5,$4E,$ED,$BD,$C1,$86,$1D,$AD,$35,$EF,$27,$26,$EA,$B2,$2D,$79
    FCB $E0,$1B,$5B,$7B,$9F,$39,$ED,$DF,$E4,$2D,$BB,$9D,$F1,$86,$FF,$66
    FCB $16,$40,$EB,$6D,$60,$47,$F6,$ED,$98,$0D,$8D,$D5,$FB,$BC,$9F,$7F
    FCB $3B,$72,$E5,$CF,$EE,$5E,$F0,$E7,$DF,$EF,$21,$DB,$CF,$F3,$94,$2A
    FCB $D4,$21,$0E,$DB,$68,$AB,$7D,$AF,$AD,$94,$B8,$71,$42,$BB,$66,$7F
    FCB $EE,$6C,$B2,$68,$E5,$35,$0F,$F7,$B0,$24,$6E,$EF,$C1,$E6,$AD,$B5
    FCB $AD,$DA,$DF,$53,$00,$55,$B8,$FD,$69,$93,$35,$1D,$B7,$F3,$FF,$F7
    FCB $6F,$F2,$A8,$DF,$FD,$F6,$1F,$FE,$16,$CF,$37,$6B,$A8,$8F,$C6,$ED
    FCB $FC,$71,$EA,$FF,$64,$C7,$77,$39,$6E,$D9,$C7,$8C,$EE,$CC,$BF,$99
    FCB $F6,$FE,$32,$5F,$C6,$7F,$F9,$47,$AB,$4A,$90,$76,$DB,$41,$16,$FD
    FCB $77,$5B,$55,$2C,$F6,$28,$57,$73,$3F,$FB,$0D,$8D,$8C,$A3,$96,$AF
    FCB $7D,$EE,$A2,$77,$E6,$E3,$7D,$AB,$DA,$DE,$DD,$C6,$62,$B7,$1B,$EB
    FCB $5C,$3E,$2B,$B6,$EE,$18,$5F,$DB,$F6,$EE,$70,$3F,$9B,$FB,$9F,$FF
    FCB $BB,$80,$C5,$5D,$6E,$63,$9D,$F6,$FE,$D9,$8A,$1E,$FC,$38,$F6,$E7
    FCB $2E,$EC,$B2,$DF,$24,$6E,$5D,$F0,$FF,$FF,$F3,$E5,$BF,$3F,$CA,$3D
    FCB $5A,$54,$83,$AD,$B5,$A7,$7F,$5B,$74,$EA,$12,$9F,$80,$7B,$33,$FF
    FCB $70,$D8,$E3,$88,$E5,$30,$FD,$B8,$C9,$67,$E1,$83,$6E,$DE,$77,$7B
    FCB $E2,$9E,$C1,$DE,$DF,$5A,$79,$98,$7F,$E1,$96,$EF,$6F,$EF,$67,$27
    FCB $90,$8F,$76,$C7,$F3,$7B,$F6,$0A,$55,$43,$5A,$DB,$E7,$0B,$DB,$C7
    FCB $BA,$E4,$56,$EF,$31,$99,$BD,$FF,$D9,$65,$BE,$48,$FD,$FF,$39,$7D
    FCB $CE,$7F,$93,$6C,$6F,$92,$E2,$3D,$51,$42,$13,$B4,$DD,$35,$DF,$D6
    FCB $DD,$31,$21,$53,$F0,$0E,$D9,$9F,$CD,$CE,$C6,$CE,$8E,$59,$EF,$BF
    FCB $3F,$E0,$71,$B7,$B7,$3F,$FB,$8C,$6C,$17,$BD,$F6,$BE,$7F,$8A,$F9
    FCB $E5,$FB,$7D,$EE,$DC,$E6,$48,$AE,$ED,$DB,$98,$F2,$EF,$97,$08,$95
    FCB $B6,$BB,$3B,$0E,$EC,$2A,$76,$ED,$93,$BB,$C7,$32,$7D,$EF,$CF,$65
    FCB $E3,$26,$F9,$FE,$6F,$DF,$33,$97,$F9,$77,$64,$F7,$A3,$D5,$52,$84
    FCB $8E,$D6,$E8,$9D,$FD,$6B,$B4,$D4,$92,$83,$F8,$07,$6C,$CF,$E6,$E6
    FCB $E6,$74,$74,$B2,$DD,$CF,$CE,$FC,$00,$BB,$5F,$B8,$66,$FD,$CD,$AF
    FCB $7B,$DE,$5F,$FD,$DA,$80,$EE,$E1,$97,$B7,$F5,$EE,$61,$38,$7B,$77
    FCB $B3,$EC,$DF,$C6,$FD,$40,$BB,$6E,$78,$6F,$61,$37,$D9,$AF,$DB,$2F
    FCB $E4,$3F,$BE,$7E,$39,$CB,$B7,$2F,$3F,$23,$FB,$30,$9B,$63,$9B,$7F
    FCB $9E,$F4,$02,$54,$81,$5E,$D6,$DA,$2D,$FD,$6E,$B5,$A9,$25,$07,$F2
    FCB $CE,$07,$6C,$F3,$73,$73,$3A,$39,$5E,$ED,$87,$3B,$BF,$81,$3B,$7F
    FCB $D4,$C9,$5F,$B8,$ED,$F7,$76,$EA,$33,$FA,$D7,$81,$BD,$E6,$2B,$BB
    FCB $FB,$BD,$91,$86,$6F,$77,$FF,$E1,$DF,$6D,$F2,$76,$DC,$F0,$DA,$C7
    FCB $3E,$D4,$D9,$EF,$1E,$EF,$30,$3F,$BC,$9F,$CF,$6D,$DC,$98,$FC,$F2
    FCB $EF,$C2,$46,$5F,$77,$F0,$7B,$71,$1D,$A5,$48,$0F,$6B,$6D,$17,$FA
    FCB $6E,$B5,$A9,$21,$58,$0F,$1C,$E6,$7F,$FF,$DC,$B2,$C4,$0B,$FC,$0A
    FCB $EE,$F6,$FC,$0F,$D9,$F0,$79,$9D,$AE,$DB,$63,$FD,$8A,$57,$3E,$D6
    FCB $9D,$BF,$F3,$D5,$93,$F7,$EE,$E3,$9B,$6F,$E4,$EE,$6C,$0F,$7D,$BF
    FCB $37,$77,$C8,$76,$EB,$FE,$D4,$B7,$89,$5E,$F7,$FC,$00,$BB,$E7,$2F
    FCB $7D,$9B,$DF,$84,$7F,$3C,$EF,$93,$1E,$FB,$EE,$41,$ED,$C4,$76,$95
    FCB $20,$3D,$AD,$AD,$3F,$F4,$DD,$36,$92,$40,$7F,$C3,$99,$FF,$FB,$DC
    FCB $27,$40,$AF,$06,$CE,$C7,$BB,$76,$48,$7B,$99,$CB,$9B,$9A,$C6,$D7
    FCB $BD,$CC,$51,$03,$ED,$6B,$B4,$DB,$7C,$0F,$03,$56,$FF,$DB,$EB,$7E
    FCB $E6,$EA,$32,$E6,$C3,$8F,$DB,$0E,$DF,$7F,$0F,$76,$BE,$C7,$76,$F1
    FCB $19,$DD,$FF,$D9,$01,$B3,$FE,$7B,$9F,$6D,$F8,$7B,$97,$21,$DE,$18
    FCB $EF,$BE,$7D,$CE,$BC,$47,$69,$09,$12,$CB,$5B,$5A,$7F,$E9,$B6,$B6
    FCB $92,$4A,$0C,$FB,$67,$93,$3F,$FB,$77,$00,$E8,$15,$F5,$3E,$ED,$9E
    FCB $2F,$F9,$DD,$46,$A6,$B7,$79,$8C,$14,$DD,$B7,$B6,$D9,$8A,$53,$03
    FCB $36,$DD,$AD,$35,$BD,$86,$F0,$C5,$49,$FB,$DD,$A7,$E4,$1F,$57,$FF
    FCB $9E,$E7,$61,$B6,$FF,$D8,$5C,$75,$3B,$5A,$C6,$5E,$31,$57,$EF,$F1
    FCB $DC,$FF,$97,$2C,$BF,$F1,$CF,$F9,$7F,$3D,$92,$77,$B6,$72,$ED,$CC
    FCB $7D,$1D,$A4,$92,$8A,$BB,$69,$B5,$AF,$FD,$36,$D3,$14,$85,$41,$BF
    FCB $0D,$C7,$99,$F7,$FB,$78,$07,$40,$AF,$8B,$63,$E4,$BD,$C3,$76,$DB
    FCB $2A,$54,$1B,$59,$67,$6D,$4A,$53,$06,$D8,$D6,$B5,$FA,$81,$C0,$EF
    FCB $95,$A6,$B5,$DA,$C5,$63,$CC,$8A,$FF,$DB,$BF,$90,$7C,$F7,$FC,$F6
    FCB $7B,$9B,$6C,$CD,$DD,$4D,$CD,$2D,$A6,$BD,$57,$A9,$8F,$BD,$FC,$BB
    FCB $FF,$92,$FB,$37,$3E,$E4,$EE,$48,$DF,$3B,$7C,$02,$DF,$7B,$CE,$FC
    FCB $F4,$76,$92,$4A,$27,$6D,$6D,$3B,$FE,$9B,$69,$8A,$42,$A0,$FE,$77
    FCB $1F,$27,$FE,$FD,$9A,$BA,$05,$73,$5C,$B3,$1D,$DB,$A9,$5B,$6B,$6E
    FCB $0A,$57,$AD,$7C,$18,$45,$29,$C6,$D6,$35,$B7,$E2,$BF,$EF,$2D,$AD
    FCB $69,$ED,$4A,$1E,$DA,$C3,$15,$E3,$B9,$CF,$E7,$DC,$F6,$7F,$F7,$8C
    FCB $7A,$E1,$F7,$BD,$E5,$5B,$5E,$D5,$B6,$A5,$9F,$BF,$9B,$BD,$F9,$25
    FCB $F7,$CD,$E6,$C2,$0F,$32,$DB,$CB,$DF,$21,$BB,$DF,$FF,$99,$A0,$12
    FCB $42,$13,$B6,$9A,$D3,$B8,$7A,$6D,$A6,$A5,$21,$51,$FE,$77,$E6,$37
    FCB $E1,$DF,$B3,$50,$E8,$15,$C2,$B8,$FB,$1D,$EC,$51,$35,$B6,$C8,$65
    FCB $AF,$8A,$86,$0D,$DB,$59,$63,$F1,$4D,$DA,$FD,$CE,$BD,$7D,$4A,$2E
    FCB $DA,$C1,$6B,$0B,$0B,$92,$65,$F1,$9E,$B1,$5D,$CF,$BE,$EF,$50,$D3
    FCB $B6,$19,$F7,$59,$C7,$CD,$D5,$DD,$CE,$EF,$3E,$F7,$EC,$B2,$7D,$F3
    FCB $79,$F8,$61,$ED,$BC,$B2,$E7,$CB,$DD,$DD,$F3,$03,$C4,$76,$92,$41
    FCB $EE,$B5,$B4,$FF,$E9,$B5,$AD,$4A,$42,$03,$CE,$3D,$F9,$97,$FF,$61
    FCB $B3,$54,$68,$15,$C5,$53,$77,$FD,$9C,$38,$EC,$BA,$8A,$AD,$EC,$06
    FCB $DB,$D9,$E3,$DC,$2A,$1A,$DB,$5B,$01,$97,$6F,$E1,$64,$DE,$9A,$C5
    FCB $5F,$71,$E5,$96,$4E,$76,$1D,$CF,$B6,$DB,$C1,$55,$BD,$81,$FF,$67
    FCB $B6,$F2,$F6,$71,$4F,$1B,$6E,$65,$7D,$FB,$3C,$FB,$E6,$F8,$7F,$03
    FCB $77,$79,$65,$CB,$E6,$F7,$DD,$FC,$14,$0E,$20,$12,$43,$3D,$B6,$9B
    FCB $44,$42,$FA,$6D,$6B,$52,$90,$A8,$CD,$E6,$FE,$76,$CE,$17,$FB,$1B
    FCB $54,$A2,$6C,$55,$37,$6D,$BC,$25,$9C,$F7,$35,$12,$DB,$6E,$11,$AD
    FCB $DB,$48,$26,$DB,$C9,$DB,$9F,$5E,$B0,$79,$72,$1E,$B6,$1E,$FA,$D6
    FCB $CC,$C8,$59,$63,$3B,$CF,$B6,$D6,$C8,$17,$96,$17,$FD,$9E,$FF,$F6
    FCB $0C,$AE,$0E,$DE,$03,$76,$B6,$32,$47,$FF,$64,$BB,$21,$73,$19,$76
    FCB $E7,$07,$AE,$05,$B8,$E5,$FD,$BB,$D4,$28,$BA,$90,$09,$24,$6E,$ED
    FCB $AD,$A7,$CF,$AD,$A6,$D2,$12,$51,$9B,$9D,$FE,$7F,$2F,$B7,$D8,$0A
    FCB $E8,$2B,$8A,$A2,$65,$6B,$0D,$56,$CE,$72,$F0,$26,$D7,$6D,$83,$B5
    FCB $D4,$52,$06,$75,$AD,$DE,$AC,$64,$2D,$B6,$D6,$AF,$7C,$84,$DB,$0E
    FCB $CE,$B5,$BF,$87,$6C,$CF,$B2,$F2,$DB,$B7,$92,$FE,$39,$0D,$B9,$DB
    FCB $39,$F7,$19,$4E,$13,$B3,$8D,$B6,$F7,$0F,$6C,$DD,$8A,$8E,$E4,$B5
    FCB $12,$DA,$DB,$F8,$0E,$37,$2D,$D9,$CB,$C2,$B8,$C0,$57,$6A,$40,$24
    FCB $91,$BB,$B5,$B6,$BE,$FE,$DA,$2A,$42,$4A,$27,$73,$BF,$9D,$B3,$FD
    FCB $BD,$B5,$28,$57,$44,$BD,$42,$0B,$8D,$83,$23,$78,$04,$F2,$7D,$B6
    FCB $D6,$CB,$B8,$A5,$0A,$FB,$16,$B6,$D7,$99,$00,$75,$B7,$67,$6D,$F2
    FCB $05,$93,$B0,$EB,$6D,$90,$AF,$6D,$AA,$D4,$EE,$33,$78,$E5,$B5,$BB
    FCB $2B,$00,$8B,$70,$9B,$07,$AD,$D5,$87,$B3,$B4,$18,$01,$B3,$95,$DB
    FCB $C9,$76,$EE,$76,$13,$7B,$06,$28,$ED,$6E,$FE,$28,$DA,$F8,$DF,$61
    FCB $7D,$42,$E3,$D4,$AE,$D2,$40,$24,$A3,$77,$69,$B6,$FB,$7E,$BA,$21
    FCB $21,$09,$39,$67,$7F,$31,$BE,$DE,$DB,$B8,$95,$4A,$31,$12,$DD,$54
    FCB $56,$A2,$D9,$C1,$93,$0F,$9F,$DB,$6B,$F1,$6C,$35,$72,$CA,$DB,$6E
    FCB $7C,$36,$37,$5B,$EF,$6E,$6A,$56,$19,$66,$EB,$B0,$A8,$69,$DA,$67
    FCB $8D,$6F,$C2,$72,$ED,$AF,$D7,$02,$37,$EA,$EA,$BB,$4D,$61,$14,$A7
    FCB $E3,$E8,$9C,$20,$3F,$8F,$6E,$55,$5B,$6E,$E6,$59,$0B,$78,$67,$2D
    FCB $B7,$EC,$12,$95,$B3,$6D,$86,$0D,$F1,$FE,$A0,$B4,$28,$05,$06,$ED
    FCB $D1,$2D,$8F,$FB,$5A,$D3,$A4,$21,$48,$FC,$DD,$B2,$DF,$B6,$DC,$20
    FCB $A0,$52,$81,$94,$5A,$91,$2D,$B4,$A8,$B0,$1E,$65,$93,$9F,$FB,$3D
    FCB $B1,$BB,$5B,$E7,$20,$DB,$8E,$77,$8F,$B5,$D6,$B0,$56,$0D,$F0,$F7
    FCB $CF,$D8,$12,$B4,$5A,$C3,$DA,$F7,$F1,$C3,$55,$BB,$DA,$C3,$2E,$E2
    FCB $B6,$57,$AE,$AE,$AF,$EF,$69,$F9,$0E,$37,$CB,$31,$AD,$E6,$F0,$7D
    FCB $43,$5F,$3D,$D4,$5B,$7E,$EA,$54,$B6,$75,$B0,$80,$B7,$75,$7B,$D4
    FCB $16,$85,$1D,$A8,$1D,$7B,$69,$AD,$8F,$FB,$6D,$62,$54,$94,$76,$FA
    FCB $6B,$76,$4D,$40,$00,$A0,$27,$93,$A6,$9B,$A2,$5B,$A3,$08,$AD,$C7
    FCB $24,$93,$F3,$FD,$9F,$7E,$DB,$AD,$DB,$00,$B7,$61,$03,$BB,$6F,$75
    FCB $E7,$9C,$FB,$6C,$2A,$B3,$E3,$EB,$4C,$A6,$06,$36,$F5,$37,$B6,$B9
    FCB $15,$6A,$B8,$DF,$73,$73,$1E,$BC,$07,$9F,$BF,$4C,$7F,$0B,$1A,$F2
    FCB $33,$D7,$B5,$0D,$C9,$D8,$37,$1F,$F5,$6E,$FD,$87,$B0,$95,$81,$65
    FCB $B6,$E2,$A5,$DA,$8E,$8C,$8E,$D5,$2D,$6E,$DA,$6B,$CF,$7A,$ED,$A9
    FCB $2A,$4A,$3A,$F1,$6B,$6D,$0C,$14,$04,$B3,$CF,$E7,$74,$4B,$68,$9B
    FCB $10,$A9,$15,$6C,$33,$E4,$F1,$9E,$FF,$FD,$EC,$DB,$6B,$91,$B8,$40
    FCB $E6,$F5,$B6,$37,$6C,$97,$2F,$F6,$EA,$27,$EF,$72,$D6,$53,$69,$2B
    FCB $1B,$E3,$96,$B5,$AE,$71,$4E,$CF,$B6,$41,$FB,$FC,$6F,$56,$F0,$5B
    FCB $D6,$3F,$CC,$6F,$78,$6D,$F0,$2F,$C7,$9B,$B7,$F0,$E3,$F6,$EA,$F7
    FCB $86,$AF,$B6,$F8,$66,$D2,$17,$11,$90,$0A,$2E,$B7,$6D,$35,$E5,$DF
    FCB $59,$A9,$42,$95,$94,$DE,$9B,$50,$8C,$94,$F3,$83,$F7,$3C,$F5,$A2
    FCB $5A,$6B,$B4,$92,$41,$99,$8F,$F3,$C7,$F6,$F7,$66,$03,$BC,$C6,$FD
    FCB $CE,$4F,$BE,$D6,$FD,$C6,$C7,$7B,$55,$EF,$51,$B3,$97,$ED,$BD,$D2
    FCB $57,$77,$B9,$EB,$59,$7B,$7A,$C0,$9B,$3F,$D8,$3D,$D9,$9B,$18,$A5
    FCB $A2,$67,$7C,$1E,$36,$5E,$11,$EF,$55,$FB,$37,$FF,$E7,$9F,$6F,$CD
    FCB $FC,$51,$BD,$E3,$33,$68,$46,$D2,$49,$1E,$A2,$EB,$6D,$B5,$AD,$9B
    FCB $FA,$60,$24,$AA,$89,$A6,$D8,$89,$6A,$A1,$42,$94,$0E,$E7,$BF,$99
    FCB $F5,$A0,$A6,$DB,$52,$32,$0B,$33,$7F,$EF,$DB,$73,$B6,$B7,$52,$85
    FCB $17,$C3,$FE,$CF,$FD,$F7,$6B,$C6,$E5,$9B,$77,$53,$5E,$B5,$33,$C3
    FCB $B7,$ED,$C8,$07,$B4,$ED,$81,$2E,$7A,$D3,$B6,$E6,$93,$5A,$B1,$BF
    FCB $2B,$F5,$1D,$9E,$D3,$7F,$CA,$AF,$7A,$88,$DA,$9D,$83,$2F,$6F,$BD
    FCB $99,$E6,$3E,$43,$76,$FB,$EF,$E2,$80,$DD,$55,$DE,$5A,$12,$D2,$52
    FCB $3D,$43,$D7,$6D,$3A,$D6,$6E,$6D,$65,$49,$15,$07,$5B,$74,$C6,$D3
    FCB $46,$46,$12,$54,$DF,$9F,$F8,$F9,$4D,$36,$89,$6A,$47,$A0,$B1,$DD
    FCB $BA,$B3,$6D,$BD,$C0,$37,$6E,$A2,$5B,$EA,$3F,$F8,$FE,$F7,$B6,$DA
    FCB $C5,$16,$F7,$1F,$C5,$AF,$5A,$A6,$55,$DD,$39,$BF,$1D,$5E,$B4,$4D
    FCB $D4,$A5,$06,$FD,$4D,$6D,$AD,$6C,$22,$E9,$7A,$F3,$36,$C3,$96,$6C
    FCB $4D,$EF,$F3,$8C,$A8,$06,$B5,$5F,$BB,$8F,$7E,$EC,$03,$DD,$D9,$87
    FCB $DB,$E7,$DE,$2A,$A5,$2E,$C2,$DD,$CB,$42,$68,$44,$2A,$2E,$B6,$DA
    FCB $25,$37,$F1,$DA,$D4,$24,$A2,$4E,$B6,$E8,$92,$6D,$10,$8C,$8C,$92
    FCB $A7,$F1,$FF,$F6,$CE,$BA,$0A,$74,$7A,$0B,$53,$6F,$27,$FF,$EC,$F1
    FCB $FD,$EF,$03,$B3,$FE,$F6,$B6,$3D,$DB,$6A,$51,$6D,$77,$B0,$CD,$96
    FCB $AF,$73,$ED,$EA,$69,$AF,$6D,$4A,$C1,$AD,$BE,$04,$1D,$E2,$DD,$B4
    FCB $E7,$AB,$59,$72,$A1,$5B,$58,$95,$D3,$92,$A4,$D7,$6B,$F9,$B0,$00
    FCB $C5,$B1,$F6,$CC,$1B,$6E,$05,$B9,$8F,$76,$F8,$4F,$7F,$81,$7F,$51
    FCB $5B,$ED,$92,$50,$8E,$8F,$A1,$51,$75,$B6,$D1,$29,$FE,$DD,$AD,$4A
    FCB $42,$A2,$A3,$D3,$5B,$68,$91,$96,$D1,$26,$8C,$85,$0A,$90,$9B,$E7
    FCB $F7,$F6,$EE,$BD,$37,$46,$40,$B5,$37,$F0,$B9,$C7,$7B,$C2,$69,$AF
    FCB $9E,$28,$EF,$FF,$ED,$6D,$B7,$24,$01,$DB,$6E,$B5,$B5,$69,$53,$91
    FCB $4D,$F2,$DF,$61,$04,$D3,$B7,$91,$25,$5B,$EE,$73,$F6,$DD,$A6,$B3
    FCB $BF,$3F,$12,$82,$DA,$5B,$5D,$5E,$DD,$A7,$F2,$30,$0E,$5B,$55,$B6
    FCB $EF,$14,$CB,$CB,$BD,$E3,$F6,$CF,$3F,$FD,$52,$CE,$2A,$ED,$37,$84
    FCB $50,$84,$5B,$47,$D0,$AA,$36,$BB,$69,$97,$ED,$EB,$A4,$A4,$21,$0F
    FCB $4D,$74,$D3,$42,$9B,$5A,$D6,$8F,$42,$A4,$64,$A7,$FF,$69,$AD,$B5
    FCB $A7,$AF,$22,$B5,$20,$57,$64,$C5,$2A,$0E,$ED,$BA,$E5,$4A,$31,$AD
    FCB $6D,$D4,$42,$7F,$DF,$CB,$6D,$B6,$CF,$50,$C3,$ED,$6B,$69,$3A,$93
    FCB $4D,$77,$21,$2B,$20,$78,$A6,$9D,$B7,$54,$53,$8E,$C7,$B6,$D6,$00
    FCB $A6,$BB,$A8,$4F,$45,$7D,$81,$B6,$21,$DA,$D4,$E4,$59,$91,$E8,$BD
    FCB $86,$0E,$76,$C1,$B6,$F9,$06,$3E,$32,$DE,$FB,$C6,$3C,$FF,$F8,$43
    FCB $F5,$29,$7A,$D7,$0C,$55,$19,$4C,$4A,$84,$ED,$36,$D6,$FE,$36,$F5
    FCB $A9,$25,$25,$0F,$D3,$6D,$05,$A1,$5B,$6B,$58,$90,$8C,$8C,$A0,$DD
    FCB $68,$9A,$D3,$6B,$6D,$6D,$8A,$52,$32,$B6,$C2,$20,$5B,$C5,$00,$A3
    FCB $5B,$5F,$96,$DC,$00,$2F,$9F,$EF,$1B,$2E,$DB,$7A,$AE,$48,$3D,$6E
    FCB $01,$B5,$AE,$A7,$AE,$B2,$EA,$7A,$DA,$95,$D8,$71,$BD,$B0,$71,$73
    FCB $EC,$AE,$D5,$EB,$4F,$A4,$93,$BD,$AE,$2E,$3B,$6E,$AD,$E6,$09,$98
    FCB $4D,$17,$93,$2E,$5B,$79,$DD,$E0,$FC,$92,$DB,$B9,$84,$DB,$7F,$FF
    FCB $0D,$4D,$E4,$57,$6D,$A4,$6B,$04,$65,$35,$2A,$84,$ED,$13,$6B,$7B
    FCB $2F,$EB,$49,$25,$28,$87,$D1,$2D,$A0,$68,$5E,$9A,$DE,$92,$4A,$1B
    FCB $5A,$D3,$6B,$77,$BC,$75,$29,$19,$4A,$49,$75,$46,$ED,$EF,$00,$B7
    FCB $DB,$B5,$BF,$92,$A5,$41,$B7,$6C,$B7,$00,$75,$A6,$9C,$A4,$A3,$33
    FCB $BA,$C2,$30,$B5,$B9,$F7,$C6,$9B,$AC,$51,$B7,$38,$D9,$6D,$2B,$75
    FCB $90,$1C,$7B,$83,$5B,$5B,$C3,$80,$AB,$6D,$69,$AC,$BC,$E3,$F8,$A8
    FCB $29,$AE,$D3,$73,$F0,$82,$DB,$CC,$DF,$F3,$36,$EF,$0D,$5D,$9B,$AF
    FCB $DC,$9B,$72,$02,$F9,$24,$A9,$2E,$82,$C4,$65,$52,$53,$48,$2D,$AD
    FCB $B4,$F7,$1F,$DB,$42,$90,$04,$3D,$12,$6B,$40,$89,$6A,$4D,$6D,$37
    FCB $DB,$76,$57,$67,$89,$21,$50,$A0,$53,$6F,$78,$F6,$B7,$05,$28,$2D
    FCB $3D,$CB,$6B,$4F,$EA,$15,$8F,$2E,$A1,$DF,$7B,$8A,$8F,$7E,$F8,$C9
    FCB $5A,$81,$D7,$F5,$7D,$6B,$BB,$E5,$49,$AC,$6D,$21,$A7,$AD,$4A,$01
    FCB $FD,$C5,$5D,$37,$87,$DD,$F7,$49,$27,$D3,$4C,$6B,$DF,$BC,$89,$21
    FCB $E3,$5D,$A0,$63,$CF,$85,$C6,$A3,$6D,$FD,$9E,$39,$C8,$15,$0E,$9A
    FCB $D4,$DB,$6C,$C8,$C5,$47,$1D,$D7,$6C,$39,$A4,$AE,$9B,$11,$EA,$68
    FCB $CA,$69,$1B,$69,$B6,$88,$0B,$DB,$DA,$92,$48,$0C,$E5,$12,$D0,$50
    FCB $52,$56,$A5,$AD,$A2,$5B,$BB,$EC,$7F,$82,$32,$03,$B6,$DC,$B3,$6F
    FCB $53,$05,$42,$53,$7B,$85,$B5,$B1,$ED,$8E,$2A,$D5,$19,$5D,$B9,$B8
    FCB $1A,$DF,$52,$8F,$19,$AD,$79,$1C,$70,$85,$A6,$5B,$B7,$0B,$6A,$70
    FCB $5A,$2E,$A6,$A1,$A5,$5A,$71,$A9,$46,$22,$6E,$E0,$45,$FE,$0A,$C1
    FCB $AD,$B5,$A6,$B6,$5F,$D4,$09,$41,$33,$68,$19,$FE,$67,$86,$D7,$91
    FCB $B1,$45,$EB,$CA,$83,$AA,$E9,$AD,$21,$D6,$D9,$97,$4A,$A1,$B4,$DD
    FCB $AC,$E5,$F8,$4F,$47,$A9,$A3,$14,$2A,$EB,$44,$9B,$4C,$CE,$DB,$AD
    FCB $4A,$48,$50,$40,$D6,$82,$B4,$0B,$52,$94,$29,$AD,$69,$AF,$76,$F7
    FCB $66,$7A,$32,$3D,$6B,$A7,$20,$C0,$D8,$0E,$18,$CA,$DC,$4C,$56,$EE
    FCB $31,$AD,$B6,$C4,$86,$AB,$4D,$62,$EA,$53,$5D,$A7,$52,$40,$26,$B5
    FCB $14,$22,$B1,$D7,$6E,$89,$6A,$2A,$54,$7B,$14,$5A,$D9,$D3,$AB,$6A
    FCB $2E,$B7,$4E,$D8,$28,$01,$76,$DB,$80,$5E,$D7,$0D,$EE,$2C,$9A,$95
    FCB $F5,$A7,$B5,$AC,$3D,$B8,$85,$4D,$7A,$29,$F3,$77,$20,$FB,$70,$8D
    FCB $8A,$FA,$77,$08,$01,$D7,$51,$BD,$6F,$1B,$56,$A6,$B5,$BD,$9E,$3E
    FCB $C7,$01,$54,$22,$EA,$52,$32,$82,$B4,$D6,$D3,$3F,$69,$BA,$D7,$C8
    FCB $02,$8A,$7A,$C5,$29,$21,$55,$B6,$DF,$5B,$89,$B7,$3A,$E2,$92,$17
    FCB $7C,$2A,$51,$B3,$6F,$02,$35,$A6,$C4,$C4,$2A,$1B,$6D,$6B,$6B,$A9
    FCB $71,$A4,$85,$A9,$AD,$6B,$16,$29,$42,$CB,$00,$8D,$17,$14,$1B,$6C
    FCB $75,$34,$C3,$D4,$E1,$ED,$E6,$BF,$A8,$4D,$C0,$45,$69,$80,$0A,$76
    FCB $DE,$D4,$14,$4C,$BC,$E9,$A8,$7A,$D9,$91,$46,$A1,$A7,$69,$B1,$5B
    FCB $5A,$7C,$42,$D6,$0C,$2F,$6A,$7E,$CB,$B1,$C7,$15,$EF,$85,$3B,$8A
    FCB $5E,$16,$60,$A1,$57,$6D,$6D,$25,$AD,$DA,$87,$A6,$0F,$62,$4F,$6B
    FCB $F8,$29,$43,$75,$21,$54,$2D,$AD,$65,$F7,$5B,$6D,$B7,$E5,$FA,$4A
    FCB $8A,$52,$15,$03,$6D,$FA,$DE,$B5,$AD,$9D,$E2,$92,$5E,$BA,$80,$01
    FCB $BB,$6D,$D8,$92,$82,$DA,$D6,$D7,$1F,$2F,$70,$20,$05,$BD,$81,$0E
    FCB $6D,$A6,$82,$CA,$92,$DD,$75,$25,$2B,$4F,$69,$B1,$0B,$A4,$2D,$84
    FCB $1D,$D8,$FA,$9B,$CD,$3D,$60,$F8,$2D,$E9,$0B,$B4,$D7,$3A,$C0,$0C
    FCB $B6,$EF,$7F,$0B,$D8,$1A,$90,$51,$70,$18,$0C,$BD,$90,$AA,$DA,$EB
    FCB $1C,$CE,$14,$F0,$AE,$E2,$96,$E7,$23,$A9,$4A,$46,$4D,$36,$D6,$A5
    FCB $2D,$3E,$A3,$1C,$5D,$B1,$4B,$77,$7C,$61,$F5,$24,$57,$57,$45,$B7
    FCB $DB,$23,$63,$9C,$F4,$88,$A5,$24,$A0,$B6,$CE,$DD,$B4,$D7,$E2,$DC
    FCB $A9,$3D,$D2,$50,$A9,$6F,$93,$BB,$AD,$77,$4A,$FA,$AB,$C5,$2B,$B6
    FCB $DB,$2D,$C7,$52,$85,$00,$FB,$6B,$6D,$42,$F6,$B6,$C4,$26,$56,$9E
    FCB $BD,$2D,$42,$FF,$5E,$33,$83,$31,$13,$6D,$A6,$A6,$C0,$4B,$71,$55
    FCB $DD,$68,$B8,$DA,$44,$84,$E9,$DB,$5F,$00,$D8,$D6,$AC,$4D,$3E,$64
    FCB $53,$7B,$F8,$28,$5D,$B7,$E0,$F0,$1F,$67,$6D,$AB,$2E,$6A,$69,$85
    FCB $0B,$59,$66,$9B,$80,$B5,$01,$4D,$6C,$4A,$9E,$B9,$0B,$49,$4D,$AD
    FCB $B9,$50,$B6,$15,$2C,$6D,$F7,$B7,$48,$83,$0E,$2B,$A8,$49,$41,$BE
    FCB $36,$F6,$89,$6C,$E9,$E6,$9B,$D4,$A2,$35,$3C,$BE,$DB,$1D,$26,$FF
    FCB $9B,$2E,$2B,$DB,$5A,$F6,$17,$50,$A4,$95,$53,$6F,$B1,$7B,$8F,$5A
    FCB $94,$F5,$BB,$B6,$B9,$14,$57,$B6,$F6,$AA,$95,$91,$C5,$A7,$6D,$FC
    FCB $C4,$89,$6E,$E9,$BE,$59,$80,$B7,$61,$2D,$6B,$B8,$2B,$AB,$59,$69
    FCB $B7,$CE,$2A,$CB,$6C,$F2,$F1,$CC,$B8,$03,$37,$8E,$D6,$1D,$F6,$56
    FCB $A9,$FD,$57,$77,$92,$D7,$04,$9A,$DB,$74,$A5,$6D,$49,$3B,$5F,$D4
    FCB $B5,$EA,$49,$38,$54,$36,$EB,$4E,$85,$44,$99,$86,$0A,$03,$CE,$DF
    FCB $44,$B6,$E3,$4E,$62,$6F,$52,$86,$DA,$9C,$15,$4D,$6D,$37,$35,$54
    FCB $C1,$71,$69,$35,$C1,$62,$92,$4A,$ED,$69,$AD,$BD,$E4,$42,$91,$53
    FCB $4D,$7B,$63,$B7,$31,$A9,$25,$95,$B0,$70,$60,$EB,$5A,$DE,$60,$94
    FCB $1C,$B4,$16,$D7,$14,$00,$A7,$B6,$24,$56,$9A,$9E,$C0,$F6,$3E,$D1
    FCB $36,$D4,$A1,$44,$4D,$7D,$54,$97,$6A,$6D,$4D,$6B,$6B,$DC,$E1,$EF
    FCB $22,$F2,$C6,$1D,$B0,$3A,$59,$5B,$6E,$DA,$A5,$86,$BC,$BB,$E5,$57
    FCB $71,$AF,$56,$C0,$17,$D8,$AB,$6B,$73,$C7,$E2,$F1,$4B,$6A,$14,$A2
    FCB $F5,$A2,$A1,$02,$06,$4E,$01,$93,$22,$DF,$4D,$6D,$39,$4D,$FA,$76
    FCB $24,$17,$1F,$55,$BB,$F1,$A9,$56,$D6,$B1,$68,$5A,$D8,$2E,$92,$49
    FCB $65,$B6,$ED,$EC,$A9,$51,$63,$44,$E6,$D6,$DC,$51,$16,$A0,$3F,$C9
    FCB $D6,$B6,$48,$BC,$58,$A6,$F4,$58,$D9,$D4,$84,$66,$B3,$6B,$4E,$A8
    FCB $33,$96,$AD,$B6,$DC,$35,$45,$35,$B8,$E6,$02,$ED,$D6,$83,$1E,$ED
    FCB $59,$BF,$B0,$F6,$65,$9D,$4D,$4E,$C6,$D8,$6D,$0B,$A4,$89,$96,$B6
    FCB $1B,$67,$22,$F6,$0B,$F0,$04,$93,$5D,$B5,$33,$BE,$02,$C5,$36,$D6
    FCB $72,$E1,$A9,$5B,$69,$D0,$84,$81,$2A,$F2,$67,$87,$EB,$5A,$D1,$4A
    FCB $27,$BA,$71,$43,$E0,$8B,$AB,$D7,$DC,$42,$94,$A6,$0E,$D1,$54,$6C
    FCB $52,$41,$72,$47,$F3,$B7,$DD,$DB,$BA,$9B,$6A,$69,$AA,$46,$F3,$0F
    FCB $64,$AD,$03,$C4,$9B,$72,$06,$FB,$49,$4B,$6D,$12,$D4,$00,$98,$AD
    FCB $76,$A6,$F7,$DD,$91,$25,$27,$55,$0B,$A0,$B9,$5B,$EA,$AB,$04,$D0
    FCB $6E,$A6,$B2,$A9,$76,$D9,$B1,$4E,$5C,$DD,$49,$78,$9D,$A7,$A8,$36
    FCB $A6,$D2,$41,$BE,$C3,$53,$59,$FE,$FE,$C1,$58,$B5,$F2,$CD,$83,$2A
    FCB $16,$93,$D1,$5E,$A1,$B0,$C3,$AE,$D0,$81,$14,$4C,$CE,$64,$C2,$D9
    FCB $B5,$D0,$59,$44,$E2,$94,$9B,$0B,$3D,$7A,$C4,$2D,$B4,$0A,$D9,$89
    FCB $25,$84,$5E,$D2,$02,$D3,$51,$CA,$83,$53,$B7,$DF,$F6,$FD,$78,$EA
    FCB $6F,$FF,$2C,$3E,$F5,$F5,$B6,$36,$2A,$B0,$23,$D6,$D2,$2D,$6E,$6D
    FCB $69,$63,$4E,$87,$13,$06,$DB,$00,$8F,$D6,$D7,$A4,$A5,$B2,$DB,$B8
    FCB $3D,$AC,$6D,$21,$19,$6A,$69,$BA,$DF,$CC,$CE,$F4,$3A,$ED,$56,$9E
    FCB $A3,$75,$3B,$5B,$36,$78,$D9,$DF,$8C,$56,$B7,$30,$6B,$FF,$C6,$0A
    FCB $23,$A9,$AD,$76,$C5,$63,$AB,$AD,$8D,$1E,$48,$A5,$49,$FF,$C3,$03
    FCB $F4,$D6,$82,$F4,$5A,$90,$A9,$6C,$DB,$A6,$EE,$D3,$11,$B1,$78,$41
    FCB $4D,$D6,$9B,$34,$95,$97,$A5,$F8,$1D,$FB,$BE,$F1,$AC,$F4,$C7,$56
    FCB $4D,$97,$E4,$77,$8D,$6B,$E5,$DA,$62,$9C,$65,$F5,$6E,$A1,$69,$ED
    FCB $49,$2C,$A7,$0D,$19,$35,$98,$DE,$F6,$49,$5D,$D4,$B7,$13,$F6,$A1
    FCB $7E,$A6,$D2,$14,$D5,$4D,$A6,$DF,$F8,$86,$BD,$B1,$2E,$89,$86,$CF
    FCB $E6,$D6,$CE,$7B,$67,$FE,$C4,$B6,$EF,$15,$5F,$59,$F3,$01,$AB,$4C
    FCB $BB,$2A,$EB,$58,$A0,$B6,$D1,$94,$AC,$51,$27,$FF,$0C,$39,$D3,$68
    FCB $97,$A2,$5C,$52,$15,$D5,$B5,$D6,$B6,$ED,$15,$49,$44,$95,$15,$B1
    FCB $6E,$82,$BA,$45,$25,$3E,$F2,$1A,$89,$DB,$DF,$AD,$7D,$B1,$4F,$13
    FCB $54,$3D,$9C,$8F,$FF,$6D,$AF,$16,$56,$D0,$65,$42,$94,$75,$F7,$50
    FCB $F8,$51,$6B,$6A,$51,$04,$D3,$2A,$62,$A2,$F1,$6D,$4E,$C6,$50,$5C
    FCB $52,$42,$DB,$6B,$12,$35,$A7,$50,$77,$5F,$6C,$6C,$89,$09,$BB,$D0
    FCB $9A,$20,$5F,$DF,$8F,$C3,$AF,$D8,$3D,$E7,$CE,$CF,$F1,$26,$D6,$31
    FCB $55,$B9,$66,$FF,$9E,$D9,$83,$68,$F4,$8C,$50,$67,$FF,$0C,$39,$D6
    FCB $D6,$8B,$41,$71,$0A,$4B,$62,$DD,$CD,$EE,$10,$C1,$D3,$64,$FB,$77
    FCB $DA,$92,$E4,$26,$CB,$EB,$EB,$5B,$B6,$AA,$96,$0E,$28,$2C,$BB,$B7
    FCB $73,$83,$59,$4D,$8B,$71,$6A,$51,$5A,$DF,$49,$4A,$5D,$AE,$A2,$34
    FCB $E3,$89,$57,$6B,$5D,$46,$2F,$C3,$2C,$EE,$AF,$11,$74,$2F,$EB,$96
    FCB $9A,$73,$7F,$D4,$F7,$FE,$6E,$1B,$1F,$7F,$FD,$A9,$4F,$1A,$FF,$79
    FCB $9A,$97,$E2,$D5,$DE,$A0,$15,$4D,$B7,$FD,$6F,$3E,$A7,$EF,$F1,$D1
    FCB $E9,$2B,$15,$0E,$47,$F8,$64,$CE,$B6,$D0,$74,$4E,$A4,$22,$6C,$7E
    FCB $5B,$76,$FF,$12,$02,$DB,$6D,$6B,$B6,$DC,$05,$29,$52,$A1,$81,$ED
    FCB $96,$FB,$5A,$26,$DA,$94,$A8,$38,$03,$DB,$6D,$34,$4D,$B1,$25,$02
    FCB $43,$59,$41,$58,$A8,$92,$83,$71,$DB,$77,$AD,$53,$1B,$B6,$0B,$4C
    FCB $33,$6A,$69,$8E,$D8,$A0,$16,$A5,$F8,$BC,$B3,$1D,$5B,$66,$E9,$DE
    FCB $B3,$C3,$EC,$EB,$FF,$56,$53,$EC,$AB,$A7,$34,$97,$7C,$67,$70,$11
    FCB $ED,$04,$71,$38,$A8,$C6,$BB,$55,$F4,$85,$DA,$DD,$2D,$54,$FB,$77
    FCB $A9,$DE,$7E,$68,$F4,$8C,$21,$99,$C7,$C8,$4E,$5A,$DD,$13,$A0,$AE
    FCB $45,$C4,$94,$F5,$AE,$DB,$11,$24,$E4,$42,$A2,$34,$4D,$E5,$51,$B0
    FCB $B2,$4A,$87,$9F,$71,$BD,$6B,$52,$25,$E2,$8D,$C1,$46,$36,$B4,$EE
    FCB $0B,$69,$29,$72,$E5,$E0,$45,$B2,$BA,$32,$9B,$69,$D6,$DB,$52,$4B
    FCB $8B,$32,$92,$28,$EA,$5A,$C2,$E2,$B4,$91,$5D,$A6,$B9,$15,$6A,$BE
    FCB $45,$89,$63,$5B,$1A,$D4,$DA,$CA,$63,$F2,$FE,$6D,$8A,$DB,$3A,$84
    FCB $E0,$A5,$B5,$3D,$33,$6A,$5F,$FE,$3A,$81,$1F,$40,$8D,$D6,$C5,$09
    FCB $3D,$6D,$3F,$A9,$4B,$7B,$62,$B4,$A9,$F1,$6B,$F1,$4B,$FF,$07,$46
    FCB $50,$6A,$03,$33,$8F,$92,$1F,$AD,$D3,$5D,$05,$C5,$8B,$69,$21,$17
    FCB $A2,$68,$6D,$B4,$4E,$E2,$90,$81,$A6,$9B,$AD,$08,$97,$E4,$92,$6E
    FCB $4F,$EE,$DB,$4D,$13,$70,$53,$A4,$61,$2E,$0E,$B1,$68,$96,$6A,$14
    FCB $90,$DA,$F6,$56,$37,$AC,$4B,$91,$6E,$D4,$A5,$DA,$2D,$C4,$39,$75
    FCB $D8,$36,$92,$B0,$4F,$AD,$FC,$AB,$2A,$76,$EA,$71,$13,$AB,$53,$5A
    FCB $2B,$6A,$AF,$64,$F6,$6D,$D5,$B9,$F7,$D4,$DC,$14,$24,$B6,$D0,$73
    FCB $37,$D9,$05,$09,$DB,$05,$D4,$21,$53,$4D,$6D,$76,$71,$FE,$6A,$AC
    FCB $CB,$4B,$A2,$AF,$9B,$A9,$4D,$48,$F5,$37,$A8,$0C,$CE,$3E,$49,$CE
    FCB $BB,$69,$D1,$2E,$24,$26,$D4,$50,$2D,$A6,$6E,$FB,$A9,$49,$4B,$4D
    FCB $C1,$4A,$2F,$09,$EC,$C5,$38,$7B,$DB,$EB,$44,$8A,$D9,$42,$B1,$08
    FCB $C2,$BB,$EA,$6D,$43,$6D,$13,$60,$92,$AF,$95,$5D,$77,$FE,$37,$A9
    FCB $AD,$56,$B5,$D5,$14,$96,$F5,$B5,$A9,$C7,$E8,$56,$30,$6E,$36,$5C
    FCB $3E,$C3,$75,$FB,$AD,$7B,$07,$B0,$F1,$69,$28,$1D,$6B,$6F,$7C,$FB
    FCB $80,$24,$26,$DB,$7E,$AB,$7A,$9D,$E0,$BE,$57,$21,$53,$B6,$B3,$67
    FCB $9B,$C5,$87,$A4,$AD,$68,$35,$62,$DD,$C5,$29,$A3,$D4,$B0,$A4,$07
    FCB $CE,$3D,$95,$4F,$37,$6D,$3A,$05,$71,$69,$26,$D2,$52,$D3,$B5,$B1
    FCB $4E,$A9,$81,$0B,$7B,$A6,$B0,$B8,$90,$1A,$20,$89,$0E,$1E,$ED,$B5
    FCB $B5,$A6,$D6,$46,$D4,$EA,$14,$69,$B6,$FC,$51,$55,$E4,$55,$F5,$B2
    FCB $D6,$92,$8B,$5A,$D5,$EE,$DA,$C4,$88,$8A,$25,$9B,$18,$9B,$7B,$2F
    FCB $19,$5C,$53,$15,$DA,$7B,$AF,$27,$6A,$6F,$AA,$9A,$F0,$F6,$92,$48
    FCB $24,$16,$11,$8B,$5D,$E6,$EA,$79,$7C,$16,$76,$3E,$3E,$A6,$CC,$6F
    FCB $FE,$0F,$DF,$AC,$57,$69,$21,$40,$E2,$DF,$2A,$56,$89,$89,$65,$66
    FCB $35,$D1,$94,$D4,$52,$03,$E7,$1E,$C8,$47,$9E,$DA,$74,$0A,$E0,$26
    FCB $D4,$A7,$FF,$23,$F3,$DB,$7A,$DB,$6F,$52,$15,$2A,$35,$BE,$06,$63
    FCB $2D,$6D,$AE,$EB,$96,$F6,$A5,$0F,$5A,$6B,$20,$A0,$BA,$B9,$04,$56
    FCB $9A,$94,$28,$16,$F6,$DA,$6D,$EF,$C5,$24,$F5,$A9,$4A,$0D,$A7,$6B
    FCB $77,$C6,$AE,$C6,$CA,$94,$1B,$5A,$77,$6F,$A9,$55,$FB,$E9,$2D,$6F
    FCB $53,$A5,$A6,$A4,$29,$E9,$97,$8C,$35,$C5,$45,$CD,$8D,$F9,$36,$DB
    FCB $D4,$C4,$6D,$A2,$59,$A9,$6D,$5E,$3C,$6D,$1A,$23,$B4,$14,$74,$EC
    FCB $CD,$A9,$4B,$DD,$99,$6A,$D7,$9D,$A9,$5A,$D7,$A1,$53,$52,$A8,$40
    FCB $F3,$C7,$BE,$A8,$7D,$37,$69,$D1,$38,$AA,$6D,$49,$3E,$5D,$E5,$F3
    FCB $BA,$D0,$5A,$86,$A4,$2D,$6C,$15,$0D,$60,$D6,$B5,$E2,$84,$85,$CA
    FCB $FD,$ED,$BB,$02,$26,$BB,$06,$43,$35,$81,$C5,$A2,$EA,$48,$53,$5A
    FCB $D3,$F1,$AF,$6F,$C1,$26,$CA,$4D,$56,$0D,$FB,$7B,$D7,$AD,$8A,$8A
    FCB $55,$44,$6B,$4E,$D8,$DE,$14,$FC,$31,$6B,$E5,$9B,$50,$E3,$A4,$8A
    FCB $FA,$BB,$90,$2A,$DB,$4F,$75,$78,$9D,$91,$0A,$D4,$ED,$37,$CB,$F1
    FCB $F2,$2A,$23,$D3,$40,$CD,$24,$93,$6D,$35,$29,$EB,$BF,$CE,$DF,$14
    FCB $DF,$1B,$42,$44,$A8,$54,$1B,$CC,$DD,$C6,$96,$B7,$6D,$76,$DA,$84
    FCB $4E,$44,$4D,$55,$2A,$5F,$FF,$9B,$5A,$25,$BF,$49,$51,$45,$44,$A6
    FCB $BB,$44,$B7,$71,$49,$2A,$72,$FB,$9B,$FB,$5D,$84,$93,$EC,$2F,$5A
    FCB $FC,$5A,$AF,$5C,$05,$6D,$6C,$23,$83,$B5,$6D,$8D,$62,$83,$77,$F1
    FCB $B3,$CA,$BA,$EB,$CD,$5B,$5B,$76,$DC,$D5,$F4,$13,$93,$E5,$D9,$6F
    FCB $49,$7E,$A6,$A5,$C8,$2C,$D0,$B5,$B6,$DE,$A8,$AD,$65,$77,$72,$F8
    FCB $CC,$63,$D8,$E0,$15,$B7,$A4,$BD,$A5,$5E,$A5,$AB,$AD,$BF,$FF,$A1
    FCB $53,$12,$10,$84,$CF,$F6,$D6,$B8,$DA,$F7,$98,$53,$70,$52,$2B,$A5
    FCB $CF,$FE,$3B,$F7,$F0,$C6,$0A,$04,$96,$89,$6B,$5B,$BD,$58,$CB,$23
    FCB $06,$46,$F2,$3F,$F7,$FF,$98,$BF,$AD,$C8,$BD,$B0,$2A,$1C,$5E,$D4
    FCB $A1,$D7,$9D,$B7,$6B,$4D,$93,$12,$1D,$67,$18,$F6,$E4,$AD,$4E,$D5
    FCB $55,$75,$AD,$6C,$8A,$52,$94,$20,$5A,$9F,$4A,$B6,$DA,$9C,$18,$ED
    FCB $A9,$FB,$6A,$00,$49,$3E,$9A,$84,$2D,$A0,$59,$36,$AB,$2D,$F0,$BB
    FCB $2D,$E2,$96,$1D,$57,$5A,$D9,$B1,$BC,$9C,$7E,$DF,$E4,$BE,$A5,$68
    FCB $44,$60,$99,$F7,$AE,$89,$D7,$6B,$75,$89,$28,$0B,$4D,$B8,$D3,$6A
    FCB $49,$40,$4B,$FD,$FC,$8F,$7F,$56,$DF,$A8,$17,$5D,$FF,$C7,$90,$66
    FCB $DC,$DC,$37,$B7,$EF,$9F,$8F,$1D,$EE,$49,$BB,$6D,$C1,$4A,$1B,$EC
    FCB $EB,$C6,$89,$3D,$C1,$49,$06,$D4,$ED,$74,$8A,$DA,$D2,$B5,$B6,$B8
    FCB $92,$16,$2D,$A6,$B6,$CA,$A2,$4A,$10,$2C,$A8,$49,$1A,$82,$9A,$D6
    FCB $D0,$B2,$E9,$27,$12,$4D,$63,$76,$93,$D7,$67,$86,$B5,$3C,$71,$5A
    FCB $93,$65,$A4,$B5,$FE,$A8,$B1,$CC,$1B,$6D,$BE,$29,$6C,$22,$49,$36
    FCB $9A,$27,$FF,$06,$CC,$05,$0D,$A9,$48,$CA,$86,$6E,$B7,$B5,$A0,$A6
    FCB $B7,$FA,$40,$54,$B5,$AD,$AC,$8B,$D2,$42,$A2,$13,$1A,$EC,$65,$90
    FCB $67,$DD,$B4,$D3,$25,$49,$5B,$CC,$DE,$FC,$0B,$BC,$CB,$E4,$6A,$5B
    FCB $8F,$78,$FE,$A5,$EE,$3F,$50,$5B,$A7,$75,$B9,$6A,$50,$C3,$E2,$C6
    FCB $3A,$2B,$94,$86,$EA,$B7,$98,$35,$D3,$56,$DB,$3A,$AA,$66,$A4,$45
    FCB $82,$B4,$1B,$AA,$95,$A6,$B6,$A7,$36,$FC,$6A,$57,$4F,$CA,$DF,$12
    FCB $4F,$AB,$D6,$52,$82,$08,$A5,$47,$52,$DA,$DD,$F2,$BF,$98,$E6,$F5
    FCB $84,$42,$A6,$DA,$0A,$DE,$7C,$FF,$A8,$62,$94,$8C,$94,$25,$F4,$4B
    FCB $6B,$5B,$44,$BB,$FD,$52,$A6,$B6,$E4,$AE,$21,$49,$41,$1F,$2E,$F3
    FCB $3E,$FD,$63,$69,$AE,$C5,$24,$18,$EA,$EB,$DE,$E1,$8E,$A8,$57,$6E
    FCB $58,$7E,$DB,$78,$07,$53,$74,$E6,$E3,$96,$E9,$95,$DF,$CB,$99,$14
    FCB $57,$95,$AD,$26,$A4,$9A,$D3,$AD,$2A,$81,$EE,$DE,$BF,$42,$9E,$EF
    FCB $14,$85,$4B,$D6,$24,$ED,$06,$9C,$DC,$74,$96,$F8,$BF,$D5,$DE,$71
    FCB $6A,$ED,$E4,$52,$ED,$8C,$D4,$D7,$50,$A5,$2A,$B6,$9A,$96,$E2,$D5
    FCB $7A,$96,$F6,$A5,$57,$B6,$A5,$EE,$3E,$E6,$2E,$65,$FF,$51,$D0,$A3
    FCB $25,$96,$BB,$AD,$05,$6B,$6E,$FF,$E7,$1F,$D5,$49,$75,$24,$01,$7B
    FCB $FF,$FF,$DD,$AD,$EA,$CC,$F0,$F7,$BB,$BC,$0A,$9D,$52,$9A,$76,$D6
    FCB $92,$9D,$27,$ED,$35,$AE,$54,$A4,$2F,$65,$DF,$56,$5E,$B8,$C7,$41
    FCB $59,$DA,$4D,$C5,$B3,$52,$AA,$80,$D6,$8C,$D4,$D6,$22,$AE,$75,$D9
    FCB $B2,$FA,$AF,$63,$C6,$85,$23,$60,$9D,$A0,$47,$8A,$58,$5D,$B3,$AE
    FCB $AD,$EF,$57,$D8,$CC,$73,$8B,$7F,$22,$1A,$DA,$B1,$4B,$5B,$4C,$76
    FCB $02,$49,$91,$77,$6A,$FD,$8F,$5F,$C6,$CE,$C4,$BA,$7F,$BA,$8E,$85
    FCB $1E,$91,$D0,$53,$AD,$6D,$36,$FE,$3F,$E7,$9E,$23,$D2,$93,$7F,$76
    FCB $CF,$66,$FC,$1F,$B1,$97,$E0,$76,$DE,$EB,$EC,$57,$CE,$B4,$44,$5D
    FCB $4E,$86,$0E,$B6,$DF,$D4,$F3,$90,$A4,$EB,$59,$14,$A1,$15,$A6,$8B
    FCB $E1,$77,$72,$24,$F0,$55,$35,$3B,$62,$C5,$0D,$DA,$65,$5B,$71,$D4
    FCB $D7,$3F,$DA,$92,$75,$6C,$A0,$5C,$CD,$F7,$39,$56,$B1,$F1,$60,$1A
    FCB $ED,$E9,$75,$E7,$6A,$ED,$4B,$83,$60,$EB,$C6,$D2,$63,$06,$D9,$81
    FCB $B5,$AE,$FF,$F1,$78,$CF,$7F,$C0,$7A,$48,$45,$5B,$44,$B5,$AF,$7F
    FCB $FF,$9E,$7F,$47,$A1,$67,$3F,$77,$9B,$72,$D9,$6A,$01,$8F,$BF,$5A
    FCB $CD,$5D,$BF,$63,$D5,$6F,$66,$EB,$2D,$74,$30,$54,$EB,$FE,$2D,$F9
    FCB $F5,$14,$D6,$AD,$08,$B7,$E8,$9D,$D4,$A6,$EE,$D7,$9A,$8B,$07,$AD
    FCB $75,$6A,$6C,$7B,$CA,$F1,$C7,$EA,$76,$05,$7B,$42,$A3,$10,$2D,$EC
    FCB $2F,$35,$69,$82,$1D,$35,$BF,$20,$6B,$1B,$22,$FD,$F9,$E9,$2D,$E5
    FCB $A5,$D7,$69,$5A,$96,$92,$2D,$A4,$D7,$B8,$FC,$7B,$1F,$C5,$9F,$73
    FCB $FA,$A0,$BC,$55,$4B,$58,$9B,$6F,$FF,$FE,$79,$FD,$0A,$3D,$9E,$DB
    FCB $2E,$7B,$FA,$A4,$FF,$BC,$77,$C8,$ED,$B2,$EF,$60,$7D,$D7,$75,$0E
    FCB $A5,$0F,$78,$D1,$3E,$94,$17,$55,$CE,$C2,$2D,$17,$42,$35,$B6,$56
    FCB $CC,$6D,$E4,$D7,$AB,$C9,$6B,$5A,$51,$CD,$8C,$5E,$DE,$F5,$33,$2E
    FCB $47,$C6,$A4,$BA,$04,$49,$76,$BD,$5A,$96,$BF,$55,$ED,$F9,$60,$0A
    FCB $63,$ED,$DB,$DF,$42,$D7,$0A,$97,$C4,$9D,$A6,$2D,$2D,$60,$9E,$29
    FCB $24,$4A,$AF,$17,$EF,$C7,$BD,$E6,$F3,$FF,$F7,$C9,$AD,$FF,$FF,$C9
    FCB $FF,$12,$46,$61,$DD,$FB,$36,$E3,$D4,$2A,$A6,$45,$EF,$7F,$1F,$22
    FCB $DC,$6F,$E6,$DE,$DF,$C9,$55,$21,$31,$B6,$EB,$B8,$52,$7E,$FB,$2F
    FCB $1A,$9F,$16,$BB,$79,$9A,$F3,$1F,$80,$F5,$5B,$73,$AE,$A9,$6A,$5D
    FCB $EB,$56,$FF,$17,$C6,$CE,$C4,$81,$34,$65,$26,$DA,$21,$F6,$33,$1B
    FCB $7E,$7B,$53,$82,$AE,$D4,$9C,$F5,$38,$9C,$55,$D6,$2F,$62,$15,$68
    FCB $AB,$C9,$76,$A5,$A9,$6A,$05,$6B,$6B,$1A,$E4,$42,$BB,$4F,$FB,$37
    FCB $F1,$9F,$F6,$0B,$D9,$F6,$76,$5F,$87,$CF,$52,$3E,$11,$AF,$BF,$8F
    FCB $96,$38,$43,$63,$DB,$38,$ED,$CB,$06,$33,$87,$6D,$DC,$79,$82,$CA
    FCB $DC,$D4,$FD,$97,$76,$9F,$8D,$E0,$CD,$9E,$DF,$82,$6F,$85,$CE,$51
    FCB $93,$66,$2E,$6D,$9D,$FD,$95,$75,$DF,$4A,$FD,$F5,$BA,$8B,$52,$EF
    FCB $9F,$66,$D9,$CB,$F8,$FA,$4B,$F8,$C1,$1E,$9A,$DB,$6B,$A4,$E4,$17
    FCB $6D,$D5,$B8,$F3,$31,$6A,$4F,$1D,$5D,$3F,$1F,$FE,$C7,$F3,$FF,$CF
    FCB $7D,$FC,$7F,$E7,$0D,$4B,$63,$E2,$34,$1A,$55,$F9,$B7,$37,$24,$FB
    FCB $F8,$D8,$DE,$38,$C7,$54,$19,$FE,$3F,$DE,$33,$B5,$2D,$33,$1C,$DA
    FCB $D7,$74,$9B,$63,$5B,$F3,$E2,$AB,$DB,$10,$E8,$94,$9F,$2C,$F7,$88
    FCB $69,$ED,$45,$EB,$67,$83,$DB,$0D,$AA,$BD,$A4,$A7,$B6,$76,$D7,$D4
    FCB $B3,$ED,$40,$85,$48,$2D,$B7,$66,$0D,$F8,$F6,$4D,$D4,$CA,$96,$FB
    FCB $AA,$E5,$E3,$61,$6F,$57,$5F,$A1,$45,$7F,$39,$31,$AD,$78,$FE,$3F
    FCB $0F,$BF,$67,$1F,$EF,$97,$FC,$D4,$A2,$0D,$6D,$BE,$A7,$8A,$22,$B1
    FCB $F7,$39,$B6,$71,$E7,$7D,$FB,$CD,$5B,$6E,$31,$4F,$27,$1F,$1A,$CD
    FCB $6A,$6B,$5E,$90,$DB,$AD,$73,$51,$4C,$B6,$DF,$CD,$43,$ED,$D5,$C6
    FCB $65,$17,$8F,$AA,$BE,$02,$F8,$71,$BE,$EC,$70,$72,$EA,$C5,$D4,$EE
    FCB $EB,$FF,$55,$BD,$1A,$8B,$F0,$18,$90,$DB,$4D,$C1,$50,$6D,$35,$F8
    FCB $F2,$8C,$B5,$AA,$14,$ED,$A9,$74,$A3,$8E,$D9,$5E,$CE,$52,$4D,$DC
    FCB $3D,$77,$E7,$FD,$81,$EB,$56,$EF,$8F,$EF,$CF,$FF,$14,$F7,$BC,$8A
    FCB $5F,$15,$AB,$81,$B5,$0E,$A1,$6D,$6E,$5F,$B8,$FF,$D4,$6D,$DB,$6F
    FCB $15,$49,$7E,$2B,$6B,$7C,$07,$76,$B5,$EA,$03,$5B,$77,$8A,$4F,$DC
    FCB $A7,$31,$D5,$BD,$F4,$AF,$8D,$F1,$D2,$83,$6B,$C1,$EF,$1E,$35,$FE
    FCB $39,$BF,$FD,$41,$6E,$BE,$2C,$FB,$D5,$1E,$C5,$3D,$31,$46,$C5,$A8
    FCB $A9,$14,$75,$B9,$B8,$A3,$6D,$B8,$0F,$2F,$2A,$1D,$AE,$DF,$F8,$A5
    FCB $FF,$ED,$F9,$23,$8E,$F1,$CE,$5E,$FF,$F7,$E7,$FF,$22,$F2,$CE,$21
    FCB $49,$95,$97,$C9,$BB,$50,$B5,$54,$B6,$A5,$B3,$FF,$F1,$CB,$A6,$9B
    FCB $20,$D3,$82,$4A,$EC,$5A,$56,$D1,$3E,$92,$92,$5F,$77,$AE,$A5,$45
    FCB $B5,$8E,$2C,$0E,$FA,$EC,$C6,$85,$DA,$D4,$DB,$CB,$01,$D5,$A4,$D9
    FCB $B1,$AE,$E2,$DF,$7F,$F8,$4D,$B6,$3D,$93,$74,$A5,$B2,$EB,$F6,$79
    FCB $6A,$D2,$4C,$5E,$EC,$82,$48,$B7,$FB,$38,$59,$71,$60,$41,$6D,$CF
    FCB $1A,$97,$AA,$D7,$AF,$F8,$4F,$B6,$DF,$9C,$A9,$EC,$5F,$8F,$FF,$99
    FCB $63,$BF,$FF,$8F,$EA,$5F,$D2,$46,$7A,$DA,$4E,$5F,$AD,$75,$14,$25
    FCB $CA,$F9,$1E,$16,$6E,$75,$A6,$CC,$49,$37,$5A,$94,$BB,$4E,$D5,$A1
    FCB $AD,$E1,$70,$53,$DD,$6B,$43,$1B,$FB,$AA,$DB,$7F,$59,$A9,$AA,$F6
    FCB $D9,$27,$78,$09,$21,$16,$DA,$24,$DF,$2F,$89,$CC,$B3,$07,$FF,$5B
    FCB $3D,$CC,$75,$74,$C3,$63,$37,$3D,$DE,$59,$83,$EC,$7F,$66,$A6,$FC
    FCB $7D,$55,$2F,$5F,$FF,$3E,$BF,$CF,$1B,$FD,$F3,$C7,$4B,$11,$3E,$7F
    FCB $98,$F0,$65,$B7,$86,$D9,$DF,$D9,$F0,$3B,$A4,$C4,$87,$6E,$DD,$44
    FCB $55,$B7,$81,$DB,$67,$0B,$3A,$EA,$44,$AE,$8C,$2D,$D0,$56,$B0,$91
    FCB $B4,$86,$B7,$DB,$05,$7D,$24,$D7,$C2,$E3,$10,$BA,$D6,$2D,$6F,$C2
    FCB $5D,$E2,$FA,$B9,$AD,$92,$92,$5B,$44,$9B,$BA,$42,$E6,$B9,$EC,$C9
    FCB $95,$5D,$AD,$67,$BF,$19,$04,$29,$B1,$B7,$F7,$FD,$4F,$CE,$EA,$E9
    FCB $8F,$F2,$21,$6D,$DB,$B5,$63,$3A,$6A,$F6,$38,$44,$96,$DB,$5F,$0F
    FCB $69,$68,$BD,$9F,$FF,$FF,$FE,$71,$B1,$43,$82,$DA,$E3,$FF,$FF,$0D
    FCB $8C,$D9,$70,$52,$42,$FB,$D8,$C0,$BD,$96,$D8,$C0,$6C,$87,$F4,$D5
    FCB $62,$3E,$EA,$40,$AD,$B6,$24,$DE,$0B,$6C,$6A,$72,$AB,$31,$36,$70
    FCB $60,$D4,$A6,$DA,$60,$ED,$DB,$76,$7F,$60,$AB,$B6,$31,$9B,$49,$4E
    FCB $D6,$FD,$59,$A6,$CC,$6F,$90,$9F,$6D,$FF,$37,$02,$85,$36,$B7,$6C
    FCB $F7,$38,$F9,$F7,$3B,$9E,$3E,$0E,$0C,$43,$EB,$6D,$B6,$A5,$BF,$F8
    FCB $1A,$DD,$5E,$C8,$69,$DF,$FC,$9B,$2D,$FF,$3E,$3D,$F2,$4B,$B7,$79
    FCB $1E,$E3,$E5,$58,$D6,$71,$BE,$29,$0A,$C3,$9C,$06,$B5,$A6,$DC,$53
    FCB $6E,$28,$6A,$20,$F8,$BF,$05,$6D,$75,$F5,$09,$DB,$2D,$91,$C7,$CE
    FCB $FC,$14,$B8,$B5,$37,$B8,$AB,$6D,$7F,$8E,$D9,$3A,$9C,$75,$6E,$BA
    FCB $4E,$2C,$97,$1F,$6B,$E5,$F9,$E3,$F7,$F3,$36,$C5,$6B,$6F,$DA,$9E
    FCB $59,$8C,$25,$AF,$7F,$9F,$18,$AE,$B1,$33,$46,$6E,$2A,$89,$B6,$15
    FCB $F1,$AB,$6F,$C1,$91,$DA,$A2,$1B,$4E,$B2,$B7,$E6,$0A,$5B,$BD,$FC
    FCB $FC,$D7,$CC,$DE,$FF,$1F,$FF,$0E,$C7,$EF,$89,$24,$B0,$35,$6B,$ED
    FCB $6B,$77,$01,$4E,$D3,$52,$94,$30,$EE,$16,$E7,$6D,$6F,$0B,$DE,$DE
    FCB $95,$95,$B4,$8D,$31,$F8,$A7,$B6,$D5,$2A,$96,$BA,$23,$1C,$DB,$AA
    FCB $59,$B1,$4D,$7D,$B5,$40,$36,$B6,$76,$FD,$FC,$BF,$FF,$3B,$3E,$FD
    FCB $C8,$0F,$8D,$83,$1B,$1D,$49,$BE,$3A,$B6,$C3,$B5,$77,$6C,$05,$54
    FCB $DE,$B5,$FF,$D2,$5F,$77,$C5,$2D,$F2,$41,$4B,$2F,$5B,$D8,$AF,$AF
    FCB $F7,$FF,$CF,$CF,$B8,$DF,$8F,$9F,$1E,$46,$5D,$7E,$52,$43,$C6,$DF
    FCB $18,$F5,$8A,$BA,$21,$5D,$36,$A0,$8A,$DD,$B1,$85,$6B,$19,$6A,$8D
    FCB $2B,$B7,$17,$B5,$29,$6A,$B1,$55,$D3,$AD,$F5,$0A,$EB,$66,$4C,$B5
    FCB $AA,$E8,$99,$F2,$24,$A5,$BC,$52,$DD,$AE,$B5,$60,$75,$AC,$3B,$1F
    FCB $1F,$BF,$E7,$86,$B7,$FB,$C2,$D2,$D4,$9B,$06,$F3,$F7,$6D,$48,$74
    FCB $1B,$3E,$E0,$A1,$DA,$DF,$84,$ED,$FB,$0D,$A4,$D7,$EF,$C7,$95,$2F
    FCB $E2,$AD,$4B,$5B,$C1,$AA,$0B,$5E,$E0,$69,$FF,$F9,$37,$7C,$7E,$C3
    FCB $D9,$3C,$EC,$71,$C1,$C4,$87,$8A,$41,$5D,$A8,$AA,$57,$49,$C4,$4D
    FCB $DA,$87,$05,$D2,$76,$26,$D0,$BA,$AB,$4F,$6A,$C0,$0D,$AC,$AF,$64
    FCB $55,$D4,$D7,$5B,$1C,$A9,$45,$D6,$F8,$CE,$E1,$D1,$2F,$9E,$21,$49
    FCB $6F,$52,$9A,$ED,$6B,$7D,$57,$EE,$AE,$FE,$4D,$AF,$F9,$20,$5A,$D3
    FCB $F1,$DE,$A5,$2D,$0F,$4C,$7A,$96,$E7,$16,$F8,$6F,$3A,$FC,$1F,$79
    FCB $F3,$76,$F1,$A5,$95,$2D,$77,$03,$16,$B3,$06,$F7,$F4,$9B,$E3,$AB
    FCB $16,$3D,$E4,$AF,$BF,$3F,$96,$47,$1B,$7F,$E3,$E4,$2E,$38,$0A,$C8
    FCB $A4,$DB,$14,$9A,$F5,$82,$4E,$F9,$55,$35,$DA,$95,$5C,$60,$B1,$DA
    FCB $49,$38,$E8,$9D,$66,$4B,$56,$CB,$F7,$57,$B5,$DB,$0E,$07,$63,$DE
    FCB $F7,$15,$C5,$AF,$AA,$BE,$A6,$28,$49,$54,$D7,$5F,$B7,$7F,$AB,$EF
    FCB $71,$28,$A4,$FB,$AD,$E4,$51,$6B,$5F,$EF,$AA,$D5,$BA,$97,$8B,$7F
    FCB $7C,$D5,$3E,$DB,$9D,$8F,$D4,$F5,$0B,$7E,$FD,$43,$80,$B7,$63,$9D
    FCB $7E,$47,$EC,$EC,$7E,$7C,$7E,$2A,$37,$5D,$FF,$E7,$1B,$E3,$FF,$F0
    FCB $9E,$CF,$54,$24,$49,$3B,$55,$6D,$B4,$D8,$AD,$64,$D4,$26,$9E,$2A
    FCB $F5,$2A,$F7,$9D,$8E,$36,$B2,$CA,$CC,$A9,$78,$3F,$5B,$EE,$CE,$A1
    FCB $F8,$F7,$1E,$E1,$28,$5A,$77,$04,$F5,$36,$28,$50,$D6,$BC,$53,$B6
    FCB $DB,$EA,$F0,$BD,$CC,$53,$67,$6B,$D9,$AB,$5B,$FF,$EC,$E5,$FD,$9D
    FCB $B3,$18,$71,$F5,$FF,$F8,$11,$92,$D6,$F0,$11,$84,$4D,$BB,$E3,$7D
    FCB $95,$F9,$FF,$FF,$48,$DA,$CB,$F8,$0D,$C6,$EC,$F9,$DE,$FB,$3F,$F9
    FCB $CB,$DC,$81,$52,$81,$D5,$5B,$53,$5B,$B6,$B7,$F5,$2B,$75,$F5,$24
    FCB $9A,$F1,$20,$95,$F6,$EB,$E3,$7C,$2B,$E1,$DC,$E9,$36,$BD,$B6,$AC
    FCB $B7,$E3,$FF,$E7,$51,$DE,$F5,$56,$28,$B7,$5C,$3B,$5B,$FA,$9B,$C9
    FCB $90,$76,$DB,$B8,$58,$0D,$96,$DF,$9F,$67,$D9,$C6,$77,$BF,$3F,$EB
    FCB $9F,$3B,$84,$A8,$DA,$D6,$E0,$A4,$6A,$26,$D6,$4D,$FE,$FE,$5E,$FF
    FCB $F8,$D4,$62,$65,$CB,$60,$65,$AD,$C0,$79,$77,$BE,$FC,$67,$E0,$33
    FCB $D8,$03,$12,$55,$B6,$C5,$B5,$2E,$AC,$4D,$6F,$01,$EF,$38,$B7,$B5
    FCB $0A,$95,$B4,$BD,$3D,$96,$42,$2E,$D7,$3B,$C8,$92,$A9,$DA,$D8,$8D
    FCB $29,$A6,$EE,$7B,$1F,$E6,$A8,$6B,$DE,$A1,$AC,$2B,$52,$4E,$AB,$4E
    FCB $D3,$FD,$27,$F3,$0D,$DB,$6B,$C0,$1B,$F8,$EF,$D9,$F8,$F6,$7E,$7B
    FCB $7C,$BF,$FF,$F9,$DC,$80,$A5,$2A,$D6,$89,$DE,$5E,$D4,$3E,$FC,$7A
    FCB $A2,$4D,$AE,$9F,$E2,$B1,$DE,$EC,$C1,$BD,$FF,$92,$FB,$FF,$7F,$FE
    FCB $7C,$99,$61,$10,$A9,$B5,$A7,$1C,$62,$5A,$96,$89,$38,$28,$E3,$BD
    FCB $C3,$4C,$65,$8B,$64,$49,$FB,$C2,$A6,$ED,$B6,$A3,$5B,$C1,$4A,$AD
    FCB $B6,$09,$6D,$34,$EE,$72,$D5,$EF,$EA,$B3,$7F,$2E,$5B,$49,$0B,$15
    FCB $5A,$76,$B6,$DC,$14,$3B,$92,$6B,$77,$BF,$8E,$4E,$C7,$7F,$FF,$B5
    FCB $37,$9F,$71,$5B,$77,$CB,$D9,$3F,$F6,$18,$0E,$D6,$A5,$EE,$3E,$4C
    FCB $6F,$BC,$50,$16,$B6,$C7,$C3,$80,$BD,$8B,$F6,$FF,$1F,$3F,$F7,$FB
    FCB $FF,$F8,$70,$C7,$81,$2E,$C6,$37,$6A,$4A,$56,$89,$77,$14,$A8,$A7
    FCB $EB,$67,$6A,$6A,$B6,$B6,$F2,$A7,$AE,$AE,$57,$E0,$AD,$6B,$C0,$2D
    FCB $BA,$8E,$D3,$59,$CE,$55,$DB,$BE,$5F,$01,$FB,$7C,$52,$41,$DB,$6D
    FCB $6B,$7C,$3B,$27,$6B,$FF,$FF,$0C,$97,$6B,$CF
HUFFIMG_END:
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
