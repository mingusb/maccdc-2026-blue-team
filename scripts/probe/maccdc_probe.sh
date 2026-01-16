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
  local route_line=""
  local line=""
  local count=""
  local state=""

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    os_id="${ID:-unknown}"
    os_ver="${VERSION_ID:-unknown}"
  fi

  echo "## summary"
  echo "time: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "host: $(hostname)"
  echo "os: ${os_id} ${os_ver}"

  ip_line="$(ip -brief addr 2>/dev/null | awk '$1 != "lo" {print; exit}')"
  if [ -n "$ip_line" ]; then
    echo "ip: $ip_line"
  fi
  route_line="$(ip route show default 2>/dev/null | head -n 1 || true)"
  if [ -n "$route_line" ]; then
    echo "route: $route_line"
  fi

  echo "## listeners (key ports)"
  local listeners=""
  if [ -n "$SUDO" ]; then
    listeners="$($SUDO ss -tuln 2>/dev/null | grep -E ':(22|25|53|80|110|143|443|587|993|995)([^0-9]|$)' | sed -n '1,5p' || true)"
  else
    listeners="$(ss -tuln 2>/dev/null | grep -E ':(22|25|53|80|110|143|443|587|993|995)([^0-9]|$)' | sed -n '1,5p' || true)"
  fi
  if [ -n "$listeners" ]; then
    echo "$listeners"
  else
    echo "listeners: none"
  fi

  echo "## sshd (key directives)"
  grep -E '^(Port|PermitRootLogin|PasswordAuthentication|AllowUsers|AllowGroups|Match)' /etc/ssh/sshd_config 2>/dev/null | sed -n '1,4p' || true
  if [ -d /etc/ssh/sshd_config.d ]; then
    count="$(ls -1 /etc/ssh/sshd_config.d 2>/dev/null | wc -l | tr -d ' ')"
    echo "sshd_config.d files: ${count:-0}"
  fi

  echo "## selinux / apparmor"
  if command -v sestatus >/dev/null 2>&1; then
    line="$(sestatus 2>/dev/null | grep -m 1 '^SELinux status' || true)"
    [ -n "$line" ] && echo "$line"
  fi
  if command -v aa-status >/dev/null 2>&1; then
    if [ -n "$SUDO" ]; then
      line="$($SUDO aa-status 2>/dev/null | head -n 1 || true)"
    else
      line="$(aa-status 2>/dev/null | head -n 1 || true)"
    fi
    [ -n "$line" ] && echo "$line"
  fi

  echo "## firewall"
  if command -v ufw >/dev/null 2>&1; then
    line="$($SUDO ufw status 2>/dev/null | head -n 1 || true)"
    [ -n "$line" ] && echo "ufw: $line"
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    state="$($SUDO firewall-cmd --state 2>/dev/null | head -n 1 || true)"
    [ -n "$state" ] && echo "firewalld: $state"
  fi

  echo "## suspicious processes"
  suspicious_procs_summary
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
