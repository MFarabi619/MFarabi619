/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CONNTRACK_H_
#define CONNTRACK_H_

#include <stdbool.h>
#include <stdint.h>

#define CONNTRACK_SIZE 128
#define MAPPING_SIZE 32

struct NatMapping {
	uint32_t client_ip;
	uint16_t client_port;
	uint8_t  proto;
	uint16_t nat_port;
	uint8_t  refcount;
	bool     is_in_use;
	uint8_t  fwd_bucket;
	uint8_t  fwd_slot;
	uint8_t  inv_bucket;
	uint8_t  inv_slot;
	uint16_t next_free;
};

struct ConntrackEntry {
	uint32_t client_ip;
	uint16_t client_port;
	uint16_t nat_port;
	uint32_t remote_ip;
	uint16_t remote_port;
	uint8_t proto;
	uint8_t flags;
	int64_t last_seen_ms;
	struct NatMapping *mapping;
	uint16_t next_free;
	uint8_t outbound_bucket;
	uint8_t outbound_slot;
	bool is_in_use;
};

void conntrackInitialize(void);

struct ConntrackEntry *conntrackLookupOutbound(uint8_t proto, uint32_t client_ip,
						  uint16_t client_port, uint32_t remote_ip,
						  uint16_t remote_port);

struct ConntrackEntry *conntrackLookupInbound(uint8_t proto, uint16_t nat_port_be,
					      uint32_t remote_ip, uint16_t remote_port);

void conntrackReapIdle(int64_t now_ms);

#endif
