rust_cargo_application(CRATE_NAME walter_router)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../firmware ${CMAKE_BINARY_DIR}/firmware)

target_sources(app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/cellular.c)
