#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  cp-to-nvme.sh (--disk=N | --policy=random|most-free) [-f|--force] [--dry-run] SRC LOGICAL_DEST

Environment:
  NVME_ROOT  default: /data/nvme
  LOGICAL_ROOT  default: /data/logical
EOF
}

fail() {
  echo "$*" >&2
  exit 1
}

NVME_ROOT="${NVME_ROOT:-/data/nvme}"
LOGICAL_ROOT="${LOGICAL_ROOT:-/data/logical}"
DISK=""
POLICY=""
FORCE=0
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
    --policy=*)
      POLICY="${1#*=}"
      shift
      ;;
    --policy)
      POLICY="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=1
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

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

if [[ -n "$DISK" && -n "$POLICY" ]] || [[ -z "$DISK" && -z "$POLICY" ]]; then
  fail "exactly one of --disk=N or --policy=random|most-free must be provided"
fi

if [[ -n "$POLICY" && "$POLICY" != "random" && "$POLICY" != "most-free" ]]; then
  fail "--policy must be one of random|most-free"
fi

SRC="$1"
LOGICAL_DEST="$2"

[[ -f "$SRC" ]] || fail "source file not found: $SRC"
[[ "$LOGICAL_DEST" != /* ]] || fail "logical destination must be relative"
[[ "$LOGICAL_DEST" != ../* ]] || fail "logical destination must be relative"
[[ "$LOGICAL_DEST" != *"/../"* ]] || fail "logical destination must be relative"

list_disks() {
  find "$NVME_ROOT" -mindepth 1 -maxdepth 1 \( -type l -o -type d \) -printf '%f\n' | grep -E '^[0-9]+$' | sort -V
}

disk_avail_kb() {
  local disk="$1"
  local env_name="NVME_AVAIL_KB_${disk}"
  if [[ -n "${!env_name:-}" ]]; then
    printf '%s\n' "${!env_name}"
    return
  fi
  df -Pk "$NVME_ROOT/$disk" | awk 'NR==2 {print $4}'
}

select_disk() {
  local disk
  if [[ -n "$DISK" ]]; then
    printf '%s\n' "$DISK"
    return
  fi

  mapfile -t disks < <(list_disks)
  [[ "${#disks[@]}" -gt 0 ]] || fail "no numeric nvme aliases found under $NVME_ROOT"

  if [[ "$POLICY" == "random" ]]; then
    printf '%s\n' "${disks[RANDOM % ${#disks[@]}]}"
    return
  fi

  local best_disk=""
  local best_avail=-1
  local avail=0
  for disk in "${disks[@]}"; do
    avail="$(disk_avail_kb "$disk")"
    if (( avail > best_avail )); then
      best_avail="$avail"
      best_disk="$disk"
    fi
  done
  printf '%s\n' "$best_disk"
}

CHOSEN_DISK="$(select_disk)"
REAL_DEST="$NVME_ROOT/$CHOSEN_DISK/$LOGICAL_DEST"
LINK_DEST="$LOGICAL_ROOT/$LOGICAL_DEST"

[[ -e "$NVME_ROOT/$CHOSEN_DISK" ]] || fail "target disk alias not found: $NVME_ROOT/$CHOSEN_DISK"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "mkdir -p -- $(dirname "$REAL_DEST")"
  echo "mkdir -p -- $(dirname "$LINK_DEST")"
  if [[ "$FORCE" -eq 1 ]]; then
    echo "rm -f -- $REAL_DEST"
    echo "rm -f -- $LINK_DEST"
  fi
  echo "cp -a -- $SRC $REAL_DEST"
  echo "ln -s -- $REAL_DEST $LINK_DEST"
  exit 0
fi

mkdir -p -- "$(dirname "$REAL_DEST")" "$(dirname "$LINK_DEST")"

if [[ "$FORCE" -eq 0 ]]; then
  [[ ! -e "$REAL_DEST" ]] || fail "real destination already exists: $REAL_DEST"
  [[ ! -e "$LINK_DEST" && ! -L "$LINK_DEST" ]] || fail "logical link destination already exists: $LINK_DEST"
else
  rm -f -- "$REAL_DEST" "$LINK_DEST"
fi

cp -a -- "$SRC" "$REAL_DEST"
ln -s -- "$REAL_DEST" "$LINK_DEST"

printf 'placed on disk %s\n' "$CHOSEN_DISK"
printf 'real: %s\n' "$REAL_DEST"
printf 'link: %s\n' "$LINK_DEST"
