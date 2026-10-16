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
ament_target_dependencies(kinova_link6_pick
  control_msgs
  geometric_shapes
  geometry_msgs
  moveit_msgs
  moveit_ros_planning_interface
  moveit_task_constructor_core
  rclcpp
  rclcpp_action
  sensor_msgs
  shape_msgs)

install(TARGETS kinova_link6_pick DESTINATION lib/${PROJECT_NAME})

ament_package()
