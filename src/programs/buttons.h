#pragma once

#include <stdint.h>

typedef void (*button_callback_t)(uint8_t button_index);

void buttons_init(void);
void buttons_service(void);

void buttons_on_press(button_callback_t cb);
void buttons_on_long_press(button_callback_t cb);

bool buttons_is_pressed(uint8_t index);
