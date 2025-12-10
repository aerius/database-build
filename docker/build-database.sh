#!/usr/bin/env bash

set -e

# validations
: ${DBDATA_PATH?'DBDATA_PATH must be provided'}
: ${DBSOURCE_PATH?'DBSOURCE_PATH must be provided'}
: ${DATABASE_NAME?'DATABASE_NAME must be provided'}

# default values if not set
: ${DBCONFIG_PATH:=aerius-database-build-config/config}
: ${DBRUNSCRIPT:=default}
: ${DBSETTINGS_BASE_DIRECTORY:=.}
: ${DBSETTINGS_PATH:=settings.rb}
: ${DBDATA_CLEANUP:=true} # A reason not to clean it up would be to cache the files using buildkit

# If the source code isn't made available by the extending Dockerfile we need to use git to check it out
USE_GIT=! [[ -d "${DBSOURCE_PATH}" ]]

[[ ${USE_GIT} ]] && echo 'Source code present in GIT..'
! [[ ${USE_GIT} ]] && echo 'Source code present locally..'

# Do git specific validations and fix paths if needed
if [[ ${USE_GIT} ]]; then
  : ${GIT_USERNAME?'GIT_USERNAME must be provided'}
  : ${GIT_TOKEN?'GIT_TOKEN must be provided'}
  : ${GIT_HOSTNAME?'GIT_HOSTNAME must be provided'}
  : ${GIT_ORG?'GIT_ORG must be provided'}
  : ${GIT_REPOSITORY?'GIT_REPOSITORY must be provided'}
  # Default to githash if there is no version explicitly set
  : ${DATABASE_VERSION:=#}

  DBSOURCE_PATH="${GIT_REPOSITORY}/${DBSOURCE_PATH}"
  DBCONFIG_PATH="${GIT_REPOSITORY}/${DBCONFIG_PATH}"
else
  # We require a version outside of git
   : ${DATABASE_VERSION?'DATABASE_VERSION must be set if source code is present locally..'}
fi

# add git dependencies if needed
[[ ${USE_GIT} ]] && apk --no-cache add --virtual .git-deps git openssh

# Make our own PGDATA.
# We are unfortunately doing this because we want the data to persist but the default PGDATA directory is marked as a volume, which cannot be undone.
mkdir -p "${PGDATA}" && chown -R postgres:postgres "${PGDATA}" && chmod 777 "${PGDATA}"

# fetch repo if needed
[[ ${USE_GIT} ]] && git --version
[[ ${USE_GIT} ]] && git clone "https://${GIT_USERNAME}:${GIT_TOKEN}@${GIT_HOSTNAME}/${GIT_ORG}/${GIT_REPOSITORY}.git"

# create db-data folder for the repo
mkdir -p "${DBDATA_PATH}"

# configure repo with the readonly SFTP password given if set
[[ -n "${SFTP_READONLY_PASSWORD}" ]] && echo "\$sftp_data_readonly_password = '${SFTP_READONLY_PASSWORD}'" >> "${DBCONFIG_PATH}/AeriusSettings.User.rb"

# configure repo with the HTTPS credentials given if set
[[ -n "${HTTPS_DATA_USERNAME}" ]] && echo "\$https_data_username = '${HTTPS_DATA_USERNAME}'" >> "${DBCONFIG_PATH}/AeriusSettings.User.rb"
[[ -n "${HTTPS_DATA_PASSWORD}" ]] && echo "\$https_data_password = '${HTTPS_DATA_PASSWORD}'" >> "${DBCONFIG_PATH}/AeriusSettings.User.rb"

# Set git support off in the build script
! [[ ${USE_GIT} ]] && echo "\$vcs = :none" >> "${DBCONFIG_PATH}/AeriusSettings.User.rb"

# sync db-data files we need
echo 'Syncing database data files..'
cd "${DBSOURCE_PATH}/"
ruby /aerius-database-build/bin/SyncDBData.rb "${DBSETTINGS_BASE_DIRECTORY}/${DBSETTINGS_PATH}" --to-local

# initialize database
# (this is a wrapper provided by the postgres image, which will initialize the db if it isn't already and is executed when starting the image for the first time.
# Run 'postgres' which will trigger the initialization and start the database, so we can start building the database.)
/usr/local/bin/docker-entrypoint.sh postgres --wal_level=minimal --fsync=off --full_page_writes=off --synchronous_commit=off --work_mem=32MB --max_wal_size=4GB --checkpoint_timeout=60min --maintenance_work_mem=2GB --autovacuum=off --max_wal_senders=0 &

# The database starts twice. First to set it up and a second time to simply start cleanly.
# Wait for it to stop once. (Detect socket file being removed)
echo 'Waiting for PostgreSQL to stop..'
inotifywait -e DELETE --include .s.PGSQL.5432 /var/run/postgresql/

# Wait for the DB to finish starting up (the second time)
echo 'Waiting for PostgreSQL to start up again..'
until pg_isready -q -d "${DATABASE_NAME}" -U "${POSTGRES_USER}" -h "$(hostname -i)"; do
  sleep 0.5s
done
echo 'PostgreSQL is up again'

# execute database build
ruby /aerius-database-build/bin/Build.rb "${DBRUNSCRIPT}" "${DBSETTINGS_BASE_DIRECTORY}/${DBSETTINGS_PATH}" -v "${DATABASE_VERSION}" -n "${DATABASE_NAME}"

# make the image smaller by doing a VACUUM FULL ANALYZE
psql -U "${POSTGRES_USER}" -d "${DATABASE_NAME}" -c 'VACUUM FULL ANALYZE'

# stop PostgreSQL database cleanly by sending a kill signal
kill %1

# Wait for the PostgreSQL process to end
wait %1

# Reset the WAL to reduce image size even more
if [[ "$(id -u)" = '0' ]]; then
  gosu postgres pg_resetwal --pgdata "${PGDATA}"
else
  pg_resetwal --pgdata "${PGDATA}"
fi

# image cleanup (removing unneeded db-data, git directory and git dependencies)
if [[ "${DBDATA_CLEANUP}" == 'true' ]]; then
  rm -rf "${DBDATA_PATH}"
fi
[[ ${USE_GIT} ]] && rm -rf "${GIT_REPOSITORY}"
[[ ${USE_GIT} ]] && apk del .git-deps

# Exit with 0 if this stage is reached, otherwise the return code from
#  the last if statement might be used, which might let Docker think the build failed
exit 0
