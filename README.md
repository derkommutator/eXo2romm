# eXo2romm

Repackage [eXoDOS](http://www.exe.dev/exodos/) game zips so they work cleanly in
[RomM](https://github.com/rommapp/romm).

## The problem

eXoDOS ships each game zip with a `dosbox.conf` whose `[autoexec]` mounts are
written relative to the **pack root**, e.g.:

```ini
[autoexec]
mount c .\eXoDOS\Abaron
imgmount d .\eXoDOS\Abaron\CD\ABARON.CUE -t cdrom
```

That works when the whole eXoDOS tree is intact and DOSBox is launched from the
pack root. It breaks the moment each game lives as a standalone zip in a RomM
library: inside the unzipped game, `.\eXoDOS\Abaron\...` does not exist.

## The fix

`eXo2romm.sh` takes each zip's top-level directory name, finds the matching
template `dosbox.conf` in the eXoDOS `!dos` tree, strips the game-directory
component from the mount paths, and grafts the corrected conf back into a copy
of the zip:

```ini
[autoexec]
mount c .\
imgmount d .\CD\ABARON.CUE -t cdrom
```

Only `mount` / `imgmount` / `boot` keyword lines (with optional leading `@`)
are touched; comments (`#`, `rem`) and paths pointing at a *different*
directory are left exactly as they are. Original zips are never modified —
output is written to a separate directory.

## Requirements

`bash`, coreutils, and `unzip`/`zip`. Nothing else.

## Usage

```bash
./eXo2romm.sh /path/to/eXoDOS/*.zip
# or a single game:
./eXo2romm.sh "Abaron (1995).zip"
```

Paths are configured in the block at the top of the script, or overridden via
the environment:

| Variable     | Default                                | Meaning                             |
| ------------ | -------------------------------------- | ----------------------------------- |
| `DOS_DIR`    | `/data/eXoDOS/Content/eXo/eXoDOS/!dos` | The `!dos` template tree from eXoDOS |
| `OUTPUT_DIR` | `/var/lib/romm/library/roms/dos`       | Where repackaged zips are written    |
| `ERROR_LOG`  | `$OUTPUT_DIR/eXo2romm-errors.log`      | Warnings/skips log                   |

```bash
DOS_DIR=/mnt/exodos/Content/eXo/eXoDOS/'!dos' \
OUTPUT_DIR=/srv/romm/library/roms/dos \
./eXo2romm.sh ~/Downloads/eXoDOS/*.zip
```

## Behavior

- **Never touches input zips.** Each zip is copied to `OUTPUT_DIR`, and the
  edited `dosbox.conf` is added inside the copy.
- **Resume-safe.** If the output zip already exists it is skipped untouched, so
  re-running the same command continues a partial batch.
- **Warn and skip, never abort.** Zips that don't unzip into a single
  top-level directory, or have no matching `dosbox.conf` under `DOS_DIR`, are
  reported on stderr, appended to `ERROR_LOG`, and the run continues. A summary
  line (`N processed, M skipped`) is printed at the end.
- **CRLF preserved.** Edited confs keep the original line endings, and the zip
  clone keeps all other entries byte-identical.

> **Tip:** the script stages edits via `mktemp -d`. On machines where `/tmp` is
> a small tmpfs, point `TMPDIR` somewhere roomier before running:
> `TMPDIR=/var/tmp ./eXo2romm.sh ...`

## Disclosure

This code is **AI-generated, human-reviewed**. It was written by
[Hermes Agent](https://hermes-agent.nousresearch.com) (Nous Research) —
harness: Hermes Agent desktop app; model: `nvidia/Qwen3.8-Flash-Next-FP4-Local` —
through an iterative build-and-test session against real eXoDOS zips, and
reviewed by a human before publication. Use at your own risk; review the script
yourself before running it on anything you care about (it only ever writes to
`OUTPUT_DIR`, but you know what you signed up for with shell scripts).
