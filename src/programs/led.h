#pragma once

#include <Adafruit_NeoPixel.h>
#include <ColorFormat.h>

class Led : public Adafruit_NeoPixel {
    using Adafruit_NeoPixel::Adafruit_NeoPixel;
public:
    bool init() noexcept;

    void set(const espRgbColor_t& c) noexcept {
        setPixelColor(0, Color(c.r, c.g, c.b));
        show();
    }

    void set(uint8_t r, uint8_t g, uint8_t b) noexcept {
        setPixelColor(0, Color(r, g, b));
        show();
    }

    void glow(uint32_t duration_ms) noexcept;
};

extern Led LED;
