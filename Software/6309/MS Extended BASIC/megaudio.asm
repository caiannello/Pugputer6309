; -----------------------------------------------------------------------------
; AUDIO CARD stuff
; -----------------------------------------------------------------------------
; -----------------------------------------------------------------------------
AUD_INIT:  ; Init audio card
    ; init globals
    LDA #0
    STA AUD_IRQ_FLAG
    RTS
; -----------------------------------------------------------------------------
AUD_IRQ:    ; Can be called by the megaudio card to acknowledge writes
    ; entire machine context should have been stacked
    LDA  $F200           ; READ CARD OUTPUT
    STA  AUD_RESPONSE    ; STASH IN A BUF
    LDA  #1              ; SET OUR INTERNAL INTERRUPT FLAG
    STA  AUD_IRQ_FLAG 

    RTI 
; -----------------------------------------------------------------------------
; EOF
; -----------------------------------------------------------------------------


