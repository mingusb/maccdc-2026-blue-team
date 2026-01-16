#!/usr/bin/env bash
# Ubuntu Ecom probe (read-only).

set -euo pipefail

SUDO=""
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO="sudo -n"
fi

echo "## ecom web stack"
for svc in apache2 nginx php-fpm php8.3-fpm php8.2-fpm; do
  if systemctl list-unit-files | grep -q "^${svc}\.service"; then
    systemctl is-active "$svc" >/dev/null 2>&1 && systemctl status "$svc" --no-pager -l | sed -n '1,8p'
  fi
done

if command -v apache2ctl >/dev/null 2>&1; then
  echo "## apache2 vhosts"
  apache2ctl -S 2>/dev/null | head -n 12 || true
fi

echo "## database"
for svc in mysql mariadb; do
  if systemctl list-unit-files | grep -q "^${svc}\.service"; then
    systemctl is-active "$svc" >/dev/null 2>&1 && systemctl status "$svc" --no-pager -l | sed -n '1,8p'
  fi
done

echo "## web listeners"
if [ -n "$SUDO" ]; then
  listeners="$($SUDO ss -tulpn 2>/dev/null | egrep ':(80|443)\b' || true)"
else
  listeners="$(ss -tulpn 2>/dev/null | egrep ':(80|443)\b' || true)"
fi
if [ -n "$listeners" ]; then
  echo "$listeners"
else
  echo "no listeners on 80/443"
fi

if command -v curl >/dev/null 2>&1; then
  echo "## local http"
  curl -sS -I http://127.0.0.1/ | head -n 10 || true
  echo "## local https"
  if echo "$listeners" | grep -q ':443\b'; then
    curl -sS -k -I https://127.0.0.1/ | head -n 10 || true
  else
    echo "https not listening on 443"
  fi
fi

echo "## apparmor"
if command -v aa-status >/dev/null 2>&1; then
  if [ -n "$SUDO" ]; then
    $SUDO aa-status | head -n 8 || true
  else
    aa-status | head -n 8 || true
  fi
fi

if command -v ufw >/dev/null 2>&1; then
  echo "## ufw"
  $SUDO ufw status verbose || true
fi
