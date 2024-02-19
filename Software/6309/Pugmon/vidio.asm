;------------------------------------------------------------------------------
; Project: PUGMON
;    File: vidio.asm
; Version: 0.0.1
;  Author: Craig Iannello
;
; Description:
;
; This driver supports a monochrome, 80x26 text display based on a Yamaha 
; V9958 Video Display Processor (VDP). There is no built-in font in this chip,
; so as part of the initializtion, we must send font data to the VCP.
;
; For this device to be usable by the console driver (conio) in Pugmon, we need
; to be able to fill out a structure containing some of our function addresses
; for some common consoley-type things and stuff. The serial port driver makes
; a structure. 
;
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
JT_FIRQ         EXTERN      ; ISR jump table entry for IRQ
;------------------------------------------------------------------------------
VDP_INIT        EXPORT
VDP_PUTC        EXPORT
VDP_MODE_TEXT2  EXPORT      ; (REG B) 0: NO VBLANK INTR, 1: YES VBLANK INTR
VDP_SHOW_PUG    EXPORT
VDP_CURS_STYLE  EXPORT
;------------------------------------------------------------------------------
    SECT bss
;------------------------------------------------------------------------------
; TEXT 2 MODE STUFF (80-COLUMNS, 26 ROWS)
VDP_TEXT2_BUFFER    RMB (80*27)   ; SCREEN CHAR BUFFER
VDP_BUF_DIRTY_START RMW 1   ; POINTS TO FIRST MODIFIED CHAR IN SCREEN BUF
VDP_BUF_DIRTY_END   RMW 1   ; POINTS TO CHAR AFTER LAST MODIFIED IN SCREEN BUF
VDP_CURS_BUFPTR     RMW 1   ; CURSOR CHAR POINTER TO TEXT2 BUFFER
VDP_CURS_COL        RMB 1   ; CUR COL 0..(LINELENGTH-1)
VDP_CURS_ROW        RMB 1   ; CUR ROW 0..(LINECOUNT-1)
VDP_CURS_STYLE      RMB 1   ; BIT MEANINGS:
                            ;   BIT 0: 0-HIDDEN,      1-VISIBLE
                            ;   BIT 1: UNUSED
                            ;   BIT 2: 0-INSERT,      1-OVERWRITE
                            ;   BIT 3: 0-BLINK HIGH,  1-BLINK LOW
VDP_CURS_GLYPH      RMB 1   ; CHARACTER CODE TO USE AS CURSOR                            
VDP_CURS_BLINKRATE  RMB 1   ; VBLANKS PER CURSOR STATE TOGGLE
VDP_CURS_BLINK_CT   RMB 1   ; CURRENT BLINK COUNT IN VBLANKS
VDP_VBLANK_ENABLED  RMB 1   ; TRUE IF VDP IS SET TO DO VBLANK INTERRUPTS 
                            ; USED FOR TEXT2 SCREEN AUTO-REFRESH
VDP_INTERRUPT_REASON RMB 1  ; VDP INTR STATUS REGISTER FOLLOWING PREV INTERRUPT
VSNEXTISR           RMB  2  ; ADDRESS OF NEXT FIRQ ISR SO UART ISR CAN DELEGATE
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
    INCLUDE font.asm
; -----------------------------------------------------------------------------
; PUGBUTT BANNER
VDP_PUG     FCB $01,$02,$04,$07,$19,$00,$0F,$11,$14
            FCC "PUGBUTT INDUSTRIES"
            FCB $0A,$20,$03,$05,$17,$0B,$0E,$10,$12,$15
            FCC "PUGPUTER-6309 V0.1"
            FCB $0A,$20,$20,$06,$09,$0C,$20,$20,$13,$16
            FCC "PUGBUTT.COM 2023"
            FCB $0A
VDP_END_PUG
; 16-COLOR PALETTE USED BY PICO-8 PROJECT
PAL_PICO8   FDB $0000,$1201,$3201,$0204,$5102,$3202,$5505,$7607
            FDB $7200,$7004,$7106,$0106,$1705,$4403,$7503,$7506
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
; SET VIDEO MODE TEXT2 (80 X 26 X 2) (USES A,B,X)
; NOTE: FIRST NYB: FG COLOR, SECOND NYB: BG COLOR
; -----------------------------------------------------------------------------
MODE_T2_SEQ FCB  $61,$87,$28,$88,$02,$84,$03,$82,$80,$89,$D2,$92
VDP_SET_T2  LDX  #MODE_T2_SEQ
            LDB  #(VDP_SET_T2-MODE_T2_SEQ)
            JSR  VDP_SETREGS
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
; Set mode TEXT2 (80x26), setup font and vars
; -----------------------------------------------------------------------------
VDP_INIT    CLRA                        ; INIT GLOBALS
            STA  VDP_CURS_BLINK_CT
            LDA  #VDP_CURS_DEF_BLINKRATE
            STA  VDP_CURS_BLINKRATE
            LDA  #VDP_CURS_DEF_STYLE
            STA  VDP_CURS_STYLE
            LDA  #VDP_CURS_DEF_GLYPH
            STA  VDP_CURS_GLYPH
            JSR  VDP_CLEAR_BUFFER
            LDX  #PAL_PICO8             ; SET DEFAULT COLOR PALETTE
            JSR  VDP_SETPAL
            JSR  VDP_SET_T2             ; SET DISPLAY MODE TEXT2
            BSR  VDP_LDFONT             ; LOAD FONT
            LDX  JT_FIRQ+1              ; PRESERVE DEFAULT IRQ ISR ADDRESS,
            STX  VSNEXTISR              ; FOR USE WHEN A NON-VDP IRQ HAPPENS.
            LDX  #VDP_FIRQ              ; GET ADDRESS OF OUR ISR,
            STX  JT_FIRQ+1              ; AND INSERT IT IN IRQ JUMP TABLE.
            RTS
; -----------------------------------------------------------------------------
; LOAD 6X8 FONT FROM ROM TO VDP (2048 BYTES)
; -----------------------------------------------------------------------------
VDP_LDFONT  CLRA                        ; SET VRAM ADRS
            STA  VREG
            LDA  #$8E                   ; -> REG 14
            STA  VREG
            CLRA                        ; VRAM ADRS A7-A0
            STA  VREG
            LDA  #$50                   ; VRAM ADRS A13-A8, AND WRITE-ENABLE
            STA  VREG
            LDX  #__FONT_BEGIN
FONT_LOOP   LDA  ,X+                    ; SLOWLY COPY BYTES TO VDP
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
            CMPX #__FONT_END
            BNE  FONT_LOOP 
            RTS            
; -----------------------------------------------------------------------------
; MARK ENTIRE TEXT BUF AS NEEDING XFER TO VDP
; -----------------------------------------------------------------------------
VDP_DIRTY_ALL
            LDX  #VDP_TEXT2_BUFFER
            STX  VDP_BUF_DIRTY_START
            LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE+80)
            STX  VDP_BUF_DIRTY_END
            RTS
; -----------------------------------------------------------------------------
; MARK THE 26 VISIBLE LINES OF TEXT BUF AS NEEDING XFER TO VDP
; -----------------------------------------------------------------------------
VDP_DIRTY_VISIBLE
            LDX  #VDP_TEXT2_BUFFER
            STX  VDP_BUF_DIRTY_START
            LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE)
            STX  VDP_BUF_DIRTY_END
            RTS    
; -----------------------------------------------------------------------------
; MARK NO CHARS OF SCREEN BUFFER AS DIRTY
; -----------------------------------------------------------------------------
VDP_CLEAN_SCREEN_BUF
            LDX  #0
            STX  VDP_BUF_DIRTY_START
            STX  VDP_BUF_DIRTY_END
            RTS    
; -----------------------------------------------------------------------------
; TEXT BUF CHAR POINTED TO BY X WAS ALTERED. 
; INIT OR ENLARGE DIRTY REGION TO INCLUDE THIS CHARACTER POSITION.
;
; A REGION IS DEFINED BY START & END POINTERS. IF EITHER POINTER IS NULL, THEN
; NO REGION IS YET SPECIFIED.
; -----------------------------------------------------------------------------
VDP_DIRTY_CHAR 
            LDW  VDP_BUF_DIRTY_START
            BNE  EXISTING_REGION
            STX  VDP_BUF_DIRTY_START    ; INIT NEW REGION: START = X
            LEAX 1,X
            STX  VDP_BUF_DIRTY_END      ; END = X + 1
            LEAX -1,X                   ; RESTORE VAL OF X
            RTS
EXISTING_REGION                         ; EXISTING REGION: ENLARGE AS NEEDED:
            CMPR X,W
            BLT  GROW_END
            STX  VDP_BUF_DIRTY_START    ; EITHER BY SETTING START = X,
            RTS
GROW_END    LDW  VDP_BUF_DIRTY_END
            CMPR X,W  
            BHI  SKIP_GROW_END
            LEAX 1,X
            STX  VDP_BUF_DIRTY_END      ; OR SETTING END = X + 1.
            LEAX -1,X                   ; RESTORE VAL OF X
SKIP_GROW_END
            RTS
; -----------------------------------------------------------------------------
; FILL WHOLE TEXT BACKING-BUFFER WITH LF'S, RESET CURSOR, AND MARK ALL DIRTY
; -----------------------------------------------------------------------------
VDP_CLEAR_BUFFER           
            LDX  #VDP_TEXT2_BUFFER
            STX  VDP_CURS_BUFPTR
            CLRB
            STB  VDP_CURS_ROW
            STB  VDP_CURS_COL    
            LDB  #LF
BCLRLOOP    STB  ,X+
            CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE+80) 
            BNE  BCLRLOOP 
            ORCC #$50
            JSR  VDP_DIRTY_ALL
            ANDCC #$AF
            RTS
; -----------------------------------------------------------------------------
VDP_PUTC:   ; TAKE CHARACTER IN REG A, POKE INTO BUFFER AT CURRENT CURSOR,
            ; AND ADVANCE THE CURSOR. THIS SUB DOESNT 
            ; CARE ABOUT CURSOR MODE OR CONTROL CHARS (EXCEPT CR, LF, AND BS) 
            ; AND INSTEAD SIMPLY PRINTS THE ASSOCIATED GLYPH. LD (ASCII CODE 
            ; $0A) IS A SPECIAL CASE:  IT GETS REPEATEDLY PRINTED (IT IS 
            ; NORMALLY BLANK) UNTIL CURSOR REACHES THE BEGINNING OF NEXT ROW. 
            ; BACKSPACE (ASCII $08) DOESNT PRINT A GLYPH AND INSTEAD MOVES
            ; THE CURSOR BACKWARDS ONE CHAR POSITION, TO PREVIOUS ROW IF
            ; NECESSARY.

    CMPA #CR
    BNE  NON_CR
PC_DONE    
    RTS                     ; VDP PUTC IGNORES CARRIAGE RETURNS

NON_CR
    CMPA #BS                ; CHECK IF THEY'RE DOING A BACKSPACE
    BNE  NON_BACKSPACE

DO_BS                       ; DOING BACKSPACE
    PSHS A
    LDA  VDP_CURS_COL       
    BEQ  BS_WRAP
    DECA                    ; IF COL > 0,
    STA  VDP_CURS_COL       ; JUST DECREMENT COL.
    BRA  BS_DECP
BS_WRAP                     ; IF COL = 0: 
    LDA  VDP_CURS_ROW
    BEQ  PC_DONE            ; AND ROW = 0: DO NOTHING.
    LDA  #(CON_COLS-1)      ; ELSE WRAP TO END OF
    STA  VDP_CURS_COL       ; PREVIOUS ROW.
    DEC  VDP_CURS_ROW
BS_DECP
    PSHS X                  
    LDX  VDP_CURS_BUFPTR    ; GET INITIAL BUS POS
    ; TODO: HANDLE DESTRUCTIVE BACKSPACE?
    ; (SHIFT CHARS FROM HERE TO EOLN LEFT BY ONE POS, 
    ; OVERWRITING A CHAR IN LEFT POS.. MAYBE IN A DIF FCN?) 
    ORCC #$50               ; DISABLE INTERRUPTS
    JSR  VDP_DIRTY_CHAR     ; DIRTY INITIAL BUF POS
    LEAX -1,X               ; DECREMENT BUF POS
    STX  VDP_CURS_BUFPTR
    JSR  VDP_DIRTY_CHAR     ; DIRTY FINAL BUF POS
    ANDCC #$AF              ; RE-ENABLE INTERRUPTS
    PULS X
    PULS A
    RTS                     ; DONE DOING A BACKSPACE

NON_BACKSPACE: 
    CMPA #LF                ; CHECK IF THEY ARE PRINTING A LF
    BNE  NORMAL_PUTC        ; NON-LF CHARACTER

DO_LF                       ; HANDLE A CARRIAGE RETURN
    PSHS A,B,X              
    PSHSW
    LDX  VDP_CURS_BUFPTR    ; X : STARTING BUF POINTER
    LDB  VDP_CURS_ROW       ; B : STARTING CURSOR ROW
    LDA  VDP_CURS_COL
    ORCC #$50               ; Disable IRQ and FIRQ interrupts
    JSR  VDP_DIRTY_CHAR     ; INCLUDE STARTING CHAR IN DIRTY REGION
    LDE  #LF                ; First, fill to eoln with LF chars
    LDA  VDP_CURS_COL
NEXTLF:
    STE  ,X+                ; PUT LF IN BUFFER AT CURSOR POS
    INCA                    ; ADVANCE CURSOR COLUMN
    CMPA #LINELENGTH        ; HIT EOLN?  (TODO: HANDLE 40-COLUMN MODES)
    BLO  NEXTLF             ; HAVENT HIT END OF LINE YET, GO AGAIN
    CLRA                    ; HIT EOLN, RESET CURSOR COLUMN
    INCB                    ; INCREMENT ROW
    CMPB #LINECOUNT            
    BLO  NON_BOTTOM_NEWLINE_DONE
    ; PASSED BOTTOM OF SCREEN, BLOCK COPY THE BUFFER 80 CHARS BACKWARDS
    PSHS Y
    LDX  #VDP_TEXT2_BUFFER                  ; src ptr
    LDY  #(VDP_TEXT2_BUFFER+LINELENGTH)     ; dest ptr
    LDW  #(DISPLAYSIZE-LINELENGTH)          ; length
    TFM  Y+,X+              ; do block copy.
    PULS Y
    ; FILL THE LAST 80 CHARS OF BUFFER WITH LF'S
    LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)
    LDB  #LF
FILL_LASTLINE_0:
    STB  ,X+
    CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE) 
    BLO  FILL_LASTLINE_0 
    LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)   ; RESET BUFFER PTR
    CLRA                    ; AND CURSOR COL
    LDB  #(LINECOUNT-1)     ; AND CURSOR ROW
    STA  VDP_CURS_COL       ; STORE NEW CURSOR ROW, AND COLUMN
    STB  VDP_CURS_ROW
    STX  VDP_CURS_BUFPTR    ; STORE UPDATED CURSOR BUF POINTER
    JSR  VDP_DIRTY_VISIBLE  ; WE SCROLLED, DIRTY VISIBLE REGION.
    ANDCC #$AF              ; REENABLE INTERRUPTS
    PULSW    
    PULS X,B,A    
    RTS
NON_BOTTOM_NEWLINE_DONE:
    STA  VDP_CURS_COL       ; STORE NEW CURSOR ROW, AND COLUMN
    STB  VDP_CURS_ROW
    STX  VDP_CURS_BUFPTR    ; STORE UPDATED CURSOR BUF POINTER
    JSR  VDP_DIRTY_CHAR     ; INCLUDE NEW CHARS IN BUF DIRTY AREA
    ANDCC #$AF              ; REENABLE
    PULSW    
    PULS X,B,A    
    RTS

NORMAL_PUTC:                ; NORMAL(NON-LF) PUTC
    PSHS A,B,X
    PSHSW                   ; A : OUTPUT CHAR
    LDX  VDP_CURS_BUFPTR    ; X : STARTING BUF POINTER
    LDB  VDP_CURS_ROW       ; B : STARTING CURSOR ROW
    ORCC #$50               ; Disable IRQ and FIRQ interrupts
    JSR  VDP_DIRTY_CHAR
    STA  ,X+                ; STORE CHARACTER AND ADVANCE CURSOR
    LDA  VDP_CURS_COL
    INCA                    ; ADVANCE CURS COL
    CMPA #LINELENGTH        ; HIT EOLN?  (TODO: HANDLE 40-COLUMN MODES)
    BLO  PUTC_DONE       
    CLRA                    ; EOLN. RESET COL AND
    INCB                    ; INC ROW
    CMPB #LINECOUNT     
    BLO  PUTC_DONE
    ; PASSED BOTTOM OF SCREEN, BLOCK COPY THE BUFFER 80 CHARS BACKWARDS
    LDX  #VDP_TEXT2_BUFFER
    LDY  #(VDP_TEXT2_BUFFER+LINELENGTH)
    LDW  #(DISPLAYSIZE-LINELENGTH)
    TFM  Y+,X+
    ; FILL THE LAST 80 CHARS OF BUFFER WITH LF'S
    LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)
    LDB  #LF
FILL_LASTLINE_1:
    STB  ,X+
    CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE) 
    BLO  FILL_LASTLINE_1 
    LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)   ; RESET BUFFER PTR
    CLRA                                ; AND CURSOR COL
    LDB  #(LINECOUNT-1)                 ; AND CURSOR ROW
    STA  VDP_CURS_COL
    STB  VDP_CURS_ROW
    STX  VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR POSITION
    JSR  VDP_DIRTY_VISIBLE  ; DIRTY VISIBLE REGION
    ANDCC #$AF ; REENABLE
    PULSW
    PULS X,B,A    
    RTS
PUTC_DONE: 
    STA  VDP_CURS_COL
    STB  VDP_CURS_ROW
    STX  VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR POSITION
    JSR  VDP_DIRTY_CHAR
    ANDCC #$AF ; REENABLE
    PULSW
    PULS X,B,A
    RTS
; -----------------------------------------------------------------------------
VDP_PUTCHAR:    ; TAKE CHARACTER IN REG A, POKE INTO BUFFER AT CURRENT CURSOR,
                ; HANDLING CURSOR MODE (INSERT TO CR AND/OR LF, OR OVERWRITE),
                ; LINEFEEDS, CARRIAGE RETURNS, CURSOR MOVEMENT, AND SCREEN 
                ; SCROLLING. FOR A DUMBER WAY THAT PRINTS CONTROL CHARACTERS AS
                ; GLYPHS, SEE VDP_PUTC, ABOVE.

    RTS
; -----------------------------------------------------------------------------
; COPY DIRTY REGION OF TEXT BUFFER TO CORRESPONDING REGION OF VDP TEXT PAGE
; -----------------------------------------------------------------------------
VDP_WRITE_BUFFER:      
    LDW VDP_BUF_DIRTY_START     ; SET DEST ADDRESS IN VDP
    SUBW #VDP_TEXT2_BUFFER
    CLRA     
    STA VREG
    LDA #$8E
    STA VREG
    STF VREG
    LDA #%00111111
    ANDR A,E 
    LDA #%01000000
    ORR A,E
    STE VREG
    LDA  VDP_CURS_STYLE
    ANDA #9                     ; IF CURSOR ENABLED AND IN ON-BLINK, 
    CMPA #9
    BEQ  WR_CURS_VIS            ; DO PIECEWISE COPY,
    LDX VDP_BUF_DIRTY_START     ; ELSE, DO STRAIGHT COPY.
BUFFER_WRITE_LOOP:
    LDA  ,X+
    STA  VDAT
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX VDP_BUF_DIRTY_END
    BNE  BUFFER_WRITE_LOOP
    LDX  #0                      ; MARK TEXT BUFF ALL CLEAN
    STX  VDP_BUF_DIRTY_START
    STX  VDP_BUF_DIRTY_END
    RTS   

WR_CURS_VIS:                    ; CURSOR VISIBLE, COPY IN PARTS.
    LDX  VDP_BUF_DIRTY_START    ; COPY FROM DIRTY START UP TO CURSOR
    CMPX VDP_CURS_BUFPTR   
    BEQ  SKIP_PRECUR
BUFFER_WRITE2_LOOP:
    LDA  ,X+
    STA  VDAT
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX VDP_CURS_BUFPTR
    BNE  BUFFER_WRITE2_LOOP
SKIP_PRECUR:
    LDA  VDP_CURS_GLYPH
    STA  VDAT                   ; WRITE CURSOR CHARACTER TO VDP
    LDA  ,X+                    ; INC BUFPTR
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX VDP_BUF_DIRTY_END      ; IF CURSOR IS AT END OF DIRTY 
    BGE  DONE_CURCOPY           ; WE'RE DONE.
BUFFER_WRITE3_LOOP:             ; COPY REMAINDER OF DIRTY TO VDP
    LDA  ,X+
    STA  VDAT
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX VDP_BUF_DIRTY_END
    BNE  BUFFER_WRITE3_LOOP
DONE_CURCOPY:
    LDX  #0                      ; MARK TEXT BUFF ALL CLEAN
    STX  VDP_BUF_DIRTY_START
    STX  VDP_BUF_DIRTY_END
    RTS
; -----------------------------------------------------------------------------
; FIRQ  - can be called by the VDP for VBLANK, HBLANK, scanline, sprite, etc.
; -----------------------------------------------------------------------------
VDP_FIRQ:    
    PSHS A,B,X,Y,U
    PSHSW     ; PUSH W ALSO

    ; ALSO TODO: MAKE THE VDP VBLANK STUFF IN HERE ONLY HAPPEN IF IT THE
    ; FIRQ WAS REALLY CAUSED BY A VBLANK AND NOT SOMETHING ELSE LIKE HBLANK
    ; OR A NON-VDP FIRQ.

    CLRA        ; GET VDP STATUS REGISTER S#0 TO DETERMINE INTERRUPT SOURCE
    STA VREG    ; AND CLEAR THE INTERRUPT.
    LDA #143
    STA VREG
    LDA VREG
    STA VDP_INTERRUPT_REASON

    TIM #1,VDP_CURS_STYLE   ; TEST CURSOR VISIBILITY,
    BEQ CURSOR_UPDATE_DONE  ; IF CURSOR DISABLED, SKIP CURSOR STUFF

    LDA VDP_CURS_BLINK_CT
    INCA                    ; INC CURS BLINK TIMER  
    STA VDP_CURS_BLINK_CT
    CMPA VDP_CURS_BLINKRATE
    BLT CURSOR_UPDATE_DONE  ; IF NOT TIME TO TOGGLE BLINK, DONE WITH CURSOR

    CLRA                    ; RESET BLINK TIMER
    STA VDP_CURS_BLINK_CT       
    LDA #8                  ; TOGGLE BLINK STATE (BIT VDP_CURS_STYLE.3)
    EORA VDP_CURS_STYLE     
    STA VDP_CURS_STYLE

    LDX VDP_CURS_BUFPTR
    JSR VDP_DIRTY_CHAR      ; INCLUDE CURSOR CHAR POSITION AS DIRTY.

CURSOR_UPDATE_DONE:
    LDW VDP_BUF_DIRTY_START ; CHECK FOR DIRTY TEXT BUF REGION.
    BEQ FIRQ_DONE           ; IF NONE, WE'RE DONE, ELSE
    JSR VDP_WRITE_BUFFER    ; COPY DIRTY REGION TO VDP.

FIRQ_DONE:
    PULSW                   ; POP W TOO
    PULS A,B,X,Y,U
    RTI 
; -----------------------------------------------------------------------------
; COPY HELLO MSG AND PUG IMAGE TO 80-COLUMN TEXT SCREEN 
; 
; -----------------------------------------------------------------------------
VDP_SHOW_PUG:  
    LDU  #VDP_PUG
SCREEN_COPY_LOOP:
    LDA  ,U+
    JSR  VDP_PUTC
    CMPU #VDP_END_PUG
    BNE  SCREEN_COPY_LOOP 
    JSR  VDP_WRITE_BUFFER ; COPY BUFFER TO CURRRNT TEXT2 PAGE IN VDP
    LDB  #1
    BSR  VDP_MODE_TEXT2   ; ENABLE TEXT SCREEN WITH AUTO REFRESH
    RTS
; -----------------------------------------------------------------------------
; Sets 80-column text mode and turns display on.
;
; REGISTER B:  1 - ENABLE VBLANK INTERRUPT (TEXT SCREEN AUTO REFRESH)
;              0 - DISABLE VBLANK INTERRUPT
; -----------------------------------------------------------------------------
VDP_MODE_TEXT2:
    LDA  #%00000100        ; Write DG=0,IE2=0,IE1=0,M5=0,M4=0,M3=0
    STA  VREG
    LDA  #$80              ; To register 0
    STA  VREG
    TSTB
    BNE  WITHV 
    LDA #%01010000         ; Write BL=1,IE0=0,M1=1,M2=0,SI=0,MAG=0
    BRA VENCNT
WITHV   
    LDA  #%01110000         ; Write BL=1,IE0=1,M1=1,M2=0,SI=0,MAG=0
VENCNT   
    STA  VREG
    LDA  #$81              ; To register 1
    STA  VREG   
    STB VDP_VBLANK_ENABLED
    RTS
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of vidio.asm
;------------------------------------------------------------------------------
