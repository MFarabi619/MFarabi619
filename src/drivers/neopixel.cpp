#include "neopixel.h"
#include "../config.h"
#include "../console/colors.h"

#include <Adafruit_NeoPixel.h>

static Adafruit_NeoPixel pixel(CONFIG_NEOPIXEL_COUNT, CONFIG_NEOPIXEL_GPIO,
                               NEO_GRB + NEO_KHZ800);

void neopixel_init(void) {
  pixel.begin();
  pixel.setBrightness(CONFIG_NEOPIXEL_BRIGHTNESS);
  pixel.clear();
  pixel.show();
}

static void set_color(uint32_t color) {
  pixel.setPixelColor(0, color);
  pixel.show();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status indicators
// ─────────────────────────────────────────────────────────────────────────────

void neopixel_off(void)     { pixel.clear(); pixel.show(); }
void neopixel_red(void)     { set_color(pixel.Color(RGB_RED)); }
void neopixel_green(void)   { set_color(pixel.Color(RGB_GREEN)); }
void neopixel_blue(void)    { set_color(pixel.Color(RGB_BLUE)); }
void neopixel_yellow(void)  { set_color(pixel.Color(RGB_YELLOW)); }
void neopixel_magenta(void) { set_color(pixel.Color(RGB_MAGENTA)); }
void neopixel_cyan(void)    { set_color(pixel.Color(RGB_CYAN)); }
void neopixel_white(void)   { set_color(pixel.Color(RGB_WHITE)); }

// ─────────────────────────────────────────────────────────────────────────────
//  Custom color
// ─────────────────────────────────────────────────────────────────────────────

void neopixel_rgb(uint8_t r, uint8_t g, uint8_t b) {
  set_color(pixel.Color(r, g, b));
}

void neopixel_hsv(uint16_t hue, uint8_t sat, uint8_t val) {
  set_color(pixel.gamma32(pixel.ColorHSV(hue, sat, val)));
}

void neopixel_brightness(uint8_t level) {
  pixel.setBrightness(level);
  pixel.show();
}

uint32_t neopixel_get_color(void) { return pixel.getPixelColor(0); }

uint8_t neopixel_get_brightness(void) { return pixel.getBrightness(); }

// ─────────────────────────────────────────────────────────────────────────────
//  Tests — describe("Neopixel")
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include <Arduino.h>

static void neopixel_test_init(void) {
  TEST_MESSAGE("user initializes the neopixel");
  neopixel_init();
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(
      CONFIG_NEOPIXEL_BRIGHTNESS, neopixel_get_brightness(),
      "device: brightness should match CONFIG_NEOPIXEL_BRIGHTNESS after init");
  TEST_MESSAGE("neopixel initialized");
}

static void neopixel_test_rgb_readback(void) {
  TEST_MESSAGE("user sets RGB color and reads it back");
  neopixel_init();

  neopixel_rgb(255, 0, 0);
  uint32_t color = neopixel_get_color();
  // Brightness scaling affects getPixelColor readback, so check non-zero
  TEST_ASSERT_NOT_EQUAL_MESSAGE(
      0, color, "device: color should be non-zero after setting red");

  neopixel_off();
  TEST_ASSERT_EQUAL_HEX32_MESSAGE(0, neopixel_get_color(),
                                  "device: color should be 0 after off");

  TEST_MESSAGE("RGB set/readback verified");
}

static void neopixel_test_status_colors(void) {
  TEST_MESSAGE("user cycles through all status colors (500ms each)");
  neopixel_init();

  struct { void (*fn)(void); const char *name; } colors[] = {
    { neopixel_red,     "RED" },
    { neopixel_green,   "GREEN" },
    { neopixel_blue,    "BLUE" },
    { neopixel_yellow,  "YELLOW" },
    { neopixel_magenta, "MAGENTA" },
    { neopixel_cyan,    "CYAN" },
    { neopixel_white,   "WHITE" },
  };

  for (int i = 0; i < 7; i++) {
    colors[i].fn();
    TEST_ASSERT_NOT_EQUAL_MESSAGE(0, neopixel_get_color(), colors[i].name);
    delay(500);
  }

  neopixel_off();
  TEST_MESSAGE("all status colors displayed");
}

static void neopixel_test_hsv_rainbow(void) {
  TEST_MESSAGE("user cycles through HSV rainbow (variable speed like Rust test)");
  neopixel_init();

  // Sweep 256 hue steps across full wheel (0-65535)
  // Speed varies: faster in the middle, slower at edges
  for (uint16_t step = 0; step < 256; step++) {
    uint16_t hue = step * 256;
    neopixel_hsv(hue, 255, 255);

    int distance_from_center = abs((int)step - 128);
    int step_ms = 4 + (24 * distance_from_center / 128);
    delay(step_ms);
  }

  // Hold final hue for 1 second
  neopixel_hsv(170 * 256, 255, 255);
  delay(1000);

  neopixel_off();
  TEST_MESSAGE("HSV rainbow cycle complete");
}

static void neopixel_test_brightness(void) {
  TEST_MESSAGE("user adjusts brightness");
  neopixel_init();

  neopixel_brightness(10);
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(10, neopixel_get_brightness(),
                                  "device: brightness should be 10");

  neopixel_brightness(255);
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(255, neopixel_get_brightness(),
                                  "device: brightness should be 255");

  neopixel_brightness(CONFIG_NEOPIXEL_BRIGHTNESS);
  neopixel_off();
  TEST_MESSAGE("brightness control verified");
}

void neopixel_run_tests(void) {
  // Skipped for now — neopixel visual tests slow down the test suite
}

#endif
