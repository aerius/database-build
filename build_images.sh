#!/bin/bash
set -Eeuo pipefail

# Change current directory to directory of script so it can be called from everywhere
SCRIPT_PATH=$(readlink -f "${0}")
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
cd "${SCRIPT_DIR}"

# If DOCKER_REGISTRY_URL is supplied we should prepend it to the image name
if [[ -z "${DOCKER_REGISTRY_URL:-}" ]]; then
  IMAGE_NAME='aerius-database-build'
else
  IMAGE_NAME="${DOCKER_REGISTRY_URL}/aerius-database-build"
fi

# Loop through all generated Docker directories
while read DIRECTORY; do
  IMAGE_TAG=$(basename "${DIRECTORY}")
  echo '# Building: '"${IMAGE_TAG}"
  docker build --pull -t "${IMAGE_NAME}":"${IMAGE_TAG}" -f "${DIRECTORY}/Dockerfile" .
done < <(find docker/ -maxdepth 1 -type d -name '*-*-*')
