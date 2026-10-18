#!/usr/bin/env bash
# A loopback block device whose I/O can be switched on and off, to force a
# genuine SQLite "disk I/O error" (SQLITE_IOERR) for testing Save As recovery.
# Not part of the repo. Put a COPY of a ledger on the mount, never the original.
set -euo pipefail

BASE=/home/dave/flakey
IMG="$BASE/backing.img"
MNT="$BASE/mnt"
DM=flakeyledger
SIZE_MB=200

loop() { cat "$BASE/.loop"; }
sz() { sudo blockdev --getsz "$(loop)"; }

case "${1:-}" in
  setup)
    mkdir -p "$BASE" "$MNT"
    [ -f "$IMG" ] || dd if=/dev/zero of="$IMG" bs=1M count="$SIZE_MB" status=none
    L=$(sudo losetup --find --show "$IMG"); echo "$L" | sudo tee "$BASE/.loop" >/dev/null
    sudo chown "$USER" "$BASE/.loop"
    echo "0 $(sudo blockdev --getsz "$L") linear $L 0" | sudo dmsetup create "$DM"
    sudo mkfs.ext4 -q -F /dev/mapper/"$DM"
    sudo mount -o errors=continue /dev/mapper/"$DM" "$MNT"
    sudo chown "$USER" "$MNT"
    echo "healthy; mount at $MNT — copy a ledger there and run the app on it"
    ;;
  break)   # all I/O to the device fails with EIO
    # An app that already holds the ledger open then gets a genuine SQLite
    # "disk I/O error" on its next save. (Opening a *fresh* connection while
    # broken reports "unable to open database file" instead -- not what the
    # app hits.) There is no 'heal': recovering an ext4 in place after it has
    # taken EIO is unreliable, and the point of the test is recovery onto a
    # healthy disk anyway. For another round, teardown then setup.
    sudo dmsetup suspend "$DM"
    sudo dmsetup reload "$DM" --table "0 $(sz) error"
    sudo dmsetup resume "$DM"
    echo "BROKEN: the device now returns disk I/O errors"
    ;;
  teardown)
    # Normal (not lazy) unmount, and remove the mapping *before* the loop:
    # a lazy unmount or pulling the loop out from under an active mapping is
    # what orphans the device into an unremovable state.
    if mountpoint -q "$MNT"; then
      if ! sudo umount "$MNT" 2>/dev/null; then
        echo "Can't unmount $MNT -- something is still using it."
        echo "Usually a shell with its working directory inside it: 'cd' out of"
        echo "$MNT (and close any app on a ledger there), then run teardown again."
        exit 1
      fi
    fi
    sudo dmsetup remove "$DM" 2>/dev/null || true
    [ -f "$BASE/.loop" ] && sudo losetup -d "$(loop)" 2>/dev/null || true
    rm -f "$BASE/.loop"
    echo "cleaned up (backing image left at $IMG; rm -rf $BASE to remove)"
    ;;
  *) echo "usage: $0 {setup|break|teardown}  (no heal -- teardown+setup for a repeat)"; exit 1 ;;
esac
