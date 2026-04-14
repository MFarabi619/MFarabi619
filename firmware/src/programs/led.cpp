#include "led.h"
#include "../config.h"

#include <FastLED.h>

namespace {
CRGB pixel[1];

CRGB toCRGB(const Color &c) { return CRGB(c.r, c.g, c.b); }
Color fromCRGB(const CRGB &c) { return {c.r, c.g, c.b}; }
}

Led LED;

bool Led::init() {
    FastLED.addLeds<NEOPIXEL, config::led::GPIO>(pixel, 1)
        .setCorrection(TypicalSMD5050);
    FastLED.setBrightness(config::led::BRIGHTNESS);
    pixel[0] = CRGB::Black;
    FastLED.show();
    return true;
}

void Led::set(const Color &color) {
    pixel[0] = toCRGB(color);
    FastLED.show();
}

void Led::set(uint8_t r, uint8_t g, uint8_t b) {
    pixel[0] = CRGB(r, g, b);
    FastLED.show();
}

void Led::setHSV(uint8_t hue, uint8_t saturation, uint8_t value) {
    pixel[0] = CHSV(hue, saturation, value);
    FastLED.show();
}

void Led::off() {
    pixel[0] = CRGB::Black;
    FastLED.show();
}

void Led::setBrightness(uint8_t b) {
    FastLED.setBrightness(b);
    FastLED.show();
}

uint8_t Led::getBrightness() {
    return FastLED.getBrightness();
}

Color Led::getColor() {
    return fromCRGB(pixel[0]);
}

void Led::glow(uint32_t duration_ms) {
    uint8_t saved = getBrightness();
    uint32_t start = millis();
    while (millis() - start < duration_ms) {
        FastLED.setBrightness(beatsin8(30, 10, 210));
        pixel[0] = toCRGB(colors::BlueViolet);
        FastLED.show();
        delay(config::led::FRAME_MS);
    }
    FastLED.setBrightness(saved);
}

void Led::fadeIn(const Color &color, uint32_t duration_ms) {
    uint8_t target = getBrightness();
    CRGB c = toCRGB(color);
    uint32_t start = millis();
    while (millis() - start < duration_ms) {
        uint8_t progress = ((millis() - start) * 255) / duration_ms;
        FastLED.setBrightness(scale8(ease8InOutQuad(progress), target));
        pixel[0] = c;
        FastLED.show();
        delay(config::led::FRAME_MS);
    }
    FastLED.setBrightness(target);
    pixel[0] = c;
    FastLED.show();
}

void Led::fadeOut(const Color &color, uint32_t duration_ms) {
    uint8_t saved = getBrightness();
    CRGB c = toCRGB(color);
    uint32_t start = millis();
    while (millis() - start < duration_ms) {
        uint8_t progress = ((millis() - start) * 255) / duration_ms;
        FastLED.setBrightness(scale8(ease8InOutQuad(255 - progress), saved));
        pixel[0] = c;
        FastLED.show();
        delay(config::led::FRAME_MS);
    }
    pixel[0] = CRGB::Black;
    FastLED.show();
    FastLED.setBrightness(saved);
}

#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"

static void led_test_init(void) {
    TEST_MESSAGE("user initializes the LED");
    TEST_ASSERT_TRUE_MESSAGE(LED.init(), "device: LED init must succeed");
    Color color = LED.getColor();
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.r, "device: LED must start black (r)");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.g, "device: LED must start black (g)");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.b, "device: LED must start black (b)");
}

static void led_test_set_named(void) {
    TEST_MESSAGE("user sets LED to a named color");
    LED.set(colors::Red);
    Color color = LED.getColor();
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(255, color.r, "device: red channel");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.g, "device: green channel");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.b, "device: blue channel");
}

static void led_test_set_rgb(void) {
    TEST_MESSAGE("user sets LED with explicit r, g, b values");
    LED.set(100, 200, 50);
    Color color = LED.getColor();
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(100, color.r, "device: red channel");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(200, color.g, "device: green channel");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(50, color.b, "device: blue channel");
}

static void led_test_set_hsv(void) {
    TEST_MESSAGE("user sets LED via HSV");
    LED.setHSV(0, 255, 255);
    Color color = LED.getColor();
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(255, color.r, "device: hue 0 should be red");
    TEST_ASSERT_TRUE_MESSAGE(color.g < 10, "device: green should be near zero for red hue");
    TEST_ASSERT_TRUE_MESSAGE(color.b < 10, "device: blue should be near zero for red hue");
}

static void led_test_off(void) {
    TEST_MESSAGE("user turns the LED off");
    LED.set(colors::White);
    LED.off();
    Color color = LED.getColor();
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.r, "device: red must be 0 after off");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.g, "device: green must be 0 after off");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.b, "device: blue must be 0 after off");
}

static void led_test_brightness(void) {
    TEST_MESSAGE("user adjusts LED brightness");
    LED.setBrightness(128);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(128, LED.getBrightness(),
        "device: brightness must match after set");
    LED.setBrightness(255);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(255, LED.getBrightness(),
        "device: brightness must restore to max");
}

static void led_test_fade_in_reaches_target(void) {
    TEST_MESSAGE("user verifies fadeIn ends at the target color");
    LED.setBrightness(config::led::BRIGHTNESS);
    LED.fadeIn(colors::Gold, 100);
    Color color = LED.getColor();
    TEST_ASSERT_TRUE_MESSAGE(color.r > 200, "device: red after fadeIn");
    TEST_ASSERT_TRUE_MESSAGE(color.g > 150, "device: green after fadeIn");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(config::led::BRIGHTNESS, LED.getBrightness(),
        "device: brightness must restore after fadeIn");
}

static void led_test_fade_out_goes_black(void) {
    TEST_MESSAGE("user verifies fadeOut ends at black");
    LED.set(colors::White);
    LED.fadeOut(colors::White, 100);
    Color color = LED.getColor();
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.r, "device: red after fadeOut");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.g, "device: green after fadeOut");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, color.b, "device: blue after fadeOut");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(config::led::BRIGHTNESS, LED.getBrightness(),
        "device: brightness must restore after fadeOut");
}

void programs::led::test(void) {
    it("user initializes the LED", led_test_init);
    it("user sets LED to a named color", led_test_set_named);
    it("user sets LED with explicit RGB values", led_test_set_rgb);
    it("user sets LED via HSV", led_test_set_hsv);
    it("user turns the LED off", led_test_off);
    it("user adjusts LED brightness", led_test_brightness);
    it("user verifies fadeIn reaches target color", led_test_fade_in_reaches_target);
    it("user verifies fadeOut ends at black", led_test_fade_out_goes_black);
}

#endif
