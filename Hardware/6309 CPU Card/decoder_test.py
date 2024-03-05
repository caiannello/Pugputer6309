'''
Because my brain is not good at turning a memory
map into source code for a PAL, I turn to sloppy 
python code for help.
'''

bankregs = [0x3f]#, 0x01, 0x80, 0x80]

# for each bank
for bank in bankregs:
  # for every 4th byte of cpu address space 
  for adrs in range(0x0000,65536, 4):
    # make an array of cpu address bits a15...a0
    x  = adrs
    a = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
    for ad in range(0,16):
      b = x&1
      x>>=1
      a[ad] = b
    # make an array of bank register bits e21...e14
    x = bank
    e = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
    for ad in range(0,8):
      b = x&1
      x>>=1
      e[ad+14] = b
    # 0000 - efff  and bk 00 - 1f   RAM 0 chip
    # 0000 - efff  and bk 20 - 3f   RAM 1 chip
    # 0000 - efff  and bk 40 - ff   Offboard memory
    # f000 - ffeff, fff0-ffff, Fixed ROM
    # fff0 - ffef  IO space
    # ffb0 - ffbf  W65C22 Versatile Interface Adaptor
    # ffe0 - ffe3  Video Card music chip
    # ffe4 - ffe7  Video Card video chip
    # ffe8 - ffeb  Serial UART R65C51P2
    # ffec - ffef  Memory Bank Regs 0...3

    # preliminary logic - discrete logic on cpu card 

    hn3 = a[15]&a[14]&a[13]&a[12]  # high nybble is $f
    hn2 = a[11]&a[10]&a[9]&a[8]    # next nybble is $f
    ssf = a[7]&a[6]&a[5]
    hn1 = ssf&a[4]                 # third nybble is $f

    # inputs to PAL - hn3,hn2,hn1,ssf,e21,e20,e19,a3,a2
    # (not counting eclk and r//w)

    # outputs from PAL (not counting /rd,/wr,aux0)
    nram0 = hn3 | e[20] | e[21] | e[19]
    nram1 = hn3 | e[20] | e[21] | (not e[19])
    xmem  = (not hn3) & (e[20] | e[21])
    nrom  = (not hn3) | hn2 & (not hn1 )
    io    = hn3 & hn2 & (not hn1)
    nvia  = (not io) | (not a[7]) | a[6] | (not a[5]) | (not a[4])
    nopl3 = (not io) | (not a[7]) | (not a[6]) | (not a[5]) | a[4] | a[3] | a[2]   
    n9958 = (not io) | (not a[7]) | (not a[6]) | (not a[5]) | a[4] | a[3] | (not a[2])
    nuart = (not io) | (not ssf) | hn1 | (not a[3]) | a[2]
    nmap  = (not io) | (not ssf) | hn1 | (not a[3]) | (not a[2])

    # make a text string indicating what's been selected,
    # and maybe do some sanity checks. 
    sel = ''
    if not nvia:
      sel+='/via'
    if not nuart:
      sel+='/uart'
    if not n9958:
      sel+='/v9958'
    if not nopl3:
      sel+='/opl3'
    if not nmap:
      sel+='/mapw'
    if sel != '' and not io:
      print(f'SANITY: {sel=} {io=}')
      exit()
    if xmem:
      sel+='xmem'
    if not nram0:
      sel+='/ram0'
    if not nram1:
      sel+='/ram1'
    if not nrom:
      sel+='/rom'

    if io or not nrom:
      phyadrs = "    N/A"
    else:
      # a21...a14 come from bank register
      # a13...a0  come from cpu address
      phyadrs = f"${(adrs & 0b11111111111111) | (bank << 14):06x}"

    print(f"Bk: ${bank:02x}, CPUAdrs: ${adrs:04x}, PhyAdrs: {phyadrs}, Sel: {sel}")
