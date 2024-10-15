import struct,math,zlib

'''

static unsigned int width = 512;
static unsigned int height = 212;

/*  Call this macro repeatedly.  After each use, the pixel data can be extracted  */

#define HEADER_PIXEL(data,pixel) {\
pixel[0] = header_data_cmap[(unsigned char)data[0]][0]; \
pixel[1] = header_data_cmap[(unsigned char)data[0]][1]; \
pixel[2] = header_data_cmap[(unsigned char)data[0]][2]; \
data ++; }

static unsigned char header_data_cmap[256][3] = {
	{  0,  0,  0},
	{ 71, 73, 70},
	{147,149,146},
	{255,255,255},
	{255,255,255},
	{255,255,255},
	{255,255,255},
	{255,255,255},
	{255,255,255},
	{255,255,255},
};
static unsigned char header_data[] = {
	3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
	3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
	};
'''

npixels = None
pal = None 
img = None
width = None
height = None

def deflate(inp):
	zo = zlib.compressobj()
	return zo.compress(inp)+zo.flush()

def showAsm(lbl,arr):
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
	global npixels,pal,img,width,height
	fname = 'pug_tiny_hires2bpp.h'
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

lbr = '; -----------------------------------------------------------------------------'

print(lbr)
print(f'IMG_WID     EQU     ${width:04X}')
print(f'IMG_HEI     EQU     ${height:04X}')
print(lbr)

areloc = [3,0,1,2]
reloc  = [1,2,3,0]

# PRINT PALETTE
print('PALETTE:')
l = '    FDB '
for i in range(len(pal)):
    c = pal[areloc[i]]
    r,g,b = c
    qr = int(r*7/255)
    qg = int(g*7/255)
    qb = int(b*7/255)
    v = qr<<12 | qb<<8 | qg
    l+=f"${v:04X},"
print(l[0:-1])

# DO RLE ENCODING SCHEME ON INPUT DATA

rarr = b''
lval = reloc[img[0]]
ct = 1
for a in range(1,npixels):
	val = reloc[img[a]]
	if (val != lval) or (a == (npixels-1)) or (ct>8190):
		if(ct<=32):
			x = ((ct-1)<<2)|lval			
			s = struct.pack('>B',x)
			rarr+=s
		else:
			x = 0x8000|((ct-1)<<2)|lval
			try:
				s = struct.pack('>H',x)
			except Exception as e:
				print(ct,lval,x)
				exit()
			rarr+=s
		#print(ct,lval)
		lval = val
		ct = 1
	else:
		ct +=1

# PRINT ENCODED DATA IN 6309 LWASM FORMAT
showAsm('IMG',rarr)
print(lbr)
print('; EOF')
print(lbr)

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
