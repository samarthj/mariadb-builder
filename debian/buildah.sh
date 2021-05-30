#!/usr/bin/env bash

#Setting up some colors for helping read the demo output
RD=$(tput setaf 1)
GR=$(tput setaf 2)
YL=$(tput setaf 3)
BL=$(tput setaf 4)
PR=$(tput setaf 5)
CY=$(tput setaf 6)
RS=$(tput sgr0)

set -o errexit

trap "buildah rm -a && buildah rmi --prune || true" EXIT

add_atomic() {
  ctr="$1"
  source="$2"
  dest="$3"
  mnt=$(buildah unshare buildah mount "$ctr")
  cp -au "$source" "$mnt/$dest"
  buildah umount "$ctr"
}

uproot() {
  echo "${YL}Uprooting..."
  ctr="$1"
  source="$2"
  dest="$3"
  newctr=$(buildah from scratch)
  mnt=$(buildah unshare buildah mount "$ctr")
  newmnt=$(buildah unshare buildah mount "$newctr")
  buildah unshare echo "$mnt / $newmnt"
  buildah unshare ls -la "$mnt"
  buildah unshare ls -la "$newmnt"
  buildah unshare cp -a "$mnt$source" "$newmnt$dest"
  buildah unshare buildah umount "$ctr"
  buildah unshare buildah umount "$newctr"
  echo "Done Uprooting...${RS}"
  return "$newctr"
}

MARIADB_VER="10.6"
OS_VER="sid-slim"
RUN_USER="mysql"
CORES=20
TZ="America/Los_Angeles"
CONTEXT="/home/sam/ws/servers/mariadb-builder"

echo -e "${GR}Building an image called common"
common_image=$(buildah images --format '{{.Name}}' | grep 'debian-base' || true)
if [ -z "$common_image" ]; then
  common=$(buildah from docker.io/debian:"${OS_VER}")
  buildah config --workingdir "/tmp" "$common"
  buildah config --env DEBIAN_FRONTEND=noninteractive "$common"
  mirror_url="http://sfo1.mirrors.digitalocean.com/debian/"
  buildah run "$common" sh -c "echo \"deb [arch=amd64] $mirror_url sid main\" > /etc/apt/sources.list"
  buildah run "$common" apt-get update
  buildah run "$common" apt-get install -y --no-install-recommends gnupg git ca-certificates
  buildah config --env PATH="/bin:/usr/bin:/usr/local/mysql/bin:$PATH" "$common"
  echo -e "Build complete${RS}"
  echo -e "${YL}Storing base"
  common_image="containers-storage:debian-base"
  buildah commit --omit-timestamp "$common" "$common_image"
  echo -e "Stored base in the container store${RS}"
else
  echo -e "Already in the container store, skipping...${RS}"
fi

echo -e "${RD}Building an image called source"
source_image=$(buildah images --format '{{.Name}}' | grep 'mariadb-source' || true)
if [ -z "$source_image" ]; then
  source=$(buildah from "$common_image")
  buildah run "$source" git clone \
    --depth=1 \
    --recurse-submodules \
    --shallow-submodules \
    -j "${CORES}" \
    --branch "bb-${MARIADB_VER}-release" \
    "https://github.com/MariaDB/server.git"
  source=$(uproot "$source" "/tmp/server" "/server")
  echo -e "Build complete${RS}"
  echo -e "${YL}Storing source"
  source_image="containers-storage:mariadb-source"
  buildah commit --omit-timestamp "$source" "$source_image" &
  echo -e "Stored source in the container store${RS}"
else
  source=source_image
  echo -e "Already in the container store, skipping...${RS}"
fi

echo -e "${BL}Building an image called builder"
build_base_image=$(buildah images --format '{{.Name}}' | grep 'mariadb-build-base' || true)
if [ -z "$build_base_image" ]; then
  build_base=$(buildah from "$common_image")
  buildah run "$build_base" apt-key adv --recv-keys \
    --keyserver "hkp://keyserver.ubuntu.com:80" \
    "0xF1656F24C74CD1D8"
  buildah run "$build_base" mkdir -p "/etc/apt/sources.list.d"
  repo_url="http://sfo1.mirrors.digitalocean.com/mariadb/repo/${MARIADB_VER}/\$(sed -n -e 's/^ID=//p' /etc/os-release)"
  buildah run "$build_base" sh -c "echo \"deb [arch=amd64] $repo_url sid main\" > /etc/apt/sources.list.d/MariaDB.list"
  buildah run "$build_base" sh -c "echo \"deb-src [arch=amd64] $repo_url sid main\" >> /etc/apt/sources.list.d/MariaDB.list"
  buildah run "$build_base" apt-get update
  buildah run "$build_base" apt-get build-dep -y mariadb-server
  buildah run "$build_base" apt-get install -y --no-install-recommends \
    ccache ninja-build valgrind \
    libreadline-dev pkg-config \
    libgoogle-perftools-dev libjemalloc-dev \
    libevent-dev
  echo -e "Install complete${RS}"
  echo -e "${YL}Storing build_base"
  build_base_image="containers-storage:mariadb-build-base"
  buildah commit --omit-timestamp "$build_base" "$build_base_image"
  echo -e "Stored build_base in the container store...${RS}"
else
  echo -e "Already in the container store, skipping...${RS}"
fi

builder=${build_base:-$(buildah from "$build_base_image")}
echo -e "${CY}Building mariadb..."
buildah run "$builder" mkdir /tmp/build
add_atomic "$builder" "${CONTEXT}/CMakeExtra.txt" "/tmp/build/"
sourcemnt=$(buildah mount "$source" "$builder" | cut -f2)
ls -la "$sourcemnt"
echo -e "Source mariadb is here - $sourcemnt..."
buildah run "$builder" cmake -S "$sourcemnt/server" -B /tmp/build \
  -DCMAKE_USER_MAKE_RULES_OVERRIDE='/tmp/build/CMakeExtra.txt' \
  -DCMAKE_EXE_LINKER_FLAGS='-ltcmalloc' \
  -DWITH_GPROF=ON \
  -DWITH_NUMA=ON \
  -DWITH_PMEM=ON \
  -DWITH_SAFEMALLOC=OFF \
  -DWITH_TSAN=ON \
  -DWITH_UBSAN=ON \
  -DCONC_WITH_UNITTEST=OFF \
  -DWITH_UNIT_TESTS=OFF \
  -DWITH_EMBEDDED_SERVER=OFF \
  -DWITH_UNIT_TESTS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DPLUGIN_ARCHIVE=NO \
  -DPLUGIN_AUTH_ED25519=NO \
  -DPLUGIN_AUTH_GSSAPI=NO \
  -DPLUGIN_BLACKHOLE=NO \
  -DPLUGIN_CRACKLIB_PASSWORD_CHECK=NO \
  -DPLUGIN_DAEMON_EXAMPLE=NO \
  -DPLUGIN_DIALOG_EXAMPLES=NO \
  -DPLUGIN_EXAMPLE=NO \
  -DPLUGIN_EXAMPLE_KEY_MANAGEMENT=NO \
  -DPLUGIN_FEEDBACK=NO \
  -DPLUGIN_FTEXAMPLE=NO \
  -DPLUGIN_MROONGA=NO \
  -DPLUGIN_OQGRAPH=NO \
  -DPLUGIN_SEQUENCE=NO \
  -DPLUGIN_SPIDER=NO \
  -DPLUGIN_SPHINX=NO \
  -DCONNECT_WITH_MONGO=OFF \
  -DWITH_INNODB_LZ4=ON \
  -DWITH_ROCKSDB_JEMALLOC=ON \
  -DWITH_ROCKSDB_LZ4=ON \
  -DWITH_ROCKSDB_ZSTD=ON \
  -DWITH_ROCKSDB_snappy=OFF \
  -DPLUGIN_ROCKSDB=YES \
  -DMYSQL_MAINTAINER_MODE=NO \
  -DWITH_READLINE=ON \
  -DWITH_URING=ON \
  -DWITH_VALGRIND=ON \
  -G Ninja \
  -LAH
echo -e "Make complete${RS}"
echo -e "${PR}Finalizing build"
buildah run "$builder" cmake --build /tmp/build/ --parallel "${CORES}" -t package
buildah run "$builder" tar \
  -zpxf "/tmp/build/mariadb-${MARIADB_VER}*.tar.gz" \
  -C /tmp \
  --exclude "mysql-test"
buildah run "$builder" rm -rf \
  /tmp/source \
  /tmp/build
echo -e "Build complete${RS}"

echo -e "${RD}Building an image called runtime"
runtime=$(buildah from docker.io/debian:"${OS_VER}")
buildah run "$runtime" apt-get install -y --no-install-recommends \
  gnutls-bin tzdata logrotate expect \
  libreadline8 libxml2 unixodbc \
  zlib1g liblz4-1 libzstd1 \
  libgoogle-perftools4 libjemalloc2 openssl \
  liburing1 libpmem1 libnuma1
buildah run "$runtime" groupadd "${RUN_USER}"
buildah run "$runtime" useradd -M -g "${RUN_USER}" "${RUN_USER}"
buildah run "$runtime" mkdir /usr/local/mysql
buildah copy "$runtime" --chown="${RUN_USER}:${RUN_USER}" --from=builder /tmp/mariadb-"${MARIADB_VER}"*-linux-x86_64 /usr/local/mysql
buildah run "$runtime" mkdir -p /etc/mysql/conf.d
buildah run "$runtime" mkdir -p /usr/local/mysql/data
buildah run "$runtime" ln -s /usr/local/mysql/support-files/systemd/* /lib/systemd/system/

add_atomic "$runtime" "${CONTEXT}/scripts" /tmp/scripts
add_atomic "$runtime" "${CONTEXT}/my.cnf" /etc/mysql/my.cnf
add_atomic "$runtime" "${CONTEXT}/logrotate" /etc/logrotate.d/mariadb_slow_log

buildah config --env PATH="/bin:/usr/bin:/usr/local/mysql/bin:$PATH" "$runtime"
buildah config --env TZ="$TZ" "$runtime"

buildah config --entrypoint '[ "/tmp/scripts/init.sh" ]' --cmd '' "$runtime"

buildah config --volume '[ "/usr/local/mysql/data" ]' "$runtime"
buildah config --volume '[ "/etc/mysql/conf.d" ]' "$runtime"

buildah config --port 3306 "$runtime"
echo -e "Build complete${RS}"

echo -e "${YL}Storing runtime${RS}"
buildah commit --omit-timestamp "$runtime" "containers-storage:mariadb:${MARIADB_VER}"
echo -e "${YL}Cleaning up${RS}"
buildah rm "$common" "$source" "$builder" "$builder" "$runtime"
echo -e "${YL}Done${RS}"
