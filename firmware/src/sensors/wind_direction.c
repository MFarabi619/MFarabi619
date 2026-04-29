/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define DT_DRV_COMPAT dfrobot_wind_direction

#include <errno.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/logging/log.h>
#include <zephyr/modbus/modbus.h>
#include <sensors/channels.h>

LOG_MODULE_REGISTER(wind_direction, CONFIG_SENSOR_LOG_LEVEL);

#define WIND_DIRECTION_REGISTER_ADDRESS 0x0000
#define WIND_DIRECTION_REGISTER_COUNT   2

struct wind_direction_config {
	const char *modbus_iface_name;
	const struct modbus_iface_param client_param;
	uint8_t slave_id;
};

struct wind_direction_data {
	int iface;
	uint16_t degrees_raw;
	uint16_t angle_slice;
};

static int wind_direction_init(const struct device *dev)
{
	const struct wind_direction_config *config = dev->config;
	struct wind_direction_data *data = dev->data;

	int iface = modbus_iface_get_by_name(config->modbus_iface_name);

	if (iface < 0) {
		LOG_ERR("Failed to get Modbus interface: %s", config->modbus_iface_name);
		return -ENODEV;
	}

	modbus_init_client(iface, config->client_param);

	data->iface = iface;

	return 0;
}

static int wind_direction_sample_fetch(const struct device *dev, enum sensor_channel chan)
{
	const struct wind_direction_config *config = dev->config;
	struct wind_direction_data *data = dev->data;

	uint16_t reg_buf[WIND_DIRECTION_REGISTER_COUNT] = {0};
	int err = modbus_read_input_regs(data->iface, config->slave_id,
					 WIND_DIRECTION_REGISTER_ADDRESS, reg_buf,
					 WIND_DIRECTION_REGISTER_COUNT);
	if (err != 0) {
		LOG_ERR("Failed to read wind direction from slave %u: %d",
			config->slave_id, err);
		return err;
	}

	data->degrees_raw = reg_buf[0];
	data->angle_slice = reg_buf[1];

	return 0;
}

static int wind_direction_channel_get(const struct device *dev, enum sensor_channel chan,
				      struct sensor_value *val)
{
	struct wind_direction_data *data = dev->data;

	switch ((uint32_t)chan) {
	case SENSOR_CHAN_CERATINA_WIND_DIRECTION_DEGREES:
		val->val1 = data->degrees_raw / 10;
		val->val2 = (data->degrees_raw % 10) * 100000;
		break;
	case SENSOR_CHAN_CERATINA_WIND_DIRECTION_SLICE:
		if (data->angle_slice > 15) {
			return -EINVAL;
		}
		val->val1 = data->angle_slice;
		val->val2 = 0;
		break;
	default:
		return -ENOTSUP;
	}

	return 0;
}

static DEVICE_API(sensor, wind_direction_api) = {
	.sample_fetch = wind_direction_sample_fetch,
	.channel_get = wind_direction_channel_get,
};

#define WIND_DIRECTION_DEFINE(inst)                                                  \
	static const struct wind_direction_config wind_direction_config_##inst = {    \
		.modbus_iface_name = DEVICE_DT_NAME(                                 \
			DT_PARENT(DT_INST(inst, dfrobot_wind_direction))),           \
		.client_param = {                                                    \
			.mode = MODBUS_MODE_RTU,                                     \
			.rx_timeout = 100000,                                        \
			.serial = {                                                  \
				.baud = 9600,                                        \
				.parity = UART_CFG_PARITY_NONE,                      \
				.stop_bits = UART_CFG_STOP_BITS_1,                   \
			},                                                           \
		},                                                                   \
		.slave_id = DT_INST_PROP(inst, slave_id),                            \
	};                                                                           \
									             \
	static struct wind_direction_data wind_direction_data_##inst;                \
									             \
	SENSOR_DEVICE_DT_INST_DEFINE(inst, &wind_direction_init, NULL,               \
				     &wind_direction_data_##inst,                     \
				     &wind_direction_config_##inst, POST_KERNEL,      \
				     CONFIG_SENSOR_INIT_PRIORITY, &wind_direction_api);

DT_INST_FOREACH_STATUS_OKAY(WIND_DIRECTION_DEFINE)
