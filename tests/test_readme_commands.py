from pathlib import Path


def test_readme_includes_required_commands():
    text = Path("README.md").read_text(encoding="utf-8")
    required = [
        "python3 scripts/setup/01_inventory.py",
        "python3 scripts/setup/02_plan.py",
        "bash scripts/setup/03_apply.sh",
        "python3 scripts/setup/04_verify.py",
        "bash scripts/setup/05_fio_bench.sh",
        "python3 scripts/setup/06_report.py",
        "bash scripts/setup/07_aliases.sh",
        "scripts/jbofs-cp.sh --disk=2",
        "scripts/jbofs-rm.sh",
        "/data/nvme/0",
        "/data/logical",
        "pcaps/symbol=ES/date=2026-03-11/file1.pcap",
        "--dry-run /data/logical",
        "--ensure-physical --rm-both /data/nvme/0",
        "--round-robin",
        "--batch",
        "srcdir/ means copy the contents",
        "bash scripts/jbofs-rm.sh -r",
    ]
    for cmd in required:
        assert cmd in text
