/* Plain-function seam over zenoh-pico for Rust callers: z_move/z_loan and
 * friends are macros, unreachable through bindgen. */

#include <zenoh-pico.h>

#include "teleop_zenoh.h"

void teleop_zenoh_on_matching_status(bool matching);

static z_owned_session_t session;
static z_owned_publisher_t publisher;

static void forward_matching_status(const z_matching_status_t *status,
                                    void *context) {
  (void)context;
  teleop_zenoh_on_matching_status(status->matching);
}

int teleop_zenoh_open(const char *locator) {
  z_owned_config_t config;
  z_config_default(&config);
  zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, "client");
  zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, locator);

  /* No transport-events listener here: z_declare_background_transport_events_listener
   * crashes in the bumped zenoh-pico (commit 6b009cd0). Its connectivity intmap insert
   * calls a garbage hash-function pointer (fault PC 0xaa..). That listener only fed the
   * on-screen link indicator; publishing is unaffected. Restore once upstream is fixed. */
  return z_open(&session, z_move(config), NULL);
}

void teleop_zenoh_close(void) {
  z_drop(z_move(publisher));
  z_drop(z_move(session));
}

int teleop_zenoh_declare_publisher(const char *keyexpr) {
  z_view_keyexpr_t view;
  z_view_keyexpr_from_str_unchecked(&view, keyexpr);
  int result = z_declare_publisher(z_loan(session), &publisher, z_loan(view),
                                   NULL);
  if (result != 0) {
    return result;
  }

  z_owned_closure_matching_status_t matching;
  z_closure_matching_status(&matching, forward_matching_status, NULL, NULL);
  result = z_publisher_declare_background_matching_listener(z_loan(publisher),
                                                            z_move(matching));
  if (result != 0) {
    z_drop(z_move(publisher));
  }
  return result;
}

int teleop_zenoh_publish(const uint8_t *payload, size_t payload_length,
                         const uint8_t *attachment, size_t attachment_length) {
  z_owned_bytes_t payload_bytes;
  z_bytes_copy_from_buf(&payload_bytes, payload, payload_length);
  z_owned_bytes_t attachment_bytes;
  z_bytes_copy_from_buf(&attachment_bytes, attachment, attachment_length);

  z_publisher_put_options_t options;
  z_publisher_put_options_default(&options);
  options.attachment = z_move(attachment_bytes);
  return z_publisher_put(z_loan(publisher), z_move(payload_bytes), &options);
}
