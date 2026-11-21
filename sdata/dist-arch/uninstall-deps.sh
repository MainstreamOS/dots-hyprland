# This script is meant to be sourced.
# It's not for directly running.

for i in mainstream-{quickshell-git,audio,backlight,basic,bibata-modern-classic-bin,extras,fonts-themes,gnome,hyprland,microtex-git,portal,python,screencapture,toolkit,widgets,assistance} plasma-browser-integration; do
  # Removing a package takes the dependencies only it needed, so a later name may already be gone.
  pacman -Qq "$i" >/dev/null 2>&1 || continue
  v sudo pacman -Rns $i
done
