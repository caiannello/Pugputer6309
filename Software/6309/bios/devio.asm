;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: devio.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; The device driver table and the BIOS call handler subroutines that
; main.asm's SWI2 dispatcher indexes into (BIOS_TAB). Every handler here
; follows the same convention: on entry, S points at the interrupted CC
; (the SWI2 stack frame -- see SWI2_* offsets in defines.d), and any result
; must be written back into that frame (via BC_OK/BC_ERR, both in main.asm)
; rather than left in a live register, since RTI restores from the frame.
;
; A device ref and a fileref are the same number space: built-in devices
; (the UART, the null device) are usable directly as filerefs with no open
; needed, since they carry no per-open state. B_FOPEN/B_FCLOSE exist for
; forward compatibility with a future file-backed device (e.g. SD) that DOES
; need per-open state; for v1 they just validate the device ref.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
DEV_INIT        EXPORT
DEV_STDIO_ALIAS EXPORT
DEV_VC_DETECT   EXPORT
CON_VIDEO       EXPORT       ; nonzero: the console is the video card
CON_PUTS        EXPORT       ; Y=string: to the UART, and the card if it's the console
CON_KEY         EXPORT       ; -> carry clear if a key was waiting on the card
DEV_REGISTER    EXPORT       ; B=devref,X=read,Y=write,U=ioctl -> A=status,C
DEV_DEREGISTER  EXPORT       ; B=devref -> A=status, carry
BIOS_DQUERY     EXPORT
BIOS_REG_DEV    EXPORT
BIOS_DEREG_DEV  EXPORT
BIOS_FOPEN      EXPORT
BIOS_FCLOSE     EXPORT
BIOS_PUTC       EXPORT
BIOS_PUTS       EXPORT
BIOS_PUT        EXPORT
BIOS_GETC       EXPORT
BIOS_GETS       EXPORT
BIOS_GET        EXPORT
BIOS_IOCTL      EXPORT
BIOS_NOTIMPL    EXPORT       ; shared stub for FSTAT/FDIR/FDELETE/FMOVE/FSEEK
;------------------------------------------------------------------------------
BC_OK       EXTERN           ; main.asm: write ERR_OK+carry-clear to frame
BC_ERR      EXTERN           ; main.asm: A already holds error code
S_LEN       EXTERN           ; helpers.asm
UT_READ     EXTERN           ; serio.asm
UT_IOCTL    EXTERN
UT_PUTS     EXTERN
;------------------------------------------------------------------------------
    SECT bss
;------------------------------------------------------------------------------
DEVTAB      RMB  NUM_DEVICES*sizeof{devdrv}

DR_TMP_READ  RMB 2           ; DEV_REGISTER scratch (see comment there for why)
DR_TMP_WRITE RMB 2
DR_TMP_IOCTL RMB 2

PUTC_SCRATCH RMB 1           ; 1-byte buffer for B_PUTC's single-char write
GETC_SCRATCH RMB 1           ; 1-byte buffer for B_GETC's single-char read

GETS_DST     RMB 2           ; B_GETS loop state
GETS_REMAIN  RMB 2
GETS_READFN  RMB 2

CON_VIDEO    RMB 1           ; nonzero: stdio is the video card (DEV_VC_DETECT)
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
; B=devref. Returns X=&DEVTAB[devref] with carry clear if devref is in range
; and its slot is registered, else carry set (X undefined). Trashes A,B.
;------------------------------------------------------------------------------
DEV_ENTRY   CMPB #NUM_DEVICES
            BHS  DE_BAD
            LDA  #sizeof{devdrv}
            MUL              ; D = devref * sizeof{devdrv}
            LDX  #DEVTAB
            LEAX D,X
            LDA  devdrv.flags,X
            BITA #1
            BEQ  DE_BAD      ; slot not registered
            ANDCC #$FE
            RTS
DE_BAD      ORCC #$01
            RTS
;------------------------------------------------------------------------------
; Zero the device table, then register the built-in null device at F_NULL.
; Called once at cold boot, before anything else touches DEVTAB.
;------------------------------------------------------------------------------
DEV_INIT    LDX  #DEVTAB
DI_LOOP     CMPX #DEVTAB+(NUM_DEVICES*sizeof{devdrv})
            BHS  DI_DONE
            CLR  devdrv.flags,X
            LEAX sizeof{devdrv},X
            BRA  DI_LOOP
DI_DONE     LDB  #F_NULL
            LDX  #NUL_READ
            LDY  #NUL_WRITE
            LDU  #0
            JSR  DEV_REGISTER
            RTS
;------------------------------------------------------------------------------
NUL_READ    LDY  #0          ; never anything to read
            RTS
NUL_WRITE   RTS              ; discard silently, "accept" instantly
;------------------------------------------------------------------------------
; Is the video card on the bus? If so it is registered as F_VDP, so B_DQUERY
; reports it (bit 9). If the card says it is to be the console (VC_ST_CONSOLE:
; the firmware always does, the emulator when it has a window), it is reset, and
; stdin, stdout and stderr become it: see CON_READ and VC_WRITE. If not, its slot
; takes the null device's routines, and the console stays on the UART. Called once
; at boot, after DEV_STDIO_ALIAS.
;
; Its last two registers identify it: ID reads 'V', VERSION $11 (or later). Only
; reads: a write would wake the emulator's video window. With no card there, a
; read gets what the bus floats at (on the machine, most likely the address's
; low byte, the instruction's last) or, in the emulator, the RAM underneath --
; not that pair.
;
; The card may not be answering yet: at power-on its RP2350 starts with the CPU,
; and keeps its level shifters off the bus until its firmware is running (some
; tens of ms). So the ID is looked for again and again, for about half a second
; (VC_WAKE spells of $FFFF polls, ~15 cycles each at 3.58MHz), before deciding
; there's no card -- a boot without one is that much slower.
;------------------------------------------------------------------------------
DEV_VC_DETECT
            LDB  #VC_WAKE
VD_SPELL    LDW  #$FFFF
VD_POLL     LDA  VCARD_BASE+VC_ID_REG
            CMPA #'V
            BEQ  VD_ID
            DECW
            BNE  VD_POLL
            DECB
            BNE  VD_SPELL
            RTS              ; no card
VD_ID       LDA  VCARD_BASE+VC_VER_REG
            CMPA #VC_VERSION_MIN
            BLO  VD_NONE
            CMPA #$7F        ; (a version, not the bus floating high)
            BHI  VD_NONE
            LDA  VCARD_BASE+VC_STATUS_REG
            BITA #VC_ST_CONSOLE
            BNE  VD_CONSOLE
            LDB  #F_VDP
            LDX  #NUL_READ
            LDY  #NUL_WRITE
            LDU  #0
            JSR  DEV_REGISTER
VD_NONE     RTS
VD_CONSOLE  LDA  #VC_RESET       ; (a clean screen, also when a key restarted the boot)
            STA  VCARD_BASE+VC_CTRL_REG
            INC  CON_VIDEO
            LDB  #F_VDP
            LDX  #VC_READ
            LDY  #VC_WRITE
            LDU  #0
            JSR  DEV_REGISTER
            LDB  #F_STDERR       ; F_STDERR, F_STDIN, F_STDOUT
VD_ALIAS    PSHS B
            LDX  #CON_READ
            LDY  #VC_WRITE
            LDU  #UT_IOCTL
            JSR  DEV_REGISTER
            PULS B
            DECB
            BNE  VD_ALIAS
            RTS
;------------------------------------------------------------------------------
; The video card as a character device. devdrv.write: X=buf, Y=len: each byte is
; a command for the card's terminal, which parses the ANSI sequences itself.
;------------------------------------------------------------------------------
VC_WRITE    PSHS A,X,Y
VW_LOOP     CMPY #0
            BEQ  VW_DONE
VW_WAIT     LDA  VCARD_BASE+VC_STATUS_REG
            BITA #VC_ST_FULL
            BNE  VW_WAIT
            LDA  #VC_C_TERM
            STA  VCARD_BASE+VC_CMD_REG
            LDA  ,X+
            STA  VCARD_BASE+VC_CMD_REG
            LEAY -1,Y
            BRA  VW_LOOP
VW_DONE     PULS A,X,Y,PC
;------------------------------------------------------------------------------
; devdrv.read: X=buf, Y=most wanted -> Y=how many: the bytes waiting on the card,
; which are what was typed at its keyboard (arrows and the like as a terminal
; sends them) and its terminal's replies. None while a program has the keys.
;------------------------------------------------------------------------------
VC_READ     LDW  #0
            LDA  VCARD_BASE+VC_INCTRL_REG
            BITA #VC_TAKE_KEYS
            BNE  VR_DONE
VR_LOOP     CMPR W,Y
            BEQ  VR_DONE
            LDA  VCARD_BASE+VC_STATUS_REG
            BITA #VC_ST_KEY
            BEQ  VR_DONE
            LDA  VCARD_BASE+VC_KEYCHAR_REG
            STA  ,X+
            INCW
            BRA  VR_LOOP
VR_DONE     TFR  W,Y
            RTS
;------------------------------------------------------------------------------
; stdin when the card is the console: the card's keyboard, or else the UART.
;------------------------------------------------------------------------------
CON_READ    PSHS X,Y
            BSR  VC_READ
            CMPY #0
            BNE  CR_GOT
            PULS X,Y
            JMP  UT_READ
CR_GOT      LEAS 4,S
            RTS
;------------------------------------------------------------------------------
; Y=a NUL-terminated string, for ROM code's own messages (the banner, a crash):
; to the UART always, and to the screen too when the card is the console.
;------------------------------------------------------------------------------
CON_PUTS    JSR  UT_PUTS
            TST  CON_VIDEO
            BEQ  CP_DONE
            PSHS D,X,Y
            TFR  Y,X
            JSR  S_LEN
            TFR  D,Y
            BSR  VC_WRITE
            PULS D,X,Y
CP_DONE     RTS
;------------------------------------------------------------------------------
; Takes a byte typed at the card's keyboard, if the card is the console and there
; is one. -> carry clear if so.
;------------------------------------------------------------------------------
CON_KEY     TST  CON_VIDEO
            BEQ  CK_NO
            PSHS X,Y
            LDX  #GETC_SCRATCH
            LDY  #1
            BSR  VC_READ
            CMPY #0
            PULS X,Y
            BEQ  CK_NO
            ANDCC #$FE
            RTS
CK_NO       ORCC #$01
            RTS
;------------------------------------------------------------------------------
; Copy the UART's driver entry (F_UART, already registered by serio.asm's
; UT_INIT) into the stdio aliases. Called once at boot, after UT_INIT.
;------------------------------------------------------------------------------
DEV_STDIO_ALIAS
            PSHS X,Y
            LDX  #DEVTAB+(F_UART*sizeof{devdrv})
            LDY  #DEVTAB+(F_STDOUT*sizeof{devdrv})
            LDW  #sizeof{devdrv}
            TFM  X+,Y+
            LDX  #DEVTAB+(F_UART*sizeof{devdrv})
            LDY  #DEVTAB+(F_STDIN*sizeof{devdrv})
            LDW  #sizeof{devdrv}
            TFM  X+,Y+
            LDX  #DEVTAB+(F_UART*sizeof{devdrv})
            LDY  #DEVTAB+(F_STDERR*sizeof{devdrv})
            LDW  #sizeof{devdrv}
            TFM  X+,Y+
            PULS X,Y,PC
;------------------------------------------------------------------------------
; B=devref, X=read fn, Y=write fn, U=ioctl fn (0 if none). -> A=status,carry.
; Stages the three incoming pointers to bss scratch before the MUL/LEAX
; address computation rather than juggling them through PSHS/PULS, since
; PSHS/PULS always transfer registers in a fixed hardware priority order
; (independent of how they're listed in the mnemonic) -- reusing one
; register name across three separate single-register PULS calls to "peel
; off" a multi-register push is a correctness trap, not just a style choice.
;------------------------------------------------------------------------------
DEV_REGISTER
            CMPB #NUM_DEVICES
            BLO  DR_INRANGE
            LDA  #ERR_BADDEV
            ORCC #$01
            RTS
DR_INRANGE  STX  DR_TMP_READ
            STY  DR_TMP_WRITE
            STU  DR_TMP_IOCTL
            LDA  #sizeof{devdrv}
            MUL              ; D = devref(B) * sizeof{devdrv}
            LDX  #DEVTAB
            LEAX D,X
            LDA  #1
            STA  devdrv.flags,X
            LDU  DR_TMP_READ
            STU  devdrv.read,X
            LDU  DR_TMP_WRITE
            STU  devdrv.write,X
            LDU  DR_TMP_IOCTL
            STU  devdrv.ioctl,X
            LDA  #ERR_OK
            ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
DEV_DEREGISTER
            CMPB #NUM_DEVICES
            BLO  DD_INRANGE
            LDA  #ERR_BADDEV
            ORCC #$01
            RTS
DD_INRANGE  PSHS X
            LDA  #sizeof{devdrv}
            MUL
            LDX  #DEVTAB
            LEAX D,X
            CLR  devdrv.flags,X
            PULS X
            LDA  #ERR_OK
            ANDCC #$FE
            RTS
;==============================================================================
; BIOS call handlers -- see file header for the calling convention.
;==============================================================================
BIO_BADDEV  LDA  #ERR_BADDEV
            JMP  BC_ERR
;------------------------------------------------------------------------------
; Returns a bitmap of present devices in D (bit N = devref N registered).
; Built by walking the table backwards so devref 0 ends up as bit 0: D moves up
; a bit for each device, and gets its bit in bit 0.
; NOTE (fixed): this used to load each slot's flags into A -- the top half of
; the D it was building -- so devices 9-11 never showed (8 did, by luck: its bit
; was the last one shifted out of B into A). It also began with PSHS X, which
; put every SWI2_* offset after it 2 off: the result went over the saved
; registers and its PULS X,PC jumped to nowhere. (Nothing called it until the
; video card's detection.) Like the other handlers it now leaves S alone and
; returns with RTI.
;------------------------------------------------------------------------------
BIOS_DQUERY LDD  #0
            LDX  #DEVTAB+(NUM_DEVICES*sizeof{devdrv})
DQ_LOOP     CMPX #DEVTAB
            BLS  DQ_DONE
            LEAX -sizeof{devdrv},X
            LSLD
            TIM  #1,devdrv.flags,X
            BEQ  DQ_LOOP
            ORB  #1
            BRA  DQ_LOOP
DQ_DONE     STD  SWI2_A,S       ; A then B, as the frame has them
            AIM  #$FE,SWI2_CC,S
            RTI
;------------------------------------------------------------------------------
BIOS_REG_DEV
            LDB  SWI2_B,S
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            LDU  SWI2_U,S
            JSR  DEV_REGISTER
            BCC  BRD_OK
            JMP  BC_ERR
BRD_OK      JMP  BC_OK
;------------------------------------------------------------------------------
BIOS_DEREG_DEV
            LDB  SWI2_B,S
            JSR  DEV_DEREGISTER
            BCC  BDD_OK
            JMP  BC_ERR
BDD_OK      JMP  BC_OK
;------------------------------------------------------------------------------
; The fileref for a v1 (non-file-backed) device is just its device ref.
;------------------------------------------------------------------------------
BIOS_FOPEN  LDB  SWI2_B,S
            JSR  DEV_ENTRY
            LBCS BIO_BADDEV
            LDA  SWI2_B,S
            STA  SWI2_A,S
            AIM  #$FE,SWI2_CC,S
            RTI
;------------------------------------------------------------------------------
BIOS_FCLOSE JMP  BC_OK        ; no per-open state to release yet
;------------------------------------------------------------------------------
BIOS_PUTC   LDB  SWI2_B,S
            JSR  DEV_ENTRY
            LBCS BIO_BADDEV
            LDU  devdrv.write,X
            LDA  SWI2_E,S
            STA  PUTC_SCRATCH
            LDX  #PUTC_SCRATCH
            LDY  #1
            JSR  ,U
            JMP  BC_OK
;------------------------------------------------------------------------------
BIOS_PUTS   LDB  SWI2_B,S
            JSR  DEV_ENTRY
            LBCS BIO_BADDEV
            LDU  devdrv.write,X
            LDX  SWI2_X,S
            JSR  S_LEN        ; D=length; S_LEN preserves X
            TFR  D,Y
            JSR  ,U
            JMP  BC_OK
;------------------------------------------------------------------------------
BIOS_PUT    LDB  SWI2_B,S
            JSR  DEV_ENTRY
            LBCS BIO_BADDEV
            LDU  devdrv.write,X
            LDY  SWI2_Y,S
            LDX  SWI2_X,S
            JSR  ,U
            JMP  BC_OK
;------------------------------------------------------------------------------
; Non-blocking single char. Success: A=char, carry clear. None ready: carry
; set (A is not meaningful, unlike every other handler A isn't a status
; code here -- matches the pre-existing B_GETC convention).
;------------------------------------------------------------------------------
BIOS_GETC   LDB  SWI2_B,S
            JSR  DEV_ENTRY
            LBCS BIO_BADDEV
            LDU  devdrv.read,X
            LDX  #GETC_SCRATCH
            LDY  #1
            JSR  ,U
            CMPY #0
            BEQ  GC_NONE
            LDA  GETC_SCRATCH
            STA  SWI2_A,S
            AIM  #$FE,SWI2_CC,S
            RTI
GC_NONE     OIM  #$01,SWI2_CC,S
            RTI
;------------------------------------------------------------------------------
; Raw line read: polls the device until CR or the buffer (minus room for a
; null terminator) fills. No echo -- an interactive caller (the loader's
; boot prompt) handles its own echo via repeated B_GETC, since echo only
; makes sense for a console, not for every possible device. SWI2 doesn't
; mask IRQ, so polling here doesn't starve the UART ISR that's filling the
; RX ring buffer in the first place.
;------------------------------------------------------------------------------
BIOS_GETS   LDB  SWI2_B,S
            JSR  DEV_ENTRY
            LBCS BIO_BADDEV
            LDU  devdrv.read,X
            STU  GETS_READFN
            LDX  SWI2_X,S
            STX  GETS_DST
            LDY  SWI2_Y,S
            BNE  GS_HAVEROOM
            LDY  #1          ; guard a 0-length caller buffer
GS_HAVEROOM LEAY -1,Y        ; reserve room for the null terminator
            STY  GETS_REMAIN
GS_LOOP     LDY  GETS_REMAIN
            CMPY #0
            BEQ  GS_DONE
            LDU  GETS_READFN
            LDX  #GETC_SCRATCH
            LDY  #1
            JSR  ,U
            CMPY #0
            BEQ  GS_LOOP     ; nothing available yet -- keep polling
            LDA  GETC_SCRATCH
            CMPA #CR
            BEQ  GS_DONE
            LDX  GETS_DST
            STA  ,X+
            STX  GETS_DST
            LDY  GETS_REMAIN
            LEAY -1,Y
            STY  GETS_REMAIN
            BRA  GS_LOOP
GS_DONE     LDX  GETS_DST
            CLR  ,X
            LDX  SWI2_X,S    ; original start of caller's buffer
            JSR  S_LEN       ; D=strlen; X preserved
            STD  SWI2_X,S    ; caller sees this as the returned X
            JMP  BC_OK
;------------------------------------------------------------------------------
; Non-blocking multi-byte read; passes straight through to the driver.
;------------------------------------------------------------------------------
BIOS_GET    LDB  SWI2_B,S
            JSR  DEV_ENTRY
            LBCS BIO_BADDEV
            LDU  devdrv.read,X
            LDY  SWI2_Y,S
            LDX  SWI2_X,S
            JSR  ,U
            STY  SWI2_X,S    ; actual length read
            JMP  BC_OK
;------------------------------------------------------------------------------
BIOS_IOCTL  LDB  SWI2_B,S
            JSR  DEV_ENTRY
            LBCS BIO_BADDEV
            LDU  devdrv.ioctl,X
            CMPU #0
            BEQ  BIO_IOC_NOTSUP
            LDA  SWI2_E,S
            LDB  SWI2_F,S
            JSR  ,U
            BCS  BIO_IOC_ERR
            STB  SWI2_B,S    ; the function's result, if it has one
            JMP  BC_OK
BIO_IOC_ERR STA  SWI2_A,S
            OIM  #$01,SWI2_CC,S
            RTI
BIO_IOC_NOTSUP
            LDA  #ERR_NOTSUP
            JMP  BC_ERR
;------------------------------------------------------------------------------
; Shared stub for the calls that only mean something once a filesystem-
; backed device (SD) exists: B_FSTAT, B_FDIR, B_FDELETE, B_FMOVE, B_FSEEK.
; Numbers stay reserved so they don't need to change later.
;------------------------------------------------------------------------------
BIOS_NOTIMPL
            LDA  #ERR_NOTSUP
            JMP  BC_ERR
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of devio.asm
;------------------------------------------------------------------------------
