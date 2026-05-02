/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CERATINA_SENSORS_CHANNELS_H_
#define CERATINA_SENSORS_CHANNELS_H_

#include <zephyr/drivers/sensor.h>

/*
 * The SENSOR_CHAN_* and SENSOR_ATTR_* prefixes are kept short on purpose:
 * these enumerators extend Zephyr's `enum sensor_channel` and
 * `enum sensor_attribute` via SENSOR_CHAN_PRIV_START / SENSOR_ATTR_PRIV_START
 * and are passed directly to sensor_channel_get() and sensor_attr_get(). Do
 * not expand them to SENSOR_CHANNEL_* / SENSOR_ATTRIBUTE_* — the short form
 * matches Zephyr's API surface, lets `grep SENSOR_CHAN_` find every channel
 * reference (ours and upstream) in one pass, and is the convention every
 * out-of-tree Zephyr driver follows. This is the one place the project's
 * "no abbreviations" rule yields to an external naming contract.
 */
enum sensor_channel_ceratina {
	SENSOR_CHAN_CERATINA_WIND_SPEED = SENSOR_CHAN_PRIV_START,
	SENSOR_CHAN_CERATINA_WIND_DIRECTION_DEGREES,
	SENSOR_CHAN_CERATINA_WIND_DIRECTION_SLICE,
	SENSOR_CHAN_CERATINA_RAINFALL,
	SENSOR_CHAN_CERATINA_SOIL_MOISTURE,
	SENSOR_CHAN_CERATINA_SOIL_CONDUCTIVITY,
	SENSOR_CHAN_CERATINA_SOIL_SALINITY,
	SENSOR_CHAN_CERATINA_SOIL_TDS,
	SENSOR_CHAN_CERATINA_SOIL_PH,
};

enum sensor_attribute_ceratina {
	SENSOR_ATTR_CERATINA_CLEAR = SENSOR_ATTR_PRIV_START,
	SENSOR_ATTR_CERATINA_SLAVE_ID,
};

#endif /* CERATINA_SENSORS_CHANNELS_H_ */
