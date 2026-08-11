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


#include <array>
#include <cmath>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include <string>

#include <rclcpp/rclcpp.hpp>
#include <robot_platform_msgs/msg/drive.hpp>
#include <robot_platform_msgs/msg/feedback.hpp>

extern "C" {
int rgpiod_start(const char *address, const char *port);
void rgpiod_stop(int sbc);
int gpiochip_open(int sbc, int device);
int gpiochip_close(int sbc, int handle);
int gpio_claim_output(int sbc, int handle, int flags, int gpio, int value);
int gpio_write(int sbc, int handle, int gpio, int value);
int tx_pwm(
  int sbc, int handle, int gpio, float frequency, float duty, int offset, int cycles);
}

using robot_platform_msgs::msg::Drive;
using robot_platform_msgs::msg::Feedback;

constexpr double FEEDBACK_RATE_HZ = 50.0;
constexpr double COMMAND_TIMEOUT_SECONDS = 0.5;
constexpr float FULL_DUTY_PERCENT = 100.0f;

class RemoteGpio
{
public:
  RemoteGpio(const std::string & host, const std::string & port, int device)
  : sbc(rgpiod_start(host.c_str(), port.c_str()))
  {
    if (sbc < 0) {
      throw std::runtime_error("could not reach rgpiod at " + host + ":" + port);
    }
    handle = gpiochip_open(sbc, device);
    if (handle < 0) {
      rgpiod_stop(sbc);
      throw std::runtime_error("gpiochip_open failed on device " + std::to_string(device));
    }
    std::fprintf(stderr, "[rgpio] connected sbc=%d handle=%d device=%d\n", sbc, handle, device);
  }

  ~RemoteGpio()
  {
    gpiochip_close(sbc, handle);
    rgpiod_stop(sbc);
  }

  void claim_output(int gpio)
  {
    if (gpio_claim_output(sbc, handle, 0, gpio, 0) < 0) {
      throw std::runtime_error("gpio_claim_output failed on gpio " + std::to_string(gpio));
    }
  }

  void write(int gpio, bool level)
  {
    const int code = gpio_write(sbc, handle, gpio, level ? 1 : 0);
    if (code < 0) {
      std::fprintf(stderr, "[rgpio] gpio_write(gpio=%d level=%d) -> %d\n", gpio, level, code);
    }
  }

  void pwm(int gpio, float frequency, float duty)
  {
    const int code = tx_pwm(sbc, handle, gpio, frequency, duty, 0, 0);
    if (code < 0) {
      std::fprintf(
        stderr, "[rgpio] tx_pwm(gpio=%d freq=%.0f duty=%.1f) -> %d\n", gpio, frequency, duty, code);
    }
  }

private:
  int sbc;
  int handle;
};

class WheelDriver
{
public:
  WheelDriver(
    RemoteGpio & gpio, int dir_line, int pwm_line, bool forward_level, float frequency)
  : gpio(gpio), dir_line(dir_line), pwm_line(pwm_line), forward_level(forward_level),
    frequency(frequency)
  {
    gpio.claim_output(dir_line);
    gpio.claim_output(pwm_line);
    halt();
  }

  void drive(double wheel_speed, double max_wheel_speed)
  {
    const bool forward = wheel_speed >= 0.0;
    set_direction(forward == forward_level);
    const double fraction = std::min(std::abs(wheel_speed) / max_wheel_speed, 1.0);
    set_duty(static_cast<float>(fraction) * FULL_DUTY_PERCENT);
    duty_fraction = forward ? fraction : -fraction;
    velocity = wheel_speed;
  }

  void halt()
  {
    // Stopping means zero duty at the same frequency; rgpio treats frequency 0 as
    // "cancel waveform" and leaves the pin in an undefined level, so never send it.
    set_duty(0.0f);
    duty_fraction = 0.0;
    velocity = 0.0;
  }

  double duty_fraction = 0.0;
  double velocity = 0.0;
  double travel = 0.0;

private:
  void set_direction(bool level)
  {
    if (level != last_direction) {
      gpio.write(dir_line, level);
      last_direction = level;
    }
  }

  void set_duty(float duty)
  {
    if (duty != last_duty) {
      gpio.pwm(pwm_line, frequency, duty);
      last_duty = duty;
    }
  }

  RemoteGpio & gpio;
  int dir_line;
  int pwm_line;
  bool forward_level;
  float frequency;
  int last_direction = -1;
  float last_duty = -1.0f;
};

class RgpioPwmDirMotorDriver : public rclcpp::Node
{
public:
  RgpioPwmDirMotorDriver()
  : Node("rgpio_pwm_dir_motor_driver")
  {
    declare_parameter("rgpiod_host", "localhost");
    declare_parameter("rgpiod_port", "8889");
    declare_parameter("gpio_chip", 0);
    declare_parameter("pwm_frequency_hz", 1000.0);
    declare_parameter("max_wheel_speed", 1.0);
    declare_parameter("left_dir_line", 26);
    declare_parameter("left_pwm_line", 12);
    declare_parameter("left_forward_level", true);
    declare_parameter("right_dir_line", 24);
    declare_parameter("right_pwm_line", 13);
    declare_parameter("right_forward_level", false);

    max_wheel_speed = get_parameter("max_wheel_speed").as_double();
    const auto frequency = static_cast<float>(get_parameter("pwm_frequency_hz").as_double());

    gpio = std::make_unique<RemoteGpio>(
      get_parameter("rgpiod_host").as_string(),
      get_parameter("rgpiod_port").as_string(),
      get_parameter("gpio_chip").as_int());

    wheels[Drive::LEFT] = std::make_unique<WheelDriver>(
      *gpio,
      get_parameter("left_dir_line").as_int(),
      get_parameter("left_pwm_line").as_int(),
      get_parameter("left_forward_level").as_bool(),
      frequency);
    wheels[Drive::RIGHT] = std::make_unique<WheelDriver>(
      *gpio,
      get_parameter("right_dir_line").as_int(),
      get_parameter("right_pwm_line").as_int(),
      get_parameter("right_forward_level").as_bool(),
      frequency);

    last_command_time = now();
    drive_subscription = create_subscription<Drive>(
      "platform/motors/cmd_drive", rclcpp::SensorDataQoS(),
      [this](const Drive & message) {on_drive(message);});
    feedback_publisher =
      create_publisher<Feedback>("platform/motors/feedback", rclcpp::SensorDataQoS());
    feedback_timer = create_wall_timer(
      std::chrono::duration<double>(1.0 / FEEDBACK_RATE_HZ), [this]() {publish_feedback();});
  }

  ~RgpioPwmDirMotorDriver() override
  {
    for (auto & wheel : wheels) {
      if (wheel) {
        wheel->halt();
      }
    }
  }

private:
  void on_drive(const Drive & message)
  {
    last_command_time = now();
    commanded_mode = message.mode;
    std::array<double, 2> wheel_speeds;
    if (message.mode == Drive::MODE_VELOCITY) {
      wheel_speeds = {message.drivers[Drive::LEFT], message.drivers[Drive::RIGHT]};
    } else if (message.mode == Drive::MODE_PWM) {
      wheel_speeds = {
        message.drivers[Drive::LEFT] * max_wheel_speed,
        message.drivers[Drive::RIGHT] * max_wheel_speed};
    } else {
      for (auto & wheel : wheels) {
        wheel->halt();
      }
      return;
    }
    for (size_t side = 0; side < wheels.size(); ++side) {
      wheels[side]->drive(wheel_speeds[side], max_wheel_speed);
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
    for (size_t side = 0; side < wheels.size(); ++side) {
      wheels[side]->travel += wheels[side]->velocity / FEEDBACK_RATE_HZ;
      message.drivers[side].duty_cycle = wheels[side]->duty_fraction;
      message.drivers[side].measured_velocity = wheels[side]->velocity;
      message.drivers[side].measured_travel = wheels[side]->travel;
    }
    feedback_publisher->publish(message);
  }

  double max_wheel_speed;
  std::unique_ptr<RemoteGpio> gpio;
  std::array<std::unique_ptr<WheelDriver>, 2> wheels;
  int8_t commanded_mode = Drive::MODE_NONE;
  rclcpp::Time last_command_time;
  rclcpp::Subscription<Drive>::SharedPtr drive_subscription;
  rclcpp::Publisher<Feedback>::SharedPtr feedback_publisher;
  rclcpp::TimerBase::SharedPtr feedback_timer;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<RgpioPwmDirMotorDriver>());
  rclcpp::shutdown();
  return 0;
}
