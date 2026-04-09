#ifndef DRIVERS_NEOPIXEL_H
#define DRIVERS_NEOPIXEL_H

#include <stdint.h>

void neopixel_init(void);

// Status indicators
void neopixel_off(void);
void neopixel_red(void);
void neopixel_green(void);
void neopixel_blue(void);
void neopixel_yellow(void);
void neopixel_magenta(void);
void neopixel_cyan(void);
void neopixel_white(void);

// Custom color
void neopixel_rgb(uint8_t r, uint8_t g, uint8_t b);
void neopixel_hsv(uint16_t hue, uint8_t sat, uint8_t val);
void neopixel_brightness(uint8_t level);

// Read back
uint32_t neopixel_get_color(void);
uint8_t neopixel_get_brightness(void);

#ifdef PIO_UNIT_TESTING
void neopixel_run_tests(void);
#endif

#endif // DRIVERS_NEOPIXEL_H
