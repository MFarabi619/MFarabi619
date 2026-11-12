cmake_minimum_required(VERSION 3.16)
project(robot_machines NONE)

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)

ament_get_python_install_dir(PYTHON_INSTALL_DIR)
install(
  DIRECTORY src/ DESTINATION ${PYTHON_INSTALL_DIR}/${PROJECT_NAME}
  FILES_MATCHING PATTERN "*.py")
install(DIRECTORY ../elec/boards DESTINATION share/${PROJECT_NAME})
file(GLOB machine_files RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
  */robot.yaml */motions.yaml */params/*.yaml)
foreach(machine_file ${machine_files})
  get_filename_component(machine ${machine_file} DIRECTORY)
  install(FILES ${machine_file} DESTINATION share/${PROJECT_NAME}/${machine})
endforeach()

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
