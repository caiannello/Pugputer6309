import struct,math,zlib
import pygame
import subprocess

fname = "lily.png"

pygame.init()
screen=pygame.display.set_mode([256*2,212*2])#,flags=pygame.FULLSCREEN)
pygame.display.set_caption(f'conv')
isurf = pygame.image.load(fname)
imgbytes = pygame.image.tobytes(isurf,"RGB")

ASM_EXAMPLE = '''
;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 - vdp experiment
; VERSION: 0.0.2
;    FILE: CONV_HICOLOR.ASM
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Description:
;
; EXPERIMENTING WITH THE V9958 HIGHCOLOR MODES.
;
; I WROTE A PYTHON UTILITY, CONV_YJK.PY, WHICH CONVERTS 256X212-SIZED 
; PNG FILES INTO UNCOMPRESSED YJK BINARIES AS SEEN BELOW.
;
; YJK
;
;         C7  C6  C5  C4  C3  C2  C1  C0
; 1 dot   Y1                  Klow
; 1 dot   Y2                  Khigh
; 1 dot   Y3                  Jlow
; 1 dot   Y4                  Jhigh
; 
; YJK+YAE (SCREEN 10-11) (ALLOWS 16-COLOR PALETTE PIXELS, 
; ALONG WITH HICOLOR PIXEL QUARTETS)
;
;         C7  C6  C5  C4  C3  C2  C1  C0
; 1 dot   Y1               A  Klow
; 1 dot   Y2               A  Khigh
; 1 dot   Y3               A  Jlow
; 1 dot   Y4               A  Jhigh
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
VDP_G7_SEQ  FCB $00,$87,$0E,$80,$08,$99,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$40
            FCB $00,$8E,$00,$40  ; SET 256 X 212 X YJK+YAE COLOR MODE
; -----------------------------------------------------------------------------        
VDP_GRAF7   LDX  #VDP_G7_SEQ
VDP_ILOOP7  LDA  ,X+        ; GET NEXT VDP INIT BYTE
            STA  VREG       ; WRITE TO VDP
            CMPX #VDP_GRAF7
            BLO  VDP_ILOOP7 ; LOOP UNTIL ALL BYTES SENT
            RTS                 
; -----------------------------------------------------------------------------
; chroma, 12 bits, spread across four horiz pixels
; luma  upper 5 bits of each pixel
; -----------------------------------------------------------------------------
VDP_INIT    JSR  VDP_GRAF7
            LDU  #IMG
DRAWLOOP    
            LDA  ,U+
            STA  VDAT
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
            CMPU #ENDIMG
            BNE  DRAWLOOP

            RTS
;------------------------------------------------------------------------------
~~~REPL~~~ENDIMG
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
'''

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

j=0
for y in range(212):
    for x in range(256):
        r=imgbytes[j+0]
        g=imgbytes[j+1]
        b=imgbytes[j+2]
        j+=3
        pygame.draw.line(screen, (r,g,b), (x*2,y*2),(x*2+2,y*2+2))
pygame.display.update()

def clamp(x,a,b):
    if x<a:
        return a
    if x>b:
        return b
    return x

def ceil(x):
    return int(x+0.5)

'''
rgbpal = []
rgbdict = {}
yjkpal = []
yjkdict = {}
for Y in range(0,32):
    for J in range (-32,32):
        for K in range(-32,32):
            rr = clamp(Y+J,0,31)
            gg = clamp(Y+K,0,31)
            bb = clamp(int((5*Y-2*J-K)/4.0),0,31)            
            rgb = (int(rr),int(gg),int(bb))
            if not rgb in rgbpal:
                rgbpal.append(rgb)
                yjk = (int(Y),int(J),int(K))
                yjkpal.append(yjk)
                rgbdict[yjk]=rgb
                yjkdict[rgb]=yjk

print(len(yjkpal))
print(len(rgbpal))
'''

yjkarr = []
j=0
for y in range(212):
    for x in range(256):
        r=imgbytes[j+0]
        g=imgbytes[j+1]
        b=imgbytes[j+2]
        j+=3
        R = int(r/8)
        G = int(g/8)
        B = int(b/8)

        Y = ceil((4*B+2*R+G)/8)
        J = R - Y
        K = G - Y 
        yjk = (Y,J,K) 
        yjkarr.append(yjk)

output = b''
for j in range(0,len(yjkarr),4):
    y0 = yjkarr[j+0]
    y1 = yjkarr[j+1]
    y2 = yjkarr[j+2]
    y3 = yjkarr[j+3]
    avj = round((y0[1] + y1[1] + y2[1] + y3[1])/4)
    avk = round((y0[2] + y1[2] + y2[2] + y3[2])/4)
    
    klow = avk&0b111
    khi  = (avk>>3)&0b111
    jlow = avj&0b111
    jhi  = (avj>>3)&0b111

    o0 = (y0[0]<<3) | klow
    o1 = (y1[0]<<3) | khi
    o2 = (y2[0]<<3) | jlow
    o3 = (y3[0]<<3) | jhi
    output+=struct.pack('BBBB',o0,o1,o2,o3)

printAsm('IMG',output)
outstr=showAsm('IMG',output)
output = ASM_EXAMPLE.replace('~~~REPL~~~',outstr)
with open('../CONV_HICOLOR.ASM','wt') as f:
    f.write(output)


'''
x=0
y=0
for Y in range(0,32):
    for J in range (-32,32):
        for K in range(-32,32):
            rr = clamp(Y+J,0,31)
            gg = clamp(Y+K,0,31)
            bb = clamp(int((5*Y-2*J-K)/4.0),0,31)
            rr = int(rr*255/31)
            gg = int(gg*255/31)
            bb = int(bb*255/31)
            #print(f"{(rr,gg,bb)},",end="")
            pygame.draw.line(screen, (rr,gg,bb), (x*2,y*2),(x*2+2,y*2+2))
            x+=1
            if x==256:
                x=0
                y+=1
'''
pygame.display.update()
while True:
  for event in pygame.event.get():
    if event.type == pygame.QUIT:  # Usually wise to be able to close your program.
      exit() # raise SystemExit
