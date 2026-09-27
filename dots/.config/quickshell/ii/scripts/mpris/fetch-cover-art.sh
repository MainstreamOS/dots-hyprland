#!/usr/bin/env bash
# Downloads a track's cover art into the cache. Arguments: the file to write,
# the address the player reported, and the protocols curl may use, such as
# "http,https".
#
# The address comes from whatever the player reports, so it reaches curl as
# an argument of its own and is never read as an option or a glob. The size
# cap stops an address that never ends, like /dev/zero, from filling the
# cache. Every media surface fetches into the same folder, so each download
# writes under a name of its own and only appears there once it is whole.
[ -f "$1" ] && exit 0
t="$1.part.$$"
stop() { kill $(jobs -p) 2>/dev/null; wait; rm -f "$t"; exit 143; }
trap stop TERM
curl -4 -fsSL -g --proto "=$3" --max-time 20 --max-filesize 20000000 --create-dirs -o "$t" -- "$2" &
wait $! && mv -f "$t" "$1"
s=$?
rm -f "$t"
exit $s
