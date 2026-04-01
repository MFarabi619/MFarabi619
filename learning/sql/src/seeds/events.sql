WITH aligned_current_time AS (
    SELECT to_timestamp(floor(extract(epoch FROM now()) / 300) * 300) AS window_center_time
),
event_time_series AS (
    SELECT generate_series(
        aligned_current_time.window_center_time - interval '24 hours',
        aligned_current_time.window_center_time + interval '24 hours',
        interval '5 minutes'
    ) AS event_time
    FROM aligned_current_time
),
event_templates AS (
    SELECT *
    FROM (
        VALUES
            ('status.v1', 0),
            ('sensors.wind_speed.v1', 1),
            ('sensors.wind_direction.v1', 2),
            ('sensors.solar_radiation.v1', 3),
            ('sensors.soil.v1', 4),
            ('sensors.temperature_and_humidity.v1', 5)
    ) AS event_template(event_type, event_sequence)
),
base_events AS (
    SELECT
        event_time_series.event_time,
        event_templates.event_type,
        event_templates.event_sequence,
        format(
            '%s-%s-%s',
            event_templates.event_type,
            to_char(event_time_series.event_time AT TIME ZONE 'UTC', 'YYYYMMDD"T"HH24MISS"Z"'),
            event_templates.event_sequence
        ) AS cloud_event_id
    FROM event_time_series
    CROSS JOIN event_templates
),
event_payloads AS (
    SELECT
        base_events.cloud_event_id AS event_name,
        'urn:pulumi:dev::arctic-rover::microvisor:index:Node::arctic-rover.01'::text AS event_source,
        base_events.event_type,
        1.0::float8 AS cloud_event_specversion,
        'application/json'::text AS cloud_event_datacontenttype,
        base_events.event_time,
        CASE base_events.event_type
            WHEN 'status.v1' THEN jsonb_build_object(
                'memory_heap', 133000 + floor(450 * (1 + sin(extract(epoch FROM base_events.event_time) / 1800.0)))::int,
                'chip_model', 'ESP32-S3',
                'chip_cores', 2,
                'chip_revision', 2,
                'ipv4_address', '192.168.1.100',
                'wifi_rssi', -40 + floor(10 * sin(extract(epoch FROM base_events.event_time) / 2400.0))::int,
                'uptime_seconds', greatest(0, extract(epoch FROM (base_events.event_time - (SELECT min(event_time) FROM event_time_series)))::bigint)
            )
            WHEN 'sensors.wind_speed.v1' THEN jsonb_build_object(
                'read_ok', true,
                'wind_speed_kilometers_per_hour', round((0.6 + 2.8 * abs(sin(extract(epoch FROM base_events.event_time) / 2200.0)))::numeric, 2)
            )
            WHEN 'sensors.wind_direction.v1' THEN jsonb_build_object(
                'read_ok', true,
                'wind_direction_angle', round(mod((extract(epoch FROM base_events.event_time) / 45.0), 360.0)::numeric, 2),
                'wind_direction_slice', floor(mod((extract(epoch FROM base_events.event_time) / 45.0), 360.0) / 22.5)::int
            )
            WHEN 'sensors.solar_radiation.v1' THEN jsonb_build_object(
                'read_ok', true,
                'solar_radiation_watts_per_square_meter', floor(greatest(0, 350 * sin(extract(epoch FROM base_events.event_time) / 14400.0)))::int
            )
            WHEN 'sensors.soil.v1' THEN jsonb_build_object(
                'range_ok', true,
                'read_ok', true,
                'first_slave_id', 53,
                'last_slave_id', 72,
                'instance_count', 20,
                'temperature_celsius', round((-3.3 + 0.6 * sin(extract(epoch FROM base_events.event_time) / 3600.0))::numeric, 2),
                'moisture_percent', round((5.5 + 0.7 * sin(extract(epoch FROM base_events.event_time) / 4200.0))::numeric, 2),
                'conductivity', floor(5 + 3 * sin(extract(epoch FROM base_events.event_time) / 3000.0))::int,
                'salinity', floor(5 + 3 * cos(extract(epoch FROM base_events.event_time) / 3000.0))::int,
                'tds', floor(4 + 3 * sin(extract(epoch FROM base_events.event_time) / 2500.0))::int,
                'instances', (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'instance_index', soil_instance.instance_index,
                            'slave_id', 53 + soil_instance.instance_index,
                            'read_ok', true,
                            'temperature_celsius', round((-3.4 + 0.5 * sin((extract(epoch FROM base_events.event_time) / 3600.0) + soil_instance.instance_index))::numeric, 2),
                            'moisture_percent', round((5.5 + 0.8 * sin((extract(epoch FROM base_events.event_time) / 4800.0) + soil_instance.instance_index))::numeric, 2),
                            'conductivity', greatest(0, least(9, floor(5 + 4 * sin((extract(epoch FROM base_events.event_time) / 3000.0) + soil_instance.instance_index))::int)),
                            'salinity', greatest(0, least(9, floor(5 + 4 * cos((extract(epoch FROM base_events.event_time) / 3000.0) + soil_instance.instance_index))::int)),
                            'tds', greatest(0, least(9, floor(4 + 4 * sin((extract(epoch FROM base_events.event_time) / 2700.0) + soil_instance.instance_index))::int))
                        )
                    )
                    FROM generate_series(0, 19) AS soil_instance(instance_index)
                )
            )
            WHEN 'sensors.temperature_and_humidity.v1' THEN jsonb_build_object(
                'init_ok', true,
                'instances', jsonb_build_array(
                    jsonb_build_object(
                        'instance_index', 0,
                        'begin_ok', true,
                        'read_ok', true,
                        'temperature_celsius', round((-4.4 + 0.5 * sin(extract(epoch FROM base_events.event_time) / 3300.0))::numeric, 2),
                        'relative_humidity_percent', round((75 + 8 * sin(extract(epoch FROM base_events.event_time) / 2800.0))::numeric, 2)
                    ),
                    jsonb_build_object(
                        'instance_index', 1,
                        'begin_ok', true,
                        'read_ok', true,
                        'temperature_celsius', round((-4.5 + 0.5 * cos(extract(epoch FROM base_events.event_time) / 3300.0))::numeric, 2),
                        'relative_humidity_percent', round((73 + 8 * cos(extract(epoch FROM base_events.event_time) / 2800.0))::numeric, 2)
                    )
                ),
                'instance_count', 2,
                'successful_reads', 2,
                'read_ok', true
            )
        END AS event_data
    FROM base_events
)
INSERT INTO events (name, source, type, specversion, datacontenttype, time, data)
SELECT
    event_payloads.event_name,
    event_payloads.event_source,
    event_payloads.event_type,
    event_payloads.cloud_event_specversion,
    event_payloads.cloud_event_datacontenttype,
    event_payloads.event_time,
    event_payloads.event_data
FROM event_payloads;

WITH aligned_current_time AS (
    SELECT to_timestamp(floor(extract(epoch FROM now()) / 300) * 300) AS window_center_time
),
event_time_series AS (
    SELECT generate_series(
        aligned_current_time.window_center_time - interval '24 hours',
        aligned_current_time.window_center_time + interval '24 hours',
        interval '5 minutes'
    ) AS event_time
    FROM aligned_current_time
),
toronto_transit_commission_subway_nodes AS (
    SELECT
        node_numbers.node_number,
        lpad(node_numbers.node_number::text, 2, '0') AS node_id,
        format(
            'urn:pulumi:dev::arctic-rover::microvisor:index:Node::toronto-transit-commission-subway.%s',
            lpad(node_numbers.node_number::text, 2, '0')
        ) AS event_source
    FROM generate_series(1, 20) AS node_numbers(node_number)
),
event_types_per_node AS (
    SELECT
        toronto_transit_commission_subway_nodes.node_number,
        toronto_transit_commission_subway_nodes.node_id,
        toronto_transit_commission_subway_nodes.event_source,
        'sensors.temperature_and_humidity.v1'::text AS event_type,
        0 AS event_sequence
    FROM toronto_transit_commission_subway_nodes

    UNION ALL

    SELECT
        toronto_transit_commission_subway_nodes.node_number,
        toronto_transit_commission_subway_nodes.node_id,
        toronto_transit_commission_subway_nodes.event_source,
        'sensors.wind_speed.v1'::text AS event_type,
        1 AS event_sequence
    FROM toronto_transit_commission_subway_nodes
    WHERE toronto_transit_commission_subway_nodes.node_number IN (19, 20)

    UNION ALL

    SELECT
        toronto_transit_commission_subway_nodes.node_number,
        toronto_transit_commission_subway_nodes.node_id,
        toronto_transit_commission_subway_nodes.event_source,
        'sensors.wind_direction.v1'::text AS event_type,
        2 AS event_sequence
    FROM toronto_transit_commission_subway_nodes
    WHERE toronto_transit_commission_subway_nodes.node_number IN (19, 20)
),
toronto_transit_commission_subway_base_events AS (
    SELECT
        event_time_series.event_time,
        event_types_per_node.node_number,
        event_types_per_node.node_id,
        event_types_per_node.event_source,
        event_types_per_node.event_type,
        event_types_per_node.event_sequence,
        format(
            '%s-%s-%s-%s',
            event_types_per_node.event_type,
            to_char(event_time_series.event_time AT TIME ZONE 'UTC', 'YYYYMMDD"T"HH24MISS"Z"'),
            event_types_per_node.node_id,
            event_types_per_node.event_sequence
        ) AS cloud_event_id
    FROM event_time_series
    CROSS JOIN event_types_per_node
),
toronto_transit_commission_subway_event_payloads AS (
    SELECT
        toronto_transit_commission_subway_base_events.cloud_event_id AS event_name,
        toronto_transit_commission_subway_base_events.event_source,
        toronto_transit_commission_subway_base_events.event_type,
        1.0::float8 AS cloud_event_specversion,
        'application/json'::text AS cloud_event_datacontenttype,
        toronto_transit_commission_subway_base_events.event_time,
        CASE toronto_transit_commission_subway_base_events.event_type
            WHEN 'sensors.temperature_and_humidity.v1' THEN jsonb_build_object(
                'init_ok', true,
                'instances', jsonb_build_array(
                    jsonb_build_object(
                        'instance_index', 0,
                        'begin_ok', true,
                        'read_ok', true,
                        'temperature_celsius', round((-2.8 + 0.8 * sin((extract(epoch FROM toronto_transit_commission_subway_base_events.event_time) / 3300.0) + toronto_transit_commission_subway_base_events.node_number))::numeric, 2),
                        'relative_humidity_percent', round((61 + 9 * cos((extract(epoch FROM toronto_transit_commission_subway_base_events.event_time) / 2800.0) + toronto_transit_commission_subway_base_events.node_number))::numeric, 2)
                    )
                ),
                'instance_count', 1,
                'successful_reads', 1,
                'read_ok', true
            )
            WHEN 'sensors.wind_speed.v1' THEN jsonb_build_object(
                'read_ok', true,
                'wind_speed_kilometers_per_hour', round((1.1 + 3.2 * abs(sin((extract(epoch FROM toronto_transit_commission_subway_base_events.event_time) / 2600.0) + toronto_transit_commission_subway_base_events.node_number)))::numeric, 2)
            )
            WHEN 'sensors.wind_direction.v1' THEN jsonb_build_object(
                'read_ok', true,
                'wind_direction_angle', round(mod((extract(epoch FROM toronto_transit_commission_subway_base_events.event_time) / 55.0) + (toronto_transit_commission_subway_base_events.node_number * 12), 360.0)::numeric, 2),
                'wind_direction_slice', floor(mod((extract(epoch FROM toronto_transit_commission_subway_base_events.event_time) / 55.0) + (toronto_transit_commission_subway_base_events.node_number * 12), 360.0) / 22.5)::int
            )
        END AS event_data
    FROM toronto_transit_commission_subway_base_events
)
INSERT INTO events (name, source, type, specversion, datacontenttype, time, data)
SELECT
    toronto_transit_commission_subway_event_payloads.event_name,
    toronto_transit_commission_subway_event_payloads.event_source,
    toronto_transit_commission_subway_event_payloads.event_type,
    toronto_transit_commission_subway_event_payloads.cloud_event_specversion,
    toronto_transit_commission_subway_event_payloads.cloud_event_datacontenttype,
    toronto_transit_commission_subway_event_payloads.event_time,
    toronto_transit_commission_subway_event_payloads.event_data
FROM toronto_transit_commission_subway_event_payloads;

\dt

SELECT * from organizations;

SELECT * from events LIMIT 10;
