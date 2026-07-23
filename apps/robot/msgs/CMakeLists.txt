cmake_minimum_required(VERSION 3.20)
project(robot_platform_msgs)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(std_msgs REQUIRED)
find_package(builtin_interfaces REQUIRED)
find_package(rosidl_default_generators REQUIRED)

rosidl_generate_interfaces(${PROJECT_NAME}
  msg/DisplayStatus.msg
  msg/Drive.msg
  msg/DriveFeedback.msg
  msg/Fans.msg
  msg/Feedback.msg
  msg/Lights.msg
  msg/PinoutCommand.msg
  msg/PinoutState.msg
  msg/Power.msg
  msg/RGB.msg
  msg/Status.msg
  msg/StopStatus.msg
  msg/Temperature.msg
  srv/ConfigureMcu.srv
  srv/SetPinout.srv
  DEPENDENCIES std_msgs builtin_interfaces
)

ament_export_dependencies(rosidl_default_runtime)

ament_package()
