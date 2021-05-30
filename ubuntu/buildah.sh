#!/bin/bash

echo "The script you are running has:"
echo " -> basename - $(basename "$0")"
echo " -> dirname - $(dirname "$0")"
echo " -> working directory - $(pwd)"

set -o errexit

# shellcheck disable=SC1091
source "$(dirname "$0")/util.sh"

trap_exec() {
  echo "Exit Code - $?"
  heading "Cleaning up containers..."
  buildah containers -a || true
  # buildah rm -a || true
  heading "Cleaning up images..."
  buildah images -a --filter "reference=${BUILD_RES_PREFIX}mariadb*" || true
  buildah rmi -p || true
  # buildah images -a --format '{{.Name}}:{{.Tag}}' |
  #   grep "${BUILD_RES_PREFIX}mariadb*" |
  #   xargs -I{} buildah rmi -f {} || true
}

trap trap_exec INT QUIT EXIT SIGINT SIGHUP SIGTERM

export MARIADB_VER=${MARIADB_VER:-"10.6"}
export OS_VER=${OS_VER:-"rolling"}
export RUN_USER=${RUN_USER:-"mysql"}
export CORES=${CORES:$(nproc)}
export TZ=${TZ:"America/Los_Angeles"}

export CONTEXT="/home/sam/ws/servers/mariadb-builder"

# shellcheck disable=SC1091
source "${CONTEXT}/ubuntu/base.sh"

# shellcheck disable=SC1091
source "${CONTEXT}/ubuntu/source.sh"

# shellcheck disable=SC1091
source "${CONTEXT}/ubuntu/build_base.sh"

image_name="${BUILD_RES_PREFIX}mariadb-complete:${OS_VER}"
working_container=$(buildah containers --format '{{.ContainerName}}' --filter name="${build_base_name_only}"-working-container)
working_container=${working_container:-$(buildah containers --format '{{.ContainerName}}' --filter name="${base_name_only}"-working-container)}
working_container=${working_container:-build_base}
builder=${working_container:-$(buildah from "$build_base_image")}
heading "Setting up builder..."

# buildah run "$builder" apt-get install -y llvm clang
# buildah run "$builder" update-alternatives --set c++ /usr/bin/clang++
# buildah run "$builder" update-alternatives --set cc /usr/bin/clang
# buildah config --add-history --env "CC=/usr/bin/clang" "$builder"
# buildah config --add-history --env "CXX=/usr/bin/clang++" "$builder"
buildah config --add-history --env "CORES=${CORES}" "$builder"

buildah run "$builder" apt-get install -y libgoogle-perftools-dev

# buildah run "$builder" apt-get install -y libbson-dev libmongoc-dev

heading "Copying make configuration for mariadb..."
add_atomic "$builder" "${CONTEXT}/CMakeExtra.txt" "/tmp"
heading "Making mariadb..."

buildah unshare --mount "U_SOURCE=$source" bash <<EOU
buildah run -v "\${U_SOURCE}/:/tmp/server" -v "${CONTEXT}:/tmp/up" "$builder" bash <"${CONTEXT}/ubuntu/make.sh"
EOU
# buildah run "$builder" ctest
# buildah run "$builder" cmake --system-information
exit 1

buildah run "$builder" ls /tmp/build/mariadb-${MARIADB_VER}*
package=$(buildah run "$builder" ls "/tmp/build/mariadb-${MARIADB_VER}*")

buildah run "$builder" cat /tmp/build/sql/CMakeFiles/mysqld.dir/flags.make
buildah run "$builder" cat /tmp/build/sql/CMakeFiles/mysqld.dir/link.txt

buildah run "$builder" tar -zpxf "$package" -C /tmp --exclude "mysql-test"

buildah run "$builder" ls -la /tmp
buildah run "$builder" ls -la /tmp/build

image_name="${BUILD_RES_PREFIX}mariadb-complete:${OS_VER}"

uproot_save "$builder" "/tmp/mariadb-${MARIADB_VER}*" "$image_name"
builder="${RETURN_UPROOT_SAVE}"

mariadb_built_image="$image_name"

ending "Build complete"

echo -e "Building an image called runtime"
runtime=$(buildah from "$common_image")
buildah run "$runtime" apt-get install -y --no-install-recommends \
  gnutls-bin tzdata logrotate expect \
  libreadline8 libxml2 unixodbc \
  zlib1g liblz4-1 libzstd1 \
  libgoogle-perftools4 libjemalloc2 openssl \
  liburing1 libpmem1 libnuma1
buildah run "$runtime" ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
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

buildah config --env LD_PRELOAD="/bin:/usr/bin:/usr/local/mysql/bin" "$runtime"
buildah config --env TZ="$TZ" "$runtime"

buildah config --entrypoint '[ "/tmp/scripts/init.sh" ]' --cmd '' "$runtime"

buildah config --volume '[ "/usr/local/mysql/data" ]' "$runtime"
buildah config --volume '[ "/etc/mysql/conf.d" ]' "$runtime"

buildah config --port 3306 "$runtime"
echo -e "Build complete"

echo -e "Storing runtime"
buildah commit --omit-timestamp "$runtime" "containers-storage:mariadb:${MARIADB_VER}"
echo -e "Cleaning up"
buildah rm "$common" "$source" "$builder" "$builder" "$runtime"
echo -e "Done"
