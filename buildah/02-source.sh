#!/bin/bash

source_image_name="${BUILD_RES_PREFIX}mariadb-source:${OS_VER}"

heading "Building an image called $source_image_name"
source_image=$(buildah images \
  --format '{{.Name}}:{{.Tag}}' \
  --filter "reference=$source_image_name" ||
  true)
source_container=$(buildah containers --format "{{.ContainerID}},{{.ContainerName}}" --filter "name=$source_image_name" | cut -f1 -d,)
if [ -z "$source_image" ] && [ -z "$source_container" ]; then
  # shellcheck disable=SC2154
  source=$(buildah from "$common_image_name")
  echo -e "Working container - $source"
  buildah run "$source" -- echo \$PATH
  buildah run "$source" -- sh -c "apt update"
  buildah run "$source" -- sh -c "apt install -y --no-install-recommends gnupg git ca-certificates"
  buildah run "$source" -- git clone \
    --depth=1 \
    --recurse-submodules \
    --shallow-submodules \
    -j "${CORES}" \
    --branch "bb-${MARIADB_VER}-release" \
    "https://github.com/MariaDB/server.git"
  uproot_save "$source" "/tmp/server" "$source_image_name"
  source_image="$source_image_name"
  echo -e "Build complete ($source -> $RETURN_UPROOT_SAVE) ..."
  source=${RETURN_UPROOT_SAVE}
  buildah rename "$source" "$source_image_name"
elif [ -n "$source_image" ] && [ -z "$source_container" ]; then
  source=$(buildah from "$source_image")
  buildah rename "$source" "$source_image_name"
  ending "Already in the container store ($source), skipping..."
fi
