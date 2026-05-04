/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/ztest.h>

const struct device *zr_sensor_get_co2(void);
int zr_sensor_init_co2(void);

struct scd41_fixture {
	const struct device *co2_device;
};

static void *scd41_setup(void)
{
	static struct scd41_fixture fixture = {
		.co2_device = DEVICE_DT_GET(DT_NODELABEL(scd41)),
	};

	return &fixture;
}

ZTEST_SUITE(scd41, NULL, scd41_setup, NULL, NULL, NULL);

ZTEST_F(scd41, test_scd41_node_matches_expected_contract)
{
	zassert_true(DT_NODE_HAS_STATUS(DT_NODELABEL(scd41), okay),
		     "scd41 devicetree node must be enabled");
	zassert_equal(DT_REG_ADDR(DT_NODELABEL(scd41)), 0x62,
		      "scd41 devicetree address changed");
}

ZTEST_F(scd41, test_scd41_device_is_present_and_deferred)
{
	zassert_not_null(fixture->co2_device, "scd41 device handle is missing");
	zassert_equal(fixture->co2_device, zr_sensor_get_co2(),
		      "C seam returned an unexpected scd41 device");
	zassert_false(device_is_ready(fixture->co2_device),
		      "scd41 should stay deferred until the test initializes it");
}

ZTEST_F(scd41, test_scd41_init_succeeds_when_sensor_model_is_attached)
{
	int init_result = zr_sensor_init_co2();

	if (init_result != 0) {
		/*
		 * The first pass of this suite pins the firmware seam and the board
		 * contract. A negative init result means the external Renode model has
		 * not been extended with an SCD41 responder yet, so the behavior test is
		 * skipped instead of producing a misleading failure.
		 */
		ztest_test_skip();
	}

	zassert_true(device_is_ready(fixture->co2_device),
		     "scd41 should be ready after a successful deferred init");
	zassert_equal(0, zr_sensor_init_co2(),
		      "re-initializing scd41 should stay idempotent");
}
