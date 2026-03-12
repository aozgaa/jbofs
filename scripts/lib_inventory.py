#!/usr/bin/env python3
import json
import re
import subprocess
from pathlib import Path
from typing import Any


def run_json(cmd: list[str]) -> dict[str, Any]:
    out = subprocess.check_output(cmd, text=True)
    return json.loads(out)


def run_text(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True)


def _flatten_mountpoints(node: dict[str, Any]) -> list[str]:
    mounts: list[str] = []
    for key in ("mountpoint", "mountpoints"):
        val = node.get(key)
        if isinstance(val, str) and val:
            mounts.append(val)
        if isinstance(val, list):
            mounts.extend([m for m in val if isinstance(m, str) and m])
    return sorted(set(mounts))


def _all_paths_for_device(devname: str) -> set[str]:
    return {f"/dev/{devname}", f"/dev/disk/by-id/{devname}"}


def references_device_in_fstab(path: str, name: str, fstab_text: str) -> bool:
    for line in fstab_text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split()
        if not fields:
            continue
        source = fields[0]
        if source == path:
            return True
        if re.search(rf"(^|/){re.escape(name)}(p\d+)?$", source):
            return True
    return False


def classify_device(device: dict[str, Any]) -> str:
    if device.get("is_system"):
        return "BLOCKED"
    if device.get("mountpoints"):
        return "BLOCKED"
    if device.get("in_fstab"):
        return "CAUTION"
    if device.get("has_signature"):
        return "CAUTION"
    if device.get("children"):
        return "CAUTION"
    if device.get("fstype"):
        return "CAUTION"
    return "SAFE_CANDIDATE"


def inventory_nvme() -> dict[str, Any]:
    lsblk = run_json(["lsblk", "-J", "-o", "NAME,PATH,TYPE,FSTYPE,MOUNTPOINT,MOUNTPOINTS,SERIAL,MODEL,SIZE,UUID,PKNAME"])
    blkid = run_text(["blkid", "-o", "full", "-c", "/dev/null"])
    root_src = run_text(["findmnt", "-n", "-o", "SOURCE", "/"]).strip()
    fstab_text = Path("/etc/fstab").read_text(encoding="utf-8", errors="ignore")

    root_base = root_src
    if root_base.startswith("/dev/") and "p" in root_base:
        # /dev/nvme0n1p2 -> /dev/nvme0n1
        if root_base.startswith("/dev/nvme") and "p" in root_base:
            root_base = root_base.rsplit("p", 1)[0]

    devices: list[dict[str, Any]] = []
    for node in lsblk.get("blockdevices", []):
        if node.get("type") != "disk":
            continue
        name = node.get("name", "")
        if not str(name).startswith("nvme"):
            continue
        path = node.get("path") or f"/dev/{name}"
        mountpoints = _flatten_mountpoints(node)
        has_signature = path in blkid
        is_system = path == root_base
        in_fstab = references_device_in_fstab(path, name, fstab_text)

        serial = (node.get("serial") or "").strip()
        stable_id = f"nvme-{serial}" if serial else f"nvme-{name}"
        stable_id = stable_id.replace(" ", "_").replace("/", "_")

        rec = {
            "name": name,
            "path": path,
            "serial": serial,
            "model": (node.get("model") or "").strip(),
            "size": node.get("size"),
            "fstype": node.get("fstype"),
            "uuid": node.get("uuid"),
            "mountpoints": mountpoints,
            "children": node.get("children") or [],
            "has_signature": has_signature,
            "is_system": is_system,
            "in_fstab": in_fstab,
            "stable_id": stable_id,
        }
        rec["classification"] = classify_device(rec)
        devices.append(rec)

    return {"devices": devices}


def render_inventory_markdown(inventory: dict[str, Any]) -> str:
    lines = [
        "# NVMe Inventory",
        "",
        "| Stable ID | Device | Size | FS | Mounted | Classification |",
        "|---|---|---:|---|---|---|",
    ]
    for dev in inventory.get("devices", []):
        mounted = ", ".join(dev.get("mountpoints") or []) or "-"
        lines.append(
            f"| {dev['stable_id']} | {dev['path']} | {dev.get('size','-')} | {dev.get('fstype') or '-'} | {mounted} | {dev['classification']} |"
        )
    lines.append("")
    return "\n".join(lines)
