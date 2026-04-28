CREATE TABLE events(
  id UUID DEFAULT uuid_generate_v7(),
  name TEXT NOT NULL,
  source TEXT NOT NULL,
  type TEXT NOT NULL,
  specversion TEXT NOT NULL,
  datacontenttype TEXT NOT NULL,
  time TIMESTAMPTZ NOT NULL,
  data jsonb NOT NULL,
  PRIMARY KEY (time, id)
);

SELECT create_hypertable('events', 'time', if_not_exists => TRUE);

CREATE UNIQUE INDEX events_time_name_idx ON events (time, name);
CREATE INDEX events_source_type_time_idx ON events (source, type, time DESC);
