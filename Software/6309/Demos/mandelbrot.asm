;------------------------------------------------------------------------------
; PROJECT: mandel 
; VERSION: 0.0.1
;    FILE: mandel.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; DESCRIPTION:
;
; DRAWS A MANDELBROT FRACTAL ON THE VIDEO DISPLAY.
;
; REQUIRES AN HD6309 CPU IN NATIVE MODE, A V9958 VDP, AND A COPY 
; OF THE MC6839 FLOATING-POINT ROM (8192 BYTES) STARTING AT ADDRESS $8000.
;
;------------------------------------------------------------------------------
                            ; V9958 VDP CONSTANTS 
VDAT        EQU     $F400   ; Port 0: VRAM Data (R/W)
VREG        EQU     $F401   ; Port 1: Status Reg (R), Register/setup (W), VRAM Addr (W)
VPAL        EQU     $F402   ; Port 2: Palette Registers (W)
VIND        EQU     $F403   ; Port 3: Register-indirect addressing (W)

                            ; MC6839 FLOATING-POINT ROM STARTS AT $8000
FPREG       EQU     $803D   ; FP CALL ADDRESS WHEN ARGS ARE IN REGISTERS
FPSTAK      EQU     $803F   ; FP CALL ADDRESS WHEN ARGS ARE ON STACK

; FLOATING POINT EXPERIMENT CONSTANTS -----------------------------------------

_XSZ        EQU     255     ; IMAGE WIDTH IN PIXELS
_YSZ        EQU     211     ; IMAGE HEIGHT IN SCANLINES
_I1         EQU     -1      ; STARTING IMAGINARY PART
_I2         EQU     1       ; ENDING IMAGINARY PART
_R1         EQU     -2      ; STARTING REAL PART
_R2         EQU     1       ; ENDING REAL PART
_MAX_ITER   EQU     32      ; MAX ITERATIONS PER PIXEL TO TRY TO ESCAPE
_TWO        EQU     2
_FOUR       EQU     4
_TWOFIVESIX EQU     256

; MC6839 FLOATING-POINT ROM OPCODES

FADD        EQU     $00
FSUB        EQU     $02
FMUL        EQU     $04
FDIV        EQU     $06
FREM        EQU     $08
FCMP        EQU     $BA
FTCMP       EQU     $CC
FPCMP       EQU     $BE
FTPCMP      EQU     $D0
FMOV        EQU     $9A
FSQRT       EQU     $12
FINT        EQU     $14
FFIXS       EQU     $16
FFIXD       EQU     $18
FFLTS       EQU     $24
FFLTD       EQU     $26
BINDEC      EQU     $1C
DECBIN      EQU     $22
FABS        EQU     $1E
FNEG        EQU     $20

; INITIAL VALUES OF BYTES IN FLOATING-POINT CONTROL BLOCK (FPCB)

FPCB0       EQU     %00001001   ; CONTROL BYTE: SINGLE PRECISION, ROUND NEAREST, 
                                ;   NORMALIZED, AFFINE CLOSURE
FPCB1       EQU     $00         ; ENABLE BYTE: NO TRAPS ARE ENABLED
FPCB2       EQU     $00         ; STATUS BYTE: NONE SET BY US
FPCB3       EQU     $00         ; SECONDARY STATUS: NONE SET BY US 
FPCB4       EQU     $00         ; TRAP ROUTINE ADDRESS HI
FPCB5       EQU     $00         ; TRAP ROUTINE ADDRESS LO

            ORG  $4000          ; RAM VARIABLES -------------------------------

FPCB        RMB     6   ; FLOATING POINT CONTROL BLOCK
PX          RMW     1   ; PIXEL X LOOP VAR
PY          RMW     1   ; PIXEL Y LOOP VAR
PN          RMB     2   ; FUNC ITERATION LOOP VAR
XSZ         RMB     4   ; IMAGE WIDTH IN PIXELS
YSZ         RMB     4   ; IMAGE HEIGHT IN PIXELS
I1          RMB     4   ; IMAGINARY START VAL
I2          RMB     4   ; IMAGINARY END VAL AND LATER WORKING VAL
R1          RMB     4   ; REAL START VAL
R2          RMB     4   ; REAL END VAL AND LATER WORKING VAL
S1          RMB     4   ; REAL VAL STEP PER HORIZONTAL PIXEL
S2          RMB     4   ; IMAG VAL STEP VER VERTICAL PIXEL
Z1          RMB     4   ; ITERATOR WORKING VAL
Z2          RMB     4   ; ITERATOR WORKING VAL
AA          RMB     4   ; ITERATOR WORKING VAL
BB          RMB     4   ; ITERATOR WORKING VAL
FTWO        RMB     4   ; 2.0
FFOUR       RMB     4   ; 4.0
FSUM        RMB     4   ; FOR DOING AA+BB
F256        RMB     4   ; 256.0
FPZ1        RMB     2
FPZ2        RMB     2
FPA         RMB     2
FPB         RMB     2
FPSUM       RMB     2
FPI2        RMB     2
FPR2        RMB     2
SHVAL       RMW     1   ; INT16 TEMP VAL

            ORG  $D000      ; START OF ROM ------------------------------------

VDP_GRAF7_SZ EQU  18        ; NUMBER OF BYTES OF SEQ BELOW
VDP_G7_SEQ  FCB $11,$87,$0E,$80,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$40
            FCB $00,$8E,$00,$40  ; SET 256 X 212 X 256 COLOR MODE

; -----------------------------------------------------------------------------
; DRAW A FULLSCREEN MANDELBROT IN THE V9958'S 256 COLOR GRAPHICS MODE 
;
; FLOATING POINT IS USED IN THE INNER X-, AND Y-LOOPS FOR CALCULATING INITIAL
; VALUES. THE FLOAT LIBRARY IS A DUMP OF MOTOROLA'S MC6829 FLOATING POINT 
; ROM. THIS 8192-BYTE LIBRARY IS VERY PRECISE, BUT ALSO VERY SLOW. 
;
; FOR THE INNERMOST N-LOOP, 8.8 FIXED-POINT MATH IS USED INSTEAD, FOR SPEED.
; THIS PROVIDES A HUGE SPEEDUP AT THE EXPENSE OF PRECISION.
;
; ZOOMING IN TO THE FRACTAL IS NOT GOING TO LOOK GOOD WHILE USING THE 
; FIXED-POINT, SO THE MATH SHOULD BE SWITCHED BACK TO FLOATING POINT IF 
; ZOOMING IS NEEDED.
; -----------------------------------------------------------------------------

FLOAT_EXPERIMENT
            LDA  #FPCB0     ; INIT FLOATING-POINT CONTROL BLOCK
            STA  (FPCB+0)   ; (FLOATING POINT LIBRARY CONFIG., SPECIFYING
            LDA  #FPCB1     ; SINGLE-PRECISION AND NO TRAPS)
            STA  (FPCB+1)
            LDA  #FPCB2
            STA  (FPCB+2)
            LDA  #FPCB3
            STA  (FPCB+3)
            LDA  #FPCB4
            STA  (FPCB+4)
            LDA  #FPCB5
            STA  (FPCB+5)

            LDX  #_XSZ      ; INIT XSZ (FLOAT) FROM INTEGER VALUE
            STX  SHVAL      ; 16-BIT TEMP VAL
            LDX  #XSZ       ; PTR TO ARG1 (RESULT)
            LDY  #SHVAL     ; PTR TO ARG2 (ARG)
            LDD  #FPCB      ; PTR TO FP CONTROL BLOCK
            LBSR FPREG      ; FP CALL - ARGS IN REGISTERS
            FCB  FFLTS      ; OPCODE: CONVERT INT16 TO FLOAT
            LDX  #_YSZ      ; INIT YSZ
            STX  SHVAL
            LDX  #YSZ
            LDY  #SHVAL
            LDD  #FPCB
            LBSR FPREG
            FCB  FFLTS
            LDX  #_I1       ; INIT I1
            STX  SHVAL
            LDX  #I1
            LDY  #SHVAL
            LDD  #FPCB
            LBSR FPREG
            FCB  FFLTS
            LDX  #_I2       ; INIT I2
            STX  SHVAL
            LDX  #I2
            LDY  #SHVAL
            LDD  #FPCB
            LBSR FPREG
            FCB  FFLTS
            LDX  #_R1       ; INIT R1
            STX  SHVAL
            LDX  #R1
            LDY  #SHVAL
            LDD  #FPCB
            LBSR FPREG
            FCB  FFLTS
            LDX  #_R2       ; INIT R2
            STX  SHVAL
            LDX  #R2
            LDY  #SHVAL
            LDD  #FPCB
            LBSR FPREG
            FCB  FFLTS
            LDX  #_TWO      ; TWO
            STX  SHVAL
            LDX  #FTWO
            LDY  #SHVAL
            LDD  #FPCB
            LBSR FPREG
            FCB  FFLTS
            LDX  #_FOUR     ; FOUR
            STX  SHVAL
            LDX  #FFOUR
            LDY  #SHVAL
            LDD  #FPCB
            LBSR FPREG
            FCB  FFLTS
            LDX  #_TWOFIVESIX ; 256.0 FOR SCALING FLOATS TO FIXED-POINT
            STX  SHVAL
            LDX  #F256
            LDY  #SHVAL
            LDD  #FPCB
            LBSR FPREG
            FCB  FFLTS

            LDX  #S1        ; CALC REAL AXIS STEP SIZE PER PIXEL X
            LDY  #R1        
            LDU  #R2        
            LDD  #FPCB
            LBSR FPREG      
            FCB  FSUB       ; S1=R2-R1
            LDX  #S1
            LDY  #XSZ       
            LDU  #S1        
            LDD  #FPCB
            LBSR FPREG       
            FCB  FDIV       ; S1=S1/XSZ
            LDX  #S2        ; CALC IMAGINARY AXIS STEP SIZE PER PIXEL Y
            LDY  #I1
            LDU  #I2
            LDD  #FPCB
            LBSR FPREG
            FCB  FSUB       ; S2=I2-I1
            LDX  #S2
            LDY  #YSZ
            LDU  #S2
            LDD  #FPCB
            LBSR FPREG
            FCB  FDIV       ; S2=S2/YSZ 

            JSR  VDP_GRAF7   ; SET GRAPHICS MODE 255*211, 256 COLORS

            LDQ  I1
            STQ  I2         ; I2 = I1

            LDX  #0
            STX  PY         ; FOR PY = 0 TO _YSZ ------------------------------
YLOOP       LDQ  R1
            STQ  R2         ; R2 = R1 ; BACK TO LEFT OF SCREEN

            LDX  #Z1        ; CONVERT I2 TO FIXED POINT FOR USE IN N-LOOP
            LDY  #I2
            LDU  #F256
            LDD  #FPCB          
            LBSR FPREG
            FCB  FMUL       ; Z1 = I2 * 256
            LDX  #SHVAL
            LDY  #Z1
            LBSR FPREG
            FCB  FFIXS
            LDX  SHVAL
            STX  FPI2       ; FPI2 = (INT)Z1

            LDX  #0
            STX  PX         ; FOR PX = 0 TO _XSZ ------------------------------

XLOOP       LDX  #Z1        ; CONVERT R2 TO FIXED-POINT FOR USE IN N-LOOP
            LDY  #R2
            LDU  #F256
            LDD  #FPCB          
            LBSR FPREG
            FCB  FMUL       ; Z1 = R2 * 256
            LDX  #SHVAL
            LDY  #Z1
            LBSR FPREG
            FCB  FFIXS
            LDX  SHVAL
            STX  FPR2       ; FPR2 = (INT)Z1

            LDD  FPR2
            STD  FPZ1       ; FPZ1 = FPR2
            LDD  FPI2
            STD  FPZ2       ; FPZ2 = FPI2

            LDX  #0
            STX  PN         ; FOR N = 0 TO _MAX_ITER --------------------------
NLOOP       LDD  FPZ1 
            MULD FPZ1       ; WHEN MULTIPLYING TWO 8.8 FIXED-POINT NUMS,
            TFR  B,A        ; THE MIDDLE 2 BYTES OF THE 32 BIT RESULT ARE THE
            TFR  E,B        ; FIXED-POINT RESULT.  E.G.:
            STD  FPA        ; A = Z1*Z1 BECOMES FPA = (FPZ1 * FPZ1)>>8
            LDD  FPZ2
            MULD FPZ2
            TFR  B,A
            TFR  E,B                        
            STD  FPB        ; FPB = (FPZ2 * FPZ2)>>8
            ADDD FPA
            STD  FPSUM      ; FPSUM = FPA + FPB
            CMPD #1024
            BGE  DONEITER   ; IF FPSUM>4*256 THEN DONEITER
NOESCAPE    LDD  FPZ1
            MULD FPZ2
            TFR  B,A
            TFR  E,B            
            MULD #512
            TFR  B,A
            TFR  E,B            
            ADDD FPI2
            STD  FPZ2       ; FPZ2 = 2*Z1*Z2+I2 = ((FPZ1 * FPZ2)>>8 * 512)>>8+FPI2
            LDD  FPA 
            SUBD FPB 
            ADDD FPR2
            STD  FPZ1       ; FPZ1 = FPA - FPB + FPR2       
            LDX  PN
            LEAX 1,X
            STX  PN 
            CMPX #_MAX_ITER
            BLO  NLOOP      ; NEXT N ------------------------------------------
            LDX  #0
            STX  PN         ; DIDNT ESCAPE IN TIME
DONEITER    LDA  PN+1
            LSLA
            LSLA
            LSLA
            STA  VDAT       ; POKE &HF400,N*8
            LDX  #R2
            LDY  #R2
            LDU  #S1
            LDD  #FPCB          
            LBSR FPREG
            FCB  FADD       ; R2 = R2 + S1
            LDX  PX
            LEAX 1,X
            STX  PX
            CMPX #_XSZ
            LBLE XLOOP      ; NEXT PX -----------------------------------------
            LDX  #I2
            LDY  #I2
            LDU  #S2
            LDD  #FPCB          
            LBSR FPREG
            FCB  FADD       ; I2 = I2 + S2    
            LDX  PY
            LEAX 1,X
            STX  PY
            CMPX #_YSZ
            LBLE YLOOP      ; NEXT PY -----------------------------------------
            RTS
; -----------------------------------------------------------------------------
VDP_GRAF7   LDX  #VDP_G7_SEQ ; INIT 256 X 212 X 256 COLORS MODE ---------------
VDP_ILOOP7  LDA  ,X+        ; GET NEXT VDP INIT BYTE
            STA  VREG       ; WRITE TO VDP
            CMPX #(VDP_G7_SEQ+VDP_GRAF7_SZ)
            BLO  VDP_ILOOP7 ; LOOP UNTIL ALL BYTES SENT
            RTS               
;------------------------------------------------------------------------------
; END OF MANDEL.ASM
;------------------------------------------------------------------------------
