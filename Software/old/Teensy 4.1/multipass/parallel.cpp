// ----------------------------------------------------------------------------
// MEGA MULTIPASS - Teensy 4.1 as a Retrocomputer Peripheral
//
// NOTE: See "parallel.h" for Theory of Operation.
//       Pin definitions are in defines.h
//
// ----------------------------------------------------------------------------
#include "parallel.h"
#include "CRC16.h"
#include "CRC.h"
// ----------------------------------------------------------------------------
t_xfer_mode xfer_mode = MODE_TEXT;

t_fifo            par_tx, par_rx; // in and out message buffers.  
uint8_t           fbuf[516];      // temp buffer
uint16_t          fbuf_sz;
uint32_t          fbuf_bidx;
CRC16             crc;
volatile uint8_t  g_tx = 0;
volatile uint32_t g_errors = 0;  // biot defs inn defines.h
volatile uint32_t g_test = 0;
char funline[80];

//#define VERBOSE
// ----------------------------------------------------------------------------
// clear a fifo buffer
// ----------------------------------------------------------------------------
void par_buf_init(t_fifo * b)
{
  b->cnt = 0; // byte count
  b->head = b->tail = b->buf;  // head and tail pointers
}
// ----------------------------------------------------------------------------
inline void par_set_data_lines_inputs()
{
  pinMode(PIN_DB0, INPUT_PULLUP);
  pinMode(PIN_DB1, INPUT_PULLUP);
  pinMode(PIN_DB2, INPUT_PULLUP);
  pinMode(PIN_DB3, INPUT_PULLUP);
  pinMode(PIN_DB4, INPUT_PULLUP);
  pinMode(PIN_DB5, INPUT_PULLUP);
  pinMode(PIN_DB6, INPUT_PULLUP);
  pinMode(PIN_DB7, INPUT_PULLUP);
}
// ----------------------------------------------------------------------------
inline void par_set_data_lines_outputs()
{
  pinMode(PIN_DB0, OUTPUT);
  pinMode(PIN_DB1, OUTPUT);
  pinMode(PIN_DB2, OUTPUT);
  pinMode(PIN_DB3, OUTPUT);
  pinMode(PIN_DB4, OUTPUT);
  pinMode(PIN_DB5, OUTPUT);
  pinMode(PIN_DB6, OUTPUT);
  pinMode(PIN_DB7, OUTPUT);  
}
// ----------------------------------------------------------------------------
uint8_t par_read_data(void)
{
  // set gpios to inputs
  par_set_data_lines_inputs();
  // set URD low (tx latch output enable)
  digitalWrite(PIN_URD, LOW);
  // pause a sec for data to stabilize
  //asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  // read data on gpios
  uint8_t c = digitalRead(PIN_DB7); c<<=1;
  c |= digitalRead(PIN_DB6); c<<=1;
  c |= digitalRead(PIN_DB5); c<<=1;
  c |= digitalRead(PIN_DB4); c<<=1;
  c |= digitalRead(PIN_DB3); c<<=1;
  c |= digitalRead(PIN_DB2); c<<=1;
  c |= digitalRead(PIN_DB1); c<<=1;
  c |= digitalRead(PIN_DB0);
  // set URD high
  digitalWrite(PIN_URD, HIGH);
  //sprintf(funline,"got: %02X ",c);
  //Serial.println(funline);
  
  return c;
}
// ----------------------------------------------------------------------------
void par_write_data(uint8_t b)
{
  g_tx=1;
  // set gpios to outputs
  par_set_data_lines_outputs();
  
  // present data on gpios
  digitalWrite(PIN_DB0, b&1); b>>=1;
  digitalWrite(PIN_DB1, b&1); b>>=1;
  digitalWrite(PIN_DB2, b&1); b>>=1;
  digitalWrite(PIN_DB3, b&1); b>>=1;
  digitalWrite(PIN_DB4, b&1); b>>=1;
  digitalWrite(PIN_DB5, b&1); b>>=1;
  digitalWrite(PIN_DB6, b&1); b>>=1;
  digitalWrite(PIN_DB7, b&1);
  // pause a sec for data to stabilize
  // before we alert CPU
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  //asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  //asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  // set UWR high (rx latch data strobe) 
  // causes /IRQ on host cpu.  
  digitalWrite(PIN_UWR, HIGH);
  // todo: Start CRD timeout timer, in case we dont see CRD go low within a 
  // reasonable time from now. (Otherwise, transmission will be stalled.)
  return;
}
// ----------------------------------------------------------------------------
// todo: crd timeout interrupt
// set flag indicating we timed out
// proceed as if we had seen a crd event
// (CRDInterrupt() and setup next outgoing byte, if any)
// ----------------------------------------------------------------------------
void CWRInterrupt() // CPU just wrote a byte to us.
{
  g_test |= 2;
  t_fifo * f = &par_rx;
  if(f->cnt >= FIFO_SZ-1 )  // if buf is full, trash byte. set error flag
  {
    g_errors |= ERR_RX_BUF_FULL;
    return;
  }
  else
  {
    *f->tail = par_read_data() ; // PINA;
    f->tail++;
    f->cnt++;
    if (f->tail >= f->buf+FIFO_SZ) // handle wraparound
      f->tail = f->buf;
  }
}
// ----------------------------------------------------------------------------
void CRDInterrupt() // CPU just did a read of last byte we sent
{
  g_test |= 1;
  digitalWrite(PIN_UWR, LOW);  // end mcu data output strobe (deassert /NMI interrupt on CPU)
  // wait a sec for CPU to handle the byte.
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");  
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");  
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");  
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  asm("nop;nop;nop;nop;nop;nop;nop;nop;");
  g_tx=0;
}
// ----------------------------------------------------------------------------
// init the parallel interface
// ----------------------------------------------------------------------------
void par_init(void)
{
  // init 12 IO lines:
  
  // URD and UWR are outputs to the pugputer 
  pinMode(PIN_URD, OUTPUT);
  digitalWrite(PIN_URD, HIGH); // active low
  pinMode(PIN_UWR, OUTPUT);
  digitalWrite(PIN_UWR, LOW);  // active high
   
  // CWR and CRD are inputs from the pugputer
  pinMode(PIN_CWR, INPUT_PULLDOWN); // active high
  pinMode(PIN_CRD, INPUT_PULLUP); // active low
  
  // db0..7 are inputs initially.
  par_set_data_lines_inputs();
  
  // init CRD and CWR pin-change interrupts
  attachInterrupt(digitalPinToInterrupt(PIN_CWR), CWRInterrupt, RISING);
  attachInterrupt(digitalPinToInterrupt(PIN_CRD), CRDInterrupt, FALLING);

  par_buf_init(&par_tx);
  par_buf_init(&par_rx);
  crc.reset();
  crc.setPolynome(CRC_POLY);  
  crc.setReverseIn(true);
  crc.setReverseOut(true);

  Serial.println("    OK.");  
}
// ----------------------------------------------------------------------------
inline uint8_t par_buf_getc(t_fifo * f) // get a char received from parallel
{
  if(f->cnt == 0) // buf empty, return NULL.
    return 0;
  else
  {
    uint8_t c = *f->head;
    f->head++;
    cli();
    f->cnt--;
    if (!f->cnt)
    {
      f->head = f->tail = f->buf;      
    }
    sei();
    if (f->head >= f->buf+FIFO_SZ) // handle wraparound
      f->head = f->buf;
    return c;
  }
}
// ----------------------------------------------------------------------------
inline void par_buf_putc(t_fifo * f, uint8_t c) // send char via parallel
{
  if(f->cnt >= FIFO_SZ-1 )  // if tx buf is full, trash byte. set error flag
  {
    g_errors |= ERR_TX_BUF_FULL;
    return;
  }
  else
  {
    *f->tail = c;
    f->tail++;
    cli();
    f->cnt++;
    sei();
    if (f->tail >= f->buf+FIFO_SZ) // handle wraparound
      f->tail = f->buf;
  }
}
// ----------------------------------------------------------------------------
inline void par_buf_puts(t_fifo * f, char * s) // send string via parallel
{
  char * p = s;
  while (*p)
    par_buf_putc(f,*p++);
}
// ----------------------------------------------------------------------------
uint8_t mj=0;
void bufadd(uint8_t b)
{
  par_buf_putc(&par_tx,b);  // add byte to par tx queue
  #ifdef VERBOSE
  char s[8];  // debug log outgoing byte
  sprintf(s,"%02X ",b);
  Serial.print(s);
  if(++mj>=32)
  {
    mj=0;
    Serial.println();
  }
  #endif
}
// ----------------------------------------------------------------------------
void par_tx_service()
{
  uint8_t c;
  while(par_tx.cnt) // need to start a new transmission?
  {
    while(g_tx);
    c = par_buf_getc(&par_tx);
    par_write_data(c);
  } 
}
// ----------------------------------------------------------------------------
int par_send_message(uint8_t msg_type, uint8_t * payload, uint16_t p_sz)
{
  uint8_t b;
  uint16_t i,byte_count;
  uint16_t csum;
  uint8_t retries = 0;

  while(true) // up to 3 retries
  {
    if(retries >=3 )
    {
      Serial.println("Ran out of retries.");
      return -1;
    }    
    byte_count = p_sz+2;
    mj = 0;
    crc.restart();
    b='\xA5';crc.add(b); bufadd(b);
    b='\x5A';crc.add(b); bufadd( b );
    b=msg_type;crc.add(b); bufadd( b );
    b=byte_count>>8; crc.add(b); bufadd( b );
    b=byte_count&0xff; crc.add(b); bufadd( b );
    for(i=0;i<p_sz;i++)
    {
      b = payload[i];
      crc.add(b); bufadd( b );
    }
    csum = crc.getCRC();
    b=csum&0xff;bufadd( b );
    b=csum>>8;bufadd( b );

    par_tx_service();
    #ifdef VERBOSE
    Serial.println("\n");
    #endif
    uint8_t ticks=0;
    while(true)  // wait for ACK, NAK, or timeout
    {
      char plbuf[516];
      uint16_t plsize;
      uint8_t resp = par_rx_service(plbuf, &plsize);
      if(resp == MSG_ACK)
      {
        #ifdef VERBOSE
        Serial.println("Did get ACK.");
        #endif
        return 0;
      } else if (resp == MSG_NAK)
      {
        Serial.println("Got a NAK.");
        retries++;
        break;
      }
      delay(5);
      if(++ticks>=500)
      {
        Serial.println("Timeout waiting for ACK.");
        retries++;
        break;
      }
    }

  } // loop for up to three retries
  return -1;
}
// ----------------------------------------------------------------------------
void par_file_tx_start(t_xfer_mode xmode)  // when data will be provided incrementally
{
  xfer_mode = xmode;
  fbuf_sz = 0;    // num bytes added to current packet
  fbuf_bidx = 0;  // num file bytes copied
}
// ----------------------------------------------------------------------------
int par_file_tx_update(uint8_t * payload, uint16_t p_sz, bool last_one)
{
  int res=0;
  uint8_t * p = payload;
  if(xfer_mode == MODE_BINARY)
  {
    for(uint16_t i = 0; i<p_sz;i++)
    {
      uint8_t c = *(payload++);
      if(!fbuf_sz)  // if starting a packet, put file byteidx at beginning
      {
        fbuf[0] = (fbuf_bidx>>24) & 0xff;
        fbuf[1] = (fbuf_bidx>>16) & 0xff;
        fbuf[2] = (fbuf_bidx>>8) & 0xff;
        fbuf[3] = fbuf_bidx & 0xff;
      }
      fbuf[ 4 + fbuf_sz ]=c;
      fbuf_sz++;
      fbuf_bidx++;
      if(fbuf_sz==512)
      {
        res = par_send_message(MSG_DUMP,fbuf,516);
        if(res<0) // xfer failed
        {
          fbuf_sz=0;
          fbuf_bidx=0;
          return res;
        }
        fbuf_sz=0;
      }
    }  
    if (last_one)
    {
      if(fbuf_sz)
        res=par_send_message(MSG_DUMPEND,fbuf,fbuf_sz+4);    
      else
        res=par_send_message(MSG_DUMPEND,0,0);
      if(res<0) // xfer failed
      {
        fbuf_sz=0;
        fbuf_bidx=0;
        return res;
      }
      fbuf_sz=0;
      fbuf_bidx=0;
    }
  } else
  {
    for(uint16_t i = 0; i<p_sz;i++)
    {
      uint8_t c = *(payload++);
      fbuf[ fbuf_sz ]=c;
      fbuf_sz++;
      fbuf_bidx++;
      if(fbuf_sz==516)
      {
        res=par_send_message(MSG_DUMPTEXT,fbuf,516);
        if(res<0) // xfer failed
        {
          fbuf_sz=0;
          fbuf_bidx=0;
          return res;
        }
        fbuf_sz=0;
      }
    }  
    if (last_one)
    {
      if(fbuf_sz)
        res=par_send_message(MSG_DUMPTEXTEND,fbuf,fbuf_sz);
      else
        res=par_send_message(MSG_DUMPTEXTEND,0,0);
      if(res<0) // xfer failed
      {
        fbuf_sz=0;
        fbuf_bidx=0;
        return res;
      }
      fbuf_sz=0;
      fbuf_bidx=0;
    }
  }
  return 0;
}
// ----------------------------------------------------------------------------
uint8_t par_rx_service(char * plbuf, uint16_t *pl_size)
{
  uint8_t  j;
  uint8_t  b0,b1,c;
  char     sline[160];
  uint16_t x;
  uint8_t  msg_type;
  uint8_t  ret_msg_type = 255;

  uint16_t byte_count;
  uint16_t sz_to_crc;
  uint8_t  *p;
  uint16_t msg_crc;
  uint16_t calc_crc;
  while(par_rx.cnt>=2)
  {
    b0 = *par_rx.head;    // ensure first two bytes in buffer are A5 5A
    b1 = *(par_rx.head+1);
    if (b0!=0xA5)  // if first byte isnt a5, trash byte and retry.
    {
      uint8_t tc = par_buf_getc(&par_rx);
      Serial.print("Trash byte: ");
      Serial.println(tc,HEX);
      
      continue;
    } else if (b1!=0x5A)  // if second byte isnt 5a, trash byte and retry.
    {
      par_buf_getc(&par_rx);
      continue;
    }
    // we have an a5 5a
    if(par_rx.cnt>=5)  // msg long enough to have msgtype and bytecount
    {
      msg_type = *(par_rx.head+2);
      byte_count = (uint16_t)(*(par_rx.head+3))<<8 | *(par_rx.head+4);
      if (par_rx.cnt < byte_count + 5)  // dont have whole message yet
        continue;
      sz_to_crc = byte_count-2+5;
      p = par_rx.head+sz_to_crc;
      msg_crc = (uint16_t)(*p)<<8 | *(p+1);
      p = par_rx.head;
      crc.restart();
      for(x=0;x<sz_to_crc;x++,p++)
        crc.add(*p);
      calc_crc = crc.getCRC();
      
      uint8_t l = calc_crc&0xff;
      calc_crc=(calc_crc>>8)|((uint16_t)l<<8);

      if(msg_crc == calc_crc)
      {
        #ifdef VERBOSE
        sprintf(sline,"*** Got valid message. Type: %d, Payload_sz: %d, msg_crc: %04X.",msg_type,byte_count-2,msg_crc);
        Serial.println(sline);
        for(x=0,j=0,p = par_rx.head;x<byte_count+5;x++,p++)
        {
          c=*p;
          sprintf(sline,"%02X ",c);
          Serial.print(sline);
          if (++j==32)
          {
            j=0;
            Serial.println();
          }
        }
        if (j)
          Serial.println();
        #endif
        *pl_size = byte_count-2;
        memcpy(plbuf,par_rx.head+5,*pl_size);
        ret_msg_type = msg_type;
      } else
      {
        sprintf(sline,"*** Got Invalid message. Type: %d, Payload_sz: %d, msg_crc: %04X  calc_crc: %04x.",msg_type,byte_count-2,msg_crc,calc_crc);
        Serial.println(sline);
      }
      cli();
      par_buf_init(&par_rx);
      sei();        
    }
  }
  return ret_msg_type;
}
// ----------------------------------------------------------------------------
// called by mainloop to handle parallel interface housekeeping stuff
// ----------------------------------------------------------------------------
uint8_t par_service(char * plbuf, uint16_t * pl_size)
{
  /*
  if(g_test)
  {
    Serial.print("g_test ");
    Serial.println(g_test);
    g_test = 0;
  }
  */
  par_tx_service();
  return par_rx_service(plbuf, pl_size);  
}
// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
