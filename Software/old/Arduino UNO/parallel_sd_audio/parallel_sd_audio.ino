///////////////////////////////////////////////////////////////////////////////
//
// This project allows an Arduino Uno or Nano to act as a peripheral 
// of the Pugputer 6309.
//  
// Connected via the Parallel IO Card, the Uno has enough memory and GPIO pins
// to provide an SPI interface, SD card filesystem, and minimal (PWM) audio.
//
// * GPIO pin definitions and other settings are in "defines.h".
// * The parallel IO interface and protocol are described in "pario.cpp".
// * The parallel card is described in "Hardware/Parallel IO Card/"
//  
///////////////////////////////////////////////////////////////////////////////
#include "defines.h"
#include "pario.h"
#include "sd.h"
// ----------------------------------------------------------------------------
// Project setup - calls init functions for each module
// ----------------------------------------------------------------------------
void setup()
{
  Serial.begin(SER_BAUD);
  while (!Serial);
  par_init();
  sd_init();
}
// ----------------------------------------------------------------------------
// Project mainloop - calls periodic housekeeping functions for each module
// ----------------------------------------------------------------------------
void loop(void) 
{
  // do parallel interface housekeeping. Returns message type if a
  // message has been received.
  uint8_t mtype = par_service();
  if(mtype)                         // if a message was received,
  {
    switch(mtype)                   // do appropriate message handler:
    {
      case PAR_MSG_GET_DIR:         // CPU wants directory of SD card.
        sd_send_dir();
        break;
      case PAR_MSG_GET_FILE:
        uint16_t bcnt = (((uint16_t)par_ack_buf[3])<<8) | par_ack_buf[4];
        for (int i=0;i<bcnt-2;i++)
          ts[i]=par_ack_buf[5+i];
        ts[bcnt-2]='\0';
        Serial.print("GET_FILE: ");
        Serial.println(ts);
        sd_send_file((const char *)ts);
        break;
    }
  }
  sd_service();
  char sc = Serial.read();
  if (sc>=0) // if got char
  {
    switch(sc)
    {
      case '.':
        par_msg_init(PAR_MSG_NAK);
        par_msg_finish();
        break;        
      case 'd':
      case 'D':
        sd_send_dir();
        break;
      case 'f':
      case 'F':
        sd_send_file((const char *)"wavy_pug.bas");
        break;   
      case 'h':
      case 'H':
        sd_send_file((const char *)"HGTTG.TXT");
        break;               
    }
  }  
}
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
