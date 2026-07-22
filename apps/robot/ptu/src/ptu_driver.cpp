#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

#include "rclcpp/rclcpp.hpp"
#include "geometry_msgs/msg/twist.hpp"
#include "sensor_msgs/msg/joint_state.hpp"

#include "rgpio.h"

namespace {
constexpr int kMode1 = 0x00;
constexpr int kPrescale = 0xFE;
constexpr int kLed0OnL = 0x06;
constexpr int kRegistersPerChannel = 4;
constexpr int kMode1Sleep = 0x10;
constexpr int kMode1AutoIncrement = 0x20;

constexpr double kOscillatorHz = 25000000.0;
constexpr double kCountsPerPeriod = 4096.0;
constexpr double kServoFrequencyHz = 50.0;
constexpr double kPeriodUsec = 1000000.0 / kServoFrequencyHz;
constexpr double kServoMinimumUsec = 500.0;
constexpr double kServoMaximumUsec = 2400.0;
constexpr double kServoRangeDeg = 180.0;
constexpr double kServoCenterDeg = 90.0;

double servo_degrees(double center_deg, double radians) {
  return center_deg + radians * 180.0 / M_PI;
}
}  // namespace

class PanTiltUnit : public rclcpp::Node {
 public:
  PanTiltUnit() : rclcpp::Node("ptu_driver") {
    host_ = declare_parameter<std::string>("rgpiod_host", "rpi5-16-2");
    port_ = declare_parameter<std::string>("rgpiod_port", "8889");
    const int bus = declare_parameter<int>("i2c_bus", 1);
    const int address = declare_parameter<int>("pca9685_addr", 0x40);
    pan_channel_ = declare_parameter<int>("pan_channel", 1);
    tilt_channel_ = declare_parameter<int>("tilt_channel", 0);
    pan_center_ = declare_parameter<double>("pan_center", kServoCenterDeg);
    tilt_center_ = declare_parameter<double>("tilt_center", kServoCenterDeg);
    pan_joint_ = declare_parameter<std::string>("pan_joint", "ptu_0_pan");
    tilt_joint_ = declare_parameter<std::string>("tilt_joint", "ptu_0_tilt");
    travel_ = declare_parameter<double>("travel", M_PI / 2.0);
    control_rate_ = declare_parameter<double>("publish_rate", 20.0);
    command_timeout_ = declare_parameter<double>("command_timeout", 0.5);

    sbc_ = rgpiod_start(host_.c_str(), port_.c_str());
    if (sbc_ < 0) {
      RCLCPP_FATAL(get_logger(), "rgpiod_start(%s:%s) failed: %d",
                   host_.c_str(), port_.c_str(), sbc_);
      throw std::runtime_error("cannot reach rgpiod");
    }
    handle_ = i2c_open(sbc_, bus, address, 0);
    if (handle_ < 0) {
      RCLCPP_FATAL(get_logger(), "i2c_open(bus %d, addr 0x%x) failed: %d",
                   bus, address, handle_);
      throw std::runtime_error("cannot open PCA9685");
    }
    initialize_pca9685();
    drive();

    command_ = create_subscription<sensor_msgs::msg::JointState>(
        "cmd", rclcpp::SensorDataQoS(),
        std::bind(&PanTiltUnit::on_command, this, std::placeholders::_1));
    velocity_ = create_subscription<geometry_msgs::msg::Twist>(
        "cmd_vel", rclcpp::SensorDataQoS(),
        std::bind(&PanTiltUnit::on_velocity, this, std::placeholders::_1));
    state_ = create_publisher<sensor_msgs::msg::JointState>(
        "state", rclcpp::SensorDataQoS());
    last_velocity_ = now();
    timer_ = create_wall_timer(
        std::chrono::duration<double>(1.0 / control_rate_),
        std::bind(&PanTiltUnit::on_tick, this));

    RCLCPP_INFO(get_logger(), "PTU driver %s:%s -> PCA9685 pan=ch%d tilt=ch%d",
                host_.c_str(), port_.c_str(), pan_channel_, tilt_channel_);
  }

  ~PanTiltUnit() override {
    if (sbc_ >= 0) {
      if (handle_ >= 0) {
        i2c_close(sbc_, handle_);
      }
      rgpiod_stop(sbc_);
    }
  }

 private:
  void initialize_pca9685() {
    const int prescale = static_cast<int>(
        std::lround(kOscillatorHz / (kCountsPerPeriod * kServoFrequencyHz)) - 1);
    i2c_write_byte_data(sbc_, handle_, kMode1, kMode1Sleep);
    i2c_write_byte_data(sbc_, handle_, kPrescale, prescale);
    i2c_write_byte_data(sbc_, handle_, kMode1, kMode1AutoIncrement);
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }

  void set_channel(int channel, std::uint16_t on_count, std::uint16_t off_count) {
    const int reg = kLed0OnL + kRegistersPerChannel * channel;
    char block[4] = {
        static_cast<char>(on_count & 0xFF), static_cast<char>(on_count >> 8),
        static_cast<char>(off_count & 0xFF), static_cast<char>(off_count >> 8)};
    i2c_write_i2c_block_data(sbc_, handle_, reg, block, 4);
  }

  void set_servo_angle(int channel, double angle_deg) {
    const double angle = std::clamp(angle_deg, 0.0, kServoRangeDeg);
    const double pulse_usec = kServoMinimumUsec +
        (kServoMaximumUsec - kServoMinimumUsec) * angle / kServoRangeDeg;
    const auto off_count = static_cast<std::uint16_t>(
        std::lround(pulse_usec / kPeriodUsec * kCountsPerPeriod));
    set_channel(channel, 0, off_count);
  }

  void drive() {
    set_servo_angle(pan_channel_, servo_degrees(pan_center_, pan_radians_));
    set_servo_angle(tilt_channel_, servo_degrees(tilt_center_, tilt_radians_));
  }

  void on_command(const sensor_msgs::msg::JointState::ConstSharedPtr & msg) {
    for (std::size_t i = 0; i < msg->name.size() && i < msg->position.size(); ++i) {
      const double position = std::clamp(msg->position[i], -travel_, travel_);
      if (msg->name[i] == pan_joint_) {
        pan_radians_ = position;
      } else if (msg->name[i] == tilt_joint_) {
        tilt_radians_ = position;
      }
    }
    pan_rate_ = 0.0;
    tilt_rate_ = 0.0;
    drive();
  }

  void on_velocity(const geometry_msgs::msg::Twist::ConstSharedPtr & msg) {
    pan_rate_ = msg->angular.z;
    tilt_rate_ = msg->linear.x;
    last_velocity_ = now();
  }

  void on_tick() {
    if ((now() - last_velocity_).seconds() > command_timeout_) {
      pan_rate_ = 0.0;
      tilt_rate_ = 0.0;
    }
    if (pan_rate_ != 0.0 || tilt_rate_ != 0.0) {
      const double dt = 1.0 / control_rate_;
      pan_radians_ = std::clamp(pan_radians_ + pan_rate_ * dt, -travel_, travel_);
      tilt_radians_ = std::clamp(tilt_radians_ + tilt_rate_ * dt, -travel_, travel_);
      drive();
    }
    publish_state();
  }

  void publish_state() {
    sensor_msgs::msg::JointState state;
    state.header.stamp = now();
    state.name = {pan_joint_, tilt_joint_};
    state.position = {pan_radians_, tilt_radians_};
    state_->publish(state);
  }

  std::string host_;
  std::string port_;
  std::string pan_joint_;
  std::string tilt_joint_;
  int sbc_ = -1;
  int handle_ = -1;
  int pan_channel_ = 1;
  int tilt_channel_ = 0;
  double pan_center_ = 90.0;
  double tilt_center_ = 90.0;
  double travel_ = M_PI / 2.0;
  double control_rate_ = 20.0;
  double command_timeout_ = 0.5;
  double pan_radians_ = 0.0;
  double tilt_radians_ = 0.0;
  double pan_rate_ = 0.0;
  double tilt_rate_ = 0.0;
  rclcpp::Time last_velocity_;
  rclcpp::Subscription<sensor_msgs::msg::JointState>::SharedPtr command_;
  rclcpp::Subscription<geometry_msgs::msg::Twist>::SharedPtr velocity_;
  rclcpp::Publisher<sensor_msgs::msg::JointState>::SharedPtr state_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char** argv) {
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<PanTiltUnit>());
  rclcpp::shutdown();
  return 0;
}
