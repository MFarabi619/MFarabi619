#pragma once
#include "../hardware/rs485.h"

#include <stdint.h>

enum class ModbusError : uint8_t {
  Success = 0,
  InvalidId = 1,
  InvalidBuffer = 2,
  InvalidQuantity = 3,
  ResponseTimeout = 4,
  FrameError = 5,
  CrcError = 6,
  UnknownCommunicationError = 7,
  UnexpectedId = 8,
  ExceptionResponse = 9,
  UnexpectedFunctionCode = 10,
  UnexpectedLength = 11,
  UnexpectedByteCount = 12,
  UnexpectedAddress = 13,
  UnexpectedValue = 14,
  UnexpectedQuantity = 15,
  NotInitialized = 16,
  InvalidChannel = 17,
};

struct ReadHoldingRegistersCommand {
  hardware::rs485::Channel channel;
  uint8_t slave_id;
  uint16_t start_register;
  uint16_t register_count;
  uint16_t *output_words;
  ModbusError error;
};

struct WriteSingleRegisterCommand {
  hardware::rs485::Channel channel;
  uint8_t slave_id;
  uint16_t register_address;
  uint16_t value;
  ModbusError error;
};

struct ModbusScanResult {
  hardware::rs485::Channel channel;
  uint8_t slave_id;
  bool responsive;
  ModbusError error;
};

struct ModbusScanCommand {
  hardware::rs485::Channel channel;
  uint8_t first_slave_id;
  uint8_t last_slave_id;
  ModbusScanResult *results;
  size_t max_results;
  size_t result_count;
};

namespace networking::modbus {

bool initialize();
bool readHoldingRegisters(ReadHoldingRegistersCommand *command);
bool writeSingleRegister(WriteSingleRegisterCommand *command);
bool scan(ModbusScanCommand *command);

}

