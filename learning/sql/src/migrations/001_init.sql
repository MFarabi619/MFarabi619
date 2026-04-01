-- Set Null char output to differentiate it from empty string
-- \pset null '☘️'
-- \pset null 'NULL'
\pset null '[NULL]'
 -- set border style
\pset border 2
--Outline table borders and separators using Unicode characters
\pset linestyle unicode
-- Always show query time
\timing 1
--Automatically format expanded display for wide columns
\x
-- output any SQL run by psql slash commands
\set ECHO_HIDDEN on
-- Have psql echo back queries
\set ECHO queries
-- \set COMP_KEYWORD_CASE upper
-- Colorize output
\pset pager on
-- Customize prompt
-- http://i-dba.blogspot.se/2014/02/colorizing-psql-prompt-guide.html
-- %m -> short hostname; %M -> full hostname
\set PROMPT1 '\n%[%033[1;31m%]➤ %[%033[2;37m%]%`\! date "+%F %I:%M %p %Z"`%[%033[0m%] %[%033[1;36m%]%n%[%033[34m%]@%[%033[1;36m%]%M:%>%[%033[1;33m%]/%/ %[%033[1;31m%]%x %[%033[K%]%[%033[0m%]\n%[%033[1;33m%]%R%#%[%033[0m%] '
\set PROMPT2 '%[%033[1;33m%]%R%#%[%033[0m%] '
-- Consider: http://petereisentraut.blogspot.c
-- \set ON_ERROR_STOP off
-- \set ON_ERROR_ROLLBACK interactive
\set HISTFILE ~/.psql_history-:DBNAME
-- Get rid of duplicates in history
\set HISTCONTROL ignoredups
-- Allow pasting of values
-- \set paste off

CREATE EXTENSION IF NOT EXISTS timescaledb;
