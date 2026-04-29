#include <zephyr/shell/shell_websocket.h>

extern const struct http_service_desc provisioning_service;

DEFINE_WEBSOCKET_SERVICE(provisioning_service);

void websocket_shell_init(void)
{
	WEBSOCKET_CONSOLE_ENABLE(provisioning_service);
}
