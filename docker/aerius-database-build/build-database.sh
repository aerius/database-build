#!/bin/sh

set -e

# validations
: ${SFTP_READONLY_PASSWORD?'SFTP_READONLY_PASSWORD must be provided'}
: ${GIT_USERNAME?'GIT_USERNAME must be provided'}
: ${GIT_TOKEN?'GIT_TOKEN must be provided'}
: ${GIT_HOSTNAME?'GIT_HOSTNAME must be provided'}
: ${GIT_ORG?'GIT_ORG must be provided'}
: ${GIT_REPOSITORY?'GIT_REPOSITORY must be provided'}
: ${DBDATA_PATH?'DBDATA_PATH must be provided'}
: ${DBSOURCE_PATH?'DBSOURCE_PATH must be provided'}
: ${DATABASE_NAME?'DATABASE_NAME must be provided'}

# default values if not set
: ${DBCONFIG_PATH:=aerius-database-build-config/config}

# add git dependencies
apk --no-cache add --virtual .git-deps git openssh

# Make our own PGDATA.
# We are unfortunately doing this because we want the data to persist but the default PGDATA directory is marked as a volume, which cannot be undone.
mkdir -p "${PGDATA}" && chown -R postgres:postgres "${PGDATA}" && chmod 777 "${PGDATA}"

# fetch repo
git --version
git clone "https://${GIT_USERNAME}:${GIT_TOKEN}@${GIT_HOSTNAME}/${GIT_ORG}/${GIT_REPOSITORY}.git"

# create db-data folder for the repo
mkdir -p "${DBDATA_PATH}"

# configure repo with the readonly SFTP password given as argument
echo "\$sftp_data_readonly_password = '${SFTP_READONLY_PASSWORD}'" > "${GIT_REPOSITORY}/${DBCONFIG_PATH}/AeriusSettings.User.rb"

# sync db-data files we need
cd "${GIT_REPOSITORY}/${DBSOURCE_PATH}/"
ruby ../../aerius-database-build/bin/SyncDBData.rb settings.rb --from-sftp --to-local

# initialize database
# (this is a wrapper provided by the postgres image, which will initialize the db if it isn't already and is executed when starting the image for the first time.
#  Run 'postgres --version' which will trigger the initialization, so we can start building the database.)
/docker-entrypoint.sh postgres --version

# start PostgreSQL database
su postgres -c 'pg_ctl start'

# execute database build
ruby ../../aerius-database-build/bin/Build.rb default settings.rb -v '#' -n "${DATABASE_NAME}"

# make the image smaller by doing a VACUUM FULL ANALYZE
su postgres -c "psql -U '${POSTGRES_USER}' -d '${DATABASE_NAME}' -c 'VACUUM FULL ANALYZE'"

# stop PostgreSQL database cleanly
su postgres -c 'pg_ctl stop'

# image cleanup (removing unneeded db-data, '.git' directory in cloned repo directory and git dependencies)
rm -rf /"${DBDATA_PATH}" "${GIT_REPOSITORY}"/.git
apk del .git-deps
