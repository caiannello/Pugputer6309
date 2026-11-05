/* The Pugputer 6309 video card, as portable C: its registers, its memory, the drawing
 * commands and the scanline renderer. The emulator (simulator/src/pugputer/video_device.cpp)
 * and the card's RP2350 firmware are meant to share this code, so that a program sees the
 * same card in both. What the card is to a program -- registers, memory map, modes,
 * commands -- is in ../README.md; the names below follow it.
 *
 * C99, no allocation, no I/O. A vc_card is about 260KB (the video memory is in it), so
 * give it static or heap storage, not the stack. */
#ifndef VIDCARD_VC_H
#define VIDCARD_VC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The picture: 640x480 at 60 frames a second, 525 lines a frame (480 shown). */
#define VC_WIDTH 640
#define VC_HEIGHT 480
#define VC_LINES 525
#define VC_FPS 60

/* The card's address space (24 bits), as the data ports see it. */
#define VC_VRAM_SIZE 0x40000u   /* $000000-$03FFFF video memory */
#define VC_CFG_BASE 0x040000u   /* $040000-$0403FF display settings and palette */
#define VC_CFG_SIZE 0x400u
#define VC_PAL_BASE 0x040200u   /* 256 colors, 2 bytes each (RGB565, big-endian) */
#define VC_PSRAM_BASE 0x800000u /* $800000-$FFFFFF the 8MB PSRAM, when there is one */
#define VC_PSRAM_SIZE 0x800000u

/* Registers: offsets from the card's base ($FF80). */
enum {
    VC_ADDR0_H = 0x00, VC_ADDR0_M, VC_ADDR0_L, VC_INC0_H, VC_INC0_L, VC_DATA0,
    VC_ADDR1_H = 0x06, VC_ADDR1_M, VC_ADDR1_L, VC_INC1_H, VC_INC1_L, VC_DATA1,
    VC_CTRL = 0x0C,   /* write: bit 7 resets the card */
    VC_STATUS = 0x0D, /* read: bit 7 in vertical blank, bit 6 commands busy, bit 5 queue full */
    VC_IEN = 0x0E,    /* interrupt enables (VC_IRQ_*) */
    VC_ISR = 0x0F,    /* interrupt flags; writing 1s clears them */
    VC_LINE_H = 0x10, /* read: the line being drawn (0-524); write: the line interrupt's line */
    VC_LINE_L = 0x11,
    VC_CMD = 0x12,    /* drawing commands, a byte at a time */
    VC_FRAME = 0x13,  /* frames shown, modulo 256 */
    /* Input: the mouse and keyboard on the card's USB port (the emulator's window). */
    VC_IN_CTRL = 0x14, /* bit 0 sprite 0 follows the mouse, bit 1 keys go to the card;
                          write bit 7: empty the key queue */
    VC_MOUSE_X_H = 0x15, /* read: 0-639 (reading this byte takes a snapshot of X and Y) */
    VC_MOUSE_X_L = 0x16,
    VC_MOUSE_Y_H = 0x17, /* read: 0-479, as of the snapshot */
    VC_MOUSE_Y_L = 0x18,
    VC_MOUSE_BTN = 0x19,   /* bit 0 left, 1 right, 2 middle; bit 7 a mouse has been seen */
    VC_MOUSE_WHEEL = 0x1A, /* wheel clicks since the last read, signed (+ is away from the user) */
    VC_KEY = 0x1B,      /* read: the next key event's USB usage code (0: none) */
    VC_KEY_CHAR = 0x1C, /* that event's character (0: none), bit 7 set if it was a release */
    VC_KEY_MODS = 0x1D, /* the modifier keys held now (VC_MOD_*) */
    VC_ID = 0x1E,     /* 'V' */
    VC_VERSION = 0x1F /* $11: 1.1 */
};
#define VC_REGS 0x20

#define VC_STATUS_VBLANK 0x80
#define VC_STATUS_BUSY 0x40
#define VC_STATUS_FULL 0x20
#define VC_STATUS_KEY 0x10 /* a key event is waiting */

#define VC_IRQ_VSYNC 0x01   /* the start of vertical blank (line 480) */
#define VC_IRQ_LINE 0x02    /* the start of the line set with VC_LINE_H/L */
#define VC_IRQ_CMDDONE 0x04 /* the command queue has emptied */
#define VC_IRQ_INPUT 0x08   /* a key event was queued, or the mouse moved or clicked */

#define VC_IN_POINTER 0x01 /* VC_IN_CTRL: sprite 0 is put where the mouse is, each frame */
#define VC_IN_KEYS 0x02    /* VC_IN_CTRL: keys typed go to the card (the emulator: not the UART) */
#define VC_IN_FLUSH 0x80   /* VC_IN_CTRL, written: empty the key queue */

/* VC_KEY_MODS: the USB boot keyboard's modifier byte. */
#define VC_MOD_LCTRL 0x01
#define VC_MOD_LSHIFT 0x02
#define VC_MOD_LALT 0x04
#define VC_MOD_LGUI 0x08
#define VC_MOD_RCTRL 0x10
#define VC_MOD_RSHIFT 0x20
#define VC_MOD_RALT 0x40
#define VC_MOD_RGUI 0x80

#define VC_KEY_QUEUE 32 /* key events the card holds; more are lost */

/* The display settings, at VC_CFG_BASE + these offsets. */
enum {
    VC_DC_CTRL = 0x00,   /* bits 0-2 layers 0-2 on, bit 3 sprites on */
    VC_DC_BACK = 0x01,   /* backdrop color: shows wherever every layer is transparent */
    VC_SPR_CTRL = 0x02,  /* bit 0: sprite coordinates are 640x480 pixels (else 320x240) */
    VC_SPR_COUNT = 0x03, /* sprite table entries in use, 0-128 */
    VC_SPR_BASE = 0x04,  /* 3 bytes: the sprite table's address */
    VC_LAYER0 = 0x10,    /* then 16 bytes a layer: */
    VC_L_MODE = 0x00,    /*   bits 0-1 type (VC_TEXT, VC_TILE, VC_BITMAP), bit 2 hires,
                               bits 3-4 bits per pixel (0-3: 1, 2, 4, 8), bit 5 big
                               (16x16 tiles, or a 16-line font) */
    VC_L_MAP = 0x01,     /*   bits 0-1 map width, 2-3 height: 32, 64, 128 or 256 cells */
    VC_L_MAPBASE = 0x02, /*   3 bytes: the map (text, tiles) or the pixels (bitmap) */
    VC_L_TILEBASE = 0x05, /*  3 bytes: the tiles' pixels, or the font */
    VC_L_HSCROLL = 0x08, /*   2 bytes */
    VC_L_VSCROLL = 0x0A, /*   2 bytes */
    VC_L_STRIDE = 0x0C,  /*   2 bytes: a bitmap's bytes per row */
    VC_L_PALOFS = 0x0E   /*   a bitmap's palette offset (x16) below 8 bits per pixel */
};
#define VC_LAYER_SIZE 0x10
#define VC_TEXT 0
#define VC_TILE 1
#define VC_BITMAP 2

/* Drawing commands (VC_CMD): the opcode, then its parameters; 16-bit ones big-endian,
 * coordinates signed. */
enum {
    VC_C_NOP = 0x00,
    VC_C_TARGET = 0x01,   /* addr:3 stride:2 width:2 height:2 bpp:1 -- where drawing goes */
    VC_C_COLOR = 0x02,    /* c:1 */
    VC_C_PLOT = 0x03,     /* x y */
    VC_C_LINE = 0x04,     /* x0 y0 x1 y1 */
    VC_C_RECT = 0x05,     /* x y w h */
    VC_C_FILLRECT = 0x06, /* x y w h */
    VC_C_CIRCLE = 0x07,   /* x y r */
    VC_C_DISC = 0x08,     /* x y r */
    VC_C_CLEAR = 0x09,    /* the whole target */
    VC_C_COPY = 0x0A,     /* src:3 dst:3 len:3 -- bytes, anywhere in the address space */
    VC_C_FILL = 0x0B,     /* dst:3 len:3 value:1 */
    VC_C_BLIT = 0x0C,     /* src:3 stride:2 w h x y flags:1 (bit 0: 0 is transparent) */
    VC_C_TRIANGLE = 0x0D, /* x0 y0 x1 y1 x2 y2, filled */
    VC_C_FONT = 0x0E,     /* addr:3 height:1 */
    VC_C_CHAR = 0x0F,     /* x y ch:1 */
    VC_C_COUNT
};

/* Where the card puts things at reset (see ../README.md, "At reset"). */
#define VC_RESET_SPR_BASE 0x037C00u
#define VC_RESET_TEXT_MAP 0x038000u
#define VC_RESET_FONT 0x03F000u

#define VC_MAX_LINE_SPRITES 32

typedef struct vc_card {
    uint8_t vram[VC_VRAM_SIZE];
    uint8_t cfg[VC_CFG_SIZE];
    uint8_t *psram;            /* VC_PSRAM_SIZE bytes, or NULL: no PSRAM (reads 0) */
    uint32_t addr[2];          /* the data ports */
    uint16_t inc[2];
    uint8_t ien, isr, frame;
    uint16_t line, irq_line;
    uint8_t cmd[16];           /* the command being received */
    uint8_t cmd_len;
    /* drawing state */
    uint32_t t_addr;
    uint16_t t_stride, t_w, t_h;
    uint8_t t_bpp, color;
    uint32_t font;
    uint8_t font_h;
    /* input */
    uint8_t in_ctrl;
    uint16_t mouse_x, mouse_y;   /* where the mouse is */
    uint16_t snap_x, snap_y;     /* as of the last read of VC_MOUSE_X_H */
    uint8_t buttons;             /* VC_MOUSE_BTN */
    int8_t wheel;
    uint8_t mods, caps_lock;
    uint8_t key_char;            /* VC_KEY_CHAR: the last event taken */
    uint8_t keyq[VC_KEY_QUEUE][2]; /* usage, character | $80 if released */
    uint8_t keyq_head, keyq_len;
} vc_card;

extern const uint8_t vc_font8x16[256 * 16];

/* Power-on state: registers, settings, the xterm palette, the font, a blank 80x30 text
 * screen on layer 0. The PSRAM (if any) is left as it is. */
void vc_reset(vc_card *c);

/* The CPU's side: a register read or write. */
uint8_t vc_read(vc_card *c, uint8_t reg);
void vc_write(vc_card *c, uint8_t reg, uint8_t value);
int vc_irq(const vc_card *c); /* the /IRQ output: an enabled flag is set */

/* The card's address space, without the ports' side effects. */
uint8_t vc_peek(const vc_card *c, uint32_t addr);
void vc_poke(vc_card *c, uint32_t addr, uint8_t value);

/* The input side: what the card's USB host (the emulator's window) reports. The mouse,
 * where it is now (clamped to the screen) or how far it moved, and which buttons are down
 * (VC_MOUSE_BTN's bits 0-2); the wheel, clicks turned; a key pressed or released, as its
 * USB HID usage code (page 7: 4 is A, $28 Enter, $E0-$E7 the modifiers). The card works out
 * the character a key types itself (a US layout), so the firmware and the emulator agree.
 * vc_reset() leaves the mouse's position and the keys held alone: they are the hardware's. */
void vc_mouse_to(vc_card *c, int x, int y, uint8_t buttons);
void vc_mouse_by(vc_card *c, int dx, int dy, uint8_t buttons);
void vc_mouse_wheel(vc_card *c, int clicks);
void vc_key(vc_card *c, uint8_t usage, int down);

/* The beam has reached `line` (0-524): the interrupt flags and frame count follow it. */
void vc_begin_line(vc_card *c, uint16_t line);

/* One line of the picture (0-479), as it looks now: 640 RGB565 pixels. */
void vc_render_line(const vc_card *c, int y, uint16_t *out);

/* RGB565 -> 0x00RRGGBB */
static inline uint32_t vc_rgb888(uint16_t p) {
    uint32_t r = (p >> 11) & 31, g = (p >> 5) & 63, b = p & 31;
    return ((r * 255 + 15) / 31) << 16 | ((g * 255 + 31) / 63) << 8 | ((b * 255 + 15) / 31);
}

#ifdef __cplusplus
}
#endif

#endif
