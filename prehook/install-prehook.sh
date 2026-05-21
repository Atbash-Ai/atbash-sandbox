#!/usr/bin/env bash
# Source this file to install the atbash prehook in the current shell.
#
#   source /opt/atbash/prehook/install-prehook.sh
#
# To make it permanent inside the sandbox container, add the line above to
# ~/.bashrc.  The prehook is intentionally OFF by default — see prehook/README.md.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "install-prehook.sh must be sourced, not executed:" >&2
  echo "    source ${BASH_SOURCE[0]}" >&2
  exit 2
fi

# shellcheck source=./atbash-prehook.sh
source "$(dirname "${BASH_SOURCE[0]}")/atbash-prehook.sh"
