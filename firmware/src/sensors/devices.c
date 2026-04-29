/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/device.h>
#include <zephyr/devicetree.h>

#define SENSOR_DEVICE_GETTER(name, nodelabel)                            \
	const struct device *zr_sensor_get_##name(void)                  \
	{                                                                \
		return DEVICE_DT_GET_OR_NULL(DT_NODELABEL(nodelabel));   \
	}

SENSOR_DEVICE_GETTER(wind_speed, wind_speed)
SENSOR_DEVICE_GETTER(wind_direction, wind_direction)
SENSOR_DEVICE_GETTER(rainfall, rainfall)
SENSOR_DEVICE_GETTER(soil_tier1, soil_tier1)
SENSOR_DEVICE_GETTER(soil_tier2, soil_tier2)
SENSOR_DEVICE_GETTER(soil_tier3, soil_tier3)
