/* The card as the machine's console: an ANSI (VT100 / xterm) terminal on the 80x30 text
 * screen the card has at reset.
 *
 * Out: each byte the CPU prints comes as a VC_C_TERM command, so it keeps its place among the
 * drawing commands. In: while the card is the console and the program hasn't taken the keys
 * (VC_IN_KEYS), what is typed is turned here into the bytes a terminal sends (the arrows as
 * ESC [ A and so on), and those and the terminal's replies wait in term.in for the CPU to read
 * through VC_KEY_CHAR.
 *
 * What it understands is what EDIT and BASIC use, and what programs commonly do besides: see
 * ../README.md, "The console". Sequences it doesn't know are read to their end and ignored.
 *
 * On the firmware the bytes are taken by core 0's main loop, the keys too, and the CPU's
 * reads by core 0's bus interrupt, so term.in has one writer and one reader, each owning its
 * own index. */
#include <string.h>

#include "vc.h"

#define COLS VC_TERM_COLS
#define ROWS VC_TERM_ROWS
#define ROW_BYTES (128u * 4u)   /* the map is 128 cells wide */
#define LINE_BYTES (COLS * 4u)  /* the part of a row that shows */

enum { GROUND, ESCAPE, CSI, OSC, SKIP_ONE };

static uint8_t *cell(vc_card *c, int x, int y) {
    return c->vram + VC_RESET_TEXT_MAP + (uint32_t)y * ROW_BYTES + (uint32_t)x * 4u;
}

/* The colors text is written in now. */
static void pen(const vc_card *c, uint8_t *fg, uint8_t *bg) {
    const vc_term *t = &c->term;
    uint8_t f = t->fg, b = t->bg;
    if (t->bold && f < 8) f = (uint8_t)(f + 8);
    if (t->inverse) {
        uint8_t k = f;
        f = b;
        b = k;
    }
    *fg = f;
    *bg = b;
}

/* Spaces from x0 up to (not including) x1 on row y, in the background color. */
static void blank(vc_card *c, int x0, int x1, int y) {
    uint8_t f, b;
    uint8_t *p = cell(c, x0, y);
    pen(c, &f, &b);
    for (; x0 < x1; ++x0, p += 4) {
        p[0] = ' ';
        p[1] = f;
        p[2] = b;
        p[3] = 0;
    }
}

static void clear_rows(vc_card *c, int y0, int y1) {
    for (; y0 < y1; ++y0) blank(c, 0, COLS, y0);
}

/* Rows top..bot (inclusive) move up n, blank ones coming in at the bottom. */
static void scroll_up(vc_card *c, int top, int bot, int n) {
    int y, h = bot - top + 1;
    if (n > h) n = h;
    for (y = top; y + n <= bot; ++y) memmove(cell(c, 0, y), cell(c, 0, y + n), LINE_BYTES);
    clear_rows(c, bot - n + 1, bot + 1);
}

static void scroll_down(vc_card *c, int top, int bot, int n) {
    int y, h = bot - top + 1;
    if (n > h) n = h;
    for (y = bot; y - n >= top; --y) memmove(cell(c, 0, y), cell(c, 0, y - n), LINE_BYTES);
    clear_rows(c, top, top + n);
}

/* Down a line, scrolling at the bottom of the region. */
static void index_down(vc_card *c) {
    vc_term *t = &c->term;
    if (t->y == t->bot) scroll_up(c, t->top, t->bot, 1);
    else if (t->y < ROWS - 1) ++t->y;
}

static void index_up(vc_card *c) {
    vc_term *t = &c->term;
    if (t->y == t->top) scroll_down(c, t->top, t->bot, 1);
    else if (t->y > 0) --t->y;
}

static void show(vc_card *c, uint8_t ch) {
    vc_term *t = &c->term;
    uint8_t *p;
    uint8_t f, b;
    if (t->pending) { /* the last column was written: the next character wraps */
        t->pending = 0;
        t->x = 0;
        index_down(c);
    }
    pen(c, &f, &b);
    p = cell(c, t->x, t->y);
    p[0] = ch;
    p[1] = f;
    p[2] = b;
    p[3] = 0;
    if (t->x < COLS - 1) ++t->x;
    else if (!t->no_wrap) t->pending = 1;
}

static void control(vc_card *c, uint8_t b) {
    vc_term *t = &c->term;
    switch (b) {
    case 0x08: /* backspace */
        if (t->x > 0) --t->x;
        t->pending = 0;
        break;
    case 0x09: /* tab */
        t->x = (uint8_t)((t->x | 7) + 1);
        if (t->x > COLS - 1) t->x = COLS - 1;
        t->pending = 0;
        break;
    case 0x0A: case 0x0B: case 0x0C: /* line feed */
        t->pending = 0;
        index_down(c);
        break;
    case 0x0D: /* carriage return */
        t->x = 0;
        t->pending = 0;
        break;
    default: break;
    }
}

/* For the CPU to read: all of it, or none if there isn't the room. */
static void reply(vc_card *c, const char *s, unsigned n) {
    vc_term *t = &c->term;
    uint8_t tail = t->in_tail;
    unsigned i;
    if ((unsigned)(VC_TERM_IN - (uint8_t)(tail - t->in_head)) < n) return;
    for (i = 0; i < n; ++i) t->in[(uint8_t)(tail + i) % VC_TERM_IN] = (uint8_t)s[i];
    t->in_tail = (uint8_t)(tail + n);
}

static unsigned put_num(char *s, unsigned v) {
    char d[6];
    unsigned n = 0, i = 0;
    do {
        d[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    while (n) s[i++] = d[--n];
    return i;
}

/* The nearest of xterm's 256 colors to a 24-bit one (the 6x6x6 cube or the gray ramp). */
static uint8_t nearest(int r, int g, int b) {
    static const uint8_t lv[6] = {0, 95, 135, 175, 215, 255};
    int ri = r < 48 ? 0 : r < 115 ? 1 : (r - 35) / 40;
    int gi = g < 48 ? 0 : g < 115 ? 1 : (g - 35) / 40;
    int bi = b < 48 ? 0 : b < 115 ? 1 : (b - 35) / 40;
    int avg = (r + g + b) / 3;
    int gray = avg > 238 ? 23 : avg < 3 ? 0 : (avg - 3) / 10;
    int gl = 8 + 10 * gray;
    int dr = r - lv[ri], dg = g - lv[gi], db = b - lv[bi];
    int ds = r - gl, dt = g - gl, du = b - gl;
    if (ds * ds + dt * dt + du * du < dr * dr + dg * dg + db * db) return (uint8_t)(232 + gray);
    return (uint8_t)(16 + 36 * ri + 6 * gi + bi);
}

static void sgr(vc_card *c) {
    vc_term *t = &c->term;
    int i, n = t->nparam + 1;
    for (i = 0; i < n; ++i) {
        unsigned p = t->param[i];
        if (p == 0) {
            t->fg = 7;
            t->bg = 0;
            t->bold = t->inverse = 0;
        } else if (p == 1) {
            t->bold = 1;
        } else if (p == 2 || p == 22) {
            t->bold = 0;
        } else if (p == 7) {
            t->inverse = 1;
        } else if (p == 27) {
            t->inverse = 0;
        } else if (p >= 30 && p <= 37) {
            t->fg = (uint8_t)(p - 30);
        } else if (p == 39) {
            t->fg = 7;
        } else if (p >= 40 && p <= 47) {
            t->bg = (uint8_t)(p - 40);
        } else if (p == 49) {
            t->bg = 0;
        } else if (p >= 90 && p <= 97) {
            t->fg = (uint8_t)(p - 90 + 8);
        } else if (p >= 100 && p <= 107) {
            t->bg = (uint8_t)(p - 100 + 8);
        } else if (p == 38 || p == 48) {
            uint8_t col = 0;
            if (i + 2 < n && t->param[i + 1] == 5) {
                col = (uint8_t)t->param[i + 2];
                i += 2;
            } else if (i + 4 < n && t->param[i + 1] == 2) {
                col = nearest(t->param[i + 2] & 255, t->param[i + 3] & 255, t->param[i + 4] & 255);
                i += 4;
            } else {
                return; /* (a form it doesn't know: the rest can't be told apart) */
            }
            if (p == 38) t->fg = col;
            else t->bg = col;
        }
    }
}

/* The alternate screen: the normal one is kept in video memory while it's in use. */
static void alt_screen(vc_card *c, int on) {
    vc_term *t = &c->term;
    int y;
    if (on == t->alt) return;
    t->alt = (uint8_t)on;
    if (on) {
        t->alt_x = t->x;
        t->alt_y = t->y;
        for (y = 0; y < ROWS; ++y) memcpy(c->vram + VC_TERM_SAVE + (uint32_t)y * LINE_BYTES, cell(c, 0, y), LINE_BYTES);
        clear_rows(c, 0, ROWS);
    } else {
        for (y = 0; y < ROWS; ++y) memcpy(cell(c, 0, y), c->vram + VC_TERM_SAVE + (uint32_t)y * LINE_BYTES, LINE_BYTES);
        t->x = t->alt_x;
        t->y = t->alt_y;
        t->pending = 0;
    }
}

static void private_mode(vc_card *c, int on) {
    vc_term *t = &c->term;
    int i;
    for (i = 0; i <= t->nparam; ++i) {
        switch (t->param[i]) {
        case 7: t->no_wrap = (uint8_t)!on; if (!on) t->pending = 0; break;
        case 25: t->cursor_off = (uint8_t)!on; break;
        case 47: case 1047: case 1049: alt_screen(c, on); break;
        default: break;
        }
    }
}

/* Parameter i, or d if it's missing or 0. */
static int arg(const vc_term *t, int i, int d) {
    return i <= t->nparam && t->param[i] ? t->param[i] : d;
}

static int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

static void csi(vc_card *c, uint8_t f) {
    vc_term *t = &c->term;
    int n = arg(t, 0, 1), y, x = t->x;
    if (t->priv == '?') {
        if (f == 'h') private_mode(c, 1);
        else if (f == 'l') private_mode(c, 0);
        return;
    }
    if (t->priv) return; /* (another private form, or one with an intermediate) */
    switch (f) {
    case 'A': t->y = (uint8_t)clamp(t->y - n, t->y >= t->top ? t->top : 0, ROWS - 1); break;
    case 'B': t->y = (uint8_t)clamp(t->y + n, 0, t->y <= t->bot ? t->bot : ROWS - 1); break;
    case 'C': case 'a': t->x = (uint8_t)clamp(t->x + n, 0, COLS - 1); break;
    case 'D': t->x = (uint8_t)clamp(t->x - n, 0, COLS - 1); break;
    case 'E': t->x = 0; t->y = (uint8_t)clamp(t->y + n, 0, t->y <= t->bot ? t->bot : ROWS - 1); break;
    case 'F': t->x = 0; t->y = (uint8_t)clamp(t->y - n, t->y >= t->top ? t->top : 0, ROWS - 1); break;
    case 'G': case '`': t->x = (uint8_t)clamp(n - 1, 0, COLS - 1); break;
    case 'd': t->y = (uint8_t)clamp(n - 1, 0, ROWS - 1); break;
    case 'H': case 'f':
        t->y = (uint8_t)clamp(arg(t, 0, 1) - 1, 0, ROWS - 1);
        t->x = (uint8_t)clamp(arg(t, 1, 1) - 1, 0, COLS - 1);
        break;
    case 'J':
        switch (t->param[0]) {
        case 0: blank(c, x, COLS, t->y); clear_rows(c, t->y + 1, ROWS); break;
        case 1: clear_rows(c, 0, t->y); blank(c, 0, x + 1, t->y); break;
        case 2: case 3: clear_rows(c, 0, ROWS); break;
        default: break;
        }
        return; /* (the cursor hasn't moved) */
    case 'K':
        switch (t->param[0]) {
        case 0: blank(c, x, COLS, t->y); break;
        case 1: blank(c, 0, x + 1, t->y); break;
        case 2: blank(c, 0, COLS, t->y); break;
        default: break;
        }
        return;
    case 'L': if (t->y >= t->top && t->y <= t->bot) { scroll_down(c, t->y, t->bot, n); t->x = 0; } break;
    case 'M': if (t->y >= t->top && t->y <= t->bot) { scroll_up(c, t->y, t->bot, n); t->x = 0; } break;
    case 'S': scroll_up(c, t->top, t->bot, n); return;
    case 'T': scroll_down(c, t->top, t->bot, n); return;
    case 'X': blank(c, x, clamp(x + n, 0, COLS), t->y); return;
    case '@':
        n = clamp(n, 0, COLS - x);
        memmove(cell(c, x + n, t->y), cell(c, x, t->y), (uint32_t)(COLS - x - n) * 4u);
        blank(c, x, x + n, t->y);
        break;
    case 'P':
        n = clamp(n, 0, COLS - x);
        memmove(cell(c, x, t->y), cell(c, x + n, t->y), (uint32_t)(COLS - x - n) * 4u);
        blank(c, COLS - n, COLS, t->y);
        break;
    case 'm': sgr(c); return;
    case 'r':
        y = clamp(arg(t, 1, ROWS), 1, ROWS);
        n = clamp(arg(t, 0, 1), 1, ROWS);
        if (n < y) {
            t->top = (uint8_t)(n - 1);
            t->bot = (uint8_t)(y - 1);
            t->x = t->y = 0;
        }
        break;
    case 's': t->save_x = t->x; t->save_y = t->y; return;
    case 'u': t->x = t->save_x; t->y = t->save_y; break;
    case 'n':
        if (t->param[0] == 5) {
            reply(c, "\x1b[0n", 4);
        } else if (t->param[0] == 6) {
            char s[16];
            unsigned i = 0;
            s[i++] = 0x1B;
            s[i++] = '[';
            i += put_num(s + i, t->y + 1u);
            s[i++] = ';';
            i += put_num(s + i, t->x + 1u);
            s[i++] = 'R';
            reply(c, s, i);
        }
        return;
    case 'c': reply(c, "\x1b[?1;0c", 7); return;
    default: return;
    }
    t->pending = 0;
}

void vc_term_reset(vc_card *c) {
    vc_term *t = &c->term;
    memset(t, 0, sizeof *t);
    t->fg = 7;
    t->bot = ROWS - 1;
}

void vc_term_byte(vc_card *c, uint8_t b) {
    vc_term *t = &c->term;
    t->started = 1;
    if (t->state == OSC) { /* a title or the like: to BEL or ESC \ */
        if (b == 0x07) t->state = GROUND;
        else if (b == 0x1B) t->state = SKIP_ONE;
        return;
    }
    if (b == 0x1B) {
        t->state = ESCAPE;
        return;
    }
    if (b == 0x18 || b == 0x1A) { /* CAN, SUB: a sequence given up */
        t->state = GROUND;
        return;
    }
    if (b < 0x20) {
        control(c, b);
        return;
    }
    switch (t->state) {
    case GROUND:
        if (b != 0x7F) show(c, b);
        break;
    case SKIP_ONE:
        t->state = GROUND;
        break;
    case ESCAPE:
        t->state = GROUND;
        switch (b) {
        case '[':
            t->state = CSI;
            t->nparam = 0;
            t->priv = 0;
            memset(t->param, 0, sizeof t->param);
            break;
        case ']': t->state = OSC; break;
        case 'D': t->pending = 0; index_down(c); break;
        case 'E': t->pending = 0; t->x = 0; index_down(c); break;
        case 'M': t->pending = 0; index_up(c); break;
        case '7': t->save_x = t->x; t->save_y = t->y; break;
        case '8': t->x = t->save_x; t->y = t->save_y; t->pending = 0; break;
        case 'c': {
            uint8_t head = t->in_head, tail = t->in_tail; /* (what's waiting to be read stays) */
            int alt = t->alt;
            if (alt) alt_screen(c, 0);
            vc_term_reset(c);
            t->started = 1;
            t->in_head = head;
            t->in_tail = tail;
            clear_rows(c, 0, ROWS);
            break;
        }
        case '(': case ')': case '*': case '+': case '#': case '%': t->state = SKIP_ONE; break;
        default: break;
        }
        break;
    case CSI:
        if (b >= '0' && b <= '9') {
            unsigned v = t->param[t->nparam] * 10u + (unsigned)(b - '0');
            t->param[t->nparam] = (uint16_t)(v > 9999u ? 9999u : v);
        } else if (b == ';' || b == ':') {
            if (t->nparam < VC_TERM_PARAMS - 1) ++t->nparam;
        } else if (b >= '<' && b <= '?') {
            t->priv = b;
        } else if (b >= 0x20 && b <= 0x2F) {
            t->priv = b; /* an intermediate: a form this doesn't do */
        } else if (b >= 0x40 && b <= 0x7E) {
            t->state = GROUND;
            csi(c, b);
        } else {
            t->state = GROUND;
        }
        break;
    default:
        t->state = GROUND;
        break;
    }
}

/* A key pressed (usage) that types ch (0: none), as a terminal would send it. */
void vc_term_key(vc_card *c, uint8_t usage, uint8_t ch) {
    static const char *const k_fn[12] = {"\x1bOP",   "\x1bOQ",   "\x1bOR",   "\x1bOS",   "\x1b[15~", "\x1b[17~",
                                         "\x1b[18~", "\x1b[19~", "\x1b[20~", "\x1b[21~", "\x1b[23~", "\x1b[24~"};
    const char *s = NULL;
    if (usage >= 0x3A && usage <= 0x45) {
        s = k_fn[usage - 0x3A];
    } else {
        switch (usage) {
        case 0x49: s = "\x1b[2~"; break; /* Insert */
        case 0x4A: s = "\x1b[H"; break;  /* Home */
        case 0x4B: s = "\x1b[5~"; break; /* Page Up */
        case 0x4C: s = "\x1b[3~"; break; /* Delete */
        case 0x4D: s = "\x1b[F"; break;  /* End */
        case 0x4E: s = "\x1b[6~"; break; /* Page Down */
        case 0x4F: s = "\x1b[C"; break;  /* the arrows: right */
        case 0x50: s = "\x1b[D"; break;  /* left */
        case 0x51: s = "\x1b[B"; break;  /* down */
        case 0x52: s = "\x1b[A"; break;  /* up */
        default: break;
        }
    }
    if (s) {
        reply(c, s, (unsigned)strlen(s));
    } else if (ch) {
        char two[2];
        unsigned n = 0;
        if (c->mods & (VC_MOD_LALT | VC_MOD_RALT)) two[n++] = 0x1B; /* Alt+key is Esc then the key */
        two[n++] = (char)ch;
        reply(c, two, n);
    }
}

uint8_t vc_term_peek(const vc_card *c) {
    const vc_term *t = &c->term;
    return t->in_head == t->in_tail ? 0 : t->in[t->in_head % VC_TERM_IN];
}

uint8_t vc_term_read(vc_card *c) {
    vc_term *t = &c->term;
    uint8_t v;
    if (t->in_head == t->in_tail) return 0;
    v = t->in[t->in_head % VC_TERM_IN];
    t->in_head = (uint8_t)(t->in_head + 1);
    return v;
}
