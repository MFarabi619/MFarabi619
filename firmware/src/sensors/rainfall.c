/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define DT_DRV_COMPAT dfrobot_rainfall

#include <errno.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/logging/log.h>
#include <zephyr/modbus/modbus.h>
#include <sensors/channels.h>

LOG_MODULE_REGISTER(rainfall, CONFIG_SENSOR_LOG_LEVEL);

#define RAINFALL_REGISTER_ADDRESS 0x0000
#define RAINFALL_REGISTER_COUNT   1
#define RAINFALL_CLEAR_VALUE      0x005A

struct rainfall_config {
	const char *modbus_iface_name;
	const struct modbus_iface_param client_param;
	uint8_t slave_id;
};

struct rainfall_data {
	int iface;
	uint16_t raw;
};

static int rainfall_init(const struct device *dev)
{
	const struct rainfall_config *config = dev->config;
	struct rainfall_data *data = dev->data;

	int iface = modbus_iface_get_by_name(config->modbus_iface_name);

	if (iface < 0) {
		LOG_ERR("Failed to get Modbus interface: %s", config->modbus_iface_name);
		return -ENODEV;
	}

	modbus_init_client(iface, config->client_param);

	data->iface = iface;

	return 0;
}

static int rainfall_sample_fetch(const struct device *dev, enum sensor_channel chan)
{
	const struct rainfall_config *config = dev->config;
	struct rainfall_data *data = dev->data;

	uint16_t reg_buf[RAINFALL_REGISTER_COUNT] = {0};
	int err = modbus_read_input_regs(data->iface, config->slave_id,
					 RAINFALL_REGISTER_ADDRESS, reg_buf,
					 RAINFALL_REGISTER_COUNT);
	if (err != 0) {
		LOG_ERR("Failed to read rainfall from slave %u: %d",
			config->slave_id, err);
		return err;
	}

	data->raw = reg_buf[0];
	return 0;
}

static int rainfall_channel_get(const struct device *dev, enum sensor_channel chan,
				struct sensor_value *val)
{
	struct rainfall_data *data = dev->data;

	if ((uint32_t)chan != SENSOR_CHAN_CERATINA_RAINFALL) {
		return -ENOTSUP;
	}

	val->val1 = data->raw / 10;
	val->val2 = (data->raw % 10) * 100000;

	return 0;
}

static int rainfall_attr_set(const struct device *dev, enum sensor_channel chan,
			     enum sensor_attribute attr, const struct sensor_value *val)
{
	const struct rainfall_config *config = dev->config;
	struct rainfall_data *data = dev->data;

	if ((uint32_t)attr != SENSOR_ATTR_CERATINA_CLEAR) {
		return -ENOTSUP;
	}

	int err = modbus_write_holding_reg(data->iface, config->slave_id,
					   RAINFALL_REGISTER_ADDRESS,
					   RAINFALL_CLEAR_VALUE);
	if (err != 0) {
		LOG_ERR("Failed to clear rainfall accumulator: %d", err);
		return err;
	}

	return 0;
}

static DEVICE_API(sensor, rainfall_api) = {
	.sample_fetch = rainfall_sample_fetch,
	.channel_get = rainfall_channel_get,
	.attr_set = rainfall_attr_set,
};

#define RAINFALL_DEFINE(inst)                                                    \
	static const struct rainfall_config rainfall_config_##inst = {           \
		.modbus_iface_name = DEVICE_DT_NAME(                             \
			DT_PARENT(DT_INST(inst, dfrobot_rainfall))),             \
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
	static struct rainfall_data rainfall_data_##inst;                        \
									         \
	SENSOR_DEVICE_DT_INST_DEFINE(inst, &rainfall_init, NULL,                 \
				     &rainfall_data_##inst,                       \
				     &rainfall_config_##inst, POST_KERNEL,        \
				     CONFIG_SENSOR_INIT_PRIORITY, &rainfall_api);

DT_INST_FOREACH_STATUS_OKAY(RAINFALL_DEFINE)
