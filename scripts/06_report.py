#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def _load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Compile final report")
    parser.add_argument("--inventory", default="artifacts/inventory.json")
    parser.add_argument("--verify", default="artifacts/verify.json")
    parser.add_argument("--output", default="artifacts/report.md")
    args = parser.parse_args()

    inv = _load_json(Path(args.inventory))
    ver = _load_json(Path(args.verify))

    devices = inv.get("devices", [])
    mounts = ver.get("mounts", [])

    lines = ["# NVMe Data Layout Report", ""]
    lines.append("## Inventory summary")
    lines.append(f"- Total NVMe devices discovered: {len(devices)}")
    for cls in ["SAFE_CANDIDATE", "CAUTION", "BLOCKED"]:
        count = sum(1 for d in devices if d.get("classification") == cls)
        lines.append(f"- {cls}: {count}")

    lines.extend(["", "## Verification summary"])
    lines.append(f"- XFS mounts under root: {len(mounts)}")
    for m in mounts:
        lines.append(f"- {m.get('target')}: probe={m.get('probe_write')}")

    fio_dirs = sorted(Path("artifacts/fio").glob("*")) if Path("artifacts/fio").exists() else []
    lines.extend(["", "## fio outputs"])
    if not fio_dirs:
        lines.append("- No fio runs found")
    else:
        latest = fio_dirs[-1]
        json_files = sorted(latest.glob("*.json"))
        lines.append(f"- Latest run: `{latest}`")
        lines.append(f"- Result files: {len(json_files)}")
        for jf in json_files:
            lines.append(f"- {jf.name}")

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
