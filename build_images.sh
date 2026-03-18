#!/bin/bash
set -Eeuo pipefail

# Change current directory to directory of script so it can be called from everywhere
SCRIPT_PATH=$(readlink -f "${0}")
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
cd "${SCRIPT_DIR}"

: "${DOCKER_BUILD_PLATFORMS:=}"

# If DOCKER_REGISTRY_URL is supplied we should prepend it to the image name
if [[ -z "${DOCKER_REGISTRY_URL:-}" ]]; then
  IMAGE_NAME='aerius-database-build'
else
  IMAGE_NAME="${DOCKER_REGISTRY_URL}/database-build"
fi

BUILDX_BUILD_EXTRA_ARGS=()
[[ -n "${DOCKER_BUILD_PLATFORMS}" ]] && BUILDX_BUILD_EXTRA_ARGS+=("--platform=${DOCKER_BUILD_PLATFORMS}")
[[ -z "${DOCKER_BUILD_PLATFORMS}" ]] && BUILDX_BUILD_EXTRA_ARGS+=("--load")

# Loop through all generated Docker directories to build then
while read DIRECTORY; do
  IMAGE_TAG=$(basename "${DIRECTORY}")
  echo '# Building: '"${IMAGE_TAG}"
  docker buildx build ${BUILDX_BUILD_EXTRA_ARGS[@]} -t "${IMAGE_NAME}":"${IMAGE_TAG}" -f "${DIRECTORY}/Dockerfile" .
done < <(find docker/ -maxdepth 1 -type d -name '*-*-*')

# Loop through all generated Docker directories to push them if requested
# We do this separately so if any image fails to build, we won't have pushed anything
if [[ "${PUSH_IMAGES:-}" == 'true' ]]; then
  while read DIRECTORY; do
    IMAGE_TAG=$(basename "${DIRECTORY}")
    echo '# Pushing: '"${IMAGE_TAG}"
    docker buildx build --push ${BUILDX_BUILD_EXTRA_ARGS[@]} -t "${IMAGE_NAME}":"${IMAGE_TAG}" -f "${DIRECTORY}/Dockerfile" .
  done < <(find docker/ -maxdepth 1 -type d -name '*-*-*')
fi
