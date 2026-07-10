#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/create-test-fixture.sh create
  scripts/create-test-fixture.sh mutate <fixture-directory>

Creates a disposable Obsidian-like directory, or alters it to produce a second
version for the snapshot-history test. Both operations are safe for a live vault
because they reject paths that do not match the generated fixture name.
EOF
}

ensure_fixture() {
  [[ "$(basename "$1")" == obsidian-vault-backup-fixture-* ]] || {
    printf 'Refusing a non-fixture path: %s\n' "$1" >&2
    exit 1
  }
}

case "${1:-}" in
  create)
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/obsidian-vault-backup-fixture-XXXXXX")"
    mkdir -p "$fixture/.obsidian" "$fixture/Projects" "$fixture/Attachments"
    printf '# Test vault\n\nInitial note.\n' > "$fixture/Home.md"
    printf '# Project alpha\n\nOriginal text.\n' > "$fixture/Projects/Alpha.md"
    printf '{"theme":"moonstone"}\n' > "$fixture/.obsidian/appearance.json"
    printf 'fixture attachment\n' > "$fixture/Attachments/example.txt"
    printf '%s\n' "$fixture"
    ;;
  mutate)
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    fixture="$2"
    ensure_fixture "$fixture"
    [[ -d "$fixture" ]] || { printf 'Fixture does not exist: %s\n' "$fixture" >&2; exit 1; }
    printf '# Project alpha\n\nUpdated text.\n' > "$fixture/Projects/Alpha.md"
    mv "$fixture/Home.md" "$fixture/Start.md"
    rm "$fixture/Attachments/example.txt"
    printf '# New note\n\nCreated in revision two.\n' > "$fixture/Projects/Beta.md"
    printf '{"theme":"obsidian"}\n' > "$fixture/.obsidian/appearance.json"
    printf 'Fixture updated: %s\n' "$fixture"
    ;;
  -h|--help|'') usage ;;
  *) printf 'Unknown command: %s\n' "$1" >&2; usage >&2; exit 1 ;;
esac
