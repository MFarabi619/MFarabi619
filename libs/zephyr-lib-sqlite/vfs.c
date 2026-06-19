#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/fs/fs.h>
#include <zephyr/random/random.h>

#include <sqlite3.h>

#define VFS_NAME       "zephyr-fs"
#define MAX_PATH_BYTES 128

typedef struct {
	sqlite3_file base;
	struct fs_file_t handle;
} zephyr_sqlite_file;

static int file_close(sqlite3_file *p_file)
{
	zephyr_sqlite_file *file = (zephyr_sqlite_file *)p_file;
	int rc = fs_close(&file->handle);
	return (rc < 0) ? SQLITE_IOERR_CLOSE : SQLITE_OK;
}

static int file_read(sqlite3_file *p_file, void *buffer, int amount, sqlite3_int64 offset)
{
	zephyr_sqlite_file *file = (zephyr_sqlite_file *)p_file;

	if (fs_seek(&file->handle, (off_t)offset, FS_SEEK_SET) < 0) {
		return SQLITE_IOERR_READ;
	}

	ssize_t bytes_read = fs_read(&file->handle, buffer, amount);
	if (bytes_read < 0) {
		return SQLITE_IOERR_READ;
	}
	if (bytes_read < amount) {
		memset((uint8_t *)buffer + bytes_read, 0, amount - bytes_read);
		return SQLITE_IOERR_SHORT_READ;
	}
	return SQLITE_OK;
}

static int file_write(sqlite3_file *p_file, const void *buffer, int amount, sqlite3_int64 offset)
{
	zephyr_sqlite_file *file = (zephyr_sqlite_file *)p_file;

	if (fs_seek(&file->handle, (off_t)offset, FS_SEEK_SET) < 0) {
		return SQLITE_IOERR_WRITE;
	}

	ssize_t bytes_written = fs_write(&file->handle, buffer, amount);
	if (bytes_written < amount) {
		return SQLITE_IOERR_WRITE;
	}
	return SQLITE_OK;
}

static int file_truncate(sqlite3_file *p_file, sqlite3_int64 size)
{
	zephyr_sqlite_file *file = (zephyr_sqlite_file *)p_file;
	int rc = fs_truncate(&file->handle, (off_t)size);
	return (rc < 0) ? SQLITE_IOERR_TRUNCATE : SQLITE_OK;
}

static int file_sync(sqlite3_file *p_file, int flags)
{
	ARG_UNUSED(flags);
	zephyr_sqlite_file *file = (zephyr_sqlite_file *)p_file;
	int rc = fs_sync(&file->handle);
	return (rc < 0) ? SQLITE_IOERR_FSYNC : SQLITE_OK;
}

static int file_size(sqlite3_file *p_file, sqlite3_int64 *p_size)
{
	zephyr_sqlite_file *file = (zephyr_sqlite_file *)p_file;

	off_t current = fs_tell(&file->handle);
	if (current < 0) {
		return SQLITE_IOERR_FSTAT;
	}
	if (fs_seek(&file->handle, 0, FS_SEEK_END) < 0) {
		return SQLITE_IOERR_FSTAT;
	}

	off_t end = fs_tell(&file->handle);
	if (end < 0) {
		return SQLITE_IOERR_FSTAT;
	}

	if (fs_seek(&file->handle, current, FS_SEEK_SET) < 0) {
		return SQLITE_IOERR_FSTAT;
	}

	*p_size = (sqlite3_int64)end;
	return SQLITE_OK;
}

static int file_lock(sqlite3_file *p_file, int lock_type)
{
	ARG_UNUSED(p_file);
	ARG_UNUSED(lock_type);
	return SQLITE_OK;
}

static int file_unlock(sqlite3_file *p_file, int lock_type)
{
	ARG_UNUSED(p_file);
	ARG_UNUSED(lock_type);
	return SQLITE_OK;
}

static int file_check_reserved_lock(sqlite3_file *p_file, int *p_result)
{
	ARG_UNUSED(p_file);
	*p_result = 0;
	return SQLITE_OK;
}

static int file_control(sqlite3_file *p_file, int op, void *argument)
{
	ARG_UNUSED(p_file);
	ARG_UNUSED(op);
	ARG_UNUSED(argument);
	return SQLITE_NOTFOUND;
}

static int file_sector_size(sqlite3_file *p_file)
{
	ARG_UNUSED(p_file);
	return 512;
}

static int file_device_characteristics(sqlite3_file *p_file)
{
	ARG_UNUSED(p_file);
	return 0;
}

static const sqlite3_io_methods io_methods = {
	.iVersion = 1,
	.xClose = file_close,
	.xRead = file_read,
	.xWrite = file_write,
	.xTruncate = file_truncate,
	.xSync = file_sync,
	.xFileSize = file_size,
	.xLock = file_lock,
	.xUnlock = file_unlock,
	.xCheckReservedLock = file_check_reserved_lock,
	.xFileControl = file_control,
	.xSectorSize = file_sector_size,
	.xDeviceCharacteristics = file_device_characteristics,
};

static int vfs_open(sqlite3_vfs *p_vfs, const char *name, sqlite3_file *p_file,
		    int flags, int *p_out_flags)
{
	ARG_UNUSED(p_vfs);

	zephyr_sqlite_file *file = (zephyr_sqlite_file *)p_file;
	memset(file, 0, sizeof(*file));
	fs_file_t_init(&file->handle);

	fs_mode_t mode = 0;
	if (flags & SQLITE_OPEN_READWRITE) {
		mode |= FS_O_RDWR;
	} else if (flags & SQLITE_OPEN_READONLY) {
		mode |= FS_O_READ;
	}
	if (flags & SQLITE_OPEN_CREATE) {
		mode |= FS_O_CREATE;
	}

	int rc = fs_open(&file->handle, name, mode);
	if (rc < 0) {
		return SQLITE_CANTOPEN;
	}

	file->base.pMethods = &io_methods;
	if (p_out_flags) {
		*p_out_flags = flags;
	}
	return SQLITE_OK;
}

static int vfs_delete(sqlite3_vfs *p_vfs, const char *name, int sync_directory)
{
	ARG_UNUSED(p_vfs);
	ARG_UNUSED(sync_directory);

	int rc = fs_unlink(name);
	if (rc < 0 && rc != -ENOENT) {
		return SQLITE_IOERR_DELETE;
	}
	return SQLITE_OK;
}

static int vfs_access(sqlite3_vfs *p_vfs, const char *name, int flags, int *p_result)
{
	ARG_UNUSED(p_vfs);
	ARG_UNUSED(flags);

	struct fs_dirent entry;
	int rc = fs_stat(name, &entry);
	*p_result = (rc == 0);
	return SQLITE_OK;
}

static int vfs_full_pathname(sqlite3_vfs *p_vfs, const char *name, int n_out, char *out)
{
	ARG_UNUSED(p_vfs);
	strncpy(out, name, n_out);
	out[n_out - 1] = '\0';
	return SQLITE_OK;
}

static int vfs_randomness(sqlite3_vfs *p_vfs, int n_byte, char *out)
{
	ARG_UNUSED(p_vfs);
	sys_rand_get(out, n_byte);
	return n_byte;
}

static int vfs_sleep(sqlite3_vfs *p_vfs, int microseconds)
{
	ARG_UNUSED(p_vfs);
	k_sleep(K_USEC(microseconds));
	return microseconds;
}

static int vfs_current_time(sqlite3_vfs *p_vfs, double *p_out)
{
	ARG_UNUSED(p_vfs);
	*p_out = 2440587.5 + (double)k_uptime_get() / 86400000.0;
	return SQLITE_OK;
}

static int vfs_get_last_error(sqlite3_vfs *p_vfs, int n_buf, char *out)
{
	ARG_UNUSED(p_vfs);
	ARG_UNUSED(n_buf);
	ARG_UNUSED(out);
	return 0;
}

static sqlite3_vfs zephyr_vfs = {
	.iVersion = 1,
	.szOsFile = sizeof(zephyr_sqlite_file),
	.mxPathname = MAX_PATH_BYTES,
	.pNext = NULL,
	.zName = VFS_NAME,
	.pAppData = NULL,
	.xOpen = vfs_open,
	.xDelete = vfs_delete,
	.xAccess = vfs_access,
	.xFullPathname = vfs_full_pathname,
	.xDlOpen = NULL,
	.xDlError = NULL,
	.xDlSym = NULL,
	.xDlClose = NULL,
	.xRandomness = vfs_randomness,
	.xSleep = vfs_sleep,
	.xCurrentTime = vfs_current_time,
	.xGetLastError = vfs_get_last_error,
};

int sqlite_vfs_register(int make_default)
{
	return sqlite3_vfs_register(&zephyr_vfs, make_default);
}

int sqlite3_os_init(void)
{
	return sqlite_vfs_register(1);
}

int sqlite3_os_end(void)
{
	return SQLITE_OK;
}
