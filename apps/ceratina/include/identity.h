#pragma once

#include <config.h>
#include <stddef.h>

struct DeviceIdentitySnapshot {
  char hostname[config::shell::HOSTNAME_SIZE + 1];
  char username[64];
  char device_name[64];
  char api_key[64];
  bool provisioned;
};

struct IdentityStringQuery {
  char *buffer;
  size_t capacity;
  bool ok;
};

namespace services::identity {

void initialize();
const char *access_hostname();
bool configure_hostname(const char *hostname);

bool access_username(IdentityStringQuery *query);
bool configure_username(const char *value);

bool access_device_name(IdentityStringQuery *query);
bool configureDeviceName(const char *value);

bool accessAPIKey(IdentityStringQuery *query);
bool configureAPIKey(const char *value);

bool accessSnapshot(DeviceIdentitySnapshot *snapshot);

#ifdef PIO_UNIT_TESTING
void test();
#endif

} // namespace services::identity
