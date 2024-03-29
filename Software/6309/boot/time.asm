;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - bootloader 
; VERSION: 0.0.2
;    FILE: time.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; The CPU Card has a clock oscillator which causes an NMI interrupt to occur 
; 16 times each second. This is handled below to increment a tick count used
; for tracking time and date.
;
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; Global settings and definitions
;------------------------------------------------------------------------------
; Imports from other modules
;------------------------------------------------------------------------------
RTC_TICKS       IMPORT      ; Number of 1/16 sec ticks since poweron or epoch
RTC_TICKS_PRIV  IMPORT 
RTC_MTX         IMPORT      ; Mutex for the above
RTC_SET         IMPORT      ; Semaphore to update private val from public val
;------------------------------------------------------------------------------
; Exports for use by other modules
;------------------------------------------------------------------------------
V_NMI           EXPORT      ; Real-time oscillator handler
;------------------------------------------------------------------------------
    SECT bss                ; Private variables - section address $0030
    ENDSECT
;------------------------------------------------------------------------------
    SECT code               ; Section address  $F000 - $FF00
; -----------------------------------------------------------------------------
; NMI ISR - Called @ 16 Hz. Maintains internal 64-bit tick count.
;
; Notes: A public version of this value, RTC_TICKS, is provided. To read it,
; software should first set the RTC_MTX semaphore to prevent the count from
; changing while it is being read. Afterwards, software should clear RTC_MTX 
; to resume updates.
;
; To change the internal tick count, software should set RTC_MTX, change the
; value of RTC_TICKS, and then set RTC_SET. This will cause the ISR to 
; set its internal count to the new value. After it has done so, it will clear
; both flags to signal that it's done.
; -----------------------------------------------------------------------------
V_NMI       TFR  0,DP               ; Set direct page to adrs $0000 thru $00FF 
            LDD  <(RTC_TICKS_PRIV+0) ; increment private tick count
            ADDD #1
            STD  <(RTC_TICKS_PRIV+0)
            BCC  TIK_COUNTED
            LDD  <(RTC_TICKS_PRIV+4)
            ADDD #1
            STD  <(RTC_TICKS_PRIV+4)
TIK_COUNTED LDA  <RTC_MTX           ; Check RTC_MTX semaphore, and if it's
            BNE  RTC_SKIP           ; in use, dont update public value.
            LDD  <RTC_TICKS_PRIV    ; Sem. clear: Copy private val to
            STD  <RTC_TICKS         ; to public val.
            LDD  <RTC_TICKS_PRIV+4
            STD  <RTC_TICKS+4
            RTI                     ; RTC interrupt done.
RTC_SKIP    LDA  <RTC_SET           ; Set new internal tick count?
            BEQ  RTC_DONE           ; If no, we're done.
            LDD  <RTC_TICKS         ; Sem. set: Copy public val to
            STD  <RTC_TICKS_PRIV    ; to private val.
            LDD  <RTC_TICKS+4
            STD  <RTC_TICKS_PRIV+4
            CLR  <RTC_SET           ; Clear both semaphores to
            CLR  <RTC_MTX           ; signal completion.
RTC_DONE    RTI                     ; RTC interrupt done.
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; End of time.asm
;------------------------------------------------------------------------------
