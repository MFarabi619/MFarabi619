#define DT_DRV_COMPAT pwm_rc_receiver

#include <zephyr/device.h>
#include <zephyr/drivers/pwm.h>
#include <zephyr/input/input.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(pwm_rc_receiver, CONFIG_INPUT_LOG_LEVEL);

#define PULSE_MIN_VALID_MICROSECONDS 800
#define PULSE_MAX_VALID_MICROSECONDS 2200

struct pwm_rc_receiver_channel_config {
	struct pwm_dt_spec capture;
	uint16_t type;
	uint16_t zephyr_code;
};

struct pwm_rc_receiver_channel_data {
	atomic_t pulse_width_microseconds;
	atomic_t last_pulse_milliseconds;
};

struct pwm_rc_receiver_config {
	const struct pwm_rc_receiver_channel_config *channel_config;
	struct pwm_rc_receiver_channel_data *channel_data;
	uint8_t num_channels;
	uint32_t poll_period_ms;
	uint32_t signal_timeout_ms;
};

struct pwm_rc_receiver_data {
	struct k_thread thread;
	K_KERNEL_STACK_MEMBER(thread_stack, CONFIG_INPUT_PWM_RC_RECEIVER_THREAD_STACK_SIZE);
};

static void pwm_rc_receiver_capture_callback(const struct device *pwm_dev, uint32_t pwm_channel,
					     uint32_t period_cycles, uint32_t pulse_cycles,
					     int status, void *user_data)
{
	struct pwm_rc_receiver_channel_data *channel_data = user_data;
	uint64_t pulse_width_microseconds;

	if (status != 0 ||
	    pwm_cycles_to_usec(pwm_dev, pwm_channel, pulse_cycles, &pulse_width_microseconds) != 0 ||
	    !IN_RANGE(pulse_width_microseconds, PULSE_MIN_VALID_MICROSECONDS,
		      PULSE_MAX_VALID_MICROSECONDS)) {
		return;
	}

	atomic_set(&channel_data->pulse_width_microseconds, pulse_width_microseconds);
	atomic_set(&channel_data->last_pulse_milliseconds, k_uptime_get_32());
}

static bool pwm_rc_receiver_has_signal(const struct device *dev)
{
	const struct pwm_rc_receiver_config *config = dev->config;
	uint32_t now_milliseconds = k_uptime_get_32();

	for (uint8_t i = 0; i < config->num_channels; i++) {
		uint32_t last_pulse_milliseconds =
			atomic_get(&config->channel_data[i].last_pulse_milliseconds);

		if (last_pulse_milliseconds == 0 ||
		    now_milliseconds - last_pulse_milliseconds > config->signal_timeout_ms) {
			return false;
		}
	}
	return true;
}

static void pwm_rc_receiver_report_channels(const struct device *dev)
{
	const struct pwm_rc_receiver_config *config = dev->config;

	for (uint8_t i = 0; i < config->num_channels; i++) {
		const struct pwm_rc_receiver_channel_config *channel_config =
			&config->channel_config[i];

		input_report(dev, channel_config->type, channel_config->zephyr_code,
			     atomic_get(&config->channel_data[i].pulse_width_microseconds),
			     false, K_FOREVER);
	}
}

static void pwm_rc_receiver_thread(void *device, void *unused2, void *unused3)
{
	const struct device *dev = device;
	const struct pwm_rc_receiver_config *config = dev->config;

	while (true) {
		if (pwm_rc_receiver_has_signal(dev)) {
			pwm_rc_receiver_report_channels(dev);
			input_report(dev, 0, 0, 0, true, K_FOREVER);
		}
		k_sleep(K_MSEC(config->poll_period_ms));
	}
}

static int pwm_rc_receiver_init(const struct device *dev)
{
	const struct pwm_rc_receiver_config *config = dev->config;
	struct pwm_rc_receiver_data *data = dev->data;
	int ret;

	for (uint8_t i = 0; i < config->num_channels; i++) {
		const struct pwm_dt_spec *capture = &config->channel_config[i].capture;

		if (!pwm_is_ready_dt(capture)) {
			LOG_ERR_DEVICE_NOT_READY(capture->dev);
			return -ENODEV;
		}

		ret = pwm_configure_capture(capture->dev, capture->channel,
					    capture->flags | PWM_CAPTURE_TYPE_PULSE |
						    PWM_CAPTURE_MODE_CONTINUOUS,
					    pwm_rc_receiver_capture_callback,
					    &config->channel_data[i]);
		if (ret < 0) {
			LOG_ERR("Could not configure capture on channel %u (%d)", i, ret);
			return ret;
		}
	}

	/* pwm_mc_esp32 checks a channel's busy bit before setting its capture signal, so
	 * configuring a channel after enabling another reads the wrong bit and fails -EBUSY.
	 */
	for (uint8_t i = 0; i < config->num_channels; i++) {
		const struct pwm_dt_spec *capture = &config->channel_config[i].capture;

		ret = pwm_enable_capture(capture->dev, capture->channel);
		if (ret < 0) {
			LOG_ERR("Could not enable capture on channel %u (%d)", i, ret);
			return ret;
		}
	}

	k_thread_create(&data->thread, data->thread_stack,
			K_KERNEL_STACK_SIZEOF(data->thread_stack), pwm_rc_receiver_thread,
			(void *)dev, NULL, NULL, CONFIG_INPUT_PWM_RC_RECEIVER_THREAD_PRIORITY, 0,
			K_NO_WAIT);
	k_thread_name_set(&data->thread, dev->name);

	return 0;
}

#define PWM_RC_RECEIVER_CHANNEL_CONFIG(node_id)                                                    \
	{                                                                                          \
		.capture = PWM_DT_SPEC_GET(node_id),                                               \
		.type = DT_PROP(node_id, type),                                                    \
		.zephyr_code = DT_PROP(node_id, zephyr_code),                                      \
	}

#define PWM_RC_RECEIVER_INIT(inst)                                                                 \
	static const struct pwm_rc_receiver_channel_config pwm_rc_receiver_channel_config_##inst[] = { \
		DT_INST_FOREACH_CHILD_STATUS_OKAY_SEP(inst, PWM_RC_RECEIVER_CHANNEL_CONFIG, (,))   \
	};                                                                                         \
                                                                                                   \
	static struct pwm_rc_receiver_channel_data                                                 \
		pwm_rc_receiver_channel_data_##inst[ARRAY_SIZE(                                    \
			pwm_rc_receiver_channel_config_##inst)];                                   \
                                                                                                   \
	static const struct pwm_rc_receiver_config pwm_rc_receiver_config_##inst = {               \
		.channel_config = pwm_rc_receiver_channel_config_##inst,                           \
		.channel_data = pwm_rc_receiver_channel_data_##inst,                               \
		.num_channels = ARRAY_SIZE(pwm_rc_receiver_channel_config_##inst),                 \
		.poll_period_ms = DT_INST_PROP(inst, poll_period_ms),                              \
		.signal_timeout_ms = DT_INST_PROP(inst, signal_timeout_ms),                        \
	};                                                                                         \
                                                                                                   \
	static struct pwm_rc_receiver_data pwm_rc_receiver_data_##inst;                            \
                                                                                                   \
	DEVICE_DT_INST_DEFINE(inst, pwm_rc_receiver_init, NULL, &pwm_rc_receiver_data_##inst,      \
			      &pwm_rc_receiver_config_##inst, POST_KERNEL,                         \
			      CONFIG_INPUT_INIT_PRIORITY, NULL);

DT_INST_FOREACH_STATUS_OKAY(PWM_RC_RECEIVER_INIT)
