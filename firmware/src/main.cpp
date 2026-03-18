#include <Arduino.h>
#include <Arduino_GFX_Library.h>

#include "apidae_banner_800x480.h"

static const uint16_t DISPLAY_WIDTH = 800;
static const uint16_t DISPLAY_HEIGHT = 480;

static const uint16_t COLOR_BLACK = 0x0000;

static const int PIN_BL = 2;

static const int PIN_DE = 40;
static const int PIN_VSYNC = 41;
static const int PIN_HSYNC = 39;
static const int PIN_PCLK = 42;

static const int PIN_R0 = 45;
static const int PIN_R1 = 48;
static const int PIN_R2 = 47;
static const int PIN_R3 = 21;
static const int PIN_R4 = 14;

static const int PIN_G0 = 5;
static const int PIN_G1 = 6;
static const int PIN_G2 = 7;
static const int PIN_G3 = 15;
static const int PIN_G4 = 16;
static const int PIN_G5 = 4;

static const int PIN_B0 = 8;
static const int PIN_B1 = 3;
static const int PIN_B2 = 46;
static const int PIN_B3 = 9;
static const int PIN_B4 = 1;

static const int PANEL_HSYNC_POLARITY = 0;
static const int PANEL_HSYNC_FRONT_PORCH = 8;
static const int PANEL_HSYNC_PULSE_WIDTH = 4;
static const int PANEL_HSYNC_BACK_PORCH = 8;

static const int PANEL_VSYNC_POLARITY = 0;
static const int PANEL_VSYNC_FRONT_PORCH = 8;
static const int PANEL_VSYNC_PULSE_WIDTH = 4;
static const int PANEL_VSYNC_BACK_PORCH = 8;

static const int PANEL_PCLK_ACTIVE_NEG = 1;
static const int PANEL_PCLK_HZ = 16000000;

static Arduino_ESP32RGBPanel
    RGB_PANEL(PIN_DE, PIN_VSYNC, PIN_HSYNC, PIN_PCLK, PIN_R0, PIN_R1, PIN_R2,
              PIN_R3, PIN_R4, PIN_G0, PIN_G1, PIN_G2, PIN_G3, PIN_G4, PIN_G5,
              PIN_B0, PIN_B1, PIN_B2, PIN_B3, PIN_B4, PANEL_HSYNC_POLARITY,
              PANEL_HSYNC_FRONT_PORCH, PANEL_HSYNC_PULSE_WIDTH,
              PANEL_HSYNC_BACK_PORCH, PANEL_VSYNC_POLARITY,
              PANEL_VSYNC_FRONT_PORCH, PANEL_VSYNC_PULSE_WIDTH,
              PANEL_VSYNC_BACK_PORCH, PANEL_PCLK_ACTIVE_NEG, PANEL_PCLK_HZ);

static Arduino_RGB_Display GFX(DISPLAY_WIDTH, DISPLAY_HEIGHT, &RGB_PANEL, 0,
                               true);

static void render_screen(void) {
  int16_t image_x = (int16_t)((DISPLAY_WIDTH - APIDAE_BANNER_WIDTH) / 2);
  int16_t image_y = (int16_t)((DISPLAY_HEIGHT - APIDAE_BANNER_HEIGHT) / 2);

  GFX.fillScreen(COLOR_BLACK);
  GFX.draw16bitRGBBitmap(image_x, image_y, (uint16_t *)APIDAE_BANNER_RGB565,
                         APIDAE_BANNER_WIDTH, APIDAE_BANNER_HEIGHT);
}

void setup(void) {
  Serial.begin(115200);
  delay(120);

  pinMode(PIN_BL, OUTPUT);
  digitalWrite(PIN_BL, HIGH);

  if (!GFX.begin()) {
    Serial.println("display init failed");
    while (true) {
      delay(1000);
    }
  }

  render_screen();
}

void loop(void) { delay(1000); }
