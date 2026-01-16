#!/usr/bin/env bash
# Safe Linux hardening helper with list/dry-run/apply/backup/restore modes.

set -euo pipefail

MODE="list"
MGMT_IPS=""
SSH_PORT=22
ENABLE_UFW=false
ENABLE_FIREWALLD=false
SSHD_HARDEN=false
RESTRICT_SSH=false
DENY_SSH=false
ENABLE_APPARMOR=false
APPARMOR_PROFILES="usr.sbin.sshd"
SELINUX_PERMISSIVE=false
SELINUX_ENFORCE=false
ALLOW_UNSAFE=false
BACKUP_DIR=""
RESTORE_FROM=""

usage() {
  cat <<'USAGE'
Usage: harden_linux.sh [options]

Modes (required via --mode):
  list       Show current config and status
  dry-run    Probe assumptions and show planned changes
  apply      Apply selected changes (auto-backup first)
  backup     Create a config backup archive
  restore    Restore a config backup archive

Options:
  --mode <list|dry-run|apply|backup|restore>
  --mgmt-ips <ip1,ip2>         Management IP allow-list for SSH firewall rules
  --ssh-port <port>            SSH port (default: 22)
  --sshd-hardening             Apply safe sshd config snippet
  --restrict-ssh               Restrict SSH via host firewall (requires --mgmt-ips)
  --deny-ssh                   Add a deny rule for SSH from non-mgmt IPs
  --enable-ufw                 Enable UFW if present
  --enable-firewalld           Enable firewalld if present
  --enable-apparmor            Enable AppArmor and enforce profiles
  --apparmor-profiles <list>   Comma-separated AppArmor profiles (default: usr.sbin.sshd)
  --selinux-permissive         Set SELinux to permissive (requires reboot to relabel)
  --selinux-enforce            Set SELinux to enforcing
  --backup-dir <path>          Backup directory (default: artifacts/backups/...)
  --restore-from <path>        Restore from backup archive
  --allow-unsafe               Skip safety checks (lockout protection)
USAGE
}

log() {
  echo "[$(date +%H:%M:%S)] $*"
}

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fatal "This mode requires root. Re-run with sudo."
  fi
}

split_csv() {
  local csv="$1"
  IFS=',' read -r -a __items <<< "$csv"
  for item in "${__items[@]}"; do
    echo "$item" | xargs
  done
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-unknown} ${VERSION_ID:-unknown}"
  else
    echo "unknown"
  fi
}

probe_system() {
  log "Probes: system status"
  log "OS: $(detect_os)"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active sshd >/dev/null 2>&1 || systemctl is-active ssh >/dev/null 2>&1 || true
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -tulpn | grep -E ":${SSH_PORT}\b" >/dev/null 2>&1 || true
  fi
  if command -v sestatus >/dev/null 2>&1; then
    sestatus | head -n 5 || true
  fi
  if command -v aa-status >/dev/null 2>&1; then
    aa-status | head -n 5 || true
  fi
  if command -v ufw >/dev/null 2>&1; then
    ufw status verbose || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --state || true
  fi
}

list_configs() {
  log "Listing key configs"
  if [ -f /etc/ssh/sshd_config ]; then
    grep -E '^(Port|PermitRootLogin|PasswordAuthentication|AllowUsers|AllowGroups|Match)' /etc/ssh/sshd_config || true
  fi
  if [ -f /etc/ssh/sshd_config.d/99-maccdc.conf ]; then
    log "sshd_config.d/99-maccdc.conf"
    cat /etc/ssh/sshd_config.d/99-maccdc.conf
  fi
  if [ -f /etc/selinux/config ]; then
    grep -E '^SELINUX|^SELINUXTYPE' /etc/selinux/config || true
  fi
  if command -v ufw >/dev/null 2>&1; then
    ufw status numbered || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --list-all || true
  fi
}

plan_changes() {
  log "Planned changes"
  if $SSHD_HARDEN; then
    echo "- Would write /etc/ssh/sshd_config.d/99-maccdc.conf (safe sshd hardening)"
  fi
  if $RESTRICT_SSH; then
    echo "- Would restrict SSH to mgmt IPs via host firewall (port ${SSH_PORT})"
    if $DENY_SSH; then
      echo "- Would add a deny rule for SSH from non-mgmt IPs"
    fi
  fi
  if $ENABLE_APPARMOR; then
    echo "- Would enable AppArmor and enforce: ${APPARMOR_PROFILES}"
  fi
  if $SELINUX_PERMISSIVE; then
    echo "- Would set SELinux to permissive and schedule relabel"
  fi
  if $SELINUX_ENFORCE; then
    echo "- Would set SELinux to enforcing"
  fi
}

ensure_safe_mgmt_ip() {
  if $ALLOW_UNSAFE; then
    return
  fi
  if [ -z "$MGMT_IPS" ]; then
    return
  fi
  if [ -n "${SSH_CONNECTION:-}" ]; then
    local remote_ip
    remote_ip="$(echo "$SSH_CONNECTION" | awk '{print $1}')"
    local allowed=false
    while read -r ip; do
      if [ "$remote_ip" = "$ip" ]; then
        allowed=true
      fi
    done < <(split_csv "$MGMT_IPS")
    if [ "$allowed" != "true" ]; then
      fatal "Current SSH remote IP $remote_ip is not in --mgmt-ips; refusing to restrict SSH. Use --allow-unsafe to override."
    fi
  fi
}

backup_configs() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local host
  host="$(hostname -s 2>/dev/null || hostname)"
  local outdir
  if [ -n "$BACKUP_DIR" ]; then
    outdir="$BACKUP_DIR"
  else
    outdir="$(pwd)/artifacts/backups/${host}-${ts}/linux"
  fi
  mkdir -p "$outdir"
  local listfile
  listfile="${outdir}/filelist.txt"
  : > "$listfile"
  for path in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/99-maccdc.conf /etc/selinux/config /etc/ufw/user.rules /etc/ufw/user6.rules /etc/firewalld; do
    if [ -e "$path" ]; then
      echo "$path" >> "$listfile"
    fi
  done
  if [ ! -s "$listfile" ]; then
    log "No config files found to back up."
    return
  fi
  local archive
  archive="${outdir}/linux-configs-${ts}.tar.gz"
  tar --absolute-names -czf "$archive" -T "$listfile"
  log "Backup created: $archive"
}

restore_configs() {
  if [ -z "$RESTORE_FROM" ]; then
    fatal "--restore-from is required for restore mode"
  fi
  if [ ! -f "$RESTORE_FROM" ]; then
    fatal "Restore archive not found: $RESTORE_FROM"
  fi
  tar --absolute-names -xzf "$RESTORE_FROM" -C /
  log "Restore complete from: $RESTORE_FROM"
}

apply_sshd_hardening() {
  mkdir -p /etc/ssh/sshd_config.d
  cat <<'CONF' > /etc/ssh/sshd_config.d/99-maccdc.conf
# Managed by harden_linux.sh
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
CONF
  if command -v sshd >/dev/null 2>&1; then
    if ! sshd -t; then
      rm -f /etc/ssh/sshd_config.d/99-maccdc.conf
      fatal "sshd config test failed; reverted 99-maccdc.conf"
    fi
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
  fi
}

apply_restrict_ssh() {
  ensure_safe_mgmt_ip
  if [ -z "$MGMT_IPS" ]; then
    fatal "--mgmt-ips is required for --restrict-ssh"
  fi
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
      while read -r ip; do
        ufw allow from "$ip" to any port "$SSH_PORT" proto tcp || true
      done < <(split_csv "$MGMT_IPS")
      if $DENY_SSH; then
        ufw deny "$SSH_PORT"/tcp || true
      fi
    else
      if $ENABLE_UFW; then
        ufw --force enable
      else
        log "UFW is installed but inactive; skipping SSH restriction (use --enable-ufw to enable)."
      fi
    fi
    return
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state >/dev/null 2>&1; then
      while read -r ip; do
        firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='${ip}' port protocol='tcp' port='${SSH_PORT}' accept" >/dev/null
      done < <(split_csv "$MGMT_IPS")
      if $DENY_SSH; then
        firewall-cmd --permanent --add-rich-rule="rule family='ipv4' port protocol='tcp' port='${SSH_PORT}' reject" >/dev/null
      fi
      firewall-cmd --reload >/dev/null
    else
      if $ENABLE_FIREWALLD; then
        systemctl enable --now firewalld
      else
        log "firewalld is installed but inactive; skipping SSH restriction (use --enable-firewalld to enable)."
      fi
    fi
    return
  fi
  log "No supported firewall (ufw/firewalld) found; skipping SSH restriction."
}

apply_apparmor() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now apparmor
  fi
  if command -v aa-enforce >/dev/null 2>&1; then
    while read -r prof; do
      if [ -f "/etc/apparmor.d/${prof}" ]; then
        aa-enforce "/etc/apparmor.d/${prof}" || true
      fi
    done < <(split_csv "$APPARMOR_PROFILES")
  fi
}

apply_selinux_permissive() {
  if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
    sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config
    touch /.autorelabel
  fi
  if command -v setenforce >/dev/null 2>&1; then
    setenforce 0 || true
  fi
  log "SELinux set to permissive; reboot required for relabel."
}

apply_selinux_enforce() {
  if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
  fi
  if command -v setenforce >/dev/null 2>&1; then
    setenforce 1 || true
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --mgmt-ips) MGMT_IPS="$2"; shift 2 ;;
      --ssh-port) SSH_PORT="$2"; shift 2 ;;
      --sshd-hardening) SSHD_HARDEN=true; shift ;;
      --restrict-ssh) RESTRICT_SSH=true; shift ;;
      --deny-ssh) DENY_SSH=true; shift ;;
      --enable-ufw) ENABLE_UFW=true; shift ;;
      --enable-firewalld) ENABLE_FIREWALLD=true; shift ;;
      --enable-apparmor) ENABLE_APPARMOR=true; shift ;;
      --apparmor-profiles) APPARMOR_PROFILES="$2"; shift 2 ;;
      --selinux-permissive) SELINUX_PERMISSIVE=true; shift ;;
      --selinux-enforce) SELINUX_ENFORCE=true; shift ;;
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
      probe_system
      list_configs
      ;;
    dry-run)
      probe_system
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
      probe_system
      plan_changes
      if ! $SSHD_HARDEN && ! $RESTRICT_SSH && ! $ENABLE_APPARMOR && ! $SELINUX_PERMISSIVE && ! $SELINUX_ENFORCE; then
        fatal "No actions selected for apply."
      fi
      backup_configs
      if $SSHD_HARDEN; then
        apply_sshd_hardening
      fi
      if $RESTRICT_SSH; then
        apply_restrict_ssh
      fi
      if $ENABLE_APPARMOR; then
        apply_apparmor
      fi
      if $SELINUX_PERMISSIVE; then
        apply_selinux_permissive
      fi
      if $SELINUX_ENFORCE; then
        apply_selinux_enforce
      fi
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
