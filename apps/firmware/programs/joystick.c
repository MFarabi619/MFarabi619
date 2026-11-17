#include <stdlib.h>

#include <zephyr/device.h>
#include <zephyr/drivers/usb/usb_buf.h>
#include <zephyr/input/input.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/usb/class/hid.h>
#include <zephyr/usb/class/usbd_hid.h>
#include <zephyr/usb/usbd.h>

#include "joystick.h"

#define DT_DRV_COMPAT joystick

LOG_MODULE_REGISTER(joystick, CONFIG_LOG_DEFAULT_LEVEL);

#define HID_DEVICE_NODE DT_INST_PHANDLE(0, hid_device)

#define IS_DIFFERENTIAL_DRIVE DT_INST_PROP(0, differential_drive)
#define SIGNAL_TIMEOUT_MILLISECONDS DT_INST_PROP(0, signal_timeout_ms)
#define CENTER_DEADZONE DT_INST_PROP(0, center_deadzone)
#define CENTER_TIMEOUT_MILLISECONDS DT_INST_PROP(0, center_timeout_ms)
#define BUTTON_PRESSED_ABOVE DT_INST_PROP(0, button_pressed_above)
#define BUTTON_CODE_COUNT DT_INST_PROP_LEN_OR(0, button_codes, 0)
#define REPORT_PERIOD_MICROSECONDS DT_PROP(HID_DEVICE_NODE, in_polling_period_us)
#define AXIS_SIZE_BITS 16
#define BUTTON_SIZE_BITS 1
#define COMMANDING_BUTTON BIT(0)
#define HID_INPUT_DATA_VARIABLE_ABSOLUTE 0x02
#define USB_VENDOR_ID 0x2fe3
#define USB_PRODUCT_ID 0x0100
#define USB_CONFIGURATION_NUMBER 1
#define USB_CONFIGURATION_ATTRIBUTES_BUS_POWERED 0
#define USB_MAX_POWER_TWO_MILLIAMPERE_UNITS 50
#define JOYSTICK_USB_THREAD_STACK_SIZE 2048
#define JOYSTICK_USB_THREAD_PRIORITY 5

BUILD_ASSERT(DT_INST_CHILD_NUM_STATUS_OKAY(0) == JOYSTICK_AXIS_COUNT,
	     "joystick needs exactly two axes");
BUILD_ASSERT(BUTTON_CODE_COUNT < JOYSTICK_BUTTON_COUNT,
	     "button-codes must leave button 0 for the commanding button");

struct axis_config {
	uint16_t zephyr_code;
	int32_t in_min;
	int32_t in_max;
	bool invert_input;
};

#define AXIS_RANGE_CHECK(node_id)                                                                  \
	BUILD_ASSERT(DT_PROP(node_id, in_min) != DT_PROP(node_id, in_max),                         \
		     "joystick axis in-min and in-max must differ");

DT_INST_FOREACH_CHILD_STATUS_OKAY(0, AXIS_RANGE_CHECK)

#define AXIS_CONFIG(node_id)                                                                       \
	{                                                                                          \
		.zephyr_code = DT_PROP(node_id, zephyr_code),                                      \
		.in_min = DT_PROP(node_id, in_min),                                                \
		.in_max = DT_PROP(node_id, in_max),                                                \
		.invert_input = DT_PROP(node_id, invert_input),                                    \
	}

static const struct axis_config axis_configs[JOYSTICK_AXIS_COUNT] = {
	DT_INST_FOREACH_CHILD_STATUS_OKAY_SEP(0, AXIS_CONFIG, (,))};

static const uint16_t button_codes[] = DT_INST_PROP_OR(0, button_codes, {});
static atomic_t axis_inputs[JOYSTICK_AXIS_COUNT];
static atomic_t button_inputs[BUTTON_CODE_COUNT];
static atomic_t last_sync_milliseconds;
static atomic_t last_off_center_milliseconds;

struct joystick_report {
	int16_t axes[JOYSTICK_AXIS_COUNT];
	uint8_t buttons;
} __packed;

BUILD_ASSERT(sizeof(((struct joystick_report *)0)->buttons) * BITS_PER_BYTE ==
		     JOYSTICK_BUTTON_COUNT,
	     "joystick report buttons must hold exactly JOYSTICK_BUTTON_COUNT bits");
BUILD_ASSERT(sizeof(struct joystick_report) == DT_PROP(HID_DEVICE_NODE, in_report_size),
	     "hid-device in-report-size must match the joystick report");

static const uint8_t report_descriptor[] = {
	HID_USAGE_PAGE(HID_USAGE_GEN_DESKTOP),
	HID_USAGE(HID_USAGE_GEN_DESKTOP_JOYSTICK),
	HID_COLLECTION(HID_COLLECTION_APPLICATION),
	HID_USAGE(HID_USAGE_GEN_DESKTOP_X),
	HID_USAGE(HID_USAGE_GEN_DESKTOP_Y),
	HID_LOGICAL_MIN16((uint8_t)(-JOYSTICK_AXIS_FULL_SCALE), (uint8_t)((-JOYSTICK_AXIS_FULL_SCALE) >> 8)),
	HID_LOGICAL_MAX16((uint8_t)JOYSTICK_AXIS_FULL_SCALE, (uint8_t)(JOYSTICK_AXIS_FULL_SCALE >> 8)),
	HID_REPORT_SIZE(AXIS_SIZE_BITS),
	HID_REPORT_COUNT(JOYSTICK_AXIS_COUNT),
	HID_INPUT(HID_INPUT_DATA_VARIABLE_ABSOLUTE),
	HID_USAGE_PAGE(HID_USAGE_GEN_BUTTON),
	HID_USAGE_MIN8(1),
	HID_USAGE_MAX8(JOYSTICK_BUTTON_COUNT),
	HID_LOGICAL_MIN8(0),
	HID_LOGICAL_MAX8(1),
	HID_REPORT_SIZE(BUTTON_SIZE_BITS),
	HID_REPORT_COUNT(JOYSTICK_BUTTON_COUNT),
	HID_INPUT(HID_INPUT_DATA_VARIABLE_ABSOLUTE),
	HID_END_COLLECTION,
};

static const struct device *const hid_device = DEVICE_DT_GET(HID_DEVICE_NODE);
UDC_STATIC_BUF_DEFINE(report_buffer, sizeof(struct joystick_report));

USBD_DEVICE_DEFINE(joystick_usbd, DEVICE_DT_GET(DT_NODELABEL(zephyr_udc0)), USB_VENDOR_ID,
		   USB_PRODUCT_ID);
USBD_DESC_LANG_DEFINE(joystick_language_descriptor);
USBD_DESC_PRODUCT_DEFINE(joystick_product_descriptor, "RC Receiver Joystick");
USBD_DESC_CONFIG_DEFINE(joystick_configuration_descriptor, "FS Configuration");
USBD_CONFIGURATION_DEFINE(joystick_configuration, USB_CONFIGURATION_ATTRIBUTES_BUS_POWERED,
			  USB_MAX_POWER_TWO_MILLIAMPERE_UNITS, &joystick_configuration_descriptor);

static bool has_signal(void)
{
	uint32_t last_sync = atomic_get(&last_sync_milliseconds);

	return last_sync != 0 && k_uptime_get_32() - last_sync <= SIGNAL_TIMEOUT_MILLISECONDS;
}

static int32_t scale_axis(size_t index)
{
	const struct axis_config *config = &axis_configs[index];
	int32_t input = atomic_get(&axis_inputs[index]);
	int32_t center = (config->in_min + config->in_max) / 2;
	int32_t half_range = (config->in_max - config->in_min) / 2;
	int32_t scaled_input = (input - center) * JOYSTICK_AXIS_FULL_SCALE / half_range;

	if (config->invert_input) {
		scaled_input = -scaled_input;
	}
	return CLAMP(scaled_input, -JOYSTICK_AXIS_FULL_SCALE, JOYSTICK_AXIS_FULL_SCALE);
}

static bool was_recently_off_center(void)
{
	uint32_t last_off_center = atomic_get(&last_off_center_milliseconds);

	return last_off_center != 0 &&
	       k_uptime_get_32() - last_off_center <= CENTER_TIMEOUT_MILLISECONDS;
}

struct joystick_stick joystick_read_stick(void)
{
	if (!has_signal()) {
		return (struct joystick_stick){0};
	}
	if (IS_DIFFERENTIAL_DRIVE) {
		int32_t right_side = scale_axis(0);
		int32_t left_side = scale_axis(1);

		return (struct joystick_stick){
			.rightward = (left_side - right_side) / 2,
			.backward = -(left_side + right_side) / 2,
			.is_commanding = was_recently_off_center(),
		};
	}
	return (struct joystick_stick){
		.rightward = scale_axis(0),
		.backward = scale_axis(1),
		.is_commanding = was_recently_off_center(),
	};
}

uint8_t joystick_read_buttons(void)
{
	uint8_t buttons = 0;

	if (!has_signal()) {
		return 0;
	}
	for (size_t index = 0; index < BUTTON_CODE_COUNT; index++) {
		if (atomic_get(&button_inputs[index]) > BUTTON_PRESSED_ABOVE) {
			buttons |= BIT(index + 1);
		}
	}
	return buttons;
}

static bool is_off_center(struct joystick_stick stick)
{
	return MAX(abs(stick.rightward), abs(stick.backward)) > CENTER_DEADZONE;
}

static void on_input_event(struct input_event *event, void *user_data)
{
	for (size_t index = 0; index < JOYSTICK_AXIS_COUNT; index++) {
		if (event->type == INPUT_EV_ABS && event->code == axis_configs[index].zephyr_code) {
			atomic_set(&axis_inputs[index], event->value);
		}
	}
	for (size_t index = 0; index < BUTTON_CODE_COUNT; index++) {
		if (event->type == INPUT_EV_ABS && event->code == button_codes[index]) {
			atomic_set(&button_inputs[index], event->value);
		}
	}
	if (!event->sync) {
		return;
	}
	uint32_t now_milliseconds = k_uptime_get_32();

	atomic_set(&last_sync_milliseconds, now_milliseconds);
	if (is_off_center(joystick_read_stick())) {
		atomic_set(&last_off_center_milliseconds, now_milliseconds);
	}
}

INPUT_CALLBACK_DEFINE(DEVICE_DT_GET(DT_INST_PHANDLE(0, input)), on_input_event, NULL);

static struct joystick_report report_from_stick(struct joystick_stick stick, uint8_t buttons)
{
	return (struct joystick_report){
		.axes = {sys_cpu_to_le16(stick.rightward), sys_cpu_to_le16(stick.backward)},
		.buttons = buttons | (stick.is_commanding ? COMMANDING_BUTTON : 0),
	};
}

static int on_get_report(const struct device *dev, const uint8_t type, const uint8_t id,
			 const uint16_t length, uint8_t *const buffer)
{
	struct joystick_report report =
		report_from_stick(joystick_read_stick(), joystick_read_buttons());
	uint16_t report_size = MIN(length, sizeof(report));

	memcpy(buffer, &report, report_size);
	return report_size;
}

static const struct hid_device_ops joystick_operations = {
	.get_report = on_get_report,
};

static int enable_usb_joystick(void)
{
	int result = hid_device_register(hid_device, report_descriptor, sizeof(report_descriptor),
					&joystick_operations);

	if (result == 0) {
		result = usbd_add_descriptor(&joystick_usbd, &joystick_language_descriptor);
	}
	if (result == 0) {
		result = usbd_add_descriptor(&joystick_usbd, &joystick_product_descriptor);
	}
	if (result == 0) {
		result = usbd_add_configuration(&joystick_usbd, USBD_SPEED_FS,
					       &joystick_configuration);
	}
	if (result == 0) {
		result = usbd_register_all_classes(&joystick_usbd, USBD_SPEED_FS,
						  USB_CONFIGURATION_NUMBER, NULL);
	}
	if (result == 0) {
		result = usbd_device_set_code_triple(&joystick_usbd, USBD_SPEED_FS, 0, 0, 0);
	}
	if (result == 0) {
		result = usbd_init(&joystick_usbd);
	}
	if (result == 0) {
		result = usbd_enable(&joystick_usbd);
	}
	if (result != 0) {
		LOG_ERR("usb joystick setup failed (%d)", result);
	}
	return result;
}

static void joystick_usb_thread(void)
{
	if (enable_usb_joystick() != 0) {
		return;
	}
	while (true) {
		struct joystick_report report =
			report_from_stick(joystick_read_stick(), joystick_read_buttons());

		memcpy(report_buffer, &report, sizeof(report));
		if (hid_device_submit_report(hid_device, sizeof(report), report_buffer) != 0) {
			k_sleep(K_USEC(REPORT_PERIOD_MICROSECONDS));
		}
	}
}

K_THREAD_DEFINE(joystick_usb, JOYSTICK_USB_THREAD_STACK_SIZE, joystick_usb_thread, NULL, NULL,
		NULL, JOYSTICK_USB_THREAD_PRIORITY, 0, 0);
