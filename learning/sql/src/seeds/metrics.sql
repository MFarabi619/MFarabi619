INSERT INTO metrics (type, name, unit)
VALUES
    ('sensors.temperature_and_humidity.v1', 'temperature_celsius', 'celsius'),
    ('sensors.temperature_and_humidity.v1', 'relative_humidity_percent', 'percent'),
    ('sensors.wind_speed.v1', 'wind_speed_kilometers_per_hour', 'kilometers_per_hour'),
    ('sensors.wind_direction.v1', 'wind_direction_angle', 'degrees'),
    ('sensors.wind_direction.v1', 'wind_direction_slice', 'slice_index'),
    ('sensors.solar_radiation.v1', 'solar_radiation_watts_per_square_meter', 'watts_per_square_meter'),
    ('sensors.soil.v1', 'temperature_celsius', 'celsius'),
    ('sensors.soil.v1', 'moisture_percent', 'percent'),
    ('sensors.soil.v1', 'conductivity', 'conductivity'),
    ('sensors.soil.v1', 'salinity', 'salinity'),
    ('sensors.soil.v1', 'tds', 'tds'),
    ('status.v1', 'memory_heap', 'bytes'),
    ('status.v1', 'chip_cores', 'count'),
    ('status.v1', 'chip_revision', 'count'),
    ('status.v1', 'wifi_rssi', 'dbm'),
    ('status.v1', 'uptime_seconds', 'seconds')
ON CONFLICT (type, name) DO NOTHING;
