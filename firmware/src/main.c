#include <programs/led.h>
#include <networking/wifi.h>
#include <console/prompt.h>

#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>
#include <zephyr/shell/shell_uart.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(main);

int main(void)
{
	led_init();
	wifi_init();

	const struct shell *sh = shell_backend_uart_get_ptr();
	prompt_init(sh);
	prompt_print_motd(sh, NULL);

	return 0;
}
