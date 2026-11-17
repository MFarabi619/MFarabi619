#ifndef JOYSTICK_H_
#define JOYSTICK_H_

#include <stdbool.h>
#include <stdint.h>

#define JOYSTICK_AXIS_FULL_SCALE 32767
#define JOYSTICK_AXIS_COUNT 2
#define JOYSTICK_BUTTON_COUNT 8

struct joystick_stick {
	int32_t rightward;
	int32_t backward;
	bool is_commanding;
};

struct joystick_stick joystick_read_stick(void);
uint8_t joystick_read_buttons(void);

#endif /* JOYSTICK_H_ */
