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
const char *accessHostname();
bool configureHostname(const char *hostname);

bool accessUsername(IdentityStringQuery *query);
bool configureUsername(const char *value);

bool accessDeviceName(IdentityStringQuery *query);
bool configureDeviceName(const char *value);

bool accessAPIKey(IdentityStringQuery *query);
bool configureAPIKey(const char *value);

bool accessSnapshot(DeviceIdentitySnapshot *snapshot);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

