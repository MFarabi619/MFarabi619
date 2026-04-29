#include <zephyr/kernel.h>
#include <zephyr/data/json.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/fs/fs.h>
#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>
#include <zephyr/net/hostname.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/sys/reboot.h>
#include <zephyr/sys/sys_heap.h>
#include <zephyr/logging/log.h>
#include <hal/efuse_hal.h>
#include <sensors/channels.h>

LOG_MODULE_REGISTER(api_http, LOG_LEVEL_INF);

extern struct k_heap _system_heap;

extern const struct device *zr_sensor_get_wind_speed(void);
extern const struct device *zr_sensor_get_wind_direction(void);
extern const struct device *zr_sensor_get_rainfall(void);
extern const struct device *zr_sensor_get_soil_tier1(void);
extern const struct device *zr_sensor_get_soil_tier2(void);
extern const struct device *zr_sensor_get_soil_tier3(void);

static char response_buffer[4096];

static uint32_t get_heap_free(void)
{
	struct sys_memory_stats stats;

	if (sys_heap_runtime_stats_get(&_system_heap.heap, &stats) == 0) {
		return (uint32_t)stats.free_bytes;
	}

	return 0;
}

static const struct http_header json_headers[] = {
	{.name = "Content-Type", .value = "application/json"},
};

static float sensor_val_to_float(const struct sensor_value *val)
{
	return (float)val->val1 + (float)val->val2 / 1000000.0f;
}

static void set_json_response(struct http_response_ctx *response_ctx,
			      enum http_status status,
			      const uint8_t *body, size_t body_len)
{
	response_ctx->status = status;
	response_ctx->headers = json_headers;
	response_ctx->header_count = ARRAY_SIZE(json_headers);
	response_ctx->body = body;
	response_ctx->body_len = body_len;
	response_ctx->final_chunk = true;
}

static int json_respond(struct http_response_ctx *response_ctx,
			const struct json_obj_descr *descr, size_t descr_len,
			const void *data)
{
	int result = json_obj_encode_buf(descr, descr_len, data,
					 response_buffer, sizeof(response_buffer));

	if (result < 0) {
		LOG_ERR("JSON encode failed: %d", result);
		static const uint8_t error_response[] = "{\"error\":\"encode failed\"}";

		set_json_response(response_ctx, HTTP_500_INTERNAL_SERVER_ERROR,
				  error_response, sizeof(error_response) - 1);
		return 0;
	}

	set_json_response(response_ctx, HTTP_200_OK,
			  (const uint8_t *)response_buffer, strlen(response_buffer));
	return 0;
}

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

	struct net_in_addr *addr =
		net_if_ipv4_get_global_addr(iface, NET_ADDR_PREFERRED);

	if (addr) {
		net_addr_ntop(AF_INET, addr,
			      network->ipv4_address,
			      sizeof(network->ipv4_address));
	}
}

static void format_uptime(char *buffer, size_t size, uint32_t seconds)
{
	uint32_t days = seconds / 86400;
	uint32_t hours = (seconds % 86400) / 3600;
	uint32_t minutes = (seconds % 3600) / 60;

	snprintk(buffer, size, "%ud %uh %um", days, hours, minutes);
}

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
	envelope.data.device.chip_revision = efuse_hal_chip_revision();

	get_wifi_info(&envelope.data.network);

	uint32_t uptime_seconds = k_uptime_seconds();

	format_uptime(envelope.data.runtime.uptime,
		      sizeof(envelope.data.runtime.uptime), uptime_seconds);
	envelope.data.runtime.uptime_seconds = uptime_seconds;
	envelope.data.runtime.memory_heap_free = get_heap_free();

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

	return json_respond(response_ctx, envelope_descr,
			    ARRAY_SIZE(envelope_descr), &envelope);
}

struct cloudevent_data {
	uint32_t uptime_seconds;
	uint32_t memory_heap_free;
	int32_t wifi_rssi;
	char ipv4_address[16];
};

struct cloudevent {
	char id[32];
	const char *type;
	const char *time;
	struct cloudevent_data data;
};

struct cloudevent_list {
	struct cloudevent events[4];
	size_t events_len;
};

static const struct json_obj_descr cloudevent_data_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct cloudevent_data, uptime_seconds, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct cloudevent_data, memory_heap_free, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct cloudevent_data, wifi_rssi, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct cloudevent_data, ipv4_address, JSON_TOK_STRING_BUF),
};

static const struct json_obj_descr cloudevent_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct cloudevent, id, JSON_TOK_STRING_BUF),
	JSON_OBJ_DESCR_PRIM(struct cloudevent, type, JSON_TOK_STRING),
	JSON_OBJ_DESCR_PRIM(struct cloudevent, time, JSON_TOK_STRING),
	JSON_OBJ_DESCR_OBJECT(struct cloudevent, data, cloudevent_data_descr),
};

static const struct json_obj_descr cloudevent_array_descr[] = {
	JSON_OBJ_DESCR_OBJ_ARRAY(struct cloudevent_list, events, 4,
				  events_len, cloudevent_descr,
				  ARRAY_SIZE(cloudevent_descr)),
};

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

	struct cloudevent_list list = {0};

	list.events_len = 1;

	uint32_t uptime_seconds = k_uptime_seconds();

	snprintk(list.events[0].id, sizeof(list.events[0].id),
		 "status-%u-0", uptime_seconds);
	list.events[0].type = "status.v1";
	list.events[0].time = "";
	list.events[0].data.uptime_seconds = uptime_seconds;
	list.events[0].data.memory_heap_free = get_heap_free();

	struct device_network network = {0};

	get_wifi_info(&network);
	list.events[0].data.wifi_rssi = network.wifi_rssi;
	memcpy(list.events[0].data.ipv4_address, network.ipv4_address,
	       sizeof(network.ipv4_address));

	int result = json_arr_encode_buf(cloudevent_array_descr, &list,
					 response_buffer,
					 sizeof(response_buffer));

	if (result < 0) {
		LOG_ERR("CloudEvents JSON encode failed: %d", result);
		static const uint8_t error_response[] = "{\"error\":\"encode failed\"}";

		set_json_response(response_ctx, HTTP_500_INTERNAL_SERVER_ERROR,
				  error_response, sizeof(error_response) - 1);
		return 0;
	}

	set_json_response(response_ctx, HTTP_200_OK,
			  (const uint8_t *)response_buffer, strlen(response_buffer));
	return 0;
}

struct wind_speed_response {
	bool ok;
	float wind_speed_kilometers_per_hour;
};

static const struct json_obj_descr wind_speed_response_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct wind_speed_response, ok, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct wind_speed_response, wind_speed_kilometers_per_hour,
			     JSON_TOK_FLOAT_FP),
};

int wind_speed_handler(struct http_client_ctx *client,
		       enum http_transaction_status status,
		       const struct http_request_ctx *request_ctx,
		       struct http_response_ctx *response_ctx,
		       void *user_data)
{
	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	struct wind_speed_response response = {0};
	const struct device *dev = zr_sensor_get_wind_speed();

	if (dev && sensor_sample_fetch(dev) == 0) {
		struct sensor_value val;

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_WIND_SPEED, &val) == 0) {
			response.ok = true;
			response.wind_speed_kilometers_per_hour = sensor_val_to_float(&val);
		}
	}

	return json_respond(response_ctx, wind_speed_response_descr,
			    ARRAY_SIZE(wind_speed_response_descr), &response);
}

struct wind_direction_response {
	bool ok;
	float wind_direction_degrees;
	uint32_t wind_direction_angle_slice;
};

static const struct json_obj_descr wind_direction_response_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct wind_direction_response, ok, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct wind_direction_response, wind_direction_degrees,
			     JSON_TOK_FLOAT_FP),
	JSON_OBJ_DESCR_PRIM(struct wind_direction_response, wind_direction_angle_slice,
			     JSON_TOK_NUMBER),
};

int wind_direction_handler(struct http_client_ctx *client,
			   enum http_transaction_status status,
			   const struct http_request_ctx *request_ctx,
			   struct http_response_ctx *response_ctx,
			   void *user_data)
{
	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	struct wind_direction_response response = {0};
	const struct device *dev = zr_sensor_get_wind_direction();

	if (dev && sensor_sample_fetch(dev) == 0) {
		struct sensor_value val;

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_WIND_DIRECTION_DEGREES,
				       &val) == 0) {
			response.wind_direction_degrees = sensor_val_to_float(&val);
			response.ok = true;
		}

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_WIND_DIRECTION_SLICE,
				       &val) == 0) {
			response.wind_direction_angle_slice = (uint32_t)val.val1;
		}
	}

	return json_respond(response_ctx, wind_direction_response_descr,
			    ARRAY_SIZE(wind_direction_response_descr), &response);
}

struct rainfall_response {
	bool ok;
	float rainfall_millimeters;
};

static const struct json_obj_descr rainfall_response_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct rainfall_response, ok, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct rainfall_response, rainfall_millimeters, JSON_TOK_FLOAT_FP),
};

int rainfall_handler(struct http_client_ctx *client,
		     enum http_transaction_status status,
		     const struct http_request_ctx *request_ctx,
		     struct http_response_ctx *response_ctx,
		     void *user_data)
{
	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	struct rainfall_response response = {0};
	const struct device *dev = zr_sensor_get_rainfall();

	if (dev && sensor_sample_fetch(dev) == 0) {
		struct sensor_value val;

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_RAINFALL, &val) == 0) {
			response.ok = true;
			response.rainfall_millimeters = sensor_val_to_float(&val);
		}
	}

	return json_respond(response_ctx, rainfall_response_descr,
			    ARRAY_SIZE(rainfall_response_descr), &response);
}

#define MAX_SOIL_PROBES 10

struct soil_probe_reading {
	uint32_t slave_id;
	bool is_read_ok;
	float temperature_celsius;
	float moisture_percent;
	bool has_conductivity;
	uint32_t conductivity;
	bool has_salinity;
	uint32_t salinity;
	bool has_tds;
	uint32_t tds;
	bool has_ph;
	float ph;
};

static const struct json_obj_descr soil_probe_reading_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, slave_id, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, is_read_ok, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, temperature_celsius, JSON_TOK_FLOAT_FP),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, moisture_percent, JSON_TOK_FLOAT_FP),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, has_conductivity, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, conductivity, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, has_salinity, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, salinity, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, has_tds, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, tds, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, has_ph, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct soil_probe_reading, ph, JSON_TOK_FLOAT_FP),
};

struct soil_response {
	bool ok;
	uint32_t probe_count;
	struct soil_probe_reading probes[MAX_SOIL_PROBES];
	size_t probes_len;
};

static const struct json_obj_descr soil_response_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct soil_response, ok, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_PRIM(struct soil_response, probe_count, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_OBJ_ARRAY(struct soil_response, probes, MAX_SOIL_PROBES,
				  probes_len, soil_probe_reading_descr,
				  ARRAY_SIZE(soil_probe_reading_descr)),
};

static void read_soil_device(const struct device *dev, struct soil_response *response)
{
	if (!dev) {
		return;
	}

	struct sensor_value val;

	if (sensor_attr_get(dev, 0, SENSOR_ATTR_CERATINA_SCAN, &val) != 0) {
		return;
	}

	uint8_t count = (uint8_t)val.val1;

	for (uint8_t index = 0; index < count; index++) {
		if (response->probes_len >= MAX_SOIL_PROBES) {
			break;
		}

		val.val1 = index;
		val.val2 = 0;
		sensor_attr_set(dev, 0, SENSOR_ATTR_CERATINA_SLAVE_ID, &val);

		struct soil_probe_reading *probe = &response->probes[response->probes_len];

		if (sensor_sample_fetch(dev) != 0) {
			continue;
		}

		if (sensor_attr_get(dev, 0, SENSOR_ATTR_CERATINA_SLAVE_ID, &val) == 0) {
			probe->slave_id = (uint32_t)val.val1;
		}

		struct sensor_value reading;

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_SOIL_MOISTURE,
				       &reading) == 0) {
			probe->moisture_percent = sensor_val_to_float(&reading);
			probe->is_read_ok = true;
		}

		if (sensor_channel_get(dev, SENSOR_CHAN_AMBIENT_TEMP, &reading) == 0) {
			probe->temperature_celsius = sensor_val_to_float(&reading);
		}

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_SOIL_CONDUCTIVITY,
				       &reading) == 0) {
			probe->has_conductivity = true;
			probe->conductivity = (uint32_t)reading.val1;
		}

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_SOIL_SALINITY,
				       &reading) == 0) {
			probe->has_salinity = true;
			probe->salinity = (uint32_t)reading.val1;
		}

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_SOIL_TDS,
				       &reading) == 0) {
			probe->has_tds = true;
			probe->tds = (uint32_t)reading.val1;
		}

		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_SOIL_PH,
				       &reading) == 0) {
			probe->has_ph = true;
			probe->ph = sensor_val_to_float(&reading);
		}

		response->probes_len++;
	}
}

int soil_handler(struct http_client_ctx *client,
		 enum http_transaction_status status,
		 const struct http_request_ctx *request_ctx,
		 struct http_response_ctx *response_ctx,
		 void *user_data)
{
	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	struct soil_response response = {0};

	read_soil_device(zr_sensor_get_soil_tier1(), &response);
	read_soil_device(zr_sensor_get_soil_tier2(), &response);
	read_soil_device(zr_sensor_get_soil_tier3(), &response);

	response.probe_count = (uint32_t)response.probes_len;
	response.ok = response.probe_count > 0;

	return json_respond(response_ctx, soil_response_descr,
			    ARRAY_SIZE(soil_response_descr), &response);
}

#define FILESYSTEM_PREFIX "/api/filesystem/"
#define FILESYSTEM_PREFIX_LEN (sizeof(FILESYSTEM_PREFIX) - 1)

static int recursive_delete(const char *path)
{
	struct fs_dirent entry;
	int result = fs_stat(path, &entry);

	if (result < 0) {
		return result;
	}

	if (entry.type == FS_DIR_ENTRY_FILE) {
		return fs_unlink(path);
	}

	struct fs_dir_t dir;

	fs_dir_t_init(&dir);
	result = fs_opendir(&dir, path);
	if (result < 0) {
		return result;
	}

	char child[256];

	while (true) {
		result = fs_readdir(&dir, &entry);
		if (result < 0) {
			break;
		}

		if (entry.name[0] == '\0') {
			break;
		}

		snprintk(child, sizeof(child), "%s/%s", path, entry.name);
		result = recursive_delete(child);
		if (result < 0) {
			break;
		}
	}

	fs_closedir(&dir);

	if (result < 0) {
		return result;
	}

	return fs_unlink(path);
}

static int resolve_fs_path(const char *url, char *fs_path, size_t fs_path_size)
{
	if (strncmp(url, FILESYSTEM_PREFIX, FILESYSTEM_PREFIX_LEN) != 0) {
		return -EINVAL;
	}

	const char *relative = url + FILESYSTEM_PREFIX_LEN;

	if (strncmp(relative, "sd", 2) != 0) {
		return -EINVAL;
	}

	relative += 2;

	if (*relative == '\0' || (*relative == '/' && *(relative + 1) == '\0')) {
		snprintk(fs_path, fs_path_size, "/sd:");
	} else if (*relative == '/') {
		snprintk(fs_path, fs_path_size, "/sd:%s", relative);
	} else {
		return -EINVAL;
	}

	return 0;
}

#define MAX_DIR_ENTRIES 64

struct dir_entry_json {
	char name[64];
	uint32_t size;
	bool is_directory;
};

static const struct json_obj_descr dir_entry_json_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct dir_entry_json, name, JSON_TOK_STRING_BUF),
	JSON_OBJ_DESCR_PRIM(struct dir_entry_json, size, JSON_TOK_NUMBER),
	JSON_OBJ_DESCR_PRIM(struct dir_entry_json, is_directory, JSON_TOK_TRUE),
};

struct dir_listing_response {
	bool ok;
	struct dir_entry_json entries[MAX_DIR_ENTRIES];
	size_t entries_len;
};

static const struct json_obj_descr dir_listing_response_descr[] = {
	JSON_OBJ_DESCR_PRIM(struct dir_listing_response, ok, JSON_TOK_TRUE),
	JSON_OBJ_DESCR_OBJ_ARRAY(struct dir_listing_response, entries, MAX_DIR_ENTRIES,
				  entries_len, dir_entry_json_descr,
				  ARRAY_SIZE(dir_entry_json_descr)),
};

int filesystem_handler(struct http_client_ctx *client,
		       enum http_transaction_status status,
		       const struct http_request_ctx *request_ctx,
		       struct http_response_ctx *response_ctx,
		       void *user_data)
{
	static const uint8_t ok_response[] = "{\"ok\":true}";
	static const uint8_t bad_path[] = "{\"ok\":false,\"error\":\"invalid path\"}";
	static const uint8_t not_found[] = "{\"ok\":false,\"error\":\"not found\"}";

	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	char fs_path[256];

	if (resolve_fs_path(client->url_buffer, fs_path, sizeof(fs_path)) < 0) {
		set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
				  bad_path, sizeof(bad_path) - 1);
		return 0;
	}

	if (client->method == HTTP_POST) {
		int result = fs_mkdir(fs_path);

		if (result == -EEXIST) {
			set_json_response(response_ctx, HTTP_200_OK,
					  ok_response, sizeof(ok_response) - 1);
		} else if (result < 0) {
			static const uint8_t mkdir_err[] = "{\"ok\":false,\"error\":\"mkdir failed\"}";

			set_json_response(response_ctx, HTTP_500_INTERNAL_SERVER_ERROR,
					  mkdir_err, sizeof(mkdir_err) - 1);
		} else {
			set_json_response(response_ctx, HTTP_200_OK,
					  ok_response, sizeof(ok_response) - 1);
		}

		return 0;
	}

	if (client->method == HTTP_PATCH) {
		if (status != HTTP_SERVER_REQUEST_DATA_FINAL) {
			return 0;
		}

		if (request_ctx->data_len == 0 || request_ctx->data_len >= 256) {
			set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
					  bad_path, sizeof(bad_path) - 1);
			return 0;
		}

		char body[256];

		memcpy(body, request_ctx->data, request_ctx->data_len);
		body[request_ctx->data_len] = '\0';

		const char *name_key = strstr(body, "\"name\"");

		if (!name_key) {
			set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
					  bad_path, sizeof(bad_path) - 1);
			return 0;
		}

		const char *colon = strchr(name_key + 6, ':');

		if (!colon) {
			set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
					  bad_path, sizeof(bad_path) - 1);
			return 0;
		}

		const char *quote_start = strchr(colon + 1, '"');

		if (!quote_start) {
			set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
					  bad_path, sizeof(bad_path) - 1);
			return 0;
		}

		quote_start++;
		const char *quote_end = strchr(quote_start, '"');

		if (!quote_end || quote_end == quote_start) {
			set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
					  bad_path, sizeof(bad_path) - 1);
			return 0;
		}

		size_t name_len = quote_end - quote_start;
		char new_path[256];
		const char *last_slash = strrchr(fs_path, '/');

		if (last_slash && last_slash != fs_path) {
			size_t parent_len = last_slash - fs_path;

			if (parent_len + 1 + name_len >= sizeof(new_path)) {
				set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
						  bad_path, sizeof(bad_path) - 1);
				return 0;
			}

			memcpy(new_path, fs_path, parent_len);
			new_path[parent_len] = '/';
			memcpy(new_path + parent_len + 1, quote_start, name_len);
			new_path[parent_len + 1 + name_len] = '\0';
		} else {
			const char *colon_pos = strchr(fs_path, ':');

			if (colon_pos) {
				size_t prefix_len = colon_pos - fs_path + 2;

				if (prefix_len + name_len >= sizeof(new_path)) {
					set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
							  bad_path, sizeof(bad_path) - 1);
					return 0;
				}

				memcpy(new_path, fs_path, colon_pos - fs_path + 1);
				new_path[colon_pos - fs_path + 1] = '/';
				memcpy(new_path + prefix_len, quote_start, name_len);
				new_path[prefix_len + name_len] = '\0';
			} else {
				set_json_response(response_ctx, HTTP_400_BAD_REQUEST,
						  bad_path, sizeof(bad_path) - 1);
				return 0;
			}
		}

		int result = fs_rename(fs_path, new_path);

		if (result < 0) {
			static const uint8_t rename_err[] = "{\"ok\":false,\"error\":\"rename failed\"}";

			set_json_response(response_ctx, HTTP_500_INTERNAL_SERVER_ERROR,
					  rename_err, sizeof(rename_err) - 1);
		} else {
			set_json_response(response_ctx, HTTP_200_OK,
					  ok_response, sizeof(ok_response) - 1);
		}

		return 0;
	}

	if (client->method == HTTP_DELETE) {
		struct fs_dirent entry;
		int result = fs_stat(fs_path, &entry);

		if (result < 0) {
			set_json_response(response_ctx, HTTP_404_NOT_FOUND,
					  not_found, sizeof(not_found) - 1);
			return 0;
		}

		result = recursive_delete(fs_path);

		if (result < 0) {
			static const uint8_t delete_err[] = "{\"ok\":false,\"error\":\"delete failed\"}";

			set_json_response(response_ctx, HTTP_500_INTERNAL_SERVER_ERROR,
					  delete_err, sizeof(delete_err) - 1);
		} else {
			set_json_response(response_ctx, HTTP_200_OK,
					  ok_response, sizeof(ok_response) - 1);
		}

		return 0;
	}

	struct fs_dirent stat_entry;
	int result = fs_stat(fs_path, &stat_entry);

	if (result < 0 && strcmp(fs_path, "/sd:") != 0) {
		set_json_response(response_ctx, HTTP_404_NOT_FOUND,
				  not_found, sizeof(not_found) - 1);
		return 0;
	}

	struct fs_dir_t dir;

	fs_dir_t_init(&dir);
	result = fs_opendir(&dir, fs_path);
	if (result < 0) {
		set_json_response(response_ctx, HTTP_404_NOT_FOUND,
				  not_found, sizeof(not_found) - 1);
		return 0;
	}

	struct dir_listing_response response = {0};

	response.ok = true;

	struct fs_dirent entry;

	while (fs_readdir(&dir, &entry) == 0 && entry.name[0] != '\0') {
		if (response.entries_len >= MAX_DIR_ENTRIES) {
			break;
		}

		struct dir_entry_json *json_entry = &response.entries[response.entries_len];

		strncpy(json_entry->name, entry.name, sizeof(json_entry->name) - 1);
		json_entry->size = (uint32_t)entry.size;
		json_entry->is_directory = entry.type == FS_DIR_ENTRY_DIR;
		response.entries_len++;
	}

	fs_closedir(&dir);

	return json_respond(response_ctx, dir_listing_response_descr,
			    ARRAY_SIZE(dir_listing_response_descr), &response);
}

int reboot_handler(struct http_client_ctx *client,
		   enum http_transaction_status status,
		   const struct http_request_ctx *request_ctx,
		   struct http_response_ctx *response_ctx,
		   void *user_data)
{
	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	static const uint8_t response[] = "{\"ok\":true,\"action\":\"rebooting\"}";

	set_json_response(response_ctx, HTTP_200_OK,
			  response, sizeof(response) - 1);

	k_sleep(K_MSEC(500));
	sys_reboot(SYS_REBOOT_COLD);

	return 0;
}
