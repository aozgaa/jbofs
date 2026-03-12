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


def make_layout() -> tuple[Path, dict[str, str], Path, Path]:
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    data_root = root / "data"
    logical_root = data_root / "logical"
    nvme_root = data_root / "nvme"
    logical_root.mkdir(parents=True)
    (nvme_root / "0" / "pcaps").mkdir(parents=True)
    (nvme_root / "nvme-ABC" / "pcaps").mkdir(parents=True)
    env = {
        **os.environ,
        "DATA_ROOT": str(data_root),
        "LOGICAL_ROOT": str(logical_root),
        "NVME_ROOT": str(nvme_root),
    }
    env["_TMPDIR_HANDLE"] = tmp.name
    return root, env, logical_root, nvme_root


def test_defaults_to_ensure_data_and_rm_both_from_logical_path():
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
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
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
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
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
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
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
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
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
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
