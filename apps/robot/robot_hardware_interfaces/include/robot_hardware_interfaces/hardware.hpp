#ifndef ROBOT_HARDWARE_INTERFACES__HARDWARE_HPP_
#define ROBOT_HARDWARE_INTERFACES__HARDWARE_HPP_

#include <cstddef>
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
  void drive_side(int pwm_pin, int dir_pin, bool forward_level, double wheel_speed);
  void halt();

  std::string rgpiod_host_;
  std::string rgpiod_port_;
  int gpio_chip_{0};
  float pwm_frequency_{0.0f};
  double max_wheel_speed_{0.0};

  int left_pwm_pin_{-1};
  int left_dir_pin_{-1};
  bool left_forward_level_{false};
  int right_pwm_pin_{-1};
  int right_dir_pin_{-1};
  bool right_forward_level_{false};
  std::size_t left_index_{0};
  std::size_t right_index_{0};

  int sbc_{-1};
  int chip_{-1};

  std::vector<double> hw_commands_velocity_;
  std::vector<double> hw_states_position_;
  std::vector<double> hw_states_velocity_;
};

}  // namespace robot_hardware_interfaces

#endif  // ROBOT_HARDWARE_INTERFACES__HARDWARE_HPP_
