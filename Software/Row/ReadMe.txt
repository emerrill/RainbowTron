Developed with Crosspack for Mac (http://www.obdev.at/products/crosspack/index.html)

USI_TWI_Slave modified to receive 0x10 broadcast address. When sync command is received, wait the delay, then step through all 8 channels, two at a time, and read the configured number of times. Then send data when requested.