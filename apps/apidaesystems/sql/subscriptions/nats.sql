CREATE SERVER nats_server FOREIGN DATA WRAPPER pgnats_fdw OPTIONS (
    host 'nats',
    port '4222'
);

SELECT nats_subscribe('ceratina.*.soil.*.state', 'handle_sensor_event'::regproc);
SELECT nats_subscribe('ceratina.*.status.state', 'handle_sensor_event'::regproc);
