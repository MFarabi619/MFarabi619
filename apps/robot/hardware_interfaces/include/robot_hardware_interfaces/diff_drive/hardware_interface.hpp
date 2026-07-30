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

#ifndef ROBOT_HARDWARE_INTERFACES__DIFF_DRIVE__HARDWARE_INTERFACE_HPP_
#define ROBOT_HARDWARE_INTERFACES__DIFF_DRIVE__HARDWARE_INTERFACE_HPP_

#include <cstdint>
#include <mutex>
#include <string>

#include "rclcpp/rclcpp.hpp"

#include "robot_platform_msgs/msg/drive.hpp"
#include "robot_platform_msgs/msg/feedback.hpp"

namespace robot_hardware_interfaces
{

class DiffDriveHardwareInterface
  : public rclcpp::Node
{
public:
  explicit DiffDriveHardwareInterface(std::string node_name);
  void drive_command(const float & left_wheel, const float & right_wheel, const int8_t & mode);
  robot_platform_msgs::msg::Feedback get_feedback();

private:
  void feedback_callback(const robot_platform_msgs::msg::Feedback::ConstSharedPtr & msg);

  rclcpp::Publisher<robot_platform_msgs::msg::Drive>::SharedPtr drive_pub_;
  rclcpp::Subscription<robot_platform_msgs::msg::Feedback>::SharedPtr feedback_sub_;

  robot_platform_msgs::msg::Feedback feedback_;
  std::mutex feedback_mutex_;
};

}  // namespace robot_hardware_interfaces

#endif  // ROBOT_HARDWARE_INTERFACES__DIFF_DRIVE__HARDWARE_INTERFACE_HPP_
