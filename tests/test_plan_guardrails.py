import re

from scripts.lib_plan import render_plan_shell, select_approved_targets


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
