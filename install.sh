#!/usr/bin/env bash
set -euo pipefail
if [[ "${STORAGER2_BOOTSTRAP_TRACE:-0}" == "1" ]]; then
  set -x
fi

REPOSITORY_URL="https://github.com/Calcoon/Storager.git"
CHANNEL="storager2"
TOKEN_FILE="${STORAGER2_GIT_TOKEN_FILE:-}"
CLD_TOKEN_FILE="${STORAGER2_CLOUDFLARE_TOKEN_FILE:-}"
WORK_DIR=""
ASKPASS_FILE=""
UNATTENDED=0
PATCHED_TIMEZONE_FILES=0

patch_ct_provision_timezone() {
  local provision_script="$1"
  local patched_script
  local exit_code
  local pattern=$'^[[:space:]]*run[[:space:]]+timedatectl[[:space:]]+set-timezone[[:space:]]+"\$TIMEZONE"'
  local already_patched_pattern=$'if ! timedatectl set-timezone "$timezone"; then'
  local relative_path

  [[ -f "$provision_script" ]] || return 0
  grep -Eq "$pattern" "$provision_script" \
    || return 0
  grep -Fq "$already_patched_pattern" "$provision_script" \
    && return 0

  patched_script="$(mktemp "${WORK_DIR}/.storager2-ct-provision.XXXXXX")" \
    || die "Fehler beim Erstellen des temporären Patch-Kontexts"
  awk '
    {
      if ($0 ~ /^[[:space:]]*run[[:space:]]+timedatectl[[:space:]]+set-timezone[[:space:]]+\"\$TIMEZONE\"[[:space:]]*$/) {
        match($0, /^[[:space:]]*/)
        indent = substr($0, 1, RLENGTH)
        print indent "timezone=\"${TIMEZONE:-Etc/UTC}\""
        print indent "if ! timedatectl set-timezone \"$timezone\"; then"
        print indent "  warn \"Zeitzone konnte nicht gesetzt werden; verwende den Standard der LXC\""
        print indent "  if [[ -f \"/usr/share/zoneinfo/$timezone\" ]]; then"
        print indent "    ln -snf \"/usr/share/zoneinfo/$timezone\" /etc/localtime"
        print indent "    printf \"%s\\\\n\" \"$timezone\" > /etc/timezone"
        print indent "  fi"
        print indent "fi"
      } else {
        print
      }
    }
  ' "$provision_script" > "$patched_script"
  exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    rm -f -- "$patched_script"
    die "Fehler beim Patchen von ct_provision.sh für tolerante Zeiteinstellung"
  fi
  mv -- "$patched_script" "$provision_script"

  relative_path="${provision_script#"$WORK_DIR/Storager/"}"
  if [[ "$relative_path" != "$provision_script" ]]; then
    if git -C "$WORK_DIR/Storager" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1; then
      if ! git -C "$WORK_DIR/Storager" update-index --skip-worktree -- "$relative_path"; then
        warn "skip-worktree konnte fuer ${relative_path} nicht gesetzt werden"
      fi
    else
      warn "Patch-Datei ${relative_path} ist nicht als git-File versioniert; skip-worktree wird uebersprungen"
    fi
  fi

  # With `set -e`, post-increment returns status 1 for the initial zero value
  # and would abort the bootstrap immediately after the first successful patch.
  ((++PATCHED_TIMEZONE_FILES))
}

die() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Warnung: %s\n' "$*" >&2
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
  # `set -x` would otherwise disclose the entered token in later conditionals.
  if [[ "${STORAGER2_BOOTSTRAP_TRACE:-0}" == "1" ]]; then
    set +x
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
  if [[ "${STORAGER2_BOOTSTRAP_TRACE:-0}" == "1" ]]; then
    set -x
  fi
fi
check_token_file "$TOKEN_FILE" "GitHub"

if [[ -z "$CLD_TOKEN_FILE" ]] && (( !UNATTENDED )) && [[ -t 0 ]]; then
  # Keep optional tunnel credentials out of bootstrap trace logs as well.
  if [[ "${STORAGER2_BOOTSTRAP_TRACE:-0}" == "1" ]]; then
    set +x
  fi
  IFS= read -r -s -p "Cloudflare-Token fuer Tunnel eingeben [optional, Enter=ueberspringen]: " CLOUDFLARE_TOKEN_INPUT
  printf '\n'
  if [[ -n "${CLOUDFLARE_TOKEN_INPUT:-}" ]]; then
    CLD_TOKEN_FILE="$(mktemp "$WORK_DIR/.storager2-cloudflare-token.XXXXXX")"
    printf '%s\n' "$CLOUDFLARE_TOKEN_INPUT" > "$CLD_TOKEN_FILE"
    chmod 0600 "$CLD_TOKEN_FILE"
  fi
  unset CLOUDFLARE_TOKEN_INPUT
  if [[ "${STORAGER2_BOOTSTRAP_TRACE:-0}" == "1" ]]; then
    set -x
  fi
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
printf 'Bootstrap-Checkout abgeschlossen.\n'
rm -f -- "$ASKPASS_FILE"
ASKPASS_FILE=""

checkout_channel="$(git -C "$WORK_DIR/Storager" branch --show-current)"
printf 'Checkout-Branch: %s\n' "${checkout_channel:-[keiner]}"
[[ "$checkout_channel" == "$CHANNEL" ]] \
  || die "Geladener Channel ist nicht storager2"
target_commit="$(git -C "$WORK_DIR/Storager" rev-parse 'HEAD^{commit}')"
remote_commit="$(git -C "$WORK_DIR/Storager" rev-parse 'refs/remotes/origin/storager2^{commit}')"
printf 'Ziel-Commit: %s\nRemote-Commit: %s\n' "$target_commit" "$remote_commit"
[[ "$target_commit" == "$remote_commit" ]] \
  || die "Checkout und origin/storager2 stimmen nicht ueberein"
patch_targets=()
while IFS= read -r -d '' file; do
  patch_targets+=("$file")
done < <(find "$WORK_DIR/Storager" -type f -name "ct_provision.sh" -print0)

if ((${#patch_targets[@]} == 0)); then
  warn "Keine ct_provision.sh im geladenen Storager-Checkout gefunden; Fortsetzung ohne Patch"
fi

for target in "${patch_targets[@]}"; do
  patch_ct_provision_timezone "$target"
done

if (( PATCHED_TIMEZONE_FILES > 0 )); then
  printf 'ct_provision-Zeitbereichs-Konfiguration tolerant gepatcht in %s Datei(en)\n' "$PATCHED_TIMEZONE_FILES"
fi
[[ -x "$WORK_DIR/Storager/scripts/storager2/install.sh" ]] \
  || die "Der geladene Stand enthaelt keinen ausfuehrbaren S2-Installer"

printf 'Gepruefter Zielcommit: %s\n\n' "$target_commit"
effective_timezone="${TIMEZONE:-Etc/UTC}"
if [[ -n "$CLD_TOKEN_FILE" ]]; then
  printf 'Starte privaten S2-Installer mit Cloudflare-Konfiguration...\n'
  printf '  GitHub-Token-Datei: %s\n' "$TOKEN_FILE"
  printf '  Cloudflare-Token-Datei: %s\n' "$CLD_TOKEN_FILE"
else
  printf 'Starte privaten S2-Installer ohne Cloudflare...\n'
  printf '  GitHub-Token-Datei: %s\n' "$TOKEN_FILE"
fi
__storager2_bootstrap_rc=0
if [[ "${STORAGER2_BOOTSTRAP_TRACE:-0}" == "1" ]]; then
  if [[ -n "$CLD_TOKEN_FILE" ]]; then
    STORAGER2_CLOUDFLARE_TOKEN_FILE="$CLD_TOKEN_FILE" \
    STORAGER2_GIT_TOKEN_FILE="$TOKEN_FILE" \
      TIMEZONE="$effective_timezone" \
      bash -x "$WORK_DIR/Storager/scripts/storager2/install.sh" "$@" \
      || __storager2_bootstrap_rc=$?
  else
    STORAGER2_GIT_TOKEN_FILE="$TOKEN_FILE" \
      TIMEZONE="$effective_timezone" \
      bash -x "$WORK_DIR/Storager/scripts/storager2/install.sh" "$@" \
      || __storager2_bootstrap_rc=$?
  fi
else
  if [[ -n "$CLD_TOKEN_FILE" ]]; then
    STORAGER2_CLOUDFLARE_TOKEN_FILE="$CLD_TOKEN_FILE" \
    STORAGER2_GIT_TOKEN_FILE="$TOKEN_FILE" \
      TIMEZONE="$effective_timezone" \
      "$WORK_DIR/Storager/scripts/storager2/install.sh" "$@" \
      || __storager2_bootstrap_rc=$?
  else
    STORAGER2_GIT_TOKEN_FILE="$TOKEN_FILE" \
      TIMEZONE="$effective_timezone" \
      "$WORK_DIR/Storager/scripts/storager2/install.sh" "$@" \
      || __storager2_bootstrap_rc=$?
  fi
fi

if (( __storager2_bootstrap_rc != 0 )); then
  die "Der private S2-Installer ist mit Fehlercode ${__storager2_bootstrap_rc} beendet."
fi
