#include <stdint.h>

#include <zephyr/device.h>
#include <zephyr/drivers/uart.h>

static const struct device *const console_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));

int zig_uart_poll_in(uint8_t *c) {
	unsigned char ch;
	int ret = uart_poll_in(console_dev, &ch);
	if (ret == 0) {
		*c = ch;
	}
	return ret;
}
