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
                            ;   BIT 1: 0-UNDERLINE,   1-BLOCK
                            ;   BIT 2: 0-INSERT,      1-OVERWRITE
                            ;   BIT 3: 0-BLINK HIGH,  1-BLINK LOW
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
VDP_PUG:                    ; PUGBUTT GLYPHS AND BANNER TEXT
    FCB $01,$02,$04,$07,$19,$00,$0F,$11,$14
    FCC "PUGBUTT INDUSTRIES"
    FCB $0D,$20,$03,$05,$17,$0B,$0E,$10,$12,$15
    FCC "PUGPUTER-6309 V0.1"
    FCB $0D,$20,$20,$06,$09,$0C,$20,$20,$13,$16
    FCC "PUGBUTT.COM 2023"
    FCB $0D
VDP_END_PUG:    
; -----------------------------------------------------------------------------
; Set mode TEXT2 (80x26), setup font and vars
; -----------------------------------------------------------------------------
VDP_INIT:  ; init globals
    LDA #0
    STA VDP_CURS_BLINK_CT
    LDA #VDP_CURS_DEF_BLINKRATE
    STA VDP_CURS_BLINKRATE
    LDA #VDP_CURS_DEF_STYLE
    STA VDP_CURS_STYLE
    JSR VDP_CLEAR_BUFFER
    LDA #$00  ; starting at idx 0,
    STA VREG
    LDA #$90  ; setup palette.
    STA VREG
    LDA #BACKGROUND1
    STA VPAL
    LDA #BACKGROUND2
    STA VPAL          ; set palette color 0  (bg color)
    LDA #FOREGROUND1
    STA VPAL
    LDA #FOREGROUND2
    STA VPAL          ; set palette color 1 (text color)
    LDA #$10  ; test screen forground color 1, background color 0    
    STA VREG
    LDA #$87  ; .. In VDP register 7
    STA VREG    
    LDA #$28  ; Select VRAM chip size, disable sprites
    STA VREG
    LDA #$88  ; .. In VDP register 8
    STA VREG
    ; Set pattern generator table to 0x1000    
    LDA #$02  ; bits 16-11 of 0x1000
    STA VREG
    LDA #$84  ; .. to register 4
    STA VREG
    ; Set pattern layout table to page 0    
    LDA #VDP_REG2_PAGE0
    STA VREG
    LDA #$82  ; .. to register 2
    STA VREG
    ; Set PAL/NTSC mode 
    LDA #DISPMODE  ; Write PAL/NTSC mode
    STA VREG
    LDA #$89  ; .. to register 9
    STA VREG
    BSR VDP_LOAD_FONT
    LDA #$D2  ; NUDGE THE 80x26 TEXT SCREEN DOWN AND LEFT TO CENTER IT
    STA VREG
    LDA #$92 ; REG #18
    STA VREG
    LDX  JT_FIRQ+1   ; PRESERVE DEFAULT IRQ ISR ADDRESS,
    STX  VSNEXTISR   ; FOR USE WHEN A NON-UART IRQ HAPPENS.
    LDX  #VDP_FIRQ   ; GET ADDRESS OF UART IRQ ISR,
    STX  JT_FIRQ+1   ; AND PUT IT IN THE IRQ JUMP TABLE.

    RTS
; -----------------------------------------------------------------------------
; MARK ENTIRE TEXT BUF, INCLUDING UNUSED PARTIAL LAST LINE, AS NEEDING XFER TO VDP
; -----------------------------------------------------------------------------
VDP_DIRTY_WHOLE_SCREEN_BUF:
    LDX #VDP_TEXT2_BUFFER
    STX VDP_BUF_DIRTY_START
    LDX #(VDP_TEXT2_BUFFER+DISPLAYSIZE+80)
    STX VDP_BUF_DIRTY_END
    RTS
; -----------------------------------------------------------------------------
; MARK ALL 26 VISIBLE LINES OF TEXT BUF AS NEEDING XFER TO VDP
; -----------------------------------------------------------------------------
VDP_DIRTY_SCREEN_BUF: 
    LDX #VDP_TEXT2_BUFFER
    STX VDP_BUF_DIRTY_START
    LDX #(VDP_TEXT2_BUFFER+DISPLAYSIZE)
    STX VDP_BUF_DIRTY_END
    RTS    
; -----------------------------------------------------------------------------
; MARK NO CHARS OF SCREEN BUFFER DIRTY
; -----------------------------------------------------------------------------
VDP_CLEAN_SCREEN_BUF: 
    LDX #0
    STX VDP_BUF_DIRTY_START
    STX VDP_BUF_DIRTY_END
    RTS    
; -----------------------------------------------------------------------------
; TEXT BUF CHAR POINTED TO BY X WAS ALTERED. INIT OR ENLARGE DIRTY REGION
; -----------------------------------------------------------------------------
VDP_DIRTY_CHAR: 
    LDW VDP_BUF_DIRTY_START ; IF ZERO, NOTHING IS DIRTY,
    BEQ REGION_INIT         ; SO MAKE DIRTY REGION TO ENCLOSE THE CHAR.
REGION_ENLARGE:             ; ENLARGE CURRENT DIRTY REGION TO ENCOMPASS CHAR
    LDW VDP_BUF_DIRTY_END
    CMPR X,W  
    BHI SKIP_ENLARGE_END    ; DIRT END IS ALREADY TO RIGHT OF CHAR
    STX VDP_BUF_DIRTY_END 
    LDW VDP_BUF_DIRTY_END
    INCW
    STW VDP_BUF_DIRTY_END
SKIP_ENLARGE_END:
    LDW VDP_BUF_DIRTY_START
    CMPR X,W
    BLT SKIP_ENLARGE_START  ; DIRT START IS ALREADY LEFT OF DIRTY CHAR
    STX VDP_BUF_DIRTY_START 
SKIP_ENLARGE_START:
    RTS
REGION_INIT:                ; DIRTY JUST THE CURRENT CHAR POSITION
    STX VDP_BUF_DIRTY_START 
    LDW VDP_BUF_DIRTY_START
    INCW
    STW VDP_BUF_DIRTY_END
    RTS
; -----------------------------------------------------------------------------
VDP_LOAD_FONT:  ; load 6x8 font from ROM into VDP
                ; Set up to write VRAM at 0x1000
                ; 0x1000 equates to 00001000000000000, 
                ; which is split across the writes as:
                ; Write 1: bits 16-14 = (00000)000  = 0
                ; Write 2: bits 7-0   = 00000000    = 0
                ; Write 3: bits 13-8  = (01)010000  = $50 ($40 is write-enable)
    LDA #$00    ; VRAM Base at 0
    STA VREG
    LDA #$8E    ; > register 14
    STA VREG
    LDA #$0     ; Set VRAM A0-A7
    STA VREG
    LDA #$50    ; Set VRAM A8-A13, and write enable
    STA VREG
    ; COPY FONT BYTES TO VDAT. SLOWLY.
    LDX #__FONT_BEGIN
FONT_COPY_LOOP:
    LDA ,X+
    NOP
    NOP
    NOP
    NOP
    NOP    
    STA VDAT
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX #__FONT_END
    BNE FONT_COPY_LOOP 
    RTS
; -----------------------------------------------------------------------------
VDP_CLEAR_BUFFER:           ; fill the 80-col screen backing buffer with CR'S
    LDX  #VDP_TEXT2_BUFFER  ; todo, handle 40-column modes
    STX  VDP_CURS_BUFPTR    ; reset cursor to beginning of buffer
    LDB  #0
    STB  VDP_CURS_ROW
    STB  VDP_CURS_COL    
    LDB  #$0D
BUF_CLEAR_LOOP:
    STB  ,X+
    ; the extra 80 is for the unused partial line at the end
    CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE+80) 
    BNE  BUF_CLEAR_LOOP 
    ORCC #$50               ; Disable IRQ and FIRQ interrupts
    JSR  VDP_DIRTY_WHOLE_SCREEN_BUF
    ANDCC #$AF              ; REENABLE
    RTS
; -----------------------------------------------------------------------------
VDP_PUTC:   ; TAKE CHARACTER IN REG A, POKE INTO BUFFER AT CURRENT CURSOR,
            ; AND ADVANCE THE CURSOR. THIS SUB DOESNT 
            ; CARE ABOUT CURSOR MODE OR CONTROL CHARS (EXCEPT CR AND BACKSPACE) 
            ; AND INSTEAD SIMPLY PRINTS THE ASSOCIATED GLYPH. CR (ASCII CODE 
            ; $0D) IS A SPECIAL CASE:  IT GETS REPEATEDLY PRINTED (IT IS 
            ; NORMALLY BLANK) UNTIL CURSOR REACHES THE BEGINNING OF NEXT ROW. 
            ; BACKSPACE (ASCII $08) DOESNT PRINT A GLYPH AND INSTEAD MOVES
            ; THE CURSOR BACKWARDS ONE CHAR POSITION, TO PREVIOUS ROW IF
            ; NECESSARY.

    CMPA #10
    BNE  NON_LINEFEED
PC_DONE    
    RTS                     ; VDP PUTC IGNORES LINFEEDS

NON_LINEFEED
    CMPA #8                 ; CHECK IF THEY'RE DOING A BACKSPACE
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
    PSHSW                   ; DECREMENT CURSOR BUF POINTER
    LDW  VDP_CURS_BUFPTR
    DECW
    STW  VDP_CURS_BUFPTR
    PULSW
    PULS A
    RTS                     ; DONE DOING BACKSPACE

NON_BACKSPACE: 
    CMPA #13                ; CHECK IF THEY ARE PRINTING A CR
    BNE  NORMAL_PUTC        ; NON-CR CHARACTER

DO_CR
    PSHS A,B,X              
    PSHSW
    LDX  VDP_CURS_BUFPTR    ; X : STARTING BUF POINTER
    LDB  VDP_CURS_ROW       ; B : STARTING CURSOR ROW
    LDA  VDP_CURS_COL
    ORCC #$50               ; Disable IRQ and FIRQ interrupts
    JSR  VDP_DIRTY_CHAR     ; INCLUDE STARTING CHAR IN DIRTY REGION
    ANDCC #$AF              ; REENABLE

    LDE  #13                ; First, fill to eoln with CR chars
    LDA  VDP_CURS_COL
NEXTCR:
    STE  ,X+                ; PUT CR IN BUFFER AT CURSOR POS
    INCA                    ; ADVANCE CURSOR COLUMN
    CMPA #LINELENGTH        ; HIT EOLN?  (TODO: HANDLE 40-COLUMN MODES)
    BLO  NEXTCR             ; HAVENT HIT END OF LINE YET, GO AGAIN
    LDA  #0                 ; HIT EOLN, RESET CURSOR COLUMN
    INCB                    ; INCREMENT ROW
    CMPB #LINECOUNT            
    BLO  NON_BOTTOM_NEWLINE_DONE

    ; PASSED BOTTOM OF SCREEN, BLOCK COPY THE BUFFER 80 CHARS BACKWARDS
    PSHS Y
    ORCC #$50               ; Disable IRQ and FIRQ interrupts
    LDX  #VDP_TEXT2_BUFFER                  ; src ptr
    LDY  #(VDP_TEXT2_BUFFER+LINELENGTH)     ; dest ptr
    LDW  #(DISPLAYSIZE-LINELENGTH)          ; length
    TFM  Y+,X+              ; do block copy.
    ANDCC #$AF              ; REENABLE
    PULS Y
    ; FILL THE LAST 80 CHARS OF BUFFER WITH CR'S
    LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)
    LDB  #13    
FILL_LASTLINE_0:
    STB  ,X+
    CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE) 
    BLO  FILL_LASTLINE_0 
    LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)   ; RESET BUFFER PTR
    LDA  #0                  ; AND CURSOR COL
    LDB  #(LINECOUNT-1)      ; AND CURSOR ROW
    STA  VDP_CURS_COL        ; STORE NEW CURSOR ROW, AND COLUMN
    STB  VDP_CURS_ROW
    STX  VDP_CURS_BUFPTR     ; STORE UPDATED CURSOR BUF POINTER
    ORCC #$50               ; Disable IRQ and FIRQ interrupts
    JSR  VDP_DIRTY_SCREEN_BUF ; WE SCROLLED, SO DIRTY WHOLE TEXT BUFFER
    ANDCC #$AF              ; REENABLE INTERRUPTS
    PULSW    
    PULS X,B,A    
    RTS

NON_BOTTOM_NEWLINE_DONE:
    STA  VDP_CURS_COL       ; STORE NEW CURSOR ROW, AND COLUMN
    STB  VDP_CURS_ROW
    STX  VDP_CURS_BUFPTR    ; STORE UPDATED CURSOR BUF POINTER
    ORCC #$50               ; DISABLE IRQ AND FIRQ INTERRUPTS
    JSR  VDP_DIRTY_CHAR     ; INCLUDE NEW CHARS IN BUF DIRTY AREA
    ANDCC #$AF              ; REENABLE
    PULSW    
    PULS X,B,A    
    RTS

NORMAL_PUTC:                ; NORMAL(NON-CR) PUTC
    PSHS A,B,X
    PSHSW                   ; A : OUTPUT CHAR
    LDX  VDP_CURS_BUFPTR    ; X : STARTING BUF POINTER
    LDB  VDP_CURS_ROW       ; B : STARTING CURSOR ROW
    ORCC #$50               ; Disable IRQ and FIRQ interrupts
    JSR  VDP_DIRTY_CHAR
    ANDCC #$AF              ; REENABLE
    STA  ,X+                ; STORE CHARACTER AND ADVANCE CURSOR
    LDA  VDP_CURS_COL
    INCA                    ; ADVANCE CURS COL
    CMPA #LINELENGTH        ; HIT EOLN?  (TODO: HANDLE 40-COLUMN MODES)
    BLO  PUTC_DONE       
    LDA  #0                 ; EOLN. RESET COL AND
    INCB                    ; INC ROW
    CMPB #LINECOUNT     
    BLO  PUTC_DONE
    ; PASSED BOTTOM OF SCREEN, BLOCK COPY THE BUFFER 80 CHARS BACKWARDS
    ORCC #$50               ; Disable IRQ and FIRQ interrupts
    LDX  #VDP_TEXT2_BUFFER
    LDY  #(VDP_TEXT2_BUFFER+LINELENGTH)
    LDW  #(DISPLAYSIZE-LINELENGTH)
    TFM  Y+,X+
    ANDCC #$AF              ; REENABLE
    ; FILL THE LAST 80 CHARS OF BUFFER WITH CR'S
    LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)
    LDB  #13    
FILL_LASTLINE_1:
    STB  ,X+
    CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE) 
    BLO  FILL_LASTLINE_1 
    LDX  #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)   ; RESET BUFFER PTR
    LDA  #0                  ; AND CURSOR COL
    LDB  #(LINECOUNT-1)                 ; AND CURSOR ROW
    STA  VDP_CURS_COL
    STB  VDP_CURS_ROW
    STX  VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR POSITION
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    JSR  VDP_DIRTY_SCREEN_BUF
    ANDCC #$AF ; REENABLE
    PULSW
    PULS X,B,A    
    RTS
PUTC_DONE: 
    STA  VDP_CURS_COL
    STB  VDP_CURS_ROW
    STX  VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR POSITION
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
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
VDP_PREPARE_WRITE:                    ; SELECT VDP TEXT PAGE 0 OR 1 FOR WRITING
    ; calculate address in vdp of dirty region of text page to write
    ; 0   0   0   0   0   A16 A14 A14
    ; A7  A6  A5  A4  A3  A2  A1  A0  
    ; 0   1   A13 A12 A11 A10 A9  A8  
    ; VDP TEXT PAGE ADDRESS RANGE
    ; [0...2160) [0b00...Ob100001110000)

    ; GET (VDP_BUF_DIRTY_START-#VDP_TEXT2_BUFFER) AS A 16-BIT WORD
    LDW VDP_BUF_DIRTY_START
    SUBW #VDP_TEXT2_BUFFER

    ; 0   0   0   0   0   A16 A14 A14
    LDA #$00     
    STA VREG
    LDA #$8E
    STA VREG

    ; A7  A6  A5  A4  A3  A2  A1  A0  
    STF VREG

    ; 0   1   A13 A12 A11 A10 A9  A8  
    LDA #%00111111
    ANDR A,E 
    LDA #%01000000
    ORR A,E
    STE VREG
    RTS
; -----------------------------------------------------------------------------
VDP_WRITE_BUFFER:  ; COPY DIRTY REGION OF BUFFER TO CORRESPONDING REGION OF VDP TEXT PAGE
    BSR VDP_PREPARE_WRITE
    TIM #1,VDP_CURS_STYLE
    BEQ WR_CURS_INVIS       ; IF CURSOR IS INVISIBLE, DO NORMAL BUF COPY
    TIM #8,VDP_CURS_STYLE   ; IF CURSOR IS IN OFF-BLINK, DO NORMAL BUF COPY
    BEQ WR_CURS_INVIS
WR_CURS_VIS:  ; CURSOR IS VISIBLE, SO COPY IN ONE, TWO, OR THREE PARTS:
    LDX VDP_BUF_DIRTY_START  ; COPY FROM DIRTY START UP TO CURSOR
    CMPX VDP_CURS_BUFPTR   
    BEQ SKIP_PRECUR       ; UNLESS CURSOR IS AT BEGINNING OF DIRTY
BUFFER_WRITE2_LOOP:
    LDA ,X+
    STA VDAT
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX VDP_CURS_BUFPTR
    BNE BUFFER_WRITE2_LOOP
SKIP_PRECUR:
    TIM #2,VDP_CURS_STYLE       ; WRITE CURSOR CHARACTER TO VDP
    BEQ CURS_UNDERLINE
    LDA #$18                     ; SOLID BLOCK CURSOR
    BRA POKE_CURS
CURS_UNDERLINE:
    LDA #$5F                    ; UNDERLINE CURSOR
POKE_CURS:
    STA VDAT
    LDA ,X+                     ; INC BUFPTR
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX VDP_BUF_DIRTY_END ; IF CURSOR IS AT END OF DIRTY 
    BGE DONE_CURCOPY
BUFFER_WRITE3_LOOP:  ; COPY REMAINDER OF DIRTY BUF TO VDP
    LDA ,X+
    STA VDAT
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX VDP_BUF_DIRTY_END
    BNE BUFFER_WRITE3_LOOP
DONE_CURCOPY:
    JSR VDP_CLEAN_SCREEN_BUF ; SCREEN BUF IS NOW CLEAN
    RTS
WR_CURS_INVIS:  ; CURSOR INVISBLE, JUST COPY DIRTY TEXT BUF TO VDP
    LDX VDP_BUF_DIRTY_START
BUFFER_WRITE_LOOP:  ; JUST WRITE WHOLE CHARBUF TO VDP
    LDA ,X+
    STA VDAT
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    CMPX VDP_BUF_DIRTY_END ; the extra 80 is for the half-line at the end
    BNE BUFFER_WRITE_LOOP
    JSR VDP_CLEAN_SCREEN_BUF ; SCREEN BUF IS NOW CLEAN
    RTS   
; -----------------------------------------------------------------------------
; FIRQ  - can be called by the VDP for VBLANK, HBLANK, scanline, sprite, etc.
; -----------------------------------------------------------------------------
VDP_FIRQ:    
    PSHS A,B,X,Y,U
    PSHSW     ; PUSH W ALSO
    ; TODO: USE THE VDP TEXT BLINK FEATURE TO IMPLEMENT THE CURSOR- 
    ; RATHER THAN ALL THIS HACKY 6309 CODE WE ARE USING CURRENTLY.

    ; TODO: MAKE GBASIC CALL THIS THROUGH A RAM TRAMPOLINE SO THE USER
    ; CAN MAKE THEIR OWN FIRQ ISR IF THEY WANT

    ; ALSO TODO: MAKE THE VDP VBLANK STUFF IN HERE ONLY HAPPEN IF IT THE
    ; FIRQ WAS REALLY CAUSED BY A VBLANK AND NOT SOMETHING ELSE LIKE HBLANK.

    LDA #0    ; GET VDP STATUS REGISTER S#0 TO DETERMINE INTERRUPT SOURCE
    STA VREG  ; AND CLEAR THE INTERRUPT.
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
    BLT CURSOR_UPDATE_DONE  ; IF NOT TIME TO BLINK, DONE WITH CURSOR
    LDA #0
    STA VDP_CURS_BLINK_CT   ; RESET BLINK TIMER
    LDA #8
    EORA VDP_CURS_STYLE     ; TOGGLE BLINK STATE (BIT VDP_CURS_STYLE.3)
    STA VDP_CURS_STYLE
    LDX VDP_CURS_BUFPTR
    JSR VDP_DIRTY_CHAR      ; INCLUDE CURSOR CHAR POSITION AS DIRTY.
    LDW VDP_BUF_DIRTY_END   ; AND A FEW AFTER, TO CLEANUP BACKSPACES.
    INCW
    INCW
    INCW
    INCW
    INCW
    INCW
    STW VDP_BUF_DIRTY_END
CURSOR_UPDATE_DONE:
    LDW VDP_BUF_DIRTY_START 
    BEQ FIRQ_DONE           ; IF ANY TEXTBUF REGION IS DIRTY,
    JSR VDP_WRITE_BUFFER    ; COPY IT TO VDP.
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
