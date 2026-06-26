#!/usr/bin/env bash
set -euo pipefail

mqtt_host="${MQTT_HOST:-127.0.0.1}"
mqtt_port="${MQTT_PORT:-1883}"
base_topic="${ZIGBEE2MQTT_BASE_TOPIC:-zigbee2mqtt}"
timeout="${MQTT_TIMEOUT_SECONDS:-15}"
dry_run=0

usage() {
  cat <<'EOF'
Usage: i4-configure-zigbee-sockets [--dry-run]

Configures Zigbee2MQTT smart sockets to:
  indicator_mode=off
  power_outage_memory=restore

Environment:
  MQTT_HOST                MQTT broker host, default: 127.0.0.1
  MQTT_PORT                MQTT broker port, default: 1883
  ZIGBEE2MQTT_BASE_TOPIC   Zigbee2MQTT base topic, default: zigbee2mqtt
  MQTT_TIMEOUT_SECONDS     MQTT subscribe timeout, default: 15
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for cmd in jq mosquitto_pub mosquitto_sub mktemp sleep; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 127
  fi
done

devices_json="$(
  mosquitto_sub \
    -h "$mqtt_host" \
    -p "$mqtt_port" \
    -t "${base_topic}/bridge/devices" \
    -C 1 \
    -W "$timeout"
)"

target_devices="$(
  printf '%s\n' "$devices_json" |
    jq -c '
      [
        .[]
        | select(.type != "Coordinator")
        | [.. | objects | .property? // empty] as $properties
        | select(
            ($properties | index("power_outage_memory") != null)
            and (($properties | index("power") != null) or (.definition.model // "" == "A7Z"))
          )
        | {
            friendly_name,
            ieee_address,
            vendor: (.definition.vendor // ""),
            model: (.definition.model // "")
          }
      ]
    '
)"

target_count="$(printf '%s\n' "$target_devices" | jq 'length')"

if [[ "$target_count" -eq 0 ]]; then
  echo "No matching Zigbee2MQTT smart sockets found."
  exit 0
fi

echo "Found $target_count matching Zigbee2MQTT smart socket(s):"
printf '%s\n' "$target_devices" |
  jq -r '.[] | "  \(.friendly_name)\t\(.vendor) \(.model)\t\(.ieee_address)"'

if [[ "$dry_run" -eq 1 ]]; then
  echo "Dry run: not publishing configuration changes."
  exit 0
fi

mapfile -t devices < <(printf '%s\n' "$target_devices" | jq -r '.[].friendly_name')

payload='{"indicator_mode":"off","power_outage_memory":"restore"}'

for device in "${devices[@]}"; do
  echo "Configuring $device"
  mosquitto_pub \
    -h "$mqtt_host" \
    -p "$mqtt_port" \
    -t "${base_topic}/${device}/set" \
    -m "$payload"
done

sleep 2

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

failures=0

for device in "${devices[@]}"; do
  tmp="${tmpdir}/${device//[^A-Za-z0-9_.-]/_}.json"

  mosquitto_sub \
    -h "$mqtt_host" \
    -p "$mqtt_port" \
    -t "${base_topic}/${device}" \
    -C 1 \
    -W "$timeout" >"$tmp" &
  sub_pid=$!

  sleep 1

  if ! mosquitto_pub \
    -h "$mqtt_host" \
    -p "$mqtt_port" \
    -t "${base_topic}/${device}/get" \
    -m '{"state":"","power_outage_memory":""}'; then
    echo "Failed to request state from $device" >&2
    failures=$((failures + 1))
    continue
  fi

  if ! wait "$sub_pid"; then
    echo "Timed out waiting for state from $device" >&2
    failures=$((failures + 1))
    continue
  fi

  if jq -e '.indicator_mode == "off" and .power_outage_memory == "restore"' "$tmp" >/dev/null; then
    jq -r --arg device "$device" \
      '"Verified \($device): indicator_mode=\(.indicator_mode) power_outage_memory=\(.power_outage_memory)"' \
      "$tmp"
  else
    echo "Verification failed for $device:" >&2
    jq '{indicator_mode, power_outage_memory, state, linkquality}' "$tmp" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -gt 0 ]]; then
  echo "$failures device(s) failed verification." >&2
  exit 1
fi
