#pragma once

#include <stdint.h>

typedef void (*ButtonCallback)(uint8_t button_index);
typedef void (*IdleCallback)(void);

namespace programs::buttons {

void initialize();
void service();

// Event callbacks — each receives the button index (0..COUNT-1)
void onPress(ButtonCallback cb);
void onClick(ButtonCallback cb);
void onDoubleClick(ButtonCallback cb);
void onMultiClick(ButtonCallback cb);
void onLongPressStart(ButtonCallback cb);
void onLongPressStop(ButtonCallback cb);
void onDuringLongPress(ButtonCallback cb);
void onIdle(IdleCallback cb);

// Timing configuration — applied to all buttons
void setClickMs(unsigned int ms);
void setIdleMs(unsigned int ms);
void setLongPressIntervalMs(unsigned int ms);

// State queries
[[nodiscard]] bool isPressed(uint8_t index);
[[nodiscard]] bool isIdle(uint8_t index);
[[nodiscard]] bool isLongPressed(uint8_t index);
[[nodiscard]] unsigned long getPressedMs(uint8_t index);
[[nodiscard]] int getNumberClicks(uint8_t index);
void reset(uint8_t index);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
