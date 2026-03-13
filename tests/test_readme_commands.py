from pathlib import Path


def test_readme_includes_required_commands():
    text = Path("README.md").read_text(encoding="utf-8")
    required = [
        "/data/nvme/0",
        "/data/logical",
        "scripts/jbofs-cp.sh",
        "scripts/jbofs-rm.sh",
        "scripts/jbofs-sync.sh",
        "scripts/jbofs-prune.sh",
        "docs/developer-guide.md",
        "docs/design.md",
        "docs/setup-guide.md",
        "docs/user-guide.md",
        "docs/benchmarking.md",
    ]
    for cmd in required:
        assert cmd in text
