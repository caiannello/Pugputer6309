///////////////////////////////////////////////////////////////////////////////
//
// SD Card functions, using the Arduino default SD library.
//
// Requires a FAT32 or FAT16 formatted SD Card.
//
///////////////////////////////////////////////////////////////////////////////
#include <Arduino.h>
#include <SPI.h>
#include <SD.h>
#include "defines.h"
#include "sd.h"
#include "pario.h"
// ----------------------------------------------------------------------------
File        root;
const int   SDChipSelect = SD_CS;
// ----------------------------------------------------------------------------
void sd_init(void)
{
  Serial.print("Init SD Interface...");    
  if ( ! SD.begin( SDChipSelect ) ) 
  {
    Serial.println(" FAIL!");
    return;
  } else 
  {
     Serial.println(" OK.");  
  }
}
// ----------------------------------------------------------------------------
// Periodic housekeeping - called by mainloop.
// ----------------------------------------------------------------------------
void sd_service(void)
{ 
}
// ----------------------------------------------------------------------------
void printDirectory(File dir, int numTabs, uint8_t recurse) 
{
  while (true) 
  {
    File entry =  dir.openNextFile();
    if (! entry) 
    {
      // no more files
      break;
    }
    for (uint8_t i = 0; i < numTabs; i++) 
    {
      Serial.print('\t');
      par_msg_add_string("\t");
    }
    Serial.print(entry.name());
    par_msg_add_string(entry.name());
    if (entry.isDirectory()) 
    {
      Serial.println("/");
      par_msg_add_string("/\r\n");
      if(recurse)
        printDirectory(entry, numTabs + 1, recurse);
    } else 
    {
      // files have sizes, directories do not
      Serial.print("\t\t");
      Serial.println(entry.size(), DEC);
      sprintf(ts,"\t\t%lu\r\n",entry.size());
      par_msg_add_string(ts);
    }
    entry.close();
  }
}
// ----------------------------------------------------------------------------
void sd_send_dir(uint8_t * path = NULL)
{
  root = SD.open("/");
  root.rewindDirectory();
  par_msg_init(PAR_MSG_DUMP, 0);
  printDirectory(root, 0, 1); 
  par_msg_finish(); 
}
// ----------------------------------------------------------------------------
void sd_send_file(char * filepath)
{
  Serial.print("Sending file ");
  Serial.println(filepath);
  // so you have to close this one before opening another.
  File dataFile = SD.open(filepath);
  if (dataFile) 
  {
    par_msg_init(PAR_MSG_DUMP, 0);
    while (dataFile.available()) 
    {
      uint8_t c = dataFile.read();
      //Serial.write(c);
      par_msg_add( &c, 1 );  // send file parts.
    }
    dataFile.close();
    par_msg_finish();  // send last part.
  }
  // if the file isn't open, pop up an error:
  else 
  {
    Serial.println("File open failed.");
    par_msg_init(PAR_MSG_NCOMP);
    par_msg_add_string("XXXXFile open failed.\r\n");
    par_msg_finish();    
  }
}
///////////////////////////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////////////////////////
