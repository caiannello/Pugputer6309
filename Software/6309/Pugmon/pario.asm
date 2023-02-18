;------------------------------------------------------------------------------
; PROJECT: PUGMON 
; VERSION: 0.0.1
;    FILE: main.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
;   Driver for the parallel bus interface. This card allows the pugputer to
;   be interfaced to a Teensy 4.1, or other microcontroller, for SD Card
;   file-system, audio, general IO, and misc. At some point, I think it will
;   also serve as a dedicated keyboard controller alongside the serial-
;   terminal as a source of keyboard input.
;
;   The parallel comms use a buffered, interrupt-driven protocol with CRC16 
;   error detection and retries. It seems pretty speedy, compared with 
;   serial comms.
;
; Theory of operation:
;
; The parallel interface is implemented with a couple 8-bit latches and
; a PLD, which intervene between the Teensy and the host CPU's data bus.
;
; One latch is for data sent from CPU to Teensy, and the other is for data
; sent from Teensy to CPU.
;
; In addition to eight bidirectional data lines, db0...db7, there are
; four handshake lines:
; 
;    CWR - CPU WRITE (Output, Active High)
;    CRD - CPU READ  (Output, Active Low)
;    UWR - MCU WRITE (Input,  Active High)
;    URD - MCU READ  (Input,  Active Low)
;
;    The function of these signals is further described below.
;
; CPU TRANSMIT (Not a closed loop)
;
; When the CPU writes a byte to the parallel card, the data is latched 
; in the transmit latch by a rising edge on the CWR line. The Teensy can
; see this signal, so it knows when a byte was written. The Teensy is
; configured to fire a pin-change interrupt on a rising edge of CWR.
; In the ISR (Interrupt handler), the Teensy will read out that byte:
; first it enables the transmit latch output by setting the URD line
; LOW, reads the value of signals db0...7db7, and finally, it sets URD
; back to HIGH.
;
; Currently, the CPU side is not made aware of a URD signal, but if we 
; ever wanted to make transmission be a closed-loop (flow-controlled) 
; operation, making the CPU aware of URD would be a good way. The Teensy 
; is nice and fast though, so hopefully it should have no trouble keeping 
; up with the reception of bytes from a vintage CPU anyway.
;
; CPU RECEIVE (Closed loop)
;
; The Teensy won't send bytes any faster than the CPU can read them. The 
; way this is accomplished is as follows:
;
; When the Teensy wants to write a byte, it presents the bits on db0...db7,
; and it brings the UWR signal HIGH. This latches the bits in the receive 
; latch, and it also begins an /NMI state on the CPU side. 
;
; In the CPU's NMI ISR, it does a read of the parallel port byte, which
; briefly causes a receive latch output enable signal (CRD) to go LOW.
;
; The Teensy sees that CRD signal, and it fires a different pin-change 
; interrupt on that falling edge. In the ISR, the Teensy returns it's UWR 
; line back to LOW, which ends the /NMI state on the CPU side. Until that
; happens, the Teensy won't try to send any more bytes.
;
; COMMUNICATIONS PROTOCOL
;
; Bytes are sent through the interface as packets in the following format:
;
; $A5, $5A, u8 PMsgType, u16 byte_cnt, u8 bytes[], u16 crc_16
;
; where $A5, $5A are single bytes, byte_cnt is the number of bytes that
; follow in the message, message types are described below, bytes are
; optional data payload, and CRC is a 16-bit CRC which uses a polynomial 
; of value $A001 and covers all message bytes besides itself. 
; 
; Not every message needs to have a data payload. In those cases, byte_cnt 
; will equal 2, and there will be no data bytes prior to the CRC. The 
; maximum payload size is 516 bytes. This is enough for 512-byte data with
; a 32-bit byte-address value. This is for use when, e.g. transferring a 
; file, in order to identify which part of the file is contained in the 
; message. There is currently no provision for sending multiple files 
; concurrently, but that might be accomplished by including some kind of 
; file ID value in the message too.
;
; Note that the vintage CPU that is currently being used in this project is
; an HD6309 which uses BIG-ENDIAN byte ordering, so this protocol does too.
; This means that an integer (16-bit, 32-bit value) is transmitted with 
; the most significant byte first. For example, a byte count value of 256
; would be sent as $01, $00. 
;
; Some other CPU's, including AVR and Intel x86, use LITTLE-ENDIAN byte-
; ordering, which is the opposite: the bytes of integers are stored with the
; the least significant byte first, e.g. a value $1234 would be stored 
; in memory and/or transmitted as $34 $12. Historically, some ARM CPUs have 
; been BI-ENDIAN, which means it is configurable which byte ordering is used, 
; but in the Teensy, I expect it uses LITTLE-ENDIAN to maintain Arduino 
; compatibility.  For this reason, if working with integers in the Teensy 
; which have originated from the HD6309, including the CRC and byte_count of 
; a received message, byte swapping may be involved when casting part of a 
; byte array as an integer.
;
;------------------------------------------------------------------------------

pa_init         EXPORT      ; no args
pa_clear        EXPORT
pa_acknowledge  EXPORT
pa_service      EXPORT
pa_send_msg     EXPORT      ; A: MsgType, X: PayloadSz or 0, Y:Payld Src. Adr.
PGotRxMsg       EXPORT
PFlags          EXPORT
PRxBuf          EXPORT
PRxHead         EXPORT
PMsgSize        EXPORT
PMsgEnd         EXPORT
CrcVal          EXPORT

JT_NMI          EXTERN      ; RAM interrupt jump table, NMI vector
con_puts        EXTERN
con_puteol      EXTERN
con_puthbyte    EXTERN

    INCLUDE defines.d       ; global settings and definitions

    SECT bss

CrcVal      rmb  2          ; crc16 temp val and result
PRxBuf      rmb  PBUFSZ     ; parallel input buffer
PRxHead     rmb  2          ; buf ptr - oldest char
PRxTail     rmb  2          ; buf ptr - newest char
PTxBuf      rmb  PBUFSZ     ; parallel output buffer
PTxHead     rmb  2          ; buf ptr - oldest char
PTxTail     rmb  2          ; buf ptr - newest char
PNextISR    rmb  2          ; address of next NMI ISR for fallthrough
PMsgType    rmb  1          ; latest received msg type
PMsgBCnt    rmb  2          ; latest received message byte count
PMsgSize    rmb  2          ; expected total size of an incoming message
PMsgEnd     rmb  2
PGotRxMsg   rmb  1          ; 1: received a valid message
PFlags      rmb  1          ; for debugging
    ENDSECT

    SECT code

; -----------------------------------------------------------------------------
; Clear parallel receive buffer and flags
; -----------------------------------------------------------------------------
pa_clear    clr  PFlags     ; clear debug flags
            clr  PGotRxMsg
            ldx  #PTxBuf    ; init tx buf pointers
            stx  PTxHead
            stx  PTxTail
            ldx  #PRxBuf    ; init rx buf pointers
            stx  PRxHead
            stx  PRxTail
            rts
; -----------------------------------------------------------------------------
; Send an acknowledgement msg to MCU when we have handled good msg from them.
; -----------------------------------------------------------------------------
pa_acknowledge
            jsr  pa_clear
            LDA  #PAR_MSG_ACK
            LDX  #0
            LDY  #0
            JSR  pa_send_msg
            rts      
; -----------------------------------------------------------------------------
; Sent when we gat a bad CRC on a received message.  If this is sent, or if 
; no response is sent before timeout, MCU should retransmit prev msg.
; -----------------------------------------------------------------------------
pa_non_acknowledge
            jsr  pa_clear
            LDA  #PAR_MSG_NAK
            LDX  #0
            LDY  #0
            JSR  pa_send_msg
            rts
; -----------------------------------------------------------------------------
; Sent when we get a valid message but cannot do what is requested for some
; reason. e.g. file not found, etc.
;
; TODO: allow an optional reason string to be specified by Y. 
; -----------------------------------------------------------------------------
pa_non_comply
            jsr  pa_clear
            LDA  #PAR_MSG_NAK
            LDX  #0
            LDY  #0
            JSR  pa_send_msg
            rts                        
; -----------------------------------------------------------------------------
; Parallel port init
; -----------------------------------------------------------------------------
pa_init     jsr  pa_clear
            ldx  JT_NMI+1   ; note preexisting NMI ISR address
            stx  PNextISR
            ldx  #pa_isr    ; insert our NMI ISR into the jump table
            stx  JT_NMI+1 
            rts
; -----------------------------------------------------------------------------
; Parallel port (/NMI) ISR: The interrupt signal starts whenever a byte has 
; been sent to us via parallel, and it ends when we read out the byte.
; If theres room in Rx buf, we add the incoming byte to it, else we do nothing.
;
; The housekeeping function, pa_service, gets called by mainloop, and it will
; determine if we have received a good message.
; -----------------------------------------------------------------------------
pa_isr      lda  PFlags
            ora  #1
            STA  PFlags
            ldx  PRxHead    ; check for space in rx buffer
            cmpx #(PRxBuf+PBUFSZ)
            blo  haveroom
            lda  PA_DAT     ; No space, clear NMI,
            rti             ; do nothing.
haveroom    lda  PA_DAT     ; get the new rx byte from parallel card.            
            sta  ,X+        ; store in buf at head, and inc. head.
            stx  PRxHead
            rti
; -----------------------------------------------------------------------------
; Parallel IO module - housekeeping service called by mainloop
;
; Checks the receive buffer for valid messages.
;
; todo: check for queued outgoing messages, and start transmission. Add some
; kind of logic to try to enforce half-duplex operation so we dont have
; bus contention.
; -----------------------------------------------------------------------------
pa_service  pshs  X,Y,A,B
            ldx   PRxHead
            cmpx  #PRxBuf
            beq   psvc_done ; rx buffer empty. 

            lda   PRxBuf
            cmpa  #$A5      ; trash whole buf if first byte isnt $A5
            bne   psvc_trash

            cmpx  #(PRxBuf+5) ; have enough bytes to check bytecount?
            blo   psvc_done    
        
            lda   PRxBuf+1
            cmpa  #$5A
            bne   psvc_trash ; trash whole buf if second byte isnt $5A

            ldd   PRxBuf+3   ; get message bytecount
            addd  #5         ; bytecount+5 is total message size
            cmpd  #PBUFSZ
            bgt   psvc_trash ; trash whole buf if bytecount isnt sane 
            
            std   PMsgSize
            addd  #PRxBuf
            std   PMsgEnd     
            cmpd  PRxHead
            bgt   psvc_done  ; dont have full message yet.

            jsr  crc_init    ; have full msg. calculate CRC
            ldx  #PRxBuf
            ldy  PMsgEnd
psvc_crclp  lda  ,X+
            jsr  crc16
            cmpr y,x
            blo  psvc_crclp
            
            jsr  crc_get    ; get final crc in D
            cmpd #0
            bne  psvc_nak   ; nonzero == bad. send NAK

            lda  #1         ; good crc
            sta  PGotRxMsg
            bra  psvc_done

psvc_nak    jsr  pa_non_acknowledge
            rts
psvc_trash  jsr  pa_clear
psvc_done   puls  X,Y,A,B
            rts
; -----------------------------------------------------------------------------
; pa_send_msg - send a protocol message out the comm port, blocking.
;
; maybe todo: have a tx service thats called by the main loop to send out
; bytes periodically rather than all in one loop.
;
; Args:
;   A = Message Type, X = Payload Size (or zero), Y = Payload Src. Address
; -----------------------------------------------------------------------------
PS_MSG      FCC  "PAR_TX: "
            FCB  0

pa_send_msg pshs y 
            LDY  #PS_MSG
            jsr  con_puts
            puls y
            ldu  #PTxBuf
            stu  PTxHead
            stu  PTxTail
            lde  #$A5
            ste  ,U+        ; $A5 +
            lde  #$5A
            ste  ,U+        ; $5A +
            sta  ,U+        ; MsgType +
            leax 2,X        ; (bytecount is payload len + 2-byte crc)
            stx  ,U++       ; ByteCnt +
            leax -2,X       ; 
            beq  sc_crc     ; If no payload, skip ahead to CRC.
sc_pl_cpy   lda  ,Y+        ; Copy payload into message
            sta  ,U+
            leax -1,X       
            bne  sc_pl_cpy  
sc_crc      stu  PTxTail    ; Set Tx Buffer Tail to end of message
            bsr  crc_init   ; Begin CRC calculation
            ldx  #PTxBuf
sc_calc     lda  ,X+        ; update CRC for each byte of message
            bsr  crc16
            cmpx PTxTail
            blo  sc_calc
            bsr  crc_get    ; Get final CRC result in D,
            stb  ,U+        ; append it to the message in little-endian order,
            sta  ,U+        ; because of stupid Intel.
            stu  PTxTail    ; update tx buf tail
            ldx  #PTxBuf
sc_loop     lda  ,X+        ; Send all bytes out right in this loop. 
            sta  PA_DAT     ; (if this causes unacceptable pauses,
            jsr  con_puthbyte
            nop             ; we can change it to be a reentrant service
            nop             ; called by the mainloop.)
            nop
            nop
            nop
            nop
            nop
            nop  
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            cmpx PTxTail
            blo  sc_loop
            jsr  con_puteol
            rts
; -----------------------------------------------------------------------------
; CRC16 ROUTINES - CRC-16/ARC ( POLYNOMIAL $A001, STARTVAL $0000 )
; -----------------------------------------------------------------------------
crc_init    pshs X 
            ldx  #0         ; init CRC16 calculator
            stx  CrcVal 
            puls X
            rts
; -----------------------------------------------------------------------------
crc_get     ldd  CrcVal     ; get final CRC result in D
            rts
; -----------------------------------------------------------------------------
; Called for each byte (in reg A) of message.
;
; uint16_t CrcVal = (CrcVal >> 8) ^ crc_tab[ (CrcVal ^ (uint16_t) A ) & 0xFF ];
;
; Note final result is in little endian byte order because CRC standards are
; intel-centric, and I wanted to check my work against known-good libs.
; For this reason, I byte-swap any generated CRC before appending it to an
; outgoing message. If this isn't done, when you calc CRC on a complete 
; message, including the final checksum, the result comes out nonzero even if
; the message is correct. 
; -----------------------------------------------------------------------------
crc16:      pshs X,A,B    
            ldx  CrcVal
            tfr  A,B
            lda  #0         ; D = (uint16_t)A
            eorr D,X        ; X = CrcVal ^ D 
            ldd  #$00FF
            andr X,D        ; D = X & 0xff
            lsld
            tfr  D,X        ; X = D * 2
            ldx  CRC_TAB,X  ; X = CRC_TAB[ X ]
            ldd  CrcVal     ; D = CrcVal
            tfr  A,B
            lda  #0         ; D = D >> 8
            eorr D,X        ; X = D ^ X
            stx  CrcVal     ; crcval = X
            puls X,A,B
            rts
; -----------------------------------------------------------------------------
; CRC Table - Polynomial $A001 (CRC-16/ARC)
; -----------------------------------------------------------------------------
CRC_TAB:
  FDB $0000,$C0C1,$C181,$0140,$C301,$03C0,$0280,$C241,$C601,$06C0,$0780,$C741,$0500,$C5C1,$C481,$0440
  FDB $CC01,$0CC0,$0D80,$CD41,$0F00,$CFC1,$CE81,$0E40,$0A00,$CAC1,$CB81,$0B40,$C901,$09C0,$0880,$C841
  FDB $D801,$18C0,$1980,$D941,$1B00,$DBC1,$DA81,$1A40,$1E00,$DEC1,$DF81,$1F40,$DD01,$1DC0,$1C80,$DC41
  FDB $1400,$D4C1,$D581,$1540,$D701,$17C0,$1680,$D641,$D201,$12C0,$1380,$D341,$1100,$D1C1,$D081,$1040
  FDB $F001,$30C0,$3180,$F141,$3300,$F3C1,$F281,$3240,$3600,$F6C1,$F781,$3740,$F501,$35C0,$3480,$F441
  FDB $3C00,$FCC1,$FD81,$3D40,$FF01,$3FC0,$3E80,$FE41,$FA01,$3AC0,$3B80,$FB41,$3900,$F9C1,$F881,$3840
  FDB $2800,$E8C1,$E981,$2940,$EB01,$2BC0,$2A80,$EA41,$EE01,$2EC0,$2F80,$EF41,$2D00,$EDC1,$EC81,$2C40
  FDB $E401,$24C0,$2580,$E541,$2700,$E7C1,$E681,$2640,$2200,$E2C1,$E381,$2340,$E101,$21C0,$2080,$E041
  FDB $A001,$60C0,$6180,$A141,$6300,$A3C1,$A281,$6240,$6600,$A6C1,$A781,$6740,$A501,$65C0,$6480,$A441
  FDB $6C00,$ACC1,$AD81,$6D40,$AF01,$6FC0,$6E80,$AE41,$AA01,$6AC0,$6B80,$AB41,$6900,$A9C1,$A881,$6840
  FDB $7800,$B8C1,$B981,$7940,$BB01,$7BC0,$7A80,$BA41,$BE01,$7EC0,$7F80,$BF41,$7D00,$BDC1,$BC81,$7C40
  FDB $B401,$74C0,$7580,$B541,$7700,$B7C1,$B681,$7640,$7200,$B2C1,$B381,$7340,$B101,$71C0,$7080,$B041
  FDB $5000,$90C1,$9181,$5140,$9301,$53C0,$5280,$9241,$9601,$56C0,$5780,$9741,$5500,$95C1,$9481,$5440
  FDB $9C01,$5CC0,$5D80,$9D41,$5F00,$9FC1,$9E81,$5E40,$5A00,$9AC1,$9B81,$5B40,$9901,$59C0,$5880,$9841
  FDB $8801,$48C0,$4980,$8941,$4B00,$8BC1,$8A81,$4A40,$4E00,$8EC1,$8F81,$4F40,$8D01,$4DC0,$4C80,$8C41
  FDB $4400,$84C1,$8581,$4540,$8701,$47C0,$4680,$8641,$8201,$42C0,$4380,$8341,$4100,$81C1,$8081,$4040
; -----------------------------------------------------------------------------
 ENDSECT code
;------------------------------------------------------------------------------
; End of pario.asm
;------------------------------------------------------------------------------
