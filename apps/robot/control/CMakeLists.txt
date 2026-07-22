cmake_minimum_required(VERSION 3.16)
project(robot_control NONE)

find_package(ament_cmake REQUIRED)

install(DIRECTORY config DESTINATION share/${PROJECT_NAME})

ament_package()
