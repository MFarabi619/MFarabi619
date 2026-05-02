zephyr_library()

zephyr_library_sources(
  devices.c
  soil_moisture.c
  soil_moisture_three_in_one.c
)

# wind_speed.c, wind_direction.c, rainfall.c are kept on disk but excluded
# from the build until those sensor models are reintroduced.
