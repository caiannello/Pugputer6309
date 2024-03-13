///////////////////////////////////////////////////////////////////////////////
//
//  MEGA MULTIPASS - Teensy 4.1 as a Retrocomputer Peripheral - v0.0.1
//  
//      This project allows the Teensy to be interfaced to 
//      classic retrocomputers to potentially provide 
//      several services:
//
//        * SD card file system
//        * Audio IN/OUT/SYNTH
//        * Misc IO (SPI, I2C, UART, USB, PS/2)
//        * Programmable Timers
//        * Coprocessor, math, crypto, etc.
//        * ???
//
//  Communications with the host system is via a bidirectional parallel 
//  interface attached to the computer's data bus. It uses a lightweight, 
//  message-based protocol with error-checking. For more info on how that 
//  works, see "parallel.h"
//
//  Note, the counterpart of this project on the 6309 side is project Pugmon,
//  module pario.asm. (I expect to add more relevant modules to pugmon soon,
//  e.g. fileio.asm, soundio.asm, kbio.asm, gpio.asm, etc.)  
//
//  Also,I'm hoping to eventually make use of these modules from Extended BASIC
//  and other languages, probably by doing 'system calls' to the Pugmon ROM.
//  
///////////////////////////////////////////////////////////////////////////////
#include <SD.h>
#include "defines.h"      // project settings, gpio pin assignments
#include "parallel.h"     // host cpu bus interface
#include "audio.h"
#include "usb_kb.h"
// ----------------------------------------------------------------------------
void setup()
{
  // Init serial debug port
  Serial.begin(SER_BAUD);
  while (!Serial);

  Serial.println("Initializing Services...");
  
  Serial.print("    Parallel bus Interface...");  
  par_init();   // parallel bus interface 
  
  Serial.print("    SD card filesystem...");  
  sd_init();    // sd card
  
  Serial.print("    Audio IO...");  
  aud_init();   // audio

  Serial.print("    USB Keyboard...");  
  ukb_init();   // usb keyboard
  
  Serial.println("\nInit complete. Have a very safe day.\n");
  sei();
}
// ----------------------------------------------------------------------------
// Main loop does housekeeping calls to some peripherals.
// ----------------------------------------------------------------------------
void loop()
{
  aud_service();
  par_service();  
  ukb_service();
  

  // todo: dispatch requests made my CPU via parallel

  // par_send_dir_blocking("/");
  //par_send_file_blocking("Float09.bin");
  //par_send_file_blocking("mandel.hex");

}

///////////////////////////////////////////////////////////////////////////////
//
// SD Card stuff is below.
// 
// I would like to move this stuff to a separate source file,
// but that causes compilation to fail!!?   WTF!!?!?!!
//
///////////////////////////////////////////////////////////////////////////////

// change this to match your SD shield or module;
// Teensy 2.0: pin 0
// Teensy++ 2.0: pin 20
// Wiz820+SD board: pin 4
// Teensy audio board: pin 10
// Teensy 3.5 & 3.6 & 4.1 on-board: BUILTIN_SDCARD

const int chipSelect = BUILTIN_SDCARD;

// ----------------------------------------------------------------------------
void par_send_file_blocking(char * fname)
{
  uint8_t buf[256];

  sprintf(buf,"*** Sending file \"%s\"...",fname);
  Serial.println((char *)buf);
  
  File dataFile = SD.open(fname);
  uint32_t i = 0;
  uint32_t m = 0;
  if (dataFile) 
  {
    par_file_tx_start();
    while (dataFile.available()) 
    {
      uint16_t sz = dataFile.readBytes(buf,256);
      par_file_tx_update(buf,sz,false);
    }
    par_file_tx_update(0,0,true);
    dataFile.close();
  }  
  else 
  {
    Serial.println("error opening file");
    par_send_message(MSG_NCOMP,0,0);
  }   
}
// ----------------------------------------------------------------------------
void par_send_dir_blocking(char * dirname)
{
   char lbuf[256];
   char b[32];

   sprintf(lbuf,"*** Sending directory of \"%s\"...",dirname);
   Serial.println(lbuf);
   
   File dir = SD.open(dirname);
   par_file_tx_start();
   bool didone = false;
   while(true) 
   {
     File entry = dir.openNextFile();
     if (! entry)
     {
       if (!didone)
       {
         par_send_message(MSG_NCOMP,0,0);
         return;
       }
       break;
     }
     didone = true;
     DateTimeFields datetime;
     if (entry.getModifyTime(datetime)) 
     {
       printTime(datetime,lbuf);
       strcat(lbuf," ");
     }
     if (entry.isDirectory()) 
       strcat(lbuf,"      --- ");
     else
     {
       sprintf(b,"%9d ",entry.size());
       strcat(lbuf,b);
     }  
     strcat(lbuf,entry.name());
     if (entry.isDirectory()) 
       strcat(lbuf,"/");
     strcat(lbuf,"\n");
     Serial.print(lbuf);
     par_file_tx_update(lbuf,strlen(lbuf),false);
     entry.close();
   }
   par_file_tx_update(0,0, true);
}
// ----------------------------------------------------------------------------
void sd_init()
{
  //Uncomment these lines for Teensy 3.x Audio Shield (Rev C)
  //SPI.setMOSI(7);  // Audio shield has MOSI on pin 7
  //SPI.setSCK(14);  // Audio shield has SCK on pin 14  
  if (!SD.begin(chipSelect)) 
  {
    Serial.println(" FAIL!!");
    return;
  }
  Serial.println(" OK.");
}
// ----------------------------------------------------------------------------
void printTime(const DateTimeFields tm, char * s) 
{
  s[0]=0;
  char b[20];  
  sprintf(b,"%04d",tm.year + 1900);
  strcat(s,b);
  strcat(s,"-");
  sprintf(b,"%02d",tm.mon);
  strcat(s,b);
  strcat(s,"-");
  sprintf(b,"%02d",tm.mday);
  strcat(s,b);
  strcat(s," ");
  sprintf(b,"%02d",tm.hour);
  strcat(s,b);
  strcat(s,":");
  sprintf(b,"%02d",tm.min);
  strcat(s,b);  
}
// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
