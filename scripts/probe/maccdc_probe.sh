#!/usr/bin/env bash
# Read-only probe for Linux hosts.

set -euo pipefail

SUDO=""
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO="sudo -n"
fi

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
command -v aa-status >/dev/null 2>&1 && aa-status | head -n 6 || true

echo "## firewall"
command -v ufw >/dev/null 2>&1 && $SUDO ufw status verbose || true
command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state && $SUDO firewall-cmd --list-all || true
command -v iptables >/dev/null 2>&1 && $SUDO iptables -S || true

echo "## disk/mem"
df -h || true
free -h || true
