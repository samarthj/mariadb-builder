#!/bin/bash

# Setting up some colors for helping read the output
# shellcheck disable=SC2155
RS="$(tput sgr0)"
export BOLD="$(tput smso)"
export RBOLD="$(tput rmso)"

export OS_NAME="\$(sed -n -e 's/^ID=//p' /etc/os-release)"
export OS_CODENAME="\$(sed -n -e 's/^VERSION_CODENAME=//p' /etc/os-release)"
export MARIADB_PATCH="\$(sed -n -e 's/^MYSQL_VERSION_PATCH=//p' /tmp/server)"
export CONTAINER_STORE=${CONTAINER_STORE:-"containers-storage"}
export BUILD_RES_PREFIX=${BUILD_RES_PREFIX:-"build-"}

heading() {
  color=$((RANDOM % 7 + 30))
  echo -e "\e[$((color))m<-"
  # echo "$(shuf -e -z -n1 "${TERM_COLORS[@]}")->"
  echo "${BOLD}$*"
  echo "++++++++++++++++++${RBOLD}"
}

ending() {
  echo "$@"
  echo "------------------${RS}"
}

save_image() {
  heading "Saving image (${CONTAINER_STORE}:${2})..."
  save_image_name="${CONTAINER_STORE}:${2}"
  buildah commit --omit-timestamp "$1" "$save_image_name"
  ending "Stored image (${CONTAINER_STORE}:${2})..."
}

add_atomic() {
  heading "Atomic add..."
  ctr="$1"
  src="$2"
  dest="$3"
  buildah unshare --mount "CTR=$ctr" <<EOF
#!/bin/sh
cp -au "$src" "\$CTR$dest"
buildah umount "$ctr"
EOF
  ending "finished copying"
}

export RETURN_UPROOT_SAVE=""
uproot_save() {
  heading "Uprooting..."
  ctr=$1
  src=$2
  img=$3
  newctr=$(buildah from scratch)
  buildah copy --from "$ctr" "$newctr" "$src"
  save_image "$newctr" "$img"
  RETURN_UPROOT_SAVE="$newctr"
  ending "Done Uprooting ..."
}

is_os() {
  [[ "$1" == "$(awk -F= '/^ID=/{print $2}' /etc/os-release)" ]]
}

os_install() {
  prog=$1
  echo "installing $prog..."
  is_os ubuntu && apt install -y --no-install-recommends "$prog" ||
    is_os archlinux && pacman -Sy "$prog" --noconfirm
}
