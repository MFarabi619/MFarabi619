cmake_minimum_required(VERSION 3.16)
project(robot_perception)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(foxglove_msgs REQUIRED)
find_package(image_geometry REQUIRED)
find_package(tf2_ros REQUIRED)
find_package(tf2_geometry_msgs REQUIRED)

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

install(PROGRAMS src/color_blob_detector.py DESTINATION lib/${PROJECT_NAME} RENAME color_blob_detector)
install(PROGRAMS src/green_detector.py DESTINATION lib/${PROJECT_NAME} RENAME green_detector)
install(PROGRAMS src/row_navigator.py DESTINATION lib/${PROJECT_NAME} RENAME row_navigator)
install(PROGRAMS src/canopy_detector.py DESTINATION lib/${PROJECT_NAME} RENAME canopy_detector)
install(PROGRAMS src/cloud_optical_relay.py DESTINATION lib/${PROJECT_NAME} RENAME cloud_optical_relay)
install(PROGRAMS src/harvest_lane_navigator.py DESTINATION lib/${PROJECT_NAME} RENAME harvest_lane_navigator)
install(PROGRAMS src/row_shuttle.py DESTINATION lib/${PROJECT_NAME} RENAME row_shuttle)
install(PROGRAMS src/apriltag_operator_adapter.py DESTINATION lib/${PROJECT_NAME} RENAME apriltag_operator_adapter)
install(PROGRAMS src/sidewalk_detector.py DESTINATION lib/${PROJECT_NAME} RENAME sidewalk_detector)
install(PROGRAMS src/ssd_mobilenet_person_detector.py DESTINATION lib/${PROJECT_NAME} RENAME ssd_mobilenet_person_detector)
install(PROGRAMS src/yolo26_person_detector.py DESTINATION lib/${PROJECT_NAME} RENAME yolo26_person_detector)
install(PROGRAMS src/approach.py DESTINATION lib/${PROJECT_NAME} RENAME approach)
install(PROGRAMS src/tracked_approach.py DESTINATION lib/${PROJECT_NAME} RENAME tracked_approach)
install(PROGRAMS src/row_follow.py DESTINATION lib/${PROJECT_NAME} RENAME row_follow)
install(PROGRAMS src/gesture_teleop.py DESTINATION lib/${PROJECT_NAME} RENAME gesture_teleop)
install(PROGRAMS src/foxglove_panels.py DESTINATION lib/${PROJECT_NAME} RENAME foxglove_panels)
install(PROGRAMS src/gesture_to_cmd_vel.py DESTINATION lib/${PROJECT_NAME} RENAME gesture_to_cmd_vel)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
