#include <zenoh-pico.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/random/random.h>
#include <zephyr/sys/byteorder.h>

#include "joystick.h"
#include "wifi_station.h"
#include "zenoh_locator.h"

LOG_MODULE_REGISTER(joystick_zenoh, CONFIG_LOG_DEFAULT_LEVEL);

#define ROS_DOMAIN_ID "0"
#define JOY_TYPE_NAME "sensor_msgs::msg::dds_::Joy_"
/* From `ros2 topic info -v`; changes only when sensor_msgs/Joy's definition does. */
#define JOY_TYPE_HASH "RIHS01_0d356c79cad3401e35ffeb75a96a96e08be3ef896b8b83841d73e890989372c5"
#define JOY_KEYEXPR                                                                                \
	ROS_DOMAIN_ID "/" CONFIG_ROBOT_NAMESPACE "/joy_teleop/joy/" JOY_TYPE_NAME "/" JOY_TYPE_HASH

#define CDR_LITTLE_ENDIAN 0x01
#define JOY_FRAME_ID "joy"
#define ATTACHMENT_GID_BYTES 16
#define PUBLISH_PERIOD_MILLISECONDS 50
#define RETRY_DELAY_SECONDS 2
#define JOYSTICK_ZENOH_THREAD_STACK_SIZE 8192
#define JOYSTICK_ZENOH_THREAD_PRIORITY 7

BUILD_ASSERT(sizeof(CONFIG_ROBOT_NAMESPACE) > 1, "CONFIG_ROBOT_NAMESPACE must be set");

/* sensor_msgs/Joy in XCDR1 little-endian; every field already falls on its natural
 * alignment relative to the byte after the encapsulation header, so no padding.
 */
struct joy_message {
	uint8_t encapsulation[4];
	int32_t stamp_sec;
	uint32_t stamp_nanosec;
	uint32_t frame_id_length;
	char frame_id[sizeof(JOY_FRAME_ID)];
	uint32_t axis_count;
	float axes[JOYSTICK_AXIS_COUNT];
	uint32_t button_count;
	int32_t buttons[JOYSTICK_BUTTON_COUNT];
} __packed;

BUILD_ASSERT(offsetof(struct joy_message, axis_count) % 4 == 0);
BUILD_ASSERT(offsetof(struct joy_message, buttons) % 4 == 0);

struct rmw_zenoh_attachment {
	int64_t sequence_number;
	int64_t source_timestamp_nanoseconds;
	uint8_t gid_length;
	uint8_t gid[ATTACHMENT_GID_BYTES];
} __packed;

static uint8_t attachment_gid[ATTACHMENT_GID_BYTES];
static int64_t sequence_number;

/* Zero header stamp: the board has no synced clock, and teleop_twist_joy stamps
 * the twist itself rather than using the Joy stamp.
 */
static struct joy_message joy_message_from_stick(struct joystick_stick stick, uint8_t buttons)
{
	struct joy_message message = {
		.encapsulation = {0, CDR_LITTLE_ENDIAN, 0, 0},
		.frame_id_length = sys_cpu_to_le32(sizeof(JOY_FRAME_ID)),
		.frame_id = JOY_FRAME_ID,
		.axis_count = sys_cpu_to_le32(JOYSTICK_AXIS_COUNT),
		.axes = {-(float)stick.rightward / JOYSTICK_AXIS_FULL_SCALE,
			 -(float)stick.backward / JOYSTICK_AXIS_FULL_SCALE},
		.button_count = sys_cpu_to_le32(JOYSTICK_BUTTON_COUNT),
		.buttons = {sys_cpu_to_le32(stick.is_commanding)},
	};

	for (size_t index = 1; index < JOYSTICK_BUTTON_COUNT; index++) {
		message.buttons[index] = sys_cpu_to_le32((buttons >> index) & 1);
	}

	return message;
}

static struct rmw_zenoh_attachment build_attachment(void)
{
	struct rmw_zenoh_attachment attachment = {
		.sequence_number = sys_cpu_to_le64(++sequence_number),
		.gid_length = ATTACHMENT_GID_BYTES,
	};

	memcpy(attachment.gid, attachment_gid, ATTACHMENT_GID_BYTES);
	return attachment;
}

static int publish_joy(const z_loaned_publisher_t *publisher)
{
	struct joy_message message =
		joy_message_from_stick(joystick_read_stick(), joystick_read_buttons());
	struct rmw_zenoh_attachment attachment = build_attachment();
	z_owned_bytes_t message_bytes;
	z_owned_bytes_t attachment_bytes;
	z_publisher_put_options_t options;

	z_bytes_copy_from_buf(&message_bytes, (const uint8_t *)&message, sizeof(message));
	z_bytes_copy_from_buf(&attachment_bytes, (const uint8_t *)&attachment, sizeof(attachment));
	z_publisher_put_options_default(&options);
	options.attachment = z_move(attachment_bytes);
	return z_publisher_put(publisher, z_move(message_bytes), &options);
}

static void wait_for_session(z_owned_session_t *session)
{
	while (true) {
		wifi_station_wait_for_ipv4_address();
		wifi_station_disable_power_save();

		int result = zenoh_locator_open_session(session);

		if (result == 0) {
			LOG_INF("session open to %s, publishing %s", zenoh_locator_get(), JOY_KEYEXPR);
			return;
		}
		LOG_WRN("z_open to %s failed (%d), retrying", zenoh_locator_get(), result);
		k_sleep(K_SECONDS(RETRY_DELAY_SECONDS));
	}
}

static void joystick_zenoh_thread(void)
{
	z_owned_session_t session;
	z_owned_publisher_t publisher;
	z_view_keyexpr_t keyexpr;

	sys_rand_get(attachment_gid, sizeof(attachment_gid));
	wait_for_session(&session);
	z_view_keyexpr_from_str_unchecked(&keyexpr, JOY_KEYEXPR);
	while (z_declare_publisher(z_loan(session), &publisher, z_loan(keyexpr), NULL) != 0) {
		LOG_WRN("declare publisher failed, retrying");
		k_sleep(K_SECONDS(RETRY_DELAY_SECONDS));
	}
	bool was_publishing = true;

	while (true) {
		bool is_publishing = publish_joy(z_loan(publisher)) == 0;

		if (was_publishing && !is_publishing) {
			LOG_WRN("publish failed; waiting for zenoh to reconnect");
		} else if (!was_publishing && is_publishing) {
			LOG_INF("publishing again");
		}
		was_publishing = is_publishing;
		k_sleep(K_MSEC(PUBLISH_PERIOD_MILLISECONDS));
	}
}

K_THREAD_DEFINE(joystick_zenoh, JOYSTICK_ZENOH_THREAD_STACK_SIZE, joystick_zenoh_thread, NULL,
		NULL, NULL, JOYSTICK_ZENOH_THREAD_PRIORITY, 0, 0);
