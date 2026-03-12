#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  rm-nvme.sh [--ensure-logical|--ensure-physical|--ensure-data] [--rm-link|--rm-data|--rm-both] [--dry-run] PATH

Defaults:
  --ensure-data --rm-both

Environment:
  DATA_ROOT     default: /data
  LOGICAL_ROOT  default: /data/logical
  NVME_ROOT     default: /data/nvme
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

DATA_ROOT="${DATA_ROOT:-/data}"
LOGICAL_ROOT="${LOGICAL_ROOT:-$DATA_ROOT/logical}"
NVME_ROOT="${NVME_ROOT:-$DATA_ROOT/nvme}"
ENSURE_MODE="data"
ENSURE_COUNT=0
REMOVE_MODE="both"
REMOVE_COUNT=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ensure-logical)
      ENSURE_MODE="logical"
      ENSURE_COUNT=$((ENSURE_COUNT + 1))
      shift
      ;;
    --ensure-physical)
      ENSURE_MODE="physical"
      ENSURE_COUNT=$((ENSURE_COUNT + 1))
      shift
      ;;
    --ensure-data)
      ENSURE_MODE="data"
      ENSURE_COUNT=$((ENSURE_COUNT + 1))
      shift
      ;;
    --rm-link)
      REMOVE_MODE="link"
      REMOVE_COUNT=$((REMOVE_COUNT + 1))
      shift
      ;;
    --rm-data)
      REMOVE_MODE="data"
      REMOVE_COUNT=$((REMOVE_COUNT + 1))
      shift
      ;;
    --rm-both)
      REMOVE_MODE="both"
      REMOVE_COUNT=$((REMOVE_COUNT + 1))
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      fail "unknown arg: $1"
      ;;
    *)
      break
      ;;
  esac
done

if (( ENSURE_COUNT > 1 )); then
  fail "ensure flags are mutually exclusive"
fi

if (( REMOVE_COUNT > 1 )); then
  fail "rm-* flags are mutually exclusive"
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

INPUT_PATH="$1"
INPUT_ABS="$(normalize_lex "$INPUT_PATH")"
DATA_ROOT_ABS="$(normalize_lex "$DATA_ROOT")"
LOGICAL_ROOT_ABS="$(normalize_lex "$LOGICAL_ROOT")"
NVME_ROOT_ABS="$(normalize_lex "$NVME_ROOT")"

under_root() {
  local path="$1"
  local root="$2"
  [[ "$path" == "$root" || "$path" == "$root"/* ]]
}

remove_file() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "rm -f -- $path"
    return 0
  fi
  rm -f -- "$path"
}

if ! under_root "$INPUT_ABS" "$DATA_ROOT_ABS"; then
  fail "path must be under $DATA_ROOT_ABS"
fi

case "$ENSURE_MODE" in
  logical)
    under_root "$INPUT_ABS" "$LOGICAL_ROOT_ABS" || fail "path must be under $LOGICAL_ROOT_ABS"
    ;;
  physical)
    under_root "$INPUT_ABS" "$NVME_ROOT_ABS" || fail "path must be under $NVME_ROOT_ABS"
    ;;
  data)
    ;;
esac

declare -a LOGICAL_PATHS=()
PHYSICAL_PATH=""

if under_root "$INPUT_ABS" "$LOGICAL_ROOT_ABS"; then
  [[ -L "$INPUT_ABS" ]] || fail "logical path must be a symlink: $INPUT_ABS"
  LOGICAL_PATHS+=("$INPUT_ABS")
  PHYSICAL_PATH="$(readlink -f -- "$INPUT_ABS" || true)"
  [[ -n "$PHYSICAL_PATH" ]] || fail "unable to resolve symlink target: $INPUT_ABS"
  under_root "$(normalize_lex "$PHYSICAL_PATH")" "$NVME_ROOT_ABS" || fail "logical symlink target must be under $NVME_ROOT_ABS"
elif under_root "$INPUT_ABS" "$NVME_ROOT_ABS"; then
  if [[ -L "$INPUT_ABS" ]]; then
    PHYSICAL_PATH="$(readlink -f -- "$INPUT_ABS" || true)"
  else
    PHYSICAL_PATH="$INPUT_ABS"
  fi
  [[ -n "$PHYSICAL_PATH" ]] || fail "unable to resolve physical path: $INPUT_ABS"
  PHYSICAL_PATH="$(normalize_lex "$PHYSICAL_PATH")"
  while IFS= read -r link_path; do
    target="$(readlink -f -- "$link_path" || true)"
    if [[ -n "$target" && "$(normalize_lex "$target")" == "$PHYSICAL_PATH" ]]; then
      LOGICAL_PATHS+=("$link_path")
    fi
  done < <(find "$LOGICAL_ROOT_ABS" -type l -print 2>/dev/null || true)
else
  fail "path must be under logical or physical nvme roots"
fi

case "$REMOVE_MODE" in
  link)
    for path in "${LOGICAL_PATHS[@]}"; do
      remove_file "$path"
    done
    ;;
  data)
    remove_file "$PHYSICAL_PATH"
    ;;
  both)
    for path in "${LOGICAL_PATHS[@]}"; do
      remove_file "$path"
    done
    remove_file "$PHYSICAL_PATH"
    ;;
esac

if [[ "$DRY_RUN" -eq 0 ]]; then
  echo "done"
fi
