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

launchd runs the backup script after a missed scheduled run.
KopiaUI is available separately for browsing, mounting, and restoring snapshots.
```

### Components

| Component | Decision | Reason |
| --- | --- | --- |
| Backup engine | Kopia | GUI makes history browsing, mounting, and complete restores more approachable; CLI remains suitable for automation. |
| Remote transport | rclone | Required for MEGA, which is not a native Kopia repository backend. Kopia starts and manages rclone once the remote is configured. |
| Remote storage | MEGA free tier | The vault is approximately 40–45 MB, so the available quota is sufficient with the selected retention policy. |
| Scheduler | macOS `launchd` | Native scheduler; configured to run missed jobs after the Mac next becomes available. |
| Secret store | macOS Keychain via `security` | The script asks for missing secrets once and then reads them non-interactively. No secret is committed to this repository. |
| Human recovery interface | KopiaUI | It can browse history, mount a snapshot, restore individual items, or restore the entire vault into another directory. |

## Backup policy

- Run once each day, with missed-run recovery rather than a strict wall-clock requirement.
- Include the whole vault, including `.obsidian/`.
- Keep 14 daily, 8 weekly, and 12 monthly snapshots.
- Use Kopia's encrypted repository defaults; do not add a second encryption layer.
- Keep the vault path in user configuration, never hard-code a personal iCloud path.

Kopia's own policy supports retention and a snapshot interval, but `launchd` is
the source of truth for this project. This keeps scheduling, Keychain access,
logging, and retry behaviour in one macOS-native entry point. The Kopia policy
will enforce retention and may be set to manual scheduling to avoid duplicate
runs.

## Security and recovery

- Store the Kopia repository password and MEGA credentials in Apple Passwords
  as the recovery record, and in Keychain only as the automation runtime store.
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
