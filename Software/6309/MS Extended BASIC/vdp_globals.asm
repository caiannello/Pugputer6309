; -----------------------------------------------------------------------------
; VIDEO DISPLAY GLOBALS FOR USE BY VDP.ASM.  THEY ARE INCLUDED IN 
; IN GBASIC.ASM RAM, RIGHT BEFORE THE PROGRAM SPACE.
; VDP.ASM IS INCLUDED IN ROM NEAR THE START OF CODE.
; -----------------------------------------------------------------------------

; TEXT 2 MODE STUFF (80-COLUMNS, 24 ROWS)
VDP_TEXT2_BUFFER	RMB 80*27	SCREEN CHAR BUFFER
VDP_BUF_DIRTY_START RMW 1       ; POINTS TO FIRST MODIFIED CHAR IN SCREEN BUF
VDP_BUF_DIRTY_END   RMW 1       ; POINTS TO CHAR AFTER LAST MODIFIED IN SCREEN BUF
VDP_CURS_BUFPTR		RMW 1       CURSOR CHAR POINTER TO TEXT2 BUFFER
VDP_CURS_COL        RMB 1       CUR COL 0..(LINELENGTH-1)
VDP_CURS_ROW        RMB 1       CUR ROW 0..(LINECOUNT-1)
VDP_CURS_STYLE     	RMB 1       BIT MEANINGS:
								; BIT 0: 0-HIDDEN, 		1-VISIBLE
								; BIT 1: 0-UNDERLINE, 	1-BLOCK
								; BIT 2: 0-INSERT, 		1-OVERWRITE
								; BIT 3: 0-BLINK HIGH,	1-BLINK LOW
VDP_CURS_BLINKRATE  RMB 1       VBLANKS PER CURSOR STATE TOGGLE
VDP_CURS_BLINK_CT   RMB 1       CURRENT BLINK COUNT IN VBLANKS

VDP_VBLANK_ENABLED  RMB 1       TRUE IF VDP IS SET TO DO VBLANK INTERRUPTS (TEXT SCREEN AUTO-REFRESH)

VDP_INTERRUPT_REASON RMB 1 		VDP INTR STATUS REGISTER FOLLOWING PREV INTERRUPT