#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="https://github.com/Calcoon/Storager.git"
CHANNEL="storager2"
TOKEN_FILE="${STORAGER2_GIT_TOKEN_FILE:-}"
CLD_TOKEN_FILE="${STORAGER2_CLOUDFLARE_TOKEN_FILE:-}"
WORK_DIR=""
ASKPASS_FILE=""
UNATTENDED=0

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

check_token_file() {
  local file="$1" context="$2"

  [[ "$file" == /* && "$file" != "/" ]] \
    || die "$context-Token-Datei muss als absoluter Pfad angegeben werden"
  [[ -f "$file" && ! -L "$file" && -s "$file" ]] \
    || die "$context-Token-Datei fehlt, ist leer oder ein Symlink"
  [[ "$(readlink -f -- "$file")" == "$file" ]] \
    || die "$context-Token-Datei muss ein kanonischer Pfad sein"
  local file_mode
  file_mode="$(stat -c '%a' "$file")"
  [[ "$file_mode" == "600" || "$file_mode" == "400" ]] \
    || die "$context-Token-Datei muss Modus 0600 oder 0400 haben"
}

for argument in "$@"; do
  case "$argument" in
    --dry-run) ;;
    --unattended) UNATTENDED=1 ;;
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

WORK_DIR="$(mktemp -d /tmp/storager2-installer.XXXXXX)"
chmod 0700 "$WORK_DIR"

if [[ -z "$TOKEN_FILE" ]]; then
  if (( UNATTENDED )); then
    die "STORAGER2_GIT_TOKEN_FILE ist im --unattended-Modus erforderlich"
  fi
  if [[ ! -t 0 ]]; then
    die "Keine TTY im interaktiven Modus; bitte STORAGER2_GIT_TOKEN_FILE setzen"
  fi
  IFS= read -r -s -p "GitHub Fine-grained PAT fuer Calcoon/Storager eingeben: " GIT_TOKEN_INPUT
  printf '\n'
  if [[ -z "${GIT_TOKEN_INPUT:-}" ]]; then
    die "GitHub Token darf nicht leer sein"
  fi
  TOKEN_FILE="$(mktemp "$WORK_DIR/.storager2-read-token.XXXXXX")"
  printf '%s\n' "$GIT_TOKEN_INPUT" > "$TOKEN_FILE"
  chmod 0600 "$TOKEN_FILE"
  unset GIT_TOKEN_INPUT
fi
check_token_file "$TOKEN_FILE" "GitHub"

if [[ -z "$CLD_TOKEN_FILE" ]] && (( !UNATTENDED )) && [[ -t 0 ]]; then
  IFS= read -r -s -p "Cloudflare-Token fuer Tunnel eingeben [optional, Enter=ueberspringen]: " CLOUDFLARE_TOKEN_INPUT
  printf '\n'
  if [[ -n "${CLOUDFLARE_TOKEN_INPUT:-}" ]]; then
    CLD_TOKEN_FILE="$(mktemp "$WORK_DIR/.storager2-cloudflare-token.XXXXXX")"
    printf '%s\n' "$CLOUDFLARE_TOKEN_INPUT" > "$CLD_TOKEN_FILE"
    chmod 0600 "$CLD_TOKEN_FILE"
  fi
  unset CLOUDFLARE_TOKEN_INPUT
fi

if [[ -n "$CLD_TOKEN_FILE" ]]; then
  check_token_file "$CLD_TOKEN_FILE" "Cloudflare"
fi
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
if [[ -n "$CLD_TOKEN_FILE" ]]; then
  STORAGER2_CLOUDFLARE_TOKEN_FILE="$CLD_TOKEN_FILE" \
  STORAGER2_GIT_TOKEN_FILE="$TOKEN_FILE" \
    "$WORK_DIR/Storager/scripts/storager2/install.sh" "$@"
else
  STORAGER2_GIT_TOKEN_FILE="$TOKEN_FILE" \
    "$WORK_DIR/Storager/scripts/storager2/install.sh" "$@"
fi
