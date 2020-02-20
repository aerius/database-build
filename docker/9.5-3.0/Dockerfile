FROM postgis/postgis:9.5-3.0-alpine

ENV POSTGRES_DB='postgres' \
    POSTGRES_USER='aerius' \
    POSTGRES_PASSWORD='aerius' \
    # Points to our own PGDATA. We are unfortunately doing this because we want the data to persist but the default PGDATA directory is marked as a volume, which cannot be undone.
    PGDATA='/postgresdata'

RUN apk update && apk upgrade \
    # add ruby dependencies + curl + inotify-tools
    && apk --no-cache add ruby ruby-irb ruby-rake ruby-io-console ruby-bigdecimal ruby-json ruby-bundler \
    libstdc++ tzdata bash ca-certificates curl inotify-tools \
    \
    # disable generating documentation for (ruby)gems
    && echo 'gem: --no-document' > /etc/gemrc \
    \
    # install needed (ruby)gems
    && gem install net-ssh -v 4.2.0 \
    && gem install net-sftp \
    && gem install clbustos-rtf \
    && ruby --version \
    && gem list \
    \
    # fetch repo
    && curl -L -o aerius-database-build.tar.gz 'https://api.github.com/repos/aerius/aerius-database-build/tarball/master' \
    && tar xfz aerius-database-build.tar.gz \
    && rm aerius-database-build.tar.gz \
    && mv aerius-aerius-database-build-* aerius-database-build \
    \
    # create necessary common folders (required by aerius-database-build - but not used by us yet)
    && mkdir -p aerius-database-common/src/data/sql \
    && mkdir -p aerius-database-common/src/main/sql

# Copy build-database.sh to the image - Dockerfiles that extend on this image
#  can use it to build a database easily. See script for the requirements.
COPY build-database.sh /
