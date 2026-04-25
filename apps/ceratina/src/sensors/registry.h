#pragma once
#include <stddef.h>
#include <stdint.h>

enum class SensorKind : uint8_t {
    TemperatureHumidity,
    Voltage,
    Current,
    CarbonDioxide,
    BarometricPressure,
    WindSpeed,
    WindDirection,
    SolarRadiation,
    Soil,
    Rain,
};

struct SensorEntry {
    SensorKind kind;
    const char *name;
    bool (*isAvailable)();
    uint8_t (*instanceCount)();
    bool (*poll)(uint8_t index, void *out, size_t capacity);
    size_t data_size;
};

namespace sensors::registry {

void add(const SensorEntry &entry);
void pollAll();

bool isAvailable(SensorKind kind);
uint8_t instanceCount(SensorKind kind);
const void *latest(SensorKind kind, uint8_t index = 0);
bool valid(SensorKind kind, uint8_t index = 0);

uint8_t entryCount();
const SensorEntry *entry(uint8_t i);
const SensorEntry *find(SensorKind kind);

}
