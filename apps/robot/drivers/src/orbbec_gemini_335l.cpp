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


#include <atomic>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <ament_index_cpp/get_package_share_path.hpp>
#include <libobsensor/ObSensor.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <rclcpp/rclcpp.hpp>
#include <rclcpp_components/register_node_macro.hpp>
#include <sensor_msgs/msg/camera_info.hpp>
#include <sensor_msgs/msg/compressed_image.hpp>
#include <sensor_msgs/msg/image.hpp>

namespace robot_drivers
{

namespace
{

constexpr uint32_t FRAME_TIMEOUT_MS = 1000;
constexpr int FRAME_TIMEOUTS_BEFORE_DEVICE_LOST = 5;
constexpr auto DEVICE_RETRY_DELAY = std::chrono::seconds(2);
constexpr int64_t MICROSECONDS_PER_SECOND = 1'000'000;
constexpr int NANOSECONDS_PER_MICROSECOND = 1000;
constexpr int MILLISECONDS_PER_SECOND = 1000;
constexpr size_t BYTES_PER_DEPTH_PIXEL = 2;
constexpr size_t BYTES_PER_COLOR_PIXEL = 3;
constexpr double MAX_PREVIEW_DEPTH_MM = 8000.0;

builtin_interfaces::msg::Time stamp_from_microseconds(uint64_t timestamp_us)
{
  builtin_interfaces::msg::Time stamp;
  stamp.sec = static_cast<int32_t>(timestamp_us / MICROSECONDS_PER_SECOND);
  stamp.nanosec = static_cast<uint32_t>(
    (timestamp_us % MICROSECONDS_PER_SECOND) * NANOSECONDS_PER_MICROSECOND);
  return stamp;
}

uint64_t frame_timestamp_us(const std::shared_ptr<ob::Frame> & frame)
{
  uint64_t global_timestamp_us = frame->getGlobalTimeStampUs();
  return global_timestamp_us != 0 ? global_timestamp_us : frame->getSystemTimeStampUs();
}

sensor_msgs::msg::CameraInfo camera_info_message(
  const OBCameraIntrinsic & intrinsic, const OBCameraDistortion & distortion,
  const std::string & frame_id)
{
  sensor_msgs::msg::CameraInfo camera_info;
  camera_info.header.frame_id = frame_id;
  camera_info.width = intrinsic.width;
  camera_info.height = intrinsic.height;
  camera_info.distortion_model = "plumb_bob";
  camera_info.d = {distortion.k1, distortion.k2, distortion.p1, distortion.p2, distortion.k3};
  camera_info.k = {intrinsic.fx, 0.0, intrinsic.cx, 0.0, intrinsic.fy, intrinsic.cy, 0.0, 0.0, 1.0};
  camera_info.r = {1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0};
  camera_info.p = {intrinsic.fx, 0.0, intrinsic.cx, 0.0,
    0.0, intrinsic.fy, intrinsic.cy, 0.0,
    0.0, 0.0, 1.0, 0.0};
  return camera_info;
}

void scale_camera_info(sensor_msgs::msg::CameraInfo & camera_info, int decimation)
{
  if (decimation == 1) {
    return;
  }
  camera_info.width = (camera_info.width + decimation - 1) / decimation;
  camera_info.height = (camera_info.height + decimation - 1) / decimation;
  for (double & value : camera_info.k) {
    value /= decimation;
  }
  camera_info.k[8] = 1.0;
  for (double & value : camera_info.p) {
    value /= decimation;
  }
  camera_info.p[10] = 1.0;
}

}  // namespace

class OrbbecCamera : public rclcpp::Node
{
public:
  explicit OrbbecCamera(const rclcpp::NodeOptions & options)
  : Node("camera", options)
  {
    declare_parameter("color_width", 640);
    declare_parameter("color_height", 480);
    declare_parameter("color_fps", 15);
    declare_parameter("jpeg_quality", 80);
    declare_parameter("enable_depth", false);
    declare_parameter("depth_width", 848);
    declare_parameter("depth_height", 480);
    declare_parameter("depth_fps", 15);
    declare_parameter("depth_decimation", 1);
    declare_parameter("frame_id", std::string("camera_0_color_optical_frame"));
    declare_parameter("depth_frame_id", std::string("camera_0_depth_optical_frame"));
    frame_id_ = get_parameter("frame_id").as_string();
    enable_depth_ = get_parameter("enable_depth").as_bool();
    depth_decimation_ = get_parameter("depth_decimation").as_int();
    jpeg_quality_ = get_parameter("jpeg_quality").as_int();

    const std::string extensions =
      (ament_index_cpp::get_package_share_path("robot_drivers") / "extensions").string();
    ob::Context::setExtensionsDirectory(extensions.c_str());
    ob::Context::setLoggerSeverity(OB_LOG_SEVERITY_WARN);

    while (rclcpp::ok()) {
      try {
        pipeline_.emplace();
        break;
      } catch (const ob::Error & error) {
        RCLCPP_WARN(get_logger(), "waiting for camera: %s", error.what());
        std::this_thread::sleep_for(DEVICE_RETRY_DELAY);
      }
    }
    if (!pipeline_) {
      throw std::runtime_error("shutdown before camera appeared");
    }

    auto config = std::make_shared<ob::Config>();
    auto color_profile = pipeline_->getStreamProfileList(OB_SENSOR_COLOR)
      ->getVideoStreamProfile(
        get_parameter("color_width").as_int(), get_parameter("color_height").as_int(),
        OB_FORMAT_BGR, get_parameter("color_fps").as_int());
    config->enableStream(color_profile);
    if (enable_depth_) {
      auto depth_profile = select_depth_profile(color_profile);
      config->enableStream(depth_profile);
      if (is_depth_aligned_) {
        config->setAlignMode(ALIGN_D2C_HW_MODE);
      }
    }
    try {
      pipeline_->getDevice()->enableGlobalTimestamp(true);
    } catch (const ob::Error & error) {
      RCLCPP_WARN(get_logger(), "global timestamps unavailable: %s", error.what());
    }
    pipeline_->start(config);

    compressed_publisher_ = create_publisher<sensor_msgs::msg::CompressedImage>(
      "color/image_raw/compressed", rclcpp::SensorDataQoS());
    camera_info_publisher_ =
      create_publisher<sensor_msgs::msg::CameraInfo>("color/camera_info", 10);
    if (enable_depth_) {
      depth_frame_id_ =
        is_depth_aligned_ ? frame_id_ : get_parameter("depth_frame_id").as_string();
      RCLCPP_INFO(
        get_logger(), "%s",
        is_depth_aligned_ ? "depth aligned to color" :
          "depth unaligned, publishing in depth frame");
      depth_image_publisher_ = create_publisher<sensor_msgs::msg::Image>(
        "depth/image_raw", rclcpp::SensorDataQoS());
      depth_compressed_publisher_ = create_publisher<sensor_msgs::msg::CompressedImage>(
        "depth/image_raw/compressed", rclcpp::SensorDataQoS());
      depth_camera_info_publisher_ =
        create_publisher<sensor_msgs::msg::CameraInfo>("depth/camera_info", 10);
    }

    running_ = true;
    frame_thread_ = std::thread([this]() {pump_frames();});
  }

  ~OrbbecCamera() override
  {
    running_ = false;
    if (frame_thread_.joinable()) {
      frame_thread_.join();
    }
    pipeline_->stop();
  }

private:
  void pump_frames()
  {
    int consecutive_timeouts = 0;
    while (running_ && rclcpp::ok()) {
      auto frame_set = pipeline_->waitForFrameset(FRAME_TIMEOUT_MS);
      auto color_frame = frame_set ? frame_set->colorFrame() : nullptr;
      auto depth_frame = frame_set ? frame_set->depthFrame() : nullptr;
      if (!color_frame && !depth_frame) {
        if (++consecutive_timeouts >= FRAME_TIMEOUTS_BEFORE_DEVICE_LOST) {
          RCLCPP_ERROR(
            get_logger(), "no frames for %ds, device lost",
            consecutive_timeouts * static_cast<int>(FRAME_TIMEOUT_MS) / MILLISECONDS_PER_SECOND);
          return;
        }
        continue;
      }
      consecutive_timeouts = 0;
      if (color_frame) {
        publish_color(color_frame);
      }
      if (depth_frame) {
        publish_depth(depth_frame);
      }
    }
  }

  std::shared_ptr<ob::StreamProfile> select_depth_profile(
    const std::shared_ptr<ob::VideoStreamProfile> & color_profile)
  {
    int width = get_parameter("depth_width").as_int();
    int height = get_parameter("depth_height").as_int();
    int fps = get_parameter("depth_fps").as_int();
    auto aligned_profiles =
      pipeline_->getD2CDepthProfileList(color_profile, ALIGN_D2C_HW_MODE);
    for (uint32_t index = 0; index < aligned_profiles->getCount(); ++index) {
      auto profile = aligned_profiles->getProfile(index)->as<ob::VideoStreamProfile>();
      if (profile->getFps() == static_cast<uint32_t>(fps)) {
        is_depth_aligned_ = true;
        return profile;
      }
    }
    if (aligned_profiles->getCount() > 0) {
      is_depth_aligned_ = true;
      return aligned_profiles->getProfile(0);
    }
    return pipeline_->getStreamProfileList(OB_SENSOR_DEPTH)
           ->getVideoStreamProfile(width, height, OB_FORMAT_Y16, fps);
  }

  void publish_color(const std::shared_ptr<ob::ColorFrame> & color_frame)
  {
    auto stamp = stamp_from_microseconds(frame_timestamp_us(color_frame));
    uint32_t width = color_frame->getWidth();
    uint32_t height = color_frame->getHeight();

    if (compressed_publisher_->get_subscription_count() > 0) {
      sensor_msgs::msg::Image image;
      image.header.stamp = stamp;
      image.header.frame_id = frame_id_;
      image.height = height;
      image.width = width;
      image.encoding = "bgr8";
      image.is_bigendian = false;
      image.step = width * BYTES_PER_COLOR_PIXEL;
      const uint8_t * pixels = static_cast<const uint8_t *>(color_frame->getData());
      image.data.assign(pixels, pixels + color_frame->dataSize());
      publish_compressed(image, stamp);
    }

    if (!camera_info_) {
      auto camera_param = pipeline_->getCameraParam();
      if (camera_param.rgbIntrinsic.width == 0) {
        return;
      }
      camera_info_ = camera_info_message(
        camera_param.rgbIntrinsic, camera_param.rgbDistortion, frame_id_);
    }
    camera_info_->header.stamp = stamp;
    camera_info_publisher_->publish(*camera_info_);
  }

  void publish_compressed(
    const sensor_msgs::msg::Image & image, const builtin_interfaces::msg::Time & stamp)
  {
    cv::Mat frame(image.height, image.width, CV_8UC3, const_cast<uint8_t *>(image.data.data()));
    auto compressed = std::make_unique<sensor_msgs::msg::CompressedImage>();
    compressed->header.stamp = stamp;
    compressed->header.frame_id = frame_id_;
    compressed->format = "jpeg";
    cv::imencode(
      ".jpg", frame, compressed->data, {cv::IMWRITE_JPEG_QUALITY, jpeg_quality_});
    compressed_publisher_->publish(std::move(compressed));
  }

  void publish_depth(const std::shared_ptr<ob::DepthFrame> & depth_frame)
  {
    auto stamp = stamp_from_microseconds(frame_timestamp_us(depth_frame));
    uint32_t source_width = depth_frame->getWidth();
    uint32_t source_height = depth_frame->getHeight();
    uint32_t width = (source_width + depth_decimation_ - 1) / depth_decimation_;
    uint32_t height = (source_height + depth_decimation_ - 1) / depth_decimation_;
    float scale = depth_frame->getValueScale();

    auto image = std::make_unique<sensor_msgs::msg::Image>();
    image->header.stamp = stamp;
    image->header.frame_id = depth_frame_id_;
    image->height = height;
    image->width = width;
    image->encoding = "16UC1";
    image->is_bigendian = false;
    image->step = width * BYTES_PER_DEPTH_PIXEL;
    image->data.resize(image->step * height);
    const auto * source = static_cast<const uint16_t *>(depth_frame->data());
    auto * destination = reinterpret_cast<uint16_t *>(image->data.data());
    for (uint32_t row = 0; row < height; ++row) {
      const uint16_t * source_row = source + row * depth_decimation_ * source_width;
      for (uint32_t column = 0; column < width; ++column) {
        uint16_t value = source_row[column * depth_decimation_];
        destination[row * width + column] =
          scale == 1.0f ? value : static_cast<uint16_t>(value * scale);
      }
    }
    if (depth_compressed_publisher_->get_subscription_count() > 0) {
      cv::Mat depth16(height, width, CV_16UC1, image->data.data());
      cv::Mat depth8;
      depth16.convertTo(depth8, CV_8UC1, 255.0 / MAX_PREVIEW_DEPTH_MM);
      cv::Mat colored;
      cv::applyColorMap(depth8, colored, cv::COLORMAP_JET);
      auto preview = std::make_unique<sensor_msgs::msg::CompressedImage>();
      preview->header = image->header;
      preview->format = "jpeg";
      cv::imencode(".jpg", colored, preview->data, {cv::IMWRITE_JPEG_QUALITY, jpeg_quality_});
      depth_compressed_publisher_->publish(std::move(preview));
    }
    depth_image_publisher_->publish(std::move(image));

    if (!depth_camera_info_) {
      auto camera_param = pipeline_->getCameraParam();
      const auto & intrinsic =
        is_depth_aligned_ ? camera_param.rgbIntrinsic : camera_param.depthIntrinsic;
      const auto & distortion =
        is_depth_aligned_ ? camera_param.rgbDistortion : camera_param.depthDistortion;
      if (intrinsic.width == 0) {
        return;
      }
      auto camera_info = camera_info_message(intrinsic, distortion, depth_frame_id_);
      scale_camera_info(camera_info, depth_decimation_);
      depth_camera_info_ = camera_info;
    }
    depth_camera_info_->header.stamp = stamp;
    depth_camera_info_publisher_->publish(*depth_camera_info_);
  }

  std::optional<ob::Pipeline> pipeline_;
  std::string frame_id_;
  std::string depth_frame_id_;
  bool enable_depth_ = false;
  bool is_depth_aligned_ = false;
  int depth_decimation_ = 1;
  int jpeg_quality_ = 80;
  std::atomic<bool> running_ = false;
  std::thread frame_thread_;
  std::optional<sensor_msgs::msg::CameraInfo> camera_info_;
  std::optional<sensor_msgs::msg::CameraInfo> depth_camera_info_;
  rclcpp::Publisher<sensor_msgs::msg::CompressedImage>::SharedPtr compressed_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::CameraInfo>::SharedPtr camera_info_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::Image>::SharedPtr depth_image_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::CompressedImage>::SharedPtr depth_compressed_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::CameraInfo>::SharedPtr depth_camera_info_publisher_;
};

}  // namespace robot_drivers

RCLCPP_COMPONENTS_REGISTER_NODE(robot_drivers::OrbbecCamera)
