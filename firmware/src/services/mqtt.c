#include <zephyr/kernel.h>
#include <zephyr/net/mqtt.h>
#include <zephyr/net/socket.h>
#include <zephyr/net/hostname.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/settings/settings.h>
#include <zephyr/sys/sys_heap.h>
#include <zephyr/sys/reboot.h>
#include <zephyr/logging/log.h>
#include <hal/efuse_hal.h>

LOG_MODULE_REGISTER(mqtt_service, LOG_LEVEL_INF);

#define MQTT_BROKER_PORT_DEFAULT 1883
#define MQTT_TOPIC_PREFIX "ceratina/"
#define MQTT_AVAILABILITY_SUFFIX "/availability"

static struct mqtt_client client;
static struct sockaddr_storage broker_addr;

static uint8_t rx_buffer[512];
static uint8_t tx_buffer[512];

static struct {
	char host[64];
	uint16_t port;
	char username[64];
	char password[64];
	uint32_t publish_interval;
	uint8_t deep_sleep_enabled;
	uint32_t sleep_duration;
} mqtt_config;

static char client_id[32];
static char availability_topic[96];
static char command_topic_filter[96];
static char config_topic_filter[96];

static volatile bool is_connected;

static struct {
	char topic[128];
	uint8_t payload[128];
	size_t topic_length;
	size_t payload_length;
	volatile bool is_pending;
} incoming_message;

static int settings_set(const char *name, size_t len,
			settings_read_cb read_cb, void *cb_arg)
{
	if (!strcmp(name, "host")) {
		if (len >= sizeof(mqtt_config.host)) {
			return -EINVAL;
		}
		int result = read_cb(cb_arg, mqtt_config.host, len);
		if (result >= 0) {
			mqtt_config.host[len] = '\0';
		}
		return result;
	}

	if (!strcmp(name, "port")) {
		return read_cb(cb_arg, &mqtt_config.port, sizeof(mqtt_config.port));
	}

	if (!strcmp(name, "username")) {
		if (len >= sizeof(mqtt_config.username)) {
			return -EINVAL;
		}
		int result = read_cb(cb_arg, mqtt_config.username, len);
		if (result >= 0) {
			mqtt_config.username[len] = '\0';
		}
		return result;
	}

	if (!strcmp(name, "password")) {
		if (len >= sizeof(mqtt_config.password)) {
			return -EINVAL;
		}
		int result = read_cb(cb_arg, mqtt_config.password, len);
		if (result >= 0) {
			mqtt_config.password[len] = '\0';
		}
		return result;
	}

	if (!strcmp(name, "interval")) {
		return read_cb(cb_arg, &mqtt_config.publish_interval,
			       sizeof(mqtt_config.publish_interval));
	}

	if (!strcmp(name, "sleep_en")) {
		return read_cb(cb_arg, &mqtt_config.deep_sleep_enabled,
			       sizeof(mqtt_config.deep_sleep_enabled));
	}

	if (!strcmp(name, "sleep_dur")) {
		return read_cb(cb_arg, &mqtt_config.sleep_duration,
			       sizeof(mqtt_config.sleep_duration));
	}

	return -ENOENT;
}

SETTINGS_STATIC_HANDLER_DEFINE(mqtt, "mqtt", NULL, settings_set, NULL, NULL);

static void build_topics(void)
{
	const char *hostname = net_hostname_get();

	snprintk(client_id, sizeof(client_id), "ceratina_%s", hostname);
	snprintk(availability_topic, sizeof(availability_topic),
		 MQTT_TOPIC_PREFIX "%s" MQTT_AVAILABILITY_SUFFIX, hostname);
	snprintk(command_topic_filter, sizeof(command_topic_filter),
		 MQTT_TOPIC_PREFIX "%s/command/#", hostname);
	snprintk(config_topic_filter, sizeof(config_topic_filter),
		 MQTT_TOPIC_PREFIX "%s/config/+/set", hostname);
}

static void publish_availability(const char *payload)
{
	struct mqtt_publish_param param = {
		.message = {
			.topic = {
				.topic = {
					.utf8 = availability_topic,
					.size = strlen(availability_topic),
				},
				.qos = MQTT_QOS_1_AT_LEAST_ONCE,
			},
			.payload = {
				.data = (uint8_t *)payload,
				.len = strlen(payload),
			},
		},
		.message_id = k_uptime_get_32(),
		.dup_flag = 0,
		.retain_flag = 1,
	};

	mqtt_publish(&client, &param);
}

static const char homeassistant_status_topic[] = "homeassistant/status";

static void subscribe_command_topics(void)
{
	struct mqtt_topic topics[] = {
		{
			.topic = {
				.utf8 = command_topic_filter,
				.size = strlen(command_topic_filter),
			},
			.qos = MQTT_QOS_1_AT_LEAST_ONCE,
		},
		{
			.topic = {
				.utf8 = config_topic_filter,
				.size = strlen(config_topic_filter),
			},
			.qos = MQTT_QOS_1_AT_LEAST_ONCE,
		},
		{
			.topic = {
				.utf8 = homeassistant_status_topic,
				.size = sizeof(homeassistant_status_topic) - 1,
			},
			.qos = MQTT_QOS_0_AT_MOST_ONCE,
		},
	};

	struct mqtt_subscription_list subscription = {
		.list = topics,
		.list_count = ARRAY_SIZE(topics),
		.message_id = k_uptime_get_32(),
	};

	int result = mqtt_subscribe(&client, &subscription);

	if (result == 0) {
		LOG_INF("Subscribed to command and config topics");
	} else {
		LOG_ERR("Subscribe failed: %d", result);
	}
}

static void handle_incoming_publish(struct mqtt_client *client_handle,
				    const struct mqtt_evt *event)
{
	const struct mqtt_publish_message *message =
		&event->param.publish.message;
	size_t topic_length = message->topic.topic.size;
	size_t payload_length = message->payload.len;

	if (topic_length < sizeof(incoming_message.topic)) {
		memcpy(incoming_message.topic,
		       message->topic.topic.utf8, topic_length);
		incoming_message.topic[topic_length] = '\0';
		incoming_message.topic_length = topic_length;
	} else {
		incoming_message.topic[0] = '\0';
		incoming_message.topic_length = 0;
	}

	if (payload_length > 0 &&
	    payload_length <= sizeof(incoming_message.payload)) {
		mqtt_readall_publish_payload(client_handle,
					    incoming_message.payload,
					    payload_length);
		incoming_message.payload_length = payload_length;
	} else if (payload_length > sizeof(incoming_message.payload)) {
		uint8_t drain[64];
		size_t remaining = payload_length;

		while (remaining > 0) {
			size_t chunk = MIN(remaining, sizeof(drain));

			mqtt_readall_publish_payload(client_handle,
						    drain, chunk);
			remaining -= chunk;
		}
		incoming_message.payload_length = 0;
	} else {
		incoming_message.payload_length = 0;
	}

	if (message->topic.qos == MQTT_QOS_1_AT_LEAST_ONCE) {
		struct mqtt_puback_param ack = {
			.message_id = event->param.publish.message_id,
		};

		mqtt_publish_qos1_ack(client_handle, &ack);
	}

	incoming_message.is_pending = true;

	LOG_INF("MQTT RX [%s] (%u bytes)",
		incoming_message.topic, incoming_message.payload_length);
}

static void event_handler(struct mqtt_client *client_handle,
			   const struct mqtt_evt *event)
{
	switch (event->type) {
	case MQTT_EVT_CONNACK:
		if (event->result == 0) {
			LOG_INF("Connected to MQTT broker");
			is_connected = true;
			publish_availability("online");
			subscribe_command_topics();
		} else {
			LOG_ERR("MQTT CONNACK error: %d", event->result);
		}
		break;

	case MQTT_EVT_DISCONNECT:
		LOG_INF("MQTT disconnected: %d", event->result);
		is_connected = false;
		break;

	case MQTT_EVT_PUBACK:
		break;

	case MQTT_EVT_SUBACK:
		LOG_INF("MQTT subscriptions acknowledged");
		break;

	case MQTT_EVT_PUBLISH:
		handle_incoming_publish(client_handle, event);
		break;

	default:
		break;
	}
}

int mqtt_service_init(void)
{
	settings_load_subtree("mqtt");

	if (mqtt_config.port == 0) {
		mqtt_config.port = MQTT_BROKER_PORT_DEFAULT;
	}

	if (mqtt_config.publish_interval == 0) {
		mqtt_config.publish_interval = 30;
	}

	if (mqtt_config.sleep_duration == 0) {
		mqtt_config.sleep_duration = 300;
	}

	build_topics();

	LOG_INF("MQTT config: host=%s port=%u interval=%us",
		mqtt_config.host[0] ? mqtt_config.host : "(unset)",
		mqtt_config.port, mqtt_config.publish_interval);

	return 0;
}

bool mqtt_service_is_configured(void)
{
	return mqtt_config.host[0] != '\0';
}

bool mqtt_service_is_connected(void)
{
	return is_connected;
}

int mqtt_service_connect(void)
{
	if (mqtt_config.host[0] == '\0') {
		LOG_WRN("MQTT broker not configured");
		return -EINVAL;
	}

	struct zsock_addrinfo *result = NULL;
	struct zsock_addrinfo hints = {
		.ai_family = AF_INET,
		.ai_socktype = SOCK_STREAM,
	};

	char port_string[6];

	snprintk(port_string, sizeof(port_string), "%u", mqtt_config.port);

	int error = zsock_getaddrinfo(mqtt_config.host, port_string,
				      &hints, &result);

	if (error || !result) {
		LOG_ERR("DNS resolve failed for %s: %d",
			mqtt_config.host, error);
		return -EHOSTUNREACH;
	}

	memcpy(&broker_addr, result->ai_addr, result->ai_addrlen);
	zsock_freeaddrinfo(result);

	mqtt_client_init(&client);

	client.broker = (struct sockaddr *)&broker_addr;
	client.evt_cb = event_handler;
	client.client_id.utf8 = client_id;
	client.client_id.size = strlen(client_id);
	client.protocol_version = MQTT_VERSION_3_1_1;

	static struct mqtt_utf8 user_name_storage;
	static struct mqtt_utf8 password_storage;

	if (mqtt_config.username[0] != '\0') {
		user_name_storage.utf8 = mqtt_config.username;
		user_name_storage.size = strlen(mqtt_config.username);
		client.user_name = &user_name_storage;

		password_storage.utf8 = mqtt_config.password;
		password_storage.size = strlen(mqtt_config.password);
		client.password = &password_storage;
	}

	static struct mqtt_topic will_topic_storage;
	static struct mqtt_utf8 will_message_storage;

	will_topic_storage.topic.utf8 = availability_topic;
	will_topic_storage.topic.size = strlen(availability_topic);
	will_topic_storage.qos = MQTT_QOS_1_AT_LEAST_ONCE;
	will_message_storage = MQTT_UTF8_LITERAL("offline");

	client.will_topic = &will_topic_storage;
	client.will_message = &will_message_storage;
	client.will_retain = 1;

	client.rx_buf = rx_buffer;
	client.rx_buf_size = sizeof(rx_buffer);
	client.tx_buf = tx_buffer;
	client.tx_buf_size = sizeof(tx_buffer);

	error = mqtt_connect(&client);

	if (error) {
		LOG_ERR("MQTT connect failed: %d", error);
		return error;
	}

	LOG_INF("MQTT connecting to %s:%u", mqtt_config.host, mqtt_config.port);
	return 0;
}

int mqtt_service_publish(const char *topic, const uint8_t *payload,
			 size_t payload_length, bool retain)
{
	if (!is_connected) {
		return -ENOTCONN;
	}

	struct mqtt_publish_param param = {
		.message = {
			.topic = {
				.topic = {
					.utf8 = topic,
					.size = strlen(topic),
				},
				.qos = MQTT_QOS_1_AT_LEAST_ONCE,
			},
			.payload = {
				.data = (uint8_t *)payload,
				.len = payload_length,
			},
		},
		.message_id = k_uptime_get_32(),
		.dup_flag = 0,
		.retain_flag = retain ? 1 : 0,
	};

	return mqtt_publish(&client, &param);
}

int mqtt_service_disconnect(void)
{
	if (!is_connected) {
		return 0;
	}

	return mqtt_disconnect(&client, NULL);
}

int mqtt_service_poll(int timeout_milliseconds)
{
	if (!is_connected && client.transport.type == 0) {
		return -ENOTCONN;
	}

	struct zsock_pollfd fds = {
		.fd = client.transport.tcp.sock,
		.events = ZSOCK_POLLIN,
	};

	int result = zsock_poll(&fds, 1, timeout_milliseconds);

	if (result > 0 && (fds.revents & ZSOCK_POLLIN)) {
		mqtt_input(&client);
	}

	mqtt_live(&client);

	return 0;
}

int mqtt_service_keepalive_time_left(void)
{
	return mqtt_keepalive_time_left(&client);
}

int mqtt_service_get_incoming(char *topic_out, size_t *topic_length,
			      uint8_t *payload_out, size_t *payload_length)
{
	if (!incoming_message.is_pending) {
		return -EAGAIN;
	}

	memcpy(topic_out, incoming_message.topic,
	       incoming_message.topic_length + 1);
	*topic_length = incoming_message.topic_length;

	if (incoming_message.payload_length > 0) {
		memcpy(payload_out, incoming_message.payload,
		       incoming_message.payload_length);
	}
	*payload_length = incoming_message.payload_length;

	incoming_message.is_pending = false;

	return 0;
}

int mqtt_service_set_config(const char *host, uint16_t port,
			    const char *username, const char *password)
{
	strncpy(mqtt_config.host, host, sizeof(mqtt_config.host) - 1);
	mqtt_config.host[sizeof(mqtt_config.host) - 1] = '\0';
	mqtt_config.port = port;

	if (username) {
		strncpy(mqtt_config.username, username,
			sizeof(mqtt_config.username) - 1);
		mqtt_config.username[sizeof(mqtt_config.username) - 1] = '\0';
	} else {
		mqtt_config.username[0] = '\0';
	}

	if (password) {
		strncpy(mqtt_config.password, password,
			sizeof(mqtt_config.password) - 1);
		mqtt_config.password[sizeof(mqtt_config.password) - 1] = '\0';
	} else {
		mqtt_config.password[0] = '\0';
	}

	settings_save_one("mqtt/host", mqtt_config.host,
			  strlen(mqtt_config.host));
	settings_save_one("mqtt/port", &mqtt_config.port,
			  sizeof(mqtt_config.port));
	settings_save_one("mqtt/username", mqtt_config.username,
			  strlen(mqtt_config.username));
	settings_save_one("mqtt/password", mqtt_config.password,
			  strlen(mqtt_config.password));

	build_topics();

	return 0;
}

uint32_t mqtt_service_get_publish_interval(void)
{
	return mqtt_config.publish_interval;
}

void mqtt_service_set_publish_interval(uint32_t seconds)
{
	mqtt_config.publish_interval = seconds;
	settings_save_one("mqtt/interval", &mqtt_config.publish_interval,
			  sizeof(mqtt_config.publish_interval));
}

bool mqtt_service_get_deep_sleep_enabled(void)
{
	return mqtt_config.deep_sleep_enabled != 0;
}

void mqtt_service_set_deep_sleep_enabled(bool enabled)
{
	mqtt_config.deep_sleep_enabled = enabled ? 1 : 0;
	settings_save_one("mqtt/sleep_en", &mqtt_config.deep_sleep_enabled,
			  sizeof(mqtt_config.deep_sleep_enabled));
}

uint32_t mqtt_service_get_sleep_duration(void)
{
	return mqtt_config.sleep_duration;
}

void mqtt_service_set_sleep_duration(uint32_t seconds)
{
	mqtt_config.sleep_duration = seconds;
	settings_save_one("mqtt/sleep_dur", &mqtt_config.sleep_duration,
			  sizeof(mqtt_config.sleep_duration));
}

const char *mqtt_service_get_host(void)
{
	return mqtt_config.host;
}

uint16_t mqtt_service_get_port(void)
{
	return mqtt_config.port;
}

const char *mqtt_service_get_username(void)
{
	return mqtt_config.username;
}

const char *mqtt_service_get_availability_topic(void)
{
	return availability_topic;
}

extern struct k_heap _system_heap;

int32_t mqtt_helper_get_wifi_rssi(void)
{
	struct net_if *iface = net_if_get_wifi_sta();

	if (!iface) {
		return 0;
	}

	struct wifi_iface_status wifi_status = {0};
	int result = net_mgmt(NET_REQUEST_WIFI_IFACE_STATUS, iface,
			      &wifi_status, sizeof(wifi_status));

	return (result == 0) ? wifi_status.rssi : 0;
}

uint32_t mqtt_helper_get_heap_free(void)
{
	struct sys_memory_stats stats;

	if (sys_heap_runtime_stats_get(&_system_heap.heap, &stats) == 0) {
		return (uint32_t)stats.free_bytes;
	}

	return 0;
}

void mqtt_helper_get_mac(uint8_t *out)
{
	memset(out, 0, 6);

	struct net_if *iface = net_if_get_wifi_sta();

	if (!iface) {
		return;
	}

	struct net_linkaddr *link_addr = net_if_get_link_addr(iface);

	if (!link_addr || link_addr->len < 6) {
		return;
	}

	memcpy(out, link_addr->addr, 6);
}

uint32_t mqtt_helper_get_chip_revision(void)
{
	return efuse_hal_chip_revision();
}

void mqtt_helper_get_ipv4(char *out, size_t out_size)
{
	out[0] = '\0';

	struct net_if *iface = net_if_get_wifi_sta();

	if (!iface) {
		iface = net_if_get_default();
	}

	if (!iface) {
		return;
	}

	struct net_in_addr *addr =
		net_if_ipv4_get_global_addr(iface, NET_ADDR_PREFERRED);

	if (addr) {
		net_addr_ntop(AF_INET, addr, out, out_size);
	}
}
