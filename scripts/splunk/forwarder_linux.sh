#!/usr/bin/env bash
# Splunk Universal Forwarder installer/config with list/dry-run/apply/backup/restore.

set -euo pipefail

MODE="list"
INSTALLER=""
INDEXER="172.20.242.20"
PORT=9997
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_USER="admin"
SPLUNK_PASS=""
BACKUP_DIR=""
RESTORE_FROM=""

usage() {
  cat <<'USAGE'
Usage: forwarder_linux.sh [options]

Modes:
  list | dry-run | apply | backup | restore

Options:
  --mode <list|dry-run|apply|backup|restore>
  --installer <path>      RPM or tgz installer path (required for install)
  --indexer <ip>          Splunk indexer IP (default: 172.20.242.20)
  --port <port>           Splunk receiving port (default: 9997)
  --splunk-home <path>    Splunk forwarder home (default: /opt/splunkforwarder)
  --splunk-user <user>    Splunk admin username (default: admin)
  --splunk-pass <pass>    Splunk admin password (required for config changes)
  --backup-dir <path>     Backup directory
  --restore-from <path>   Restore from backup archive
USAGE
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

fatal() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fatal "This mode requires root."
  fi
}

probe() {
  log "Probes: indexer connectivity"
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$INDEXER" "$PORT" && log "Indexer reachable" || log "Indexer not reachable"
  else
    log "nc not found; skipping connectivity probe"
  fi
}

list_status() {
  if [ -x "${SPLUNK_HOME}/bin/splunk" ]; then
    "${SPLUNK_HOME}/bin/splunk" status || true
    "${SPLUNK_HOME}/bin/splunk" list forward-server || true
    if [ -f "${SPLUNK_HOME}/etc/system/local/inputs.conf" ]; then
      cat "${SPLUNK_HOME}/etc/system/local/inputs.conf"
    fi
  else
    log "Splunk forwarder not installed at ${SPLUNK_HOME}"
  fi
}

plan_changes() {
  log "Planned changes"
  if [ -n "$INSTALLER" ] && [ ! -x "${SPLUNK_HOME}/bin/splunk" ]; then
    echo "- Would install forwarder from $INSTALLER"
  fi
  echo "- Would configure forwarder to send to ${INDEXER}:${PORT}"
  echo "- Would set minimal inputs (auth.log/secure)"
}

backup_configs() {
  local ts host outdir
  ts="$(date +%Y%m%d-%H%M%S)"
  host="$(hostname -s 2>/dev/null || hostname)"
  if [ -n "$BACKUP_DIR" ]; then
    outdir="$BACKUP_DIR"
  else
    outdir="$(pwd)/artifacts/backups/${host}-${ts}/splunk-forwarder"
  fi
  mkdir -p "$outdir"
  if [ -d "${SPLUNK_HOME}/etc/system/local" ]; then
    tar -czf "${outdir}/forwarder-local-${ts}.tar.gz" "${SPLUNK_HOME}/etc/system/local"
    log "Backup created: ${outdir}/forwarder-local-${ts}.tar.gz"
  else
    log "No forwarder config to back up"
  fi
}

restore_configs() {
  if [ -z "$RESTORE_FROM" ]; then
    fatal "--restore-from is required"
  fi
  if [ ! -f "$RESTORE_FROM" ]; then
    fatal "Restore archive not found: $RESTORE_FROM"
  fi
  tar -xzf "$RESTORE_FROM" -C /
  log "Restore complete from: $RESTORE_FROM"
}

install_forwarder() {
  if [ -x "${SPLUNK_HOME}/bin/splunk" ]; then
    log "Forwarder already installed at ${SPLUNK_HOME}"
    return
  fi
  if [ -z "$INSTALLER" ]; then
    fatal "--installer is required to install the forwarder"
  fi
  if [ ! -f "$INSTALLER" ]; then
    fatal "Installer not found: $INSTALLER"
  fi
  case "$INSTALLER" in
    *.rpm)
      rpm -i "$INSTALLER"
      ;;
    *.deb)
      dpkg -i "$INSTALLER"
      ;;
    *.tgz|*.tar.gz)
      tar -xzf "$INSTALLER" -C /opt
      ;;
    *)
      fatal "Unsupported installer type: $INSTALLER"
      ;;
  esac
}

configure_forwarder() {
  if [ -z "$SPLUNK_PASS" ]; then
    fatal "--splunk-pass is required to configure the forwarder"
  fi
  SPLUNK_PASSWORD="$SPLUNK_PASS" "${SPLUNK_HOME}/bin/splunk" start --accept-license --answer-yes --no-prompt || true
  "${SPLUNK_HOME}/bin/splunk" enable boot-start || true
  "${SPLUNK_HOME}/bin/splunk" add forward-server "${INDEXER}:${PORT}" -auth "${SPLUNK_USER}:${SPLUNK_PASS}" || true
  mkdir -p "${SPLUNK_HOME}/etc/system/local"
  cat <<'CONF' > "${SPLUNK_HOME}/etc/system/local/inputs.conf"
[monitor:///var/log/auth.log]
index=maccdc
sourcetype=linux_secure

[monitor:///var/log/secure]
index=maccdc
sourcetype=linux_secure
CONF
  "${SPLUNK_HOME}/bin/splunk" restart || true
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --installer) INSTALLER="$2"; shift 2 ;;
      --indexer) INDEXER="$2"; shift 2 ;;
      --port) PORT="$2"; shift 2 ;;
      --splunk-home) SPLUNK_HOME="$2"; shift 2 ;;
      --splunk-user) SPLUNK_USER="$2"; shift 2 ;;
      --splunk-pass) SPLUNK_PASS="$2"; shift 2 ;;
      --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
      --restore-from) RESTORE_FROM="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) fatal "Unknown argument: $1" ;;
    esac
  done
}

main() {
  parse_args "$@"
  case "$MODE" in
    list)
      probe
      list_status
      ;;
    dry-run)
      probe
      plan_changes
      ;;
    backup)
      need_root
      backup_configs
      ;;
    restore)
      need_root
      restore_configs
      ;;
    apply)
      need_root
      probe
      plan_changes
      backup_configs
      install_forwarder
      configure_forwarder
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
