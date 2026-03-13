#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jbofs-prune.sh [--logical-prefix RELPATH] [--dry-run]

Environment:
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

LOGICAL_ROOT="${LOGICAL_ROOT:-/data/logical}"
LOGICAL_PREFIX=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
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

LOGICAL_ROOT_ABS="$(normalize_lex "$LOGICAL_ROOT")"
LOGICAL_PREFIX="${LOGICAL_PREFIX#/}"
[[ "$LOGICAL_PREFIX" != ../* ]] || fail "logical prefix must be relative"
[[ "$LOGICAL_PREFIX" != *"/../"* ]] || fail "logical prefix must be relative"

while IFS= read -r link_path; do
  rel="${link_path#$LOGICAL_ROOT_ABS/}"
  if [[ -n "$LOGICAL_PREFIX" ]]; then
    [[ "$rel" == "$LOGICAL_PREFIX" || "$rel" == "$LOGICAL_PREFIX"/* ]] || continue
  fi
  if [[ -e "$link_path" ]]; then
    continue
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "rm -f -- $link_path"
  else
    rm -f -- "$link_path"
    echo "pruned $link_path"
  fi
done < <(find "$LOGICAL_ROOT_ABS" -type l | sort 2>/dev/null || true)
