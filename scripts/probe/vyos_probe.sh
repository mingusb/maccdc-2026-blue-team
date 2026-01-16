#!/usr/bin/env bash
# VyOS probe wrapper (read-only).

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: vyos_probe.sh --host <ip> [--user <user>] [--ssh-key <path>] [--ssh-port <port>]
USAGE
}

ARGS=("--mode" "list")
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host|--user|--ssh-key|--ssh-port)
      ARGS+=("$1" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

exec "$(dirname "$0")/../firewalls/vyos_manage.sh" "${ARGS[@]}"
