# disclean（ディスクリン）

[日本語](README.md)

A macOS disk cleaner that **shows you the weight before it deletes anything**.
Deletion goes through a quarantine store, and for 7 days (by default) everything can be put back exactly where it was.

- The three steps are separate: **scan (read only) → plan (choose) → apply (move to quarantine)**
- Missing permissions, empty targets and absent tools are never counted as success — each one is reported **with a reason** (no silent failures)
- The CLI (`disclean`) and the GUI (`Disclean.app`) share one core, one quarantine store and one audit log

## Install

```bash
brew install suzuki-junya108/disclean/disclean
```

The GUI is the `.dmg` on the [Releases](https://github.com/suzuki-junya108/disclean/releases) page (signed and notarised).

Requires macOS 14 or later, Apple Silicon or Intel.

## Use

```bash
disclean doctor     # check the environment (permissions, external tools, storage, OS drift)
disclean scan       # find out what can be freed — reads only, deletes nothing
disclean inspect uv-cache   # look inside a target, file by file
disclean apply      # move the selected items into quarantine (Tier A is selected by default)
disclean undo --last        # undo the last run
disclean purge      # delete from quarantine for good (cannot be undone)
disclean report     # show the big things disclean never touches
disclean report --unknown   # find large places no rule looks at (deletes nothing)
disclean history    # what has been done so far
disclean update     # review and apply rule updates
```

Every subcommand accepts `--json` and prints a single object with a `schemaVersion`.

### See what is inside before deleting

`inspect` reads only. It lists the contents largest first, tells you what kind of file each one is
(archive, log, cached blob …) and what happens if it goes away.

```bash
disclean inspect uv-cache
disclean inspect --path ~/.cache/uv/wheels   # one level down (home and quarantine only)
disclean inspect --run 01J...                # what is inside a quarantined run
```

### What disclean looks at

105 bundled rules (Tier A 38 / B 50 / look-only 17), covering package managers, build tools,
browsers, desktop apps, simulators and local model caches. `disclean rules list` prints them all.

Anything **not** covered shows up in `disclean report --unknown`, so the gaps in the rule set are
visible on your own machine instead of being invisible.

### Risk tiers

| Tier | Meaning | Default |
|---|---|---|
| A | Cheap to re-create, low risk | selected |
| B | Look inside before removing | not selected |
| look-only (C) | **Never deleted.** Size and manual steps only | cannot be selected |

- Directory rules move things into quarantine and can be undone with `disclean undo`.
- A few rules hand the work to an external tool (Docker, simulators). Those **cannot be undone**, and the confirmation screen says so.

## Rule updates

Cache locations change when macOS changes, so the **rules** are shipped separately, signed with Ed25519.

- Updates are verified against a public key compiled into the binary. TLS or GitHub being compromised is not enough to install a rule.
- Changes that **add** things to delete require your approval; changes that remove things apply automatically.
- Turn it off completely with `disclean update --off`. Nothing is sent except the disclean and macOS versions.

## Safety

- Everything lives under your home directory. Paths shallower than two levels, system locations, symlinks and your exclusion list are refused.
- A move is a same-volume `rename(2)`: it is atomic, so there is no half-moved state, and it takes the same time for 1 KB or 100 GB.
- Every move, restore and permanent delete is appended to a JSONL audit log. **If the log cannot be written, nothing is deleted.**
- Free space is measured before and after, and the report never claims more than was actually moved.

## Uninstall

```bash
disclean purge --all      # empty the quarantine first (optional)
brew uninstall disclean
rm -rf ~/.local/state/disclean ~/.config/disclean   # state and settings
```

Then drag `Disclean.app` to the Trash if you installed the GUI.

## Getting help

- **Bugs and requests**: open a [GitHub Issue](https://github.com/suzuki-junya108/disclean/issues).
  Pasting the output of `disclean doctor` makes diagnosis much faster.
- **Rule suggestions**: attach the output of `disclean report --unknown`.
  For your machine only, drop JSON into `~/.config/disclean/rules.d/`.
- **Deleted something by mistake**: `disclean undo --last` within 7 days.
- **Security reports**: please use
  [Security Advisories](https://github.com/suzuki-junya108/disclean/security/advisories/new) rather than a public issue.

## License

MIT ([LICENSE](LICENSE)). The bundled fonts keep their own SIL Open Font License 1.1 terms.
