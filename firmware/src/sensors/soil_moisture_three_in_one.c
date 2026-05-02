/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define DT_DRV_COMPAT dfrobot_soil_moisture_three_in_one

#include <errno.h>
#include <string.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/logging/log.h>
#include <zephyr/modbus/modbus.h>
#include <sensors/channels.h>

LOG_MODULE_REGISTER(soil_moisture_three_in_one, CONFIG_SENSOR_LOG_LEVEL);

#define SOIL_MOISTURE_THREE_IN_ONE_REGISTER_START         0
#define SOIL_MOISTURE_THREE_IN_ONE_REGISTER_COUNT         5
#define SOIL_MOISTURE_THREE_IN_ONE_INDEX_MOISTURE         0
#define SOIL_MOISTURE_THREE_IN_ONE_INDEX_TEMPERATURE      1
#define SOIL_MOISTURE_THREE_IN_ONE_INDEX_CONDUCTIVITY     2
#define SOIL_MOISTURE_THREE_IN_ONE_INDEX_SALINITY         3
#define SOIL_MOISTURE_THREE_IN_ONE_INDEX_TDS              4

struct soil_moisture_three_in_one_config {
	const char *modbus_iface_name;
	const struct modbus_iface_param client_param;
	uint8_t slave_id;
};

struct soil_moisture_three_in_one_data {
	int iface;
	uint16_t register_values[SOIL_MOISTURE_THREE_IN_ONE_REGISTER_COUNT];
};

static int soil_moisture_three_in_one_init(const struct device *device)
{
	const struct soil_moisture_three_in_one_config *config = device->config;
	struct soil_moisture_three_in_one_data *data = device->data;

	int iface = modbus_iface_get_by_name(config->modbus_iface_name);

	if (iface < 0) {
		LOG_ERR("Failed to get Modbus interface: %s", config->modbus_iface_name);
		return -ENODEV;
	}

	int init_status = modbus_init_client(iface, config->client_param);

	if (init_status != 0 && init_status != -EALREADY) {
		LOG_ERR("modbus client init failed: %d", init_status);
		return init_status;
	}

	data->iface = iface;
	return 0;
}

static int soil_moisture_three_in_one_sample_fetch(const struct device *device,
						   enum sensor_channel channel)
{
	const struct soil_moisture_three_in_one_config *config = device->config;
	struct soil_moisture_three_in_one_data *data = device->data;

	memset(data->register_values, 0, sizeof(data->register_values));

	int read_status = modbus_read_holding_regs(
		data->iface, config->slave_id,
		SOIL_MOISTURE_THREE_IN_ONE_REGISTER_START,
		data->register_values,
		SOIL_MOISTURE_THREE_IN_ONE_REGISTER_COUNT);
	if (read_status != 0) {
		LOG_ERR("Failed to read SEN0601 slave %u: %d",
			config->slave_id, read_status);
		return read_status < 0 ? read_status : -EIO;
	}

	return 0;
}

static int soil_moisture_three_in_one_channel_get(const struct device *device,
						  enum sensor_channel channel,
						  struct sensor_value *value)
{
	struct soil_moisture_three_in_one_data *data = device->data;

	switch ((uint32_t)channel) {
	case SENSOR_CHAN_CERATINA_SOIL_MOISTURE: {
		uint16_t raw_moisture =
			data->register_values[SOIL_MOISTURE_THREE_IN_ONE_INDEX_MOISTURE];

		value->val1 = raw_moisture / 10;
		value->val2 = (raw_moisture % 10) * 100000;
		break;
	}

	case SENSOR_CHAN_AMBIENT_TEMP: {
		int16_t raw_temperature = (int16_t)data->register_values
			[SOIL_MOISTURE_THREE_IN_ONE_INDEX_TEMPERATURE];

		if (raw_temperature < 0) {
			value->val1 = -((-raw_temperature) / 10);
			value->val2 = -((-raw_temperature) % 10) * 100000;
		} else {
			value->val1 = raw_temperature / 10;
			value->val2 = (raw_temperature % 10) * 100000;
		}
		break;
	}

	case SENSOR_CHAN_CERATINA_SOIL_CONDUCTIVITY:
		value->val1 = data->register_values
			[SOIL_MOISTURE_THREE_IN_ONE_INDEX_CONDUCTIVITY];
		value->val2 = 0;
		break;

	case SENSOR_CHAN_CERATINA_SOIL_SALINITY:
		value->val1 = data->register_values
			[SOIL_MOISTURE_THREE_IN_ONE_INDEX_SALINITY];
		value->val2 = 0;
		break;

	case SENSOR_CHAN_CERATINA_SOIL_TDS:
		value->val1 = data->register_values[SOIL_MOISTURE_THREE_IN_ONE_INDEX_TDS];
		value->val2 = 0;
		break;

	default:
		return -ENOTSUP;
	}

	return 0;
}

static int soil_moisture_three_in_one_attr_get(const struct device *device,
					       enum sensor_channel channel,
					       enum sensor_attribute attribute,
					       struct sensor_value *value)
{
	const struct soil_moisture_three_in_one_config *config = device->config;

	if ((uint32_t)attribute != SENSOR_ATTR_CERATINA_SLAVE_ID) {
		return -ENOTSUP;
	}

	value->val1 = config->slave_id;
	value->val2 = 0;
	return 0;
}

static DEVICE_API(sensor, soil_moisture_three_in_one_api) = {
	.sample_fetch = soil_moisture_three_in_one_sample_fetch,
	.channel_get = soil_moisture_three_in_one_channel_get,
	.attr_get = soil_moisture_three_in_one_attr_get,
};

#define SOIL_MOISTURE_THREE_IN_ONE_DEFINE(inst)                                              \
	static const struct soil_moisture_three_in_one_config                                \
		soil_moisture_three_in_one_config_##inst = {                                 \
			.modbus_iface_name = DEVICE_DT_NAME(DT_PARENT(                       \
				DT_INST(inst, dfrobot_soil_moisture_three_in_one))),         \
			.client_param = {                                                    \
				.mode = MODBUS_MODE_RTU,                                     \
				.rx_timeout = 500000,                                        \
				.serial = {                                                  \
					.baud = 9600,                                        \
					.parity = UART_CFG_PARITY_NONE,                      \
					.stop_bits = UART_CFG_STOP_BITS_1,                   \
				},                                                           \
			},                                                                   \
			.slave_id = DT_INST_PROP(inst, slave_id),                            \
		};                                                                           \
											     \
	static struct soil_moisture_three_in_one_data                                        \
		soil_moisture_three_in_one_data_##inst;                                      \
											     \
	SENSOR_DEVICE_DT_INST_DEFINE(inst, &soil_moisture_three_in_one_init, NULL,           \
				     &soil_moisture_three_in_one_data_##inst,                \
				     &soil_moisture_three_in_one_config_##inst,              \
				     POST_KERNEL, CONFIG_SENSOR_INIT_PRIORITY,               \
				     &soil_moisture_three_in_one_api);

DT_INST_FOREACH_STATUS_OKAY(SOIL_MOISTURE_THREE_IN_ONE_DEFINE)
