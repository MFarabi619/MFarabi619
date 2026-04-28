#include <led.h>
#include <config.h>
#include "../power/sleep.h"

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

    SleepConfig sleep_config = {};
    power::sleep::accessConfig(&sleep_config);
    uint8_t brightness = sleep_config.enabled
        ? config::led::DIM_BRIGHTNESS
        : config::led::BRIGHTNESS;
    FastLED.setBrightness(brightness);

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

#include <testing/utils.h>

static void test_led_init(void) {
    WHEN("the LED is initialized");
    TEST_ASSERT_TRUE_MESSAGE(LED.init(), "device: LED init must succeed");
    Color color = LED.getColor();
    TEST_ASSERT_EACH_EQUAL_UINT8_MESSAGE(0, &color.r, 3,
        "device: LED must start black");
}

static void test_led_set_named(void) {
    WHEN("the LED is set to a named color");
    LED.set(colors::Red);
    Color color = LED.getColor();
    Color expected = colors::Red;
    TEST_ASSERT_EQUAL_UINT8_ARRAY_MESSAGE(&expected.r, &color.r, 3,
        "device: color should match Red");
}

static void test_led_set_rgb(void) {
    WHEN("the LED is set with explicit RGB values");
    LED.set(100, 200, 50);
    Color color = LED.getColor();
    Color expected = {100, 200, 50};
    TEST_ASSERT_EQUAL_UINT8_ARRAY_MESSAGE(&expected.r, &color.r, 3,
        "device: color should match {100, 200, 50}");
}

static void test_led_set_hsv(void) {
    WHEN("the LED is set via HSV");
    LED.setHSV(0, 255, 255);
    Color color = LED.getColor();
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(255, color.r, "device: hue 0 should be red");
    TEST_ASSERT_LESS_THAN_UINT8_MESSAGE(10, color.g, "device: green should be near zero for red hue");
    TEST_ASSERT_LESS_THAN_UINT8_MESSAGE(10, color.b, "device: blue should be near zero for red hue");
}

static void test_led_off(void) {
    GIVEN("the LED is set to white");
    LED.set(colors::White);

    WHEN("the LED is turned off");
    LED.off();
    Color color = LED.getColor();
    TEST_ASSERT_EACH_EQUAL_UINT8_MESSAGE(0, &color.r, 3,
        "device: LED must be black after off");
}

static void test_led_brightness(void) {
    WHEN("brightness is adjusted");
    LED.setBrightness(128);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(128, LED.getBrightness(),
        "device: brightness must match after set");
    LED.setBrightness(255);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(255, LED.getBrightness(),
        "device: brightness must restore to max");
}

static void test_led_fade_in(void) {
    WHEN("fadeIn is called with Gold");
    LED.setBrightness(config::led::BRIGHTNESS);
    LED.fadeIn(colors::Gold, 100);
    Color color = LED.getColor();
    TEST_ASSERT_GREATER_THAN_UINT8_MESSAGE(200, color.r, "device: red after fadeIn");
    TEST_ASSERT_GREATER_THAN_UINT8_MESSAGE(150, color.g, "device: green after fadeIn");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(config::led::BRIGHTNESS, LED.getBrightness(),
        "device: brightness must restore after fadeIn");
}

static void test_led_fade_out(void) {
    GIVEN("the LED is set to white");
    LED.set(colors::White);

    WHEN("fadeOut is called");
    LED.fadeOut(colors::White, 100);
    Color color = LED.getColor();
    TEST_ASSERT_EACH_EQUAL_UINT8_MESSAGE(0, &color.r, 3,
        "device: LED must be black after fadeOut");
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(config::led::BRIGHTNESS, LED.getBrightness(),
        "device: brightness must restore after fadeOut");
}

void programs::led::test(void) {
    MODULE("LED");
    RUN_TEST(test_led_init);
    RUN_TEST(test_led_set_named);
    RUN_TEST(test_led_set_rgb);
    RUN_TEST(test_led_set_hsv);
    RUN_TEST(test_led_off);
    RUN_TEST(test_led_brightness);
    RUN_TEST(test_led_fade_in);
    RUN_TEST(test_led_fade_out);
}

#endif
