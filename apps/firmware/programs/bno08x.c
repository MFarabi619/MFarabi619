#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <bno08x/bno08x.h>
#include <sh2_err.h>

LOG_MODULE_REGISTER(bno08x, LOG_LEVEL_INF);

#define BNO08X_REPORT_INTERVAL_US 100000

static const sh2_SensorId_t bno08x_reports[] = {
	SH2_ROTATION_VECTOR,
	SH2_GAME_ROTATION_VECTOR,
	SH2_GEOMAGNETIC_ROTATION_VECTOR,
	SH2_ACCELEROMETER,
	SH2_LINEAR_ACCELERATION,
	SH2_GRAVITY,
	SH2_GYROSCOPE_CALIBRATED,
	SH2_MAGNETIC_FIELD_CALIBRATED,
	SH2_STABILITY_CLASSIFIER,
	SH2_SIGNIFICANT_MOTION,
	SH2_STEP_COUNTER,
	SH2_TAP_DETECTOR,
	SH2_SHAKE_DETECTOR,
	SH2_PERSONAL_ACTIVITY_CLASSIFIER,
};

static void log_quat(const char *tag, sh2_RotationVectorWAcc_t *rv)
{
	bno08x_euler_t e;

	bno08x_quaternion_to_euler_rv(rv, &e, true);
	LOG_INF("%s w=%.4f i=%.4f j=%.4f k=%.4f acc_rad=%.3f yaw=%.1f pitch=%.1f roll=%.1f",
		tag, (double)rv->real, (double)rv->i, (double)rv->j, (double)rv->k,
		(double)rv->accuracy, (double)e.yaw, (double)e.pitch, (double)e.roll);
}

static void bno08x_thread(void *a, void *b, void *c)
{
	ARG_UNUSED(a);
	ARG_UNUSED(b);
	ARG_UNUSED(c);

	k_msleep(500);

	if (bno08x_init() != SH2_OK) {
		LOG_ERR("bno08x_init failed");
		return;
	}
	for (size_t i = 0; i < ARRAY_SIZE(bno08x_reports); i++) {
		bno08x_enable_report(bno08x_reports[i], BNO08X_REPORT_INTERVAL_US);
	}

	sh2_SensorValue_t v;

	while (1) {
		if (!bno08x_get_sensor_event(&v)) {
			k_msleep(1);
			continue;
		}

		switch (v.sensorId) {
		case SH2_ROTATION_VECTOR:
			log_quat("rotv", &v.un.rotationVector);
			break;
		case SH2_GEOMAGNETIC_ROTATION_VECTOR:
			log_quat("geov", &v.un.geoMagRotationVector);
			break;
		case SH2_GAME_ROTATION_VECTOR:
			LOG_INF("gamv w=%.4f i=%.4f j=%.4f k=%.4f",
				(double)v.un.gameRotationVector.real,
				(double)v.un.gameRotationVector.i,
				(double)v.un.gameRotationVector.j,
				(double)v.un.gameRotationVector.k);
			break;
		case SH2_ACCELEROMETER:
			LOG_INF("accel x=%.3f y=%.3f z=%.3f", (double)v.un.accelerometer.x,
				(double)v.un.accelerometer.y, (double)v.un.accelerometer.z);
			break;
		case SH2_LINEAR_ACCELERATION:
			LOG_INF("linac x=%.3f y=%.3f z=%.3f", (double)v.un.linearAcceleration.x,
				(double)v.un.linearAcceleration.y,
				(double)v.un.linearAcceleration.z);
			break;
		case SH2_GRAVITY:
			LOG_INF("grav x=%.3f y=%.3f z=%.3f", (double)v.un.gravity.x,
				(double)v.un.gravity.y, (double)v.un.gravity.z);
			break;
		case SH2_GYROSCOPE_CALIBRATED:
			LOG_INF("gyro x=%.4f y=%.4f z=%.4f", (double)v.un.gyroscope.x,
				(double)v.un.gyroscope.y, (double)v.un.gyroscope.z);
			break;
		case SH2_MAGNETIC_FIELD_CALIBRATED:
			LOG_INF("mag x=%.2f y=%.2f z=%.2f", (double)v.un.magneticField.x,
				(double)v.un.magneticField.y, (double)v.un.magneticField.z);
			break;
		case SH2_STABILITY_CLASSIFIER:
			LOG_INF("stab class=%u",
				(unsigned int)v.un.stabilityClassifier.classification);
			break;
		case SH2_SIGNIFICANT_MOTION:
			LOG_INF("sigmot motion=%u", (unsigned int)v.un.sigMotion.motion);
			break;
		case SH2_STEP_COUNTER:
			LOG_INF("steps count=%u", (unsigned int)v.un.stepCounter.steps);
			break;
		case SH2_TAP_DETECTOR:
			LOG_INF("tap flags=0x%02x", (unsigned int)v.un.tapDetector.flags);
			break;
		case SH2_SHAKE_DETECTOR:
			LOG_INF("shake bits=0x%04x", (unsigned int)v.un.shakeDetector.shake);
			break;
		case SH2_PERSONAL_ACTIVITY_CLASSIFIER:
			LOG_INF("activity state=%u",
				(unsigned int)v.un.personalActivityClassifier.mostLikelyState);
			break;
		}
	}
}

K_THREAD_DEFINE(bno08x, 4096, bno08x_thread, NULL, NULL, NULL, 7, 0, 0);
