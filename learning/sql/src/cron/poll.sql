\set device_url 'https://ceratina.apidaesystems.ca/api'

SELECT cron.schedule(
    'poll-temperature-humidity',
    '* * * * *',
    format($$SELECT poll_sensor_loop('%s/sensors/temperature-humidity', 'sensors.temperature_and_humidity.v1', 1)$$, :'device_url')
);

SELECT cron.schedule(
    'poll-cloudevents',
    '* * * * *',
    format($$SELECT poll_cloudevents('%s/cloudevents')$$, :'device_url')
);
