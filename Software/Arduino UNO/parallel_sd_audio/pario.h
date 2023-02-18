///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
#ifndef __PARIO_H__
#define __PARIO_H__
// ----------------------------------------------------------------------------
#include "defines.h"
// ----------------------------------------------------------------------------
extern uint8_t           par_buf[ PAR_BUF_SZ ];
extern uint16_t          par_len;

extern uint8_t           par_ack_buf[32]; 
// ----------------------------------------------------------------------------

void par_init(void);
uint8_t par_service(void);

void par_msg_init(uint8_t msg_type, uint32_t byte_index = 0);
void par_msg_add(uint8_t * msg_bytes, uint16_t num_bytes );
void par_msg_add_string(char * s );
uint8_t par_msg_finish( bool last_part = true );
// ----------------------------------------------------------------------------
#endif
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
