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
; Functions imported from other modules
;------------------------------------------------------------------------------
S_HEXA          EXTERN      ; string.asm
S_CPY           EXTERN
S_LEN           EXTERN
S_EOL           EXTERN
UT_INIT         EXTERN      ; serio.asm
EndOfVars       EXTERN      ; provided by linker, start of unused RAM
;------------------------------------------------------------------------------
; Functions exported for use by other modules
;------------------------------------------------------------------------------
JT_IRQ          EXPORT      ; ISR for IRQ - Serial, VIA, OPL3
JT_FIRQ         EXPORT      ; ISR for FIRQ - video HBLANK and/or VBLANK
JT_SW2          EXPORT      ; ISR for Software Intr. 2 - BIOS call
V_CBRK          EXPORT      ; Pseudo-ISR for when BIOS gets a CTRL-C input
;------------------------------------------------------------------------------
    SECT ram_start          ; Public variables - Section address $0000 
;------------------------------------------------------------------------------
DP_WARM         RMB  1      ; If not $55 on reset, we do a cold start
USER_RAM        RMB  2      ; Start adrs of free RAM not used by bootloader
RTC_TICKS       RMB  8      ; Number of 1/16 sec ticks since poweron or epoch
RTC_MTX         RMB  1      ; Semaphore for the above
BANKREG_1       RMB  1      ; shadow copies of the (unreadable) bank regs
BANKREG_2       RMB  1
BANKREG_3       RMB  1
RAM_JTAB                    ; BEGIN RAM ISR JUMP TABLE ------------------------
JT_DZINST       RMB  3      ; DIVIDE BY ZERO OR ILLEGAL INSTRUCTION
JT_SW3          RMB  3      ; SWI 3 
JT_SW2          RMB  3      ; SWI 2 - BIOS
JT_FIRQ         RMB  3      ; FIRQ 
JT_IRQ          RMB  3      ; IRQ 
JT_SWI          RMB  3      ; SWI END RAM JUMP TABLE -------------------------
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT bss                ; Private variables - section address $0030
;------------------------------------------------------------------------------
NEW_CTX         RMB  1      ; Set when theres a new break context to show
CTX_BUF         RMB  15     ; Most recent break context (register dump)
DUMP_ADRS       RMB  2      ; Start address used by hexdump display routine
EDUMP_ADRS      RMB  2      ; End address for hexdump display
RTC_TICKS_PRIV  RMB  8      ; number of 1/16 sec ticks since poweron or epoch
LINBUF          RMB  256    ; Misc line buffer
STACK           RMB  1024   ; CPU stack
STACK_END
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT code               ; Section address  $F000 - $FF00
;------------------------------------------------------------------------------

; Bootloader definitions and ROM constants (See also defines.d)

MSG_HELLO   FCC  "Pugputer 6309 - Bootloader v0.0.2"  ; Startup banner
            FCB  LF,CR,0

; Break types, used to label a break context for display

BC_SWI      EQU  $00        ; break code - software interrupt 
BC_DZINST   EQU  $01        ; divide by zero or illegal instruction
BC_CBRK     EQU  $02        ; control-c break
BS_SWI      FCC  "<SWI>"    ; break tag - normal (swi) break 
            FCB  0     
BS_DZINST   FCC  "<DZI>"    ; illegal instruction or divide by zero
            FCB  0                        
BS_CBRK     FCC  "<BRK>"    ; control-c break
            FCB  0       

; This little example program gets copied to RAM on cold start 
; in order to test the debugger

E_MSG       FCC  "Hello, World!"
            FCB  0            
PRG_EXAMP   LDY  #E_MSG
            ;JSR  CON_PUTS   ; Show hello message
            FCB  $15        ; Cause an illegal instruction interrupt
            SWI             ; Cause a software break
EXAMP_ADRS  EQU  $4000      ; examp prg loads to this RAM address
END_EXAMP

; Pseudo-ISR that is called whenever BIOS receives a CONTROL-C

V_CBRK      LDA  #BC_CBRK   
            JMP  SAVE_CTX

; -----------------------------------------------------------------------------
; Interrupt Service Routines - Some are hard-coded in the interrupt vector 
; table at $fff0 and are not changable, but others are referenced by the RAM 
; jump table so other modules can insert handlers at runtime.
; -----------------------------------------------------------------------------

; (Hardcoded) Handler for illegal instruction, divide-by-zero, or breakpoint

V_DZINST    LDA  #BC_DZINST ; Break type: div by 0 or illegal instr.
            JMP  SAVE_CTX
V_SWI       LDA  #BC_SWI    ; Break type: Software intr. 1 (breakpoint)
SAVE_CTX    LDY  #CTX_BUF   ; Store break type as first byte
            STA  ,Y+        ; of break context buffer.
            LDE  #14        ; Unstack the context registers manually, since
CTXLOOP     PULS A          ; we're storing them rather than doing an RTI
            STA  ,Y+        ; after this ISR.
            DECE            ; Pop order: CC, A, B, E, F, DP, X, Y, U, PC
            BNE  CTXLOOP
            LDA  #1
            STA  NEW_CTX    ; Note we have a new register context to show,
            JMP  MON_ENTRY  ; and jump to ML monitor prompt.

; (Hardcoded) NMI ISR - Called @ 16 Hz. Increments RTC_TICKS (64-bit int)

; Note: When software wants to read or change RTC_TICKS, it should set
; the RTX_MTX semaphore to prevent this ISR from changing it in the middle
; of the operation.

V_NMI       LDD  (RTC_TICKS_PRIV+0) ; increment private tick count
            ADDD #1
            STD  (RTC_TICKS_PRIV+0)
            BCC  NMI_COUNTED
            LDD  (RTC_TICKS_PRIV+4)
            ADDD #1
            STD  (RTC_TICKS_PRIV+4)
NMI_COUNTED LDA  RTC_MTX            ; Check RTC_TICKS semaphore,
            BNE  NMI_DONE           ; if it's in use, we're done.
            LDD  RTC_TICKS_PRIV     ; Copy RTC_TICKS_PRIV to
            STD  RTC_TICKS          ; to RTC_TICKS (public).
            LDD  RTC_TICKS_PRIV+4
            STD  RTC_TICKS+4
NMI_DONE    RTI

; Configurable ISR Stubs

V_SW3       RTI             ; SOFTWARE INTERRUPT 3 - Currently Unused

V_SW2       RTI             ; SOFTWARE INTERRUPT 2 - BIOS call

V_FIRQ      RTI             ; FIRQ - V9958 VBLANK/HBLANK interrupts
V_IRQ       RTI             ; IRQ - UART TX/RX, VIA io, OPL3 music

; -----------------------------------------------------------------------------
; This ROM ISR jump table gets copied to RAM during cold start so other modules
; can add their own handlers at runtime without needing to modify the ROM.
; -----------------------------------------------------------------------------

ROM_JTAB    JMP  V_DZINST   ; divide by zero, illegal instruction
            JMP  V_SW3      ;
            JMP  V_SW2      ;  
            JMP  V_FIRQ     ; vidio
            JMP  V_IRQ      ; serio
            JMP  V_SWI      ; monitor breakpoint
; -----------------------------------------------------------------------------
; RESET VECTOR ENTRYPOINT
; -----------------------------------------------------------------------------
V_RESET     LDMD #$01       ; Program entrypoint - Enable 6309 native mode

            ; Setup bank registers to first 4 pages of RAM
            
            LDA  #$00       ; Map RAM physical adrs $000000
            STA  $FFEC      ; ..to CPU adrs $0000
                            ; (and keep it that way, else things will break.)
                            ; Would be nice to have a small area of fixed RAM
                            ; that's not subject to the mapper, but we dont.
            LDA  #$01       ; Map RAM $004000
            STA  $FFED      ; ..to CPU adrs $4000
            STA  BANKREG_1  ; make a readable copy of this register setting
            LDA  #$02       ; Map RAM $008000
            STA  $FFEE      ; ..at CPU adrs $8000
            STA  BANKREG_2  ; make readable copy of this reg
            LDA  #$03       ; Map RAM $00C000
            STA  $FFEF      ; ..at CPU adrs $C000            
            STA  BANKREG_3  ; make readable copy of this reg

            ; handle cold-start / warm-start behavior

            LDA  DP_WARM    ; Get warm start flag
            CMPA #$55       ; and if its $55, 
            BEQ  WARMST     ; skip the cold-start initialization.

COLDST      LDX  #0         ; Zero all public and private vars
            LDY  #0    
            LDW  #(EndOfVars)
            TFM  x,y+

            ; init some helpful public vars

            LDX  #EndOfVars ; Get start address of free RAM,
            STX  USER_RAM   ; and note it in public variable
            LDA  #$55       
            STA  DP_WARM    ; We'll do a warm start next time
            CLR  NEW_CTX    ; No break register context to show yet

            ; init interrupt jump table

            LDX  #ROM_JTAB  ; Copy interrupt jump table to RAM
            LDY  #RAM_JTAB  ; 
            LDW  #(3*6)     ; 6 JMPs is 18 bytes
            TFM  X+,Y+      ; Use 6309'S nice block-bopy instruction.

            ; Copy example program to RAM

            LDX  #PRG_EXAMP 
            LDY  #EXAMP_ADRS     
            LDW  #(END_EXAMP-PRG_EXAMP)
            TFM  X+,Y+    

            LDS  #(STACK_END-1)     ; Init stack pointer (enables NMI int)
            
            ; Init BIOS

            ; init hardware peripherals used by BIOS
            
            ;JSR  pa_init   ; Init VIA/SD card
            JSR  UT_INIT    ; Init serial UART
            ;JSR  VD_INIT    ; Init video card
            
            ANDCC #$AF      ; Enable IRQ and FIRQ interrupts

            ; Warm start

WARMST      LDY  #MSG_HELLO ; Show bootloader title banner
            ;JSR  con_puts            
            ; try to boot from SD.. if couldnt boot, 
            BRA  MON_ENTRY  ; Start ML monitor.
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
MAINLOOP    ;JSR  con_svc    ; Console housekeeping service
            BEQ  ML_PAR     ; returns nonzero if we got something to do.

ML_PAR      ;JSR  pa_svc     ; parallel port housekeeping service
            ;LDA  PGotRxMsg
            ;BEQ  MAINLOOP
            ;JSR  show_pa    ; Show messages received via parallel
            BRA  MAINLOOP
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
            ;JSR  con_puts   ; OUTPUT CTX STRING TO CONSOLE
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
            ;JSR  con_puts   ; OUTPUT CTX STRING TO CONSOLE
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
            FDB  JT_DZINST  ; DIVIDE BY ZERO OR ILLEGAL INSTRUCTION
            FDB  JT_SW3     ; SWI3 
            FDB  JT_SW2     ; SWI2 
            FDB  JT_FIRQ    ; FIRQ 
            FDB  JT_IRQ     ; IRQ
            FDB  JT_SWI     ; SWI
            FDB  V_NMI      ; NMI 
            FDB  V_RESET    ; RESET
    ENDSECT
;------------------------------------------------------------------------------
; End of boot.main.asm
;------------------------------------------------------------------------------
