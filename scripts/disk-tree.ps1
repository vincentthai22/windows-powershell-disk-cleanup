# Single-pass disk usage scan: records the size of every directory down to $MaxDepth, then prints a text tree.
param(
    [string]$Root = 'C:\',
    [int]$MaxDepth = 3,
    [double]$MinGB = 1.0,
    # Defaults into the gitignored personal/ folder: the tree exposes this machine's user and folder names
    [string]$Out = "$PSScriptRoot\..\personal\disk-tree.txt"
)
New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent) | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;

public static class DiskScan {
    public static Dictionary<string, long> Sizes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    public static long DeniedDirs;
    static int maxDepth;

    // OFFLINE | RECALL_ON_OPEN | RECALL_ON_DATA_ACCESS: OneDrive online-only files report a size but use no disk
    const FileAttributes Cloud = (FileAttributes)(0x1000 | 0x40000 | 0x400000);

    public static long Run(string root, int depth) { maxDepth = depth; return Walk(new DirectoryInfo(root), 0); }

    static long Walk(DirectoryInfo dir, int depth) {
        long total = 0;
        try {
            foreach (FileSystemInfo e in dir.EnumerateFileSystemInfos()) {
                if ((e.Attributes & FileAttributes.ReparsePoint) != 0) continue;   // junctions/symlinks: would double-count
                if ((e.Attributes & FileAttributes.Directory) != 0) total += Walk((DirectoryInfo)e, depth + 1);
                else if ((e.Attributes & Cloud) == 0) total += ((FileInfo)e).Length;
            }
        } catch (UnauthorizedAccessException) { DeniedDirs++; }
          catch (IOException) { DeniedDirs++; }
        if (depth <= maxDepth) Sizes[dir.FullName.TrimEnd('\\') + (depth == 0 ? "\\" : "")] = total;
        return total;
    }
}
'@

function Format-Size([long]$b) {
    if ($b -ge 1GB) { '{0,7:N1} GB' -f ($b / 1GB) } else { '{0,7:N0} MB' -f ($b / 1MB) }
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$scanned = [DiskScan]::Run($Root, $MaxDepth)
$sizes = [DiskScan]::Sizes
$sw.Stop()

$children = @{}
foreach ($p in $sizes.Keys) {
    if ($p -eq $Root) { continue }
    # Only the drive root keeps its trailing backslash ("C:\"); every other key has none
    $parent = Split-Path $p -Parent
    if ($parent.TrimEnd('\') -eq $Root.TrimEnd('\')) { $parent = $Root }
    if (-not $children.ContainsKey($parent)) { $children[$parent] = New-Object System.Collections.ArrayList }
    [void]$children[$parent].Add($p)
}

$lines = New-Object System.Collections.ArrayList
function Add-Node([string]$path, [string]$prefix, [bool]$last, [int]$depth) {
    $kids = @()
    if ($children.ContainsKey($path)) { $kids = @($children[$path] | Sort-Object { -$sizes[$_] }) }
    $big = @($kids | Where-Object { $sizes[$_] -ge $MinGB * 1GB })
    $small = @($kids | Where-Object { $sizes[$_] -lt $MinGB * 1GB })
    $rows = @($big | ForEach-Object { @{ Path = $_; Size = $sizes[$_]; Label = (Split-Path $_ -Leaf) } })
    if ($small.Count -gt 0) {
        $smallSum = ($small | ForEach-Object { $sizes[$_] } | Measure-Object -Sum).Sum
        $rows += @{ Path = $null; Size = $smallSum; Label = "($($small.Count) smaller folders)" }
    }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $isLast = ($i -eq $rows.Count - 1)
        $branch = if ($isLast) { '\-- ' } else { '+-- ' }
        [void]$lines.Add(('{0}  {1}{2}{3}' -f (Format-Size $rows[$i].Size), $prefix, $branch, $rows[$i].Label))
        if ($rows[$i].Path) {
            $next = $prefix + $(if ($isLast) { '    ' } else { '|   ' })
            Add-Node $rows[$i].Path $next $isLast ($depth + 1)
        }
    }
}

$drive = Get-PSDrive ($Root.Substring(0, 1))
[void]$lines.Add(('{0}  {1}   (folders under {2} GB hidden, depth {3})' -f (Format-Size $sizes[$Root]), $Root, $MinGB, $MaxDepth))
Add-Node $Root '' $true 0
[void]$lines.Add('')
[void]$lines.Add(('Scanned as visible to this (non-admin) user : {0}' -f (Format-Size $scanned).Trim()))
[void]$lines.Add(('Drive reports used                        : {0}' -f (Format-Size $drive.Used).Trim()))
[void]$lines.Add(('Unaccounted (protected/system/hardlinks)   : {0}' -f (Format-Size ($drive.Used - $scanned)).Trim()))
[void]$lines.Add(('Directories denied: {0}   Scan time: {1:N0}s' -f [DiskScan]::DeniedDirs, $sw.Elapsed.TotalSeconds))
$lines | Set-Content -Path $Out -Encoding UTF8
"Wrote $Out"
