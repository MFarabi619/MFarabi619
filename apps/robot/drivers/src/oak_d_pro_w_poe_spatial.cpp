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

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include <depthai/depthai.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <foxglove_msgs/msg/image_annotations.hpp>
#include <foxglove_msgs/msg/points_annotation.hpp>
#include <foxglove_msgs/msg/text_annotation.hpp>
#include <geometry_msgs/msg/point.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/camera_info.hpp>
#include <sensor_msgs/msg/compressed_image.hpp>
#include <sensor_msgs/msg/image.hpp>
#include <sensor_msgs/msg/imu.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>
#include <sensor_msgs/msg/point_field.hpp>
#include <vision_msgs/msg/detection2_d_array.hpp>

namespace
{

constexpr double QUEUE_POLL_RATE_HZ = 60.0;
constexpr double DEVICE_RETRY_DELAY_SECONDS = 2.0;
constexpr double MAX_PREVIEW_DEPTH_MM = 8000.0;
constexpr int SENSOR_WIDTH = 1280;
constexpr int SENSOR_HEIGHT = 800;
constexpr int IMU_RATE_HZ = 100;
constexpr float POINTCLOUD_RATE_HZ = 10.0f;
constexpr double METERS_PER_MILLIMETER = 0.001;
constexpr double MILLIMETERS_PER_METER = 1000.0;
constexpr int BYTES_PER_CLOUD_POINT = 12;
constexpr int BYTES_PER_DEPTH_PIXEL = 2;

constexpr int YOLO_INPUT_WIDTH = 640;
constexpr int YOLO_INPUT_HEIGHT = 352;
constexpr int YOLO_CLASS_COUNT = 80;
constexpr int YOLO_COORDINATE_SIZE = 4;
constexpr float YOLO_IOU_THRESHOLD = 0.5f;
constexpr int COCO_PERSON_CLASS_ID = 0;
constexpr float BOUNDING_BOX_DEPTH_FRACTION = 0.5f;
constexpr float DEVICE_CONFIDENCE_FLOOR = 0.2f;
constexpr int FRAME_QUEUE_MAX_SIZE = 2;
constexpr int IMU_QUEUE_MAX_SIZE = 20;
constexpr int DETECTIONS_QUEUE_MAX_SIZE = 4;

constexpr double LABEL_MARGIN_PIXELS = 8.0;
constexpr double LABEL_FONT_SIZE = 18.0;
constexpr double BOX_THICKNESS = 2.0;

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

}  // namespace

class OakDProWPoeSpatial : public rclcpp::Node
{
public:
  OakDProWPoeSpatial()
  : rclcpp::Node("oak_d_pro_w_poe")
  {
    ip_ = declare_parameter("ip", std::string(""));
    const double depth_fps = declare_parameter("depth_fps", 15.0);
    const double declared_color_fps = declare_parameter("color_fps", 0.0);
    const double color_fps =
      declared_color_fps > 0.0 ? declared_color_fps : depth_fps;
    jpeg_quality_ = static_cast<int>(declare_parameter("jpeg_quality", 60));
    frame_id_ = declare_parameter("frame_id", std::string("camera_0_link"));
    const int color_resolution_divisor =
      static_cast<int>(declare_parameter("color_resolution_divisor", 2));
    const int depth_resolution_divisor =
      static_cast<int>(declare_parameter("depth_resolution_divisor", 4));
    ir_dot_projector_intensity_ =
      declare_parameter("ir_dot_projector_intensity", 0.5);
    ir_flood_light_intensity_ =
      declare_parameter("ir_flood_light_intensity", 0.0);
    const auto model_path = declare_parameter(
      "model_path",
      std::string("perception/models/yolov8n_coco_640x352.blob"));
    min_score_ = declare_parameter("min_score", 0.3);
    person_class_id_ = static_cast<int>(
      declare_parameter("person_class_id", COCO_PERSON_CLASS_ID));
    class_label_ = declare_parameter("class_label", std::string("person"));
    const double min_detection_depth_meters =
      declare_parameter("min_detection_depth_meters", 0.3);
    const double max_detection_depth_meters =
      declare_parameter("max_detection_depth_meters", 10.0);

    color_width_ = SENSOR_WIDTH / color_resolution_divisor;
    color_height_ = SENSOR_HEIGHT / color_resolution_divisor;
    depth_width_ = SENSOR_WIDTH / depth_resolution_divisor;
    depth_height_ = SENSOR_HEIGHT / depth_resolution_divisor;
    pipeline_ = build_pipeline(
      depth_fps, color_fps, jpeg_quality_, color_resolution_divisor,
      depth_resolution_divisor, model_path, min_score_,
      min_detection_depth_meters, max_detection_depth_meters);
    connect();

    color_publisher_ = create_publisher<sensor_msgs::msg::CompressedImage>(
      "color/image_raw/compressed", rclcpp::SensorDataQoS());
    depth_publisher_ = create_publisher<sensor_msgs::msg::Image>(
      "depth/image_raw", rclcpp::SensorDataQoS());
    depth_preview_publisher_ =
      create_publisher<sensor_msgs::msg::CompressedImage>(
      "depth/image_raw/compressed", rclcpp::SensorDataQoS());
    color_camera_info_publisher_ = create_publisher<sensor_msgs::msg::CameraInfo>(
      "color/camera_info", rclcpp::SensorDataQoS());
    depth_camera_info_publisher_ = create_publisher<sensor_msgs::msg::CameraInfo>(
      "depth/camera_info", rclcpp::SensorDataQoS());
    imu_publisher_ = create_publisher<sensor_msgs::msg::Imu>(
      "imu/data", rclcpp::SensorDataQoS());
    points_publisher_ = create_publisher<sensor_msgs::msg::PointCloud2>(
      "depth/points", rclcpp::SensorDataQoS());
    detections_publisher_ = create_publisher<vision_msgs::msg::Detection2DArray>(
      "detections", rclcpp::SensorDataQoS());
    overlay_publisher_ = create_publisher<foxglove_msgs::msg::ImageAnnotations>(
      "perception/vision/overlay", 10);
    parameters_callback_handle_ = add_post_set_parameters_callback(
      [this](const std::vector<rclcpp::Parameter> & parameters) {
        on_parameters_set(parameters);
      });
    poll_timer_ = create_wall_timer(
      std::chrono::duration<double>(1.0 / QUEUE_POLL_RATE_HZ),
      [this]() {poll_queues();});
  }

  void release_device()
  {
    try {
      if (device_) {
        device_->close();
      }
    } catch (const std::exception &) {
    }
  }

private:
  static dai::Pipeline build_pipeline(
    double depth_fps, double color_fps, int jpeg_quality,
    int color_resolution_divisor, int depth_resolution_divisor,
    const std::string & model_path, double min_score,
    double min_detection_depth_meters, double max_detection_depth_meters)
  {
    dai::Pipeline pipeline;
    auto color = pipeline.create<dai::node::ColorCamera>();
    auto left = pipeline.create<dai::node::MonoCamera>();
    auto right = pipeline.create<dai::node::MonoCamera>();
    auto stereo = pipeline.create<dai::node::StereoDepth>();
    auto color_encoder = pipeline.create<dai::node::VideoEncoder>();
    auto imu = pipeline.create<dai::node::IMU>();
    auto pointcloud = pipeline.create<dai::node::PointCloud>();
    auto yolo = pipeline.create<dai::node::YoloSpatialDetectionNetwork>();
    auto color_output = pipeline.create<dai::node::XLinkOut>();
    auto depth_output = pipeline.create<dai::node::XLinkOut>();
    auto imu_output = pipeline.create<dai::node::XLinkOut>();
    auto points_output = pipeline.create<dai::node::XLinkOut>();
    auto detections_output = pipeline.create<dai::node::XLinkOut>();
    color_output->setStreamName("color");
    depth_output->setStreamName("depth");
    imu_output->setStreamName("imu");
    points_output->setStreamName("points");
    detections_output->setStreamName("detections");
    points_output->setFpsLimit(POINTCLOUD_RATE_HZ);
    color->setResolution(dai::ColorCameraProperties::SensorResolution::THE_800_P);
    color->setCamera("color");
    color->setFps(color_fps);
    color->setIspScale(1, color_resolution_divisor);
    color->setPreviewSize(YOLO_INPUT_WIDTH, YOLO_INPUT_HEIGHT);
    color->setPreviewKeepAspectRatio(false);
    color->setInterleaved(false);
    for (auto & [camera, socket] :
      {std::pair{left, "left"}, std::pair{right, "right"}})
    {
      camera->setResolution(
        dai::MonoCameraProperties::SensorResolution::THE_800_P);
      camera->setCamera(socket);
      camera->setFps(depth_fps);
    }
    stereo->setDefaultProfilePreset(dai::node::StereoDepth::PresetMode::DEFAULT);
    stereo->initialConfig.setMedianFilter(dai::MedianFilter::KERNEL_7x7);
    stereo->setLeftRightCheck(true);
    stereo->setSubpixel(true);
    stereo->setExtendedDisparity(true);
    stereo->setDepthAlign(dai::CameraBoardSocket::CAM_A);
    stereo->setOutputSize(
      SENSOR_WIDTH / depth_resolution_divisor,
      SENSOR_HEIGHT / depth_resolution_divisor);
    color_encoder->setDefaultProfilePreset(
      color_fps, dai::VideoEncoderProperties::Profile::MJPEG);
    color_encoder->setQuality(jpeg_quality);
    imu->enableIMUSensor(
      {dai::IMUSensor::ACCELEROMETER_RAW, dai::IMUSensor::GYROSCOPE_RAW},
      IMU_RATE_HZ);
    imu->setBatchReportThreshold(1);
    imu->setMaxBatchReports(10);
    pointcloud->initialConfig.setSparse(true);
    yolo->input.setBlocking(false);
    yolo->input.setQueueSize(1);
    yolo->setBlobPath(model_path);
    yolo->setConfidenceThreshold(
      std::min(static_cast<float>(min_score), DEVICE_CONFIDENCE_FLOOR));
    yolo->setNumClasses(YOLO_CLASS_COUNT);
    yolo->setCoordinateSize(YOLO_COORDINATE_SIZE);
    yolo->setIouThreshold(YOLO_IOU_THRESHOLD);
    yolo->setBoundingBoxScaleFactor(BOUNDING_BOX_DEPTH_FRACTION);
    yolo->setDepthLowerThreshold(
      static_cast<int>(min_detection_depth_meters * MILLIMETERS_PER_METER));
    yolo->setDepthUpperThreshold(
      static_cast<int>(max_detection_depth_meters * MILLIMETERS_PER_METER));
    left->out.link(stereo->left);
    right->out.link(stereo->right);
    color->video.link(color_encoder->input);
    color->preview.link(yolo->input);
    color_encoder->bitstream.link(color_output->input);
    stereo->depth.link(depth_output->input);
    stereo->depth.link(pointcloud->inputDepth);
    stereo->depth.link(yolo->inputDepth);
    pointcloud->outputPointCloud.link(points_output->input);
    yolo->out.link(detections_output->input);
    imu->out.link(imu_output->input);
    return pipeline;
  }

  void connect()
  {
    device_ = wait_for_device();
    device_->setIrLaserDotProjectorIntensity(
      static_cast<float>(ir_dot_projector_intensity_));
    device_->setIrFloodLightIntensity(
      static_cast<float>(ir_flood_light_intensity_));
    color_queue_ = device_->getOutputQueue("color", FRAME_QUEUE_MAX_SIZE, false);
    depth_queue_ = device_->getOutputQueue("depth", FRAME_QUEUE_MAX_SIZE, false);
    imu_queue_ = device_->getOutputQueue("imu", IMU_QUEUE_MAX_SIZE, false);
    points_queue_ = device_->getOutputQueue("points", FRAME_QUEUE_MAX_SIZE, false);
    detections_queue_ = device_->getOutputQueue(
      "detections", DETECTIONS_QUEUE_MAX_SIZE, false);
    auto calibration = device_->readCalibration();
    color_camera_info_ = read_camera_info(
      calibration, dai::CameraBoardSocket::CAM_A, color_width_, color_height_);
    depth_camera_info_ = read_camera_info(
      calibration, dai::CameraBoardSocket::CAM_A, depth_width_, depth_height_);
    RCLCPP_INFO(
      get_logger(), "connected %s with on-camera detection",
      device_->getDeviceName().c_str());
  }

  std::shared_ptr<dai::Device> wait_for_device()
  {
    while (rclcpp::ok()) {
      try {
        return std::make_shared<dai::Device>(
          pipeline_, dai::DeviceInfo(ip_), dai::UsbSpeed::SUPER);
      } catch (const std::exception & error) {
        RCLCPP_WARN(
          get_logger(), "waiting for camera at %s: %s",
          ip_.c_str(), error.what());
        std::this_thread::sleep_for(
          std::chrono::duration<double>(DEVICE_RETRY_DELAY_SECONDS));
      }
    }
    throw std::runtime_error("shutdown before camera appeared");
  }

  sensor_msgs::msg::CameraInfo read_camera_info(
    dai::CalibrationHandler & calibration, dai::CameraBoardSocket socket,
    int width, int height)
  {
    const auto intrinsics = calibration.getCameraIntrinsics(
      socket, width, height);
    const auto distortion_coefficients =
      calibration.getDistortionCoefficients(socket);
    const bool is_fisheye =
      calibration.getDistortionModel(socket) == dai::CameraModel::Fisheye;
    sensor_msgs::msg::CameraInfo camera_info;
    camera_info.width = width;
    camera_info.height = height;
    camera_info.distortion_model =
      is_fisheye ? "equidistant" : "rational_polynomial";
    const size_t distortion_count =
      is_fisheye ? distortion_coefficients.size() : std::min<size_t>(
      distortion_coefficients.size(), 8);
    camera_info.d.assign(
      distortion_coefficients.begin(),
      distortion_coefficients.begin() + distortion_count);
    size_t index = 0;
    for (const auto & row : intrinsics) {
      for (const auto value : row) {
        camera_info.k[index++] = value;
      }
    }
    camera_info.r = {1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0};
    camera_info.p = {
      camera_info.k[0], 0.0, camera_info.k[2], 0.0,
      0.0, camera_info.k[4], camera_info.k[5], 0.0,
      0.0, 0.0, 1.0, 0.0,
    };
    return camera_info;
  }

  void poll_queues()
  {
    try {
      for (const auto & frame : color_queue_->tryGetAll<dai::ImgFrame>()) {
        publish_color(*frame);
      }
      for (const auto & frame : depth_queue_->tryGetAll<dai::ImgFrame>()) {
        publish_depth(*frame);
      }
      for (const auto & imu_data : imu_queue_->tryGetAll<dai::IMUData>()) {
        publish_imu(*imu_data);
      }
      for (const auto & cloud :
        points_queue_->tryGetAll<dai::PointCloudData>())
      {
        publish_points(*cloud);
      }
      for (const auto & spatial_detections :
        detections_queue_->tryGetAll<dai::SpatialImgDetections>())
      {
        publish_detections(*spatial_detections);
      }
    } catch (const std::exception & error) {
      RCLCPP_WARN(get_logger(), "camera lost, reconnecting: %s", error.what());
      release_device();
      connect();
    }
  }

  void publish_detections(const dai::SpatialImgDetections & spatial_detections)
  {
    const builtin_interfaces::msg::Time stamp = now();
    const bool wants_overlay = overlay_publisher_->get_subscription_count() > 0;
    vision_msgs::msg::Detection2DArray detections;
    detections.header.stamp = stamp;
    detections.header.frame_id = frame_id_;
    foxglove_msgs::msg::ImageAnnotations overlay;
    for (const auto & detection : spatial_detections.detections) {
      if (static_cast<int>(detection.label) != person_class_id_) {
        continue;
      }
      if (detection.confidence < min_score_) {
        continue;
      }
      const std::array<double, 4> bounding_box{
        detection.xmin * color_width_,
        detection.ymin * color_height_,
        (detection.xmax - detection.xmin) * color_width_,
        (detection.ymax - detection.ymin) * color_height_,
      };
      const auto point = spatial_point(detection.spatialCoordinates);
      detections.detections.push_back(
        make_detection(stamp, bounding_box, detection.confidence, point));
      if (wants_overlay) {
        annotate(overlay, stamp, bounding_box, point);
      }
    }
    detections_publisher_->publish(detections);
    if (wants_overlay) {
      overlay_publisher_->publish(overlay);
    }
  }

  std::optional<geometry_msgs::msg::Point> spatial_point(
    const dai::Point3f & spatial_coordinates)
  {
    if (spatial_coordinates.z <= 0.0f) {
      return std::nullopt;
    }
    geometry_msgs::msg::Point point;
    point.x = spatial_coordinates.x * METERS_PER_MILLIMETER;
    point.y = -spatial_coordinates.y * METERS_PER_MILLIMETER;
    point.z = spatial_coordinates.z * METERS_PER_MILLIMETER;
    return point;
  }

  vision_msgs::msg::Detection2D make_detection(
    const builtin_interfaces::msg::Time & stamp,
    const std::array<double, 4> & bounding_box, double score,
    const std::optional<geometry_msgs::msg::Point> & point)
  {
    const auto [x, y, width, height] = bounding_box;
    vision_msgs::msg::Detection2D detection;
    detection.header.stamp = stamp;
    detection.header.frame_id = frame_id_;
    detection.id = class_label_;
    detection.bbox.center.position.x = x + width / 2.0;
    detection.bbox.center.position.y = y + height / 2.0;
    detection.bbox.center.theta = 0.0;
    detection.bbox.size_x = width;
    detection.bbox.size_y = height;
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
    const std::array<double, 4> & bounding_box,
    const std::optional<geometry_msgs::msg::Point> & point)
  {
    const auto [x, y, width, height] = bounding_box;
    foxglove_msgs::msg::PointsAnnotation box;
    box.timestamp = stamp;
    box.type = foxglove_msgs::msg::PointsAnnotation::LINE_LOOP;
    box.points = {
      make_point(x, y), make_point(x + width, y),
      make_point(x + width, y + height), make_point(x, y + height)};
    box.outline_color = PERSON_COLOR;
    box.thickness = BOX_THICKNESS;
    overlay.points.push_back(box);
    foxglove_msgs::msg::TextAnnotation label;
    label.timestamp = stamp;
    label.position = make_point(x, std::max(y - LABEL_MARGIN_PIXELS, 0.0));
    char distance_text[32];
    if (point.has_value()) {
      snprintf(distance_text, sizeof(distance_text), "%.1fm", point->z);
    } else {
      snprintf(distance_text, sizeof(distance_text), "?");
    }
    label.text = class_label_ + " " + distance_text;
    label.font_size = LABEL_FONT_SIZE;
    label.text_color = TEXT_COLOR;
    label.background_color = TEXT_BACKGROUND_COLOR;
    overlay.texts.push_back(label);
  }

  void publish_imu(const dai::IMUData & imu_data)
  {
    if (imu_publisher_->get_subscription_count() == 0) {
      return;
    }
    for (const auto & packet : imu_data.packets) {
      sensor_msgs::msg::Imu message;
      stamp_header(message.header);
      message.orientation_covariance[0] = -1.0;
      message.linear_acceleration.x = packet.acceleroMeter.x;
      message.linear_acceleration.y = packet.acceleroMeter.y;
      message.linear_acceleration.z = packet.acceleroMeter.z;
      message.angular_velocity.x = packet.gyroscope.x;
      message.angular_velocity.y = packet.gyroscope.y;
      message.angular_velocity.z = packet.gyroscope.z;
      imu_publisher_->publish(message);
    }
  }

  void publish_points(dai::PointCloudData & cloud)
  {
    if (points_publisher_->get_subscription_count() == 0) {
      return;
    }
    const auto points = cloud.getPoints();
    sensor_msgs::msg::PointCloud2 message;
    stamp_header(message.header);
    message.height = 1;
    message.width = points.size();
    for (const auto & [axis, offset] :
      {std::pair{"x", 0}, std::pair{"y", 4}, std::pair{"z", 8}})
    {
      sensor_msgs::msg::PointField field;
      field.name = axis;
      field.offset = offset;
      field.datatype = sensor_msgs::msg::PointField::FLOAT32;
      field.count = 1;
      message.fields.push_back(field);
    }
    message.is_bigendian = false;
    message.point_step = BYTES_PER_CLOUD_POINT;
    message.row_step = BYTES_PER_CLOUD_POINT * points.size();
    message.is_dense = true;
    message.data.resize(message.row_step);
    float * destination = reinterpret_cast<float *>(message.data.data());
    for (const auto & point : points) {
      *destination++ = point.x * static_cast<float>(METERS_PER_MILLIMETER);
      *destination++ = point.y * static_cast<float>(METERS_PER_MILLIMETER);
      *destination++ = point.z * static_cast<float>(METERS_PER_MILLIMETER);
    }
    points_publisher_->publish(message);
  }

  void stamp_header(std_msgs::msg::Header & header)
  {
    header.stamp = now();
    header.frame_id = frame_id_;
  }

  void publish_color(const dai::ImgFrame & frame)
  {
    stamp_header(color_camera_info_.header);
    color_camera_info_publisher_->publish(color_camera_info_);
    if (color_publisher_->get_subscription_count() == 0) {
      return;
    }
    sensor_msgs::msg::CompressedImage message;
    stamp_header(message.header);
    message.format = "jpeg";
    message.data = frame.getData();
    color_publisher_->publish(message);
  }

  void publish_depth(const dai::ImgFrame & frame)
  {
    stamp_header(depth_camera_info_.header);
    depth_camera_info_publisher_->publish(depth_camera_info_);
    const bool wants_raw = depth_publisher_->get_subscription_count() > 0;
    const bool wants_preview =
      depth_preview_publisher_->get_subscription_count() > 0;
    if (!wants_raw && !wants_preview) {
      return;
    }
    const auto & depth_bytes = frame.getData();
    const int width = frame.getWidth();
    const int height = frame.getHeight();
    if (wants_raw) {
      sensor_msgs::msg::Image message;
      stamp_header(message.header);
      message.height = height;
      message.width = width;
      message.encoding = "16UC1";
      message.step = width * BYTES_PER_DEPTH_PIXEL;
      message.data = depth_bytes;
      depth_publisher_->publish(message);
    }
    if (wants_preview) {
      const cv::Mat depth(
        height, width, CV_16UC1,
        const_cast<uint8_t *>(depth_bytes.data()));
      cv::Mat scaled;
      cv::convertScaleAbs(depth, scaled, 255.0 / MAX_PREVIEW_DEPTH_MM);
      cv::Mat colored;
      cv::applyColorMap(scaled, colored, cv::COLORMAP_JET);
      std::vector<uint8_t> encoded;
      if (!cv::imencode(
          ".jpg", colored, encoded, {cv::IMWRITE_JPEG_QUALITY, jpeg_quality_}))
      {
        return;
      }
      sensor_msgs::msg::CompressedImage message;
      stamp_header(message.header);
      message.format = "jpeg";
      message.data = std::move(encoded);
      depth_preview_publisher_->publish(message);
    }
  }

  void on_parameters_set(const std::vector<rclcpp::Parameter> & parameters)
  {
    for (const auto & parameter : parameters) {
      if (parameter.get_name() == "min_score") {
        min_score_ = parameter.as_double();
      }
    }
  }

  dai::Pipeline pipeline_;
  std::shared_ptr<dai::Device> device_;
  std::shared_ptr<dai::DataOutputQueue> color_queue_;
  std::shared_ptr<dai::DataOutputQueue> depth_queue_;
  std::shared_ptr<dai::DataOutputQueue> imu_queue_;
  std::shared_ptr<dai::DataOutputQueue> points_queue_;
  std::shared_ptr<dai::DataOutputQueue> detections_queue_;

  std::string ip_;
  std::string frame_id_;
  std::string class_label_;
  int jpeg_quality_ = 60;
  int color_width_ = 0;
  int color_height_ = 0;
  int depth_width_ = 0;
  int depth_height_ = 0;
  int person_class_id_ = COCO_PERSON_CLASS_ID;
  double min_score_ = 0.3;
  double ir_dot_projector_intensity_ = 0.5;
  double ir_flood_light_intensity_ = 0.0;
  sensor_msgs::msg::CameraInfo color_camera_info_;
  sensor_msgs::msg::CameraInfo depth_camera_info_;

  rclcpp::Publisher<sensor_msgs::msg::CompressedImage>::SharedPtr color_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::Image>::SharedPtr depth_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::CompressedImage>::SharedPtr
    depth_preview_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::CameraInfo>::SharedPtr
    color_camera_info_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::CameraInfo>::SharedPtr
    depth_camera_info_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::Imu>::SharedPtr imu_publisher_;
  rclcpp::Publisher<sensor_msgs::msg::PointCloud2>::SharedPtr points_publisher_;
  rclcpp::Publisher<vision_msgs::msg::Detection2DArray>::SharedPtr
    detections_publisher_;
  rclcpp::Publisher<foxglove_msgs::msg::ImageAnnotations>::SharedPtr
    overlay_publisher_;
  rclcpp::node_interfaces::PostSetParametersCallbackHandle::SharedPtr
    parameters_callback_handle_;
  rclcpp::TimerBase::SharedPtr poll_timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto node = std::make_shared<OakDProWPoeSpatial>();
  rclcpp::spin(node);
  node->release_device();
  rclcpp::shutdown();
  return 0;
}
