# -----------------------------------------------------------------------------
# This is an experiment for Python 3 + pygame for looking at an interesting
# 8-bit color palette that has two bits each for red, green, and blue,
# and the remaining two bits controlling overall lightness.
#
# One nice thing about this scheme is that you get 16 gray shades, as well
# as different saturations of the 64 basic colors.
# -----------------------------------------------------------------------------
import pygame
from pygame.locals import *
from pygame import display, surfarray, image, pixelcopy, transform
import math
import serial
# -----------------------------------------------------------------------------
pygame.init()
# -----------------------------------------------------------------------------
# globals
# -----------------------------------------------------------------------------
char_surfs = WW = HH = SFW = SFH = SS = BB = None
# -----------------------------------------------------------------------------
WW = 1920            # internal screen size (MSX 2 hires text)
HH = 1080
# upscaled display screen
SS = pygame.display.set_mode([WW, HH])
# -----------------------------------------------------------------------------
def makePaletteRGBI2222():
    rgbi2222 = []
    # program main event loop    
    for i in range(0,256):
        ridx = (i>>6) & 3
        gidx = (i>>4) & 3
        bidx = (i>>2) & 3
        iidx = (i>>0) & 3
        rr = int(ridx*85.0+iidx*21.25)
        gg = int(gidx*85.0+iidx*21.25)
        bb = int(bidx*85.0+iidx*21.25)
        if rr > 255:
            rr=255-11
        if gg > 255:
            gg=255-11
        if bb > 255:
            bb=255-11
        c = (rr,gg,bb)
        print(i,c)
        rgbi2222.append( c )
    return rgbi2222    
# -----------------------------------------------------------------------------
def makePaletteRGB222():
    rgb222 = []
    # program main event loop    
    for i in range(0,256):
        ridx = (i>>6) & 3
        gidx = (i>>4) & 3
        bidx = (i>>2) & 3
        rr = int(ridx*255/3)
        gg = int(gidx*255/3)
        bb = int(bidx*255/3)
        if rr > 255:
            rr=255
        if gg > 255:
            gg=255
        if bb > 255:
            bb=255
        c = (rr,gg,bb)
        print(i,c)
        rgb222.append( c )
    return rgb222       
# -----------------------------------------------------------------------------
def makePaletteRRRGGGBB():
    rgb332 = []
    # program main event loop    
    for i in range(0,256):
        ridx = (i>>5) & 7
        gidx = (i>>2) & 7
        bidx = (i>>0) & 3
        rr = int(ridx*36.4286)
        gg = int(gidx*36.4286)
        bb = int(bidx*85.0)
        if rr > 255:
            rr=255
        if gg > 255:
            gg=255
        if bb > 255:
            bb=255
        c = (rr,gg,bb)
        print(i,c)
        rgb332.append( c )
    return rgb332    
# -----------------------------------------------------------------------------
def drawPalette(x0,y0,colrs):
    global WW, HH, SS, SFW, SFH, pal
    for y in range(0,16):        
        for x in range(0,16):
            i = y*16+x                
            pygame.draw.rect(SS,colrs[i], (x*20+x0,y*20+y0,20,20), 0)
# -----------------------------------------------------------------------------
# Load font from png file and colorize it in memory.
# -----------------------------------------------------------------------------
def loadPng(filename):
    cidx = 0
    # for each glyph in 16x16 matrix of png file
    for cy in range(0,16):
        for cx in range(0,16):
            # make a surface for the glyph
            char_surf = pygame.Surface([6, 8], pygame.SRCALPHA, 32)
            char_surf.fill(as_color)
            sx = cx*6
            sy = cy*8
            char_surf.blit(fsurf,(0,0),(sx,sy,6,8),special_flags=pygame.BLEND_MULT)
            char_surf.set_colorkey((0,0,0))
            char_surfs.append(char_surf)
            cidx+=1              
# -----------------------------------------------------------------------------
def quantizeColor(c, colrs):
    bestat = -1
    bestdif = 99999999
    r0 = c[0]
    g0 = c[1]
    b0 = c[2]
    for i in range(0,len(colrs)):
        r1 = colrs[i][0]
        g1 = colrs[i][1]
        b1 = colrs[i][2]
        diff = math.sqrt((r0-r1)*(r0-r1)+(g0-g1)*(g0-g1)+(b0-b1)*(b0-b1))
        if diff<bestdif:
            bestdif = diff
            bestat = i
    return colrs[bestat]
# -----------------------------------------------------------------------------
def main():
    global WW, HH, SS, SFW, SFH, pal
    FPSCLOCK = pygame.time.Clock()
    rgbi2222 = makePaletteRGBI2222()
    rgb222 = makePaletteRGB222()

    rgb332 = makePaletteRRRGGGBB()
    isurf = pygame.image.load("24bit_palette.png")

    rgbi2222_surf = pygame.Surface([258, 200], pygame.SRCALPHA, 32)
    rgb222_surf = pygame.Surface([258, 200], pygame.SRCALPHA, 32)
    rgb332_surf = pygame.Surface([258, 200], pygame.SRCALPHA, 32)

    ser = serial.Serial()
    ser.baudrate = 115200
    ser.port = 'COM8'
    ser.open()

    '''
    for y in range(0,200):
        for x in range(0,258):
            c = isurf.get_at((x, y))
            qc = quantizeColor(c, rgbi2222)
            rgbi2222_surf.set_at((x, y),qc)
            qc = quantizeColor(c, rgb222)
            rgb222_surf.set_at((x, y),qc)
            qc = quantizeColor(c, rgb332)
            rgb332_surf.set_at((x, y),qc)
    '''
    graph = [ 0 for i in range(0,WW) ]
    b = b''
    val = 0.0
    while True:  
        c=ser.read()
        if c==b'\n':
            val = float(b.split(b'\t')[-1][0:-1].decode('utf-8'))
            y = (HH-1)-int(val*HH/1023.0)
            graph.append(y)
            graph = graph[1:]
            #print(val, y, len(graph) )
            b=b''
            SS.fill((0,0,0,255))
            j=0
            lasty = graph[0]
            for x in range(1,len(graph)):
                lastx = x-1
                y=graph[x]
                pygame.draw.line(SS,(255,0,255,255), (lastx, lasty),(x,y))
                lasty = y

            pygame.display.flip()            
            pygame.display.update()
            # check for events like quit or keypresses
            for event in pygame.event.get():
                if ( event.type == pygame.QUIT ):
                    return False    
                elif event.type == pygame.KEYDOWN:
                    keys = pygame.key.get_pressed()
                    if ( keys[pygame.K_ESCAPE] ):
                        return False
            #FPSCLOCK.tick_busy_loop(60)    
        else:
            b+=c

        # clear screen to bg color
        '''
        SS.fill((0,0,0,255))
        drawPalette(val,0,rgbi2222)
        SS.blit(isurf,(330,0),(0,0,258,200))
        SS.blit(rgbi2222_surf,(600,0),(0,0,258,200))

        drawPalette(0,320,rgb222)
        SS.blit(rgb222_surf,(330,320),(0,0,258,200))
        
        drawPalette(0,640,rgb332)
        SS.blit(rgb332_surf,(330,640),(0,0,258,200))
        '''


# -----------------------------------------------------------------------------
# Program entrypoint
# -----------------------------------------------------------------------------
if __name__ == '__main__':
    main()
    pygame.quit()
    print('Goodbye.')    
###############################################################################
# EOF
###############################################################################
    
