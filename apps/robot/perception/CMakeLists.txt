cmake_minimum_required(VERSION 3.16)
project(robot_perception)

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)
find_package(ament_index_cpp REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(vision_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(std_srvs REQUIRED)
find_package(foxglove_msgs REQUIRED)
find_package(image_geometry REQUIRED)
find_package(tf2_ros REQUIRED)
find_package(tf2_geometry_msgs REQUIRED)
find_package(OpenCV REQUIRED COMPONENTS imgcodecs imgproc)
find_package(onnxruntime CONFIG REQUIRED)

add_executable(collision_overlay src/collision_overlay.cpp)
target_compile_features(collision_overlay PUBLIC cxx_std_17)
target_link_libraries(collision_overlay
  rclcpp::rclcpp
  image_geometry::image_geometry
  tf2_ros::tf2_ros
  ${sensor_msgs_TARGETS}
  ${foxglove_msgs_TARGETS}
  ${tf2_geometry_msgs_TARGETS})
install(TARGETS collision_overlay DESTINATION lib/${PROJECT_NAME})

add_executable(person_detector src/person_detector.cpp)
target_compile_features(person_detector PUBLIC cxx_std_17)
target_link_libraries(person_detector
  rclcpp::rclcpp
  ament_index_cpp::ament_index_cpp
  image_geometry::image_geometry
  onnxruntime::onnxruntime
  opencv_imgcodecs
  opencv_imgproc
  ${sensor_msgs_TARGETS}
  ${vision_msgs_TARGETS}
  ${geometry_msgs_TARGETS}
  ${std_srvs_TARGETS}
  ${foxglove_msgs_TARGETS})
install(TARGETS person_detector DESTINATION lib/${PROJECT_NAME})

install(PROGRAMS src/color_blob_detector.py DESTINATION lib/${PROJECT_NAME} RENAME color_blob_detector)
install(PROGRAMS src/green_detector.py DESTINATION lib/${PROJECT_NAME} RENAME green_detector)
install(PROGRAMS src/canopy_detector.py DESTINATION lib/${PROJECT_NAME} RENAME canopy_detector)
install(PROGRAMS src/point_cloud_optical_adapter.py DESTINATION lib/${PROJECT_NAME} RENAME point_cloud_optical_adapter)
install(PROGRAMS src/apriltag_operator_adapter.py DESTINATION lib/${PROJECT_NAME} RENAME apriltag_operator_adapter)
install(PROGRAMS src/surface_detector.py DESTINATION lib/${PROJECT_NAME} RENAME surface_detector)
install(PROGRAMS src/ssd_mobilenet_person_detector.py DESTINATION lib/${PROJECT_NAME} RENAME ssd_mobilenet_person_detector)
install(PROGRAMS src/yolo26_person_detector.py DESTINATION lib/${PROJECT_NAME} RENAME yolo26_person_detector)
install(DIRECTORY models DESTINATION lib/${PROJECT_NAME})
install(DIRECTORY launch config DESTINATION share/${PROJECT_NAME} PATTERN "__pycache__" EXCLUDE)
install(PROGRAMS src/voice_word_detector.py DESTINATION lib/${PROJECT_NAME} RENAME voice_word_detector)
install(PROGRAMS src/voice_speaker.py DESTINATION lib/${PROJECT_NAME} RENAME voice_speaker)
install(PROGRAMS src/voice_transcriber.py DESTINATION lib/${PROJECT_NAME} RENAME voice_transcriber)
install(FILES src/voice_word_detector.py DESTINATION lib/${PROJECT_NAME})
ament_python_install_module(src/voice_vocabulary.py)
install(PROGRAMS src/hand_gesture_detector.py DESTINATION lib/${PROJECT_NAME} RENAME hand_gesture_detector)
install(PROGRAMS src/foxglove_panels.py DESTINATION lib/${PROJECT_NAME} RENAME foxglove_panels)
install(PROGRAMS src/stereolabs_zed_object_overlay.py DESTINATION lib/${PROJECT_NAME} RENAME stereolabs_zed_object_overlay)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
