;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: time.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; The CPU Card has a clock oscillator which causes an NMI interrupt to occur
; 16 times each second. This is handled below to increment a tick count used
; for tracking time and date. NMI is wired directly to this routine (not
; through the RAM jump table) since it's core BIOS functionality that
; shouldn't be silently overridden -- see main.asm's interrupt vector table.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
RTC_TICKS       IMPORT      ; Number of 1/16 sec ticks since poweron or epoch
RTC_TICKS_PRIV  IMPORT
RTC_MTX         IMPORT      ; Mutex for the above
RTC_SET         IMPORT      ; Semaphore to update private val from public val
;------------------------------------------------------------------------------
V_NMI           EXPORT      ; Real-time oscillator handler
RTC_GETTIX      EXPORT
;------------------------------------------------------------------------------
    SECT code
; -----------------------------------------------------------------------------
; NMI ISR - Called @ 16 Hz. Maintains internal 64-bit tick count
; in RTC_TICKS_PRIV.
;
; A public version of this value, RTC_TICKS, is provided. To read it,
; software should first set the RTC_MTX semaphore to prevent the count from
; changing while it is being read. Afterwards, software should clear RTC_MTX
; to resume updates.
;
; To change the internal tick count, software should set RTC_MTX, change the
; value of RTC_TICKS, and then set RTC_SET. This will cause the ISR to
; set its internal count to the new value. After it has done so, it will clear
; both flags to signal that it's done.
; -----------------------------------------------------------------------------
; NOTE (fixed): "TFR 0,DP" is not "transfer the constant zero" (TFR only
; moves between named registers) -- see main.asm's V_RESET for the full
; explanation of why that silently set DP to $FF instead of $00 here on
; every single NMI tick (16/sec) since this file was written.
V_NMI       CLRA
            TFR  A,DP               ; Set direct page to adrs $0000 thru $00FF
            LDX  #RTC_TICKS_PRIV
            LDY  #RTC_TICKS
            LDW  #8
            LDD  <(RTC_TICKS_PRIV+6) ; increment private tick count
            ADDD #1
            STD  <(RTC_TICKS_PRIV+6)
            BCC  TIK_CNTD
            LDD  <(RTC_TICKS_PRIV+4)
            ADDD #1
            STD  <(RTC_TICKS_PRIV+4)
            BCC  TIK_CNTD
            LDD  <(RTC_TICKS_PRIV+2)
            ADDD #1
            STD  <(RTC_TICKS_PRIV+2)
            BCC  TIK_CNTD
            LDD  <(RTC_TICKS_PRIV+0)
            ADDD #1
            STD  <(RTC_TICKS_PRIV+0)
TIK_CNTD    LDA  <RTC_MTX           ; Check RTC_MTX semaphore, and if it's
            BNE  RTC_SKIP           ; in use, dont update public value.
            TFM  X+,Y+              ; Copy private val to public val,
            RTI                     ; RTC interrupt done.
RTC_SKIP    LDA  <RTC_SET           ; Set new internal tick count?
            BEQ  RTC_DONE           ; If no, we're done.
            TFM  Y+,X+              ; Copy public val to private val,
            CLR  <RTC_SET           ; Clear both semaphores to signal
            CLR  <RTC_MTX           ; completion,
RTC_DONE    RTI                     ; RTC interrupt done.
;------------------------------------------------------------------------------
; Load current 64-bit RTC tick count to address in X
;------------------------------------------------------------------------------
RTC_GETTIX  PSHS A,B,DP
            CLRA
            TFR  A,DP               ; see V_NMI's note above
            LDA  #1
            STA  <RTC_MTX
            LDD  <RTC_TICKS+0
            STD  ,X++
            LDD  <RTC_TICKS+2
            STD  ,X++
            LDD  <RTC_TICKS+4
            STD  ,X++
            LDD  <RTC_TICKS+6
            STD  ,X++
            CLR  <RTC_MTX
            PULS DP,B,A
            RTS
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of time.asm
;------------------------------------------------------------------------------
