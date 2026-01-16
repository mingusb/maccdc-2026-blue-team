#!/usr/bin/env bash
# Palo Alto API helper with list/dry-run/apply/backup/restore modes.

set -euo pipefail

MODE="list"
HOST=""
USER="admin"
PASS=""
API_KEY=""
INSECURE=true
BACKUP_DIR=""
RESTORE_FROM=""
MGMT_IPS=""
DISABLE_HTTP=true
DISABLE_TELNET=true
ALLOW_UNSAFE=false

usage() {
  cat <<'USAGE'
Usage: palo_alto_manage.sh [options]

Modes:
  list | summary | dry-run | harden | apply | backup | restore

Options:
  --mode <list|summary|dry-run|harden|apply|backup|restore>
  --host <ip>             Palo Alto management IP
  --user <user>           Username (default: admin)
  --pass <pass>           Password (required if no --key)
  --key <api_key>         API key (optional)
  --insecure              Skip TLS verify (default)
  --secure                Enforce TLS verify
  --mgmt-ips <csv>         Comma-separated mgmt allow-list (e.g., 172.20.242.0/24)
  --allow-unsafe           Skip mgmt allow-list requirement
  --enable-http            Do not disable HTTP management
  --enable-telnet          Do not disable Telnet management
  --backup-dir <path>     Backup directory
  --restore-from <path>   Restore from config XML file
USAGE
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

fatal() { echo "ERROR: $*" >&2; exit 1; }

curl_opts() {
  if $INSECURE; then
    echo "-sk"
  else
    echo "-s"
  fi
}

get_key() {
  if [ -n "$API_KEY" ]; then
    return
  fi
  if [ -z "$PASS" ]; then
    fatal "--pass is required when no --key is provided"
  fi
  local resp
  local resp_one
  resp=$(curl $(curl_opts) "https://${HOST}/api/?type=keygen&user=${USER}&password=${PASS}")
  resp_one="$(echo "$resp" | tr -d '\n')"
  API_KEY=""
  if [ "${resp_one#*<key>}" != "$resp_one" ]; then
    API_KEY="${resp_one#*<key>}"
    API_KEY="${API_KEY%%</key>*}"
  fi
  if [ -z "$API_KEY" ]; then
    msg=""
    if [ "${resp_one#*<msg>}" != "$resp_one" ]; then
      msg="${resp_one#*<msg>}"
      msg="${msg%%</msg>*}"
    fi
    if [ -n "$msg" ]; then
      fatal "Failed to obtain API key: $msg"
    fi
    snippet="$(echo "$resp_one" | head -c 200)"
    fatal "Failed to obtain API key. Response: ${snippet:-empty}"
  fi
}

api_op() {
  local cmd="$1"
  curl $(curl_opts) "https://${HOST}/api/?type=op&cmd=${cmd}&key=${API_KEY}"
}

api_config_set() {
  local xpath="$1"
  local element="$2"
  curl $(curl_opts) \
    --data-urlencode "type=config" \
    --data-urlencode "action=set" \
    --data-urlencode "xpath=${xpath}" \
    --data-urlencode "element=${element}" \
    --data-urlencode "key=${API_KEY}" \
    "https://${HOST}/api/"
}

api_config_edit() {
  local xpath="$1"
  local element="$2"
  curl $(curl_opts) \
    --data-urlencode "type=config" \
    --data-urlencode "action=edit" \
    --data-urlencode "xpath=${xpath}" \
    --data-urlencode "element=${element}" \
    --data-urlencode "key=${API_KEY}" \
    "https://${HOST}/api/"
}

probe() {
  if [ -z "$HOST" ]; then
    fatal "--host is required"
  fi
  get_key
  api_op "<show><system><info></info></system></show>" >/dev/null 2>&1 || log "API probe failed"
}

list_info() {
  api_op "<show><system><info></info></system></show>" || true
}

extract_tag() {
  local xml="$1"
  local tag="$2"
  local val=""
  if [ "${xml#*<${tag}>}" != "$xml" ]; then
    val="${xml#*<${tag}>}"
    val="${val%%</${tag}>*}"
  fi
  echo "$val"
}

list_summary() {
  local xml
  local xml_one
  local hostname ipaddr netmask gateway model serial swver uptime appver avver threatver
  xml="$(api_op "<show><system><info></info></system></show>" || true)"
  xml_one="$(echo "$xml" | tr -d '\n')"
  hostname="$(extract_tag "$xml_one" "hostname")"
  ipaddr="$(extract_tag "$xml_one" "ip-address")"
  netmask="$(extract_tag "$xml_one" "netmask")"
  gateway="$(extract_tag "$xml_one" "default-gateway")"
  model="$(extract_tag "$xml_one" "model")"
  serial="$(extract_tag "$xml_one" "serial")"
  swver="$(extract_tag "$xml_one" "sw-version")"
  uptime="$(extract_tag "$xml_one" "uptime")"
  appver="$(extract_tag "$xml_one" "app-version")"
  avver="$(extract_tag "$xml_one" "av-version")"
  threatver="$(extract_tag "$xml_one" "threat-version")"

  echo "## palo alto summary"
  [ -n "$hostname" ] && echo "hostname: $hostname"
  [ -n "$ipaddr" ] && echo "mgmt_ip: ${ipaddr}${netmask:+/${netmask}}"
  [ -n "$gateway" ] && echo "gateway: $gateway"
  [ -n "$model" ] && echo "model: $model"
  [ -n "$serial" ] && echo "serial: $serial"
  [ -n "$swver" ] && echo "sw_version: $swver"
  [ -n "$appver" ] && echo "app_version: $appver"
  [ -n "$avver" ] && echo "av_version: $avver"
  [ -n "$threatver" ] && echo "threat_version: $threatver"
  [ -n "$uptime" ] && echo "uptime: $uptime"
}

plan_changes() {
  if [ "$MODE" = "dry-run" ]; then
    log "Planned changes"
  else
    log "Applying changes"
  fi
  if [ "$MODE" = "apply" ] || [ "$MODE" = "restore" ]; then
    if [ -n "$RESTORE_FROM" ]; then
      echo "- Would import and load config from $RESTORE_FROM"
    else
      echo "- No config file specified for apply/restore"
    fi
  fi
  if [ -n "$MGMT_IPS" ]; then
    echo "- Would set management permitted IPs: $MGMT_IPS"
  fi
  if $DISABLE_HTTP; then
    echo "- Would disable HTTP management"
  fi
  if $DISABLE_TELNET; then
    echo "- Would disable Telnet management"
  fi
}

backup_configs() {
  local ts outdir host
  ts="$(date +%Y%m%d-%H%M%S)"
  host="${HOST:-paloalto}"
  if [ -n "$BACKUP_DIR" ]; then
    outdir="$BACKUP_DIR"
  else
    outdir="$(pwd)/artifacts/backups/${host}-${ts}/palo_alto"
  fi
  mkdir -p "$outdir"
  local outfile
  outfile="${outdir}/paloalto-running-${ts}.xml"
  curl $(curl_opts) "https://${HOST}/api/?type=export&category=configuration&key=${API_KEY}" > "$outfile"
  log "Backup created: $outfile"
}

import_config() {
  local file="$1"
  local resp
  resp=$(curl $(curl_opts) -F "file=@${file}" "https://${HOST}/api/?type=import&category=configuration&key=${API_KEY}")
  local name
  name=$(python3 - <<PY
import sys, xml.etree.ElementTree as ET
try:
    root = ET.fromstring(sys.stdin.read())
    msg = root.findtext('.//msg') or ''
    # try to extract filename from message
    parts = msg.split()
    print(parts[-1] if parts else '')
except Exception:
    print('')
PY
<<< "$resp")
  echo "$name"
}

load_and_commit() {
  local filename="$1"
  if [ -z "$filename" ]; then
    fatal "Imported filename is empty"
  fi
  api_op "<load><config><from>${filename}</from></config></load>" >/dev/null
  curl $(curl_opts) "https://${HOST}/api/?type=commit&cmd=<commit></commit>&key=${API_KEY}" >/dev/null
}

restore_configs() {
  if [ -z "$RESTORE_FROM" ]; then
    fatal "--restore-from is required"
  fi
  if [ ! -f "$RESTORE_FROM" ]; then
    fatal "Restore file not found: $RESTORE_FROM"
  fi
  local filename
  filename=$(import_config "$RESTORE_FROM")
  load_and_commit "$filename"
  log "Restore applied from: $RESTORE_FROM"
}

require_mgmt_ips() {
  if $ALLOW_UNSAFE; then
    return
  fi
  if [ -z "$MGMT_IPS" ]; then
    fatal "--mgmt-ips is required for harden (use --allow-unsafe to override)"
  fi
}

harden_device() {
  local xpath_base
  local members=""
  xpath_base="/config/devices/entry[@name='localhost.localdomain']/deviceconfig/system"

  require_mgmt_ips

  if [ -n "$MGMT_IPS" ]; then
    while read -r ip; do
      ip="$(echo "$ip" | xargs)"
      [ -n "$ip" ] && members="${members}<member>${ip}</member>"
    done < <(echo "$MGMT_IPS" | tr ',' '\n')
    api_config_edit "${xpath_base}/permitted-ip" "${members}" >/dev/null
  fi

  if $DISABLE_HTTP; then
    api_config_set "${xpath_base}/service" "<disable-http>yes</disable-http>" >/dev/null
  fi
  if $DISABLE_TELNET; then
    api_config_set "${xpath_base}/service" "<disable-telnet>yes</disable-telnet>" >/dev/null
  fi

  curl $(curl_opts) \
    --data-urlencode "type=commit" \
    --data-urlencode "cmd=<commit></commit>" \
    --data-urlencode "key=${API_KEY}" \
    "https://${HOST}/api/" >/dev/null
  log "Commit requested"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --host) HOST="$2"; shift 2 ;;
      --user) USER="$2"; shift 2 ;;
      --pass) PASS="$2"; shift 2 ;;
      --key) API_KEY="$2"; shift 2 ;;
      --insecure) INSECURE=true; shift ;;
      --secure) INSECURE=false; shift ;;
      --mgmt-ips) MGMT_IPS="$2"; shift 2 ;;
      --allow-unsafe) ALLOW_UNSAFE=true; shift ;;
      --enable-http) DISABLE_HTTP=false; shift ;;
      --enable-telnet) DISABLE_TELNET=false; shift ;;
      --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
      --restore-from) RESTORE_FROM="$2"; shift 2 ;;
      --summary) MODE="summary"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fatal "Unknown argument: $1" ;;
    esac
  done
}

main() {
  parse_args "$@"
  case "$MODE" in
    list)
      probe
      list_info
      ;;
    summary)
      probe
      list_summary
      ;;
    harden)
      probe
      plan_changes
      backup_configs
      harden_device
      ;;
    dry-run)
      probe
      plan_changes
      ;;
    backup)
      probe
      backup_configs
      ;;
    restore)
      probe
      restore_configs
      ;;
    apply)
      probe
      plan_changes
      backup_configs
      restore_configs
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
