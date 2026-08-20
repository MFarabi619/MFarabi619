// Copyright 2023 Clearpath Robotics, Inc.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
//    * Redistributions of source code must retain the above copyright
//      notice, this list of conditions and the following disclaimer.
//
//    * Redistributions in binary form must reproduce the above copyright
//      notice, this list of conditions and the following disclaimer in the
//      documentation and/or other materials provided with the distribution.
//
//    * Neither the name of the Clearpath Robotics, Inc. nor the names of its
//      contributors may be used to endorse or promote products derived from
//      this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "hardware_interface/handle.hpp"
#include "hardware_interface/hardware_info.hpp"
#include "hardware_interface/system_interface.hpp"
#include "hardware_interface/types/hardware_interface_return_values.hpp"
#include "hardware_interface/types/hardware_interface_type_values.hpp"
#include "pluginlib/class_list_macros.hpp"
#include "rclcpp/rclcpp.hpp"
#include "realtime_tools/realtime_thread_safe_box.hpp"

#include "robot_platform_msgs/msg/drive.hpp"
#include "robot_platform_msgs/msg/feedback.hpp"

namespace robot_drivers
{

constexpr double WHEEL_COMMAND_DEADBAND_RADIANS_PER_SECOND = 0.01;
constexpr double ENCODER_ROLLOVER_THRESHOLD_RADIANS = 1.0;
constexpr std::size_t EXPECTED_COMMAND_INTERFACE_COUNT = 1;
constexpr std::size_t EXPECTED_STATE_INTERFACE_COUNT = 2;

class DiffDriveHardware : public hardware_interface::SystemInterface
{
public:
  RCLCPP_SHARED_PTR_DEFINITIONS(DiffDriveHardware)

  hardware_interface::CallbackReturn on_init(
    const hardware_interface::HardwareComponentInterfaceParams & params) override;

  hardware_interface::CallbackReturn on_activate(
    const rclcpp_lifecycle::State & previous_state) override;

  hardware_interface::CallbackReturn on_deactivate(
    const rclcpp_lifecycle::State & previous_state) override;

  hardware_interface::return_type read(
    const rclcpp::Time & time,
    const rclcpp::Duration & period) override;

  hardware_interface::return_type write(
    const rclcpp::Time & time,
    const rclcpp::Duration & period) override;

protected:
  void writeCommandsToHardware();
  void updateJointsFromHardware();
  virtual hardware_interface::CallbackReturn initializeFromHardwareInfo(
    const hardware_interface::HardwareComponentInterfaceParams & params);
  virtual hardware_interface::CallbackReturn validateJoints();
  virtual hardware_interface::CallbackReturn resolveJointSides();
  virtual hardware_interface::CallbackReturn createPlatformTopics();

  rclcpp::Publisher<robot_platform_msgs::msg::Drive>::SharedPtr drive_publisher_;
  rclcpp::Subscription<robot_platform_msgs::msg::Feedback>::SharedPtr feedback_subscription_;
  realtime_tools::RealtimeThreadSafeBox<robot_platform_msgs::msg::Feedback> feedback_;

  std::vector<double> joint_position_offsets_;
  std::vector<std::string> joint_position_names_;
  std::vector<std::string> joint_velocity_names_;

  std::vector<int8_t> joint_sides_;
  uint8_t left_joint_index_ = 0;
  uint8_t right_joint_index_ = 0;

  uint8_t joint_count_;
  std::string hardware_name_;
};

void DiffDriveHardware::writeCommandsToHardware()
{
  double left_wheel_velocity = get_command(joint_velocity_names_[left_joint_index_]);
  double right_wheel_velocity = get_command(joint_velocity_names_[right_joint_index_]);

  if (std::abs(left_wheel_velocity) < WHEEL_COMMAND_DEADBAND_RADIANS_PER_SECOND &&
    std::abs(right_wheel_velocity) < WHEEL_COMMAND_DEADBAND_RADIANS_PER_SECOND)
  {
    left_wheel_velocity = right_wheel_velocity = 0.0;
  }

  robot_platform_msgs::msg::Drive drive_msg;
  drive_msg.mode = robot_platform_msgs::msg::Drive::MODE_VELOCITY;
  drive_msg.drivers[robot_platform_msgs::msg::Drive::LEFT] =
    static_cast<float>(left_wheel_velocity);
  drive_msg.drivers[robot_platform_msgs::msg::Drive::RIGHT] =
    static_cast<float>(right_wheel_velocity);
  drive_publisher_->publish(drive_msg);
}

void DiffDriveHardware::updateJointsFromHardware()
{
  robot_platform_msgs::msg::Feedback feedback = feedback_.get();
  RCLCPP_DEBUG(
    rclcpp::get_logger(hardware_name_),
    "Received linear distance information (L: %f, R: %f)",
    feedback.drivers[0].measured_travel, feedback.drivers[1].measured_travel);

  for (auto i = 0u; i < joint_count_; i++) {
    const auto side = joint_sides_[i];
    const double joint_position = get_state(joint_position_names_[i]);

    double travel_delta = feedback.drivers[side].measured_travel -
      joint_position - joint_position_offsets_[i];

    // detect suspiciously large readings, possibly from encoder rollover
    if (std::abs(travel_delta) < ENCODER_ROLLOVER_THRESHOLD_RADIANS) {
      set_state(joint_position_names_[i], joint_position + travel_delta);
    } else {
      joint_position_offsets_[i] += travel_delta;
      RCLCPP_WARN(
        rclcpp::get_logger(hardware_name_), "Dropping overflow measurement from encoder");
    }

    set_state(joint_velocity_names_[i], feedback.drivers[side].measured_velocity);
  }
}

hardware_interface::CallbackReturn DiffDriveHardware::initializeFromHardwareInfo(
  const hardware_interface::HardwareComponentInterfaceParams & params)
{
  if (hardware_interface::SystemInterface::on_init(params) !=
    hardware_interface::CallbackReturn::SUCCESS)
  {
    return hardware_interface::CallbackReturn::ERROR;
  }

  hardware_name_ = info_.name;
  joint_count_ = info_.joints.size();

  RCLCPP_INFO(rclcpp::get_logger(hardware_name_), "Name: %s", hardware_name_.c_str());
  RCLCPP_INFO(rclcpp::get_logger(hardware_name_), "Number of Joints %u", joint_count_);

  joint_position_offsets_.resize(joint_count_);
  for (const hardware_interface::ComponentInfo & joint : info_.joints) {
    joint_position_names_.push_back(
      joint.name + "/" + hardware_interface::HW_IF_POSITION);
    joint_velocity_names_.push_back(
      joint.name + "/" + hardware_interface::HW_IF_VELOCITY);
  }

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn DiffDriveHardware::validateJoints()
{
  for (const hardware_interface::ComponentInfo & joint : info_.joints) {
    if (joint.command_interfaces.size() != EXPECTED_COMMAND_INTERFACE_COUNT) {
      RCLCPP_FATAL(
        rclcpp::get_logger(hardware_name_),
        "Joint '%s' has %zu command interfaces found. %zu expected.", joint.name.c_str(),
        joint.command_interfaces.size(), EXPECTED_COMMAND_INTERFACE_COUNT);
      return hardware_interface::CallbackReturn::ERROR;
    }

    if (joint.command_interfaces[0].name != hardware_interface::HW_IF_VELOCITY) {
      RCLCPP_FATAL(
        rclcpp::get_logger(hardware_name_),
        "Joint '%s' have %s command interfaces found. '%s' expected.", joint.name.c_str(),
        joint.command_interfaces[0].name.c_str(), hardware_interface::HW_IF_VELOCITY);
      return hardware_interface::CallbackReturn::ERROR;
    }

    if (joint.state_interfaces.size() != EXPECTED_STATE_INTERFACE_COUNT) {
      RCLCPP_FATAL(
        rclcpp::get_logger(hardware_name_),
        "Joint '%s' has %zu state interface. %zu expected.", joint.name.c_str(),
        joint.state_interfaces.size(), EXPECTED_STATE_INTERFACE_COUNT);
      return hardware_interface::CallbackReturn::ERROR;
    }

    if (joint.state_interfaces[0].name != hardware_interface::HW_IF_POSITION) {
      RCLCPP_FATAL(
        rclcpp::get_logger(hardware_name_),
        "Joint '%s' have '%s' as first state interface. '%s' expected.",
        joint.name.c_str(), joint.state_interfaces[0].name.c_str(),
        hardware_interface::HW_IF_POSITION);
      return hardware_interface::CallbackReturn::ERROR;
    }

    if (joint.state_interfaces[1].name != hardware_interface::HW_IF_VELOCITY) {
      RCLCPP_FATAL(
        rclcpp::get_logger(hardware_name_),
        "Joint '%s' have '%s' as second state interface. '%s' expected.", joint.name.c_str(),
        joint.state_interfaces[1].name.c_str(), hardware_interface::HW_IF_VELOCITY);
      return hardware_interface::CallbackReturn::ERROR;
    }
  }

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn DiffDriveHardware::resolveJointSides()
{
  joint_sides_.resize(joint_count_);
  unsigned left_joint_count = 0;
  unsigned right_joint_count = 0;

  for (auto i = 0u; i < joint_count_; i++) {
    const std::string & joint_name = info_.joints[i].name;
    const bool name_says_left = joint_name.find("left") != std::string::npos;
    const bool name_says_right = joint_name.find("right") != std::string::npos;

    if (name_says_left == name_says_right) {
      RCLCPP_FATAL(
        rclcpp::get_logger(hardware_name_),
        "Joint '%s' must contain exactly one of 'left' or 'right'.", joint_name.c_str());
      return hardware_interface::CallbackReturn::ERROR;
    }

    if (name_says_left) {
      joint_sides_[i] = robot_platform_msgs::msg::Drive::LEFT;
      if (left_joint_count == 0) {
        left_joint_index_ = i;
      }
      left_joint_count++;
    } else {
      joint_sides_[i] = robot_platform_msgs::msg::Drive::RIGHT;
      if (right_joint_count == 0) {
        right_joint_index_ = i;
      }
      right_joint_count++;
    }
  }

  if (left_joint_count == 0 || right_joint_count == 0) {
    RCLCPP_FATAL(
      rclcpp::get_logger(hardware_name_),
      "Need at least one wheel joint per side, found %u left and %u right.",
      left_joint_count, right_joint_count);
    return hardware_interface::CallbackReturn::ERROR;
  }

  RCLCPP_INFO(
    rclcpp::get_logger(hardware_name_),
    "Commanding side LEFT from joint '%s' and side RIGHT from joint '%s'",
    info_.joints[left_joint_index_].name.c_str(),
    info_.joints[right_joint_index_].name.c_str());

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn DiffDriveHardware::createPlatformTopics()
{
  auto node = get_node();

  if (node == nullptr) {
    return hardware_interface::CallbackReturn::ERROR;
  }

  feedback_subscription_ = node->create_subscription<robot_platform_msgs::msg::Feedback>(
    "platform/motors/feedback",
    rclcpp::SensorDataQoS(),
    [this](robot_platform_msgs::msg::Feedback::ConstSharedPtr message) {
      feedback_.set(*message);
    });

  drive_publisher_ = node->create_publisher<robot_platform_msgs::msg::Drive>(
    "platform/motors/cmd_drive",
    rclcpp::SensorDataQoS());

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn DiffDriveHardware::on_init(
  const hardware_interface::HardwareComponentInterfaceParams & params)
{
  hardware_interface::CallbackReturn result;
  result = initializeFromHardwareInfo(params);

  if (result != hardware_interface::CallbackReturn::SUCCESS) {
    return result;
  }

  result = validateJoints();

  if (result != hardware_interface::CallbackReturn::SUCCESS) {
    return result;
  }

  result = resolveJointSides();

  if (result != hardware_interface::CallbackReturn::SUCCESS) {
    return result;
  }

  return createPlatformTopics();
}

hardware_interface::CallbackReturn DiffDriveHardware::on_activate(
  const rclcpp_lifecycle::State & /*previous_state*/)
{
  RCLCPP_INFO(rclcpp::get_logger(hardware_name_), "Starting ...please wait...");

  for (auto i = 0u; i < joint_count_; i++) {
    joint_position_offsets_[i] = 0.0;
    set_state(joint_position_names_[i], 0.0);
    set_state(joint_velocity_names_[i], 0.0);
    set_command(joint_velocity_names_[i], 0.0);
  }

  RCLCPP_INFO(rclcpp::get_logger(hardware_name_), "System Successfully started!");

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn DiffDriveHardware::on_deactivate(
  const rclcpp_lifecycle::State & /*previous_state*/)
{
  RCLCPP_INFO(rclcpp::get_logger(hardware_name_), "Stopping ...please wait...");

  RCLCPP_INFO(rclcpp::get_logger(hardware_name_), "System successfully stopped!");

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::return_type DiffDriveHardware::read(
  const rclcpp::Time & /*time*/,
  const rclcpp::Duration & /*period*/)
{
  RCLCPP_DEBUG(rclcpp::get_logger(hardware_name_), "Reading from hardware");

  updateJointsFromHardware();

  RCLCPP_DEBUG(rclcpp::get_logger(hardware_name_), "Joints successfully read!");

  return hardware_interface::return_type::OK;
}

hardware_interface::return_type DiffDriveHardware::write(
  const rclcpp::Time & /*time*/,
  const rclcpp::Duration & /*period*/)
{
  RCLCPP_DEBUG(rclcpp::get_logger(hardware_name_), "Writing to hardware");

  writeCommandsToHardware();

  RCLCPP_DEBUG(rclcpp::get_logger(hardware_name_), "Joints successfully written!");

  return hardware_interface::return_type::OK;
}

}  // namespace robot_drivers

PLUGINLIB_EXPORT_CLASS(robot_drivers::DiffDriveHardware,
  hardware_interface::SystemInterface)
