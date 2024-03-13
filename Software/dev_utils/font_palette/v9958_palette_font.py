# -----------------------------------------------------------------------------
# This is an experiment for Python 3 + pygame for reviewing graphics for use
# in the pugputer with video card.
#
# It parses font.asm, shows character set, and shows the color palette. It
# gets pretty close to showing things in the weird aspect ratio of the 
# V9958, so it might be a good starting point for a pugputer graphics editor,
# image viewer, or maybe even a pugputer emulator.
# -----------------------------------------------------------------------------
import pygame, sys, time
from pygame.locals import *
from pygame import display, surfarray, image, pixelcopy, transform
from copy import deepcopy
import numpy
import json
# -----------------------------------------------------------------------------
# Initialize graphic display 
# -----------------------------------------------------------------------------
pygame.init()
WW = 512            # internal screen size (MSX 2 hires text)
HH = 212
SFW = 5
SFH = 9              # pixel up-scaling factors for aspect ratio
# upscaled display screen
SS = pygame.display.set_mode([WW*SFW, HH*SFH])
# non-upscaled backing buffer
BB = pygame.Surface([WW, HH], pygame.SRCALPHA, 32) 

# pugputer palette - combination of the 16-color PICO-8 palette
# and a few pairs simulating vintage monochrome CRT displays.

pal = [ 0x0000,0x1201,0x3201,0x0204,0x5102,0x3202,0x5505,0x7607,
        0x7200,0x7004,0x7106,0x0106,0x1705,0x4403,0x7503,0x7506,
        0x1000,0x6005,  # amber
        0x0001,0x0307,  # green
        0x0100,0x6707,  # white
      ]

font = []
with open("font.asm") as f:
    ft = f.read().split('\n')
    chridx=0
    lidx=0
    char = []
    for line in ft:
        if 'FCB' in line:
            if lidx==0:
                print(f"; chidx 0x{chridx:02x} '{chr(chridx)}'")
            pidx = line.find('%')
            l = line[pidx+1:]
            l=l.replace('0','.')
            l=l.replace('1','#')
            print(l)
            for p in l:
                char.append(1 if p == '#' else 0)
            lidx+=1
            if lidx == 8:
                font.append(char)
                print(f"len char: {len(char)}")
                char = []
                lidx = 0
                chridx+=1
# -----------------------------------------------------------------------------
# given a V9958 color (9-bit RGB) returns a 24-bit RGB tuple (r8,g8,b8)
# v9958 colors are organized as two bytes like this: %.rrr.bbb %.....ggg
# -----------------------------------------------------------------------------
def pugToRGB(x):
    red = x>>12
    green = x&7
    blue = (x>>8)&7
    return (int(red*255/7),int(green*255/7),int(blue*255/7))
# -----------------------------------------------------------------------------
# Converts a 24-bit RGB tuple to a V9958 9-bit color word
# -----------------------------------------------------------------------------
def rgbToPug(r,g,b):
    pr = round(r*7.0/255.0)
    pg = round(g*7.0/255.0)
    pb = round(b*7.0/255.0)
    x = pr<<12|pb<<8|pg
    print(f"{r=} {g=} {b=}: 0x{x:04x}")
    return x
# -----------------------------------------------------------------------------
def main():
    global BB, WW, HH, SS, SFW, SFH, pal
    FPSCLOCK = pygame.time.Clock()
    while True:  # program main event loop
        BB.fill(pugToRGB(0x0100))
        for c in range(0,len(pal)):
            pygame.draw.circle(BB,pugToRGB(pal[c]), (10*c,5), 5)
        sy = 20
        sx = 0
        col = 0
        for chridx in range(0,256):
            char = font[chridx]
            for y in range(0,8):
                for x in range(0,6):
                    p = char[x+y*8]
                    if p:
                        BB.set_at((sx+x,sy+y),pugToRGB(0x6707))
            sx  += 6
            col += 1
            if col>=16:
                col=0
                sx=0
                sy+=8
        SS.blit(transform.scale(BB, (WW*SFW, HH*SFH)), (0, 0))
        pygame.display.flip()
        pygame.display.update()        
        for event in pygame.event.get():
            if ( event.type == pygame.QUIT ):
                return False    
            elif event.type == pygame.KEYDOWN:
                keys = pygame.key.get_pressed()
                if ( keys[pygame.K_ESCAPE] ):
                    return False
        FPSCLOCK.tick_busy_loop(60)    
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
    