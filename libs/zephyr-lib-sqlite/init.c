#include <zephyr/init.h>
#include <zephyr/sys/printk.h>

#include <sqlite3.h>

static int sqlite_init(void)
{
	int rc = sqlite3_initialize();
	printk("SQLite %s (init rc=%d)\n", sqlite3_libversion(), rc);
	return rc == SQLITE_OK ? 0 : -1;
}

SYS_INIT(sqlite_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
