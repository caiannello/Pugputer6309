
; -----------------------------------------------------------------------------
; V9958 VIDEO DISPLAY PROCESSOR stuff
; -----------------------------------------------------------------------------

; V9958 VDP addresses

VDAT     EQU $F400  ; Port 0: VRAM Data (R/W)
VREG     EQU $F401  ; Port 1: Status Reg (R), Register/setup (W), VRAM Addr (W)
VPAL     EQU $F402  ; Port 2: Palette Registers (W)
VIND     EQU $F403  ; Port 3: Register-indirect addressing (W)

; ANDCC #$AF          ENABLE IRQ,FIRQ 

; settings and constants

VDP_CURS_DEF_BLINKRATE equ 30    ; vblanks per cursor state toggle
VDP_CURS_DEF_STYLE     equ %111  ; see vdp_curs_style in globals for bit definitions

; 80-column text is bluish-white on dark blue..
BACKGROUND1       equ   $12     ; 0 R2 R1 R0 0 B2 B1 B0
BACKGROUND2       equ   $01     ; 0 0  0  0  0 G2 G1 G0
FOREGROUND1       equ   $57     ; 0 R2 R1 R0 0 B2 B1 B0
FOREGROUND2       equ   $05     ; 0 0  0  0  0 G2 G1 G0

DISPMODE          equ   DM_NTSC           ; DM_PAL or DM_NTSC
LINELENGTH        equ   80                ; TODO: HANDLE 40-COLUMN MODES

LINECOUNT         equ   26
DM_NTSC           equ   128 ; 0 for 24 line mode
DM_PAL            equ   130 ; 2 for 24 line mode

;LINECOUNT         equ   26
;DM_NTSC           equ   128
;DM_PAL            equ   130

DISPLAYSIZE       equ   LINELENGTH*LINECOUNT
CURSORDELAY2      equ   CURSORDELAY*2


VDP_REG2_PAGE0    equ   $3           ; Page 0 at 0x0
VDP_REG2_PAGE1    equ   $B           ; Page 1 at 0x2000

; 0   0   0   0   0   A16 A14 A14
VRAM_HIGH         equ   $0           ; VRAM A14-16 for any page

; A7  A6  A5  A4  A3  A2  A1  A0  
VRAM_LOW          equ   $0           ; VRAM A0-A7 for any page (base)

; 0   1   A13 A12 A11 A10 A9  A8  
VRAM_MID_PAGE0_R  equ   $0           ; VRAM A8-A13 for page 0 (Read)
VRAM_MID_PAGE0_W  equ   $40          ; VRAM A8-A13 for page 0 (Write)
VRAM_MID_PAGE1_R  equ   $20          ; VRAM A8-A13 for page 1 (Read)
VRAM_MID_PAGE1_W  equ   $60          ; VRAM A8-A13 for page 1 (Write)
; -----------------------------------------------------------------------------
__VDP_STARTUP_MESSAGE_BEGIN:  ; PUGBUTT GLYPHS AND BANNER TEXT, CR-DELIMITED
    FCB $01,$02,$04,$07,$0A,$00,$0F,$11,$14
    FCC "PUGBUTT INDUSTRIES, LLC."
    FCB $0D,$20,$03,$05,$17,$0B,$0E,$10,$12,$15
    FCC "6309 COMPUTER V0.1"
    FCB $0D,$20,$20,$06,$09,$0C,$20,$20,$13,$16
    FCC "COPYRIGHT 2022"
    FCB $0D
__VDP_STARTUP_MESSAGE_END:
; -----------------------------------------------------------------------------
    INCLUDE font.asm
; -----------------------------------------------------------------------------
VDP_INIT:  ; set TEXT 2 mode, page 0, load font into VDP, clear text page 0
    ; init globals
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
    RTS
; -----------------------------------------------------------------------------
; MARK ENTIRE TEXT BUF, INCLUDING UNUSED PARTIAL LAST LINE, AS NEEDING XFER TO VDP
VDP_DIRTY_WHOLE_SCREEN_BUF:
    LDX #VDP_TEXT2_BUFFER
    STX VDP_BUF_DIRTY_START
    LDX #(VDP_TEXT2_BUFFER+DISPLAYSIZE+80)
    STX VDP_BUF_DIRTY_END
    RTS
; -----------------------------------------------------------------------------
; MARK ALL 26 VISIBLE LINES OF TEXT BUF AS NEEDING XFER TO VDP
VDP_DIRTY_SCREEN_BUF: 
    LDX #VDP_TEXT2_BUFFER
    STX VDP_BUF_DIRTY_START
    LDX #(VDP_TEXT2_BUFFER+DISPLAYSIZE)
    STX VDP_BUF_DIRTY_END
    RTS    
; -----------------------------------------------------------------------------
; MARK NO CHARS OF SCREEN BUFFER DIRTY
VDP_CLEAN_SCREEN_BUF: 
    LDX #0
    STX VDP_BUF_DIRTY_START
    STX VDP_BUF_DIRTY_END
    RTS    
; -----------------------------------------------------------------------------
; TEXT BUF CHAR POINTED TO BY X WAS ALTERED. INIT OR ENLARGE DIRTY REGION
VDP_DIRTY_CHAR: 
    ; IF DIRTY STARTING POINTER IS ZERO, THERE IS CURRENTLY NO DIRTY REGION.
    LDW VDP_BUF_DIRTY_START
    BEQ REGION_INIT   ; SO WE HAVE TO MAKE DIRTY REGION TO ENCLOSE JUST THAT CHAR.
REGION_ENLARGE: ;  WE HAVE A PREEXISTING DIRTY REGION, ENLARGE IT TO ENCOMPASS DIRTY CHAR
    ; IF DIRTY ENDPTR IS ALREADY RIGHT OF DIRTY CHAR POS, NO CHANGE TO ENDPTR IS NEEDED.
    LDW VDP_BUF_DIRTY_END
    CMPR X,W  
    BHI SKIP_ENLARGE_END
    STX VDP_BUF_DIRTY_END 
    LDW VDP_BUF_DIRTY_END
    INCW
    STW VDP_BUF_DIRTY_END
SKIP_ENLARGE_END:
    LDW VDP_BUF_DIRTY_START
    CMPR X,W
    BLT SKIP_ENLARGE_START
    STX VDP_BUF_DIRTY_START 
SKIP_ENLARGE_START:
    RTS
REGION_INIT:
    STX VDP_BUF_DIRTY_START 
    LDW VDP_BUF_DIRTY_START
    INCW
    STW VDP_BUF_DIRTY_END
    RTS
; -----------------------------------------------------------------------------
VDP_LOAD_FONT:   ; load 6x8 font from ROM into VDP
    ; Set up to write VRAM at 0x1000
    ; 0x1000 equates to 00001000000000000, which is split across the writes as:
    ; Write 1: bits 16-14 = (00000)000  = 0
    ; Write 2: bits 7-0   = 00000000    = 0
    ; Write 3: bits 13-8  = (01)010000  = $50 ($40 is write-enable)
    LDA #$00  ; VRAM Base at 0
    STA VREG
    LDA #$8E  ; > register 14
    STA VREG
    LDA #$0   ; Set VRAM A0-A7
    STA VREG
    LDA #$50  ; Set VRAM A8-A13, and write enable
    STA VREG
    ; COPY BYTES FROM __FONT_BEGIN TO __FONT_END TO VDAT. SLOWLY.
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
    LDX #VDP_TEXT2_BUFFER   ; todo, handle 40-column modes
    STX VDP_CURS_BUFPTR     ; reset cursor to beginning of buffer
    LDB #0
    STB VDP_CURS_ROW
    STB VDP_CURS_COL    
    LDB #$0D
BUF_CLEAR_LOOP:
    STB ,X+
    ; the extra 80 is for the unused partial line at the end
    CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE+80) 
    BNE BUF_CLEAR_LOOP 
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    JSR VDP_DIRTY_WHOLE_SCREEN_BUF
    ANDCC #$AF ; REENABLE
    RTS
; -----------------------------------------------------------------------------
VDP_PUTC:       ; TAKE CHARACTER IN REG A, POKE INTO BUFFER AT CURRENT CURSOR,
                ; AND ADVANCE THE CURSOR. THIS SUB DOESNT 
                ; CARE ABOUT CURSOR MODE OR CONTROL CHARS (EXCEPT CR AND BACKSPACE) 
                ; AND INSTEAD SIMPLY PRINTS THE ASSOCIATED GLYPH. CR (ASCII CODE 
                ; $0D) IS A SPECIAL CASE:  IT GETS REPEATEDLY PRINTED (IT IS 
                ; NORMALLY BLANK) UNTIL CURSOR REACHES THE BEGINNING OF NEXT ROW. 
                ; BACKSPACE (ASCII $08) DOESNT PRINT A GLYPH AND INSTEAD MOVES
                ; THE CURSOR BACKWARDS ONE CHAR POSITION, TO PREVIOUS ROW IF
                ; NECESSARY.
                ; FOR A MORE SOPHISTICATED WAY TO PRINT CHARS WHICH RESPECTS
                ; INSERTION, ETC., SEE VDP_PUTCHAR, BELOW.
    PSHS A,B,X
    PSHSW
    LDX VDP_CURS_BUFPTR
    LDB VDP_CURS_ROW   
    CMPA #8             ; CHECK IF THEY'RE DOING A BACKSPACE
    BNE NON_BACKSPACE
PRINT_A_BACKSPACE:  ; DOING A BACKSPACE: DECREMENT CURSOR COL AND MAYBE ROW
    LDA VDP_CURS_COL
    DECA
    STA VDP_CURS_COL
    CMPA #-1
    BNE NO_PREVLINE
    LDA #79
    STA VDP_CURS_COL
    DECB
NO_PREVLINE:
    LDA ,-X
    STB VDP_CURS_ROW
    STX VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR POSITION
    PULSW        
    PULS X,B,A    
    RTS
NON_BACKSPACE: 
    CMPA #$0D           ; CHECK IF THEY ARE PRINTING A CR
    BNE NORMAL_PUTC     ; NON-CR CHARACTER
DO_NEWLINE:             ; CR CHAR, FILL ROW WITH IT 
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    JSR VDP_DIRTY_CHAR  ; INCLUDE STARTING CHAR IN DIRTY REGION
    ANDCC #$AF ; REENABLE
    LDA VDP_CURS_COL
    LDE #$0D
NEXTCR:
    STE ,X+             ; PUT CR IN BUFFER AT CURSOR POS
    INCA                ; ADVANCE CURSOR COLUMN
    CMPA #LINELENGTH            ; HIT EOLN?  (TODO: HANDLE 40-COLUMN MODES)
    BNE NEXTCR          ; HAVENT HIT END OF LINE YET, GO AGAIN
    LDA #0              ; HIT EOLN, RESET CURSOR COLUMN
    INCB                ; INCREMENT ROW
    CMPB #LINECOUNT            
    BNE NON_BOTTOM_NEWLINE_DONE
    ; PASSED BOTTOM OF SCREEN, BLOCK COPY THE BUFFER 80 CHARS BACKWARDS
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    LDX #VDP_TEXT2_BUFFER
    LDY #(VDP_TEXT2_BUFFER+LINELENGTH)
    LDW #(DISPLAYSIZE-LINELENGTH)
    TFM Y+,X+
    ANDCC #$AF ; REENABLE
    ; FILL THE LAST 80 CHARS OF BUFFER WITH CR'S
    LDX #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)
    LDB #$0D    
FILL_LASTLINE_0:
    STB ,X+
    CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE) 
    BNE FILL_LASTLINE_0 
    LDX #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)   ; RESET BUFFER PTR
    LDA #0                  ; AND CURSOR COL
    LDB #(LINECOUNT-1)                 ; AND CURSOR ROW
    STA VDP_CURS_COL      ; STORE NEW CURSOR ROW, AND COLUMN
    STB VDP_CURS_ROW
    STX VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR BUF POINTER
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    JSR VDP_DIRTY_SCREEN_BUF ; WE SCROLLED, SO DIRTY WHILE TEXT BUFFER
    ANDCC #$AF ; REENABLE
    PULSW    
    PULS X,B,A    
    RTS
NON_BOTTOM_NEWLINE_DONE:
    STA VDP_CURS_COL      ; STORE NEW CURSOR ROW, AND COLUMN
    STB VDP_CURS_ROW
    STX VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR BUF POINTER
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    JSR VDP_DIRTY_CHAR
    ANDCC #$AF ; REENABLE
    PULSW    
    PULS X,B,A    
    RTS
NORMAL_PUTC:           ; NORMAL(NON-CR) PUTC
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    JSR VDP_DIRTY_CHAR
    ANDCC #$AF ; REENABLE
    STA ,X+            ; STORE CHARACTER AND ADVANCE CURSOR
    LDA VDP_CURS_COL
    INCA                ; ADVANCE CURS COL
    CMPA #LINELENGTH            ; HIT EOLN?  (TODO: HANDLE 40-COLUMN MODES)
    BNE PUTC_DONE       
    LDA #0              ; EOLN. RESET COL AND
    INCB                ; INC ROW
    CMPB #LINECOUNT     
    BNE PUTC_DONE
    ; PASSED BOTTOM OF SCREEN, BLOCK COPY THE BUFFER 80 CHARS BACKWARDS
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    LDX #VDP_TEXT2_BUFFER
    LDY #(VDP_TEXT2_BUFFER+LINELENGTH)
    LDW #(DISPLAYSIZE-LINELENGTH)
    TFM Y+,X+
    ANDCC #$AF ; REENABLE
    ; FILL THE LAST 80 CHARS OF BUFFER WITH CR'S
    LDX #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)
    LDB #$0D    
FILL_LASTLINE_1:
    STB ,X+
    CMPX #(VDP_TEXT2_BUFFER+DISPLAYSIZE) 
    BNE FILL_LASTLINE_1 
    LDX #(VDP_TEXT2_BUFFER+DISPLAYSIZE-LINELENGTH)   ; RESET BUFFER PTR
    LDA #0                  ; AND CURSOR COL
    LDB #(LINECOUNT-1)                 ; AND CURSOR ROW
    STA VDP_CURS_COL
    STB VDP_CURS_ROW
    STX VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR POSITION
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    JSR VDP_DIRTY_SCREEN_BUF
    ANDCC #$AF ; REENABLE
    PULSW
    PULS X,B,A    
    RTS
PUTC_DONE: 
    STA VDP_CURS_COL
    STB VDP_CURS_ROW
    STX VDP_CURS_BUFPTR   ; STORE UPDATED CURSOR POSITION
    ORCC #$50 ;Disable IRQ and FIRQ interrupts
    JSR VDP_DIRTY_CHAR
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

OLDWAY:
    LDA #$00     ; 0   0   0   0   0   A16 A14 A14
    STA VREG
    LDA #$8E
    STA VREG
    LDA #$00     ; A7  A6  A5  A4  A3  A2  A1  A0  
    STA VREG
    ; 0   1   A13 A12 A11 A10 A9  A8  
    LDA #VRAM_MID_PAGE0_W  ; WRITE CHAR PAGE 0
    STA VREG
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
VDP_FIRQ:    ; Can be called by the VDP for VBLANK, HBLANK, scanline, sprite, etc.
    PSHS A,X
    PSHSW     ; PUSH W ALSO


    ; TODO: USE THE VDP TEXT BLINK FEATURE TO IMPLEMENT THE CURSOR- 
    ; RATHER THAN ALL THIS HACKY 6309 CODE WE ARE USING CURRENTLY.

    ; TODO: MAKE GBASIC CALL THIS THROUGH A RAM TRAMPOLINE SO THE USER
    ; CAN MAKE THEIR OWN FIRQ ISR IF THEY WANT

    ; ALSO TODO: MAKE THE VDP VBLANK STUFF IN HERE ONLY HAPPEN IF IT THE
    ; FIRQ WAS REALLY CAUSED BY A VBLANK AND NOT SOMETHING ELSE LIKE HBLANK.

    LDA #0    ; GET VDP STATUS REGISTER S#0 TO DETERMINE INTERRUPT SOURCE
    STA VREG  ; AND CLEAR THE INTERRUPT.
    ;NOP
    LDA #143
    STA VREG
    ;NOP
    LDA VREG
    ;NOP
    ;NOP
    ;NOP
    STA VDP_INTERRUPT_REASON

    ; CURSOR ENABLED, SO DO BLINK STUFF
    ; TODO: DONT SHOW CURSOR WHILE BASIC PRG 
    ; IS RUNNING UNLESS DOING AN INPUT 
    ; 
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
    PULS X,A
    RTI 
; -----------------------------------------------------------------------------
VDP_SHOW_STARTUP_MESSAGE:  ; COPY HELLO MSG TO SCREEN BUF -> VDP PAGE -> SCREEN
    ; TEXT2 SCREEN BUF SHOULD HAVE BEEN CLEARED BEFORE THIS, SO IT IS PROPERLY DIRTIED
    LDU #__VDP_STARTUP_MESSAGE_BEGIN
SCREEN_COPY_LOOP:
    LDA ,U+
    JSR VDP_PUTC
    CMPU #__VDP_STARTUP_MESSAGE_END
    BNE SCREEN_COPY_LOOP 
    JSR VDP_WRITE_BUFFER ; COPY BUFFER TO CURRRNT TEXT2 PAGE IN VDP
    ; Set text mode 1, NO INTERRUPTS, and turn display on
    LDA #%00000100  ; Write DG=0,IE2=0,IE1=0,M5=0,M4=0,M3=0
    STA VREG
    LDA #$80  ; To register 0
    STA VREG
    BSR VDP_ENABLE_TEXT2_DISPLAY_WITHOUT_VBLANK
    RTS
; -----------------------------------------------------------------------------
VDP_ENABLE_TEXT2_DISPLAY_WITH_VBLANK:
    LDA #%01110000  ; Write BL=1,IE0=1,M1=1,M2=0,SI=0,MAG=0
    STA VREG
    LDA #$81  ; To register 1
    STA VREG
    LDA #1
    STA VDP_VBLANK_ENABLED
    RTS
; -----------------------------------------------------------------------------
VDP_ENABLE_TEXT2_DISPLAY_WITHOUT_VBLANK:
    LDA #%01010000  ; Write BL=1,IE0=0,M1=1,M2=0,SI=0,MAG=0
    STA VREG
    LDA #$81  ; To register 1
    STA VREG
    LDA #0
    STA VDP_VBLANK_ENABLED
    RTS
; -----------------------------------------------------------------------------
; EOF
; -----------------------------------------------------------------------------


