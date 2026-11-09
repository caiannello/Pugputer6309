/* The picture: 640x480 at 60 Hz, DVI through HSTX, drawn up to three lines ahead of the
 * beam, by core 1 and, when that can't keep up, core 0 too. */
#ifndef VIDCARD_FW_DVI_H
#define VIDCARD_FW_DVI_H

#include <stdbool.h>
#include <stdint.h>

#include "vc.h"

/* On core 0, before core 1 starts: core 0's part (an interrupt). */
void dvi_init(void);

/* Core 1's whole job: never returns. clk_hstx must already be 126 MHz. */
void dvi_run(void);

/* Lines whose time came before they were drawn (part of them showed the line before). */
extern volatile uint32_t dvi_late_lines;

#if VIDCARD_DIAG
/* The longest a line took core 1 to draw (us), the lines each drew, and the frames core 0
 * helped with: main.c reports them. dvi_solo: core 1 alone (bench.c times lines). */
extern volatile uint32_t diag_render_us_max, diag_lines_drawn, diag_lines_core0, diag_help_frames;
extern volatile uint32_t diag_core_us[2], diag_core_lines[2];
void dvi_retime(int y, uint32_t r[4]); /* core 0 alone, core 1 alone, both: core 0, core 1 (us) */
extern volatile bool dvi_solo, dvi_park; /* (dvi_park: core 1 draws nothing) */
/* By 16 lines: the slowest drawn (us) and the most sprites on one, since they were last
 * cleared; and the times the sprite table has been decoded (both cores). */
extern volatile uint16_t diag_strip_us[30];
extern volatile uint8_t diag_strip_sprites[30];
uint32_t dvi_decodes(void);
/* Core 0's render cache, for bench.c (which runs with core 0's help off). */
vc_palette *dvi_bench_palette(void);
#endif

#endif
