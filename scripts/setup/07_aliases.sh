#!/usr/bin/env bash
set -euo pipefail

NVME_ROOT="${NVME_ROOT:-/data/nvme}"
LOGICAL_ROOT="${LOGICAL_ROOT:-/data/logical}"
SELECTED_CONFIG="${SELECTED_CONFIG:-config/selected-devices.yaml}"

if [[ ! -f "$SELECTED_CONFIG" ]]; then
  echo "selected-devices config not found: $SELECTED_CONFIG" >&2
  exit 1
fi

mapfile -t selected_ids < <(grep -E '^[[:space:]]*-' "$SELECTED_CONFIG" | sed -E 's/^[[:space:]]*-[[:space:]]*//')

if [[ "${#selected_ids[@]}" -eq 0 ]]; then
  echo "no selected devices found in $SELECTED_CONFIG" >&2
  exit 1
fi

sudo mkdir -p "$LOGICAL_ROOT"

index=0
for stable_id in "${selected_ids[@]}"; do
  target="$NVME_ROOT/$stable_id"
  alias_path="$NVME_ROOT/$index"
  if [[ ! -e "$target" ]]; then
    echo "missing target mount: $target" >&2
    exit 1
  fi
  sudo ln -sfn "$target" "$alias_path"
  printf '%s -> %s\n' "$alias_path" "$target"
  index=$((index + 1))
done

printf 'logical root -> %s\n' "$LOGICAL_ROOT"
