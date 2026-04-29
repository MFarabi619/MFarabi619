#include <zephyr/kernel.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>
#include <zephyr/net/prometheus/collector.h>
#include <zephyr/net/prometheus/gauge.h>
#include <zephyr/net/prometheus/formatter.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/sys/sys_heap.h>
#include <sensors/channels.h>

extern struct k_heap _system_heap;

extern const struct device *zr_sensor_get_wind_speed(void);
extern const struct device *zr_sensor_get_wind_direction(void);
extern const struct device *zr_sensor_get_rainfall(void);
extern const struct device *zr_sensor_get_soil_tier1(void);
extern const struct device *zr_sensor_get_soil_tier2(void);
extern const struct device *zr_sensor_get_soil_tier3(void);

PROMETHEUS_COLLECTOR_DEFINE(ceratina_collector);

PROMETHEUS_GAUGE_DEFINE(ceratina_uptime_seconds,
			"System uptime in seconds",
			({ .key = "device", .value = "ceratina" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_heap_free_bytes,
			"Free heap memory in bytes",
			({ .key = "device", .value = "ceratina" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_wifi_rssi,
			"WiFi signal strength in dBm",
			({ .key = "device", .value = "ceratina" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_wind_speed_kilometers_per_hour,
			"Wind speed in km/h",
			({ .key = "sensor", .value = "wind_speed" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_wind_direction_degrees,
			"Wind direction in degrees",
			({ .key = "sensor", .value = "wind_direction" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_rainfall_millimeters,
			"Cumulative rainfall in mm",
			({ .key = "sensor", .value = "rainfall" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_moisture_percent_tier1,
			"Soil moisture percentage tier 1",
			({ .key = "tier", .value = "1" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_temperature_celsius_tier1,
			"Soil temperature celsius tier 1",
			({ .key = "tier", .value = "1" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_moisture_percent_tier2,
			"Soil moisture percentage tier 2",
			({ .key = "tier", .value = "2" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_temperature_celsius_tier2,
			"Soil temperature celsius tier 2",
			({ .key = "tier", .value = "2" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_moisture_percent_tier3,
			"Soil moisture percentage tier 3",
			({ .key = "tier", .value = "3" }), NULL);

PROMETHEUS_GAUGE_DEFINE(ceratina_soil_temperature_celsius_tier3,
			"Soil temperature celsius tier 3",
			({ .key = "tier", .value = "3" }), NULL);

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
			prometheus_gauge_set(&ceratina_wifi_rssi, (double)wifi_status.rssi);
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

static void update_soil_tier(const struct device *dev,
			     struct prometheus_gauge *moisture_gauge,
			     struct prometheus_gauge *temperature_gauge)
{
	if (!dev) {
		return;
	}

	struct sensor_value val;

	val.val1 = 0;
	val.val2 = 0;
	sensor_attr_set(dev, 0, SENSOR_ATTR_CERATINA_SLAVE_ID, &val);

	if (sensor_sample_fetch(dev) != 0) {
		return;
	}

	struct sensor_value reading;

	if (sensor_channel_get(dev, SENSOR_CHAN_CERATINA_SOIL_MOISTURE, &reading) == 0) {
		prometheus_gauge_set(moisture_gauge, (double)sensor_val_to_float(&reading));
	}

	if (sensor_channel_get(dev, SENSOR_CHAN_AMBIENT_TEMP, &reading) == 0) {
		prometheus_gauge_set(temperature_gauge, (double)sensor_val_to_float(&reading));
	}
}

static void update_soil_gauges(void)
{
	update_soil_tier(zr_sensor_get_soil_tier1(),
			 &ceratina_soil_moisture_percent_tier1,
			 &ceratina_soil_temperature_celsius_tier1);
	update_soil_tier(zr_sensor_get_soil_tier2(),
			 &ceratina_soil_moisture_percent_tier2,
			 &ceratina_soil_temperature_celsius_tier2);
	update_soil_tier(zr_sensor_get_soil_tier3(),
			 &ceratina_soil_moisture_percent_tier3,
			 &ceratina_soil_temperature_celsius_tier3);
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
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_moisture_percent_tier1.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_temperature_celsius_tier1.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_moisture_percent_tier2.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_temperature_celsius_tier2.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_moisture_percent_tier3.base);
	prometheus_collector_register_metric(&ceratina_collector, &ceratina_soil_temperature_celsius_tier3.base);

	is_registered = true;
}

static char metrics_buffer[2048];

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

	static const struct http_header plaintext_headers[] = {
		{.name = "Content-Type", .value = "text/plain; charset=utf-8"},
	};

	response_ctx->status = HTTP_200_OK;
	response_ctx->headers = plaintext_headers;
	response_ctx->header_count = ARRAY_SIZE(plaintext_headers);
	response_ctx->body = (const uint8_t *)metrics_buffer;
	response_ctx->body_len = strlen(metrics_buffer);
	response_ctx->final_chunk = true;

	return 0;
}
