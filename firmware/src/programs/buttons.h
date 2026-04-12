#pragma once

#include <stdint.h>

typedef void (*ButtonCallback)(uint8_t button_index);

namespace programs::buttons {

void initialize() noexcept;
void service() noexcept;

void onPress(ButtonCallback cb) noexcept;
void onLongPress(ButtonCallback cb) noexcept;

[[nodiscard]] bool isPressed(uint8_t index) noexcept;

}
