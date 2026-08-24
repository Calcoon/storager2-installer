#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/storager2-bootstrap-test.XXXXXX)"
trap 'rm -rf --one-file-system -- "$TEST_DIR"' EXIT
BIN_DIR="$TEST_DIR/bin"
TOKEN_FILE="$TEST_DIR/github-token"
RECORD_FILE="$TEST_DIR/record"
mkdir -p "$BIN_DIR"
printf 'test-token-never-log\n' > "$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"

cat > "$BIN_DIR/id" <<'EOF'
#!/bin/sh
if [ "$1" = "-u" ]; then printf '0\n'; else exec /usr/bin/id "$@"; fi
EOF
cat > "$BIN_DIR/pct" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  clone)
    [ "$GIT_TERMINAL_PROMPT" = "0" ]
    [ -x "$GIT_ASKPASS" ]
    [ "$STORAGER2_BOOTSTRAP_TOKEN_FILE" = "$EXPECTED_TOKEN_FILE" ]
    case "$*" in *"x-access-token"*|*"test-token-never-log"*) exit 91 ;; esac
    destination="${@: -1}"
    mkdir -p "$destination/scripts/storager2"
    cat > "$destination/scripts/storager2/ct_provision.sh" <<'PROVISION'
run timedatectl set-timezone "$TIMEZONE"
PROVISION
    cat > "$destination/scripts/storager2/install.sh" <<'INNER'
#!/bin/sh
printf '%s\n' "$STORAGER2_GIT_TOKEN_FILE" "$@" > "$BOOTSTRAP_TEST_RECORD"
INNER
    chmod 0755 "$destination/scripts/storager2/install.sh"
    ;;
  -C)
    case "$3" in
      branch) printf 'storager2\n' ;;
      rev-parse) printf '%040d\n' 7 ;;
      ls-files|update-index) ;;
      *) exit 92 ;;
    esac
    ;;
  *) exit 93 ;;
esac
EOF
chmod 0755 "$BIN_DIR/id" "$BIN_DIR/pct" "$BIN_DIR/git"

help_output="$("$REPO_ROOT/install.sh" --help)"
[[ "$help_output" == *"Oeffentlicher Bootstrap"* ]]

output="$({
  PATH="$BIN_DIR:$PATH" \
  EXPECTED_TOKEN_FILE="$TOKEN_FILE" \
  BOOTSTRAP_TEST_RECORD="$RECORD_FILE" \
  STORAGER2_GIT_TOKEN_FILE="$TOKEN_FILE" \
    "$REPO_ROOT/install.sh" --dry-run
} 2>&1)"
[[ "$output" == *"Gepruefter Zielcommit"* ]]
[[ "$output" == *"ct_provision-Zeitbereichs-Konfiguration tolerant gepatcht in 1 Datei(en)"* ]]
[[ "$output" != *"test-token-never-log"* ]]
mapfile -t record < "$RECORD_FILE"
[[ "${record[0]}" == "$TOKEN_FILE" ]]
[[ "${record[1]}" == "--dry-run" ]]

printf 'bootstrap_test: ok\n'
