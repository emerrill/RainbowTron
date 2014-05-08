#include <FastSPI_LED.h>
#include <i2c_t3.h>
#include <Encabulator.h>

#define HEIGHT 6
#define WIDTH 8

#define NUM_LEDS 96

#define STRIP_SUBPIX_COUNT 990
#define STRIP_PIX_COUNT 330
#define STRIP_LENGTH 66
#define STRIP_COUNT 5

#define FORCE_REDRAW 100

// If we need to save on baud, and there will be X successive LEDs in a pixel.
#define LED_DIVISOR 2

struct CRGB { unsigned char r; unsigned char g; unsigned char b; };
struct CRGB *leds;

#define FPS 15

struct CELL { unsigned char mode; char dir; };
CELL cells[48];

#define NUM_SENSORS 48
#define PIN_ANALOG_CHANNEL_0 14
#define PIN_ANALOG_CHANNEL_1 15
#define PIN_ANALOG_CHANNEL_2 16
#define PIN_ANALOG_CHANNEL_3 17
#define PIN_ANALOG_CHANNEL_4 20
#define PIN_ANALOG_CHANNEL_5 21
#define PIN_ANALOG_SWITCH 22
#define PIN_ANALOG_ADDR_0 4
#define PIN_ANALOG_ADDR_N0 3
#define PIN_ANALOG_ADDR_1 2
#define MAX_ADDRESS 3

int analogAddress = 0;
int analogCells[HEIGHT][WIDTH];

int lastUpdateTime = 0;
int lastByteTime = 0;
int lastRedrawTime = 0;

int receiveMode = 0;
int modeBytes = 0;
int pixelsChanged = 1;


#define MODE_CELL 1
#define MODE_CELL_BYTES 4
#define MODE_PLAY_HEAD 2
#define MODE_PLAY_HEAD_BYTES 1
#define MODE_PLAY_HEAD_MOVING 3
#define MODE_PLAY_HEAD_MOVING_BYTES 2
#define MODE_STRIP_CLEAR 4
#define MODE_STRIP_CLEAR_BYTES 0
#define MODE_CLEAR_ALL 5

boolean dirtyFrame = true;
boolean dirtyStrip = true;

char buffer[255];

byte analogBuffer[NUM_SENSORS * 2];

int bufferPoint = 0;


uint8_t stripPixs[STRIP_SUBPIX_COUNT];

byte headUpdateTime = 0;
int lastHeadUpdateTime = 0;
byte playerHeadLocation = 0;


//TODO - Switch i2c speeds?

#define I2C_ADDR_SWITCH         0x70
#define I2C_ADDR_ADC_BROADCAST  0x10
#define I2C_ADDR_ADC_BASE       0x30

void setup()
{
  Serial.begin(115200);
  Serial1.begin(115200);
  
  FastSPI_LED.setLeds(NUM_LEDS);

  FastSPI_LED.setChipset(CFastSPI_LED::SPI_WS2801);

  FastSPI_LED.setDataRate(1);
  FastSPI_LED.init();
  FastSPI_LED.start();

  leds = (struct CRGB*)FastSPI_LED.getRGBData();
  
  //analogReadAveraging(16);
  //analogReadRes(12);
  
  /*pinMode(PIN_ANALOG_CHANNEL_0, INPUT);
  pinMode(PIN_ANALOG_CHANNEL_1, INPUT);
  pinMode(PIN_ANALOG_CHANNEL_2, INPUT);
  pinMode(PIN_ANALOG_CHANNEL_3, INPUT);
  pinMode(PIN_ANALOG_CHANNEL_4, INPUT);
  pinMode(PIN_ANALOG_CHANNEL_5, INPUT);
  pinMode(PIN_ANALOG_SWITCH, OUTPUT);
  pinMode(PIN_ANALOG_ADDR_0, OUTPUT);
  pinMode(PIN_ANALOG_ADDR_N0, OUTPUT);
  pinMode(PIN_ANALOG_ADDR_1, OUTPUT);*/
  //pinMode(PIN_LED, OUTPUT);
  //digitalWrite(PIN_LED, 1);
  /*digitalWrite(PIN_ANALOG_SWITCH, 0);
  digitalWrite(PIN_ANALOG_ADDR_0, 1);
  digitalWrite(PIN_ANALOG_ADDR_N0, 0);
  digitalWrite(PIN_ANALOG_ADDR_1, 0);*/
  Encabulator.upUpDownDownLeftRightLeftRightBA();
  delay(1000);
  
  
  Serial1.println("Starting");
}

void loop() {
  int byte1, addr, r, g, b;
  int time = millis();
  
  if ((headUpdateTime > 0) && ((time - lastHeadUpdateTime) > headUpdateTime)) {
    playerHeadLocation++;
    if (playerHeadLocation >= STRIP_LENGTH) {
      playerHeadLocation = 0;
    }
    updatePlayerHeadBuffer();
    lastHeadUpdateTime = time;
  }
  
  if ((time - lastUpdateTime) > (1000/FPS)) {
    updateAnalog();
    lastUpdateTime = time;
  }
  
  if (receiveMode > 0) {
    if ((time - lastByteTime) > 10) {
      //Serial1.println("Reset");
      receiveMode = 0;
      bufferPoint = 0;
    }
  }
  
  if ((time - lastRedrawTime) > FORCE_REDRAW) {
    //Serial1.println("Force Redraw");
    dirtyFrame = true;
    //dirtyStrip = true;
  }
  
  while (Serial.available()) {
    lastByteTime = millis();
    byte1 = Serial.read();
    if (receiveMode == 0) {
      //byte1 = Serial.read();
      //Serial1.print((char)byte1);
      switch(byte1) {
        case 'c':
          receiveMode = MODE_CELL;
          bufferPoint = 0;
          break;
        case 'p':
          receiveMode = MODE_PLAY_HEAD;
          bufferPoint = 0;
          break;
        case 'm':
          receiveMode = MODE_PLAY_HEAD_MOVING;
          bufferPoint = 0;
          break;
        
        case 's':
          clearStrips();
          bufferPoint = 0;
          break; 
        case 'C':
          clearBoard();
          bufferPoint = 0;
          break; 
        default:
          Serial1.print("Unknown: ");
          Serial1.println((char)byte1);
          break;
      }
    } else {
      // Set a cell: cARGB  A = Address, R = red, G = green, B = blue
      // Set play head: pA
      // Set moving play head: mAT  T = update time in ms
      // Clear strips: s
      //byte1 = Serial.read();
      buffer[bufferPoint] = byte1;
      bufferPoint++;
      switch (receiveMode) {
        case (MODE_CELL):
          if (bufferPoint >= MODE_CELL_BYTES) {
            addr = buffer[0];
            //Serial1.println(addr);
            r = buffer[1];
            g = buffer[2];
            b = buffer[3];
            for (int i = 0; i < LED_DIVISOR; i++) {
              leds[(addr*LED_DIVISOR)+i].r = r;
              leds[(addr*LED_DIVISOR)+i].g = g;
              leds[(addr*LED_DIVISOR)+i].b = b;
            }
            dirtyFrame = true;
            
            receiveMode = 0;
            bufferPoint = 0;
            pixelsChanged++;
          }
          break;
        case (MODE_PLAY_HEAD):
          if (bufferPoint >= MODE_PLAY_HEAD_BYTES) {
            playerHeadLocation = buffer[0];

            updatePlayerHeadBuffer();
            headUpdateTime = 0;
            
            receiveMode = 0;
            bufferPoint = 0;
          }
          break;
        case (MODE_PLAY_HEAD_MOVING):
          if (bufferPoint >= MODE_PLAY_HEAD_MOVING_BYTES) {
            playerHeadLocation = buffer[0];
            headUpdateTime = buffer[1];

            updatePlayerHeadBuffer();
            
            lastHeadUpdateTime = millis();
            receiveMode = 0;
            bufferPoint = 0;
          }
          break;
      }
    }

    
  }



  if (dirtyFrame) {
    lastRedrawTime = millis();
    FastSPI_LED.show();
    //Serial1.println("Redraw");
    if (pixelsChanged) {
      //Serial1.print(pixelsChanged);
      
    }
    pixelsChanged = 0;

    dirtyFrame = false;
  }
  
  if (dirtyStrip) {
    //Serial1.println(playerHeadLocation);
    Encabulator.addressable.drawFrame(STRIP_SUBPIX_COUNT, stripPixs);
    //delay(1);
    dirtyStrip = false;
  }

}

void clearStrips() {
  headUpdateTime = 0;
  for (int x = 0; x < (STRIP_SUBPIX_COUNT); x++) {
    stripPixs[x] = 0;
  }
  dirtyStrip = true;
}

void clearBoard() {
  for (int x = 0; x < (NUM_LEDS*3); x++) {
    stripPixs[(NUM_LEDS*3) + x] = 0;
  }
  dirtyFrame = true;
}

void updatePlayerHeadBuffer() {
//  
//  headUpdateTime = 0;
//  for (int x = 0; x < (STRIP_SUBPIX_COUNT); x++) {
//    stripPixs[x] = 128;
//  }
//  dirtyStrip = true;
//  
//  return;
  byte addr = playerHeadLocation;

  uint8_t tmp[STRIP_LENGTH*3];
  uint8_t head[] = {10, 10, 10, 50, 50, 50, 100, 100, 100, 128, 128, 128, 50, 50, 50};
  //compensate for the 'head' length;
  for (int i = 0; i < 3; i++) {
    if (addr <= 0) {
      addr = STRIP_LENGTH-1;
    } else {
      addr--;
    }
  }
//Serial1.println(addr);
  
  for (int i = 0; i < (STRIP_LENGTH*3); i++) {
    tmp[i] = 0;
  }
  
  for (int i = 0; i < (15); i++) {
    tmp[(i + (addr*3)) % (STRIP_LENGTH*3)] = head[i];
  }
  


  for (int h = 0; h < STRIP_COUNT; h++) {
    if ((h % 2) == 0) {
      for (int x = 0; x < STRIP_LENGTH*3; x++) {
        stripPixs[(h*STRIP_LENGTH*3) + x] = tmp[((STRIP_LENGTH*3)-1)-x];
      }
    } else {
      for (int x = 0; x < STRIP_LENGTH*3; x++) {
        stripPixs[(h*STRIP_LENGTH*3) + x] = tmp[x];
      }
    }
    
  }

  dirtyStrip = true;
}


void updateAnalog() {
  /*analogAddress = -1;
  for (int i = 0; i <= MAX_ADDRESS; i++) {
    setAnalogAddress(i);
    delay(1);
    readCurrentValues();
  }*/
  readEntireBoard();
  sendValues();

}

/*void setAnalogAddress(int add) {
  analogAddress = add;
  digitalWrite(PIN_ANALOG_ADDR_0, ((analogAddress & B00000010) >> 1));
  digitalWrite(PIN_ANALOG_ADDR_N0, !(boolean)((analogAddress & B00000010) >> 1));
  digitalWrite(PIN_ANALOG_ADDR_1, (analogAddress & B00000001));
}*/

/*void readCurrentValues() {
  int address = analogAddress;
  int nAddress = (analogAddress ^ B00000010);

  analogCells[0][nAddress] = analogRead(PIN_ANALOG_CHANNEL_0);
  analogCells[1][address] = analogRead(PIN_ANALOG_CHANNEL_1);
  analogCells[2][nAddress] = analogRead(PIN_ANALOG_CHANNEL_2);
  analogCells[3][address] = analogRead(PIN_ANALOG_CHANNEL_3);
  analogCells[4][nAddress] = analogRead(PIN_ANALOG_CHANNEL_4);
  analogCells[5][address] = analogRead(PIN_ANALOG_CHANNEL_5);

  digitalWrite(PIN_ANALOG_SWITCH, 1);
  delay(1); // Delay to propigate switch
  
  address = analogAddress + MAX_ADDRESS + 1;
  nAddress = (analogAddress ^ B00000010) + MAX_ADDRESS + 1;
  analogCells[0][nAddress] = analogRead(PIN_ANALOG_CHANNEL_0);
  analogCells[1][address] = analogRead(PIN_ANALOG_CHANNEL_1);
  analogCells[2][nAddress] = analogRead(PIN_ANALOG_CHANNEL_2);
  analogCells[3][address] = analogRead(PIN_ANALOG_CHANNEL_3);
  analogCells[4][nAddress] = analogRead(PIN_ANALOG_CHANNEL_4);
  analogCells[5][address] = analogRead(PIN_ANALOG_CHANNEL_5);
  
  digitalWrite(PIN_ANALOG_SWITCH, 0);
}*/

void readCurrentValues() {
  switchADC();
  char addr = I2C_ADDR_ADC_BASE;
  char c;

  for (int i = 0; i < 5; i++) {
    Wire.requestFrom(addr, 16);
    delay(1);
    while(Wire.available()) {
      c = Wire.read();
      Serial.println(c);
    }
  }
  
  //Setup the next read
  startADCCycle();
}




void switchADC() {
  //Wire.finish(5000);
  //Serial.println("ADC1");
  while (!Wire.pinConfigure(I2C_PINS_18_19, I2C_PULLUP_EXT));
  //Serial.println("ADC2");
}

void switchDisplay() {
  //Wire.finish(5000);
  //Serial.println("Dis1");
  while (!Wire.pinConfigure(I2C_PINS_16_17, I2C_PULLUP_EXT));
  //Serial.println("Dis2");
}

void sendADCConfig() {
  Wire.beginTransmission(I2C_ADDR_ADC_BROADCAST);
  Wire.write(0x01);
  Wire.endTransmission();
}

void startADCCycle() {
  Wire.beginTransmission(I2C_ADDR_ADC_BROADCAST);
  Wire.write(0xc1);
  Wire.endTransmission();
}

void readEntireBoard() {
  switchADC();
  char addr = I2C_ADDR_ADC_BASE;
  char c;
  int cell = 0;
  
  for (int row = 0; row < HEIGHT; row++) {
    cell = 0;
    Wire.requestFrom(addr, 8, I2C_STOP, 2000);
    while(Wire.available()) {
      c = Wire.read();
      c = (c & 0x7F);
      //Serial.print(c, DEC);Serial.print(',');
      analogCells[row][cell] = (int)c;
      cell++;
      //TODO
    }
    //Serial.println();
    addr++;
  }
  
  //Setup the next read
  delay(1);
  startADCCycle();
  switchDisplay();
}


void sendValues() {
  char byte1, byte2;
  for (int row = 0; row < HEIGHT; row++) {
    for (int cell = 0; cell < WIDTH; cell++) {
      //Serial1.println(analogCells[row][cell]);
      byte1 = analogCells[row][cell] & B11111111;
      byte2 = analogCells[row][cell] >> 8;
      byte2 &= B11111111;

      analogBuffer[(row * WIDTH * 2)+(cell *2)+1] = byte1;
      analogBuffer[(row * WIDTH * 2)+(cell *2)] = byte2;
      
      //Serial.write(byte2);
      //Serial.write(byte1);
      //Serial.print("12");
    }
  }
  Serial.write(analogBuffer, (NUM_SENSORS * 2));
}






