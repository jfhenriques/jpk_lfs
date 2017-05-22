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

function jpk_print_pkg_info() {
  if [ -z "$JPK_PKG_NAME" ]; then
    echo "There is no package configured"
  else
    echo "Configured package is '$JPK_PKG_NAME' version '$JPK_PKG_VER'"
    echo "Source dir is '$JPK_PKG_SRC'"
    echo "Destination dir is '$JPK_PKG_DST'"
  fi
}

function jpk_unset_pkg() {
  unset JPK_PKG_SRC
  unset JPK_PKG_NAME
  unset JPK_PKG_VER
  unset JPK_PKG_DST
}


function jpk_setup_pkg() {

  local SRC_DIR
  local DST_DIR
  local DST_DIR_ROOT
  local DST_DIR_SCRIPTS
  local DST_DIR_SCRIPTS_PRE
  local DST_DIR_SCRIPTS_POST
  local DST_DIR_SCRIPTS_INFO
  local PKG_NAME
  local PKG_VERSION
  local PKG_TAR
  local FULL_PKG_TAR

  PKG_NAME=$1
  PKG_VERSION=$2
  PKG_TAR=$3

  if [ -z "$PKG_NAME" ] || [ -z "$PKG_VERSION" ]; then
    echo "please use 'jpk_setup_pkg PKG_NAME PKG_VER [PKG_TAR]'"
    return 1
  fi


  SRC_DIR="$(jpk_get_base_dir)/src/${PKG_NAME}/${PKG_VERSION}"
  DST_DIR="$(jpk_get_base_dir)/dst/${PKG_NAME}/${PKG_VERSION}"
  DST_DIR_ROOT="${DST_DIR}/root"
  DST_DIR_SCRIPTS="${DST_DIR}/scripts"
  DST_DIR_SCRIPTS_PRE="${DST_DIR_SCRIPTS}/pre_jpk.sh"
  DST_DIR_SCRIPTS_POST="${DST_DIR_SCRIPTS}/post_jpk.sh"
  DST_DIR_SCRIPTS_INFO="${DST_DIR_SCRIPTS}/jpk.info"

  echo "Setting up '$PKG_NAME' version '$PKG_VERSION'"
  echo "Source dir is '$SRC_DIR'"
  echo "Destination dir is '$DST_DIR'"


  if [ ! -z "$PKG_TAR" ]; then
    if [ -e "$SRC_DIR" ]; then
      echo "'$SRC_DIR' already exists"
      return 1
    fi
    if [ -e "$DST_DIR" ]; then
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
Maintainer: $JPK_PKG_MAINTAINER

Description: 

Setup Date: $(date)
Pack Date: 

Dependencies: 

Pre-Script: 
Post-Script: 

EOF

    FULL_PKG_TAR=$(readlink -f "$PKG_TAR")
    echo "Extracting '$FULL_PKG_TAR'"

    ( cd "$SRC_DIR" ; tar xf "$FULL_PKG_TAR" --strip-components 1 )

  fi


  export JPK_PKG_SRC=$SRC_DIR
  export JPK_PKG_NAME=$PKG_NAME
  export JPK_PKG_VER=$PKG_VERSION
  export JPK_PKG_DST=$DST_DIR
}



function jpk_install_pkg() {
  if [ -z "$JPK_PKG_DST" ]; then
    echo "Error: pkg not setup"
  else
    echo "Installing in '$JPK_PKG_DST'"
    make DESTDIR="${JPK_PKG_DST}/root" install $@
  fi
}



function jpk_pack_pkg() {
  local TMP_DIR_P
  local TMP_DIR
  local ROOT_DIR
  local SCRIPTS_DIR
  local TMP_DATE
  local TMP_DATE_N
  local JPK_FILE
  local DISK_SIZE
  local REPO_DIR

  if [ -z "$JPK_PKG_DST" ] ; then
    echo "Error: pkg not setup/installed"
    return 1
  fi

  TMP_DIR_P="${JPK_PKG_DST}/tmp"
  ROOT_DIR="${JPK_PKG_DST}/root"
  SCRIPTS_DIR="${JPK_PKG_DST}/scripts" 

  if [ ! -d "$ROOT_DIR" ] || [ ! -d "$SCRIPTS_DIR" ]; then
    echo "Error: root and/or scripts dir don't exist"
    return 1
  fi

  TMP_DIR=$(mktemp -d "${TMP_DIR_P}.XXXXXXXXXX")
  mkdir -p "${TMP_DIR}/jpk"
  cp -f "$SCRIPTS_DIR"/* "${TMP_DIR}/jpk/"

  ( cd "$ROOT_DIR" ; tar cf "${TMP_DIR}/pkg.tar" * ) 

  REPO_DIR="$(jpk_get_base_dir)/repo"
  mkdir -p "$REPO_DIR"

  TMP_DATE_N=$(date)
  TMP_DATE=$(date +"%Y%m%d%H%M%S" --date="$TMP_DATE_N")
  JPK_FILE="${REPO_DIR}/${JPK_PKG_NAME}.${JPK_PKG_VER}.$(uname -m)__${TMP_DATE}.jpk"
  DISK_SIZE=$(du -s "$ROOT_DIR" |cut -f1)

  sed -i "s/Pack Date:.*/Pack Date: ${TMP_DATE_N}/" "${TMP_DIR}/jpk/jpk.info"
  sed -i "s/Disk Size:.*/Disk Size: ${DISK_SIZE}/" "${TMP_DIR}/jpk/jpk.info"

  echo "Creating jpk file '$JPK_FILE'"
  
  ( cd "$TMP_DIR" ; tar --xz -cf "$JPK_FILE"  * )
 
  rm -rf "$TMP_DIR" 

}


