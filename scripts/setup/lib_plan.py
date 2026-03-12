#!/usr/bin/env python3
import secrets
from pathlib import Path
from typing import Any

import yaml


def load_yaml_list(path: str, key: str) -> set[str]:
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    vals = data.get(key, [])
    return {str(v) for v in vals}


def select_approved_targets(
    devices: list[dict[str, Any]], selected: set[str], protected: set[str]
) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    approved: list[dict[str, Any]] = []
    rejected: list[dict[str, str]] = []
    for d in devices:
        sid = d.get("stable_id", "")
        cls = d.get("classification", "")
        if sid not in selected:
            rejected.append({"stable_id": sid, "reason": "Not in selected-devices.yaml"})
            continue
        if sid in protected:
            rejected.append({"stable_id": sid, "reason": "Device is protected"})
            continue
        if cls != "SAFE_CANDIDATE":
            rejected.append({"stable_id": sid, "reason": f"Classification is {cls}"})
            continue
        approved.append(d)
    return approved, rejected


def _label_for(stable_id: str) -> str:
    cleaned = "".join(ch for ch in stable_id.replace("nvme-", "") if ch.isalnum())
    suffix = cleaned[-11:] if len(cleaned) > 11 else cleaned
    return f"d{suffix}"


def render_plan_shell(approved: list[dict[str, Any]]) -> tuple[str, str]:
    token = secrets.token_hex(4)
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        f"CONFIRM_TOKEN=\"{token}\"",
        "echo \"This plan is destructive. Confirm token required.\"",
        "",
    ]
    for d in approved:
        dev = d["path"]
        sid = d["stable_id"]
        mnt = f"/data/nvme/{sid}"
        label = _label_for(sid)
        lines.extend(
            [
                f"echo 'Preparing {sid} ({dev})'",
                f"sudo mkfs.xfs -f -L {label} {dev}",
                f"sudo mkdir -p {mnt}",
                f"UUID=$(sudo blkid -s UUID -o value {dev})",
                f"LINE=\"UUID=$UUID {mnt} xfs defaults,noatime,nodiratime 0 2\"",
                "if ! grep -q \"$UUID\" /etc/fstab; then",
                "  echo \"$LINE\" | sudo tee -a /etc/fstab >/dev/null",
                "fi",
                f"sudo mount {mnt}",
                "",
            ]
        )
    return "\n".join(lines) + "\n", token


def render_plan_markdown(
    approved: list[dict[str, Any]], rejected: list[dict[str, str]], token: str
) -> str:
    lines = [
        "# Setup Plan",
        "",
        "## Confirmation",
        f"- Confirm token: `{token}`",
        "",
        "## Approved targets",
    ]
    if not approved:
        lines.append("- None")
    for d in approved:
        lines.append(f"- {d['stable_id']} ({d['path']})")
    lines.extend(["", "## Rejected targets"])
    if not rejected:
        lines.append("- None")
    for r in rejected:
        lines.append(f"- {r['stable_id']}: {r['reason']}")
    lines.append("")
    return "\n".join(lines)
