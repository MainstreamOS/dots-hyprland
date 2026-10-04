#!/usr/bin/env bash
# Whether an update is still running: the Update page's run or a dotfiles update.
#
#   update-busy.sh <update.pid> <dotfiles .update-lock>    exit 0 while one is
#
# The lock holder must still be a dotfiles update, as exp_lock_owner_live in
# sdata/subcmd-exp-update/0.run.sh judges it, since a crash leaves the lock behind.
set -u

bash "$(dirname "${BASH_SOURCE[0]}")/update-live.sh" "${1:?pid file}" >/dev/null 2>&1 && exit 0
pid=$(cat "${2:?lock file}" 2>/dev/null) || exit 1
case "$pid" in ""|*[!0-9]*) exit 1 ;; esac
kill -0 "$pid" 2>/dev/null || exit 1
tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -qE 'exp-update|finish-deferred'
