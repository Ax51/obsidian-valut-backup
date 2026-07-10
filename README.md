## What is this project
This is a future backup setup for my Obsidian vault.

The vault already lives in iCloud and I want to keep it that way. This project is only about adding an extra backup layer on top of the current storage.

## Current idea
- use `restic` or `kopia` to create backup snapshots
- use `rclone` as a transport layer to push backups into cloud storage
- store backups in `Mega` free tier (`20 GB`)
- make sure backups are encrypted because some notes contain sensitive data
- run backups by schedule on my Mac

## Why this is interesting
- iCloud sync is not the same as backup
- snapshots give versioned recovery instead of just "latest state"
- encrypted offsite copy reduces the risk of local device loss
- the vault can stay in the current iCloud-based workflow without migration

## Open decisions
- `restic` vs `kopia`
- whether `rclone` is really needed if the backup tool can already work well with the selected target
- snapshot frequency
- retention policy
- restore workflow testing
- how much of the `20 GB` Mega free tier is realistically usable for this vault over time

## Rough architecture
1. Obsidian vault stays in `iCloud`
2. A scheduled job on Mac creates encrypted snapshots
3. Backup data is uploaded to cloud storage through `rclone`
4. Recovery should be possible for a single file, note folder, or the whole vault

## Success criteria
- backups run automatically
- snapshots are encrypted at rest
- restore steps are documented and verified
- solution fits into the Mega free tier, at least for the current vault size

## Implementation

- [Architecture decisions](docs/architecture-decisions.md)
- [Setup, isolated acceptance test, and recovery guide](docs/usage.md)
