#include "robot_hardware_interfaces/hardware.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <string>
#include <vector>

#include "hardware_interface/types/hardware_interface_type_values.hpp"
#include "pluginlib/class_list_macros.hpp"
#include "rgpio.h"

namespace robot_hardware_interfaces
{

hardware_interface::CallbackReturn RobotHardware::on_init(
  const hardware_interface::HardwareComponentInterfaceParams & params)
{
  if (hardware_interface::SystemInterface::on_init(params) !=
    hardware_interface::CallbackReturn::SUCCESS)
  {
    return hardware_interface::CallbackReturn::ERROR;
  }

  const auto & hw = info_.hardware_parameters;
  rgpiod_host_ = hw.at("rgpiod_host");
  rgpiod_port_ = hw.at("rgpiod_port");
  gpio_chip_ = std::stoi(hw.at("gpio_chip"));
  pwm_frequency_ = std::stof(hw.at("pwm_frequency"));
  max_wheel_speed_ = std::stod(hw.at("max_wheel_speed"));
  left_pwm_pin_ = std::stoi(hw.at("left_pwm_pin"));
  left_dir_pin_ = std::stoi(hw.at("left_dir_pin"));
  left_forward_level_ = std::stoi(hw.at("left_forward_level")) != 0;
  right_pwm_pin_ = std::stoi(hw.at("right_pwm_pin"));
  right_dir_pin_ = std::stoi(hw.at("right_dir_pin"));
  right_forward_level_ = std::stoi(hw.at("right_forward_level")) != 0;

  const std::string left_wheel = hw.at("left_wheel");
  const std::string right_wheel = hw.at("right_wheel");
  for (std::size_t i = 0; i < info_.joints.size(); ++i)
  {
    if (info_.joints[i].name == left_wheel) { left_index_ = i; }
    if (info_.joints[i].name == right_wheel) { right_index_ = i; }
  }

  const std::size_t num_joints = info_.joints.size();
  hw_commands_velocity_.assign(num_joints, 0.0);
  hw_states_position_.assign(num_joints, 0.0);
  hw_states_velocity_.assign(num_joints, 0.0);

  return hardware_interface::CallbackReturn::SUCCESS;
}

std::vector<hardware_interface::StateInterface> RobotHardware::export_state_interfaces()
{
  std::vector<hardware_interface::StateInterface> state_interfaces;
  for (std::size_t i = 0; i < info_.joints.size(); ++i)
  {
    state_interfaces.emplace_back(
      info_.joints[i].name, hardware_interface::HW_IF_POSITION, &hw_states_position_[i]);
    state_interfaces.emplace_back(
      info_.joints[i].name, hardware_interface::HW_IF_VELOCITY, &hw_states_velocity_[i]);
  }
  return state_interfaces;
}

std::vector<hardware_interface::CommandInterface> RobotHardware::export_command_interfaces()
{
  std::vector<hardware_interface::CommandInterface> command_interfaces;
  for (std::size_t i = 0; i < info_.joints.size(); ++i)
  {
    command_interfaces.emplace_back(
      info_.joints[i].name, hardware_interface::HW_IF_VELOCITY, &hw_commands_velocity_[i]);
  }
  return command_interfaces;
}

hardware_interface::CallbackReturn RobotHardware::on_activate(
  const rclcpp_lifecycle::State & /*previous_state*/)
{
  sbc_ = rgpiod_start(rgpiod_host_.c_str(), rgpiod_port_.c_str());
  if (sbc_ < 0)
  {
    return hardware_interface::CallbackReturn::ERROR;
  }

  chip_ = gpiochip_open(sbc_, gpio_chip_);
  if (chip_ < 0)
  {
    rgpiod_stop(sbc_);
    return hardware_interface::CallbackReturn::ERROR;
  }

  gpio_claim_output(sbc_, chip_, 0, left_dir_pin_, 0);
  gpio_claim_output(sbc_, chip_, 0, left_pwm_pin_, 0);
  gpio_claim_output(sbc_, chip_, 0, right_dir_pin_, 0);
  gpio_claim_output(sbc_, chip_, 0, right_pwm_pin_, 0);

  std::fill(hw_commands_velocity_.begin(), hw_commands_velocity_.end(), 0.0);
  std::fill(hw_states_position_.begin(), hw_states_position_.end(), 0.0);
  std::fill(hw_states_velocity_.begin(), hw_states_velocity_.end(), 0.0);
  halt();

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn RobotHardware::on_deactivate(
  const rclcpp_lifecycle::State & /*previous_state*/)
{
  if (sbc_ >= 0)
  {
    halt();
    gpio_free(sbc_, chip_, left_pwm_pin_);
    gpio_free(sbc_, chip_, left_dir_pin_);
    gpio_free(sbc_, chip_, right_pwm_pin_);
    gpio_free(sbc_, chip_, right_dir_pin_);
    gpiochip_close(sbc_, chip_);
    rgpiod_stop(sbc_);
    sbc_ = -1;
  }
  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::return_type RobotHardware::read(
  const rclcpp::Time & /*time*/, const rclcpp::Duration & period)
{
  const double dt = period.seconds();
  for (std::size_t i = 0; i < info_.joints.size(); ++i)
  {
    hw_states_velocity_[i] = hw_commands_velocity_[i];
    hw_states_position_[i] += hw_commands_velocity_[i] * dt;
  }
  return hardware_interface::return_type::OK;
}

hardware_interface::return_type RobotHardware::write(
  const rclcpp::Time & /*time*/, const rclcpp::Duration & /*period*/)
{
  drive_side(left_pwm_pin_, left_dir_pin_, left_forward_level_, hw_commands_velocity_[left_index_]);
  drive_side(right_pwm_pin_, right_dir_pin_, right_forward_level_, hw_commands_velocity_[right_index_]);
  return hardware_interface::return_type::OK;
}

void RobotHardware::drive_side(int pwm_pin, int dir_pin, bool forward_level, double wheel_speed)
{
  gpio_write(sbc_, chip_, dir_pin, ((wheel_speed >= 0.0) == forward_level) ? 1 : 0);
  const double duty = std::clamp(std::abs(wheel_speed) / max_wheel_speed_ * 100.0, 0.0, 100.0);
  tx_pwm(sbc_, chip_, pwm_pin, pwm_frequency_, static_cast<float>(duty), 0, 0);
}

void RobotHardware::halt()
{
  // Stop by driving 0% duty at a valid frequency (holds the pin low). tx_pwm with
  // frequency 0 returns LG_BAD_PWM_MICROS (-86) on a fresh pin and does NOT stop.
  tx_pwm(sbc_, chip_, left_pwm_pin_, pwm_frequency_, 0.0f, 0, 0);
  tx_pwm(sbc_, chip_, right_pwm_pin_, pwm_frequency_, 0.0f, 0, 0);
}

}  // namespace robot_hardware_interfaces

PLUGINLIB_EXPORT_CLASS(robot_hardware_interfaces::RobotHardware, hardware_interface::SystemInterface)
