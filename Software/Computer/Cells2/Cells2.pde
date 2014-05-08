import ddf.minim.*;
import processing.video.*;
import processing.serial.*;


// Constants

final boolean SERIAL_ENABLE = true;

// Run Modes
final int RUN_MODE_CALIBRATING = 0;
final int RUN_MODE_MUSIC = 1;
final int RUN_MODE_FRAMES = 2;
final int RUN_MODE_VIDEO = 3;

// Cell Control Modes
final int CELL_CONTROL_MODE_CALIBRATE = 1;
final int CELL_CONTROL_MODE_CLEAR_BOARD = 2;
final int CELL_CONTROL_MODE_RR_CHECK = 3;
final int CELL_CONTROL_MODE_PLAY_PAUSE = 4;

final int HEAD_MODE_STOP = 0;
final int HEAD_MODE_PLAY = 2;
final int HEAD_MODE_PAUSE = 1;

// Fade Direction
final int FADE_UP = 1;
final int FADE_DOWN = -1;
final int FADE_STOP = 0;

// Fade settings
final float CELL_NODE_LOW_FADE = 0.5;
final float CELL_NODE_FADE_HIT = 1.0;
final float CELL_NODE_FADE_SPEED = 0.02;

final float CELL_PULSE_LOW_FADE = 0.5;
final float CELL_PULSE_HIGH_FADE = 1.0;
final float CELL_PULSE_FADE_SPEED = 0.03;


// Input settings
final float TOUCH_TRIGGER_LEVEL = 0.7;
final float TOUCH_RELEASE_LEVEL = 0.5;
final int TOUCH_SUCESSIVE_FRAMES = 2; // Number of updates needed in a row above TOUCH_TRIGGER_LEVEL
final int TOUCH_DIFF_MULTIPLIER = 10;

final int TOUCH_AVERAGE_LENGTH = 3;

final int TOUCH_VALUE_RANGE = 128;


// Time controls
final int LOOP_TIME = 2000; // In ms.

final int FPS = 30;
final int REMOTE_FPS = 10;
final int KEY_FRAME = 30;
final int VIDEO_FPS = 10;
final int CALIBRATION_FPS = 10;


final int CALIBRATION_RUN_TIME = 5000;


// Physical information
final int PLAY_HEAD_LEDS = 66; // How many LEDs in a play head row.
final int HEIGHT = 6;
final int WIDTH = 8;

final String RR_FILE = "RR/RR.mov";

String samplesFolder = "Samples/Standard/";


int runMode = RUN_MODE_CALIBRATING;

int boxSize = 40;
Cell[][] cells;
Cell[] controls;
Cell[] insts;
Cell[][] nodes;
Cell selectedInst = null;
IRCell[][] irCells;
PlayHead head;

int lastUpdateTime = 0;
int lastRemoteUpdateTime = 0;
int lastHitCol;

// IR Stuff
int lastByteTime = 0;
int value = 0;
int nextCell = 0;
int nextRow = 0;
boolean firstByteReceived = false;
boolean receivingFrame = false;

boolean started = false;


int lastFullFrame = 0;

byte[] frameBuffer;

int handX = -1, handY = -1, handCount = 0;

boolean calibrating = true;

Serial serial;      // The serial port

PImage vidImg;
int vidFrame = 1;
AudioPlayer vidAudio;

Movie videoPlayer;

int calibrationStartTime = 0;

void setup() {
  if (SERIAL_ENABLE) {
    String portName = "/dev/tty.usbmodem181"; // Serial.list()[5];
    serial = new Serial(this, portName, 115200);
  }
  
  size(boxSize*WIDTH, ((boxSize*HEIGHT)*2)+20);
  //frameRate(FPS);

  setupBoard();

  started = true;
  
  startCalibration();
  //calibrating = false;
  //setMusicMode();
}

void draw() {
  int time = millis();
  
  switch (runMode) {
    case RUN_MODE_MUSIC:
      // Update the head and hits as quick as we can for best timing;
      head.update();
      updateHit();
      
      // Just update at a fraterate.
      if ((time - lastUpdateTime) > (1000/FPS)) {
        background(0);
        
        lastUpdateTime = time;
        
        for (int x = 0; x < WIDTH; x++) {
          for (int y = 0; y < HEIGHT; y++) {
            cells[y][x].update();
            cells[y][x].display();
            irCells[y][x].update();
            irCells[y][x].display();
          }
        }
        
        
        head.display();
    
        findMaxIRCell();
        
        
      }
      
      if ((time - lastRemoteUpdateTime) > (1000/REMOTE_FPS)) {
        lastRemoteUpdateTime = time;
        lastFullFrame++;
        if (lastFullFrame > KEY_FRAME) {
          lastFullFrame = 0;
          sendFrame(true);
        } else {
          sendFrame(false);
        }
        
      }
      break;
    case RUN_MODE_FRAMES:
      
      if ((time - lastRemoteUpdateTime) > (1000/12)) {
        lastRemoteUpdateTime = time;
        background(0);
        vidImg = loadImage("RR/"+vidFrame+".jpg");
        if (vidImg != null) {
          for (int x = 0; x < WIDTH; x++) {
            for (int y = 0; y < HEIGHT; y++) {
              cells[y][x].setColor(vidImg.get(x, y));
              cells[y][x].display();
            }
          }
          sendFrame(false);
          vidFrame++;
        } else {
          println("Done playing frames");
          setMusicMode();
        }
      }
      break;
    case RUN_MODE_VIDEO:
      
      if ((time - lastRemoteUpdateTime) > (1000/VIDEO_FPS)) {
        if (videoPlayer.available()) {
          lastRemoteUpdateTime = time;
          videoPlayer.read();
          videoPlayer.loadPixels();
          vidImg = videoPlayer.get();
          vidImg.resize(8, 6);
          for (int x = 0; x < WIDTH; x++) {
            for (int y = 0; y < HEIGHT; y++) {
              color c = vidImg.get(x, y);
              int avg = (int)(red(c) + green(c) + blue(c))/3;
              cells[y][x].setColor(c);
              cells[y][x].display();
            }
          }
          sendFrame(false);
        } else if ((time - lastRemoteUpdateTime) > ((1000/VIDEO_FPS)*10)) {
          println("Done playing video");
          setMusicMode();
        }
      } 
      break;
    case RUN_MODE_CALIBRATING:

      if ((time - lastRemoteUpdateTime) > (1000/CALIBRATION_FPS)) {
        lastRemoteUpdateTime = time;
        for (int x = 0; x < WIDTH; x++) {
          for (int y = 0; y < HEIGHT; y++) {
            cells[y][x].setColor(lerpColor(color(0,0,0), color(255,255,255), random(1)));
            cells[y][x].display();
          }
        }
        head.setHead((int)random(head.MAX_HEAD));
        head.display();
        sendFrame(false);
      }
      
      if ((time - calibrationStartTime) > CALIBRATION_RUN_TIME) {
        calibrating = false;
        setMusicMode();
        println("Calibrating Done");
      }
      break;
  }
  
  
}

void startCalibration() {
  //setupClearBoard(1.0);
  calibrating = true;
//  for (int y = 0; y < HEIGHT; y++) {
//    for (int x = 0; x < WIDTH; x++) {
//      irCells[y][x].resetValues();
//    }
//  }
  clearBoard(1.0);
  head.setMode(HEAD_MODE_PAUSE);
  Minim minim = new Minim(this);
  vidAudio = minim.loadFile("Calibrating.mp3");
  
  calibrationStartTime = millis();
  
  vidAudio.play();
  runMode = RUN_MODE_CALIBRATING;
}

//void playRR() {
//  println("RR");
//  runMode = RUN_MODE_FRAMES;
//  //setupClearBoard(1.0);
//  clearBoard(1.0);
//  lastRemoteUpdateTime = millis();
//  
//  Minim minim = new Minim(this);
//  
//  vidAudio = minim.loadFile("RR/RR.mp3");
//  vidAudio.play();
//}

void playVideo(String file) {
  print("Playing: ");
  println(file);
  runMode = RUN_MODE_VIDEO;
  //setupClearBoard(1.0);
  clearBoard(1.0);
  lastRemoteUpdateTime = millis();
  
  videoPlayer = new Movie(this, file);
  videoPlayer.frameRate(VIDEO_FPS);
  videoPlayer.play();
}

void setMusicMode() {
  setupMusicBoard();
  
  runMode = RUN_MODE_MUSIC;
}


void calibrate() {
  calibrating = true;

}

void nullBoard() {
  
}

void clearBoard(float fade) {
  for (int y = 0; y < cells.length; y++) {
    for (int x = 0; x < cells[y].length; x++) {
      //cells[y][x].setColor(color(0, 0, 0));
      //cells[y][x].setFade(fade);
      cells[y][x].clear();
      cells[y][x].setFade(fade);
    } 
  }
  
  head.setMode(HEAD_MODE_STOP);
}

void setupBoard() {
  if (cells == null) {
    cells = new Cell[HEIGHT][WIDTH];
  }
  
  controls = cells[0];
  for (int x = 0; x < controls.length; x++) {
    controls[x] = new CellControl(x, x*boxSize, 0*boxSize, boxSize, boxSize, color(0, 0, 0), this);
  }
  
  controls[7].setCellMode(CELL_CONTROL_MODE_CLEAR_BOARD);
  
  nodes = new Cell[HEIGHT-2][WIDTH];
  for (int y = 1; y < cells.length-1; y++) {
    //cells[y] = new Cell[WIDTH];
    for (int x = 0; x < cells[y].length; x++) {
      cells[y][x] = new CellNode(x, x*boxSize, y*boxSize, boxSize, boxSize, color(0, 0, 0), this);
      nodes[y-1][x] = cells[y][x];
    } 
  }
  
  insts = cells[cells.length - 1];
  
  for (int x = 0; x < insts.length; x++) {
    insts[x] = new CellInst(x, x*boxSize, (cells.length - 1)*boxSize, boxSize, boxSize, color(0, 0, 0), this);
  }

  
  //head = new PlayHead(0, (cells.length)*boxSize, boxSize*WIDTH, 20, PLAY_HEAD_LEDS);
  
  int tmpAddr = 0;
  for (int row = (HEIGHT-1); row >= 0; row--) {
    if ((row % 2) == 0) {
      for (int i = 0; i < WIDTH; i++) {
        cells[row][i].setAddress(tmpAddr);
        tmpAddr++;
      }
    } else {
      for (int i = (WIDTH - 1); i >= 0; i--) {
        cells[row][i].setAddress(tmpAddr);
        tmpAddr++;
      }
    }
  }


  irCells = new IRCell[HEIGHT][WIDTH];
  
  for (int y = 0; y < cells.length; y++) {
    for (int x = 0; x < cells[y].length; x++) {
       irCells[y][x] = new IRCell(x*boxSize, y*boxSize+((HEIGHT*boxSize)+20), boxSize, boxSize, color(0, 255, 0), this);
    }
  }

  head = new PlayHead(0, (cells.length)*boxSize, boxSize*WIDTH, 20, PLAY_HEAD_LEDS);

}

void setupMusicBoard() {
  clearBoard(0);
  

  for (int x = 0; x < controls.length; x++) {
    //controls[x].clear();
    controls[x].setColor(color(0, 0, 255));
    controls[x].setFade(1.0);
  }
  
  controls[0].setCellMode(CELL_CONTROL_MODE_PLAY_PAUSE);
  
  controls[5].setCellMode(CELL_CONTROL_MODE_RR_CHECK);
  controls[6].setCellMode(CELL_CONTROL_MODE_CALIBRATE);
  controls[7].setCellMode(CELL_CONTROL_MODE_CLEAR_BOARD);
  
  
  for (int y = 1; y < cells.length-1; y++) {
    //cells[y] = new Cell[WIDTH];
    for (int x = 0; x < cells[y].length; x++) {
      cells[y][x].clear();
      cells[y][x].setColor(0, 0, 0);
      cells[y][x].setFade(0.0);
    } 
  }
    
  for (int x = 0; x < insts.length; x++) {
    insts[x].clear();
    insts[x].setColor(color(0, 0, 255));
    insts[x].setFade(1.0);
  }
  
  // Setup the sounds
  insts[0].setColor(255, 255, 255);
  insts[0].setSoundFile(samplesFolder + "1.mp3");
  insts[1].setColor(255, 0, 0);
  insts[1].setSoundFile(samplesFolder + "2.mp3");
  insts[2].setColor(0, 255, 0);
  insts[2].setSoundFile(samplesFolder + "3.mp3");
  insts[3].setColor(0, 0, 255);
  insts[3].setSoundFile(samplesFolder + "4.mp3");
  insts[4].setColor(255, 255, 0);
  insts[4].setSoundFile(samplesFolder + "5.mp3");
  insts[5].setColor(255, 0, 255);
  insts[5].setSoundFile(samplesFolder + "6.mp3");
  insts[6].setColor(0, 255, 255);
  insts[6].setSoundFile(samplesFolder + "7.mp3");
  insts[7].setColor(255, 165, 0);
  insts[7].setSoundFile(samplesFolder + "8.mp3");
  
  
  head.reset();
  head.setMode(HEAD_MODE_PLAY);
}


// Check and do a hit (if needed);
void updateHit() {
  int col = head.getCol(WIDTH);
  if (col != lastHitCol) {
    hitColumn(col);
    lastHitCol = col;
  }
}

// Stop all instruments from pulsating.
void clearInsts() {
  for (int x = 0; x < insts.length; x++) {
    insts[x].clearSelected();
  }
}

// Trigger the 'hit' of all cells in a column.
void hitColumn(int col) {
  for (int y = 0; y < nodes.length; y++) {
    nodes[y][col].hit();
  }
}


// Do the process of sending a frame.
void sendFrame(boolean force) {
  buildFrame(force);
  if (SERIAL_ENABLE && frameBuffer.length > 0) {
    //println(frameBuffer);
    serial.write(frameBuffer);
  }
}

// Build up a frame to be sent.
void buildFrame(boolean force) {
  int bufPoint = 0;
  frameBuffer = new byte[0];
  
  for (int x = 0; x < WIDTH; x++) {
    for (int y = 0; y < HEIGHT; y++) {
      if (force || cells[y][x].getDirty()) {
        cells[y][x].setDirty(false);
        frameBuffer = expand(frameBuffer, (frameBuffer.length + 5));
        color pixel = cells[y][x].getPixel();
        char[] rgb = {'c', (char)cells[y][x].getAddress(), (char)red(pixel), (char)green(pixel), (char)blue(pixel)};
        frameBuffer[bufPoint] = 'c';
        bufPoint++;
        frameBuffer[bufPoint] = (byte)cells[y][x].getAddress();
        bufPoint++;
        frameBuffer[bufPoint] = (byte)red(pixel);
        bufPoint++;
        frameBuffer[bufPoint] = (byte)green(pixel);
        bufPoint++;
        frameBuffer[bufPoint] = (byte)blue(pixel);
        bufPoint++;
      }
    }
  }
  if (force || head.getDirty()) {
    switch (head.getMode()) {
      case HEAD_MODE_PLAY:
        frameBuffer = expand(frameBuffer, (frameBuffer.length + 3));
        frameBuffer[bufPoint] = 'm';
        bufPoint++;
        frameBuffer[bufPoint] = (byte)head.getPosition();
        bufPoint++;
        frameBuffer[bufPoint] = LOOP_TIME/PLAY_HEAD_LEDS;
        bufPoint++;
        break;
      case HEAD_MODE_PAUSE:
        frameBuffer = expand(frameBuffer, (frameBuffer.length + 2));
        frameBuffer[bufPoint] = 'p';
        bufPoint++;
        frameBuffer[bufPoint] = (byte)head.getPosition();
        bufPoint++;
        break;
      case HEAD_MODE_STOP:
        frameBuffer = expand(frameBuffer, (frameBuffer.length + 1));
        frameBuffer[bufPoint] = 's';
        bufPoint++;
        break;
      
    }
    head.setDirty(false);
    
  }
  
}



void serialEvent(Serial myPort) {
  if (!started) {
    myPort.clear();
    return;
  }
  
  int time = millis();
  if (receivingFrame && ((time - lastByteTime) > 50)) {
    println("Reset");
    value = 0;
    firstByteReceived = false;
    receivingFrame = false;
    nextCell = 0;
    nextRow = 0;
  }
  
  while (serial.available() > 0) {
    receivingFrame = true;
    
    lastByteTime = time;
    if (firstByteReceived) {
      value |= serial.read();
      //println(value);
      
      irCells[nextRow][nextCell].setValue(value);
      
      nextCell++;
      if (nextCell >= WIDTH) {
        nextCell = 0;
        nextRow++;
        if (nextRow >= HEIGHT) {
          //println(value);
          //println("Complete Frame");
          value = 0;
          firstByteReceived = false;
          receivingFrame = false;
          nextCell = 0;
          nextRow = 0;
        }
      }
      
      value = 0;
      firstByteReceived = false;
    } else {
      value = serial.read();
      value = value << 8;
      firstByteReceived = true;
    }
  }
}

// Get the average of all the IRCells
float getIRCellAvg() {
  float sum = 0;
  for (int x = 0; x < WIDTH; x++) {
    for (int y = 0; y < HEIGHT; y++) {

      sum += irCells[y][x].getFade();

    }
  }
  
  return sum/(WIDTH*HEIGHT);
}

// Get the max cell, filtering for various criteria
void findMaxIRCell() {
  int maxX = 0, maxY = 0;
  float maxFloat = 0;
  float secondFloat = 0;
  for (int x = 0; x < WIDTH; x++) {
    for (int y = 0; y < HEIGHT; y++) {
      if (irCells[y][x].getFade() > maxFloat) {
        secondFloat = maxFloat;
        maxFloat = irCells[y][x].getFade();
        
        maxX = x;
        maxY = y;
      }
    }
  }
  
  float avg = getIRCellAvg();
  
  if (maxFloat > TOUCH_TRIGGER_LEVEL) {
    handCount++;
    if ((handX == -1) && (handCount > TOUCH_SUCESSIVE_FRAMES)) {
      print("TOUCH! Row:");
      print(maxY+1);
      print(" Cell:");
      println(maxX+1);
      handX = maxX;
      handY = maxY;
      cells[handY][handX].pressEvent();
    }
  } else if (handX >= 0 && maxFloat < TOUCH_RELEASE_LEVEL) {
    print("HAND GONE!");
    cells[handY][handX].releaseEvent();
    handX = -1;
    handY = -1;
    handCount = 0;
  } else if ((handX >= 0) && ((handX != maxX) || (handY != maxY))) {
    print("HAND Move!");
    cells[handY][handX].releaseEvent();
    handX = -1;
    handY = -1;
    handCount = 0;
  } else {
    handCount = 0;
  }
}


// Generic cell class, mainly to be extended.
class Cell {
  // A cell object knows about its location in the grid as well as its size with the variables x,y,w,h.
  int column;
  int x,y;   // x,y location
  int w,h;   // WIDTH and HEIGHT
  int R, G, B; // Color
  color cellColor;
  boolean over;
  boolean pressed;
  boolean selected = false;
  float fade = 1;
  float fadeDir = 0;
  
  boolean dirty = true;
  
  int address = 0;

  // Cell Constructor
  Cell(int c, int tempX, int tempY, int tempW, int tempH, color tempColor, PApplet parent) {
    this.column = c;
    this.x = tempX;
    this.y = tempY;
    this.w = tempW;
    this.h = tempH;
    this.setColor(tempColor);
  }
  
  void setAddress (int addr) {
    this.address = addr;
  }
  
  int getAddress() {
    return this.address;
  }
  

  void setDirty(boolean d) {
    this.dirty = d;
  }
  
  boolean getDirty() {
    return this.dirty;
  }
  

  void setColor(int tempR, int tempG, int tempB) {
    R = tempR;
    G = tempG;
    B = tempB;
    this.cellColor = color(R, G, B);
    this.setDirty(true);
  }
  
  void setColor(color tempColor) {
    if (tempColor != this.cellColor) {
      R = (int)red(tempColor);
      G = (int)green(tempColor);
      B = (int)blue(tempColor);
      this.cellColor = tempColor;
      this.setDirty(true);
    }
  }
  
  void setFade(float f) {
    this.fade = f;
    this.setDirty(true);
  }

  color getColor() {
    return this.cellColor;
  }
  
  void update() {
    if (mousePressed) {
      if (overRect(x, y, w, h)) {
        if (!this.pressed) {
          pressEvent();
          this.pressed = true;
        }
      }
    }
  }
  
  void releaseEvent() {
    this.pressed = false;
  }
  
  color getPixel() {
    return color(red(this.cellColor)*fade, green(this.cellColor)*fade, blue(this.cellColor)*fade);
  }

  void display() {
    stroke(255);

    fill(this.getPixel());
    
    rect(this.x, this.y, this.w, this.h); 
  }


  // Stubs
  void pressEvent() {}
  
  void clear() {
    this.selected = false;
    this.setFade(0);
    this.setColor(color(0, 0, 0));
  }
  
  void clearSelected() {}
  
  void setSoundFile(String tmpFile) {}
  
  void setPlayer(AudioPlayer tmpPlayer) {}
  
  void hit() {}
  
  AudioPlayer getPlayer(int x) { return null; }
  
  String getSoundFile() { return ""; }
  
  void setCellMode(int m) {}

}

// Represents a 'node', or a place on the board for instruments to be placed.
class CellNode extends Cell {
  Cell inst = null;
  AudioPlayer player = null;
  
  CellNode(int c, int tempX, int tempY, int tempW, int tempH, color tempColor, PApplet parent) {
    super(c, tempX, tempY, tempW, tempH, tempColor, parent);    
  }
  
  void update() {
    super.update();
    if (this.fade > CELL_NODE_LOW_FADE) {
      this.setFade(this.fade - CELL_NODE_FADE_SPEED);
    }
  }
  
  void pressEvent() {
    this.selected = !this.selected;
    
    if (this.selected) {
      if (selectedInst != null) {
        this.setColor(selectedInst.getColor());
        this.setFade(CELL_NODE_LOW_FADE);
        this.setPlayer(selectedInst.getPlayer(this.column % 2));
        
      } else {
        this.selected = false;
      }
    } else {
      player = null;
      System.gc();
      this.setColor(0, 0, 0);
    }
    
  }
  
  void setPlayer(AudioPlayer tmpPlayer) {
    this.player = tmpPlayer;
  }
  
  void playSound() {
    if (this.selected) {
      this.player.play(0);
    }
  }
  
  void hit() {
    if (this.selected) {
      this.setFade(CELL_NODE_FADE_HIT);
      playSound();
    }
  }
  
  void clear() {
    super.clear();
    this.inst = null;
    this.player = null;
  }
}

// A pulsating cell class
class CellPulse extends Cell {
  CellPulse(int c, int tempX, int tempY, int tempW, int tempH, color tempColor, PApplet parent) {
    super(c, tempX, tempY, tempW, tempH, tempColor, parent);
  }
  
  void update() {
    super.update();
    
    if (selected) {
      this.setFade(this.fade + (this.fadeDir * CELL_PULSE_FADE_SPEED));
      
      if (this.fade >= CELL_PULSE_HIGH_FADE) {
        this.setFade(fade = CELL_PULSE_HIGH_FADE);
        this.fadeDir = FADE_DOWN;
      } else if (fade <= CELL_PULSE_LOW_FADE) {
        this.setFade(CELL_PULSE_LOW_FADE);
        this.fadeDir = FADE_UP;
      }
    }
  }
  
  void pressEvent() {
    selected = true;
    this.setFade(CELL_PULSE_LOW_FADE);
  }
  
  void clear() {
    super.clear();
    this.fadeDir = FADE_STOP;
    this.setFade(1.00);
    this.selected = false;
  }
  
  void clearSelected() {
    this.fadeDir = FADE_STOP;
    this.setFade(1.00);
    this.selected = false;
  }
}

// An instrument cell.
class CellInst extends CellPulse {
  AudioPlayer player[] = new AudioPlayer[2];;
  Minim minim;
  String soundFile = null;
  
  CellInst(int c, int tempX, int tempY, int tempW, int tempH, color tempColor, PApplet parent) {
    super(c, tempX, tempY, tempW, tempH, tempColor, parent);
    
    this.minim = new Minim(parent);
  }
  
  void pressEvent() {
    super.pressEvent();
    if (this.selected) {
      clearInsts();
      this.selected = true;
      selectedInst = this;
      this.fadeDir = FADE_DOWN;
    } else {
      
    }
  }
  
  void setSoundFile(String tmpSound) {
    this.soundFile = tmpSound;
    this.player[0] = minim.loadFile(soundFile);
    this.player[1] = minim.loadFile(soundFile);
  }
  
  AudioPlayer getPlayer(int x) {
    return this.player[x];
  }
  
  String getSoundFile() {
    return this.soundFile;
  }
  
  void clear() {
    super.clear();
    if (player != null) {
      if (player[0] != null) {
        player[0].close();
        player[0] = null;
      }
      if (player[1] != null) {
        player[1].close();
        player[1] = null;
      }
    }
    soundFile = null;
  }
}

class CellControl extends CellPulse {
  int cellMode = 0;
  
  CellControl(int c, int tempX, int tempY, int tempW, int tempH, color tempColor, PApplet parent) {
    super(c, tempX, tempY, tempW, tempH, tempColor, parent);
  }
  
  void setCellMode(int m) {
    this.cellMode = m;
  }
  
  void pressEvent() {
    switch (this.cellMode) {
      case CELL_CONTROL_MODE_CALIBRATE:
        startCalibration();
        break;
      case CELL_CONTROL_MODE_CLEAR_BOARD:
        setupMusicBoard();
        break;
      case CELL_CONTROL_MODE_RR_CHECK:
        println("Check");
        if (cells[1][4].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[2][1].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[2][2].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[2][4].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[2][5].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[3][0].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[3][4].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[3][6].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[4][0].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[4][4].getColor() != color(255, 0, 0)) {
          return;
        }
        if (cells[4][5].getColor() != color(255, 0, 0)) {
          return;
        }
        
        playVideo(RR_FILE);
        break;
    }
  }
}

class PlayHead {
  final int MAX_HEAD = 1024;
  int x,y;   // x,y location
  int w,h;   // WIDTH and HEIGHT
  int segments;
  int speed = 1;
  int position = 0;
  int head = 0;
  int lastTime = 0;
  int loopTime = LOOP_TIME;
  int mode = HEAD_MODE_STOP;
  boolean dirty = true;
  
  color[] pixs;
  
  PlayHead(int tempX, int tempY, int tempW, int tempH, int tempSegs) {
    this.x = tempX;
    this.y = tempY;
    this.w = tempW;
    this.h = tempH;
    this.segments = tempSegs;
    this.pixs = new color[segments];
    lastTime = millis();
  }

  void update() {
    switch (this.mode) {
      case HEAD_MODE_PLAY:
        int diff = millis() - this.lastTime;
        this.lastTime = millis();
        this.setHead(this.head + (int)(((float)diff/this.loopTime)*MAX_HEAD));
        
        
        break;
      case HEAD_MODE_PAUSE:
      
        break;
      case HEAD_MODE_STOP:
      
        break;
      
    }
    
  }
  
  void setHead(int h) {
    //println(h);
    while (h >= MAX_HEAD) {
      h -= MAX_HEAD;
    }
    
    this.head = h;
    
    int pos = (int)(min(((float)this.head/MAX_HEAD), 1.0) * (this.segments-1));
    pos = max(0, pos);
    //println(h);
    this.pixs[pos] = color(255);
    this.position = pos;
    if (pos == 0) {
      this.pixs[segments - 1] = color(0);
    } else {
      this.pixs[pos - 1] = color(0);
    }
    
    this.setDirty(true);
  }
  
  void display() {
    stroke(255);
    for (int i = 0; i < this.segments; i ++) {
      fill(this.pixs[i]);
      rect((this.w/this.segments)*i, this.y, (this.w/this.segments), this.h);
    }
  }
  
  void reset() {
    this.lastTime = millis();
    this.position = 0;
    this.head = 0;
    for (int i = 0; i < this.pixs.length; i++) {
      this.pixs[i] = color(0);
    }
    
    this.setDirty(true);
  }
  
  void setMode(int m) {
    this.mode = m;
  }
  
  int getMode() {
    return this.mode;
  }
  
  int getPosition() {
    return this.position;
  }
  
  int getCol(int cnt) {
    return floor(((float)this.head/MAX_HEAD)*cnt);
  }
  
  boolean getDirty() {
    return this.dirty;
  }
  
  void setDirty(boolean d) {
    this.dirty = d;
  }
}



class IRCell {
  // A cell object knows about its location in the grid as well as its size with the variables x,y,w,h.
  int x,y;   // x,y location
  int w,h;   // WIDTH and HEIGHT
  int R, G, B; // Color
  int value = 0;
  color cellColor;
  boolean over;
  float fade;
  
  float longVal = 0;
  float shortVal = 0;
  
  int[] lastValues = new int[TOUCH_AVERAGE_LENGTH];

  // Cell Constructor
  IRCell(int tempX, int tempY, int tempW, int tempH, color tempColor, PApplet parent) {
    this.x = tempX;
    this.y = tempY;
    this.w = tempW;
    this.h = tempH;
    this.setColor(tempColor);
  }
  
  void setColor(int tempR, int tempG, int tempB) {
    this.R = tempR;
    this.G = tempG;
    this.B = tempB;
    this.cellColor = color(R, G, B);
  }

void resetValues() {
//  this.longVal = 0.0;
//  this.shortVal = 0.0;
//  for (int i = 0; i < this.lastValues.length; i++) {
//    this.lastValues[i] = 0;
//  }
}

  void setColor(color tempColor) {
    this.R = (int)red(tempColor);
    this.G = (int)green(tempColor);
    this.B = (int)blue(tempColor);
    this.cellColor = tempColor;
  }
  
  
  void setValue(int val) {
    for(int i = (this.lastValues.length - 1); i > 0; i--) {
      this.lastValues[i] = this.lastValues[i-1];
    }
    this.lastValues[0] = val;
    
    int sum = 0;
    for(int i = 0; i < this.lastValues.length; i++) {
      sum += this.lastValues[i];
    }
    this.shortVal = sum/this.lastValues.length;
    //println(this.shortVal);
    //shortVal = shortVal + (1-.5)*(val - shortVal);
    if (calibrating) {
      //longVal = longVal + (1-.95)*(shortVal - longVal);
      //println("U");
      if (this.shortVal > this.longVal) {
        println("Update");
        this.longVal = this.shortVal;
      }
    } else {
      //this.longVal = this.longVal + (1-.999)*(this.shortVal - this.longVal);
    }
    //longVal = min(950, longVal);
    //longVal = 775;
    //println(val);
    this.value = val;
    float tmp = this.shortVal-this.longVal;
    //println(this.longVal);
    tmp = (float)tmp/(TOUCH_VALUE_RANGE-this.longVal);
    tmp *= TOUCH_DIFF_MULTIPLIER;
    //println(tmp);
    tmp = max(0.0, tmp);
    tmp = min(1.0, tmp);
    this.fade = tmp;
  }
  
  int getVal() {
    return this.value;
  }
  
  float getFade() {
    return this.fade;
  }
  

  color getColor() {
    return this.cellColor;
  }
  
  void update() {}
  

  void releaseEvent() {}
  
  color getPixel() {
    return color(red(this.cellColor)*this.fade, green(this.cellColor)*this.fade, blue(this.cellColor)*this.fade);
  }

  void display() {
    stroke(255);

    fill(this.getPixel());
    
    rect(this.x, this.y, this.w, this.h); 
  }
}







// Helper functions
boolean overRect(int x, int y, int w, int h) {
  if (mouseX >= x && mouseX <= x+w && 
      mouseY >= y && mouseY <= y+h) {
    return true;
  } else {
    return false;
  }
}

void mouseReleased()  {
  for (int x = 0; x < WIDTH; x++) {
    for (int y = 0; y < HEIGHT; y++) {
      // Oscillate and display each object
      cells[y][x].releaseEvent();
    }
  }
}
