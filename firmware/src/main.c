#include <programs/led.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(main);

int main(void)
{
	if (!led_init()) {
		return 0;
	}

	while (1) {
		led_set(color_red);
		k_sleep(K_MSEC(500));
		led_set(color_green);
		k_sleep(K_MSEC(500));
		led_set(color_blue);
		k_sleep(K_MSEC(500));
	}

	return 0;
}
