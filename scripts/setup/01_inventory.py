#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parent.parent))

from scripts.setup.lib_inventory import inventory_nvme, render_inventory_markdown


def main() -> int:
    parser = argparse.ArgumentParser(description="Inventory NVMe devices and classify risk")
    parser.add_argument("--output-dir", default="artifacts")
    args = parser.parse_args()

    outdir = Path(args.output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    inv = inventory_nvme()
    (outdir / "inventory.json").write_text(json.dumps(inv, indent=2), encoding="utf-8")
    (outdir / "inventory.md").write_text(render_inventory_markdown(inv), encoding="utf-8")
    print(f"wrote {outdir / 'inventory.json'}")
    print(f"wrote {outdir / 'inventory.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
