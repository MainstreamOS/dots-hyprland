#!/usr/bin/env bash
# app-remover.test.sh: what Uninstall Apps refuses to remove, run against a stand-in
# pacman that only records what it is asked. Nothing is installed or removed.
# Run: bash sdata/tests/app-remover.test.sh   (exit 0 = all green)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMOVER="$ROOT/sdata/polkit/app-remover"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILS=0; CASES=0
chk() { CASES=$((CASES + 1)); if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }

# Every package counts as installed and as taking only itself with it, unless CASCADE
# names what removing it would take. No group or meta package is installed, so the
# denylist alone protects.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/pacman" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1" in
  -Qq)  [[ "${2:-}" == -- ]] && { printf '%s\n' "$3"; exit 0; }; exit 1 ;;
  -Rs)  if [[ -n "${CASCADE:-}" ]]; then printf '%s\n' $CASCADE; else printf '%s\n' "${@: -1}"; fi ;;
  -Rns) exit 0 ;;
  *)    exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/pacman"

# Runs the remover; prints its exit code and whether pacman was asked to remove anything.
run() {
  : > "$WORK/calls"
  local rc=0
  CALLS="$WORK/calls" PATH="$WORK/bin:/usr/bin:/bin" bash "$REMOVER" "$@" > "$WORK/out" 2>&1 || rc=$?
  if grep -q '^-Rns' "$WORK/calls"; then printf '%s removed' "$rc"; else printf '%s kept' "$rc"; fi
}

for pkg in linux linux-headers linux-mainstream linux-mainstream-headers \
           linux-mainstream-performance linux-mainstream-performance-headers \
           nvidia-open nvidia-open-dkms dkms nvidia-utils; do
  chk "remove $pkg"  "$(run remove "$pkg")" "22 kept"
  chk "remove $pkg says why" "$(grep -c 'is a protected system component' "$WORK/out")" 1
  chk "preview $pkg" "$(run preview "$pkg")" "22 kept"
done

# An app whose removal would take a kernel or the DKMS driver with it is refused too.
chk "cascade takes the Mainstream headers" "$(CASCADE="some-app linux-mainstream-headers" run remove some-app)" "22 kept"
chk "cascade names what it would take" "$(grep -c 'removal would affect protected packages: linux-mainstream-headers' "$WORK/out")" 1
chk "cascade takes the DKMS driver" "$(CASCADE="some-app nvidia-open-dkms dkms" run remove some-app)" "22 kept"

# An ordinary app is removed.
chk "an app is removed" "$(run remove vlc)" "0 removed"
chk "the app alone is removed" "$(grep '^-Rns' "$WORK/calls")" "-Rns --noconfirm -- vlc"

echo "app-remover: $CASES cases, $FAILS failed"
[[ $FAILS -eq 0 ]]
