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

SENSOR_DEVICE_GETTER(soil_moisture, soil_moisture)
SENSOR_DEVICE_GETTER(soil_moisture_three_in_one, soil_moisture_three_in_one)
