#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(readlink -f "$script_dir/..")"
env_file="$script_dir/.env"
compose_file="$script_dir/compose.production.yaml"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$env_file"
set +a

for variable in SERVER_NAME CADDY_EMAIL JWT_SECRET; do
  if [[ -z "${!variable:-}" ]] || [[ "${!variable}" == replace_* ]]; then
    echo "Set a real value for $variable in infra/.env" >&2
    exit 1
  fi
done

if [[ "${MOBILE_FACE_AUTH_ENABLED:-false}" != "true" ]]; then
  for variable in FACE_CLIENT_API_KEY FACE_ADMIN_API_KEY; do
    if [[ -z "${!variable:-}" ]] || [[ "${!variable}" == replace_* ]]; then
      echo "Set a real value for $variable in infra/.env" >&2
      exit 1
    fi
  done
fi

if [[ ${#JWT_SECRET} -lt 32 ]]; then
  echo "JWT_SECRET must be at least 32 characters" >&2
  exit 1
fi

if [[ "${ATTENDANCE_REQUIRE_BLE:-true}" == "true" && -z "${BLE_C6_DEVICES_JSON:-}" ]]; then
  echo "Set BLE_C6_DEVICES_JSON before enabling BLE-backed attendance" >&2
  exit 1
fi

if ! getent ahostsv4 "$SERVER_NAME" >/dev/null; then
  echo "SERVER_NAME does not resolve to an IPv4 address yet" >&2
  exit 1
fi

memory_kib="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
required_memory_kib=$((2 * 1024 * 1024))
if [[ "${MOBILE_FACE_AUTH_ENABLED:-false}" == "true" ]]; then
  required_memory_kib=$((512 * 1024))
fi
if (( memory_kib < required_memory_kib )); then
  echo "At least $((required_memory_kib / 1024)) MiB available RAM is required for this selected stack; found $((memory_kib / 1024)) MiB." >&2
  exit 1
fi

cd "$project_root"
docker compose --env-file "$env_file" -f "$compose_file" config --quiet
echo "Preflight passed for https://$SERVER_NAME"
