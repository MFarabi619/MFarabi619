\set rutabaga_1_url 'https://rutabaga-1.apidaesystems.ca/api/cloudevents'
\set rutabaga_2_url 'https://rutabaga-2.apidaesystems.ca/api/cloudevents'
\set funguy_url    'https://funguy.apidaesystems.ca/api/cloudevents'


SELECT cron.schedule(
    'poll-rutabaga-1',
    '* * * * *',
    format($$SELECT poll_cloudevents('%s')$$, :'rutabaga_1_url')
);

SELECT cron.schedule(
    'poll-rutabaga-2',
    '* * * * *',
    format($$SELECT poll_cloudevents('%s')$$, :'rutabaga_2_url')
);

SELECT cron.schedule(
    'poll-funguy',
    '* * * * *',
    format($$SELECT poll_cloudevents('%s')$$, :'funguy_url')
);
