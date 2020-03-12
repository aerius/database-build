#!/usr/bin/env bash

set -em

# Source entrypoint script which contains some useful functions - no need to reinvent the wheel
source /usr/local/bin/docker-entrypoint.sh

# start DB process in background using the imported functions
_main "${@}" &

# If POST_STARTUP_SQL/DATABASE_NAME env is set, we should use it to patch the DB
if [[ -n "${POST_STARTUP_SQL}" ]] && [[ -n "${DATABASE_NAME}" ]]; then
  echo 'Post startup SQL found..'
  echo 'Waiting for PostgreSQL to start up..'
  while [[ ! -S /var/run/postgresql/.s.PGSQL.5432 ]]; do
    sleep 0.1s
  done
  echo 'PostgreSQL is up!'

  # Execute patch using the imported functions
  echo 'Executing post startup SQL'
  docker_process_sql --dbname="${DATABASE_NAME}" <<< "${POST_STARTUP_SQL}"
fi

# Bring DB process to foreground
fg
