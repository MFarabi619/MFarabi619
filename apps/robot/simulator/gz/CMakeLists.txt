cmake_minimum_required(VERSION 3.16)
project(robot_gz NONE)

find_package(ament_cmake REQUIRED)

install(DIRECTORY launch worlds models DESTINATION share/${PROJECT_NAME})

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
