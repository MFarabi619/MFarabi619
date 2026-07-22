#ifndef ROBOT_HARDWARE_INTERFACES__HARDWARE_HPP_
#define ROBOT_HARDWARE_INTERFACES__HARDWARE_HPP_

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "hardware_interface/system_interface.hpp"
#include "hardware_interface/types/hardware_interface_return_values.hpp"
#include "rclcpp_lifecycle/state.hpp"

namespace robot_hardware_interfaces
{

class RobotHardware : public hardware_interface::SystemInterface
{
public:
  hardware_interface::CallbackReturn on_init(
    const hardware_interface::HardwareComponentInterfaceParams & params) override;

  std::vector<hardware_interface::StateInterface> export_state_interfaces() override;
  std::vector<hardware_interface::CommandInterface> export_command_interfaces() override;

  hardware_interface::CallbackReturn on_activate(
    const rclcpp_lifecycle::State & previous_state) override;
  hardware_interface::CallbackReturn on_deactivate(
    const rclcpp_lifecycle::State & previous_state) override;

  hardware_interface::return_type read(
    const rclcpp::Time & time, const rclcpp::Duration & period) override;
  hardware_interface::return_type write(
    const rclcpp::Time & time, const rclcpp::Duration & period) override;

private:
  int open_pwm_channel(const std::string & channel_path, int chip, int channel);
  void drive_side(
    int duty_fd, int dir_pin, bool forward_level, double wheel_speed,
    std::int64_t & last_duty_ns, int & last_dir_level);
  void write_duty(int duty_fd, std::int64_t duty_ns);
  void halt();
  void release();

  int gpio_chip_{0};
  float pwm_frequency_{0.0f};
  double max_wheel_speed_{0.0};
  std::int64_t period_ns_{0};

  int left_dir_pin_{-1};
  bool left_forward_level_{false};
  std::string left_channel_path_;
  int left_pwm_chip_{-1};
  int left_pwm_channel_{-1};

  int right_dir_pin_{-1};
  bool right_forward_level_{false};
  std::string right_channel_path_;
  int right_pwm_chip_{-1};
  int right_pwm_channel_{-1};

  std::size_t left_index_{0};
  std::size_t right_index_{0};

  int chip_handle_{-1};
  int left_duty_fd_{-1};
  int right_duty_fd_{-1};
  std::int64_t left_last_duty_ns_{-1};
  std::int64_t right_last_duty_ns_{-1};
  int left_last_dir_level_{-1};
  int right_last_dir_level_{-1};

  std::vector<double> hw_commands_velocity_;
  std::vector<double> hw_states_position_;
  std::vector<double> hw_states_velocity_;
};

}  // namespace robot_hardware_interfaces

#endif  // ROBOT_HARDWARE_INTERFACES__HARDWARE_HPP_
