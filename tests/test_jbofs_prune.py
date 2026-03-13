import os
import subprocess
import tempfile
from pathlib import Path


SCRIPT = Path("scripts/jbofs-prune.sh")


def run_helper(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


def test_jbofs_prune_removes_broken_symlinks_by_default():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        logical_root = root / "logical"
        broken = logical_root / "pcaps" / "day1" / "a.pcap"
        broken.parent.mkdir(parents=True)
        broken.symlink_to(root / "missing" / "a.pcap")

        proc = run_helper(env={**os.environ, "LOGICAL_ROOT": str(logical_root)})

        assert proc.returncode == 0
        assert not broken.exists()
        assert not broken.is_symlink()


def test_jbofs_prune_keeps_valid_symlinks():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        logical_root = root / "logical"
        target = root / "raw" / "nvme-AAA" / "pcaps" / "day1" / "a.pcap"
        link = logical_root / "pcaps" / "day1" / "a.pcap"
        target.parent.mkdir(parents=True)
        link.parent.mkdir(parents=True)
        target.write_text("a\n", encoding="utf-8")
        link.symlink_to(target)

        proc = run_helper(env={**os.environ, "LOGICAL_ROOT": str(logical_root)})

        assert proc.returncode == 0
        assert link.is_symlink()


def test_jbofs_prune_logical_prefix_limits_removals():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        logical_root = root / "logical"
        broken_a = logical_root / "pcaps" / "day1" / "a.pcap"
        broken_b = logical_root / "logs" / "day1" / "b.log"
        broken_a.parent.mkdir(parents=True)
        broken_b.parent.mkdir(parents=True)
        broken_a.symlink_to(root / "missing" / "a.pcap")
        broken_b.symlink_to(root / "missing" / "b.log")

        proc = run_helper("--logical-prefix", "pcaps/day1", env={**os.environ, "LOGICAL_ROOT": str(logical_root)})

        assert proc.returncode == 0
        assert not broken_a.exists()
        assert broken_b.is_symlink()


def test_jbofs_prune_dry_run_prints_actions_without_deleting():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        logical_root = root / "logical"
        broken = logical_root / "pcaps" / "day1" / "a.pcap"
        broken.parent.mkdir(parents=True)
        broken.symlink_to(root / "missing" / "a.pcap")

        proc = run_helper("--dry-run", env={**os.environ, "LOGICAL_ROOT": str(logical_root)})

        assert proc.returncode == 0
        assert "rm -f --" in proc.stdout
        assert broken.is_symlink()


def test_jbofs_prune_ignores_regular_files():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        logical_root = root / "logical"
        regular = logical_root / "pcaps" / "day1" / "a.pcap"
        regular.parent.mkdir(parents=True)
        regular.write_text("a\n", encoding="utf-8")

        proc = run_helper(env={**os.environ, "LOGICAL_ROOT": str(logical_root)})

        assert proc.returncode == 0
        assert regular.exists()
