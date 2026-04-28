INSERT INTO samples (time, event_name, source, type, metric_id, instance_index, value)
SELECT
    events.time,
    events.name,
    events.source,
    events.type,
    metrics.id,
    metric_extraction.instance_index,
    metric_extraction.metric_value
FROM events
CROSS JOIN LATERAL (
    SELECT
        COALESCE((temperature_instance ->> 'instance_index')::int, 0) AS instance_index,
        temperature_metric.metric_name,
        temperature_metric.metric_value
    FROM jsonb_array_elements(events.data -> 'instances') AS temperature_instance
    CROSS JOIN LATERAL (
        VALUES
            ('temperature_celsius', (temperature_instance ->> 'temperature_celsius')::double precision),
            ('relative_humidity_percent', (temperature_instance ->> 'relative_humidity_percent')::double precision)
    ) AS temperature_metric(metric_name, metric_value)
    WHERE events.type = 'sensors.temperature_and_humidity.v1'
      AND jsonb_typeof(events.data -> 'instances') = 'array'

    UNION ALL

    SELECT
        0 AS instance_index,
        'wind_speed_kilometers_per_hour'::text AS metric_name,
        (events.data ->> 'wind_speed_kilometers_per_hour')::double precision AS metric_value
    WHERE events.type = 'sensors.wind_speed.v1'

    UNION ALL

    SELECT
        0 AS instance_index,
        wind_direction_metric.metric_name,
        wind_direction_metric.metric_value
    FROM (
        VALUES
            ('wind_direction_angle', (events.data ->> 'wind_direction_angle')::double precision),
            ('wind_direction_slice', (events.data ->> 'wind_direction_slice')::double precision)
    ) AS wind_direction_metric(metric_name, metric_value)
    WHERE events.type = 'sensors.wind_direction.v1'

    UNION ALL

    SELECT
        0 AS instance_index,
        soil_metric.metric_name,
        soil_metric.metric_value
    FROM (
        VALUES
            ('temperature_celsius', (events.data ->> 'temperature_celsius')::double precision),
            ('moisture_percent', (events.data ->> 'moisture_percent')::double precision),
            ('conductivity', (events.data ->> 'conductivity')::double precision),
            ('salinity', (events.data ->> 'salinity')::double precision),
            ('tds', (events.data ->> 'tds')::double precision)
    ) AS soil_metric(metric_name, metric_value)
    WHERE events.type = 'sensors.soil.v1'

    UNION ALL

    SELECT
        0 AS instance_index,
        'solar_radiation_watts_per_square_meter'::text AS metric_name,
        (events.data ->> 'solar_radiation_watts_per_square_meter')::double precision AS metric_value
    WHERE events.type = 'sensors.solar_radiation.v1'

    UNION ALL

    SELECT
        0 AS instance_index,
        co2_metric.metric_name,
        co2_metric.metric_value
    FROM (
        VALUES
            ('co2_ppm', (events.data ->> 'co2_ppm')::double precision),
            ('temperature', (events.data ->> 'temperature')::double precision),
            ('humidity', (events.data ->> 'humidity')::double precision)
    ) AS co2_metric(metric_name, metric_value)
    WHERE events.type = 'sensors.carbon_dioxide.v1'

    UNION ALL

    SELECT
        0 AS instance_index,
        current_metric.metric_name,
        current_metric.metric_value
    FROM (
        VALUES
            ('current_mA', (events.data ->> 'current_mA')::double precision),
            ('bus_voltage_V', (events.data ->> 'bus_voltage_V')::double precision),
            ('shunt_voltage_mV', (events.data ->> 'shunt_voltage_mV')::double precision),
            ('power_mW', (events.data ->> 'power_mW')::double precision),
            ('energy_J', (events.data ->> 'energy_J')::double precision),
            ('charge_C', (events.data ->> 'charge_C')::double precision),
            ('die_temperature_C', (events.data ->> 'die_temperature_C')::double precision)
    ) AS current_metric(metric_name, metric_value)
    WHERE events.type = 'sensors.current.v1'

    UNION ALL

    SELECT
        0 AS instance_index,
        pressure_metric.metric_name,
        pressure_metric.metric_value
    FROM (
        VALUES
            ('pressure_hpa', (events.data ->> 'pressure_hpa')::double precision),
            ('temperature_celsius', (events.data ->> 'temperature_celsius')::double precision)
    ) AS pressure_metric(metric_name, metric_value)
    WHERE events.type = 'sensors.barometric_pressure.v1'

    UNION ALL

    SELECT
        0 AS instance_index,
        'rainfall_millimeters'::text AS metric_name,
        (events.data ->> 'rainfall_millimeters')::double precision AS metric_value
    WHERE events.type = 'sensors.rainfall.v1'

    UNION ALL

    SELECT
        voltage_channel.channel_index AS instance_index,
        voltage_metric.metric_name,
        voltage_metric.metric_value
    FROM generate_series(0, 3) AS voltage_channel(channel_index)
    CROSS JOIN LATERAL (
        VALUES
            ('voltage', (events.data -> 'voltage' ->> voltage_channel.channel_index)::double precision),
            ('temperature_celsius', (events.data -> 'temperature_celsius' ->> voltage_channel.channel_index)::double precision)
    ) AS voltage_metric(metric_name, metric_value)
    WHERE events.type = 'sensors.power.v1'
      AND jsonb_typeof(events.data -> 'voltage') = 'array'

    UNION ALL

    SELECT
        0 AS instance_index,
        status_metric.metric_name,
        status_metric.metric_value
    FROM (
        VALUES
            ('memory_heap', (events.data ->> 'memory_heap')::double precision),
            ('chip_cores', (events.data ->> 'chip_cores')::double precision),
            ('chip_revision', (events.data ->> 'chip_revision')::double precision),
            ('wifi_rssi', (events.data ->> 'wifi_rssi')::double precision),
            ('uptime_seconds', (events.data ->> 'uptime_seconds')::double precision)
    ) AS status_metric(metric_name, metric_value)
    WHERE events.type = 'status.v1'
) AS metric_extraction(instance_index, metric_name, metric_value)
JOIN metrics
    ON metrics.type = events.type
   AND metrics.name = metric_extraction.metric_name
ON CONFLICT DO NOTHING;
