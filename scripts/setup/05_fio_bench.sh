#!/usr/bin/env bash
set -euo pipefail

MOUNT_ROOT="/srv/jbofs/raw"
PROFILES="seq_write,seq_read,mixed_iter"
RUNTIME=60
PARALLEL=0
DRY_RUN=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mount-root) MOUNT_ROOT="$2"; shift 2 ;;
    --profiles) PROFILES="$2"; shift 2 ;;
    --runtime) RUNTIME="$2"; shift 2 ;;
    --parallel) PARALLEL=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --apply) DRY_RUN=0; shift ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

if [[ "$DRY_RUN" -ne 1 ]] && ! command -v fio >/dev/null 2>&1; then
  echo "fio is not installed"
  exit 1
fi

if [[ ! -d "$MOUNT_ROOT" ]]; then
  echo "mount root not found: $MOUNT_ROOT"
  exit 1
fi

RUN_DIR="artifacts/fio/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_DIR"

IFS=',' read -r -a profile_arr <<< "$PROFILES"
mapfile -t mounts < <(find "$MOUNT_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)

run_one() {
  local mp="$1"
  local prof="$2"
  local rw bs iodepth rwmix
  rwmix=""
  case "$prof" in
    seq_write) rw="write"; bs="1m"; iodepth=32 ;;
    seq_read) rw="read"; bs="1m"; iodepth=32 ;;
    mixed_iter) rw="randrw"; bs="256k"; iodepth=16; rwmix="--rwmixread=80" ;;
    *) echo "unknown profile $prof"; return 2 ;;
  esac

  local disk out
  disk=$(basename "$mp")
  out="$RUN_DIR/${disk}-${prof}.json"
  local cmd=(fio "--name=${disk}-${prof}" "--directory=${mp}" "--rw=${rw}" "--bs=${bs}" "--iodepth=${iodepth}" "--ioengine=libaio" "--direct=1" "--time_based=1" "--runtime=${RUNTIME}" "--size=4G" "--output-format=json" "--output=${out}")
  if [[ -n "$rwmix" ]]; then
    cmd+=("$rwmix")
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: %q ' "${cmd[@]}"
    printf '\n'
  else
    "${cmd[@]}"
  fi
}

pids=()
for mp in "${mounts[@]}"; do
  for prof in "${profile_arr[@]}"; do
    if [[ "$PARALLEL" -eq 1 ]]; then
      run_one "$mp" "$prof" &
      pids+=("$!")
    else
      run_one "$mp" "$prof"
    fi
  done
done

if [[ "$PARALLEL" -eq 1 ]]; then
  for p in "${pids[@]}"; do
    wait "$p"
  done
fi

echo "fio outputs: $RUN_DIR"
