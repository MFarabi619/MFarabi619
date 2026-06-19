#include <stdbool.h>
#include <stdint.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>

const struct device *zig_gpio_emul_device(void)
{
	return DEVICE_DT_GET(DT_NODELABEL(test_gpio));
}

bool zig_gpio_emul_device_is_ready(void)
{
	return device_is_ready(zig_gpio_emul_device());
}

/*
 * Bridges for inline gpio_pin_* APIs. The z_impl_* versions in
 * <zephyr/drivers/gpio.h> are all `static inline`, so Zig can't extern
 * them directly. These wrappers give Zig a stable symbol for each.
 */
int zig_gpio_pin_configure(const struct device *port, uint8_t pin, uint32_t flags)
{
	return gpio_pin_configure(port, pin, flags);
}

int zig_gpio_pin_set_raw(const struct device *port, uint8_t pin, int value)
{
	return gpio_pin_set_raw(port, pin, value);
}

int zig_gpio_pin_get_raw(const struct device *port, uint8_t pin)
{
	return gpio_pin_get_raw(port, pin);
}
