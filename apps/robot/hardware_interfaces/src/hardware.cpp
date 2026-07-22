#include "robot_hardware_interfaces/hardware.hpp"

#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <string>
#include <vector>

#include "hardware_interface/types/hardware_interface_type_values.hpp"
#include "lgpio.h"
#include "pluginlib/class_list_macros.hpp"

namespace robot_hardware_interfaces {

namespace {

constexpr int kExportRetries = 100;
constexpr int kExportRetryDelayUs = 10000;
constexpr std::int64_t kNanosecondsPerSecond = 1000000000LL;

bool write_sysfs(const std::string &path, const std::string &value) {
  const int fd = ::open(path.c_str(), O_WRONLY);
  if (fd < 0) {
    return false;
  }
  const ssize_t written = ::write(fd, value.c_str(), value.size());
  ::close(fd);
  return written == static_cast<ssize_t>(value.size());
}

} // namespace

hardware_interface::CallbackReturn RobotHardware::on_init(
    const hardware_interface::HardwareComponentInterfaceParams &params) {
  if (hardware_interface::SystemInterface::on_init(params) !=
      hardware_interface::CallbackReturn::SUCCESS) {
    return hardware_interface::CallbackReturn::ERROR;
  }

  const auto &hw = info_.hardware_parameters;
  gpio_chip_ = std::stoi(hw.at("gpio_chip"));
  pwm_frequency_ = std::stof(hw.at("pwm_frequency"));
  max_wheel_speed_ = std::stod(hw.at("max_wheel_speed"));
  period_ns_ = static_cast<std::int64_t>(
      static_cast<double>(kNanosecondsPerSecond) / pwm_frequency_);
  left_pwm_chip_ = std::stoi(hw.at("left_pwm_chip"));
  left_pwm_channel_ = std::stoi(hw.at("left_pwm_channel"));
  left_dir_pin_ = std::stoi(hw.at("left_dir_pin"));
  left_forward_level_ = std::stoi(hw.at("left_forward_level")) != 0;
  right_pwm_chip_ = std::stoi(hw.at("right_pwm_chip"));
  right_pwm_channel_ = std::stoi(hw.at("right_pwm_channel"));
  right_dir_pin_ = std::stoi(hw.at("right_dir_pin"));
  right_forward_level_ = std::stoi(hw.at("right_forward_level")) != 0;

  left_channel_path_ = "/sys/class/pwm/pwmchip" +
                       std::to_string(left_pwm_chip_) + "/pwm" +
                       std::to_string(left_pwm_channel_);
  right_channel_path_ = "/sys/class/pwm/pwmchip" +
                        std::to_string(right_pwm_chip_) + "/pwm" +
                        std::to_string(right_pwm_channel_);

  const std::string left_wheel = hw.at("left_wheel");
  const std::string right_wheel = hw.at("right_wheel");
  for (std::size_t i = 0; i < info_.joints.size(); ++i) {
    if (info_.joints[i].name == left_wheel) {
      left_index_ = i;
    }
    if (info_.joints[i].name == right_wheel) {
      right_index_ = i;
    }
  }

  const std::size_t num_joints = info_.joints.size();
  hw_commands_velocity_.assign(num_joints, 0.0);
  hw_states_position_.assign(num_joints, 0.0);
  hw_states_velocity_.assign(num_joints, 0.0);

  return hardware_interface::CallbackReturn::SUCCESS;
}

std::vector<hardware_interface::StateInterface>
RobotHardware::export_state_interfaces() {
  std::vector<hardware_interface::StateInterface> state_interfaces;
  for (std::size_t i = 0; i < info_.joints.size(); ++i) {
    state_interfaces.emplace_back(info_.joints[i].name,
                                  hardware_interface::HW_IF_POSITION,
                                  &hw_states_position_[i]);
    state_interfaces.emplace_back(info_.joints[i].name,
                                  hardware_interface::HW_IF_VELOCITY,
                                  &hw_states_velocity_[i]);
  }
  return state_interfaces;
}

std::vector<hardware_interface::CommandInterface>
RobotHardware::export_command_interfaces() {
  std::vector<hardware_interface::CommandInterface> command_interfaces;
  for (std::size_t i = 0; i < info_.joints.size(); ++i) {
    command_interfaces.emplace_back(info_.joints[i].name,
                                    hardware_interface::HW_IF_VELOCITY,
                                    &hw_commands_velocity_[i]);
  }
  return command_interfaces;
}

int RobotHardware::open_pwm_channel(const std::string &channel_path, int chip,
                                    int channel) {
  const std::string chip_path =
      "/sys/class/pwm/pwmchip" + std::to_string(chip);
  const std::string duty_path = channel_path + "/duty_cycle";

  if (::access(channel_path.c_str(), F_OK) != 0) {
    write_sysfs(chip_path + "/export", std::to_string(channel));
  }
  for (int i = 0; i < kExportRetries; ++i) {
    if (::access(duty_path.c_str(), W_OK) == 0) {
      break;
    }
    ::usleep(kExportRetryDelayUs);
  }

  if (!write_sysfs(duty_path, "0")) {
    return -1;
  }
  if (!write_sysfs(channel_path + "/period", std::to_string(period_ns_))) {
    return -1;
  }
  if (!write_sysfs(channel_path + "/enable", "1")) {
    return -1;
  }
  return ::open(duty_path.c_str(), O_WRONLY);
}

hardware_interface::CallbackReturn
RobotHardware::on_activate(const rclcpp_lifecycle::State & /*previous_state*/) {
  chip_handle_ = lgGpiochipOpen(gpio_chip_);
  if (chip_handle_ < 0) {
    return hardware_interface::CallbackReturn::ERROR;
  }
  if (lgGpioClaimOutput(chip_handle_, 0, left_dir_pin_, 0) < 0 ||
      lgGpioClaimOutput(chip_handle_, 0, right_dir_pin_, 0) < 0) {
    release();
    return hardware_interface::CallbackReturn::ERROR;
  }

  left_duty_fd_ = open_pwm_channel(left_channel_path_, left_pwm_chip_,
                                   left_pwm_channel_);
  right_duty_fd_ = open_pwm_channel(right_channel_path_, right_pwm_chip_,
                                    right_pwm_channel_);
  if (left_duty_fd_ < 0 || right_duty_fd_ < 0) {
    release();
    return hardware_interface::CallbackReturn::ERROR;
  }

  std::fill(hw_commands_velocity_.begin(), hw_commands_velocity_.end(), 0.0);
  std::fill(hw_states_position_.begin(), hw_states_position_.end(), 0.0);
  std::fill(hw_states_velocity_.begin(), hw_states_velocity_.end(), 0.0);
  halt();

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn RobotHardware::on_deactivate(
    const rclcpp_lifecycle::State & /*previous_state*/) {
  halt();
  write_sysfs(left_channel_path_ + "/enable", "0");
  write_sysfs(right_channel_path_ + "/enable", "0");
  release();
  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::return_type
RobotHardware::read(const rclcpp::Time & /*time*/,
                    const rclcpp::Duration &period) {
  // FIXME: use encoders for actual wheel speed
  const double elapsed_seconds = period.seconds();
  for (std::size_t i = 0; i < info_.joints.size(); ++i) {
    hw_states_velocity_[i] = hw_commands_velocity_[i];
    hw_states_position_[i] += hw_commands_velocity_[i] * elapsed_seconds;
  }
  return hardware_interface::return_type::OK;
}

hardware_interface::return_type
RobotHardware::write(const rclcpp::Time & /*time*/,
                     const rclcpp::Duration & /*period*/) {
  drive_side(left_duty_fd_, left_dir_pin_, left_forward_level_,
             hw_commands_velocity_[left_index_], left_last_duty_ns_,
             left_last_dir_level_);
  drive_side(right_duty_fd_, right_dir_pin_, right_forward_level_,
             hw_commands_velocity_[right_index_], right_last_duty_ns_,
             right_last_dir_level_);
  return hardware_interface::return_type::OK;
}

void RobotHardware::drive_side(int duty_fd, int dir_pin, bool forward_level,
                               double wheel_speed,
                               std::int64_t &last_duty_ns,
                               int &last_dir_level) {
  const int dir_level = ((wheel_speed >= 0.0) == forward_level) ? 1 : 0;
  if (dir_level != last_dir_level) {
    lgGpioWrite(chip_handle_, dir_pin, dir_level);
    last_dir_level = dir_level;
  }
  const double fraction =
      std::clamp(std::abs(wheel_speed) / max_wheel_speed_, 0.0, 1.0);
  const auto duty_ns =
      static_cast<std::int64_t>(fraction * static_cast<double>(period_ns_));
  if (duty_ns != last_duty_ns) {
    write_duty(duty_fd, duty_ns);
    last_duty_ns = duty_ns;
  }
}

void RobotHardware::write_duty(int duty_fd, std::int64_t duty_ns) {
  if (duty_fd < 0) {
    return;
  }
  char buffer[32];
  const int length =
      std::snprintf(buffer, sizeof(buffer), "%lld",
                    static_cast<long long>(duty_ns));
  ::pwrite(duty_fd, buffer, static_cast<size_t>(length), 0);
}

void RobotHardware::halt() {
  write_duty(left_duty_fd_, 0);
  write_duty(right_duty_fd_, 0);
  left_last_duty_ns_ = 0;
  right_last_duty_ns_ = 0;
  left_last_dir_level_ = -1;
  right_last_dir_level_ = -1;
}

void RobotHardware::release() {
  if (left_duty_fd_ >= 0) {
    ::close(left_duty_fd_);
    left_duty_fd_ = -1;
  }
  if (right_duty_fd_ >= 0) {
    ::close(right_duty_fd_);
    right_duty_fd_ = -1;
  }
  if (chip_handle_ >= 0) {
    lgGpioFree(chip_handle_, left_dir_pin_);
    lgGpioFree(chip_handle_, right_dir_pin_);
    lgGpiochipClose(chip_handle_);
    chip_handle_ = -1;
  }
}

} // namespace robot_hardware_interfaces

PLUGINLIB_EXPORT_CLASS(robot_hardware_interfaces::RobotHardware,
                       hardware_interface::SystemInterface)
