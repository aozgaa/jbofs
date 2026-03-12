import os
import subprocess
import tempfile
from pathlib import Path


SCRIPT = Path("scripts/rm-nvme.sh")


def run_helper(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )

def test_defaults_to_ensure_data_and_rm_both_from_logical_path():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        data_root = root / "data"
        logical_root = data_root / "logical"
        nvme_root = data_root / "nvme"
        physical = nvme_root / "0" / "pcaps" / "file1.pcap"
        logical = logical_root / "pcaps" / "file1.pcap"
        physical.parent.mkdir(parents=True)
        logical.parent.mkdir(parents=True)
        physical.write_text("x\n", encoding="utf-8")
        logical.symlink_to(physical)

        proc = run_helper(
            str(logical),
            env={**os.environ, "DATA_ROOT": str(data_root), "LOGICAL_ROOT": str(logical_root), "NVME_ROOT": str(nvme_root)},
        )

        assert proc.returncode == 0
        assert not logical.exists()
        assert not physical.exists()


def test_rejects_multiple_ensure_modes():
    proc = run_helper("--ensure-logical", "--ensure-physical", "/data/logical/x")
    assert proc.returncode != 0
    assert "ensure" in proc.stderr.lower()


def test_rejects_multiple_remove_modes():
    proc = run_helper("--rm-data", "--rm-link", "/data/logical/x")
    assert proc.returncode != 0
    assert "rm-" in proc.stderr.lower()


def test_dry_run_does_not_delete():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        data_root = root / "data"
        logical_root = data_root / "logical"
        nvme_root = data_root / "nvme"
        physical = nvme_root / "1" / "pcaps" / "file1.pcap"
        logical = logical_root / "pcaps" / "file1.pcap"
        physical.parent.mkdir(parents=True)
        logical.parent.mkdir(parents=True)
        physical.write_text("x\n", encoding="utf-8")
        logical.symlink_to(physical)

        proc = run_helper(
            "--dry-run",
            str(logical),
            env={**os.environ, "DATA_ROOT": str(data_root), "LOGICAL_ROOT": str(logical_root), "NVME_ROOT": str(nvme_root)},
        )

        assert proc.returncode == 0
        assert "rm" in proc.stdout
        assert logical.is_symlink()
        assert physical.exists()


def test_physical_path_removes_all_matching_logical_symlinks():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        data_root = root / "data"
        logical_root = data_root / "logical"
        nvme_root = data_root / "nvme"
        physical = nvme_root / "nvme-ABC" / "pcaps" / "file1.pcap"
        logical_a = logical_root / "pcaps" / "a.pcap"
        logical_b = logical_root / "other" / "b.pcap"
        physical.parent.mkdir(parents=True)
        logical_a.parent.mkdir(parents=True)
        logical_b.parent.mkdir(parents=True)
        physical.write_text("x\n", encoding="utf-8")
        logical_a.symlink_to(physical)
        logical_b.symlink_to(physical)

        proc = run_helper(
            "--ensure-physical",
            "--rm-both",
            str(physical),
            env={**os.environ, "DATA_ROOT": str(data_root), "LOGICAL_ROOT": str(logical_root), "NVME_ROOT": str(nvme_root)},
        )

        assert proc.returncode == 0
        assert not physical.exists()
        assert not logical_a.exists()
        assert not logical_b.exists()


def test_rm_link_only_keeps_physical_data():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        data_root = root / "data"
        logical_root = data_root / "logical"
        nvme_root = data_root / "nvme"
        physical = nvme_root / "2" / "pcaps" / "file1.pcap"
        logical = logical_root / "pcaps" / "file1.pcap"
        physical.parent.mkdir(parents=True)
        logical.parent.mkdir(parents=True)
        physical.write_text("x\n", encoding="utf-8")
        logical.symlink_to(physical)

        proc = run_helper(
            "--ensure-logical",
            "--rm-link",
            str(logical),
            env={**os.environ, "DATA_ROOT": str(data_root), "LOGICAL_ROOT": str(logical_root), "NVME_ROOT": str(nvme_root)},
        )

        assert proc.returncode == 0
        assert not logical.exists()
        assert physical.exists()


def test_rejects_paths_outside_data_root():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        data_root = root / "data"
        logical_root = data_root / "logical"
        nvme_root = data_root / "nvme"
        outside = root / "elsewhere" / "file1"
        outside.parent.mkdir(parents=True)
        outside.write_text("x\n", encoding="utf-8")

        proc = run_helper(
            str(outside),
            env={**os.environ, "DATA_ROOT": str(data_root), "LOGICAL_ROOT": str(logical_root), "NVME_ROOT": str(nvme_root)},
        )

        assert proc.returncode != 0
        assert "under" in proc.stderr.lower()


def test_recursive_rm_both_from_logical_directory_removes_tree_and_data():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        data_root = root / "data"
        logical_root = data_root / "logical"
        nvme_root = data_root / "nvme"
        physical_a = nvme_root / "0" / "pcaps" / "day1" / "a.pcap"
        physical_b = nvme_root / "1" / "pcaps" / "day1" / "b.pcap"
        logical_a = logical_root / "pcaps" / "day1" / "a.pcap"
        logical_b = logical_root / "pcaps" / "day1" / "b.pcap"
        physical_a.parent.mkdir(parents=True)
        physical_b.parent.mkdir(parents=True)
        logical_a.parent.mkdir(parents=True)
        physical_a.write_text("a\n", encoding="utf-8")
        physical_b.write_text("b\n", encoding="utf-8")
        logical_a.symlink_to(physical_a)
        logical_b.symlink_to(physical_b)

        proc = run_helper(
            "-r",
            str(logical_root / "pcaps" / "day1"),
            env={**os.environ, "DATA_ROOT": str(data_root), "LOGICAL_ROOT": str(logical_root), "NVME_ROOT": str(nvme_root)},
        )

        assert proc.returncode == 0
        assert not logical_a.exists()
        assert not logical_b.exists()
        assert not physical_a.exists()
        assert not physical_b.exists()


def test_recursive_dry_run_from_physical_directory_keeps_files():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        data_root = root / "data"
        logical_root = data_root / "logical"
        nvme_root = data_root / "nvme"
        physical = nvme_root / "0" / "pcaps" / "day1" / "a.pcap"
        logical = logical_root / "pcaps" / "day1" / "a.pcap"
        physical.parent.mkdir(parents=True)
        logical.parent.mkdir(parents=True)
        physical.write_text("a\n", encoding="utf-8")
        logical.symlink_to(physical)

        proc = run_helper(
            "-r",
            "--ensure-physical",
            "--dry-run",
            str(nvme_root / "0" / "pcaps" / "day1"),
            env={**os.environ, "DATA_ROOT": str(data_root), "LOGICAL_ROOT": str(logical_root), "NVME_ROOT": str(nvme_root)},
        )

        assert proc.returncode == 0
        assert "rm -f --" in proc.stdout
        assert logical.is_symlink()
        assert physical.exists()
