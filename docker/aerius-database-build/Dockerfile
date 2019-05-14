FROM aerius-database:latest

# Points to our own PGDATA. We are unfortunately doing this because we want the data to persist but the default PGDATA directory is marked as a volume, which cannot be undone.
ENV PGDATA /postgresdata

RUN apk update && apk upgrade \
    # add ruby dependencies
    && apk --no-cache add ruby ruby-irb ruby-rake ruby-io-console ruby-bigdecimal ruby-json ruby-bundler \
    libstdc++ tzdata bash ca-certificates \

    # add git dependencies
    && apk --no-cache add --virtual .git-deps git openssh \

    # disable generating documentation for (ruby)gems
    && echo 'gem: --no-document' > /etc/gemrc \

    # install needed (ruby)gems
    && gem install net-ssh -v 4.2.0 \
    && gem install net-sftp \
    && gem install clbustos-rtf \
    && ruby --version \
    && gem list \

    # fetch repo
    && git --version \
    && git clone 'https://github.com/aerius/aerius-database-build.git' \

    # create necessary common folders (required by aerius-database-build - but not used by us yet)
    && mkdir -p aerius-database-common/src/data/sql \
    && mkdir -p aerius-database-common/src/main/sql \

    # image cleanup (removing unneeded '.git' directory in cloned repo directory)
    && rm -rf aerius-database-build/.git \
    && apk del .git-deps

# Copy build-database.sh to the image - Dockerfiles that extend on this image
#  can use it to build a database easily. See script for the requirements.
COPY build-database.sh /
