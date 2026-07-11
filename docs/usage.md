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

## Options

```text
--source PATH          Override the saved source for this run only.
--interval SECONDS     Override the schedule interval without saving the setting.
--no-immediate-backup  Complete setup without starting a backup now.
--no-schedule          Do not install or inspect the launchd schedule.
--update-settings      Interactively update saved settings and credentials.
--verify               Verify 100% of snapshot files after backup.
--version              Show the script version.
-h, --help             Show built-in help.
```

On every manual run from another location, the script compares its semantic
version with the copy in `~/.config/obsidian-vault-backup`. A newer version
refreshes the installed copy atomically, an equal version is a no-op, and an
older version stops instead of overwriting a newer installation.

Changing the remote name or remote folder is done through `--update-settings`,
because those values identify the repository rather than just one backup run.
If they change, the previous Kopia connection file is preserved with a timestamp
before the script asks whether to create or connect to the new repository.
Updating the Kopia password replaces only its local Keychain copy; it must match
the password already used by the repository.

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
├── settings.sh               source, remote, and interval settings
├── repository.config         Kopia connection metadata
└── backup.log                launchd output

~/Library/LaunchAgents/
└── com.example.obsidian-vault-backup.plist
```

The Kopia repository password is stored separately in macOS Keychain.
The MEGA remote is stored in rclone's standard config; run `rclone config file`
to print its location.

## Restore

Use KopiaUI to browse history, download individual notes, mount a snapshot, or
restore the whole vault. Always restore into a new directory first; keep the
live vault untouched until the restored copy has been checked in Obsidian.
