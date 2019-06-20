FROM mdillon/postgis:10-alpine

ENV POSTGRES_DB='postgres' \
    POSTGRES_USER='aerius' \
    POSTGRES_PASSWORD='aerius'

# Remove chown commands as they slow startup way down, our permissions are okay from the start
RUN sed -i -e 's/^\(.*chown\)/#\1/' /usr/local/bin/docker-entrypoint.sh

