# Connecting KopiaUI to an existing backup

This guide connects the KopiaUI desktop application to the repository already
created by `obsidian-vault-backup.sh`. It does not create another repository and
does not change the backup schedule.

## Before you start

The script must have completed at least one successful backup. You need:

- the Kopia repository password — this is not the MEGA account password;
- the existing rclone remote name and repository folder;
- the path to the rclone executable; and
- access to the same macOS account where the script configured rclone.

Print the values needed by KopiaUI:

```bash
command -v rclone
grep -E '^(REMOTE_NAME|REMOTE_PATH)=' \
  ~/.config/obsidian-vault-backup/settings.sh
```

With the default settings, the values are normally:

```text
Rclone Executable Path: /opt/homebrew/bin/rclone
Rclone Remote Path:     mega:ObsidianVaultBackup
```

Intel Macs may report `/usr/local/bin/rclone` instead. Always use the result of
`command -v rclone` from your Mac.

The repository password should be available in Apple Passwords. The automation
copy is also stored in macOS Keychain. If necessary, print it with:

```bash
security find-generic-password \
  -s "com.$(id -un).obsidian-vault-backup.kopia" \
  -a repository-password \
  -w
```

This command displays the secret in Terminal. Do not copy its output into
documentation, screenshots, shell scripts, or issue reports.

## Install KopiaUI

If KopiaUI was not installed during the script setup:

```bash
brew install --cask kopiaui
```

Open **KopiaUI** from the Applications folder.

## Connect to the repository

1. Open the **Repository** screen in KopiaUI.
2. Choose the option to connect to an existing repository. Do not create a new
   repository.
3. Select **Rclone Remote** as the storage type.
4. Enter the **Rclone Executable Path** returned by `command -v rclone`.
5. Enter **Rclone Remote Path** as `<REMOTE_NAME>:<REMOTE_PATH>`. With the
   defaults, this is `mega:ObsidianVaultBackup`.
6. Continue and enter the existing **Kopia repository password**.
7. Leave advanced repository format, encryption, hashing, and splitter options
   unchanged. Those values were fixed when the repository was created.
8. Finish the connection and wait for KopiaUI to load repository metadata.

Kopia may display a warning that the rclone storage provider is not actively
tested. This is expected for this project. It is also the reason the complete
restore acceptance test is mandatory before using the real vault.

The script and KopiaUI keep separate local connection files, but both connect
to the same encrypted repository. Connecting KopiaUI does not disable the CLI
backup flow.

## Confirm that the backup is visible

1. Open **Snapshots**.
2. Select the entry whose path matches the configured vault or test fixture.
3. Open the newest snapshot and browse several directories.
4. Confirm that `.obsidian/` and a representative selection of notes and
   attachments are present.
5. If two test snapshots were created, open both and confirm that their file
   histories differ as expected.

Do not add an automatic snapshot interval in KopiaUI. `launchd` owns scheduling
for this project, while the global Kopia policy owns retention.

## Restore the whole vault

1. In **Snapshots**, open the snapshot you want to test.
2. Choose **Restore**.
3. Select a new, empty destination outside the live vault, for example:

   ```text
   ~/Desktop/ObsidianVault-Restore-Test
   ```

4. Restore the complete snapshot and wait for the operation to finish.
5. Compare the restored directory with the expected vault contents.
6. Open the restored directory as a separate vault in Obsidian and verify notes,
   attachments, links, and settings.

Never test a restore by writing over the live iCloud vault.

## Browse or restore individual files

From a selected snapshot, KopiaUI can also:

- **Mount** the snapshot as a local drive for read-only browsing and copying;
- browse directories inside KopiaUI; or
- download or restore an individual note, attachment, or folder.

Mounting is convenient for exploration, but a complete restore into a separate
directory remains the acceptance criterion for this project.

## Troubleshooting

### The rclone remote is not available

Verify that KopiaUI is using the same macOS account and standard rclone config:

```bash
rclone config file
rclone listremotes
```

The expected list must contain `<REMOTE_NAME>:` — `mega:` with the defaults.

### Repository not found

Check the remote path exactly, including spelling, capitalization, the colon,
and the repository subdirectory:

```text
mega:ObsidianVaultBackup
```

Do not select the MEGA account root if the repository was created in a
subdirectory.

### Invalid repository password

Use the Kopia repository password saved during the first setup. The MEGA
password and MEGA recovery key cannot decrypt a Kopia repository.

### rclone executable not found

Run `command -v rclone` in Terminal and paste that complete absolute path into
KopiaUI. Do not assume the Homebrew prefix is the same on Intel and Apple
Silicon Macs.

### No snapshots are displayed

First confirm that the CLI backup completed successfully:

```bash
~/.config/obsidian-vault-backup/obsidian-vault-backup.sh \
  --no-schedule --verify
```

Then reconnect KopiaUI using the same remote path and repository password.

## Further reading

- [Kopia repository and rclone documentation](https://kopia.io/docs/repositories/)
- [KopiaUI getting started and restore documentation](https://kopia.io/docs/getting-started/)
- [Kopia installation documentation](https://kopia.io/docs/installation/)

