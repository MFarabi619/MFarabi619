#pragma once

#include <stdint.h>

typedef void (*ButtonCallback)(uint8_t button_index);

namespace programs::buttons {

void initialize();
void service();

void onPress(ButtonCallback cb);
void onLongPress(ButtonCallback cb);

[[nodiscard]] bool isPressed(uint8_t index);

}
