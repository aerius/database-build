FROM aerius-database:latest

RUN apk update && apk upgrade \
    # add ruby dependencies
    && apk --no-cache add ruby ruby-irb ruby-rake ruby-io-console ruby-bigdecimal ruby-json ruby-bundler \
    libstdc++ tzdata bash ca-certificates \

    # add git dependencies
    && apk --no-cache add --virtual .git-deps git openssh \

    # disable generating documentation for (ruby)gems
    && echo 'gem: --no-document' > /etc/gemrc \

    # install needed (ruby)gems
    && gem install net-ssh \
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

    # image cleanup (removing unneeded '.git' directory in cloned repo directory and git dependencies)
    && rm -rf aerius-database-build/.git \
    && apk del .git-deps

CMD ["/bin/bash"]

