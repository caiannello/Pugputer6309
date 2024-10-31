###############################################################################
# PUGTERM - SERIAL TERMINAL FOR PUGPUTER 6309
#
# Pretty janky and lame at this point, but at least
# you can DRAG AND DROP S-RECORDS to the pugputer!
#
###############################################################################
import struct,math,zlib
import pygame
import subprocess
import time
import datetime
import serial
import threading
from copy import deepcopy
import queue
# -----------------------------------------------------------------------------
pygame.init()
# -----------------------------------------------------------------------------
# globals
# -----------------------------------------------------------------------------
SER_CONFIG = (19200,'com5')
TEXT_COLOR = (255, 200, 16)
BKGD_COLOR = (32, 16, 0)
g_thread_run = True
do_quit = False
q = queue.Queue(32767)


pygame.init()

WW = 640*2  # starting/current window dimensions in pixels
HH = 480*2

MAX_SCROLLBACK_LINES = 10000    # independent of line lengths
scrollback = []     # line scrollback buffer

termfont = None     # a monospaced pygame bitmap font
CHAR_HEIGHT = -1    # current pixel dimensions of a single monospaced char
CHAR_WIDTH = -1
WIN_MAXROWS = -1   # how many rows will fit at current font size
WIN_MAXCOLS = -1   #    .||.  cols   .||.

# scrollback line-index of beginning of 
# displayed text region
TOP_LIDX  = 0 

# scrollback line-index past the end of 
# displayed text region
BOT_LIDX = 0

# scrollback line-index and char index where we think the
# cursor should be.
CUR_LIDX, CUR_CIDX = 0,0

# scrollback line-index past the end of stored text
END_LIDX = 0

# used for timing display updates (60Hz, hopefully)
TLASTUPDATE = 0

screen=pygame.display.set_mode([WW,HH], pygame.RESIZABLE, vsync=1)
NORMAL_CAPTION = "PugTerm - Ver. 0.0.1"
UPLOADING_CAPTION = "PugTerm - Ver. 0.0.1 - UPLOADING"

pygame.display.set_caption(NORMAL_CAPTION)
ser = serial.Serial()
#------------------------------------------------------------------------------
def serThread(baudval, portval):
    global g_thread_run, q,ser
    ser.baudrate = baudval # e.g. 115200
    ser.port = portval # e.g. 'COM8'
    ser.timeout = 0.1
    ser.open()
    b = b''
    while g_thread_run:
        w = ser.in_waiting 
        if w:
            c=ser.read(w)
            q.put(c)
#------------------------------------------------------------------------------
# new window dims. re-layout the scrollback buf, 
# and update display. changed font size to 
# fit 80 cols to window width. updates globals containing
# current width and height in pixels of any (monospaced)
# character.
#------------------------------------------------------------------------------
def redraw():
    global scrollback
    global WW,HH,screen, termfont, TEXT_COLOR, BKGD_COLOR
    global CHAR_HEIGHT, CHAR_WIDTH
    global TOP_LIDX
    global BOT_LIDX
    global CUR_LIDX, CUR_CIDX
    global END_LIDX
    global WIN_MAXROWS, WIN_MAXCOLS
    global TLASTUPDATE

    # blank the display window
    pygame.draw.rect(screen,BKGD_COLOR,(0,0,WW,HH))
    
    # iteratively (slowly) determine font size to fit 80 cols
    # in given window width.
    ffh=0
    for fh in range(8,256):
        termfont = pygame.font.SysFont("Consolas", size=fh) 
        text_width, text_height = termfont.size("01234567890123456789012345678901234567890123456789012345678901234567890123456789")
        #print(text_width)
        if text_width<=(WW-8):
            CHAR_HEIGHT = ffh
            CHAR_WIDTH = text_width//80
            ffh = fh
        else:
            break
    if CHAR_WIDTH<=0 or CHAR_HEIGHT<=0:
        return
    termfont = pygame.font.SysFont("Consolas", size=ffh) 
    WIN_MAXROWS = (HH-8)//CHAR_HEIGHT
    WIN_MAXCOLS = (WW-8)//CHAR_WIDTH
    
    # layout the scroolback buf, starting from TOP_LIDX
    # to the display screen
    BOT_LIDX = TOP_LIDX
    cx = 0  # cur char pos x
    cy = 0  # cur char pos y
    rem_x = WIN_MAXCOLS # remaining char space x
    rem_y = WIN_MAXROWS # remaining char space y
    newline = False
    lws = len(scrollback)
    if lws>=WIN_MAXROWS:
        BOT_LIDX = TOP_LIDX = lws - WIN_MAXROWS

    #print('*********************************')
    #print(f'{TOP_LIDX=} {BOT_LIDX=} {CUR_LIDX=}')
    #for i,l in enumerate(scrollback):
    #    print(f'{i:3d}: >>>{l}<<<')

    while rem_y and (BOT_LIDX<len(scrollback)):
        s = scrollback[BOT_LIDX]
        text_width, text_height = termfont.size(s)
        if text_width:
            tsurf = pygame.font.Font.render(termfont,s, True, TEXT_COLOR, BKGD_COLOR)
            screen.blit(tsurf,(4+cx*CHAR_WIDTH,4+cy*CHAR_HEIGHT))
            CUR_LIDX = BOT_LIDX
            CUR_CIDX = len(s)
            if CUR_CIDX>=80:
                CUR_CIDX = 0
                CUR_LIDX += 1         
            cy+=1
            rem_y -= 1
            BOT_LIDX+=1
    END_LIDX = len(scrollback)

    cx = CUR_CIDX*CHAR_WIDTH
    cy = (CUR_LIDX-TOP_LIDX) * CHAR_HEIGHT
    pygame.draw.rect(screen,TEXT_COLOR,(cx+4,cy+4,CHAR_WIDTH,CHAR_HEIGHT))
    #print(f'{TOP_LIDX=} {BOT_LIDX=} dif:{BOT_LIDX-TOP_LIDX} out of {WIN_MAXROWS=} {END_LIDX=}')
    #print('*********************************')
    pygame.display.update()
    TLASTUPDATE = time.time()

#------------------------------------------------------------------------------
# given an imput string,
# split into segments following linefeeds, if any,
# and/or the end of string, and return all segments
# as a list of strings
#------------------------------------------------------------------------------
def segmentLines(s):
    global scrollback,TOP_LIDX,BOT_LIDX
    segs=[]
    if '\x1b[2J' in s:
        s = s.replace('\x1b[2J','')
        TOP_LIDX = BOT_LIDX=0
        scrollback = []
        redraw()
    if '\n' in s:
        while len(s):
            cat = s.find('\n')
            if cat>=0:
                seg = s[0:cat+1]
                s=s[cat+1:]
                segs.append(seg)
            else:
                segs.append(s)
                s=''
        return segs
    else:
        return [s]
#------------------------------------------------------------------------------
# We got some new characters in the scrollback buffer.
# Affect minimal updates to the display screen, scrolling and drawing
# new chars as needed.
# Does housekeeping to update TOP/BOT_LIDX to allow changes to be
# tracked.
#------------------------------------------------------------------------------
def refresh():
    global scrollback, CHAR_HEIGHT, CHAR_WIDTH
    global WW,HH,screen, termfont, TEXT_COLOR, BKGD_COLOR
    global TOP_LIDX
    global BOT_LIDX
    global CUR_LIDX, CUR_CIDX
    global END_LIDX
    global WIN_MAXROWS, WIN_MAXCOLS

    # of scrollback is too big, prune off retired lines 
    # and update line indexes
    if len(scrollback)>MAX_SCROLLBACK_LINES:
        extra = len(scrollback) - MAX_SCROLLBACK_LINES
        scrollback = scrollback[-MAX_SCROLLBACK_LINES:]
        TOP_LIDX -= extra
        BOT_LIDX -= extra

    END_LIDX = len(scrollback)
    OLDCT = BOT_LIDX - TOP_LIDX  # currently displayed linecount
    NEWCT = END_LIDX-BOT_LIDX    # number of new lines


    #print(f'REFRESH {TOP_LIDX=} {BOT_LIDX=} {OLDCT=} {END_LIDX=} {NEWCT=}')

    # find count of displayed lines plus new lines
    newheight = OLDCT + NEWCT

    if newheight <= WIN_MAXROWS:  # no scrolling needed:
        extra = 0
        cy = (OLDCT-1)*CHAR_HEIGHT
    else:
        extra = newheight-WIN_MAXROWS
        newheight = WIN_MAXROWS
        # blit remainder of old lines upward
        PY = extra*CHAR_HEIGHT
        screen.scroll(0,-PY)
        # blank uncovered region
        pygame.draw.rect(screen,BKGD_COLOR,(0,HH-PY,WW,PY))
        # update TOP_LIDX, init BOT_LIDX
        TOP_LIDX += extra
        cy = ((OLDCT-1)-extra)*CHAR_HEIGHT

    # draw new lines. bot_lidx should then == end_lidx
    l0 = BOT_LIDX-1
    l1 = END_LIDX
    for i in range(l0,l1):
        s = scrollback[i]
        text_width, text_height = termfont.size(s)
        if text_width:
            tsurf = pygame.font.Font.render(termfont,s, True, TEXT_COLOR, BKGD_COLOR)
            screen.blit(tsurf,(4,4+cy))
            CUR_LIDX = i
            CUR_CIDX = len(s)
            if CUR_CIDX>=80:
                CUR_CIDX = 0
                CUR_LIDX += 1                     
            cy+=CHAR_HEIGHT
    BOT_LIDX = END_LIDX

    cx = CUR_CIDX*CHAR_WIDTH
    cy = (CUR_LIDX-TOP_LIDX) * CHAR_HEIGHT
    pygame.draw.rect(screen,TEXT_COLOR,(cx+4,cy+4,CHAR_WIDTH,CHAR_HEIGHT))


    return
#------------------------------------------------------------------------------
# add new text to scrollback buffer (a list of text lines, each of length 80
# except for the last one, where the cursor is..
#------------------------------------------------------------------------------
def updateScrollback(s):
    global scrollback, CUR_LIDX, CUR_LIDX
    global TOP_LIDX, BOT_LIDX, END_LIDX

    # if prior last line in scrollback is unfinished,
    # get it for appending the incoming data
    if len(scrollback) and len(scrollback[-1])<80:
        lidx = len(scrollback)-1 
        startl = scrollback[lidx]
        extend = True
    else:
        lidx = len(scrollback)
        startl = ''
        extend=False
    # split on newlines
    segs = segmentLines(s)
    for i,seg in enumerate(segs):
        if i==0:
            l = startl+seg
        else:
            l = seg
        newline = False
        if l.endswith('\n'):
            newline = True
            l=l[0:-1]
        while True:
            if len(l)<80:
                if newline:
                    l+=' '*(80-len(l))
                if extend:
                    scrollback[lidx]=l
                    extend=False
                else:
                    scrollback.append(l)
                break
            else:
                scrollback.append(l[0:80])
                l=l[80:]
    refresh()  # update screen
#------------------------------------------------------------------------------
def myHandleEvent(event):
    global ser,do_quit,WW,HH
    if event.type == pygame.WINDOWRESIZED:
        if (WW != event.x) or (HH != event.y):
            WW = event.x
            HH = event.y
            redraw()
    elif event.type == pygame.DROPFILE:
        fname = event.file
        if fname.lower().endswith('.s19'):
            uploadSRecord(fname)
        else:
            print(f'UNKNOWN DROPFILE TYPE: {fname}')
    elif event.type == pygame.QUIT:
        do_quit = True
    elif event.type == pygame.KEYUP:
        if event.key == 13:  # b'\r' 
            ser.write( b'\n\r' )
        elif event.key == 99:  # ctrl-c
            ser.write( b'\x03' )
        elif event.key == 0x1b:  # escape
            ser.write( b'\x1b' )
    elif event.type == pygame.TEXTINPUT:
        zebytes = event.text.encode('utf-8')
        ser.write( zebytes )
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
def uploadSRecord(fname):
    global ser,screen,TEXT_COLOR,BKGD_COLOR,WW,HH,TLASTUPDATE
    print(f'Uploading S-Record: {fname}')
    pygame.display.set_caption(UPLOADING_CAPTION)
    try:
        with open(fname,'rt') as f:
            fdat=f.read().split()
        lfd = len(fdat)
        if lfd>1:
            ser.write(b'x\r')
            ser.flush()
            time.sleep(0.1)
            for i,line in enumerate(fdat):
                ser.write(line.encode('utf-8')+b'\r')
                ser.flush()
                event = pygame.event.poll()
                if event.type!=pygame.NOEVENT:
                    myHandleEvent(event)
                progress = i/(lfd-1)
                tnow = time.time()
                tdelt = tnow-TLASTUPDATE
                if tdelt>=(1/60):
                  TLASTUPDATE = tnow
                  barx = 4
                  bary = HH-36
                  barw = WW-8
                  barh = 30
                  pygame.draw.rect(screen,TEXT_COLOR,(barx,bary,barw,barh))
                  pygame.draw.rect(screen,BKGD_COLOR,(barx+2,bary+2,barw-4,barh-4))
                  if progress>0:
                    wid = int((barw-8)*progress)
                    pygame.draw.rect(screen,TEXT_COLOR,(barx+4,bary+4,wid,barh-8))
                  pygame.display.update()                    
            redraw()
    except Exception as e:
        print(f'Upload failed: {e}')
    pygame.display.set_caption(NORMAL_CAPTION)
#------------------------------------------------------------------------------
# do initial screen update
redraw()
# init the serial port
st = threading.Thread(target=serThread, args=SER_CONFIG)
# Start the serial reader thread
st.start()
#------------------------------------------------------------------------------
# main event loop
#------------------------------------------------------------------------------
while not do_quit:
  tin = b''
  while not q.empty():
    val = q.get_nowait()
    tin+=val
  if len(tin):
    tin=tin.replace(b'\r',b'') 
    tin=tin.replace(b'\xA8',b'|')   
    tin=tin.decode('utf-8',errors='replace')
    updateScrollback(tin)
  tnow = time.time()
  tdelt = tnow-TLASTUPDATE
  if tdelt>=(1/60):
    TLASTUPDATE = tnow
    pygame.display.update()
  for event in pygame.event.get():
    #pygame.display.update() 
    #if event.type not in [pygame.MOUSEMOTION, pygame.KEYDOWN, pygame.ACTIVEEVENT, pygame.WINDOWENTER, pygame.WINDOWLEAVE]:
    #    print(event.type, event)
    myHandleEvent(event)
g_thread_run = False
st.join()      
###############################################################################
# EOF
###############################################################################

