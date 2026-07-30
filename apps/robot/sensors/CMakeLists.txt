cmake_minimum_required(VERSION 3.16)
project(robot_sensors)

find_package(ament_cmake REQUIRED)

install(PROGRAMS src/imu.py DESTINATION lib/${PROJECT_NAME} RENAME imu)
install(PROGRAMS src/camera.py DESTINATION lib/${PROJECT_NAME} RENAME camera)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
