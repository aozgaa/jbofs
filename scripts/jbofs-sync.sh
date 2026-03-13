#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jbofs-sync.sh [--disk=N | --disk-path PATH] [--logical-prefix RELPATH] [--dry-run]

Environment:
  NVME_ROOT     default: /data/nvme
  LOGICAL_ROOT  default: /data/logical
EOF
}

fail() {
  echo "$*" >&2
  exit 1
}

normalize_lex() {
  python3 - "$1" <<'PY'
import os
import sys
print(os.path.abspath(os.path.normpath(sys.argv[1])))
PY
}

under_root() {
  local path="$1"
  local root="$2"
  [[ "$path" == "$root" || "$path" == "$root"/* ]]
}

NVME_ROOT="${NVME_ROOT:-/data/nvme}"
LOGICAL_ROOT="${LOGICAL_ROOT:-/data/logical}"
DISK=""
DISK_PATH=""
LOGICAL_PREFIX=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk=*)
      DISK="${1#*=}"
      shift
      ;;
    --disk)
      DISK="$2"
      shift 2
      ;;
    --disk-path)
      DISK_PATH="$2"
      shift 2
      ;;
    --logical-prefix)
      LOGICAL_PREFIX="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown arg: $1"
      ;;
  esac
done

if [[ -n "$DISK" && -n "$DISK_PATH" ]]; then
  fail "--disk and --disk-path are mutually exclusive"
fi

LOGICAL_PREFIX="${LOGICAL_PREFIX#/}"
[[ "$LOGICAL_PREFIX" != ../* ]] || fail "logical prefix must be relative"
[[ "$LOGICAL_PREFIX" != *"/../"* ]] || fail "logical prefix must be relative"

NVME_ROOT_ABS="$(normalize_lex "$NVME_ROOT")"
LOGICAL_ROOT_ABS="$(normalize_lex "$LOGICAL_ROOT")"

mapfile -t stable_roots < <(find "$NVME_ROOT_ABS" -mindepth 1 -maxdepth 1 -type d | sort)

declare -a scan_pairs=()

if [[ -n "$DISK" ]]; then
  alias_path="$NVME_ROOT_ABS/$DISK"
  [[ -e "$alias_path" ]] || fail "disk alias not found: $alias_path"
  stable_root="$(readlink -f -- "$alias_path")"
  [[ -d "$stable_root" ]] || fail "resolved disk path is not a directory: $stable_root"
  scan_pairs+=("$stable_root|$stable_root")
elif [[ -n "$DISK_PATH" ]]; then
  [[ -e "$DISK_PATH" ]] || fail "disk path not found: $DISK_PATH"
  scan_path="$(readlink -f -- "$DISK_PATH")"
  under_root "$(normalize_lex "$scan_path")" "$NVME_ROOT_ABS" || fail "disk path must be under $NVME_ROOT_ABS"
  matched_root=""
  for root in "${stable_roots[@]}"; do
    if under_root "$scan_path" "$root"; then
      matched_root="$root"
      break
    fi
  done
  [[ -n "$matched_root" ]] || fail "could not map disk path to a stable mount root"
  scan_pairs+=("$matched_root|$scan_path")
else
  for root in "${stable_roots[@]}"; do
    scan_pairs+=("$root|$root")
  done
fi

create_link() {
  local physical="$1"
  local logical="$2"

  if [[ -L "$logical" ]]; then
    target="$(readlink -f -- "$logical" || true)"
    if [[ -n "$target" && "$(normalize_lex "$target")" == "$(normalize_lex "$physical")" ]]; then
      return 0
    fi
    echo "conflict: $logical points somewhere else" >&2
    return 0
  fi

  if [[ -e "$logical" ]]; then
    echo "conflict: $logical already exists" >&2
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "mkdir -p -- $(dirname "$logical")"
    echo "ln -s -- $physical $logical"
    return 0
  fi

  mkdir -p -- "$(dirname "$logical")"
  ln -s -- "$physical" "$logical"
  echo "linked $logical"
}

for pair in "${scan_pairs[@]}"; do
  stable_root="${pair%%|*}"
  scan_root="${pair#*|}"
  [[ -d "$scan_root" ]] || continue
  while IFS= read -r physical; do
    rel="${physical#$stable_root/}"
    if [[ "$rel" == "$physical" ]]; then
      continue
    fi
    if [[ -n "$LOGICAL_PREFIX" ]]; then
      [[ "$rel" == "$LOGICAL_PREFIX" || "$rel" == "$LOGICAL_PREFIX"/* ]] || continue
    fi
    logical="$LOGICAL_ROOT_ABS/$rel"
    create_link "$physical" "$logical"
  done < <(find "$scan_root" -type f | sort)
done
