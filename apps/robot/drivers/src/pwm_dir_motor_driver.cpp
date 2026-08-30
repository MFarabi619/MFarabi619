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


#include <gpiod.h>
#include <unistd.h>

#include <array>
#include <chrono>
#include <cmath>
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
constexpr int64_t NANOSECONDS_PER_SECOND = 1'000'000'000;
constexpr double FEEDBACK_RATE_HZ = 50.0;
constexpr double COMMAND_TIMEOUT_SECONDS = 0.5;

void write_sysfs(const std::string & path, const std::string & value)
{
  std::ofstream file(path);
  file << value;
  file.flush();
  if (!file.good()) {
    throw std::runtime_error("failed writing " + value + " to " + path);
  }
}

class PwmChannel
{
public:
  PwmChannel(int64_t chip, int64_t channel, int64_t period_ns)
  : period_ns(period_ns),
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
    write_sysfs(channel_path + "/period", std::to_string(period_ns));
    write_sysfs(channel_path + "/enable", "1");
    duty_file = std::fopen(duty_path.c_str(), "w");
    if (duty_file == nullptr) {
      throw std::runtime_error("failed opening " + duty_path);
    }
  }

  ~PwmChannel()
  {
    write_duty_ns(0);
    std::fclose(duty_file);
    try {
      write_sysfs(channel_path + "/enable", "0");
    } catch (const std::runtime_error &) {
    }
  }

  void write_duty_ns(int64_t duty_ns)
  {
    if (duty_ns == last_duty_ns) {
      return;
    }
    std::rewind(duty_file);
    std::fprintf(duty_file, "%s", std::to_string(duty_ns).c_str());
    std::fflush(duty_file);
    last_duty_ns = duty_ns;
  }

  const int64_t period_ns;

private:
  const std::string channel_path;
  std::FILE *duty_file;
  int64_t last_duty_ns = 0;
};

class WheelDriver
{
public:
  WheelDriver(
    gpiod_line_request *dir_request, unsigned int dir_line, bool forward_level,
    int64_t pwm_chip, int64_t pwm_channel, int64_t period_ns)
  : dir_request(dir_request),
    dir_line(dir_line),
    forward_level(forward_level),
    pwm(pwm_chip, pwm_channel, period_ns)
  {
  }

  void drive(double wheel_speed, double max_wheel_speed)
  {
    if (!std::isfinite(wheel_speed) || !std::isfinite(max_wheel_speed) ||
      max_wheel_speed <= 0.0)
    {
      halt();
      return;
    }
    const int dir_level = ((wheel_speed >= 0.0) == forward_level) ? 1 : 0;
    if (dir_level != last_dir_level) {
      gpiod_line_request_set_value(
        dir_request, dir_line,
        dir_level ? GPIOD_LINE_VALUE_ACTIVE : GPIOD_LINE_VALUE_INACTIVE);
      last_dir_level = dir_level;
    }
    double fraction = std::min(std::abs(wheel_speed) / max_wheel_speed, 1.0);
    pwm.write_duty_ns(static_cast<int64_t>(fraction * pwm.period_ns));
    duty_fraction = wheel_speed >= 0.0 ? fraction : -fraction;
    velocity = wheel_speed;
  }

  void halt()
  {
    pwm.write_duty_ns(0);
    duty_fraction = 0.0;
    velocity = 0.0;
  }

  double duty_fraction = 0.0;
  double velocity = 0.0;
  double travel = 0.0;

private:
  gpiod_line_request *dir_request;
  unsigned int dir_line;
  bool forward_level;
  PwmChannel pwm;
  int last_dir_level = -1;
};

class PwmDirMotorDriver : public rclcpp::Node
{
public:
  PwmDirMotorDriver()
  : Node("pwm_dir_motor_driver")
  {
    declare_parameter("gpio_chip", 0);
    declare_parameter("pwm_frequency_hz", 20000.0);
    declare_parameter("max_wheel_speed", 1.0);
    for (const std::string side : {"left", "right"}) {
      declare_parameter(side + "_pwm_chip", 0);
      declare_parameter(side + "_pwm_channel", 0);
      declare_parameter(side + "_dir_line", 0);
      declare_parameter(side + "_forward_level", true);
    }

    max_wheel_speed = get_parameter("max_wheel_speed").as_double();
    const auto period_ns = static_cast<int64_t>(
      NANOSECONDS_PER_SECOND / get_parameter("pwm_frequency_hz").as_double());
    const std::array<unsigned int, 2> dir_lines = {
      static_cast<unsigned int>(get_parameter("left_dir_line").as_int()),
      static_cast<unsigned int>(get_parameter("right_dir_line").as_int()),
    };

    const std::string chip_path =
      "/dev/gpiochip" + std::to_string(get_parameter("gpio_chip").as_int());
    dir_chip = gpiod_chip_open(chip_path.c_str());
    if (dir_chip == nullptr) {
      throw std::runtime_error("failed opening " + chip_path);
    }
    gpiod_line_settings *settings = gpiod_line_settings_new();
    gpiod_line_settings_set_direction(settings, GPIOD_LINE_DIRECTION_OUTPUT);
    gpiod_line_settings_set_output_value(settings, GPIOD_LINE_VALUE_INACTIVE);
    gpiod_line_config *line_config = gpiod_line_config_new();
    gpiod_line_config_add_line_settings(line_config, dir_lines.data(), dir_lines.size(), settings);
    gpiod_request_config *request_config = gpiod_request_config_new();
    gpiod_request_config_set_consumer(request_config, get_name());
    dir_request = gpiod_chip_request_lines(dir_chip, request_config, line_config);
    gpiod_request_config_free(request_config);
    gpiod_line_config_free(line_config);
    gpiod_line_settings_free(settings);
    if (dir_request == nullptr) {
      throw std::runtime_error("failed requesting dir lines on " + chip_path);
    }

    for (size_t side_index = 0; side_index < wheels.size(); ++side_index) {
      const std::string side = side_index == 0 ? "left" : "right";
      wheels[side_index] = std::make_unique<WheelDriver>(
        dir_request, dir_lines[side_index],
        get_parameter(side + "_forward_level").as_bool(),
        get_parameter(side + "_pwm_chip").as_int(),
        get_parameter(side + "_pwm_channel").as_int(),
        period_ns);
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

  ~PwmDirMotorDriver() override
  {
    for (auto & wheel : wheels) {
      wheel.reset();
    }
    gpiod_line_request_release(dir_request);
    gpiod_chip_close(dir_chip);
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
      message.drivers[side_index].duty_cycle = wheels[side_index]->duty_fraction;
      message.drivers[side_index].measured_velocity = wheels[side_index]->velocity;
      message.drivers[side_index].measured_travel = wheels[side_index]->travel;
    }
    feedback_publisher->publish(message);
  }

  double max_wheel_speed;
  gpiod_chip *dir_chip = nullptr;
  gpiod_line_request *dir_request = nullptr;
  std::array<std::unique_ptr<WheelDriver>, 2> wheels;
  int8_t commanded_mode = Drive::MODE_NONE;
  rclcpp::Time last_command_time;
  rclcpp::Subscription<Drive>::SharedPtr drive_subscription;
  rclcpp::Publisher<Feedback>::SharedPtr feedback_publisher;
  rclcpp::TimerBase::SharedPtr feedback_timer;
};

int main(int argc, char **argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<PwmDirMotorDriver>());
  rclcpp::shutdown();
  return 0;
}
