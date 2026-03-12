#!/usr/bin/env bash
set -euo pipefail

PLAN="artifacts/setup-plan.sh"
APPLY=0
CONFIRM=""
EXPECTED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --confirm) CONFIRM="$2"; shift 2 ;;
    --expected-confirm) EXPECTED="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

if [[ "$APPLY" -ne 1 ]]; then
  echo "Dry-run mode: refusing to execute destructive plan. Use --apply --confirm <token>."
  exit 1
fi

if [[ ! -f "$PLAN" ]]; then
  echo "Plan not found: $PLAN"
  exit 1
fi

if [[ -z "$EXPECTED" ]]; then
  EXPECTED=$(grep -E '^CONFIRM_TOKEN=' "$PLAN" | head -n1 | sed -E 's/^CONFIRM_TOKEN="?([a-f0-9]+)"?$/\1/')
fi

if [[ -z "$CONFIRM" || -z "$EXPECTED" || "$CONFIRM" != "$EXPECTED" ]]; then
  echo "Confirmation token mismatch."
  echo "Expected: $EXPECTED"
  exit 1
fi

mkdir -p artifacts/logs
LOG="artifacts/logs/apply-$(date +%Y%m%d-%H%M%S).log"
echo "Executing $PLAN"
echo "Logging to $LOG"

bash -o pipefail "$PLAN" 2>&1 | tee "$LOG"
