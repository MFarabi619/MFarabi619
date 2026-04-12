#include "led.h"
#include "../config.h"

#include <math.h>

Led LED(config::led::COUNT, config::led::GPIO, NEO_GRB + NEO_KHZ800);

bool Led::init() noexcept {
    bool ok = begin();
    setBrightness(config::led::BRIGHTNESS);
    clear();
    show();
    return ok;
}

void Led::glow(uint32_t duration_ms) noexcept {
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
