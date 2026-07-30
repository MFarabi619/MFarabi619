cmake_minimum_required(VERSION 3.16)
project(robot_drivers)

if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  include(FetchContent)
  fetchcontent_declare(orbbec_sdk
    URL https://github.com/orbbec/OrbbecSDK_v2/releases/download/v2.9.3/OrbbecSDK_v2.9.3_202607151523_2f6561c_linux_arm64.tar.gz
    URL_HASH SHA256=ce2c476c283b932181b04daf44debadff9e4a743344bd69eecf34f8c18009ac1
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  fetchcontent_makeavailable(orbbec_sdk)
  find_package(OrbbecSDK REQUIRED CONFIG PATHS ${orbbec_sdk_SOURCE_DIR}/lib NO_DEFAULT_PATH)
endif()

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)

ament_python_install_module(src/adafruit_bno085.py)
install(FILES src/pwm_dir_motor_driver.py src/rpicam_mjpeg.py DESTINATION "${PYTHON_INSTALL_DIR}")

if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    add_compile_options(-Wall -Wextra)
  endif()

  find_package(rclcpp REQUIRED)
  find_package(rclcpp_components REQUIRED)
  find_package(robot_platform_msgs REQUIRED)
  find_package(ament_index_cpp REQUIRED)
  find_package(sensor_msgs REQUIRED)
  find_package(OpenCV REQUIRED)

  find_path(GPIOD_INCLUDE_DIR gpiod.h PATHS /usr/include REQUIRED)
  find_library(GPIOD_LIBRARY gpiod PATHS /usr/lib/aarch64-linux-gnu /usr/lib REQUIRED)

  add_executable(pwm_dir_motor_driver src/pwm_dir_motor_driver.cpp)
  target_compile_features(pwm_dir_motor_driver PUBLIC cxx_std_17)
  target_compile_options(pwm_dir_motor_driver PRIVATE "-idirafter${GPIOD_INCLUDE_DIR}")
  target_link_libraries(pwm_dir_motor_driver
    ${GPIOD_LIBRARY}
    rclcpp::rclcpp
    ${robot_platform_msgs_TARGETS})
  install(TARGETS pwm_dir_motor_driver DESTINATION lib/${PROJECT_NAME})

  add_library(orbbec_camera_component SHARED src/orbbec_gemini_335l.cpp)
  target_compile_features(orbbec_camera_component PUBLIC cxx_std_17)
  target_include_directories(orbbec_camera_component PRIVATE ${OpenCV_INCLUDE_DIRS})
  target_link_libraries(orbbec_camera_component
    ob::OrbbecSDK
    ament_index_cpp::ament_index_cpp
    rclcpp::rclcpp
    rclcpp_components::component
    ${OpenCV_LIBS}
    ${sensor_msgs_TARGETS})
  rclcpp_components_register_node(orbbec_camera_component
    PLUGIN "robot_drivers::OrbbecCamera"
    EXECUTABLE orbbec_gemini_335l)
  set_target_properties(orbbec_camera_component PROPERTIES INSTALL_RPATH "$ORIGIN")
  install(TARGETS orbbec_camera_component
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION lib/${PROJECT_NAME})
  set_target_properties(orbbec_gemini_335l PROPERTIES INSTALL_RPATH "$ORIGIN/..")
  install(TARGETS orbbec_gemini_335l DESTINATION lib/${PROJECT_NAME})
  file(GLOB orbbec_libraries ${orbbec_sdk_SOURCE_DIR}/lib/libOrbbecSDK.so*)
  install(FILES ${orbbec_libraries} DESTINATION lib)
  install(FILES ${orbbec_sdk_SOURCE_DIR}/lib/OrbbecSDKConfig.xml DESTINATION lib)
  install(DIRECTORY ${orbbec_sdk_SOURCE_DIR}/lib/extensions/ DESTINATION share/${PROJECT_NAME}/extensions)
endif()

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
