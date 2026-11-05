;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: sdcard.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; SD/block storage driver, plus the disk-boot sequence (SD_BOOT_TRY, called
; from V_RESET). The register interface (see SD_LBA/SD_DATA/SD_CMDSTA in
; defines.d) is an idealized, transport-agnostic block device -- closer to
; ATA PIO mode than real SPI/SD card protocol -- since the real SD/SPI
; transport hardware isn't chosen yet (VIA-bit-banged vs. MCU-offloaded).
; Whichever one is chosen later, only this file's SD_READ_BLOCK/
; SD_WRITE_BLOCK need to change -- everything above them (BIOS_BLK_READ/
; WRITE, SD_BOOT_TRY, and every future caller) stays the same.
;
; SD_BOOT_TRY reads block 0 (the FAT16 boot sector) into free RAM (whatever
; USER_RAM currently points at -- nothing else needs that RAM yet, this
; early in V_RESET) as scratch. If it doesn't look like a valid FAT16
; volume, it just returns and V_RESET falls through to the existing
; S-record loader prompt exactly as before -- this is also what happens
; today when no SD device is mapped at all, since an unmapped read reads
; back as zero, which never matches the boot signature. If valid, it loads
; the volume's reserved sectors (which hold dos/dos.asm -- see that file's
; header for the FAT16 root-directory/cluster-chain walk) to that same
; scratch address, overwriting the now-unneeded boot sector bytes, and
; jumps there. Never returns on success.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
SD_READ_BLOCK   EXPORT
SD_WRITE_BLOCK  EXPORT
BIOS_BLK_READ   EXPORT
BIOS_BLK_WRITE  EXPORT
BIOS_BLK_READ32  EXPORT
BIOS_BLK_WRITE32 EXPORT
BIOS_DOS        EXPORT
SD_BOOT_TRY     EXPORT
;------------------------------------------------------------------------------
BC_OK       EXTERN          ; main.asm
BC_ERR      EXTERN
USER_RAM    EXTERN
UT_PUTS     EXTERN          ; serio.asm
JT_DOS         EXTERN     ; main.asm -- DOS call vectors, patched by dos/dos.asm at boot
DOSMASK        EXTERN     ; (defaulting to DOS_NOTPRESENT if no disk-resident DOS ever ran)
;------------------------------------------------------------------------------
    SECT bss
;------------------------------------------------------------------------------
SDBOOT_CNT  RMB  2          ; SD_BOOT_TRY's remaining-sectors-to-load counter
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
FAT16_SIG   FCC  "FAT16   "     ; BPB FS-type string, offset $36 -- no
                                 ; trailing zero, matched byte-for-byte below
;------------------------------------------------------------------------------
; X=16-bit LBA, Y=destination RAM address. Reads 512 bytes into [Y..Y+511].
; Carry set on failure, with A = ERR_NOCARD (no card), ERR_TIMEOUT (BUSY for
; SD_TIMEOUT polls) or ERR_IOERR (the card reported an error on SD_TRIES tries in
; a row) -- [Y..Y+511] is then undefined. Trashes A, B, X, W. SD_READ_BLOCK32 is the
; same with the LBA's high word in W (SD_READ_BLOCK is high word 0).
;------------------------------------------------------------------------------
SD_READ_BLOCK
            LDW  #0
SD_READ_BLOCK32
            PSHS Y
            STW  SD_LBA           ; the high word, latched by SETHI ...
            LDA  #SD_CMD_SETHI
            STA  SD_CMDSTA
            STX  SD_LBA           ; ... then the low word
            LDB  #SD_TRIES
SDRD_TRY    LDA  #SD_CMD_READ
            STA  SD_CMDSTA
            LDW  #SD_TIMEOUT
SDRD_WAIT   LDA  SD_CMDSTA
            BITA #SD_STA_BUSY
            BEQ  SDRD_IDLE
            DECW
            BNE  SDRD_WAIT
            LDA  #ERR_TIMEOUT    ; never came back from BUSY
            BRA  SDRD_FAIL
SDRD_IDLE   BITA #SD_STA_CARD
            BNE  SDRD_CARD
            LDA  #ERR_NOCARD
            BRA  SDRD_FAIL
SDRD_CARD   BITA #SD_STA_ERROR   ; the underlying read actually failed:
            BEQ  SDRD_XFER       ; try again a couple of times before giving up
            DECB
            BNE  SDRD_TRY
            LDA  #ERR_IOERR
            BRA  SDRD_FAIL
SDRD_XFER   LDX  #512
SDRD_LOOP   LDA  SD_DATA
            STA  ,Y+
            LEAX -1,X
            BNE  SDRD_LOOP
            ANDCC #$FE
            PULS Y,PC
SDRD_FAIL   ORCC #$01
            PULS Y,PC
;------------------------------------------------------------------------------
; X=16-bit LBA, Y=source RAM address. Writes [Y..Y+511] to the block. Carry set
; on failure with A as for SD_READ_BLOCK. Trashes A, B, X, W. SD_WRITE_BLOCK32: the
; LBA's high word in W.
;------------------------------------------------------------------------------
SD_WRITE_BLOCK
            LDW  #0
SD_WRITE_BLOCK32
            PSHS Y
            LDB  #1              ; CARD means nothing while BUSY says so
            BSR  SD_WAIT_READY
            BCS  SDWR_FAIL
            BITA #SD_STA_CARD
            BNE  SDWR_CARD
            LDA  #ERR_NOCARD
            BRA  SDWR_FAIL
SDWR_CARD   STW  SD_LBA
            LDA  #SD_CMD_SETHI
            STA  SD_CMDSTA
            STX  SD_LBA
            LDB  #SD_TRIES
SDWR_TRY    LDY  ,S              ; (the data is streamed in again on a retry)
            LDX  #512
SDWR_LOOP   LDA  ,Y+
            STA  SD_DATA
            LEAX -1,X
            BNE  SDWR_LOOP
            LDA  #SD_CMD_WRITE
            STA  SD_CMDSTA
            LDW  #SD_TIMEOUT
SDWR_WAIT   LDA  SD_CMDSTA
            BITA #SD_STA_BUSY
            BEQ  SDWR_IDLE
            DECW
            BNE  SDWR_WAIT
            LDA  #ERR_TIMEOUT
            BRA  SDWR_FAIL
SDWR_IDLE   BITA #SD_STA_ERROR   ; the underlying write actually failed
            BEQ  SDWR_OK         ; (permissions, disk full, ...): retry
            DECB
            BNE  SDWR_TRY
            LDA  #ERR_IOERR
            BRA  SDWR_FAIL
SDWR_OK     ANDCC #$FE
            PULS Y,PC
SDWR_FAIL   ORCC #$01
            PULS Y,PC
;------------------------------------------------------------------------------
; Waits up to B spells of SD_TIMEOUT polls for BUSY to clear. OUT: A = the
; status, carry clear -- or, still BUSY, A = ERR_TIMEOUT and carry set. Trashes
; B; keeps W (SD_WRITE_BLOCK32's LBA high word).
;------------------------------------------------------------------------------
SD_WAIT_READY
            PSHSW
SDW_SPELL   LDW  #SD_TIMEOUT
SDW_POLL    LDA  SD_CMDSTA
            BITA #SD_STA_BUSY
            BEQ  SDW_READY
            DECW
            BNE  SDW_POLL
            DECB
            BNE  SDW_SPELL
            PULSW
            LDA  #ERR_TIMEOUT
            ORCC #$01
            RTS
SDW_READY   PULSW
            ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; IN: Y = a block buffer. OUT: carry clear if all 512 bytes lie below the ROM
; ($F000) -- a block transfer into the ROM/IO area would scribble over the
; hardware registers -- else carry set. Trashes D.
;------------------------------------------------------------------------------
BLK_CHKBUF  TFR  Y,D
            ADDD #511
            BCS  BLKC_BAD
            CMPD #EXE_MAXTOP
            BHS  BLKC_BAD
            ANDCC #$FE
            RTS
BLKC_BAD    ORCC #$01
            RTS
;------------------------------------------------------------------------------
; SWI2 handlers. X=16-bit LBA, Y=RAM buffer adrs, from SWI2_X,S/SWI2_Y,S --
; same convention as every other BIOS_* handler (see defines.d). A failure hands
; the driver's error code (NOCARD / TIMEOUT / IOERR) to the caller.
;------------------------------------------------------------------------------
BIOS_BLK_READ
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  BLK_CHKBUF
            BCS  SDBLK_BADBUF
            JSR  SD_READ_BLOCK
            BCS  SDBLK_ERR
            JMP  BC_OK
SDBLK_ERR   JMP  BC_ERR
SDBLK_BADBUF LDA #ERR_BADPARAM
            JMP  BC_ERR
;------------------------------------------------------------------------------
BIOS_BLK_WRITE
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  BLK_CHKBUF
            BCS  SDBLK_BADBUF
            JSR  SD_WRITE_BLOCK
            BCS  SDBLK_ERR
            JMP  BC_OK
;------------------------------------------------------------------------------
; The 32-bit variants: the LBA's high word is the caller's W (E:F in the frame).
;------------------------------------------------------------------------------
BIOS_BLK_READ32
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  BLK_CHKBUF
            BCS  SDBLK_BADBUF
            LDW  SWI2_E,S
            JSR  SD_READ_BLOCK32
            BCS  SDBLK_ERR
            JMP  BC_OK
;------------------------------------------------------------------------------
BIOS_BLK_WRITE32
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  BLK_CHKBUF
            BCS  SDBLK_BADBUF
            LDW  SWI2_E,S
            JSR  SD_WRITE_BLOCK32
            BCS  SDBLK_ERR
            JMP  BC_OK
;------------------------------------------------------------------------------
; Resident DOS calls (function codes B_FOPEN_NAME and up), ALL through this one
; handler. It loads the registers the DOS routine expects from the caller's SWI2
; frame -- A = the caller's E, B, X, Y (so a "mode", byte or whence goes in E)
; -- and JSRs the routine's entry in the JT_DOS table (whatever dos/dos.asm
; patched in at boot, or DOS_NOTPRESENT's clean-error stub if no disk-resident
; DOS ever ran). The routine is a plain subroutine: carry clear = success, else
; carry set and A = an ERR_* code. This file (never the callee) finishes the
; SWI2 frame -- the callee must never RTI, since only the handler holding the
; original SWI2 context may -- and DOS_OUTMASK below says which results the call
; returns to the caller: bit 0 = A (a value, e.g. a handle or byte; otherwise A
; comes back as ERR_OK), bit 1 = X, bit 2 = Y. Registers a call doesn't return
; are left exactly as the caller had them.
;
; Adding a DOS call: give it the next function code in defines.d, one FDB in
; dos.asm's DOS_ENTRIES, and one byte here -- nothing else changes.
;------------------------------------------------------------------------------
BIOS_DOS    LDB  SWI2_A,S       ; the function code ...
            SUBB #B_FOPEN_NAME  ; ... as an index (0..NUM_DOS_JT-1)
            LDX  #DOS_OUTMASK
            LDA  B,X
            STA  >DOSMASK       ; extended: the caller's DP is not ours
            ASLB
            LDU  #JT_DOS
            LEAU B,U            ; U -> this call's slot
            LDA  SWI2_E,S
            LDB  SWI2_B,S
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  [,U]
            BCS  BDOS_ERR
            LDB  >DOSMASK
            BITB #1
            BNE  BDOS_A
            CLRA                ; no value: A = ERR_OK
BDOS_A      STA  SWI2_A,S
            BITB #2
            BEQ  BDOS_NOX
            STX  SWI2_X,S
BDOS_NOX    BITB #4
            BEQ  BDOS_NOY
            STY  SWI2_Y,S
BDOS_NOY    AIM  #$FE,SWI2_CC,S
            RTI
BDOS_ERR    STA  SWI2_A,S
            OIM  #$01,SWI2_CC,S
            RTI
; Results each DOS call returns, in function-code order (see the byte above).
DOS_OUTMASK FCB  1              ; $13 B_FOPEN_NAME   A = handle
            FCB  2              ; $14 B_READLINE     X = length
            FCB  0              ; $15 B_WRITELINE
            FCB  0              ; $16 B_FCLOSE_NAME
            FCB  1              ; $17 B_OPENDIR      A = scan handle
            FCB  0              ; $18 B_READDIR      (the entry is in the buffer)
            FCB  0              ; $19 B_KILL_NAME
            FCB  0              ; $1A B_RENAME_NAME
            FCB  1              ; $1B B_FGETC        A = byte
            FCB  0              ; $1C B_FPUTC
            FCB  2              ; $1D B_FREAD        X = bytes read
            FCB  0              ; $1E B_FWRITE
            FCB  6              ; $1F B_FSEEK_NAME   X:Y = new position
            FCB  0              ; $20 B_FSTAT_NAME   (in the buffer)
            FCB  0              ; $21 B_FFLUSH
            FCB  0              ; $22 B_MKDIR
            FCB  0              ; $23 B_RMDIR
            FCB  0              ; $24 B_CHDIR
            FCB  0              ; $25 B_GETCWD       (in the buffer)
            FCB  0              ; $26 B_CLOSEDIR
            FCB  0              ; $27 B_STAT         (in the buffer)
            FCB  1              ; $28 B_DOS_VERSION  A = version
            FCB  0              ; $29 B_EXEC         (returns only on failure)
            FCB  2              ; $2A B_ARGS         X = the command tail
            FCB  0              ; $2B B_EXIT         (never returns)
            FCB  2              ; $2C B_PATH         X = the search path
DOS_OUTMASK_END
    IFNE (DOS_OUTMASK_END-DOS_OUTMASK)-NUM_DOS_JT
    ERROR "DOS_OUTMASK must have one byte per DOS call (see defines.d)"
    ENDC
;------------------------------------------------------------------------------
; See file header. Called from V_RESET, right before its existing
; JMP LOADER_START.
;------------------------------------------------------------------------------
SD_BOOT_TRY LDA  SD_CMDSTA      ; status bits 3-7 are always 0: if any is
            BITA #$F8           ; set, nothing's answering (the bus floats
            LBNE SDBOOT_NONE    ; high), so don't wait for it
            LDB  #SD_WAKE       ; at power-on the card says BUSY until it's
            JSR  SD_WAIT_READY  ; awake (the video card's RP2350 starting it
            LBCS SDBOOT_NONE    ; up): give it a few seconds
            LDX  #0             ; LBA 0: the boot sector
            LDY  <USER_RAM
            JSR  SD_READ_BLOCK
            BCS  SDBOOT_NONE    ; no card / unreadable -- bail out
            LDX  <USER_RAM
            LDD  510,X          ; boot signature, offset $1FE
            CMPD #$55AA
            BNE  SDBOOT_NONE
            LEAX 54,X           ; offset $36: the 8-byte FS type string
            LDY  #FAT16_SIG
            LDB  #8
SDBOOT_CHK  LDA  ,X+
            CMPA ,Y+
            BNE  SDBOOT_NONE
            DECB
            BNE  SDBOOT_CHK
            LDX  <USER_RAM
            LDA  11,X           ; bytes per sector, offset $0B (little-endian): must
            BNE  SDBOOT_NONE    ; be 512 -- everything after this assumes it
            LDA  12,X
            CMPA #2
            BNE  SDBOOT_NONE
            ; Reserved sector count, offset $0E, stored little-endian --
            ; read the high/low bytes individually (in the opposite order
            ; LDD would) rather than via a single misordered 16-bit load.
            LDA  15,X           ; high byte, offset $0F
            LDB  14,X           ; low byte, offset $0E
            SUBD #1             ; minus the boot sector itself (already read)
            BEQ  SDBOOT_NONE    ; no DOS in the reserved sectors
            CMPD #DOS_MAXSECT
            BHI  SDBOOT_NONE    ; more than fits in bank 0: a corrupt boot sector,
                                ; not something to load over the machine
            STD  SDBOOT_CNT
            ; Load the reserved sectors (dos/dos.asm) starting at LBA 1 to
            ; DOS_LOAD (which may overlap the boot-sector scratch: the fields
            ; needed from it have been extracted by now).
            LDX  #1
            LDY  #DOS_LOAD
SDBOOT_LOAD LDD  SDBOOT_CNT
            BEQ  SDBOOT_GO
            PSHS X,Y,D
            JSR  SD_READ_BLOCK
            PULS D,Y,X          ; (PULS leaves the carry from the read alone)
            BCS  SDBOOT_LOADERR
            SUBD #1
            STD  SDBOOT_CNT
            LEAX 1,X
            LEAY 512,Y
            BRA  SDBOOT_LOAD
SDBOOT_GO   LDX  #DOS_LOAD
            LDY  #JT_DOS        ; DOS gets its call table's address in Y (no hand-synced constant)
            JMP  ,X             ; hand off to DOS -- never returns
SDBOOT_LOADERR
            LDY  #MSG_BOOTERR
            JSR  UT_PUTS
SDBOOT_NONE RTS                 ; caller falls through to LOADER_START
MSG_BOOTERR FCC  "Disk boot failed: could not read DOS."
            FCB  LF,CR,0
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of sdcard.asm
;------------------------------------------------------------------------------
