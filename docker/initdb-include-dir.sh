#!/usr/bin/env bash

set -e

echo "include_dir = '${PGCONF_INCLUDE_DIR}'" >> "${PGDATA}/postgresql.conf"

echo 'Custom include directory added: '"${PGCONF_INCLUDE_DIR}"
