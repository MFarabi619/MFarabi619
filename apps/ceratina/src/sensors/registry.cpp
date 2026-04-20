#include "registry.h"
#include <string.h>

namespace {

constexpr uint8_t MAX_ENTRIES = 12;
constexpr uint8_t MAX_INSTANCES = 8;
constexpr size_t MAX_DATA_SIZE = 48;

struct Slot {
    SensorEntry entry;
    alignas(8) uint8_t snapshots[MAX_INSTANCES][MAX_DATA_SIZE];
    bool validity[MAX_INSTANCES];
};

Slot slots[MAX_ENTRIES] = {};
uint8_t count = 0;

Slot *findSlot(SensorKind kind) {
    for (uint8_t i = 0; i < count; i++) {
        if (slots[i].entry.kind == kind) return &slots[i];
    }
    return nullptr;
}

}

void sensors::registry::add(const SensorEntry &entry) {
    if (findSlot(entry.kind)) return;
    if (count >= MAX_ENTRIES) return;
    slots[count].entry = entry;
    memset(slots[count].snapshots, 0, sizeof(slots[count].snapshots));
    memset(slots[count].validity, 0, sizeof(slots[count].validity));
    count++;
}

void sensors::registry::pollAll() {
    for (uint8_t i = 0; i < count; i++) {
        uint8_t n = slots[i].entry.instanceCount();
        for (uint8_t j = 0; j < n && j < MAX_INSTANCES; j++) {
            slots[i].validity[j] = slots[i].entry.poll(
                j, slots[i].snapshots[j], slots[i].entry.data_size);
        }
    }
}

bool sensors::registry::isAvailable(SensorKind kind) {
    Slot *s = findSlot(kind);
    return s && s->entry.isAvailable();
}

uint8_t sensors::registry::instanceCount(SensorKind kind) {
    Slot *s = findSlot(kind);
    return s ? s->entry.instanceCount() : 0;
}

const void *sensors::registry::latest(SensorKind kind, uint8_t index) {
    Slot *s = findSlot(kind);
    if (!s || index >= MAX_INSTANCES) return nullptr;
    return s->snapshots[index];
}

bool sensors::registry::valid(SensorKind kind, uint8_t index) {
    Slot *s = findSlot(kind);
    if (!s || index >= MAX_INSTANCES) return false;
    return s->validity[index];
}

uint8_t sensors::registry::entryCount() {
    return count;
}

const SensorEntry *sensors::registry::entry(uint8_t i) {
    if (i >= count) return nullptr;
    return &slots[i].entry;
}

const SensorEntry *sensors::registry::find(SensorKind kind) {
    Slot *s = findSlot(kind);
    return s ? &s->entry : nullptr;
}
