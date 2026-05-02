#include <zephyr/kernel.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>
#include <zephyr/net/prometheus/collector.h>
#include <zephyr/net/prometheus/counter.h>
#include <zephyr/net/prometheus/gauge.h>
#include <zephyr/net/prometheus/formatter.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/sys/sys_heap.h>
#include <sensors/channels.h>

/* Stubs for the FFI surface used by publish.rs / diagnostics.rs while the
 * Prometheus collector below is parked. Restore by removing the #if 0/#endif. */
static uint32_t publish_failures_count;

void prometheus_increment_publish_failures(void)
{
	publish_failures_count++;
}

uint32_t prometheus_get_publish_failures(void)
{
	return publish_failures_count;
}

#if 0
extern struct k_heap _system_heap;

extern const struct device *zr_sensor_get_wind_speed(void);
extern const struct device *zr_sensor_get_wind_direction(void);
extern const struct device *zr_sensor_get_rainfall(void);
extern const struct device *zr_sensor_get_soil_moisture(void);
extern const struct device *zr_sensor_get_soil_moisture_three_in_one(void);

extern void mqtt_helper_get_mac(uint8_t *out);
extern void mqtt_helper_get_ipv4(char *out, size_t out_size);
extern uint32_t mqtt_helper_get_chip_revision(void);

#define CERATINA_FIRMWARE_VERSION "0.1.0"

PROMETHEUS_COLLECTOR_DEFINE(ceratina_collector);

PROMETHEUS_GAUGE_DEFINE(ceratina_uptime_seconds,
			"System uptime in seconds",
			({ .key = "class", .value = "system" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_heap_free_bytes,
			"Free heap memory in bytes",
			({ .key = "class", .value = "system" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_wifi_rssi,
			"WiFi signal strength in dBm",
			({ .key = "class", .value = "system" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_wind_speed_kilometers_per_hour,
			"Wind speed in km/h",
			({ .key = "sensor", .value = "wind_speed" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_wind_direction_degrees,
			"Wind direction in degrees",
			({ .key = "sensor", .value = "wind_direction" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_rainfall_millimeters,
			"Cumulative rainfall in mm",
			({ .key = "sensor", .value = "rainfall" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_moisture_percent,
			"Soil moisture percentage",
			({ .key = "probe", .value = "soil_moisture" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_temperature_celsius,
			"Soil temperature celsius",
			({ .key = "probe", .value = "soil_moisture" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_moisture_three_in_one_percent,
			"Soil moisture percentage (three-in-one probe)",
			({ .key = "probe", .value = "soil_moisture_three_in_one" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_three_in_one_temperature_celsius,
			"Soil temperature celsius (three-in-one probe)",
			({ .key = "probe", .value = "soil_moisture_three_in_one" }), NULL);

PROMETHEUS_COUNTER_DEFINE(ceratina_mqtt_publish_failures_total,
			  "Total MQTT publish failures since boot",
			  ({ .key = "class", .value = "mqtt" }), NULL);

void prometheus_increment_publish_failures(void)
{
	prometheus_counter_inc(&ceratina_mqtt_publish_failures_total);
}

uint32_t prometheus_get_publish_failures(void)
{
	return (uint32_t)ceratina_mqtt_publish_failures_total.value;
}

static float sensor_val_to_float(const struct sensor_value *val)
{
	return (float)val->val1 + (float)val->val2 / 1000000.0f;
}

static void update_system_gauges(void)
{
	prometheus_gauge_set(&ceratina_uptime_seconds, (double)k_uptime_seconds());

	struct sys_memory_stats stats;

	if (sys_heap_runtime_stats_get(&_system_heap.heap, &stats) == 0) {
		prometheus_gauge_set(&ceratina_heap_free_bytes, (double)stats.free_bytes);
	}

	struct net_if *iface = net_if_get_wifi_sta();

	if (!iface) {
		iface = net_if_get_default();
	}

	if (iface) {
		struct wifi_iface_status wifi_status = {0};

		if (net_mgmt(NET_REQUEST_WIFI_IFACE_STATUS, iface,
			     &wifi_status, sizeof(wifi_status)) == 0) {
			ceratina_wifi_rssi.value = (double)wifi_status.rssi;
		}
	}
}

static void update_weather_gauges(void)
{
	const struct device *dev;
	struct sensor_value val;

	dev = zr_sensor_get_wind_speed();
	if (dev && sensor_sample_fetch(dev) == 0) {
		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_WIND_SPEED, &val) == 0) {
			prometheus_gauge_set(&ceratina_wind_speed_kilometers_per_hour,
					     (double)sensor_val_to_float(&val));
		}
	}

	dev = zr_sensor_get_wind_direction();
	if (dev && sensor_sample_fetch(dev) == 0) {
		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_WIND_DIRECTION_DEGREES,
				       &val) == 0) {
			prometheus_gauge_set(&ceratina_wind_direction_degrees,
					     (double)sensor_val_to_float(&val));
		}
	}

	dev = zr_sensor_get_rainfall();
	if (dev && sensor_sample_fetch(dev) == 0) {
		if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_RAINFALL, &val) == 0) {
			prometheus_gauge_set(&ceratina_rainfall_millimeters,
					     (double)sensor_val_to_float(&val));
		}
	}
}

static void update_soil_probe(const struct device *device,
			      struct prometheus_gauge *moisture_gauge,
			      struct prometheus_gauge *temperature_gauge)
{
	if (!device) {
		return;
	}

	if (sensor_sample_fetch(device) != 0) {
		return;
	}

	struct sensor_value reading;

	if (sensor_channel_get(device, SENSOR_CHAN_CERATINA_SOIL_MOISTURE, &reading) == 0) {
		prometheus_gauge_set(moisture_gauge, (double)sensor_val_to_float(&reading));
	}

	if (sensor_channel_get(device, SENSOR_CHAN_AMBIENT_TEMP, &reading) == 0) {
		prometheus_gauge_set(temperature_gauge, (double)sensor_val_to_float(&reading));
	}
}

static void update_soil_gauges(void)
{
	update_soil_probe(zr_sensor_get_soil_moisture(),
			  &ceratina_soil_moisture_percent,
			  &ceratina_soil_temperature_celsius);
	update_soil_probe(zr_sensor_get_soil_moisture_three_in_one(),
			  &ceratina_soil_moisture_three_in_one_percent,
			  &ceratina_soil_three_in_one_temperature_celsius);
}

static bool is_registered;

static void register_metrics(void)
{
	if (is_registered) {
		return;
	}

	prometheus_collector_register_metric(&ceratina_collector, &ceratina_uptime_seconds.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_heap_free_bytes.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_wifi_rssi.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_wind_speed_kilometers_per_hour.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_wind_direction_degrees.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_rainfall_millimeters.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_moisture_percent.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_temperature_celsius.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_moisture_three_in_one_percent.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_three_in_one_temperature_celsius.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_mqtt_publish_failures_total.base);

	is_registered = true;
}

static char metrics_buffer[4096];

static size_t append_device_info(char *buffer, size_t buffer_size, size_t used)
{
	uint8_t mac[6] = {0};
	char ip[16] = {0};

	mqtt_helper_get_mac(mac);
	mqtt_helper_get_ipv4(ip, sizeof(ip));

	int written = snprintk(buffer + used, buffer_size - used,
		"# HELP ceratina_device_info Device metadata\n"
		"# TYPE ceratina_device_info gauge\n"
		"ceratina_device_info{firmware=\"%s\",hardware=\"rev%u\","
		"mac=\"%02x%02x%02x%02x%02x%02x\",ip=\"%s\"} 1\n",
		CERATINA_FIRMWARE_VERSION,
		mqtt_helper_get_chip_revision(),
		mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
		ip);

	if (written > 0 && (size_t)written < buffer_size - used) {
		return used + written;
	}
	return used;
}

int metrics_handler(struct http_client_ctx *client,
		    enum http_transaction_status status,
		    const struct http_request_ctx *request_ctx,
		    struct http_response_ctx *response_ctx,
		    void *user_data)
{
	if (status == HTTP_SERVER_TRANSACTION_ABORTED ||
	    status == HTTP_SERVER_TRANSACTION_COMPLETE) {
		return 0;
	}

	register_metrics();

	update_system_gauges();
	update_weather_gauges();
	update_soil_gauges();

	memset(metrics_buffer, 0, sizeof(metrics_buffer));

	int result = prometheus_format_exposition(&ceratina_collector,
						  metrics_buffer,
						  sizeof(metrics_buffer));
	if (result < 0) {
		static const uint8_t error_response[] = "# error formatting metrics\n";

		response_ctx->body = error_response;
		response_ctx->body_len = sizeof(error_response) - 1;
		response_ctx->final_chunk = true;
		return 0;
	}

	size_t used = strlen(metrics_buffer);
	used = append_device_info(metrics_buffer, sizeof(metrics_buffer), used);

	static const struct http_header plaintext_headers[] = {
		{.name = "Content-Type", .value = "text/plain; charset=utf-8"},
	};

	response_ctx->status = HTTP_200_OK;
	response_ctx->headers = plaintext_headers;
	response_ctx->header_count = ARRAY_SIZE(plaintext_headers);
	response_ctx->body = (const uint8_t *)metrics_buffer;
	response_ctx->body_len = used;
	response_ctx->final_chunk = true;

	return 0;
}
#endif
