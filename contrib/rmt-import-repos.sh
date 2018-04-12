#!/bin/bash

NAME="$(basename $0)"
IMPORT_REPOS=0
IMPORT_CUSTOM_REPOS=0

SMT_TAR_FILE=""
SMT_TAR_DIR="smt-export"

# -- UTILITY ------------------------------------------------------------------
function warn() { echo -ne "\033[31m$@\033[0m\n"; }
function step() { echo -ne "$@...\n"; }
function action() { echo -ne " \033[32m::\033[0m $@\n"; }

function tar_read_file() {
  local path="$SMT_TAR_DIR/$1"

  tar xfO $SMT_TAR_FILE $path
}

function tar_has_file() {
  local path="$SMT_TAR_DIR/$1"

  if tar tf $SMT_TAR_FILE $path &> /dev/null; then
    return 0
  fi
  return 1
}

function usage() {
  echo "Usage: $NAME TARBALL [--no-custom-repos, --only-custom-repos]"
  echo ""
  echo "    TARBALL              Tarball created by the 'smt-export' script."
  echo ""
  echo "    --no-custom-repos    Only import and enable normal repositories"
  echo "                         which are defined by products"
  echo "    --only-custom-repos  Only import and enable custom defined"
  echo "                         repositories"
  echo ""
  echo "Import and enable repositories from 'smt-export' tarball to rmt."
}

# -- RMT ----------------------------------------------------------------------
function rmt_enable_repo() {
  local id="$1"

  rmt-cli repos enable $id
}

function rmt_enable_custom_repo() {
  local id="$1"
  local name="$2"
  local url="$3"

  rmt-cli repos custom add $url $name
  # FIXME: attaching the new added repo is missing right now!
}

# -- STEPS --------------------------------------------------------------------

function step_validate_environment() {
  if [[ ! -f $SMT_TAR_FILE ]]; then
    usage
    exit 0
  fi

  if ! which rmt-cli &> /dev/null; then
    warn "Fatal:"
    warn "No rmt commandline client found! Make sure that rmt-server is"
    warn "installed and running before importing repositories."
    exit 1
  fi
}

function step_enable_repos() {
  local enabled=0

  if ! tar_has_file "enabled_repos.csv"; then
    warn "Fatal:"
    warn "Could not read enabled repositories from $SMT_TAR_FILE!"
    exit 1
  fi

  step "Adding repositories from exported configuration"
  while read repo; do
    if ! rmt_enable_repo $repo; then
      action "failed to enable $repo!"
    else
      enabled=$((enabled + 1))
    fi
  done < <(tar_read_file "enabled_repos.csv")

  action "$enabled repositories enabled!"
}

function step_enable_custom_repos() {
  local enabled=0

  if ! tar_has_file "enabled_custom_repos.csv"; then
    warn "Fatal:"
    warn "Could not read enabled custom repositories from $SMT_TAR_FILE!"
    exit 1
  fi

  step "Adding repositories from exported configuration"
  while IFS=, read id name url; do
    if ! rmt_enable_custom_repo $id $name $url; then
      action "failed to enable $repo!"
    else
      enabled=$((enabled + 1))
    fi
  done < <(tar_read_file "enabled_custom_repos.csv")
  action "$enabled custom repositories enabled!"
}

# -- MAIN ---------------------------------------------------------------------

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "" ]]; then
  usage
  exit 0
fi

if [[ "$1" == "--no-custom-repos" ]]; then
  IMPORT_CUSTOM_REPOS=1
  shift
fi

if [[ "$1" == "--only-custom-repos" ]]; then
  IMPORT_REPOS=1
  shift
fi

if [[ $1 != *.tar.gz ]]; then
  warn "No or invalid smt-export supplied!"
  exit 1
fi

if [[ "$2" == "--no-custom-repos" ]]; then
  IMPORT_CUSTOM_REPOS=1
fi

if [[ "$2" == "--only-custom-repos" ]]; then
  IMPORT_REPOS=1
fi

SMT_TAR_FILE=$1

step_validate_environment

if [[ $IMPORT_REPOS == 0 ]]; then
  step_enable_repos
fi

if [[ $IMPORT_CUSTOM_REPOS == 0 ]]; then
  step_enable_custom_repos
fi