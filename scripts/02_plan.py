#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parent.parent))

from scripts.lib_plan import (
    load_yaml_list,
    render_plan_markdown,
    render_plan_shell,
    select_approved_targets,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate guarded setup plan")
    parser.add_argument("--inventory", default="artifacts/inventory.json")
    parser.add_argument("--protected", default="config/protected-devices.yaml")
    parser.add_argument("--selected", default="config/selected-devices.yaml")
    parser.add_argument("--output-dir", default="artifacts")
    args = parser.parse_args()

    outdir = Path(args.output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    inventory = json.loads(Path(args.inventory).read_text(encoding="utf-8"))
    selected = load_yaml_list(args.selected, "selected_devices")
    protected = load_yaml_list(args.protected, "protected_devices")

    approved, rejected = select_approved_targets(inventory.get("devices", []), selected, protected)
    shell, token = render_plan_shell(approved)
    md = render_plan_markdown(approved, rejected, token)

    (outdir / "setup-plan.sh").write_text(shell, encoding="utf-8")
    (outdir / "setup-plan.md").write_text(md, encoding="utf-8")

    print(f"wrote {outdir / 'setup-plan.sh'}")
    print(f"wrote {outdir / 'setup-plan.md'}")
    print(f"confirm token: {token}")

    if not approved:
        print("No approved targets. Edit config/selected-devices.yaml and rerun.")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
