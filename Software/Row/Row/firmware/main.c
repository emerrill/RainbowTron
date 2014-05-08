/* Name: main.c
 * Author: <insert your name here>
 * Copyright: <insert your copyright message here>
 * License: <insert your license reference here>
 */

// Pins
// ADDRA    PA3
// ADDRB    PA7
// VDIFF    PA1
// AIN1     PA0
// AIN2     PA2
// I2CADD0  PB0
// I2CADD1  PB1
// I2CADD1  PB2


// ADC
// AREF:
// VCC -  cbi(ADMUX, REFS0); cbi(ADMUX, REFS1);
// 1.1V - cbi(ADMUX, REFS0); sbi(ADMUX, REFS1);
//
// ADCSRA:
// ADEN //Enables ADC
// ADSC //Start conversion. Changes to 0 when complete
// ADPS[2:0] //ADC Clock Prescaler
//
// ADCSRB:
// BIN // Binary mode, +- around PA1
//
// DIDR0:
// Use to disable digital inputs on analog pins to save power
//
// Output:
// ADCL then ADCH
//
//
// ADMUX: REFS[1:0];MUX[5:0]
// 
// AIN1 (PA0)
// SINGLE    - 00000000 x00
// SINGLE11  - 10000000 x80
// DIFF      - 00001000 x08
// DIFF11    - 10001000 x88
//
// AIN2 (PA2)
// SINGLE    - 00000010 x02
// SINGLE11  - 10000010 x82
// DIFF      - 00101100 x2C
// DIFF11    - 10101100 xAC
//
//
//
//
//
//
//
//



#include <avr/io.h>
#include <util/delay.h>
#include <avr/interrupt.h>
//#include <util/twi.h>
#include "USI_TWI_Slave.h"
//#include "usiTwiSlave.h"

//#include "i2c.h"

#define sbi(x,y) x |= _BV(y) //set bit - using bitwise OR operator
#define cbi(x,y) x &= ~(_BV(y)) //clear bit - using bitwise AND operator
#define tbi(x,y) x ^= _BV(y) //toggle bit - using bitwise XOR operator
#define is_high(x,y) ((x & _BV(y)) == _BV(y)) //check if the y'th bit of register 'x' is high ... test if its AND with 1 is 1


static const uint8_t AIN1SINGLE = 0x00;
static const uint8_t AIN1SINGLE11 = 0x80;
static const uint8_t AIN1DIFF = 0x08;
static const uint8_t AIN1DIFF11 = 0x88;

static const uint8_t AIN2SINGLE = 0x02;
static const uint8_t AIN2SINGLE11 = 0x82;
static const uint8_t AIN2DIFF = 0x2C;
static const uint8_t AIN2DIFF11 = 0xAC;

static const uint8_t DELAY_MODE_START = 0x00;
static const uint8_t DELAY_MODE_SWITCH = 0x01;

/*
 Program Flow:
 Bootup
    Init
    Reset ADC
    ADC Off
 
 Receive Config
    Set Config
    Stop Timer
    Reset ADC
    Reset Readings
    ADC Off
 
 Receive Command
    Reset ADC
    Reset Readings
    Setup Start Delay
 
 Start Delay
    Begin reading sequence
    
 Read
    Start read
    Set Switch Delay
 
 Switch Delay
    Switch to next address
 
 */



// Config
// 0 0 0 0 0 0 0 0
// | | | | | \---/
// | | | | |   +----- Samples, value * 16 (0 = 1 sample)
// | | | | +--------- ADC Type 0 = Single, 1 = Differential
// | | | +----------- VRef 0 = Vcc, 1 = 1.1V
// | | +------------- Differential 0 = Unipolar, 1 = Bipolar
// | +---------------
// +----------------- 0 = Config Byte
//
uint8_t config = 0x02;

// Command Byte
// 1 0 0 0 0 0 0 0
// | | | | \-----/
// | | | |    +------ Start Delay in ms
// | | | +-----------
// | | +-------------
// | +--------------- 1 = Start ADC
// +----------------- 1 = Command Byte

uint8_t i2cAddress = 0x30;

uint8_t numberOfSamples = 16;
uint8_t sampleNumber = 0;
uint16_t sampleSum = 0;
uint8_t adcAddress = 0;
uint8_t switchAddress = 0;
uint16_t readings[] = {0, 0, 0, 0, 0, 0, 0, 0};
uint8_t startDelay = 1;


void startup();
void loadConfig();
void resetReading();
void enableADC();
void disableADC();
void setADCAddress();
void setChannel();
void setADMUX(uint8_t b);
void incrementSwitch();
void startRead();
void startCycle();
void processTWI();
void fillTXBuffer();


int main() {
    startup();
    /*USI_TWI_Transmit_Byte(0x7f);
    USI_TWI_Transmit_Byte(0x0A);
    USI_TWI_Transmit_Byte(0xFF);
    USI_TWI_Transmit_Byte(0xaa);
    USI_TWI_Transmit_Byte(0xaa);
    USI_TWI_Transmit_Byte(0xaa);
    USI_TWI_Transmit_Byte(0xaa);
    USI_TWI_Transmit_Byte(0xaa);
    USI_TWI_Transmit_Byte(0xaa);*/
    
    
    startRead();
    
    while (1) {
        
        /*if (TWI_TxHead == TWI_TxTail) {
            //Buffer Empty
            _delay_ms(startDelay);
            resetReading();
            startRead();
        }*/
        //_delay_ms(500);
        //resetReading();
        //startRead();
        if (USI_TWI_Data_In_Receive_Buffer()){
            processTWI();
        }
    }
    
    return 1;
}


// ---------------------------------------------------------------------
// Init Functions
// ---------------------------------------------------------------------
void startup() {
    sei(); //Enable interrupts
    loadConfig();
    
    //Setting up address jumpers
    DDRB &= 0b11111000;
    PORTB |= 0b00000111;
    _delay_ms(10);
    //Load i2c address
    i2cAddress |= (~((PINB & 0b00000111) | 0b11111000)); //TODO
    
    //Output
    sbi(DDRA, PA3);
    sbi(DDRA, PA7);
    cbi(PORTA, PA3);
    cbi(PORTA, PA7);
    
    USI_TWI_Slave_Initialise(i2cAddress);
    
    PORTA |= _BV(PA3);
    _delay_ms(100);
    PORTA &= ~(_BV(PA3));
    
    //Init ADC
    //Set ADIE and ADSP[2..0]
    //ADC Clock Prescale (pg 147)
    //ADSP[2..0] = 110 = 125kHz
    //ADSP[2..0] = 101 = 250kHz
    ADCSRA |= 0b00001101;
    ADCSRA &= 0b11111101;

}



void loadConfig() {
    //config[2..0]
    numberOfSamples = ((config & 0b00000111) * 16)-1;
    
    resetReading();
}


// ---------------------------------------------------------------------
// Control Functions
// ---------------------------------------------------------------------
void resetReading() {
    disableADC();
    sampleNumber = 0;
    sampleSum = 0;
    adcAddress = 0;
    switchAddress = 0;
    setADCAddress();
}





// ---------------------------------------------------------------------
// Interupts Functions
// ---------------------------------------------------------------------
ISR(ADC_vect) {

    if (sampleNumber == numberOfSamples) {
        int tmpADCAddr = adcAddress;
        

        if (i2cAddress & 0x01) {
            tmpADCAddr -= 4;
            tmpADCAddr &= 0x07;
        }
        
        tmpADCAddr = ((tmpADCAddr >> 1) | ((tmpADCAddr & 0x01) << 2));
        
        
        incrementSwitch();
        _delay_us(200);
        sampleSum += (ADCL | (ADCH<<8));
        readings[tmpADCAddr] = sampleSum;
        
        sampleNumber = 0;
        sampleSum = 0;
        if (switchAddress == 0b00001000) {
            resetReading();
            fillTXBuffer();
        } else {
            startRead();
        }
        
    } else {
        sampleSum += (ADCL | (ADCH<<8));
        sampleNumber++;
        startRead();
    }

}

// ---------------------------------------------------------------------
// Reader Functions
// ---------------------------------------------------------------------
void startCycle() {
    resetReading();
    startRead();
}

void enableADC() {
    sbi(ADCSRA, ADEN);
}

void disableADC() {
    cbi(ADCSRA, ADEN);
}

void incrementSwitch() {
    switchAddress++;
    setADCAddress();
}

void startRead() {
    enableADC();
    adcAddress = switchAddress;
    sbi(ADCSRA, ADSC);
}

void setADCAddress() {
    //Offset by 2 if we are an odd row
    uint8_t tmpAddress = switchAddress;
    if (i2cAddress & 0x01) {
        tmpAddress += 4;
    }
    
    //ADDRA
    if (tmpAddress & 0b00000010) {
        sbi(PORTA, PA3);
    } else {
        cbi(PORTA, PA3);
    }
    
    //ADDRB
    if (tmpAddress & 0b00000100) {
        sbi(PORTA, PA7);
    } else {
        cbi(PORTA, PA7);
    }
    
    setChannel();
}

void setChannel() {
    if (switchAddress & 0x01) { //AIN2
        if (config & 0b00001000) { //ADC Differential
            if (config & 0b00010000) { //VRef 1.1V
                if (config & 0b00100000) { //Bipolar
                    
                } else { //Unipolar
                    setADMUX(AIN2DIFF11);
                }
            } else { //VRef Vcc
                if (config & 0b00100000) { //Bipolar
                    
                } else { //Unipolar
                    setADMUX(AIN2DIFF);
                }
            }
        } else { //ADC Single
            if (config & 0b00010000) { //VRef 1.1V
                if (config & 0b00100000) { //Bipolar
                    
                } else { //Unipolar
                    setADMUX(AIN2SINGLE11);
                }
            } else { //VRef Vcc
                if (config & 0b00100000) { //Bipolar
                    
                } else { //Unipolar
                    setADMUX(AIN2SINGLE);
                }
            }
        }
    } else { //AIN1
        if (config & 0b00001000) { //ADC Differential
            if (config & 0b00010000) { //VRef 1.1V
                if (config & 0b00100000) { //Bipolar
                    
                } else { //Unipolar
                    setADMUX(AIN1DIFF11);
                }
            } else { //VRef Vcc
                if (config & 0b00100000) { //Bipolar
                    
                } else { //Unipolar
                    setADMUX(AIN1DIFF);
                }
            }
        } else { //ADC Single
            if (config & 0b00010000) { //VRef 1.1V
                if (config & 0b00100000) { //Bipolar
                    
                } else { //Unipolar
                    setADMUX(AIN1SINGLE11);
                }
            } else { //VRef Vcc
                if (config & 0b00100000) { //Bipolar
                    
                } else { //Unipolar
                    setADMUX(AIN1SINGLE);
                }
            }
        }
    }
}

void setADMUX(uint8_t b) {
    ADMUX = b;
}


// ---------------------------------------------------------------------
// Timer Functions
// ---------------------------------------------------------------------



// ---------------------------------------------------------------------
// i2c Functions
// ---------------------------------------------------------------------
void processTWI() {
    //sbi(PORTA, PA3);
    uint8_t tmp = 0;
    uint8_t recByte = 0;
    while (USI_TWI_Data_In_Receive_Buffer()) {
        recByte = USI_TWI_Receive_Byte();
        
        if (recByte & 0b10000000) { //Command Byte
            startDelay = (recByte & 0x0f);
            if (recByte & 0b01000000) {
                tmp = 0x01;
            }
        } else { //Config Byte
            sbi(PORTA, PA7);
            _delay_ms(100);
            cbi(PORTA, PA7);
            config = recByte;
            loadConfig();
        }
    }
    
    if (tmp) {
        _delay_ms(5);
        startCycle();
    }
    //cbi(PORTA, PA3);
}

void fillTXBuffer() {
    uint8_t tmp = 0;
    uint8_t i = 0;
    Flush_TWI_Buffers();
    
    for (i = 0; i < 8; i++) {
        tmp = (readings[i] / numberOfSamples);
        //tmp = (tmp >> 1);
        //tmp = ((readings[i] >> 7) && 0x7f);
        USI_TWI_Transmit_Byte(tmp);
        //tmp = (readings[i] & 0x7f);
        //USI_TWI_Transmit_Byte(0x00);
        //sbi(PORTA, PA3);
    }
    USI_TWI_Transmit_Byte(0x00);
    USI_TWI_Transmit_Byte(0x00);
    USI_TWI_Transmit_Byte(0x00);
    USI_TWI_Transmit_Byte(0x00);
    
}




