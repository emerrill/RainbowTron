#include <Encabulator.h>
#include <Wire.h>
// #include <I2C.h>   // NOTE: For reasons buried in the Encabulator.cpp file, you might want to download and use this library instead. 

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

  // check the temperature
  
  float weatherReport = Encabulator.temperature.getFahrenheit();
  Serial.print("Currrent operating temperature is: ");
  Serial.print(weatherReport);
  Serial.println("F");

  // check EEPROM   

  for (uint16_t i = 0 ; i < 52 ; i++) {
    Serial.print((char) Encabulator.eeprom.readAddress(i));
  }  
  Serial.println();

  // check the DAC

  Encabulator.dac.write(100);

  // check the XYZ

  int x = Encabulator.accelerometer.x();
  int y = Encabulator.accelerometer.y();
  int z = Encabulator.accelerometer.z();

  Serial.print("Heads or Tails?");

  if (z < 0.0) {
    Serial.println("  ...Heads!");
  } else {
    Serial.println("  ...Tails!");
  }
    
  delay(5000);
}

void loop() {               
  Serial.print("x: ");
  Serial.print(Encabulator.accelerometer.x());
  Serial.print(" y: ");
  Serial.print(Encabulator.accelerometer.y());
  Serial.print(" z: ");
  Serial.println(Encabulator.accelerometer.z());
  delay(10);
}
