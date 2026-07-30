cmake_minimum_required(VERSION 3.16)
project(robot_perception)

find_package(ament_cmake REQUIRED)

install(PROGRAMS src/cone_detector.py DESTINATION lib/${PROJECT_NAME} RENAME cone_detector)
install(PROGRAMS src/row_detector.py DESTINATION lib/${PROJECT_NAME} RENAME row_detector)
install(PROGRAMS src/approach.py DESTINATION lib/${PROJECT_NAME} RENAME approach)
install(PROGRAMS src/row_follow.py DESTINATION lib/${PROJECT_NAME} RENAME row_follow)
install(PROGRAMS src/gesture_teleop.py DESTINATION lib/${PROJECT_NAME} RENAME gesture_teleop)
install(PROGRAMS src/foxglove_panels.py DESTINATION lib/${PROJECT_NAME} RENAME foxglove_panels)
install(PROGRAMS src/gesture_to_cmd_vel.py DESTINATION lib/${PROJECT_NAME} RENAME gesture_to_cmd_vel)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
