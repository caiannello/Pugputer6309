"""Keeps this repository and the Pugputer6309_Emulator (beside it, ../Pugputer6309_Emulator) in
step: the files the two share, each copied from the repository where it's worked on.

  From the emulator (6309 software, worked on and tested there):
    bios/ sources                 -> Software/6309/bios/  (then pugbios.s19/.hex/_rom.bin rebuilt)
    the release SD image          -> Software/6309/sdcard/pugdisk.img
                                     (the emulator's mkdiskimg --add-dir demo/programs --sources .)
  From here (the video card, worked on on the hardware):
    Software/RP2350/video_misc/core/, src/, CMakeLists.txt -> vidcard/core/, vidcard/firmware/
    Hardware/Pico2_Video_Misc/VIDCARD.PLD, .jed            -> vidcard/hardware/

    python sync_emulator.py                    what differs (nothing is changed); exit 1 if anything
    python sync_emulator.py --apply            copy what differs
    python sync_emulator.py --build-emulator   run the emulator's build_all.bat notests first, so
                                               the SD image has its latest programs (with --apply too)
    python sync_emulator.py --apply --force    copy over uncommitted changes too (when they're
                                               an earlier sync's, not edits of their own)

A file is not overwritten if it has uncommitted changes where it would be copied to: an edit made
on the wrong side would be lost. It's reported instead; move the edit to the other side (or commit
or revert it) and run again. Text files are compared without regard to CRLF/LF; each is written
with the line endings its destination repository uses.

The SD image comes from the emulator's last build: --build-emulator rebuilds it first. Its BIOS
build uses the emulator's lwtools (lwtools/win_bin), Windows only (on Linux, run
Software/6309/bios/compile.sh by hand).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HW = os.path.dirname(os.path.abspath(__file__))
EMU = os.path.normpath(os.path.join(HW, '..', 'Pugputer6309_Emulator'))
TEXT = ('.c', '.h', '.pio', '.txt', '.asm', '.d', '.pld', '.md', '')

BIOS_FILES = ['banks.asm', 'devio.asm', 'helpers.asm', 'loader.asm', 'main.asm', 'sdcard.asm',
              'serio.asm', 'time.asm', 'defines.d', 'linker_script']
FW = 'Software/RP2350/video_misc'


def is_text(path):
    return os.path.splitext(path)[1].lower() in TEXT or path.endswith('CMakeLists.txt')


def read(path, text):
    with open(path, 'rb') as f:
        b = f.read()
    return b.replace(b'\r\n', b'\n') if text else b


def pairs():
    """(source, destination, transform or None), every shared file."""
    out = []
    for f in BIOS_FILES:
        out.append((os.path.join(EMU, 'bios', f), os.path.join(HW, 'Software/6309/bios', f), None))
    for f in ('vc.c', 'vc.h', 'vc_term.c', 'vc_font.c'):
        out.append((os.path.join(HW, FW, 'core', f), os.path.join(EMU, 'vidcard/core', f), None))
    for f in sorted(os.listdir(os.path.join(HW, FW, 'src'))):
        out.append((os.path.join(HW, FW, 'src', f), os.path.join(EMU, 'vidcard/firmware/src', f), None))

    def core_path(b):   # (the core is ./core here, ../core there)
        a = (b'# The card itself: the same C the emulator runs (Pugputer6309_Emulator\'s vidcard/core).\n'
             b'set(CORE ${CMAKE_CURRENT_LIST_DIR}/core)')
        if a not in b:
            sys.exit('sync_emulator: the firmware CMakeLists.txt no longer has the line setting CORE')
        return b.replace(a, b'set(CORE ${CMAKE_CURRENT_LIST_DIR}/../core)')

    out.append((os.path.join(HW, FW, 'CMakeLists.txt'), os.path.join(EMU, 'vidcard/firmware/CMakeLists.txt'),
                core_path))
    for f in ('VIDCARD.PLD', 'VIDCARD.jed'):
        out.append((os.path.join(HW, 'Hardware/Pico2_Video_Misc', f), os.path.join(EMU, 'vidcard/hardware', f), None))
    return out


def repo_of(path):
    return EMU if os.path.normcase(path).startswith(os.path.normcase(EMU)) else HW


def uncommitted(path):
    """True if path is tracked and has changes not committed (or is untracked but there)."""
    repo = repo_of(path)
    rel = os.path.relpath(path, repo)
    r = subprocess.run(['git', '-C', repo, 'status', '--porcelain', '--', rel], capture_output=True, text=True)
    return bool(r.stdout.strip())


def write(dst, data, text):
    if text:
        crlf = False
        if os.path.exists(dst):
            with open(dst, 'rb') as f:
                crlf = b'\r\n' in f.read()
        elif repo_of(dst) == HW:
            crlf = os.name == 'nt'   # (this repository's checkouts: autocrlf)
        if crlf:
            data = data.replace(b'\n', b'\r\n')
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, 'wb') as f:
        f.write(data)


def short(p):
    return os.path.relpath(p, os.path.dirname(HW))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--apply', action='store_true', help='copy what differs')
    ap.add_argument('--force', action='store_true', help='with --apply: copy over uncommitted changes too')
    ap.add_argument('--build-emulator', action='store_true', help="run the emulator's build_all.bat notests first")
    args = ap.parse_args()
    if not os.path.isdir(EMU):
        sys.exit('sync_emulator: no emulator repository at ' + EMU)

    if args.build_emulator:
        print('Building the emulator (build_all.bat notests)...')
        if subprocess.run(['cmd', '/c', os.path.join(EMU, 'build_all.bat'), 'notests'], cwd=EMU).returncode:
            sys.exit('sync_emulator: the emulator build failed')

    differ, held, copied, bios_changed = 0, [], 0, False
    for src, dst, fix in pairs():
        text = is_text(src)
        want = read(src, text)
        if fix:
            want = fix(want)
        have = read(dst, text) if os.path.exists(dst) else None
        if have == want:
            continue
        differ += 1
        what = 'new' if have is None else 'differs'
        if args.apply and not args.force and have is not None and uncommitted(dst):
            held.append(dst)
            print('  HELD   %s (%s; it has uncommitted changes there)' % (short(dst), what))
            continue
        print('  %s %s  <-  %s' % ('COPIED' if args.apply else what.upper().ljust(6), short(dst), short(src)))
        if args.apply:
            write(dst, want, text)
            copied += 1
            if 'Software/6309/bios' in dst.replace('\\', '/'):
                bios_changed = True

    # Files in the emulator's firmware copy that are gone from here.
    for f in sorted(os.listdir(os.path.join(EMU, 'vidcard/firmware/src'))):
        if not os.path.exists(os.path.join(HW, FW, 'src', f)):
            differ += 1
            print('  EXTRA  %s (not in %s/src: delete it if it was removed here)' %
                  (short(os.path.join(EMU, 'vidcard/firmware/src', f)), FW))

    # The BIOS's built ROM, as the emulator builds it.
    hw_s19 = os.path.join(HW, 'Software/6309/bios/pugbios.s19')
    emu_s19 = os.path.join(EMU, 'bios/pugbios.s19')
    if os.path.exists(emu_s19) and (not os.path.exists(hw_s19) or read(emu_s19, True) != read(hw_s19, True)):
        differ += 1
        print('  DIFFERS Software/6309/bios/pugbios.s19 and pugbios_rom.bin (the BIOS build)')
        bios_changed = bios_changed or args.apply
    if args.apply and bios_changed:
        if os.name != 'nt':
            print('  (rebuild the BIOS: Software/6309/bios/compile.sh)')
        else:
            env = dict(os.environ)
            win_bin = os.path.join(EMU, 'lwtools', 'win_bin')
            env.update(LWASM=os.path.join(win_bin, 'lwasm.exe'), LWLINK=os.path.join(win_bin, 'lwlink.exe'),
                       SRECCAT=os.path.join(win_bin, 'srec_cat.exe'))
            r = subprocess.run(['cmd', '/c', 'compile.bat'], cwd=os.path.join(HW, 'Software/6309/bios'), env=env,
                               capture_output=True, text=True)
            print('  BUILT  the BIOS (pugbios.s19, .hex, _rom.bin): burn pugbios_rom.bin' if r.returncode == 0
                  else '  FAILED the BIOS build:\n' + r.stdout + r.stderr)
            if r.returncode == 0 and read(emu_s19, True) != read(hw_s19, True):
                print('  WARNING: the BIOS built here differs from the emulator\'s pugbios.s19')

    # The SD image.
    mk = os.path.join(EMU, 'simulator', 'build', 'tools', 'Release', 'mkdiskimg.exe')
    img = os.path.join(HW, 'Software/6309/sdcard/pugdisk.img')
    if not os.path.exists(mk):
        print('  (the SD image: build the emulator first, or use --build-emulator: no ' + short(mk) + ')')
        differ += 1
    else:
        with tempfile.TemporaryDirectory() as tmp:
            new = os.path.join(tmp, 'pugdisk.img')
            r = subprocess.run([mk, '--out', new, '--add-dir', os.path.join(EMU, 'demo', 'programs'),
                                '--sources', EMU], cwd=EMU, capture_output=True, text=True)
            if r.returncode:
                sys.exit('sync_emulator: mkdiskimg failed:\n' + r.stdout + r.stderr)
            if not os.path.exists(img) or read(new, False) != read(img, False):
                differ += 1
                if args.apply and not args.force and os.path.exists(img) and uncommitted(img):
                    held.append(img)
                    print('  HELD   %s (it has uncommitted changes)' % short(img))
                else:
                    print('  %s %s  <-  the emulator\'s mkdiskimg' % ('COPIED' if args.apply else 'DIFFERS', short(img)))
                    if args.apply:
                        shutil.copyfile(new, img)
                        copied += 1

    if not differ:
        print('In step: nothing to copy.')
    elif args.apply:
        print('%d copied%s.' % (copied, ', %d held' % len(held) if held else ''))
    else:
        print('%d to copy: run with --apply.' % differ)
    return 1 if (differ and not args.apply) or held else 0


if __name__ == '__main__':
    sys.exit(main())
