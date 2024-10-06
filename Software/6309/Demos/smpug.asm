;------------------------------------------------------------------------------
; PROJECT: SMPUG
; VERSION: 0.0.1
;    FILE: SMPUG.ASM
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; DESCRIPTION: 
;   DRAWS A SMALL PUG IN FOUR COLOES USING THE V9958 VIDEO DISPLAY PROCESSOR.
;
;------------------------------------------------------------------------------
    INCLUDE DEFINES.D           ; COMMON DEFINITIONS
    INCLUDE BIOS_FUNC_TAB.D     ; BIOS FCN JUMP TABLE AND CONSTANTS
;------------------------------------------------------------------------------
; V9958 VDP REGISTERS
VDAT        EQU  VDP_BASE+0 ; PORT 0: VRAM DATA (R/W)
VREG        EQU  VDP_BASE+1 ; PORT 1: STATUS REG (R), REGISTER/SETUP (W), VRAM ADDR (W)
VPAL        EQU  VDP_BASE+2 ; PORT 2: PALETTE REGISTERS (W)
VIND        EQU  VDP_BASE+3 ; PORT 3: REGISTER-INDIRECT ADDRESSING (W)

; 80-COLUMN TEXT IS BLUISH-WHITE ON DARK BLUE..
BACKGROUND1       EQU   $12     ; 0 R2 R1 R0 0 B2 B1 B0
BACKGROUND2       EQU   $01     ; 0 0  0  0  0 G2 G1 G0
FOREGROUND1       EQU   $57     ; 0 R2 R1 R0 0 B2 B1 B0
FOREGROUND2       EQU   $05     ; 0 0  0  0  0 G2 G1 G0
DISPMODE          EQU   DM_NTSC           ; DM_PAL OR DM_NTSC
LINELENGTH        EQU   80                ; TODO: HANDLE 40-COLUMN MODES
DM_NTSC           EQU   128 ; 0 FOR 24 LINE MODE
DM_PAL            EQU   130 ; 2 FOR 24 LINE MODE
DISPLAYSIZE       EQU   LINELENGTH*LINECOUNT
VDP_REG2_PAGE0    EQU   $3           ; PAGE 0 AT 0X0
VDP_REG2_PAGE1    EQU   $B           ; PAGE 1 AT 0X2000
;------------------------------------------------------------------------------
            ORG     $1000   ; VARS
; -----------------------------------------------------------------------------
; PROGRAM ENTRYPOINT
; -----------------------------------------------------------------------------
ENTRYPOINT  
    LDX  #VDP_G4_SEQ ; SET MODE GRAPHICS4
VDP_INIT    
    LDA  ,X+
    STA  VREG
    CMPX #(VDP_G4_SEQ+VDP_G4_SZ)
    BLO  VDP_INIT
    LDX  #PALETTE   ; SET 16-COLOR PALETTE
    LDA  #0
    STA  VREG
    LDA  #$90
    STA  VREG
    LDE  #0
SET_PAL     
    LDA  ,X+
    STA  VPAL
    LDA  ,X+
    STA  VPAL
    INCE
    CMPE #16
    BLO  SET_PAL
    LDA  #2
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
    LSLB
    LSLB
    ORB  PIXCOLR
    DEC  OUTELEMS
    BNE  SKIPPLOT8
    STB  VDAT       ; EVERY TWO PIXELS, SEND BYTE THE VDP
    LDA  #2
    STA  OUTELEMS       
    BRA  ELOOP8
SKIPPLOT8
    STB  OUTBYTE
ELOOP8
    DEC  PIXCNT+1   ; CHECK FOR END OF PIXEL RUN
    BNE  LOOPPIXELS8
    CMPU #ENDIMG    ; CHECK FOR END OF IMAGE
    BNE  DRAWLOOP
    RTS             ; IMAGE DONE.

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
    LSLB
    LSLB
    ORB  PIXCOLR
    DEC  OUTELEMS
    BNE  SKIPPLOT
    STB  VDAT       ; EVERY TWO PIXELS, SEND BYTE THE VDP
    LDA  #2
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
    RTS             ; IMAGE DONE.



; -----------------------------------------------------------------------------
VDP_G4_SZ   EQU     14      ; INIT SEQ FOR VDP MODE GRAPHICS4 (512 X 212 X 16)
VDP_G4_SEQ  FCB     $06,$80,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$8E,$00,$40
OUTBUF      RMB     64
PIXCOLR     RMB     1
PIXCNT      RMB     2
OUTBYTE     RMB     1
OUTELEMS    RMB     1
; -----------------------------------------------------------------------------
PALETTE:
    FDB $0000,$2202,$6505,$5605
IMG:
    FCB $FF,$FB,$FF,$FB,$CA,$17,$01,$00,$05,$10,$83,$CB,$01,$08,$01,$0A,$11,$04,$01,$83,$B3,$0C,$06,$00,$1A,$00,$09,$0C,$83,$A3,$00,$05
    FCB $32,$00,$0D,$00,$01,$00,$83,$9B,$00,$05,$3A,$00,$15,$00,$83,$93,$09,$00,$3E,$00,$11,$00,$83,$8F,$04,$01,$00,$2E,$09,$06,$1D,$83
    FCB $87,$04,$09,$26,$01,$00,$06,$01,$00,$06,$00,$15,$83,$83,$00,$0D,$06,$08,$01,$12,$01,$1E,$11,$83,$83,$00,$0D,$00,$12,$05,$0A,$00
    FCB $06,$09,$0E,$00,$09,$00,$83,$83,$00,$0D,$00,$06,$09,$02,$01,$12,$05,$00,$01,$04,$06,$00,$09,$00,$83,$83,$11,$06,$11,$12,$09,$00
    FCB $02,$04,$01,$06,$09,$00,$83,$83,$0D,$00,$02,$05,$04,$25,$0C,$01,$06,$00,$09,$83,$83,$00,$0D,$02,$00,$02,$04,$09,$10,$05,$0C,$01
    FCB $06,$00,$01,$00,$83,$8B,$00,$05,$00,$02,$10,$01,$18,$01,$0C,$01,$0A,$00,$01,$83,$8B,$01,$00,$01,$00,$02,$0C,$05,$10,$05,$00,$11
    FCB $0A,$00,$83,$6B,$04,$1F,$00,$01,$00,$02,$01,$08,$01,$00,$01,$0C,$09,$10,$0A,$01,$83,$63,$04,$06,$04,$17,$01,$04,$02,$0D,$00,$09
    FCB $04,$21,$00,$06,$00,$83,$5F,$00,$01,$0E,$00,$01,$13,$01,$00,$06,$09,$04,$0D,$00,$25,$06,$00,$83,$5F,$00,$16,$00,$03,$01,$04,$01
    FCB $02,$00,$06,$00,$01,$00,$15,$00,$21,$0A,$00,$83,$5F,$01,$16,$04,$12,$00,$06,$1D,$08,$1D,$0A,$00,$83,$5F,$00,$02,$00,$0E,$00,$16
    FCB $00,$06,$1D,$0C,$11,$00,$0A,$01,$83,$63,$00,$06,$00,$02,$01,$00,$26,$01,$00,$11,$00,$02,$00,$06,$00,$0D,$00,$0A,$00,$83,$63,$01
    FCB $00,$02,$04,$01,$22,$00,$06,$01,$00,$11,$02,$01,$0A,$0C,$0A,$01,$83,$6B,$08,$2A,$00,$0A,$00,$09,$00,$0A,$01,$06,$09,$0E,$00,$83
    FCB $73,$01,$2E,$00,$0A,$08,$01,$00,$0E,$00,$01,$00,$0E,$00,$83,$73,$01,$32,$05,$0E,$00,$05,$00,$06,$00,$05,$00,$0A,$04,$83,$73,$01
    FCB $36,$01,$00,$0E,$00,$05,$04,$05,$00,$06,$01,$00,$01,$83,$77,$00,$3E,$00,$01,$0A,$01,$0C,$01,$12,$00,$83,$77,$00,$42,$01,$04,$01
    FCB $2A,$00,$83,$77,$01,$7A,$00,$83,$77,$00,$7E,$00,$83,$77,$00,$7A,$00,$83,$77,$01,$76,$01,$02,$01,$83,$77,$00,$72,$00,$02,$00,$83
    FCB $7B,$00,$62,$00,$06,$05,$02,$01,$83,$7B,$00,$1E,$01,$04,$12,$00,$1A,$00,$0A,$00,$02,$00,$83,$7F,$01,$1A,$04,$06,$00,$01,$0A,$00
    FCB $1A,$00,$06,$00,$06,$01,$83,$7F,$00,$12,$04,$01,$0E,$04,$06,$00,$1A,$00,$02,$00,$06,$01,$83,$83,$00,$0E,$00,$07,$00,$0E,$00,$01
    FCB $00,$01,$00,$1A,$04,$0A,$00,$83,$83,$00,$0E,$01,$07,$05,$0A,$00,$07,$01,$00,$1A,$00,$0E,$01,$83,$83,$05,$0A,$01,$0B,$0C,$01,$0B
    FCB $05,$16,$00,$12,$01,$83,$83,$0C,$01,$2F,$00,$16,$00,$0E,$05,$83,$C7,$05,$12,$00,$0E,$00,$83,$CF,$00,$12,$00,$01,$08,$83,$D7,$00
    FCB $01,$02,$01,$00,$01,$83,$EB,$09,$FF,$FB,$FF,$FB,$CD,$F7
ENDIMG
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
