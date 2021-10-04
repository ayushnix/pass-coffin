#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Ayush Agarwal <ayush at fastmail dot in>
#
# pass coffin - Password Store Extension (https://www.passwordstore.org)
# A pass extension that prevents metadata exposure by encrypting everything
# ------------------------------------------------------------------------------

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
COFFIN_TIMER=false
COFFIN_TIME=""
COFFIN_STATUS=""

coffin_close() {
  COFFIN_STATUS="close"

  local pwd
  if [[ -n "$PWD" ]]; then
    pwd="$PWD"
  else
    printf '%s\n' "Unable to determine your current working directory. This is strange!" >&2
  fi

  cd "$PREFIX" > /dev/null 2>&1 \
    || coffin_die "Unable to find a password store directory"

  if [[ -f "$COFFIN_FILE" ]]; then
    coffin_die "An encrypted GPG coffin already exists"
  fi

  mkdir -p "$COFFIN_DIR" > /dev/null 2>&1 \
    || coffin_die "Unable to create a directory for the coffin" >&2
  set_gpg_recipients "$COFFIN_DIR"

  tar c --exclude ".gpg-id" --exclude "$COFFIN_DIR" --exclude ".extensions" . \
    | "$GPG" -e "${GPG_RECIPIENT_ARGS[@]}" -o "$COFFIN_FILE" "${GPG_OPTS[@]}" \
      > /dev/null 2>&1 || coffin_die "Unable to create an encrypted GPG coffin"

  chmod 400 "$COFFIN_FILE" \
    || printf '%s\n' "Unable to make the encrypted coffin a readonly file" >&2

  find . ! -name '.' ! -name '..' ! -name '.gpg-id' ! -path "./$COFFIN_DIR" \
    ! -path "./$COFFIN_FILE" ! -path "./${EXTENSIONS##*/}" \
    ! -path "./${EXTENSIONS##*/}/*" -delete > /dev/null 2>&1 \
    || coffin_bail "Unable to finish creating a coffin. Trying to restore any changes."

  cd "$pwd" > /dev/null 2>&1 || cd "$HOME" || false

  printf '%s\n' "[#] Password Store data is now hidden inside a GPG coffin"
}

coffin_open() {
  COFFIN_STATUS="open"

  local pwd flag
  flag=false

  if [[ -n "$PWD" ]]; then
    pwd="$PWD"
  else
    printf '%s\n' "Unable to determine your current working directory. This is strange!" >&2
  fi

  cd "$PREFIX" > /dev/null 2>&1 \
    || coffin_die "Unable to find a password store directory"

  if [[ -f "$COFFIN_FILE" ]]; then
    $GPG -d "${GPG_OPTS[@]}" "$COFFIN_FILE" | tar x \
      || coffin_bail "Unable to retrieve data from the encrypted coffin"
  else
    coffin_die "Unable to find an encrypted GPG coffin"
  fi

  rm -f "$COFFIN_FILE" || {
    printf '%s' "Unable to delete the encrypted coffin." >&2
    printf '%s\n' " Please delete $PREFIX/$COFFIN_FILE manually if it exists." >&2
  }
  rmdir "$COFFIN_DIR" || {
    printf '%s' "Unable to delete the directory which holds the coffin." >&2
    printf '%s\n' " Please delete $PREFIX/$COFFIN_DIR manually if it exists." >&2
  }

  if "$COFFIN_TIMER"; then
    systemd-run --user -E PASSWORD_STORE_DIR="$PREFIX" -E PASSWORD_STORE_ENABLE_EXTENSIONS=true \
      --on-active="$COFFIN_TIME" --unit="$PROGRAM-coffin" -G \
      "$(command -v "$PROGRAM")" close > /dev/null 2>&1 && flag=true \
      || printf '%s\n' "Unable to start a timer to close the coffin" >&2
  fi

  if "$flag"; then
    printf '%s\n' "[#] Password Store data has been retrieved from the GPG coffin"
    printf '%s\n' "[#] Password Store will be hidden inside a coffin after $COFFIN_TIME"
  else
    printf '%s\n' "[#] Password Store data has been retrieved from the GPG coffin"
  fi

  cd "$pwd" > /dev/null 2>&1 || cd "$HOME" || false
}

coffin_timer() {
  local choice="$1"
  local status

  status="$(systemctl --user is-active "$PROGRAM-coffin".timer)"
  if [[ "$status" == "active" && -z "$choice" ]]; then
    systemctl --user list-timers "$PROGRAM-coffin".timer \
      || coffin_die "Unable to print the timer status"
  elif [[ "$status" == "active" && "$choice" == "stop" ]]; then
    systemctl --user stop "$PROGRAM-coffin".timer > /dev/null 2>&1 \
      || coffin_die "Unable to stop the timer"
    printf '%s\n' "[#] The timer to hide password store data has been stopped"
  elif [[ "$status" == "inactive" && -z "$choice" ]]; then
    coffin_die "The timer to hide password store isn't active"
  else
    coffin_die "An unknown error has occured. Please raise an issue on GitHub"
  fi
}

coffin_bail() {
  printf '%s\n' "$1" >&2

  if [[ -f "$COFFIN_FILE" && "$COFFIN_STATUS" == "close" ]]; then
    $GPG -d "${GPG_OPTS[@]}" "$COFFIN_FILE" | tar x \
      || coffin_die "An unknown error has occured. Please raise an issue on GitHub"
    rm -f "$COFFIN_FILE" \
      || coffin_die "An unknown error has occured. Please raise an issue on GitHub"
    rmdir "$COFFIN_DIR" || false
  elif [[ -f "$COFFIN_FILE" && "$COFFIN_STATUS" == "open" ]]; then
    $GPG -d "${GPG_OPTS[@]}" "$COFFIN_FILE" \
      || coffin_die "An unknown error has occured. Please raise an issue on GitHub"
    tar x "${COFFIN_FILE%.gpg}" \
      || coffin_die "An unknown error has occured. Please raise an issue on GitHub"
  else
    coffin_die "An unknown error has occured. Please raise an issue on GitHub"
  fi
}

coffin_die() {
  printf '%s\n' "$1" >&2
  exit 1
}

coffin_help() {
  printf '%s\n' "$PROGRAM coffin - hide password store in a coffin" ""
  printf '%s\n' "If you're using $PROGRAM coffin for the first time, execute" ""
  printf '\t%s\n' "\$ $PROGRAM close" ""
  printf '%s\n' "as the first step" ""
  printf '%s\n' "Usage:"
  printf '%s\n' "$PROGRAM close"
  printf '%s\n' "    hide password store data by closing (creating) the coffin"
  printf '%s\n' "$PROGRAM open [-t <time>|--timer <time>|--timer=<time>]"
  printf '%s\n' "    reveal password store data by opening the coffin"
  printf '%s\n' "    optionally, provide a valid systemd compatible time after which the coffin"
  printf '%s\n' "    will be automatically closed"
  printf '%s\n' "$PROGRAM timer [stop]"
  printf '%s\n' "    show the time left before password store data is hidden"
  printf '%s\n' "    'pass timer stop' will stop any active timers started by 'pass open -t'" ""
  printf '%s\n' "Options: $PROGRAM coffin [-h|--help] [-v|--version]"
  printf '%s\n' "-h, --help:    print this help menu"
  printf '%s\n' "-v, --version: print the version of $PROGRAM coffin" ""
  printf '%s\n' "For more details, visit https://github.com/ayushnix/pass-tessen"
}

if [[ "$#" -eq 0 && "$COMMAND" == "coffin" ]]; then
  coffin_help
  exit 0
fi

while [[ "$#" -gt 0 ]]; do
  _opt="$1"
  case "$_opt" in
    -t | --timer)
      if [[ "$COMMAND" == "open" ]]; then
        [[ "$#" -lt 2 ]] && {
          printf '%s\n' "Please specify a valid systemd compatible time format" >&2
          exit 1
        }
        COFFIN_TIMER=true
        COFFIN_TIME="$2"
      else
        coffin_die "invalid argument detected"
      fi
      shift
      ;;
    --timer=*)
      if [[ "$COMMAND" == "open" ]]; then
        COFFIN_TIMER=true
        COFFIN_TIME="${_opt##--timer=}"
      else
        coffin_die "invalid argument detected"
      fi
      ;;
    -h | --help)
      coffin_help
      exit 0
      ;;
    -v | --version)
      printf '%s\n' "$PROGRAM coffin version $COFFIN_VERSION"
      exit 0
      ;;
    stop)
      if [[ "$COMMAND" == "timer" ]]; then
        break
      else
        coffin_die "invalid argument detected"
      fi
      ;;
    --)
      shift
      break
      ;;
    *)
      coffin_die "invalid argument detected"
      ;;
  esac
  shift
done
unset -v _opt
