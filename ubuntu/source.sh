#!/bin/bash

image_name="${BUILD_RES_PREFIX}mariadb-source:${OS_VER}"

heading "Building an image called $image_name"
source_image=$(buildah images \
  --format '{{.Name}}:{{.Tag}}' \
  --filter "reference=$image_name" ||
  true)
if [ -z "$source_image" ]; then
  # shellcheck disable=SC2154
  source=${common:-$(buildah from "$common_image")}
  echo -e "Working container - $source"
  buildah run "$source" apt-get update
  buildah run "$source" apt-get install -y --no-install-recommends gnupg git ca-certificates
  buildah run "$source" git clone \
    --depth=1 \
    --recurse-submodules \
    --shallow-submodules \
    -j "${CORES}" \
    --branch "bb-${MARIADB_VER}-release" \
    "https://github.com/MariaDB/server.git"
  uproot_save "$source" "/tmp/server" "$image_name"
  source_image="$image_name"
  echo -e "Build complete ($source -> $RETURN_UPROOT_SAVE) ..."
  source=${RETURN_UPROOT_SAVE}
else
  source=$(buildah from "$source_image")
  ending "Already in the container store ($source), skipping..."
fi
