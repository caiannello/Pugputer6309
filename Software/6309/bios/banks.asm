;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: banks.asm
;
; RAM banking services. The CPU's 64KB is four 16KB banks; each bank register
; (write-only, $FFEC..$FFEF) selects which of up to 256 physical 16KB RAM pages
; appears there (see defines.d's MBANK_*). The BIOS keeps readable shadow copies
; (SBANK_1..3, main.asm) -- they are only right if EVERY change goes through
; B_BANK_SET. Bank 0 is permanently page 0: the BIOS's own variables, the system
; stack and the resident DOS live there, so it is never remapped. Banks 1..3 are
; the applications'.
;
; Calls (function codes in defines.d):
;   B_BANK_GET   B=bank (0..3)               -> A = the page mapped there
;   B_BANK_SET   B=bank (1..3), E=page       maps it (ERR_BADPARAM for bank 0, a
;                                            page that isn't installed, or the
;                                            bank the caller's stack is in --
;                                            remapping that would strand the
;                                            SWI2 frame the call returns through)
;   B_PAGE_ALLOC                             -> A = a free page (lowest first)
;   B_PAGE_FREE  B=page
;   B_PAGE_INFO                              -> X = installed pages, Y = free pages
;   B_PAGE_COPY  B=source page, E=destination page, X=source offset, Y=destination
;                offset, U=length: copies bytes between two pages whatever the
;                banks currently show, without disturbing the caller's mapping.
;                Neither range may run past the end of its 16KB page, and if both
;                are in the same page they may not overlap.
;
; Pages 0..3 are never handed out: page 0 is the system's, and pages 1..3 are the
; reset mapping of banks 1..3 (what a 64KB program like basic309 runs in). Pages at
; and beyond the installed RAM (found by PAGE_INIT's probe at reset) are marked used.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
PAGE_INIT        EXPORT
BANKS_IDENTITY   EXPORT
BIOS_BANK_GET    EXPORT
BIOS_BANK_SET    EXPORT
BIOS_PAGE_ALLOC  EXPORT
BIOS_PAGE_FREE   EXPORT
BIOS_PAGE_INFO   EXPORT
BIOS_PAGE_COPY   EXPORT
;------------------------------------------------------------------------------
BC_OK       EXTERN
BC_ERR      EXTERN
SBANK_1     EXTERN          ; main.asm: SBANK_1..SBANK_3 are consecutive bytes
;------------------------------------------------------------------------------
PC_CHUNKMAX equ  128         ; B_PAGE_COPY's chunk (PC_BOUNCE)
    SECT bss
PAGEMAP     RMB  32         ; one bit per page: 1 = used / not installed
NPAGES      RMB  2          ; installed RAM pages (4..256)
NFREE       RMB  2          ; pages B_PAGE_ALLOC can still hand out
PC_LEN      RMB  2          ; B_PAGE_COPY: bytes left to copy
PC_CHUNK    RMB  2          ; bytes in the current chunk
PC_SPAGE    RMB  1          ; source / destination page
PC_DPAGE    RMB  1
PC_TB       RMB  1          ; the bank used for the temporary mapping
PC_KEEPI    RMB  1          ; nonzero: the caller had interrupts masked, so leave them so
PC_BOUNCE   RMB  PC_CHUNKMAX ; each chunk goes source -> here -> destination
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
; Called once from V_RESET (after the stack is set up). Finds how many pages of RAM
; are installed and builds the allocation map. The probe writes a two-byte tag
; (page, ~page) at the start of every page from 255 down to 4, through bank 1,
; then reads them back in ascending order: the first page whose tag isn't intact
; is the end of the RAM (an uninstalled page reads back wrong, and a page that
; just aliases a lower one was overwritten by the lower page's tag, which is
; written later). Pages 0..3 are assumed present and are not touched. Bank 1 is
; put back at page 1 afterwards. Trashes A, B, X.
;------------------------------------------------------------------------------
PAGE_INIT   LDB  #255
PI_WRITE    STB  MBANK_1
            STB  $4000
            TFR  B,A
            COMA
            STA  $4001
            DECB
            CMPB #3
            BHI  PI_WRITE
            LDB  #4
PI_VERIFY   STB  MBANK_1
            CMPB $4000
            BNE  PI_COUNTED
            TFR  B,A
            COMA
            CMPA $4001
            BNE  PI_COUNTED
            INCB
            BNE  PI_VERIFY
PI_COUNTED  TSTB                  ; B = the first page that failed (0: all 256 present)
            BNE  PI_SET
            LDD  #256
            BRA  PI_STORE
PI_SET      CLRA
PI_STORE    STD  >NPAGES
            LDA  >SBANK_1         ; bank 1 back where the system had it
            STA  MBANK_1
            LDX  #PAGEMAP
            LDB  #32
PI_CLR      CLR  ,X+
            DECB
            BNE  PI_CLR
            LDB  #0
PI_MARK     CMPB #4
            BLO  PI_USED          ; pages 0..3: never handed out
            CLRA
            CMPD >NPAGES
            BLO  PI_NEXT          ; installed: free
PI_USED     BSR  PG_LOC           ; not installed: marked used
            ORA  ,X
            STA  ,X
PI_NEXT     INCB
            BNE  PI_MARK
            LDD  >NPAGES          ; and NFREE = every installed page from 4 up
            SUBD #4
            STD  >NFREE
            RTS
;------------------------------------------------------------------------------
; IN: B = a page. OUT: X -> its byte in PAGEMAP, A = its bit mask. B is kept.
;------------------------------------------------------------------------------
PG_LOC      PSHS B
            LSRB
            LSRB
            LSRB
            LDX  #PAGEMAP
            ABX
            PULS B
            PSHS B
            ANDB #7
            LDA  #1
PGL_SHIFT   TSTB
            BEQ  PGL_DONE
            ASLA
            DECB
            BRA  PGL_SHIFT
PGL_DONE    PULS B,PC
;------------------------------------------------------------------------------
; The SWI2 handlers. They read their arguments from, and return through, the
; caller's SWI2 frame (SWI2_* in defines.d) -- see main.asm's dispatcher notes: no
; JSR may be outstanding when they finish (BC_OK/BC_ERR/RTI end them), and BIOS
; variables are addressed with ">" (extended) because the caller's DP isn't ours.
;------------------------------------------------------------------------------
; Banks 1..3 back at pages 1..3 (the reset mapping), shadows included. Used when a
; program has crashed: whatever it did to the banks, the BIOS and the next program
; start from the mapping they expect. Trashes A.
BANKS_IDENTITY
            LDA  #1
            STA  >SBANK_1
            STA  MBANK_1
            INCA
            STA  >SBANK_1+1
            STA  MBANK_2
            INCA
            STA  >SBANK_1+2
            STA  MBANK_3
            RTS
;------------------------------------------------------------------------------
BIOS_BANK_GET
            LDB  SWI2_B,S
            CMPB #3
            BHI  BB_BAD
            CLRA                  ; bank 0 is always page 0
            TSTB
            BEQ  BBG_OUT
            LDX  #SBANK_1-1
            ABX
            LDA  ,X
BBG_OUT     STA  SWI2_A,S
            AIM  #$FE,SWI2_CC,S
            RTI
BB_BAD      LDA  #ERR_BADPARAM
            JMP  BC_ERR
;------------------------------------------------------------------------------
BIOS_BANK_SET
            LDB  SWI2_B,S
            BEQ  BB_BAD           ; bank 0 is fixed
            CMPB #3
            BHI  BB_BAD
            TFR  S,D              ; the bank the caller's stack is in ...
            ANDA #$C0
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            CMPA SWI2_B,S
            BEQ  BB_BAD           ; ... can't be remapped (see the file header)
            CLRA
            LDB  SWI2_E,S         ; the page: must be installed
            CMPD >NPAGES
            BHS  BB_BAD
            LDA  SWI2_E,S
            LDB  SWI2_B,S
            LDX  #SBANK_1-1
            ABX
            STA  ,X               ; the shadow first, then the register
            LDX  #BANK_BASE
            ABX
            STA  ,X
            JMP  BC_OK
;------------------------------------------------------------------------------
BIOS_PAGE_ALLOC
            LDX  #PAGEMAP
            LDB  #0
PA_BYTE     LDA  ,X+
            CMPA #$FF
            BNE  PA_FOUND
            INCB
            CMPB #32
            BNE  PA_BYTE
            LDA  #ERR_NOSPACE
            JMP  BC_ERR
PA_FOUND    COMA                  ; the 1 bits are now the free pages
            LDF  #0
PA_BIT      LSRA
            BCS  PA_GOT
            INCF
            BRA  PA_BIT
PA_GOT      ASLB
            ASLB
            ASLB
            ADDR F,B              ; B = byte*8 + bit = the page
            STB  SWI2_A,S
            LBSR PG_LOC
            ORA  ,X
            STA  ,X
            LDD  >NFREE
            SUBD #1
            STD  >NFREE
            AIM  #$FE,SWI2_CC,S
            RTI
;------------------------------------------------------------------------------
BIOS_PAGE_FREE
            LDB  SWI2_B,S
            CMPB #4
            BLO  BB_BAD           ; pages 0..3 are never allocated
            CLRA
            CMPD >NPAGES
            BHS  BB_BAD
            LBSR PG_LOC
            BITA ,X
            LBEQ BB_BAD           ; not allocated
            COMA
            ANDA ,X
            STA  ,X
            LDD  >NFREE
            ADDD #1
            STD  >NFREE
            JMP  BC_OK
;------------------------------------------------------------------------------
BIOS_PAGE_INFO
            LDD  >NPAGES
            STD  SWI2_X,S
            LDD  >NFREE
            STD  SWI2_Y,S
            JMP  BC_OK
;------------------------------------------------------------------------------
; B_PAGE_COPY. A chunk at a time, the source page is mapped into a bank and the
; chunk copied (TFM) into PC_BOUNCE, in the BIOS's RAM; then the destination page
; is mapped into the same bank and the chunk copied on from PC_BOUNCE. Interrupts
; are masked while the mapping differs from the caller's. The bank is 1, or 2 if
; the stack is in bank 1: never the stack's bank, since an interrupt that cannot
; be masked (the NMI tick) would push its frame onto whatever page is there, and
; never bank 3, whose top 4KB is hidden by the ROM and I/O (page offsets $3000-
; $3FFF can't be reached through it).
;------------------------------------------------------------------------------
BIOS_PAGE_COPY
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            LDU  SWI2_U,S
            CLRA
            LDB  SWI2_B,S
            CMPD >NPAGES
            LBHS BB_BAD
            STB  >PC_SPAGE
            CLRA
            LDB  SWI2_E,S
            CMPD >NPAGES
            LBHS BB_BAD
            STB  >PC_DPAGE
            TFR  U,D              ; both ranges must lie inside their page
            ADDD SWI2_X,S
            LBCS BB_BAD
            CMPD #$4000
            LBHI BB_BAD
            TFR  U,D
            ADDD SWI2_Y,S
            LBCS BB_BAD
            CMPD #$4000
            LBHI BB_BAD
            STU  >PC_LEN
            LDA  >PC_SPAGE
            CMPA >PC_DPAGE
            BNE  PC_NOOVERLAP
            LDD  SWI2_X,S         ; the same page: the ranges may not overlap
            SUBD SWI2_Y,S
            BPL  PC_ABS
            NEGD
PC_ABS      CMPD >PC_LEN
            LBLO BB_BAD
PC_NOOVERLAP
            LDD  >PC_LEN
            LBEQ BC_OK            ; nothing to copy
            TFR  S,D              ; the temporary bank: 1, or 2 if the stack is in bank 1
            LDB  #1
            ANDA #$C0
            CMPA #$40
            BNE  PC_BANK
            INCB
PC_BANK     STB  >PC_TB
            TFR  B,A              ; X, Y = the bank's window + the offsets
            LDB  #$40
            MUL
            TFR  B,A
            CLRB
            ADDR D,X
            ADDR D,Y
            LDA  SWI2_CC,S
            ANDA #$50             ; I or F set: the caller wants interrupts off
            STA  >PC_KEEPI
PC_LOOP     LDD  >PC_LEN
            BEQ  PC_DONE
            CMPD #PC_CHUNKMAX
            BLS  PC_SET
            LDD  #PC_CHUNKMAX
PC_SET      STD  >PC_CHUNK
            ORCC #$50             ; from here to the restore, the map is ours
            LDU  #BANK_BASE
            LDB  >PC_TB
            LDA  >PC_SPAGE        ; the source page: its chunk to PC_BOUNCE
            STA  B,U
            LDW  >PC_CHUNK
            PSHS Y
            LDY  #PC_BOUNCE
            TFM  X+,Y+
            PULS Y
            LDA  >PC_DPAGE        ; the destination page: the chunk from PC_BOUNCE
            STA  B,U
            LDW  >PC_CHUNK
            PSHS X
            LDX  #PC_BOUNCE
            TFM  X+,Y+
            PULS X
            LDU  #SBANK_1-1       ; put the caller's mapping back from the shadows
            LDA  B,U
            LDU  #BANK_BASE
            STA  B,U
            TST  >PC_KEEPI
            BNE  PC_KEEP
            ANDCC #$AF            ; the caller allowed interrupts: allow them again
PC_KEEP     LDD  >PC_LEN
            SUBD >PC_CHUNK
            STD  >PC_LEN
            BRA  PC_LOOP
PC_DONE     JMP  BC_OK
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of banks.asm
;------------------------------------------------------------------------------
