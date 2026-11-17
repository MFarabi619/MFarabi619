#include <errno.h>
#include <string.h>

#include <zephyr/init.h>

#include "zenoh_locator.h"

#define LOCATOR_MAX_LEN 64

static char locator[LOCATOR_MAX_LEN] = CONFIG_ZENOH_LOCATOR_DEFAULT;

const char *zenoh_locator_get(void) { return locator; }

int zenoh_locator_open_session(z_owned_session_t *session) {
  z_owned_config_t config;
  z_config_default(&config);
  zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, Z_CONFIG_MODE_CLIENT);
  zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, locator);
  return z_open(session, z_move(config), NULL);
}

#ifdef CONFIG_SETTINGS

#include <zephyr/settings/settings.h>

int zenoh_locator_set(const char *new_locator) {
  size_t len = strnlen(new_locator, LOCATOR_MAX_LEN - 1);

  memcpy(locator, new_locator, len);
  locator[len] = '\0';
  return settings_save_one("zenoh/locator", locator, len);
}

static int zenoh_locator_init(void) {
  int rc = settings_subsys_init();

  if (rc == 0) {
    ssize_t len = settings_load_one("zenoh/locator", locator, sizeof(locator) - 1);
    if (len > 0) {
      locator[len] = '\0';
    }
  }
  return rc;
}

SYS_INIT(zenoh_locator_init, APPLICATION, 90);

#endif /* CONFIG_SETTINGS */
