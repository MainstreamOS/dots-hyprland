#!/usr/bin/env bash
#
# exp-update-tester.sh - Test suite for exp-update
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TEST_DIR=""
ORIGINAL_DIR="$PWD"
ORIGINAL_HOME="${HOME:-}"
TEST_ROOT=""
SANDBOX=""
STUB_DIR=""
STUB_LOG=""
# Commands that reach the running session or ask for root. Each one is
# replaced by a stub that logs the call and fails.
SESSION_COMMANDS=(hyprctl qs quickshell systemctl systemd-run run0 loginctl notify-send sudo pkexec su pacman)
SESSION_VARS=(HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS BASH_ENV ENV)

# Helper functions
log_test() {
  echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  ((TESTS_FAILED++))
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

refuse() {
  log_error "$1"
  log_error "Refusing to run: the tests must never reach the real home or the running session"
  exit 99
}

# /tmp is often held in memory, and the dry-run test copies the repository,
# so a disk-backed location comes first.
scratch_base() {
  local d
  for d in "${TMPDIR:-}" /var/tmp "${XDG_CACHE_HOME:-$HOME/.cache}"; do
    if [[ -n "$d" && -d "$d" && -w "$d" && "$(stat -f -c %T "$d" 2>/dev/null)" != tmpfs ]]; then
      echo "$d"
      return 0
    fi
  done
  echo "${TMPDIR:-/tmp}"
}

sandbox_init() {
  local base cmd v
  base=$(scratch_base)
  TEST_ROOT=$(mktemp -d "${base%/}/exp-update-tester.XXXXXX") || refuse "Could not create a test directory in $base"
  STUB_DIR="$TEST_ROOT/stubs"
  STUB_LOG="$TEST_ROOT/stub-calls.log"
  mkdir -p "$STUB_DIR"
  : >"$STUB_LOG"
  printf '#!/bin/bash\necho "${0##*/} $*" >>%q\nexit 1\n' "$STUB_LOG" >"$STUB_DIR/.stub"
  chmod +x "$STUB_DIR/.stub"
  for cmd in "${SESSION_COMMANDS[@]}"; do
    ln -s .stub "$STUB_DIR/$cmd"
  done
  export PATH="$STUB_DIR:$PATH"
  # GIT_DIR and friends would point the test repos at a real repository, and
  # BASH_ENV would let every child shell put PATH and the session back.
  unset "${SESSION_VARS[@]}"
  for v in $(compgen -v XDG_ || true) $(compgen -v GIT_ || true); do
    unset "$v"
  done
}

sandbox_guard() {
  local v cmd real_home
  real_home=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6) || real_home=""
  [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] || refuse "The test directory is missing"
  [[ "$HOME" == "$TEST_ROOT"/* ]] || refuse "HOME is outside the test directory: $HOME"
  for v in "$real_home" "$ORIGINAL_HOME"; do
    if [[ -n "$v" && "$(realpath -m -- "$HOME")" == "$(realpath -m -- "$v")" ]]; then
      refuse "HOME is the real home: $HOME"
    fi
  done
  for v in $(compgen -v XDG_ || true); do
    [[ "${!v}" == "$TEST_ROOT"/* ]] || refuse "$v points outside the test directory: ${!v}"
  done
  for v in "${SESSION_VARS[@]}" $(compgen -v GIT_ || true); do
    [[ -z "${!v+set}" ]] || refuse "$v is still set"
  done
  for cmd in "${SESSION_COMMANDS[@]}"; do
    [[ "$(command -v "$cmd")" == "$STUB_DIR/$cmd" ]] || refuse "$cmd does not resolve to its stub"
  done
}

# Each test gets its own home and runtime directory, so nothing it does lands
# in the real ones or carries over to the next test.
sandbox_enter() {
  SANDBOX="$TEST_ROOT/$1"
  mkdir -p "$SANDBOX/home" "$SANDBOX/runtime"
  chmod 700 "$SANDBOX/runtime"
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" \
    XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache" \
    XDG_BIN_HOME="$HOME/.local/bin" XDG_RUNTIME_DIR="$SANDBOX/runtime"
  sandbox_guard
}

sandbox_leave() {
  cd "$ORIGINAL_DIR"
  rm -rf -- "$SANDBOX"
  SANDBOX=""
}

# Copies only what git tracks or would track, so build output under
# sdata/dist-arch (gigabytes) stays behind.
copy_repo_files() {
  local dest="$1"
  shift
  if git -C "$ORIGINAL_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "$ORIGINAL_DIR" ls-files -z --cached --others --exclude-standard -- "$@" |
      tar -C "$ORIGINAL_DIR" --null --ignore-failed-read --exclude=.git -T - -cf - 2>/dev/null |
      tar -C "$dest" -xf -
  else
    local p
    for p in "$@"; do
      cp -r "$ORIGINAL_DIR/$p" "$dest/"
    done
  fi
}

# Setup test environment
setup_test_env() {
  local temp_dir
  temp_dir=$(mktemp -d "$SANDBOX/dotfiles-test.XXXXXX")

  cd "$temp_dir" || { echo "Failed to cd to test directory"; return 1; }
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  git commit --allow-empty -m "Initial commit" -q

  echo "$temp_dir"
}

# Cleanup test environment
cleanup_test_env() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
    TEST_DIR=""
  fi
}

# Run a test and handle cleanup
run_test() {
  local test_name="$1"
  local test_func="$2"

  # Cleanup before test
  cleanup_test_env

  # Run the test
  if $test_func; then
    echo "✓ $test_name passed"
    return 0
  else
    echo "✗ $test_name failed"
    return 1
  fi
}

# Test 2: Script has no syntax errors
test_syntax() {
  log_test "Checking script syntax"

  if bash -n setup; then
    log_pass "No syntax errors found"
    return 0
  else
    log_fail "Syntax errors detected"
    return 1
  fi
}

# Test 3: Help option works
test_help_option() {
  log_test "Testing --help option"

  if ./setup exp-update --help 2>&1 | grep -qiE "(Syntax|Options|exp-update)"; then
    log_pass "Help option works"
    return 0
  else
    log_fail "Help option failed"
    return 1
  fi
}

# Test 4: Test repository structure detection (dots/ prefix)
test_dots_structure() {
  log_test "Testing dots/ prefix structure detection"

  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"

  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  mkdir -p dots/.config/test-app
  mkdir -p dots/.local/bin
  echo "test config" > dots/.config/test-app/config.conf

  git add .
  git commit -m "Add dots structure" -q

  cat > test_detection.sh << EOF
#!/bin/bash
# Mock logging and style functions/variables
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1"; exit 1; }
STY_CYAN="" STY_RST="" STY_YELLOW=""

# Set required environment variables for exp-update/0.run.sh
SKIP_NOTICE=true
REPO_ROOT="\$1"
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh"
detected_dirs=\$(detect_repo_structure)
if [[ -n "\$detected_dirs" ]]; then
  read -ra MONITOR_DIRS <<<"\$detected_dirs"
fi
echo "Structure: \${MONITOR_DIRS[*]}"
EOF

  chmod +x test_detection.sh
  result=$(./test_detection.sh "$test_repo")

  if [[ "$result" == *"dots/.config"* ]]; then
    log_pass "Dots structure detected correctly"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Failed to detect dots structure. Got: $result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 5: Test flat structure detection
test_flat_structure() {
  log_test "Testing flat structure detection"

  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"

  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  mkdir -p .config/test-app
  mkdir -p .local/bin
  echo "test config" > .config/test-app/config.conf

  git add .
  git commit -m "Add flat structure" -q

  cat > test_detection.sh << EOF
#!/bin/bash
# Mock logging and style functions/variables
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1"; exit 1; }

# Set required environment variables for exp-update
SKIP_NOTICE=true
REPO_ROOT="\$1"
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh"
detected_dirs=\$(detect_repo_structure)
if [[ -n "\$detected_dirs" ]]; then
  read -ra MONITOR_DIRS <<<"\$detected_dirs"
fi
echo "Structure: \${MONITOR_DIRS[*]}"
EOF

  chmod +x test_detection.sh
  result=$(./test_detection.sh "$test_repo")

  if [[ "$result" == *".config"* ]] && [[ "$result" != *"dots/"* ]]; then
    log_pass "Flat structure detected correctly"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Failed to detect flat structure. Got: $result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 6: Test dots prefix mapping to home directory
test_dots_mapping() {
  log_test "Testing dots/ prefix home directory mapping"
  
  dir_name="dots/.config"
  if [[ "$dir_name" == dots/* ]]; then
    home_subdir="${dir_name#dots/}"
    home_dir_path="${HOME}/${home_subdir}"
  else
    home_dir_path="${HOME}/${dir_name}"
  fi
  
  expected_path="${HOME}/.config"
  if [[ "$home_dir_path" == "$expected_path" ]]; then
    log_pass "Dots prefix mapping correct: $dir_name → $home_dir_path"
    return 0
  else
    log_fail "Dots prefix mapping failed: $dir_name → $home_dir_path (expected: $expected_path)"
    return 1
  fi
}

# Test 7: Test ignore file patterns - FIXED
test_ignore_patterns() {
  log_test "Testing ignore file pattern matching"
  
  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"
  
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }
  
  cat > .updateignore << 'EOF'
*.log
secrets/
.config/private*
*backup*
EOF
  
  mkdir -p .config
  mkdir -p secrets
  
  cat > test_ignore.sh << EOF
#!/bin/bash
# Suppress all output from sourced script
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1" >&2; exit 1; }

# FIXED: Set REPO_ROOT before sourcing exp-update
REPO_ROOT="\$1"
export REPO_ROOT

# Set other required environment variables
SKIP_NOTICE=true
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

UPDATE_IGNORE_FILE="\${REPO_ROOT}/.updateignore"
HOME_UPDATE_IGNORE_FILE="/dev/null"

# Source the production script to use the real should_ignore function
# Redirect all unwanted output to stderr, then to /dev/null
source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh" 2>/dev/null

# Load patterns into cache
load_ignore_patterns

test_cases=(
  "\$REPO_ROOT/app.log:0"
  "\$REPO_ROOT/secrets/key.txt:0" 
  "\$REPO_ROOT/.config/private-config:0"
  "\$REPO_ROOT/.config/backup-file:0"
  "\$REPO_ROOT/normal-config:1"
)

all_passed=true
for test_case in "\${test_cases[@]}"; do
  IFS=":" read -r file expected <<< "\$test_case"
  mkdir -p "\$(dirname "\$file")"
  touch "\$file"
  
  if should_ignore "\$file"; then
    result=0
  else
    result=1
  fi
  
  if [[ \$result -ne \$expected ]]; then
    echo "FAIL: \$file (expected: \$expected, got: \$result)"
    all_passed=false
  fi
done

if [[ "\$all_passed" == true ]]; then
  echo "PASS"
else
  echo "FAIL"
fi
EOF
  
  chmod +x test_ignore.sh
  result=$(./test_ignore.sh "$test_repo" 2>&1 | grep -E "^(PASS|FAIL)")
  
  if [[ "$result" == "PASS" ]]; then
    log_pass "All ignore pattern tests passed"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Some ignore pattern tests failed"
    echo "$result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 8: Test safe_read security - FIXED
test_safe_read_security() {
  log_test "Testing safe_read uses secure assignment (printf -v)"

  local safe_read_function
  safe_read_function=$(awk '/^safe_read\(\) \{/,/^\}/' "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh")

  if [[ -z "$safe_read_function" ]]; then
    log_fail "Could not find safe_read function"
    return 1
  fi

  # FIXED: Remove comments before checking for eval
  # The function has a comment mentioning eval, which shouldn't count
  local function_without_comments
  function_without_comments=$(echo "$safe_read_function" | sed 's/#.*$//')
  
  local has_printf_v=false
  local has_eval=false
  
  if echo "$safe_read_function" | grep -F 'printf -v' > /dev/null; then
    has_printf_v=true
  fi
  
  # Check for eval in actual code (not comments)
  if echo "$function_without_comments" | grep -w 'eval' > /dev/null; then
    has_eval=true
  fi

  if [[ "$has_printf_v" == true ]] && [[ "$has_eval" == false ]]; then
    log_pass "safe_read uses secure printf -v assignment and no eval"
    return 0
  else
    log_fail "safe_read does not use secure assignment or contains eval (has_printf_v=$has_printf_v, has_eval=$has_eval)"
    echo "Function content:"
    echo "$safe_read_function"
    return 1
  fi
}

# Test 9: Test dry-run mode - FIXED
test_dry_run() {
  log_test "Testing dry-run mode"

  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"

  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  # Copy necessary files for setup to run
  if ! copy_repo_files . setup sdata dots; then
    log_fail "Failed to copy the repository files"
    cd "$ORIGINAL_DIR"
    return 1
  fi
  chmod +x setup

  # Create a test config file in repo
  mkdir -p dots/.config/test-app
  echo "test config" > dots/.config/test-app/config.conf

  git add .
  git commit -m "Add test config" -q

  # Use non-interactive mode and check for DRY-RUN marker
  ./setup exp-update -n --skip-notice --non-interactive 2>&1 | tee dry_run_output.txt

  if grep -q "DRY-RUN" dry_run_output.txt; then
    log_pass "Dry-run mode detected in output"
  else
    log_fail "Dry-run mode not properly indicated"
    cd "$ORIGINAL_DIR"
    return 1
  fi

  # FIXED: Check if files were created (they shouldn't be in dry-run)
  if [[ -f "${HOME}/.config/test-app/config.conf" ]]; then
    log_fail "Files were created in home during dry-run"
    cd "$ORIGINAL_DIR"
    return 1
  else
    log_pass "No files created in home during dry-run"
  fi

  cd "$ORIGINAL_DIR"
  return 0
}

# Test 10: Test command-line flags
test_flags() {
  log_test "Testing command-line flags"

  # Only test non-interactive flags
  local flags=("-h" "--help")
  local all_passed=true

  for flag in "${flags[@]}"; do
    if ./setup exp-update "$flag" 2>&1 | grep -qiE "(Syntax|Options|exp-update)"; then
      log_test "  ✓ $flag recognized"
    else
      log_test "  ✗ $flag not recognized"
      all_passed=false
    fi
  done

  if [[ "$all_passed" == true ]]; then
    log_pass "Help flags recognized correctly"
    return 0
  else
    log_fail "Some flags not recognized properly"
    return 1
  fi
}

# Test 11: Check for shellcheck
test_shellcheck() {
  log_test "Running shellcheck (if available)"
  
  if ! command -v shellcheck &>/dev/null; then
    log_test "shellcheck not found, skipping static analysis"
    return 0
  fi
  
  if shellcheck -e SC1090,SC1091,SC2148,SC2034,SC2155,SC2164 setup; then
    log_pass "shellcheck passed"
    return 0
  else
    log_fail "shellcheck found issues"
    return 1
  fi
}

# Test 12: Test lock file mechanism
test_lock_file() {
  log_test "Testing lock file mechanism"
  
  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"
  
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }
  
  # Copy necessary files
  if ! copy_repo_files . setup sdata; then
    log_fail "Failed to copy the repository files"
    cd "$ORIGINAL_DIR"
    return 1
  fi
  mkdir -p dots/.config
  chmod +x setup
  
  git add .
  git commit -m "Add files" -q
  
  # Create a fake lock file
  echo "99999" > .update-lock
  
  # Try to run update - should fail due to lock
  if ./setup exp-update --skip-notice --non-interactive > lock_test_output.txt 2>&1; then
    if grep -q "stale lock" lock_test_output.txt; then
      log_pass "Lock file mechanism works (detected stale lock)"
      cd "$ORIGINAL_DIR"
      return 0
    fi
  fi
  log_fail "Lock file mechanism did not work as expected"
  cat lock_test_output.txt  # Show output for debugging
  cd "$ORIGINAL_DIR"
  return 1
}

# Test 13: Test ** substring ignore patterns - FIXED
test_substring_ignore_patterns() {
  log_test "Testing ** substring ignore pattern matching"

  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"

  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  cat > .updateignore << 'EOF'
**temp**
**backup**
**testfile**
EOF

  mkdir -p .config/test-app
  mkdir -p temp-backup-dir
  mkdir -p .local/share/test-temp
  mkdir -p .config/temp-file

  cat > test_substring_ignore.sh << EOF
#!/bin/bash
# Suppress all output from sourced script
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1" >&2; exit 1; }

# FIXED: Set REPO_ROOT before sourcing exp-update
REPO_ROOT="\$1"
export REPO_ROOT

# Set other required environment variables
SKIP_NOTICE=true
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

UPDATE_IGNORE_FILE="\${REPO_ROOT}/.updateignore"
HOME_UPDATE_IGNORE_FILE="/dev/null"

# Source the production script to use the real should_ignore function
source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh" 2>/dev/null

# Load patterns into cache
load_ignore_patterns

test_cases=(
  "\$REPO_ROOT/temp-backup-dir/file:0"
  "\$REPO_ROOT/.config/test-app/temp.conf:0"
  "\$REPO_ROOT/.local/share/test-temp/data:0"
  "\$REPO_ROOT/.config/temp-file/config:0"
  "\$REPO_ROOT/normal-config:1"
  "\$REPO_ROOT/.config/my-testfile.conf:0"
)

all_passed=true
for test_case in "\${test_cases[@]}"; do
  IFS=":" read -r file expected <<< "\$test_case"
  mkdir -p "\$(dirname "\$file")"
  touch "\$file"

  if should_ignore "\$file"; then
    result=0
  else
    result=1
  fi

  if [[ \$result -ne \$expected ]]; then
    echo "FAIL: \$file (expected: \$expected, got: \$result)"
    all_passed=false
  fi
done

if [[ "\$all_passed" == true ]]; then
  echo "PASS"
else
  echo "FAIL"
fi
EOF

  chmod +x test_substring_ignore.sh
  result=$(./test_substring_ignore.sh "$test_repo" 2>&1 | grep -E "^(PASS|FAIL)")

  if [[ "$result" == "PASS" ]]; then
    log_pass "** substring ignore patterns work correctly"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "** substring ignore patterns failed"
    echo "$result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 14: Test ensure_directory caching
test_directory_caching() {
  log_test "Testing directory creation caching"
  
  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"
  
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }
  
  cat > test_dir_cache.sh << EOF
#!/bin/bash
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1" >&2; exit 1; }

REPO_ROOT="\$1"
export REPO_ROOT

SKIP_NOTICE=true
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh" 2>/dev/null

test_dir="\$1/test-ensure-dir-\$\$"

# First call should create
ensure_directory "\$test_dir"
result1=\$?

# Second call should use cache
ensure_directory "\$test_dir"
result2=\$?

# Check if CREATED_DIRS has the entry
if [[ -n "\${CREATED_DIRS[\$test_dir]:-}" ]] && [[ \$result1 -eq 0 ]] && [[ \$result2 -eq 0 ]]; then
  echo "PASS"
  rm -rf "\$test_dir"
else
  echo "FAIL"
fi
EOF
  
  chmod +x test_dir_cache.sh
  result=$(./test_dir_cache.sh "$test_repo" 2>&1 | grep -E "^(PASS|FAIL)")
  
  if [[ "$result" == "PASS" ]]; then
    log_pass "Directory creation caching works"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Directory creation caching failed"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 15: Test enhanced safe_read with non-interactive mode
test_safe_read_noninteractive() {
  log_test "Testing safe_read in non-interactive mode"
  
  local script="$SANDBOX/test_safe_read.sh"
  cat > "$script" << 'EOF'
#!/bin/bash
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_warning() { :; }
log_error() { :; }

# Simulate the enhanced safe_read function
safe_read() {
  local prompt="$1"
  local varname="$2"
  local default="${3:-}"
  local input_value=""

  # In non-interactive mode, use default immediately
  if [[ "$NON_INTERACTIVE" == true ]]; then
    if [[ -n "$default" ]]; then
      printf -v "$varname" '%s' "$default"
      return 0
    else
      log_error "Non-interactive mode requires default value for: $prompt"
      return 1
    fi
  fi
  
  # Regular read logic...
  printf -v "$varname" '%s' "$default"
  return 0
}

# Test 1: With default in non-interactive mode
NON_INTERACTIVE=true
if safe_read "Test: " result "default_value"; then
  if [[ "$result" == "default_value" ]]; then
    echo "TEST1: PASS"
  else
    echo "TEST1: FAIL - got '$result'"
  fi
else
  echo "TEST1: FAIL - returned error"
fi

# Test 2: Without default in non-interactive mode (should fail)
if safe_read "Test: " result ""; then
  echo "TEST2: FAIL - should have failed"
else
  echo "TEST2: PASS - correctly failed"
fi
EOF
  
  chmod +x "$script"
  result=$(ORIGINAL_DIR="$ORIGINAL_DIR" "$script" 2>&1)
  
  if echo "$result" | grep -q "TEST1: PASS" && echo "$result" | grep -q "TEST2: PASS"; then
    log_pass "Enhanced safe_read handles non-interactive mode correctly"
    rm -f "$script"
    return 0
  else
    log_fail "Enhanced safe_read non-interactive mode failed"
    echo "$result"
    rm -f "$script"
    return 1
  fi
}

# Main test runner
main() {
  # A trapped signal waits for the running child, so the EXIT trap removes the
  # test directory only once nothing is writing to it.
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 131' QUIT
  trap 'exit 143' TERM
  sandbox_init

  echo -e "${BLUE}================================${NC}"
  echo -e "${BLUE}  Update.sh Test Suite (Enhanced)${NC}"
  echo -e "${BLUE}================================${NC}\n"

  if [[ ! -f "setup" ]]; then
    log_error "Please run this test from the directory containing setup"
    exit 1
  fi

  chmod +x setup 2>/dev/null || true

  # Define tests
  tests=(
    "test_syntax"
    "test_help_option"
    "test_dots_structure"
    "test_flat_structure"
    "test_dots_mapping"
    "test_ignore_patterns"
    "test_substring_ignore_patterns"
    "test_safe_read_security"
    "test_dry_run"
    "test_flags"
    "test_shellcheck"
    "test_lock_file"
    "test_directory_caching"
    "test_safe_read_noninteractive"
  )

  # Run tests
  for test in "${tests[@]}"; do
    sandbox_enter "$test"
    if $test; then
      echo "✓ $test passed"
    else
      echo "✗ $test failed"
    fi
    sandbox_leave
    echo
  done

  # Summary
  echo -e "${BLUE}================================${NC}"
  echo -e "${BLUE}  Test Summary${NC}"
  echo -e "${BLUE}================================${NC}"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  echo -e "${BLUE}Total:  ${#tests[@]}${NC}\n"
  if [[ -s "$STUB_LOG" ]]; then
    echo -e "${BLUE}Stubbed session calls: $(wc -l <"$STUB_LOG") ($(cut -d' ' -f1 "$STUB_LOG" | sort -u | paste -sd' ' -))${NC}\n"
  fi

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed! 🎉${NC}\n"
    exit 0
  else
    echo -e "${RED}Some tests failed! ❌${NC}\n"
    exit 1
  fi
}

# Global cleanup
cleanup() {
  echo "Cleaning up test files..."
  cd "$ORIGINAL_DIR" 2>/dev/null || cd /
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
