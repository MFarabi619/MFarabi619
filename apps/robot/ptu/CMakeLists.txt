cmake_minimum_required(VERSION 3.16)
project(robot_ptu)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(tf2_ros REQUIRED)
find_package(tf2_geometry_msgs REQUIRED)

include(FetchContent)
FetchContent_Declare(lg
  GIT_REPOSITORY https://github.com/joan2937/lg.git
  GIT_TAG v0.2.2)
FetchContent_GetProperties(lg)
if(NOT lg_POPULATED)
  FetchContent_Populate(lg)
endif()

set(LG_SOURCES
  ${lg_SOURCE_DIR}/rgpio.c
  ${lg_SOURCE_DIR}/lgCfg.c
  ${lg_SOURCE_DIR}/lgErr.c
  ${lg_SOURCE_DIR}/lgDbg.c
  ${lg_SOURCE_DIR}/lgMD5.c)

add_executable(ptu_driver src/ptu_driver.cpp ${LG_SOURCES})
target_compile_features(ptu_driver PUBLIC cxx_std_17)
target_include_directories(ptu_driver PRIVATE
  ${lg_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/lg_portability)
set_source_files_properties(
  ${LG_SOURCES}
  ${CMAKE_CURRENT_SOURCE_DIR}/src/ptu_driver.cpp
  PROPERTIES COMPILE_OPTIONS
  "-include;${CMAKE_CURRENT_SOURCE_DIR}/lg_portability/portability.h")
target_link_libraries(ptu_driver
  rclcpp::rclcpp
  ${geometry_msgs_TARGETS}
  ${sensor_msgs_TARGETS})

add_executable(ptu_aim src/ptu_aim.cpp)
target_compile_features(ptu_aim PUBLIC cxx_std_17)
target_link_libraries(ptu_aim
  rclcpp::rclcpp
  tf2_ros::tf2_ros
  tf2_geometry_msgs::tf2_geometry_msgs
  ${geometry_msgs_TARGETS}
  ${sensor_msgs_TARGETS})

install(TARGETS ptu_driver ptu_aim
  RUNTIME DESTINATION lib/${PROJECT_NAME})

ament_package()
