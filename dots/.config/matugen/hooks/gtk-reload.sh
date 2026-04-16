#!/usr/bin/env bash
# Nudges GTK apps to re-read the regenerated ~/.config/gtk-{3,4}.0/gtk.css.
# GTK4 doesn't watch user CSS, so we (1) toggle a gsettings key as a
# best-effort signal to running apps, and (2) quit Nautilus so its
# background daemon respawns on next use with the new theme.

# Best-effort gsettings toggle — ignored silently if gsettings/dconf absent.
if command -v gsettings >/dev/null; then
  current=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo "'default'")
  case "$current" in
    "'prefer-dark'") other="'default'" ;;
    *)               other="'prefer-dark'" ;;
  esac
  gsettings set org.gnome.desktop.interface color-scheme "$other" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme "$current" 2>/dev/null || true
fi

# Quit Nautilus if running. It's a D-Bus-activated service, so the next
# file-manager call relaunches it and it picks up the fresh gtk.css.
if pgrep -x nautilus >/dev/null 2>&1; then
  nautilus -q >/dev/null 2>&1 || true
fi
