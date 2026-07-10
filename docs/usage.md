# Usage

## Prerequisites

Install the macOS versions of `kopia` and `rclone`. Keep the KopiaUI app
installed: it is the recovery interface, while the scripts use the same Kopia
engine through its CLI.

Before the first run, save two recovery records in Apple Passwords:

1. the MEGA account recovery key; and
2. a strong, unique Kopia repository password.

The initial setup also writes the Kopia password to macOS Keychain so that a
background `launchd` job can run without displaying a prompt. The Keychain copy
is operational convenience, not the sole recovery copy.

## Isolated acceptance test

Run these commands from the project root. They only use a generated fixture.

```bash
cp config/backup.env.example config/local.env
scripts/create-test-fixture.sh create
```

Set the printed directory as `BACKUP_SOURCE` in `config/local.env`. Keep the
provided `RCLONE_REMOTE_NAME=mega`, or change it to the name you choose in
rclone.

```bash
scripts/setup.sh
scripts/setup.sh --create-repository
scripts/run-backup.sh
scripts/create-test-fixture.sh mutate /tmp/obsidian-vault-backup-fixture.XXXXXX
scripts/run-backup.sh
```

The first setup invokes `rclone config` if the named remote does not yet exist.
Create a MEGA remote there and return to the script. `setup.sh` asks for the
Kopia password only if its Keychain entry is missing.

Open KopiaUI, connect it to the newly created rclone repository, and use the
same repository password. Confirm that both revisions are visible; mount one
and restore the latest one into a separate directory. Do not restore over the
fixture or a live vault.

Finally, verify every backed-up file:

```bash
scripts/verify-backup.sh
```

## Enable the real vault only after the test passes

Change `BACKUP_SOURCE` to the real vault path, run one manual backup, and
restore it to a neighbouring directory. Once that passes, enable the agent:

```bash
scripts/install-launchd.sh
```

The agent runs once at login and then every 24 hours. Its log is in
`logs/launchd.log`; a concurrent run is skipped.

## Restore

Use KopiaUI to browse the snapshot history, mount a snapshot, or restore the
entire vault to a new directory. Keep the old vault untouched until the restored
copy is checked in Obsidian.
