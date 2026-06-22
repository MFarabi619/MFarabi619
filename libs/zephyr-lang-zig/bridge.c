#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(zephyr_lang_zig, LOG_LEVEL_DBG);

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
