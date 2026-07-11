# Architecture decisions

## Purpose and scope

This project adds an independent, encrypted, offsite backup to an Obsidian vault
that continues to use iCloud for day-to-day synchronisation. It must not modify
the vault. The source path is configurable, so the initial setup can be tested
entirely with a disposable fixture directory.

## Decision status

The target design is approved. The choice of backup engine is **Kopia, pending a
small compatibility test with MEGA**. The test must succeed before the real
vault is configured.

## Chosen design

```
configurable vault path
        |
        v
Kopia CLI (snapshots, encryption, retention)
        |
        v
rclone remote (MEGA transport)
        |
        v
MEGA repository

launchd runs the installed standalone script on its daily calendar schedule.
KopiaUI is available separately for browsing, mounting, and restoring snapshots.
```

### Components

| Component | Decision | Reason |
| --- | --- | --- |
| Backup engine | Kopia | GUI makes history browsing, mounting, and complete restores more approachable; CLI remains suitable for automation. |
| Remote transport | rclone | Required for MEGA, which is not a native Kopia repository backend. Kopia starts and manages rclone once the remote is configured. |
| Remote storage | MEGA free tier | The vault is approximately 40–45 MB, so the available quota is sufficient with the selected retention policy. |
| Scheduler | macOS `launchd` | A daily `StartCalendarInterval` event provides wake-after-sleep catch-up. A configurable soak and preflight run before Kopia. |
| Manual shell entry point | Optional Homebrew `bin` symlink | `obsidian-backup` works across shells without modifying user profile files and continues to target the stable installed script after atomic upgrades. |
| Secret storage | macOS Keychain and a restricted rclone config | The Kopia password lives in Keychain. rclone stores the MEGA password in its obscured format in a file readable only by the current macOS user. Recovery copies live in Apple Passwords. |
| Human recovery interface | KopiaUI | It can browse history, mount a snapshot, restore individual items, or restore the entire vault into another directory. |

## Backup policy

- Request one run each day at the configured local time. A firing missed during
  sleep runs after wake; a firing missed while powered off waits until the next
  calendar day.
- Apply MEGA connectivity retries, then a scheduled-only soak (10 minutes by
  default) and source quiet-window check before starting Kopia.
- Include the whole vault, including `.obsidian/`.
- Keep 14 daily, 8 weekly, and 12 monthly snapshots.
- Use Kopia's encrypted repository defaults; do not add a second encryption layer.
- Keep the vault path in user configuration, never hard-code a personal iCloud
  path, and persist it only as a normalized absolute directory path.
- Treat each normalized source path as a separate Kopia snapshot history. A
  switch from a fixture to the real vault does not merge or rewrite old
  snapshots.

Kopia's own policy supports retention and snapshot scheduling, but `launchd` is
the source of truth for this project. This keeps scheduling, Keychain access,
logging, and retry behaviour in one macOS-native entry point. The Kopia policy
does not configure an automatic snapshot interval, avoiding duplicate runs.

The complete operational flow is distributed as one standalone script. On its
first interactive run it copies itself to
`~/.config/obsidian-vault-backup/obsidian-vault-backup.sh`, where the launchd
agent can invoke it from a stable path. The same directory contains the user's
settings and the Kopia connection. The MEGA remote uses rclone's standard
config location so that Kopia CLI and KopiaUI can both discover it.

After explicit interactive consent, the script may create
`$(brew --prefix)/bin/obsidian-backup` as a symlink to the stable installed
copy. It never modifies shell startup files or replaces an existing command.
Declining the offer is persisted, while `--update-settings` provides an explicit
way to receive the offer again.

The script carries a semantic version. Manual runs atomically refresh the
installed copy only when the running version is newer. Equal versions are a
no-op, while an older copy is prevented from overwriting a newer installation.

## Security and recovery

- Store the Kopia repository password and MEGA credentials in Apple Passwords
  as independent recovery records.
- Store the Kopia repository password in Keychain for unattended automation.
- rclone stores the MEGA password in obscured form in its mode-`600` config.
  Obscuring is reversible and protects against casual viewing, not an attacker
  who already has access to the macOS account.
- Store the MEGA recovery key in Apple Passwords too.
- Losing the Kopia repository password makes the encrypted repository
  unrecoverable; changing or deleting the local Keychain item must not be the
  only copy of a secret.
- Never restore over the live vault during validation. Restore to a sibling or
  temporary directory first.

## Definition of done

Before using the real vault, the implementation must prove all of the following
against a disposable test fixture:

1. Create and upload an encrypted snapshot through Kopia, rclone, and MEGA.
2. Run a second snapshot after adding, editing, moving, and deleting test files.
3. Browse both snapshot histories in KopiaUI and mount one snapshot.
4. Restore the newest snapshot into a separate directory and compare it with
   the expected fixture contents.
5. Restore an older snapshot or an individual file to demonstrate version
   recovery.
6. Verify repository data with Kopia after the upload.

After this succeeds, configure the real vault path and repeat a full restore to
a neighbouring directory. That successful restore is the acceptance criterion.

## Open risk and decision gate

Kopia's rclone repository backend is documented as experimental and its
officially tested providers do not include MEGA. The project will therefore run
the above isolated compatibility test first. If any of snapshot creation,
listing, GUI browsing, mounting, full restore, or verification is unreliable,
we will switch the engine to **Restic** while retaining rclone, MEGA, launchd,
Keychain, and the same retention policy. This keeps the fallback small and
avoids experimenting on the real vault.

## Explicit non-goals

- Replacing iCloud or changing the current Obsidian workflow.
- Backing up arbitrary Mac data.
- A second remote provider or ransomware-resistant object locking in the first
  version.
- Running a permanently active backup daemon.
