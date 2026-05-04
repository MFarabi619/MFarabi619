/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <errno.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>

#define SENSOR_DEVICE_GETTER(name, nodelabel)                            \
	const struct device *zr_sensor_get_##name(void)                  \
	{                                                                \
		return DEVICE_DT_GET_OR_NULL(DT_NODELABEL(nodelabel));   \
	}

SENSOR_DEVICE_GETTER(soil_moisture, soil_moisture)
SENSOR_DEVICE_GETTER(soil_moisture_three_in_one, soil_moisture_three_in_one)
SENSOR_DEVICE_GETTER(co2, scd41)

int zr_sensor_init_co2(void)
{
	const struct device *dev = DEVICE_DT_GET_OR_NULL(DT_NODELABEL(scd41));
	if (dev == NULL) {
		return -ENODEV;
	}
	int result = device_init(dev);
	if (result == -EALREADY) {
		return 0;
	}
	return result;
}
