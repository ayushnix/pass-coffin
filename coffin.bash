#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Ayush Agarwal <ayushnix at fastmail dot com>
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
readonly coffin_version="1.2.0"
readonly coffin_name="coffin"
readonly coffin_dir=".$coffin_name"
readonly coffin_file="$coffin_dir/$coffin_name".tar.gpg
# red color for errors
readonly coffin_red="\e[31m"
# yellow color for warnings
readonly coffin_yel="\e[33m"
readonly coffin_res="\e[0m"
coffin_time=""

coffin_close() {
  # if the PREFIX (PASSWORD_STORE_DIR) exists, cd into it
  if [[ -d $PREFIX ]]; then
    cd "$PREFIX" > /dev/null 2>&1 \
      || coffin_die "unable to open the password store dir"
  fi

  # if the encrypted coffin already exists, exit
  if [[ -f $coffin_file ]]; then
    coffin_die "an encrypted coffin already exists"
  fi

  # create the dir for the coffin
  mkdir -p "$coffin_dir" > /dev/null 2>&1 \
    || coffin_die "unable to create a directory for the coffin"

  # this function accepts a dir, checks if there's a different .gpg-id for the
  # dir and if not found, it ends up using the .gpg-id in PASSWORD_STORE_DIR
  # and initializes the gpg variables we'll need to create the coffin and sign
  # it
  set_gpg_recipients "$coffin_dir"

  # get the basename of the extensions dir
  # extensions won't be empty because password-store.sh sets it to a default
  # value of $PREFIX/.extensions if PASSWORD_STORE_EXTENSIONS_DIR isn't set
  local extbase
  extbase="$(coffin_basename "$EXTENSIONS")"

  # tar and encrypt the password store data
  set -o pipefail
  tar c --exclude ".gpg-id" --exclude ".gpg-id.sig" --exclude "$coffin_dir" --exclude "$extbase" . \
    | "$GPG" -e "${GPG_RECIPIENT_ARGS[@]}" -o "$coffin_file" "${GPG_OPTS[@]}" \
      > /dev/null 2>&1 || coffin_die "unable to create an encrypted coffin"
  # sign the coffin
  # borrowed from password-store.sh from the cmd_init function
  local key
  local -a signing_keys
  if [[ -n $PASSWORD_STORE_SIGNING_KEY ]]; then
    for key in $PASSWORD_STORE_SIGNING_KEY; do
      signing_keys+=(--default-key "$key")
    done
    "$GPG" "${GPG_OPTS[@]}" "${signing_keys[@]}" --detach-sign "$coffin_file" \
      || coffin_die "unable to sign the coffin"
    key="$("$GPG" "${GPG_OPTS[@]}" --verify --status-fd=1 "$coffin_file".sig "$coffin_file" 2> /dev/null \
      | sed -n 's/^\[GNUPG:\] VALIDSIG [A-F0-9]\{40\} .* \([A-F0-9]\{40\}\)$/\1/p')"
    [[ -n $key ]] || coffin_die "unable to sign the coffin"
  fi
  set +o pipefail

  chmod 400 "$coffin_file" \
    || coffin_warn "unable to make the coffin a readonly file"
  chmod 400 "$coffin_file.sig" \
    || coffin_warn "unable to make the coffin signature a readonly file"

  # delete the remaining data inside PREFIX (PASSWORD_STORE_DIR)
  # CAVEAT: pass init supports specifying different .gpg-id files for different
  # subdirectories
  # however, since we're not modifying the password store itself, using just
  # the .gpg-id in PASSWORD_STORE_DIR to create the coffin sounds fine but I'd
  # like to know if I'm missing something
  # -delete isn't supposed to delete directories unless they're empty but this
  # does? probably because -delete implies -depth and files end up getting
  # deleted before directories
  find . ! -name '.' ! -name '..' ! -name '.gpg-id' ! -name '.gpg-id.sig' \
    ! -path "./$coffin_dir" ! -path "./$coffin_file" ! -path "./$coffin_file.sig" \
    ! -path "./$extbase" ! -path "./$extbase/*" -delete > /dev/null 2>&1 \
    || coffin_die "unable to hide the password store files"

  # if the timer to close the coffin is active, stop it
  local timer_status
  timer_status="$(systemctl --user is-active "$PROGRAM-coffin".timer 2> /dev/null)"
  if [[ $timer_status == "active" ]]; then
    systemctl --user stop "$PROGRAM-coffin".timer > /dev/null 2>&1 \
      || coffin_warn "unable to stop the timer to close the coffin"
  fi

  # clear the password from gpg-agent
  gpg-connect-agent reloadagent /bye > /dev/null 2>&1 \
    || coffin_warn "unable to clear password from gpg-agent"

  if [[ -n $PASSWORD_STORE_SIGNING_KEY ]] && [[ -n $key ]]; then
    printf "%s\n" "password store data has been signed and buried inside a coffin"
  else
    printf "%s\n" "password store data has been buried inside a coffin"
  fi

  unset -v extbase timer_status key signing_keys
}

coffin_open() {
  COFFIN_STATUS="open"

  local pwd flag
  flag=false

  cd "$PREFIX" > /dev/null 2>&1 \
    || coffin_die "Unable to find a password store directory"

  if [[ -f $COFFIN_FILE ]]; then
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
      --on-active="$COFFIN_TIME" --timer-property=AccuracySec=100ms --unit="$PROGRAM-coffin" -G \
      "$(command -v "$PROGRAM")" close > /dev/null 2>&1 && flag=true \
      || printf '%s\n' "Unable to start a timer to close the coffin" >&2
  fi

  if "$flag"; then
    printf '%s\n' "[#] Password Store data has been retrieved from the GPG coffin"
    printf '%s\n' "[#] Password Store will be hidden inside a coffin after $COFFIN_TIME"
  else
    printf '%s\n' "[#] Password Store data has been retrieved from the GPG coffin"
  fi
}

coffin_timer() {
  local choice="$1"
  local status

  status="$(systemctl --user is-active "$PROGRAM-coffin".timer)"
  if [[ $status == "active" && -z $choice ]]; then
    systemctl --user list-timers "$PROGRAM-coffin".timer \
      || coffin_die "Unable to print the timer status"
  elif [[ $status == "active" && $choice == "stop" ]]; then
    systemctl --user stop "$PROGRAM-coffin".timer > /dev/null 2>&1 \
      || coffin_die "Unable to stop the timer"
    printf '%s\n' "[#] The timer to hide password store data has been stopped"
  elif [[ $status == "inactive" && -z $choice ]]; then
    coffin_die "The timer to hide password store isn't active"
  else
    coffin_die "An unknown error has occured. Please raise an issue on GitHub"
  fi
}

coffin_head() {
  local -a line

  mapfile -tn "$1" line < "$2"
  printf "%s\n" "${line[@]}"

  unset -v line
}

coffin_basename() {
  local tmp

  # remove everything except the trailing forward slash, if it exists
  tmp="${1##*[!/]}"
  # remove the trailing forward slash, if it was found
  tmp="${1%"$tmp"}"
  # remove the everything except the name of the file/dir
  tmp="${tmp##*/}"
  # print the name of the file/dir and if it's empty, print `/` because that's
  # the only case when $tmp would become empty
  printf "%s\n" "${tmp:-/}"

  unset -v tmp
}

coffin_warn() {
  if [[ -n $NO_COLOR ]]; then
    printf "%s\n" "$1" >&2
  else
    printf "%b%s%b\n" "$coffin_yel" "$1" "$coffin_res" >&2
  fi
}

coffin_die() {
  if [[ -n $NO_COLOR ]]; then
    printf "%s\n" "$1" >&2
  else
    printf "%b%s%b\n" "$coffin_red" "$1" "$coffin_res" >&2
  fi
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
  printf '%s\n' "For more details, visit https://github.com/ayushnix/pass-coffin"
}

if [[ $# -eq 0 && $COMMAND == "coffin" ]]; then
  coffin_help
  exit 0
fi

while [[ $# -gt 0 ]]; do
  _opt="$1"
  case "$_opt" in
    -t | --timer)
      if [[ $COMMAND == "open" ]]; then
        [[ $# -lt 2 ]] && {
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
      if [[ $COMMAND == "open" ]]; then
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
      if [[ $COMMAND == "timer" ]]; then
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
