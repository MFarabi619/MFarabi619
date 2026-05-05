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
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;
CREATE EXTENSION IF NOT EXISTS byteamagic;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS system_stats;
CREATE EXTENSION IF NOT EXISTS plpgsql_check;
CREATE EXTENSION IF NOT EXISTS pgnats;

\ir functions/set_modified_at.sql

\ir tables/assets.sql
\ir tables/organizations.sql
\ir tables/stacks.sql
\ir tables/resources.sql
\ir tables/ipv4_addresses.sql
\ir tables/metrics.sql

\ir triggers/set_modified_at.sql

\ir hypertables/events.sql
\ir hypertables/samples.sql

\ir seeds/metrics.sql

\ir functions/extract_samples_from_event.sql
\ir triggers/events_extract_samples.sql

\ir hypertables/policies.sql

\ir functions/handle_sensor_event.sql

\ir subscriptions/nats.sql
