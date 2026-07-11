# Obsidian Vault Backup

A standalone macOS script that creates encrypted, versioned backups of an
Obsidian vault in MEGA.

The vault can continue living in iCloud: this project adds an independent
offsite backup layer and does not replace the existing sync workflow.

> [!IMPORTANT]
> If the vault is stored in iCloud Drive, enable **Keep Downloaded** for the
> vault (or its enclosing Obsidian folder) in Finder before relying on scheduled
> backups. See [Using an iCloud vault](docs/usage.md#using-an-icloud-vault).

## How it works

```text
Obsidian vault in iCloud
          │
          ▼
Kopia encrypted snapshots
          │
          ▼
rclone transport
          │
          ▼
MEGA repository
```

- **Kopia** provides encryption, compression, deduplication, snapshots, and
  retention.
- **rclone** connects Kopia to MEGA.
- **launchd** runs the backup automatically on macOS.
- **KopiaUI** provides visual history browsing, mounting, and restores.

The default retention policy keeps 14 daily, 8 weekly, and 12 monthly
snapshots. The whole selected directory is backed up, including `.obsidian/`.

## Quick start

Download the standalone script and run it in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Ax51/obsidian-valut-backup/main/obsidian-vault-backup.sh \
  -o obsidian-vault-backup.sh
chmod +x obsidian-vault-backup.sh
./obsidian-vault-backup.sh
```

Download it to a file instead of piping it into Bash. The script needs a local
copy so it can install itself at a stable path for scheduled runs.

During the first run, the script:

1. displays a risk and filesystem-change disclaimer that must be explicitly
   accepted with `[y/N]` on the first run;
2. checks that it is running on macOS;
3. offers to install Homebrew when necessary;
4. offers to install Kopia, rclone, and KopiaUI;
5. asks for the source directory and MEGA credentials;
6. creates or connects to an encrypted Kopia repository;
7. offers to add the `obsidian-backup` command through a Homebrew `bin`
   symlink;
8. runs the first backup immediately; and
9. installs one `launchd` schedule without creating duplicates.

After acceptance, the script records `DISCLAIMER_ACCEPTED=true` and an
acceptance timestamp in `~/.config/obsidian-vault-backup/settings.sh`. Later
manual and scheduled runs read that setting and do not ask again. Declining
exits before the script writes configuration or performs backup actions.

Settings and the permanent script are stored under:

```text
~/.config/obsidian-vault-backup
```

If accepted, the optional shell command is installed as
`$(brew --prefix)/bin/obsidian-backup` and points to the permanent script. It
does not modify shell profile files. Afterwards, a manual backup can be started
from any directory with:

```bash
obsidian-backup
```

Source paths are normalized before they are saved. A relative input such as
`./docs` is resolved against the directory from which the script was launched
and stored as an absolute path, so later manual and scheduled runs cannot point
at a different directory accidentally. Finder/Terminal-style escaped paths such
as `/Users/me/Library/Mobile\ Documents/...` can be pasted into the interactive
prompt directly.

## Command-line options

```text
--source PATH          Use a different source for this run only.
--no-immediate-backup  Configure the flow without starting a backup now.
--no-schedule          Do not install or update the launchd schedule.
--update-settings      Update saved settings and credentials interactively.
--verify               Verify 100% of snapshot files after the backup.
--restore              Restore the latest snapshot into the saved source.
--inspect              Show configuration and schedule status without changes.
--version              Show the script version.
-h, --help             Show built-in help.
```

For example, configure everything without performing the first backup:

```bash
./obsidian-vault-backup.sh --no-immediate-backup
```

`--no-schedule` only skips schedule installation or updates; it does not unload
an existing launchd job. `--source` applies only to the current process and is
never saved. For exact side effects and safe combinations, see
[Options and common flag combinations](docs/usage.md#options).

To restore into the configured source from its latest snapshot:

```bash
obsidian-backup --restore
```

Every restore is manual and disables backup and schedule changes for that run.
The script first asks whether existing files may be overwritten; the default
restores the snapshot to protected staging and copies only missing files into
the source. It then requires a separate confirmation before writing anything.

Update settings later using the installed copy:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh --update-settings
```

Inspect the saved source, last successful backup, and launchd state without
changing anything:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh --inspect
```

Scheduled backups use a daily wake-aware calendar event, defaulting to 03:00
local time. If the Mac is asleep, launchd starts the job after wake. The script
then waits for MEGA connectivity, applies the configured soak period (10 minutes
by default), and checks that the source tree has settled before starting Kopia.

Every action-oriented manual run from a downloaded file compares its version
with the installed copy. A newer version atomically refreshes the installed
script, an equal version leaves it untouched, and an older script cannot
overwrite a newer installed version. `--help`, `--version`, and `--inspect` exit
without changing the installed copy.

## Test before using the real vault

Kopia's rclone repository backend is experimental, and MEGA is not listed as an
officially tested provider. Point the first run at a disposable test directory,
not the real vault.

The acceptance test is complete only after you can:

1. create at least two snapshots with changed files;
2. verify the repository with `--verify`;
3. browse both versions in KopiaUI;
4. mount a snapshot; and
5. restore the complete test vault into a separate directory.

After that, update the source to the real vault and perform another full restore
into a neighbouring directory before relying on the schedule.

## Security

- Kopia encrypts repository contents before they leave the Mac.
- The Kopia repository password is stored in macOS Keychain for unattended
  backups.
- rclone stores the MEGA password in obscured form in its standard config.
  Obscuring prevents casual viewing but is not strong encryption.
- Local configuration files are restricted to the current macOS user.
- The MEGA password, MEGA recovery key, and Kopia repository password should
  also be kept in Apple Passwords as independent recovery records.

Losing the Kopia repository password makes the encrypted backup unrecoverable.
Always restore into a new directory first; never validate recovery by
overwriting the live vault.

## Documentation

- [Standalone backup script](obsidian-vault-backup.sh)
- [Setup, acceptance test, and restore guide](docs/usage.md)
- [Connect KopiaUI and restore an existing backup](docs/kopia-ui.md)
- [Architecture decisions](docs/architecture-decisions.md)

## Current status

The standalone flow and its scheduling behaviour have been tested locally with
isolated command stubs. The remaining validation gate is a real end-to-end
Kopia → rclone → MEGA backup and restore using a disposable vault.
