\getenv devenv_root DEVENV_ROOT
\if :{?devenv_root}
  \cd :devenv_root/learning/sql/src
\else
  \echo 'DEVENV_ROOT is not set'
  \quit 1
\endif


\x off
\timing 1
\pset border 2
\pset pager off
\set ECHO queries
\set ECHO_HIDDEN on
\pset null '[NULL]'
\pset linestyle unicode
\set PROMPT2 '%[%033[1;33m%]%R%#%[%033[0m%] '
\set PROMPT1 '\n%[%033[1;31m%]➤ %[%033[2;37m%]%`\! date "+%F %I:%M %p %Z"`%[%033[0m%] %[%033[1;36m%]%n%[%033[34m%]@%[%033[1;36m%]%M:%>%[%033[1;33m%]/%/ %[%033[1;31m%]%x %[%033[K%]%[%033[0m%]\n%[%033[1;33m%]%R%#%[%033[0m%] '
