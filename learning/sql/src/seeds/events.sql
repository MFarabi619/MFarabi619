DROP TABLE IF EXISTS seed_event_time_series;

CREATE TEMP TABLE seed_event_time_series AS
WITH aligned_current_time AS (
    SELECT to_timestamp(floor(extract(epoch FROM now()) / 300) * 300) AS window_center_time
)
SELECT generate_series(
    aligned_current_time.window_center_time - interval '24 hours',
    aligned_current_time.window_center_time + interval '24 hours',
    interval '5 minutes'
) AS event_time
FROM aligned_current_time;

WITH seed_node_definitions AS (
    SELECT
        'urn:pulumi:dev::arctic-rover::microvisor:index:Node::arctic-rover.01'::text AS event_source,
        NULL::int AS node_number,
        NULL::text AS node_id,
        'arctic'::text AS node_group

    UNION ALL

    SELECT
        format(
            'urn:pulumi:dev::arctic-rover::microvisor:index:Node::toronto-transit-commission-subway.%s',
            lpad(toronto_node.node_number::text, 2, '0')
        ) AS event_source,
        toronto_node.node_number,
        lpad(toronto_node.node_number::text, 2, '0') AS node_id,
        'toronto'::text AS node_group
    FROM generate_series(1, 20) AS toronto_node(node_number)
),
seed_event_definitions AS (
    SELECT
        seed_node_definitions.event_source,
        seed_node_definitions.node_number,
        seed_node_definitions.node_id,
        seed_node_definitions.node_group,
        arctic_event.event_type,
        arctic_event.event_sequence
    FROM seed_node_definitions
    CROSS JOIN (
        VALUES
            ('status.v1', 0),
            ('sensors.wind_speed.v1', 1),
            ('sensors.wind_direction.v1', 2),
            ('sensors.solar_radiation.v1', 3),
            ('sensors.soil.v1', 4),
            ('sensors.temperature_and_humidity.v1', 5),
            ('sensors.power.v1', 6),
            ('sensors.current.v1', 7),
            ('sensors.barometric_pressure.v1', 8),
            ('sensors.rainfall.v1', 9)
    ) AS arctic_event(event_type, event_sequence)
    WHERE seed_node_definitions.node_group = 'arctic'

    UNION ALL

    SELECT
        seed_node_definitions.event_source,
        seed_node_definitions.node_number,
        seed_node_definitions.node_id,
        seed_node_definitions.node_group,
        'sensors.temperature_and_humidity.v1'::text AS event_type,
        0 AS event_sequence
    FROM seed_node_definitions
    WHERE seed_node_definitions.node_group = 'toronto'

    UNION ALL

    SELECT
        seed_node_definitions.event_source,
        seed_node_definitions.node_number,
        seed_node_definitions.node_id,
        seed_node_definitions.node_group,
        'sensors.wind_speed.v1'::text AS event_type,
        1 AS event_sequence
    FROM seed_node_definitions
    WHERE seed_node_definitions.node_group = 'toronto'
      AND seed_node_definitions.node_number IN (19, 20)

    UNION ALL

    SELECT
        seed_node_definitions.event_source,
        seed_node_definitions.node_number,
        seed_node_definitions.node_id,
        seed_node_definitions.node_group,
        'sensors.wind_direction.v1'::text AS event_type,
        2 AS event_sequence
    FROM seed_node_definitions
    WHERE seed_node_definitions.node_group = 'toronto'
      AND seed_node_definitions.node_number IN (19, 20)
),
seed_event_rows AS (
    SELECT
        seed_event_time_series.event_time,
        seed_event_definitions.event_source,
        seed_event_definitions.node_number,
        seed_event_definitions.node_group,
        seed_event_definitions.event_type,
        seed_event_definitions.event_sequence,
        CASE
            WHEN seed_event_definitions.node_group = 'arctic' THEN format(
                '%s-%s-%s',
                seed_event_definitions.event_type,
                to_char(seed_event_time_series.event_time AT TIME ZONE 'UTC', 'YYYYMMDD"T"HH24MISS"Z"'),
                seed_event_definitions.event_sequence
            )
            ELSE format(
                '%s-%s-%s-%s',
                seed_event_definitions.event_type,
                to_char(seed_event_time_series.event_time AT TIME ZONE 'UTC', 'YYYYMMDD"T"HH24MISS"Z"'),
                seed_event_definitions.node_id,
                seed_event_definitions.event_sequence
            )
        END AS cloud_event_id
    FROM seed_event_time_series
    CROSS JOIN seed_event_definitions
)
INSERT INTO events (name, source, type, specversion, datacontenttype, time, data)
SELECT
    seed_event_rows.cloud_event_id,
    seed_event_rows.event_source,
    seed_event_rows.event_type,
    '1.0'::text AS specversion,
    'application/json'::text AS datacontenttype,
    seed_event_rows.event_time,
    CASE
        WHEN seed_event_rows.event_type = 'status.v1' THEN jsonb_build_object(
            'memory_heap', 133000 + floor(450 * (1 + sin(extract(epoch FROM seed_event_rows.event_time) / 1800.0)))::int,
            'chip_model', 'ESP32-S3',
            'chip_cores', 2,
            'chip_revision', 2,
            'ipv4_address', '192.168.1.100',
            'wifi_rssi', -40 + floor(10 * sin(extract(epoch FROM seed_event_rows.event_time) / 2400.0))::int,
            'uptime_seconds', greatest(0, extract(epoch FROM (seed_event_rows.event_time - (SELECT min(event_time) FROM seed_event_time_series)))::bigint)
        )
        WHEN seed_event_rows.event_type = 'sensors.wind_speed.v1'
         AND seed_event_rows.node_group = 'arctic' THEN jsonb_build_object(
            'read_ok', true,
            'wind_speed_kilometers_per_hour', round((0.6 + 2.8 * abs(sin(extract(epoch FROM seed_event_rows.event_time) / 2200.0)))::numeric, 2)
        )
        WHEN seed_event_rows.event_type = 'sensors.wind_direction.v1'
         AND seed_event_rows.node_group = 'arctic' THEN jsonb_build_object(
            'read_ok', true,
            'wind_direction_angle', round(mod((extract(epoch FROM seed_event_rows.event_time) / 45.0), 360.0)::numeric, 2),
            'wind_direction_slice', floor(mod((extract(epoch FROM seed_event_rows.event_time) / 45.0), 360.0) / 22.5)::int
        )
        WHEN seed_event_rows.event_type = 'sensors.solar_radiation.v1' THEN jsonb_build_object(
            'read_ok', true,
            'solar_radiation_watts_per_square_meter', floor(greatest(0, 350 * sin(extract(epoch FROM seed_event_rows.event_time) / 14400.0)))::int
        )
        WHEN seed_event_rows.event_type = 'sensors.soil.v1' THEN jsonb_build_object(
            'range_ok', true,
            'read_ok', true,
            'first_slave_id', 53,
            'last_slave_id', 72,
            'instance_count', 20,
            'temperature_celsius', round((-3.3 + 0.6 * sin(extract(epoch FROM seed_event_rows.event_time) / 3600.0))::numeric, 2),
            'moisture_percent', round((5.5 + 0.7 * sin(extract(epoch FROM seed_event_rows.event_time) / 4200.0))::numeric, 2),
            'conductivity', floor(5 + 3 * sin(extract(epoch FROM seed_event_rows.event_time) / 3000.0))::int,
            'salinity', floor(5 + 3 * cos(extract(epoch FROM seed_event_rows.event_time) / 3000.0))::int,
            'tds', floor(4 + 3 * sin(extract(epoch FROM seed_event_rows.event_time) / 2500.0))::int,
            'instances', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'instance_index', soil_instance.instance_index,
                        'slave_id', 53 + soil_instance.instance_index,
                        'read_ok', true,
                        'temperature_celsius', round((-3.4 + 0.5 * sin((extract(epoch FROM seed_event_rows.event_time) / 3600.0) + soil_instance.instance_index))::numeric, 2),
                        'moisture_percent', round((5.5 + 0.8 * sin((extract(epoch FROM seed_event_rows.event_time) / 4800.0) + soil_instance.instance_index))::numeric, 2),
                        'conductivity', greatest(0, least(9, floor(5 + 4 * sin((extract(epoch FROM seed_event_rows.event_time) / 3000.0) + soil_instance.instance_index))::int)),
                        'salinity', greatest(0, least(9, floor(5 + 4 * cos((extract(epoch FROM seed_event_rows.event_time) / 3000.0) + soil_instance.instance_index))::int)),
                        'tds', greatest(0, least(9, floor(4 + 4 * sin((extract(epoch FROM seed_event_rows.event_time) / 2700.0) + soil_instance.instance_index))::int))
                    )
                )
                FROM generate_series(0, 19) AS soil_instance(instance_index)
            )
        )
        WHEN seed_event_rows.event_type = 'sensors.power.v1' THEN jsonb_build_object(
            'read_ok', true,
            'gain', 'GAIN_ONE',
            'voltage', jsonb_build_array(
                round((3.30 + 0.02 * sin(extract(epoch FROM seed_event_rows.event_time) / 1800.0))::numeric, 4),
                round((3.31 + 0.02 * cos(extract(epoch FROM seed_event_rows.event_time) / 1800.0))::numeric, 4),
                round((12.00 + 0.05 * sin(extract(epoch FROM seed_event_rows.event_time) / 2400.0))::numeric, 4),
                round((0.001 * abs(sin(extract(epoch FROM seed_event_rows.event_time) / 3600.0)))::numeric, 4)
            ),
            'temperature_celsius', jsonb_build_array(
                round((25.1 + 0.3 * sin(extract(epoch FROM seed_event_rows.event_time) / 3000.0))::numeric, 6),
                round((25.2 + 0.3 * cos(extract(epoch FROM seed_event_rows.event_time) / 3000.0))::numeric, 6),
                round((25.0 + 0.2 * sin(extract(epoch FROM seed_event_rows.event_time) / 3200.0))::numeric, 6),
                round((25.0 + 0.2 * cos(extract(epoch FROM seed_event_rows.event_time) / 3200.0))::numeric, 6)
            )
        )
        WHEN seed_event_rows.event_type = 'sensors.current.v1' THEN jsonb_build_object(
            'current_mA', round((150.0 + 20.0 * sin(extract(epoch FROM seed_event_rows.event_time) / 2000.0))::numeric, 3),
            'bus_voltage_V', round((3.30 + 0.01 * sin(extract(epoch FROM seed_event_rows.event_time) / 1800.0))::numeric, 4),
            'shunt_voltage_mV', round((4.90 + 0.6 * sin(extract(epoch FROM seed_event_rows.event_time) / 2000.0))::numeric, 4),
            'power_mW', round((495.0 + 66.0 * sin(extract(epoch FROM seed_event_rows.event_time) / 2000.0))::numeric, 3),
            'energy_J', round(greatest(0, extract(epoch FROM (seed_event_rows.event_time - (SELECT min(event_time) FROM seed_event_time_series))) * 0.495)::numeric, 3),
            'charge_C', round(greatest(0, extract(epoch FROM (seed_event_rows.event_time - (SELECT min(event_time) FROM seed_event_time_series))) * 0.150)::numeric, 6),
            'die_temperature_C', round((28.0 + 1.0 * sin(extract(epoch FROM seed_event_rows.event_time) / 3600.0))::numeric, 1)
        )
        WHEN seed_event_rows.event_type = 'sensors.barometric_pressure.v1' THEN jsonb_build_object(
            'model', 'LPS25',
            'pressure_hpa', round((1013.25 + 5.0 * sin(extract(epoch FROM seed_event_rows.event_time) / 7200.0))::numeric, 2),
            'temperature_celsius', round((22.0 + 1.5 * sin(extract(epoch FROM seed_event_rows.event_time) / 3600.0))::numeric, 1)
        )
        WHEN seed_event_rows.event_type = 'sensors.rainfall.v1' THEN jsonb_build_object(
            'rainfall_millimeters', round(greatest(0, 0.8 * abs(sin(extract(epoch FROM seed_event_rows.event_time) / 5400.0)))::numeric, 1)
        )
        WHEN seed_event_rows.event_type = 'sensors.temperature_and_humidity.v1'
         AND seed_event_rows.node_group = 'arctic' THEN jsonb_build_object(
            'init_ok', true,
            'instances', jsonb_build_array(
                jsonb_build_object(
                    'instance_index', 0,
                    'begin_ok', true,
                    'read_ok', true,
                    'temperature_celsius', round((-4.4 + 0.5 * sin(extract(epoch FROM seed_event_rows.event_time) / 3300.0))::numeric, 2),
                    'relative_humidity_percent', round((75 + 8 * sin(extract(epoch FROM seed_event_rows.event_time) / 2800.0))::numeric, 2)
                ),
                jsonb_build_object(
                    'instance_index', 1,
                    'begin_ok', true,
                    'read_ok', true,
                    'temperature_celsius', round((-4.5 + 0.5 * cos(extract(epoch FROM seed_event_rows.event_time) / 3300.0))::numeric, 2),
                    'relative_humidity_percent', round((73 + 8 * cos(extract(epoch FROM seed_event_rows.event_time) / 2800.0))::numeric, 2)
                )
            ),
            'instance_count', 2,
            'successful_reads', 2,
            'read_ok', true
        )
        WHEN seed_event_rows.event_type = 'sensors.temperature_and_humidity.v1' THEN jsonb_build_object(
            'init_ok', true,
            'instances', jsonb_build_array(
                jsonb_build_object(
                    'instance_index', 0,
                    'begin_ok', true,
                    'read_ok', true,
                    'temperature_celsius', round((-2.8 + 0.8 * sin((extract(epoch FROM seed_event_rows.event_time) / 3300.0) + seed_event_rows.node_number))::numeric, 2),
                    'relative_humidity_percent', round((61 + 9 * cos((extract(epoch FROM seed_event_rows.event_time) / 2800.0) + seed_event_rows.node_number))::numeric, 2)
                )
            ),
            'instance_count', 1,
            'successful_reads', 1,
            'read_ok', true
        )
        WHEN seed_event_rows.event_type = 'sensors.wind_speed.v1' THEN jsonb_build_object(
            'read_ok', true,
            'wind_speed_kilometers_per_hour', round((1.1 + 3.2 * abs(sin((extract(epoch FROM seed_event_rows.event_time) / 2600.0) + seed_event_rows.node_number)))::numeric, 2)
        )
        WHEN seed_event_rows.event_type = 'sensors.wind_direction.v1' THEN jsonb_build_object(
            'read_ok', true,
            'wind_direction_angle', round(mod((extract(epoch FROM seed_event_rows.event_time) / 55.0) + (seed_event_rows.node_number * 12), 360.0)::numeric, 2),
            'wind_direction_slice', floor(mod((extract(epoch FROM seed_event_rows.event_time) / 55.0) + (seed_event_rows.node_number * 12), 360.0) / 22.5)::int
        )
    END AS data
FROM seed_event_rows;
