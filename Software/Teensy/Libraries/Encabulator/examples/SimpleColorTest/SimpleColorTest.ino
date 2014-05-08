#include <Encabulator.h>
#include <Wire.h>
// #include <I2C.h>   // NOTE: For reasons buried in the Encabulator.cpp file, you might want to download and use this library instead. 

// 9241082682

int loopCounter = 0;

int tempR = 0;
int tempG = 0;
int tempB = 0;

float tempX = 0.0;
float tempY = 0.0;

void setup() {               
  
  Encabulator.upUpDownDownLeftRightLeftRightBA();

  // enable some debugging on the serial port

  Encabulator.setVerbose(true);

}

void loop() {
  
 // draw some gradients on the addressable based on the loop counter
  
  tempR = random(255);
  tempB = random(255);

  Encabulator.addressable.drawGradient(tempR,0,tempB,255 - tempR,0,255 - tempB,64);  
  
  // cycle through RGB on the headers.  this is a great way to make sure the strip is fastened properly
  
  for (int i = 1 ; i < 5 ; i++) {  // 
      Encabulator.stripBankA.jumpHeaderToRGB(i,255,0,0);
      Encabulator.stripBankB.jumpHeaderToRGB(i,255,0,0);      
  }
  delay(1000);
  for (int i = 1 ; i < 5 ; i++) { 
      Encabulator.stripBankA.fadeHeaderToRGB(i,0,0,0,5);
      Encabulator.stripBankB.fadeHeaderToRGB(i,0,0,0,5);
  } 
  delay(500);
  for (int i = 1 ; i < 5 ; i++) {
      Encabulator.stripBankA.jumpHeaderToRGB(i,0,255,0);
      Encabulator.stripBankB.jumpHeaderToRGB(i,0,255,0);      
  }
  delay(1000);
  for (int i = 1 ; i < 5 ; i++) { 
      Encabulator.stripBankA.fadeHeaderToRGB(i,0,0,0,5);
      Encabulator.stripBankB.fadeHeaderToRGB(i,0,0,0,5);
  } 
  
  delay(500);
  for (int i = 1 ; i < 5 ; i++) {
      Encabulator.stripBankA.jumpHeaderToRGB(i,0,0,255);
      Encabulator.stripBankB.jumpHeaderToRGB(i,0,0,255);      
  }
  delay(1000);
  
  for (int i = 1 ; i < 5 ; i++) { 
      Encabulator.stripBankA.fadeHeaderToRGB(i,0,0,0,5);
      Encabulator.stripBankB.fadeHeaderToRGB(i,0,0,0,5);
  } 
  delay(500);
 
}

