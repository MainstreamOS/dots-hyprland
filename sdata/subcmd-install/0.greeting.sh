# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

#####################################################################################

clear 2>/dev/null || true
ms_logo
ms_section "Mainstream installer"
ms_hint "Arch, approachable. Hyprland, at home."
printf "\n"
ms_step_raw "step 1 — install dependencies"
ms_step_raw "step 2 — set up permissions / services"
ms_step_raw "step 3 — copy config files"
printf "\n"
ms_hint "idempotent · safe to re-run · use --help for options"
printf "\n"

# Visual mode is non-interactive — no per-command confirm prompt and no
# blocking pause. Visual is the default for ./setup install; pass
# --verbose to fall back to the legacy interactive prompts.
if [[ "${MS_VISUAL:-0}" == "1" ]]; then
  ask=false
else
  pause
  case $ask in
    false) sleep 0 ;;
    *)
      ms_section "Confirm every command before it runs?"
      ms_hint "y = yes, ask before each (default)"
      ms_hint "n = no, just run them"
      ms_hint "a = abort"
      ms_ask "===> [Y/n/a]: " p
      case $p in
        n) ask=false ;;
        a) exit 1 ;;
        *) ask=true ;;
      esac
      ;;
  esac
fi
