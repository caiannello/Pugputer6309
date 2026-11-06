/* The picture: 640x480 at 60 Hz, DVI through HSTX, drawn a line ahead of the beam. */
#ifndef VIDCARD_FW_DVI_H
#define VIDCARD_FW_DVI_H

/* Core 1's whole job: never returns. clk_hstx must already be 126 MHz. */
void dvi_run(void);

#if VIDCARD_DIAG
#include <stdint.h>
/* The longest a line took to draw (us), and the lines drawn: main.c reports them. */
extern volatile uint32_t diag_render_us_max, diag_lines_drawn;
#endif

#endif
