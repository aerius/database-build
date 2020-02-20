#!/bin/bash
set -Eeuo pipefail

declare POSTGRES_VERSIONS=(9.5 9.6 10 11 12)
declare POSTGIS_VERSIONS=(2.5 3.0)

for POSTGRES_VERSION in "${POSTGRES_VERSIONS[@]}"; do
  for POSTGIS_VERSION in "${POSTGIS_VERSIONS[@]}"; do
    echo "PostgreSQL: ${POSTGRES_VERSION} - PostGIS: ${POSTGIS_VERSION}"
    VERSION="${POSTGRES_VERSION}-${POSTGIS_VERSION}"

    # Create directory if it doesn't exist yet
    if [[ ! -d "${VERSION}" ]]; then
      mkdir "${VERSION}"
    fi

    # Copy over files and process templates
    cp build-database.sh "${VERSION}/"
    sed -e 's/%%POSTGRESQL_VERSION%%/'"${POSTGRES_VERSION}"'/g;' \
        -e 's/%%POSTGIS_VERSION%%/'"${POSTGIS_VERSION}"'/g;' \
        Dockerfile.template > "${VERSION}/Dockerfile"
  done
done
