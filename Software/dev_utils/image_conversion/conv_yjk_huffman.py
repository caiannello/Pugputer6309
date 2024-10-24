import struct,math,zlib
import pygame
import subprocess
import time
import datetime

# input image (must be 256x212 and already aspect corrected 1.154:1 )

fname = "hc_goblins.png"

# init graphics display
pygame.init()
WW = 256
HH = 212
SF = 4
screen=pygame.display.set_mode([WW*SF,HH*SF])#,flags=pygame.FULLSCREEN)
pygame.display.set_caption("ENCODING...")

# load input image and convert to an array of bytes r0,g0,b0,r1,g1,b1...
isurf = pygame.image.load(fname)
imgbytes = pygame.image.tobytes(isurf,"RGB")

###############################################
###############################################
# HUFFMAN DELTA-YJK IMAGE ENCODER
#
# NO RLE OR LEMPEL-ZIV ARE YET SUPPORTED, 
# SINCE I'M NOT FEELING TO FOR WRITING THE
# 6309 ASSEMBLY LANGUAGE VERSION OF SUCH A
# DECODER FOR USE IN THE PUGPUTER 6309.
#
# STILL, THIS HUFFMAN-ONLY APPROACH DOES GET 
# AROUND A 50% SIZE-REDUCTION ON TYPICAL 
# IMAGES.
###############################################
###############################################

# Start of huffman stuff
class NodeTree(object):
    def __init__(self, left=None, right=None):
        self.left = left
        self.right = right
    def children(self):
        return (self.left, self.right)
    def nodes(self):
        return (self.left, self.right)
    def __str__(self):
        return '%s_%s' % (self.left, self.right)

def huffman_code_tree(node, left=True, binString=''):
    if type(node) != NodeTree:  #in [tuple, int]:
        return {node: binString}
    (l, r) = node.children()
    d = dict()
    d.update(huffman_code_tree(l, True, binString + '0'))
    d.update(huffman_code_tree(r, False, binString + '1'))
    return d

def calcCodes(string):
    freq = {}
    for c in string:
        if c in freq:
            freq[c] += 1
        else:
            freq[c] = 1
    freq = sorted(freq.items(), key=lambda x: x[1], reverse=True)
    nodes = freq
    while len(nodes) > 1:
        (key1, c1) = nodes[-1]
        (key2, c2) = nodes[-2]
        nodes = nodes[:-2]
        node = NodeTree(key1, key2)
        nodes.append((node, c1 + c2))
        nodes = sorted(nodes, key=lambda x: x[1], reverse=True)
    return freq, huffman_code_tree(nodes[0][0])

def showCodes(freq, huffmanCode, orig, orig_bits):
    # show optimal code for each unique character of input
    symbol_table = []
    encoded_seq = []
    bitstring_symbol_table = f'{len(freq):016b}'
    #print(f'num rows serialized = {bitstring_symbol_table} (${len(freq):04X})')
    print('         Symbol |    Huffman code | Serialized')
    print('    -------------------------------------------')
    max_code_len = 0
    last_code_len = 0
    for (char, frequency) in freq:
        hcode = huffmanCode[char]
        table_element = (char, hcode)
        symbol_table.append(table_element)
        code_len = len(hcode)
        if code_len > max_code_len:
            max_code_len = code_len    
        code_len_bs = f'{code_len-1:04b}'
        delt_code_len = code_len - last_code_len
        delt_code_len_bs = f'{delt_code_len:04b}'
        last_code_len = code_len
        code_bs = hcode
        if orig_bits==6:
            dy = table_element[0]            
            dyb = f'{int_to_signed6_bitstring(dy)}'
            symb_bs = dyb 
            symb_hex = int(symb_bs,2)
        else: 
            j,k = table_element[0]
            jb = f'{int_to_signed6_bitstring(j)}'
            kb = f'{int_to_signed6_bitstring(k)}'           
            symb_bs = jb+kb 
            symb_hex = int(symb_bs,2)
        bitstring=delt_code_len_bs+code_bs+symb_bs
        bitstring_symbol_table+=bitstring
        print(f'     {table_element[0]:>10d} |{table_element[1]:>16s} : {bitstring:32s} {delt_code_len:02X} {int(hcode,2):04X} {symb_hex:02X}')
        #print ('     %10r |%16s : %32s' % (table_element[0], table_element[1], bitstring))
    # calculate raw verses encoded lengths for given input sequence
    orig_len_bits = 0
    compressed_len_bits = 0
    for char in orig:
        hcode = huffmanCode[char]
        orig_len_bits += orig_bits
        compressed_len_bits += len(hcode)
        encoded_seq.append(hcode)
    print('    ----------------------------------------------------')
    print(f'   unompressed bytes: {orig_len_bits/8}, compressed: {compressed_len_bits/8}  ')
    print(f'   huf code max len: {max_code_len}, size reduction: {100.0-(compressed_len_bits*100.0/orig_len_bits):0.02f} %')
    print(f'   code table len: {len(freq)} rows out of 64')

    return symbol_table, bitstring_symbol_table,encoded_seq

def huffmanEncode(label, sequence, symbol_nbits):
    print(f'\n{label} symbol table:\n')
    freq, huf_codes = calcCodes(sequence)
    code_table, bitstring_symbol_table, encoded_sequence = showCodes(freq, huf_codes, sequence, symbol_nbits)
    return code_table, bitstring_symbol_table, encoded_sequence

def int_to_signed6_bitstring(val):
    do_neg = False
    if val>=0:
        b = bin(val)[2:]
    else:
        b = bin(-val)[2:]
        do_neg = True
    lb = len(b)
    b='0'*(6-lb)+b
    if do_neg:
        # complement bits
        nb = ''
        for bit in b:
            if bit=='0':
                nb+='1'
            else:
                nb+='0'
        nb = int(nb,2)+1
        b=f'{nb:06b}'
    return b

# given a python signed int and bit-length, 
# returns a signed two's-complement version of
# the specified length.

def twos_comp(val, bits):
    if (val & (1 << (bits - 1))) != 0:  # if sign bit is set e.g., 8bit: 128-255
        val = val - (1 << bits)         # compute negative value
    return val     

# YJK to RGB helpers (Thanks Grauw!)

def clamp(x,a,b):
    if x<a:
        return a
    if x>b:
        return b
    return x

def ceil(x):
    return int(x+0.5)

def floor(x):
    return int(x)

def rgbToYJK(r,g,b):
    R = r/8.0
    G = g/8.0
    B = b/8.0
    Y = ceil((4.0*B+2.0*R+G)/8.0)
    J = int(R - Y)
    K = int(G - Y)
    return (Y,J,K) 

def yjkToRGB(Y,J,K):
    rr = clamp(Y+J,0,31)
    gg = clamp(Y+K,0,31)
    bb = clamp(floor((5.0*Y-2.0*J-K)/4.0),0,31)
    rr = int(rr*255/31)
    gg = int(gg*255/31)
    bb = int(bb*255/31)
    return (rr,gg,bb)

def bitStringToBytes(bitstring):
    led = len(bitstring)                     # pad bitstring out to a multiple of eight
    pad = '1'*(led%8)
    bitstring += pad
    obyt = b''                                  # convert bitsstring to bytes
    for bp in range(0,len(bitstring),8):
        bs = bitstring[bp:bp+8]
        bv = int(bs,2)
        obyt+=struct.pack('B',bv)
    return obyt     

# Convert rgb img into YJK img
yjkarr = []
j=0
for y in range(HH):
    for x in range(WW):
        r=imgbytes[j+0]
        g=imgbytes[j+1]
        b=imgbytes[j+2]
        j+=3
        yjk = rgbToYJK(r,g,b)
        yjkarr.append(yjk)

# Convert YJK data into raw v9958's 256x212 YJK image format 
# Pixels are grouped in fours, each getting its own 5-bit 
# luminance Y, but sharing a single 12-bit chrominance (J,K)

luminances = []  # luminance val for each pixel of image
chrominances = [] # chrominance (J,K) per every four pixels
uncompressed_img_out = b''
for j in range(0,len(yjkarr),4):
    y0 = yjkarr[j+0]
    y1 = yjkarr[j+1]
    y2 = yjkarr[j+2]
    y3 = yjkarr[j+3]
    luminances+=[y0[0],y1[0],y2[0],y3[0]]
    avj = round((y0[1] + y1[1] + y2[1] + y3[1])/4.0)
    avk = round((y0[2] + y1[2] + y2[2] + y3[2])/4.0)
    chrominances+=[(avj,avk)]
    #if j<64:
    #    print(f'{avj:3d},{avk:3d},{y0[0]:3d},{y1[0]:3d},{y2[0]:3d},{y3[0]:3d}')
    klow = avk&0b111
    khi  = (avk>>3)&0b111
    jlow = avj&0b111
    jhi  = (avj>>3)&0b111
    o0 = (y0[0]<<3) | klow
    o1 = (y1[0]<<3) | khi
    o2 = (y2[0]<<3) | jlow
    o3 = (y3[0]<<3) | jhi
    uncompressed_img_out+=struct.pack('BBBB',o0,o1,o2,o3)

# delta-encode the luminances
initial_y = ll = luminances[0]
y_deltas = [0]
for l in luminances[1:]:
    delt = l-ll
    y_deltas.append(delt)
    ll = l    
# delta encode the chrominance J's, and K's
initial_j = lj = chrominances[0][0]
j_deltas = []
initial_k = lk = chrominances[0][1]
k_deltas = []
for j,k in chrominances:
    delt = j-lj
    j_deltas.append(delt)
    lj = j
    delt = k-lk
    k_deltas.append(delt)
    lk = k

# interleave the delta-j, delta-k and delta-y sequences
# like this:
# dj0, dk0, dy0, dy1, dy2, dy3, 
# dj1, dk2, dy4, dy5, dy6, dy7, 
# ...
yjkdelt_orig_seq = []
orig_out = []
for i in range(len(j_deltas)):
    dj = j_deltas[i]
    dk = k_deltas[i]
    dy0 = y_deltas[i*4+0]
    dy1 = y_deltas[i*4+1]
    dy2 = y_deltas[i*4+2]
    dy3 = y_deltas[i*4+3]
    quart = [dj, dk, dy0, dy1, dy2, dy3 ]
    if len(orig_out)<21:
        orig_out+=quart
    yjkdelt_orig_seq += quart

# huffman encode the sequence
# (returns code table as dict, code table as bits, and encoded sequence as bits)
yjkdelt_codes, ycb, yjkdelt_huf_seq  = huffmanEncode("YJK Deltas", yjkdelt_orig_seq, 6)

#print(f'\ndelta encoded bitlens = {(len(ycb)+len(yjkdelt_huf_seq))/8}')

###############################################
###############################################
# BUILD THE COMPRESSED OUTPUT
###############################################
###############################################

# it starts with huffman code=symbol table
yjkdelt_huf = ycb
# then initial values for Y,J,K
yjkdelt_huf += int_to_signed6_bitstring(initial_y)
yjkdelt_huf += int_to_signed6_bitstring(initial_j)
yjkdelt_huf += int_to_signed6_bitstring(initial_k)
# and finally, the code sequence.
#for o in orig_out:
#    print(f'{o:<6d}',end='')
#print()
j=0
for i in yjkdelt_huf_seq:
    #if j<24:
    #    print(f"{i:6s}",end='')
    #    j+=1
    yjkdelt_huf += i
#print()
'''
for i in range(0,32,4):
    p0 = uncompressed_img_out[i+0]
    p1 = uncompressed_img_out[i+1]
    p2 = uncompressed_img_out[i+2]
    p3 = uncompressed_img_out[i+3]
    print(f'{p0:02x}{p1:02x}{p2:02x}{p3:02x}')
'''
yjkdelt_huf = bitStringToBytes(yjkdelt_huf)

# show some statistics
print(f'\n{initial_y=}, {initial_j=}, {initial_k=}\n')


###############################################
###############################################
# WRITE OUTPUT FILES 
###############################################
###############################################

# write raw uncompressed binary
with open('hicolor_raw_v9958.bin','wb') as f:
    f.write(uncompressed_img_out)

# and the compressed binary
with open('dhicolor_huff.bin','wb') as f:
    f.write(yjkdelt_huf)

# and a LWASM version
with open('../HUFFIMG.ASM','wt') as f:
    f.write('HUFFIMG:\n')
    l = ''
    j=0
    outb=0
    for b in yjkdelt_huf:
        if l == '':
            l = '    FCB '
        l += f'${b:02X},'
        outb+=1
        j+=1
        if j>=16:
            f.write(l[0:-1]+'\n')
            j=0
            l=''
    if len(l):
        f.write(l[0:-1]+'\n')
    f.write('HUFFIMG_END:\n')

###############################################
###############################################
# SHOW WHOLE CODE SEQUENCE FOR INSPECTION
###############################################
###############################################

# print(yjkdelt_huf_seq)

###############################################
###############################################
# DECODE TEST
###############################################
###############################################

print('\nDECODING, PLEASE WAIT...\n')

# note start time for duration report
now = datetime.datetime.now()
ts0 = now.timestamp()

# cursor for encoded input data
ibytepos = 0
ibitpos = 0

# cursor for huffman code table
tbytepos = 0
tbitpos = 0

# Returns specified number of bits, at the table cursor
# and advances the cursor position.
# result is returned as an integer.
def getTBits(num_bits):
    global tbytepos, tbitpos, yjkdelt_huf
    tinput_word = 0
    while num_bits:                
        keep_bits = 8-tbitpos
        if keep_bits>num_bits:
            keep_bits = num_bits
        inbyte = yjkdelt_huf[tbytepos]
        inbyte=(inbyte<<tbitpos)&0xff                
        inbyte>>=tbitpos
        inbyte>>=(8-(tbitpos+keep_bits))
        tinput_word<<=keep_bits            
        tinput_word|=inbyte        
        num_bits -= keep_bits
        # update input cursor (ibytepos,ibitpos)
        tbitpos+=keep_bits
        if tbitpos>=8:
            tbitpos %= 8
            tbytepos += 1    
    return tinput_word

# does initial parse of huffman code/symbol table to 
# find the next section of the input data.
# (Each symbol is a 6-bit signed integer representing
# a change of one color component, Y,J, or K, and 
# each corresponding code is a bit string of varying length.
# Code length increases for less-common symbols.)
def parseTable():
    lnum_elems = getTBits(16)
    tcode_sz = 0
    for telem in range(lnum_elems):
        delt_tcode_sz = getTBits(4)
        tcode_sz += delt_tcode_sz
        tcode = getTBits(tcode_sz)
        tsymbol = twos_comp(getTBits(6),6)

# decode the symbol at (ibytepos,ibitpos)
def decodeSymbol():
    global ibytepos,ibitpos
    global tbytepos,tbitpos
    global yjkdelt_huf        
    # init input shift register
    iinput_word = 0
    iinput_len = 0
    # reset t cursor to beginning of symbol table
    tbytepos = 0
    tbitpos = 0
    # get table num elements
    lnum_elems = getTBits(16)
    # iterate through table
    tcode_sz = 0
    for telem in range(lnum_elems):
        #tcode_sz = getTBits(4)+1
        delt_tcode_sz = getTBits(4)
        tcode_sz += delt_tcode_sz
        tcode = getTBits(tcode_sz)
        tsymbol = getTBits(6)
        # shift in more data bits as dictated by 
        # the next candidate code's length.
        if iinput_len<tcode_sz:
            num_bits = tcode_sz-iinput_len
            while num_bits:                
                keep_bits = 8-ibitpos
                if keep_bits>num_bits:
                    keep_bits = num_bits
                inbyte = yjkdelt_huf[ibytepos]
                inbyte=(inbyte<<ibitpos)&0xff                
                inbyte>>=ibitpos
                inbyte>>=(8-(ibitpos+keep_bits))
                iinput_word<<=keep_bits            
                iinput_word|=inbyte        
                iinput_len+=keep_bits
                num_bits -= keep_bits
                # update input cursor (ibytepos,ibitpos)
                ibitpos+=keep_bits
                if ibitpos>=8:
                    ibitpos %= 8
                    ibytepos += 1
        # if found matching code, return the corresponding symbol.
        if tcode == iinput_word:
            return tsymbol
    # if w gt hr, the input data is malformed.
    return None

# change window title 
pygame.display.set_caption(f'DECODE')

# position the table cursor past the code table.
parseTable()

# following the code table are the initial values of Y,J, and K.
Y = twos_comp(getTBits(6),6)
J = twos_comp(getTBits(6),6)
K = twos_comp(getTBits(6),6)

# The table cursor now points at the encoded image data.
# Set the input data cursor to this position.

ibytepos = tbytepos
ibitpos = tbitpos

# Changes in Y,J,K are signified by codes which 
# occur in the following order:
#
# dj0, dk0, dy0, dy1, dy2, dy3,
# dj1, dk1, dy4, dy5, dy6, dy7,
# ...
#
# (For every one change of chrominance (J,K), there's 
# four changes of luminance (Y), all-together describing 
# four pixel colors.)

# set initial pixel position onscreen to (x, y) = (0, 0)

x=0
y=0
for pidx in range(64*212):   # for each quartet of image pixels
    # decode delta-J and delta-K and update current (J,K).
    J += twos_comp(decodeSymbol(),6)
    K += twos_comp(decodeSymbol(),6)
    # Four times: encode next delta-Y, update Y, and plot pixel.
    for p in range(4):
        Y += twos_comp(decodeSymbol(),6)
        c = yjkToRGB(Y,J,K)
        pygame.draw.rect(screen, c, (x*SF,y*SF,SF,SF))
        x+=1    # update pixel x position
    if x>=WW:   # wrap at right edge of screen
        x=0
        y+=1

# display image
pygame.display.update()

# show decode duration
now = datetime.datetime.now()
ts1 = now.timestamp()
print(f'DONE! (Took: {ts1-ts0} sec)')
###############################################################################
# wait for user quit
###############################################################################
while True:
  for event in pygame.event.get():
    if event.type == pygame.QUIT:
      exit()
###############################################################################
# EOF
###############################################################################

