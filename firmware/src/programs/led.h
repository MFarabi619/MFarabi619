#pragma once

#include <FastLED.h>

class Led {
    CRGB pixel[1];
public:
    bool init();
    void set(const CRGB &color);
    void set(uint8_t r, uint8_t g, uint8_t b);
    void setHSV(uint8_t hue, uint8_t saturation, uint8_t value);
    void off();
    void fadeIn(const CRGB &color, uint32_t duration_ms);
    void fadeOut(const CRGB &color, uint32_t duration_ms);
    void glow(uint32_t duration_ms);

    void setBrightness(uint8_t b);
    uint8_t getBrightness();
    CRGB getColor();
};

extern Led LED;

#ifdef PIO_UNIT_TESTING
namespace programs::led { void test(); }
#endif
