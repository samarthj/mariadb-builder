#!/bin/bash

export SCRIPT_DIR="${SCRIPT_DIR:-$(dirname "$0")}"
export CONTEXT=${CONTEXT:-${SCRIPT_DIR%/*}}

echo "The script you are running has:"
echo " -> basename - $(basename "$0")"
echo " -> SCRIPT_DIR - $SCRIPT_DIR"
echo " -> CONTEXT - $CONTEXT"

set -o errexit

# shellcheck disable=SC1091
source "$(dirname "$0")/util.sh"

trap_exec() {
  echo "Exit Code - $?"
  # heading "Cleaning up containers..."
  # buildah containers -a || true
  # buildah rm -a || true
  # heading "Cleaning up images..."
  # buildah images -a --filter "reference=${BUILD_RES_PREFIX}mariadb*" || true
  # buildah rmi -p || true
  # buildah images -a --format '{{.Name}}:{{.Tag}}' |
  #   grep "${BUILD_RES_PREFIX}mariadb*" |
  #   xargs -I{} buildah rmi -f {} || true
}

trap trap_exec INT QUIT EXIT SIGINT SIGHUP SIGTERM

export MARIADB_VER=${MARIADB_VER:-"10.6"}
export OS_NAME="debian"
export OS_VER=${OS_VER:-"sid"}
export OS_CODENAME=${OS_VER:-"sid"}
export RUN_USER=${RUN_USER:-"mysql"}
export CORES=${CORES:-$(nproc)}
export TZ=${TZ:"America/Los_Angeles"}

mariadb_built_image_name="${BUILD_RES_PREFIX}mariadb-complete:${OS_VER}"
mariadb_built_container=$(get_container_id "$mariadb_built_image_name")

common_image_name_only="${BUILD_RES_PREFIX}mariadb-base"
common_image_name="${common_image_name_only}:${OS_VER}"

if [ -z "$mariadb_built_container" ] && [ -z "$(get_image "$mariadb_built_image_name")" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/01-base.sh"

  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/02-source.sh"

  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/03-build_base.sh"

  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/04-build.sh"
  ending "Build complete"
fi

mariadb_runtime_image_name="mariadb-complete-${MARIADB_VER}:${OS_VER}"
if [ -z "$(get_image "$mariadb_runtime_image_name")" ]; then

  heading -e "Building an image called $mariadb_runtime_image_name"

  mariadb_built_container=$(get_container_id "$mariadb_built_image_name")
  mariadb_built_container=${mariadb_built_container:-$(buildah from --name="$mariadb_built_image_name" "$mariadb_built_image_name")}
  runtime=$(get_container_id "$mariadb_runtime_image_name")
  runtime=${runtime:-$(buildah from --name="$mariadb_runtime_image_name" "$common_image_name")}
  buildah run "$runtime" bash <<EOU
apt update &&
apt install -y --no-install-recommends \
  gnutls-bin tzdata logrotate expect \
  libwrap0 libgoogle-perftools4 \
  liburing1 libpmem1 libnuma1 \
  libreadline8 libxml2 unixodbc \
  zlib1g liblz4-1 libzstd1 \
  libjemalloc2 openssl \
  libcurl4 libncurses6 libedit2 libmongoc-1.0-0 libbson-1.0-0
EOU

  buildah config --env PATH="\$PATH:/usr/local/mysql/bin" "$runtime"
  # buildah run "$runtime" ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
  buildah run "$runtime" groupadd -g 1001 "${RUN_USER}"
  buildah run "$runtime" useradd -M -g "${RUN_USER}" -u 1000 "${RUN_USER}"
  buildah run "$runtime" mkdir -p /home/"${RUN_USER}"
  buildah run "$runtime" touch /home/"${RUN_USER}"/.bashrc
  buildah run "$runtime" sh -c "echo 'umask 002' > /home/${RUN_USER}/.bashrc"

  buildah run "$runtime" mkdir /usr/local/mysql
  buildah copy --from="$mariadb_built_container" "$runtime" / /usr/local/mysql
  buildah run "$runtime" mkdir -p /etc/mysql/conf.d
  buildah run "$runtime" mkdir -p /usr/local/mysql/data
  buildah run "$runtime" ln -s /usr/local/mysql/support-files/systemd/* /lib/systemd/system/

  add_atomic "$runtime" "${CONTEXT}/scripts" /tmp/scripts
  add_atomic "$runtime" "${CONTEXT}/my.cnf" /etc/mysql/my.cnf
  add_atomic "$runtime" "${CONTEXT}/logrotate" /etc/logrotate.d/mariadb_slow_log
  # buildah config --env LD_PRELOAD="\$PATH:/usr/local/mysql/bin" "$runtime"
  buildah config --env TZ="$TZ" "$runtime"

  buildah config --entrypoint '[ "/tmp/scripts/init.sh" ]' --cmd '' "$runtime"

  buildah config --volume "/usr/local/mysql/data" "$runtime"
  buildah config --volume "/etc/mysql/conf.d" "$runtime"

  buildah config --port 3306 "$runtime"
  ending "Build complete"

  save_image "$runtime" "$mariadb_runtime_image_name"
  heading "Cleaning up"
  buildah rm -a
  ending "Done"

fi
