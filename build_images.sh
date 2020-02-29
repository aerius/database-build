#!/bin/bash
set -Eeuo pipefail

# Loop through all
while read DIRECTORY; do
  VERSION=$(basename "${DIRECTORY}")
  echo 'Building: '"${VERSION}"
  docker build -t stikstofje/aerius-database-build:"${VERSION}" -f "${DIRECTORY}/Dockerfile" .
done < <(find docker/ -maxdepth 1 -type d -name '*-*.*')
