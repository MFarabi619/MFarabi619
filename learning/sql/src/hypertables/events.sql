CREATE TABLE events(
  id UUID DEFAULT generate_uuid_v7(),
  name TEXT NOT NULL,
  source TEXT NOT NULL,
  type TEXT NOT NULL,
  specversion FLOAT NOT NULL,
  datacontenttype TEXT NOT NULL,
  time TIMESTAMPTZ NOT NULL,
  data jsonb NOT NULL,
  PRIMARY KEY (time, id)
);

SELECT create_hypertable('events', 'time', if_not_exists => TRUE);
