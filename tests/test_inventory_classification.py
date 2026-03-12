from scripts.setup.lib_inventory import classify_device, references_device_in_fstab


def test_classify_safe_candidate():
    device = {
        "name": "nvme1n1",
        "path": "/dev/nvme1n1",
        "mountpoints": [],
        "children": [],
        "fstype": None,
        "has_signature": False,
        "is_system": False,
        "in_fstab": False,
    }
    assert classify_device(device) == "SAFE_CANDIDATE"


def test_classify_caution_signature_or_partitions():
    device_sig = {
        "name": "nvme2n1",
        "path": "/dev/nvme2n1",
        "mountpoints": [],
        "children": [],
        "fstype": "xfs",
        "has_signature": True,
        "is_system": False,
        "in_fstab": False,
    }
    assert classify_device(device_sig) == "CAUTION"

    device_parts = {
        "name": "nvme3n1",
        "path": "/dev/nvme3n1",
        "mountpoints": [],
        "children": [{"name": "nvme3n1p1"}],
        "fstype": None,
        "has_signature": False,
        "is_system": False,
        "in_fstab": False,
    }
    assert classify_device(device_parts) == "CAUTION"


def test_classify_blocked_mounted_or_system():
    mounted = {
        "name": "nvme4n1",
        "path": "/dev/nvme4n1",
        "mountpoints": ["/data"],
        "children": [],
        "fstype": None,
        "has_signature": False,
        "is_system": False,
        "in_fstab": False,
    }
    assert classify_device(mounted) == "BLOCKED"

    system = {
        "name": "nvme0n1",
        "path": "/dev/nvme0n1",
        "mountpoints": [],
        "children": [],
        "fstype": None,
        "has_signature": False,
        "is_system": True,
        "in_fstab": False,
    }
    assert classify_device(system) == "BLOCKED"


def test_references_device_in_fstab_ignores_comments_and_substring_matches():
    fstab_text = """# / was on /dev/nvme0n1p3 during installation
UUID=2ce9261d-19fb-4c0c-bd87-87dd18f37679 / ext4 errors=remount-ro 0 0
# /boot/efi was on /dev/nvme0n1p1 during installation
UUID=E8FC-BBD8 /boot/efi vfat umask=0077 0 1
"""
    assert not references_device_in_fstab("/dev/nvme0n1", "nvme0n1", fstab_text)


def test_references_device_in_fstab_matches_active_device_entries():
    fstab_text = """/dev/nvme2n1 /data ext4 defaults 0 0
UUID=E8FC-BBD8 /boot/efi vfat umask=0077 0 1
"""
    assert references_device_in_fstab("/dev/nvme2n1", "nvme2n1", fstab_text)
