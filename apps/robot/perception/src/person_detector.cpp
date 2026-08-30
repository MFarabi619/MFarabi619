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

#include <algorithm>
#include <array>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <core/session/onnxruntime_cxx_api.h>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <foxglove_msgs/msg/image_annotations.hpp>
#include <foxglove_msgs/msg/points_annotation.hpp>
#include <foxglove_msgs/msg/text_annotation.hpp>
#include <geometry_msgs/msg/point.hpp>
#include <image_geometry/pinhole_camera_model.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/camera_info.hpp>
#include <sensor_msgs/msg/compressed_image.hpp>
#include <sensor_msgs/msg/image.hpp>
#include <std_srvs/srv/set_bool.hpp>
#include <vision_msgs/msg/detection2_d_array.hpp>

namespace
{

constexpr double MILLIMETERS_PER_METER = 1000.0;
constexpr int RGB_CHANNELS = 3;
constexpr double LABEL_MARGIN_PIXELS = 8.0;
constexpr double LABEL_FONT_SIZE = 18.0;
constexpr double BOX_THICKNESS = 2.0;
constexpr char MILLIMETER_DEPTH_ENCODING[] = "16UC1";
constexpr char METER_DEPTH_ENCODING[] = "32FC1";
constexpr std::string_view COMPRESSED_TOPIC_SUFFIX = "/compressed";

foxglove_msgs::msg::Color make_color(float red, float green, float blue, float alpha)
{
  foxglove_msgs::msg::Color color;
  color.r = red;
  color.g = green;
  color.b = blue;
  color.a = alpha;
  return color;
}

foxglove_msgs::msg::Point2 make_point(double x, double y)
{
  foxglove_msgs::msg::Point2 point;
  point.x = x;
  point.y = y;
  return point;
}

const foxglove_msgs::msg::Color PERSON_COLOR = make_color(0.3f, 0.9f, 1.0f, 1.0f);
const foxglove_msgs::msg::Color TEXT_COLOR = make_color(1.0f, 1.0f, 1.0f, 1.0f);
const foxglove_msgs::msg::Color TEXT_BACKGROUND_COLOR =
  make_color(0.0f, 0.0f, 0.0f, 0.6f);

uint16_t swap_bytes(uint16_t value) {return __builtin_bswap16(value);}
uint32_t swap_bytes(uint32_t value) {return __builtin_bswap32(value);}

template<typename WordType>
cv::Mat byteswapped(const cv::Mat & source, int matrix_type)
{
  cv::Mat swapped(source.rows, source.cols, matrix_type);
  for (int row = 0; row < source.rows; ++row) {
    const WordType * source_row = source.ptr<WordType>(row);
    WordType * destination_row = swapped.ptr<WordType>(row);
    for (int column = 0; column < source.cols; ++column) {
      destination_row[column] = swap_bytes(source_row[column]);
    }
  }
  return swapped;
}

}  // namespace

class PersonDetector : public rclcpp::Node
{
public:
  PersonDetector()
  : rclcpp::Node("person_detector"),
    onnx_environment_(ORT_LOGGING_LEVEL_WARNING, "person_detector")
  {
    image_topic_ = declare_parameter(
      "image_topic", std::string("sensors/camera_0/color/image_raw/compressed"));
    const auto depth_topic = declare_parameter(
      "depth_topic", std::string("sensors/camera_0/depth/image_raw"));
    const auto depth_camera_info_topic = declare_parameter(
      "depth_camera_info_topic", std::string("sensors/camera_0/depth/camera_info"));
    const auto detections_topic = declare_parameter(
      "detections_topic", std::string("detections"));
    const auto overlay_topic = declare_parameter(
      "overlay_topic", std::string("perception/vision/overlay"));
    const auto model_path = declare_parameter(
      "model_path", std::string("perception/models/ssd_mobilenet_v1_12.onnx"));
    class_label_ = declare_parameter("class_label", std::string("person"));
    person_class_id_ = declare_parameter("person_class_id", 1);
    min_score_ = declare_parameter("min_score", 0.5);
    depth_sample_radius_ = declare_parameter("depth_sample_radius", 4);
    depth_timeout_seconds_ = declare_parameter("depth_timeout_seconds", 0.5);
    max_detections_per_second_ = declare_parameter("max_detections_per_second", 10.0);
    min_detection_interval_ = max_detections_per_second_ > 0.0
      ? rclcpp::Duration::from_seconds(1.0 / max_detections_per_second_)
      : rclcpp::Duration(0, 0);
    is_enabled_ = declare_parameter("start_enabled", true);

    const int inference_threads =
      static_cast<int>(declare_parameter("inference_threads", 2));
    inference_size_ = static_cast<int>(declare_parameter("inference_size", 300));
    Ort::SessionOptions session_options;
    session_options.SetIntraOpNumThreads(inference_threads);
    session_options.AddConfigEntry("session.intra_op.allow_spinning", "0");
    session_ = std::make_unique<Ort::Session>(
      onnx_environment_, model_path.c_str(), session_options);
    Ort::AllocatorWithDefaultOptions allocator;
    input_name_ = session_->GetInputNameAllocated(0, allocator).get();
    for (size_t index = 0; index < session_->GetOutputCount(); ++index) {
      output_names_.push_back(session_->GetOutputNameAllocated(index, allocator).get());
    }
    for (const auto & name : output_names_) {
      output_name_pointers_.push_back(name.c_str());
    }

    detections_publisher_ = create_publisher<vision_msgs::msg::Detection2DArray>(
      detections_topic, rclcpp::SensorDataQoS());
    overlay_publisher_ = create_publisher<foxglove_msgs::msg::ImageAnnotations>(
      overlay_topic, 10);
    parameters_callback_handle_ = add_post_set_parameters_callback(
      [this](const std::vector<rclcpp::Parameter> & parameters) {
        on_parameters_set(parameters);
      });

    enable_service_ = create_service<std_srvs::srv::SetBool>(
      "~/enable",
      [this](
        std_srvs::srv::SetBool::Request::ConstSharedPtr request,
        std_srvs::srv::SetBool::Response::SharedPtr response) {
        on_enable(request, response);
      });

    camera_info_subscription_ = create_subscription<sensor_msgs::msg::CameraInfo>(
      depth_camera_info_topic, rclcpp::SensorDataQoS(),
      [this](sensor_msgs::msg::CameraInfo::ConstSharedPtr message) {
        on_depth_camera_info(message);
      });
    const auto freshest_frame = rclcpp::QoS(1).best_effort();
    depth_subscription_ = create_subscription<sensor_msgs::msg::Image>(
      depth_topic, freshest_frame,
      [this](sensor_msgs::msg::Image::ConstSharedPtr message) {on_depth(message);});
    if (image_topic_.size() >= COMPRESSED_TOPIC_SUFFIX.size() &&
      image_topic_.compare(
        image_topic_.size() - COMPRESSED_TOPIC_SUFFIX.size(),
        COMPRESSED_TOPIC_SUFFIX.size(), COMPRESSED_TOPIC_SUFFIX.data()) == 0)
    {
      compressed_image_subscription_ =
        create_subscription<sensor_msgs::msg::CompressedImage>(
        image_topic_, freshest_frame,
        [this](sensor_msgs::msg::CompressedImage::ConstSharedPtr message) {
          on_compressed_image(message);
        });
    } else {
      raw_image_subscription_ = create_subscription<sensor_msgs::msg::Image>(
        image_topic_, freshest_frame,
        [this](sensor_msgs::msg::Image::ConstSharedPtr message) {
          on_raw_image(message);
        });
    }
    RCLCPP_INFO(
      get_logger(), "%s detector %s: %s",
      class_label_.c_str(), model_path.c_str(), image_topic_.c_str());
  }

private:
  void on_depth_camera_info(sensor_msgs::msg::CameraInfo::ConstSharedPtr message)
  {
    depth_frame_id_ = message->header.frame_id;
    camera_model_.fromCameraInfo(*message);
    has_camera_model_ = true;
  }

  void on_depth(sensor_msgs::msg::Image::ConstSharedPtr message)
  {
    if (message->encoding == MILLIMETER_DEPTH_ENCODING) {
      cv::Mat depth(
        message->height, message->width, CV_16UC1,
        const_cast<uint8_t *>(message->data.data()), message->step);
      if (message->is_bigendian) {
        depth = byteswapped<uint16_t>(depth, CV_16UC1);
      }
      depth.convertTo(latest_depth_millimeters_, CV_32FC1);
    } else if (message->encoding == METER_DEPTH_ENCODING) {
      cv::Mat depth(
        message->height, message->width, CV_32FC1,
        const_cast<uint8_t *>(message->data.data()), message->step);
      if (message->is_bigendian) {
        depth = byteswapped<uint32_t>(depth, CV_32FC1);
      }
      depth.convertTo(latest_depth_millimeters_, CV_32FC1, MILLIMETERS_PER_METER);
    } else {
      RCLCPP_WARN_THROTTLE(
        get_logger(), *get_clock(), 5000,
        "expected %s or %s depth, got %s",
        MILLIMETER_DEPTH_ENCODING, METER_DEPTH_ENCODING, message->encoding.c_str());
      return;
    }
    latest_depth_time_ = now();
  }

  void on_enable(
    std_srvs::srv::SetBool::Request::ConstSharedPtr request,
    std_srvs::srv::SetBool::Response::SharedPtr response)
  {
    is_enabled_ = request->data;
    response->success = true;
    response->message = request->data ? "enabled" : "disabled";
  }

  bool claim_detection_slot()
  {
    if (!is_enabled_) {
      return false;
    }
    const auto current_time = now();
    if (previous_detection_time_.has_value() &&
      current_time - *previous_detection_time_ < min_detection_interval_)
    {
      return false;
    }
    previous_detection_time_ = current_time;
    return true;
  }

  void on_compressed_image(sensor_msgs::msg::CompressedImage::ConstSharedPtr message)
  {
    if (!claim_detection_slot()) {
      return;
    }
    const cv::Mat encoded(
      1, static_cast<int>(message->data.size()), CV_8UC1,
      const_cast<uint8_t *>(message->data.data()));
    cv::Mat rgb = cv::imdecode(encoded, cv::IMREAD_COLOR_RGB);
    if (rgb.empty()) {
      return;
    }
    detect(rgb, message->header.stamp);
  }

  void on_raw_image(sensor_msgs::msg::Image::ConstSharedPtr message)
  {
    if (!claim_detection_slot()) {
      return;
    }
    const cv::Mat bgr(
      message->height, message->width, CV_8UC3,
      const_cast<uint8_t *>(message->data.data()), message->step);
    cv::Mat rgb;
    cv::cvtColor(bgr, rgb, cv::COLOR_BGR2RGB);
    detect(rgb, message->header.stamp);
  }

  void detect(const cv::Mat & rgb, const builtin_interfaces::msg::Time & stamp)
  {
    const int height = rgb.rows;
    const int width = rgb.cols;
    cv::Mat inference_input = rgb;
    if (inference_size_ > 0 &&
      (rgb.cols != inference_size_ || rgb.rows != inference_size_))
    {
      cv::resize(
        rgb, inference_input, cv::Size(inference_size_, inference_size_), 0, 0,
        cv::INTER_LINEAR);
    }
    const std::array<int64_t, 4> input_shape{
      1, inference_input.rows, inference_input.cols, RGB_CHANNELS};
    static const auto memory_info =
      Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    Ort::Value input_tensor = Ort::Value::CreateTensor<uint8_t>(
      memory_info, const_cast<uint8_t *>(inference_input.data),
      inference_input.total() * RGB_CHANNELS,
      input_shape.data(), input_shape.size());
    const char * input_names[] = {input_name_.c_str()};
    const auto outputs = session_->Run(
      Ort::RunOptions{nullptr}, input_names, &input_tensor, 1,
      output_name_pointers_.data(), output_name_pointers_.size());
    const float * boxes = outputs[0].GetTensorData<float>();
    const float * classes = outputs[1].GetTensorData<float>();
    const float * scores = outputs[2].GetTensorData<float>();
    const int count = static_cast<int>(outputs[3].GetTensorData<float>()[0]);

    vision_msgs::msg::Detection2DArray detections;
    detections.header.stamp = stamp;
    detections.header.frame_id = depth_frame_id_;
    const bool wants_overlay = overlay_publisher_->get_subscription_count() > 0;
    foxglove_msgs::msg::ImageAnnotations overlay;
    for (int index = 0; index < count; ++index) {
      if (static_cast<int>(classes[index]) != person_class_id_) {
        continue;
      }
      const double score = scores[index];
      if (score < min_score_) {
        continue;
      }
      const double top = boxes[index * 4] * height;
      const double left = boxes[index * 4 + 1] * width;
      const double bottom = boxes[index * 4 + 2] * height;
      const double right = boxes[index * 4 + 3] * width;
      const std::array<double, 4> bounding_box{
        left, top, right - left, bottom - top};
      const auto [distance, point] = bounding_box_range(bounding_box, width, height);
      detections.detections.push_back(detection(stamp, bounding_box, score, point));
      if (wants_overlay) {
        annotate(overlay, stamp, bounding_box, distance);
      }
    }
    detections_publisher_->publish(detections);
    if (wants_overlay) {
      overlay_publisher_->publish(overlay);
    }
  }

  std::pair<std::optional<double>, std::optional<geometry_msgs::msg::Point>>
  bounding_box_range(
    const std::array<double, 4> & bounding_box, int color_width, int color_height)
  {
    if (latest_depth_millimeters_.empty() || depth_is_stale()) {
      return {std::nullopt, std::nullopt};
    }
    const auto [x, y, w, h] = bounding_box;
    const int depth_width = latest_depth_millimeters_.cols;
    const int depth_height = latest_depth_millimeters_.rows;
    const int depth_x = static_cast<int>((x + w / 2.0) / color_width * depth_width);
    const int depth_y = static_cast<int>((y + h / 2.0) / color_height * depth_height);
    const int radius = depth_sample_radius_;
    const int row_begin = std::max(depth_y - radius, 0);
    const int row_end = std::min(depth_y + radius + 1, depth_height);
    const int column_begin = std::max(depth_x - radius, 0);
    const int column_end = std::min(depth_x + radius + 1, depth_width);
    std::vector<float> valid_depths;
    for (int row = row_begin; row < row_end; ++row) {
      const float * values = latest_depth_millimeters_.ptr<float>(row);
      for (int column = column_begin; column < column_end; ++column) {
        if (std::isfinite(values[column]) && values[column] > 0.0f) {
          valid_depths.push_back(values[column]);
        }
      }
    }
    if (valid_depths.empty()) {
      return {std::nullopt, std::nullopt};
    }
    const auto middle = valid_depths.begin() + valid_depths.size() / 2;
    std::nth_element(valid_depths.begin(), middle, valid_depths.end());
    double median = *middle;
    if (valid_depths.size() % 2 == 0) {
      const auto lower_median = std::max_element(valid_depths.begin(), middle);
      median = (median + *lower_median) / 2.0;
    }
    const double distance = median / MILLIMETERS_PER_METER;
    return {distance, deproject(depth_x, depth_y, distance)};
  }

  std::optional<geometry_msgs::msg::Point> deproject(
    int depth_x, int depth_y, double distance)
  {
    if (!has_camera_model_) {
      return std::nullopt;
    }
    const cv::Point3d ray =
      camera_model_.projectPixelTo3dRay(cv::Point2d(depth_x, depth_y));
    geometry_msgs::msg::Point point;
    point.x = ray.x / ray.z * distance;
    point.y = ray.y / ray.z * distance;
    point.z = distance;
    return point;
  }

  bool depth_is_stale()
  {
    if (!latest_depth_time_.has_value()) {
      return true;
    }
    return now() - *latest_depth_time_ >
           rclcpp::Duration::from_seconds(depth_timeout_seconds_);
  }

  vision_msgs::msg::Detection2D detection(
    const builtin_interfaces::msg::Time & stamp,
    const std::array<double, 4> & bounding_box, double score,
    const std::optional<geometry_msgs::msg::Point> & point)
  {
    const auto [x, y, w, h] = bounding_box;
    vision_msgs::msg::Detection2D detection;
    detection.header.stamp = stamp;
    detection.header.frame_id = depth_frame_id_;
    detection.id = class_label_;
    detection.bbox.center.position.x = x + w / 2.0;
    detection.bbox.center.position.y = y + h / 2.0;
    detection.bbox.center.theta = 0.0;
    detection.bbox.size_x = w;
    detection.bbox.size_y = h;
    vision_msgs::msg::ObjectHypothesisWithPose hypothesis;
    hypothesis.hypothesis.class_id = class_label_;
    hypothesis.hypothesis.score = score;
    if (point.has_value()) {
      hypothesis.pose.pose.position = *point;
    }
    detection.results.push_back(hypothesis);
    return detection;
  }

  void annotate(
    foxglove_msgs::msg::ImageAnnotations & overlay,
    const builtin_interfaces::msg::Time & stamp,
    const std::array<double, 4> & bounding_box, std::optional<double> distance)
  {
    const auto [x, y, w, h] = bounding_box;
    foxglove_msgs::msg::PointsAnnotation box;
    box.timestamp = stamp;
    box.type = foxglove_msgs::msg::PointsAnnotation::LINE_LOOP;
    box.points = {
      make_point(x, y), make_point(x + w, y),
      make_point(x + w, y + h), make_point(x, y + h)};
    box.outline_color = PERSON_COLOR;
    box.thickness = BOX_THICKNESS;
    overlay.points.push_back(box);
    foxglove_msgs::msg::TextAnnotation label;
    label.timestamp = stamp;
    label.position = make_point(x, std::max(y - LABEL_MARGIN_PIXELS, 0.0));
    char distance_text[32];
    if (distance.has_value()) {
      snprintf(distance_text, sizeof(distance_text), "%.1fm", *distance);
    } else {
      snprintf(distance_text, sizeof(distance_text), "?");
    }
    label.text = class_label_ + " " + distance_text;
    label.font_size = LABEL_FONT_SIZE;
    label.text_color = TEXT_COLOR;
    label.background_color = TEXT_BACKGROUND_COLOR;
    overlay.texts.push_back(label);
  }

  void on_parameters_set(const std::vector<rclcpp::Parameter> & parameters)
  {
    for (const auto & parameter : parameters) {
      if (parameter.get_name() == "min_score") {
        min_score_ = parameter.as_double();
      }
    }
  }

  Ort::Env onnx_environment_;
  std::unique_ptr<Ort::Session> session_;
  std::string input_name_;
  std::vector<std::string> output_names_;
  std::vector<const char *> output_name_pointers_;

  std::string image_topic_;
  std::string class_label_;
  std::string depth_frame_id_;
  int person_class_id_ = 1;
  int inference_size_ = 300;
  double min_score_ = 0.5;
  int depth_sample_radius_ = 4;
  double depth_timeout_seconds_ = 0.5;
  double max_detections_per_second_ = 10.0;
  rclcpp::Duration min_detection_interval_{0, 0};

  cv::Mat latest_depth_millimeters_;
  std::optional<rclcpp::Time> latest_depth_time_;
  std::optional<rclcpp::Time> previous_detection_time_;
  image_geometry::PinholeCameraModel camera_model_;
  bool has_camera_model_ = false;

  rclcpp::Publisher<vision_msgs::msg::Detection2DArray>::SharedPtr detections_publisher_;
  rclcpp::Publisher<foxglove_msgs::msg::ImageAnnotations>::SharedPtr overlay_publisher_;
  bool is_enabled_{true};
  rclcpp::Service<std_srvs::srv::SetBool>::SharedPtr enable_service_;
  rclcpp::Subscription<sensor_msgs::msg::CameraInfo>::SharedPtr camera_info_subscription_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr depth_subscription_;
  rclcpp::Subscription<sensor_msgs::msg::CompressedImage>::SharedPtr
    compressed_image_subscription_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr raw_image_subscription_;
  rclcpp::node_interfaces::PostSetParametersCallbackHandle::SharedPtr
    parameters_callback_handle_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<PersonDetector>());
  rclcpp::shutdown();
  return 0;
}
