#include <zephyr/device.h>
#include <zephyr/drivers/auxdisplay.h>
#include <zephyr/init.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(lcd, CONFIG_LOG_DEFAULT_LEVEL);

static int lcd_show_banner(void)
{
	const struct device *const lcd = DEVICE_DT_GET_ANY(hit_hd44780);

	if (!device_is_ready(lcd)) {
		LOG_ERR("hd44780 not ready");
		return -ENODEV;
	}

	auxdisplay_backlight_set(lcd, 1);
	auxdisplay_clear(lcd);

	static const char line_top[] = "hello world";
	auxdisplay_write(lcd, line_top, sizeof(line_top) - 1);

	auxdisplay_cursor_position_set(lcd, AUXDISPLAY_POSITION_ABSOLUTE, 0, 1);
	static const char line_bottom[] = CONFIG_BOARD;
	auxdisplay_write(lcd, line_bottom, sizeof(line_bottom) - 1);

	return 0;
}

SYS_INIT(lcd_show_banner, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
