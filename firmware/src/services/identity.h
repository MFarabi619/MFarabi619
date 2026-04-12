#ifndef SERVICES_IDENTITY_H
#define SERVICES_IDENTITY_H

#include "../config.h"
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

void initialize() noexcept;
const char *accessHostname() noexcept;
bool configureHostname(const char *hostname) noexcept;

bool accessUsername(IdentityStringQuery *query) noexcept;
bool configureUsername(const char *value) noexcept;

bool accessDeviceName(IdentityStringQuery *query) noexcept;
bool configureDeviceName(const char *value) noexcept;

bool accessAPIKey(IdentityStringQuery *query) noexcept;
bool configureAPIKey(const char *value) noexcept;

bool accessSnapshot(DeviceIdentitySnapshot *snapshot) noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif
