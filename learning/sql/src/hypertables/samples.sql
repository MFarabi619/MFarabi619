CREATE TABLE samples (
    time TIMESTAMPTZ NOT NULL,
    event_name TEXT NOT NULL,
    source TEXT NOT NULL,
    type TEXT NOT NULL,
    metric_id UUID NOT NULL REFERENCES metrics(id),
    instance_index INT NOT NULL DEFAULT 0,
    value DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (time, event_name, metric_id, instance_index)
);

SELECT create_hypertable('samples', 'time', if_not_exists => TRUE);

CREATE INDEX samples_source_type_metric_time_idx
    ON samples (source, type, metric_id, time DESC);
