#include "modbus.h"

#include <Arduino.h>
#include <ModbusRTUMaster.h>

namespace {

constexpr uint8_t MAX_CHANNELS = config::rs485::CHANNEL_COUNT;
ModbusRTUMaster modbus0(Serial1, config::rs485::BUS_0.de_re_gpio);
ModbusRTUMaster modbus1(Serial2, config::rs485::BUS_1.de_re_gpio);

struct ChannelContext {
  hardware::rs485::Channel channel;
  ModbusRTUMaster *master;
  bool ready;
};

ChannelContext channels[MAX_CHANNELS] = {
  {hardware::rs485::Channel::Bus0, &modbus0, false},
  {hardware::rs485::Channel::Bus1, &modbus1, false},
};

bool initialized = false;

size_t channel_index(hardware::rs485::Channel channel) {
  return static_cast<size_t>(channel);
}

ModbusError translate_error(uint8_t error) {
  switch (error) {
    case MODBUS_RTU_MASTER_SUCCESS: return ModbusError::Success;
    case MODBUS_RTU_MASTER_INVALID_ID: return ModbusError::InvalidId;
    case MODBUS_RTU_MASTER_INVALID_BUFFER: return ModbusError::InvalidBuffer;
    case MODBUS_RTU_MASTER_INVALID_QUANTITY: return ModbusError::InvalidQuantity;
    case MODBUS_RTU_MASTER_RESPONSE_TIMEOUT: return ModbusError::ResponseTimeout;
    case MODBUS_RTU_MASTER_FRAME_ERROR: return ModbusError::FrameError;
    case MODBUS_RTU_MASTER_CRC_ERROR: return ModbusError::CrcError;
    case MODBUS_RTU_MASTER_UNKNOWN_COMM_ERROR: return ModbusError::UnknownCommunicationError;
    case MODBUS_RTU_MASTER_UNEXPECTED_ID: return ModbusError::UnexpectedId;
    case MODBUS_RTU_MASTER_EXCEPTION_RESPONSE: return ModbusError::ExceptionResponse;
    case MODBUS_RTU_MASTER_UNEXPECTED_FUNCTION_CODE: return ModbusError::UnexpectedFunctionCode;
    case MODBUS_RTU_MASTER_UNEXPECTED_LENGTH: return ModbusError::UnexpectedLength;
    case MODBUS_RTU_MASTER_UNEXPECTED_BYTE_COUNT: return ModbusError::UnexpectedByteCount;
    case MODBUS_RTU_MASTER_UNEXPECTED_ADDRESS: return ModbusError::UnexpectedAddress;
    case MODBUS_RTU_MASTER_UNEXPECTED_VALUE: return ModbusError::UnexpectedValue;
    case MODBUS_RTU_MASTER_UNEXPECTED_QUANTITY: return ModbusError::UnexpectedQuantity;
    default: return ModbusError::UnknownCommunicationError;
  }
}

}

bool networking::modbus::initialize() {
  if (initialized) return true;
  if (!hardware::rs485::initialize()) return false;

  for (size_t index = 0; index < MAX_CHANNELS; index++) {
    hardware::rs485::BusDescriptor descriptor = {
      .channel = channels[index].channel,
      .serial = nullptr,
      .de_re_gpio = -1,
      .baud_rate = 0,
      .ready = false,
    };
    if (!hardware::rs485::accessDescriptor(&descriptor) || !descriptor.ready || !descriptor.serial) {
      channels[index].ready = false;
      continue;
    }

    channels[index].master->begin(descriptor.baud_rate, SERIAL_8N1);
    channels[index].master->setTimeout(config::wind::SENSOR_DELAY_MS * 5);
    channels[index].ready = true;
  }

  initialized = true;
  return true;
}

bool networking::modbus::readHoldingRegisters(ReadHoldingRegistersCommand *command) {
  if (!command || !command->output_words || command->register_count == 0) {
    if (command) command->error = ModbusError::InvalidBuffer;
    return false;
  }
  if (!networking::modbus::initialize()) {
    command->error = ModbusError::NotInitialized;
    return false;
  }

  size_t index = channel_index(command->channel);
  if (index >= MAX_CHANNELS || !channels[index].ready) {
    command->error = ModbusError::InvalidChannel;
    return false;
  }

  ModbusRTUMasterError error = channels[index].master->readHoldingRegisters(
      command->slave_id, command->start_register, command->output_words,
      command->register_count);
  command->error = translate_error(error);
  return command->error == ModbusError::Success;
}

bool networking::modbus::writeSingleRegister(WriteSingleRegisterCommand *command) {
  if (!command) return false;
  if (!networking::modbus::initialize()) {
    command->error = ModbusError::NotInitialized;
    return false;
  }

  size_t index = channel_index(command->channel);
  if (index >= MAX_CHANNELS || !channels[index].ready) {
    command->error = ModbusError::InvalidChannel;
    return false;
  }

  ModbusRTUMasterError error = channels[index].master->writeSingleHoldingRegister(
      command->slave_id, command->register_address, command->value);
  command->error = translate_error(error);
  return command->error == ModbusError::Success;
}

bool networking::modbus::scan(ModbusScanCommand *command) {
  if (!command || !command->results || command->max_results == 0) return false;
  if (!networking::modbus::initialize()) return false;

  command->result_count = 0;
  for (uint8_t slave_id = command->first_slave_id;
       slave_id <= command->last_slave_id && command->result_count < command->max_results;
       slave_id++) {
    uint16_t output_word = 0;
    ReadHoldingRegistersCommand read_command = {
      .channel = command->channel,
      .slave_id = slave_id,
      .start_register = 0,
      .register_count = 1,
      .output_words = &output_word,
      .error = ModbusError::NotInitialized,
    };

    bool responsive = networking::modbus::readHoldingRegisters(&read_command) ||
                      read_command.error == ModbusError::ExceptionResponse;
    if (responsive) {
      command->results[command->result_count++] = {
        .channel = command->channel,
        .slave_id = slave_id,
        .responsive = true,
        .error = read_command.error,
      };
    }
    delay(10);
    if (slave_id == UINT8_MAX) break;
  }

  return true;
}
