#!/usr/bin/env bash
# VyOS management helper with list/dry-run/apply/backup/restore modes.

set -euo pipefail

MODE="list"
HOST=""
USER="vyos"
SSH_KEY=""
SSH_PORT=22
MGMT_IPS=""
RESTRICT_SSH=false
REPLACE_SSH=false
BACKUP_DIR=""
RESTORE_FROM=""

usage() {
  cat <<'USAGE'
Usage: vyos_manage.sh [options]

Modes:
  list | dry-run | apply | backup | restore

Options:
  --mode <list|dry-run|apply|backup|restore>
  --host <ip>             VyOS management IP
  --user <user>           SSH username (default: vyos)
  --ssh-key <path>        SSH private key
  --ssh-port <port>       SSH port (default: 22)
  --mgmt-ips <ip1,ip2>    Management IPs for ssh listen-address
  --restrict-ssh          Set ssh listen-address to mgmt IPs
  --replace-ssh           Remove existing listen-address before adding new
  --backup-dir <path>     Backup directory
  --restore-from <path>   Restore from backup file (commands)
USAGE
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

fatal() { echo "ERROR: $*" >&2; exit 1; }

split_csv() {
  local csv="$1"
  IFS=',' read -r -a __items <<< "$csv"
  for item in "${__items[@]}"; do
    echo "$item" | xargs
  done
}

ssh_cmd() {
  local opts="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p ${SSH_PORT}"
  if [ -n "$SSH_KEY" ]; then
    opts="$opts -i $SSH_KEY"
  fi
  ssh $opts "$USER@$HOST" "$@"
}

probe() {
  if [ -z "$HOST" ]; then
    fatal "--host is required"
  fi
  log "Probing SSH connectivity"
  ssh_cmd "show version" >/dev/null 2>&1 || log "SSH probe failed"
}

list_configs() {
  ssh_cmd "show configuration commands" || true
}

plan_changes() {
  log "Planned changes"
  if $RESTRICT_SSH; then
    echo "- Would set service ssh listen-address to: $MGMT_IPS"
    if $REPLACE_SSH; then
      echo "- Would remove existing service ssh listen-address entries"
    fi
  fi
}

backup_configs() {
  local ts host outdir
  ts="$(date +%Y%m%d-%H%M%S)"
  host="${HOST:-vyos}"
  if [ -n "$BACKUP_DIR" ]; then
    outdir="$BACKUP_DIR"
  else
    outdir="$(pwd)/artifacts/backups/${host}-${ts}/vyos"
  fi
  mkdir -p "$outdir"
  local outfile
  outfile="${outdir}/vyos-config-${ts}.txt"
  ssh_cmd "show configuration commands" > "$outfile"
  log "Backup created: $outfile"
}

restore_configs() {
  if [ -z "$RESTORE_FROM" ]; then
    fatal "--restore-from is required"
  fi
  if [ ! -f "$RESTORE_FROM" ]; then
    fatal "Restore file not found: $RESTORE_FROM"
  fi
  log "Applying restore file: $RESTORE_FROM"
  local opts="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p ${SSH_PORT}"
  if [ -n "$SSH_KEY" ]; then
    opts="$opts -i $SSH_KEY"
  fi
  ssh $opts "$USER@$HOST" <<EOF_CFG
configure
$(grep -E '^(set|delete) ' "$RESTORE_FROM")
commit
save
exit
EOF_CFG
}

apply_changes() {
  if $RESTRICT_SSH; then
    if [ -z "$MGMT_IPS" ]; then
      fatal "--mgmt-ips is required for --restrict-ssh"
    fi
    local opts="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p ${SSH_PORT}"
    if [ -n "$SSH_KEY" ]; then
      opts="$opts -i $SSH_KEY"
    fi
    ssh $opts "$USER@$HOST" <<EOF_CFG
configure
$(if $REPLACE_SSH; then echo "delete service ssh listen-address"; fi)
$(while read -r ip; do echo "set service ssh listen-address ${ip}"; done < <(split_csv "$MGMT_IPS"))
commit
save
exit
EOF_CFG
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --host) HOST="$2"; shift 2 ;;
      --user) USER="$2"; shift 2 ;;
      --ssh-key) SSH_KEY="$2"; shift 2 ;;
      --ssh-port) SSH_PORT="$2"; shift 2 ;;
      --mgmt-ips) MGMT_IPS="$2"; shift 2 ;;
      --restrict-ssh) RESTRICT_SSH=true; shift ;;
      --replace-ssh) REPLACE_SSH=true; shift ;;
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
      list_configs
      ;;
    dry-run)
      probe
      plan_changes
      ;;
    backup)
      probe
      backup_configs
      ;;
    restore)
      probe
      restore_configs
      ;;
    apply)
      probe
      plan_changes
      backup_configs
      apply_changes
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
