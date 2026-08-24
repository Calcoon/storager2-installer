#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="https://github.com/Calcoon/Storager.git"
CHANNEL="storager2"
TOKEN_FILE="${STORAGER2_GIT_TOKEN_FILE:-}"
WORK_DIR=""
ASKPASS_FILE=""

die() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local status=$?
  [[ -z "$ASKPASS_FILE" ]] || rm -f -- "$ASKPASS_FILE"
  [[ -z "$WORK_DIR" ]] || rm -rf --one-file-system -- "$WORK_DIR"
  exit "$status"
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Benoetigtes Programm fehlt: $1"
}

usage() {
  cat <<'EOF'
Oeffentlicher Bootstrap fuer den interaktiven Storager-2-Proxmox-Installer.

Verwendung: install.sh [--dry-run] [--unattended] [--help]

Die Optionen werden nach dem sicheren, temporaeren Checkout unveraendert an
den privaten Storager-2-Installer weitergereicht. Ein echter unbeaufsichtigter
Lauf benoetigt dessen dokumentierte STORAGER2_INSTALL_*-Umgebungswerte.
EOF
}

for argument in "$@"; do
  case "$argument" in
    --dry-run|--unattended) ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unbekannte Option: $argument" ;;
  esac
done

printf '\nStorager 2 · interaktiver Proxmox-LXC-Installer\n'
printf 'Quelle: %s · Channel: %s\n\n' "$REPOSITORY_URL" "$CHANNEL"
printf 'Der Bootstrap legt nur einen temporaeren Checkout unter /tmp an.\n'
printf 'Storager 1 und bestehende Container werden nicht als Ziel verwendet.\n\n'

[[ "$(id -u)" == "0" ]] || die "Der Installer muss in der Proxmox-Shell als root laufen"
require_command git
require_command mktemp
require_command readlink
require_command stat
require_command pct
[[ -z "${STORAGER2_GIT_TOKEN:-}" ]] \
  || die "Git-Token nicht als Environmentwert uebergeben; nur STORAGER2_GIT_TOKEN_FILE verwenden"

if [[ -z "$TOKEN_FILE" ]]; then
  read -r -p "Pfad zur read-only GitHub-Token-Datei (0600): " TOKEN_FILE
fi
[[ "$TOKEN_FILE" == /* && "$TOKEN_FILE" != "/" ]] \
  || die "GitHub-Token-Datei muss als absoluter Pfad angegeben werden"
[[ -f "$TOKEN_FILE" && ! -L "$TOKEN_FILE" && -s "$TOKEN_FILE" ]] \
  || die "GitHub-Token-Datei fehlt, ist leer oder ein Symlink"
[[ "$(readlink -f -- "$TOKEN_FILE")" == "$TOKEN_FILE" ]] \
  || die "GitHub-Token-Datei muss ein kanonischer Pfad sein"
token_mode="$(stat -c '%a' "$TOKEN_FILE")"
[[ "$token_mode" == "600" || "$token_mode" == "400" ]] \
  || die "GitHub-Token-Datei muss Modus 0600 oder 0400 haben"

WORK_DIR="$(mktemp -d /tmp/storager2-installer.XXXXXX)"
chmod 0700 "$WORK_DIR"
ASKPASS_FILE="$(mktemp "$WORK_DIR/askpass.XXXXXX")"
chmod 0700 "$ASKPASS_FILE"
cat > "$ASKPASS_FILE" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *) cat -- "$STORAGER2_BOOTSTRAP_TOKEN_FILE" ;;
esac
EOF

printf 'Lade den privaten, aktuellen Storager-2-Installationsstand ...\n'
GIT_ASKPASS="$ASKPASS_FILE" \
GIT_TERMINAL_PROMPT=0 \
STORAGER2_BOOTSTRAP_TOKEN_FILE="$TOKEN_FILE" \
  git clone --quiet --filter=blob:none --single-branch --branch "$CHANNEL" \
    "$REPOSITORY_URL" "$WORK_DIR/Storager"
rm -f -- "$ASKPASS_FILE"
ASKPASS_FILE=""

checkout_channel="$(git -C "$WORK_DIR/Storager" branch --show-current)"
[[ "$checkout_channel" == "$CHANNEL" ]] \
  || die "Geladener Channel ist nicht storager2"
target_commit="$(git -C "$WORK_DIR/Storager" rev-parse 'HEAD^{commit}')"
remote_commit="$(git -C "$WORK_DIR/Storager" rev-parse 'refs/remotes/origin/storager2^{commit}')"
[[ "$target_commit" == "$remote_commit" ]] \
  || die "Checkout und origin/storager2 stimmen nicht ueberein"
[[ -x "$WORK_DIR/Storager/scripts/storager2/install.sh" ]] \
  || die "Der geladene Stand enthaelt keinen ausfuehrbaren S2-Installer"

printf 'Gepruefter Zielcommit: %s\n\n' "$target_commit"
STORAGER2_GIT_TOKEN_FILE="$TOKEN_FILE" \
  "$WORK_DIR/Storager/scripts/storager2/install.sh" "$@"
