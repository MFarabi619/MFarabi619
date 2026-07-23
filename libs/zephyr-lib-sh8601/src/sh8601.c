#define DT_DRV_COMPAT sinowealth_sh8601

#include <zephyr/device.h>
#include <zephyr/drivers/display.h>
#include <zephyr/drivers/mipi_dbi.h>
#include <zephyr/display/mipi_display.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(sh8601, CONFIG_DISPLAY_LOG_LEVEL);

#define SH8601_WIDTH_PIXELS_MAX 368
#define SH8601_BYTES_PER_PIXEL 2

#define SH8601_TEAR_EFFECT_VBLANK_ONLY 0x00
#define SH8601_CTRL_DISPLAY_BRIGHTNESS_CTRL BIT(5)
#define SH8601_BRIGHTNESS_SCALE_SHIFT 2

#define SH8601_RESET_PULSE_MS 20
#define SH8601_RESET_RECOVERY_MS 150
#define SH8601_SOFT_RESET_DELAY_MS 10
#define SH8601_SLEEP_OUT_DELAY_MS 120
#define SH8601_DISPLAY_ON_DELAY_MS 120

struct sh8601_config {
	const struct device *mipi_dbi;
	struct mipi_dbi_config dbi_config;
	uint16_t width;
	uint16_t height;
};

static int sh8601_command(const struct device *dev, uint8_t cmd, const uint8_t *data, size_t len)
{
	const struct sh8601_config *config = dev->config;

	return mipi_dbi_command_write(config->mipi_dbi, &config->dbi_config, cmd, data, len);
}

static int sh8601_set_window(const struct device *dev, uint16_t x, uint16_t y, uint16_t width,
			     uint16_t height)
{
	uint16_t x_end = x + width - 1;
	uint16_t y_end = y + height - 1;
	uint8_t column[4] = {x >> 8, x & 0xff, x_end >> 8, x_end & 0xff};
	uint8_t page[4] = {y >> 8, y & 0xff, y_end >> 8, y_end & 0xff};
	int ret;

	ret = sh8601_command(dev, MIPI_DCS_SET_COLUMN_ADDRESS, column, sizeof(column));
	if (ret < 0) {
		return ret;
	}
	return sh8601_command(dev, MIPI_DCS_SET_PAGE_ADDRESS, page, sizeof(page));
}

static int sh8601_write(const struct device *dev, uint16_t x, uint16_t y,
			const struct display_buffer_descriptor *desc, const void *buf)
{
	const struct sh8601_config *config = dev->config;
	struct display_buffer_descriptor mipi_desc = *desc;
	int ret;

	ret = sh8601_set_window(dev, x, y, desc->width, desc->height);
	if (ret < 0) {
		return ret;
	}

	return mipi_dbi_write_display(config->mipi_dbi, &config->dbi_config, buf, &mipi_desc,
				      PIXEL_FORMAT_RGB_565);
}

static int sh8601_blanking_off(const struct device *dev)
{
	return sh8601_command(dev, MIPI_DCS_SET_DISPLAY_ON, NULL, 0);
}

static int sh8601_blanking_on(const struct device *dev)
{
	return sh8601_command(dev, MIPI_DCS_SET_DISPLAY_OFF, NULL, 0);
}

static int sh8601_set_brightness(const struct device *dev, uint8_t brightness)
{
	uint16_t value = (uint16_t)brightness << SH8601_BRIGHTNESS_SCALE_SHIFT;
	uint8_t payload[2] = {value & 0xff, value >> 8};

	return sh8601_command(dev, MIPI_DCS_SET_DISPLAY_BRIGHTNESS, payload, sizeof(payload));
}

static void sh8601_get_capabilities(const struct device *dev,
				    struct display_capabilities *capabilities)
{
	const struct sh8601_config *config = dev->config;

	memset(capabilities, 0, sizeof(*capabilities));
	capabilities->x_resolution = config->width;
	capabilities->y_resolution = config->height;
	capabilities->supported_pixel_formats = PIXEL_FORMAT_RGB_565;
	capabilities->current_pixel_format = PIXEL_FORMAT_RGB_565;
}

static int sh8601_set_pixel_format(const struct device *dev, enum display_pixel_format format)
{
	if (format == PIXEL_FORMAT_RGB_565) {
		return 0;
	}
	return -ENOTSUP;
}

static int sh8601_fill(const struct device *dev, uint16_t color)
{
	const struct sh8601_config *config = dev->config;
	static uint8_t row[SH8601_WIDTH_PIXELS_MAX * SH8601_BYTES_PER_PIXEL];
	struct display_buffer_descriptor desc = {
		.buf_size = sizeof(row),
		.width = config->width,
		.height = 1,
		.pitch = config->width,
	};
	int ret;

	for (size_t i = 0; i < sizeof(row); i += SH8601_BYTES_PER_PIXEL) {
		row[i] = color >> 8;
		row[i + 1] = color & 0xff;
	}

	for (uint16_t y = 0; y < config->height; y++) {
		ret = sh8601_write(dev, 0, y, &desc, row);
		if (ret < 0) {
			return ret;
		}
	}

	return 0;
}

static int sh8601_init(const struct device *dev)
{
	const struct sh8601_config *config = dev->config;
	const uint8_t pixel_format = MIPI_DCS_PIXEL_FORMAT_16BIT;
	const uint8_t address_mode = 0x00;
	const uint8_t tear_effect_mode = SH8601_TEAR_EFFECT_VBLANK_ONLY;
	const uint8_t control_display = SH8601_CTRL_DISPLAY_BRIGHTNESS_CTRL;
	int ret;

	if (!device_is_ready(config->mipi_dbi)) {
		LOG_ERR("MIPI DBI device not ready");
		return -ENODEV;
	}

	ret = mipi_dbi_reset(config->mipi_dbi, SH8601_RESET_PULSE_MS);
	if (ret < 0 && ret != -ENOTSUP) {
		return ret;
	}
	k_msleep(SH8601_RESET_RECOVERY_MS);

	ret = sh8601_command(dev, MIPI_DCS_SOFT_RESET, NULL, 0);
	if (ret < 0) {
		return ret;
	}
	k_msleep(SH8601_SOFT_RESET_DELAY_MS);

	ret = sh8601_command(dev, MIPI_DCS_EXIT_SLEEP_MODE, NULL, 0);
	if (ret < 0) {
		return ret;
	}
	k_msleep(SH8601_SLEEP_OUT_DELAY_MS);

	ret = sh8601_command(dev, MIPI_DCS_SET_PIXEL_FORMAT, &pixel_format, 1);
	if (ret < 0) {
		return ret;
	}
	ret = sh8601_command(dev, MIPI_DCS_SET_ADDRESS_MODE, &address_mode, 1);
	if (ret < 0) {
		return ret;
	}
	ret = sh8601_command(dev, MIPI_DCS_SET_TEAR_ON, &tear_effect_mode, 1);
	if (ret < 0) {
		return ret;
	}
	ret = sh8601_command(dev, MIPI_DCS_WRITE_CONTROL_DISPLAY, &control_display, 1);
	if (ret < 0) {
		return ret;
	}
	ret = sh8601_set_brightness(dev, UINT8_MAX);
	if (ret < 0) {
		return ret;
	}

	ret = sh8601_command(dev, MIPI_DCS_SET_DISPLAY_ON, NULL, 0);
	if (ret < 0) {
		return ret;
	}
	k_msleep(SH8601_DISPLAY_ON_DELAY_MS);

	return sh8601_fill(dev, 0x0000);
}

static DEVICE_API(display, sh8601_api) = {
	.blanking_on = sh8601_blanking_on,
	.blanking_off = sh8601_blanking_off,
	.write = sh8601_write,
	.set_brightness = sh8601_set_brightness,
	.get_capabilities = sh8601_get_capabilities,
	.set_pixel_format = sh8601_set_pixel_format,
};

#define SH8601_DEFINE(inst)                                                                        \
	static const struct sh8601_config sh8601_config_##inst = {                                 \
		.mipi_dbi = DEVICE_DT_GET(DT_INST_BUS(inst)),                                      \
		.dbi_config = {0},                                                                 \
		.width = DT_INST_PROP(inst, width),                                                \
		.height = DT_INST_PROP(inst, height),                                              \
	};                                                                                         \
	DEVICE_DT_INST_DEFINE(inst, sh8601_init, NULL, NULL, &sh8601_config_##inst, POST_KERNEL,   \
			      CONFIG_DISPLAY_INIT_PRIORITY, &sh8601_api);

DT_INST_FOREACH_STATUS_OKAY(SH8601_DEFINE)
