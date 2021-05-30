#!/bin/bash

base_name_only="${BUILD_RES_PREFIX}mariadb-base"
image_name="${base_name_only}:${OS_VER}"

heading "Building an image called $image_name"
common_image=$(buildah images \
  --format '{{.Name}}:{{.Tag}}' \
  --filter "reference=$image_name" ||
  true)
if [ -z "$common_image" ]; then
  common=$(buildah from docker.io/ubuntu:"${OS_VER}")
  buildah config --workingdir "/tmp" "$common"
  buildah config --add-history --env FRONTEND=noninteractive "$common"
  # buildah config --add-history --env PATH="/bin:/usr/bin:\$PATH" "$common"
  buildah config --add-history --env DEBIAN_FRONTEND='noninteractive' "$common"
  buildah config --add-history --env TZ="${TZ}" "$common"
  save_image "$common" "$image_name"
  ending "Build complete"
else
  ending "Already in the container store, skipping..."
fi
