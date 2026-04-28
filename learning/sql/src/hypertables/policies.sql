ALTER TABLE events SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'source, type',
    timescaledb.compress_orderby = 'time DESC, id, name'
);
SELECT add_compression_policy('events', INTERVAL '7 days');

ALTER TABLE samples SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'source, type, metric_id',
    timescaledb.compress_orderby = 'time DESC, event_name, instance_index'
);
SELECT add_compression_policy('samples', INTERVAL '7 days');

SELECT add_retention_policy('events', INTERVAL '12 months');
SELECT add_retention_policy('samples', INTERVAL '12 months');
