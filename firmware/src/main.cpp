#include <Arduino.h>

typedef struct {
  int gpio;
  int header_pin;
  const char *name;
} pin_t;

enum {
  PIN_IO44_RX0,
  PIN_IO43_TX0,
  PIN_IO0_3V3_EN,
  PIN_IO12,
  PIN_IO11,
  PIN_IO13,
  PIN_IO38,
  PIN_IO39,
  PIN_IO40,
  PIN_IO41,
  PIN_IO42,
  PIN_IO2,
  PIN_IO1,
  PIN_IO10,
  PIN_IO9,
  PIN_IO8,
  PIN_IO18,
  PIN_IO17,
  PIN_IO16,
  PIN_IO15,
  PIN_IO7,
  PIN_IO6,
  PIN_IO5,
  PIN_IO4,
  PIN_COUNT
};

static const pin_t pins[PIN_COUNT] = {[PIN_IO44_RX0] = {44, 2, "IO44/RX0"},
                                      [PIN_IO43_TX0] = {43, 3, "IO43/TX0"},
                                      [PIN_IO0_3V3_EN] = {0, 4, "IO0/3V3-EN"},
                                      [PIN_IO12] = {12, 5, "IO12"},
                                      [PIN_IO11] = {11, 6, "IO11"},
                                      [PIN_IO13] = {13, 7, "IO13"},
                                      [PIN_IO38] = {38, 8, "IO38"},
                                      [PIN_IO39] = {39, 9, "IO39"},
                                      [PIN_IO40] = {40, 10, "IO40"},
                                      [PIN_IO41] = {41, 11, "IO41"},
                                      [PIN_IO42] = {42, 12, "IO42"},
                                      [PIN_IO2] = {2, 13, "IO2"},
                                      [PIN_IO1] = {1, 14, "IO1"},
                                      [PIN_IO10] = {10, 25, "IO10"},
                                      [PIN_IO9] = {9, 24, "IO9"},
                                      [PIN_IO8] = {8, 23, "IO8"},
                                      [PIN_IO18] = {18, 22, "IO18"},
                                      [PIN_IO17] = {17, 21, "IO17"},
                                      [PIN_IO16] = {16, 20, "IO16"},
                                      [PIN_IO15] = {15, 19, "IO15"},
                                      [PIN_IO7] = {7, 18, "IO7"},
                                      [PIN_IO6] = {6, 17, "IO6"},
                                      [PIN_IO5] = {5, 16, "IO5"},
                                      [PIN_IO4] = {4, 15, "IO4"}};

static int gpio(int pin_id) { return pins[pin_id].gpio; }

void setup(void) {
  Serial.begin(115200);
  pinMode(gpio(PIN_IO12), OUTPUT);
}

void loop(void) {
  delay(1000);
  digitalWrite(gpio(PIN_IO12), !digitalRead(gpio(PIN_IO12)));
  Serial.println(digitalRead(gpio(PIN_IO12)));
}

// #include <Arduino_GFX_Library.h>

// #include "apidae_banner_800x480.h"

// static const uint16_t DISPLAY_WIDTH = 800;
// static const uint16_t DISPLAY_HEIGHT = 480;

// static const uint16_t COLOR_BLACK = 0x0000;

// static const int PIN_BL = 2;

// static const int PIN_DE = 40;
// static const int PIN_VSYNC = 41;
// static const int PIN_HSYNC = 39;
// static const int PIN_PCLK = 42;

// static const int PIN_R0 = 45;
// static const int PIN_R1 = 48;
// static const int PIN_R2 = 47;
// static const int PIN_R3 = 21;
// static const int PIN_R4 = 14;

// static const int PIN_G0 = 5;
// static const int PIN_G1 = 6;
// static const int PIN_G2 = 7;
// static const int PIN_G3 = 15;
// static const int PIN_G4 = 16;
// static const int PIN_G5 = 4;

// static const int PIN_B0 = 8;
// static const int PIN_B1 = 3;
// static const int PIN_B2 = 46;
// static const int PIN_B3 = 9;
// static const int PIN_B4 = 1;

// static const int PANEL_HSYNC_POLARITY = 0;
// static const int PANEL_HSYNC_FRONT_PORCH = 8;
// static const int PANEL_HSYNC_PULSE_WIDTH = 4;
// static const int PANEL_HSYNC_BACK_PORCH = 8;

// static const int PANEL_VSYNC_POLARITY = 0;
// static const int PANEL_VSYNC_FRONT_PORCH = 8;
// static const int PANEL_VSYNC_PULSE_WIDTH = 4;
// static const int PANEL_VSYNC_BACK_PORCH = 8;

// static const int PANEL_PCLK_ACTIVE_NEG = 1;
// static const int PANEL_PCLK_HZ = 16000000;

// static Arduino_ESP32RGBPanel
//     RGB_PANEL(PIN_DE, PIN_VSYNC, PIN_HSYNC, PIN_PCLK, PIN_R0, PIN_R1, PIN_R2,
//               PIN_R3, PIN_R4, PIN_G0, PIN_G1, PIN_G2, PIN_G3, PIN_G4, PIN_G5,
//               PIN_B0, PIN_B1, PIN_B2, PIN_B3, PIN_B4, PANEL_HSYNC_POLARITY,
//               PANEL_HSYNC_FRONT_PORCH, PANEL_HSYNC_PULSE_WIDTH,
//               PANEL_HSYNC_BACK_PORCH, PANEL_VSYNC_POLARITY,
//               PANEL_VSYNC_FRONT_PORCH, PANEL_VSYNC_PULSE_WIDTH,
//               PANEL_VSYNC_BACK_PORCH, PANEL_PCLK_ACTIVE_NEG, PANEL_PCLK_HZ);

// static Arduino_RGB_Display GFX(DISPLAY_WIDTH, DISPLAY_HEIGHT, &RGB_PANEL, 0,
//                                true);

// static void render_screen(void) {
//   int16_t image_x = (int16_t)((DISPLAY_WIDTH - APIDAE_BANNER_WIDTH) / 2);
//   int16_t image_y = (int16_t)((DISPLAY_HEIGHT - APIDAE_BANNER_HEIGHT) / 2);

//   GFX.fillScreen(COLOR_BLACK);
//   GFX.draw16bitRGBBitmap(image_x, image_y, (uint16_t *)APIDAE_BANNER_RGB565,
//                          APIDAE_BANNER_WIDTH, APIDAE_BANNER_HEIGHT);
// }

// void setup(void) {
//   Serial.begin(115200);
//   delay(120);

//   pinMode(PIN_BL, OUTPUT);
//   digitalWrite(PIN_BL, HIGH);

//   if (!GFX.begin()) {
//     Serial.println("display init failed");
//     while (true) {
//       delay(1000);
//     }
//   }

//   render_screen();
// }

// void loop(void) {
//   delay(1000);
// }
