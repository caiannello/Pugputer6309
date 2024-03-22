# -----------------------------------------------------------------------------
# This is an experiment for Python 3 + pygame for reviewing graphics for use
# in the pugputer with video card.
#
# It loads font.png, outputs an assembly launguage version at font.asm, and
# shows the character set on screen along with a color palette.
#
# The render gets pretty close to showing things in the weird aspect ratio of 
# the V9958's 80-column text mode.
# -----------------------------------------------------------------------------
import pygame, sys, time
from pygame.locals import *
from pygame import display, surfarray, image, pixelcopy, transform
from copy import deepcopy
import numpy
import json
# -----------------------------------------------------------------------------
pygame.init()
# -----------------------------------------------------------------------------
# globals
# -----------------------------------------------------------------------------
char_surfs = WW = HH = SFW = SFH = SS = BB = None
# -----------------------------------------------------------------------------
# pugputer palette - combination of the 16-color PICO-8 palette
# and a few pairs simulating vintage monochrome CRT displays.
# -----------------------------------------------------------------------------
pal = [ 0x0000,0x1201,0x3201,0x0204,0x5102,0x3202,0x5505,0x7607,
        0x7200,0x7004,0x7106,0x0106,0x1705,0x4403,0x7503,0x7506,
        0x1000,0x6005,  # amber
        0x0001,0x0207,  # green
        0x0100,0x6707,  # white
      ]
# -----------------------------------------------------------------------------
def set80ColTextMode():
    global WW,HH,SFW,SFH,SS,BB        
    WW = 512            # internal screen size (MSX 2 hires text)
    HH = 212
    SFW = 5
    SFH = 9              # pixel up-scaling factors for aspect ratio
    # upscaled display screen
    SS = pygame.display.set_mode([WW*SFW, HH*SFH])
    # non-upscaled backing buffer
    BB = pygame.Surface([WW, HH], pygame.SRCALPHA, 32) 
# -----------------------------------------------------------------------------
# Load font from png file and colorize it in memory.
# -----------------------------------------------------------------------------
def loadPngFont(filename, as_color):
    global char_surfs
    char_surfs = []
    fsurf = pygame.image.load(filename)
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
# Save font as assembly language source code
# -----------------------------------------------------------------------------
def saveAsmFont(filename):
    with open(filename, 'w') as f:
        f.write("__FONT_BEGIN:\n")
        for i,charsurf in enumerate(char_surfs):
            f.write(f"; 0x{i:02x}\n")
            for r in range(0,8):
                f.write('    FCB    %')
                for c in range(0,6):
                    clr = charsurf.get_at((c,r))
                    oc = '1' if clr[0]>128 else '0'
                    f.write(oc)
                f.write('00\n')
        f.write("__FONT_END:\n")
# -----------------------------------------------------------------------------
# Given a V9958 color (9-bit RGB) returns a 24-bit RGB tuple (r8,g8,b8) 
# v9958 colors are organized as two bytes like this: %.rrr.bbb %.....ggg
# -----------------------------------------------------------------------------
def pugToRGB(x):
    red = x>>12
    green = x&7
    blue = (x>>8)&7
    return (int(red*255/7),int(green*255/7),int(blue*255/7))
# -----------------------------------------------------------------------------
# Converts a 24-bit RGB tuple into a V9958 9-bit color word
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
    global BB, WW, HH, SS, SFW, SFH, pal, char_surfs
    # initialize
    bg = pugToRGB(pal[20])
    text_fg = pugToRGB(pal[21])
    loadPngFont("font.png", as_color = text_fg)
    saveAsmFont("font.asm")
    set80ColTextMode()
    FPSCLOCK = pygame.time.Clock()
    # program main event loop    
    while True:  
        # clear screen to bg color
        BB.fill(bg)
        # draw palette
        for c in range(0,len(pal)):
            pygame.draw.circle(BB,pugToRGB(pal[c]), (10*c,5), 5)
        # draw charset
        sy = 20
        sx = 0
        col = 0
        for chridx in range(0,256):
            BB.blit(char_surfs[chridx],(sx,sy))
            sx  += 6
            col += 1
            if col>=16:
                col=0
                sx=0
                sy+=8
        # copy upscaled backing-buffer to screen
        SS.blit(transform.scale(BB, (WW*SFW, HH*SFH)), (0, 0))
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
    
