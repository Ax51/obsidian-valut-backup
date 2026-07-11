# AGENTS.md

## Project scope

This repository ships one standalone, macOS-only backup program:
`obsidian-vault-backup.sh`. Keep the operational flow in that file so users can
download it with `curl` and run it outside this repository.

The script must remain compatible with the system Bash 3.2 distributed with
macOS. Do not introduce dependencies on newer Bash features.

## Script versioning — mandatory

`readonly SCRIPT_VERSION="X.Y.Z"` in `obsidian-vault-backup.sh` is the single
source of truth for the script version. Keep this declaration in exactly that
format because the installed-copy updater reads it without executing the file.

Follow Semantic Versioning:

- increment `PATCH` for backward-compatible fixes;
- increment `MINOR` for backward-compatible features or meaningful workflow
  changes;
- increment `MAJOR` for breaking CLI, configuration, storage, or recovery
  changes.

Every completed iteration that changes `obsidian-vault-backup.sh` must have a
version different from the previously published or installed script. Increment
`PATCH` at least once for each such iteration; use a `MINOR` or `MAJOR` bump
instead when Semantic Versioning requires it. Do not bump repeatedly for
intermediate edits within the same unfinished iteration. Documentation-only and
test-only changes do not require a bump.

The installed-copy behavior is a project invariant:

- a newer manually launched version replaces the installed script;
- an equal version is a no-op and must not rewrite the installed script;
- an older version must never overwrite a newer installed version;
- replacement must remain atomic through a temporary file followed by `mv`;
- scheduled runs must not perform self-update or require interactive input.

Never remove or weaken the equality or downgrade checks in
`install_script_copy()`. Any change to version parsing or update behavior must
include tests for missing, equal, newer, and older installed versions.

## Safety invariants

- Never commit credentials, repository passwords, MEGA passwords, generated
  settings, Kopia repository metadata, or launchd files from a user's machine.
- Keep persistent project state under `~/.config/obsidian-vault-backup`.
- Keep the Kopia repository password in macOS Keychain.
- Treat the selected vault as read-only. Restores must target a separate
  directory during validation.
- Do not create or reconnect a real remote repository in automated tests.
- Do not make scheduled execution interactive.
- Preserve the explicit disclaimer acceptance gate for first-time manual use.
- Keep `launchd` idempotent: a repeated run must not install duplicate jobs.
- Kopia owns encryption and retention; `launchd` owns scheduling.

## Required validation

For every change to `obsidian-vault-backup.sh`, run at minimum:

```bash
bash -n obsidian-vault-backup.sh
./obsidian-vault-backup.sh --help
./obsidian-vault-backup.sh --version
git diff --check
```

Use disposable directories and a temporary `HOME` for behavioral tests. When a
Kopia repository is needed, use a temporary filesystem repository with a test
password and disable Keychain persistence. Never use the configured MEGA remote
or the user's real vault for automated validation.

When changing CLI options, filesystem paths, retention, security behavior, or
the setup flow, update `README.md`, `docs/usage.md`, and
`docs/architecture-decisions.md` where applicable.
