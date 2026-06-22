#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(zephyr_lang_zig, LOG_LEVEL_DBG);

unsigned int zig_sem_count(struct k_sem *sem)
{
	return k_sem_count_get(sem);
}

uint32_t zig_cycle_get_32(void)
{
	return sys_clock_cycle_get_32();
}

uint32_t zig_cycle_hz(void)
{
	return sys_clock_hw_cycles_per_sec();
}

bool zig_gpio_is_ready_dt(const struct gpio_dt_spec *spec)
{
	return gpio_is_ready_dt(spec);
}

int zig_gpio_pin_configure_dt(const struct gpio_dt_spec *spec, gpio_flags_t flags)
{
	return gpio_pin_configure_dt(spec, flags);
}

int zig_gpio_pin_toggle_dt(const struct gpio_dt_spec *spec)
{
	return gpio_pin_toggle_dt(spec);
}

void zig_log_err(const char *msg)
{
	LOG_ERR("%s", msg);
}

void zig_log_warn(const char *msg)
{
	LOG_WRN("%s", msg);
}

void zig_log_info(const char *msg)
{
	LOG_INF("%s", msg);
}

void zig_log_debug(const char *msg)
{
	LOG_DBG("%s", msg);
}
