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
  IMAGE_NAME="${DOCKER_REGISTRY_URL}/database-build"
fi

# Loop through all generated Docker directories
IMAGES_TO_PUSH=()
while read DIRECTORY; do
  IMAGE_TAG=$(basename "${DIRECTORY}")
  echo '# Building: '"${IMAGE_TAG}"
  docker build --pull -t "${IMAGE_NAME}":"${IMAGE_TAG}" -f "${DIRECTORY}/Dockerfile" .

  if [[ "${PUSH_IMAGES:-}" == 'true' ]]; then
    IMAGES_TO_PUSH+=("${IMAGE_NAME}":"${IMAGE_TAG}")
  fi
done < <(find docker/ -maxdepth 1 -type d -name '*-psql_*-pgis_*')

# If there are images to push, do so
for IMAGE_TO_PUSH in "${IMAGES_TO_PUSH[@]}"; do
  echo '# Pushing image: '"${IMAGE_TO_PUSH}"
  docker push "${IMAGE_TO_PUSH}"
done
