#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(readlink -f "$script_dir/..")"
compose_file="$script_dir/compose.production.300.yaml"
env_file="$script_dir/.env"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file" >&2
  exit 1
fi

cpu_count="$(nproc)"
memory_kib="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
minimum_memory_kib=$((128 * 1024 * 1024))

if (( cpu_count < 192 )); then
  echo "Need at least 192 logical CPUs for the single-host 40-shard stack; found $cpu_count." >&2
  exit 1
fi

if (( memory_kib < minimum_memory_kib )); then
  echo "Need at least 128 GiB RAM for the single-host 40-shard stack." >&2
  exit 1
fi

cd "$project_root"
docker compose --env-file "$env_file" -f "$compose_file" config --quiet

echo "Preflight passed: CPUs=$cpu_count RAM_GiB=$((memory_kib / 1024 / 1024))"
echo "This only validates host capacity and configuration; run the staging load test before real use."
