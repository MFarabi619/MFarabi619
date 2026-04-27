#include <zephyr/fs/fs.h>
#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(filesystem_http, LOG_LEVEL_INF);

#define API_PREFIX "/api/filesystem/"
#define API_PREFIX_LEN (sizeof(API_PREFIX) - 1)

static struct fs_file_t upload_file;
static bool upload_file_is_open;

static int create_parent_directories(const char *path)
{
	char buffer[256];
	size_t length = strlen(path);

	if (length >= sizeof(buffer)) {
		return -ENAMETOOLONG;
	}

	memcpy(buffer, path, length + 1);

	const char *colon = strchr(path, ':');
	size_t start = colon ? (size_t)(colon - path) + 2 : 1;

	for (size_t index = start; index < length; index++) {
		if (buffer[index] == '/') {
			buffer[index] = '\0';
			int result = fs_mkdir(buffer);
			if (result < 0 && result != -EEXIST) {
				return result;
			}
			buffer[index] = '/';
		}
	}

	return 0;
}

int filesystem_upload_handler(struct http_client_ctx *client,
				     enum http_transaction_status status,
				     const struct http_request_ctx *request_ctx,
				     struct http_response_ctx *response_ctx,
				     void *user_data)
{
	static const uint8_t response_ok[] = "{\"ok\":true}";
	static const uint8_t response_err[] = "{\"ok\":false}";

	if (status == HTTP_SERVER_TRANSACTION_ABORTED) {
		if (upload_file_is_open) {
			fs_close(&upload_file);
			upload_file_is_open = false;
		}
		return 0;
	}

	if (status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	if (!upload_file_is_open) {
		const char *url = client->url_buffer;

		if (strncmp(url, API_PREFIX, API_PREFIX_LEN) != 0) {
			response_ctx->status = HTTP_400_BAD_REQUEST;
			response_ctx->body = response_err;
			response_ctx->body_len = sizeof(response_err) - 1;
			response_ctx->final_chunk = true;
			return 0;
		}

		const char *relative = url + API_PREFIX_LEN;

		if (strncmp(relative, "sd/", 3) != 0) {
			response_ctx->status = HTTP_400_BAD_REQUEST;
			response_ctx->body = response_err;
			response_ctx->body_len = sizeof(response_err) - 1;
			response_ctx->final_chunk = true;
			return 0;
		}

		char fs_path[256];
		int written = snprintf(fs_path, sizeof(fs_path), "/sd:/%s", relative + 3);
		if (written < 0 || written >= (int)sizeof(fs_path)) {
			response_ctx->status = HTTP_414_URI_TOO_LONG;
			response_ctx->body = response_err;
			response_ctx->body_len = sizeof(response_err) - 1;
			response_ctx->final_chunk = true;
			return 0;
		}

		int result = create_parent_directories(fs_path);
		if (result < 0) {
			LOG_ERR("mkdir failed for %s: %d", fs_path, result);
			response_ctx->status = HTTP_500_INTERNAL_SERVER_ERROR;
			response_ctx->body = response_err;
			response_ctx->body_len = sizeof(response_err) - 1;
			response_ctx->final_chunk = true;
			return 0;
		}

		fs_file_t_init(&upload_file);
		result = fs_open(&upload_file, fs_path, FS_O_WRITE | FS_O_CREATE | FS_O_TRUNC);
		if (result < 0) {
			LOG_ERR("open failed for %s: %d", fs_path, result);
			response_ctx->status = HTTP_500_INTERNAL_SERVER_ERROR;
			response_ctx->body = response_err;
			response_ctx->body_len = sizeof(response_err) - 1;
			response_ctx->final_chunk = true;
			return 0;
		}

		upload_file_is_open = true;
		LOG_INF("uploading %s", fs_path);
	}

	if (request_ctx->data_len > 0) {
		ssize_t written = fs_write(&upload_file, request_ctx->data, request_ctx->data_len);
		if (written < 0) {
			LOG_ERR("write failed: %d", (int)written);
			fs_close(&upload_file);
			upload_file_is_open = false;
			response_ctx->status = HTTP_500_INTERNAL_SERVER_ERROR;
			response_ctx->body = response_err;
			response_ctx->body_len = sizeof(response_err) - 1;
			response_ctx->final_chunk = true;
			return 0;
		}
	}

	if (status == HTTP_SERVER_REQUEST_DATA_FINAL) {
		fs_close(&upload_file);
		upload_file_is_open = false;
		response_ctx->status = HTTP_200_OK;
		response_ctx->body = response_ok;
		response_ctx->body_len = sizeof(response_ok) - 1;
		response_ctx->final_chunk = true;
	}

	return 0;
}
