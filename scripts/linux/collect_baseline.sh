#!/usr/bin/env bash
# Collects read-only baseline info for a Linux host.

set -u

usage() {
  echo "Usage: $0 [-o output_dir]" >&2
}

OUTPUT_DIR=""
while getopts ":o:h" opt; do
  case "$opt" in
    o) OUTPUT_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TS="$(date +%Y%m%d-%H%M%S)"

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="${REPO_ROOT}/artifacts/baselines/${HOSTNAME_SHORT}-${TS}"
fi

mkdir -p "$OUTPUT_DIR"

run_cmd() {
  local file="$1"
  shift
  local cmd="$*"
  {
    echo "## $cmd"
    if eval "$cmd"; then
      echo ""
    else
      echo "command failed: $cmd"
      echo ""
    fi
  } >> "$file" 2>&1
}

SYS_FILE="${OUTPUT_DIR}/system.txt"
NET_FILE="${OUTPUT_DIR}/network.txt"
SVC_FILE="${OUTPUT_DIR}/services.txt"
FW_FILE="${OUTPUT_DIR}/firewall.txt"

run_cmd "$SYS_FILE" "date -u"
run_cmd "$SYS_FILE" "hostname"
run_cmd "$SYS_FILE" "uname -a"
run_cmd "$SYS_FILE" "cat /etc/os-release"
if command -v lsb_release >/dev/null 2>&1; then
  run_cmd "$SYS_FILE" "lsb_release -a"
fi
run_cmd "$SYS_FILE" "uptime"
run_cmd "$SYS_FILE" "who -a"
run_cmd "$SYS_FILE" "last -a | head -n 20"

if command -v ip >/dev/null 2>&1; then
  run_cmd "$NET_FILE" "ip -brief addr"
  run_cmd "$NET_FILE" "ip route"
fi
if command -v ss >/dev/null 2>&1; then
  run_cmd "$NET_FILE" "ss -tulpn"
fi

if command -v systemctl >/dev/null 2>&1; then
  run_cmd "$SVC_FILE" "systemctl --type=service --state=running"
fi
run_cmd "$SVC_FILE" "ps aux --sort=-%cpu | head -n 20"

if command -v ufw >/dev/null 2>&1; then
  run_cmd "$FW_FILE" "ufw status verbose"
fi
if command -v firewall-cmd >/dev/null 2>&1; then
  run_cmd "$FW_FILE" "firewall-cmd --state"
  run_cmd "$FW_FILE" "firewall-cmd --list-all"
fi
if command -v iptables >/dev/null 2>&1; then
  run_cmd "$FW_FILE" "iptables -S"
fi

run_cmd "$SYS_FILE" "df -h"
run_cmd "$SYS_FILE" "free -h"

echo "Baseline captured in: $OUTPUT_DIR"
