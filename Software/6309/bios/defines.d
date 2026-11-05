; -----------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: defines.d
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Global hardware equates, BIOS call codes, and shared data structures.
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; IO DEVICE BASE ADDRESSES (full memory map, even where a driver isn't built
; yet -- these mirror the fixed hardware address decode, not code)
; -----------------------------------------------------------------------------

BANK_BASE   equ  $FFEC      ; ffec - ffef: Memory Bank Regs 0...3 (Built-in)
ACIA_BASE   equ  $FFE8      ; ffe8 - ffeb: Serial UART R65C51P2 (Built-in)
VDP_BASE    equ  $FFE4      ; ffe4 - ffe7: Video Chip V9958 (optional card)
OPL3_BASE   equ  $FFE0      ; ffe0 - ffe3: Music Chip YMF262 (optional card)
SD_BASE     equ  $FFD8      ; ffd8 - ffdb: SD/block storage (Built-in; see
                             ;              sdcard.asm -- an idealized block
                             ;              register interface, not real SPI/
                             ;              SD protocol, since the real
                             ;              transport hardware isn't decided)
VIA_BASE    equ  $FFB0      ; ffb0 - ffbf: W65C22 VIA (optional card)
VCARD_BASE  equ  $FF80      ; ff80 - ff9f: the video card (optional; its registers
                             ;              are in vidcard/vidcard.d)
VC_ID_REG   equ  $1E        ; the card's ID register: reads 'V'
VC_VER_REG  equ  $1F        ; its version (major*16 + minor): $11 or later
VC_VERSION_MIN equ $11      ; (the BIOS looks for these at boot: see F_VDP)
VC_WAKE     equ  2          ; spells of $FFFF polls (~0.27s each) the BIOS gives the
                             ; card to start answering at boot (DEV_VC_DETECT)

; Memory bank registers 0..3 (write-only; readable copies kept in
; SBANK_1...SBANK_3 -- see main.asm)

MBANK_0     equ  BANK_BASE+0
MBANK_1     equ  BANK_BASE+1
MBANK_2     equ  BANK_BASE+2
MBANK_3     equ  BANK_BASE+3

; UART registers

UT_DAT      equ  ACIA_BASE+0  ; R65C51P2 UART DATA REGISTER (RD: RX, WR: TX)
UT_STA      equ  ACIA_BASE+1  ; READ: UART STATUS REG, WRITE: PROGRAM RESET
UT_CMD      equ  ACIA_BASE+2  ; COMMAND REG (parity, echo, IRQ enables, DTR)
UT_CTL      equ  ACIA_BASE+3  ; CONTROL REG (baud rate, word length, stop bits)

; UART constants

SBUFSZ      equ  $7E        ; SIZE OF THE SERIAL INPUT / OUTPUT RING BUFFERS
SUARTCTL    equ  $1F        ; %0001 1111 = 19200 BAUD,
                             ;              EXTERNAL RECEIVER CLOCK,
                             ;              8 DATA BITS,
                             ;              1 STOP BIT.
SUARTCMD    equ  $09        ; %0000 1001 = ODD PARITY CHECK, BUT
                             ;              PARITY CHECK DISABLED.
                             ;              NORMAL RECEIVER MODE, NO ECHO.
                             ;              RTSB LOW, TX INTERRUPT DISABLED.
                             ;              IRQB RX INTERRUPT ENABLED.
                             ;              DATA TERMINAL READY, DTRB LOW.

; SD/block storage registers (see sdcard.asm). SD_LBA is a single 16-bit
; register (STX/LDX-friendly: high byte at +0, low byte at +1, matching the
; 6309's natural big-endian STX order) rather than two separately-named
; byte registers. Block numbers are 32 bits: SD_LBA is the LOW word, and the
; high word is latched into the device by the SETHI command (SD_LBA = the high
; word, then SD_CMDSTA = SD_CMD_SETHI). It stays latched until the next SETHI
; (and is 0 after reset), so a driver that only wants the first 32MB never
; needs to touch it.

SD_LBA      equ  SD_BASE+0  ; low 16 bits of the block number (r/w); with
                             ; SETHI's high word: 2^32 blocks * 512B = 2TB
SD_DATA     equ  SD_BASE+2  ; stream port into/out of the active 512-byte
                             ; sector buffer; cursor auto-increments and
                             ; resets to 0 after each READ/WRITE command
SD_CMDSTA   equ  SD_BASE+3  ; WRITE: command (1=READ block at LBA into
                             ; buffer, 2=WRITE buffer to block at LBA).
                             ; READ: status (bit0 BUSY, bit1 CARD_PRESENT)

SD_CMD_READ  equ  1
SD_CMD_WRITE equ  2
SD_TRIES    equ  3           ; attempts at a block command the card reports as failed
SD_TIMEOUT  equ  $FFFF       ; polls of BUSY before a command is declared timed out
                             ; (~15 cycles each: about 0.27s at 3.58MHz)
SD_WAKE     equ  12          ; spells of SD_TIMEOUT polls (about 3.3s) SD_BOOT_TRY
                             ; gives the card to wake up at power-on (BUSY until then)
SD_CMD_SETHI equ  3          ; latch SD_LBA's current value as block-number
                             ; bits 31..16 (see above)
SD_STA_BUSY  equ  %00000001
SD_STA_CARD  equ  %00000010
SD_STA_ERROR equ  %00000100  ; the last READ/WRITE command's underlying
                             ; file I/O actually failed (permissions,
                             ; disk full, etc.); cleared by the next cmd
; -----------------------------------------------------------------------------
; Device ref / fileref numbers
;
; A "device ref" and a "fileref" are the same number space. Built-in devices
; are usable directly as filerefs (no open needed -- they have no per-open
; state). B_FOPEN exists for forward compatibility with future file-backed
; devices (e.g. SD card files) that DO need per-open state; for a plain
; device it just validates the ref and hands it back.
; -----------------------------------------------------------------------------
F_NULL      equ  $00        ; Discards writes, reads return nothing
F_STDOUT    equ  $01        ; Aliased to the console device at BIOS init
F_STDIN     equ  $02
F_STDERR    equ  $03        ; (reserved numbering: 4-7 unused for now)
F_UART      equ  $08        ; Direct access to the UART, bypassing stdio
F_VDP       equ  $09        ; the video card: registered at boot when the card is
                             ; there (so B_DQUERY's bit 9 says so); no character
                             ; driver yet (reads give nothing, writes are dropped)
F_VIA_KB    equ  $0A        ; reserved for a future VIA/keyboard driver
NUM_DEVICES equ  $0C        ; size of the device driver table (0..$0B)

; -----------------------------------------------------------------------------
; BIOS Functions - function type codes passed in reg A when doing a BIOS
; call (SWI2). Common arg: B = device ref / fileref, where applicable.
; -----------------------------------------------------------------------------
B_DQUERY    equ  $00        ; Returns bitmap of present devices in D
B_REG_DEV   equ  $01        ; B: devref, X: read fn, Y: write fn, U: ioctl fn
B_DEREG_DEV equ  $02        ; B: devref
B_FSTAT     equ  $03        ; (reserved; not implemented until SD exists)
B_FDIR      equ  $04        ; (reserved; not implemented until SD exists)
B_FOPEN     equ  $05        ; B: devref, E: flags -> A: fileref (== devref)
B_FCLOSE    equ  $06        ; B: fileref
B_FDELETE   equ  $07        ; (reserved; not implemented until SD exists)
B_FMOVE     equ  $08        ; (reserved; not implemented until SD exists)
B_PUTC      equ  $09        ; B: fileref, E: the char (blocks if buf full)
B_PUTS      equ  $0A        ; B: fileref, X: adrs of null-terminated string
B_PUT       equ  $0B        ; B: fileref, X: adrs of bytes, Y: len
B_GETC      equ  $0C        ; B: fileref -> A: char, or carry set if none
B_GETS      equ  $0D        ; B: fileref, X: buf adrs, Y: buf len (raw, no
                             ; echo, stops at CR or full) -> X: strlen
B_GET       equ  $0E        ; B: fileref, X: buf adrs, Y: max len (non-
                             ; blocking) -> X: actual len read
B_IOCTL     equ  $0F        ; B: fileref, E: func code, F: param byte -> B: the
                             ; function's result, where it has one
B_FSEEK     equ  $10        ; (reserved; not implemented until SD exists)
B_BLK_READ  equ  $11        ; X: 16-bit LBA, Y: RAM buffer adrs -> reads
                             ; 512 bytes from the SD device into [Y..Y+511]
B_BLK_WRITE equ  $12        ; X: 16-bit LBA, Y: RAM buffer adrs -> writes
                             ; [Y..Y+511] to the SD device
                             ; Both (and the 32-bit forms) retry a command the card
                             ; reports as failed (SD_TRIES attempts) and fail with
                             ; ERR_NOCARD, ERR_TIMEOUT (BUSY for SD_TIMEOUT polls) or
                             ; ERR_IOERR; ERR_BADPARAM if the 512-byte buffer isn't
                             ; entirely below the ROM ($F000).
                             ; (Both address only the first 64K blocks = 32MB;
                             ; see B_BLK_READ32/B_BLK_WRITE32 below.)
; Resident DOS calls (dos/dos.asm, API version DOS_API_VERSION). All of them are
; reached through ONE generic handler in sdcard.asm (BIOS_DOS), which loads
; A=E, B=B, X=X, Y=Y from the caller's frame, calls the routine DOS installed in
; the JT_DOS table (main.asm) for that function code, and hands back carry, A
; (status, or the call's value where noted) and X/Y where noted. They fail
; cleanly with ERR_NOTSUP if no disk-resident DOS ever patched the table (e.g. a
; boot path with no SD card).
;
; Names ("path") are NUL-terminated strings in the caller's memory: components
; separated by "/", a leading "/" meaning the root directory, otherwise relative
; to the current directory; "." and ".." are understood; each component is an
; 8.3 name (letters are folded to upper case). Handles are small numbers: file
; handles 0..7 (DOS_NFILES) and, separately, directory-scan handles 0..3.
; Sizes and positions are 32-bit in the API and in DOS (ERR_TOOBIG only for a
; position past 32 bits).
B_FOPEN_NAME  equ $13        ; X: path, E: mode (FOPEN_*) -> A: file handle
B_READLINE    equ $14        ; B: handle, X: dest buf, Y: max len ->
                             ; X: actual length read (0 = empty line or EOF).
                             ; CR, LF and CR LF all end a line.
B_WRITELINE   equ $15        ; B: handle, X: src buf, Y: len -> writes
                             ; the line plus a trailing CR
B_FCLOSE_NAME equ $16        ; B: handle -> flushes and finalizes the file
B_OPENDIR     equ $17        ; X: path of a directory ("" or "." = the current
                             ; one) -> A: directory-scan handle
B_READDIR     equ $18        ; B: scan handle, X: dest buf (16 bytes: 11 name +
                             ; 1 attr + 4 size, big-endian) -> the next live
                             ; entry ("." and ".." included); carry set +
                             ; A=ERR_EOF when there are no more
B_KILL_NAME   equ $19        ; X: path -> deletes the file
B_RENAME_NAME equ $1A        ; X: old path, Y: the new NAME (a single component,
                             ; same directory) -> renames a file or directory;
                             ; fails if old is missing or new already exists
; Byte-level access to open DOS files (mode-dependent; see FOPEN_* below).
; Each open file has its own sector buffer, so several can be open and
; interleaved freely.
B_FGETC     equ  $1B         ; B: handle -> A: next byte, or carry set +
                             ; A=ERR_EOF at end of file
B_FPUTC     equ  $1C         ; B: handle, E: the byte (write/append/update)
B_FREAD     equ  $1D         ; B: handle, X: buf, Y: len -> X: bytes actually
                             ; read (short only at end of file)
B_FWRITE    equ  $1E         ; B: handle, X: buf, Y: len
B_FSEEK_NAME equ $1F         ; B: handle, X:Y: 32-bit offset (X = high word),
                             ; E: whence (SEEK_*) -> X:Y: the new position
                             ; (read or update mode). Positions past the end
                             ; read as end-of-file; an update-mode write there
                             ; zero-fills the gap.
B_FSTAT_NAME equ $20         ; B: handle, X: dest buf (16 bytes: size 4,
                             ; position 4, attr 1, open mode 1, 6 reserved;
                             ; 32-bit values big-endian)
B_FFLUSH    equ  $21         ; B: handle (or $FF = every open file): writes out
                             ; buffered data and updates the directory entry, so
                             ; the file survives a crash from here on
B_MKDIR     equ  $22         ; X: path of the new directory
B_RMDIR     equ  $23         ; X: path -> removes an empty directory
B_CHDIR     equ  $24         ; X: path -> makes it the current directory
B_GETCWD    equ  $25         ; X: dest buf, Y: its size -> the current directory
                             ; as an absolute path ("/" for the root)
B_CLOSEDIR  equ  $26         ; B: scan handle
B_STAT      equ  $27         ; X: path, Y: dest buf (same 16 bytes as FSTAT; the
                             ; position is 0 and the open mode $FF)
B_DOS_VERSION equ $28        ; -> A: API version (DOS_API_VERSION)
; Programs. A program file starts with an 8-byte header (EXE_* below); DOS loads
; its body at the header's load address and starts it at the entry address.
B_EXEC        equ $29        ; X: path of a program file, Y: its command tail (a
                             ; NUL-terminated string, or 0 for none) -> loads and
                             ; STARTS the program: on success this does not return
                             ; (the caller's memory may be overwritten); on failure
                             ; carry set + A = ERR_NOTFOUND / ERR_BADEXE / ERR_TOOBIG
B_ARGS        equ $2A        ; -> X: address (in DOS's RAM) of the running program's
                             ; command tail, NUL-terminated (empty if there was none)
B_EXIT        equ $2B        ; the program is finished: DOS closes every open file
                             ; and directory scan and starts the shell again (or, on
                             ; a disk with none, BASIC.COM). Never returns.
B_PATH        equ $2C        ; X: a new program search path (NUL-terminated: directories
                             ; separated by ";", at most PATHVARMAX characters), or 0
                             ; to leave it -> X: address (in DOS's RAM) of the current
                             ; one. DOS only keeps it (the shell searches it); it
                             ; starts as "/CMD" and survives B_EXIT. ERR_TOOBIG if
                             ; the new one is too long (the old one is kept).
B_DOS_END   equ  $2D         ; the DOS calls are B_FOPEN_NAME up to (not including) this
NUM_DOS_JT  equ  B_DOS_END-B_FOPEN_NAME ; DOS-resident calls: one JT_DOS slot
                             ; each (main.asm), in call-code order

; RAM banking (banks.asm). Bank 0 is always page 0 (the system's); banks 1..3
; belong to applications. Every bank change must go through B_BANK_SET, which
; keeps the BIOS's readable shadow copies right (the registers are write-only).
B_BANK_GET  equ  B_DOS_END   ; B: bank (0..3) -> A: the page mapped there
B_BANK_SET  equ  B_DOS_END+1 ; B: bank (1..3), E: page -> maps it. ERR_BADPARAM for
                             ; bank 0, a page that isn't installed, or the bank the
                             ; caller's stack is in (remapping that would strand the
                             ; frame the call returns through)
B_PAGE_ALLOC equ B_DOS_END+2 ; -> A: a free 16KB RAM page (pages 0..3 are never
                             ; handed out); ERR_NOSPACE when none are left
B_PAGE_FREE equ  B_DOS_END+3 ; B: a page from B_PAGE_ALLOC (ERR_BADPARAM otherwise)
B_PAGE_INFO equ  B_DOS_END+4 ; -> X: installed pages, Y: pages still free
B_PAGE_COPY equ  B_DOS_END+5 ; B: source page, E: destination page, X: source
                             ; offset, Y: destination offset, U: length -- copies
                             ; between two pages regardless of the current banks,
                             ; leaving the caller's mapping alone. Ranges must stay
                             ; inside their 16KB page, and inside one page may not
                             ; overlap (ERR_BADPARAM).

; 32-bit block numbers (sdcard.asm). Same as B_BLK_READ/WRITE, but the LBA's HIGH
; word comes in W (E:F) -- the calls above always use high word 0.
B_BLK_READ32  equ B_DOS_END+6 ; X: LBA low word, W: LBA high word, Y: RAM buffer adrs
B_BLK_WRITE32 equ B_DOS_END+7 ; same arguments; writes [Y..Y+511]
NUM_BCALLS  equ  B_DOS_END+8

DOS_MAXSECT equ  ($4000-DOS_LOAD)/512 ; the most sectors SD_BOOT_TRY will load for DOS:
                             ; it has to fit in bank 0
DOS_LOAD    equ  $0600       ; where SD_BOOT_TRY loads dos/dos.asm and jumps to it
RAM_IRQV    equ  $0026       ; the IRQ entry of the BIOS's RAM jump table is a JMP; this is
                             ; the address it jumps to. A program can take the interrupt:
                             ; keep the old address, put its own, and JMP [old] when the
                             ; interrupt isn't its own -- and put the old one back before
                             ; B_EXIT (serio.asm does this for the UART; VIDGFX in
                             ; /ASM/VIDEO for the video card). (Checked against the BIOS's
                             ; map: JT_IRQ + 1.) Write >RAM_IRQV: it is below $100, and a
                             ; program's DP needn't be 0.
                             ; (dos.asm ORGs here too, so nothing is hand-synced).
                             ; Must be above the BIOS's RAM (EndOfVars in
                             ; pugbios.map); test_bios_layout checks that.

DOS_API_VERSION equ $22      ; major*16 + minor: 2.2 (2.1 added programs, 2.2 B_PATH)
PATHVARMAX  equ  79          ; the longest B_PATH search path

; Program files. Header, all 16-bit values big-endian:
;   +0  "PX"           magic
;   +2  load address   where the body (everything after the header) goes; must be at
;                      or above the end of DOS's RAM (DOS_END) and the body must end
;                      below the ROM ($F000)
;   +4  entry address  where execution starts; inside the body
;   +6  flags          must be 0 (reserved: a later revision will use it to mark a
;                      header extension with a segment table for banked programs)
EXE_MAGIC   equ  $5058       ; "PX"
EXE_HDRSIZE equ  8
EXE_MAXTOP  equ  $F000       ; a body may not reach the ROM
DOS_NFILES  equ  8           ; open files at once (handles 0..7)
DOS_NDIRS   equ  4           ; directory scans open at once

; BIOS call status codes (returned in A; carry set on any non-OK status)

ERR_OK      equ  $00
ERR_BADFN   equ  $01        ; unknown BIOS function code
ERR_BADDEV  equ  $02        ; devref/fileref out of range or not registered
ERR_NOTSUP  equ  $03        ; operation not supported by this device
ERR_IOERR   equ  $04        ; block IO failed (no card / bad block, etc.)
ERR_NOTFOUND equ $05        ; file or directory not found
ERR_NOSPACE equ  $06        ; B_WRITELINE: disk full (no free clusters)
ERR_NOSLOT  equ  $07        ; B_FOPEN_NAME: no free open-file slot
ERR_EXISTS  equ  $08        ; B_RENAME_NAME: target name already exists
ERR_EOF     equ  $09        ; B_FGETC: no more data in the file
ERR_ISOPEN  equ  $0A        ; file is already open (open/kill/rename)
ERR_BADMODE equ  $0B        ; operation not allowed in the file's open mode
ERR_NOTDIR  equ  $0C        ; a path component (or the target) isn't a directory
ERR_ISDIR   equ  $0D        ; the path names a directory where a file is needed
ERR_NOTEMPTY equ $0E        ; B_RMDIR: the directory still has entries
ERR_BADPATH equ  $0F        ; a name that isn't a valid 8.3 name / too long
ERR_TOOBIG  equ  $10        ; a size or position beyond what this DOS handles
ERR_BADPARAM equ $11        ; an argument out of range (bank, page, offset, length)
ERR_BADEXE  equ  $12        ; B_EXEC: not a valid program file (magic, flags, addresses)
ERR_NOCARD  equ  $13        ; block calls: no SD card present
ERR_TIMEOUT equ  $14        ; block calls: the card stayed BUSY (SD_TIMEOUT polls)

; B_FOPEN_NAME mode values
FOPEN_READ   equ $00        ; must exist; read (and seek) only
FOPEN_WRITE  equ $01        ; create, or truncate an existing file; write only
FOPEN_APPEND equ $02        ; create if missing; writes go at the end
FOPEN_UPDATE equ $03        ; create if missing; read/write/seek in place,
                            ; existing contents kept

; B_FSEEK_NAME whence values
SEEK_SET    equ  $00        ; offset from the start of the file
SEEK_CUR    equ  $01        ; offset added to the current position
SEEK_END    equ  $02        ; offset added to the end of the file

; Directory-entry attribute bits (as in FAT16)
ATTR_DIR    equ  $10

; UART ioctl function codes (used with B_IOCTL on F_UART or aliases)

UT_IOC_SETCTL equ $00       ; F: new UART Control Register value (raw HW
                             ; encoding -- baud rate / word length / stop
                             ; bits, see R65C51 datasheet Control Register).
                             ; Waits for TX idle before applying.
UT_IOC_GETERR equ $01       ; -> B: the UART error flags seen since the last call
                             ; (then cleared): bit 0 parity, bit 1 framing, bit 2
                             ; receiver overrun (the R65C51's own status bits), bit 3
                             ; the RX ring buffer overflowed (a received byte was
                             ; dropped because nobody read the buffer in time)
UT_ERR_PARITY equ $01
UT_ERR_FRAMING equ $02
UT_ERR_OVERRUN equ $04
UT_ERR_RXFULL equ $08

; -----------------------------------------------------------------------------
; Native-mode interrupt/SWI stack frame offsets, relative to S immediately
; after entry (i.e. S points at the stacked CC). Confirmed against the 6309
; native-mode register stacking order: PC,U,Y,X,DP,F,E,B,A,CC pushed in that
; order, so CC ends up nearest the post-entry S. A BIOS call handler (see
; devio.asm) reads its arguments from these offsets and, since RTI restores
; registers FROM this frame rather than from whatever's live in the CPU at
; the time, must write any return values back to these same offsets before
; returning -- leaving a result only in a live register is silently lost.
; -----------------------------------------------------------------------------
SWI2_CC     equ  0
SWI2_A      equ  1
SWI2_B      equ  2
SWI2_E      equ  3
SWI2_F      equ  4
SWI2_DP     equ  5
SWI2_X      equ  6
SWI2_Y      equ  8
SWI2_U      equ  10
SWI2_PC     equ  12

; -----------------------------------------------------------------------------
; MISC CONSTANTS
; -----------------------------------------------------------------------------
ESCAPE      equ  $1B        ; ASCII CODE FOR ESCAPE
LF          equ  $0A        ; LINE FEED
CR          equ  $0D        ; CARRIAGE RETURN
SPACE       equ  $20
TILDE       equ  $7E

; -----------------------------------------------------------------------------
; Generic circular byte buffer (methods in helpers.asm). Used for the UART's
; RX and TX buffers, sized identically via SBUFSZ so both instances share one
; implementation of the push/pop logic.
; -----------------------------------------------------------------------------
circbuf     STRUCT
head        rmb  1          ; write index into buf (0..SBUFSZ-1)
tail        rmb  1          ; read index into buf
count       rmb  1          ; number of bytes currently buffered
buf         rmb  SBUFSZ     ; storage
            ENDS

; -----------------------------------------------------------------------------
; Device driver descriptor - one per registered device (see devio.asm).
; A device with no per-byte concept of "read" (i.e. write-only) or no ioctl
; support simply registers a null (0) pointer for that entry.
; -----------------------------------------------------------------------------
devdrv      STRUCT
flags       rmb  1          ; bit 0: slot in use
read        rmw  1          ; (X=buf,Y=maxlen) -> Y=actual len, non-blocking
write       rmw  1          ; (X=buf,Y=len) -> blocks until all len sent
ioctl       rmw  1          ; (A=func,B=param) -> A=status, carry=error
            ENDS
; -----------------------------------------------------------------------------
; END OF DEFINES.D
; -----------------------------------------------------------------------------
