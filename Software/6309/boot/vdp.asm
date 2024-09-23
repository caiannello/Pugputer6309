;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - bootloader 
; VERSION: 0.0.2
;    FILE: vdp.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; There may be a V9958 video card on the system. If so, these routines allow
; the bootloader to init a simple video mode and draw a minimal splash screen.
;
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; Global settings and definitions
;------------------------------------------------------------------------------
VDP_INIT    EXPORT
;------------------------------------------------------------------------------
    SECT bss                ; Private variables - section address $0030
    ENDSECT
;------------------------------------------------------------------------------
    SECT code               ; Section address  $F000 - $FF00
; -----------------------------------------------------------------------------
VDP_G7_SEQ  FCB $11,$87,$0E,$80,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$40
            FCB $00,$8E,$00,$40  ; SET 256 X 212 X 256 COLOR MODE
; -----------------------------------------------------------------------------
VDP_GRAF7   LDX  #VDP_G7_SEQ ; INIT 256 X 212 X 256 COLORS MODE ---------------
VDP_ILOOP7  LDA  ,X+        ; GET NEXT VDP INIT BYTE
            STA  VREG       ; WRITE TO VDP
            CMPX #VDP_GRAF7
            BLO  VDP_ILOOP7 ; LOOP UNTIL ALL BYTES SENT
            RTS                 
; -----------------------------------------------------------------------------
; MONOCHROME CRT NOSTALGIA
PAL_WHITE   FDB $0100,$6707
; -----------------------------------------------------------------------------
; SEND A SEQUENCE OF REGISTER SETTINGS TO VDP (USES A,B,X)
; X = ADRS OF SEQ, B = SEQ LEN
; -----------------------------------------------------------------------------
VDP_SETREGS LDA  ,X+
            STA  VREG
            DECB
            BNE  VDP_SETREGS
            RTS
; -----------------------------------------------------------------------------
; SET VDP DEFAULTS: VIDEO FORMAT, TEXT FORMAT, AND PALETTE (USES A,B,X)
; NOTE: FIRST NYB: TEXT FG COLOR, SECOND NYB: TEXT BG COLOR
; NOTE: STILL HAVE TO CALL VDP_MODE_TEXT2 TO ENABLE THE TEXT DISPLAY
; -----------------------------------------------------------------------------
VDP_INI_SEQ FCB  $10,$87,$28,$88,$02,$84,$03,$82,$80,$89,$D2,$92
VDP_SET_DEF LDX  #VDP_INI_SEQ
            LDB  #(VDP_SET_DEF-VDP_INI_SEQ)
            JSR  VDP_SETREGS
            LDX  #PAL_WHITE
            JSR  VDP_SETPAL
            RTS
; -----------------------------------------------------------------------------
; SET VDP PALETTE (16-COLORS)  (USES A,B,X)
; X = ADRS OF PALETTE 
; -----------------------------------------------------------------------------
VDP_SETPAL  CLRA        ; starting at idx 0,
            STA  VREG
            LDA  #$90   ; setup palette.
            STA  VREG
            LDB  #32
PAL_LOOP    LDA  ,X+
            STA  VPAL
            DECB
            BNE  PAL_LOOP
            RTS            
; -----------------------------------------------------------------------------
VDP_INIT    JSR  VDP_SET_DEF
            ; set text2 mode, no vblank
            LDA  #%00000100        ; Write DG=0,IE2=0,IE1=0, M5=0,M4=1,M3=0 
            STA  VREG              ; NO hblank interrupt, TEXT2
            LDA  #$80              ; To reg 0: (0)(dg)(ie2)(ie1)(m5)(m4)(m3)(0)
            STA  VREG
            LDA #%01010000         ; Screen on, NO vblank interrupt, TEXT2
            STA  VREG
            LDA  #$81              ; To reg 1: (0)(bl)(ie0)(m1)(m2)(0)(si)(mag)
            STA  VREG   
            JSR  VDP_GRAF7
            ; for now, just load an incrementing color byte for eack of the 
            ; pixels of the display. (256*212 pixels/bytes)
            LDD  #0
DRAWLOOP    NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            STA  VDAT
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            STB  VDAT            
            INCD
            CMPD #(128*212)
            BLO  DRAWLOOP
            RTS
;------------------------------------------------------------------------------
    ENDSECT            
;------------------------------------------------------------------------------
; End of vdp.asm
;------------------------------------------------------------------------------
