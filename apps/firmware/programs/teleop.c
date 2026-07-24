#include <lvgl.h>
#include <math.h>
#include <stdint.h>
#include <string.h>
#include <zenoh-pico.h>
#include <zephyr/drivers/display.h>
#include <zephyr/kernel.h>
#include <zephyr/net/net_event.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/random/random.h>
#include <zephyr/sys/clock.h>

#define ZENOH_LOCATOR "tcp/10.0.0.222:7447"
#define CMD_VEL_KEYEXPR                                                        \
  "0/joy_teleop/cmd_vel/geometry_msgs::msg::dds_::TwistStamped_/"              \
  "RIHS01_5f0fcd4f81d5d06ad9b4c4c63e3ea51b82d6ae4d0558f1d475229b1121db6f64"

#define FRAME_ID "base_link"
#define LINEAR_SPEED 1.0
#define ANGULAR_SPEED 1.0

#define PUBLISH_PERIOD_MS 200
#define STATUS_REFRESH_PERIOD_MS 500
#define RECONNECT_DELAY_S 2

#define CDR_ENCAPSULATION_HEADER_BYTES 4
#define STAMP_SEC_OFFSET (CDR_ENCAPSULATION_HEADER_BYTES + 0)
#define STAMP_NANOSEC_OFFSET (CDR_ENCAPSULATION_HEADER_BYTES + 4)
#define FRAME_ID_LENGTH_OFFSET (CDR_ENCAPSULATION_HEADER_BYTES + 8)
#define FRAME_ID_OFFSET (CDR_ENCAPSULATION_HEADER_BYTES + 12)
#define TWIST_OFFSET (CDR_ENCAPSULATION_HEADER_BYTES + 24)
#define TWIST_LINEAR_X_OFFSET (TWIST_OFFSET + 0 * sizeof(double))
#define TWIST_ANGULAR_Z_OFFSET (TWIST_OFFSET + 5 * sizeof(double))
#define TWIST_STAMPED_CDR_BYTES (TWIST_OFFSET + 6 * sizeof(double))

BUILD_ASSERT(FRAME_ID_OFFSET + sizeof(FRAME_ID) <= TWIST_OFFSET);
BUILD_ASSERT((TWIST_OFFSET - CDR_ENCAPSULATION_HEADER_BYTES) % 8 == 0);

#define ATTACHMENT_GID_BYTES 16
#define ATTACHMENT_BYTES (8 + 8 + 1 + ATTACHMENT_GID_BYTES)

#define UI_THREAD_STACK_SIZE 16384
#define UI_THREAD_PRIORITY 7
#define NET_THREAD_STACK_SIZE 8192
#define NET_THREAD_PRIORITY 7

enum link_state {
  LINK_WAITING_FOR_NETWORK,
  LINK_CONNECTING,
  LINK_READY,
};

static enum link_state link_state = LINK_WAITING_FOR_NETWORK;
static z_owned_session_t session;
static z_owned_publisher_t publisher;
static int64_t sequence_number;
static uint8_t gid[ATTACHMENT_GID_BYTES];

static lv_obj_t *status_label;
static lv_timer_t *publish_timer;
static double held_linear;
static double held_angular;
static lv_style_t pad_cell_style;
static lv_style_t pad_cell_pressed_style;
static lv_style_t arrow_line_style;

#define PAD_GRID_SIZE 3
#define ARROW_POINT_COUNT 5
#define ARROW_BOX_SIZE 40
static const float arrow_base_x[ARROW_POINT_COUNT] = {0, 0, -10, 0, 10};
static const float arrow_base_y[ARROW_POINT_COUNT] = {16, -16, -6, -16, -6};
static lv_point_precise_t arrow_points[PAD_GRID_SIZE][PAD_GRID_SIZE]
                                      [ARROW_POINT_COUNT];

static int64_t epoch_nanoseconds(void) {
  struct timespec now = {0};
  sys_clock_gettime(SYS_CLOCK_REALTIME, &now);
  return (int64_t)now.tv_sec * 1000000000LL + now.tv_nsec;
}

static void encode_twist_stamped(uint8_t *out, double linear_x,
                                 double angular_z) {
  memset(out, 0, TWIST_STAMPED_CDR_BYTES);
  out[1] = 0x01; /* CDR little-endian */

  struct timespec now = {0};
  sys_clock_gettime(SYS_CLOCK_REALTIME, &now);
  int32_t stamp_sec = (int32_t)now.tv_sec;
  uint32_t stamp_nanosec = (uint32_t)now.tv_nsec;
  memcpy(out + STAMP_SEC_OFFSET, &stamp_sec, sizeof(stamp_sec));
  memcpy(out + STAMP_NANOSEC_OFFSET, &stamp_nanosec, sizeof(stamp_nanosec));

  uint32_t frame_id_length = sizeof(FRAME_ID);
  memcpy(out + FRAME_ID_LENGTH_OFFSET, &frame_id_length,
         sizeof(frame_id_length));
  memcpy(out + FRAME_ID_OFFSET, FRAME_ID, sizeof(FRAME_ID));

  memcpy(out + TWIST_LINEAR_X_OFFSET, &linear_x, sizeof(linear_x));
  memcpy(out + TWIST_ANGULAR_Z_OFFSET, &angular_z, sizeof(angular_z));
}

static void encode_attachment(uint8_t *out) {
  int64_t source_timestamp = epoch_nanoseconds();
  memcpy(out, &sequence_number, sizeof(sequence_number));
  memcpy(out + 8, &source_timestamp, sizeof(source_timestamp));
  out[16] = ATTACHMENT_GID_BYTES;
  memcpy(out + 17, gid, ATTACHMENT_GID_BYTES);
}

static void publish_command(double linear_x, double angular_z) {
  if (link_state != LINK_READY) {
    return;
  }
  sequence_number++;

  uint8_t twist_stamped[TWIST_STAMPED_CDR_BYTES];
  encode_twist_stamped(twist_stamped, linear_x, angular_z);
  uint8_t attachment_bytes[ATTACHMENT_BYTES];
  encode_attachment(attachment_bytes);

  z_owned_bytes_t payload;
  z_bytes_copy_from_buf(&payload, twist_stamped, sizeof(twist_stamped));
  z_owned_bytes_t attachment;
  z_bytes_copy_from_buf(&attachment, attachment_bytes,
                        sizeof(attachment_bytes));

  z_publisher_put_options_t options;
  z_publisher_put_options_default(&options);
  options.attachment = z_move(attachment);
  z_publisher_put(z_loan(publisher), z_move(payload), &options);
}

static const double direction_linear[PAD_GRID_SIZE][PAD_GRID_SIZE] = {
    {1.0, 1.0, 1.0},
    {0.0, 0.0, 0.0},
    {-1.0, -1.0, -1.0},
};
static const double direction_angular[PAD_GRID_SIZE][PAD_GRID_SIZE] = {
    {1.0, 0.0, -1.0},
    {1.0, 0.0, -1.0},
    {1.0, 0.0, -1.0},
};
static const int16_t arrow_rotation_degrees[PAD_GRID_SIZE][PAD_GRID_SIZE] = {
    {315, 0, 45},
    {270, 0, 90},
    {225, 180, 135},
};

static void on_publish_tick(lv_timer_t *timer) {
  ARG_UNUSED(timer);
  publish_command(held_linear, held_angular);
}

static void on_pad_event(lv_event_t *event) {
  if (lv_event_get_target(event) == lv_event_get_current_target(event)) {
    return;
  }
  uint32_t cell_index = lv_obj_get_index(lv_event_get_target_obj(event));
  unsigned int row = cell_index / PAD_GRID_SIZE;
  unsigned int column = cell_index % PAD_GRID_SIZE;

  switch (lv_event_get_code(event)) {
  case LV_EVENT_PRESSED:
    held_linear = LINEAR_SPEED * direction_linear[row][column];
    held_angular = ANGULAR_SPEED * direction_angular[row][column];
    publish_command(held_linear, held_angular);
    lv_timer_resume(publish_timer);
    break;
  default:
    lv_timer_pause(publish_timer);
    held_linear = 0.0;
    held_angular = 0.0;
    publish_command(0.0, 0.0);
  }
}

static void on_status_refresh(lv_timer_t *timer) {
  ARG_UNUSED(timer);
  static int displayed_state = -1;
  if ((int)link_state == displayed_state) {
    return;
  }
  displayed_state = (int)link_state;
  switch (link_state) {
  case LINK_WAITING_FOR_NETWORK:
    lv_label_set_text(status_label, "wifi " LV_SYMBOL_REFRESH);
    break;
  case LINK_CONNECTING:
    lv_label_set_text(status_label, "zenoh " LV_SYMBOL_REFRESH);
    break;
  case LINK_READY:
    lv_label_set_text(status_label, LV_SYMBOL_WIFI " " ZENOH_LOCATOR);
    break;
  }
}

static void build_pad(void) {
  static int32_t column_template[] = {LV_GRID_FR(1), LV_GRID_FR(1),
                                      LV_GRID_FR(1), LV_GRID_TEMPLATE_LAST};
  static int32_t row_template[] = {LV_GRID_FR(1), LV_GRID_FR(1), LV_GRID_FR(1),
                                   LV_GRID_TEMPLATE_LAST};

  lv_style_init(&pad_cell_style);
  lv_style_set_bg_color(&pad_cell_style, lv_color_hex(0x3c3836));
  lv_style_set_border_color(&pad_cell_style, lv_color_hex(0x665c54));
  lv_style_set_border_width(&pad_cell_style, 1);
  lv_style_set_radius(&pad_cell_style, 6);
  lv_style_init(&pad_cell_pressed_style);
  lv_style_set_bg_color(&pad_cell_pressed_style, lv_color_hex(0x504945));
  lv_style_set_border_color(&pad_cell_pressed_style, lv_color_hex(0xfe8019));
  lv_style_init(&arrow_line_style);
  lv_style_set_line_color(&arrow_line_style, lv_color_hex(0xebdbb2));
  lv_style_set_line_width(&arrow_line_style, 4);
  lv_style_set_line_rounded(&arrow_line_style, true);

  lv_obj_t *screen = lv_screen_active();
  lv_obj_set_style_bg_color(screen, lv_color_hex(0x282828), 0);
  lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

  status_label = lv_label_create(screen);
  lv_obj_align(status_label, LV_ALIGN_TOP_MID, 0, 8);
  lv_obj_set_style_text_color(status_label, lv_color_hex(0x928374), 0);
  lv_label_set_text(status_label, "");

  lv_obj_t *pad = lv_obj_create(screen);
  lv_obj_set_size(pad, 368, 368);
  lv_obj_align(pad, LV_ALIGN_BOTTOM_MID, 0, 0);
  lv_obj_set_style_bg_opa(pad, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(pad, 0, 0);
  lv_obj_set_style_pad_all(pad, 4, 0);
  lv_obj_set_style_pad_gap(pad, 4, 0);
  lv_obj_set_grid_dsc_array(pad, column_template, row_template);
  lv_obj_remove_flag(pad, LV_OBJ_FLAG_SCROLLABLE);

  for (unsigned int row = 0; row < PAD_GRID_SIZE; row++) {
    for (unsigned int column = 0; column < PAD_GRID_SIZE; column++) {
      lv_obj_t *button = lv_button_create(pad);
      lv_obj_set_grid_cell(button, LV_GRID_ALIGN_STRETCH, column, 1,
                           LV_GRID_ALIGN_STRETCH, row, 1);
      lv_obj_add_style(button, &pad_cell_style, 0);
      lv_obj_add_style(button, &pad_cell_pressed_style, LV_STATE_PRESSED);

      if (row == 1 && column == 1) {
        lv_obj_t *stop = lv_label_create(button);
        lv_label_set_text(stop, LV_SYMBOL_STOP);
        lv_obj_set_style_text_color(stop, lv_color_hex(0xfb4934), 0);
        lv_obj_center(stop);
      } else {
        float radians =
            (float)arrow_rotation_degrees[row][column] * 3.14159265f / 180.0f;
        float sine = sinf(radians);
        float cosine = cosf(radians);
        for (unsigned int point = 0; point < ARROW_POINT_COUNT; point++) {
          float x = arrow_base_x[point] * cosine - arrow_base_y[point] * sine;
          float y = arrow_base_x[point] * sine + arrow_base_y[point] * cosine;
          arrow_points[row][column][point].x =
              (lv_value_precise_t)(ARROW_BOX_SIZE / 2 + x);
          arrow_points[row][column][point].y =
              (lv_value_precise_t)(ARROW_BOX_SIZE / 2 + y);
        }
        lv_obj_t *arrow = lv_line_create(button);
        lv_obj_set_size(arrow, ARROW_BOX_SIZE, ARROW_BOX_SIZE);
        lv_obj_center(arrow);
        lv_line_set_points(arrow, arrow_points[row][column], ARROW_POINT_COUNT);
        lv_obj_add_style(arrow, &arrow_line_style, 0);
        lv_obj_remove_flag(arrow, LV_OBJ_FLAG_CLICKABLE);
      }

      lv_obj_add_flag(button,
                      LV_OBJ_FLAG_EVENT_BUBBLE | LV_OBJ_FLAG_PRESS_LOCK);
    }
  }

  lv_obj_add_event_cb(pad, on_pad_event, LV_EVENT_PRESSED, NULL);
  lv_obj_add_event_cb(pad, on_pad_event, LV_EVENT_RELEASED, NULL);
  lv_obj_add_event_cb(pad, on_pad_event, LV_EVENT_PRESS_LOST, NULL);

  publish_timer = lv_timer_create(on_publish_tick, PUBLISH_PERIOD_MS, NULL);
  lv_timer_pause(publish_timer);

  lv_timer_create(on_status_refresh, STATUS_REFRESH_PERIOD_MS, NULL);
}

static void wait_for_network(void) {
  struct net_if *station = net_if_get_wifi_sta();
  if (station == NULL) {
    return;
  }
  if (net_if_ipv4_get_global_addr(station, NET_ADDR_PREFERRED) != NULL) {
    return;
  }
  uint64_t raised_event;
  net_mgmt_event_wait_on_iface(station, NET_EVENT_IPV4_DHCP_BOUND,
                               &raised_event, NULL, NULL, K_FOREVER);
}

static void disable_wifi_power_save(void) {
  struct net_if *station = net_if_get_wifi_sta();
  if (station == NULL) {
    return;
  }
  struct wifi_ps_params params = {.enabled = WIFI_PS_DISABLED};
  int ret = net_mgmt(NET_REQUEST_WIFI_PS, station, &params, sizeof(params));
  if (ret < 0) {
    printk("teleop: wifi ps off failed (%d)\n", ret);
  }
}

static void teleop_net_thread(void) {
  sys_rand_get(gid, sizeof(gid));

  while (1) {
    wait_for_network();
    disable_wifi_power_save();
    link_state = LINK_CONNECTING;

    z_owned_config_t config;
    z_config_default(&config);
    zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, "client");
    zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, ZENOH_LOCATOR);
    int open_result = z_open(&session, z_move(config), NULL);
    if (open_result == 0) {
      break;
    }
    printk("teleop: z_open failed (%d), retrying\n", open_result);
    link_state = LINK_WAITING_FOR_NETWORK;
    k_sleep(K_SECONDS(RECONNECT_DELAY_S));
  }

  if (zp_start_lease_task(z_loan_mut(session), NULL) < 0) {
    printk("teleop: start_lease_task failed\n");
    return;
  }

  z_view_keyexpr_t keyexpr;
  z_view_keyexpr_from_str_unchecked(&keyexpr, CMD_VEL_KEYEXPR);
  if (z_declare_publisher(z_loan(session), &publisher, z_loan(keyexpr), NULL) <
      0) {
    printk("teleop: declare_publisher failed\n");
    return;
  }
  printk("teleop: publishing on %s\n", CMD_VEL_KEYEXPR);
  link_state = LINK_READY;
}

static void teleop_ui_thread(void) {
  while (!lv_is_initialized()) {
    k_sleep(K_MSEC(50));
  }

  build_pad();

  lv_timer_handler();
  display_blanking_off(DEVICE_DT_GET(DT_CHOSEN(zephyr_display)));

  while (1) {
    uint32_t sleep_ms = lv_timer_handler();
    k_sleep(K_MSEC(CLAMP(sleep_ms, 5, 100)));
  }
}

K_THREAD_DEFINE(teleop_ui, UI_THREAD_STACK_SIZE, teleop_ui_thread, NULL, NULL,
                NULL, UI_THREAD_PRIORITY, 0, 0);
K_THREAD_DEFINE(teleop_net, NET_THREAD_STACK_SIZE, teleop_net_thread, NULL,
                NULL, NULL, NET_THREAD_PRIORITY, 0, 0);
