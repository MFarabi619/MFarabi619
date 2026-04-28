// clang-format off
#pragma once

#include <config.h>
#include "../hardware/rs485.h"

inline const config::ModbusSensorConfig* find_modbus_device(config::ModbusSensorKind kind) {
    for (uint32_t i = 0; i < config::modbus::DEVICE_COUNT; i++) {
        if (config::modbus::DEVICES[i].kind == kind) return &config::modbus::DEVICES[i];
    }
    return nullptr;
}

inline hardware::rs485::Channel channel_for_device(const config::ModbusSensorConfig *device) {
    return device && device->channel == 0
        ? hardware::rs485::Channel::Bus0
        : hardware::rs485::Channel::Bus1;
}
