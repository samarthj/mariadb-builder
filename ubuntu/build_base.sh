#!/bin/bash

build_base_name_only="${BUILD_RES_PREFIX}mariadb-base-build"
image_name="${build_base_name_only}:${OS_VER}"

heading "Building an image called $image_name"
build_base_image=$(buildah images \
  --format '{{.Name}}:{{.Tag}}' \
  --filter "reference=$image_name" ||
  true)
if [ -z "$build_base_image" ]; then
  build_base=${common:-$(buildah from "$common_image")}
  buildah run "$build_base" apt-get update
  buildah run "$build_base" apt-get install -y --no-install-recommends \
    gnupg curl ca-certificates
  buildah run "$build_base" mkdir -p "/usr/share/keyrings"
  repo_url="http://sfo1.mirrors.digitalocean.com/mariadb/repo/${MARIADB_VER}/${OS_NAME}"
  key_location="/usr/share/keyrings/mariadb-archive-keyring.gpg"
  buildah run "$build_base" sh -c "curl https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor > $key_location"
  buildah run "$build_base" mkdir -p "/etc/apt/sources.list.d"
  buildah run "$build_base" sh -c "echo \"deb [signed-by=$key_location] $repo_url ${OS_CODENAME} main\" > /etc/apt/sources.list.d/mariadb.list"
  buildah run "$build_base" sh -c "echo \"deb-src [signed-by=$key_location] $repo_url ${OS_CODENAME} main\" >> /etc/apt/sources.list.d/mariadb.list"
  heading "update"
  buildah run "$build_base" apt-get update
  heading "build-dep"
  buildah run "$build_base" apt-get build-dep -y mariadb-server
  heading "manual-dependencies"
  buildah run "$build_base" apt-get install -y --no-install-recommends \
    ccache ninja-build valgrind \
    git libreadline-dev pkg-config \
    libjemalloc-dev \
    libevent-dev \
    libmsgpack-dev libczmq-dev \
    curl ca-certificates \
    binutils-dev libpthreadpool-dev libpthread-stubs0-dev \
    libwrap0-dev libpcre2-posix2 \
    zlib1g-dev
  save_image "$build_base" "$image_name"
  ending "Install complete"
else
  ending "Already in the container store, skipping..."
fi
