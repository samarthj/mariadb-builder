#!/bin/bash

builder=$(get_container_id "$build_base_image_name")

[ -n "$builder" ] && package=$(buildah run "$builder" find /tmp/build/ -maxdepth 1 -name "*.tar.gz" || true)

if [ -z "$package" ]; then
  heading "Setting up builder..."

  if [ -z "$builder" ]; then
    builder=$(buildah from --name "$build_base_image_name" "$build_base_image_name")
  fi

  buildah run "$builder" apt update
  buildah run "$builder" apt install -y libmongoc-dev libbson-dev
  buildah config --add-history --env "CORES=${CORES}" "$builder"

  source_container=$(buildah containers --format "{{.ContainerID}},{{.ContainerName}}" --filter "name=$source_image_name" | cut -f1 -d,)
  echo "$source_container"

  heading "Copying make configuration for mariadb..."
  add_atomic "$builder" "${CONTEXT}/CMakeExtra.txt" "/tmp"
  heading "Making mariadb..."

  buildah unshare --mount "U_SOURCE=$source_container" bash <<EOU
buildah run -v "\${U_SOURCE}/:/tmp/server" -v "${CONTEXT}:/tmp/up" "$builder" bash <"${CONTEXT}/ubuntu/make.sh"
EOU

  buildah rm "$source_container"
fi

heading "Setting up package..."

package=$(buildah run "$builder" find /tmp/build/ -maxdepth 1 -name "*.tar.gz")
basename=${package##*/}
basename_only=${basename%%.tar.gz}
buildah run "$builder" tar -zpxf "$package" -C /tmp --exclude "mysql-test"

uproot_save "$builder" "/tmp/$basename_only" "$mariadb_built_image_name"
mariadb_built_container="${RETURN_UPROOT_SAVE}"
buildah rename "$mariadb_built_container" "$mariadb_built_image_name"
