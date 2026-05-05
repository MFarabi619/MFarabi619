CREATE SERVER nats_server FOREIGN DATA WRAPPER pgnats_fdw OPTIONS (
    host 'nats',
    port '4222'
);

SELECT nats_subscribe('ceratina.>', 'handle_sensor_event'::regproc);
