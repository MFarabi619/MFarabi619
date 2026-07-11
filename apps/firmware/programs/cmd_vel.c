#include <math.h>
#include <string.h>
#include <zenoh-pico.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/led_strip.h>
#include <zephyr/drivers/pwm.h>
#include <zephyr/kernel.h>
#include <zephyr/net/net_event.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>

#define ZENOH_LOCATOR "tcp/10.0.0.161:7447"
#define CMD_VEL_KEYEXPR "0/cmd_vel/**"

#define CDR_ENCAPSULATION_HEADER_BYTES 4
#define TWIST_FIELD_BYTES sizeof(double)
#define TWIST_LINEAR_X_OFFSET                                                  \
  (CDR_ENCAPSULATION_HEADER_BYTES + 0 * TWIST_FIELD_BYTES)
#define TWIST_ANGULAR_Z_OFFSET                                                 \
  (CDR_ENCAPSULATION_HEADER_BYTES + 5 * TWIST_FIELD_BYTES)
#define TWIST_CDR_BYTES (CDR_ENCAPSULATION_HEADER_BYTES + 6 * TWIST_FIELD_BYTES)

#define PWM_FREQUENCY_HZ 20000
#define PWM_PERIOD_NS PWM_HZ(PWM_FREQUENCY_HZ)

#define LEFT_PWM_CHANNEL 0
#define RIGHT_PWM_CHANNEL 1
#define LEFT_DIR_PIN 2
#define RIGHT_DIR_PIN 7
#define LEFT_FORWARD_LEVEL 1
#define RIGHT_FORWARD_LEVEL 0

#define SHAPING_DEADZONE 0.05
#define SHAPING_MIN_SPEED 0.35
#define MAX_NORMALIZED_SPEED 1.0

#define DEADMAN_TIMEOUT_MS 500

#define LED_PIXEL_COUNT 4
#define LED_WIPE_WAIT_MS 120

#define RECONNECT_DELAY_SECONDS 2

#define CMD_VEL_THREAD_STACK_SIZE 8192
#define CMD_VEL_THREAD_PRIORITY 7
#define DEADMAN_THREAD_STACK_SIZE 1024
#define DEADMAN_THREAD_PRIORITY 6

static const struct device *const motor_pwm = DEVICE_DT_GET(DT_NODELABEL(ledc0));
static const struct device *const motor_dir = DEVICE_DT_GET(DT_NODELABEL(gpio0));
#if DT_NODE_EXISTS(DT_NODELABEL(led_strip))
static const struct device *const led_strip =
    DEVICE_DT_GET(DT_NODELABEL(led_strip));

static const struct led_rgb LED_GREEN = {.r = 0, .g = 255, .b = 0};
#endif

struct wheel_speeds {
  double left;
  double right;
};

static struct wheel_speeds mix_wheel_speeds(double linear, double angular) {
  return (struct wheel_speeds){
      .left = linear - angular,
      .right = linear + angular,
  };
}

static double shape_wheel(double speed) {
  double magnitude = fabs(speed);
  if (magnitude < SHAPING_DEADZONE) {
    return 0.0;
  }
  double scaled = magnitude;
  if (scaled > MAX_NORMALIZED_SPEED) {
    scaled = MAX_NORMALIZED_SPEED;
  }
  if (scaled < SHAPING_MIN_SPEED) {
    scaled = SHAPING_MIN_SPEED;
  }
  return speed < 0.0 ? -scaled : scaled;
}

static void drive_wheel(uint32_t pwm_channel, gpio_pin_t dir_pin,
                        int forward_level, double speed) {
  double magnitude = fabs(speed);
  if (magnitude > MAX_NORMALIZED_SPEED) {
    magnitude = MAX_NORMALIZED_SPEED;
  }
  gpio_pin_set(motor_dir, dir_pin, speed >= 0.0 ? forward_level : !forward_level);
  pwm_set(motor_pwm, pwm_channel, PWM_PERIOD_NS,
          (uint32_t)(magnitude * PWM_PERIOD_NS), 0);
}

static void drive_robot(double linear, double angular) {
  struct wheel_speeds wheel_speeds = mix_wheel_speeds(linear, angular);
  drive_wheel(LEFT_PWM_CHANNEL, LEFT_DIR_PIN, LEFT_FORWARD_LEVEL,
              shape_wheel(wheel_speeds.left));
  drive_wheel(RIGHT_PWM_CHANNEL, RIGHT_DIR_PIN, RIGHT_FORWARD_LEVEL,
              shape_wheel(wheel_speeds.right));
}

static void halt(void) { drive_robot(0.0, 0.0); }

K_SEM_DEFINE(deadman_sem, 0, 1);

static void deadman_expired(struct k_timer *timer) {
  ARG_UNUSED(timer);
  k_sem_give(&deadman_sem);
}

K_TIMER_DEFINE(deadman_timer, deadman_expired, NULL);

static void deadman_thread(void) {
  while (1) {
    k_sem_take(&deadman_sem, K_FOREVER);
    halt();
  }
}

static void on_cmd_vel(z_loaned_sample_t *sample, void *arg) {
  ARG_UNUSED(arg);
  z_owned_slice_t payload;
  z_bytes_to_slice(z_sample_payload(sample), &payload);
  const uint8_t *payload_bytes = z_slice_data(z_loan(payload));
  size_t payload_length = z_slice_len(z_loan(payload));

  if (payload_length >= TWIST_CDR_BYTES) {
    double linear_x;
    double angular_z;
    memcpy(&linear_x, payload_bytes + TWIST_LINEAR_X_OFFSET, TWIST_FIELD_BYTES);
    memcpy(&angular_z, payload_bytes + TWIST_ANGULAR_Z_OFFSET,
           TWIST_FIELD_BYTES);
    drive_robot(linear_x, angular_z);
    k_timer_start(&deadman_timer, K_MSEC(DEADMAN_TIMEOUT_MS), K_NO_WAIT);
  }

  z_drop(z_move(payload));
}

#if DT_NODE_EXISTS(DT_NODELABEL(led_strip))
static void led_color_wipe(struct led_rgb color) {
  struct led_rgb frame[LED_PIXEL_COUNT] = {0};
  for (size_t pixel_index = 0; pixel_index < LED_PIXEL_COUNT; pixel_index++) {
    frame[pixel_index] = color;
    led_strip_update_rgb(led_strip, frame, LED_PIXEL_COUNT);
    k_sleep(K_MSEC(LED_WIPE_WAIT_MS));
  }
}
#endif

static void wait_for_network(void) {
  struct net_if *station = net_if_get_wifi_sta();
  if (station == NULL) {
    return;
  }
  if (net_if_ipv4_get_global_addr(station, NET_ADDR_PREFERRED) != NULL) {
    return;
  }
  uint64_t raised_event;
  net_mgmt_event_wait_on_iface(station, NET_EVENT_IPV4_DHCP_BOUND, &raised_event,
                               NULL, NULL, K_FOREVER);
}

static void cmd_vel_thread(void) {
#if DT_NODE_EXISTS(DT_NODELABEL(led_strip))
  if (device_is_ready(led_strip)) {
    led_color_wipe(LED_GREEN);
  } else {
    printk("cmd_vel: led_strip not ready\n");
  }
#endif

  if (!device_is_ready(motor_pwm)) {
    printk("cmd_vel: motor pwm not ready\n");
    return;
  }
  if (!device_is_ready(motor_dir)) {
    printk("cmd_vel: motor dir gpio not ready\n");
    return;
  }
  gpio_pin_configure(motor_dir, LEFT_DIR_PIN, GPIO_OUTPUT_INACTIVE);
  gpio_pin_configure(motor_dir, RIGHT_DIR_PIN, GPIO_OUTPUT_INACTIVE);
  halt();

  z_owned_session_t session;
  while (1) {
    wait_for_network();

    struct net_if *station = net_if_get_wifi_sta();
    void *ipv4 = station == NULL
                     ? NULL
                     : net_if_ipv4_get_global_addr(station, NET_ADDR_PREFERRED);
    if (ipv4 != NULL) {
      const uint8_t *octets = ipv4;
      printk("cmd_vel: ip %u.%u.%u.%u, opening %s\n", octets[0], octets[1],
             octets[2], octets[3], ZENOH_LOCATOR);
    }

    z_owned_config_t config;
    z_config_default(&config);
    zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, "client");
    zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, ZENOH_LOCATOR);
    int open_result = z_open(&session, z_move(config), NULL);
    if (open_result == 0) {
      break;
    }
    printk("cmd_vel: z_open failed (%d), retrying\n", open_result);
    k_sleep(K_SECONDS(RECONNECT_DELAY_SECONDS));
  }
  printk("cmd_vel: session open, connecting %s\n", ZENOH_LOCATOR);

  if (zp_start_lease_task(z_loan_mut(session), NULL) < 0) {
    printk("cmd_vel: start_lease_task failed\n");
    return;
  }

  z_owned_closure_sample_t callback;
  z_closure(&callback, on_cmd_vel, NULL, NULL);
  z_view_keyexpr_t keyexpr;
  z_view_keyexpr_from_str_unchecked(&keyexpr, CMD_VEL_KEYEXPR);
  z_owned_subscriber_t subscriber;
  if (z_declare_subscriber(z_loan(session), &subscriber, z_loan(keyexpr),
                           z_move(callback), NULL) < 0) {
    printk("cmd_vel: declare_subscriber failed\n");
    return;
  }
  printk("cmd_vel: subscribed on %s\n", CMD_VEL_KEYEXPR);

  while (1) {
    k_sleep(K_SECONDS(1));
  }
}

K_THREAD_DEFINE(cmd_vel, CMD_VEL_THREAD_STACK_SIZE, cmd_vel_thread, NULL, NULL,
                NULL, CMD_VEL_THREAD_PRIORITY, 0, 0);
K_THREAD_DEFINE(deadman, DEADMAN_THREAD_STACK_SIZE, deadman_thread, NULL, NULL,
                NULL, DEADMAN_THREAD_PRIORITY, 0, 0);
