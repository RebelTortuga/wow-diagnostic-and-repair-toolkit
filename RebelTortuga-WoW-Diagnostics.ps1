# RebelTortuga WoW Diagnostics Center
# Read-only: no changes to WoW/Battle.net data or Windows settings.
# The only writes are explicitly requested local diagnostic reports.

function New-DiagnosticResult([string]$Area, [string]$Status, [string]$Finding, [string]$Advice) {
    [pscustomobject]@{ Area=$Area; Status=$Status; Finding=$Finding; Advice=$Advice }
}
function Get-SafePathLabel([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '(not selected)' }
    return Split-Path -Leaf ($Path.TrimEnd('\','/'))
}
function Test-WowDiagnostics([bool]$Full) {
    $results = [System.Collections.Generic.List[object]]::new()
    $versionPath = Get-VersionPath
    if (-not $versionPath -or -not (Test-Path -LiteralPath $versionPath -PathType Container)) {
        $results.Add((New-DiagnosticResult 'Installation' 'FAIL' 'Selected game-version directory missing.' 'Use menu option 3 to choose a valid WoW installation.'))
        return @($results.ToArray())
    }
    $exeFound = $script:WowExe -and (Test-Path -LiteralPath $script:WowExe -PathType Leaf)
    $results.Add((New-DiagnosticResult 'Installation' $(if($exeFound){'PASS'}else{'FAIL'}) $(if($exeFound){'Selected game executable exists.'}else{'Selected game executable missing.'}) 'Use menu option 3 if the installation was moved.'))
    foreach ($dirName in @('Interface','WTF','Cache','Screenshots')) {
        $p = Join-Path $versionPath $dirName
        $exists = Test-Path -LiteralPath $p -PathType Container
        $status = if ($exists) {'PASS'} else {'INFO'}
        $advice = if($exists){'No action required.'}else{'May be normal for a new or reset installation; WoW can recreate this folder.'}
        $results.Add((New-DiagnosticResult "Folder: $dirName" $status $(if($exists){'Present.'}else{'Not present.'}) $advice))
    }
    try {
        $driveRoot=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($versionPath))
        $drive=New-Object System.IO.DriveInfo($driveRoot)
        $freeGb=[math]::Round($drive.AvailableFreeSpace/1GB,1)
        $status=if($freeGb -lt 10){'WARN'}else{'PASS'}
        $results.Add((New-DiagnosticResult 'Free disk space' $status "$freeGb GB free on the game volume." 'Low space can interfere with game updates; no automatic cleanup is performed.'))
    } catch { $results.Add((New-DiagnosticResult 'Free disk space' 'UNKNOWN' 'Could not read free space.' 'Check the drive in Windows Explorer.')) }
    $running=@(Get-Process -Name 'Wow','WowClassic','WowClassicT','WowB','WowT','Wow-64' -ErrorAction SilentlyContinue)
    $results.Add((New-DiagnosticResult 'WoW process' 'INFO' $(if($running.Count){'WoW appears to be running.'}else{'WoW is not running.'}) 'Close the game before running any file-changing repairs.'))
    $bn=@(Get-Process -Name 'Battle.net','Agent' -ErrorAction SilentlyContinue)
    $results.Add((New-DiagnosticResult 'Battle.net processes' 'INFO' $(if($bn.Count){'Launcher or Agent process detected.'}else{'No launcher or Agent process detected.'}) 'Process presence alone does not indicate a problem.'))
    $addons=Join-Path $versionPath 'Interface\AddOns'
    if(Test-Path -LiteralPath $addons -PathType Container) {
        try {
            $dirs=@(Get-ChildItem -LiteralPath $addons -Directory -ErrorAction Stop)
            $nested=0; $noToc=0; $tocCount=0
            foreach($d in $dirs) {
                $tocs=@(Get-ChildItem -LiteralPath $d.FullName -File -Filter '*.toc' -ErrorAction SilentlyContinue)
                if($tocs.Count -eq 0){$noToc++}else{$tocCount+=$tocs.Count}
                $sub=@(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)
                foreach($child in $sub){if(@(Get-ChildItem -LiteralPath $child.FullName -File -Filter '*.toc' -ErrorAction SilentlyContinue).Count -gt 0){$nested++}}
            }
            $status=if($nested -gt 0){'WARN'}else{'PASS'}
            $results.Add((New-DiagnosticResult 'AddOn folder structure' $status "$($dirs.Count) top-level folders, $tocCount TOC files, $nested possible nested AddOn folders; $noToc folders without a top-level TOC." 'Nested TOC files may indicate an incorrect extraction. Libraries and support folders may legitimately lack TOC files.'))
        } catch {$results.Add((New-DiagnosticResult 'AddOn folder structure' 'UNKNOWN' 'Unable to enumerate AddOn folders.' 'Check folder permissions.'))}
    } else {$results.Add((New-DiagnosticResult 'AddOn folder structure' 'INFO' 'No AddOns folder found.' 'Normal if AddOns have not been installed.'))}
    $wtf=Join-Path $versionPath 'WTF'
    if(Test-Path -LiteralPath $wtf -PathType Container){
        $config=Join-Path $wtf 'Config.wtf'
        $results.Add((New-DiagnosticResult 'WoW configuration' $(if(Test-Path -LiteralPath $config -PathType Leaf){'PASS'}else{'INFO'}) $(if(Test-Path -LiteralPath $config -PathType Leaf){'Config.wtf exists.'}else{'Config.wtf not found.'}) 'Absence is not necessarily corruption; WoW can recreate settings.'))
    }
    if($Full){
        try {
            $lua=Join-Path $versionPath 'Logs'
            $errors=@()
            if(Test-Path -LiteralPath $lua -PathType Container){$errors=@(Get-ChildItem -LiteralPath $lua -File -ErrorAction Stop | Where-Object {$_.Name -match '(?i)(error|lua|crash)' } | Sort-Object LastWriteTime -Descending | Select-Object -First 10)}
            $results.Add((New-DiagnosticResult 'Game error logs' 'INFO' "$($errors.Count) matching log filenames in the game Logs directory (up to 10)." 'This is filename inspection, not proof of an AddOn fault. For Lua errors consider BugSack/BugGrabber logs if installed.'))
        } catch {$results.Add((New-DiagnosticResult 'Game error logs' 'UNKNOWN' 'Could not inspect log filenames.' 'Check permissions.'))}
        try {
            $cache=Join-Path $versionPath 'Cache'
            if(Test-Path -LiteralPath $cache -PathType Container){
                $files=@(Get-ChildItem -LiteralPath $cache -File -Recurse -ErrorAction Stop)
                $bytes=($files | Measure-Object Length -Sum).Sum
                $mb=[math]::Round(([double]$bytes)/1MB,1)
                $results.Add((New-DiagnosticResult 'Cache inspection' 'INFO' "$mb MB in $($files.Count) cache files." 'Size alone does not indicate corruption; cleanup is optional.'))
            } else {$results.Add((New-DiagnosticResult 'Cache inspection' 'INFO' 'Cache folder absent.' 'No action needed.'))}
        } catch {$results.Add((New-DiagnosticResult 'Cache inspection' 'UNKNOWN' 'Cache could not be fully enumerated.' 'Possible access restriction; no changes made.'))}
        try {
            $gpu=@(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -First 3)
            $names=($gpu | ForEach-Object { $_.Name }) -join ', '
            $results.Add((New-DiagnosticResult 'Graphics adapters' 'INFO' $(if($names){$names}else{'No adapter information returned.'}) 'Driver age and stability cannot be determined from adapter names alone.'))
        } catch {$results.Add((New-DiagnosticResult 'Graphics adapters' 'UNKNOWN' 'Graphics adapter query failed.' 'Check Device Manager if experiencing graphics issues.'))}
        try {
            $events=@(Get-WinEvent -FilterHashtable @{LogName='Application';Level=2;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 200 -ErrorAction Stop | Where-Object {$_.ProviderName -match '(?i)(application error|windows error reporting)' -and $_.Message -match '(?i)(wow|world of warcraft|battle.net)' } | Select-Object -First 10)
            $results.Add((New-DiagnosticResult 'Windows application errors' 'INFO' "$($events.Count) matching events in up to 200 recent Application errors (last 7 days)." 'This is a limited sample, not an exhaustive crash-history check.'))
        } catch {$results.Add((New-DiagnosticResult 'Windows application errors' 'UNKNOWN' 'Event log unavailable or no matching error-level events returned.' 'No crash conclusion can be drawn.'))}
        try {
            $dns=[System.Net.Dns]::GetHostAddresses('us.battle.net')
            $results.Add((New-DiagnosticResult 'Battle.net DNS' $(if($dns.Count){'PASS'}else{'UNKNOWN'}) 'DNS lookup completed for us.battle.net.' 'DNS success does not prove that game servers are reachable.'))
        } catch {$results.Add((New-DiagnosticResult 'Battle.net DNS' 'UNKNOWN' 'DNS lookup failed.' 'Could be offline, filtered, or temporary; do not reset networking automatically.'))}
    }
    return @($results.ToArray())
}
function Get-DiagnosticSummary([object[]]$Results) {
    $passed=@($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $warnings=@($Results | Where-Object { $_.Status -in @('WARN','FAIL') }).Count
    $info=@($Results | Where-Object { $_.Status -eq 'INFO' }).Count
    $unknown=@($Results | Where-Object { $_.Status -eq 'UNKNOWN' }).Count
    $headline=if($warnings -gt 0){'Your diagnostic scan found items worth reviewing.'}elseif($unknown -gt 0){'Your diagnostic scan found no confirmed problems, but some checks were inconclusive.'}else{'Your diagnostic scan looks excellent.'}
    $recommendation=if($warnings -gt 0){'Review the warnings and failures below. Only run a repair if it addresses a specific problem you are experiencing.'}elseif($unknown -gt 0){'No confirmed problems were detected. Some checks could not complete; do not run repairs just because a check is unknown.'}else{'Based on the checks performed, I would not run any repair options right now unless you are experiencing a specific WoW problem.'}
    return [pscustomobject]@{Passed=$passed;Warnings=$warnings;Info=$info;Unknown=$unknown;Headline=$headline;Recommendation=$recommendation}
}
function Get-DiagnosticHighlights([object[]]$Results) {
    $notes=[System.Collections.Generic.List[string]]::new()
    foreach($r in $Results) {
        switch -Wildcard ($r.Area) {
            'AddOn folder structure' { $notes.Add('AddOns: '+$r.Finding+' Folder structure alone cannot establish whether AddOns are current or error-free.') }
            'Free disk space' { $notes.Add('Storage: '+$r.Finding+' Low space can interfere with updates.') }
            'WoW configuration' { $notes.Add('Configuration: '+$r.Finding+' There is no reason to reset settings solely because this file exists.') }
            'Cache inspection' { $notes.Add('Cache: '+$r.Finding+' Size alone is not evidence of corruption or a reason to clear it.') }
            'Windows application errors' { $notes.Add('Windows errors: '+$r.Finding+' This is a limited sample, not a complete crash history.') }
            'Battle.net DNS' { $notes.Add('Network: '+$r.Finding+' DNS resolution does not establish actual server connectivity or latency.') }
            'Installation' { if($r.Status -ne 'PASS'){$notes.Add('Installation: '+$r.Finding+' '+$r.Advice)} }
            default { if($r.Status -in @('WARN','FAIL','UNKNOWN')) {$notes.Add($r.Area+': '+$r.Finding+' '+$r.Advice)} }
        }
    }
    return @($notes.ToArray())
}
function Get-DiagnosticReportLines([object[]]$Results, [string]$Mode, [bool]$Markdown) {
    $summary=Get-DiagnosticSummary $Results
    $highlights=@(Get-DiagnosticHighlights $Results)
    $lines=[System.Collections.Generic.List[string]]::new()
    if($Markdown){
        $lines.Add('# RebelTortuga WoW Diagnostics')
        $lines.Add('')
        $lines.Add('**Scan:** '+$Mode+' | **Created:** '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')+' | **Version:** '+$script:WowVersion)
        $lines.Add('')
        $lines.Add('## '+$summary.Headline)
        $lines.Add('')
        $lines.Add('| Passed | Warnings / failures | Informational | Unknown |')
        $lines.Add('|---:|---:|---:|---:|')
        $lines.Add('| '+$summary.Passed+' | '+$summary.Warnings+' | '+$summary.Info+' | '+$summary.Unknown+' |')
        $lines.Add('')
        $lines.Add($summary.Recommendation)
        $lines.Add('')
        $lines.Add('## What stands out')
        $lines.Add('')
        foreach($note in $highlights){$lines.Add('- '+$note)}
        $lines.Add('')
        $lines.Add('## All check results')
        $lines.Add('')
        foreach($r in $Results){$lines.Add('- **['+$r.Status+'] '+$r.Area+':** '+$r.Finding+'  ');$lines.Add('  Guidance: '+$r.Advice)}
        $lines.Add('')
        $lines.Add('**Privacy:** Paths and usernames intentionally omitted; adapter names and findings may still identify system details. Review before sharing.')
        $lines.Add('**Safety:** No repair actions were executed. These checks do not prove that the installation is fault-free.')
    }else{
        $lines.Add('REBELTORTUGA WoW DIAGNOSTICS')
        $lines.Add('Scan: '+$Mode+' | Created: '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')+' | Version: '+$script:WowVersion)
        $lines.Add('')
        $lines.Add($summary.Headline)
        $lines.Add('')
        $lines.Add('PASSED: '+$summary.Passed+'    WARNINGS / FAILURES: '+$summary.Warnings+'    INFORMATIONAL: '+$summary.Info+'    UNKNOWN: '+$summary.Unknown)
        $lines.Add('')
        $lines.Add($summary.Recommendation)
        $lines.Add('')
        $lines.Add('WHAT STANDS OUT')
        foreach($note in $highlights){$lines.Add('  - '+$note)}
        $lines.Add('')
        $lines.Add('ALL CHECK RESULTS')
        foreach($r in $Results){$lines.Add('['+$r.Status+'] '+$r.Area+': '+$r.Finding);$lines.Add('  Guidance: '+$r.Advice)}
        $lines.Add('')
        $lines.Add('PRIVACY: Paths and usernames omitted. Review adapter names and findings before sharing.')
        $lines.Add('SAFETY: No repairs executed. Checks do not prove the installation is fault-free.')
    }
    return @($lines.ToArray())
}
function Show-DiagnosticResults([object[]]$Results) {
    $summary=Get-DiagnosticSummary $Results
    Write-Host ''
    Write-Host $summary.Headline -ForegroundColor $(if($summary.Warnings -gt 0){'Yellow'}else{'Green'})
    Write-Host ('PASSED: {0}  |  WARNINGS / FAILURES: {1}  |  INFORMATIONAL: {2}  |  UNKNOWN: {3}' -f $summary.Passed,$summary.Warnings,$summary.Info,$summary.Unknown) -ForegroundColor Cyan
    Write-Host ''
    Write-Host $summary.Recommendation -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'WHAT STANDS OUT' -ForegroundColor Cyan
    foreach($note in @(Get-DiagnosticHighlights $Results)){Write-Host (' - '+$note)}
    Write-Host ''
    Write-Host 'ALL CHECK RESULTS' -ForegroundColor Cyan
    foreach($r in $Results){
        $color=switch($r.Status){'PASS'{'Green'}'WARN'{'Yellow'}'FAIL'{'Red'}default{'Gray'}}
        Write-Host ('[{0}] {1}: {2}' -f $r.Status,$r.Area,$r.Finding) -ForegroundColor $color
        if($r.Status -in @('WARN','FAIL','UNKNOWN')){Write-Host ('       Guidance: '+$r.Advice) -ForegroundColor DarkGray}
    }
    Write-Host ''
    Write-Host 'Results suggest areas to investigate; they do not establish root cause.' -ForegroundColor Yellow
}
function Export-DiagnosticResults([object[]]$Results, [string]$Mode) {
    # Choose a familiar folder each time; never silently write into AppData.
    $desktop=[Environment]::GetFolderPath('Desktop')
    $documents=[Environment]::GetFolderPath('MyDocuments')
    $downloads=Join-Path $env:USERPROFILE 'Downloads'
    $options=@(
        @{Label='Desktop';Path=$desktop},
        @{Label='Documents';Path=$documents},
        @{Label='Downloads';Path=$downloads}
    )
    Write-Host ''
    Write-Host '=== SAVE DIAGNOSTIC REPORT ===' -ForegroundColor Cyan
    Write-Host 'Both readable TXT and Markdown reports will be saved together.'
    Write-Host '1. Desktop'
    Write-Host '2. Documents'
    Write-Host '3. Downloads'
    Write-Host '4. Browse for a folder...'
    Write-Host '5. Enter a folder path manually'
    Write-Host '0. Cancel (do not save)'
    $choice=Read-Host 'Choose where to save'
    $folder=$null
    switch($choice) {
        '1' {$folder=$options[0].Path}
        '2' {$folder=$options[1].Path}
        '3' {$folder=$options[2].Path}
        '4' {
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                $dialog=New-Object System.Windows.Forms.FolderBrowserDialog
                $dialog.Description='Choose a folder for the WoW diagnostic reports'
                $dialog.ShowNewFolderButton=$true
                if(Test-Path -LiteralPath $desktop -PathType Container){$dialog.SelectedPath=$desktop}
                if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$folder=$dialog.SelectedPath}
                $dialog.Dispose()
            } catch {
                Write-Host 'Folder browser unavailable; enter a folder path instead.' -ForegroundColor Yellow
                $folder=Read-Host 'Folder path (blank to cancel)'
            }
        }
        '5' {$folder=Read-Host 'Folder path (blank to cancel)'}
        '0' {Write-Host 'Report export canceled.';return}
        default {Write-Host 'Invalid choice; no report saved.' -ForegroundColor Yellow;return}
    }
    if([string]::IsNullOrWhiteSpace($folder)){Write-Host 'Report export canceled.';return}
    $folder=[Environment]::ExpandEnvironmentVariables($folder.Trim().Trim('"'))
    try {
        if(-not (Test-Path -LiteralPath $folder -PathType Container)) {
            $confirm=Read-Host "Folder does not exist. Create it? (Y/N)"
            if($confirm -notmatch '^(?i:y|yes)$'){Write-Host 'Report export canceled.';return}
            New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null
        }
        $base='WoW-Diagnostics-'+(Get-Date -Format 'yyyyMMdd-HHmmss')
        $txt=Join-Path $folder ($base+'.txt')
        $md=Join-Path $folder ($base+'.md')
        $i=1
        while((Test-Path -LiteralPath $txt) -or (Test-Path -LiteralPath $md)) {
            $txt=Join-Path $folder ($base+'-'+$i+'.txt')
            $md=Join-Path $folder ($base+'-'+$i+'.md')
            $i++
        }
        @(Get-DiagnosticReportLines $Results $Mode $false) | Set-Content -LiteralPath $txt -Encoding UTF8 -ErrorAction Stop
        @(Get-DiagnosticReportLines $Results $Mode $true) | Set-Content -LiteralPath $md -Encoding UTF8 -ErrorAction Stop
        Write-Host ('Saved text report: '+$txt) -ForegroundColor Green
        Write-Host ('Saved Markdown report: '+$md) -ForegroundColor Green
        Write-Host 'Review reports before sharing publicly.' -ForegroundColor Yellow
        if((Read-Host 'Open the saved folder in File Explorer? (Y/N)') -match '^(?i:y|yes)$') {
            Invoke-Item -LiteralPath $folder
        }
    } catch {
        Write-Host ('Could not save reports: '+$_.Exception.Message) -ForegroundColor Red
        Write-Host 'Choose a different writable folder and try again.' -ForegroundColor Yellow
    }
}
function Show-DiagnosticsCenter {
    $last=$null; $mode=''
    while($true){
        Write-Host ''
        Write-Host '=== DIAGNOSTICS CENTER: READ-ONLY ===' -ForegroundColor Cyan
        Write-Host '1. Quick Health Check (local checks, no network)'
        Write-Host '2. Full Diagnostic Scan (includes optional DNS lookup)'
        Write-Host '3. Save last scan reports (choose Desktop, Documents, Downloads, or folder)'
        Write-Host '0. Return to main menu'
        $choice=Read-Host 'Choose'
        switch($choice){
            '1' {$last=@(Test-WowDiagnostics $false);$mode='Quick';Show-DiagnosticResults $last}
            '2' {$last=@(Test-WowDiagnostics $true);$mode='Full';Show-DiagnosticResults $last}
            '3' {if($null -eq $last){Write-Host 'Run a scan first.' -ForegroundColor Yellow}else{Export-DiagnosticResults $last $mode}}
            '0' {return}
            default {Write-Host 'Invalid choice.' -ForegroundColor Yellow}
        }
    }
}
