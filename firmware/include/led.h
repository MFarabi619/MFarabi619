#pragma once

#include <stdint.h>

struct Color {
    uint8_t r, g, b;
};

namespace colors {
    constexpr Color Black       = {0, 0, 0};
    constexpr Color Red         = {255, 0, 0};
    constexpr Color Green       = {0, 128, 0};
    constexpr Color Blue        = {0, 0, 255};
    constexpr Color Yellow      = {255, 255, 0};
    constexpr Color Cyan        = {0, 255, 255};
    constexpr Color Magenta     = {255, 0, 255};
    constexpr Color White       = {255, 255, 255};
    constexpr Color Gold        = {255, 215, 0};
    constexpr Color DarkOrange  = {255, 140, 0};
    constexpr Color BlueViolet  = {138, 43, 226};
}

class Led {
public:
    bool init();
    void set(const Color &color);
    void set(uint8_t r, uint8_t g, uint8_t b);
    void setHSV(uint8_t hue, uint8_t saturation, uint8_t value);
    void off();
    void fadeIn(const Color &color, uint32_t duration_ms);
    void fadeOut(const Color &color, uint32_t duration_ms);
    void glow(uint32_t duration_ms);

    void setBrightness(uint8_t b);
    uint8_t getBrightness();
    Color getColor();
};

extern Led LED;

#ifdef PIO_UNIT_TESTING
namespace programs::led { void test(); }
#endif
