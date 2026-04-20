#include <programs/led.h>

#include <string.h>
#include <zephyr/device.h>
#include <zephyr/drivers/led_strip.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(led);

#define STRIP_NODE       DT_ALIAS(led_strip)
#define STRIP_NUM_PIXELS DT_PROP(DT_ALIAS(led_strip), chain_length)

static struct led_rgb pixels[STRIP_NUM_PIXELS];
static const struct device *const strip = DEVICE_DT_GET(STRIP_NODE);
static struct color current_color;
static uint8_t brightness = 20;

bool led_init(void)
{
	if (!device_is_ready(strip)) {
		LOG_ERR("LED strip device %s is not ready", strip->name);
		return false;
	}

	current_color = color_black;
	memset(pixels, 0, sizeof(pixels));
	led_strip_update_rgb(strip, pixels, STRIP_NUM_PIXELS);

	LOG_INF("LED strip device %s ready", strip->name);
	return true;
}

int led_set(struct color c)
{
	return led_set_rgb(c.r, c.g, c.b);
}

int led_set_rgb(uint8_t r, uint8_t g, uint8_t b)
{
	pixels[0].r = (uint8_t)((r * brightness) / 255);
	pixels[0].g = (uint8_t)((g * brightness) / 255);
	pixels[0].b = (uint8_t)((b * brightness) / 255);
	current_color = (struct color){r, g, b};
	return led_strip_update_rgb(strip, pixels, STRIP_NUM_PIXELS);
}

void led_set_brightness(uint8_t value)
{
	brightness = value;
	led_set(current_color);
}

uint8_t led_get_brightness(void)
{
	return brightness;
}

int led_off(void)
{
	return led_set(color_black);
}

struct color led_get_color(void)
{
	return current_color;
}

//---

#if defined(CONFIG_ZTEST) && defined(CONFIG_TEST_LED)
#include <zephyr/ztest.h>

ZTEST_SUITE(led, NULL, NULL, NULL, NULL, NULL);

ZTEST(led, test_init)
{
	zassert_true(led_init());
	struct color c = led_get_color();
	zassert_equal(c.r, 0);
	zassert_equal(c.g, 0);
	zassert_equal(c.b, 0);
}

ZTEST(led, test_set_named)
{
	zassert_ok(led_set(color_red));
	struct color c = led_get_color();
	zassert_equal(c.r, 255);
	zassert_equal(c.g, 0);
	zassert_equal(c.b, 0);
}

ZTEST(led, test_set_rgb)
{
	zassert_ok(led_set_rgb(100, 200, 50));
	struct color c = led_get_color();
	zassert_equal(c.r, 100);
	zassert_equal(c.g, 200);
	zassert_equal(c.b, 50);
}

ZTEST(led, test_off)
{
	led_set(color_white);
	zassert_ok(led_off());
	struct color c = led_get_color();
	zassert_equal(c.r, 0);
	zassert_equal(c.g, 0);
	zassert_equal(c.b, 0);
}
#endif
