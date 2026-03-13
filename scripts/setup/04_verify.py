#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path


def _run_json(cmd: list[str]) -> dict:
    out = subprocess.check_output(cmd, text=True)
    return json.loads(out)


def _xfs_mounts() -> list[dict]:
    data = _run_json(["findmnt", "-J", "-t", "xfs"])
    return data.get("filesystems", [])


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify mounted XFS targets")
    parser.add_argument("--mount-root", default="/srv/jbofs/raw")
    parser.add_argument("--output-dir", default="artifacts")
    parser.add_argument("--probe-write", action="store_true")
    args = parser.parse_args()

    outdir = Path(args.output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    mounts = []
    for fs in _xfs_mounts():
        target = fs.get("target", "")
        if not target.startswith(args.mount_root):
            continue
        rec = {
            "source": fs.get("source"),
            "target": target,
            "fstype": fs.get("fstype"),
            "probe_write": "skipped",
        }
        if args.probe_write:
            p = Path(target) / ".jbofs_verify_write"
            try:
                p.write_text("ok\n", encoding="utf-8")
                p.unlink(missing_ok=True)
                rec["probe_write"] = "ok"
            except Exception as exc:  # noqa: BLE001
                rec["probe_write"] = f"error: {exc}"
        mounts.append(rec)

    verify = {"mount_root": args.mount_root, "mounts": mounts}
    (outdir / "verify.json").write_text(json.dumps(verify, indent=2), encoding="utf-8")

    lines = ["# Verify", "", f"Mount root: `{args.mount_root}`", ""]
    if not mounts:
        lines.append("No XFS mounts found under mount root.")
    else:
        lines.append("| Source | Target | FS | Write Probe |")
        lines.append("|---|---|---|---|")
        for m in mounts:
            lines.append(f"| {m['source']} | {m['target']} | {m['fstype']} | {m['probe_write']} |")
    lines.append("")
    (outdir / "verify.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {outdir / 'verify.json'}")
    print(f"wrote {outdir / 'verify.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
