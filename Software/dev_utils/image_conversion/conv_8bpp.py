import struct,math,zlib
import pygame
import subprocess

#fname = 'advance_wars_rgb332.h'
fname = "psyg.h"

ASM_EXAMPLE = '''
;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - vdp experiment
; VERSION: 0.0.2
;    FILE: vdp.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
;------------------------------------------------------------------------------
    INCLUDE DEFINES.D           ; COMMON DEFINITIONS
    INCLUDE BIOS_FUNC_TAB.D     ; BIOS FCN JUMP TABLE AND CONSTANTS
;------------------------------------------------------------------------------
TICKS_PER_MINUTE    EQU  $3C0       ; 960
TICKS_PER_SECOND    EQU  $10        ; 16
EPOCH_YEAR          EQU  2024       ; BECAUSE 1970 TAKES LONGER TO COUNT. :D
; -----------------------------------------------------------------------------
    ORG     $1000               ; BEGIN CODE & VARS
; -----------------------------------------------------------------------------
; PROGRAM ENTRYPOINT
; -----------------------------------------------------------------------------
ENTRYPOINT  
    JMP  VDP_INIT
; -----------------------------------------------------------------------------
VDP_G7_SEQ  FCB $11,$87,$0E,$80,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$40
            FCB $00,$8E,$00,$40  ; SET 256 X 212 X 256 COLOR MODE
;            FCB $18,$99          ; BUMP IT TO YJK + YAE HIGH-COLOR MODE            
; -----------------------------------------------------------------------------
VDP_GRAF7   LDX  #VDP_G7_SEQ ; INIT 256 X 212 X 256 COLORS MODE ---------------
VDP_ILOOP7  LDA  ,X+        ; GET NEXT VDP INIT BYTE
            STA  VREG       ; WRITE TO VDP
            CMPX #VDP_GRAF7
            BLO  VDP_ILOOP7 ; LOOP UNTIL ALL BYTES SENT
            RTS                 
; -----------------------------------------------------------------------------
VDP_INIT    JSR  VDP_GRAF7
            ; for now, just load an incrementing color byte for eack of the 
            ; pixels of the display. (256*212 pixels/bytes)
            LDD  #0
            LDU  #IMG   
DRAWLOOP    LDE  ,U+
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
            STE  VDAT
            INCD
            CMPD #(256*212)
            BLO  DRAWLOOP
            RTS
~~~REPL~~~ENDIMG
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
'''
pygame.init()
screen=pygame.display.set_mode([256,212])#,flags=pygame.FULLSCREEN)
pygame.display.set_caption(f'conv')


npixels = None
pal = None 
img = None
width = None
height = None

def deflate(inp):
    zo = zlib.compressobj()
    return zo.compress(inp)+zo.flush()

def showAsm(lbl,arr):
    ostr = lbl+'\n'
    l=''
    j=0
    for b in arr:
        if l=='':
            l='    FCB '
        s=f'${b:02X},'
        l+=s
        j+=1
        if j==16:
            ostr+=l[0:-1]+'\n'
            l=''
            j=0
    if len(l):
        ostr+=l[0:-1]+'\n'
    return ostr

def printAsm(lbl,arr):
    print(lbl)
    l=''
    j=0
    for b in arr:
        if l=='':
            l='    FCB '
        s=f'${b:02X},'
        l+=s
        j+=1
        if j==16:
            print(l[0:-1])
            l=''
            j=0
    if len(l):
        print(l[0:-1])

def txtGetArray(i,htxt):
    arr=[]
    ss='['
    while not ';' in htxt[i]:
        s = htxt[i].strip()
        s = s.replace('{','[')
        s = s.replace('}',']')
        ss+=s
        i+=1
    ss+=']'
    arr = eval(ss)
    return arr,i

def txtGetFinalInt(l):
    toks = l.split(' ')
    x = int(toks[-1][0:-1],10)
    return x

def loadHFile():
    global npixels,pal,img,width,height, fname
    with open(fname,'rt') as f:
        htxt = f.read().split('\n')
        i = 0
        while i<len(htxt):
            l = htxt[i]
            #print(l)
            if 'static unsigned char header_data_cmap' in l:
                i+=1
                pal,i = txtGetArray(i,htxt)
            elif 'static unsigned char header_data' in l:
                i+=1
                img,i = txtGetArray(i,htxt)
                mval = -1
                for j in img:
                    if j>mval:
                        mval=j
                # calc pal size as lowest power of 2 which exceeds mval
                # 0..1 : 2
                # 2..3 : 4
                # 4..7 : 8 ...
                a = int(math.log(mval,2))
                palsize = int(math.pow(2,a+1))
                pal = pal[0:palsize]
            elif 'width =' in l:
                width = txtGetFinalInt(l)
                i+=1
            elif 'height =' in l:
                height = txtGetFinalInt(l)
                i+=1
            else:
                i+=1
        npixels = width*height

loadHFile()
outstr = ''

outstr+=f'IMG_WID     EQU     ${width:04X}\n'
outstr+=f'IMG_HEI     EQU     ${height:04X}\n'
outstr+='; -----------------------------------------------------------------------------\n'
# CONV PALETTE TO RGB332
outstr += 'PALETTE:\n'

l = '    FDB '
dupes = {}
qpal = []
for i in range(len(pal)):
    c = pal[i]
    r,g,b = c
    #print(i,r,g,b)
    qr = int(r*7/255)
    qg = int(g*7/255)
    qb = int(b*3/255)
    v = qg<<5 | qr<<2 | qb
    if v in qpal:  # note
        dupes[i] = qpal.index(v)
    qpal.append(v)
    l+=f"${v:04X},"
outstr += l[0:-1]+'\n'
#print(outstr)
outstr = ''

rarr = b''
ct = 1
px=0
py=0
bc=0
for a in range(0,npixels):
    val = img[a]
    rarr+= struct.pack('>B',qpal[val])

outstr+=showAsm('IMG',rarr)
output = ASM_EXAMPLE.replace('~~~REPL~~~',outstr)
with open('../CONV256.ASM','wt') as f:
    f.write(output)


