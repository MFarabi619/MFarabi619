#include <identity.h>

#include "../boot/provisioning.h"
#include <networking/wifi.h>

#include <Arduino.h>
#include <Preferences.h>
#include <string.h>

namespace {

static char hostname_data[config::shell::HOSTNAME_SIZE + 1] = {};
static bool hostname_initialized = false;

static bool get_provisioning_string(const char *key,
                                    IdentityStringQuery *query) {
  if (!query || !query->buffer || query->capacity == 0)
    return false;
  Preferences prefs;
  if (!prefs.begin(config::provisioning::NVS_NAMESPACE, true))
    return false;
  bool ok = prefs.getString(key, query->buffer, query->capacity) > 0;
  prefs.end();
  query->ok = ok;
  return ok;
}

static bool set_provisioning_string(const char *key, const char *value) {
  Preferences prefs;
  if (!prefs.begin(config::provisioning::NVS_NAMESPACE, false))
    return false;
  prefs.putString(key, value ? value : "");
  prefs.end();
  return true;
}

static void ensure_hostname(void) {
  if (hostname_initialized)
    return;
  strncpy(hostname_data, config::HOSTNAME, config::shell::HOSTNAME_SIZE);
  hostname_data[config::shell::HOSTNAME_SIZE] = '\0';
  hostname_initialized = true;
}

} // namespace

void services::identity::initialize() { ensure_hostname(); }

const char *services::identity::access_hostname() {
  ensure_hostname();
  return hostname_data;
}

bool services::identity::configure_hostname(const char *hostname) {
  ensure_hostname();
  if (!hostname)
    return false;

  strncpy(hostname_data, hostname, config::shell::HOSTNAME_SIZE);
  hostname_data[config::shell::HOSTNAME_SIZE] = '\0';
  networking::wifi::configure_hostname(hostname_data);
  return true;
}

bool services::identity::access_username(IdentityStringQuery *query) {
  return get_provisioning_string("username", query);
}

bool services::identity::configure_username(const char *value) {
  return set_provisioning_string("username", value);
}

bool services::identity::access_device_name(IdentityStringQuery *query) {
  return get_provisioning_string("device_name", query);
}

bool services::identity::configureDeviceName(const char *value) {
  return set_provisioning_string("device_name", value);
}

bool services::identity::accessAPIKey(IdentityStringQuery *query) {
  return get_provisioning_string("api_key", query);
}

bool services::identity::configureAPIKey(const char *value) {
  return set_provisioning_string("api_key", value);
}

bool services::identity::accessSnapshot(DeviceIdentitySnapshot *snapshot) {
  if (!snapshot)
    return false;
  memset(snapshot, 0, sizeof(*snapshot));

  strncpy(snapshot->hostname, services::identity::access_hostname(),
          sizeof(snapshot->hostname) - 1);
  IdentityStringQuery username_query = {
      .buffer = snapshot->username,
      .capacity = sizeof(snapshot->username),
      .ok = false,
  };
  services::identity::access_username(&username_query);
  IdentityStringQuery device_name_query = {
      .buffer = snapshot->device_name,
      .capacity = sizeof(snapshot->device_name),
      .ok = false,
  };
  if (!services::identity::access_device_name(&device_name_query)) {
    strncpy(snapshot->device_name, config::HOSTNAME,
            sizeof(snapshot->device_name) - 1);
  }
  IdentityStringQuery api_key_query = {
      .buffer = snapshot->api_key,
      .capacity = sizeof(snapshot->api_key),
      .ok = false,
  };
  services::identity::accessAPIKey(&api_key_query);
  snapshot->provisioned = boot::provisioning::isProvisioned();
  return true;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_identity_hostname_default(void) {
  GIVEN("a freshly booted device");
  THEN("hostname matches config::HOSTNAME");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(
      config::HOSTNAME, services::identity::access_hostname(),
      "device: boot-time hostname should match config::HOSTNAME");
}

static void test_identity_hostname_truncation(void) {
  WHEN("a hostname longer than HOSTNAME_SIZE is set");

  char long_name[config::shell::HOSTNAME_SIZE + 20];
  memset(long_name, 'A', sizeof(long_name) - 1);
  long_name[sizeof(long_name) - 1] = '\0';

  services::identity::configure_hostname(long_name);
  size_t result_len = strlen(services::identity::access_hostname());
  TEST_ASSERT_LESS_OR_EQUAL_UINT32_MESSAGE(
      config::shell::HOSTNAME_SIZE, result_len,
      "device: hostname exceeds config::shell::HOSTNAME_SIZE after truncation");

  services::identity::configure_hostname(config::HOSTNAME);
}

static void test_identity_username_roundtrip(void) {
  WHEN("a username is stored and read back");
  TEST_ASSERT_TRUE_MESSAGE(services::identity::configure_username("alice"),
                           "device: username should be writable");

  char username[64] = {0};
  IdentityStringQuery query = {
      .buffer = username,
      .capacity = sizeof(username),
      .ok = false,
  };
  TEST_ASSERT_TRUE_MESSAGE(services::identity::access_username(&query),
                           "device: username should be readable");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("alice", username,
                                   "device: username mismatch after roundtrip");
}

static void test_identity_device_name_roundtrip(void) {
  WHEN("a device name is stored and read back");
  TEST_ASSERT_TRUE_MESSAGE(
      services::identity::configureDeviceName("ceratina-lab"),
      "device: device_name should be writable");

  char device_name[64] = {0};
  IdentityStringQuery query = {
      .buffer = device_name,
      .capacity = sizeof(device_name),
      .ok = false,
  };
  TEST_ASSERT_TRUE_MESSAGE(services::identity::access_device_name(&query),
                           "device: device_name should be readable");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(
      "ceratina-lab", device_name,
      "device: device_name mismatch after roundtrip");
}

static void test_identity_api_key_roundtrip(void) {
  WHEN("an API key is stored and read back");
  TEST_ASSERT_TRUE_MESSAGE(services::identity::configureAPIKey("secret-key"),
                           "device: api_key should be writable");

  char api_key[64] = {0};
  IdentityStringQuery query = {
      .buffer = api_key,
      .capacity = sizeof(api_key),
      .ok = false,
  };
  TEST_ASSERT_TRUE_MESSAGE(services::identity::accessAPIKey(&query),
                           "device: api_key should be readable");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("secret-key", api_key,
                                   "device: api_key mismatch after roundtrip");
}

void services::identity::test() {
  RUN_TEST(test_identity_hostname_default);
  RUN_TEST(test_identity_hostname_truncation);
  RUN_TEST(test_identity_username_roundtrip);
  RUN_TEST(test_identity_device_name_roundtrip);
  RUN_TEST(test_identity_api_key_roundtrip);
}

#endif
