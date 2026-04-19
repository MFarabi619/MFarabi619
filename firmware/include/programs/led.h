#ifndef PROGRAMS_LED_H
#define PROGRAMS_LED_H

#include <stdint.h>
#include <stdbool.h>

struct color {
	uint8_t r, g, b;
};

static const struct color color_black       = {0, 0, 0};
static const struct color color_red         = {255, 0, 0};
static const struct color color_green       = {0, 128, 0};
static const struct color color_blue        = {0, 0, 255};
static const struct color color_yellow      = {255, 255, 0};
static const struct color color_cyan        = {0, 255, 255};
static const struct color color_magenta     = {255, 0, 255};
static const struct color color_white       = {255, 255, 255};
static const struct color color_gold        = {255, 215, 0};
static const struct color color_dark_orange = {255, 140, 0};
static const struct color color_blue_violet = {138, 43, 226};

bool led_init(void);
int  led_set(struct color c);
int  led_set_rgb(uint8_t r, uint8_t g, uint8_t b);
int  led_off(void);
struct color led_get_color(void);

#endif /* PROGRAMS_LED_H */
