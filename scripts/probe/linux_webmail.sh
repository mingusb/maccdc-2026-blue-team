#!/usr/bin/env bash
# Fedora Webmail probe (read-only).

set -euo pipefail

MODE="full"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO="sudo -n"
  fi
fi

usage() {
  cat <<'USAGE'
Usage: linux_webmail.sh [--summary|--full]
USAGE
}

suspicious_procs_summary() {
  local allowed_prefixes=(
    "/bin" "/sbin" "/usr/bin" "/usr/sbin" "/usr/local/bin" "/usr/local/sbin"
    "/usr/lib" "/usr/lib64" "/usr/libexec" "/lib" "/lib64" "/opt" "/snap"
  )
  local suspect_count=0
  local shown=0
  local max=3
  local exe=""
  local pid=""
  local comm=""
  local allowed=false
  local suspects=()

  while read -r pid comm; do
    if [[ "$comm" == \[* ]]; then
      continue
    fi
    exe="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
    if [ -z "$exe" ]; then
      continue
    fi
    allowed=false
    for prefix in "${allowed_prefixes[@]}"; do
      if [[ "$exe" == "$prefix"* ]]; then
        allowed=true
        break
      fi
    done
    if ! $allowed; then
      suspect_count=$((suspect_count + 1))
      if [ $shown -lt $max ]; then
        suspects+=("$pid $comm $exe")
        shown=$((shown + 1))
      fi
    fi
  done < <(ps -eo pid=,comm=)

  if [ $suspect_count -eq 0 ]; then
    echo "none"
    return
  fi
  echo "count: $suspect_count"
  printf '%s\n' "${suspects[@]}"
}

summary() {
  local os_id="unknown"
  local os_ver="unknown"
  local ip_line=""

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    os_id="${ID:-unknown}"
    os_ver="${VERSION_ID:-unknown}"
  fi

  echo "## webmail summary"
  echo "host: $(hostname)"
  echo "os: ${os_id} ${os_ver}"
  ip_line="$(ip -brief addr 2>/dev/null | awk '$1 != "lo" {print; exit}')"
  if [ -n "$ip_line" ]; then
    echo "ip: $ip_line"
  fi

  echo "## services"
  for svc in postfix dovecot spamassassin amavis httpd nginx; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
      echo "${svc}: $(systemctl is-active "$svc" 2>/dev/null || true)"
    fi
  done

  echo "## listeners 25/110/143/587/993/995/80/443"
  if [ -n "$SUDO" ]; then
    $SUDO ss -tuln 2>/dev/null | grep -E ':(25|110|143|587|993|995|80|443)([^0-9]|$)' | sed -n '1,6p' || true
  else
    ss -tuln 2>/dev/null | grep -E ':(25|110|143|587|993|995|80|443)([^0-9]|$)' | sed -n '1,6p' || true
  fi

  if command -v curl >/dev/null 2>&1; then
    echo "## local web"
    http_code="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1/ || true)"
    echo "http: ${http_code}"
    if [ -n "$SUDO" ]; then
      if $SUDO ss -tuln 2>/dev/null | grep -q ':443([^0-9]|$)'; then
        https_code="$(curl -sS -k -o /dev/null -w '%{http_code}' https://127.0.0.1/ || true)"
        echo "https: ${https_code}"
      else
        echo "https not listening on 443"
      fi
    else
      if ss -tuln 2>/dev/null | grep -q ':443([^0-9]|$)'; then
        https_code="$(curl -sS -k -o /dev/null -w '%{http_code}' https://127.0.0.1/ || true)"
        echo "https: ${https_code}"
      else
        echo "https not listening on 443"
      fi
    fi
  fi

  if command -v getenforce >/dev/null 2>&1; then
    echo "## selinux"
    getenforce || true
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    echo "## firewalld"
    $SUDO firewall-cmd --state 2>/dev/null || true
  fi

  echo "## suspicious processes"
  suspicious_procs_summary
}

full() {
  echo "## mail services"
  for svc in postfix dovecot spamassassin amavis; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
      systemctl is-active "$svc" >/dev/null 2>&1 && systemctl status "$svc" --no-pager -l | sed -n '1,8p'
    fi
  done

  echo "## listeners"
  if [ -n "$SUDO" ]; then
    $SUDO ss -tulpn 2>/dev/null | grep -E ':(25|110|143|587|993|995)\b' || true
  else
    ss -tulpn 2>/dev/null | grep -E ':(25|110|143|587|993|995)\b' || true
  fi

  echo "## selinux"
  command -v sestatus >/dev/null 2>&1 && sestatus | head -n 6 || true

  if command -v firewall-cmd >/dev/null 2>&1; then
    echo "## firewalld"
    $SUDO firewall-cmd --state || true
    $SUDO firewall-cmd --list-all || true
  fi
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
