cmake_minimum_required(VERSION 3.16)
project(robot_manipulation)

find_package(ament_cmake REQUIRED)
find_package(control_msgs REQUIRED)
find_package(geometric_shapes REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(moveit_msgs REQUIRED)
find_package(moveit_ros_planning_interface REQUIRED)
find_package(moveit_task_constructor_core REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rclcpp_action REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(shape_msgs REQUIRED)

add_executable(kinova_link6_pick src/kinova_link6_pick.cpp)
target_compile_features(kinova_link6_pick PUBLIC cxx_std_17)
target_link_libraries(kinova_link6_pick
  rclcpp::rclcpp
  rclcpp_action::rclcpp_action
  geometric_shapes::geometric_shapes
  moveit_ros_planning_interface::moveit_planning_scene_interface
  moveit_task_constructor_core::moveit_task_constructor_core
  moveit_task_constructor_core::moveit_task_constructor_core_stages
  ${control_msgs_TARGETS}
  ${geometry_msgs_TARGETS}
  ${moveit_msgs_TARGETS}
  ${sensor_msgs_TARGETS}
  ${shape_msgs_TARGETS})

install(TARGETS kinova_link6_pick DESTINATION lib/${PROJECT_NAME})

ament_package()
