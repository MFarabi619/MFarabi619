#include <programs/led.h>
#include <console/prompt.h>

#include <zephyr/kernel.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/shell/shell.h>
#include <zephyr/shell/shell_uart.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(main);

int main(void)
{
	led_init();

	net_mgmt(NET_REQUEST_WIFI_CONNECT_STORED, net_if_get_default(), NULL, 0);

	const struct shell *sh = shell_backend_uart_get_ptr();
	prompt_init(sh);
	prompt_print_motd(sh, NULL);

	return 0;
}
