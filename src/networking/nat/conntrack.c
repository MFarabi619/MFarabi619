#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/net_ip.h>
#include <zephyr/sys/bitarray.h>
#include <zephyr/sys/byteorder.h>

#include "iram.h"
#include "conntrack.h"

LOG_MODULE_REGISTER(conntrack, LOG_LEVEL_INF);

#define NAT_PORT_RANGE_START 49152u
#define NAT_PORT_RANGE_END   65535u
#define NAT_PORT_RANGE_COUNT (NAT_PORT_RANGE_END - NAT_PORT_RANGE_START + 1u)

#define NAT_IDLE_TIMEOUT_UDP_MS 120000
#define NAT_IDLE_TIMEOUT_TCP_MS 300000

#define NAT_HASH_BUCKETS    64
#define NAT_HASH_PER_BUCKET 8

#define MAPPING_HASH_BUCKETS    16
#define MAPPING_HASH_PER_BUCKET 4

#define FREE_LIST_END 0xFFFFu

static int64_t idle_timeout_for_proto(uint8_t proto)
{
	return (proto == IPPROTO_TCP) ? NAT_IDLE_TIMEOUT_TCP_MS : NAT_IDLE_TIMEOUT_UDP_MS;
}

static struct ConntrackEntry table[CONNTRACK_SIZE];
static struct ConntrackEntry *outbound_buckets[NAT_HASH_BUCKETS][NAT_HASH_PER_BUCKET];
static uint16_t free_head = FREE_LIST_END;
static struct k_spinlock table_lock;

static struct NatMapping mapping_table[MAPPING_SIZE];
static struct NatMapping *mapping_fwd_buckets[MAPPING_HASH_BUCKETS][MAPPING_HASH_PER_BUCKET];
static struct NatMapping *mapping_inv_buckets[MAPPING_HASH_BUCKETS][MAPPING_HASH_PER_BUCKET];
static uint16_t mapping_free_head = FREE_LIST_END;

SYS_BITARRAY_DEFINE_STATIC(tcp_ports_used, NAT_PORT_RANGE_COUNT);
SYS_BITARRAY_DEFINE_STATIC(udp_ports_used, NAT_PORT_RANGE_COUNT);

static sys_bitarray_t *port_bitmap_for(uint8_t proto)
{
	return (proto == IPPROTO_TCP) ? &tcp_ports_used : &udp_ports_used;
}

static void release_nat_port_unlocked(uint8_t proto, uint16_t nat_port_be)
{
	uint16_t host = sys_be16_to_cpu(nat_port_be);

	if (host < NAT_PORT_RANGE_START || host > NAT_PORT_RANGE_END) {
		return;
	}
	sys_bitarray_clear_bit(port_bitmap_for(proto), host - NAT_PORT_RANGE_START);
}

static IRAM_HOT uint8_t hash_outbound(uint8_t proto, uint32_t client_ip, uint16_t client_port,
				      uint32_t remote_ip, uint16_t remote_port)
{
	uint32_t hash = client_ip ^ remote_ip;

	hash ^= ((uint32_t)client_port << 16) | remote_port;
	hash ^= (uint32_t)proto * 0x9E3779B9u;
	hash ^= hash >> 16;
	hash ^= hash >> 8;
	return hash & (NAT_HASH_BUCKETS - 1);
}

static IRAM_HOT uint8_t mapping_hash_fwd(uint8_t proto, uint32_t client_ip, uint16_t client_port)
{
	uint32_t hash = client_ip;

	hash ^= (uint32_t)client_port << 16;
	hash ^= (uint32_t)proto * 0x9E3779B9u;
	hash ^= hash >> 16;
	hash ^= hash >> 8;
	return hash & (MAPPING_HASH_BUCKETS - 1);
}

static IRAM_HOT uint8_t mapping_hash_inv(uint8_t proto, uint16_t nat_port_be)
{
	uint32_t hash = (uint32_t)nat_port_be * 0x9E3779B9u;

	hash ^= (uint32_t)proto * 0x85EBCA6Bu;
	hash ^= hash >> 16;
	return hash & (MAPPING_HASH_BUCKETS - 1);
}

static void push_free_unlocked(struct ConntrackEntry *entry)
{
	entry->next_free = free_head;
	free_head = (uint16_t)(entry - table);
}

static void mapping_push_free_unlocked(struct NatMapping *m)
{
	m->next_free = mapping_free_head;
	mapping_free_head = (uint16_t)(m - mapping_table);
}

static void mapping_remove_from_buckets_unlocked(struct NatMapping *m)
{
	mapping_fwd_buckets[m->fwd_bucket][m->fwd_slot] = NULL;
	mapping_inv_buckets[m->inv_bucket][m->inv_slot] = NULL;
}

static void mapping_evict_unlocked(struct NatMapping *m)
{
	release_nat_port_unlocked(m->proto, m->nat_port);
	mapping_remove_from_buckets_unlocked(m);
	m->is_in_use = false;
	mapping_push_free_unlocked(m);
}

static void fully_evict_unlocked(struct ConntrackEntry *entry)
{
	outbound_buckets[entry->outbound_bucket][entry->outbound_slot] = NULL;

	if (entry->mapping != NULL) {
		entry->mapping->refcount--;
		if (entry->mapping->refcount == 0) {
			mapping_evict_unlocked(entry->mapping);
		}
		entry->mapping = NULL;
	}

	entry->is_in_use = false;
	push_free_unlocked(entry);
}

void conntrackInitialize(void)
{
	k_spinlock_key_t key = k_spin_lock(&table_lock);

	memset(table, 0, sizeof(table));
	memset(outbound_buckets, 0, sizeof(outbound_buckets));
	memset(mapping_table, 0, sizeof(mapping_table));
	memset(mapping_fwd_buckets, 0, sizeof(mapping_fwd_buckets));
	memset(mapping_inv_buckets, 0, sizeof(mapping_inv_buckets));

	for (uint16_t index = 0; index < CONNTRACK_SIZE - 1; index++) {
		table[index].next_free = index + 1;
	}
	table[CONNTRACK_SIZE - 1].next_free = FREE_LIST_END;
	free_head = 0;

	for (uint16_t index = 0; index < MAPPING_SIZE - 1; index++) {
		mapping_table[index].next_free = index + 1;
	}
	mapping_table[MAPPING_SIZE - 1].next_free = FREE_LIST_END;
	mapping_free_head = 0;

	k_spin_unlock(&table_lock, key);
}

static IRAM_HOT struct ConntrackEntry *find_outbound_unlocked(uint8_t proto, uint32_t client_ip,
							       uint16_t client_port,
							       uint32_t remote_ip,
							       uint16_t remote_port)
{
	uint8_t bucket = hash_outbound(proto, client_ip, client_port, remote_ip, remote_port);

	for (int index = 0; index < NAT_HASH_PER_BUCKET; index++) {
		struct ConntrackEntry *entry = outbound_buckets[bucket][index];

		if (entry == NULL) {
			continue;
		}
		if (entry->proto == proto && entry->client_ip == client_ip &&
		    entry->client_port == client_port && entry->remote_ip == remote_ip &&
		    entry->remote_port == remote_port) {
			return entry;
		}
	}
	return NULL;
}

static IRAM_HOT struct NatMapping *find_mapping_fwd_unlocked(uint8_t proto, uint32_t client_ip,
							     uint16_t client_port)
{
	uint8_t bucket = mapping_hash_fwd(proto, client_ip, client_port);

	for (int index = 0; index < MAPPING_HASH_PER_BUCKET; index++) {
		struct NatMapping *m = mapping_fwd_buckets[bucket][index];

		if (m == NULL) {
			continue;
		}
		if (m->proto == proto && m->client_ip == client_ip &&
		    m->client_port == client_port) {
			return m;
		}
	}
	return NULL;
}

static IRAM_HOT struct NatMapping *find_mapping_inv_unlocked(uint8_t proto, uint16_t nat_port_be)
{
	uint8_t bucket = mapping_hash_inv(proto, nat_port_be);

	for (int index = 0; index < MAPPING_HASH_PER_BUCKET; index++) {
		struct NatMapping *m = mapping_inv_buckets[bucket][index];

		if (m != NULL && m->proto == proto && m->nat_port == nat_port_be) {
			return m;
		}
	}
	return NULL;
}

static struct ConntrackEntry *allocate_entry_unlocked(int64_t now_ms)
{
	if (free_head != FREE_LIST_END) {
		uint16_t index = free_head;
		struct ConntrackEntry *entry = &table[index];

		free_head = entry->next_free;
		return entry;
	}

	int64_t oldest_age = -1;
	struct ConntrackEntry *oldest = NULL;

	for (int index = 0; index < CONNTRACK_SIZE; index++) {
		struct ConntrackEntry *entry = &table[index];

		if (!entry->is_in_use) {
			continue;
		}
		int64_t age = now_ms - entry->last_seen_ms;

		if (age > idle_timeout_for_proto(entry->proto) && age > oldest_age) {
			oldest_age = age;
			oldest = entry;
		}
	}
	if (oldest == NULL) {
		return NULL;
	}
	fully_evict_unlocked(oldest);

	uint16_t index = free_head;
	struct ConntrackEntry *entry = &table[index];

	free_head = entry->next_free;
	return entry;
}

static uint16_t allocate_nat_port_unlocked(uint8_t proto)
{
	size_t offset;

	if (sys_bitarray_alloc(port_bitmap_for(proto), 1, &offset) != 0) {
		return 0;
	}
	return sys_cpu_to_be16(NAT_PORT_RANGE_START + (uint16_t)offset);
}

static uint8_t insert_outbound_unlocked(struct ConntrackEntry *entry, uint8_t bucket)
{
	int lru_index = 0;
	int64_t lru_seen = INT64_MAX;

	for (int index = 0; index < NAT_HASH_PER_BUCKET; index++) {
		if (outbound_buckets[bucket][index] == NULL) {
			outbound_buckets[bucket][index] = entry;
			return (uint8_t)index;
		}
		if (outbound_buckets[bucket][index]->last_seen_ms < lru_seen) {
			lru_seen = outbound_buckets[bucket][index]->last_seen_ms;
			lru_index = index;
		}
	}
	fully_evict_unlocked(outbound_buckets[bucket][lru_index]);
	outbound_buckets[bucket][lru_index] = entry;
	return (uint8_t)lru_index;
}

static uint8_t mapping_insert_fwd_unlocked(struct NatMapping *m, uint8_t bucket)
{
	for (int index = 0; index < MAPPING_HASH_PER_BUCKET; index++) {
		if (mapping_fwd_buckets[bucket][index] == NULL) {
			mapping_fwd_buckets[bucket][index] = m;
			return (uint8_t)index;
		}
	}
	return MAPPING_HASH_PER_BUCKET;
}

static uint8_t mapping_insert_inv_unlocked(struct NatMapping *m, uint8_t bucket)
{
	for (int index = 0; index < MAPPING_HASH_PER_BUCKET; index++) {
		if (mapping_inv_buckets[bucket][index] == NULL) {
			mapping_inv_buckets[bucket][index] = m;
			return (uint8_t)index;
		}
	}
	return MAPPING_HASH_PER_BUCKET;
}

static struct NatMapping *mapping_alloc_unlocked(uint8_t proto, uint32_t client_ip,
						 uint16_t client_port, uint16_t nat_port_be)
{
	if (mapping_free_head == FREE_LIST_END) {
		LOG_WRN("mapping table full");
		return NULL;
	}
	uint8_t fwd_bucket = mapping_hash_fwd(proto, client_ip, client_port);
	uint8_t inv_bucket = mapping_hash_inv(proto, nat_port_be);
	uint16_t index = mapping_free_head;
	struct NatMapping *m = &mapping_table[index];

	uint8_t fwd_slot = mapping_insert_fwd_unlocked(m, fwd_bucket);

	if (fwd_slot == MAPPING_HASH_PER_BUCKET) {
		LOG_WRN("mapping fwd bucket full");
		return NULL;
	}
	uint8_t inv_slot = mapping_insert_inv_unlocked(m, inv_bucket);

	if (inv_slot == MAPPING_HASH_PER_BUCKET) {
		mapping_fwd_buckets[fwd_bucket][fwd_slot] = NULL;
		LOG_WRN("mapping inv bucket full");
		return NULL;
	}

	mapping_free_head = m->next_free;
	m->client_ip = client_ip;
	m->client_port = client_port;
	m->proto = proto;
	m->nat_port = nat_port_be;
	m->refcount = 0;
	m->is_in_use = true;
	m->fwd_bucket = fwd_bucket;
	m->fwd_slot = fwd_slot;
	m->inv_bucket = inv_bucket;
	m->inv_slot = inv_slot;
	return m;
}

IRAM_HOT struct ConntrackEntry *conntrackLookupOutbound(uint8_t proto, uint32_t client_ip,
							   uint16_t client_port, uint32_t remote_ip,
							   uint16_t remote_port)
{
	k_spinlock_key_t key = k_spin_lock(&table_lock);
	int64_t now = k_uptime_get();

	struct ConntrackEntry *entry =
		find_outbound_unlocked(proto, client_ip, client_port, remote_ip, remote_port);
	if (entry != NULL) {
		entry->last_seen_ms = now;
		k_spin_unlock(&table_lock, key);
		return entry;
	}

	entry = allocate_entry_unlocked(now);
	if (entry == NULL) {
		k_spin_unlock(&table_lock, key);
		LOG_WRN("table full, dropping new flow");
		return NULL;
	}

	uint16_t allocated_port_be;
	struct NatMapping *mapping = NULL;

	if (proto == IPPROTO_ICMP) {
		allocated_port_be = client_port;
	} else {
		mapping = find_mapping_fwd_unlocked(proto, client_ip, client_port);
		if (mapping == NULL) {
			allocated_port_be = allocate_nat_port_unlocked(proto);
			if (allocated_port_be == 0) {
				push_free_unlocked(entry);
				k_spin_unlock(&table_lock, key);
				LOG_WRN("NAT port pool exhausted");
				return NULL;
			}
			mapping = mapping_alloc_unlocked(proto, client_ip, client_port,
							 allocated_port_be);
			if (mapping == NULL) {
				release_nat_port_unlocked(proto, allocated_port_be);
				push_free_unlocked(entry);
				k_spin_unlock(&table_lock, key);
				return NULL;
			}
		} else {
			allocated_port_be = mapping->nat_port;
		}
		mapping->refcount++;
	}

	entry->client_ip = client_ip;
	entry->client_port = client_port;
	entry->remote_ip = remote_ip;
	entry->remote_port = remote_port;
	entry->nat_port = allocated_port_be;
	entry->proto = proto;
	entry->flags = 0;
	entry->last_seen_ms = now;
	entry->mapping = mapping;
	entry->is_in_use = true;

	uint8_t ob = hash_outbound(proto, client_ip, client_port, remote_ip, remote_port);

	entry->outbound_bucket = ob;
	entry->outbound_slot = insert_outbound_unlocked(entry, ob);

	LOG_DBG("new flow: proto=%u client_port=%u remote_port=%u nat_port=%u", proto,
		sys_be16_to_cpu(client_port), sys_be16_to_cpu(remote_port),
		sys_be16_to_cpu(allocated_port_be));

	k_spin_unlock(&table_lock, key);
	return entry;
}

IRAM_HOT struct ConntrackEntry *conntrackLookupInbound(uint8_t proto, uint16_t nat_port_be,
						       uint32_t remote_ip, uint16_t remote_port)
{
	k_spinlock_key_t key = k_spin_lock(&table_lock);
	struct ConntrackEntry *result = NULL;

	if (proto == IPPROTO_ICMP) {
		for (int index = 0; index < CONNTRACK_SIZE; index++) {
			struct ConntrackEntry *entry = &table[index];

			if (entry->is_in_use && entry->proto == IPPROTO_ICMP &&
			    entry->nat_port == nat_port_be) {
				entry->last_seen_ms = k_uptime_get();
				result = entry;
				break;
			}
		}
		k_spin_unlock(&table_lock, key);
		return result;
	}

	struct NatMapping *mapping = find_mapping_inv_unlocked(proto, nat_port_be);

	if (mapping != NULL) {
		result = find_outbound_unlocked(proto, mapping->client_ip, mapping->client_port,
						remote_ip, remote_port);
		if (result != NULL) {
			result->last_seen_ms = k_uptime_get();
		}
	}
	k_spin_unlock(&table_lock, key);
	return result;
}

void conntrackReapIdle(int64_t now_ms)
{
	uint16_t evict_indices[CONNTRACK_SIZE];
	size_t evict_count = 0;

	k_spinlock_key_t key = k_spin_lock(&table_lock);

	for (int index = 0; index < CONNTRACK_SIZE; index++) {
		const struct ConntrackEntry *entry = &table[index];

		if (entry->is_in_use &&
		    (now_ms - entry->last_seen_ms) > idle_timeout_for_proto(entry->proto)) {
			evict_indices[evict_count++] = (uint16_t)index;
		}
	}
	k_spin_unlock(&table_lock, key);

	size_t reaped = 0;

	for (size_t slot = 0; slot < evict_count; slot++) {
		key = k_spin_lock(&table_lock);
		struct ConntrackEntry *entry = &table[evict_indices[slot]];

		if (entry->is_in_use &&
		    (now_ms - entry->last_seen_ms) > idle_timeout_for_proto(entry->proto)) {
			fully_evict_unlocked(entry);
			reaped++;
		}
		k_spin_unlock(&table_lock, key);
	}

	if (reaped > 0) {
		LOG_DBG("reaped %zu idle entries", reaped);
	}
}
