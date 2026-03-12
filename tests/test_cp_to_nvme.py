import os
import subprocess
import tempfile
from pathlib import Path


SCRIPT = Path("scripts/cp-to-nvme.sh")


def run_helper(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


def test_requires_exactly_one_selector():
    proc = run_helper("src", "dest")
    assert proc.returncode != 0
    assert "exactly one" in proc.stderr

    proc = run_helper("--disk=1", "--policy=random", "src", "dest")
    assert proc.returncode != 0
    assert "exactly one" in proc.stderr


def test_rejects_invalid_policy():
    proc = run_helper("--policy=bad", "src", "dest")
    assert proc.returncode != 0
    assert "random|most-free" in proc.stderr


def test_explicit_disk_dry_run_renders_copy_and_symlink_commands():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "src.txt").write_text("hello\n", encoding="utf-8")
        (root / "nvme" / "2").mkdir(parents=True)
        (root / "logical").mkdir(parents=True)

        proc = run_helper(
            "--disk=2",
            "--dry-run",
            str(root / "src.txt"),
            "pcaps/symbol=ES/date=2026-03-11/file1.txt",
            env={
                **os.environ,
                "NVME_ROOT": str(root / "nvme"),
                "LOGICAL_ROOT": str(root / "logical"),
            },
        )

        assert proc.returncode == 0
        assert f"cp -a -- {root / 'src.txt'} {root / 'nvme' / '2' / 'pcaps/symbol=ES/date=2026-03-11/file1.txt'}" in proc.stdout
        assert f"ln -s -- {root / 'nvme' / '2' / 'pcaps/symbol=ES/date=2026-03-11/file1.txt'} {root / 'logical' / 'pcaps/symbol=ES/date=2026-03-11/file1.txt'}" in proc.stdout


def test_most_free_selects_branch_with_highest_available_space():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "src.txt").write_text("hello\n", encoding="utf-8")
        for disk in ("0", "1", "2", "3"):
            (root / "nvme" / disk).mkdir(parents=True)
        (root / "logical").mkdir(parents=True)

        proc = run_helper(
            "--policy=most-free",
            "--dry-run",
            str(root / "src.txt"),
            "file1.txt",
            env={
                **os.environ,
                "NVME_ROOT": str(root / "nvme"),
                "LOGICAL_ROOT": str(root / "logical"),
                "NVME_AVAIL_KB_0": "100",
                "NVME_AVAIL_KB_1": "500",
                "NVME_AVAIL_KB_2": "200",
                "NVME_AVAIL_KB_3": "300",
            },
        )

        assert proc.returncode == 0
        assert f"{root / 'nvme' / '1' / 'file1.txt'}" in proc.stdout
