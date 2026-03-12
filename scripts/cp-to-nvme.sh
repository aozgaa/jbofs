#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  cp-to-nvme.sh (--disk=N | --policy=random|most-free) [-r|--recursive] [--round-robin|--batch] [-f|--force] [--dry-run] SRC LOGICAL_DEST

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
RECURSIVE=0
GROUP_MODE=""
GROUP_COUNT=0

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
    -r|--recursive)
      RECURSIVE=1
      shift
      ;;
    --round-robin)
      GROUP_MODE="round-robin"
      GROUP_COUNT=$((GROUP_COUNT + 1))
      shift
      ;;
    --batch)
      GROUP_MODE="batch"
      GROUP_COUNT=$((GROUP_COUNT + 1))
      shift
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

SRC_HAS_TRAILING_SLASH=0
[[ "$SRC" == */ ]] && SRC_HAS_TRAILING_SLASH=1
SRC_STRIPPED="${SRC%/}"
[[ -n "$SRC_STRIPPED" ]] || SRC_STRIPPED="/"

if [[ "$RECURSIVE" -eq 1 ]]; then
  [[ -d "$SRC_STRIPPED" ]] || fail "source directory not found: $SRC"
else
  [[ -f "$SRC_STRIPPED" ]] || fail "source file not found: $SRC"
fi
[[ "$LOGICAL_DEST" != /* ]] || fail "logical destination must be relative"
[[ "$LOGICAL_DEST" != ../* ]] || fail "logical destination must be relative"
[[ "$LOGICAL_DEST" != *"/../"* ]] || fail "logical destination must be relative"

if [[ "$RECURSIVE" -eq 1 ]]; then
  if (( GROUP_COUNT != 1 )); then
    fail "recursive mode requires exactly one of --round-robin or --batch"
  fi
else
  [[ -z "$GROUP_MODE" ]] || fail "--round-robin/--batch require --recursive"
fi

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

copy_one() {
  local src_file="$1"
  local logical_rel="$2"
  local chosen_disk="$3"
  local real_dest="$NVME_ROOT/$chosen_disk/$logical_rel"
  local link_dest="$LOGICAL_ROOT/$logical_rel"

  [[ -e "$NVME_ROOT/$chosen_disk" ]] || fail "target disk alias not found: $NVME_ROOT/$chosen_disk"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "mkdir -p -- $(dirname "$real_dest")"
    echo "mkdir -p -- $(dirname "$link_dest")"
    if [[ "$FORCE" -eq 1 ]]; then
      echo "rm -f -- $real_dest"
      echo "rm -f -- $link_dest"
    fi
    echo "cp -a -- $src_file $real_dest"
    echo "ln -s -- $real_dest $link_dest"
    return
  fi

  mkdir -p -- "$(dirname "$real_dest")" "$(dirname "$link_dest")"

  if [[ "$FORCE" -eq 0 ]]; then
    [[ ! -e "$real_dest" ]] || fail "real destination already exists: $real_dest"
    [[ ! -e "$link_dest" && ! -L "$link_dest" ]] || fail "logical link destination already exists: $link_dest"
  else
    rm -f -- "$real_dest" "$link_dest"
  fi

  cp -a -- "$src_file" "$real_dest"
  ln -s -- "$real_dest" "$link_dest"

  printf 'placed on disk %s\n' "$chosen_disk"
  printf 'real: %s\n' "$real_dest"
  printf 'link: %s\n' "$link_dest"
}

if [[ "$RECURSIVE" -eq 0 ]]; then
  CHOSEN_DISK="$(select_disk)"
  copy_one "$SRC_STRIPPED" "$LOGICAL_DEST" "$CHOSEN_DISK"
  exit 0
fi

base_dir="$SRC_STRIPPED"
dest_prefix="$LOGICAL_DEST"
if [[ "$SRC_HAS_TRAILING_SLASH" -eq 0 ]]; then
  src_name="$(basename -- "$SRC_STRIPPED")"
  dest_prefix="$LOGICAL_DEST/$src_name"
fi

mapfile -t source_files < <(find "$base_dir" -type f | sort)
[[ "${#source_files[@]}" -gt 0 ]] || exit 0

if [[ "$GROUP_MODE" == "batch" ]]; then
  batch_disk="$(select_disk)"
fi

idx=0
for src_file in "${source_files[@]}"; do
  rel="${src_file#$base_dir/}"
  logical_rel="$dest_prefix/$rel"
  if [[ "$GROUP_MODE" == "batch" ]]; then
    chosen_disk="$batch_disk"
  else
    mapfile -t disks < <(list_disks)
    [[ "${#disks[@]}" -gt 0 ]] || fail "no numeric nvme aliases found under $NVME_ROOT"
    chosen_disk="${disks[$((idx % ${#disks[@]}))]}"
  fi
  copy_one "$src_file" "$logical_rel" "$chosen_disk"
  idx=$((idx + 1))
done
