#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/led_strip.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(zephyr_lang_zig, LOG_LEVEL_DBG);

bool bridge_gpio_is_ready_dt(const struct gpio_dt_spec *spec)
{
	return gpio_is_ready_dt(spec);
}

int bridge_gpio_pin_configure_dt(const struct gpio_dt_spec *spec, gpio_flags_t flags)
{
	return gpio_pin_configure_dt(spec, flags);
}

int bridge_gpio_pin_toggle_dt(const struct gpio_dt_spec *spec)
{
	return gpio_pin_toggle_dt(spec);
}

int bridge_led_strip_update_rgb(const struct device *dev, struct led_rgb *pixels, size_t num_pixels)
{
	return led_strip_update_rgb(dev, pixels, num_pixels);
}

void log_err(const char *msg)
{
	LOG_ERR("%s", msg);
}

void log_warn(const char *msg)
{
	LOG_WRN("%s", msg);
}

void log_info(const char *msg)
{
	LOG_INF("%s", msg);
}

void log_debug(const char *msg)
{
	LOG_DBG("%s", msg);
}
