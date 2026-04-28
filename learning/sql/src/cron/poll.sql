\set device_url 'https://ceratina.apidaesystems.ca/api'


SELECT cron.schedule(
    'poll-cloudevents',
    '* * * * *',
    format($$SELECT poll_cloudevents('%s/cloudevents')$$, :'device_url')
);
