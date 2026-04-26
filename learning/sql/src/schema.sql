\getenv devenv_root DEVENV_ROOT
\if :{?devenv_root}
  \cd :devenv_root/learning/sql/src
\else
  \echo 'DEVENV_ROOT is not set'
  \quit 1
\endif

SET TIME ZONE 'UTC';

\ir drop_schema.sql

CREATE EXTENSION IF NOT EXISTS ip4r;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;
CREATE EXTENSION IF NOT EXISTS byteamagic;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS system_stats;
CREATE EXTENSION IF NOT EXISTS plpgsql_check;
CREATE EXTENSION IF NOT EXISTS http;

\ir functions/generate_uuid_v7.sql

\ir tables/assets.sql
\ir tables/organizations.sql
\ir tables/stacks.sql
\ir tables/resources.sql
\ir tables/ipv4_addresses.sql
\ir tables/metrics.sql

\ir hypertables/events.sql
\ir hypertables/samples.sql

\ir seeds/metrics.sql

\ir functions/extract_samples_from_event.sql
\ir triggers/events_extract_samples.sql

\ir functions/poll_cloudevents.sql
\ir functions/poll_sensor.sql
\ir functions/poll_sensor_loop.sql

\ir cron/poll.sql
