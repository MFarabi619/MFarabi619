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

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/joy.hpp>

using sensor_msgs::msg::Joy;

constexpr double JOY_RATE_HZ = 50.0;
constexpr int64_t NANOSECONDS_PER_MICROSECOND = 1'000;
constexpr int64_t PULSE_TIMEOUT_NS = 100'000'000;
constexpr int64_t EVENT_WAIT_TIMEOUT_NS = 100'000'000;
constexpr int64_t PULSE_CENTER_US = 1500;
constexpr int64_t PULSE_HALF_RANGE_US = 500;
constexpr int64_t PULSE_MIN_VALID_US = 800;
constexpr int64_t PULSE_MAX_VALID_US = 2200;
constexpr unsigned long DEBOUNCE_PERIOD_US = 50;
constexpr size_t EVENT_BUFFER_CAPACITY = 64;

struct RcChannel
{
  unsigned int line = 0;
  int64_t rising_ns = 0;
  std::atomic<double> position{0.0};
  std::atomic<int64_t> last_pulse_ns{0};
};

class RcReceiverJoy : public rclcpp::Node
{
public:
  RcReceiverJoy()
  : Node("rc_receiver_joy")
  {
    declare_parameter("gpio_chip", 0);
    declare_parameter("channel_1_line", 0);
    declare_parameter("channel_2_line", 0);
    declare_parameter("deadzone", 0.05);
    declare_parameter("tank_mixed", false);

    deadzone = get_parameter("deadzone").as_double();
    is_tank_mixed = get_parameter("tank_mixed").as_bool();
    channels[CHANNEL_1].line =
      static_cast<unsigned int>(get_parameter("channel_1_line").as_int());
    channels[CHANNEL_2].line =
      static_cast<unsigned int>(get_parameter("channel_2_line").as_int());

    const std::string chip_path =
      "/dev/gpiochip" + std::to_string(get_parameter("gpio_chip").as_int());
    chip = gpiod_chip_open(chip_path.c_str());
    if (chip == nullptr) {
      throw std::runtime_error("failed opening " + chip_path);
    }
    const std::array<unsigned int, 2> lines = {
      channels[CHANNEL_1].line, channels[CHANNEL_2].line};
    gpiod_line_settings *settings = gpiod_line_settings_new();
    gpiod_line_settings_set_direction(settings, GPIOD_LINE_DIRECTION_INPUT);
    gpiod_line_settings_set_edge_detection(settings, GPIOD_LINE_EDGE_BOTH);
    gpiod_line_settings_set_event_clock(settings, GPIOD_LINE_CLOCK_MONOTONIC);
    gpiod_line_settings_set_debounce_period_us(settings, DEBOUNCE_PERIOD_US);
    gpiod_line_config *line_config = gpiod_line_config_new();
    gpiod_line_config_add_line_settings(line_config, lines.data(), lines.size(), settings);
    gpiod_request_config *request_config = gpiod_request_config_new();
    gpiod_request_config_set_consumer(request_config, get_name());
    request = gpiod_chip_request_lines(chip, request_config, line_config);
    gpiod_request_config_free(request_config);
    gpiod_line_config_free(line_config);
    gpiod_line_settings_free(settings);
    if (request == nullptr) {
      throw std::runtime_error("failed requesting rc lines on " + chip_path);
    }

    event_buffer = gpiod_edge_event_buffer_new(EVENT_BUFFER_CAPACITY);
    edge_reader = std::thread([this]() {read_edges();});
    joy_publisher = create_publisher<Joy>("joy", rclcpp::SensorDataQoS());
    joy_timer = create_wall_timer(
      std::chrono::duration<double>(1.0 / JOY_RATE_HZ), [this]() {publish_joy();});
  }

  ~RcReceiverJoy() override
  {
    is_running = false;
    edge_reader.join();
    gpiod_edge_event_buffer_free(event_buffer);
    gpiod_line_request_release(request);
    gpiod_chip_close(chip);
  }

private:
  enum Channel {CHANNEL_1 = 0, CHANNEL_2 = 1};

  void read_edges()
  {
    while (is_running) {
      const int wait_result =
        gpiod_line_request_wait_edge_events(request, EVENT_WAIT_TIMEOUT_NS);
      if (wait_result <= 0) {
        continue;
      }
      const int event_count = gpiod_line_request_read_edge_events(
        request, event_buffer, EVENT_BUFFER_CAPACITY);
      for (int event_index = 0; event_index < event_count; ++event_index) {
        gpiod_edge_event *event =
          gpiod_edge_event_buffer_get_event(event_buffer, event_index);
        const unsigned int line = gpiod_edge_event_get_line_offset(event);
        const auto timestamp_ns =
          static_cast<int64_t>(gpiod_edge_event_get_timestamp_ns(event));
        for (auto & channel : channels) {
          if (channel.line == line) {
            on_edge(channel, gpiod_edge_event_get_event_type(event), timestamp_ns);
          }
        }
      }
    }
  }

  void on_edge(RcChannel & channel, gpiod_edge_event_type event_type, int64_t timestamp_ns)
  {
    if (event_type == GPIOD_EDGE_EVENT_RISING_EDGE) {
      channel.rising_ns = timestamp_ns;
      return;
    }
    if (channel.rising_ns == 0) {
      return;
    }
    const int64_t pulse_width_us =
      (timestamp_ns - channel.rising_ns) / NANOSECONDS_PER_MICROSECOND;
    channel.rising_ns = 0;
    if (pulse_width_us < PULSE_MIN_VALID_US || pulse_width_us > PULSE_MAX_VALID_US) {
      return;
    }
    channel.position.store(normalize(pulse_width_us));
    channel.last_pulse_ns.store(timestamp_ns);
  }

  double normalize(int64_t pulse_width_us) const
  {
    const double raw_position = std::clamp(
      static_cast<double>(pulse_width_us - PULSE_CENTER_US) / PULSE_HALF_RANGE_US, -1.0, 1.0);
    if (std::abs(raw_position) < deadzone) {
      return 0.0;
    }
    const double sign = raw_position > 0.0 ? 1.0 : -1.0;
    return (raw_position - sign * deadzone) / (1.0 - deadzone);
  }

  void publish_joy()
  {
    const int64_t now_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count();
    for (const auto & channel : channels) {
      if (now_ns - channel.last_pulse_ns.load() > PULSE_TIMEOUT_NS) {
        return;
      }
    }
    const double channel_1 = channels[CHANNEL_1].position.load();
    const double channel_2 = channels[CHANNEL_2].position.load();
    double steering = channel_1;
    double throttle = channel_2;
    if (is_tank_mixed) {
      steering = std::clamp(channel_2 - channel_1, -1.0, 1.0);
      throttle = std::clamp(channel_1 + channel_2, -1.0, 1.0);
    }
    Joy message;
    message.header.stamp = now();
    message.header.frame_id = "joy";
    message.axes = {
      static_cast<float>(steering), static_cast<float>(throttle)};
    joy_publisher->publish(message);
  }

  double deadzone;
  bool is_tank_mixed;
  std::array<RcChannel, 2> channels;
  gpiod_chip *chip = nullptr;
  gpiod_line_request *request = nullptr;
  gpiod_edge_event_buffer *event_buffer = nullptr;
  std::atomic<bool> is_running{true};
  std::thread edge_reader;
  rclcpp::Publisher<Joy>::SharedPtr joy_publisher;
  rclcpp::TimerBase::SharedPtr joy_timer;
};

int main(int argc, char **argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<RcReceiverJoy>());
  rclcpp::shutdown();
  return 0;
}
