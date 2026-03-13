import os
import subprocess
import tempfile
from pathlib import Path


SCRIPT = Path("scripts/jbofs-cp.sh")


def run_helper(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


def test_jbofs_cp_requires_exactly_one_selector():
    proc = run_helper("src", "dest")
    assert proc.returncode != 0
    assert "exactly one" in proc.stderr

    proc = run_helper("--disk=1", "--policy=random", "src", "dest")
    assert proc.returncode != 0
    assert "exactly one" in proc.stderr


def test_jbofs_cp_rejects_invalid_policy():
    proc = run_helper("--policy=bad", "src", "dest")
    assert proc.returncode != 0
    assert "random|most-free" in proc.stderr


def test_jbofs_cp_explicit_disk_dry_run_renders_copy_and_symlink_commands():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "src.txt").write_text("hello\n", encoding="utf-8")
        (root / "aliased" / "disk-2").mkdir(parents=True)
        (root / "logical").mkdir(parents=True)

        proc = run_helper(
            "--disk=disk-2",
            "--dry-run",
            str(root / "src.txt"),
            "pcaps/symbol=ES/date=2026-03-11/file1.txt",
            env={
                **os.environ,
                "ALIASED_ROOT": str(root / "aliased"),
                "LOGICAL_ROOT": str(root / "logical"),
            },
        )

        assert proc.returncode == 0
        assert f"cp -a -- {root / 'src.txt'} {root / 'aliased' / 'disk-2' / 'pcaps/symbol=ES/date=2026-03-11/file1.txt'}" in proc.stdout
        assert f"ln -s -- {root / 'aliased' / 'disk-2' / 'pcaps/symbol=ES/date=2026-03-11/file1.txt'} {root / 'logical' / 'pcaps/symbol=ES/date=2026-03-11/file1.txt'}" in proc.stdout


def test_jbofs_cp_most_free_selects_branch_with_highest_available_space():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "src.txt").write_text("hello\n", encoding="utf-8")
        for disk in ("disk-0", "disk-1", "disk-2", "disk-3"):
            (root / "aliased" / disk).mkdir(parents=True)
        (root / "logical").mkdir(parents=True)

        proc = run_helper(
            "--policy=most-free",
            "--dry-run",
            str(root / "src.txt"),
            "file1.txt",
            env={
                **os.environ,
                "ALIASED_ROOT": str(root / "aliased"),
                "LOGICAL_ROOT": str(root / "logical"),
                "ALIASED_AVAIL_KB_disk_0": "100",
                "ALIASED_AVAIL_KB_disk_1": "500",
                "ALIASED_AVAIL_KB_disk_2": "200",
                "ALIASED_AVAIL_KB_disk_3": "300",
            },
        )

        assert proc.returncode == 0
        assert f"{root / 'aliased' / 'disk-1' / 'file1.txt'}" in proc.stdout


def test_jbofs_cp_recursive_requires_exactly_one_grouping_mode():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        srcdir = root / "captures"
        srcdir.mkdir()
        (srcdir / "a.txt").write_text("a\n", encoding="utf-8")
        (root / "aliased" / "disk-0").mkdir(parents=True)
        (root / "logical").mkdir(parents=True)

        proc = run_helper(
            "-r",
            "--policy=random",
            str(srcdir),
            "pcaps/day1",
            env={**os.environ, "ALIASED_ROOT": str(root / "aliased"), "LOGICAL_ROOT": str(root / "logical")},
        )
        assert proc.returncode != 0
        assert "round-robin" in proc.stderr.lower() or "batch" in proc.stderr.lower()

        proc = run_helper(
            "-r",
            "--policy=random",
            "--round-robin",
            "--batch",
            str(srcdir),
            "pcaps/day1",
            env={**os.environ, "ALIASED_ROOT": str(root / "aliased"), "LOGICAL_ROOT": str(root / "logical")},
        )
        assert proc.returncode != 0


def test_jbofs_cp_recursive_batch_preserves_source_dir_without_trailing_slash():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        srcdir = root / "captures"
        srcdir.mkdir()
        (srcdir / "a.txt").write_text("a\n", encoding="utf-8")
        (root / "aliased" / "disk-1").mkdir(parents=True)
        (root / "logical").mkdir(parents=True)

        proc = run_helper(
            "-r",
            "--policy=most-free",
            "--batch",
            "--dry-run",
            str(srcdir),
            "pcaps/day1",
            env={
                **os.environ,
                "ALIASED_ROOT": str(root / "aliased"),
                "LOGICAL_ROOT": str(root / "logical"),
                "ALIASED_AVAIL_KB_disk_1": "1000",
            },
        )
        assert proc.returncode == 0
        assert f"{root / 'aliased' / 'disk-1' / 'pcaps/day1/captures/a.txt'}" in proc.stdout
        assert f"{root / 'logical' / 'pcaps/day1/captures/a.txt'}" in proc.stdout


def test_jbofs_cp_recursive_round_robin_uses_rsync_style_trailing_slash_contents():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        srcdir = root / "captures"
        srcdir.mkdir()
        (srcdir / "a.txt").write_text("a\n", encoding="utf-8")
        (srcdir / "b.txt").write_text("b\n", encoding="utf-8")
        for disk in ("disk-0", "disk-1"):
            (root / "aliased" / disk).mkdir(parents=True)
        (root / "logical").mkdir(parents=True)

        proc = run_helper(
            "-r",
            "--policy=random",
            "--round-robin",
            "--dry-run",
            str(srcdir) + "/",
            "pcaps/day1",
            env={**os.environ, "ALIASED_ROOT": str(root / "aliased"), "LOGICAL_ROOT": str(root / "logical")},
        )
        assert proc.returncode == 0
        assert f"{root / 'aliased' / 'disk-0' / 'pcaps/day1/a.txt'}" in proc.stdout
        assert f"{root / 'aliased' / 'disk-1' / 'pcaps/day1/b.txt'}" in proc.stdout
        assert f"{root / 'logical' / 'pcaps/day1/a.txt'}" in proc.stdout
        assert f"{root / 'logical' / 'pcaps/day1/b.txt'}" in proc.stdout
