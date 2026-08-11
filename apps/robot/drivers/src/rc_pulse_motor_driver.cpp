// Copyright 2026 Mumtahin Farabi
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


#include <unistd.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

#include <rclcpp/rclcpp.hpp>
#include <robot_platform_msgs/msg/drive.hpp>
#include <robot_platform_msgs/msg/feedback.hpp>

using robot_platform_msgs::msg::Drive;
using robot_platform_msgs::msg::Feedback;

constexpr int PWM_EXPORT_RETRIES = 500;
constexpr auto PWM_EXPORT_RETRY_DELAY = std::chrono::milliseconds(10);
constexpr double FEEDBACK_RATE_HZ = 50.0;
constexpr double COMMAND_TIMEOUT_SECONDS = 0.5;
constexpr int64_t PULSE_PERIOD_NS = 20'000'000;
constexpr int64_t PULSE_NEUTRAL_NS = 1'500'000;
constexpr int64_t PULSE_HALF_RANGE_NS = 500'000;

void write_sysfs(const std::string & path, const std::string & value)
{
  std::ofstream file(path);
  file << value;
  file.flush();
  if (!file.good()) {
    throw std::runtime_error("failed writing " + value + " to " + path);
  }
}

class PulseChannel
{
public:
  PulseChannel(int64_t chip, int64_t channel, bool reversed)
  : reversed(reversed),
    channel_path(
      "/sys/class/pwm/pwmchip" + std::to_string(chip) + "/pwm" + std::to_string(channel))
  {
    const std::string duty_path = channel_path + "/duty_cycle";
    if (access(channel_path.c_str(), F_OK) != 0) {
      write_sysfs(
        "/sys/class/pwm/pwmchip" + std::to_string(chip) + "/export", std::to_string(channel));
    }
    for (int attempt = 0; attempt < PWM_EXPORT_RETRIES; ++attempt) {
      if (access(duty_path.c_str(), W_OK) == 0) {
        break;
      }
      std::this_thread::sleep_for(PWM_EXPORT_RETRY_DELAY);
    }
    write_sysfs(duty_path, "0");
    write_sysfs(channel_path + "/period", std::to_string(PULSE_PERIOD_NS));
    write_sysfs(channel_path + "/enable", "1");
    duty_file = std::fopen(duty_path.c_str(), "w");
    if (duty_file == nullptr) {
      throw std::runtime_error("failed opening " + duty_path);
    }
    halt();
  }

  ~PulseChannel()
  {
    halt();
    std::fclose(duty_file);
    try {
      write_sysfs(channel_path + "/enable", "0");
    } catch (const std::runtime_error &) {
    }
  }

  void drive(double wheel_speed, double max_wheel_speed)
  {
    double fraction = std::clamp(wheel_speed / max_wheel_speed, -1.0, 1.0);
    if (reversed) {
      fraction = -fraction;
    }
    write_pulse_ns(
      PULSE_NEUTRAL_NS + static_cast<int64_t>(fraction * PULSE_HALF_RANGE_NS));
    command_fraction = wheel_speed >= 0.0 ? std::abs(fraction) : -std::abs(fraction);
    velocity = wheel_speed;
  }

  void halt()
  {
    write_pulse_ns(PULSE_NEUTRAL_NS);
    command_fraction = 0.0;
    velocity = 0.0;
  }

  double command_fraction = 0.0;
  double velocity = 0.0;
  double travel = 0.0;

private:
  void write_pulse_ns(int64_t pulse_ns)
  {
    if (pulse_ns == last_pulse_ns) {
      return;
    }
    std::rewind(duty_file);
    std::fprintf(duty_file, "%s", std::to_string(pulse_ns).c_str());
    std::fflush(duty_file);
    last_pulse_ns = pulse_ns;
  }

  const bool reversed;
  const std::string channel_path;
  std::FILE *duty_file;
  int64_t last_pulse_ns = 0;
};

class RcPulseMotorDriver : public rclcpp::Node
{
public:
  RcPulseMotorDriver()
  : Node("rc_pulse_motor_driver")
  {
    declare_parameter("max_wheel_speed", 1.0);
    for (const std::string side : {"left", "right"}) {
      declare_parameter(side + "_pwm_chip", 0);
      declare_parameter(side + "_pwm_channel", 0);
      declare_parameter(side + "_reversed", false);
    }

    max_wheel_speed = get_parameter("max_wheel_speed").as_double();
    for (size_t side_index = 0; side_index < wheels.size(); ++side_index) {
      const std::string side = side_index == 0 ? "left" : "right";
      wheels[side_index] = std::make_unique<PulseChannel>(
        get_parameter(side + "_pwm_chip").as_int(),
        get_parameter(side + "_pwm_channel").as_int(),
        get_parameter(side + "_reversed").as_bool());
    }

    last_command_time = now();
    drive_subscription = create_subscription<Drive>(
      "platform/motors/cmd_drive", rclcpp::SensorDataQoS(),
      [this](const Drive & message) {on_drive(message);});
    feedback_publisher =
      create_publisher<Feedback>("platform/motors/feedback", rclcpp::SensorDataQoS());
    feedback_timer = create_wall_timer(
      std::chrono::duration<double>(1.0 / FEEDBACK_RATE_HZ), [this]() {publish_feedback();});
  }

private:
  void on_drive(const Drive & message)
  {
    last_command_time = now();
    commanded_mode = message.mode;
    std::array<double, 2> wheel_speeds;
    if (message.mode == Drive::MODE_VELOCITY) {
      wheel_speeds = {message.drivers[0], message.drivers[1]};
    } else if (message.mode == Drive::MODE_PWM) {
      wheel_speeds = {
        message.drivers[0] * max_wheel_speed, message.drivers[1] * max_wheel_speed};
    } else {
      for (auto & wheel : wheels) {
        wheel->halt();
      }
      return;
    }
    for (size_t side_index = 0; side_index < wheels.size(); ++side_index) {
      wheels[side_index]->drive(wheel_speeds[side_index], max_wheel_speed);
    }
  }

  void publish_feedback()
  {
    const auto current_time = now();
    const bool has_timed_out =
      (current_time - last_command_time).seconds() > COMMAND_TIMEOUT_SECONDS;
    if (has_timed_out) {
      for (auto & wheel : wheels) {
        wheel->halt();
      }
    }

    Feedback message;
    message.header.stamp = current_time;
    message.commanded_mode = commanded_mode;
    message.actual_mode = has_timed_out ? Drive::MODE_NONE : commanded_mode;
    for (size_t side_index = 0; side_index < wheels.size(); ++side_index) {
      wheels[side_index]->travel += wheels[side_index]->velocity / FEEDBACK_RATE_HZ;
      message.drivers[side_index].duty_cycle = wheels[side_index]->command_fraction;
      message.drivers[side_index].measured_velocity = wheels[side_index]->velocity;
      message.drivers[side_index].measured_travel = wheels[side_index]->travel;
    }
    feedback_publisher->publish(message);
  }

  double max_wheel_speed;
  std::array<std::unique_ptr<PulseChannel>, 2> wheels;
  int8_t commanded_mode = Drive::MODE_NONE;
  rclcpp::Time last_command_time;
  rclcpp::Subscription<Drive>::SharedPtr drive_subscription;
  rclcpp::Publisher<Feedback>::SharedPtr feedback_publisher;
  rclcpp::TimerBase::SharedPtr feedback_timer;
};

int main(int argc, char **argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<RcPulseMotorDriver>());
  rclcpp::shutdown();
  return 0;
}
