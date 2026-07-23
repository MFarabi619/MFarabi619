#define DT_DRV_COMPAT mipi_dbi_esp32_qspi

#include <zephyr/device.h>
#include <zephyr/drivers/clock_control.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/mipi_dbi.h>
#include <zephyr/display/mipi_display.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <esp_clk_tree.h>
#include <esp_rom_gpio.h>
#include <hal/spi_hal.h>
#include <soc/spi_periph.h>

LOG_MODULE_REGISTER(mipi_dbi_esp32_qspi, CONFIG_DISPLAY_LOG_LEVEL);

#define QSPI_OPCODE_COMMAND 0x02
#define QSPI_OPCODE_PIXEL   0x32
#define QSPI_FIFO_SIZE      64
#define QSPI_DONE_TIMEOUT_US 50000
#define QSPI_DUTY_CYCLE_50_PERCENT 128
#define QSPI_RESET_GPIOS_MAX 4

struct mipi_dbi_esp32_qspi_config {
	const struct device *clock_dev;
	clock_control_subsys_t clock_subsys;
	int spi_host;
	int sclk_pin;
	int sio_pins[4];
	struct gpio_dt_spec cs;
	struct gpio_dt_spec resets[QSPI_RESET_GPIOS_MAX];
	int reset_count;
	uint32_t frequency;
};

struct mipi_dbi_esp32_qspi_data {
	spi_hal_context_t hal;
	spi_hal_dev_config_t hal_dev;
	struct k_mutex lock;
};

static int mipi_dbi_esp32_qspi_transact(const struct device *dev, uint8_t opcode,
					uint8_t cmd, const uint8_t *data_buf, size_t len,
					uint8_t data_lines)
{
	const struct mipi_dbi_esp32_qspi_config *config = dev->config;
	struct mipi_dbi_esp32_qspi_data *data = dev->data;
	spi_hal_context_t *hal = &data->hal;
	spi_hal_trans_config_t trans = {
		.cmd = opcode,
		.cmd_bits = 8,
		.addr = (uint64_t)cmd << 8,
		.addr_bits = 24,
		.dummy_bits = 0,
		.tx_bitlen = len * 8,
		.rx_bitlen = 0,
		.send_buffer = (uint8_t *)data_buf,
		.rcv_buffer = NULL,
		.line_mode = {
			.cmd_lines = 1,
			.addr_lines = 1,
			.data_lines = data_lines,
		},
		.cs_keep_active = 0,
	};

	gpio_pin_set_dt(&config->cs, 1);
	spi_hal_setup_trans(hal, &data->hal_dev, &trans);
	if (len > 0) {
		spi_hal_push_tx_buffer(hal, &trans);
	}
	spi_hal_enable_data_line(hal->hw, len > 0, false);
	spi_hal_user_start(hal);

	if (!WAIT_FOR(spi_hal_usr_is_done(hal), QSPI_DONE_TIMEOUT_US, NULL)) {
		gpio_pin_set_dt(&config->cs, 0);
		LOG_ERR("Transaction timed out (opcode 0x%02x, cmd 0x%02x)", opcode, cmd);
		return -ETIMEDOUT;
	}
	gpio_pin_set_dt(&config->cs, 0);

	return 0;
}

static int mipi_dbi_esp32_qspi_command_write(const struct device *dev,
					     const struct mipi_dbi_config *dbi_config,
					     uint8_t cmd, const uint8_t *data_buf, size_t len)
{
	struct mipi_dbi_esp32_qspi_data *data = dev->data;
	int ret;

	ARG_UNUSED(dbi_config);

	if (len > QSPI_FIFO_SIZE) {
		return -EINVAL;
	}

	k_mutex_lock(&data->lock, K_FOREVER);
	ret = mipi_dbi_esp32_qspi_transact(dev, QSPI_OPCODE_COMMAND, cmd, data_buf, len, 1);
	k_mutex_unlock(&data->lock);

	return ret;
}

static int mipi_dbi_esp32_qspi_write_display(const struct device *dev,
					     const struct mipi_dbi_config *dbi_config,
					     const uint8_t *framebuf,
					     struct display_buffer_descriptor *desc,
					     enum display_pixel_format pixfmt)
{
	struct mipi_dbi_esp32_qspi_data *data = dev->data;
	size_t remaining = desc->buf_size;
	uint8_t cmd = MIPI_DCS_WRITE_MEMORY_START;
	int ret = 0;

	ARG_UNUSED(dbi_config);
	ARG_UNUSED(pixfmt);

	k_mutex_lock(&data->lock, K_FOREVER);
	while (remaining > 0) {
		size_t chunk = MIN(remaining, (size_t)QSPI_FIFO_SIZE);

		ret = mipi_dbi_esp32_qspi_transact(dev, QSPI_OPCODE_PIXEL, cmd, framebuf, chunk, 4);
		if (ret < 0) {
			break;
		}
		framebuf += chunk;
		remaining -= chunk;
		cmd = MIPI_DCS_WRITE_MEMORY_CONTINUE;
	}
	k_mutex_unlock(&data->lock);

	return ret;
}

static int mipi_dbi_esp32_qspi_reset(const struct device *dev, k_timeout_t delay)
{
	const struct mipi_dbi_esp32_qspi_config *config = dev->config;
	int ret;

	if (config->reset_count == 0) {
		return -ENOTSUP;
	}

	for (int i = 0; i < config->reset_count; i++) {
		ret = gpio_pin_set_dt(&config->resets[i], 1);
		if (ret < 0) {
			return ret;
		}
	}
	k_sleep(delay);
	for (int i = 0; i < config->reset_count; i++) {
		ret = gpio_pin_set_dt(&config->resets[i], 0);
		if (ret < 0) {
			return ret;
		}
	}

	return 0;
}

static int mipi_dbi_esp32_qspi_init(const struct device *dev)
{
	const struct mipi_dbi_esp32_qspi_config *config = dev->config;
	struct mipi_dbi_esp32_qspi_data *data = dev->data;
	const spi_signal_conn_t *signals = &spi_periph_signal[config->spi_host];
	const int out_signals[4] = {signals->spid_out, signals->spiq_out, signals->spiwp_out,
				    signals->spihd_out};
	const int in_signals[4] = {signals->spid_in, signals->spiq_in, signals->spiwp_in,
				   signals->spihd_in};
	uint32_t clock_source_hz;
	int ret;

	k_mutex_init(&data->lock);

	ret = clock_control_on(config->clock_dev, config->clock_subsys);
	if (ret < 0) {
		LOG_ERR("Could not enable SPI clock (%d)", ret);
		return ret;
	}

	ret = gpio_pin_configure_dt(&config->cs, GPIO_OUTPUT_INACTIVE);
	if (ret < 0) {
		return ret;
	}
	for (int i = 0; i < config->reset_count; i++) {
		ret = gpio_pin_configure_dt(&config->resets[i], GPIO_OUTPUT_INACTIVE);
		if (ret < 0) {
			return ret;
		}
	}

	esp_rom_gpio_pad_select_gpio(config->sclk_pin);
	esp_rom_gpio_connect_out_signal(config->sclk_pin, signals->spiclk_out, false, false);
	for (int i = 0; i < 4; i++) {
		esp_rom_gpio_pad_select_gpio(config->sio_pins[i]);
		esp_rom_gpio_connect_out_signal(config->sio_pins[i], out_signals[i], false, false);
		esp_rom_gpio_connect_in_signal(config->sio_pins[i], in_signals[i], false);
	}

	spi_hal_init(&data->hal, config->spi_host);

	ret = esp_clk_tree_src_get_freq_hz(SPI_CLK_SRC_DEFAULT,
					   ESP_CLK_TREE_SRC_FREQ_PRECISION_APPROX,
					   &clock_source_hz);
	if (ret != 0) {
		LOG_ERR("Could not get SPI clock source frequency");
		return -EIO;
	}

	spi_hal_timing_param_t timing_param = {
		.half_duplex = 1,
		.no_compensate = 1,
		.expected_freq = config->frequency,
		.duty_cycle = QSPI_DUTY_CYCLE_50_PERCENT,
		.input_delay_ns = 0,
		.use_gpio = true,
		.clk_src_hz = clock_source_hz,
	};

	ret = spi_hal_cal_clock_conf(&timing_param, &data->hal_dev.timing_conf);
	if (ret != 0) {
		LOG_ERR("Could not configure SPI clock (%d)", ret);
		return -EIO;
	}

	data->hal_dev.mode = 0;
	data->hal_dev.cs_pin_id = -1;
	data->hal_dev.half_duplex = 1;
	data->hal_dev.no_compensate = 1;

	spi_hal_setup_device(&data->hal, &data->hal_dev);

	LOG_INF("QSPI host %d ready, source clock %u Hz, target %u Hz", config->spi_host,
		clock_source_hz, config->frequency);

	return 0;
}

static DEVICE_API(mipi_dbi, mipi_dbi_esp32_qspi_api) = {
	.command_write = mipi_dbi_esp32_qspi_command_write,
	.write_display = mipi_dbi_esp32_qspi_write_display,
	.reset = mipi_dbi_esp32_qspi_reset,
};

#define MIPI_DBI_ESP32_QSPI_DEFINE(inst)                                                           \
	static const struct mipi_dbi_esp32_qspi_config mipi_dbi_esp32_qspi_config_##inst = {       \
		.clock_dev = DEVICE_DT_GET(DT_INST_CLOCKS_CTLR(inst)),                             \
		.clock_subsys = (clock_control_subsys_t)DT_INST_CLOCKS_CELL(inst, offset),         \
		.spi_host = DT_INST_PROP(inst, spi_host),                                          \
		.sclk_pin = DT_INST_PROP(inst, sclk_pin),                                          \
		.sio_pins = {DT_INST_PROP_BY_IDX(inst, sio_pins, 0),                               \
			     DT_INST_PROP_BY_IDX(inst, sio_pins, 1),                               \
			     DT_INST_PROP_BY_IDX(inst, sio_pins, 2),                               \
			     DT_INST_PROP_BY_IDX(inst, sio_pins, 3)},                              \
		.cs = GPIO_DT_SPEC_INST_GET(inst, cs_gpios),                                       \
		.resets = COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, reset_gpios),                    \
				      ({DT_INST_FOREACH_PROP_ELEM_SEP(inst, reset_gpios,           \
							GPIO_DT_SPEC_GET_BY_IDX, (,))}),           \
				      ({0})),                                                      \
		.reset_count = DT_INST_PROP_LEN_OR(inst, reset_gpios, 0),                          \
		.frequency = DT_INST_PROP(inst, clock_frequency),                                  \
	};                                                                                         \
	static struct mipi_dbi_esp32_qspi_data mipi_dbi_esp32_qspi_data_##inst;                    \
	DEVICE_DT_INST_DEFINE(inst, mipi_dbi_esp32_qspi_init, NULL,                                \
			      &mipi_dbi_esp32_qspi_data_##inst,                                    \
			      &mipi_dbi_esp32_qspi_config_##inst, POST_KERNEL,                     \
			      CONFIG_MIPI_DBI_INIT_PRIORITY, &mipi_dbi_esp32_qspi_api);

DT_INST_FOREACH_STATUS_OKAY(MIPI_DBI_ESP32_QSPI_DEFINE)
