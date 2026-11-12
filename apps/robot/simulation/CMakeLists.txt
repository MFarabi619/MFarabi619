cmake_minimum_required(VERSION 3.16)
project(robot_simulation NONE)

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)

install(
  DIRECTORY launch worlds models DESTINATION share/${PROJECT_NAME}
  PATTERN "__pycache__" EXCLUDE)
install(FILES gui.config arm_gui.config DESTINATION share/${PROJECT_NAME})
ament_get_python_install_dir(PYTHON_INSTALL_DIR)
install(
  DIRECTORY src/ DESTINATION ${PYTHON_INSTALL_DIR}/${PROJECT_NAME}
  FILES_MATCHING PATTERN "*.py")

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
