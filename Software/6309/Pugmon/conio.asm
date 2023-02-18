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
VDP_INIT        EXTERN
VDP_PUTC        EXTERN
UT_INIT         EXTERN
UT_GETC         EXTERN
UT_PUTC         EXTERN
VDP_MODE_TEXT2  EXTERN
VDP_SHOW_PUG    EXTERN
HEXBYTE         EXTERN
;------------------------------------------------------------------------------
con_init        EXPORT
con_register    EXPORT
con_service     EXPORT
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
ConBufPtr       rmw     1               ; pointer to current char of b.buf.
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
    rts
;------------------------------------------------------------------------------
; Send cursor and bufptr to top-left of screen, and do same on each device
;------------------------------------------------------------------------------
con_cur_home
    clr  ConCurCol          ; init cursor to (x,y) = (0,0)
    clr  ConCurRow
    ldx  #ConBufChars       ; init buf pointer to beg. of buf
    stx  ConBufPtr
    ; todo: call cur home fcn for each associated IO device
    rts
;------------------------------------------------------------------------------
; Get a char from input device to reg A, return $0 if none.
;------------------------------------------------------------------------------
con_getc
    ; call getc for each IO device
    jsr  UT_GETC
    rts
;------------------------------------------------------------------------------
; con_putc - char in Reg A is inserted or overwritten to buffer at current 
; cursor position. 
;
; As needed, update cursor pos, scroll chars, remove preceeding cr's.
;
; Finally, call device functions to sync them with the new console state
;------------------------------------------------------------------------------
con_putc    
    ; call putc fcn for each IO device
    jsr  VDP_PUTC
    jsr  UT_PUTC
    rts            
;------------------------------------------------------------------------------
; Associate an IO device with this console. Called by relevant device drivers 
; after successful init, with X pointing at a ConDriver structure. (defines.h)
;
; Registration involves adding the device to a list and then setting the 
; state of the device to reflect the current state of the backing buffer and
; cursor. After that, any changes to console state will be relayed to the
; device, and the device will be polled for user input by a reentrant conio
; service call in the pugmon main loop.
;------------------------------------------------------------------------------
con_register:
    rts
;------------------------------------------------------------------------------
; Periodically called my mainloop to handle any console housekeeping
;------------------------------------------------------------------------------
con_service:
    rts
;------------------------------------------------------------------------------
; Print to console the null-terminated string pointed to by Y
;
; todo: be more careful of side effects, so I dont have to push and pop so many
; registers as I am in this subroutine!!
;------------------------------------------------------------------------------
con_puts
    pshs x,y,a,b
psloop
    LDA  ,Y+
    BEQ  psdone     ; done when reach null terminator
    BSR  con_putc
    BRA  psloop     ; loop around for next char of string
psdone
    PULS x,y,a,b
    RTS
;------------------------------------------------------------------------------
; Print a CR+LF to console
;------------------------------------------------------------------------------
con_puteol  
    LDA  #CR        
    JSR  con_putc
    LDA  #LF
    JSR  con_putc
    RTS
;------------------------------------------------------------------------------
; Print Reg. A to console as a hex octet + space
;------------------------------------------------------------------------------
con_puthbyte 
    PSHS X          
    LDX  #ConLinBuf
    JSR  HEXBYTE
    LDA  #32
    STA  ,X+
    LDA  #0
    STA  ,X+
    LDY  #ConLinBuf
    JSR  con_puts
    PULS X
    RTS
;------------------------------------------------------------------------------
; Print Reg. D to console as two hex octets + space
;------------------------------------------------------------------------------
con_puthword 
    PSHS X,D       
    PSHS D
    LDX  #ConLinBuf
    JSR  HEXBYTE
    PULS D
    TFR  B,A
    JSR  HEXBYTE            
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
