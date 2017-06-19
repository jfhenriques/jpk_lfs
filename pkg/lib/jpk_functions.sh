#!/bin/bash

function jpk_get_base_dir() {
  echo "/pkg"
}

pathprepend "$(jpk_get_base_dir)/bin"


function jpk_cd_pkg_src_dir() {
  if [ ! -z "$JPK_PKG_SRC" ] && [ -d "$JPK_PKG_SRC" ]; then
    cd "$JPK_PKG_SRC"
  else
    echo "Error: pkg src directory does not exist or pkg not setup"
  fi
}
function jpk_cd_pkg_dst_dir() {
  if [ ! -z "$JPK_PKG_DST" ] && [ -d "$JPK_PKG_DST" ]; then
    cd "$JPK_PKG_DST"
  else
    echo "Error: pkg dst directory does not exist or pkg not setup"
  fi
}

function jpk_get_build_user() {
  if [ -z "$JPK_BUILD_USER" ]; then
    echo -n $(whoami)
  else
    echo -n $JPK_BUILD_USER
  fi
  echo
}

function jpk_set_build_user() {
  export JPK_BUILD_USER=$1
}
function jpk_set_pkg_maintainer() {
  export JPK_PKG_MAINTAINER=$1
}

function jpk_print_pkg_info() {
  if [ -z "$JPK_PKG_NAME" ]; then
    echo "There is no package configured"
  else
    echo "Configured package '$JPK_PKG_NAME' version '$JPK_PKG_VER'"
    echo "Source dir: $JPK_PKG_SRC"
    echo "Destination dir: $JPK_PKG_DST"
    echo "Build user: $(jpk_get_build_user)"
  fi
}

function jpk_unset_pkg() {
  unset JPK_PKG_SRC
  unset JPK_PKG_NAME
  unset JPK_PKG_VER
  unset JPK_PKG_DST
}


function jpk_setup_pkg() {

  local PKG_NAME=$1
  local PKG_VERSION=$2
  local PKG_TAR=$3

  if [ -z "$PKG_NAME" ] || [ -z "$PKG_VERSION" ]; then
    echo "please use 'jpk_setup_pkg PKG_NAME PKG_VER [PKG_TAR]'"
    return 1
  fi


  local SRC_DIR="$(jpk_get_base_dir)/src/${PKG_NAME}/${PKG_VERSION}"
  local DST_DIR="$(jpk_get_base_dir)/dst/${PKG_NAME}/${PKG_VERSION}"
  local DST_DIR_ROOT="${DST_DIR}/root"
  local DST_DIR_SCRIPTS="${DST_DIR}/scripts"
  local DST_DIR_SCRIPTS_PRE="${DST_DIR_SCRIPTS}/pre_jpk.sh"
  local DST_DIR_SCRIPTS_POST="${DST_DIR_SCRIPTS}/post_jpk.sh"
  local DST_DIR_SCRIPTS_INFO="${DST_DIR_SCRIPTS}/jpk.info"

  echo "Setting up '$PKG_NAME' version '$PKG_VERSION'"
  echo "Source dir: $SRC_DIR"
  echo "Destination dir: $DST_DIR"


  if [ ! -z "$PKG_TAR" ]; then
    if [ -e "$SRC_DIR" ] && [ "$PKG_TAR" != "-" ]; then
      echo "'$SRC_DIR' already exists"
      return 1
    fi
    if [ -e "$DST_DIR" ] && [ "$PKG_TAR" != "-" ]; then
      echo "'$DST_DIR' already exists"
      return 1
    fi

    mkdir -p "$SRC_DIR"
    chmod 777 "$SRC_DIR"
    mkdir -p "$DST_DIR_ROOT"
    mkdir -p "$DST_DIR_SCRIPTS"

    echo -e "#"'!'"/bin/bash\n" | tee "$DST_DIR_SCRIPTS_PRE" "$DST_DIR_SCRIPTS_POST" > /dev/null
    chmod +x "$DST_DIR_SCRIPTS_PRE"
    chmod +x "$DST_DIR_SCRIPTS_POST"

    cat > "$DST_DIR_SCRIPTS_INFO" << EOF
#
# JPK Info file
#

Name: $PKG_NAME
Version: $PKG_VERSION
Machine: $(uname -m)
Disk Size: 
Checksum: 

Maintainer: $JPK_PKG_MAINTAINER

Description: 

Setup Date: $(date)
Pack Date: 

Dependencies: 

Pre-Script: 
Post-Script: 
Remove-Script: 

EOF

   if [ "$PKG_TAR" != "-" ]; then

      local FULL_PKG_TAR=$(readlink -f "$PKG_TAR")
      local BUILD_USER=$(jpk_get_build_user)
      echo "Extracting '$FULL_PKG_TAR' as '$BUILD_USER'"

      su -l "$BUILD_USER" -c "cd \"$SRC_DIR\" ; tar xf \"$FULL_PKG_TAR\" --strip-components 1 "
    fi

  fi

  export JPK_PKG_SRC=$SRC_DIR
  export JPK_PKG_NAME=$PKG_NAME
  export JPK_PKG_VER=$PKG_VERSION
  export JPK_PKG_DST=$DST_DIR

  jpk_cd_pkg_src_dir
}



function jpk_install_pkg() {
  if [ -z "$JPK_PKG_DST" ] || [ ! -d "$JPK_PKG_DST" ]; then
    echo "Error: pkg not setup"
    return 1
  else
    echo "Installing in '$JPK_PKG_DST'"
    make DESTDIR="${JPK_PKG_DST}/root" install $@ && cd "$JPK_PKG_DST"
  fi
}



function jpk_strip_pkg() {
  if [ -z "$JPK_PKG_DST" ] || [ ! -d "$JPK_PKG_DST" ]; then
    echo "Error: pkg not setup"
    return 1
  else
    local ROOT_DIR="${JPK_PKG_DST}/root"
    local START_SIZE=$(du -s "$ROOT_DIR" | cut -f1)
    find $ROOT_DIR/{,usr/}{bin,lib,sbin} -type f -exec strip --strip-unneeded {} \; 2>/dev/null
    echo "Size before $START_SIZE, size after $(du -s "$ROOT_DIR" | cut -f1)"
  fi
}


function _jpk_append_if_not_exists() {
  local FOUND=$(grep "^$1" "$2")
  if [ -z "$FOUND" ]; then
    echo "$1" >> "$2"
  fi
}


function jpk_pack_pkg() {
  if [ -z "$JPK_PKG_DST" ] || [ ! -d "$JPK_PKG_DST" ]; then
    echo "Error: pkg not setup/installed"
    return 1
  fi

  local TMP_DIR_P="${JPK_PKG_DST}/tmp"
  local ROOT_DIR="${JPK_PKG_DST}/root"
  local SCRIPTS_DIR="${JPK_PKG_DST}/scripts" 

  if [ ! -d "$ROOT_DIR" ] || [ ! -d "$SCRIPTS_DIR" ]; then
    echo "Error: root and/or scripts dir don't exist"
    return 1
  fi

  local TMP_DIR=$(mktemp -d "${TMP_DIR_P}.XXXXXXXXXX")
  mkdir -p "${TMP_DIR}/jpk"
  cp -f "$SCRIPTS_DIR"/* "${TMP_DIR}/jpk/"

  local PKG_TAR_FILE="${TMP_DIR}/pkg.tar"
  ( cd "$ROOT_DIR" ; tar cf "$PKG_TAR_FILE" * )

  tar tvf "$PKG_TAR_FILE" | gzip -9 > "${TMP_DIR}/jpk/index.gz"

  local REPO_DIR="$(jpk_get_base_dir)/repo"
  mkdir -p "$REPO_DIR"

  local TMP_DATE_N=$(date)
  local TMP_DATE=$(date +"%Y%m%d%H%M%S" --date="$TMP_DATE_N")
  local JPK_FILE="${REPO_DIR}/${JPK_PKG_NAME}.${JPK_PKG_VER}.$(uname -m)__${TMP_DATE}.jpk"
  local DISK_SIZE=$(du -s "$ROOT_DIR" | cut -f1)
  local PKG_CHECKSUM=$(sha1sum -b "$PKG_TAR_FILE" 2>/dev/null | cut -d' ' -f1)
  local JPK_INFO_FILE="${TMP_DIR}/jpk/jpk.info"

  _jpk_append_if_not_exists "Pack Date:" "$JPK_INFO_FILE"
  _jpk_append_if_not_exists "Disk Size:" "$JPK_INFO_FILE"
  _jpk_append_if_not_exists "Checksum:" "$JPK_INFO_FILE"


  sed -i "s/Pack Date:.*/Pack Date: ${TMP_DATE_N}/" "$JPK_INFO_FILE"
  sed -i "s/Disk Size:.*/Disk Size: ${DISK_SIZE}/" "$JPK_INFO_FILE"
  sed -i "s/Checksum:.*/Checksum: ${PKG_CHECKSUM}/" "$JPK_INFO_FILE"

  echo "Creating jpk file $JPK_FILE"
  
  ( cd "$TMP_DIR" ; tar --xz -cf "$JPK_FILE"  * )
 
  rm -rf "$TMP_DIR" 

}


jpk_provides() {

  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Please use 'jpk_provides SRC_DIR PATTERN'"
    return 1
  fi

  for jpk in $(find "$1" -name "*.jpk" 2>/dev/null ); do
#    local cont=$(tar xOf "$jpk" jpk/index.gz | gzip -dc|rev|cut -d' ' -f1|rev|grep "$2") 2>/dev/null
    local cont=$(tar xOf "$jpk" jpk/index.gz | gzip -dc|cut -c49-|grep "$2"|xargs -I {} echo "/{}") 2>/dev/null
    if [ "$cont" != "" ]; then
      echo "--> Found: $jpk"
      echo "$cont"
    fi
  done 
}


function jpk_set_pkg_dependencies() {
  local JPK_INFO_FILE="${JPK_PKG_DST}/scripts/jpk.info"
  if [ -z "$JPK_PKG_DST" ] || [ ! -d "$JPK_PKG_DST" ] || [ ! -f "$JPK_INFO_FILE" ]; then
    echo "Error: pkg not setup/installed"
    return 1
  fi

  local args="$@"

  _jpk_append_if_not_exists "Dependencies:" "$JPK_INFO_FILE"
  sed -i "s/Dependencies:.*/Dependencies: ${args}/" "$JPK_INFO_FILE"

  cat "$JPK_INFO_FILE"

}


function jpk_find_pkg_dependencies() {
  local JPK_ROOT_DIR="${JPK_PKG_DST}/root"
  if [ -z "$JPK_PKG_DST" ] || [ ! -d "$JPK_ROOT_DIR" ]; then
    echo "Error: pkg not setup/installed"
    return 1
  fi

  for f in $(find_elf_dependencies "$JPK_ROOT_DIR"); do find /pkg/dst -name "$f"; done
}
