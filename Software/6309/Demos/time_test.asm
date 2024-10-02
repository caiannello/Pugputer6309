;------------------------------------------------------------------------------
; PROJECT: TIME TEST
; VERSION: 0.0.1
;    FILE: time_test.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; DESCRIPTION: 
;   Experiments with realtime clock and 64-bit integers
;
;------------------------------------------------------------------------------
    INCLUDE bios_func_tab.d     ; BIOS functions jump table
;------------------------------------------------------------------------------
TICKS_PER_MINUTE    equ  $3C0       ; 960
TICKS_PER_SECOND    equ  $10        ; 16
; -----------------------------------------------------------------------------
    ORG     $2000               ; Begin CODE & VARS
; -----------------------------------------------------------------------------
; PROGRAM ENTRYPOINT
; -----------------------------------------------------------------------------
ENTRYPOINT  
    LDX  #TIMESET    ; SET SYSTEM TICK COUNT FROM TIMESET CONSTANT
    ;JSR  BF_RTC_SETTIX
    JMP  TESTLOOP
;------------------------------------------------------------------------------
; STARTING TIMESTAMP (SET ABOVE) IT'S AN INT64 UNIX_TIMESTAMP_SECS*16
;------------------------------------------------------------------------------
TIMESET     FQB $6,$6FD76EE0
;------------------------------------------------------------------------------
; VARS
;------------------------------------------------------------------------------
; USED IN TEST
MYBUF       RMB  64     ; STRING BUF
THISTICKS   RMB  8      ; STASH OF FULL RTC TICK COUNTER (1/16THS OF SECS)
; USED IN TS_TO_DATE
TMP64       RMB  8
TMP16_0     RMB  2
TMP16_1     RMB  2
TMP8_0      RMB  1
TMP8_1      RMB  1

TMPYEAR     RMB  2      ; DECIMAL RESULT
TMPDAYYR    RMB  2
TMPMON      RMB  1
TMPDAYMON   RMB  1
TMPHOUR     RMB  1
TMPMIN      RMB  1
TMPSEC      RMB  1
TMPTICKS    RMB  1

YRHIBCD     RMB  1      ; BCD RESULT
YRLOWBCD    RMB  1
MONBCD      RMB  1
DAYMONBCD   RMB  1
HOURBCD     RMB  1
MINBCD      RMB  1
SECBCD      RMB  1
HUNDBCD     RMB  1
;------------------------------------------------------------------------------
; TEST
;------------------------------------------------------------------------------
TESTLOOP    
    JSR  BF_UT_GETC ; QUIT LOOP IF ESC RECEIVED
    CMPA #$1B
    LBEQ ENDLOOP
    LDX  #THISTICKS ; GET SYSTEM TICK COUNT (U64 16THS OF SECONDS)
    JSR  BF_RTC_GETTIX  
    LDX  #THISTICKS
    JSR  TS_TO_DATE ; CONVERT TICKCOUNT TO DATE/TIME,
    LDY  #MYBUF     ; AND TO OUTPUT BUFFER,
    JSR  STRDATE    ; WRITE AS AN ISO-8601 STRING.
    LDA  #CR        ; ADD LF + CR + NULL
    STA  ,Y+
    LDA  #LF
    STA  ,Y+
    LDA  #0
    STA  ,Y+
    LDY  #MYBUF     ; OUTPUT STRING VIS SERIAL
    JSR  BF_UT_PUTS
    JSR  BF_UT_WAITTX
    JMP  TESTLOOP   ; KEEP LOOPING  
ENDLOOP
    RTS
;------------------------------------------------------------------------------
; GIVEN BCD DATE FIELDS FROM TS_TO_DATE, OUTPUTS TO Y AS AN ISO-8601 STRING.
;------------------------------------------------------------------------------
STRDATE
    LDA  YRHIBCD
    JSR  S_HEXA
    LDA  YRLOWBCD
    JSR  S_HEXA
    LDA  #'-'
    STA  ,Y+
    LDA  MONBCD
    JSR  S_HEXA
    LDA  #'-'
    STA  ,Y+
    LDA  DAYMONBCD
    JSR  S_HEXA
    LDA  #' '
    STA  ,Y+
    LDA  HOURBCD
    JSR  S_HEXA
    LDA  #':'
    STA  ,Y+
    LDA  MINBCD
    JSR  S_HEXA
    LDA  #':'
    STA  ,Y+
    LDA  SECBCD
    JSR  S_HEXA
    LDA  #'.'
    STA  ,Y+
    LDA  HUNDBCD
    JSR  S_HEXA
    LDA  #NUL
    STA  ,Y
    RTS
;------------------------------------------------------------------------------
; CONVERTS BYTE VALUE FROM A TO AN UNTERMINATED 2-BYTE HEX STRING AT Y. 
; Y IS INCREMENTED BY TWO. (L. LEVENTHAL)
;------------------------------------------------------------------------------
S_HEXA      
    TFR  A,B        ; SAVE ORIGINAL BINARY VALUE
    LSRA            ; MOVE HIGH DIGIT TO LOW DIGIT
    LSRA
    LSRA
    LSRA
    CMPA #9
    BLS  AD30       ; BRANCH IF HIGH DIGIT IS DECIMAL
    ADDA #7         ; ELSE ADD 7 SO AFTER ADDING '0' THE
                    ; CHARACTER WILL BE IN ‘'A'..'F'
AD30:       
    ADDA #'0        ; ADD ASCII 0 TO MAKE A CHARACTER
    ANDB #$0F       ; MASK OFF LOW DIGIT
    CMPB #9
    BLS AD3OLD      ; BRANCH IF LOW DIGIT IS DECIMAL
    ADDB #7         ; ELSE ADD 7 SO AFTER ADDING '0' THE
                    ; CHARACTER WILL BE IN '‘A'..'F!
AD3OLD:     
    ADDB #'0        ; ADD ASCII 0 TO MAKE A CHARACTER
    STA ,Y+         ; INSERT HEX BYTES INTO DEST STRING AT Y
    STB ,Y+         ; AND NCREMENT Y
    RTS     
;------------------------------------------------------------------------------
; CONVERT A U8 IN A TO BCD IN D (FROM LANCE LEVENTHAL)
;------------------------------------------------------------------------------
BN2BCD: 
    LDB  #$FF       ; START QUOTIENT AT -1
D10LP:  
    INCB            ; ADD 1 TO QUOTIENT
    SUBA #10        ; SUBTRACT 10 FROM DIVIDEND
    BCC  D10LP      ; JUMP IF DIFFERENCE STILL POSITIVE
    ADDA #10        ; IF NOT, ADD THE LAST 10 BACK
    LSLB            ; MOVE 10'S DIGIT TO HIGH NIBBLE LSLB
    LSLB
    LSLB
    LSLB
    STA  ,-S        ; SAVE 1'S DIGIT ON STACK
    ADDB ,S+        ; COMBINE 1'S AND 10'S DIGITS IN B
    RTS
;------------------------------------------------------------------------------
; Compare U64 at Y to U32 at X
;------------------------------------------------------------------------------
Y64_CMPX32
    LDD  0,Y
    LDW  #0
    CMPR W,D
    BNE  Y64_CMPX32_DONE
    LDD  2,Y
    CMPR W,D
    BNE  Y64_CMPX32_DONE
    LDD  4,Y
    LDW  0,X
    CMPR W,D
    BNE  Y64_CMPX32_DONE
    LDD  6,Y
    LDW  2,X
    CMPR W,D
Y64_CMPX32_DONE    
    RTS        
;------------------------------------------------------------------------------
; Subtract i32 X from i64 Y, leaving result in Y.
;------------------------------------------------------------------------------
I64Y_SUBI32X    
    ANDCC #$FE  ; CLEAR CARRY
    LDQ  4,Y    ; Get lower 32-bits of I64 into Q
    EXG  D,W    ; subtract 32-bit number at X from Q
    SBCD 2,X
    EXG  D,W
    SBCD 0,X
    STQ  4,Y    ; store lower 32-bits of result, note borroe
    LDQ  0,Y    ; Get lower 32-bits of I64 into Q
    EXG  D,W    ; subtract 32-bit number at X from Q
    SBCD #0
    EXG  D,W
    SBCD #0
    STQ  0,Y    ; store lower 32-bits of result, note borroe
    RTS
;------------------------------------------------------------------------------
; Function to check if the year in D is a leap year
; Sets carry if leap year, clears carry otherwise
; Argument: D = year
; Result: C flag set if leap year, cleared otherwise
;------------------------------------------------------------------------------
IS_LEAP:
    STD  TMPYEAR    
    ; Check if divisible by four
D4L CMPD #4
    BLT  NOT_LEAP  ; not leap if not divisble by 4
    SUBD #4     ; D=D-4
    BEQ  MAYBE  ; If divisible by 4, it's maybe leap year
    BRA  D4L
MAYBE    
    ; Divisible by 4, now check if divisible by 100
    LDD  TMPYEAR
    DIVD #100
    TSTA        ;
    BNE  LEAP   ; IF NOT DIVISIBLE BY 100, IT IS A LEAP YEAR.
    ; Divisible by 100, now check if divisible by 400
    LDD  TMPYEAR
D40L CMPD #400
    BLT  NOT_LEAP
    SUBD #400   ; D=D-400    
    BEQ  LEAP   ; If divisible by 400, it's a leap year
    BRA  D40L
NOT_LEAP:
    LDD  TMPYEAR ; RESTORE YEAR IN D
    ANDCC #$FE  ; Clear carry, not a leap year
    BRA  END_LEAP
LEAP:
    LDD  TMPYEAR ; RESTORE YEAR IN D
    ORCC    #1  ; Set carry, leap year
END_LEAP:
    RTS         ; Return from subroutine    
;------------------------------------------------------------------------------
; Given a year in D, points x to the u32 number of 1/16th sec ticks in that 
; year. (366*86400*16 if leap year, 365*86400*16 otherwise.)
;------------------------------------------------------------------------------
TICKS_PER_LEAP_YEAR FQB  $1E285000          ; 505958400
TICKS_PER_YEAR      FQB  $1E133800          ; 504576000
TICKS_IN_YEAR
    JSR  IS_LEAP
    BCC  DY_NOTLEAP
DY_LEAP
    LDX  #TICKS_PER_LEAP_YEAR
    RTS
DY_NOTLEAP
    LDX  #TICKS_PER_YEAR
    RTS    
;------------------------------------------------------------------------------
; Given a 64-bit UNIX timestamp at X, fills out the date struct
;------------------------------------------------------------------------------
TICKS_PER_DAY       FQB  $151800            ; 1382400
TICKS_PER_HOUR      FQB  $E100              ; 57600
DAYS_IN_MONTHS      FCB  31,28,31,30,31,30,31,31,30,31,30,31
DAYS_IN_MONTHS_LEAP FCB  31,29,31,30,31,30,31,31,30,31,30,31
; TICKCOUNTS [0...15] IN HUNDREDTHS OF SECS * 100
FRACS               FCB 0,6,12,19,25,31,38,44,50,56,62,69,75,81,88,94
;------------------------------------------------------------------------------
TS_TO_DATE
    PSHS A,B,X,Y
    LDQ  0,X        ; Stash 64-bit working timestamp
    STQ  TMP64+0
    LDQ  4,X
    STQ  TMP64+4
    LDD  #1970      ; starting with unix epoch year
    STD  TMPYEAR
    CLR  TMPDAYYR
    CLR  TMPDAYYR+1
    CLR  TMPHOUR
    CLR  TMPMIN
    CLR  TMPSEC
    CLR  TMPMON
    CLR  TMPDAYMON
    LDY  #TMP64         ; get working timestamp to y
YEARSLOOP
    JSR  TICKS_IN_YEAR  ; get the year's ticks to X
    JSR  Y64_CMPX32     ; Compare timestamp to yearly ticks, and
    BLO  DAYSLOOP       ; if timestamp is less, we're done counting years.
    JSR  I64Y_SUBI32X   ; subtract ticks from working timestamp
    LDD  TMPYEAR
    INCD                ; Increment year
    STD  TMPYEAR
    BRA  YEARSLOOP
DAYSLOOP                ; Calculate day of year
    LDX  #TICKS_PER_DAY
    JSR  Y64_CMPX32
    BLO  GOTDAYYR
    JSR  I64Y_SUBI32X
    LDD  TMPDAYYR
    INCD
    STD  TMPDAYYR
    BRA  DAYSLOOP
GOTDAYYR
    ; by now, remaining timestamp will be a u32 (<$151800) and
    ; ticks per hour is a u16 ($E100), so we can calc this more efficiently
    ; (But we're not, yet.)
HOURSLOOP               ; CALC HOUR OF DAY
    LDX  #TICKS_PER_HOUR
    JSR  Y64_CMPX32
    BLO  GOTHOUR
    JSR  I64Y_SUBI32X
    INC  TMPHOUR
    BRA  HOURSLOOP
GOTHOUR                 ; CALC MINUTE OF HOUR
    ; remaining timestamp will be a u16 (<$e100) and ticks per 
    ; minute is a u16 ($3c0), so we can calc minutes efficiently
    LDQ  #0
    LDW  6,Y
    DIVQ #TICKS_PER_MINUTE
    STF  TMPMIN
    STD  6,Y
GOTMINUTE               ; CALC SECOND OF MINUTE               
    ; remaining timestamp will be a u16 (<$3C0) and
    ; ticks per second is a u8 ($10).
    LDD  6,Y
    DIVD #TICKS_PER_SECOND
    STB  TMPSEC
    TFR  A,D
    STB  TMPTICKS
GOTSECOND               ; CALC MONTH OF YEAR
    LDD  TMPDAYYR
    STD  TMP16_0
    LDD  TMPYEAR
    JSR  IS_LEAP    ; depending on whether lts a leap year,
    BCS  MONLEAP    ; point x to approproate array of days per month. 
    LDX  #DAYS_IN_MONTHS
    BRA  GOTDAYSM
MONLEAP
    LDX  #DAYS_IN_MONTHS_LEAP
GOTDAYSM
    LDD  TMP16_0    ; temp day of year
MONTHSLOOP
    LDD  TMP16_0
    LDW  #0
    LDF  ,X
    STW  TMP16_1
    CMPD TMP16_1
    BLT  GOTMONTH
    SUBD TMP16_1
    STD  TMP16_0
    LEAX 1,X
    INC  TMPMON
    BRA  MONTHSLOOP
GOTMONTH
    INC  TMPMON     ; MONTHS ARE NUMBERED STARTING AT ONE.
    LDD  TMP16_0    ; STORE CURRENT DAY WITHIN MONTH
    STB  TMPDAYMON
    INC  TMPDAYMON  ; ALSO STARTING AT ONE.
    LDD  TMPYEAR    ; GET YEAR AS INT16, E.G. 2024
    DIVD #100       ; GET HIGH AND LOW PARTS, E.G. 20 AND 24
    STA  TMP8_0
    STB  TMP8_1
    LDA  TMP8_1
    JSR  BN2BCD
    STB  YRHIBCD    ; HIGH PART AS BCD (CURRENTLY $20)
    LDA  TMP8_0
    JSR  BN2BCD
    STB  YRLOWBCD   ; LOW PART AS BCD (CURRENTLY $24)
    LDA  TMPMON     ; MONTH BCD ($01...$12)
    JSR  BN2BCD
    STB  MONBCD
    LDA  TMPDAYMON  ; DAY OF MONTH BCD ($01...$31)
    JSR  BN2BCD
    STB  DAYMONBCD
    LDA  TMPHOUR    ; HOUR OF DAY BCD ($00..$23)
    JSR  BN2BCD
    STB  HOURBCD
    LDA  TMPMIN     ; MINUTE OF HOUR BCD ($00...$59)
    JSR  BN2BCD
    STB  MINBCD
    LDA  TMPSEC     ; SECOND OF MINUTE BCD ($00...$59)
    JSR  BN2BCD
    STB  SECBCD
    LDA  TMPTICKS   ; REMAINING TICKS AS HUNDREDTHS OF SEC BCD ($00...$94)
    LDX  #FRACS
    LDA  A,X
    JSR  BN2BCD
    STB  HUNDBCD

    PULS A,B,X,Y
    RTS
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
