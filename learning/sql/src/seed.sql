\getenv devenv_root DEVENV_ROOT
\if :{?devenv_root}
  \cd :devenv_root/learning/sql/src
\else
  \echo 'DEVENV_ROOT is not set'
  \quit 1
\endif

SET TIME ZONE 'UTC';

\ir psqlrc.sql

\ir seeds/assets.sql

\ir seeds/organizations.sql

\ir seeds/stacks.sql

\ir seeds/resources.sql

\ir seeds/ipv4_addresses.sql

\ir seeds/metrics.sql

\ir seeds/events.sql

\ir seeds/samples.sql
