# NVMe Bring-Up Debug Checklist (Lenovo P620)

Purpose: isolate why only one NVMe device is enumerating in Linux.

Current known state:
- Linux sees only `/dev/nvme0n1` (boot disk).
- This indicates likely BIOS/slot/adapter/hardware enumeration issue, not mount/filesystem issue.

## Rules

- Change one thing per reboot.
- Record outputs after every reboot.
- Do not format any disk during this process.

## Quick Log Template (copy per reboot)

- Reboot #: 
- Hardware change made: 
- BIOS change made: 
- Expected result: 
- Actual result: 
- Next action: 

---

## Step 0: Baseline Snapshot (before changing anything)

Run and save output:

```bash
date
hostname
uname -a
nvme list
lspci | grep -Ei 'Non-Volatile memory|Root Complex'
lspci -tv
lsblk -d -o NAME,MODEL,SIZE,TYPE
```

---

## Step 1: Minimal Hardware Topology (Power Off)

Set machine to minimal test setup:

- Keep boot NVMe installed (current OS disk).
- Keep only one GPU if possible (temporarily remove extra GPU).
- Install one NVMe adapter card in one known x16 slot.
- Install exactly one test NVMe SSD on that adapter.

Goal: reduce variables and confirm basic enumeration first.

---

## Step 2: BIOS Configuration (for that exact slot)

In BIOS, for the slot containing the NVMe adapter:

- PCIe bifurcation: `x4x4x4x4` (not `Auto`)
- PCIe speed: `Gen4` (not `Auto`)

Also recommended:

- Update BIOS/firmware to latest available for P620.

Save and reboot.

---

## Step 3: Post-Reboot Verification Command Set

Run after each reboot:

```bash
date
nvme list
lspci | grep -i 'Non-Volatile memory'
lspci -tv
```

Expected when successful: at least one additional NVMe controller/device beyond boot drive appears.

---

## Step 4: If No Additional NVMe Appears

Power off and change exactly one variable, then return to Step 3.

Change options (one at a time):

1. Same adapter + same SSD, move adapter to different x16 slot.
2. Same slot + same adapter, swap to different SSD.
3. Same slot + same SSD, swap to different adapter card.

After each change:
- Ensure slot bifurcation is still `x4x4x4x4`.
- Ensure slot speed is still `Gen4`.

---

## Step 5: Scale-Up After Single-Drive Success

Once one extra NVMe appears consistently:

1. Add second SSD to same adapter.
2. Reboot, verify with Step 3 commands.
3. Add more SSDs one by one, verifying each reboot.

Then, if using second adapter:

1. Install second adapter in another x16 slot.
2. Configure that slot in BIOS:
   - bifurcation `x4x4x4x4`
   - speed `Gen4`
3. Reboot and verify.

---

## Step 6: Reintroduce Extra GPU Last

If you removed a GPU for isolation:

1. Reinstall second GPU only after NVMe setup is stable.
2. Reboot and re-run Step 3 commands.
3. Confirm NVMe count does not drop.

---

## Step 7: Final Linux Validation (when all drives visible)

```bash
nvme list
lsblk -d -o NAME,MODEL,SIZE,ROTA,TYPE
for d in /sys/class/nvme/nvme*/device/current_link_speed; do
  printf '%s: ' "$d"
  cat "$d"
done
```

Optional detailed PCI links:

```bash
lspci -vv | grep -E '^[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]|LnkCap|LnkSta'
```

---

## Common Failure Patterns

- Slot left on `Auto` bifurcation -> no SSDs behind quad-M.2 adapter enumerate.
- Link speed `Auto` -> unstable/slow negotiation; force `Gen4` for test.
- Adapter requires motherboard bifurcation but slot not configured.
- Physical slot/cable/backplane path does not carry NVMe lanes.
- Too many variables changed at once (hard to isolate root cause).

---

## Safety Reminder

Do not run any `mkfs`, `wipefs`, partitioning, or mount automation until:

- Expected NVMe devices all appear in `nvme list` and `lspci`.
- You have reviewed the inventory report and explicitly selected target disks.

When ready, resume toolkit flow in this repo:

```bash
python3 scripts/01_inventory.py --output-dir artifacts
python3 scripts/02_plan.py --inventory artifacts/inventory.json --selected config/selected-devices.yaml --protected config/protected-devices.yaml --output-dir artifacts
```
