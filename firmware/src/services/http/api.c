#include <zephyr/kernel.h>
#include <zephyr/data/json.h>
#include <zephyr/fs/fs.h>
#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>
#include <zephyr/net/hostname.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(api_http, LOG_LEVEL_INF);

static char response_buffer[2048];

struct device_identity {
	const char *chip_model;
	uint32_t chip_cores;
	uint32_t chip_revision;
};

struct device_network {
	char ipv4_address[16];
	int32_t wifi_rssi;
};

struct device_runtime {
	char uptime[32];
	uint32_t uptime_seconds;
	uint32_t memory_heap_free;
};

struct device_sleep {
	bool enabled;
	uint32_t default_duration_seconds;
};

struct device_storage {
	const char *location;
	uint64_t total_bytes;
	uint64_t used_bytes;
	uint64_t free_bytes;
};

struct device_status_data {
	struct device_identity device;
	struct device_network network;
	struct device_runtime runtime;
	struct device_sleep sleep;
	struct device_storage storage;
};

struct device_status_envelope {
	struct device_status_data data;
	char time[32];
};

static const struct json_obj_descr identity_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct device_identity, chip_model, JSON_TOK_STRING),
	JSON_OBJ_DESCR_PRIM(struct device_identity, chip_cores, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct device_identity, chip_revision, JSON_TOK_NUMBER),
};

static const struct json_obj_descr network_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct device_network, ipv4_address, JSON_TOK_STRING_BUF),
	JSON_OBJ_DESCR_PRIM(struct device_network, wifi_rssi, JSON_TOK_NUMBER),
};

static const struct json_obj_descr runtime_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct device_runtime, uptime, JSON_TOK_STRING_BUF),
	JSON_OBJ_DESCR_PRIM(struct device_runtime, uptime_seconds, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct device_runtime, memory_heap_free, JSON_TOK_NUMBER),
};

static const struct json_obj_descr sleep_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct device_sleep, enabled, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct device_sleep, default_duration_seconds, JSON_TOK_NUMBER),
};

static const struct json_obj_descr storage_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct device_storage, location, JSON_TOK_STRING),
	JSON_OBJ_DESCR_PRIM(struct device_storage, total_bytes, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct device_storage, used_bytes, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct device_storage, free_bytes, JSON_TOK_NUMBER),
};

static const struct json_obj_descr status_data_descr[] = {
	JSON_OBJ_DESCR_OBJECT(struct device_status_data, device, identity_descr),
	JSON_OBJ_DESCR_OBJECT(struct device_status_data, network, network_descr),
	JSON_OBJ_DESCR_OBJECT(struct device_status_data, runtime, runtime_descr),
	JSON_OBJ_DESCR_OBJECT(struct device_status_data, sleep, sleep_descr),
	JSON_OBJ_DESCR_OBJECT(struct device_status_data, storage, storage_descr),
};

static const struct json_obj_descr envelope_descr[] = {
	JSON_OBJ_DESCR_OBJECT(struct device_status_envelope, data, status_data_descr),
	JSON_OBJ_DESCR_PRIM(struct device_status_envelope, time, JSON_TOK_STRING_BUF),
};

static void get_wifi_info(struct device_network *network)
{
	struct net_if *iface = net_if_get_wifi_sta();

	if (!iface) {
		iface = net_if_get_default();
	}

	if (!iface) {
		return;
	}

	struct wifi_iface_status wifi_status = {0};
	int result = net_mgmt(NET_REQUEST_WIFI_IFACE_STATUS, iface,
			      &wifi_status, sizeof(wifi_status));

	if (result == 0) {
		network->wifi_rssi = wifi_status.rssi;
	}

	struct net_if_ipv4 *ipv4 = iface->config.ip.ipv4;

	if (ipv4) {
		net_addr_ntop(AF_INET, &ipv4->unicast[0].ipv4.address.in_addr,
			      network->ipv4_address, sizeof(network->ipv4_address));
	}
}

static void format_uptime(char *buffer, size_t size, uint32_t seconds)
{
	uint32_t days = seconds / 86400;
	uint32_t hours = (seconds % 86400) / 3600;
	uint32_t minutes = (seconds % 3600) / 60;

	snprintk(buffer, size, "%ud %uh %um", days, hours, minutes);
}

int device_status_handler(struct http_client_ctx *client,
			  enum http_transaction_status status,
			  const struct http_request_ctx *request_ctx,
			  struct http_response_ctx *response_ctx,
			  void *user_data)
{
	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	struct device_status_envelope envelope = {0};

	envelope.data.device.chip_model = "ESP32-S3";
	envelope.data.device.chip_cores = 2;
	envelope.data.device.chip_revision = 0;

	get_wifi_info(&envelope.data.network);

	uint32_t uptime_seconds = k_uptime_seconds();

	format_uptime(envelope.data.runtime.uptime,
		      sizeof(envelope.data.runtime.uptime), uptime_seconds);
	envelope.data.runtime.uptime_seconds = uptime_seconds;
	envelope.data.runtime.memory_heap_free = 0;

	envelope.data.sleep.enabled = false;
	envelope.data.sleep.default_duration_seconds = 0;

	envelope.data.storage.location = "sd";
	struct fs_statvfs stat;

	if (fs_statvfs("/sd:", &stat) == 0) {
		uint64_t frsize = stat.f_frsize;

		envelope.data.storage.total_bytes = frsize * stat.f_blocks;
		envelope.data.storage.free_bytes = frsize * stat.f_bfree;
		envelope.data.storage.used_bytes =
			envelope.data.storage.total_bytes -
			envelope.data.storage.free_bytes;
	}

	snprintk(envelope.time, sizeof(envelope.time), "");

	int result = json_obj_encode_buf(envelope_descr,
					 ARRAY_SIZE(envelope_descr),
					 &envelope, response_buffer,
					 sizeof(response_buffer));

	if (result < 0) {
		LOG_ERR("JSON encode failed: %d", result);
		static const uint8_t error_response[] = "{\"error\":\"encode failed\"}";

		response_ctx->status = HTTP_500_INTERNAL_SERVER_ERROR;
		response_ctx->body = error_response;
		response_ctx->body_len = sizeof(error_response) - 1;
		response_ctx->final_chunk = true;
		return 0;
	}

	response_ctx->status = HTTP_200_OK;
	response_ctx->body = (const uint8_t *)response_buffer;
	response_ctx->body_len = strlen(response_buffer);
	response_ctx->final_chunk = true;
	return 0;
}

int cloudevents_handler(struct http_client_ctx *client,
			enum http_transaction_status status,
			const struct http_request_ctx *request_ctx,
			struct http_response_ctx *response_ctx,
			void *user_data)
{
	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	uint32_t uptime_seconds = k_uptime_seconds();
	uint32_t memory_heap_free = 0;

	struct device_network network = {0};

	get_wifi_info(&network);

	int length = snprintk(response_buffer, sizeof(response_buffer),
		"[{\"id\":\"status-%u-0\","
		"\"type\":\"status.v1\","
		"\"time\":\"\","
		"\"data\":{"
		"\"uptime_seconds\":%u,"
		"\"memory_heap_free\":%u,"
		"\"wifi_rssi\":%d,"
		"\"ipv4_address\":\"%s\""
		"}}]",
		uptime_seconds,
		uptime_seconds,
		memory_heap_free,
		network.wifi_rssi,
		network.ipv4_address);

	if (length < 0 || length >= (int)sizeof(response_buffer)) {
		static const uint8_t error_response[] = "{\"error\":\"buffer overflow\"}";

		response_ctx->status = HTTP_500_INTERNAL_SERVER_ERROR;
		response_ctx->body = error_response;
		response_ctx->body_len = sizeof(error_response) - 1;
		response_ctx->final_chunk = true;
		return 0;
	}

	response_ctx->status = HTTP_200_OK;
	response_ctx->body = (const uint8_t *)response_buffer;
	response_ctx->body_len = length;
	response_ctx->final_chunk = true;
	return 0;
}
