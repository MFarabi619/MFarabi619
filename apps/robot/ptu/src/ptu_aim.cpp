#include <algorithm>
#include <cmath>
#include <memory>
#include <string>

#include "geometry_msgs/msg/point_stamped.hpp"
#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/joint_state.hpp"
#include "tf2_geometry_msgs/tf2_geometry_msgs.hpp"
#include "tf2_ros/buffer.hpp"
#include "tf2_ros/transform_listener.hpp"

class PanTiltAim : public rclcpp::Node {
 public:
  PanTiltAim() : rclcpp::Node("ptu_aim") {
    base_frame_ = declare_parameter<std::string>("base_frame", "ptu_0_base_link");
    pan_joint_ = declare_parameter<std::string>("pan_joint", "ptu_0_pan");
    tilt_joint_ = declare_parameter<std::string>("tilt_joint", "ptu_0_tilt");
    travel_ = declare_parameter<double>("travel", M_PI / 2.0);

    buffer_ = std::make_unique<tf2_ros::Buffer>(get_clock());
    listener_ = std::make_shared<tf2_ros::TransformListener>(*buffer_);
    command_ = create_publisher<sensor_msgs::msg::JointState>(
        "cmd", rclcpp::SensorDataQoS());
    look_at_ = create_subscription<geometry_msgs::msg::PointStamped>(
        "look_at", rclcpp::SensorDataQoS(),
        std::bind(&PanTiltAim::on_look_at, this, std::placeholders::_1));
    RCLCPP_INFO(get_logger(), "ptu aim: look_at -> pan/tilt about %s", base_frame_.c_str());
  }

 private:
  void on_look_at(const geometry_msgs::msg::PointStamped::ConstSharedPtr & msg) {
    geometry_msgs::msg::PointStamped target;
    try {
      target = buffer_->transform(*msg, base_frame_, tf2::durationFromSec(0.2));
    } catch (const tf2::TransformException & error) {
      RCLCPP_WARN(get_logger(), "cannot transform look_at into %s: %s",
                  base_frame_.c_str(), error.what());
      return;
    }
    const double x = target.point.x;
    const double y = target.point.y;
    const double z = target.point.z;
    const double pan = std::clamp(std::atan2(y, x), -travel_, travel_);
    const double tilt = std::clamp(-std::atan2(z, std::hypot(x, y)), -travel_, travel_);

    sensor_msgs::msg::JointState command;
    command.header.stamp = now();
    command.name = {pan_joint_, tilt_joint_};
    command.position = {pan, tilt};
    command_->publish(command);
  }

  std::string base_frame_;
  std::string pan_joint_;
  std::string tilt_joint_;
  double travel_ = M_PI / 2.0;
  std::unique_ptr<tf2_ros::Buffer> buffer_;
  std::shared_ptr<tf2_ros::TransformListener> listener_;
  rclcpp::Publisher<sensor_msgs::msg::JointState>::SharedPtr command_;
  rclcpp::Subscription<geometry_msgs::msg::PointStamped>::SharedPtr look_at_;
};

int main(int argc, char** argv) {
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<PanTiltAim>());
  rclcpp::shutdown();
  return 0;
}
