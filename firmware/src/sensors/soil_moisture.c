/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define DT_DRV_COMPAT dfrobot_soil_moisture

#include <errno.h>
#include <string.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/logging/log.h>
#include <zephyr/modbus/modbus.h>
#include <sensors/channels.h>

LOG_MODULE_REGISTER(soil_moisture, CONFIG_SENSOR_LOG_LEVEL);

#define MAX_PROBES_PER_RANGE 10
#define MAX_REGISTERS        9
#define SCAN_TIMEOUT_MS      10

enum soil_probe_tier {
	SOIL_TIER_UNKNOWN = 0,
	SOIL_TIER_SEN0600 = 1,
	SOIL_TIER_SEN0601 = 2,
	SOIL_TIER_SEN0604 = 3,
};

struct soil_register_map {
	uint16_t start_register;
	uint8_t register_count;
	int8_t moisture_offset;
	int8_t temperature_offset;
	int8_t conductivity_offset;
	int8_t salinity_offset;
	int8_t tds_offset;
	int8_t ph_offset;
};

static const struct soil_register_map tier_maps[] = {
	[SOIL_TIER_SEN0600] = {
		.start_register      = 0,
		.register_count      = 2,
		.moisture_offset     = 0,
		.temperature_offset  = 1,
		.conductivity_offset = -1,
		.salinity_offset     = -1,
		.tds_offset          = -1,
		.ph_offset           = -1,
	},
	[SOIL_TIER_SEN0601] = {
		.start_register      = 0,
		.register_count      = 5,
		.moisture_offset     = 0,
		.temperature_offset  = 1,
		.conductivity_offset = 2,
		.salinity_offset     = 3,
		.tds_offset          = 4,
		.ph_offset           = -1,
	},
	[SOIL_TIER_SEN0604] = {
		.start_register      = 0,
		.register_count      = 9,
		.moisture_offset     = 0,
		.temperature_offset  = 1,
		.conductivity_offset = 2,
		.salinity_offset     = 7,
		.tds_offset          = 8,
		.ph_offset           = 3,
	},
};

struct soil_probe {
	uint8_t slave_id;
	enum soil_probe_tier tier;
	bool is_responsive;
};

struct soil_moisture_config {
	const char *modbus_iface_name;
	const struct modbus_iface_param client_param;
	uint8_t scan_range_start;
	uint8_t scan_range_end;
};

struct soil_moisture_data {
	int iface;
	struct soil_probe probes[MAX_PROBES_PER_RANGE];
	uint8_t probe_count;
	uint8_t active_probe;
	uint16_t registers[MAX_REGISTERS];
};

static enum soil_probe_tier detect_tier(int iface, uint8_t slave_id)
{
	uint16_t buf[9] = {0};

	if (modbus_read_holding_regs(iface, slave_id, 0, buf, 9) == 0) {
		return SOIL_TIER_SEN0604;
	}

	if (modbus_read_holding_regs(iface, slave_id, 0, buf, 5) == 0) {
		return SOIL_TIER_SEN0601;
	}

	if (modbus_read_holding_regs(iface, slave_id, 0, buf, 2) == 0) {
		return SOIL_TIER_SEN0600;
	}

	return SOIL_TIER_UNKNOWN;
}

static void discover_probes(const struct device *dev)
{
	const struct soil_moisture_config *config = dev->config;
	struct soil_moisture_data *data = dev->data;

	data->probe_count = 0;
	memset(data->probes, 0, sizeof(data->probes));

	for (uint8_t slave_id = config->scan_range_start;
	     slave_id <= config->scan_range_end;
	     slave_id++) {

		if (data->probe_count >= MAX_PROBES_PER_RANGE) {
			break;
		}

		uint16_t buf[2] = {0};
		int err = modbus_read_holding_regs(data->iface, slave_id, 0, buf, 2);

		if (err != 0) {
			k_msleep(SCAN_TIMEOUT_MS);
			continue;
		}

		enum soil_probe_tier tier = detect_tier(data->iface, slave_id);

		if (tier == SOIL_TIER_UNKNOWN) {
			continue;
		}

		data->probes[data->probe_count] = (struct soil_probe){
			.slave_id = slave_id,
			.tier = tier,
			.is_responsive = true,
		};

		LOG_INF("Soil probe slave %u: tier %u", slave_id, tier);
		data->probe_count++;
		k_msleep(SCAN_TIMEOUT_MS);
	}

	LOG_INF("Discovered %u soil probes in range %u-%u",
		data->probe_count, config->scan_range_start, config->scan_range_end);
}

static int soil_moisture_init(const struct device *dev)
{
	const struct soil_moisture_config *config = dev->config;
	struct soil_moisture_data *data = dev->data;

	int iface = modbus_iface_get_by_name(config->modbus_iface_name);

	if (iface < 0) {
		LOG_ERR("Failed to get Modbus interface: %s", config->modbus_iface_name);
		return -ENODEV;
	}

	modbus_init_client(iface, config->client_param);

	data->iface = iface;
	discover_probes(dev);

	return 0;
}

static int soil_moisture_sample_fetch(const struct device *dev, enum sensor_channel chan)
{
	struct soil_moisture_data *data = dev->data;

	if (data->active_probe >= data->probe_count) {
		return -ENODATA;
	}

	struct soil_probe *probe = &data->probes[data->active_probe];

	if (!probe->is_responsive || probe->tier == SOIL_TIER_UNKNOWN) {
		return -ENODATA;
	}

	const struct soil_register_map *map = &tier_maps[probe->tier];

	memset(data->registers, 0, sizeof(data->registers));
	int err = modbus_read_holding_regs(data->iface, probe->slave_id,
					   map->start_register, data->registers,
					   map->register_count);
	if (err != 0) {
		LOG_ERR("Failed to read soil probe slave %u: %d",
			probe->slave_id, err);
		probe->is_responsive = false;
		return err;
	}

	return 0;
}

static int soil_moisture_channel_get(const struct device *dev, enum sensor_channel chan,
				     struct sensor_value *val)
{
	struct soil_moisture_data *data = dev->data;

	if (data->active_probe >= data->probe_count) {
		return -ENODATA;
	}

	struct soil_probe *probe = &data->probes[data->active_probe];
	const struct soil_register_map *map = &tier_maps[probe->tier];

	switch ((uint32_t)chan) {
	case SENSOR_CHAN_CERATINA_SOIL_MOISTURE:
		if (map->moisture_offset < 0) {
			return -ENOTSUP;
		}
		val->val1 = data->registers[map->moisture_offset] / 10;
		val->val2 = (data->registers[map->moisture_offset] % 10) * 100000;
		break;

	case SENSOR_CHAN_AMBIENT_TEMP: {
		if (map->temperature_offset < 0) {
			return -ENOTSUP;
		}
		int16_t raw_temp = (int16_t)data->registers[map->temperature_offset];
		if (raw_temp < 0) {
			val->val1 = -((-raw_temp) / 10);
			val->val2 = -((-raw_temp) % 10) * 100000;
		} else {
			val->val1 = raw_temp / 10;
			val->val2 = (raw_temp % 10) * 100000;
		}
		break;
	}

	case SENSOR_CHAN_CERATINA_SOIL_CONDUCTIVITY:
		if (map->conductivity_offset < 0) {
			return -ENOTSUP;
		}
		val->val1 = data->registers[map->conductivity_offset];
		val->val2 = 0;
		break;

	case SENSOR_CHAN_CERATINA_SOIL_SALINITY:
		if (map->salinity_offset < 0) {
			return -ENOTSUP;
		}
		val->val1 = data->registers[map->salinity_offset];
		val->val2 = 0;
		break;

	case SENSOR_CHAN_CERATINA_SOIL_TDS:
		if (map->tds_offset < 0) {
			return -ENOTSUP;
		}
		val->val1 = data->registers[map->tds_offset];
		val->val2 = 0;
		break;

	case SENSOR_CHAN_CERATINA_SOIL_PH:
		if (map->ph_offset < 0) {
			return -ENOTSUP;
		}
		val->val1 = data->registers[map->ph_offset] / 10;
		val->val2 = (data->registers[map->ph_offset] % 10) * 100000;
		break;

	default:
		return -ENOTSUP;
	}

	return 0;
}

static int soil_moisture_attr_set(const struct device *dev, enum sensor_channel chan,
				  enum sensor_attribute attr, const struct sensor_value *val)
{
	struct soil_moisture_data *data = dev->data;

	switch ((uint32_t)attr) {
	case SENSOR_ATTR_CERATINA_SLAVE_ID:
		if (val->val1 < 0 || (uint8_t)val->val1 >= data->probe_count) {
			return -EINVAL;
		}
		data->active_probe = (uint8_t)val->val1;
		break;

	case SENSOR_ATTR_CERATINA_SCAN:
		discover_probes(dev);
		break;

	default:
		return -ENOTSUP;
	}

	return 0;
}

static int soil_moisture_attr_get(const struct device *dev, enum sensor_channel chan,
				  enum sensor_attribute attr, struct sensor_value *val)
{
	struct soil_moisture_data *data = dev->data;

	switch ((uint32_t)attr) {
	case SENSOR_ATTR_CERATINA_SLAVE_ID:
		if (data->active_probe < data->probe_count) {
			val->val1 = data->probes[data->active_probe].slave_id;
		} else {
			val->val1 = 0;
		}
		val->val2 = 0;
		break;

	case SENSOR_ATTR_CERATINA_SCAN:
		val->val1 = data->probe_count;
		val->val2 = 0;
		break;

	default:
		return -ENOTSUP;
	}

	return 0;
}

static DEVICE_API(sensor, soil_moisture_api) = {
	.sample_fetch = soil_moisture_sample_fetch,
	.channel_get = soil_moisture_channel_get,
	.attr_set = soil_moisture_attr_set,
	.attr_get = soil_moisture_attr_get,
};

#define SOIL_MOISTURE_DEFINE(inst)                                                  \
	static const struct soil_moisture_config soil_moisture_config_##inst = {     \
		.modbus_iface_name = DEVICE_DT_NAME(                                \
			DT_PARENT(DT_INST(inst, dfrobot_soil_moisture))),           \
		.client_param = {                                                   \
			.mode = MODBUS_MODE_RTU,                                    \
			.rx_timeout = 100000,                                       \
			.serial = {                                                 \
				.baud = 9600,                                       \
				.parity = UART_CFG_PARITY_NONE,                     \
				.stop_bits = UART_CFG_STOP_BITS_1,                  \
			},                                                          \
		},                                                                  \
		.scan_range_start = DT_INST_PROP(inst, scan_range_start),           \
		.scan_range_end = DT_INST_PROP(inst, scan_range_end),               \
	};                                                                          \
									            \
	static struct soil_moisture_data soil_moisture_data_##inst;                  \
									            \
	SENSOR_DEVICE_DT_INST_DEFINE(inst, &soil_moisture_init, NULL,               \
				     &soil_moisture_data_##inst,                     \
				     &soil_moisture_config_##inst, POST_KERNEL,      \
				     CONFIG_SENSOR_INIT_PRIORITY,                    \
				     &soil_moisture_api);

DT_INST_FOREACH_STATUS_OKAY(SOIL_MOISTURE_DEFINE)
