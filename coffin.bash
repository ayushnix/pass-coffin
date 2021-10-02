#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Ayush Agarwal <ayush at fastmail dot in>
#
# pass coffin - Password Store Extension (https://www.passwordstore.org)
# A pass extension that prevents metadata exposure by encrypting everything
# ------------------------------------------------------------------------------

# don't leak potentially sensitive password-store data if debug mode is enabled
set +x

# list of variables and functions from password-store.sh used in this extension
# PREFIX             - the location of the user password-store data
# EXTENSIONS         - the location of user installed extensions
# PROGRAM            - the name of password-store, pass
# set_gpg_recipients - verify the GPG keyfile and set up GPG for encryption

# initialize the global variables
readonly COFFIN_VERSION="0.1"
readonly COFFIN_NAME="coffin"
readonly COFFIN_DIR=".$COFFIN_NAME"
readonly COFFIN_FILE="$COFFIN_DIR/$COFFIN_NAME".tar.gpg
TIMER=false

coffin_close() {
  local pwd="$PWD"
  cd "$PREFIX" > /dev/null 2>&1 || coffin_die "Password Store data not found. Exiting!"

  if [[ -f "$COFFIN_FILE" ]]; then
    coffin_die '%s\n' "A coffin already exists. Exiting!"
  fi

  mkdir -p "$COFFIN_DIR" > /dev/null 2>&1 || coffin_die "Unable to create a coffin. Exiting!"
  set_gpg_recipients "$COFFIN_DIR"

  tar --exclude=".gpg-id" --exclude="$COFFIN_DIR" --exclude=".extensions" \
    -c . | "$GPG" -e "${GPG_RECIPIENT_ARGS[@]}" -o "$COFFIN_FILE" \
    "${GPG_OPTS[@]}" || coffin_die "Unable to create a coffin. Exiting!"

  chmod 400 "$COFFIN_FILE" || printf '%s\n' "Unable to make the coffin read-only." >&2

  find . ! -name '.gpg-id' -name "./$COFFIN_DIR" ! -name "./$COFFIN_FILE" \
    ! -name "./.extensions" -name "./.extensions/*" -delete \
    || coffin_die "Unable to hide the password store data. Exiting!"

  printf '%s\n' "Your password store data is now hidden inside a coffin"
  cd "$pwd" > /dev/null 2>&1 || exit 1
}

coffin_open() {
  local time="${1-}"
  shift
  local pwd="$PWD"
  cd "$PREFIX" || coffin_die "Password Store data not found. Exiting!"

  if ! [[ -f "$COFFIN_FILE" ]]; then
    coffin_die "Unable to find a coffin. Exiting!"
  fi

  $GPG -d "${GPG_OPTS[@]}" "$COFFIN_FILE" | tar x \
    || coffin_die "Unable to retrieve data from the coffin. Exiting!"

  rm -f "$COFFIN_FILE" || coffin_die "Unable to delete the coffin. Exiting!"
  rm -f "$COFFIN_DIR" || false

  printf '%s' "${0##*/} has retrieved your password store data from the coffin"

  if "$TIMER"; then
    systemd-run --user --on-active="$time" --unit="$PROGRAM-${0##*/}" \
      "$(command -v "$PROGRAM")" close > /dev/null 2>&1 || {
      printf '%s\n' "unable to start the timer" >&2
    }
  fi

  cd "$pwd" > /dev/null 2>&1 || exit 1
}

coffin_timer() {
  local status

  status="$(systemctl --user is-active "$PROGRAM-${0##*/}".timer)"
  if [[ "$status" == "active" ]]; then
    systemctl --user list-timers "$PROGRAM-${0##*/}".timer
  fi
}

coffin_die() {
  printf '%s\n' "${1-}" >&2
  exit 1
}

coffin_help() {
  printf '%s\n' "$PROGRAM coffin - hide password store in a coffin" ""
  printf '%s\n' "If you're using $PROGRAM coffin for the first time, execute" ""
  printf '\t%s\n' "\$ $PROGRAM close" ""
  printf '%s\n' "as the first step" ""
  printf '%s\n' "Usage:"
  printf '%s\n' "$PROGRAM close [-t|--timer]"
  printf '%s\n' "    hide password store data by closing (creating) the coffin"
  printf '%s\n' "    optionally, provide a time to close the coffin after a specific period of time"
  printf '%s\n' "    rather than closing it immediately"
  printf '%s\n' "$PROGRAM open [-t|--timer]"
  printf '%s\n' "    reveal password store data by opening the coffin"
  printf '%s\n' "    optionally, provide a time after which the coffin will be automatically closed"
  printf '%s\n' "$PROGRAM timer"
  printf '%s\n' "    show the time left before password store data is hidden" ""
  printf '%s\n' "Options: $PROGRAM coffin [-h|--help] [-v|--version]"
  printf '%s\n' "-h, --help:    print this help menu"
  printf '%s\n' "-v, --version: print the version of $PROGRAM coffin" ""
  printf '%s\n' "For more details, visit https://github.com/ayushnix/pass-tessen"
}

case "${1-}" in
  -h | --help)
    coffin_help
    exit 0
    ;;
  -v | --version)
    printf '%s\n' "$PROGRAM coffin version $COFFIN_VERSION"
    exit 0
    ;;
  --)
    shift
    ;;
  *)
    coffin_die "Invalid argument detected. Exiting!"
    ;;
esac
shift
