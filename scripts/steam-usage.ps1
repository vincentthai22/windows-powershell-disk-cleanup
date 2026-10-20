# Steam doesn't update NTFS last-access time on game folders, so filesystem metadata can't tell us
# "recently played". Each appmanifest_<id>.acf carries an authoritative LastPlayed unix timestamp instead.
param([string]$SteamApps = 'C:\Program Files (x86)\Steam\steamapps')

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
public static class DirSize {
    public static long Of(string path) {
        long total = 0;
        var stack = new Stack<string>();
        stack.Push(path);
        while (stack.Count > 0) {
            string dir = stack.Pop();
            try {
                foreach (var f in Directory.EnumerateFiles(dir)) total += new FileInfo(f).Length;
                foreach (var d in Directory.EnumerateDirectories(dir)) stack.Push(d);
            } catch (UnauthorizedAccessException) {} catch (IOException) {}
        }
        return total;
    }
}
'@

$epoch = [DateTime]'1970-01-01Z'
$rows = foreach ($acf in Get-ChildItem $SteamApps -Filter 'appmanifest_*.acf') {
    $text = Get-Content $acf.FullName -Raw
    $name = if ($text -match '"name"\s*"([^"]*)"') { $Matches[1] } else { '?' }
    $installDir = if ($text -match '"installdir"\s*"([^"]*)"') { $Matches[1] } else { $null }
    $lastPlayedEpoch = if ($text -match '"LastPlayed"\s*"(\d+)"') { [long]$Matches[1] } else { 0 }
    $sizeOnDiskBytes = if ($text -match '"SizeOnDisk"\s*"(\d+)"') { [long]$Matches[1] } else { 0 }
    if (-not $installDir) { continue }

    $folder = Join-Path $SteamApps "common\$installDir"
    # SizeOnDisk in the manifest is set at install time and doesn't include later updates/DLC/saves,
    # so measure the folder on disk directly instead of trusting that field.
    $actualBytes = if (Test-Path $folder) { [DirSize]::Of($folder) } else { $sizeOnDiskBytes }

    [PSCustomObject]@{
        Name       = $name
        LastPlayed = if ($lastPlayedEpoch -gt 0) { $epoch.AddSeconds($lastPlayedEpoch) } else { $null }
        SizeGB     = [math]::Round($actualBytes / 1GB, 1)
        Folder     = $folder
    }
}

$rows | Sort-Object @{Expression = { if ($_.LastPlayed) { $_.LastPlayed } else { [DateTime]::MinValue } }; Descending = $true } |
    Format-Table @{L='Last Played';E={ if ($_.LastPlayed) { $_.LastPlayed.ToString('yyyy-MM-dd') } else { 'never' } }},
                 @{L='Size(GB)';E={$_.SizeGB};Align='Right'},
                 Name -AutoSize

'{0} total, {1:N1} GB' -f $rows.Count, ($rows.SizeGB | Measure-Object -Sum).Sum
