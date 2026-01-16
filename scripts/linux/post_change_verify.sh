#!/usr/bin/env bash
# Post-change verification: service checks + local health snapshots.

set -u

usage() {
  echo "Usage: $0 [-c config_json] [-o output_dir] [-t tag]" >&2
}

CONFIG=""
OUTPUT_DIR=""
TAG=""
while getopts ":c:o:t:h" opt; do
  case "$opt" in
    c) CONFIG="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    t) TAG="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
TS="$(date +%Y%m%d-%H%M%S)"

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="${REPO_ROOT}/artifacts/post_change/${HOSTNAME_SHORT}-${TS}"
fi

if [ -z "$CONFIG" ]; then
  CONFIG="${REPO_ROOT}/config/services.json"
fi

mkdir -p "$OUTPUT_DIR"

if [ -n "$TAG" ]; then
  echo "tag: $TAG" > "${OUTPUT_DIR}/tag.txt"
fi

SERVICE_OUT="${OUTPUT_DIR}/service_check.json"
if command -v python3 >/dev/null 2>&1 && [ -f "$CONFIG" ]; then
  python3 "${REPO_ROOT}/tools/service_check.py" --config "$CONFIG" --output "$SERVICE_OUT" || true
else
  echo "service_check skipped (missing python3 or config)" > "${OUTPUT_DIR}/service_check.txt"
fi

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
run_cmd "$SYS_FILE" "uptime"
run_cmd "$SYS_FILE" "who -a"

if command -v timedatectl >/dev/null 2>&1; then
  run_cmd "$SYS_FILE" "timedatectl"
fi

if command -v ip >/dev/null 2>&1; then
  run_cmd "$NET_FILE" "ip -brief addr"
  run_cmd "$NET_FILE" "ip route"
fi
if command -v ss >/dev/null 2>&1; then
  run_cmd "$NET_FILE" "ss -tulpn"
fi

if command -v systemctl >/dev/null 2>&1; then
  run_cmd "$SVC_FILE" "systemctl --failed"
  run_cmd "$SVC_FILE" "systemctl --type=service --state=running"
fi

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

echo "Post-change verification captured in: $OUTPUT_DIR"
