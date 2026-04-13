#include "led.h"
#include "../config.h"

#include <math.h>

Led LED(config::led::COUNT, config::led::GPIO, NEO_GRB + NEO_KHZ800);

bool Led::init() {
    bool ok = begin();
    setBrightness(config::led::BRIGHTNESS);
    clear();
    show();
    return ok;
}

void Led::glow(uint32_t duration_ms) {
    uint32_t start = millis();
    uint8_t saved = getBrightness();
    while (millis() - start < duration_ms) {
        float t = (float)((millis() - start) % 2000) / 2000.0f;
        float val = (sinf(t * 2.0f * 3.14159f - 1.5708f) + 1.0f) / 2.0f;
        uint8_t brightness = (uint8_t)(val * 200.0f) + 10;
        setBrightness(brightness);
        setPixelColor(0, Color(128, 0, 255));
        show();
        delay(20);
    }
    setBrightness(saved);
}

void Led::fadeIn(uint8_t r, uint8_t g, uint8_t b, uint32_t duration_ms) {
    uint8_t target = getBrightness();
    uint32_t start = millis();
    while (millis() - start < duration_ms) {
        float t = (float)(millis() - start) / (float)duration_ms;
        setBrightness((uint8_t)(t * target));
        setPixelColor(0, Color(r, g, b));
        show();
        delay(20);
    }
    setBrightness(target);
    setPixelColor(0, Color(r, g, b));
    show();
}

void Led::fadeOut(uint8_t r, uint8_t g, uint8_t b, uint32_t duration_ms) {
    uint8_t saved = getBrightness();
    uint32_t start = millis();
    while (millis() - start < duration_ms) {
        float t = 1.0f - (float)(millis() - start) / (float)duration_ms;
        setBrightness((uint8_t)(t * saved));
        setPixelColor(0, Color(r, g, b));
        show();
        delay(20);
    }
    clear();
    show();
    setBrightness(saved);
}
