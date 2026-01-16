#!/usr/bin/env bash
# Splunk server probe (read-only).

set -euo pipefail

SPLUNK_HOME="/opt/splunk"

if [ -x "${SPLUNK_HOME}/bin/splunk" ]; then
  echo "## splunk status"
  "${SPLUNK_HOME}/bin/splunk" status || true
fi

echo "## listeners"
ss -tulpn 2>/dev/null | egrep ':(8000|8089|9997)\b' || true

echo "## systemd"
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active splunk >/dev/null 2>&1 && systemctl status splunk --no-pager -l | sed -n '1,8p'
fi

echo "## selinux"
command -v sestatus >/dev/null 2>&1 && sestatus | head -n 6 || true
