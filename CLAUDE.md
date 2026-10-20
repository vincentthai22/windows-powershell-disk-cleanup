# Disk Cleanup Workspace

Public repo of PowerShell disk-usage scripts plus a cleanup playbook. See `README.md` for usage.

## Layout

- `scripts/`: reusable scans. Run them from here rather than recreating them in a scratchpad.
- `personal/` (**gitignored, this machine only**): `storage-log.md` (dated scans, findings, deletions; add a new entry each session) and `reminders/` (checkbox to-dos). Read these first when the user asks about past cleanup work.

## Rules

- **The repo is public.** Machine-specific details belong in `personal/`, never in tracked files. That covers usernames, installed games and apps, sizes, and scan output. Before committing, check that `git status` shows nothing from `personal/`.
- **Never delete anything without explicit confirmation.** Report candidates and let the user decide. Remove games and apps through their launcher or uninstaller, not by deleting folders.
- **Use Steam's `LastPlayed` from `appmanifest_*.acf` for recency, not file timestamps.** Treat "never played" as suspect for games that launch through a third-party launcher or anti-cheat.
- **Never hand-delete `C:\Windows\WinSxS`.** Use DISM or Disk Cleanup.
- Scans run as non-admin, so an "unaccounted" gap against the drive's reported usage is expected.
