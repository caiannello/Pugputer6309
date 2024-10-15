;------------------------------------------------------------------------------
; PROJECT: PUGPUTER 6309 
; VERSION: 0.0.1
;    FILE: TINY_PUG_WITH_JINGLE.ASM
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; DESCRIPTION: 
;
; POSSIBLE PUGPUTER SPLASH SCREEN. FADES-IN A TINY B&W PUG ON A WHITE
; BACKGROUND AND PLAYS THE JINGLE BY BISQWIT. 
;
;------------------------------------------------------------------------------
    INCLUDE DEFINES.D           ; COMMON DEFINITIONS
    INCLUDE BIOS_FUNC_TAB.D     ; BIOS FCN JUMP TABLE AND CONSTANTS
;------------------------------------------------------------------------------
    ORG     $2000   ; VARS
; -----------------------------------------------------------------------------
; PROGRAM ENTRYPOINT
; -----------------------------------------------------------------------------
ENTRYPOINT  
    JSR  DRAW_STARTUP_IMAGE
    LDA  #0
    STA  LASTVAL
    LDX  #FADEPALETTE
    STX  FADEPOS
    JSR  PLAY_STARTUP_SOUND
    RTS
; -----------------------------------------------------------------------------
; SETS VDP COLOR PALETTE FROM U16 ARRAY AT X, COLOR COUNT IN E
; -----------------------------------------------------------------------------
SET_PALETTE     
    LDA  #0
    STA  VREG
    LDA  #$90
    STA  VREG
PAL_LOOP     
    LDA  ,X+
    STA  VPAL
    LDA  ,X+
    STA  VPAL
    DECE
    BNE  PAL_LOOP
    RTS    
; -----------------------------------------------------------------------------
DRAW_STARTUP_IMAGE  
    LDX  #VDP_G4_SEQ ; SET MODE GRAPHICS4
VDP_INIT    
    LDA  ,X+
    STA  VREG
    CMPX #(VDP_G4_SEQ+VDP_G4_SZ)
    BLO  VDP_INIT
    LDX  #BLANKPALETTE   ; SET 16-COLOR PALETTE
    LDE  #16
    JSR  SET_PALETTE
    LDA  #4
    STA  OUTELEMS
    LDU  #IMG       ; POINT X TO START OF RLE DATA
DRAWLOOP    
    LDA  ,U+        ; GET NEXT BYTE OF RLE DATA
    BMI  U16ELEM    ; IF TOP BIT SET, NEED TO GET ANOTHER BYTE.
U8ELEM              ; THIS PIXEL RUN IS ENCODED IN ONE BYTE:
    TFR  A,B 
    ANDB #3
    STB  PIXCOLR    ; PIXEL COLOR
    LSRA
    LSRA    
    INCA
    STA  PIXCNT+1   ; RUN LENGTH
DRAWPIXELS8  
    LDB  OUTBYTE
LOOPPIXELS8         ; SHIFT PIXEL INTO OUTPUT BYTE
    LSLB
    LSLB
    ORB  PIXCOLR
    DEC  OUTELEMS
    BNE  SKIPPLOT8
    STB  VDAT       ; EVERY FOUR PIXELS, SEND BYTE THE VDP
    LDA  #4
    STA  OUTELEMS       
    BRA  ELOOP8
SKIPPLOT8
    STB  OUTBYTE
ELOOP8
    DEC  PIXCNT+1   ; CHECK FOR END OF PIXEL RUN
    BNE  LOOPPIXELS8
    CMPU #ENDIMG    ; CHECK FOR END OF IMAGE
    BNE  DRAWLOOP
    JMP  DRAWING_DONE
U16ELEM             ; THIS PIXEL RUN IS ENCODED IN TWO BYTES:
    LDB  ,U+  
    ANDA #$7F
    TFR  D,W
    ANDB #3
    STB  PIXCOLR    ; PIXEL COLOR
    TFR  W,D
    LSRD
    LSRD
    INCD
    STD  PIXCNT     ; RUN LENGTH   
DRAWPIXELS          ; SHIFT PIXEL INTO OUTPUT BYTE
    LDB  OUTBYTE
LOOPPIXELS16
    LSLB
    LSLB
    ORB  PIXCOLR
    DEC  OUTELEMS
    BNE  SKIPPLOT
    STB  VDAT       ; EVERY FOUR PIXELS, SEND BYTE THE VDP
    LDA  #4
    STA  OUTELEMS       
    BRA  ELOOP
SKIPPLOT
    STB  OUTBYTE
ELOOP
    LDW  PIXCNT
    DECW
    STW  PIXCNT     ; CHECK FOR END OF PIXEL RUN
    BNE  LOOPPIXELS16
    CMPU #ENDIMG    ; CHECK FOR END OF IMAGE
    BNE DRAWLOOP
DRAWING_DONE:
    LDB  #0
    STB  VDAT       ; PLOT THAT LAST PIXEL
    RTS             ; IMAGE DONE.
; -----------------------------------------------------------------------------
; PLAY STARTUP SOUND USING THE YAMAHA YMF262M (OPL3) MUSIC SYNTHESIZER
; -----------------------------------------------------------------------------
PLAY_STARTUP_SOUND   
    LDX  #SONG
SONGLOOP
    LDA  ,X+
    CMPA #$5A
    BEQ  WR_BANK0
    CMPA #$5F
    BEQ  WR_BANK1
    CMPA #$61
    BEQ  DLY_VAR0
    JMP  LOOPEND                             
DLY_VAR0
    LDY  ,X++
    JSR  DELAY
    JMP  LOOPEND
WR_BANK1
    LDA  ,X+
    LDB  ,X+
    LDE  #1
    JSR  OPL_WRITE
    JMP  LOOPEND
WR_BANK0
    LDA  ,X+
    LDB  ,X+
    LDE  #0
    JSR  OPL_WRITE
LOOPEND
    JSR  BF_UT_GETC
    CMPA #$1B
    BEQ  ENDLOOP
    TFR  X,D
    LSRD
    LSRD
    LSRD
    LSRD
    LSRD
    LSRD  
    LSRD  
    CMPB LASTVAL 
    BEQ  SKIPFADE
    STB  LASTVAL
    JSR DOFADE
SKIPFADE
    CMPX #ENDSONG
    LBNE SONGLOOP
ENDLOOP     
    JSR  OPL_RESET
    RTS             ; ALL DONE.
; -----------------------------------------------------------------------------
OPL_RESET:
    LDE  #0
    LDA  #0
    LDB  #0
L0  JSR  OPL_WRITE
    INCA  
    BNE  L0
    LDE  #1
    LDA  #0
    LDB  #0
L1  JSR  OPL_WRITE
    INCA  
    BNE  L1
    RTS
; -----------------------------------------------------------------------------
; POKES SPECIFIED VALUE INTO SPECIFIED REGISTER OF SOUNDCHIP (YMF-262M)
; A = REG NUM, B = VALUE, E = OPL3 BANK NUMBER (0,1)           
; -----------------------------------------------------------------------------
OPL_WRITE
    CMPE #00
    BEQ  BANK0
BANK1
    STA  OPL3_BASE+2
    NOP
    NOP
    NOP
    STB  OPL3_BASE+3
    NOP
    NOP
    RTS
BANK0
    STA  OPL3_BASE+0
    NOP
    NOP
    NOP
    STB  OPL3_BASE+1
    NOP
    NOP
    RTS
; -----------------------------------------------------------------------------
; WAIT THE NUMBER OF SAMPLE PERIODS GIVEN IN Y. THE SAMPLE RATE IS 44100 HZ.
;
; THIS IS JUST A BUSYLOOP FOR NOW, BUT IT WOULD BE NICE TO HAVE A PERIODIC 
; INTERRUPT INSTEAD SO WE CAN DO OTHER THINGS LIKE FADE-IN THE SPLASH SCREEN.
; -----------------------------------------------------------------------------
DELAY
    LDB  #17
DLOOP
    DECB
    BNE  DLOOP
    LEAY -1,Y
    BNE  DELAY
    RTS
; -----------------------------------------------------------------------------
; CALLED PERIODICALLY DURING STARTUP TUNE TO FADE THE PUG IN
; -----------------------------------------------------------------------------
DOFADE:
    PSHS X,Y,D
    PSHSW
    LDX  FADEPOS
    CMPX #PALETTE
    BGT  NOFADE
    LDE  #4
    JSR  SET_PALETTE
    LDX  FADEPOS
    LEAX 8,X
    STX  FADEPOS
NOFADE:
    PULSW
    PULS X,Y,D
    RTS
; -----------------------------------------------------------------------------
PIXCOLR     RMB     1
PIXCNT      RMB     2
OUTBYTE     RMB     1
OUTELEMS    RMB     1
FADEPOS     RMB     2
LASTVAL     RMB     1
VDP_G4_SZ   EQU     18      ; INIT SEQ FOR VDP MODE GRAPHICS4 (512 X 212 X 16)
VDP_G4_SEQ  FCB     $00,$99,$10,$87,$08,$80,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$8E,$00,$40
; -----------------------------------------------------------------------------
BLANKPALETTE:
    FDB $7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707,$7707
FADEPALETTE:
    FDB $7707,$7707,$7707,$7707
    FDB $7707,$6606,$7707,$7707
    FDB $7707,$5505,$7707,$6606
    FDB $7707,$4404,$6606,$6606
    FDB $7707,$3303,$5505,$5505
    FDB $7707,$2202,$4404,$5505
    FDB $7707,$1101,$3303,$4404
PALETTE:
    FDB $7707,$0000,$2202,$4404
IMG:
    FCB $FF,$F8,$FF,$F8,$FF,$F8,$FF,$F8,$FF,$F8,$CC,$28,$13,$12,$03,$87
    FCB $B4,$13,$01,$03,$0C,$0F,$0E,$05,$02,$07,$87,$88,$02,$05,$02,$07
    FCB $0C,$07,$20,$03,$02,$01,$0E,$0D,$02,$87,$70,$03,$01,$06,$03,$50
    FCB $02,$01,$0E,$01,$06,$01,$03,$87,$64,$02,$01,$02,$01,$02,$58,$03
    FCB $01,$1A,$01,$03,$87,$54,$03,$05,$06,$01,$02,$38,$03,$02,$0F,$02
    FCB $03,$04,$03,$01,$16,$01,$02,$87,$4C,$03,$01,$02,$01,$0A,$01,$04
    FCB $03,$02,$07,$06,$14,$03,$02,$28,$03,$01,$12,$01,$87,$4C,$03,$01
    FCB $12,$01,$03,$1C,$02,$18,$03,$12,$01,$02,$03,$08,$02,$01,$0A,$01
    FCB $02,$87,$4C,$01,$12,$05,$04,$03,$05,$0E,$03,$08,$07,$00,$03,$0A
    FCB $01,$03,$00,$09,$02,$08,$01,$0A,$01,$03,$87,$4C,$05,$0E,$01,$04
    FCB $02,$00,$03,$09,$0E,$15,$0A,$19,$03,$04,$02,$01,$06,$01,$87,$54
    FCB $02,$01,$0A,$01,$00,$03,$19,$02,$41,$02,$0C,$02,$01,$02,$87,$60
    FCB $01,$06,$01,$00,$03,$15,$02,$21,$06,$0D,$0E,$10,$02,$87,$24,$06
    FCB $0B,$02,$03,$24,$09,$04,$06,$05,$06,$05,$06,$11,$16,$15,$02,$08
    FCB $02,$87,$1C,$06,$18,$02,$03,$10,$0B,$02,$01,$08,$02,$11,$16,$05
    FCB $32,$03,$08,$01,$87,$18,$03,$02,$1C,$03,$01,$03,$02,$0B,$0C,$01
    FCB $04,$02,$01,$26,$11,$22,$01,$03,$08,$03,$02,$87,$18,$03,$02,$04
    FCB $07,$0C,$06,$20,$01,$04,$03,$26,$19,$1A,$01,$03,$0C,$01,$87,$20
    FCB $02,$03,$04,$06,$03,$06,$03,$24,$03,$02,$04,$03,$02,$01,$16,$01
    FCB $02,$00,$03,$01,$04,$07,$11,$02,$03,$0C,$02,$87,$28,$03,$02,$03
    FCB $02,$03,$38,$02,$03,$08,$03,$05,$0A,$05,$08,$07,$04,$03,$01,$02
    FCB $01,$02,$10,$03,$02,$87,$34,$03,$02,$40,$03,$02,$0C,$03,$06,$09
    FCB $02,$03,$0C,$03,$01,$02,$05,$10,$06,$87,$38,$07,$48,$02,$03,$14
    FCB $02,$0D,$06,$0D,$02,$08,$03,$02,$03,$01,$87,$3C,$01,$54,$03,$02
    FCB $07,$0C,$03,$02,$0D,$02,$03,$18,$07,$87,$38,$03,$02,$64,$0B,$38
    FCB $03,$02,$87,$3C,$01,$80,$AC,$03,$02,$87,$3C,$01,$80,$AC,$07,$87
    FCB $3C,$02,$03,$80,$9C,$03,$02,$00,$02,$03,$87,$40,$01,$58,$03,$28
    FCB $02,$03,$08,$03,$02,$00,$02,$03,$87,$44,$02,$28,$03,$02,$07,$06
    FCB $03,$0C,$03,$02,$24,$02,$03,$04,$03,$02,$03,$00,$02,$03,$87,$48
    FCB $01,$18,$03,$06,$01,$03,$10,$02,$01,$03,$08,$01,$24,$01,$07,$02
    FCB $03,$08,$01,$87,$4C,$01,$14,$01,$03,$04,$03,$01,$10,$03,$01,$03
    FCB $0A,$01,$03,$20,$01,$03,$10,$03,$02,$87,$4C,$03,$02,$0C,$03,$02
    FCB $0C,$03,$06,$07,$06,$03,$08,$07,$01,$20,$01,$18,$01,$03,$87,$4C
    FCB $03,$12,$03,$14,$0F,$18,$06,$1C,$01,$03,$10,$03,$01,$03,$87,$B0
    FCB $03,$02,$18,$01,$0A,$03,$0A,$03,$87,$B8,$03,$06,$0F,$02,$03,$04
    FCB $0B,$FF,$F8,$FF,$F8,$FF,$F8,$FF,$F8,$FF,$F8,$D3,$E0
ENDIMG
;------------------------------------------------------------------------------
; PUGPUTER STARTUP SOUND IN VGM FORMAT (MUSIC BY BISQWIT)
; NOTE THE TWO ARGUMENT BYTES OF DELAY COMMAND (OPCODE $61) ARE SWAPPED TO 
; BIG ENDIAN FORM, BECAUSE LITTLE ENDIAN IS LAME.
;
; TODO: MORE SPACE-EFFICIENT FORMAT
;------------------------------------------------------------------------------
SONG:
    FCB $5A,$B0,$00,$5A,$B1,$00,$5A,$B2,$00,$5A,$B3,$00,$5A,$B4,$00,$5A,$B5,$00
    FCB $5A,$B6,$00,$5A,$B7,$00,$5A,$B8,$00,$5F,$B0,$00,$5F,$B1,$00,$5F,$B2,$00
    FCB $5F,$B3,$00,$5F,$B4,$00,$5F,$B5,$00,$5F,$B6,$00,$5F,$B7,$00,$5F,$B8,$00
    FCB $5A,$04,$60,$5A,$04,$80,$5F,$05,$00,$5F,$05,$01,$5F,$05,$00,$5A,$01,$20
    FCB $5F,$05,$01,$5A,$BD,$C0,$5F,$04,$3F,$5A,$20,$21,$5A,$21,$30,$5A,$22,$30
    FCB $5A,$23,$61,$5A,$24,$A0,$5A,$25,$A0,$5A,$28,$A1,$5A,$29,$61,$5A,$2A,$61
    FCB $5A,$2B,$21,$5A,$2C,$21,$5A,$2D,$21,$5A,$30,$31,$5A,$31,$31,$5A,$32,$31
    FCB $5A,$33,$31,$5A,$34,$34,$5A,$35,$34,$5A,$40,$16,$5A,$41,$98,$5A,$42,$98
    FCB $5A,$43,$09,$5A,$44,$08,$5A,$45,$08,$5A,$48,$8A,$5A,$49,$92,$5A,$4A,$92
    FCB $5A,$4B,$00,$5A,$4C,$06,$5A,$4D,$06,$5A,$50,$8D,$5A,$51,$0A,$5A,$52,$0A
    FCB $5A,$53,$00,$5A,$54,$05,$5A,$55,$0A,$5A,$60,$C2,$5A,$61,$61,$5A,$62,$61
    FCB $5A,$63,$CF,$5A,$64,$64,$5A,$65,$64,$5A,$68,$74,$5A,$69,$65,$5A,$6A,$65
    FCB $5A,$6B,$7F,$5A,$6C,$65,$5A,$6D,$65,$5A,$70,$F1,$5A,$71,$A8,$5A,$72,$A8
    FCB $5A,$73,$F1,$5A,$74,$D2,$5A,$75,$D2,$5A,$80,$35,$5A,$81,$03,$5A,$82,$03
    FCB $5A,$83,$0A,$5A,$84,$17,$5A,$85,$17,$5A,$88,$45,$5A,$89,$17,$5A,$8A,$17
    FCB $5A,$8B,$08,$5A,$8C,$17,$5A,$8D,$17,$5A,$90,$E8,$5A,$91,$10,$5A,$92,$10
    FCB $5A,$93,$78,$5A,$94,$B9,$5A,$95,$B9,$5A,$A0,$58,$5A,$A1,$B0,$5A,$A2,$03
    FCB $5A,$A3,$58,$5A,$A4,$B0,$5A,$A5,$03,$5A,$A6,$B0,$5A,$A7,$03,$5A,$A8,$B8
    FCB $5A,$B0,$21,$5A,$B1,$2E,$5A,$B2,$2E,$5A,$B3,$21,$5A,$B4,$2E,$5A,$B5,$2E
    FCB $5A,$B6,$22,$5A,$B7,$3A,$5A,$B8,$32,$5A,$C0,$3E,$5A,$C1,$3E,$5A,$C2,$2E
    FCB $5A,$C3,$3F,$5A,$C4,$3F,$5A,$C5,$2F,$5A,$C6,$3A,$5A,$C7,$36,$5A,$C8,$36
    FCB $5A,$E0,$00,$5A,$E1,$02,$5A,$E2,$02,$5A,$E3,$00,$5A,$E4,$02,$5A,$E5,$02
    FCB $5A,$E8,$00,$5A,$E9,$01,$5A,$EA,$01,$5A,$EB,$00,$5A,$EC,$00,$5A,$ED,$00
    FCB $5A,$F0,$00,$5A,$F1,$00,$5A,$F2,$00,$5A,$F3,$00,$5A,$F4,$01,$5A,$F5,$01
    FCB $5F,$30,$0E,$5F,$33,$00,$5F,$40,$BF,$5F,$41,$BF,$5F,$42,$BF,$5F,$43,$9E
    FCB $5F,$44,$9E,$5F,$45,$9E,$5F,$48,$BF,$5F,$49,$BF,$5F,$4A,$BF,$5F,$4B,$BF
    FCB $5F,$4C,$BF,$5F,$4D,$BF,$5F,$50,$00,$5F,$51,$BF,$5F,$52,$BF,$5F,$53,$00
    FCB $5F,$54,$BF,$5F,$55,$BF,$5F,$70,$1E,$5F,$73,$18,$5F,$90,$00,$5F,$93,$FE
    FCB $5F,$A6,$63,$5F,$B6,$33,$5F,$C6,$3E,$5F,$F0,$00,$5F,$F3,$03,$61,$23,$E7
    FCB $5F,$31,$31,$5F,$51,$0A,$5F,$71,$A8,$5F,$91,$10,$5F,$F1,$00,$5F,$34,$34
    FCB $5F,$54,$05,$5F,$74,$D2,$5F,$94,$B9,$5F,$F4,$01,$5F,$A7,$63,$5F,$B7,$37
    FCB $5F,$C7,$36,$61,$1D,$60,$5A,$B7,$1A,$61,$03,$44,$5F,$20,$21,$5F,$40,$16
    FCB $5F,$60,$C2,$5F,$80,$35,$5F,$A0,$63,$5F,$B0,$27,$5F,$C0,$3E,$5F,$E0,$00
    FCB $5F,$23,$61,$5F,$32,$31,$5F,$43,$10,$5F,$52,$0A,$5F,$63,$CF,$5F,$72,$A8
    FCB $5F,$83,$0A,$5F,$92,$10,$5F,$A3,$63,$5F,$B3,$27,$5F,$C3,$3F,$5F,$E3,$00
    FCB $5F,$F2,$00,$5A,$44,$05,$5A,$54,$0A,$5F,$35,$34,$5A,$45,$05,$5F,$55,$05
    FCB $5F,$75,$D2,$5F,$95,$B9,$5F,$F5,$01,$5A,$A7,$B8,$5A,$B7,$36,$5A,$B8,$12
    FCB $5F,$28,$A1,$5F,$48,$8A,$5F,$68,$74,$5F,$88,$45,$5F,$A8,$B0,$5F,$B8,$3A
    FCB $5F,$C8,$36,$5F,$E8,$00,$5F,$2B,$21,$5F,$4B,$09,$5F,$6B,$7F,$5F,$8B,$08
    FCB $5F,$EB,$00,$5A,$4C,$03,$5A,$4D,$03,$61,$16,$D9,$5A,$52,$8D,$5A,$72,$F1
    FCB $5A,$92,$E8,$5A,$35,$31,$5A,$55,$00,$5A,$75,$F1,$5A,$95,$78,$5A,$F5,$00
    FCB $5A,$B6,$02,$5A,$A8,$B0,$5A,$B8,$26,$5A,$C8,$3A,$61,$09,$CB,$5F,$B6,$13
    FCB $61,$06,$87,$5F,$B7,$17,$61,$03,$44,$5A,$B7,$16,$5F,$B8,$1A,$61,$13,$95
    FCB $5F,$51,$8D,$5F,$71,$F1,$5F,$91,$E8,$5F,$43,$09,$5A,$44,$03,$5F,$34,$31
    FCB $5A,$45,$03,$5F,$54,$00,$5F,$74,$F1,$5F,$94,$78,$5F,$F4,$00,$5F,$A7,$B0
    FCB $5F,$B7,$22,$5F,$C7,$3A,$5A,$B8,$06,$5F,$4B,$00,$5A,$4C,$01,$5A,$4D,$01
    FCB $61,$47,$CE,$5A,$54,$05,$5F,$55,$0A,$5A,$A7,$65,$5A,$B7,$36,$5F,$A8,$6D
    FCB $5F,$B8,$33,$5A,$4C,$00,$5A,$4D,$00,$61,$13,$95,$5A,$B6,$26,$5F,$B7,$02
    FCB $61,$09,$CB,$5A,$52,$0A,$5A,$72,$A8,$5A,$92,$10,$5A,$35,$34,$5A,$55,$05
    FCB $5A,$75,$D2,$5A,$95,$B9,$5A,$F5,$01,$5A,$A8,$43,$5A,$B8,$36,$5A,$C8,$36
    FCB $61,$23,$E7,$5A,$A0,$32,$5A,$B0,$27,$5F,$21,$21,$5F,$41,$16,$5A,$51,$8D
    FCB $5F,$51,$0A,$5F,$61,$C2,$5A,$71,$F1,$5F,$71,$A8,$5F,$81,$35,$5A,$91,$E8
    FCB $5F,$91,$10,$5F,$A1,$6C,$5A,$B1,$0E,$5F,$B0,$07,$5F,$B1,$21,$5F,$C1,$3E
    FCB $5F,$E1,$00,$5A,$B2,$0E,$5F,$22,$30,$5F,$42,$98,$5F,$62,$61,$5F,$82,$03
    FCB $5F,$A2,$04,$5A,$A3,$32,$5A,$B3,$27,$5F,$B3,$07,$5F,$B2,$2F,$5F,$C2,$3E
    FCB $5F,$E2,$02,$5A,$34,$31,$5A,$54,$00,$5A,$74,$F1,$5A,$94,$78,$5A,$B4,$0E
    FCB $5A,$F4,$00,$5F,$24,$61,$5F,$25,$A0,$5F,$34,$34,$5F,$44,$09,$5F,$45,$1F
    FCB $5F,$54,$05,$5F,$64,$CF,$5F,$65,$64,$5F,$74,$D2,$5F,$84,$0A,$5F,$85,$17
    FCB $5F,$94,$B9,$5F,$A4,$6C,$5F,$A5,$04,$5A,$B5,$0E,$5F,$B4,$21,$5F,$B5,$2F
    FCB $5F,$C4,$3F,$5F,$C5,$3F,$5F,$E4,$00,$5F,$E5,$02,$5F,$F4,$01,$5A,$B6,$06
    FCB $5A,$A7,$04,$5F,$A7,$04,$5A,$B7,$23,$5F,$B7,$37,$5A,$C7,$3A,$5F,$C7,$36
    FCB $5A,$A8,$04,$5A,$B8,$37,$5F,$29,$A1,$5F,$49,$8A,$5F,$69,$74,$5F,$89,$45
    FCB $5F,$E9,$00,$5F,$2A,$61,$5F,$4A,$92,$5F,$6A,$65,$5F,$8A,$17,$5F,$EA,$01
    FCB $5F,$2C,$21,$5F,$2D,$21,$5F,$4C,$00,$5F,$4D,$1E,$5F,$6C,$7F,$5F,$6D,$65
    FCB $5F,$8C,$08,$5F,$8D,$17,$5F,$EC,$00,$5F,$ED,$00,$61,$06,$87,$5F,$B8,$13
    FCB $61,$1A,$1C,$5F,$A8,$D8,$5F,$B8,$33,$61,$23,$E7,$5A,$B0,$07,$5A,$21,$21
    FCB $5A,$41,$16,$5A,$61,$C2,$5A,$81,$35,$5F,$A0,$82,$5A,$A1,$04,$5F,$B1,$01
    FCB $5F,$B0,$21,$5A,$B1,$27,$5A,$E1,$00,$5F,$A3,$82,$5A,$B3,$07,$5F,$B3,$21
    FCB $5A,$24,$61,$5A,$44,$09,$5A,$64,$CF,$5A,$84,$0A,$5A,$A4,$04,$5A,$B4,$27
    FCB $5A,$E4,$00,$5F,$45,$12,$5F,$B4,$01,$5A,$A8,$43,$5A,$B8,$3A,$5A,$29,$A1
    FCB $5A,$49,$8A,$5A,$69,$74,$5A,$89,$45,$5F,$A8,$0D,$5F,$B8,$2B,$5A,$E9,$00
    FCB $5A,$6C,$7F,$5A,$8C,$08,$5F,$4D,$10,$61,$10,$52,$5F,$B7,$17,$61,$10,$52
    FCB $5F,$B7,$3B,$61,$16,$D9,$5A,$B8,$1A,$61,$09,$CB,$5F,$45,$07,$5F,$4D,$05
    FCB $61,$06,$87,$5F,$B7,$1B,$61,$00,$00,$5F,$45,$11,$5F,$4D,$0F,$61,$16,$D9
    FCB $5F,$B0,$01,$5A,$22,$21,$5A,$42,$16,$5A,$62,$C2,$5A,$82,$35,$5A,$B2,$26
    FCB $5A,$C2,$3E,$5A,$E2,$00,$5F,$B3,$01,$5A,$25,$61,$5A,$45,$1B,$5A,$65,$CF
    FCB $5A,$85,$0A,$5A,$B5,$26,$5A,$C5,$3F,$5A,$E5,$00,$5A,$2A,$A1,$5A,$4A,$8A
    FCB $5A,$6A,$74,$5A,$8A,$45,$5A,$EA,$00,$5A,$4D,$16,$5A,$6D,$7F,$5A,$8D,$08
    FCB $61,$2D,$B2,$5F,$B2,$0F,$5A,$45,$09,$5F,$B5,$0F,$5A,$4D,$00,$61,$47,$CE
    FCB $5A,$B2,$06,$5A,$44,$0B,$5A,$B5,$06,$5A,$4C,$03,$61,$44,$8A,$5A,$B1,$07
    FCB $5A,$B4,$07,$61,$3A,$C0,$5F,$B8,$0B,$61,$09,$CB,$5A,$B7,$03
ENDSONG
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
