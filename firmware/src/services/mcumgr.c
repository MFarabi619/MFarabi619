#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <zephyr/logging/log.h>
#include <zephyr/mgmt/mcumgr/mgmt/callbacks.h>
#include <zephyr/mgmt/mcumgr/grp/fs_mgmt/fs_mgmt_callbacks.h>

LOG_MODULE_REGISTER(mcumgr_service, LOG_LEVEL_INF);

#define ALLOWED_PATH_PREFIX "/sd:/public/"

static enum mgmt_cb_return fs_access_hook(uint32_t event,
					   enum mgmt_cb_return previous_status,
					   int32_t *return_code,
					   uint16_t *group,
					   bool *abort_more,
					   void *data,
					   size_t data_size)
{
	if (event != MGMT_EVT_OP_FS_MGMT_FILE_ACCESS ||
	    previous_status != MGMT_CB_OK) {
		return MGMT_CB_OK;
	}

	struct fs_mgmt_file_access *access = data;

	if (strncmp(access->filename, ALLOWED_PATH_PREFIX,
		    sizeof(ALLOWED_PATH_PREFIX) - 1) != 0 ||
	    strstr(access->filename, "/..") != NULL) {
		LOG_WRN("MCUmgr fs access denied: %s", access->filename);
		*abort_more = true;
		*return_code = MGMT_ERR_EACCESSDENIED;
		return MGMT_CB_ERROR_RC;
	}

	return MGMT_CB_OK;
}

static struct mgmt_callback fs_access_callback = {
	.callback = fs_access_hook,
	.event_id = MGMT_EVT_OP_FS_MGMT_FILE_ACCESS,
};

static int mcumgr_service_init(void)
{
	mgmt_callback_register(&fs_access_callback);
	LOG_INF("MCUmgr fs_mgmt access hook registered (scope: %s)",
		ALLOWED_PATH_PREFIX);
	return 0;
}

SYS_INIT(mcumgr_service_init, APPLICATION, 90);
