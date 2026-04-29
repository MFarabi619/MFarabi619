#include <zephyr/fs/fs.h>
#include <ff.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(sdcard, LOG_LEVEL_INF);

static FATFS fat_fs;

static struct fs_mount_t sdcard_mount = {
	.type = FS_FATFS,
	.fs_data = &fat_fs,
	.storage_dev = (void *)"sd",
	.mnt_point = "/sd:",
	.flags = FS_MOUNT_FLAG_USE_DISK_ACCESS,
};

static bool is_mounted;

int sdcard_mount_filesystem(void)
{
	int result = fs_mount(&sdcard_mount);
	if (result < 0) {
		LOG_ERR("mount failed: %d", result);
	} else {
		LOG_INF("mounted at /sd:");
		is_mounted = true;
	}
	return result;
}

bool sdcard_is_mounted(void)
{
	return is_mounted;
}
