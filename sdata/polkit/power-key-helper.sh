#!/bin/bash
# Helper script to update HandlePowerKey in logind drop-in.
# Called via pkexec with polkit policy to avoid interactive auth prompts.
set -euo pipefail

ACTION="$1"

# Validate action
case "$ACTION" in
    suspend|hibernate|poweroff|ignore) ;;
    *) echo "Invalid action: $ACTION" >&2; exit 1 ;;
esac

mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandlePowerKey=%s\n' "$ACTION" > /etc/systemd/logind.conf.d/10-power-key.conf
systemctl kill -s HUP systemd-logind
