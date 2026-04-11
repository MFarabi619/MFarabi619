#pragma once

#include <stddef.h>

void provisioning_start(void);
bool provisioning_is_provisioned(void);
void provisioning_reset(void);

bool provisioning_get_username(char *buf, size_t len);
bool provisioning_get_api_key(char *buf, size_t len);
bool provisioning_get_device_name(char *buf, size_t len);

void provisioning_run_tests(void);
