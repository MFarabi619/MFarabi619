#pragma once

#include <stddef.h>
#include <stdint.h>

int teleop_zenoh_open(const char *locator);
void teleop_zenoh_close(void);
int teleop_zenoh_declare_publisher(const char *keyexpr);
int teleop_zenoh_publish(const uint8_t *payload, size_t payload_length,
			 const uint8_t *attachment, size_t attachment_length);
