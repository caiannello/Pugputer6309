;------------------------------------------------------------------------------
; Project: PUGMON
;    File: serio.asm
; Version: 0.0.1
;  Author: Craig Iannello
;
; Description:
;
; This file implements a buffered, interrupt-driven serial port based on
; a Rockwell R65C51P2 UART. This, along with the video display, (vidio.asm), 
; comprise the two methods of interacting with pugmon. 
;
;------------------------------------------------------------------------------
UT_INIT     EXPORT
UT_GETC     EXPORT
UT_PUTC     EXPORT
UT_CLRSCR   EXPORT
UT_CUR_HOME EXPORT
UT_CUR_XY   EXPORT
UT_CLEAR_EOL EXPORT
;------------------------------------------------------------------------------
JT_IRQ      EXTERN          ; RAM interrupt jump table, IRQ vector
V_CBRK      EXTERN
S_INTD      EXTERN
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; global settings and definitions
;------------------------------------------------------------------------------
    SECT bss
;------------------------------------------------------------------------------
SRXBUF      RMB  SBUFSZ     ; SERIAL INPUT BUFFER
ESRXBUF                     ; END OF BUF
SRXHEAD     RMB  2          ; RING BUFFER HEAD - PTR TO OLDEST CHAR 
SRXTAIL     RMB  2          ; PTR TO NEWEST CHAR
SRXCNT      RMB  1          ; NUM CHARS IN RX BUF
STXBUF      RMB  SBUFSZ     ; SERIAL OUTPUT BUFFER
ESTXBUF                     ; END BUF
STXHEAD     RMB  2          ; RING BUFFER HEAD - PTR TO OLDEST CHAR
STXTAIL     RMB  2          ; PTR TO NEWEST CHAR
STXCNT      RMB  1          ; NUM CHARS IN TX BUF
STXIE       RMB  1          ; 0 = TRANSMITTER IDLE, 1 = TRANSMITTING
SNEXTISR    RMB  2          ; ADDRESS OF NEXT IRQ ISR SO UART ISR CAN DELEGATE
TSTA        RMB  1          ; TEMP STORAGE OF UART STATUS
TMP_STR     RMB  16         ; USED WHEN MAKING/PARSING ANSI CODES
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
UT_INIT     CLR  STXCNT     ; INITIALIZE SERIAL VARS AND UART -----------------        
            CLR  SRXCNT     ; ZERO THE TX AND RX BYTE COUNTS
            CLR  STXIE      ; NOTE THAT TX IRQ IS INITIALLY DISABLED
            LDX  #STXBUF    ; INIT TX BUF HEAD AND TAIL
            STX  STXHEAD
            STX  STXTAIL
            LDX  #SRXBUF    ; INIT RX BUF HEAD AND TAIL
            STX  SRXHEAD
            STX  SRXTAIL
            LDX  JT_IRQ+1   ; PRESERVE DEFAULT IRQ ISR ADDRESS,
            STX  SNEXTISR   ; FOR USE WHEN A NON-UART IRQ HAPPENS.
            LDX  #UT_ISR    ; GET ADDRESS OF UART IRQ ISR,
            STX  JT_IRQ+1   ; AND PUT IT IN THE IRQ JUMP TABLE.                            
            LDA  #SUARTCTL  ; Initialize UART baud, parity, etc. (defines.d)
            STA  UT_CTL
            LDA  #SUARTCMD
            STA  UT_CMD
            RTS             ; SERIAL INIT DONE
;------------------------------------------------------------------------------
UT_ISR      LDA  UT_STA     ; UART INTERRUPT HANDLER --------------------------
            STA  TSTA       ; GET UART STATUS
            TIM  #128,TSTA  ; IF BIT 7 = 0: THE IRQ WASN'T CAUSED BY THE UART.
            BEQ  NOT_UART
CHK_RX      TIM  #8,TSTA    ; IF BIT 3 = 0: WE HAVENT RECEIVED A BYTE,
            BEQ  CHK_TX     ; SO SKIP RX STUFF. ELSE,
HANDL_RX    LDA  UT_DAT     ; GET RX BYTE FROM UART
            CMPA #03        ; IF CONTROL-C, JUMP TO THE CBREAK HANDLER.
            BNE  NOTBREAK
            JMP  V_CBRK
NOTBREAK    LDB  SRXCNT     ; CHECK IF RX BUFFER HAS ROOM.
            CMPB #(SBUFSZ-1)
            BGE  CHK_TX     ; BUF FULL, TRASH THE BYTE. TODO: SET ERR BIT
            LDX  SRXHEAD    ; GET HEAD POINTER,
            STA  ,X+        ; STORE BYTE THERE, INCREMENT HEAD 
            CMPX #ESRXBUF   ; CHECK IF HEAD WRAPPED AROUND.
            BLO  RX_DONE
            LDX  #SRXBUF    ; RESET HEAD PTR TO BEGINNING OF RX BUFFER.
RX_DONE     STX  SRXHEAD    ; STORE UPDATED RX HEAD
            INC  SRXCNT     ; INCREMENT RX BYTE COUNT
CHK_TX      TIM  #16,TSTA   ; IF BIT 4 = 0: WE HAVE A TX STILL PENDING,
            BEQ  IQ_DONE    ; SO WE'RE DONE. ELSE,
HANDL_TX    LDA  STXCNT     ; BYTE TRANSMITTED. CHECK IF MORE TO SEND.
            BEQ  TX_END     ; NO MORE TO SEND, LEAVE TRANSMT MODE, ELSE,
            LDX  STXTAIL
            LDA  ,X+        ; GET NEXT BYTE TO SEND, ADVANCE TAIL.
            PSHS A          ; STOR TX BYTE FOR A BIT 
            CMPX #ESTXBUF   ; CHECK IF TAIL NEEDS TO WRAP AROUND.
            BLO  TX_DONE
            LDX  #STXBUF    ; RESET TX TAIL TO BEGINNING OF TX BUF
TX_DONE     STX  STXTAIL    ; STORE UPDATED TX TAIL
            PULS A
            STA  UT_DAT     ; SEND NEXT TX BYTE TO UART,
            DEC  STXCNT     ; DECREMENT TX BYTE COUNT
            RTI             ; DONE HANDLING UART IRQ.
TX_END:     LDA  #$09       ; DISABLE UART TX INTERRUPT REQUESTS.
            STA  UT_CMD
            CLR  STXIE      ; NOTE THAT WE ARE NO LONGER TRANSMITTING.
            LDX  #STXBUF    ; RESET TX BUF PTRS BECAUSE THERE'S SOME KIND OF 
            STX  STXHEAD    ; SYNC ISSUE I HAVENT YET TRACKED DOWN, WHERE
            STX  STXTAIL    ; TXCNT IS ZERO, BUT TXHEAD DOESN'T EQUAL TXTAIL!
IQ_DONE     RTI             ; DONE HANDLING UART INTERRUPT.
NOT_UART    JMP  [SNEXTISR] ; IRQ WASNT CAUSED BY UART, CALL NEXT IRQ ISR.
;------------------------------------------------------------------------------
UT_GETC     LDA  SRXCNT     ; GET AN RX CHAR, IF ANY, ELSE NULL ---------------
            BEQ  NOCHAR
            ORCC #$10       ; DISABLE IRQ INTERRUPTS
            LDX  SRXTAIL
            LDA  ,X+        ; GET CHAR AT RX TAIL, ADVANCE TAIL. 
            CMPX #ESRXBUF   ; CHECK IF TAIL NEEDS TO WRAP AROUND.
            BLO  GETC_DONE  ; NOPE.
            LDX  #SRXBUF    ; RESET TAIL TO BEGINNING OF RX BUF
GETC_DONE   STX  SRXTAIL    ; STORE NEW TAIL.
            DEC  SRXCNT     ; DECREMENT RX BYTE COUNT
            ANDCC #$EF      ; ENABLE IRQ INTERRUPTS
            TSTA
            RTS
NOCHAR      CLRA            ; NULL IF NONE          
            RTS     
;------------------------------------------------------------------------------
;UT_WAITC    BSR  UT_GETC    ; WAIT FOR A RX CHAR FROM UART AND RETURN IT ------
;            BEQ  UT_WAITC
;            RTS
;------------------------------------------------------------------------------
; <ESC>[0K - clear terminal line from cursor to end-of-line
;------------------------------------------------------------------------------
UT_CLEAR_EOL
            PSHS A
            LDA  #$1B
            BSR  UT_PUTC
            LDA  #'[
            BSR  UT_PUTC
            LDA  #'0
            BSR  UT_PUTC
            LDA  #'K
            BSR  UT_PUTC
            PULS A
            RTS
;------------------------------------------------------------------------------
UT_PUTC     PSHS A,B,X
BUFWAIT     LDB  STXCNT     ; CHECK TX BUF BYTE COUNT
            CMPB #(SBUFSZ-1)
            BGE  BUFWAIT    ; LOOP UNTIL THERE'S ROOM IN TX BUF.
            ORCC #$10       ; PAUSE IRQ INTERRUPTS
            LDX  STXHEAD    ; GET HEAD POINTER,
            STA  ,X+        ; STORE BYTE THERE, ADVANCE HEAD 
            CMPX #ESTXBUF   ; CHECK IF HEAD WRAPPED AROUND.
            BLO  PC_NEXT    ; NOPE.
            LDX  #STXBUF    ; RESET HEAD PTR TO BEGINNING OF TX BUFFER.
PC_NEXT     STX  STXHEAD    ; STORE UPDATED TX HEAD PTR
            INC  STXCNT     ; INCREMENT TX BYTE COUNT
            LDA  STXIE      ; CHECK IF IN TRANSMIT MODE
            BNE  PC_DONE    ; IF TX INTERRUPT ALREADY ENABLED, WE'RE DONE.
            LDX  STXTAIL    ; NEED TO INITIATE TRANSMISSION,
            LDA  ,X+        ; GET NEXT BYTE TO SEND, ADVANCE TAIL.
            PSHS A          ; SAVE TX BYTE FOR A BIT
            CMPX #ESTXBUF   ; CHECK IF TAIL NEEDS TO WRAP AROUND.
            BLO  TX_ENAB    ; NOPE.
            LDX  #STXBUF    ; RESET TX TAIL TO BEGINNING OF TX BUFFER.
TX_ENAB     STX  STXTAIL    ; STORE UPDATED TX TAIL PTR
            DEC  STXCNT     ; DECREMENT TX BYTE COUNT 
            LDA  #$05       ; ENABLE UART TX INTERRUPT
            STA  UT_CMD
            PULS A
            STA  UT_DAT     ; SEND BYTE TO UART.
            LDA  #1
            STA  STXIE      ; NOTE WE ARE TRANSMITTING
PC_DONE     ANDCC #$EF      ; RESUME IRQ INTERRUPTS
            PULS A,B,X
            RTS      
;------------------------------------------------------------------------------
; <ESC>[2J   - Clear screen and send cursor to top-left
;------------------------------------------------------------------------------
UT_CLRSCR   PSHS A
            LDA  #$1B
            BSR  UT_PUTC
            LDA  #'[
            BSR  UT_PUTC
            LDA  #'2
            BSR  UT_PUTC
            LDA  #'J
            BSR  UT_PUTC
            PULS A
            RTS
;------------------------------------------------------------------------------
; SEND STRING AT Y OUT THE UART
;------------------------------------------------------------------------------            
UT_PUTS     PSHS x,y,a,b
UPSLOOP     LDA  ,Y+
            BEQ  UPSDONE    ; done when reach null terminator
            BSR  UT_PUTC
            BRA  UPSLOOP    ; loop around for next char of string
UPSDONE     PULS x,y,a,b
            RTS                 
;------------------------------------------------------------------------------
; Send cursor to row E and column F
;
; ANSI codes:  <ESC>[{ROW};{COLUMN}H
;------------------------------------------------------------------------------
UT_CUR_XY   PSHS A,B,X,Y
            LDU  #TMP_STR
            LDA  #$1B
            STA  ,U+
            LDA  #'[
            STA  ,U+
            LDA  #0
            TFR  E,B
            TFR  U,X
            JSR  S_INTD 
            LEAX -1,X
            TFR  X,U 
            LDA  #';
            STA  ,U+
            LDA  #0
            TFR  F,B
            TFR  U,X
            JSR  S_INTD 
            LEAX -1,X
            TFR  X,U 
            LDA  #'H
            STA  ,U+
            LDA  #0
            STA  ,U+
            LDY  #TMP_STR
            JSR  UT_PUTS
            PULS A,B,X,Y
            RTS
;------------------------------------------------------------------------------
; Send cursor to top left corner of screen
;
; ANSI codes:  <ESC>[{ROW};{COLUMN}H   or <ESC>[H
;
; todo: make generic version that takes row/col args and call that from here.
;------------------------------------------------------------------------------
UT_CUR_HOME LDE  #1
            LDF  #1
            BSR  UT_CUR_XY
            RTS
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of serio.asm
;------------------------------------------------------------------------------

