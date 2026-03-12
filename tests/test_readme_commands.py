from pathlib import Path


def test_readme_includes_required_commands():
    text = Path("README.md").read_text(encoding="utf-8")
    required = [
        "python3 scripts/01_inventory.py",
        "python3 scripts/02_plan.py",
        "bash scripts/03_apply.sh",
        "python3 scripts/04_verify.py",
        "bash scripts/05_fio_bench.sh",
        "python3 scripts/06_report.py",
        "bash scripts/07_aliases.sh",
        "scripts/cp-to-nvme.sh --disk=2",
        "/data/nvme/0",
        "/data/logical",
        "pcaps/symbol=ES/date=2026-03-11/file1.pcap",
    ]
    for cmd in required:
        assert cmd in text
