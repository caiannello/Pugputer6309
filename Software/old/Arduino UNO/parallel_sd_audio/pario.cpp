///////////////////////////////////////////////////////////////////////////////
//
// Parallel bus interface and comms protocol
//
// The parallel interface is implemented with a couple 8-bit latches and
// a PLD, which intervene between the Arduino Uno (MCU) and the host CPU's 
// data bus. (CPU)
//
// One latch is for data sent from CPU to MCU, and the other is for data
// sent from MCU to CPU.
//
// In addition to eight bidirectional data lines, db0...db7, there are
// four handshake lines:
// 
//    CWR - CPU WRITE (Input,  Active High)
//    CRD - CPU READ  (Input,  Active Low)
//    UWR - MCU WRITE (Output, Active High)
//    URD - MCU READ  (Output, Active Low)
//
//    The function of these signals is further described below.
//
// CPU TRANSMIT (Not a closed loop)
//
// When the CPU writes a byte to the parallel card, the data is latched 
// in the transmit latch by a rising edge on the CWR line. The MCU can
// see this signal, so it knows when a byte was written. The MCU is
// configured to fire a pin-change interrupt on a rising edge of CWR.
// In the ISR (Interrupt handler), the MCU will read out that byte:
// first it enables the transmit latch output by setting the URD line
// LOW, reads the value of signals db0...7db7, and finally, it sets URD
// back to HIGH.
//
// Currently, the CPU side is not made aware of a URD signal, but if we 
// ever wanted to make transmission be a closed-loop (flow-controlled) 
// operation, making the CPU aware of URD would be a good way. The MCU 
// is nice and fast though, so hopefully it should have no trouble keeping 
// up with the reception of bytes from a vintage CPU anyway.
//
// CPU RECEIVE (Closed loop)
//
// The MCU won't send bytes any faster than the CPU can read them. The 
// way this is accomplished is as follows:
//
// When the MCU wants to write a byte, it presents the bits on db0...db7,
// and it brings the UWR signal HIGH. This latches the bits in the receive 
// latch, and it also begins an /NMI state on the CPU side. 
//
// In the CPU's NMI ISR, it does a read of the parallel port byte, which
// briefly causes a receive latch output enable signal (CRD) to go LOW.
//
// The MCU sees that CRD signal, and it fires a different pin-change 
// interrupt on that falling edge. In the ISR, the MCU returns it's UWR 
// line back to LOW, which ends the /NMI state on the CPU side. Until that
// happens, the MCU won't try to send any more bytes.
//
// COMMUNICATIONS PROTOCOL
//
// Bytes are sent through the interface as packets in the following format:
//
// 0xA5, 0x5A, u8 msg_type, u16 byte_cnt, u8 bytes[], u16 crc16_arc
//
// ENDIANNESS NOTE: The CRC is in little-endian byte order, which means the
// least significant byte comes first. All other integers, including the
// byte count, are in big-endian byte order. 
//
// where 0xA5, 0x5A are single bytes, byte_cnt is the number of bytes that
// follow in the message, message types are described in defines.h, bytes[]
// is an optional data payload, and CRC is a 16-bit CRC which uses a 
// polynomial of value 0xA001. The CRC calculation is done over all of the
// previous message bytes, starting with the 0xA5, and then the two CRC 
// bytes are appended to the message, low-byte first.
// 
// Not every message needs to have a data payload. In those cases, byte_cnt 
// will equal 2, and there will be no data bytes prior to the CRC. The 
// maximum payload size is 516 bytes. This is enough for 512-byte data with
// a 32-bit byte-address value. This is for use when, e.g. transferring a 
// file, in order to identify which part of the file is contained in the 
// message. There is currently no provision for sending multiple files 
// concurrently, but that might be accomplished by including some kind of 
// file ID value in the message too.
//
///////////////////////////////////////////////////////////////////////////////
#include "pario.h"
// ----------------------------------------------------------------------------
uint8_t           par_buf[ PAR_BUF_SZ ];  // Used for both input and output
                                          // (ATMEGA328 only has 2k of RAM)
uint16_t          par_len = 0 ;           // number of chars in buffer

// parallel receiver stuff

uint8_t           par_ack_buf[32];        // small par data buf for when the big 
uint8_t           par_ack_len = 0;        // one is in use. (for receiving acks
                                          // during file upload, for instance.)
volatile uint8_t  par_receiving = 0 ;     // true while receiving a message
volatile uint8_t  g_byte_in = 0;          // temp storage of a received byte
volatile uint8_t  g_got_byte = 0;         // true when a new byte was received

// parallel transmitter stuff

volatile uint8_t  par_sending = 0 ;       // true while sending a message
volatile uint8_t  *par_tx_p;              // adrs of next Tx byte
volatile uint8_t  *par_rx_p;              // adrs of next Rx byte
uint32_t          g_byte_index;           // used during file uploads
uint8_t           g_msg_type;             // used in multipart messages
volatile uint8_t  g_cpu_read_timeout = false;

// global scratchpad strings (because we have so little stack)

char              ts[32];
char              asc[17];
                                          
// ----------------------------------------------------------------------------
// Optional debug log stuff. Enabled in defines.h
// ----------------------------------------------------------------------------
#ifdef DEBUG
  void par_log_message( void )      // Show contents of parallel data buffer
  {
    Serial.print("par_buf: ");
    uint8_t c;
    int k = 15;
    asc[0]='\0';
    asc[16]='\0';
    for(uint16_t i=0;i<par_len;i++)
    {
      if (++k == 16)
      {
        k=0;
        sprintf(ts,"%s\n%04X ",asc,i);
        Serial.print(ts);
      }
      c = par_buf[i];
      sprintf(ts,"%02X ",c);
      Serial.print(ts);
      if ((c>=32)&&(c<=127))
        asc[k] = c;
      else
        asc[k] = '.';
    }
    Serial.println();
  }
#else
  #define par_log_message(...) 
#endif
// ----------------------------------------------------------------------------
// Wait a few cycles to give all I/O signals a chance to stabilize
// ----------------------------------------------------------------------------
inline void par_bus_pause(void)
{
  asm("nop;nop;");                  // assembly no-op instructions.
}
// ----------------------------------------------------------------------------
// Configure our data lines as inputs, enable parallel card's Tx latch 
// outputs, wait a moment, and read the Tx byte.
// ----------------------------------------------------------------------------
inline uint8_t par_get_input(void) 
{
  // set data lines as inputs with pullups  
  //DDRC  = 0x00;                     // inputs with pullups
  //PORTC = 0xff;
  //DDRD  &= 0x3f;  
  //PORTD |= 0xc0;
  pinMode(PAR_PIN_D0, INPUT_PULLUP);
  pinMode(PAR_PIN_D1, INPUT_PULLUP);
  pinMode(PAR_PIN_D2, INPUT_PULLUP);
  pinMode(PAR_PIN_D3, INPUT_PULLUP);
  pinMode(PAR_PIN_D4, INPUT_PULLUP);
  pinMode(PAR_PIN_D5, INPUT_PULLUP);
  pinMode(PAR_PIN_D6, INPUT_PULLUP);
  pinMode(PAR_PIN_D7, INPUT_PULLUP);  
  digitalWrite ( PAR_PIN_URD , 0 ); // Tx latch output enable.
  par_bus_pause();                  // brief pause
  //uint8_t b = PINC & 0x3f;          // Read lower 6 bits from port C,
  //b |= (PIND & 0xc0);               // and upper 2 bits from port D
  uint8_t b = 0;
  b|=digitalRead(PAR_PIN_D7);b<<=1;
  b|=digitalRead(PAR_PIN_D6);b<<=1;
  b|=digitalRead(PAR_PIN_D5);b<<=1;
  b|=digitalRead(PAR_PIN_D4);b<<=1;
  b|=digitalRead(PAR_PIN_D3);b<<=1;
  b|=digitalRead(PAR_PIN_D2);b<<=1;
  b|=digitalRead(PAR_PIN_D1);b<<=1;
  b|=digitalRead(PAR_PIN_D0);
  
  digitalWrite ( PAR_PIN_URD , 1 ); // Tx latch output disable.
  return b;
}
// ----------------------------------------------------------------------------
// Set parallel I/O lines to output the given value, wait a moment for the
// signals to stabilize, then start latching the value in the parallel card's
// Rx latch. This begins an /NMI state for the CPU.
// ----------------------------------------------------------------------------
inline void par_set_output(uint8_t b)
{
  //DDRC  = 0xff;                   // lower 5 bits of port C are db0 ... db4
  //PORTC = b & 0x3f;               // set value of db0 ... db4
  //DDRD  |= 0xc0;                  // higher 2 bits of port D are db6 and db7
  //PORTD &= 0x3f;                  // clear existing value
  //PORTD |= ( 0xc0 & b );          // set value of db6 and db7
  // set data lines as outputs set to b
  pinMode(PAR_PIN_D0, OUTPUT);
  pinMode(PAR_PIN_D1, OUTPUT);
  pinMode(PAR_PIN_D2, OUTPUT);
  pinMode(PAR_PIN_D3, OUTPUT);
  pinMode(PAR_PIN_D4, OUTPUT);
  pinMode(PAR_PIN_D5, OUTPUT);
  pinMode(PAR_PIN_D6, OUTPUT);
  pinMode(PAR_PIN_D7, OUTPUT);  
  digitalWrite(PAR_PIN_D0, b&1); b>>=1;
  digitalWrite(PAR_PIN_D1, b&1); b>>=1;
  digitalWrite(PAR_PIN_D2, b&1); b>>=1;
  digitalWrite(PAR_PIN_D3, b&1); b>>=1;
  digitalWrite(PAR_PIN_D4, b&1); b>>=1;
  digitalWrite(PAR_PIN_D5, b&1); b>>=1;
  digitalWrite(PAR_PIN_D6, b&1); b>>=1;
  digitalWrite(PAR_PIN_D7, b&1);    
  par_bus_pause();                // pause
  digitalWrite( PAR_PIN_UWR, 1 ); // Begin latching Rx data.
  // Start CRD timeout timer, in case we dont see CRD go low within a 
  // reasonable time from now. (Otherwise, transmission will be stalled.)
  TCNT2 = 0;        // reset timer 2
  TIFR2 = 0x01;     // clear t2 ovf int
  TIMSK2 = 0x01;    // enable overflow interrupt
}
// ----------------------------------------------------------------------------
// Called when CPU has read the byte we sent. (Rx latch output enable (CRD) 
// went low.)  We can end our MCU write strobe, ending the CPU's /NMI state,
// and then we can send another byte or end transmit mode.
//
// Occasionally, it seems that MCU misses this signal, so a timeout is 
// implemented. If we don't see the CPU read the byte within a reasonable
// time, we go ahead with the call to par_cpu_read().
//
// Might be a good idea add a pulse-stretcher to the card, to make the 
// signal visible to the MCU for a longer time.
// ----------------------------------------------------------------------------
void par_cpu_read(void)
{
  // If CRD timeout timer is running, end it.
  TIMSK2 = 0;
  digitalWrite( PAR_PIN_UWR, 0 );         // end data strobe on Rx latch
  par_bus_pause();
  if(par_sending)
  {
    if (par_tx_p < par_buf + par_len)     // if more bytes,
      par_set_output( *( par_tx_p++ ) );  // send next byte,
    else
      par_sending = false;                // else leave send mode.
  }
}
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
ISR (TIMER2_OVF_vect)
{
  TIMSK2 = 0x00;
  g_cpu_read_timeout = true;
  par_cpu_read();
  
}
// ----------------------------------------------------------------------------
// Called when CPU has written a byte to us. (Tx latch strobe STX went high.)
// We read in the byte to a tmp variable and set a flag. (The housekeeping fcn 
// below, par_service, will handle the byte.)
// ----------------------------------------------------------------------------
void par_cpu_write(void)
{
  g_byte_in = par_get_input();
  g_got_byte = true;
}
// ----------------------------------------------------------------------------
// Append a byte to the parallel data buf, and include it in CRC calculation.
// ----------------------------------------------------------------------------
inline void par_bufc(uint8_t c)
{
  par_buf[ par_len++ ] = c;
}
// ----------------------------------------------------------------------------
// Begin a new parallel Tx message. If PAR_MSG_DUMP, include file byte idx.
// ----------------------------------------------------------------------------
void par_msg_init(uint8_t msg_type, uint32_t byte_index)
{
  //while( par_sending ) ; // Wait for pending transmission, if any.
  par_len = 0;
  par_bufc( 0xA5 );
  par_bufc( 0x5A );
  par_bufc( msg_type );
  g_msg_type = msg_type;      // remember these in case we end up doing a
  g_byte_index = byte_index;  // multi-part message.
 
  par_len+=2;    // skip the bytecount for now. (will poke it here later.)
  
  if ( msg_type == PAR_MSG_DUMP ) // dump messages have a byte idx in file
  {
    par_bufc( ( byte_index >> 24 ) & 0xff );
    par_bufc( ( byte_index >> 16 ) & 0xff );
    par_bufc( ( byte_index >> 8  ) & 0xff );
    par_bufc( ( byte_index       ) & 0xff );    
  }
}
// ----------------------------------------------------------------------------
// Append some bytes to parallel Tx message.  
//
// TODO: If message fills up, finish it, transmit it, and start a new message. 
// Keep a byte count for use in the next message.
// ----------------------------------------------------------------------------
void par_msg_add(uint8_t * msg_bytes, uint16_t num_bytes )
{
  uint8_t *p = msg_bytes;
  while( num_bytes-- )
  {
    par_bufc( *(p++) );
    g_byte_index++;
    // multi-part message logic: if the current message is full, (only enough 
    // room remaining for the CRC-16)
    // finish the message, send it, and start making a new message.
    if ( par_len == ( PAR_BUF_SZ - 2 ) )
    {
      par_msg_finish( false );  // multi-part, but not last part
      par_msg_init( g_msg_type, g_byte_index );
    }
  }
}
// ----------------------------------------------------------------------------
// Append a null-terminaled string to parallel Tx message
// ----------------------------------------------------------------------------
void par_msg_add_string(char * s )
{
  par_msg_add( (uint8_t *)s, strlen( s ) );
}
// ----------------------------------------------------------------------------
uint16_t crc_16( const unsigned char *input_str, uint16_t num_bytes ) 
{
  uint16_t cv;
  const unsigned char *ptr;
  uint16_t lookup;
  uint16_t a;
  cv = 0x0000;
  ptr = input_str;
  for (a=0; a<num_bytes; a++) 
  {
    lookup = pgm_read_word_near ( crc_tab16 + ((cv ^ (uint16_t) *ptr++) & 0x00FF));
    cv = (cv >> 8) ^ lookup;
  }
  return cv;
}
// ----------------------------------------------------------------------------
uint16_t update_crc_16( uint16_t cv, unsigned char c ) 
{
  return (cv >> 8) ^ crc_tab16[ (cv ^ (uint16_t) c) & 0x00FF ];
} 
// ----------------------------------------------------------------------------
// Complete a parallel Tx message, and start transmitting it.
// a5 5a msgtype u16 bytes[] crc .  
//
// If the 'last_part' argument is true, and the message_type is PAR_MSG_DUMP,  
// the type will be changed to PAR_MSG_DUMP_END. This is so the receiver can
// recognize the final part of a file transfer. 
// ----------------------------------------------------------------------------
uint8_t par_msg_finish( bool last_part = true )
{
  uint16_t bytecnt = par_len - 3; // insert message bytecount
  uint8_t c = (bytecnt >> 8)&0xff;
  par_buf[3] = c;
  c = bytecnt & 0xff;
  par_buf[4] = c;

  // if msg type is a PAR_MSG_DUMP and this is the last part,
  // change the msg type to PAR_MSG_DUMP_END
  if ( last_part && ( par_buf[2] == PAR_MSG_DUMP ) )
    par_buf[2] = PAR_MSG_DUMP_END;

  uint16_t crc_val = crc_16(par_buf, par_len);  // Append CRC-16 to complete the message.
  par_bufc( crc_val & 0xff );  
  par_bufc( ( crc_val >> 8 ) & 0xff );
  par_log_message();
  par_tx_p = par_buf ;                // Reset transmit byte pointer,
  par_sending = 1;                    // start transmit mode,
  par_set_output( *( par_tx_p++ ) );  // send initial byte.

  // todo: we need a state machine that looks for par_sending to go back to 
  // zero following a transfer and then for either an ack, nak, or timeout
  // before another message can be sent, whether it is a retry, the next part
  // of a multipart transfer, or a new type of message.
  uint32_t t_start = millis();
  par_ack_len = 0;
  while(1)
  {
    uint32_t t_now = millis();
    if(t_now-t_start > 3000)
    {
      Serial.println("\nRESP: TIMEOUT!\n");
      return PAR_MSG_NAK;
    }
    if(g_got_byte)  // a byte came in from parallel interface. 
    {
      //sprintf(ts, "%02X ", g_byte_in);
      //Serial.print(s);
      
      par_ack_buf[par_ack_len++] = g_byte_in;
      
      if (par_ack_buf[0]!=0xA5)
        par_ack_len = 0;
        
      if(par_ack_len>=5)
      {
        uint16_t bc = ((uint16_t)par_ack_buf[3])<<8|par_ack_buf[4];
        if (par_ack_len>=(bc+5))
        {
          uint16_t cc = crc_16(par_ack_buf,bc+5);
          if(cc)
          {
            Serial.println("\nBAD CRC!\n");
            par_ack_len = 0;
            return PAR_MSG_NAK;            
          } else
          {
            uint8_t mtype = par_ack_buf[2];
            if(mtype==PAR_MSG_ACK)
            {
              //Serial.println("ACK!");
              par_ack_len = 0;
              return 0;
            } else
            {
              Serial.println("\nNON ACK!\n");
              par_ack_len = 0;
              return mtype;            
            }            
          }
        }
      }      
      g_got_byte = false;
    }
    if(g_cpu_read_timeout)
    {
      g_cpu_read_timeout = false;
      Serial.println("CPU READ TIMEOUT");
    }

  }
     
}
// ----------------------------------------------------------------------------
// Initialize the parallel interface
// ----------------------------------------------------------------------------
void par_init(void)
{
  Serial.print( "Init Parallel Interface..." );  
  par_get_input();                  // Cfg. I/O lines to be inputs by default.
  //DDRD  = 0b00110010;               // d7, d6, UWR 1, URD 1, CRD 0, CWR 0, tx, rx
  //PORTD = 0b11011111;   

  pinMode(PAR_PIN_UWR, OUTPUT);
  digitalWrite(PAR_PIN_UWR,0);
  pinMode(PAR_PIN_URD, OUTPUT);
  digitalWrite(PAR_PIN_URD,1);
  pinMode(PAR_PIN_CWR, INPUT_PULLUP);
  pinMode(PAR_PIN_CRD, INPUT_PULLUP);
  
  
  // init pin-change interrupts for each handshaking input from CPU  
  attachInterrupt(digitalPinToInterrupt(PAR_PIN_CWR), par_cpu_write, RISING);
  attachInterrupt(digitalPinToInterrupt(PAR_PIN_CRD), par_cpu_read, FALLING);
  par_get_input();                  // Cfg. I/O lines to be inputs by default.
  
  // initialize timer 2 to use as a CPU read timeout.
  cli();
  TCCR2A = 0b00000000;    // normal mode
  TCCR2B = 0b00000111;    // 61 Hz rollover
  TIMSK2 = 0b00000000;    // no interrupt unles doing timeout
  sei();
  Serial.println( " OK." );  
}
// ----------------------------------------------------------------------------
// Periodic housekeeping - called by mainloop.
// ----------------------------------------------------------------------------
uint8_t par_service(void)
{
  if(g_got_byte)  // a byte came in from parallel interface. 
  {
      sprintf(ts, "%02X ", g_byte_in);
      Serial.print(ts);
      
      par_ack_buf[par_ack_len++] = g_byte_in;
      
      if (par_ack_buf[0]!=0xA5)
        par_ack_len = 0;
        
      if(par_ack_len>=5)
      {
        uint16_t bc = ((uint16_t)par_ack_buf[3])<<8|par_ack_buf[4];
        if (par_ack_len>=(bc+5))
        {
          uint16_t cc = crc_16(par_ack_buf,bc+5);
          if(cc)
          {
            Serial.println("\nBAD CRC!\n");
            par_ack_len=0;
            return 0;            
          } else
          {
            uint8_t mtype = par_ack_buf[2];
            Serial.print("GOT MSG TYPE 0x");
            Serial.println(mtype,HEX);
            par_ack_len=0;
            return mtype;
          }
        }
      }      
      g_got_byte = false;
  }
  if(g_cpu_read_timeout)
  {
    g_cpu_read_timeout = false;
    Serial.println("CPU READ TIMEOUT");
  }
  return 0;
}
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
