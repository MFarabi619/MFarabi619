cmake_minimum_required(VERSION 3.16)
project(robot_hardware_interfaces)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra)
endif()

find_package(ament_cmake REQUIRED)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  find_package(hardware_interface REQUIRED)
  find_package(pluginlib REQUIRED)
  find_package(rclcpp REQUIRED)
  find_package(rclcpp_lifecycle REQUIRED)
  find_package(Threads REQUIRED)

  include(FetchContent)
  FetchContent_Declare(lg
    GIT_REPOSITORY https://github.com/joan2937/lg.git
    GIT_TAG v0.2.2)
  FetchContent_GetProperties(lg)
  if(NOT lg_POPULATED)
    FetchContent_Populate(lg)
  endif()

  file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/uapi/linux)
  file(COPY_FILE /usr/include/linux/gpio.h
    ${CMAKE_CURRENT_BINARY_DIR}/uapi/linux/gpio.h ONLY_IF_DIFFERENT)

  add_library(robot_hardware_interfaces SHARED
    src/hardware.cpp
    ${lg_SOURCE_DIR}/lgCtx.c
    ${lg_SOURCE_DIR}/lgDbg.c
    ${lg_SOURCE_DIR}/lgErr.c
    ${lg_SOURCE_DIR}/lgGpio.c
    ${lg_SOURCE_DIR}/lgHdl.c
    ${lg_SOURCE_DIR}/lgI2C.c
    ${lg_SOURCE_DIR}/lgNotify.c
    ${lg_SOURCE_DIR}/lgPthAlerts.c
    ${lg_SOURCE_DIR}/lgPthTx.c
    ${lg_SOURCE_DIR}/lgSerial.c
    ${lg_SOURCE_DIR}/lgSPI.c
    ${lg_SOURCE_DIR}/lgThread.c
    ${lg_SOURCE_DIR}/lgUtil.c)
  target_compile_features(robot_hardware_interfaces PUBLIC cxx_std_17)
  target_include_directories(robot_hardware_interfaces PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>)
  target_include_directories(robot_hardware_interfaces PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}/uapi
    ${lg_SOURCE_DIR})
  target_link_libraries(robot_hardware_interfaces PUBLIC
    hardware_interface::hardware_interface
    pluginlib::pluginlib
    rclcpp::rclcpp
    rclcpp_lifecycle::rclcpp_lifecycle
    Threads::Threads)

  pluginlib_export_plugin_description_file(hardware_interface robot_hardware_interfaces.xml)

  install(TARGETS robot_hardware_interfaces
    EXPORT export_robot_hardware_interfaces
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin)
  install(DIRECTORY include/ DESTINATION include)

  ament_export_targets(export_robot_hardware_interfaces HAS_LIBRARY_TARGET)
  ament_export_dependencies(hardware_interface pluginlib rclcpp rclcpp_lifecycle)
endif()

ament_package()
