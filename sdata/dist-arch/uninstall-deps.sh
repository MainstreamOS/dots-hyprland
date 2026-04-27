# This script is meant to be sourced.
# It's not for directly running.

for i in mainstream-{quickshell-git,audio,backlight,basic,bibata-modern-classic-bin,extras,fonts-themes,gnome,hyprland,microtex-git,portal,python,screencapture,toolkit,widgets} plasma-browser-integration; do
  v yay -Rns $i
done
