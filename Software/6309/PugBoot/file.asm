;------------------------------------------------------------------------------
; PROJECT: PUGMON 
; VERSION: 0.0.1
;    FILE: file.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; functions related to file io
;------------------------------------------------------------------------------
    INCLUDE defines.d       ; Global settings and definitions
;------------------------------------------------------------------------------
; Module function imports
;------------------------------------------------------------------------------

; strings
S_LEN           EXTERN

; parallel io
pa_svc          EXTERN
pa_acknowledge  EXTERN
pa_send_msg     EXTERN
PGotRxMsg       EXTERN
PRxBuf          EXTERN
PMsgSize        EXTERN

; console
con_putc        EXTERN

;------------------------------------------------------------------------------
; EXPORTED FUNCTIONS
;------------------------------------------------------------------------------

FIL_GET         EXPORT
FIL_DIR         EXPORT
FIL_CAT         EXPORT

;------------------------------------------------------------------------------
; Misc Variables
;------------------------------------------------------------------------------
    SECT bss                ; Section Address $0018
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
    SECT code               ; Section address  $D000
; -----------------------------------------------------------------------------
; Request a file from SD card via parallel interface, and show it on the 
; console.
; -----------------------------------------------------------------------------
GFILE_NAME  FCC  "WAVY_PUG.BAS"
            FCB  0

FIL_GET     LDX  #GFILE_NAME        ; get len of filename into X
            JSR  S_LEN
            TFR  D,X 
            LDY  #GFILE_NAME        ; get address of filename into Y
            LDA  #PAR_MSG_GET_FILE  ; send cmd to get file
            JSR  pa_send_msg
            BRA  FIL_CAT
; -----------------------------------------------------------------------------
; Request a directory of files from SD card via parallel interface
; -----------------------------------------------------------------------------
FIL_DIR     LDA  #PAR_MSG_GET_DIR  ; send cmd to get dir
            LDX  #0
            LDY  #0
            JSR  pa_send_msg
            BRA  FIL_CAT
; -----------------------------------------------------------------------------
; List a file in the console as it comes in via the parallel port. These come
; as a series of zero or more PAR_MSG_DUMP messages, followed by a PAR_DUMP_END
; message. The payload in either case is a uint32_t file_byte_index, followed
; by zero or more file bytes.
;
; If a file request could not be fullfilled, a different type of message will
; come back: type PAR_MSG_NCOMP. The payload in this case will be four dummy 
; bytes, followed by an optional error message such as "File not found.\r\n"
; -----------------------------------------------------------------------------
FIL_CAT     JSR  pa_svc     ; wait for response.  todo: msg timeouts!
            LDA  PGotRxMsg
            BEQ  FIL_CAT
            LDW  #PRxBuf
            ADDW #9         ; skip header and index
            TFR  W,X        ; X is beginning of file content or errmsg
            LDW  #PRxBuf
            ADDW PMsgSize
            SUBW #2          
            TFR  W,Y        ; Y is end of file content or errmsg
cat_loop    LDA  ,X+        ; output chars to console from X to Y
            PSHS X,Y,A
            JSR  con_putc
            PULS X,Y,A
            CMPR Y,X
            BLO  cat_loop 

            ; If msgtype is PAR_MSG_DUMP, loop around for
            ; next part of file. If it is PAR_MSG_DUMP_END,
            ; this is the last msg of file. If it is
            ; PAR_MSG_NCOMP, the content is an error message.

            LDA  (PRxBuf+2) ; get msg type in A
            CMPA #PAR_MSG_DUMP
            BNE  done_cat
            
            ; send ack and loop around for next message
            JSR  pa_acknowledge 
            BRA  FIL_CAT

done_cat    JSR  pa_acknowledge ; Send ack to MCU.
            RTS
; -----------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; END OF FILE.ASM
;------------------------------------------------------------------------------
