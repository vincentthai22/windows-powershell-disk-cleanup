# windows-powershell-disk-cleanup

PowerShell scripts and a short playbook for finding what's taking up space on a Windows drive and reclaiming it safely.

## Setup on a new device

```powershell
git clone https://github.com/vincentthai22/windows-powershell-disk-cleanup.git
cd windows-powershell-disk-cleanup
New-Item -ItemType Directory -Force personal | Out-Null   # local-only notes, gitignored
```

If script execution is blocked, allow local scripts for your user once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Works with Windows PowerShell 5.1 and PowerShell 7. You don't need admin rights.

## Scripts

### `scripts/disk-tree.ps1`: where is the space going?

```powershell
.\scripts\disk-tree.ps1 -MaxDepth 4 -MinGB 2
Get-Content .\personal\disk-tree.txt
```

| Param | Default | Meaning |
|---|---|---|
| `-Root` | `C:\` | Drive or folder to scan |
| `-MaxDepth` | `3` | How deep the tree goes. The scan still totals everything below that depth |
| `-MinGB` | `1.0` | Folders smaller than this are grouped into "(N smaller folders)" |
| `-Out` | `personal\disk-tree.txt` | Output file |

How it works:
- **Single pass in compiled C#.** `Get-ChildItem -Recurse | Measure-Object` is far too slow for hundreds of GB.
- **Skips junctions and symlinks** so nothing is counted twice.
- **Skips OneDrive online-only files.** They report a size but use no local disk.
- **Compares the scanned total with the drive's reported usage.** A gap of roughly 10–30 GB is normal: it's protected system data a non-admin user can't read, plus hardlinks.

### `scripts/steam-usage.ps1`: which games haven't you played?

```powershell
.\scripts\steam-usage.ps1
.\scripts\steam-usage.ps1 -SteamApps 'D:\SteamLibrary\steamapps'   # other library folders
```

This lists installed Steam games sorted by last played, with their actual size on disk.
- Recency comes from `LastPlayed` in each `appmanifest_*.acf`. File timestamps don't work for this, because NTFS last-access tracking is unreliable and Steam doesn't touch game folders when you play.
- Size is measured on disk. The manifest's `SizeOnDisk` value leaves out later updates and DLC.
- **"never" is often wrong** for games that launch through another launcher or an anti-cheat bootstrapper (Ubisoft Connect, EA app, EAC). Check that launcher's history before uninstalling.

## Cleanup playbook

1. **Baseline:** `Get-PSDrive C` for used and free space, then `disk-tree.ps1` to see where it's going.
2. **Drill into the biggest branch.** For games, run `steam-usage.ps1`. For anything else, rerun `disk-tree.ps1 -Root <folder>`.
3. **Decide, then remove things the supported way:**

| Target | How to remove safely |
|---|---|
| Steam / Battle.net / Ubisoft / EA games | Uninstall from the launcher. Don't delete folders, or the launcher's manifests go stale |
| Desktop apps (duplicate Photoshop versions, etc.) | Settings → Apps → Installed apps |
| Game recordings in `Videos\` | Review, then move to external or cloud storage |
| Recycle Bin, temp files, old Windows Update files | Disk Cleanup (`cleanmgr`) → "Clean up system files" |
| `C:\Windows\WinSxS` | **Never delete by hand.** Run `DISM /Online /Cleanup-Image /StartComponentCleanup` (admin) |
| `AppData\Local` | Run `disk-tree.ps1 -Root $env:LOCALAPPDATA` to find the app, then clear its cache from inside the app if it has the option |
| Dev caches (`.gradle`, `node_modules`, Android SDK) | Safe to delete. They re-download on the next build |

4. **Re-measure** with `Get-PSDrive C` and write down what was freed.

## Personal notes

`personal/` is gitignored. Keep anything specific to one machine there, such as scan output, a cleanup log, and reminder checklists. It never leaves that machine.
