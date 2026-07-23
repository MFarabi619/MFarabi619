cmake_minimum_required(VERSION 3.16)
project(robot_hardware_interfaces)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra)
endif()

find_package(ament_cmake REQUIRED)
find_package(hardware_interface REQUIRED)
find_package(pluginlib REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rclcpp_lifecycle REQUIRED)
find_package(robot_platform_msgs REQUIRED)

add_library(robot_hardware_interfaces SHARED
  src/diff_drive/hardware.cpp
  src/diff_drive/hardware_interface.cpp)
target_compile_features(robot_hardware_interfaces PUBLIC cxx_std_17)
target_include_directories(robot_hardware_interfaces PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:include>)
target_link_libraries(robot_hardware_interfaces PUBLIC
  hardware_interface::hardware_interface
  pluginlib::pluginlib
  rclcpp::rclcpp
  rclcpp_lifecycle::rclcpp_lifecycle
  ${robot_platform_msgs_TARGETS})

pluginlib_export_plugin_description_file(hardware_interface robot_hardware_interfaces.xml)

install(TARGETS robot_hardware_interfaces
  EXPORT export_robot_hardware_interfaces
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
install(DIRECTORY include/ DESTINATION include)

ament_export_targets(export_robot_hardware_interfaces HAS_LIBRARY_TARGET)
ament_export_dependencies(hardware_interface pluginlib rclcpp rclcpp_lifecycle robot_platform_msgs)

ament_package()
