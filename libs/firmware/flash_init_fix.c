#include <zephyr/init.h>
#include <zephyr/sys/printk.h>

extern void esp_flash_app_init(void);
extern int esp_flash_init_default_chip(void);

static int esp32_flash_default_chip_init(void)
{
	esp_flash_app_init();
	int err = esp_flash_init_default_chip();
	printk("[flash_init_fix] esp_flash_init_default_chip = %d\n", err);
	return 0;
}

SYS_INIT(esp32_flash_default_chip_init, POST_KERNEL, 99);
