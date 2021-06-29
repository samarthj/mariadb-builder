#!/bin/bash

heading "Building an image called $common_image_name"
common_image=$(buildah images \
  --format '{{.Name}}:{{.Tag}}' \
  --filter "reference=$common_image_name" ||
  true)
if [ -z "$common_image" ]; then
  common=$(buildah from --name="$common_image_name" docker.io/"${OS_NAME:-ubuntu}":"${OS_VER}")
  buildah config --workingdir "/tmp" "$common"
  buildah config --add-history --env FRONTEND=noninteractive "$common"
  buildah config --add-history --env DEBIAN_FRONTEND='noninteractive' "$common"
  buildah config --add-history --env PATH="/bin:/usr/bin:\$PATH" "$common"
  buildah config --add-history --env TZ="${TZ}" "$common"
  save_image "$common" "$common_image_name"
  ending "Build complete"
else
  ending "Already in the container store, skipping..."
fi
