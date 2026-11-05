;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
; VERSION: 0.1.0
;    FILE: main.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Reset/init, the RAM-resident ISR jump table, the SWI2 BIOS-call dispatcher,
; a lightweight TRAP/breakpoint fault handler, and the fixed hardware
; interrupt vector table.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
; Imported from other modules
;------------------------------------------------------------------------------
V_NMI           EXTERN      ; time.asm - real-time interrupt (wired direct)
UT_INIT         EXTERN      ; serio.asm
UT_PUTS         EXTERN
S_HEXA          EXTERN      ; helpers.asm
S_EOL           EXTERN
DEV_INIT        EXTERN      ; devio.asm
DEV_STDIO_ALIAS EXTERN
DEV_VC_DETECT   EXTERN
BIOS_DQUERY     EXTERN
BIOS_REG_DEV    EXTERN
BIOS_DEREG_DEV  EXTERN
BIOS_FOPEN      EXTERN
BIOS_FCLOSE     EXTERN
BIOS_PUTC       EXTERN
BIOS_PUTS       EXTERN
BIOS_PUT        EXTERN
BIOS_GETC       EXTERN
BIOS_GETS       EXTERN
BIOS_GET        EXTERN
BIOS_IOCTL      EXTERN
BIOS_NOTIMPL    EXTERN
BIOS_BLK_READ   EXTERN      ; sdcard.asm
BIOS_BLK_WRITE  EXTERN
BIOS_DOS        EXTERN      ; sdcard.asm: every resident-DOS call (codes B_FOPEN_NAME..)
BIOS_BANK_GET   EXTERN      ; banks.asm
BIOS_BLK_READ32  EXTERN     ; sdcard.asm
BIOS_BLK_WRITE32 EXTERN
BIOS_BANK_SET   EXTERN
BIOS_PAGE_ALLOC EXTERN
BIOS_PAGE_FREE  EXTERN
BIOS_PAGE_INFO  EXTERN
BIOS_PAGE_COPY  EXTERN
PAGE_INIT       EXTERN
BANKS_IDENTITY  EXTERN
SD_BOOT_TRY     EXTERN      ; sdcard.asm - tries an SD disk boot; returns
                             ; (falls through to LOADER_START) if none found
LOADER_START    EXTERN      ; loader.asm - boot prompt entry point
;------------------------------------------------------------------------------
; Exported for use by other modules
;------------------------------------------------------------------------------
JT_IRQ          EXPORT      ; RAM jump table IRQ slot -- serio.asm hooks it
; RAM vector table for a resident DOS's calls: NUM_DOS_JT plain 2-byte
; addresses, in function-code order (not JMP instructions -- BIOS_DOS JSRs
; indirect through them and the routine RTSes back, unlike RAM_JTAB's
; hardware-vector slots). SD_BOOT_TRY hands the table's address to DOS in X when
; it jumps there, and dos/dos.asm patches every slot before starting BASIC.
; Same "default in RAM at cold boot, patched at runtime" pattern RAM_JTAB/
; JT_IRQ already uses for UT_ISR.
JT_DOS          EXPORT
DOSMASK         EXPORT      ; BIOS_DOS scratch byte (sdcard.asm)
SBANK_1         EXPORT      ; the readable copies of bank registers 1..3 (banks.asm)
USER_RAM        EXPORT      ; first byte of RAM the BIOS doesn't use
BC_OK           EXPORT      ; devio.asm's handlers tail-call these to store
BC_ERR          EXPORT      ; a result into the SWI2 frame before returning
RTC_TICKS       EXPORT      ; time.asm's public tick count + its mutex pair
RTC_TICKS_PRIV  EXPORT
RTC_MTX         EXPORT
RTC_SET         EXPORT
;------------------------------------------------------------------------------
; Public variables - Section address $0000 (direct page)
;------------------------------------------------------------------------------
    SECT ram_start
USER_RAM        RMB  2      ; start adrs of free RAM not used by the BIOS
JTAB_ADRS        RMB  2      ; start adrs of the RAM ISR jump table
RTC_TICKS        RMB  8      ; number of 1/16 sec ticks since poweron
RTC_TICKS_PRIV   RMB  8
RTC_MTX          RMB  1      ; mutex for the above (see time.asm)
RTC_SET          RMB  1
SBANK_1          RMB  1      ; readable copies of the write-only bank regs
SBANK_2          RMB  1
SBANK_3          RMB  1
RAM_JTAB                     ; BEGIN RAM ISR JUMP TABLE -------------------
JT_DZINST        RMB  3      ; TRAP: illegal instruction / divide by zero
JT_SW3           RMB  3      ; unused, reserved
JT_SW2           RMB  3      ; BIOS call dispatcher
JT_FIRQ          RMB  3      ; unused, reserved (future VIA/video)
JT_IRQ           RMB  3      ; shared IRQ -- UART claims this at init
JT_SWI           RMB  3      ; software breakpoint -- END RAM JUMP TABLE --
JT_DOS          RMB  2*NUM_DOS_JT ; DOS call vectors (see BIOS_DOS in sdcard.asm)
DOSMASK         RMB  1      ; BIOS_DOS scratch: which results the call returns
    ENDSECT
;------------------------------------------------------------------------------
; Private variables - Section address $0100
;------------------------------------------------------------------------------
    SECT bss
FAULTBUF        RMB  8      ; scratch for the fault handler's hex PC + EOL
    ENDSECT
;------------------------------------------------------------------------------
; ROM Code - Section address $F000 - $FF00
;------------------------------------------------------------------------------
    SECT code

MSG_HELLO   FCC  "Pugputer 6309 BIOS v0.1.0"
            FCB  LF,CR,0
; -----------------------------------------------------------------------------
; Interrupt Service Routines. RESET and NMI are hard-coded in the fixed
; hardware vector table below and can't be redirected. The rest are jumped
; to indirectly through RAM_JTAB (copied from ROM_JTAB below at cold start)
; so other code can hook or replace a handler at runtime: save the existing
; target from the jump table before overwriting it, and chain to it if the
; interrupt turns out not to be yours (serio.asm's SNEXTISR does exactly
; this for IRQ).
; -----------------------------------------------------------------------------

; TRAP vector: illegal opcode or divide-by-zero. BITMD distinguishes the two
; (and, as a side effect of testing it, clears the flag) -- see "Using the
; TRAP Vector" in the 6309 reference.

V_DZINST    BITMD #%01000000    ; MD.6: illegal opcode trap flag
            LBEQ FAULT_DIV0     ; clear -- wasn't an illegal opcode
            LDX  #FAULTMSG_ILL
            LBRA FAULT_COMMON
FAULT_DIV0  LDX  #FAULTMSG_DIV0
            LBRA FAULT_COMMON

; Software breakpoint (SWI). Not a debugger -- just reports where and drops
; back to the boot prompt. A real monitor can replace this vector later.

V_SWI       LDX  #FAULTMSG_SWI
            LBRA FAULT_COMMON   ; (this used to "fall through" -- into the message
                                 ; strings below, executing them as code)

FAULTMSG_ILL  FCC  "*** ILLEGAL OPCODE at $"
              FCB  0
FAULTMSG_DIV0 FCC  "*** DIVIDE BY ZERO at $"
              FCB  0
FAULTMSG_SWI  FCC  "*** BREAKPOINT at $"
              FCB  0

FAULT_COMMON
            LDD  SWI2_PC,S      ; where it happened (native-mode frame), taken before
            LDS  #STACK_END     ; S is replaced: the crashed program's stack, and its
            PSHS D              ; direct page and bank mapping, may be what broke
            TFR  X,Y
            CLRA
            TFR  A,DP
            JSR  BANKS_IDENTITY
            JSR  UT_PUTS
            LDX  #FAULTBUF
            PULS D
            JSR  S_HEXA         ; PC high byte
            TFR  B,A
            JSR  S_HEXA         ; PC low byte
            JSR  S_EOL
            LDY  #FAULTBUF
            JSR  UT_PUTS
            ANDCC #$AF          ; interrupts on: the console needs them
            LDA  #B_EXIT        ; not resumable. With a DOS in RAM, restart the shell
            SWI2                ; (this doesn't come back) ...
            JMP  LOADER_START   ; ... else back to the boot prompt

; Default stubs for the vectors nothing uses yet

V_SW3       RTI             ; SOFTWARE INTERRUPT 3 - unused
V_FIRQ      RTI             ; FIRQ - unused (future VIA/video)
V_IRQ_STUB  RTI             ; default IRQ target before UT_INIT installs
                             ; its own handler
; -----------------------------------------------------------------------------
; BIOS call dispatcher (SWI2). See devio.asm's file header and defines.d's
; SWI2_* equates for the calling convention: every BIOS_* handler reads its
; arguments from, and writes its result back into, the SWI2 stack frame
; that S still points at when it's called (SWI2 pushes all registers but
; does not disable IRQ/FIRQ, so a handler that needs to poll a device is
; not blocking anything else that services interrupts).
; -----------------------------------------------------------------------------
; NOTE (fixed): this dispatcher and BC_OK/BC_ERR below must never JSR into
; a handler/epilogue and then RTI at the call site -- a JSR pushes its own
; 2-byte return address *on top of* the SWI2 register frame, so every
; SWI2_* offset used inside the callee (and inside BC_OK/BC_ERR, which
; read/write SWI2_A/SWI2_CC directly) would be off by 2 from that point on.
; Every step here is JMP (never touches the stack) all the way through to
; BC_OK/BC_ERR, which RTI directly -- so S is exactly what SWI2 left it at
; for the whole chain, and the SWI2_* offsets used throughout devio.asm's
; handlers (as documented, unchanged) are correct as written.
V_SW2       LDA  SWI2_A,S       ; caller's function code
            CMPA #NUM_BCALLS
            BLO  SW2_OK
            LDA  #ERR_BADFN
            JMP  BC_ERR
SW2_OK      CMPA #B_BANK_GET
            BHS  SW2_EXT        ; the calls added after the DOS range: EXT_TAB
            CMPA #B_FOPEN_NAME  ; codes from here up to there are the resident DOS's:
            LBHS BIOS_DOS       ; one generic handler, not a table entry each
            LSLA                ; word index into BIOS_TAB
            LDX  #BIOS_TAB
            JMP  [A,X]          ; indexed-indirect, accumulator offset:
                                ; dispatch straight into the handler
SW2_EXT     SUBA #B_BANK_GET
            LSLA
            LDX  #EXT_TAB
            JMP  [A,X]

; Shared epilogues every BIOS_* handler in devio.asm tail-calls (JMP, not
; JSR) as its last step. Writing into the stack frame is what actually
; matters here: in native mode RTI restores registers FROM this frame, so a
; result left only in a live register would simply be discarded.

BC_OK       LDA  #ERR_OK
            STA  SWI2_A,S
            AIM  #$FE,SWI2_CC,S
            RTI
BC_ERR      STA  SWI2_A,S       ; caller already put the error code in A
            OIM  #$01,SWI2_CC,S
            RTI

; Jump table indexed by BIOS function code * 2 (see defines.d B_* equates).
; Five reserved, filesystem-shaped calls share one "not supported" stub
; until an SD driver exists to give them meaning.

BIOS_TAB    FDB  BIOS_DQUERY     ; $00 B_DQUERY
            FDB  BIOS_REG_DEV    ; $01 B_REG_DEV
            FDB  BIOS_DEREG_DEV  ; $02 B_DEREG_DEV
            FDB  BIOS_NOTIMPL    ; $03 B_FSTAT
            FDB  BIOS_NOTIMPL    ; $04 B_FDIR
            FDB  BIOS_FOPEN      ; $05 B_FOPEN
            FDB  BIOS_FCLOSE     ; $06 B_FCLOSE
            FDB  BIOS_NOTIMPL    ; $07 B_FDELETE
            FDB  BIOS_NOTIMPL    ; $08 B_FMOVE
            FDB  BIOS_PUTC       ; $09 B_PUTC
            FDB  BIOS_PUTS       ; $0A B_PUTS
            FDB  BIOS_PUT        ; $0B B_PUT
            FDB  BIOS_GETC       ; $0C B_GETC
            FDB  BIOS_GETS       ; $0D B_GETS
            FDB  BIOS_GET        ; $0E B_GET
            FDB  BIOS_IOCTL      ; $0F B_IOCTL
            FDB  BIOS_NOTIMPL    ; $10 B_FSEEK
            FDB  BIOS_BLK_READ   ; $11 B_BLK_READ
            FDB  BIOS_BLK_WRITE  ; $12 B_BLK_WRITE

; The calls numbered above the DOS range, from B_BANK_GET up: banking
; (banks.asm), then the 32-bit block calls (sdcard.asm).
EXT_TAB     FDB  BIOS_BANK_GET    ; B_BANK_GET
            FDB  BIOS_BANK_SET    ; B_BANK_SET
            FDB  BIOS_PAGE_ALLOC  ; B_PAGE_ALLOC
            FDB  BIOS_PAGE_FREE   ; B_PAGE_FREE
            FDB  BIOS_PAGE_INFO   ; B_PAGE_INFO
            FDB  BIOS_PAGE_COPY   ; B_PAGE_COPY
            FDB  BIOS_BLK_READ32  ; B_BLK_READ32
            FDB  BIOS_BLK_WRITE32 ; B_BLK_WRITE32
EXT_TAB_END
    IFNE (EXT_TAB_END-EXT_TAB)-2*(NUM_BCALLS-B_BANK_GET)
    ERROR "EXT_TAB must have one entry per call from B_BANK_GET up (see defines.d)"
    ENDC

; -----------------------------------------------------------------------------
; This ROM template gets copied to RAM_JTAB during cold start (see V_RESET)
; so the vectors it covers can be hooked/replaced at runtime.
; -----------------------------------------------------------------------------
ROM_JTAB    JMP  V_DZINST
            JMP  V_SW3
            JMP  V_SW2
            JMP  V_FIRQ
            JMP  V_IRQ_STUB
            JMP  V_SWI
ROM_JTAB_END

; -----------------------------------------------------------------------------
; ROM template for the DOS file-API table (JT_DOS_OPEN..JT_DOS_CLOSE),
; copied to RAM alongside ROM_JTAB during cold start. Defaults every slot
; to a clean "no DOS present" error rather than an address into whatever
; garbage happens to be in RAM, so LOAD/SAVE fail with a normal BASIC
; error on any boot path that never runs dos/dos.asm (e.g. the
; hijack-based basic309_demo) instead of jumping into nowhere. Plain
; 2-byte addresses, not JMP instructions -- sdcard.asm's handlers JSR
; indirect through these and expect a normal RTS back (see DOS_NOTPRESENT
; below, and its handlers' own comments for why this must never RTI).
; -----------------------------------------------------------------------------
; (No literal template table any more: V_RESET fills the NUM_DOS_JT slots with
; a loop, so adding a DOS call only means adding its JT_DOS_* slot -- there is
; no hand-counted list of FDBs to keep in sync. NUM_DOS_JT comes from the
; call-code range in defines.d.)

; A plain subroutine (RTS, not RTI/JMP BC_ERR) -- its caller (sdcard.asm's
; BIOS_FOPEN_NAME/etc.) is what owns the SWI2 frame and must be the only
; thing that finishes it, exactly like every other BIOS_* handler.
DOS_NOTPRESENT
            LDA  #ERR_NOTSUP
            ORCC #$01
            RTS
; -----------------------------------------------------------------------------
; Reset Vector Entrypoint - Initialize system
; -----------------------------------------------------------------------------
V_RESET     LDMD #$01       ; Enable 6309 native mode
            ; NOTE (fixed): TFR only moves between named registers -- there
            ; is no immediate-to-register form, so a literal "TFR 0,DP"
            ; isn't "transfer the constant zero" but assembles with source
            ; register code $C, one of the 6309's reserved/unused TFR
            ; codes (see hd6309_core.cpp's get_reg_by_code): that reads
            ; back as $FFFF, truncated to $FF for the 8-bit DP destination.
            ; DP silently ended up $FF instead of $00 on every boot as a
            ; result -- undetected until now because nothing previously
            ; depended on a direct-page BIOS variable's actual value
            ; (basic309 sets its own DP explicitly, masking it downstream).
            LDA  #$00       ; Map RAM physical adrs $000000
            TFR  A,DP       ; Set direct page to Public vars (A is known $00)
            STA  MBANK_0    ; ..to CPU adrs $0000
                             ; (and keep it that way, else things will break.)
            LDX  #0         ; Zero all RAM the BIOS uses ($0000..EndOfVars),
            CLR  ,X         ; using the 6309 block-move instruction to
            LDY  #0         ; replicate that single zeroed byte forward --
            LDW  #EndOfVars ; about 4x faster than a byte-at-a-time loop.
            TFM  X,Y+
            ; Init stack pointer (must be valid before any interrupt, incl.
            ; NMI, which is non-maskable and could fire immediately -- the
            ; 6309 holds NMI off until S is first loaded)
            LDS  #STACK_END
            ; Map memory bank registers 1-3 to the first 4 physical pages
            ; (and keep readable copies: the registers are write-only)
            JSR  BANKS_IDENTITY
            LDX  #EndOfVars ; Note the start of free RAM in a public var
            STX  <USER_RAM
            LDX  #RAM_JTAB
            STX  <JTAB_ADRS
            ; Copy the ISR jump table template to RAM
            LDX  #ROM_JTAB
            LDY  #RAM_JTAB
            LDW  #(ROM_JTAB_END-ROM_JTAB)
            TFM  X+,Y+
            ; Point every DOS file-API slot at DOS_NOTPRESENT until a
            ; disk-resident DOS patches them (dos/dos.asm)
            LDX  #JT_DOS
            LDY  #NUM_DOS_JT
DJ_FILL     LDD  #DOS_NOTPRESENT
            STD  ,X++
            LEAY -1,Y
            BNE  DJ_FILL
            JSR  PAGE_INIT      ; banks.asm: probe the installed RAM, build the page map
            JSR  DEV_INIT       ; devio.asm: clear device table, add F_NULL
            JSR  UT_INIT        ; serio.asm: UART + adds F_UART
            JSR  DEV_STDIO_ALIAS
            JSR  DEV_VC_DETECT  ; devio.asm: the video card, as F_VDP, if it's there
            ANDCC #$AF          ; Enable IRQ and FIRQ interrupts
            LDY  #MSG_HELLO
            JSR  UT_PUTS
            JSR  SD_BOOT_TRY    ; tries a disk boot; only returns if none
                                 ; found (see sdcard.asm)
            JMP  LOADER_START
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; Private variables (system stack) - deliberately the LAST bss content
; linked (see linker_script / compile order), so EndOfVars marks the true
; end of all BIOS-reserved RAM across every module's bss.
;------------------------------------------------------------------------------
    SECT bss
STACK       RMB  512
STACK_END
EndOfVars
    ENDSECT
;------------------------------------------------------------------------------
; Interrupt vectors
;------------------------------------------------------------------------------
    SECT intvect
            FDB  JT_DZINST  ; $FFF0 TRAP: illegal instruction / div by zero
            FDB  JT_SW3     ; $FFF2 SWI3
            FDB  JT_SW2     ; $FFF4 SWI2 (BIOS call)
            FDB  JT_FIRQ    ; $FFF6 FIRQ
            FDB  JT_IRQ     ; $FFF8 IRQ
            FDB  JT_SWI     ; $FFFA SWI
            FDB  V_NMI      ; $FFFC NMI -- wired directly, not via RAM_JTAB
            FDB  V_RESET    ; $FFFE RESET -- wired directly, not via RAM_JTAB
    ENDSECT
;------------------------------------------------------------------------------
; End of main.asm
;------------------------------------------------------------------------------
