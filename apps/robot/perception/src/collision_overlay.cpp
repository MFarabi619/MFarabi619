// Copyright 2026 Mumtahin Farabi
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.


#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include <foxglove_msgs/msg/image_annotations.hpp>
#include <image_geometry/pinhole_camera_model.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/camera_info.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>
#include <sensor_msgs/point_cloud2_iterator.hpp>
#include <tf2_geometry_msgs/tf2_geometry_msgs.hpp>
#include <tf2_ros/buffer.hpp>
#include <tf2_ros/transform_listener.hpp>

using foxglove_msgs::msg::CircleAnnotation;
using foxglove_msgs::msg::Color;
using foxglove_msgs::msg::ImageAnnotations;
using foxglove_msgs::msg::Point2;
using foxglove_msgs::msg::TextAnnotation;

constexpr double POINT_DIAMETER_PIXELS = 5.0;
constexpr double POINT_THICKNESS_PIXELS = 1.0;
constexpr size_t MAX_POINTS_PER_ZONE = 200;
constexpr double LABEL_MARGIN_PIXELS = 10.0;
constexpr double LABEL_FONT_SIZE = 18.0;

Color make_color(float red, float green, float blue, float alpha)
{
  Color color;
  color.r = red;
  color.g = green;
  color.b = blue;
  color.a = alpha;
  return color;
}

const Color STOP_COLOR = make_color(1.0, 0.25, 0.2, 0.85);
const Color SLOWDOWN_COLOR = make_color(1.0, 0.7, 0.1, 0.6);
const Color TEXT_BACKGROUND_COLOR = make_color(0.0, 0.0, 0.0, 0.6);

struct Zone
{
  Color color;
  size_t point_count = 0;
  std::vector<CircleAnnotation> markers;
  bool has_nearest = false;
  double nearest_distance = 0.0;
  Point2 nearest_pixel;
};

class CollisionOverlay : public rclcpp::Node
{
public:
  CollisionOverlay()
  : Node("collision_overlay"),
    tf_buffer_(get_clock()),
    tf_listener_(tf_buffer_)
  {
    const std::string cloud_topic =
      declare_parameter("cloud_topic", std::string("sensors/camera_0/depth/points"));
    const std::string camera_info_topic =
      declare_parameter("camera_info_topic", std::string("sensors/camera_0/color/camera_info"));
    const std::string overlay_topic =
      declare_parameter("overlay_topic", std::string("perception/collision/overlay"));
    base_frame_ = declare_parameter("base_frame_", std::string("base_link"));
    min_height_ = declare_parameter("min_height_", 0.15);
    max_height_ = declare_parameter("max_height_", 2.0);
    stop_x_range_ = declare_parameter("stop_x_range_", std::vector<double>{0.0, 1.45});
    stop_half_width_ = declare_parameter("stop_half_width_", 0.45);
    slowdown_x_range_ = declare_parameter("slowdown_x_range_", std::vector<double>{0.55, 2.6});
    slowdown_half_width_ = declare_parameter("slowdown_half_width_", 0.5);
    sample_stride_ = declare_parameter("sample_stride_", 4);

    overlay_publisher_ =
      create_publisher<ImageAnnotations>(overlay_topic, rclcpp::SensorDataQoS());
    camera_info_subscription_ = create_subscription<sensor_msgs::msg::CameraInfo>(
      camera_info_topic, rclcpp::SensorDataQoS(),
      [this](const sensor_msgs::msg::CameraInfo & message) {on_camera_info(message);});
    cloud_subscription_ = create_subscription<sensor_msgs::msg::PointCloud2>(
      cloud_topic, rclcpp::SensorDataQoS(),
      [this](const sensor_msgs::msg::PointCloud2 & message) {on_cloud(message);});
    RCLCPP_INFO(
      get_logger(), "collision overlay: %s -> %s",
      cloud_topic.c_str(), overlay_topic.c_str());
  }

private:
  void on_camera_info(const sensor_msgs::msg::CameraInfo & message)
  {
    camera_model_.fromCameraInfo(message);
    image_width_ = message.width;
    image_height_ = message.height;
    has_camera_model_ = true;
  }

  void on_cloud(const sensor_msgs::msg::PointCloud2 & message)
  {
    if (!has_camera_model_) {
      return;
    }
    geometry_msgs::msg::TransformStamped transform_message;
    try {
      transform_message = tf_buffer_.lookupTransform(
        base_frame_, message.header.frame_id, tf2::TimePointZero);
    } catch (const tf2::TransformException &) {
      return;
    }
    tf2::Transform to_base;
    tf2::fromMsg(transform_message.transform, to_base);

    Zone stop_zone{STOP_COLOR, 0, {}, false, 0.0, Point2()};
    Zone slowdown_zone{SLOWDOWN_COLOR, 0, {}, false, 0.0, Point2()};

    sensor_msgs::PointCloud2ConstIterator<float> x_iterator(message, "x");
    sensor_msgs::PointCloud2ConstIterator<float> y_iterator(message, "y");
    sensor_msgs::PointCloud2ConstIterator<float> z_iterator(message, "z");
    size_t point_index = 0;
    for (; x_iterator != x_iterator.end();
      ++x_iterator, ++y_iterator, ++z_iterator, ++point_index)
    {
      if (point_index % static_cast<size_t>(sample_stride_) != 0) {
        continue;
      }
      const tf2::Vector3 optical(*x_iterator, *y_iterator, *z_iterator);
      if (!std::isfinite(optical.x()) || !std::isfinite(optical.y()) ||
        !std::isfinite(optical.z()))
      {
        continue;
      }
      const tf2::Vector3 base = to_base * optical;
      if (base.z() < min_height_ || base.z() > max_height_) {
        continue;
      }
      const bool in_stop = base.x() >= stop_x_range_[0] && base.x() <= stop_x_range_[1] &&
        std::abs(base.y()) <= stop_half_width_;
      const bool in_slowdown = !in_stop &&
        base.x() >= slowdown_x_range_[0] && base.x() <= slowdown_x_range_[1] &&
        std::abs(base.y()) <= slowdown_half_width_;
      if (in_stop) {
        accumulate(stop_zone, optical, base.x(), message.header.stamp);
      } else if (in_slowdown) {
        accumulate(slowdown_zone, optical, base.x(), message.header.stamp);
      }
    }

    ImageAnnotations overlay;
    for (Zone * zone : {&stop_zone, &slowdown_zone}) {
      overlay.circles.insert(
        overlay.circles.end(), zone->markers.begin(), zone->markers.end());
      if (zone->has_nearest) {
        TextAnnotation label;
        label.timestamp = message.header.stamp;
        label.position.x = zone->nearest_pixel.x;
        label.position.y = std::max(zone->nearest_pixel.y - LABEL_MARGIN_PIXELS, 0.0);
        char text[16];
        std::snprintf(text, sizeof(text), "%.1fm", zone->nearest_distance);
        label.text = text;
        label.font_size = LABEL_FONT_SIZE;
        label.text_color = zone->color;
        label.background_color = TEXT_BACKGROUND_COLOR;
        overlay.texts.push_back(label);
      }
    }
    overlay_publisher_->publish(overlay);
  }

  void accumulate(
    Zone & zone, const tf2::Vector3 & optical, double forward_distance,
    const builtin_interfaces::msg::Time & stamp)
  {
    if (zone.point_count >= MAX_POINTS_PER_ZONE) {
      return;
    }
    zone.point_count++;
    if (optical.z() <= 0.0) {
      return;
    }
    const cv::Point2d pixel =
      camera_model_.project3dToPixel(cv::Point3d(optical.x(), optical.y(), optical.z()));
    if (pixel.x < 0.0 || pixel.x >= image_width_ || pixel.y < 0.0 || pixel.y >= image_height_) {
      return;
    }
    CircleAnnotation marker;
    marker.timestamp = stamp;
    marker.position.x = pixel.x;
    marker.position.y = pixel.y;
    marker.diameter = POINT_DIAMETER_PIXELS;
    marker.thickness = POINT_THICKNESS_PIXELS;
    marker.fill_color = zone.color;
    marker.outline_color = zone.color;
    zone.markers.push_back(marker);
    if (!zone.has_nearest || forward_distance < zone.nearest_distance) {
      zone.has_nearest = true;
      zone.nearest_distance = forward_distance;
      zone.nearest_pixel = marker.position;
    }
  }

  tf2_ros::Buffer tf_buffer_;
  tf2_ros::TransformListener tf_listener_;
  image_geometry::PinholeCameraModel camera_model_;
  bool has_camera_model_ = false;
  double image_width_ = 0.0;
  double image_height_ = 0.0;
  std::string base_frame_;
  double min_height_;
  double max_height_;
  std::vector<double> stop_x_range_;
  double stop_half_width_;
  std::vector<double> slowdown_x_range_;
  double slowdown_half_width_;
  int64_t sample_stride_;
  rclcpp::Publisher<ImageAnnotations>::SharedPtr overlay_publisher_;
  rclcpp::Subscription<sensor_msgs::msg::CameraInfo>::SharedPtr camera_info_subscription_;
  rclcpp::Subscription<sensor_msgs::msg::PointCloud2>::SharedPtr cloud_subscription_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<CollisionOverlay>());
  rclcpp::shutdown();
  return 0;
}
