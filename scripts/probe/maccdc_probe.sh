#!/usr/bin/env bash
# Read-only probe for Linux hosts.

set -euo pipefail

MODE="full"
SUDO=""
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO="sudo -n"
fi

usage() {
  cat <<'USAGE'
Usage: maccdc_probe.sh [--summary|--full]
USAGE
}

summary() {
  echo "## time"
  date -u

  echo "## os"
  [ -f /etc/os-release ] && grep -E '^(ID|VERSION_ID)=' /etc/os-release || true

  echo "## host"
  hostname

  echo "## network"
  ip -brief addr 2>/dev/null | sed -n '1,3p' || true
  ip route 2>/dev/null | sed -n '1,3p' || true

  echo "## listeners (key ports)"
  if [ -n "$SUDO" ]; then
    $SUDO ss -tulpn 2>/dev/null | egrep ':(22|25|53|80|110|143|443|587|993|995)\b' | sed -n '1,8p' || true
  else
    ss -tulpn 2>/dev/null | egrep ':(22|25|53|80|110|143|443|587|993|995)\b' | sed -n '1,8p' || true
  fi

  echo "## sshd config (key directives)"
  grep -E '^(Port|PermitRootLogin|PasswordAuthentication|AllowUsers|AllowGroups|Match)' /etc/ssh/sshd_config 2>/dev/null || true

  echo "## selinux / apparmor"
  command -v sestatus >/dev/null 2>&1 && sestatus | head -n 4 || true
  if command -v aa-status >/dev/null 2>&1; then
    if [ -n "$SUDO" ]; then
      $SUDO aa-status | head -n 4 || true
    else
      aa-status | head -n 4 || true
    fi
  fi

  echo "## firewall"
  command -v ufw >/dev/null 2>&1 && $SUDO ufw status verbose | head -n 3 || true
  command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state | head -n 1 || true
}

full() {
  echo "## time"
  date -u

  echo "## os"
  [ -f /etc/os-release ] && cat /etc/os-release
  uname -a

  echo "## host"
  hostname
  hostname -f 2>/dev/null || true

  echo "## network"
  ip -brief addr || true
  ip route || true

  echo "## services (key)"
  for svc in ssh sshd apache2 nginx postfix dovecot vsftpd proftpd; do
    if systemctl is-active "$svc" >/dev/null 2>&1; then
      echo "--- $svc ---"
      systemctl status "$svc" --no-pager -l | sed -n '1,8p'
    fi
  done

  echo "## listeners"
  if [ -n "$SUDO" ]; then
    $SUDO ss -tulpn 2>/dev/null || $SUDO ss -tuln || true
  else
    ss -tulpn 2>/dev/null || ss -tuln || true
  fi

  echo "## sshd config (key directives)"
  grep -E '^(Port|PermitRootLogin|PasswordAuthentication|AllowUsers|AllowGroups|Match)' /etc/ssh/sshd_config 2>/dev/null || true
  [ -d /etc/ssh/sshd_config.d ] && ls -la /etc/ssh/sshd_config.d || true

  echo "## selinux / apparmor"
  command -v sestatus >/dev/null 2>&1 && sestatus | head -n 6 || true
  if command -v aa-status >/dev/null 2>&1; then
    if [ -n "$SUDO" ]; then
      $SUDO aa-status | head -n 6 || true
    else
      aa-status | head -n 6 || true
    fi
  fi

  echo "## firewall"
  command -v ufw >/dev/null 2>&1 && $SUDO ufw status verbose || true
  command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state && $SUDO firewall-cmd --list-all || true
  command -v iptables >/dev/null 2>&1 && $SUDO iptables -S || true

  echo "## disk/mem"
  df -h || true
  free -h || true
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --summary) MODE="summary"; shift ;;
    --full) MODE="full"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [ "$MODE" = "summary" ]; then
  summary
else
  full
fi
