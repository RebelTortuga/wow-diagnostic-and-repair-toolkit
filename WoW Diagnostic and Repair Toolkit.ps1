param([string]$Action = '')

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    try {
        $args = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
        Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs
        exit
    } catch {
        Write-Host ""
        Write-Host "Administrator elevation was cancelled or failed." -ForegroundColor Red
        Read-Host "Press Enter to close"
        exit 1
    }
}

$Desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($Desktop)) { $Desktop = Join-Path $env:USERPROFILE 'Desktop' }

$LogDir = Join-Path $env:LOCALAPPDATA 'RebelTortuga\WoW-Toolkit\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$Stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$Log = Join-Path $LogDir "Blizzard_Repair_$Stamp.txt"

function Log([string]$Text) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Text"
    Add-Content -LiteralPath $Log -Value $line
}

Log "Toolkit started."
Log "Toolkit session initialized (machine/user identifiers intentionally omitted)."

# Installation preference is local to the Windows account running this toolkit.
$script:SettingsDir = Join-Path $env:LOCALAPPDATA 'RebelTortuga\WoW-Toolkit'
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'
$script:WowRoot = $null
$script:WowVersion = $null
$script:WowExe = $null

function Save-WowPreference {
    if (-not $script:WowRoot -or -not $script:WowVersion -or -not $script:WowExe) { return }
    New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
    $settings = [ordered]@{
        SchemaVersion = 1
        WowRoot = $script:WowRoot
        WowVersion = $script:WowVersion
        WowExeName = [IO.Path]::GetFileName($script:WowExe)
    }
    $tempFile = Join-Path $script:SettingsDir ('settings.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $settings | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $tempFile -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tempFile -Destination $script:SettingsFile -Force -ErrorAction Stop
        Log 'Saved last selected WoW installation to local settings.'
    } finally {
        if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

function Load-WowPreference {
    if (-not (Test-Path -LiteralPath $script:SettingsFile -PathType Leaf)) { return $false }
    try {
        $settings = Get-Content -LiteralPath $script:SettingsFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($settings.SchemaVersion -ne 1) { throw 'Unsupported settings version' }
        $root = [string]$settings.WowRoot
        $version = [string]$settings.WowVersion
        $exeName = [string]$settings.WowExeName
        if ([string]::IsNullOrWhiteSpace($root) -or $version -notmatch '^_[A-Za-z0-9_]+_$' -or $exeName -notin @('Wow.exe','WowClassic.exe','WowClassicT.exe','WowB.exe','WowT.exe','Wow-64.exe')) { throw 'Invalid saved installation settings' }
        $root = [IO.Path]::GetFullPath($root).TrimEnd('\')
        $versionFolder = Join-Path $root $version
        $exe = Join-Path $versionFolder $exeName
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Saved game executable no longer exists' }
        $script:WowRoot = $root
        $script:WowVersion = $version
        $script:WowExe = $exe
        Log 'Loaded previously selected WoW installation.'
        return $true
    } catch {
        Log "Saved installation could not be used: $($_.Exception.Message)"
        return $false
    }
}


function Validate-WowInstall {
    if ($script:WowExe -and (Test-Path -LiteralPath $script:WowExe -PathType Leaf)) {
        Log "Validated WoW executable: $script:WowExe"
        return $true
    }

    Log "WoW executable NOT found at authoritative path: $script:WowExe"
    return $false
}


function Assert-WowClosed {
    $running = @(Get-Process -Name Wow,WowClassic,WowClassicT,WowB,WowT,Wow-64 -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) { throw 'Close all World of Warcraft clients before changing files. No game process was terminated.' }
}
function Assert-WowInstall {
    Assert-WowClosed
    if (!(Validate-WowInstall)) { throw 'WoW executable not found. Correct the install path before making changes.' }
    $root = [IO.Path]::GetFullPath($script:WowRoot).TrimEnd('\')
    $vp = [IO.Path]::GetFullPath((Get-VersionPath))
    if (!$vp.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Version path must be inside the WoW install root.' }
}

function Get-VersionPath {
    if (!$script:WowRoot -or !$script:WowVersion) { return $null }
    return Join-Path $script:WowRoot $script:WowVersion
}

function Pause-Toolkit {
    Write-Host ""
    [void](Read-Host "Press Enter to return to the menu")
}

function Show-Path {
    $vp = Get-VersionPath
    $exists = $script:WowExe -and (Test-Path -LiteralPath $script:WowExe -PathType Leaf)

    Write-Host ""
    Write-Host "WoW root:        " -NoNewline
    Write-Host $script:WowRoot -ForegroundColor Cyan
    Write-Host "WoW version:     " -NoNewline
    Write-Host $script:WowVersion -ForegroundColor Cyan
    Write-Host "Resolved folder: " -NoNewline
    Write-Host $vp -ForegroundColor Cyan
    Write-Host "Game executable: " -NoNewline
    if ($exists) {
        Write-Host $script:WowExe -ForegroundColor Green
    } else {
        Write-Host "$($script:WowExe)  [NOT FOUND]" -ForegroundColor Red
    }
    Write-Host "Log:             $Log"
}

function Browse-WowFolder([string]$Description, [string]$InitialPath) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $false
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath -PathType Container)) { $dialog.SelectedPath = $InitialPath }
    try {
        if ($dialog.ShowDialog() -eq 'OK') { return $dialog.SelectedPath }
        return $null
    } finally { $dialog.Dispose() }
}

function Set-WowPath {
    Write-Host ''
    Write-Host 'CHOOSE YOUR WORLD OF WARCRAFT INSTALLATION' -ForegroundColor Cyan
    Write-Host 'Press Enter or type B to browse, or enter a path yourself.'
    Write-Host 'Root folder: the World of Warcraft folder containing Data and version folders.'
    Write-Host 'Version folder: _retail_, _classic_, or another installed version.'
    Write-Host ''
    while ($true) {
        $p = Read-Host 'WoW ROOT: Enter/B = Browse, C = keep current, Q = cancel, or type a path'
        if ($p -eq 'Q') { return $false }
        if ($p -eq 'C') {
            if ($script:WowRoot) { $p = $script:WowRoot } else { Write-Host 'No current installation selected.' -ForegroundColor Yellow; continue }
        } elseif ([string]::IsNullOrWhiteSpace($p) -or $p -eq 'B') {
            $initial = $script:WowRoot
            if (!$initial) { $initial = [Environment]::GetFolderPath('MyComputer') }
            $p = Browse-WowFolder 'Choose World of Warcraft ROOT, or an installed version folder such as _retail_' $initial
            if (!$p) { return $false }
        }
        $p = [Environment]::ExpandEnvironmentVariables($p.Trim().Trim('"'))
        if (!(Test-Path -LiteralPath $p -PathType Container)) { Write-Host 'That folder does not exist.' -ForegroundColor Red; continue }
        $p = [IO.Path]::GetFullPath($p).TrimEnd('\')
        $pickedVersion = $null
        if ((Split-Path $p -Leaf) -match '^_[A-Za-z0-9_]+_$') {
            $pickedVersion = Split-Path $p -Leaf
            $p = Split-Path $p -Parent
        }
        Write-Host ''
        Write-Host 'Installed version folders:' -ForegroundColor Cyan
        Get-ChildItem -LiteralPath $p -Directory | Where-Object { $_.Name -match '^_[A-Za-z0-9_]+_$' } | ForEach-Object { Write-Host ('  ' + $_.Name) }
        if ($pickedVersion) { $v = $pickedVersion } else {
            $v = Read-Host 'VERSION: B = Browse, Q = cancel, Enter = _retail_, or type folder name/path'
            if ($v -eq 'Q') { return $false }
            if ($v -eq 'B') {
                $versionPath = Browse-WowFolder 'Choose the WoW version folder directly inside the selected root' $p
                if (!$versionPath) { return $false }
                if (![IO.Path]::GetFullPath((Split-Path $versionPath -Parent)).TrimEnd('\').Equals($p,[StringComparison]::OrdinalIgnoreCase)) { Write-Host 'Choose a version folder directly inside the selected WoW root.' -ForegroundColor Red; continue }
                $v = Split-Path $versionPath -Leaf
            } elseif ([string]::IsNullOrWhiteSpace($v)) { $v = '_retail_' }
            else {
                $v = [Environment]::ExpandEnvironmentVariables($v.Trim().Trim('"'))
                if ([IO.Path]::IsPathRooted($v)) {
                    if (![IO.Path]::GetFullPath((Split-Path $v -Parent)).TrimEnd('\').Equals($p,[StringComparison]::OrdinalIgnoreCase)) { Write-Host 'Version path must be directly inside the selected WoW root.' -ForegroundColor Red; continue }
                    $v = Split-Path $v -Leaf
                }
            }
        }
        $v = $v.Trim()
        if ($v -notmatch '^_[A-Za-z0-9_]+_$') { Write-Host 'Enter a version folder name, such as _retail_.' -ForegroundColor Red; continue }
        $resolved = Join-Path $p $v
        $executables = @(foreach ($exeName in @('Wow.exe','WowClassic.exe','WowClassicT.exe','WowB.exe','WowT.exe','Wow-64.exe')) {
            $candidate = Join-Path $resolved $exeName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate }
        })
        if ($executables.Count -eq 0) { Write-Host 'No recognized WoW executable found in that version folder.' -ForegroundColor Red; continue }
        $exe = $executables[0]
        if ($executables.Count -gt 1) {
            for ($i=0; $i -lt $executables.Count; $i++) { Write-Host ('  {0}. {1}' -f ($i+1), $executables[$i]) }
            $number = 0
            if (![int]::TryParse((Read-Host 'Choose executable number'), [ref]$number) -or $number -lt 1 -or $number -gt $executables.Count) { Write-Host 'Invalid selection.' -ForegroundColor Red; continue }
            $exe = $executables[$number-1]
        }
        Write-Host ''
        Write-Host "WoW root:        $p" -ForegroundColor Cyan
        Write-Host "WoW version:     $v" -ForegroundColor Cyan
        Write-Host "Resolved folder: $resolved" -ForegroundColor Cyan
        Write-Host "Game executable: $exe" -ForegroundColor Green
        if ((Read-Host 'Use this installation? [Y/N]') -notmatch '^[Yy]$') { continue }
        $script:WowRoot = $p
        $script:WowVersion = $v
        $script:WowExe = $exe
        Log "User selected WoW installation: $exe"
        try { Save-WowPreference } catch { Write-Host "Warning: Could not remember this path for next time: $($_.Exception.Message)" -ForegroundColor Yellow; Log "Could not save installation preference: $($_.Exception.Message)" }
        return $true
    }
}

function Stop-BattleNetProcesses {
    Assert-WowClosed
    $roots = @(
        (Join-Path $env:ProgramData 'Battle.net'),
        (Join-Path $env:ProgramData 'Blizzard Entertainment'),
        (Join-Path $env:LOCALAPPDATA 'Battle.net')
    )
    foreach ($base in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
        if ($base) { $roots += Join-Path $base 'Battle.net'; $roots += Join-Path $base 'Blizzard Entertainment' }
    }
    foreach ($process in @(Get-Process -Name 'Battle.net','Agent','BlizzardError','BlizzardBrowser' -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $process.Path } catch { }
        if (!$path) { throw "Cannot verify executable path for $($process.ProcessName) PID $($process.Id). Close Battle.net manually and retry." }
        $verified = $false
        foreach ($root in $roots) {
            if ($path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { $verified = $true; break }
        }
        if (!$verified) {
            if ($process.ProcessName -eq 'Agent') { Log "Skipped unrelated/unverified Agent PID $($process.Id): $path"; continue }
            throw "Unrecognized Blizzard process location: $path. Close it manually and retry."
        }
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        $process.WaitForExit(5000) | Out-Null
        if (!$process.HasExited) { throw "Process did not exit: $path" }
        Log "Stopped verified Blizzard process: $path PID $($process.Id)"
    }
}

function Remove-FolderSafe([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Log "$Label not found: $Path"
        Write-Host "  [skip] $Label" -ForegroundColor Gray
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Log "Deleted ${Label}: $Path"
        Write-Host "  [deleted] $Label" -ForegroundColor Green
    } catch {
        Log "FAILED deleting $Label at ${Path}: $($_.Exception.Message)"
        Write-Host "  [warning] ${Label}: $($_.Exception.Message)" -ForegroundColor Yellow
        throw
    }
}

function Remove-ChildrenSafe([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Log "$Label not found: $Path"
        Write-Host "  [skip] $Label" -ForegroundColor Gray
        return
    }

    $before = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count
    $failed = 0

    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            $failed++
            Log "FAILED deleting $($_.FullName): $($_.Exception.Message)"
        }
    }

    $after = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count
    Log "Cleared ${Label}: before=$before after=$after failed=$failed path=$Path"
    if ($failed -gt 0 -or $after -gt 0) { throw "Cleanup incomplete: $Label; remaining=$after failures=$failed" }
    Write-Host "  [done] $Label - before $before, remaining $after, failures $failed" -ForegroundColor Green
}

function Clear-BattleNetCaches {
    Write-Host "CAUTION: This deletes launcher support-data folders, not just temporary caches." -ForegroundColor Yellow
    Assert-WowClosed
    Write-Host ""
    Write-Host "Battle.net support-data cleanup" -ForegroundColor Cyan
    Write-Host "Deletes Battle.net / Blizzard / Blizzard Entertainment folders from:"
    Write-Host "  %PROGRAMDATA%, %APPDATA%, %LOCALAPPDATA%, %TEMP%"
    Write-Host "Installed game clients are not deleted." -ForegroundColor Yellow
    $ok = Read-Host "Type DELETE to confirm launcher support-data removal"
    if ($ok -cne 'DELETE') { return }

    Stop-BattleNetProcesses

    $roots = @($env:ProgramData,$env:APPDATA,$env:LOCALAPPDATA,$env:TEMP) | Select-Object -Unique
    $folderNames = @('Battle.net','Blizzard Entertainment','Blizzard','Bnet')

    foreach ($root in $roots) {
        foreach ($name in $folderNames) {
            Remove-FolderSafe (Join-Path $root $name) "$name under $root"
        }
    }

    Log "Battle.net support-data cleanup completed."
}


function Choose-BackupDestination {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose a backup location OUTSIDE the WoW installation (another drive recommended)'
    $dialog.ShowNewFolderButton = $true
    $dialog.SelectedPath = [Environment]::GetFolderPath('MyDocuments')
    try {
        if ($dialog.ShowDialog() -ne 'OK') { return $null }
        $destination = [IO.Path]::GetFullPath($dialog.SelectedPath).TrimEnd('\')
    } finally { $dialog.Dispose() }
    $root = [IO.Path]::GetFullPath($script:WowRoot).TrimEnd('\')
    if ($destination.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or $destination.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'The backup destination must be outside the WoW installation.' }
    return $destination
}
function Resolve-BackupSource([string]$Path, [string[]]$Chain = @()) {
    $current = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    while ($true) {
        if ($Chain -contains $current) { throw "Linked-folder loop detected: $Path. Backup stopped; originals unchanged." }
        $Chain += $current
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { return $current }
        if ($item.LinkType -notin @('Junction','SymbolicLink') -or !$item.Target) { throw "Unsupported reparse point: $current. Backup stopped rather than skipping data." }
        $target = @($item.Target)[0]
        if ($target.StartsWith('\??\')) { $target = $target.Substring(4) }
        if (![IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path $current -Parent) $target }
        $current = [IO.Path]::GetFullPath($target).TrimEnd('\')
    }
}
function Copy-VerifiedTree([string]$Source, [string]$Destination, [string]$CopyLog, [string[]]$Ancestors = @()) {
    Assert-WowClosed
    $resolved = Resolve-BackupSource $Source
    $destFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if ($destFull.Equals($resolved,[StringComparison]::OrdinalIgnoreCase) -or $destFull.StartsWith($resolved+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Copy destination is inside the source or a linked target. Choose another backup location.' }
    if ($Ancestors -contains $resolved) { throw "Directory-link cycle: $Source. Backup stopped." }
    $ancestorsHere = @($Ancestors) + $resolved
    New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
    foreach ($entry in @(Get-ChildItem -LiteralPath $resolved -Force -ErrorAction Stop)) {
        $target = Join-Path $Destination $entry.Name
        if ($entry.PSIsContainer) {
            Copy-VerifiedTree $entry.FullName $target $CopyLog $ancestorsHere
        } else {
            $file = Resolve-BackupSource $entry.FullName
            $before = (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash
            Copy-Item -LiteralPath $file -Destination $target -Force -ErrorAction Stop
            $after = (Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash
            $sourceAfter = (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($before -ne $after -or $before -ne $sourceAfter) { throw "Copy verification failed or source changed: $file" }
            Add-Content -LiteralPath $CopyLog -Value "Verified: $($entry.FullName) -> $target | SHA256 $after" -Encoding UTF8
        }
    }
}
function Create-WowSnapshot([string]$Destination, [string[]]$Folders, [string]$Prefix = 'WoW Backed up ') {
    Assert-WowInstall
    $vp = Get-VersionPath
    $backupDir = Join-Path $Destination ($Prefix + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'))
    New-Item -ItemType Directory -Path $backupDir -ErrorAction Stop | Out-Null
    $copied = @(); $missing = @()
    foreach ($name in $Folders) {
        if ($name -notin @('Interface','WTF','Cache','Screenshots')) { throw 'Invalid backup folder name.' }
        $source = Join-Path $vp $name
        if (!(Test-Path -LiteralPath $source -PathType Container)) { $missing += $name; continue }
        Copy-VerifiedTree $source (Join-Path $backupDir $name) (Join-Path $backupDir 'Backup Copy Log.txt')
        $copied += $name
        Write-Host "Saved and verified: $name" -ForegroundColor Green
    }
    Assert-WowClosed
    if ($copied.Count -eq 0) { throw 'No requested folders were found. No completed backup was created.' }
    @{Format='WoWToolkitBackup2';Created=(Get-Date).ToString('o');VersionPath=$vp;Executable=$script:WowExe;Folders=$copied;MissingFolders=$missing;Mode='Backup only'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupDir 'Backup Complete.json') -Encoding UTF8
    if ($missing.Count) { Write-Host "Not present: $($missing -join ', ')" -ForegroundColor Yellow }
    Log "Verified snapshot: $backupDir"
    return $backupDir
}

function Backup-Interface {
    $destination = Choose-BackupDestination
    if (!$destination) { throw 'Backup cancelled; repair was not started.' }
    $saved = Create-WowSnapshot $destination @('Interface','WTF')
    Write-Host "Pre-reset backup saved: $saved" -ForegroundColor Green
    return $true
}
function Save-WowBackup {
    Assert-WowInstall
    $destination = Choose-BackupDestination
    if (!$destination) { Write-Host 'Backup cancelled.'; return }
    $saved = Create-WowSnapshot $destination @('Interface','WTF','Cache','Screenshots')
    Write-Host "Backup saved: $saved" -ForegroundColor Green
}
function Restore-WowBackup {
    Assert-WowInstall
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the completed WoW backup folder containing Backup Complete.json'
    try { if ($dialog.ShowDialog() -ne 'OK') { return }; $backup = $dialog.SelectedPath } finally { $dialog.Dispose() }
    $meta = Get-Content -LiteralPath (Join-Path $backup 'Backup Complete.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $folders = @($meta.Folders)
    if (!$folders.Count -or @($folders | Where-Object { $_ -notin @('Interface','WTF','Cache','Screenshots') }).Count) { throw 'Invalid backup folder list.' }
    if (@($folders | Select-Object -Unique).Count -ne $folders.Count) { throw 'Duplicate folder names in backup.' }
    $vp = Get-VersionPath
    $backupFull = [IO.Path]::GetFullPath($backup).TrimEnd('\')
    if ($backupFull.Equals([IO.Path]::GetFullPath($vp).TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Select a backup folder, not the live game folder.' }
    foreach ($name in $folders) {
        $saved = Join-Path $backup $name
        if (!(Test-Path -LiteralPath $saved -PathType Container)) { throw "Backup folder missing: $name" }
        $live = Join-Path $vp $name
        if (Test-Path -LiteralPath $live) {
            if (((Get-Item -LiteralPath $live -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Live top-level $name is a link. Restore manually to preserve its layout." }
        }
    }
    Write-Host "Source backup: $backup" -ForegroundColor Cyan
    Write-Host "Restore into:  $vp" -ForegroundColor Cyan
    Write-Host "Folders:       $($folders -join ', ')" -ForegroundColor Yellow
    if ($meta.VersionPath -ne $vp) { Write-Host 'This backup came from a different path/version. Confirm it matches the intended game edition.' -ForegroundColor Yellow }
    Write-Host 'Restored folders replace their current contents. Current folders are backed up first.' -ForegroundColor Yellow
    if ((Read-Host 'Type RESTORE to proceed') -cne 'RESTORE') { return }
    $recoveryDestination = Choose-BackupDestination
    if (!$recoveryDestination) { Write-Host 'Restore cancelled.'; return }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $stage = Join-Path $vp ('_Toolkit_Restore_Staging_'+$stamp)
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($name in $folders) { Copy-VerifiedTree (Join-Path $backup $name) (Join-Path $stage $name) (Join-Path $stage 'Restore Copy Log.txt') }
    $present = @($folders | Where-Object { Test-Path -LiteralPath (Join-Path $vp $_) -PathType Container })
    $recovery = $null
    if ($present.Count) { $recovery = Create-WowSnapshot $recoveryDestination $present 'WoW Before restore ' }
    Assert-WowClosed
    $changed = @()
    try {
        foreach ($name in $folders) {
            Assert-WowClosed
            $original = Join-Path $vp $name
            $old = Join-Path $vp ($name+'_BEFORE_RESTORE_'+$stamp)
            $record = [pscustomobject]@{Original=$original;Old=$old;HadOriginal=$false;Installed=$false}
            $changed += $record
            if (Test-Path -LiteralPath $original) { Move-Item -LiteralPath $original -Destination $old -ErrorAction Stop; $record.HadOriginal=$true }
            Move-Item -LiteralPath (Join-Path $stage $name) -Destination $original -ErrorAction Stop
            $record.Installed=$true
        }
    } catch {
        $failure = $_
        for ($i=$changed.Count-1;$i -ge 0;$i--) {
            $record=$changed[$i]
            try {
                if ($record.Installed) { Move-Item -LiteralPath $record.Original -Destination (Join-Path $stage (Split-Path $record.Original -Leaf)) -ErrorAction Stop }
                if ($record.HadOriginal) { Move-Item -LiteralPath $record.Old -Destination $record.Original -ErrorAction Stop }
            } catch { Log "RESTORE ROLLBACK FAILED: $($record.Original): $($_.Exception.Message)" }
        }
        throw $failure
    }
    Log "Restore completed from $backup; current-data backup: $recovery"
    Write-Host 'Restore completed. Renamed originals remain in the game folder.' -ForegroundColor Green
    if ($recovery) { Write-Host "External recovery backup: $recovery" -ForegroundColor Green }
    Write-Host "Staging/log folder retained: $stage"
}

function Reset-WowUI {
    Assert-WowInstall
    Write-Host 'Copies and verifies Interface and WTF, then renames Cache, Interface and WTF.' -ForegroundColor Yellow
    if ((Read-Host 'Continue? [Y/N]') -notmatch '^[Yy]$') { return }
    [void](Backup-Interface)
    Reset-WowFolders
}
function Reset-WowFolders {
    Assert-WowInstall
    $vp = Get-VersionPath
    $suffix = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $moved = @()
    try {
        foreach ($name in @('Cache','Interface','WTF')) {
            Assert-WowClosed
            $original = Join-Path $vp $name
            if (!(Test-Path -LiteralPath $original)) { continue }
            $renamed = Join-Path $vp ($name+'_OLD_'+$suffix)
            Move-Item -LiteralPath $original -Destination $renamed -ErrorAction Stop
            $moved += [pscustomobject]@{Original=$original;Renamed=$renamed}
            Log "Renamed $original -> $renamed"
        }
    } catch {
        $failure = $_
        for ($i=$moved.Count-1;$i -ge 0;$i--) {
            try {
                if (Test-Path -LiteralPath $moved[$i].Original) { throw 'Original path reappeared; cannot roll back automatically.' }
                Move-Item -LiteralPath $moved[$i].Renamed -Destination $moved[$i].Original -ErrorAction Stop
            } catch { Log "ROLLBACK FAILED: $($moved[$i].Renamed): $($_.Exception.Message)" }
        }
        throw $failure
    }
    Write-Host 'UI folders reset. Verified backup and renamed originals retained.' -ForegroundColor Green
}

function Clear-WDB {
    Assert-WowInstall
    $vp = Get-VersionPath
    if (-not $vp) {
        Write-Host "Set the WoW path first." -ForegroundColor Red
        return
    }

    $wdb = Join-Path $vp 'Cache\WDB\enUS'
    Write-Host ""
    Write-Host "Clear WoW WDB enUS cache" -ForegroundColor Cyan
    Write-Host $wdb
    $ok = Read-Host "Continue? [Y/N]"
    if ($ok -notmatch '^[Yy]$') { return }

    Remove-ChildrenSafe $wdb 'WoW WDB enUS cache'
}

function Repair-Indices {
    Assert-WowInstall
    if (-not $script:WowRoot) {
        Write-Host "Set the WoW path first." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Repair WoW indices / IDX files" -ForegroundColor Cyan
    Write-Host "Removes Data\indices and *.idx files." -ForegroundColor Yellow
    Write-Host "It explicitly does NOT delete data.### files."
    $ok = Read-Host "Continue? [Y/N]"
    if ($ok -notmatch '^[Yy]$') { return }

    Stop-BattleNetProcesses

    $data = Join-Path $script:WowRoot 'Data'
    if (-not (Test-Path -LiteralPath $data)) {
        Write-Host "WoW Data folder not found: $data" -ForegroundColor Red
        Log "WoW Data folder not found: $data"
        return
    }

    $indices = Join-Path $data 'indices'
    Remove-FolderSafe $indices 'WoW Data\indices'

    $targets = @($data,(Join-Path $data 'data')) | Where-Object { Test-Path -LiteralPath $_ }
    $removed = 0
    $failed = 0

    foreach ($t in $targets) {
        Get-ChildItem -LiteralPath $t -Filter '*.idx' -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removed++
                Log "Deleted IDX: $($_.FullName)"
            } catch {
                $failed++
                Log "FAILED deleting IDX $($_.FullName): $($_.Exception.Message)"
            }
        }
    }

    if ($failed -gt 0) { throw "IDX repair incomplete: $failed deletion failures." }
    Write-Host "IDX files removed: $removed | failures: $failed" -ForegroundColor Green
    Log "Indices/IDX repair completed. removed=$removed failed=$failed"
}

function Copy-D3D11 {
    '-d3d11' | Set-Clipboard
    Log "Copied -d3d11 to clipboard."
    Write-Host ""
    Write-Host "-d3d11 copied to clipboard." -ForegroundColor Green
    Write-Host "Paste it into Battle.net -> WoW -> Game Settings -> Additional command line arguments."
    Write-Host "Use it as a troubleshooting test; remove it again if it does not help." -ForegroundColor Yellow
}

function Set-WowAdminFlag([bool]$Enable) {
    Assert-WowInstall
    $exe = $script:WowExe
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    New-Item -Path $key -Force | Out-Null
    $existing = [string](Get-Item -LiteralPath $key -ErrorAction Stop).GetValue($exe, '')
    $tokens = @($existing -split '\s+' | Where-Object { $_ -and $_ -ine 'RUNASADMIN' })
    if ($Enable) {
        if ($tokens -notcontains '~') { $tokens = @('~') + $tokens }
        $tokens += 'RUNASADMIN'
    }
    if (@($tokens | Where-Object { $_ -ne '~' }).Count -eq 0) {
        if ($existing) { Remove-ItemProperty -LiteralPath $key -Name $exe -ErrorAction Stop }
    } else {
        New-ItemProperty -LiteralPath $key -Name $exe -PropertyType String -Value ($tokens -join ' ') -Force -ErrorAction Stop | Out-Null
    }
    Log "RUNASADMIN=$Enable for $exe; other compatibility tokens preserved."
    Write-Host 'Administrator flag updated; other compatibility flags preserved.' -ForegroundColor Green
}

function Open-WowFolder {
    $vp = Get-VersionPath
    if ($vp -and (Test-Path -LiteralPath $vp)) {
        Start-Process explorer.exe -ArgumentList "`"$vp`""
        Log "Opened WoW folder: $vp"
    } else {
        Write-Host "WoW version folder not found." -ForegroundColor Red
    }
}

function Open-LogFolder {
    Start-Process explorer.exe -ArgumentList "`"$LogDir`""
}

function Full-Safe-Repair {
    Assert-WowInstall
    Write-Host 'Combined reset: verified Interface/WTF backup, Battle.net support-data cleanup, then WoW UI reset.' -ForegroundColor Yellow
    Write-Host 'Completed cleanup steps cannot be rolled back if a later step fails.' -ForegroundColor Yellow
    if ((Read-Host 'Continue? [Y/N]') -notmatch '^[Yy]$') { return }
    [void](Backup-Interface)
    Stop-BattleNetProcesses
    $roots = @($env:ProgramData,$env:APPDATA,$env:LOCALAPPDATA,$env:TEMP) | Where-Object { $_ } | Select-Object -Unique
    foreach ($root in $roots) {
        Assert-WowClosed
        foreach ($name in @('Battle.net','Blizzard Entertainment','Blizzard','Bnet')) {
            Remove-FolderSafe (Join-Path $root $name) "$name under $root"
        }
    }
    Reset-WowFolders
    Log 'Combined reset completed without reported errors.'
    Write-Host 'Combined reset completed. Open Battle.net to rebuild support data.' -ForegroundColor Green
}

# Load independent, read-only diagnostic routines.
$diagScript = Join-Path $PSScriptRoot 'RebelTortuga-WoW-Diagnostics.ps1'
if (Test-Path -LiteralPath $diagScript -PathType Leaf) {
    . $diagScript
} else {
    function Show-DiagnosticsCenter { Write-Host 'Diagnostics companion script missing. Re-extract the complete ZIP.' -ForegroundColor Red }
}

if (Load-WowPreference) {
    Write-Host 'Loaded your previously selected World of Warcraft installation:' -ForegroundColor Green
    Show-Path
    Write-Host 'Use menu option 4 whenever you want to change it.' -ForegroundColor Cyan
    Start-Sleep -Seconds 2
} elseif (-not (Set-WowPath)) {
    Log 'Startup selection cancelled.'
    exit
}

# Center the whole dashboard using the live console width, not a fixed left margin.
function Get-ToolkitConsoleWidth {
    # The host's visible window width is more reliable than the console buffer
    # when Windows Terminal or the classic console is maximized.
    try {
        $size = $Host.UI.RawUI.WindowSize
        if ([int]$size.Width -ge 20) { return [int]$size.Width }
    } catch { }
    try {
        $w = [int][Console]::WindowWidth
        if ($w -ge 20) { return $w }
    } catch { }
    return 80
}
function Get-ToolkitLeftMargin {
    param([int]$ContentWidth)
    $visible = Get-ToolkitConsoleWidth
    return [Math]::Max(0, [int][Math]::Floor(($visible - $ContentWidth) / 2))
}
function Write-MenuLine {
    param([AllowEmptyString()][string]$Text = '', [string]$ForegroundColor = 'Gray', [switch]$CenterText)
    $cw = Get-ToolkitConsoleWidth
    $width = [Math]::Min(91, [Math]::Max(1,$cw - 2))
    $margin = [Math]::Max(0,[int][Math]::Floor(($cw - $width)/2))
    if ([string]::IsNullOrEmpty($Text)) { Write-Host ''; return }
    $remaining = $Text
    while ($remaining.Length -gt 0) {
        if ($remaining.Length -le $width) { $part = $remaining; $remaining = '' }
        else {
            $cut = $remaining.LastIndexOf(' ',[Math]::Min($width,$remaining.Length-1))
            if ($cut -le 0) { $cut = $width }
            $part = $remaining.Substring(0,$cut).TrimEnd()
            $remaining = $remaining.Substring($cut).TrimStart()
        }
        $pad = $margin
        if ($CenterText) { $pad += [Math]::Max(0,[int][Math]::Floor(($width-$part.Length)/2)) }
        Write-Host ((' '*$pad)+$part) -ForegroundColor $ForegroundColor
    }
}
function Write-MenuPath {
    param([string]$Label,[string]$Value,[string]$Color='Gray')
    Write-MenuLine ($Label + ':') -ForegroundColor Cyan
    Write-MenuLine ('  ' + $Value) -ForegroundColor $Color
}
function Show-CenteredPath {
    Write-MenuLine 'CURRENT WoW INSTALLATION' -ForegroundColor Cyan
    Write-MenuLine ('Root:     ' + $script:WowRoot) -ForegroundColor Gray
    Write-MenuLine ('Version:  ' + $script:WowVersion) -ForegroundColor Gray
    Write-MenuLine ''
    Write-MenuPath 'Saved Log Path' $Log
}
function New-ToolkitBoxLines {
    param([string]$Title,[string]$Color,[string[]]$Items,[int]$InnerWidth=38)
    $lines = New-Object System.Collections.ArrayList
    $edge = '+' + ('-' * ($InnerWidth+2)) + '+'
    [void]$lines.Add(@{Text=$edge;Color='DarkGray'})
    [void]$lines.Add(@{Text=('| '+$Title.PadRight($InnerWidth)+' |');Color=$Color})
    foreach ($item in $Items) {
        $itemColor = if ($item -match '^1\.  ') {'Green'} elseif ($item -match '^15\.  ') {'Yellow'} else {'Gray'}
        [void]$lines.Add(@{Text=('| '+$item.PadRight($InnerWidth)+' |');Color=$itemColor})
    }
    [void]$lines.Add(@{Text=$edge;Color='DarkGray'})
    return ,$lines
}
function Write-ToolkitDashboard {
    $sections = @(
        @{Title='DIAGNOSTICS';Color='Green';Items=@('1.  Diagnostics Center')},
        @{Title='BACKUP & RESTORE';Color='Cyan';Items=@('2.  Save a backup','3.  Restore a backup')},
        @{Title='INSTALLATION & FOLDERS';Color='Magenta';Items=@('4.  Choose WoW installation','5.  Open WoW folder','6.  Saved Logs','7.  Clear Battle.net files')},
        @{Title='REPAIR & RESET';Color='DarkYellow';Items=@('8.  Reset AddOns and settings','9.  Clear WDB cache','10.  Rebuild game indexes','11.  Comprehensive repair')},
        @{Title='OTHER TOOLS';Color='Blue';Items=@('12.  Copy DirectX 11 argument','13.  Enable admin requirement','14.  Remove admin requirement')},
        @{Title='OPTIONAL SUPPORT';Color='Yellow';Items=@('15.  Optional taco tip')}
    )
    $cw = Get-ToolkitConsoleWidth
    $inner = 38; $boxWidth = $inner+4; $gap=3
    if ($cw -ge (2*$boxWidth+$gap+2)) {
        $total = 2*$boxWidth+$gap
        $margin = [Math]::Max(0,[int][Math]::Floor(($cw-$total)/2))
        $left = New-Object System.Collections.ArrayList
        $right = New-Object System.Collections.ArrayList
        foreach ($idx in @(0,1,2)) {
            foreach ($line in (New-ToolkitBoxLines $sections[$idx].Title $sections[$idx].Color $sections[$idx].Items $inner)) { [void]$left.Add($line) }
            [void]$left.Add(@{Text=(' '*$boxWidth);Color='Gray'})
        }
        foreach ($idx in @(3,4,5)) {
            foreach ($line in (New-ToolkitBoxLines $sections[$idx].Title $sections[$idx].Color $sections[$idx].Items $inner)) { [void]$right.Add($line) }
            [void]$right.Add(@{Text=(' '*$boxWidth);Color='Gray'})
        }
        for ($i=0; $i -lt [Math]::Max($left.Count,$right.Count);$i++) {
            $leftText  = if ($i -lt $left.Count)  { [string]$left[$i].Text }  else { ' ' * $boxWidth }
            $rightText = if ($i -lt $right.Count) { [string]$right[$i].Text } else { '' }
            # Keep the whole row anchored to the same calculated visible-window margin.
            $marginText = ' ' * (Get-ToolkitLeftMargin $total)
            Write-Host ($marginText + $leftText + (' ' * $gap)) -NoNewline -ForegroundColor $(if ($i -lt $left.Count) { $left[$i].Color } else { 'Gray' })
            if ($rightText) {
                Write-Host $rightText -ForegroundColor $right[$i].Color
            } else {
                Write-Host ''
            }
        }
    } else {
        foreach ($section in $sections) {
            foreach ($line in (New-ToolkitBoxLines $section.Title $section.Color $section.Items $inner)) {
                Write-MenuLine $line.Text -ForegroundColor $line.Color -CenterText
            }
            Write-MenuLine ''
        }
    }
}

# GUI action mode: retain the original, confirmed, interactive repair workflows.
if ($Action) {
    $actions = @{
        '1' = { Show-DiagnosticsCenter }
        '2' = { Save-WowBackup }
        '3' = { Restore-WowBackup }
        '4' = { [void](Set-WowPath) }
        '5' = { Open-WowFolder }
        '6' = { Open-LogFolder }
        '7' = { Clear-BattleNetCaches }
        '8' = { Reset-WowUI }
        '9' = { Clear-WDB }
        '10' = { Repair-Indices }
        '11' = { Full-Safe-Repair }
        '12' = { Copy-D3D11 }
        '13' = { Set-WowAdminFlag $true }
        '14' = { Set-WowAdminFlag $false }
        '15' = { Write-Host 'Optional support: all features are free. Ko-fi: https://ko-fi.com/rebeltortuga' }
    }
    if (-not $actions.ContainsKey($Action)) { throw "Unknown action: $Action" }
    try {
        Write-Host "WoW Diagnostic and Repair Toolkit - $Action" -ForegroundColor Cyan
        Write-Host 'Read each prompt carefully. Close WoW and Battle.net completely before repairs.' -ForegroundColor Yellow
        & $actions[$Action]
        Write-Host ''
        Write-Host 'Operation finished.' -ForegroundColor Green
    } catch {
        Log "OPERATION FAILED: $($_.Exception.Message)"
        Write-Host "Operation failed or was incomplete: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Toolkit
    exit
}

while ($true) {
    Clear-Host
    Write-MenuLine ('=' * 91) -ForegroundColor DarkCyan -CenterText
    Write-MenuLine 'WoW DIAGNOSTIC AND REPAIR TOOLKIT' -ForegroundColor Cyan -CenterText
    Write-MenuLine ('=' * 91) -ForegroundColor DarkCyan -CenterText
    Write-MenuLine 'Shared by RebelTortuga | Free to use' -ForegroundColor Gray -CenterText
    Write-MenuLine ''
    Write-MenuLine 'INDEPENDENT TOOL' -ForegroundColor Magenta
    Write-MenuLine 'Some procedures follow official Blizzard Support recommendations and blue posts.' -ForegroundColor Gray
    Write-MenuLine 'Independently developed; not an official Blizzard product. Provided as is.' -ForegroundColor Gray
    Write-MenuLine ''
    Write-MenuLine 'BEFORE REPAIRS' -ForegroundColor DarkYellow
    Write-MenuLine 'Back up settings. Close WoW and Battle.net. Read README and OPTIONS-README.md.' -ForegroundColor Yellow
    Write-MenuLine 'Diagnostics are read-only and never initiate repairs.' -ForegroundColor Green
    Write-MenuLine ''
    Show-CenteredPath
    Write-MenuLine ''
    Write-MenuLine ('-' * 91) -ForegroundColor DarkGray -CenterText
    Write-ToolkitDashboard
    Write-MenuLine '0.  Exit' -ForegroundColor DarkGray -CenterText
    Write-MenuLine ''
    Write-MenuLine 'H.  Open detailed options guide (OPTIONS-README.md)' -ForegroundColor Cyan -CenterText
    Write-MenuLine ''
    $choice = Read-Host ((' '*(Get-ToolkitLeftMargin ([Math]::Min(91,[Math]::Max(1,(Get-ToolkitConsoleWidth)-2)))))+'Select option (0-15 or H for help)')

    if ($choice -match '^[Hh]$') {
        $guide = Join-Path $PSScriptRoot 'OPTIONS-README.md'
        if (-not (Test-Path -LiteralPath $guide -PathType Leaf)) {
            Write-Host 'The options guide is missing. Keep OPTIONS-README.md beside the toolkit script.' -ForegroundColor Yellow
            Pause-Toolkit
            continue
        }
        try {
            Start-Process -FilePath $guide -ErrorAction Stop
        } catch {
            try {
                Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $guide + '"') -ErrorAction Stop
            } catch {
                Write-Host ("Could not open the options guide: " + $_.Exception.Message) -ForegroundColor Red
            }
        }
        continue
    }

    $optionDetails = @{
        '1' = 'Diagnostics Center: read-only quick check, full scan, and report export. No repairs are run automatically.'
        '2' = 'Save a backup: choose where to copy Interface/AddOns, WTF, Cache and Screenshots. Originals stay unchanged.'
        '3' = 'Restore a backup: choose a backup and recovery location. Current data is preserved before replacement.'
        '4' = 'Choose WoW installation: select and remember the game root, version folder and executable.'
        '5' = 'Open WoW folder: opens the selected game folder in File Explorer.'
        '6' = 'Saved Logs: opens the folder containing toolkit repair logs.'
        '7' = 'Clear Battle.net support files: closes verified launcher processes and removes selected launcher support data so it can rebuild.'
        '8' = 'Reset AddOns and settings: backs up Interface/WTF, then renames Interface, WTF and Cache for a fresh setup.'
        '9' = 'Clear WDB cache: removes only the English (enUS) WDB cache for the selected installation.'
        '10' = 'Rebuild game indexes: removes selected index and IDX files; Battle.net rebuilds them. Large game data files remain.'
        '11' = 'Comprehensive repair: combines launcher support-data cleanup and WoW AddOns/settings reset. Back up first.'
        '12' = 'Copy DirectX 11 argument: copies -d3d11 to the clipboard; game settings are not modified.'
        '13' = 'Enable administrator requirement: configures the selected game executable to request elevation.'
        '14' = 'Remove administrator requirement: removes that elevation requirement from the selected executable.'
        '15' = 'Optional support: no payment required. Ko-fi: https://ko-fi.com/rebeltortuga'
    }
    if ($optionDetails.ContainsKey($choice)) {
        Write-Host ''
        Write-Host $optionDetails[$choice] -ForegroundColor Cyan
        if ($choice -in @('3','7','8','9','10','11','13','14')) {
            $confirm = Read-Host 'Press Enter to continue to this option, or type C to cancel'
            if ($confirm -match '^[Cc]$') { continue }
        }
    }
    try {
    switch ($choice) {
        '4'  { [void](Set-WowPath); Pause-Toolkit }
        '7'  { Clear-BattleNetCaches; Pause-Toolkit }
        '8'  { Reset-WowUI; Pause-Toolkit }
        '9'  { Clear-WDB; Pause-Toolkit }
        '10'  { Repair-Indices; Pause-Toolkit }
        '12'  { Copy-D3D11; Pause-Toolkit }
        '13'  { Set-WowAdminFlag $true; Pause-Toolkit }
        '14'  { Set-WowAdminFlag $false; Pause-Toolkit }
        '5'  { Open-WowFolder; Pause-Toolkit }
        '6' { Open-LogFolder; Pause-Toolkit }
        '11' { Full-Safe-Repair; Pause-Toolkit }
        '2' { Save-WowBackup; Pause-Toolkit }
        '3' { Restore-WowBackup; Pause-Toolkit }
        '1' { Show-DiagnosticsCenter; Pause-Toolkit }
        '15' { Write-Host 'Ko-fi: https://ko-fi.com/rebeltortuga (optional; all toolkit features are free).' -ForegroundColor Cyan; Pause-Toolkit }
        '0'  { Log "Toolkit exited normally."; break }
        default { Write-Host "Invalid selection." -ForegroundColor Red; Start-Sleep 1 }
    }

    } catch {
        Log "OPERATION FAILED: $($_.Exception.Message)"
        Write-MenuLine "Operation failed or was incomplete: $($_.Exception.Message)" -ForegroundColor Red
        Pause-Toolkit
    }
    if ($choice -eq '0') { break }
}
