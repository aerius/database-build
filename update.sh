#!/bin/bash
set -Eeuo pipefail

# Change current directory to directory of script so it can be called from everywhere
SCRIPT_PATH=$(readlink -f "${0}")
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
cd "${SCRIPT_DIR}"

# Key is the PostgreSQL version and values are the PostGIS versions images are available for that PostgreSQL version.
declare -A IMAGE_VERSIONS=(
  [17]="3.5"
  [15]="3.4"
)

# Read in current version of the script
BUILD_VERSION=$(<VERSION)

for POSTGRESQL_VERSION in "${!IMAGE_VERSIONS[@]}"; do
  for POSTGIS_VERSION in ${IMAGE_VERSIONS[${POSTGRESQL_VERSION}]}; do
    echo "# Processing - PostgreSQL: ${POSTGRESQL_VERSION} - PostGIS: ${POSTGIS_VERSION}"
    IMAGE_TAG="${BUILD_VERSION}-psql_${POSTGRESQL_VERSION}-pgis_${POSTGIS_VERSION}"

    # Create directory if it doesn't exist yet
    if [[ ! -d "${IMAGE_TAG}" ]]; then
      mkdir -p "docker/${IMAGE_TAG}"
    fi

    # Copy over files and process templates
    sed -e 's/%%POSTGRESQL_VERSION%%/'"${POSTGRESQL_VERSION}"'/g;' \
        -e 's/%%POSTGIS_VERSION%%/'"${POSTGIS_VERSION}"'/g;' \
        docker/Dockerfile.template > "docker/${IMAGE_TAG}/Dockerfile"
  done
done
