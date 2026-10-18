# flakey

A tiny harness for forcing a genuine SQLite **`disk I/O error`** on demand, so
disk-failure handling can be tested deterministically instead of waiting for a
flaky network or shared folder to misbehave.

It builds a loopback-backed block device via Linux device-mapper, puts an
`ext4` filesystem on it, and lets you switch all I/O to the device off (every
read/write returns `EIO`) and the filesystem into failure. A database held open
across the switch then gets a real `SQLITE_IOERR` — the same error a VMware
`vmhgfs` shared folder produces — rather than a simulated one.

## Requirements

Linux, with `dmsetup`, `losetup`, `mkfs.ext4`, the `dm_flakey`/`dm-error`
device-mapper targets, and **passwordless `sudo`** (the script uses `sudo` for
the loop device, the mapping, mkfs and mount).

## Usage

```bash
./flakey.sh setup        # create the device, format it, mount it at ./mnt
./flakey.sh break        # all I/O to the device now fails with EIO
./flakey.sh teardown     # unmount, remove the mapping and loop device
```

There is no `heal`: recovering an `ext4` in place after it has taken an `EIO`
is unreliable, and the point of the exercise is the recovery *onto a healthy
disk* anyway. For another round, `teardown` then `setup`.

## Testing an app

```bash
./flakey.sh setup
cp /path/to/a/copy.sqlite3 ./mnt/test.sqlite3    # always a COPY, never real data
your-app ./mnt/test.sqlite3                      # open it and make an edit
#   from another terminal:
./flakey.sh break
#   trigger a save in the app -> it should report "disk I/O error"
./flakey.sh teardown
```

## Gotchas

- **The app must already hold the database open before `break`.** A connection
  open across the failure gets `disk I/O error` on its next write. Opening a
  *fresh* connection while broken reports `unable to open database file`
  instead — not the case most apps hit.
- **Don't `cd` into `./mnt` in a shell you keep open.** A working directory
  inside the mount pins it, so `teardown` can't unmount — `cd` out first.
- **Always use a copy on the mount, never real data.** The point is to break it.

## What the script creates (not committed)

`setup` generates these as runtime artifacts; only `flakey.sh` (and this file)
belong in version control:

- `backing.img` — a 200 MB sparse file, the virtual disk behind the loop device.
- `mnt/` — the mountpoint.
- `.loop` — records which `/dev/loopN` is in use.

Remove them with `./flakey.sh teardown` (which releases the loop/mount) followed
by `rm -rf backing.img mnt .loop`. Run `teardown` *before* deleting
`backing.img`, or the loop device keeps the inode open and the space is not
freed.
