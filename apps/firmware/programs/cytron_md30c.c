#include "motor.h"

#include <math.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/pwm.h>

#define DT_DRV_COMPAT cytron_md30c

static const struct pwm_dt_spec left_pwm = PWM_DT_SPEC_INST_GET_BY_NAME(0, left);
static const struct pwm_dt_spec right_pwm = PWM_DT_SPEC_INST_GET_BY_NAME(0, right);
static const struct gpio_dt_spec left_dir =
    GPIO_DT_SPEC_INST_GET_BY_IDX(0, dir_gpios, 0);
static const struct gpio_dt_spec right_dir =
    GPIO_DT_SPEC_INST_GET_BY_IDX(0, dir_gpios, 1);

static void drive_wheel(const struct pwm_dt_spec *pwm,
                        const struct gpio_dt_spec *dir, double speed) {
  gpio_pin_set_dt(dir, speed >= 0.0);
  pwm_set_pulse_dt(pwm, (uint32_t)(fabs(speed) * pwm->period));
}

int motor_init(void) {
  if (!pwm_is_ready_dt(&left_pwm) || !pwm_is_ready_dt(&right_pwm) ||
      !gpio_is_ready_dt(&left_dir) || !gpio_is_ready_dt(&right_dir)) {
    return -1;
  }
  gpio_pin_configure_dt(&left_dir, GPIO_OUTPUT_INACTIVE);
  gpio_pin_configure_dt(&right_dir, GPIO_OUTPUT_INACTIVE);
  motor_stop();
  return 0;
}

void motor_drive(double left, double right) {
  drive_wheel(&left_pwm, &left_dir, left);
  drive_wheel(&right_pwm, &right_dir, right);
}

void motor_stop(void) {
  pwm_set_pulse_dt(&left_pwm, 0);
  pwm_set_pulse_dt(&right_pwm, 0);
}
