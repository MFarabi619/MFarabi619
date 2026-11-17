#include <math.h>

#include <zephyr/device.h>
#include <zephyr/drivers/led_strip.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "joystick.h"

#define DT_DRV_COMPAT joystick

LOG_MODULE_REGISTER(joystick_led, CONFIG_LOG_DEFAULT_LEVEL);

#define LED_STRIP_NODE DT_INST_PHANDLE(0, led_strip)
#define LED_BRIGHTNESS 32
#define LED_UPDATE_PERIOD_MILLISECONDS 20
#define HUE_SECTOR_COUNT 6
#define DEGREES_PER_TURN 360.0f
#define DEGREES_PER_RADIAN 57.2957795f
#define JOYSTICK_LED_THREAD_STACK_SIZE 1024
#define JOYSTICK_LED_THREAD_PRIORITY 7

static const struct device *const led_strip = DEVICE_DT_GET(LED_STRIP_NODE);

static struct led_rgb rgb_from_hsv(float hue_degrees, float saturation, uint8_t value)
{
	float sector = fmodf(hue_degrees, DEGREES_PER_TURN) / (DEGREES_PER_TURN / HUE_SECTOR_COUNT);
	float fraction = sector - floorf(sector);
	uint8_t lowest = value * (1.0f - saturation);
	uint8_t falling = value * (1.0f - saturation * fraction);
	uint8_t rising = value * (1.0f - saturation * (1.0f - fraction));

	switch ((int)sector) {
	case 0:
		return (struct led_rgb){.r = value, .g = rising, .b = lowest};
	case 1:
		return (struct led_rgb){.r = falling, .g = value, .b = lowest};
	case 2:
		return (struct led_rgb){.r = lowest, .g = value, .b = rising};
	case 3:
		return (struct led_rgb){.r = lowest, .g = falling, .b = value};
	case 4:
		return (struct led_rgb){.r = rising, .g = lowest, .b = value};
	default:
		return (struct led_rgb){.r = value, .g = lowest, .b = falling};
	}
}

static struct led_rgb rgb_from_stick(struct joystick_stick stick)
{
	if (!stick.is_commanding) {
		return (struct led_rgb){0};
	}
	float rightward_fraction = (float)stick.rightward / JOYSTICK_AXIS_FULL_SCALE;
	float forward_fraction = -(float)stick.backward / JOYSTICK_AXIS_FULL_SCALE;
	float clockwise_from_forward_degrees =
		atan2f(rightward_fraction, forward_fraction) * DEGREES_PER_RADIAN;
	float deflection = fminf(hypotf(rightward_fraction, forward_fraction), 1.0f);

	return rgb_from_hsv(clockwise_from_forward_degrees + DEGREES_PER_TURN, deflection,
			    LED_BRIGHTNESS);
}

static void joystick_led_thread(void)
{
	if (!device_is_ready(led_strip)) {
		LOG_ERR_DEVICE_NOT_READY(led_strip);
		return;
	}
	while (true) {
		struct led_rgb rgb = rgb_from_stick(joystick_read_stick());

		led_strip_update_rgb(led_strip, &rgb, 1);
		k_sleep(K_MSEC(LED_UPDATE_PERIOD_MILLISECONDS));
	}
}

K_THREAD_DEFINE(joystick_led, JOYSTICK_LED_THREAD_STACK_SIZE, joystick_led_thread, NULL, NULL,
		NULL, JOYSTICK_LED_THREAD_PRIORITY, 0, 0);
