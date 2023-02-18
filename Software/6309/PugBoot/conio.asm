;------------------------------------------------------------------------------
; Project: PUGMON
;    File: conio.asm
; Version: 0.0.1
;  Author: Craig Iannello
;
; Description:
;
; Console driver: maintains console screen backing buffer, text screen editor,
; cursor position and control, line input, scrolling, etc.  And controls 
; associated IO devices.
;
; Conio is able to use more than one IO device at the same time, e.g., using
; both video display and UART serial terminal, with mirrored results.
;
; Revelant devices, upon detection and initialization, will register with this
; module by passing the address of a consistent API structure.
;
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; CON_COLS, CON_ROWS, etc.
;------------------------------------------------------------------------------
UT_INIT         EXTERN
UT_GETC         EXTERN
UT_PUTC         EXTERN
UT_CLRSCR       EXTERN
UT_CUR_HOME     EXTERN
UT_CUR_XY       EXTERN
UT_CLEAR_EOL    EXTERN
S_HEXA          EXTERN
S_INTD          EXTERN
C_ISPRINT       EXTERN
;------------------------------------------------------------------------------
con_init        EXPORT
con_register    EXPORT
con_svc         EXPORT
con_clrhome     EXPORT
;con_keyswaiting EXPORT
;con_readline    EXPORT
;con_gotoxy      EXPORT
;con_home        EXPORT
con_getc        EXPORT
con_putc        EXPORT
con_puts        EXPORT
con_puthbyte    EXPORT
con_puthword    EXPORT
con_puteol      EXPORT
;------------------------------------------------------------------------------
    SECT bss
;------------------------------------------------------------------------------
ConBufChars     rmb     CON_BUF_SIZE    ; console backing buffer (defines.d)
ConCurCol       rmb     1               ; cursor current column
ConCurRow       rmb     1               ; cursor current row
ConBufPtr       rmw     1               ; ptr to current char of backing buf
ConLinBuf       rmb     255             ; line buffer
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
; Initialize console driver
;------------------------------------------------------------------------------
con_init
    bsr  con_clrhome
    rts
;------------------------------------------------------------------------------
; Clear text screen, and send cursor to top-left on all associated io devices
;------------------------------------------------------------------------------
con_clrhome
    pshs x,a
    bsr  con_buf_clr        ; clear backing buffer
    bsr  con_cur_home       ; send cursor and bufptr to home
    puls a,x    
    rts
;------------------------------------------------------------------------------
; Fill console backing buffer with CR's, call each dev's clearscreen fcn
;------------------------------------------------------------------------------
con_buf_clr
    lda  #CR
    ldx  #ConBufChars
ci_cbuf
    sta  ,x+
    cmpx #(ConBufChars+CON_BUF_SIZE)
    blo  ci_cbuf
    ; todo: call screen clear fcn for each associated IO device
    ; todo: use device driver struct for future modularity
    jsr  UT_CLRSCR

    rts
;------------------------------------------------------------------------------
; Send cursor and bufptr to top-left of screen, and do same on each device
;------------------------------------------------------------------------------
con_cur_home
    clr  ConCurCol          ; init cursor to (x,y) = (0,0)
    clr  ConCurRow
    ldx  #ConBufChars       ; init buf pointer to beg. of buf
    stx  ConBufPtr
    ; todo: use device driver struct for future modularity
    ; todo: call cur home fcn for each associated IO device
    jsr  UT_CUR_HOME

    rts
;------------------------------------------------------------------------------
con_clear_eol
    jsr  UT_CLEAR_EOL
    rts
;------------------------------------------------------------------------------
; Enforce our notion of where the cursor should be.
;------------------------------------------------------------------------------
con_place_cursor
    lde  ConCurRow
    ince
    ldf  ConCurCol
    incf
    jsr  UT_CUR_XY          ; Send cursor to row E and column F
    rts
;------------------------------------------------------------------------------
; Get a char from input device to reg A, return $0 if none.
;------------------------------------------------------------------------------
con_getc
    ; todo: call putc fcn for only registered IO devices
    jsr  UT_GETC
    rts
;------------------------------------------------------------------------------
; advance cursor right, with wraparound and possibility of scrolling.
; update buffer pointer
;------------------------------------------------------------------------------
con_cur_rt
    pshs a,x
    lda  ConCurCol
    cmpa #(CON_COLS-1)
    beq  crt_rtedge
    inca                    ; cursor is not at right edge of screen,
    sta  ConCurCol          ; increment cursor column,
    ldx  ConBufPtr          ; increment buffer pointer,
    leax 1,x
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it    
    puls a,x                ; all done.
    rts
crt_rtedge                  ; Cursor is in rightmost column.
    lda  #0
    sta  ConCurCol          ; Reset col to leftmost.
    lda  ConCurRow
    cmpa #(CON_ROWS-1)
    bge  atbot    
    inca                    ; Cur at right but not at bottom, 
    sta  ConCurRow          ; increment row,
    ldx  ConBufPtr          ; increment buffer pointer,
    leax 1,x
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it    
    puls a,x                ; all done.
    rts
atbot        
    lda  #(CON_ROWS-1)      ; cur at bottom right corner, 
    sta  ConCurRow          ; go to bot left.
    ldx  #(CON_SCREEN_SIZE-CON_COLS+ConBufChars)
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it
    puls a,x
    rts
;------------------------------------------------------------------------------
; called after a printable char has been sent. In most cases, just need to inc
; the buf ptr and cursor column value and not force any cursor placement, but
; in some cases the terminal cursor will get moved manually.
;------------------------------------------------------------------------------
con_cur_maybe_rt
    pshs a,x
    lda  ConCurCol
    cmpa #(CON_COLS-1)
    beq  crt_mrtedge
    inca                    ; cursor is not at right edge of screen,
    sta  ConCurCol          ; increment cursor column,
    ldx  ConBufPtr          ; increment buffer pointer,
    leax 1,x
    stx  ConBufPtr
    puls a,x                ; all done.
    rts
crt_mrtedge                 ; Cursor is in rightmost column.
    lda  #0
    sta  ConCurCol          ; Reset col to leftmost.
    lda  ConCurRow
    cmpa #(CON_ROWS-1)
    bge  matbot    
    inca                    ; Cur at right but not at bottom, 
    sta  ConCurRow          ; increment row,
    ldx  ConBufPtr          ; increment buffer pointer,
    leax 1,x
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it    
    puls a,x                ; all done.
    rts
matbot        
    lda  #(CON_ROWS-1)      ; cur at bottom right corner, 
    sta  ConCurRow          ; go to bot left.
    ldx  #(CON_SCREEN_SIZE-CON_COLS+ConBufChars)
    stx  ConBufPtr
    ; todo: maybe scroll up, inject CR/lf in terminal
    jsr  con_place_cursor   ; make cursor be where we want it
    puls a,x
    rts
;------------------------------------------------------------------------------
; move cursor left, with wraparound, update buffer pointer
; todo: possibility of scrolling if we have a scrollback buffer or editing a
; text file.
;------------------------------------------------------------------------------
con_cur_lt
    pshs a,x
    lda  ConCurCol
    beq  crt_ltedge
    deca                    ; cursor is not at left edge of screen,
    sta  ConCurCol          ; decrement cursor column,
    ldx  ConBufPtr          ; decrement buffer pointer,
    leax -1,x
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it    
    puls a,x                ; all done.
    rts
crt_ltedge                  ; Cursor is in leftmost column.
    lda  ConCurRow
    beq  attop    
    deca                    ; Cur at left but not at top, 
    sta  ConCurRow          ; decrement row,
    lda  #(CON_COLS-1)
    sta  ConCurCol          ; Reset col to rightmost.
    ldx  ConBufPtr          ; decrement buffer pointer,
    leax -1,x
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it    
    puls a,x                ; all done.
    rts
attop        
    lda  #0                 ; cur at top left corner, 
    sta  ConCurRow          ; stay at top-left.
    sta  ConCurCol
    ldx  #ConBufChars       ; beginning of console buffer
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it
    puls a,x
    rts
;------------------------------------------------------------------------------
; move cursor up, update buffer pointer
; todo: possibility of scrolling if we have a scrollback buffer or editing a
; text file.
;------------------------------------------------------------------------------
con_cur_up
    pshs a,x
    lda  ConCurRow
    beq  crt_topedge
    deca                    ; cursor is not at top edge of screen,
    sta  ConCurRow          ; decrement cursor row,
    ldx  ConBufPtr          ; decrement buffer pointer,
    leax (-CON_COLS),x
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it    
    puls a,x                ; all done.
    rts
crt_topedge                 ; Cursor is on top row
    jsr  con_place_cursor   ; make cursor be where we want it
    puls a,x
    rts
;------------------------------------------------------------------------------
; move cursor down, update buffer pointer, possibility of scrolling
;------------------------------------------------------------------------------
con_cur_dn
    pshs a,x
    lda  ConCurRow
    cmpa #(CON_ROWS-1)
    bge  crt_botedge
    inca                    ; cursor is not at bottom edge of screen,
    sta  ConCurRow          ; increment cursor row,
    ldx  ConBufPtr          ; increment buffer pointer,
    leax CON_COLS,x
    stx  ConBufPtr
    jsr  con_place_cursor   ; make cursor be where we want it    
    puls a,x                ; all done.
    rts
crt_botedge                 ; Cursor is on bottom row
    jsr  con_place_cursor   ; make cursor be where we want it
    puls a,x
    rts
;------------------------------------------------------------------------------
; In the console backing buffer, put a CR at current cursor position, and then
; put spaces until end of line. On terminal display, echo spaces to 
; end-of-line, followed by a CR and LF.
; 
; Set cursor and bufptr to first column of next row (or stay on last row 
; if already at the bottom) 
;
; Enforce final onscreen cursor placement, because all terminal emulators
; handle edge cases like this a bit differently, and I want to have
; consistent behavior.
;------------------------------------------------------------------------------
con_cur_cr
    pshs a,b,x,y
    pshsw
    jsr  con_clear_eol      ; clear terminal from cursor to end of line
    lda  #CR                ; echo CR to terminal
    jsr  con_putc_q
    ldb  #CR                ; store a CR in backbuffer, initially.
    lde  ConCurCol
    ldx  ConBufPtr
crloop
    cmpe #CON_COLS
    bge  donecrs            ; until reach end-of-line:
    stb  ,x+                ; store b in buffer at x,
    ince                    ; increment col in e,
    ldb  #32                ; switch to putting spaces in backing buffer
    bra  crloop

donecrs
    stx  ConBufPtr          ; store updated buf ptr
    lda  #0
    sta  ConCurCol          ; set cursor to leftmost col
    lda  ConCurRow
    cmpa #(CON_ROWS-1)
    bge  cr_at_bottom
    inca                    ; cr on non-bottom row:
    sta  ConCurRow          ; increment row, and done.
    jsr  con_place_cursor   ; make cursor be where we want it
    pulsw
    puls a,b,x,y
    rts    
cr_at_bottom                ; cr on bottom row
    lda  #(CON_ROWS-1)      ; move curs. and bufptr to bot-left.
    sta  ConCurRow
    ldx  #((CON_COLS*(CON_ROWS-1))+ConBufChars)
    stx  ConBufPtr    
    lda  #LF                ; echo LF to terminal
    jsr  con_putc_q
    jsr  con_place_cursor   ; make cursor be where we want it
    ; scroll backing buffer up one line
    LDX  #(ConBufChars+CON_COLS) 
    LDY  #(ConBufChars) 
    LDW  #(CON_SCREEN_SIZE-CON_COLS)
    TFM  X+,Y+
    pulsw    
    puls a,b,x,y
    rts
;------------------------------------------------------------------------------
; put char from A into backing buffer at current buffer pos. Does not affect
; cursor pos or buf pointer pos.
;------------------------------------------------------------------------------
con_putc_bb
    pshs a,x
    ldx  ConBufPtr
    sta  ,X
    puls a,x
    rts
;------------------------------------------------------------------------------
; outputs a char to console without affecting cursor pos or backing buffer
;------------------------------------------------------------------------------
con_putc_q
    ; todo: call putc fcn for only registered IO devices
    jsr  UT_PUTC
    rts
;------------------------------------------------------------------------------
; outputs char to console, updates cursor pos and backing buffer
;------------------------------------------------------------------------------
con_putc
    jsr  C_ISPRINT
    bcc  pc_nonprint
    jsr  con_putc_q         ; print printable to console
    jsr  con_putc_bb        ; update backing buffer
    jsr  con_cur_maybe_rt   ; advance cursor
    rts
pc_nonprint                 ; beginning of nonprintables, special chars
    cmpa #$08
    bne  pc_notbs                            
    jsr  con_putc_q         ; backspace - echo to console
    jsr  con_cur_lt         ; move cursor left
    rts
pc_notbs                    
    cmpa #CR
    bne  pc_notcr                            
    jsr  con_cur_cr         ; carriage return
    rts
pc_notcr                    ; simple nonprintable
    rts
;------------------------------------------------------------------------------
; Associate an IO device with this console. Called by relevant device drivers 
; after successful init, with X pointing at a ConDriver structure. (defines.h)
;
; Registration involves adding the device to a list and then setting the 
; state of the device to reflect the current state of the backing buffer and
; cursor. After that, any changes to console state will be relayed to the
; device, and the device will be polled for user input by a reentrant conio
; svc call in the pugmon main loop.
;------------------------------------------------------------------------------
con_register
    rts
;------------------------------------------------------------------------------
; For debugging console buffer. Clear terminal screem, send cursor to top left,
; the coppy console buffer to uart, replacing CR characters with spaces.
; After all characters sent, return cursor to its previous location.
;------------------------------------------------------------------------------
con_redraw
    ; terminal cursor home
    jsr  UT_CUR_HOME
    ldx  #ConBufChars
drloop
    lda  ,x+
    cmpa #CR
    bne  drnotcr
    lda  #$FF
drnotcr
    jsr  con_putc_q
    cmpx #(ConBufChars+CON_SCREEN_SIZE)
    blo  drloop
    jsr  con_place_cursor
    rts
;------------------------------------------------------------------------------
; Periodically called my mainloop to handle any console housekeeping.
;
; First, checks if any keypresses happened, updates console backing buffer as
; needed, and if enter was pressed, calls any registered callbacks to report 
; the line text that was entered.
;
; Notes regarding misc keypresses (from Tera Term)
; Looks like there's a long legacy of bolt-ons to consider:
;
; backspace : 08 
;     enter : 0D
;    escape : 1B (with no subsequent char within a short time)
;    CTRL-A : 01
;       ...  
;    CTRL-K : 0B
;    CTRL-L : 0C
;       ...  
;    CTRL-Z : 1A
;    CTRL-1 : ? (? - No code received by UART)
;    CTRL-2 : ?
;    CTRL-3 : 1B
;    CTRL-4 : 1C
;    CTRL-5 : 1D
;    CTRL-6 : 1E
;    CTRL-7 : 1F
;    CTRL-8 : 7F
;    CTRL-9 : ?
;    CTRL-0 : ?
;
; test int-to-string:
;
; LDD  #-1250
; LDX  #ConLinBuf
; JSR  S_INTD
; LDY  #ConLinBuf
; JSR  con_puts
; JSR  con_puteol
;------------------------------------------------------------------------------
;con_svc
;    JSR  con_getc   ; Check for keypress,
;    BEQ  cs_done    ; end if none.
;gotchar             ; received a character from keyboard/uart:
;    CMPA #CR        ; cr received
;    BNE  notcr
;    JSR  con_putc_q
;    LDA  #LF
;    JSR  con_putc_q
;    BRA  cs_done    ; done with cr.
;notcr
;    CMPA #$0C       ; ctrl-l - clear screen and cursor to top-left
;    BNE  notcls
;    JSR  con_clrhome
;    BRA  cs_done
;notcls
;    JSR  con_putc_q
;    BRA  cs_done
;cs_done
;    RTS


con_svc
    JSR  con_getc   ; Check for keypress,
    BEQ  cs_done    ; end if none.
gotchar             ; received a character from keyboard/uart:
    CMPA #ESCAPE    ; escape received
    BNE  notesc
    JSR  con_esc    ; This might be the start of an ANSI code sequence.
    BRA  cs_done    ; done with esc.
notesc
    CMPA #$0C       ; ctrl-l - clear screen and cursor to top-left
    BNE  notcls
    JSR  con_clrhome
    BRA  cs_done
notcls
    CMPA #$1A       ; ctrl-z - copy console buffer to uart for debug
    BNE  notredraw
    JSR  con_redraw
    BRA  cs_done
notredraw
    JSR  con_putc
    BRA  cs_done
cs_done
    RTS
;------------------------------------------------------------------------------
; When an escape character comes in from the keyboard, it may just be because
; the user pressed the escape key, or it may be the beginning of an ANSI escape
; sequence. For example, the cursor-up key generates this sequence: <ESC>[A . 
;
; When the console service first receives an escape key, it calls this 
; subroutine to handle it. The escape char is put into a small buffer, and a
; countdown timer is started. If the timer elapses before any more chars come
; in, the result is considered to be just a press of the escape key.
;
; If characters arrive during the countdown, they are appended to the buffer. 
; This continues until either the timer elapses or a complete sequence is
; recognized. Some sequences are acted upon by the console driver, and others
; may be ignored or passed along to a user-defined handler. 
;
; Because a minimally-configured Pugputer has no dedicated timer hardware,
; we instead count iterations of this function's wait loop. Every N times
; through the loop, the countdown is decremented. These values are chosen to
; give a timeout duration of roughly 0.25 seconds.
;
; Some ANSI codes for cursor and function keys
;
;        up : 1B 5B 41 
;      down : 1B 5B 42 
;      left : 1B 5B 44 
;     right : 1B 5B 43
;        F1 : 1B 5B 31 31 7E 
;        F2 : 1B 5B 31 32 7E
;        F3 : 1B 5B 31 33 7E
;        F4 : 1B 5B 31 34 7E
;        F5 : 1B 5B 31 35 7E  <-- note discontinuities
;        F6 : 1B 5B 31 37 7E  <--
;        F7 : 1B 5B 31 38 7E
;        F8 : 1B 5B 31 39 7E  <--
;        F9 : 1B 5B 32 30 7E
;       F10 : 1B 5B 32 31 7E
;       F11 : 1B 5B 32 33 7E
;       F12 : 1B 5B 32 34 7E
;------------------------------------------------------------------------------
con_esc
    PSHS D,X,Y,U
    LDX  #0
    LDY  #ESC_CTDN          ; setup timeout countdown
    LDU  #ConLinBuf         ; and buffer pointer.
    STA  ,U+                ; store escape char in buffer.
esc_loop
    JSR  con_getc           ; check for incoming char.
    LBNE esc_gotchar
    LEAX 1,X                ; no key was pressed. Increment x, and
    CMPX #ESC_N             ; compare x to N.
    BLO  esc_loop           ; if x < N: keep looping.
    LDX  #0                 ; if x = N: reset x, and
    LEAY -1,Y               ; decrement countdown.
    BGT  esc_loop           ; if countdown > 0, keep looping.

esc_timeout                 ; timeout elapsed:
    TFR  U,D
    SUBD #ConLinBuf         ; get code length in A:B
    CMPB #1
    BGT  twoormore
    ; have just a single escape character.
    ; return 27 in A
    JSR  esc_done

esc_gotchar
    STA  ,U+                ; store next char in buffer
    JMP  esc_loop           ; todo: check for complete code here

twoormore
    ; check if we have an initial <esc>[
    LDA  ConLinBuf+1
    CMPA #'[
    LBNE esc_done  ; not handling code if it doesnt have the [
    CMPB #2
    BGT  threeormore
    ; have a two byte code.
    JMP  esc_echo

threeormore
    CMPB #3
    BGT  fourormore
    ; have a three-byte code. get last byte in A.
    LDA  ConLinBuf+2 

    CMPA #$41
    BNE  notup    
    jsr  con_cur_up         ; cursor up
    JMP  esc_done    
notup
    CMPA #$42
    BNE  notdown    
    jsr  con_cur_dn         ; cursor down
    JMP  esc_done
notdown
    CMPA #$44
    BNE  notleft
    jsr  con_cur_lt         ; cursor left
    JMP  esc_done
notleft
    jsr  con_cur_rt         ; cursor right
    JMP  esc_done

fourormore
    CMPB #4
    BGT  fiveormore
    ; have a four-byte code
    JMP  esc_echo

fiveormore
    CMPB #5
    BGT  esc_echo
    ; have a five-byte code
    JMP  esc_echo

esc_echo
    LDA  #0                 ; add a null terminator to the stored code
    STA  ,U+
    LDY  #ConLinBuf         ; echo the code to console out
    JSR  con_puts_q         ; without affecting backing buffer or cursor pos
    PULS D,X,Y,U            ; todo: maybe pass unhandled code to user func
    RTS                     ; sub done due to timeout.

esc_done                    ; done because got a full code
    PULS D,X,Y,U
    RTS
;------------------------------------------------------------------------------
; Print to console the null-terminated string pointed to by Y
;------------------------------------------------------------------------------
con_puts
    pshs x,y,a,b
psloop
    LDA  ,Y+
    BEQ  psdone     ; done when reach null terminator
    LBSR con_putc
    BRA  psloop     ; loop around for next char of string
psdone
    PULS x,y,a,b
    RTS
;------------------------------------------------------------------------------
; Print to console the null-terminated string pointed to by Y
; Does not affect cursor position or console backing buffer
;------------------------------------------------------------------------------
con_puts_q
    pshs x,y,a,b
qpsloop
    LDA  ,Y+
    BEQ  qpsdone    ; done when reach null terminator
    LBSR con_putc_q
    BRA  qpsloop    ; loop around for next char of string
qpsdone
    PULS x,y,a,b
    RTS
;------------------------------------------------------------------------------
; Print a CR+LF to console
;------------------------------------------------------------------------------
con_puteol  
    LDA  #CR
    JSR  con_putc
    LDA  #LF
    JSR  con_putc_q
    RTS
;------------------------------------------------------------------------------
; Print Reg. A to console as a hex octet + space
;------------------------------------------------------------------------------
con_puthbyte 
    PSHS X,A,B
    LDX  #ConLinBuf
    JSR  S_HEXA
    LDA  #32
    STA  ,X+
    LDA  #0
    STA  ,X+
    LDY  #ConLinBuf
    JSR  con_puts
    PULS X,A,B
    RTS
;------------------------------------------------------------------------------
; Print Reg. D to console as two hex octets + space
;------------------------------------------------------------------------------
con_puthword 
    PSHS X,D
    PSHS D
    LDX  #ConLinBuf
    JSR  S_HEXA
    PULS D
    TFR  B,A
    JSR  S_HEXA
    LDA  #32
    STA  ,X+
    LDA  #0
    STA  ,X+
    LDY  #ConLinBuf
    JSR  con_puts
    PULS X,D
    RTS
;------------------------------------------------------------------------------        
    ENDSECT
;------------------------------------------------------------------------------
; End of conio.asm
;------------------------------------------------------------------------------
