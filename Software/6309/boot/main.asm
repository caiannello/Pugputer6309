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
V_DZINST        EXTERN      ; mon.asm
V_CBRK          EXTERN
V_SWI           EXTERN
V_NMI           EXTERN      ; time.asm
MON_INIT        EXTERN
MON_ENTRY       EXTERN
NEW_CTX         EXTERN
V_SW2           EXTERN      ; bios.asm
BIOS_INIT       EXTERN
UT_INIT         EXTERN      ; serio.asm
UT_PUTC         EXTERN
UT_PUTS         EXTERN
STXIE           EXTERN
EndOfVars       EXTERN      ; provided by linker, start of unused RAM
;------------------------------------------------------------------------------
; Stuff exported for use by other modules
;------------------------------------------------------------------------------
RTC_TICKS       EXPORT      ; Number of 1/16 sec ticks since poweron or epoch
RTC_TICKS_PRIV  EXPORT
RTC_MTX         EXPORT      ; Mutex for the above
RTC_SET         EXPORT      ; Semaphore to update private val from public val
JT_FIRQ         EXPORT      ; RAM jump to ISR for FIRQ - video HBLANK, VBLANK
JT_IRQ          EXPORT      ; RAM jump to ISR for IRQ - Serial, VIA, OPL3
JT_CBRK         EXPORT      ; RAM jump to ISR for user break (Ctrl-C)
;------------------------------------------------------------------------------
; Public variables - Section address $0000
;------------------------------------------------------------------------------
    SECT ram_start           
WARM_ST         RMB  1      ; If not $55 on reset, we do a cold start
USER_RAM        RMB  2      ; Start adrs of free RAM not used by bootloader
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
STACK           RMB  1024   ; System stack
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

E_MSG       FCC  "Hello, World!"
            FCB  0            
PRG_EXAMP   LDY  #E_MSG
            ;JSR  CON_PUTS   ; Show hello message
            FCB  $15        ; Cause an illegal instruction interrupt
            SWI             ; Cause a software break
EXAMP_ADRS  EQU  $4000      ; examp prg loads to this RAM address
END_EXAMP

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
; way, this should probably be reimplemented as a doubly-linked list.
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

            ; Setup bank registers to first 4 pages of RAM

            LDA  #$00       ; Map RAM physical adrs $000000
            STA  MBANK_0    ; ..to CPU adrs $0000 
                            ; (and keep it that way, else things will break.)
            LDA  #$01       ; Map RAM $004000
            STA  MBANK_1    ; ..to CPU adrs $4000
            STA  <SBANK_1   ; make a readable copy of this register setting
            LDA  #$02       ; Map RAM $008000
            STA  MBANK_2    ; ..at CPU adrs $8000
            STA  <SBANK_2   ; make readable copy of this reg
            LDA  #$03       ; Map RAM $00C000
            STA  MBANK_3    ; ..at CPU adrs $C000            
            STA  <SBANK_3   ; make readable copy of this reg

            LDA  <WARM_ST   ; Get warm start flag
            CMPA #$55       ; and if its $55, 
            BEQ  WARMST     ; skip the cold-start initialization.

COLDST      LDX  #0         ; Zero all public and private vars
            LDY  #0    
            LDW  #(EndOfVars)
            TFM  x,y+

            ; init some helpful public vars

            LDX  #EndOfVars ; Get start address of free RAM,
            STX  <USER_RAM  ; and note it in public variable
            LDA  #$55       
            STA  <WARM_ST   ; We'll do a warm start next time
            CLR  NEW_CTX    ; No break register context to show yet

            ; Copy interrupt jump table to RAM

            LDX  #ROM_JTAB  
            LDY  #RAM_JTAB  ; 
            LDW  #(3*7)     ; 7 JMPs is 21 bytes
            TFM  X+,Y+      ; Use 6309'S nice block-copy instruction.

            ; Copy example program to RAM

            LDX  #PRG_EXAMP 
            LDY  #EXAMP_ADRS     
            LDW  #(END_EXAMP-PRG_EXAMP)
            TFM  X+,Y+    

            LDS  #(STACK_END-1)     ; Init stack pointer (enables NMI)
            
            ; Init BIOS
            JSR  BIOS_INIT
            ; Init hardware peripherals
            
            ; JSR  pa_init  ; Init VIA/SD card
            JSR  UT_INIT    ; Init serial UART
            ; JSR  VD_INIT  ; Init video card
            
            ANDCC #$AF      ; Enable IRQ and FIRQ interrupts

            ; Warm start

            ; DEBUG - try to repeatedly reinit comms
            ; and send a message.
            ; (uart chip-select isn't acting right)

WARMST      LDA  #SUARTCTL  ; Initialize UART baud, parity, etc. (defines.d)
            STA  UT_CTL
            LDA  #SUARTCMD
            STA  UT_CMD
            LDY  #MSG_HELLO ; Bootloader title banner
            JSR  UT_PUTS
WAITTX      LDA  STXIE
            BNE  WAITTX            
            JMP  WARMST
            ; TODO: Bootloader shouldnt need to go through the bios fcns
            ; table since we are compiled along with the bios code.

            ; TODO: Try to boot from SD.. if couldnt boot, 
            JMP  MON_ENTRY  ; Start ML monitor.

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
