; -----------------------------------------------------------------------------
; Microsoft Extended BASIC adapted for the Pugputer 6309 bootloader.
; -----------------------------------------------------------------------------
; The original BASIC expects these console entry points.
KEYIN       EQU  GBASIC_KEYIN
PUTCHR      EQU  GBASIC_PUTCHR
KEYWAIT     EQU  GBASIC_KEYWAIT

; BIOS routines use bootloader state on direct page $00.
GBASIC_KEYIN
            PSHS DP
            LDA  #$00
            TFR  A,DP
            JSR  BF_UT_GETC
            ANDA #$7F
            PULS DP
            RTS

GBASIC_PUTCHR
            CMPA #CR
            BEQ  GBASIC_PUTCHR_CR
            INC  LPTPOS
            LDA  LPTPOS
            CMPA LPTWID
            BLO  GBASIC_PUTCHR_SEND
GBASIC_PUTCHR_CR
            CLR  LPTPOS
GBASIC_PUTCHR_SEND
            PSHS A
            PSHS DP
            LDA  #$00
            TFR  A,DP
            PULS A
            JSR  BF_UT_PUTC
            PULS DP
            RTS

GBASIC_KEYWAIT
            JSR  GBASIC_KEYIN
            BEQ  GBASIC_KEYWAIT
            RTS
