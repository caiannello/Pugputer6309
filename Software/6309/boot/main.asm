;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - bootloader 
; VERSION: 0.0.2
;    FILE: main.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; This will be the firmware for the Rev 2 hardware. We have 32K of FLASH, but 
; because I'm hoping to keep most of the CPU's address space dedicated to RAM,
; I'm leaving only 3840 bytes of the FLASH exposed, from $F000 to $FF00, to
; contain the system firmware.
;
; Planned features:
;
;   - Interrupt handler ISRs or stubs for all interrupts, some reconfigurable
;     via a jump table in RAM.
;
;   - NMI handler which increments a 64-bit real-time counter in RAM
;   
;   - Buffered, interrupt-driven serial interface at 19200 baud
; 
;   - BIOS functions for IO, SD Card, date and time, and a way to plug 
;     additional IO devices during boot for video and keyboard. (See notes)
; 
;   - Init VIA card, if present, and attempts boot from SD card.
; 
;   - If nothing is bootable, starts built-in ML monitor:
; 
;       ML mon features:
; 
;         - Serial interface by default ( + video/kbd after boot )
;         - Simple memory inspection / edit / call / jump
;         - XMODEM file transfer / serial boot
;         - Catches illegal-instruction interrupt by default, or can be
;           redirected to a custom handler by a running application.
; 
; Notes:
;   
; Due to small flash size (3840 bytes) and large font size (2048 bytes) it's 
; not easy to include full text-mode video support in firmware. Besides that,
; a system may have a different video solution from the existing V9958 card.
; It may be possible to have v9958 support in firmware using a pared-down 
; font and/or data compression, but for now, the video driver will get 
; loaded into RAM during boot and then plugged-in to the BIOS. This will 
; enable video/keyboard support in the ML monitor in addition to the default
; serial interface.
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; Global settings and definitions
;------------------------------------------------------------------------------
; Functions imported from other modules
;------------------------------------------------------------------------------
V_NMI           EXTERN      ; time.asm - real-time interrupt
RTC_GETTIX      EXTERN
UT_INIT         EXTERN      ; serio.asm - serial port UART
UT_GETC         EXTERN
UT_PUTC         EXTERN
UT_PUTS         EXTERN
UT_WAITTX       EXTERN
UT_CLRSCR       EXTERN
STXIE           EXTERN
S_HEXA          EXTERN      ; helpers.h
S_EOL           EXTERN
S_LEN           EXTERN
S_CPY           EXTERN
VDP_INIT        EXTERN      ; vdp.h - optional graphics card
EndOfVars       EXTERN      ; provided by linker, start of unused RAM
;------------------------------------------------------------------------------
; Stuff exported for use by other modules
;------------------------------------------------------------------------------
RTC_TICKS       EXPORT      ; Number of 1/16 sec ticks since poweron or epoch
RTC_TICKS_PRIV  EXPORT
RTC_MTX         EXPORT      ; Mutex for the above
RTC_SET         EXPORT      ; Semaphore to update private val from public val
RTC_SHOW        EXPORT      ; Sub to show current tick count
JT_FIRQ         EXPORT      ; RAM jump to ISR for FIRQ - video HBLANK, VBLANK
JT_IRQ          EXPORT      ; RAM jump to ISR for IRQ - Serial, VIA, OPL3
JT_CBRK         EXPORT      ; RAM jump to ISR for user break (Ctrl-C)
;------------------------------------------------------------------------------
; Public variables - Section address $0000
;------------------------------------------------------------------------------
    SECT ram_start           
WARM_ST         RMB  1      ; If not $55 on reset, we do a cold start
USER_RAM        RMB  2      ; Start adrs of free RAM not used by bootloader
JTAB_ADRS       RMB  2      ; Start adrs of ISR jump table
RTC_TICKS       RMB  8      ; Number of 1/16 sec ticks since poweron or epoch
RTC_TICKS_PRIV  RMB  8
RTC_MTX         RMB  1      ; Mutex for the above
RTC_SET         RMB  1      ; Semaphore to update private val from public val
SBANK_1         RMB  1      ; Readable copies of the mem bank registers
SBANK_2         RMB  1
SBANK_3         RMB  1
RAM_JTAB                    ; BEGIN RAM ISR JUMP TABLE ------------------------
JT_DZINST       RMB  3      ; DIVIDE BY ZERO OR ILLEGAL INSTRUCTION
JT_SW3          RMB  3      ; SWI 3 - UNUSED
JT_SW2          RMB  3      ; SWI 2 - BIOS CALL
JT_FIRQ         RMB  3      ; FIRQ - VIDEO (VBLANK, HBLANK)
JT_IRQ          RMB  3      ; IRQ - UART, VIA, OPL3
JT_SWI          RMB  3      ; SWI - SW BREAKPOINT
JT_CBRK         RMB  3      ; CTRL-C BREAK - END RAM JUMP TABLE ---------------
    ENDSECT
;------------------------------------------------------------------------------
; Private variables - section address $0100
;------------------------------------------------------------------------------
    SECT bss
NEW_CTX         RMB  1      ; Set when theres a new break context to show
CTX_BUF         RMB  15     ; Most recent break context (register dump)
DUMP_ADRS       RMB  2      ; Start address used by hexdump display routine
EDUMP_ADRS      RMB  2      ; End address for hexdump display
TMP_KEY         RMB  1      ; holds monitor cli keystroke
LINBUF          RMB  256    ; Misc text line buffer    
TMP8_0          RMB  1      ; Misc 8-bit value (used in ram test)
TMP16_0         RMB  2      ; Misc 16-bit value (used in ram test)
TMP8_1          RMB  1      ; Misc 8-bit value (used in ram test)
TMP16_1         RMB  2      ; Misc 16-bit value (used in ram test)
TMP64_0         RMB  8      ; Misc 64-bit value (used for tick counts)
SRECCHK         RMB  1      ; Running checksum of current SREC line
SRECBC          RMB  1      ; Bytecount of current SREC line
SRECBUF         RMB  32
STACK           RMB  512    ; System stack
STACK_END
    ENDSECT
;------------------------------------------------------------------------------
; ROM Code/Data - Section address  $F000 - $FF00
;------------------------------------------------------------------------------
    SECT code

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

;E_MSG       FCC  "Hello, World!"
;            FCB  0            
;PRG_EXAMP   LDY  #E_MSG
            ;JSR  CON_PUTS   ; Show hello message
;            FCB  $15        ; Cause an illegal instruction interrupt
;            SWI             ; Cause a software break
;EXAMP_ADRS  EQU  $4000      ; examp prg loads to this RAM address
;END_EXAMP

; -----------------------------------------------------------------------------
; Interrupt Service Routines - Two of these, RESET and NMI are hard-coded in 
; the interrupt vector table at $fff0 and can't be changed. The rest are 
; directed though a RAM jump table so other modules can add or replace 
; handlers at runtime. More on this below.
; Note: NMI ISR is in time.asm.
; -----------------------------------------------------------------------------

; built-in handler for illegal instruction / divide-by-zero (DZINST vector)

V_DZINST    LDA  #BC_DZINST
            JMP  SAVE_CTX

; built-in handler for breakpoint (SWI vector)

V_SWI       LDA  #BC_SWI
            JMP  SAVE_CTX

; handler for when BIOS receives a CONTROL-C

V_CBRK      LDA  #BC_CBRK   
            JMP  SAVE_CTX

; Default stubs for some configurable ISRs 

V_SW2       RTI             ; SOFTWARE INTERRUPT 2 - Unused
V_SW3       RTI             ; SOFTWARE INTERRUPT 3 - Unused
V_FIRQ      RTI             ; FIRQ - V9958 VBLANK/HBLANK interrupts
V_IRQ       RTI             ; IRQ - UART TX/RX, VIA I/O, OPL3 music
; -----------------------------------------------------------------------------
; This ROM ISR jump table gets copied to RAM_JTAB during cold start so other 
; modules can add their own interrupt handlers at runtime without having to 
; modify the ROM.
;
; To add a handler, a program should make a copy of the preexisting jump 
; target before poking the address of its own handler in its place.
;
; For a vector like IRQ, which is shared among UART, OPL3 music, and VIA,
; each ISR should check if the interrupt was actually caused by the relevant 
; device, and if not, it should jump to the address it found during init.
; It should be OK for any one device per vector to not be able to tell what 
; caused the interrupt, as long as it's the last handler in the chain.
;
; If we get to the point where we ever want to remove handlers in a robust
; way, this should probably be reimplemented as a linked-list.
; -----------------------------------------------------------------------------
ROM_JTAB    JMP  V_DZINST   ; Divide by zero, illegal instruction
            JMP  V_SW3      ; Unused
            JMP  V_SW2      ; BIOS call 
            JMP  V_FIRQ     ; video HBLANK, VBLANK
            JMP  V_IRQ      ; UART, VIA, OPL3
            JMP  V_SWI      ; Breakpoint
            JMP  V_CBRK     ; Ctrl-C break (Pseudo-ISR from BIOS)
; -----------------------------------------------------------------------------
; store break type and context, and jump to ML monitor.
; -----------------------------------------------------------------------------
SAVE_CTX    LDY  #CTX_BUF   ; Store break type as first byte
            STA  ,Y+        ; of break context buffer.
            LDE  #14        ; Unstack the context registers manually, since
CTXLOOP     PULS A          ; we're storing them rather than doing an RTI.
            STA  ,Y+
            DECE            ; Pop order: CC, A, B, E, F, DP, X, Y, U, PC
            BNE  CTXLOOP
            LDA  #1
            STA  NEW_CTX    ; Note we have a new register context to show,
            JMP  MON_ENTRY  ; and jump to ML monitor prompt.            
; -----------------------------------------------------------------------------
; Reset Vector Entrypoint - Initialize system
; -----------------------------------------------------------------------------
V_RESET     LDMD #$01       ; Enable 6309 native mode
            TFR  0,DP       ; Set direct page to Public vars
            LDA  #$00       ; Map RAM physical adrs $000000
            STA  MBANK_0    ; ..to CPU adrs $0000 
                            ; (and keep it that way, else things will break.)
            ;LDA  <WARM_ST   ; Get warm start flag
            ;CMPA #$55       ; and if its $55, 
            ;BEQ  WARMST     ; skip the cold-start initialization.
COLDST      LDX  #0         ; Zero all RAM used by ROM code
            CLR  ,X
            LDY  #0    
            LDW  #2000
            TFM  x,y+
            ; Setup bank registers to first 4 pages of RAM
            LDA  #$01       ; Map RAM $004000
            STA  MBANK_1    ; ..to CPU adrs $4000
            STA  <SBANK_1   ; make a readable copy of this register setting
            LDA  #$02       ; Map RAM $008000
            STA  MBANK_2    ; ..at CPU adrs $8000
            STA  <SBANK_2   ; make readable copy of this reg
            LDA  #$03       ; Map RAM $00C000
            STA  MBANK_3    ; ..at CPU adrs $C000            
            STA  <SBANK_3   ; make readable copy of this reg
            ; init some helpful public vars
            LDA  #$55       
            STA  <WARM_ST   ; $0000 We'll do a warm start next time
            LDX  #EndOfVars ; Get start address of free RAM,
            STX  <USER_RAM  ; $0001 and note it in public variable
            LDX  #RAM_JTAB  ; Get start address of RAM ISR jump table
            STX  <JTAB_ADRS ; $0003 - and note it in public variable
            CLR  NEW_CTX    ; No break register context to show yet
            ; Copy interrupt jump table to RAM
            LDX  #ROM_JTAB  
            LDY  #RAM_JTAB  ; 
            LDW  #(3*7)     ; 7 JMPs is 21 bytes
            TFM  X+,Y+      ; Use 6309'S nice block-copy instruction.
            ; Init stack pointer (enables NMI)
            LDS  #(STACK_END-2)
            ; Init BIOS
            ; JSR  BIOS_INIT
            ; Init hardware peripherals            
            ; JSR  pa_init  ; Init VIA/SD card
            JSR  UT_INIT    ; Init serial UART
            ; JSR  VDP_INIT  ; Init graphics card, if any, do bootscreen             
            ANDCC #$AF      ; Enable IRQ and FIRQ interrupts
            ;ORCC  #$50      ; Disable IRQ and FIRQ interrupts            
            JMP  RAMTEST    ; TEST 1MB ONBOARD RAM            
            ; Warm start
WARMST      LDS  #(STACK_END-2)     ; Init stack pointer (enables NMI)                    
            LDY  #MSG_HELLO ; Bootloader title banner
            JSR  UT_PUTS    ; Start transmitting it via serial.

            ;JSR  RTC_SHOW   ; show current tickcount
            ;JMP  WARMST     ; RINSE AND REPEAT

            ; TODO: Try to boot from SD.. if couldnt boot, 
            JMP  MON_ENTRY  ; Start ML monitor.
; -----------------------------------------------------------------------------
; Entrypoint to ML Monitor
; -----------------------------------------------------------------------------
MON_ENTRY   LDA  NEW_CTX    ; Check if got a break context to show
            BEQ  MAINLOOP   ; If not, go to monitor mainloop.
            CLR  NEW_CTX
            JSR  SHOW_CTX   ; Show context.
            JMP  MAINLOOP
; -----------------------------------------------------------------------------
; ML Monitor Mainloop
; -----------------------------------------------------------------------------
MAINLOOP    ;JSR  con_svc    ; Console housekeeping service
            ;BEQ  ML_PAR     ; returns nonzero if we got something to do.

ML_GETKEY   JSR  UT_GETC    ; READ RX CHARACTER, IF ANY.
            BEQ  ML_GETKEY  ; LOOP UNTIL A CHARACTER IS RECEIVED.
            CMPA #CR        ; IF WE GET A CR, ECHO IT, FOLLOWED BY A LF.
            BNE  ML_ECHO
            JSR  UT_PUTC 
            LDA  #LF
ML_ECHO     STA  TMP_KEY    ; STASH PRESSED KEY FOR FURTHER CHECKING, THEN
            JSR  UT_PUTC    ; ECHO THE RECEIVED CHARACTER TO USER.
            LDA  TMP_KEY    ; DEPENDING ON KEY, MAYBE DO STUFF:
ML_K_TIL    CMPA #TILDE     ; '~': RUN RAM EXAMPLE PROGRAM, THEN BREAK.
            BNE  ML_K_DUMP
            JMP  V_RESET
ML_K_DUMP   CMPA #'.        ; '.': DUMP RAM $4000...$8000
            BNE  ML_K_TIM
            LDX  #$2000
            STX  DUMP_ADRS
            LDX  #$3000
            STX  EDUMP_ADRS
            JSR  HEXDUMP_BLOCK
ML_K_TIM    CMPA #'T        ; 'T': SHOW CURRENT TICKCOUNT
            BNE  ML_K_XFER
            JSR  RTC_SHOW
ML_K_XFER   CMPA #'X        ; 'X': Xfer S-Record file
            BNE  ML_END
            JSR  XFER
ML_END      BRA  MAINLOOP   
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
            LDY  #LINBUF    ; context string
            JSR  UT_PUTS
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
            JSR  UT_PUTS    
            RTS
;------------------------------------------------------------------------------
; HEX+ASCII DUMP MEM FROM DUMP_ADRS THROUGH EDUMP_ADRS 
;------------------------------------------------------------------------------
HEXDUMP_BLOCK
            LDX  DUMP_ADRS
            CMPX EDUMP_ADRS
            BGE  DONE_BLOCK
            BSR  HEXDUMP_LINE
            BRA  HEXDUMP_BLOCK
DONE_BLOCK  RTS    
;------------------------------------------------------------------------------
; Show current RTC tick count - uses y, x, a, tmp64_0
;------------------------------------------------------------------------------
MSG_TIME    FCB  LF,CR
            FCC  "Tick count: "  ; Startup banner
            FCB  0
RTC_SHOW    PSHS A,X,Y
            LDY  #MSG_TIME
            JSR  UT_PUTS
            ;JSR  UT_WAITTX  ; await transmission
            ; get current rtc tickcount and show it as hex
            LDX  #TMP64_0   ; get rtc tickcount
            JSR  RTC_GETTIX            
            LDX  #LINBUF            
            LDA  TMP64_0+0
            JSR  S_HEXA     ; hex$(A) -> linbuf
            LDA  TMP64_0+1
            JSR  S_HEXA     ; hex$(A) -> linbuf
            LDA  TMP64_0+2
            JSR  S_HEXA     ; hex$(A) -> linbuf
            LDA  TMP64_0+3
            JSR  S_HEXA     ; hex$(A) -> linbuf
            LDA  TMP64_0+4
            JSR  S_HEXA     ; hex$(A) -> linbuf
            LDA  TMP64_0+5
            JSR  S_HEXA     ; hex$(A) -> linbuf
            LDA  TMP64_0+6
            JSR  S_HEXA     ; hex$(A) -> linbuf
            LDA  TMP64_0+7
            STA  VDAT  
            JSR  S_HEXA     ; hex$(A) -> linbuf
            LDA  #LF
            STA  ,X+
            LDA  #CR
            STA  ,X+
            LDA  #0
            STA  ,X+
            LDY  #LINBUF
            JSR  UT_PUTS
            PULS A,X,Y
            RTS
;------------------------------------------------------------------------------
; Test CPU card's 1MB onboard SRAM using Bank #1 (CPU Address' $4000-$7FFF)
; Write an ascending 32-bit count to physical RAM from $002000 to $0FFFFF and 
; then read it back.
;
; write 4-byte repeating pattern to all 
; addresses within all ram banks
;------------------------------------------------------------------------------
MSG_RAMTEST FCC  "RAM TEST 1MB... "
            FCB  0
MSG_RAMGOOD FCC  "OK"
            FCB  LF,CR,0
MSG_RAMBAD  FCC  "FAIL AT $"
            FCB  0
RAMTEST     JSR  UT_CLRSCR
            LDY  #MSG_RAMTEST
            JSR  UT_PUTS
            LDA  #0         ; initial bank reg setting of test
WBANKLOOP   STA  MBANK_1    ; 
            CMPA #$00       ; Bank 0 is handled slightly differently:
            BEQ  WPARTIAL
            LDX  #$4000     ; If not first bank bank, write whole range 4000...7fff
            BSR  WADRSLOOP
WPARTIAL    LDX  #$6000     ; If first bank, write 6000...7fff to spare our vars
WADRSLOOP   STA  0,X        ; write A (bank idx) to ADRS X+0
            STA  1,X        ; write A to ADRS X+1
            STX  2,X        ; write X (CPU adrs) to ADRS X+2, X+3
            LEAX 4,X        ; let X = X + 4
            CMPX #$8000     ; end of bank?
            BNE  WADRSLOOP  ; continue within bank.
            INCA            ; Increment bank index
            CMPA #$40       ; if not done with banks,
            BNE  WBANKLOOP  ; keep writing patterns.
            LDA  #0         ; Time to read back. Set initial bank
RBANKLOOP   STA  MBANK_1
            CMPA #$00       ; Bank 0 handled slightly differently:
            BEQ  RPARTIAL
            LDX  #$4000     ; If not first bank bank, verify whole range 4000...7fff
            BSR  RADRSLOOP
RPARTIAL    LDX  #$6000     ; If first bank, write 6000...7fff to spare our vars
RADRSLOOP   LDB  0,X        ; check bank idx val at ADRS X+0
            LDB  1,X        
            LDY  2,X        ; check X (CPU adrs) at ADRS X+2, X+3    
            STB  TMP8_0     ; store retrieved value
            STA  TMP8_1     ; store expected value
            STY  TMP16_0    ; store retrieved 16-bit value
            STX  TMP16_1    ; store expected 16-bit value
            LDE  #0         ; innocent until proven guilty
            CMPA TMP8_0     ; compare retrieved byte to expected byte
            BEQ  RDIDBTEST
            ADDE #1         ; note byte test fail.
RDIDBTEST   CMPX TMP16_0    ; compare retrieved word to expected word.
            BEQ  WORD_OK
            ADDE #1         ; note word test fail
WORD_OK     CMPE #0
            BNE  RT_FAIL
RT_CONT     LEAX 4,X        ; One pattern was right, prepare for next.
            CMPX #$8000     ; If not at end of bank,
            BNE  RADRSLOOP  ; continue testing bank.
            INCA            ; Increment to next bank
            CMPA #$40       ; (Up to 1 MB)
            BNE  RBANKLOOP  ; test next bank.
            LDY  #MSG_RAMGOOD ; report ram test passed
            JSR  UT_PUTS
RT_END      LDA  SBANK_1    ; Restore memory bank #1 setting to prev val
            STA  MBANK_1
            JMP  WARMST      ; And we're done.  
RT_FAIL     LDY  #MSG_RAMBAD ; print 'FAIL AT $XXXX'
            JSR  UT_PUTS
            LDX  #LINBUF    ; Where XXXX is failing address
            LDA  TMP16_1
            JSR  S_HEXA
            LDA  TMP16_1+1
            JSR  S_HEXA
            JSR  S_EOL
            LDY  #LINBUF
            JSR  UT_PUTS
            JMP  RT_END
; -----------------------------------------------------------------------------
; Receives a Motorola S-Record file to RAM. ESC to quit, '.' to run.
; -----------------------------------------------------------------------------
MSG_XFER    FCC  "Send S-Record now. Press . to run, ESC to quit."
            FCB  LF,CR,0
MSG_DOT     FCC  "Calling sub."
            FCB  LF,CR,0
MSG_EDOT    FCC  "Sub. returned."
            FCB  LF,CR,0
MSG_BADREC  FCC  "<- Bad Rec"
            FCB  LF,CR,0
MSG_CR      FCB  LF,CR,0
MSG_XEND    FCC  "Leaving Xfer mode."
            FCB  LF,CR,0
MSG_COMP    FCC  "Xfer complete."
            FCB  LF,CR,0
XFER        LDY  #MSG_XFER
            JSR  UT_PUTS
            LDX  #LINBUF
KLOOP       JSR  UT_GETC    ; READ RX CHARACTER, IF ANY.
            BEQ  KLOOP      ; LOOP UNTIL A CHARACTER IS RECEIVED.
            CMPA #ESCAPE
            BEQ  X_END
            CMPA #CR
            BEQ  GOTCR
            CMPA #'.
            BEQ  GOTDOT
            STA  ,X+        ; Add char to linbuf (non-esc, non-dot, non-cr)
            JMP  KLOOP      
X_END       LDY  #MSG_XEND
            JSR  UT_PUTS
            RTS             ; END XFER MODE, RETURN TO MONITOR
GOTDOT      LDY  #MSG_DOT   ; Say we're starting the subroutine.
            JSR  UT_PUTS
            JSR  $2000      ; Call sub
            LDY  #MSG_EDOT  ; Say the sub ended
            JSR  UT_PUTS
            RTS
GOTCR       LDA  #0         ; Null-terminate the input line
            STA  ,X+
            LDX  #LINBUF
            JSR  S_LEN      ; get line length in D
            CMPD #4
            BLT  ENDPARSE   ; trash line if length is less than 4.            
            STD  TMP16_0    ; store length in tmp val
            LDX  #LINBUF    ; trash lines not starting with "S1"
            LDA  ,X+
            CMPA #'S
            BNE  ENDPARSE
            LDA  ,X+
            CMPA #'9
            BEQ  GOT_SEOF
            CMPA #'1
            BNE  ENDPARSE
            LDX  #(LINBUF+2) ; point to byte-count octet
            CLRA
            STA  SRECCHK
            JSR  SRECREAD  ; get bytecount
            STA  SRECBC    ; stash it for later
            LDY  #SRECBUF
            LDB  SRECBC
OCTLOOP     JSR  SRECREAD  ; read in all srec octets and convert into bytes 
            STA  ,Y+
            DECB
            BNE  OCTLOOP
            LDA  SRECCHK
            CMPA #$FF
            BEQ  GOODLINE
BADLINE     LDX  #LINBUF   ; show address from bad record and err msg
            LDA  SRECBUF+0
            JSR  S_HEXA
            LDA  SRECBUF+1
            JSR  S_HEXA
            LDA  #0
            STA  ,X+
            LDY  #LINBUF
            JSR  UT_PUTS
            LDY  #MSG_BADREC
            JSR  UT_PUTS
            LDX  #LINBUF
            JMP  KLOOP
GOODLINE    LDY  SRECBUF   ; get dest address in y
            LDX  #(SRECBUF+2) ; get src address in x
            LDB  SRECBC    ; get len of bytes to write 
            DECB           ; (minus adrs and csum)
            DECB
            DECB
XWRLOOP     LDA  ,X+
            STA  ,Y+
            DECB
            BNE  XWRLOOP                       
ENDPARSE    LDX  #LINBUF
            JMP  KLOOP
GOT_SEOF    LDY  #MSG_COMP  ; say we got final record of srec file
            JSR  UT_PUTS
            LDX  #LINBUF
            JMP  KLOOP
; -----------------------------------------------------------------------------
; read next octet of srec line into A and update checksum
; -----------------------------------------------------------------------------
SRECREAD:
    PSHS B
    CLRA
    JSR  READHEXDIGIT
    LSLA
    LSLA
    LSLA
    LSLA
    JSR  READHEXDIGIT
    ; update checksum
    TFR  A,B
    ADDB SRECCHK
    STB  SRECCHK
    PULS B
    RTS            

; OR next nybble of srec line into reg A
READHEXDIGIT:
    PSHS B
    PSHS A          ; save A for later    
    LDA  ,X+
    SUBA #'0'       ; move ascii 0 down to binary 0
    BMI READHEX_ERR
    CMPA #9
    BLE READHEX_OK  ; 0-9 found
    SUBA #7         ; drop 'A' down to 10
    CMPA #$F
    BLE READHEX_OK
READHEX_ERR:
    PULS A
    PULS B
    RTS
READHEX_OK:
    STA TMP8_0      ; store 4-bit value in temp
    PULS A          ; restore old value
    ORA TMP8_0      ; or the hex value
    PULS B
    RTS                    
;------------------------------------------------------------------------------
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
; End of main.asm
;------------------------------------------------------------------------------
