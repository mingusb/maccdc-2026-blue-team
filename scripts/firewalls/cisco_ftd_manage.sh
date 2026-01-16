#!/usr/bin/env bash
# Cisco FTD CLI helper with list/dry-run/apply/backup/restore modes.
# Note: FTD CLI capabilities vary; test in dry-run before apply.

set -euo pipefail

MODE="list"
HOST=""
USER="admin"
PASS=""
SSH_PORT=22
SSH_KEY=""
BACKUP_DIR=""
RESTORE_FROM=""
ALLOW_UNSAFE=false

usage() {
  cat <<'USAGE'
Usage: cisco_ftd_manage.sh [options]

Modes:
  list | dry-run | apply | backup | restore

Options:
  --mode <list|dry-run|apply|backup|restore>
  --host <ip>             FTD management IP
  --user <user>           SSH username (default: admin)
  --pass <pass>           SSH password (uses expect)
  --ssh-key <path>        SSH private key
  --ssh-port <port>       SSH port (default: 22)
  --backup-dir <path>     Backup directory
  --restore-from <path>   Restore/apply from CLI command file
  --allow-unsafe          Allow apply/restore without confirmation
USAGE
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

fatal() { echo "ERROR: $*" >&2; exit 1; }

ssh_cmd() {
  local opts="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p ${SSH_PORT}"
  if [ -n "$SSH_KEY" ]; then
    opts="$opts -i $SSH_KEY"
    ssh $opts "$USER@$HOST" "$@"
    return
  fi
  if [ -n "$PASS" ]; then
    if ! command -v expect >/dev/null 2>&1; then
      fatal "expect is required for --pass (install expect or use --ssh-key)"
    fi
    FTD_USER="$USER" FTD_HOST="$HOST" FTD_PORT="$SSH_PORT" FTD_PASS="$PASS" FTD_CMD="$*" expect <<'EOF'
set timeout -1
set user $env(FTD_USER)
set host $env(FTD_HOST)
set port $env(FTD_PORT)
set pass $env(FTD_PASS)
set cmd $env(FTD_CMD)
spawn ssh -o StrictHostKeyChecking=accept-new -p $port $user@$host $cmd
expect {
  -re "(?i)assword:" { send -- "$pass\r"; exp_continue }
  eof
}
EOF
    return
  fi
  ssh $opts "$USER@$HOST" "$@"
}

ssh_cmd_interactive() {
  local cmds="$1"
  local opts="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p ${SSH_PORT}"
  if [ -n "$SSH_KEY" ]; then
    opts="$opts -i $SSH_KEY"
    ssh $opts "$USER@$HOST" <<EOF_CFG
$cmds
EOF_CFG
    return
  fi
  if [ -n "$PASS" ]; then
    if ! command -v expect >/dev/null 2>&1; then
      fatal "expect is required for --pass (install expect or use --ssh-key)"
    fi
    FTD_USER="$USER" FTD_HOST="$HOST" FTD_PORT="$SSH_PORT" FTD_PASS="$PASS" FTD_CMDS="$cmds" expect <<'EOF'
set timeout -1
set user $env(FTD_USER)
set host $env(FTD_HOST)
set port $env(FTD_PORT)
set pass $env(FTD_PASS)
set cmds $env(FTD_CMDS)
spawn ssh -o StrictHostKeyChecking=accept-new -p $port $user@$host
expect {
  -re "(?i)assword:" { send -- "$pass\r"; exp_continue }
  -re {>|#} {}
}
send -- "$cmds\r"
send -- "exit\r"
expect eof
EOF
    return
  fi
  ssh $opts "$USER@$HOST" <<EOF_CFG
$cmds
EOF_CFG
}

probe() {
  if [ -z "$HOST" ]; then
    fatal "--host is required"
  fi
  log "Probing SSH connectivity"
  ssh_cmd_interactive "show version" >/dev/null 2>&1 || log "SSH probe failed"
}

list_info() {
  ssh_cmd_interactive "show version" || true
}

plan_changes() {
  log "Planned changes"
  if [ -n "$RESTORE_FROM" ]; then
    echo "- Would apply CLI commands from $RESTORE_FROM"
  else
    echo "- No command file specified for apply/restore"
  fi
}

backup_configs() {
  local ts host outdir
  ts="$(date +%Y%m%d-%H%M%S)"
  host="${HOST:-ftd}"
  if [ -n "$BACKUP_DIR" ]; then
    outdir="$BACKUP_DIR"
  else
    outdir="$(pwd)/artifacts/backups/${host}-${ts}/cisco_ftd"
  fi
  mkdir -p "$outdir"
  local outfile
  outfile="${outdir}/ftd-running-${ts}.txt"
  ssh_cmd "show running-config" > "$outfile" || true
  log "Backup created: $outfile"
}

restore_configs() {
  if [ -z "$RESTORE_FROM" ]; then
    fatal "--restore-from is required"
  fi
  if [ ! -f "$RESTORE_FROM" ]; then
    fatal "Restore file not found: $RESTORE_FROM"
  fi
  if ! $ALLOW_UNSAFE; then
    fatal "Apply/restore requires --allow-unsafe due to FTD CLI variability."
  fi
  log "Applying CLI commands from: $RESTORE_FROM"
  ssh_cmd_interactive "$(cat <<EOF_CFG
configure terminal
$(grep -v '^#' "$RESTORE_FROM")
end
write memory
EOF_CFG
)"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --host) HOST="$2"; shift 2 ;;
      --user) USER="$2"; shift 2 ;;
      --pass) PASS="$2"; shift 2 ;;
      --ssh-key) SSH_KEY="$2"; shift 2 ;;
      --ssh-port) SSH_PORT="$2"; shift 2 ;;
      --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
      --restore-from) RESTORE_FROM="$2"; shift 2 ;;
      --allow-unsafe) ALLOW_UNSAFE=true; shift ;;
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
      list_info
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
      restore_configs
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
