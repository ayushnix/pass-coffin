#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Ayush Agarwal <ayushnix at fastmail dot com>
#
# pass coffin - Password Store Extension (https://www.passwordstore.org)
# A password store extension that hides data inside a GPG coffin
# ------------------------------------------------------------------------------

if [[ -x "${EXTENSIONS}/coffin.bash" ]]; then
  source "${EXTENSIONS}/coffin.bash"
elif [[ -x "${SYSTEM_EXTENSION_DIR}/coffin.bash" ]]; then
  source "${SYSTEM_EXTENSION_DIR}/coffin.bash"
else
  printf '%s\n' "Unable to load pass coffin. Exiting!" >&2
  exit 1
fi

coffin_close
