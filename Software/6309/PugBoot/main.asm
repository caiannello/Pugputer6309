;------------------------------------------------------------------------------
; PROJECT: PUGMON 
; VERSION: 0.0.1
;    FILE: main.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; PUGMON IS INTENDED TO BE A FULLY-FEATURED MACHINE-CODE MONITOR, DEBUGGER, 
; DISASSEMBLER, AND MINI ASSEMBLER FOR THE PUGBUTT INDUSTRIES PUGPUTER, A 
; SYSTEM BASED ON THE HITACHI HD63C09, A DESCENDENT OF THE MOTOROLA MC6809.
;
; RELEASED IN THE MID-1980'S, THE HD6309 WAS MARKETED AS 100% COMPATIBLE WITH
; THE MC6809, BUT AFTER A FEW YEARS, IT WAS DISCOVERED THAT THIS PART HAD SOME
; SECRET ENHANCEMENTS: IT CAN BE SWITCHED INTO "NATIVE MODE", WHICH OFFERS
; SIGNIFICANTLY FASTER EXECUTION SPEED, ADDITIONAL REGISTERS, AND NEW 
; INSTRUCTIONS SUCH AS MEMORY BLOCK-COPY AT 4X SPEED.
;
; I PLAN ON RUNNING THE HD6309 IN NATIVE MODE AT ALL TIMES, SO THIS UTILITY 
; WILL NOT WORK ON MC6809 SYSTEMS, FOR NOW ANYWAY.
;
; NOTES:
;
; PUGMON SUPPORTS TWO CONSOLE INTERFACES: A SERIAL PORT BASED ON THE ROCKWELL
; R65C51P2 UART, AT 19.2 KBAUD, AND A VIDEO DISPLAY BASED ON THE YAMAHA V9958.
; BECAUSE RAM IS CHEAP THESE DAYS, I'M IMPLEMENTING A FULL-SCREEN EDITOR,
; WITH ANSI CURSOR KEYS, REMINSCENT OF COMMODORE MACHINES, SO ONE WILL BE ABLE
; TO CURSOR-UP TO A LINE OF HEX-DUMP OR DISASSEMBLY AND CHANGE IT IN-SITU. 
; 
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; Global settings and definitions
;------------------------------------------------------------------------------
; Module function imports
;------------------------------------------------------------------------------
S_HEXA          EXTERN      ; string.asm
S_CPY           EXTERN
S_LEN           EXTERN
S_EOL           EXTERN
FIL_GET         EXTERN      ; file.asm
FIL_DIR         EXTERN
FIL_CAT         EXTERN
UT_INIT         EXTERN      ; serio.asm
pa_init         EXTERN      ; pario.asm
pa_clear        EXTERN
pa_acknowledge  EXTERN
pa_svc          EXTERN
pa_send_msg     EXTERN
PGotRxMsg       EXTERN
PFlags          EXTERN
PRxBuf          EXTERN
PRxHead         EXTERN
CrcVal          EXTERN
PMsgSize        EXTERN
PMsgEnd         EXTERN
con_init        EXTERN      ; conio.asm
con_svc         EXTERN
con_clrhome     EXTERN
con_puteol      EXTERN
con_getc        EXTERN
con_putc        EXTERN
con_puts        EXTERN
con_puthbyte    EXTERN
con_puthword    EXTERN
EndOfVars       EXTERN      ; provided by linker, start of unused RAM
;------------------------------------------------------------------------------
; Functions exported for use by other modules
;------------------------------------------------------------------------------
JT_IRQ          EXPORT      ; ram jump table entry for IRQ vector
JT_FIRQ         EXPORT      ; ISR for FIRQ (vidio.asm)
JT_NMI          EXPORT
V_CBRK          EXPORT      ; Pseudo-ISR for when get CONTROL-C keypress
;------------------------------------------------------------------------------
; Zero page variables
;------------------------------------------------------------------------------
    SECT ram_start          ; Section address $0000 
;------------------------------------------------------------------------------
USER_RAM        RMB  2      ; STARTING ADDRESS OF FREE USER RAM
DP_WARM         RMB  1      ; IF NOT $55 ON RESET, WE DO A COLD START.
RAM_JTAB                    ; BEGIN RAM ISR JUMP TABLE ------------------------
JT_DZINST       RMB  3      ; DIVIDE BY ZERO OR ILLEGAL INSTRUCTION
JT_SW3          RMB  3      ; SWI 3 
JT_SW2          RMB  3      ; SWI 2 
JT_FIRQ         RMB  3      ; FIRQ 
JT_IRQ          RMB  3      ; IRQ 
JT_SWI          RMB  3      ; SWI
JT_NMI          RMB  3      ; NMI, END RAM JUMP TABLE -------------------------
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; Misc Variables
;------------------------------------------------------------------------------
    SECT bss                ; Section Address $0018
;------------------------------------------------------------------------------
TMP_KEY     RMB  1          ; TEMP STORAGE OF MONITOR PROMPT KEYPRESS
DUMP_ADRS   RMB  2          ; ADDRESS USED BY HEXDUMP ROUTINE
EDUMP_ADRS  RMB  2          ; ENDING ADDRESS USED BY HEXDUMP ROUTINE
NEW_CTX     RMB  1          ; TRUE WHEN HAVE A NEW REGISTER CONTEXT TO SHOW
CTX_BUF     RMB  15         ; HOLDS MOST RECENT BREAK CONTEXT
LINBUF      RMB  256        ; BUFFER USED BY LINE EDITOR AND OUTPUT
DBG_HEX     RMB  1          ; IF TRUE, CONSOLE KEYPRESSES ARE SHOWN AS HEX
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT code               ; Section address  $D000
;------------------------------------------------------------------------------
MSG_HELLO   FCC  "PUGMON v0.0.1"  ; MESSAGE SHOWN ON COLD START
            FCB  LF,CR,0

BC_SWI      EQU  $00        ; break code - software interrupt 
BC_DZINST   EQU  $01        ; divide by zero or illegal instruction
BC_CBRK     EQU  $02        ; control-c break
BS_SWI      FCC  "<SWI>"    ; break tag - normal (swi) break 
            FCB  0     
BS_DZINST   FCC  "<DZI>"    ; illegal instruction or divide by zero
            FCB  0                        
BS_CBRK     FCC  "<BRK>"    ; control-c break
            FCB  0       
; this is a little example program that gets copied to RAM on startup
; in order to test the debugger:
E_MSG       FCC  "Hello, World!"
            FCB  0            
PRG_EXAMP   LDY  #E_MSG     ; EXAMPLE DBG PROG, LOADED TO RAM ON STARTUP
            JSR  con_puts   ; SHOW HELLO MESSAGE
            FCB  $15        ; ILLEGAL INSTRUCTION
            SWI             ; BREAK
END_EXAMP
; -----------------------------------------------------------------------------
; Interrupt Service Routines - RAM jump table is pointed to these at startup
; -----------------------------------------------------------------------------
V_NMI       RTI             ; NON MASKABLE INTERRUPT ISR - USED BY PARIO
V_SW3       RTI             ; SOFTWARE INTERRUPT 3 - UNUSED BY PUGMON
V_SW2       RTI             ; SOFTWARE INTERRUPT 2 - UNUSED BY PUGMON 
V_FIRQ      RTI             ; FIRQ ISR - USED IN VIDIO.ASM
V_IRQ       RTI             ; IRQ ISR - UART TX/RX
V_DZINST    LDA  #BC_DZINST ; DIVIDE BY ZERO, ILLEGAL INSTRUCTION ISR
            JMP  SAVE_CTX
V_SWI:      LDA  #BC_SWI    ; SOFTWARE INTERRUPT 1 (BREAKPOINT) ISR
SAVE_CTX    LDY  #CTX_BUF   ; IN BREAK CONTEXT BUFFER,
            STA  ,Y+        ; STORE BREAK TYPE CODE, 
            LDE  #14        ; WE UNSTACK THE CONTEXT MANUALLY, SINCE WE'RE
CTXLOOP     PULS A          ; STORING IT, AND WE'RE NOT DOING AN RTI AT THE
            STA  ,Y+        ; END OF THIS ISR.
            DECE            ; PULL ORDER: CC, A, B, E, F, DP, X, Y, U, PC
            BNE  CTXLOOP
            LDA  #1
            STA  NEW_CTX    ; NOTE WE HAVE A NEW REGISTER CONTEXT TO SHOW.
            JMP  MON_ENTRY  ; JUMP TO MONITOR PROMPT 
; -----------------------------------------------------------------------------
; ISR ROM JUMP-TABLE - GETS COPIED TO RAM DURING COLD-START, SO USER CAN 
; CUSTOMIZE ISRS WITHOUT NEEDING TO MODIFY THE ROM.
; -----------------------------------------------------------------------------
ROM_JTAB    JMP  V_DZINST   ; divide by zero, illegal instruction
            JMP  V_SW3      ;
            JMP  V_SW2      ;  
            JMP  V_FIRQ     ; vidio
            JMP  V_IRQ      ; serio
            JMP  V_SWI      ; monitor breakpoint
            JMP  V_NMI      ; pario
; -----------------------------------------------------------------------------
V_CBRK      LDA  #BC_CBRK   ; Pseudo-ISR. Called by serio when a CONTROL-C is
            JMP  SAVE_CTX   ; received.
; -----------------------------------------------------------------------------
; RESET VECTOR ENTRYPOINT
; -----------------------------------------------------------------------------
V_RESET     LDMD #$01       ; PROGRAM ENTRY-POINT - ENABLE 6309 NATIVE MODE 
            LDS  #$1000     ; SET STACK TO END OF FIRST 4K OF RAM
            LDX  #EndOfVars ; start of user ram
            STX  USER_RAM   ; STORE THE STARTING ADRS OF USER RAM AT $0000
            LDA  DP_WARM    ; GET WARM START FLAG 
            CMPA #$55       ; IS IT A WARM START? 
            BEQ  WARMST     ; YES
COLDST      LDA  #$55       ; COLD START --------------------------------------
            STA  DP_WARM    ; DO A WARM START NEXT TIME. 
            LDX  #ROM_JTAB  ; COPY INTERRUPT JUMP TABLE FROM ROM TO RAM:
            LDY  #RAM_JTAB  ; 
            LDW  #(3*7)     ; 7 JMPS IS 21 BYTES
            TFM  X+,Y+      ; USING 6309'S NICE BLOCK COPY INSTRUCTION.
            CLR  NEW_CTX    ; No break register context to show yet
            CLR  DBG_HEX    ; Dont show keypresses as hex, initially.
            JSR  pa_init    ; INIT PARALLEL PORT - MUST HAPPEN BEFORE UT_INIT
                            ; (TO ENABLE UART ISR'S FALLTHROUGH TO PAR. ISR.)
            JSR  UT_INIT    ; INIT SERIAL PORT
            ANDCC #$AF      ; ENABLE IRQ AND FIRQ INTERRUPTS
WARMST      LDX  #PRG_EXAMP ; WARM START --------------------------------------
            LDY  #$1000     ; COPY THE EXAMPLE PROGRAM TO RAM 
            LDW  #(END_EXAMP-PRG_EXAMP)
            TFM  X+,Y+    
            JSR  con_init   ; init the console driver 
            LDY  #MSG_HELLO ; SHOW PUGMON TITLE BANNER
            JSR  con_puts
            BRA  MON_ENTRY
; -----------------------------------------------------------------------------
; BREAK ENTRYPOINT TO MAINLOOP
; -----------------------------------------------------------------------------
MON_ENTRY   LDA  NEW_CTX    ; MONITOR ENTRYPOINT: CHECK IF GOT A REG CONTEXT --
            BEQ  MAINLOOP 
            CLR  NEW_CTX    ; GOT A NEW CTX TO SHOW
            JSR  SHOW_CTX
; -----------------------------------------------------------------------------
; MAIN LOOP
; -----------------------------------------------------------------------------
MAINLOOP    JSR  con_svc    ; Console housekeeping service
            BEQ  ML_PAR     ; returns nonzero if we got something to do.

ML_PAR      JSR  pa_svc     ; parallel port housekeeping service
            LDA  PGotRxMsg
            BEQ  MAINLOOP
            JSR  show_pa    ; Show messages received via parallel
            BRA  MAINLOOP
; -----------------------------------------------------------------------------
;MAINLOOP    JSR  con_svc   ; Console housekeeping svc
;ML_PAR      JSR  pa_svc    ; parallel port housekeeping svc
;            LDA  PGotRxMsg
;            BEQ  ML_GETKEY
;            JSR  show_pa    ; Show messages received via parallel
;ML_GETKEY   JSR  con_getc   ; Check for keypress,
;            BEQ  MAINLOOP   ; and loop until we get one. 
;            BSR  KEYHANDLER
;            BRA  MAINLOOP
; -----------------------------------------------------------------------------
;KEYHANDLER
;            CMPA #CR        ; IF WE GET A CR, ECHO IT, FOLLOWED BY A LF.
;            BNE  ML_ECHO
;            JSR  con_putc 
;            LDA  #LF
;            JSR  con_putc   
;            BRA  MAINLOOP   ; done with cr/lf.
;ML_ECHO     STA  TMP_KEY    ; STASH PRESSED KEY FOR FURTHER CHECKING, THEN
;            JSR  con_putc   ; ECHO THE RECEIVED CHARACTER TO USER.
;            LDA  TMP_KEY    ; DEPENDING ON KEY, MAYBE DO STUFF:
;ML_K_CTL_L  CMPA #108       ; CTRL-L : CLEAR TEXT SCREEN AND CURSOR HOME
;            BNE  ML_K_TIL
;            JSR  con_clrhome    
;ML_K_TIL    CMPA #TILDE     ; '~': RUN RAM EXAMPLE PROGRAM, THEN BREAK.
;            BNE  ML_K_DIR
;            JSR  con_puteol ; NEWLINE
;            JMP  $1000
;            BRA  MAINLOOP
;ML_K_DIR    CMPA #'D        ; 'D': SEND DIR COMMAND VIA PARALLEL
;            BNE  ML_K_FILE
;            JSR  con_puteol
;            JSR  FIL_DIR
;            BRA  MAINLOOP 
;ML_K_FILE   CMPA #'F        ; 'F': GET A FILE VIA PARALLEL
;            BNE  ML_H_HEXDMP
;            JSR  con_puteol
;            JSR  FIL_GET
;            BRA  MAINLOOP 
;ML_H_HEXDMP CMPA #'H        ; 'H': HEX DUMP 8K STARTING AT $8000
;            BNE  ML_K_DUMP
;            JSR  con_puteol
;            LDX  #$8000
;            STX  DUMP_ADRS
;            LEAX 64,X
;            STX  EDUMP_ADRS
;            JSR  HEXDUMP_BLOCK            
;            JMP  MAINLOOP
;ML_K_DUMP   CMPA #'.        ; '.': Show parallel flags and buffer
;            LBNE MAINLOOP
;            JSR  show_pa
;            JMP  MAINLOOP
;ML_END      JMP  MAINLOOP

; -----------------------------------------------------------------------------
; Show hexdump of received parallel message and some stats, and if it is a 
; freshly-received message, send an ACK so MCU knows we're ready for more.
; -----------------------------------------------------------------------------
PHDR        FCC  "GM FL  SZ  CRC"
            FCB  LF,CR,0    
show_pa:    LDY  #PHDR      ; print header
            JSR  con_puts
            LDA  PGotRxMsg  ; 1: new valid message
            JSR  con_puthbyte
            LDA  PFlags     ; parallel debug flags
            JSR  con_puthbyte        
            LDD  PMsgSize   ; parallel rx message size
            JSR  con_puthword
            LDD  CrcVal     ; CRC-16 (0 for valid message)
            JSR  con_puthword
            JSR  con_puteol
            LDX  #PRxBuf    ; Hex dump of message bytes
            STX  DUMP_ADRS
            TFR  X,W
            ADDW PMsgSize
            TFR  W,X
            STX  EDUMP_ADRS
            JSR  HEXDUMP_BLOCK
            LDA  PGotRxMsg  ; If newly received message,
            BEQ  spa_done   
            JSR  pa_acknowledge ; Send ack to MCU.
spa_done    RTS
; -----------------------------------------------------------------------------
; Show latest saved register context from a monitor break, e.g.:
; "...<BRK_TAG>                            "
; "  CC A  B  E  F  DP  X    Y    U    PC  "
; "  A5 00 0C 00 00 00 00A9 E07D FFFF 1008 "
; -----------------------------------------------------------------------------
CTX_HDR     FCB  LF,CR      ; BREAK REGISTER CONTEXT HEADER
            FCC  "  CC A  B  E  F  DP  X    Y    U    PC"
            FCB  LF,CR,0
SHOW_CTX    LDX  #LINBUF            
            LDY  #CTX_BUF    
            LDF  ,Y+        ; GET BREAK TYPE IN F
            BEQ  BT_SW
            CMPF #BC_CBRK
            BNE  BT_DZ
BT_CB       LDY  #BS_CBRK   ; CODE 2: CONTROL-C BREAK: <CBK>
            BRA  BT_HDR
BT_DZ       LDY  #BS_DZINST ; CODE 3: DIV 0 OR ILLEGAL INSTRUCTION BREAK <DZI>
            BRA  BT_HDR
BT_SW       LDY  #BS_SWI    ; CODE 0: SOFTWARE INTERRUPT 1 BREAK <SWI>
BT_HDR      JSR  S_CPY 
            LEAX ,-X        ; REMV NULL
            LDY  #CTX_HDR   ; e.g. "  CC A  B  E  F  DP  X    Y    U    PC "
            JSR  S_CPY      ;      "; A5 00 0C 00 00 00 00A9 E07D FFFF 1008"
            LEAX ,-X        ; REMV NULL
            LDA  #';        ; PRECEED EDITABLE REG VALUES WITH A ';'
            STA  ,X+
            LDY  #CTX_BUF+1    
            LDE  #6
CTX_BYTE    LDA  #SPACE     ; DO CC, A, B, E, F, DP
            STA  ,X+
            LDA  ,Y+
            JSR  S_HEXA  
            DECE
            BNE  CTX_BYTE
            LDE  #4
CTX_WORD    LDA  #SPACE     ; DO X, Y, U, PC  
            STA  ,X+
            LDA  ,Y+
            JSR  S_HEXA  
            LDA  ,Y+
            JSR  S_HEXA  
            DECE
            BNE  CTX_WORD
            JSR  S_EOL      ; ADD CR+LF+NULL TO OUTPUT STRING
            LDY  #LINBUF
            JSR  con_puts   ; OUTPUT CTX STRING TO CONSOLE
            RTS             ; END REG CONTEXT PRINT 
;------------------------------------------------------------------------------
; PRINTS UP TO 16 BYTES OF MEMORY, STARTING AT DUMP_ADRS, AS HEX + ASCII, AND
; DUMP_ADRS IS INCREMENTED BY THE AMOUNT OF SHOWN. 
; IF DUMP_ADRS IS LESS THAN SIXTEEN LESS THAN EDUMP_ADRS, LESS BYTES ARE SHOWN,
; REPLACED BY SPACES.
;------------------------------------------------------------------------------
HEXDUMP_LINE:               
            LDX  #LINBUF
            LDA  #'>        ; PUT '>' BEFORE ADDRESS
            STA  ,X+
            LDA  DUMP_ADRS  ; THEN 4-CHAR HEX ADDRESS
            JSR  S_HEXA  
            LDA  DUMP_ADRS+1
            JSR  S_HEXA  
            LDA  #32        ; THEN A SPACE,
            STA  ,X+
            LDY  DUMP_ADRS  ; GET STARTING ADDRESS IN Y
            LDE  #16        ; FOR 16 ITERATIONS
            LDU  #(LINBUF+1+5+16*3)  ; POINT U AT ASCII PART AFTER HEX CHARS
            LDA  #$A8       ; WHICH BEGINS WITH THIS AS A DELIMITER
            STA  ,U+
            LDF  #'.
HEXLOOP     CMPY EDUMP_ADRS ; IF PASS THE END DUMP ADRS, STOP SHOWING HEX
            BGE  NULLOOP
            LDA  ,Y+        ; GONNA SHOW A HEX OCTET  
            CMPA #32
            BGE  ASCIIOK
            STF  ,U+        ; SHOW ASCII NONPRINTABLES AS A DECIMAL POINT
            BRA  DONEASCII
ASCIIOK     STA  ,U+        ; ADD ASCII CHAR OR DEC TO LINE AT POS U
DONEASCII   JSR  S_HEXA      ; AT LINE POS X, ADD 2-CHAR HEX BYTE AND
            LDA  #32        ; A SPACE,
            STA  ,X+
            DECE            ; CHECK IF MORE BYTES TO DO
            BNE  HEXLOOP
            BRA  LINEDONE
NULLOOP     LDA  ,Y+        ; PAST EDUMP ADRS, SHOW NOTHING
            LDA  #32
            STA  ,U+        
            STA  ,X+
            STA  ,X+
            STA  ,X+
            DECE            ; CHECK IF MORE BYTES TO DO
            BNE  NULLOOP
LINEDONE    STY  DUMP_ADRS  ; LINE DONE. UPDATE DUMP POSITION TO NEXT ROW,
            LDA  #$A8       ; PUT END DELIMITER ON ASCII PART.
            STA  ,U+              
            TFR  U,X
            JSR  S_EOL      ; ADD CR+LF+NULL TO OUTPUT STRING
            LDY  #LINBUF
            JSR  con_puts   ; OUTPUT CTX STRING TO CONSOLE
            RTS
;------------------------------------------------------------------------------
; HEX+ASCII DUMP MEM FROM DUMP_ADRS THROUGH EDUMP_ADRS 
;------------------------------------------------------------------------------
HEXDUMP_BLOCK
            LDX  DUMP_ADRS
            CMPX EDUMP_ADRS
            BGT  DONE_BLOCK
            BSR  HEXDUMP_LINE
            BRA  HEXDUMP_BLOCK
DONE_BLOCK  RTS
; -----------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; Interrupt vectors
;------------------------------------------------------------------------------
    SECT intvect
;------------------------------------------------------------------------------
            FDB  JT_DZINST  ; DIVIDE BY ZERO OR ILLEGAL INSTRUCTION
            FDB  JT_SW3     ; SWI3 
            FDB  JT_SW2     ; SWI2 
            FDB  JT_FIRQ    ; FIRQ 
            FDB  JT_IRQ     ; IRQ
            FDB  JT_SWI     ; SWI
            FDB  JT_NMI     ; NMI 
            FDB  V_RESET    ; RESET
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; END OF PUGMON.ASM
;------------------------------------------------------------------------------
