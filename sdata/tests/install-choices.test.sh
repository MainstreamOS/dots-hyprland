#!/usr/bin/env bash
# install-choices.test.sh: the Custom install flags, choosers, catalog choice items and app source swap.
# Run: bash sdata/tests/install-choices.test.sh   (exit 0 = all green)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILS=0; CASES=0
chk() { CASES=$((CASES + 1)); if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }

printf 'flags\t\t: fpu avx avx2 bmi1 bmi2 f16c fma movbe xsave abm\n' > "$WORK/v3"
printf 'flags\t\t: fpu avx avx2 bmi1 bmi2 f16c fma movbe xsave lzcnt\n' > "$WORK/v3-lzcnt"
printf 'flags\t\t: fpu avx avx2 bmi1 bmi2 f16c fma xsave abm\n' > "$WORK/no-movbe"
printf 'flags\t\t: fpu avx avx2 bmi1 bmi2 f16c fma movbe xsave\n' > "$WORK/no-abm"

# A catalog with the real optional groups and two default apps.
REPO="$WORK/repo"
mkdir -p "$REPO/sdata/dist-arch/mainstream-extras" "$REPO/sdata/subcmd-install"
cp "$ROOT/sdata/subcmd-install/optional-apps.conf" "$REPO/sdata/subcmd-install/"
cat > "$REPO/sdata/dist-arch/mainstream-extras/default-apps.list" <<'LIST'
MAINSTREAM_DEFAULT_APPS=(
  "mpv|mpv|Media player"
  "gimp|GIMP|Image editor"
)
LIST

# Runs options.sh as ./setup would, with the profile step reporting the result.
# Input comes from /dev/null unless TEST_TTY is set, so the choosers see no terminal.
report() {
  printf '%s|%s|%s|%s|%s' "$MS_INSTALL_PROFILE" "${MS_INSTALL_APP_SOURCE-unset}" \
    "${MS_INSTALL_KERNELS-unset}" "${MS_INSTALL_PROTONS-unset}" "${MS_SELECTED_APPS[*]-}"
}
setup_env() {
  source "$ROOT/sdata/lib/functions.sh"
  source "$ROOT/sdata/subcmd-install/profiles.sh"
  REPO_ROOT="$REPO" SUBCMD_NAME=install OS_GROUP_ID=arch
  eval "$(declare -f cpu_runs_x86_64_v3 | sed '1s/cpu_runs_x86_64_v3/real_cpu_runs_x86_64_v3/')"
  cpu_runs_x86_64_v3() { real_cpu_runs_x86_64_v3 "$TEST_CPU"; }
}
opts() {
  ( setup_env; source "$ROOT/sdata/subcmd-install/options.sh" "$@" || exit $?; report ) </dev/null 2>"$WORK/err"
}
# The choosers with a terminal: $1 is the typed input, the rest are flags.
typed() {
  local input=$1; shift
  ( setup_env
    # Pretend stdin and stdout are a terminal for the choosers alone.
    eval "$(declare -f choose_install_kernel choose_install_apps _choose_install_option | sed 's/\[\[ ! -t 0 || ! -t 1 \]\]/false/')"
    source "$ROOT/sdata/subcmd-install/options.sh" "$@" || exit $?
    report ) <<<"$input" 2>"$WORK/err" | tail -1 | sed 's/^.*Choice \[1\]: //; s/^.*Kernels \[1\]: //; s/^.*continue: //'
}
_v3() { (source "$ROOT/sdata/lib/functions.sh"; cpu_runs_x86_64_v3 "$1"); }

for f in v3 v3-lzcnt; do _v3 "$WORK/$f"; chk "cpu $f" $? 0; done
for f in no-movbe no-abm missing; do _v3 "$WORK/$f"; chk "cpu $f" $? 1; done

TEST_CPU="$WORK/v3"

# Catalog: choice items carry their preselection, and --list-apps leaves them out.
catalog=$( (setup_env; install_app_catalog --groups) )
chk "proton items in Gaming" "$(grep -c $'^proton:[a-z]*\t[^\t]*\t[a-z]*\tGaming$' <<<"$catalog")" 3
chk "proton:mainstream preselected" "$(grep $'^proton:mainstream\t' <<<"$catalog" | cut -f3)" default
chk "proton:ge not preselected" "$(grep $'^proton:ge\t' <<<"$catalog" | cut -f3)" optional
chk "proton items last in Gaming" "$(grep $'\tGaming$' <<<"$catalog" | tail -3 | cut -f1 | tr '\n' ' ')" \
  "proton:mainstream proton:ge proton:cachyos "
chk "ordinary items stay optional" "$(grep $'^steam\t' <<<"$catalog" | cut -f3)" optional
chk "default apps stay default" "$(grep -c $'\tdefault\tDefault apps$' <<<"$catalog")" 2
listed=$( (setup_env; source "$ROOT/sdata/subcmd-install/options.sh" --list-apps) 2>&1 )
chk "--list-apps has no choice items" "$(grep -c ':' <<<"$listed")" 0
chk "--list-apps has apps" "$(grep -c $'^steam\t' <<<"$listed")" 1

# Flags.
apps=(--apps steam,org.gimp.GIMP)
chk "custom defaults without a terminal" "$(opts --profile custom "${apps[@]}")" \
  "custom||mainstream|mainstream|steam org.gimp.GIMP"
chk "no terminal kernel message" "$(grep -c 'No terminal: using --kernel mainstream' "$WORK/err")" 1
chk "no terminal app source message" "$(grep -c 'No terminal: apps install as listed' "$WORK/err")" 1
chk "kernel and proton lists ordered" \
  "$(opts --profile custom --kernel linux,mainstream-performance,mainstream --proton cachyos,mainstream,ge "${apps[@]}")" \
  "custom||mainstream-performance mainstream linux|mainstream ge cachyos|steam org.gimp.GIMP"
chk "repeated values once" "$(opts --profile custom --kernel linux,linux --proton ge,ge "${apps[@]}")" \
  "custom||linux|ge|steam org.gimp.GIMP"
chk "proton none" "$(opts --profile custom --proton none "${apps[@]}")" \
  "custom||mainstream||steam org.gimp.GIMP"
TEST_CPU="$WORK/no-movbe"
chk "performance becomes mainstream on an older CPU" \
  "$(opts --profile custom --kernel mainstream-performance,linux "${apps[@]}")" \
  "custom||mainstream linux|mainstream|steam org.gimp.GIMP"
chk "refusal explained" "$(grep -c 'does not support x86-64-v3' "$WORK/err")" 1
chk "performance and mainstream on an older CPU" \
  "$(opts --profile custom --kernel mainstream-performance,mainstream "${apps[@]}")" \
  "custom||mainstream|mainstream|steam org.gimp.GIMP"
TEST_CPU="$WORK/v3"

chk "old kernel names are today's" \
  "$(opts --profile custom --kernel linux,linux-mainstream-performance,linux-mainstream "${apps[@]}")" \
  "custom||mainstream-performance mainstream linux|mainstream|steam org.gimp.GIMP"
chk "an old name beside today's counts once" "$(opts --profile custom --kernel mainstream,linux-mainstream "${apps[@]}")" \
  "custom||mainstream|mainstream|steam org.gimp.GIMP"
opts --profile custom --kernel linux-mainstream-performance-eac "${apps[@]}" >/dev/null; chk "a kernel never offered stays unknown" $? 1
opts --profile custom --kernel mainstream-system "${apps[@]}" >/dev/null; chk "another Mainstream package is no kernel" $? 1
opts --profile custom --kernel ,linux "${apps[@]}" >/dev/null; chk "a leading empty kernel item refused" $? 1

opts --profile default --kernel linux >/dev/null; chk "kernel needs custom" $? 1
chk "kernel needs custom message" "$(cat "$WORK/err")" "--kernel requires --profile custom."
opts --proton ge >/dev/null; chk "proton needs custom" $? 1
opts --profile custom --kernel bogus "${apps[@]}" >/dev/null; chk "unknown kernel" $? 1
chk "unknown kernel message" "$(grep -c "Unknown --kernel value bogus" "$WORK/err")" 1
opts --profile custom --kernel none "${apps[@]}" >/dev/null; chk "kernel none refused" $? 1
opts --profile custom --kernel '' "${apps[@]}" >/dev/null; chk "empty kernel refused" $? 1
opts --profile custom --kernel linux,,mainstream "${apps[@]}" >/dev/null; chk "empty kernel item refused" $? 1
opts --profile custom --app-source snap "${apps[@]}" >/dev/null; chk "unknown app source" $? 1
opts --profile custom --proton steam "${apps[@]}" >/dev/null; chk "unknown proton" $? 1
chk "unknown proton message" "$(grep -c "Unknown --proton value steam. Choose from mainstream,ge,cachyos, or none." "$WORK/err")" 1
opts --profile custom --proton none,ge "${apps[@]}" >/dev/null; chk "none mixed with a proton refused" $? 1
opts --profile custom --apps steam,proton:ge >/dev/null; chk "proton in --apps refused" $? 1
chk "proton in --apps message" "$(grep -c 'Choose Proton with --proton' "$WORK/err")" 1
chk "other profiles leave the choices unset" \
  "$(MS_INSTALL_KERNELS=linux MS_INSTALL_PROTONS=ge opts --profile default)" "default|unset|unset|unset|"
chk "environment never sets the choices" \
  "$(MS_INSTALL_KERNELS=linux MS_INSTALL_PROTONS=ge opts --profile custom "${apps[@]}")" \
  "custom||mainstream|mainstream|steam org.gimp.GIMP"

# The choosers with a terminal.
chk "typed kernels" "$(typed $'\n1 2 3\n\n' --profile custom)" \
  "custom|native|mainstream-performance mainstream linux|mainstream|mpv gimp"
chk "kernel default" "$(typed $'\n\n\n' --profile custom)" "custom|native|mainstream|mainstream|mpv gimp"
chk "bad kernel number asks again" "$(typed $'\n4\n3\n\n' --profile custom)" "custom|native|linux|mainstream|mpv gimp"
TEST_CPU="$WORK/no-movbe"
chk "typed performance on an older CPU" "$(typed $'\n2\n\n' --profile custom)" \
  "custom|native|mainstream|mainstream|mpv gimp"
TEST_CPU="$WORK/v3"
# The picker numbers the 2 default apps first; find the Proton items' numbers.
picker=$( (setup_env; install_app_catalog) | awk -F'\t' '!seen[$1]++ {print NR - 0 "\t" $1}')
num() { awk -F'\t' -v id="$1" '$2 == id {print $1}' <<<"$picker"; }
chk "picker toggles protons" "$(typed $'\n\n'"$(num proton:mainstream) $(num proton:cachyos) $(num proton:ge)"$'\n\n' --profile custom)" \
  "custom|native|mainstream|ge cachyos|mpv gimp"
chk "picker can drop every proton" "$(typed $'\n\n'"$(num proton:mainstream)"$'\n\n' --profile custom)" \
  "custom|native|mainstream||mpv gimp"
chk "--proton preselects the picker" "$(typed $'\n\n'"$(num steam)"$'\n\n' --profile custom --proton ge,cachyos)" \
  "custom|native|mainstream|ge cachyos|mpv gimp steam"

# The swap, with and without the pairs file. A scripted run without
# --app-source keeps its --apps as listed even when pairs exist.
chk "flatpak without a pairs file" "$(opts --profile custom --app-source flatpak --kernel linux --proton ge "${apps[@]}")" \
  "custom|flatpak|linux|ge|steam org.gimp.GIMP"
cat > "$REPO/sdata/dist-arch/mainstream-extras/app-variants.list" <<'LIST'
# native|flatpak
chromium|org.chromium.Chromium
gimp|org.gimp.GIMP   # trailing comment

krita|org.kde.krita
LIST
chk "flatpak swaps native apps" "$(opts --profile custom --app-source flatpak --apps chromium,steam,org.gimp.GIMP)" \
  "custom|flatpak|mainstream|mainstream|org.chromium.Chromium steam org.gimp.GIMP"
chk "native swaps flatpak apps" "$(opts --profile custom --app-source native "${apps[@]}")" \
  "custom|native|mainstream|mainstream|steam gimp"
chk "a swap never lists an app twice" "$(opts --profile custom --app-source native --apps gimp,org.gimp.GIMP)" \
  "custom|native|mainstream|mainstream|gimp"
chk "no --app-source keeps --apps as listed" "$(opts --profile custom --apps chromium,org.gimp.GIMP)" \
  "custom||mainstream|mainstream|chromium org.gimp.GIMP"
swapped() {
  ( setup_env; source "$ROOT/sdata/subcmd-install/options.sh" "$@" || exit $?; printf '%s' "${MS_SWAPPED_FLATPAKS[*]-}" ) </dev/null 2>"$WORK/err"
}
chk "only swapped-in Flatpaks may fall back to native" \
  "$(swapped --profile custom --app-source flatpak --apps chromium,steam,org.gimp.GIMP)" "org.chromium.Chromium"
chk "native source swaps in no Flatpak" "$(swapped --profile custom --app-source native --apps org.gimp.GIMP)" ""

# setup_mainstream_kernel on a first install, with the installed kernels as $1, the choices as $2 and
# a stand-in pacman. Prints the kernels it added, then the boot default it picked.
kernel_step() {
  (
    source "$ROOT/sdata/subcmd-install/profiles.sh"
    eval "$(sed -n '/^function setup_mainstream_kernel(){/,/^}/p; /^function _installed_kernel_package(){/,/^}/p' "$ROOT/sdata/subcmd-install/2.setups.sh")"
    OS_GROUP_ID=arch INSTALL_FIRSTRUN=true MAINSTREAM_KERNEL_CHOICES=$2 MAINSTREAM_KERNEL="" STY_BLUE="" STY_YELLOW="" STY_RST=""
    INSTALLED=" $1 "
    pacman() { [[ $1 == -Qq && $INSTALLED == *" $2 "* ]] && echo "$2"; }
    cpu_runs_x86_64_v3() { true; }
    gpu_kernel_nvidia_ready() { true; }
    _add_mainstream_kernel() { printf '+%s ' "$1"; }
    setup_mainstream_kernel >"$WORK/kernel-step" 2>/dev/null
    printf '%s|%s' "$(grep -o '+[^ ]*' "$WORK/kernel-step" | tr '\n' ' ')" "$MAINSTREAM_KERNEL"
  )
}
chk "Arch's kernel: Mainstream is added beside it" "$(kernel_step linux mainstream)" "+mainstream |mainstream"
chk "Mainstream only: the installed kernel stays the default" "$(kernel_step mainstream mainstream)" "|mainstream"
chk "Mainstream only: performance is added beside it" \
  "$(kernel_step mainstream "mainstream-performance mainstream")" \
  "+mainstream-performance |mainstream-performance"
chk "another kernel only: nothing is added" "$(kernel_step linux-zen mainstream)" "|"
chk "linux-t2 only: nothing is added" "$(kernel_step linux-t2 mainstream)" "|"
chk "old name installed: it stays the default under that name" "$(kernel_step linux-mainstream mainstream)" "|linux-mainstream"
chk "old name installed: performance is added beside it" \
  "$(kernel_step "linux linux-mainstream" "mainstream-performance mainstream")" "+mainstream-performance |mainstream-performance"
chk "old performance name installed: it is the default" \
  "$(kernel_step "linux linux-mainstream-performance" "mainstream-performance mainstream")" "+mainstream |linux-mainstream-performance"

# _add_mainstream_kernel against the repositories in $1; prints what pacman was asked to install.
add_step() {
  (
    source "$ROOT/sdata/subcmd-install/profiles.sh"
    eval "$(sed -n '/^function _add_mainstream_kernel(){/,/^}/p' "$ROOT/sdata/subcmd-install/2.setups.sh")"
    STY_BLUE="" STY_YELLOW="" STY_CYAN="" STY_RST="" MAINSTREAM_KERNEL_MIN_FREE_MIB=1 GPU_FAILURES=()
    REPO=" $1 "
    pacman() { [[ $1 == -Si && $REPO == *" $2 "* ]]; }
    sudo() { shift; printf '%s ' "$@"; }
    bootctl() { echo /; }
    df() { printf 'x\nx 1 1 999\n'; }
    gpu_detect() { return 1; }
    gpu_kernel_nvidia_ready() { true; }
    _add_mainstream_kernel "$2" 2>/dev/null | grep -o -- '-S --needed --noconfirm.*' | sed 's/ *$//'
  )
}
chk "today's name is added when the repositories carry it" \
  "$(add_step "mainstream mainstream-headers linux-mainstream linux-mainstream-headers" mainstream)" \
  "-S --needed --noconfirm mainstream mainstream-headers"
chk "the old name is added while the repositories carry only that" \
  "$(add_step "linux-mainstream linux-mainstream-headers" mainstream)" \
  "-S --needed --noconfirm linux-mainstream linux-mainstream-headers"
chk "nothing is added when neither is offered with its headers" "$(add_step "mainstream linux-mainstream" mainstream)" ""

echo "install-choices: $((CASES - FAILS))/$CASES passed"
(( FAILS == 0 ))
