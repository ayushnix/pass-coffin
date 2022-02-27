#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Ayush Agarwal <ayushnix at fastmail dot com>
#
# pass coffin - Password Store Extension (https://www.passwordstore.org)
# A pass extension that prevents metadata exposure by encrypting the password
# store directory
# ------------------------------------------------------------------------------

# list of variables and functions from password-store.sh used in this extension
# PREFIX                     - the location of the directory where pass data is kept
# EXTENSIONS                 - the location of user installed extensions
# PROGRAM                    - the name of the pass script itself
# PASSWORD_STORE_SIGNING_KEY - sign the encrypted coffin to ensure data integrity and authenticity
# set_gpg_recipients         - verify the GPG keyfile and set up GPG for encryption

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
  # if the PREFIX (PASSWORD_STORE_DIR) exists, cd into it
  if [[ -d $PREFIX ]]; then
    cd "$PREFIX" > /dev/null 2>&1 \
      || coffin_die "unable to open the password store dir"
  fi

  # check if coffin file is present and if it isn't present, check if .gpg
  # files are present in the password store and warn the user that password
  # store is already decrypted
  # only if no coffin and no .gpg files are found in the password store, throw
  # and error and print a scary message
  local -a num_files
  local extbase
  extbase="$(coffin_basename "$EXTENSIONS")"
  if ! [[ -f $coffin_file ]]; then
    mapfile -t num_files < <(find . -depth ! -name '.' ! -name '..' \
      ! -path "./$coffin_dir" ! -path "./$coffin_file" ! -path "./$extbase" \
      ! -path "./$extbase/*" -name "*.gpg" -print 2> /dev/null)
    if [[ ${#num_files[@]} -gt 0 ]]; then
      coffin_warn "password store data is probably not inside a coffin"
      coffin_warn "${#num_files[@]} password files found"
      exit 1
    else
      coffin_die "unable to find a password store coffin"
    fi
  fi

  # check if $coffin_file.sig is valid, if it exists
  # could've used the verify_file function but we need custom output for
  # pass_coffin
  set -o pipefail
  local fgprnt key sigflag
  if [[ -n $PASSWORD_STORE_SIGNING_KEY ]]; then
    if ! [[ -f "$coffin_file".sig ]]; then
      coffin_die "unable to find the signature for the coffin"
    fi
    sigflag=false
    fgprnt="$("$GPG" "${GPG_OPTS[@]}" --verify --status-fd=1 "$coffin_file".sig \
      "$coffin_file" 2> /dev/null \
      | sed -n 's/^\[GNUPG:\] VALIDSIG [A-F0-9]\{40\} .* \([A-F0-9]\{40\}\)$/\1/p')"
    if [[ -z $fgprnt ]]; then
      coffin_die "the signature for the coffin is invalid"
    else
      sigflag=true
    fi
  fi

  # extract the files from the coffin
  # we've already checked if the coffin exists and if its signature is valid
  $GPG -d "${GPG_OPTS[@]}" "$coffin_file" | tar x \
    || coffin_die "unable to retrieve data from the coffin"
  set +o pipefail

  # remove the coffin_file and coffin_dir
  rm -f "$coffin_file" "$coffin_file".sig || {
    coffin_warn "unable to delete the coffin"
    coffin_warn "please delete $PREFIX/$coffin_file manually if it exists"
  }
  rmdir "$coffin_dir" || {
    coffin_warn "unable to delete the directory which holds the coffin"
    coffin_warn "please delete $PREFIX/$coffin_dir manually if it exists"
  }

  # if the environment variables are defined, they will be imported and if not, they will be blank
  # thankfully, password-store.sh deals with this correctly
  local timer_flag
  if [[ -n $coffin_time ]]; then
    if command -v systemd-run > /dev/null 2>&1; then
      if systemd-run --user -E PASSWORD_STORE_DIR -E PASSWORD_STORE_ENABLE_EXTENSIONS \
        -E PASSWORD_STORE_SIGNING_KEY -E PASSWORD_STORE_GPG_OPTS \
        -E PASSWORD_STORE_EXTENSIONS_DIR --on-active="$coffin_time" \
        --timer-property=AccuracySec=100ms --unit="$PROGRAM-coffin" \
        -G "$(command -v "$PROGRAM")" close > /dev/null 2>&1; then
        timer_flag=true
      else
        coffin_warn "unable to start a timer to create a coffin"
      fi
    else
      coffin_warn "systemd-run is not installed"
      coffin_warn "password store data will not be hidden inside a coffin automatically"
    fi
  fi

  if [[ $sigflag == true ]] && [[ $timer_flag == true ]]; then
    printf "%s\n" "the signature for the coffin is valid"
    printf "%s\n" "password store data has been retrieved from the coffin"
    printf "%s\n" "password store data will be hidden inside a coffin after $coffin_time"
  elif [[ $sigflag == true ]] && [[ -z $timer_flag ]]; then
    printf "%s\n" "the signature for the coffin is valid"
    printf "%s\n" "password store data has been retrieved from the coffin"
  elif [[ -z $sigflag ]] && [[ $timer_flag == true ]]; then
    printf "%s\n" "password store data has been retrieved from the coffin"
    printf "%s\n" "password store data will be hidden inside a coffin after $coffin_time"
  elif [[ -z $sigflag ]] && [[ -z $timer_flag ]]; then
    printf "%s\n" "password store data has been retrieved from the coffin"
  fi

  unset -v num_files fgprnt key sigflag timer_flag extbase
}

coffin_timer() {
  if ! command -v systemd-run > /dev/null 2>&1; then
    coffin_die "systemd-run is not installed"
  fi

  local choice="$1"
  if systemctl --user --quiet is-active "$PROGRAM"-coffin.timer 2> /dev/null; then
    if [[ -z $choice ]]; then
      coffin_head 2 <(systemctl --user list-timers "$PROGRAM"-coffin.timer)
    elif [[ $choice == "stop" ]]; then
      systemctl --user stop "$PROGRAM"-coffin.timer > /dev/null 2>&1 \
        || coffin_die "unable to stop the timer"
      printf "%s\n" "the timer to create the coffin has been stopped"
    fi
  else
    coffin_die "the timer to create the coffin isn't active"
  fi

  unset -v choice
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
  printf "%s" "\
$PROGRAM coffin - hide password store data inside a coffin

usage:
    $PROGRAM close
        create a tar archive with the password store data and encrypt it
        optionally, if PASSWORD_STORE_SIGNING_KEY is set, sign the encrypted
        tar archive

    $PROGRAM open [ -t <time>, --timer <time>, --timer=<time> ]
        decrypt and extract the encrypted tar archive and, optionally, close it
        automatically after <time>
        to use the <time> functionality, systemd-run must be installed and
        <time> must be valid systemd.time(7)
        if PASSWORD_STORE_SIGNING_KEY is set, the encrypted tar archive must
        have a valid detached signature

    $PROGRAM timer [stop]
        show the state of the timer started using $PROGRAM open -t
        optionally, stop the timer before its scheduled time

    $PROGRAM coffin [-h | --help] [-v | --version]
        -h, --help: print this help menu
        -v, --version: print the version of $PROGRAM coffin

        show the help menu by default and show the version if -v is given

for more details, visit https://github.com/ayushnix/pass-coffin
"
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
        if [[ $# -lt 2 ]]; then
          coffin_die "please specify a valid systemd compatible time format"
        fi
        coffin_time="$2"
      fi
      shift
      ;;
    --timer=*)
      if [[ $COMMAND == "open" ]]; then
        if [[ -n ${_opt##--timer=} ]]; then
          coffin_time="${_opt##--timer=}"
        else
          coffin_die "please specify a valid systemd compatible time format"
        fi
      fi
      ;;
    -h | --help)
      coffin_help
      exit 0
      ;;
    -v | --version)
      printf "%s\n" "$PROGRAM coffin version $coffin_version"
      exit 0
      ;;
    # ignore the stop argument and let timer.bash handle it
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
