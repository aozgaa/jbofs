import importlib.util
import re
import subprocess
import tempfile
from pathlib import Path

from scripts.setup.lib_plan import render_plan_shell, select_approved_targets


VERIFY_SCRIPT = Path("scripts/setup/04_verify.py")
ALIASES_SCRIPT = Path("scripts/setup/07_aliases.sh")


def load_verify_module():
    spec = importlib.util.spec_from_file_location("verify_script", VERIFY_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_rejects_unselected_and_blocked_and_protected():
    devices = [
        {"stable_id": "disk-a", "classification": "SAFE_CANDIDATE", "path": "/dev/nvme1n1"},
        {"stable_id": "disk-b", "classification": "BLOCKED", "path": "/dev/nvme0n1"},
        {"stable_id": "disk-c", "classification": "SAFE_CANDIDATE", "path": "/dev/nvme2n1"},
    ]
    selected = {"disk-a", "disk-b", "disk-c"}
    protected = {"disk-c"}

    approved, rejected = select_approved_targets(devices, selected, protected)

    assert [d["stable_id"] for d in approved] == ["disk-a"]
    reasons = {r["stable_id"]: r["reason"] for r in rejected}
    assert "BLOCKED" in reasons["disk-b"]
    assert "protected" in reasons["disk-c"].lower()


def test_render_plan_shell_uses_unique_labels_for_similar_serial_prefixes():
    approved = [
        {"stable_id": "nvme-S5P2NG0R607889Z", "path": "/dev/nvme2n1"},
        {"stable_id": "nvme-S5P2NG0R607870N", "path": "/dev/nvme0n1"},
        {"stable_id": "nvme-S5P2NG0R608243B", "path": "/dev/nvme1n1"},
        {"stable_id": "nvme-S5P2NG0R608249J", "path": "/dev/nvme3n1"},
    ]

    shell, _ = render_plan_shell(approved)
    labels = re.findall(r"mkfs\.xfs -f -L (\S+) ", shell)

    assert len(labels) == 4
    assert len(set(labels)) == 4


def test_render_plan_shell_mounts_under_srv_jbofs_raw():
    approved = [{"stable_id": "nvme-S5P2NG0R607870N", "path": "/dev/nvme0n1"}]

    shell, _ = render_plan_shell(approved)

    assert "/srv/jbofs/raw/nvme-S5P2NG0R607870N" in shell
    assert 'LINE="UUID=$UUID /srv/jbofs/raw/nvme-S5P2NG0R607870N xfs defaults,noatime,nodiratime 0 2"' in shell


def test_verify_defaults_mount_root_to_srv_jbofs_raw(tmp_path, monkeypatch):
    verify = load_verify_module()
    monkeypatch.setattr("sys.argv", ["04_verify.py", "--output-dir", str(tmp_path)])
    monkeypatch.setattr(verify, "_xfs_mounts", lambda: [])

    rc = verify.main()

    assert rc == 0
    assert "/srv/jbofs/raw" in (tmp_path / "verify.md").read_text(encoding="utf-8")


def test_alias_script_creates_disk_n_symlinks_under_aliased_root():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        raw_root = root / "srv/jbofs/raw"
        aliased_root = root / "srv/jbofs/aliased"
        logical_root = root / "srv/jbofs/logical"
        selected = root / "selected-devices.yaml"
        fakebin = root / "bin"
        fakebin.mkdir()

        (fakebin / "sudo").write_text("#!/usr/bin/env bash\n\"$@\"\n", encoding="utf-8")
        (fakebin / "sudo").chmod(0o755)
        (raw_root / "disk-a").mkdir(parents=True)
        (raw_root / "disk-b").mkdir(parents=True)
        selected.write_text("selected_devices:\n  - disk-a\n  - disk-b\n", encoding="utf-8")

        proc = subprocess.run(
            ["bash", str(ALIASES_SCRIPT)],
            text=True,
            capture_output=True,
            check=False,
            env={
                "PATH": f"{fakebin}:{Path('/usr/bin')}:{Path('/bin')}",
                "RAW_ROOT": str(raw_root),
                "ALIASED_ROOT": str(aliased_root),
                "LOGICAL_ROOT": str(logical_root),
                "SELECTED_CONFIG": str(selected),
            },
        )

        assert proc.returncode == 0
        assert (aliased_root / "disk-0").is_symlink()
        assert (aliased_root / "disk-0").resolve() == (raw_root / "disk-a").resolve()
        assert (aliased_root / "disk-1").is_symlink()
        assert (aliased_root / "disk-1").resolve() == (raw_root / "disk-b").resolve()
        assert logical_root.is_dir()
