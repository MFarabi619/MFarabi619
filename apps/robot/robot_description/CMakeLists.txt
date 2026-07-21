cmake_minimum_required(VERSION 3.16)
project(robot_description NONE)

find_package(ament_cmake REQUIRED)

install(DIRECTORY urdf meshes launch DESTINATION share/${PROJECT_NAME})

ament_package()
