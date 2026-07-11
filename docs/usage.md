# Usage

The complete setup and backup flow lives in one standalone macOS script:
[`obsidian-vault-backup.sh`](../obsidian-vault-backup.sh).

## Download and run

Download the script from GitHub and run it in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Ax51/obsidian-valut-backup/main/obsidian-vault-backup.sh \
  -o obsidian-vault-backup.sh
chmod +x obsidian-vault-backup.sh
./obsidian-vault-backup.sh
```

Downloading to a file is intentional: the script installs a permanent copy for
`launchd`. Do not use `curl ... | bash`.

The first run:

1. displays a disclaimer and requires explicit `[y/N]` confirmation before it
   installs software, writes operational configuration, or starts a backup;
2. checks that the computer is running macOS;
3. offers to install Homebrew if it is missing;
4. offers to install `kopia` and `rclone`, plus the optional KopiaUI app;
5. asks for the vault path, MEGA credentials, remote folder, and schedule;
6. stores non-secret settings under `~/.config/obsidian-vault-backup` and the
   MEGA remote in rclone's standard config so KopiaUI can see it;
7. stores the Kopia repository password in macOS Keychain;
8. creates or connects to the encrypted repository;
9. runs a backup immediately; and
10. installs one `launchd` schedule if it is not already present.

Acceptance and its UTC timestamp are stored in `settings.sh`, so the disclaimer
is not shown again after the user agrees. Declining does not write an acceptance
record. The internal `--scheduled-run` mode is deliberately non-interactive so
launchd backups can complete unattended.

The standard rclone config contains an obscured MEGA password. Obscuring
prevents casual reading but is not strong encryption. rclone prints the config
location during setup and restricts the file to the current macOS user. Keep the
MEGA password, MEGA recovery key, and Kopia repository password in Apple
Passwords as independent recovery records.

The source directory is always saved as an absolute, physically resolved path.
If `./docs` is entered, it is resolved relative to the current Terminal working
directory during that run. A previously saved relative source is rejected and
must be entered again manually; launchd never guesses how to resolve it. Paths
dragged from Finder or copied in shell-escaped form are accepted: backslashes in
inputs such as `Mobile\ Documents/com\~apple\~CloudDocs` are decoded before the
directory is resolved.

## Options

| Option | Persistent changes | Backup and schedule behavior |
| --- | --- | --- |
| `--source PATH` | Does not change `settings.sh`. | Uses the normalized path only for the immediate backup in this process. A scheduled run continues to read the saved source. |
| `--no-immediate-backup` | Configuration changes are still saved. | Skips `snapshot create`. Repository connection, retention policy, and schedule setup still run. |
| `--no-schedule` | Does not delete or unload anything. | Skips installing or updating the launchd plist. An existing loaded schedule remains active. |
| `--update-settings` | Rewrites `settings.sh` with the resulting values and may update rclone or Keychain credentials. | By itself, it is followed by an immediate backup and schedule reconciliation. |
| `--verify` | Does not change saved settings. | After a successful immediate backup, downloads, decrypts, and verifies 100% of snapshot files. It does nothing when the backup is skipped. |
| `--inspect` | None. | Prints saved state and exits before dependency checks, repository access, self-update, backup, or schedule changes. Do not combine it with action flags. |
| `--version` | None. | Prints the running file's version and exits. |
| `-h`, `--help` | None. | Prints built-in help and exits. |

`--scheduled-run` is an internal launchd argument. It is intentionally omitted
from public help and must not be used for interactive or manual runs.

For `--update-settings`, the value in square brackets is the currently loaded
value. Press **Return** to keep it. The MEGA and Kopia password questions use
`[y/N]`; pressing **Return** keeps the existing password. The script never
turns an empty answer into an empty saved value when a default is displayed.
If the saved source is relative, missing, or otherwise invalid, a valid existing
directory must be entered and cannot be skipped.

Changing the source through `--update-settings` affects the next scheduled run
because launchd reads `settings.sh` at runtime—even if that settings update used
`--no-schedule`. The flag prevents plist changes; it does not pause an already
loaded job.

Action-oriented manual runs compare their semantic version with the copy in
`~/.config/obsidian-vault-backup`. A newer version refreshes the installed copy
atomically, an equal version is a no-op, and an older version stops instead of
overwriting a newer installation. Read-only `--help`, `--version`, and
`--inspect` calls exit before the installed-copy update.

## Common flag combinations

Run a normal backup using saved settings and reconcile the schedule:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh
```

Update settings without immediately backing up and without rewriting the
launchd plist:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh \
  --update-settings --no-immediate-backup --no-schedule
```

This does not pause an existing schedule. To temporarily unload it before a
settings experiment, run:

```bash
launchctl bootout \
  "gui/$(id -u)/com.$(id -un).obsidian-vault-backup"
```

The plist remains on disk. A later normal script run loads it again.

Back up a disposable directory once without changing the saved source or
launchd plist:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh \
  --source /tmp/TestVault --no-schedule
```

Create a snapshot from the saved source, fully verify snapshot contents, and
leave the launchd plist untouched:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh \
  --verify --no-schedule
```

Do not combine `--verify` with `--no-immediate-backup`: verification is part of
the backup flow and therefore will not run when snapshot creation is skipped.
Similarly, `--source PATH --no-immediate-backup` neither saves nor backs up the
override and has no useful source-related effect.

## Inspect configuration and schedule

Use the installed script to inspect state without connecting to MEGA or making
changes:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh --inspect
```

The report shows the installed version, normalized source, repository connection
file, last successful backup, launchd plist, whether the service is loaded,
current job state, invocation count, last exit code, and log path.

The schedule uses launchd `StartCalendarInterval`, daily at the configured local
time (03:00 by default). A calendar event missed during sleep runs after wake;
multiple sleeping events are coalesced. An event missed while the Mac is fully
powered off is not recovered and waits for the next calendar day.

After a scheduled launch, the script retries MEGA access for up to five minutes,
waits for the configured soak period (10 minutes by default), and verifies that
the source metadata remains stable. This ordering gives iCloud time to settle
after network connectivity returns. `--inspect` reports the configured calendar
time, soak, next calendar event, launchd state, and last exit code.

Changing the remote name or remote folder is done through `--update-settings`,
because those values identify the repository rather than just one backup run.
If they change, the previous Kopia connection file is preserved with a timestamp
before the script asks whether to create or connect to the new repository.
Updating the Kopia password replaces only its local Keychain copy; it must match
the password already used by the repository.

## Switch from a test folder to the real vault

Update the saved source without creating a backup immediately:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh \
  --update-settings --no-immediate-backup --no-schedule
```

Enter the real vault directory. The script normalizes and saves its absolute
path. Retention and repository settings are global and do not need to be
reconfigured. Run a manual backup after reviewing the new path with `--inspect`.

Kopia identifies snapshot histories by `username@hostname:/source/path`.
Changing the source path therefore starts a separate history; it does not alter,
rename, or merge the test snapshots. The previous test history remains
available in KopiaUI and can be deleted there after the real-vault restore test
passes. Do not copy the test history to the real source identity because the two
directories represent different data.

### Using an iCloud vault

An iCloud Drive vault can be backed up because it is exposed as a normal macOS
directory. For an Obsidian vault shared with iOS/iPadOS, select the vault inside
**iCloud Drive → Obsidian**. On disk it is commonly under:

```text
~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<Vault Name>
```

Use Obsidian's **Reveal in Finder** action and drag the vault folder into
Terminal rather than typing this internal path manually.

Before relying on unattended backups, right-click the vault or the enclosing
Obsidian folder in Finder and choose **Keep Downloaded**. iCloud can otherwise
evict older files when storage optimization is enabled; a scheduled backup may
then require network downloads or fail while the Mac is offline. Perform a
manual backup and complete restore after switching to the real iCloud vault.

There is no stable public macOS command that proves an iCloud folder is fully
synchronized. The soak and quiet-window checks are therefore best-effort, not
an atomic filesystem snapshot. If files change while Kopia is reading them, the
script creates one follow-up snapshot. Continuous changes or unreadable files
still cause the scheduled run to fail rather than claim a clean backup.

## Safe acceptance test

For the first run, point the script at a disposable folder rather than the real
vault. Put several Markdown files and a `.obsidian` directory in it, run a
backup, edit the files, and run the installed script again:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh --no-schedule --verify
```

Open KopiaUI, choose **Rclone Remote**, and connect using the rclone executable,
the same remote path (for example `mega:ObsidianVaultBackup`), and the Kopia
password. Because the script uses rclone's standard config, the remote is
available to KopiaUI too. Confirm that both revisions can be browsed, mount a
snapshot, and restore it into a separate folder. After this passes, update the
source path:

See the complete [KopiaUI connection and restore guide](kopia-ui.md) for exact
fields, password retrieval, validation, and troubleshooting.

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh \
  --update-settings --no-immediate-backup
```

Then run the script normally to back up the real vault and install the daily
schedule.

## Files created on the Mac

```text
~/.config/obsidian-vault-backup/
├── obsidian-vault-backup.sh  permanent runnable copy
├── settings.sh               source, remote, calendar, and soak settings
├── repository.config         Kopia connection metadata
├── state.sh                  last successful backup state
└── backup.log                launchd output

~/Library/LaunchAgents/
└── com.<system-user>.obsidian-vault-backup.plist
```

The Kopia repository password is stored separately in macOS Keychain.
The MEGA remote is stored in rclone's standard config; run `rclone config file`
to print its location.

## Restore

Use KopiaUI to browse history, download individual notes, mount a snapshot, or
restore the whole vault. Always restore into a new directory first; keep the
live vault untouched until the restored copy has been checked in Obsidian.
