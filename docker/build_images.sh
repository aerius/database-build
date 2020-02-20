#!/bin/bash
set -Eeuo pipefail

# Loop through all
while read DIRECTORY; do
  VERSION=$(basename "${DIRECTORY}")
  echo 'Building: '"${VERSION}"
  docker build -t stikstofje/aerius-database-build:"${VERSION}" "${VERSION}/"
done < <(find . -maxdepth 1 -type d -name '*-*.*')
