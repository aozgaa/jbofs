import os
import subprocess
import tempfile
from pathlib import Path


SCRIPT = Path("scripts/jbofs-sync.sh")


def run_helper(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


def make_layout(tmp: str) -> tuple[Path, Path, Path]:
    root = Path(tmp)
    logical_root = root / "logical"
    raw_root = root / "raw"
    aliased_root = root / "aliased"
    stable0 = raw_root / "nvme-AAA"
    stable1 = raw_root / "nvme-BBB"
    stable0.mkdir(parents=True)
    stable1.mkdir(parents=True)
    aliased_root.mkdir(parents=True)
    (aliased_root / "disk-0").symlink_to(stable0)
    (aliased_root / "disk-1").symlink_to(stable1)
    logical_root.mkdir(parents=True)
    return logical_root, raw_root, aliased_root


def test_jbofs_sync_adds_missing_logical_links_by_default():
    with tempfile.TemporaryDirectory() as tmp:
        logical_root, raw_root, aliased_root = make_layout(tmp)
        physical = raw_root / "nvme-AAA" / "pcaps" / "day1" / "a.pcap"
        physical.parent.mkdir(parents=True)
        physical.write_text("a\n", encoding="utf-8")

        proc = run_helper(env={**os.environ, "RAW_ROOT": str(raw_root), "ALIASED_ROOT": str(aliased_root), "LOGICAL_ROOT": str(logical_root)})

        logical = logical_root / "pcaps" / "day1" / "a.pcap"
        assert proc.returncode == 0
        assert logical.is_symlink()
        assert logical.resolve() == physical.resolve()


def test_jbofs_sync_disk_flag_limits_scan_to_one_alias():
    with tempfile.TemporaryDirectory() as tmp:
        logical_root, raw_root, aliased_root = make_layout(tmp)
        physical0 = raw_root / "nvme-AAA" / "pcaps" / "day1" / "a.pcap"
        physical1 = raw_root / "nvme-BBB" / "pcaps" / "day1" / "b.pcap"
        physical0.parent.mkdir(parents=True)
        physical1.parent.mkdir(parents=True)
        physical0.write_text("a\n", encoding="utf-8")
        physical1.write_text("b\n", encoding="utf-8")

        proc = run_helper("--disk=disk-1", env={**os.environ, "RAW_ROOT": str(raw_root), "ALIASED_ROOT": str(aliased_root), "LOGICAL_ROOT": str(logical_root)})

        assert proc.returncode == 0
        assert not (logical_root / "pcaps" / "day1" / "a.pcap").exists()
        assert (logical_root / "pcaps" / "day1" / "b.pcap").is_symlink()


def test_jbofs_sync_disk_path_limits_scan_to_subtree():
    with tempfile.TemporaryDirectory() as tmp:
        logical_root, raw_root, aliased_root = make_layout(tmp)
        physical_a = raw_root / "nvme-AAA" / "pcaps" / "day1" / "a.pcap"
        physical_b = raw_root / "nvme-AAA" / "logs" / "b.log"
        physical_a.parent.mkdir(parents=True)
        physical_b.parent.mkdir(parents=True)
        physical_a.write_text("a\n", encoding="utf-8")
        physical_b.write_text("b\n", encoding="utf-8")

        proc = run_helper(
            "--disk-path",
            str(aliased_root / "disk-0" / "pcaps"),
            env={**os.environ, "RAW_ROOT": str(raw_root), "ALIASED_ROOT": str(aliased_root), "LOGICAL_ROOT": str(logical_root)},
        )

        assert proc.returncode == 0
        assert (logical_root / "pcaps" / "day1" / "a.pcap").is_symlink()
        assert not (logical_root / "logs" / "b.log").exists()


def test_jbofs_sync_logical_prefix_filters_results():
    with tempfile.TemporaryDirectory() as tmp:
        logical_root, raw_root, aliased_root = make_layout(tmp)
        physical_a = raw_root / "nvme-AAA" / "pcaps" / "day1" / "a.pcap"
        physical_b = raw_root / "nvme-AAA" / "logs" / "b.log"
        physical_a.parent.mkdir(parents=True)
        physical_b.parent.mkdir(parents=True)
        physical_a.write_text("a\n", encoding="utf-8")
        physical_b.write_text("b\n", encoding="utf-8")

        proc = run_helper(
            "--logical-prefix",
            "pcaps/day1",
            env={**os.environ, "RAW_ROOT": str(raw_root), "ALIASED_ROOT": str(aliased_root), "LOGICAL_ROOT": str(logical_root)},
        )

        assert proc.returncode == 0
        assert (logical_root / "pcaps" / "day1" / "a.pcap").is_symlink()
        assert not (logical_root / "logs" / "b.log").exists()


def test_jbofs_sync_skips_conflicting_existing_path():
    with tempfile.TemporaryDirectory() as tmp:
        logical_root, raw_root, aliased_root = make_layout(tmp)
        physical = raw_root / "nvme-AAA" / "pcaps" / "day1" / "a.pcap"
        logical = logical_root / "pcaps" / "day1" / "a.pcap"
        physical.parent.mkdir(parents=True)
        logical.parent.mkdir(parents=True)
        physical.write_text("a\n", encoding="utf-8")
        logical.write_text("conflict\n", encoding="utf-8")

        proc = run_helper(env={**os.environ, "RAW_ROOT": str(raw_root), "ALIASED_ROOT": str(aliased_root), "LOGICAL_ROOT": str(logical_root)})

        assert proc.returncode == 0
        assert "conflict" in proc.stdout.lower() or "conflict" in proc.stderr.lower()
        assert not logical.is_symlink()


def test_jbofs_sync_dry_run_prints_actions_without_changes():
    with tempfile.TemporaryDirectory() as tmp:
        logical_root, raw_root, aliased_root = make_layout(tmp)
        physical = raw_root / "nvme-AAA" / "pcaps" / "day1" / "a.pcap"
        physical.parent.mkdir(parents=True)
        physical.write_text("a\n", encoding="utf-8")

        proc = run_helper("--dry-run", env={**os.environ, "RAW_ROOT": str(raw_root), "ALIASED_ROOT": str(aliased_root), "LOGICAL_ROOT": str(logical_root)})

        logical = logical_root / "pcaps" / "day1" / "a.pcap"
        assert proc.returncode == 0
        assert "ln -s --" in proc.stdout
        assert not logical.exists()
