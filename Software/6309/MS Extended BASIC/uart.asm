; W65C51N UART 
UARTDAT     EQU  $F000  ; RD RX, WR TX
UARTSTA     EQU  $F001  ; RD for UART Status, WR for reset
UARTCMD     EQU  $F002  ; UART Command Register
UARTCTL     EQU  $F003  ; UART Control Register

; Wait for a keystroke from the console.
KEYWAIT   BSR  KEYIN          ; GET A CHARACTER FROM CONSOLE IN 
          BEQ  KEYWAIT        ; LOOP IF NO KEY DOWN 
          RTS                  
                               
; THIS ROUTINE GETS A KEYSTROKE FROM THE KEYBOARD IF A KEY                      
; IS DOWN. IT RETURNS ZERO TRUE IF THERE WAS NO KEY DOWN.                      
KEYIN     LDA  UARTSTA        ; get uart status
          BITA #8             ; if data register  
          BEQ  NOCHAR         ; not full, else
          LDA  UARTDAT        ; read character from UART into A
          ANDA #$7F            
          RTS                  
NOCHAR    CLRA                 
          RTS                  
                               
; CONSOLE OUT                      
PUTCHR    PSHS A
          TST VDP_VBLANK_ENABLED  ; IF SCREEN UPDATES ARE DISABLED
          BEQ DO_UART_PUTCHAR     ; OUTPUT TO CHARS UART
          JSR VDP_PUTC            ; ELSE OUTPUT TO SCREEN
          CMPA #CR            IS IT CARRIAGE RETURN? 
          BEQ  NEWLINE0        YES 
          INC  LPTPOS         INCREMENT CHARACTER COUNTER 
          LDA  LPTPOS         CHECK FOR END OF LINE PRINTER LINE 
          CMPA LPTWID         AT END OF LINE PRINTER LINE? 
          BLO  PUTEND0         NO 
NEWLINE0  CLR  LPTPOS         RESET CHARACTER COUNTER 
PUTEND0   PULS A               
          RTS                  

DO_UART_PUTCHAR:
          BSR  WAITUART        
          CMPA #CR            IS IT CARRIAGE RETURN? 
          BEQ  NEWLINE        YES 
          STA  UARTDAT        ; put character in data register        
          INC  LPTPOS         INCREMENT CHARACTER COUNTER 
          LDA  LPTPOS         CHECK FOR END OF LINE PRINTER LINE 
          CMPA LPTWID         AT END OF LINE PRINTER LINE? 
          BLO  PUTEND         NO 
NEWLINE   CLR  LPTPOS         RESET CHARACTER COUNTER 
          BSR  WAITUART        
          LDA  #CR
          STA  UARTDAT        ; put CR in data register        
          BSR  WAITUART        
          LDA  #LF            DO LINEFEED AFTER CR 
          STA  UARTDAT        ; put LF in data register        
PUTEND    PULS A               
          RTS                  
                               
WAITUART  PSHS A               
WRWAIT    LDA  UARTSTA        ; get uart status
          LDA  UARTSTA        ; get uart status
          BITA #16            ; status.4 is TDRE bit
          BEQ  WRWAIT         ; 0: transmit reg still occupied. keep waiting.
          PULS A
          RTS      

; Init W65C51N UART polled

UART_INIT:
        LDA #$1F            ; %0001 1111 = 19200 Baud
                            ;              External receiver
                            ;              8 bit words
                            ;              1 stop bit
        STA UARTCTL
        LDA #$0B            ; %0000 1011 = Receiver odd parity check
                            ;              Parity mode disabled
                            ;              Receiver normal mode
                            ;              RTSB Low, trans int disabled
                            ;              IRQB disabled
                            ;              Data terminal ready (DTRB low)
        STA UARTCMD
        RTS
