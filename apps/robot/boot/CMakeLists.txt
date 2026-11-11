cmake_minimum_required(VERSION 3.16)
project(robot_boot NONE)

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)

install(DIRECTORY launch config DESTINATION share/${PROJECT_NAME})
ament_python_install_module(launch/zenoh_router.py)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
