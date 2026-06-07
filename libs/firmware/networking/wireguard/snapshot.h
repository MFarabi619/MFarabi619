/*
 * Copyright (c) 2026 Apidae Systems
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include <zephyr/net/wireguard.h>

#define WG_PUBLIC_KEY_B64_SIZE  45
#define WG_ENDPOINT_STR_SIZE    24
#define WG_ALLOWED_CIDR_SIZE    20

struct wg_peer_snapshot {
	bool valid;
	int32_t id;
	int32_t iface_index;
	char public_key_b64[WG_PUBLIC_KEY_B64_SIZE];
	char endpoint[WG_ENDPOINT_STR_SIZE];
	char allowed_cidr[WG_ALLOWED_CIDR_SIZE];
	int32_t keepalive_seconds;
	uint32_t last_handshake_age_sec;
	uint32_t last_tx_age_sec;
	uint32_t last_rx_age_sec;
};

struct wg_snapshot {
	bool iface_up;
	char local_public_key_b64[WG_PUBLIC_KEY_B64_SIZE];
	uint8_t peer_count;
	struct wg_peer_snapshot peers[CONFIG_WIREGUARD_MAX_PEER];
};
