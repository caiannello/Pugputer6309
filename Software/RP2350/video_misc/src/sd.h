/* The board's microSD card, in SPI mode: 512-byte blocks by number. */
#ifndef VIDCARD_FW_SD_H
#define VIDCARD_FW_SD_H

#include <stdbool.h>
#include <stdint.h>

/* Wakes the card up (SDSC, SDHC or SDXC). False: no card, or one that didn't answer. */
bool sd_init(void);
bool sd_read(uint32_t block, uint8_t *buf);
bool sd_write(uint32_t block, const uint8_t *buf);

#endif
