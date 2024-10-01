;------------------------------------------------------------------------------
;
; ITOA64 - 64-BIT SIGNED INTEGER TO DECOMAL STRING - EXPERIMENTS
;
; THIS IS A FAIRLY NAIVE IMPLEMENTATION OF ITOA FOR 64-BIT INTEGERS.
;
; FOR FUN, AND TO COMPARE PERFORMANCE DIFFERENCES BETWEEN MC6809 AND HD6309,
; TWO DIFFERENT VERSIONS OF EACH FUNCTION ARE PROVIDED, ONE FOR EACH 
; ARCHITECTURE.
;
; THE PRIMARY DIFFERENCE BETWEEN THE TWO VERSIONS IS THAT THE 6809 DOES 
; EVERYTHING BYTE-WISE, WHILE THE HD6309 VERSION, WHERE POSSIBLE DOES 
; A LOT OF THINGS WORD-WISE. 
;
; (THE 6309 FCN NAMES HAVE A _3, WHILE 6809 ONES HAVE _8)
;
; FOR TIMING, IT GETS THE START AND END TIMES OF EACH TEST USING THE 
; PUGPUTER 6309'S INTERRUPT-BASED 16HZ TICK COUNTER.
; 
; HERE'S THE RESULTS I GOT.
;
;   CPU-MODE            CODE_VERSION            16HZ_TICKS
;   --------------      ------------            ----------
;   6309-NATIVE         6809                    187
;   6309-NATIVE         6309                    133   
;   6809-EMULATION      6809                    196
;   6809-EMULATION      6309                    144
;
;------------------------------------------------------------------------------
    INCLUDE bios_func_tab.d     ; BIOS functions jump table
;------------------------------------------------------------------------------
LF              EQU  $0A        ; LINE FEED
CR              EQU  $0D        ; CARRIAGE RETURN
NUL             EQU  $00
TEST_ITERATIONS EQU 40
;------------------------------------------------------------------------------
; ENTRYPOINT
;------------------------------------------------------------------------------
    ORG $2000
;------------------------------------------------------------------------------
START:
    JSR MAIN_8
    JSR MAIN_3
    RTS
;------------------------------------------------------------------------------
; CONSTS
;------------------------------------------------------------------------------
MSG_START   FCC  "RUNNING ITOA64 BENCHMARK (6"
            FCB  0
MSG_8       FCC  "8"
            FCB  0
MSG_3       FCC  "3"
            FCB  0
MSG_VER     FCC  "09 VER)... "
            FCB  0
MSG_TOOK    FCC  "DONE. ("
            FCB  0
MSG_END     FCC  " TICKS)"
MSG_CR      FCB  LF,CR,0
;------------------------------------------------------------------------------
; VARS
;------------------------------------------------------------------------------
; USED BY TESTS
SERBUF      RMB 32
STARTTICKS  RMB 8
ENDTICKS    RMB 8
TEST_IDX    RMB 1
; USED BY ITOA64
I64         RMB 8       ; WORKING VALUE
DIGIT       RMB 1       ; WORKING DIGIT
LEADZ       RMB 1       ; 1:IGNORING LEADING ZEROES
;------------------------------------------------------------------------------
; I64 POWERS OF 10, IN DESCENDING-ORDER, STARTING WITH 10^18
POWERS:
    FDB $0DE0,$B6B3,$A764,$0000
    FDB $0163,$4578,$5D8A,$0000
    FDB $0023,$86F2,$6FC1,$0000
    FDB $0003,$8D7E,$A4C6,$8000
    FDB $0000,$5Af3,$107A,$4000
    FDB $0000,$0918,$4E72,$A000
    FDB $0000,$00E8,$D4A5,$1000
    FDB $0000,$0017,$4876,$E800
    FDB $0000,$0002,$540B,$E400
    FDB $0000,$0000,$3B9A,$CA00
    FDB $0000,$0000,$05F5,$E100
    FDB $0000,$0000,$0098,$9680
    FDB $0000,$0000,$000F,$4240
    FDB $0000,$0000,$0001,$86A0
    FDB $0000,$0000,$0000,$2710
    FDB $0000,$0000,$0000,$03E8
    FDB $0000,$0000,$0000,$0064
    FDB $0000,$0000,$0000,$000A
    FDB $0000,$0000,$0000,$0001
TEST_VECTORS:
;                INPUT                       EXPECTED_RESULT
    FDB $0000,$0000,$0000,$0000     ;                    "0"
    FDB $FFFF,$FFFF,$FFFF,$FFFF     ;                   "-1"
    FDB $8000,$0000,$0000,$0001     ; "-9223372036854775807"
    FDB $7FFF,$FFFF,$FFFF,$FFFF     ;  "9223372036854775807"
    FDB $6DCE,$388D,$2268,$3D8E     ;  "7912323774155341198"
    FDB $042D,$E29E,$DBA9,$75E3     ;   "301145922021717475"
    FDB $956B,$1FF4,$42D8,$6D8C     ; "-7680009605596287604"
    FDB $5BB5,$4CE2,$0B9F,$00CB     ;  "6608272561977360587"
    FDB $53F3,$1C26,$4629,$A901     ;  "6049209675200178433"
    FDB $F534,$D33F,$EF79,$0672     ;  "-777764564074166670"
    FDB $63ED,$6274,$F6C4,$6F48     ;  "7200519633731088200"
    FDB $3382,$7281,$A3CA,$F21A     ;  "3711654944031044122"
    FDB $06E7,$D790,$8F3C,$9FDE     ;   "497603299726106590"
    FDB $8C0A,$82D1,$9DD8,$EDC1     ; "-8355722321824518719"
    FDB $A359,$093B,$F556,$CAE2     ; "-6676294819476223262"
    FDB $2A76,$6792,$F566,$982A     ;  "3059746877724858410"
    FDB $1DBE,$386E,$B05F,$261C     ;  "2143212520731518492"
    FDB $CC00,$59E6,$0631,$791C     ; "-3746896045490996964"
    FDB $B440,$A004,$3225,$3BFF     ; "-5458186808491426817"
    FDB $7AE4,$AF7B,$5545,$57B8     ;  "8855395711563683768"
    FDB $DB9D,$5E05,$DAE9,$B3FF     ; "-2621836028819164161"
    FDB $0C3C,$C474,$3945,$32D8     ;   "881795630513861336"
    FDB $1C4E,$55AF,$2001,$67AE     ;  "2039661891890014126"
    FDB $341F,$DCD1,$587D,$384A     ;  "3755963405941160010"
    FDB $8709,$6D7B,$1E25,$E080     ; "-8716315228244680576"
    FDB $B9EF,$89A4,$2809,$D981     ; "-5048665319119660671"
    FDB $66B8,$7BAA,$CA47,$B4ED     ;  "7401801961051763949"
    FDB $D89B,$5980,$EDB8,$D730     ; "-2838576729847965904"
    FDB $502C,$7AA0,$DAF0,$E364     ;  "5777127253296079716"
    FDB $37E6,$D013,$7198,$391C     ;  "4028135698658244892"
    FDB $81A2,$3793,$9D1C,$A806     ; "-9105654389454100474"
    FDB $11B9,$AA1D,$BF5E,$2F81     ;  "1277239014077640577"
    FDB $FFFA,$68EC,$F9A5,$3C0B     ;    "-1573482850337781"
    FDB $C0B9,$A811,$7B8A,$3BB8     ; "-4559428354695349320"
    FDB $E852,$35AD,$31C8,$23DC     ; "-1706242290839182372"
    FDB $E2F9,$B2F6,$9151,$BB1A     ; "-2091443779867133158"
    FDB $8FF2,$6D9B,$663E,$733C     ; "-8074270667719150788"
    FDB $7033,$84F1,$9E9C,$6C4B     ;  "8084951929343208523"
    FDB $3BF1,$C358,$7E4C,$FCDA     ;  "4319448302468529370"
    FDB $7A3A,$B9A2,$4A95,$F498     ;  "8807556127963608216"
    FDB $36CB,$06AF,$7D48,$21EF     ;  "3948256849111294447"
    FDB $448C,$CD9B,$AFB5,$2D11     ;  "4939548959870102801"
    FDB $01EF,$C92B,$D2B1,$6D30     ;   "139551303527394608"
    FDB $FAC8,$AD65,$47C3,$8473     ;  "-375859918378138509"
    FDB $9F54,$6DEF,$5EA8,$8E4A     ; "-6965821848782598582"
    FDB $AC8F,$8058,$34F6,$2F61     ; "-6012445861182296223"
    FDB $FE41,$4F75,$A284,$3934     ;  "-125731947933320908"
    FDB $4C2B,$FBC2,$8945,$567A     ;  "5488757383826331258"
    FDB $AB7E,$9485,$564B,$9B69     ; "-6089266345758975127"
    FDB $2AD7,$39D9,$CB15,$70A2     ;  "3086999677163630754"
;------------------------------------------------------------------------------
; MAINLOOP - 6809 VERSION
;------------------------------------------------------------------------------
MAIN_8:
    LDY  #MSG_CR
    JSR  BF_UT_PUTS
    LDY  #MSG_START
    JSR  BF_UT_PUTS
    LDY  #MSG_8
    JSR  BF_UT_PUTS
    LDY  #MSG_VER
    JSR  BF_UT_PUTS    
    JSR  BF_UT_WAITTX
    LDX  #STARTTICKS    ; GET STARTING SYS TICK COUNT (U64 16THS OF SECONDS)
    JSR  BF_RTC_GETTIX
    CLR  TEST_IDX
OLOOP_8:
    LDX  #TEST_VECTORS
MAINLOOP_8:
    LDY  #SERBUF
    JSR  ITOA64_8
    CMPX #MAIN_8
    BNE  MAINLOOP_8
    INC  TEST_IDX
    LDA  TEST_IDX
    CMPA #TEST_ITERATIONS
    BNE  OLOOP_8
    JMP  DO_END_TICKS
;------------------------------------------------------------------------------
; MAINLOOP - 6309 VERSION
;------------------------------------------------------------------------------
MAIN_3:
    LDY  #MSG_START
    JSR  BF_UT_PUTS
    LDY  #MSG_3
    JSR  BF_UT_PUTS
    LDY  #MSG_VER
    JSR  BF_UT_PUTS
    JSR  BF_UT_WAITTX
    LDX  #STARTTICKS    ; GET STARTING SYS TICK COUNT (U64 16THS OF SECONDS)
    JSR  BF_RTC_GETTIX  
    CLR  TEST_IDX
OLOOP_3:
    LDX  #TEST_VECTORS
MAINLOOP_3:
    LDY  #SERBUF
    JSR  ITOA64_3
    CMPX #MAIN_8
    BNE  MAINLOOP_3
    INC  TEST_IDX
    LDA  TEST_IDX
    CMPA #TEST_ITERATIONS
    BNE  OLOOP_3
    JMP  DO_END_TICKS
;------------------------------------------------------------------------------
DO_END_TICKS:
    LDX  #ENDTICKS      ; GET ENDING TICKCOUNT
    JSR  BF_RTC_GETTIX  
    LDX  #ENDTICKS
    LDU  #STARTTICKS
    JSR  SUB64_XU_3
    LDY  #MSG_TOOK
    JSR  BF_UT_PUTS
    LDY  #SERBUF
    JSR  ITOA64_3
    LDY  #SERBUF
    JSR  BF_UT_PUTS
    LDY  #MSG_END
    JSR  BF_UT_PUTS
    JSR  BF_UT_WAITTX
    RTS
;------------------------------------------------------------------------------
; GIVEN AN I64 AT X, NEGATE IT. (COMPLEMENT ALL WORDS, THEN ADD 1.)
;------------------------------------------------------------------------------
NEGATE64_8:
    LDA  #0
    SUBA  7,X
    STA   7,X
    LDA  #0
    SBCA  6,X
    STA   6,X
    LDA  #0
    SBCA  5,X
    STA   5,X
    LDA  #0
    SBCA  4,X
    STA   4,X
    LDA  #0
    SBCA  3,X
    STA   3,X
    LDA  #0
    SBCA  2,X
    STA   2,X
    LDA  #0
    SBCA  1,X
    STA   1,X
    LDA  #0
    SBCA  0,X
    STA   0,X
    RTS
;------------------------------------------------------------------------------
; GIVEN I64'S AT X AND U, SUBTRACT U FROM X, LEAVING RESULT IN X.
;------------------------------------------------------------------------------
SUB64_XU_8:
    LDA   7,X
    SUBA  7,U
    STA   7,X
    LDA   6,X
    SBCA  6,U
    STA   6,X
    LDA   5,X
    SBCA  5,U
    STA   5,X
    LDA   4,X
    SBCA  4,U
    STA   4,X
    LDA   3,X
    SBCA  3,U
    STA   3,X
    LDA   2,X
    SBCA  2,U
    STA   2,X
    LDA   1,X
    SBCA  1,U
    STA   1,X
    LDA   0,X
    SBCA  0,U
    STA   0,X
    RTS
;------------------------------------------------------------------------------
; GIVEN I64'S AT X AND U, COMPARE X TO U.
;------------------------------------------------------------------------------
CMP64_XU_8:
    ANDCC #$7E          ; CLEAR CARRY
    LDA   0,X
    CMPA  0,U
    BNE   DONECMP64
    LDA   1,X
    CMPA  1,U
    BNE   DONECMP64
    LDA   2,X
    CMPA  2,U
    BNE   DONECMP64
    LDA   3,X
    CMPA  3,U
    BNE   DONECMP64
    LDA   4,X
    CMPA  4,U
    BNE   DONECMP64
    LDA   5,X
    CMPA  5,U
    BNE   DONECMP64
    LDA   6,X
    CMPA  6,U
    BNE   DONECMP64
    LDA   7,X
    CMPA  7,U
    BNE   DONECMP64
DONECMP64:
    RTS      
;------------------------------------------------------------------------------
; GIVEN AN I64 AT X, OUTPUTS IT AS A NULL-TERMINATED DECIMAL STRING AT Y.
; ON RETURN, X WILL BE PAST THE 8-BYTE INPUT, AND Y WILL POINT AT THE STR NULL.
;------------------------------------------------------------------------------
ITOA64_8:
    LDD  ,X++           ; STASH I64 INPUT VALUE AT X TO TEMP WORKING VAR
    STD  I64+0
    LDD  ,X++
    STD  I64+2
    LDD  ,X++
    STD  I64+4
    LDD  ,X++
    STD  I64+6
    PSHS X
    LDA  I64
    ANDA #$80
    BEQ  DIDNEG
    LDX  #I64           ; IF I64 IS NEGATIVE, NEGATE IT,
    JSR  NEGATE64_8
    LDA  #'-'           ; AND OUTPUT A MINUS SIGN.
    STA  ,Y+
DIDNEG:
    LDX  #I64           ; X AT TMP64
    LDU  #POWERS        ; U AT POWERS TABLE
    LDA  #1
    STA  LEADZ          ; IGNORING LEADING ZEROES
IT64_LOOP:              ; FOR EACH POWER OF TEN (EACH DIGIT)
    LDA  #'0'
    STA  DIGIT
IT64_ILOOP:             ; CALCULATE A DIGIT
    JSR  CMP64_XU_8     ; WHILE TMP64 >= POWER:
    BLO  DONE_ILOOP
    INC  DIGIT          ;     DIGIT++
    JSR  SUB64_XU_8     ;     TMP64 -= POWER
    BRA  IT64_ILOOP
DONE_ILOOP:
    LDA  LEADZ          ; IF NOT IGNORING LEADING ZEROES,
    BEQ  ADDDIGIT       ; OUTPUT EVERY DIGIT.   
    LDA  DIGIT
    CMPA #'0'
    BNE  NONZERO        ; DIGIT IS NONZERO.
    CMPU #TEST_VECTORS-8 ; IF ALL ZEROES, DO OUTPUT THE LAST ONE.
    BEQ  NONZERO
    BRA  SKIPDIGIT      ; SKIP THIS ZERO DIGIT.
NONZERO:
    CLR  LEADZ          ; DONE IGNORING ZEROES.
ADDDIGIT:
    LDA  DIGIT          ; ADD DIGIT TO OUTPUT
    STA  ,Y+
SKIPDIGIT:
    LEAU 8,U            ; POINT U AT NEXT (LOWER) POWER OF 10, IF ANY.
    CMPU #POWERS+152    ; IF PLACE VALUES REMAINING,
    BNE  IT64_LOOP      ; DO NEXT ONE.
IT64_DONE:
    LDA  #0
    STA  ,Y
    PULS X
    RTS
;------------------------------------------------------------------------------
; GIVEN AN I64 AT X, NEGATE IT. (COMPLEMENT ALL WORDS, THEN ADD 1.)
;------------------------------------------------------------------------------
NEGATE64_3:
    LDD  #0
    SUBD 6,X
    STD  6,X
    LDD  #0
    SBCD 4,X
    STD  4,X
    LDD  #0
    SBCD 2,X
    STD  2,X
    LDD  #0
    SBCD 0,X
    STD  0,X
    RTS
;------------------------------------------------------------------------------
; GIVEN I64'S AT X AND U, SUBTRACT U FROM X, LEAVING RESULT IN X.
;------------------------------------------------------------------------------
SUB64_XU_3:
    LDD   6,X
    SUBD  6,U
    STD   6,X
    LDD   4,X
    SBCD  4,U
    STD   4,X
    LDD   2,X
    SBCD  2,U
    STD   2,X
    LDD   0,X
    SBCD  0,U
    STD   0,X
    RTS
;------------------------------------------------------------------------------
; GIVEN I64'S AT X AND U, COMPARE X TO U.
;------------------------------------------------------------------------------
CMP64_XU_3:
    ANDCC #$7E          ; CLEAR CARRY
    LDD   0,X
    CMPD  0,U
    BNE   DONECMP64_3
    LDD   2,X
    CMPD  2,U
    BNE   DONECMP64_3
    LDD   4,X
    CMPD  4,U
    BNE   DONECMP64_3
    LDD   6,X
    CMPD  6,U
DONECMP64_3:
    RTS      
;------------------------------------------------------------------------------
; GIVEN AN I64 AT X, OUTPUTS IT AS A NULL-TERMINATED DECIMAL STRING AT Y.
; ON RETURN, X WILL BE PAST THE 8-BYTE INPUT, AND Y WILL POINT AT THE STR NULL.
;------------------------------------------------------------------------------
ITOA64_3:
    LDQ   ,X++          ; STASH I64 INPUT VALUE AT X TO TEMP WORKING VAR
    LEAX 2,X
    STQ  I64+0
    LDQ   ,X++
    LEAX 2,X
    STQ  I64+4
    PSHS X
    LDA  I64
    ANDA #$80
    BEQ  DIDNEG_3
    LDX  #I64           ; IF I64 IS NEGATIVE, NEGATE IT,
    JSR  NEGATE64_3
    LDA  #'-'           ; AND OUTPUT A MINUS SIGN.
    STA  ,Y+
DIDNEG_3:
    LDX  #I64           ; X AT TMP64
    LDU  #POWERS        ; U AT POWERS TABLE
    LDA  #1
    STA  LEADZ          ; IGNORING LEADING ZEROES
IT64_LOOP_3:            ; FOR EACH POWER OF TEN (EACH DIGIT)
    LDA  #'0'
    STA  DIGIT
IT64_ILOOP_3:           ; CALCULATE A DIGIT
    JSR  CMP64_XU_3     ; WHILE TMP64 >= POWER:
    BLO  DONE_ILOOP_3
    INC  DIGIT          ;     DIGIT++
    JSR  SUB64_XU_3     ;     TMP64 -= POWER
    BRA  IT64_ILOOP_3
DONE_ILOOP_3:
    LDA  LEADZ          ; IF NOT IGNORING LEADING ZEROES,
    BEQ  ADDDIGIT_3     ; OUTPUT EVERY DIGIT.   
    LDA  DIGIT
    CMPA #'0'
    BNE  NONZERO_3      ; DIGIT IS NONZERO.
    CMPU #TEST_VECTORS-8 ; IF ALL ZEROES, DO OUTPUT THE LAST ONE.
    BEQ  NONZERO_3
    BRA  SKIPDIGIT_3    ; SKIP THIS ZERO DIGIT.
NONZERO_3:
    CLR  LEADZ          ; DONE IGNORING ZEROES.
ADDDIGIT_3:
    LDA  DIGIT          ; ADD DIGIT TO OUTPUT
    STA  ,Y+
SKIPDIGIT_3:
    LEAU 8,U            ; POINT U AT NEXT (LOWER) POWER OF 10, IF ANY.
    CMPU #POWERS+152    ; IF PLACE VALUES REMAINING,
    BNE  IT64_LOOP_3    ; DO NEXT ONE.
IT64_DONE_3:
    LDA  #0
    STA  ,Y
    PULS X
    RTS
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
