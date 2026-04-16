#!/bin/bash
# Graphical sudo askpass helper for use with SUDO_ASKPASS
# Tries zenity, then kdialog, then rofi as a fallback

if command -v zenity &>/dev/null; then
    zenity --password --title="Authentication Required" 2>/dev/null
elif command -v kdialog &>/dev/null; then
    kdialog --password "Authentication Required" 2>/dev/null
elif command -v rofi &>/dev/null; then
    rofi -dmenu -password -p "Password" -theme-str 'window {width: 300px;}' 2>/dev/null
else
    exit 1
fi
