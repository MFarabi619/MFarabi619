/* Plain-function seam over zenoh-pico for Rust callers: z_move/z_loan and
 * friends are macros, unreachable through bindgen. */

#include <zenoh-pico.h>

#include "teleop_zenoh.h"

static z_owned_session_t session;
static z_owned_publisher_t publisher;

int teleop_zenoh_open(const char *locator) {
  z_owned_config_t config;
  z_config_default(&config);
  zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, "client");
  zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, locator);
  return z_open(&session, z_move(config), NULL);
}

void teleop_zenoh_close(void) { z_drop(z_move(session)); }

int teleop_zenoh_declare_publisher(const char *keyexpr) {
  z_view_keyexpr_t view;
  z_view_keyexpr_from_str_unchecked(&view, keyexpr);
  return z_declare_publisher(z_loan(session), &publisher, z_loan(view), NULL);
}

void teleop_zenoh_publish(const uint8_t *payload, size_t payload_length,
                          const uint8_t *attachment,
                          size_t attachment_length) {
  z_owned_bytes_t payload_bytes;
  z_bytes_copy_from_buf(&payload_bytes, payload, payload_length);
  z_owned_bytes_t attachment_bytes;
  z_bytes_copy_from_buf(&attachment_bytes, attachment, attachment_length);

  z_publisher_put_options_t options;
  z_publisher_put_options_default(&options);
  options.attachment = z_move(attachment_bytes);
  z_publisher_put(z_loan(publisher), z_move(payload_bytes), &options);
}
