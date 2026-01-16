#!/usr/bin/env bash
# Wrapper for tools/service_check.py with list/dry-run/apply modes.

set -euo pipefail

MODE="list"
CONFIG="config/services.json"
REPEAT=1
INTERVAL=30
OUTPUT_DIR="artifacts/service_checks"

usage() {
  cat <<'USAGE'
Usage: run_service_checks.sh [options]

Modes:
  list | dry-run | apply | backup | restore

Options:
  --mode <list|dry-run|apply|backup|restore>
  --config <path>        Service config JSON
  --repeat <n>           Number of runs (apply mode)
  --interval <seconds>   Delay between runs (apply mode)
  --output-dir <path>    Output directory
USAGE
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --config) CONFIG="$2"; shift 2 ;;
      --repeat) REPEAT="$2"; shift 2 ;;
      --interval) INTERVAL="$2"; shift 2 ;;
      --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
  done
}

list_services() {
  if [ ! -f "$CONFIG" ]; then
    echo "Config not found: $CONFIG" >&2
    exit 1
  fi
  python3 - <<PY
import json
with open("$CONFIG", "r", encoding="utf-8") as f:
    cfg = json.load(f)
services = cfg.get("services", [])
print(f"services: {len(services)}")
for svc in services:
    print(f"- {svc.get('name','unnamed')} ({svc.get('type','tcp')}) enabled={svc.get('enabled',True)}")
PY
}

dry_run() {
  if [ ! -f "$CONFIG" ]; then
    echo "Config not found: $CONFIG" >&2
    exit 1
  fi
  mkdir -p "$OUTPUT_DIR"
  local out
  out="${OUTPUT_DIR}/dry_run_$(date +%Y%m%d-%H%M%S).json"
  log "Running probes via service_check.py"
  python3 tools/service_check.py --config "$CONFIG" --output "$out" || true
  log "Wrote: $out"
}

apply_run() {
  if [ ! -f "$CONFIG" ]; then
    echo "Config not found: $CONFIG" >&2
    exit 1
  fi
  mkdir -p "$OUTPUT_DIR"
  local i
  for i in $(seq 1 "$REPEAT"); do
    local out
    out="${OUTPUT_DIR}/run_${i}_$(date +%Y%m%d-%H%M%S).json"
    python3 tools/service_check.py --config "$CONFIG" --output "$out" || true
    log "Wrote: $out"
    if [ "$i" -lt "$REPEAT" ]; then
      sleep "$INTERVAL"
    fi
  done
}

main() {
  parse_args "$@"
  case "$MODE" in
    list)
      list_services
      ;;
    dry-run)
      dry_run
      ;;
    apply)
      apply_run
      ;;
    backup|restore)
      log "No config changes for service checks; $MODE is a no-op."
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
