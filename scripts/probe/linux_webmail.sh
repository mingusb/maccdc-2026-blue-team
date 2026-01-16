#!/usr/bin/env bash
# Fedora Webmail probe (read-only).

set -euo pipefail

SUDO=""
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO="sudo -n"
fi

echo "## mail services"
for svc in postfix dovecot spamassassin amavis; do
  if systemctl list-unit-files | grep -q "^${svc}\.service"; then
    systemctl is-active "$svc" >/dev/null 2>&1 && systemctl status "$svc" --no-pager -l | sed -n '1,8p'
  fi
done

echo "## listeners"
ss -tulpn 2>/dev/null | egrep ':(25|110|143|587|993|995)\b' || true

echo "## selinux"
command -v sestatus >/dev/null 2>&1 && sestatus | head -n 6 || true

if command -v firewall-cmd >/dev/null 2>&1; then
  echo "## firewalld"
  $SUDO firewall-cmd --state || true
  $SUDO firewall-cmd --list-all || true
fi
