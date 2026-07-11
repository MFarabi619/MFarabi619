#include "motor.h"

#include <math.h>
#include <zephyr/device.h>
#include <zephyr/drivers/led_strip.h>
#include <zephyr/drivers/pwm.h>
#include <zephyr/kernel.h>

#define DT_DRV_COMPAT freenove_fnk0077

#define LED_PIXEL_COUNT 4
#define LED_WIPE_WAIT_MS 120

static const struct device *const led_strip =
    DEVICE_DT_GET(DT_NODELABEL(led_strip));

static const struct led_rgb LED_GREEN = {.r = 0, .g = 255, .b = 0};

static void led_color_wipe(struct led_rgb color) {
  struct led_rgb pixels[LED_PIXEL_COUNT] = {0};
  for (size_t pixel_index = 0; pixel_index < LED_PIXEL_COUNT; pixel_index++) {
    pixels[pixel_index] = color;
    led_strip_update_rgb(led_strip, pixels, LED_PIXEL_COUNT);
    k_sleep(K_MSEC(LED_WIPE_WAIT_MS));
  }
}

static const struct pwm_dt_spec left_forward =
    PWM_DT_SPEC_INST_GET_BY_NAME(0, left_forward);
static const struct pwm_dt_spec left_backward =
    PWM_DT_SPEC_INST_GET_BY_NAME(0, left_backward);
static const struct pwm_dt_spec right_forward =
    PWM_DT_SPEC_INST_GET_BY_NAME(0, right_forward);
static const struct pwm_dt_spec right_backward =
    PWM_DT_SPEC_INST_GET_BY_NAME(0, right_backward);

static void drive_wheel(const struct pwm_dt_spec *forward,
                        const struct pwm_dt_spec *backward, double speed) {
  uint32_t pulse = (uint32_t)(fabs(speed) * forward->period);
  if (speed >= 0.0) {
    pwm_set_pulse_dt(backward, 0);
    pwm_set_pulse_dt(forward, pulse);
  } else {
    pwm_set_pulse_dt(forward, 0);
    pwm_set_pulse_dt(backward, pulse);
  }
}

int motor_init(void) {
  if (device_is_ready(led_strip)) {
    led_color_wipe(LED_GREEN);
  }
  if (!pwm_is_ready_dt(&left_forward) || !pwm_is_ready_dt(&left_backward) ||
      !pwm_is_ready_dt(&right_forward) || !pwm_is_ready_dt(&right_backward)) {
    return -1;
  }
  motor_stop();
  return 0;
}

void motor_drive(double left, double right) {
  drive_wheel(&left_forward, &left_backward, left);
  drive_wheel(&right_forward, &right_backward, right);
}

void motor_stop(void) {
  pwm_set_pulse_dt(&left_forward, 0);
  pwm_set_pulse_dt(&left_backward, 0);
  pwm_set_pulse_dt(&right_forward, 0);
  pwm_set_pulse_dt(&right_backward, 0);
}
