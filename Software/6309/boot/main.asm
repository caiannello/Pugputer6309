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
V_DZINST        EXTERN      ; mon.asm - machine code monitor
V_CBRK          EXTERN
V_SWI           EXTERN
MON_INIT        EXTERN
MON_ENTRY       EXTERN
NEW_CTX         EXTERN
V_NMI           EXTERN      ; time.asm - real-time interrupt
RTC_GETTIX      EXTERN
UT_INIT         EXTERN      ; serio.asm - serial port UART
UT_PUTC         EXTERN
UT_PUTS         EXTERN
UT_WAITTX       EXTERN
UT_CLRSCR       EXTERN
STXIE           EXTERN
S_HEXA          EXTERN      ; helpers.h
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
LINBUF          EXPORT
V_RESET         EXPORT
TMP8_0          EXPORT
TMP16_0         EXPORT
TMP8_1          EXPORT
TMP16_1         EXPORT
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
LINBUF          RMB  256    ; Misc text line buffer    
TMP8_0          RMB  1      ; Misc 8-bit value (used in ram test)
TMP16_0         RMB  2      ; Misc 16-bit value (used in ram test)
TMP8_1          RMB  1      ; Misc 8-bit value (used in ram test)
TMP16_1         RMB  2      ; Misc 16-bit value (used in ram test)
TMP64_0         RMB  8      ; Misc 64-bit value (used for tick counts)
STACK           RMB  512    ; System stack
STACK_END
    ENDSECT
;------------------------------------------------------------------------------
; ROM Code/Data - Section address  $F000 - $FF00
;------------------------------------------------------------------------------
    SECT code

; Memory bank registers 0..3 (Base address in defines.d)
; These are write-only, so we keep copies of 1 through 3 in SBANK_1...SBANK_3
MBANK_0     equ  BANK_BASE+0
MBANK_1     equ  BANK_BASE+1
MBANK_2     equ  BANK_BASE+2
MBANK_3     equ  BANK_BASE+3

; Bootloader definitions and ROM constants (See also defines.d)

MSG_HELLO   FCC  "Pugputer 6309 - Bootloader v0.0.2"  ; Startup banner
            FCB  LF,CR,0

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

; -----------------------------------------------------------------------------
; Default stubs for some configurable ISRs (Remaining handlers are in mon.asm,
;   serio.asm, and bios.asm)
; -----------------------------------------------------------------------------

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
            ; Warm start
            JMP  RAMTEST    ; TEST 1MB ONBOARD RAM

WARMST      LDS  #(STACK_END-2)     ; Init stack pointer (enables NMI)                    
            LDY  #MSG_HELLO ; Bootloader title banner
            JSR  UT_PUTS    ; Start transmitting it via serial.

            ;JSR  RTC_SHOW   ; show current tickcount
            ;JMP  WARMST     ; RINSE AND REPEAT

            ; TODO: Try to boot from SD.. if couldnt boot, 
            JMP  MON_ENTRY  ; Start ML monitor.
;------------------------------------------------------------------------------
; Show current RTC tick count - uses y, x, a, tmp64_0
;------------------------------------------------------------------------------
MSG_TIME    FCC  "Tick count: "  ; Startup banner
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
            ;JSR  UT_WAITTX  ; await transmission
            PULS A,X,Y
            RTS
;------------------------------------------------------------------------------
; Test CPU card's 1MB onboard SRAM using Bank #1 (CPU Address' $4000-$7FFF)
; Write an ascending 32-bit count to physical RAM from $002000 to $0FFFFF and 
; then read it back.
;------------------------------------------------------------------------------
MSG_RAMTEST FCC  "RAM TEST... "
            FCB  0

MSG_RAMGOOD FCC  "GOOD"
            FCB  LF,CR,0

MSG_RAMBAD  FCC  "FAIL"
            FCB  LF,CR,0

RAMTEST     ;PSHS A,B,X,Y,U,DP
            ;PSHSW 
            JSR  UT_CLRSCR
            LDY  #MSG_RAMTEST
            JSR  UT_PUTS
            ;JSR  UT_WAITTX

; write 4-byte repeating pattern to all 
; addresses within all ram banks

            LDA  #0         ; initial bank setting of test
WBANKLOOP   STA  MBANK_1    ; Set bank register.
            CMPA #$00       ; Bank 0 is handled slightly differently:
            BEQ  WPARTIAL
            LDX  #$4000     ; If subsequent bank, test whole range 4000...7fff
            BSR  WADRSLOOP
WPARTIAL    LDX  #$6000     ; If first bank, test partial range 6000...7fff to spare our vars
WADRSLOOP   
            STA  0,X        ; write A (bank idx) to ADRS X+0
            STA  1,X        ; write A to ADRS X+1
            STX  2,X        ; write X (CPU adrs) to ADRS X+2, X+3
            LEAX 4,X        ; let X = X + 4
            CMPX #$8000     ; end of bank?
            BNE  WADRSLOOP  ; continue within bank.
            INCA            ; Increment bank index
            CMPA #$40       ; not done with banks?
            BNE  WBANKLOOP  ; keep writing patterns.

; verify repeating pattern across all banks

            LDA  #0         ; initial bank setting of test
RBANKLOOP   STA  MBANK_1    ; Set bank register
            CMPA #$00       ; Bank 0 handled slightly differently.
            BEQ  RPARTIAL
            LDX  #$4000     ; test full bank for banks 1+
            BSR  RADRSLOOP
RPARTIAL    LDX  #$6000     ; test partial bank fpr bank 0
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
            ADDE #1         ; byte test fail.
RDIDBTEST   CMPX TMP16_0    ; compare retrieved word to expected word.
            BEQ  VERDICT
            ADDE #1         ; word test fail
VERDICT     CMPE #0
            BEQ  RDIDTEST
            LDY  #MSG_RAMBAD  ; output test fail
            JSR  UT_PUTS
            ;JSR  UT_WAITTX
            JMP  RT_SHOW_FAILURE 

RDIDTEST    LEAX 4,X        ; One pattern was right, prepare for next one.
            CMPX #$8000     ; end of bank?
            BNE  RADRSLOOP  ; continue testing bank
            INCA            ; Increment bank
            CMPA #$40       ; Up to 1 MB,
            BNE  RBANKLOOP  ; test next bank.

            LDY  #MSG_RAMGOOD ; report test pass
            JSR  UT_PUTS
            ;JSR  UT_WAITTX
            JMP  RT_END

RT_SHOW_FAILURE
            ; print tmp8_0, tmp16_0 and tmp8_1, tmp16_1 as hex
            LDX  #LINBUF
            LDA  TMP8_0
            JSR  S_HEXA
            LDA  TMP16_0
            JSR  S_HEXA
            LDA  TMP16_0+1
            JSR  S_HEXA

            LDA  TMP8_1
            JSR  S_HEXA
            LDA  TMP16_1
            JSR  S_HEXA
            LDA  TMP16_1+1
            JSR  S_HEXA
            
            LDA  #LF
            STA  ,X+
            LDA  #CR
            STA  ,X+
            LDA  #0
            STA  ,X+
            
            LDY  #LINBUF
            JSR  UT_PUTS
            ;JSR  UT_WAITTX

RT_END      ; done doing ram test  
            LDA  SBANK_1   ; Restore memory bank #1 setting to prev val
            STA  MBANK_1
            ;PULSW
            ;PULS DP,U,Y,X,B,A
            JMP WARMST
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
