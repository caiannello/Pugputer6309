import struct,math,zlib
import pygame
import subprocess

fname = 'pcb.h'

ASM_EXAMPLE = '''
;------------------------------------------------------------------------------
; PROJECT: CONV.ASM
; VERSION: 0.0.1
;    FILE: MANA.ASM
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; DESCRIPTION: 
;   DRAWS A 4BPP HIRES BITMAP AS OUTPUT BY CONVERSION UTILITY
;
;------------------------------------------------------------------------------
    INCLUDE DEFINES.D           ; COMMON DEFINITIONS
    INCLUDE BIOS_FUNC_TAB.D     ; BIOS FCN JUMP TABLE AND CONSTANTS
;------------------------------------------------------------------------------
            ORG     $1000   ; VARS
; -----------------------------------------------------------------------------
; PROGRAM ENTRYPOINT
; -----------------------------------------------------------------------------
ENTRYPOINT  
    LDX  #VDP_G4_SEQ ; SET MODE GRAPHICS4
VDP_INIT    
    LDA  ,X+
    STA  VREG
    CMPX #(VDP_G4_SEQ+VDP_G4_SZ)
    BLO  VDP_INIT
    LDX  #PALETTE   ; SET 16-COLOR PALETTE
    LDA  #0
    STA  VREG
    LDA  #$90
    STA  VREG
    LDE  #0
SET_PAL     
    LDA  ,X+
    STA  VPAL
    LDA  ,X+
    STA  VPAL
    INCE
    CMPE #16
    BLO  SET_PAL
    LDA  #2
    STA  OUTELEMS
    LDU  #IMG       ; POINT X TO START OF RLE DATA
DRAWLOOP    
    LDA  ,U+        ; GET NEXT BYTE OF RLE DATA
    BMI  U16ELEM    ; IF TOP BIT SET, NEED TO GET ANOTHER BYTE.
U8ELEM              ; THIS PIXEL RUN IS ENCODED IN ONE BYTE:
    TFR  A,B 
    ANDB #15
    STB  PIXCOLR    ; PIXEL COLOR
    LSRA
    LSRA
    LSRA
    LSRA 
    INCA
    STA  PIXCNT+1   ; RUN LENGTH
DRAWPIXELS8  
    LDB  OUTBYTE
LOOPPIXELS8         ; SHIFT PIXEL INTO OUTPUT BYTE
    LSLB
    LSLB
    LSLB
    LSLB
    ORB  PIXCOLR
    DEC  OUTELEMS
    BNE  SKIPPLOT8
    STB  VDAT       ; EVERY FOUR PIXELS, SEND BYTE THE VDP
    LDA  #2
    STA  OUTELEMS       
    BRA  ELOOP8
SKIPPLOT8
    STB  OUTBYTE
ELOOP8
    DEC  PIXCNT+1   ; CHECK FOR END OF PIXEL RUN
    BNE  LOOPPIXELS8
    CMPU #ENDIMG    ; CHECK FOR END OF IMAGE
    BNE  DRAWLOOP
    RTS             ; IMAGE DONE.
U16ELEM             ; THIS PIXEL RUN IS ENCODED IN TWO BYTES:
    LDB  ,U+  
    ANDA #$7F
    TFR  D,W
    ANDB #15
    STB  PIXCOLR    ; PIXEL COLOR
    TFR  W,D
    LSRD
    LSRD
    LSRD
    LSRD
    INCD
    STD  PIXCNT     ; RUN LENGTH   
DRAWPIXELS          ; SHIFT PIXEL INTO OUTPUT BYTE
    LDB  OUTBYTE
LOOPPIXELS16
    LSLB
    LSLB
    LSLB
    LSLB
    ORB  PIXCOLR
    DEC  OUTELEMS
    BNE  SKIPPLOT
    STB  VDAT       ; EVERY FOUR PIXELS, SEND BYTE THE VDP
    LDA  #2
    STA  OUTELEMS       
    BRA  ELOOP
SKIPPLOT
    STB  OUTBYTE
ELOOP
    LDW  PIXCNT
    DECW
    STW  PIXCNT     ; CHECK FOR END OF PIXEL RUN
    BNE  LOOPPIXELS16
    CMPU #ENDIMG    ; CHECK FOR END OF IMAGE
    LBNE DRAWLOOP
    RTS             ; IMAGE DONE.
; -----------------------------------------------------------------------------
VDP_G4_SZ   EQU     16      ; INIT SEQ FOR VDP MODE GRAPHICS4 (512 X 212 X 16)
VDP_G4_SEQ  FCB     $10,$87,$0A,$80,$40,$81,$0A,$88,$80,$89,$1F,$82,$00,$8E,$00,$40
OUTBUF      RMB     64
PIXCOLR     RMB     1
PIXCNT      RMB     2
OUTBYTE     RMB     1
OUTELEMS    RMB     1
; -----------------------------------------------------------------------------
~~~REPL~~~ENDIMG
;------------------------------------------------------------------------------
; EOF
;------------------------------------------------------------------------------
'''
pygame.init()
screen=pygame.display.set_mode([512,424])#,flags=pygame.FULLSCREEN)
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
# PRINT PALETTE
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
    qb = int(b*7/255)
    v = qr<<12 | qb<<8 | qg
    if v in qpal:  # note
        dupes[i] = qpal.index(v)
    qpal.append(v)
    l+=f"${v:04X},"
outstr += l[0:-1]+'\n'

if len(dupes):
    print(f'{dupes=}')
# DO RLE ENCODING SCHEME ON INPUT DATA

rarr = b''
lval = img[0]
ct = 1
px=0
py=0
bc=0
for a in range(1,npixels):
    val = img[a]
    if val in dupes:
        val = dupes[val]
    if (val != lval) or (a == (npixels-1)) or (ct>=2040):
        if(ct<=8):
            x = ((ct-1)<<4)|lval            
            s = struct.pack('>B',x)
            rarr+=s
            bc+=1
        else:
            x = 0x8000|((ct-1)<<4)|lval
            try:
                s = struct.pack('>H',x)
            except Exception as e:
                print(ct,lval,x)
                exit()
            rarr+=s
            bc+=2
        #print(ct,lval)
        lval = val
        ct = 1
    else:
        ct +=1

# SHOW RLE IMAGE AND OUTPUT ASM FILE
px=0
py=0
pi=0
while pi<len(rarr):
    v = struct.unpack('>B',rarr[pi:pi+1])[0]
    if v&0x80:
        v = struct.unpack('>H',rarr[pi:pi+2])[0]
        pi+=2
        pclr = v&15
        pcnt = ((v&0x7fff)>>4)+1
    else:
        pclr = v&15
        pcnt = (v>>4)+1
        pi+=1
    #print(pcnt,pclr)
    v = qpal[pclr]
    rr = ((v>>12)&7)*(255/7)
    bb = ((v>>8)&7)*(255/7)
    gg = (v&7)*(255/7)
    rr=int(rr)
    gg=int(gg)
    bb=int(bb)
    for i in range(pcnt):
        #rr,gg,bb = pal[val]
        pygame.draw.line(screen, (rr,gg,bb), (px,py*2),(px,py*2+1))
        px+=1
        if px>=512:
            px=0
            py+=1
pygame.display.update()

outstr+=showAsm('IMG',rarr)
output = ASM_EXAMPLE.replace('~~~REPL~~~',outstr)
with open('../CONV.ASM','wt') as f:
    f.write(output)

# PACK IMAGE AS NYBBLES
packed = b''
b=0
ct=0
bc2 = 0
for a in range(0,npixels):
    val = img[a]
    b=(b<<4)|val
    ct+=1
    if ct==2:
        packed += struct.pack('>B',b)
        b=0
        ct=0
        bc2+=1
# ZX0-COMPRESS PACKED IMAGE        
with open('CONV.BIN',"wb") as f:
    f.write(packed)
epath = '..\\..\\pytools\\zx0.exe'
subprocess.run([epath,'-c','-f','CONV.BIN','CONV.ZX0'])    
with open('CONV.ZX0',"rb") as f:
    zx = f.read()

printAsm('ZX0',zx)

# DELATE PACKED IMAGE
defpack = deflate(packed)

# SHOW STATISTICS
print(f'rle sz: {bc}, packed sz: {len(packed)}, deflated packed sz: {len(defpack)}, packed zx0 sz: {len(zx)}')

while True:
  for event in pygame.event.get():
    if event.type == pygame.QUIT:  # Usually wise to be able to close your program.
      exit() # raise SystemExit
'''
packed = b''
b=0
ct=0
bc2 = 0
for a in range(0,npixels):
    val = reloc[img[a]]
    b=(b<<2)|val
    ct+=1
    if ct==4:
        packed += struct.pack('>B',b)
        b=0
        ct=0
        bc2+=1

showAsm('PACKED',packed)
defpack = deflate(packed)
showAsm('DEF_PACKED',defpack)
print(f'rle sz: {bc}, packed sz: {len(packed)}, deflated packed sz: {len(defpack)}')
'''
