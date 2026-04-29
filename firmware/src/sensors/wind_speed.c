/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define DT_DRV_COMPAT dfrobot_wind_speed

#include <errno.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/logging/log.h>
#include <zephyr/modbus/modbus.h>
#include <sensors/channels.h>

LOG_MODULE_REGISTER(wind_speed, CONFIG_SENSOR_LOG_LEVEL);

#define WIND_SPEED_REGISTER_ADDRESS 0x0000
#define WIND_SPEED_REGISTER_COUNT   1

struct wind_speed_config {
	const char *modbus_iface_name;
	const struct modbus_iface_param client_param;
	uint8_t slave_id;
};

struct wind_speed_data {
	int iface;
	uint16_t raw;
};

static int wind_speed_init(const struct device *dev)
{
	const struct wind_speed_config *config = dev->config;
	struct wind_speed_data *data = dev->data;

	int iface = modbus_iface_get_by_name(config->modbus_iface_name);

	if (iface < 0) {
		LOG_ERR("Failed to get Modbus interface: %s", config->modbus_iface_name);
		return -ENODEV;
	}

	modbus_init_client(iface, config->client_param);

	data->iface = iface;

	return 0;
}

static int wind_speed_sample_fetch(const struct device *dev, enum sensor_channel chan)
{
	const struct wind_speed_config *config = dev->config;
	struct wind_speed_data *data = dev->data;

	uint16_t reg_buf[WIND_SPEED_REGISTER_COUNT] = {0};
	int err = modbus_read_input_regs(data->iface, config->slave_id,
					 WIND_SPEED_REGISTER_ADDRESS, reg_buf,
					 WIND_SPEED_REGISTER_COUNT);
	if (err != 0) {
		LOG_ERR("Failed to read wind speed from slave %u: %d",
			config->slave_id, err);
		return err;
	}

	data->raw = reg_buf[0];
	return 0;
}

static int wind_speed_channel_get(const struct device *dev, enum sensor_channel chan,
				  struct sensor_value *val)
{
	struct wind_speed_data *data = dev->data;

	if ((uint32_t)chan != SENSOR_CHAN_CERATINA_WIND_SPEED) {
		return -ENOTSUP;
	}

	uint32_t scaled = (uint32_t)data->raw * 36;
	val->val1 = scaled / 100;
	val->val2 = (scaled % 100) * 10000;

	return 0;
}

static DEVICE_API(sensor, wind_speed_api) = {
	.sample_fetch = wind_speed_sample_fetch,
	.channel_get = wind_speed_channel_get,
};

#define WIND_SPEED_DEFINE(inst)                                                  \
	static const struct wind_speed_config wind_speed_config_##inst = {       \
		.modbus_iface_name = DEVICE_DT_NAME(                             \
			DT_PARENT(DT_INST(inst, dfrobot_wind_speed))),           \
		.client_param = {                                                \
			.mode = MODBUS_MODE_RTU,                                 \
			.rx_timeout = 100000,                                    \
			.serial = {                                              \
				.baud = 9600,                                    \
				.parity = UART_CFG_PARITY_NONE,                  \
				.stop_bits = UART_CFG_STOP_BITS_1,               \
			},                                                       \
		},                                                               \
		.slave_id = DT_INST_PROP(inst, slave_id),                        \
	};                                                                       \
									         \
	static struct wind_speed_data wind_speed_data_##inst;                    \
									         \
	SENSOR_DEVICE_DT_INST_DEFINE(inst, &wind_speed_init, NULL,               \
				     &wind_speed_data_##inst,                     \
				     &wind_speed_config_##inst, POST_KERNEL,      \
				     CONFIG_SENSOR_INIT_PRIORITY, &wind_speed_api);

DT_INST_FOREACH_STATUS_OKAY(WIND_SPEED_DEFINE)
