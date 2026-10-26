# WoW Diagnostic and Repair Toolkit - graphical front end
# Windows PowerShell 5.1 / WinForms. The original repair engine remains separate.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Engine = Join-Path $PSScriptRoot 'WoW Diagnostic and Repair Toolkit.ps1'
$script:Guide = Join-Path $PSScriptRoot 'OPTIONS-README.md'
$script:State = Join-Path $env:LOCALAPPDATA 'RebelTortuga\WoW-Toolkit'
$script:Settings = Join-Path $script:State 'settings.json'
$script:LogFolder = Join-Path $script:State 'Logs'
$script:Busy = $false
$script:LastProcess = $null

function Add-Result([string]$Text) {
    $script:Results.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Text`r`n")
    $script:Results.SelectionStart = $script:Results.TextLength
    $script:Results.ScrollToCaret()
}
function Update-Installation {
    $label = 'No WoW installation selected. Choose your WoW installation to begin.'
    if (Test-Path -LiteralPath $script:Settings) {
        try {
            $data = Get-Content -LiteralPath $script:Settings -Raw | ConvertFrom-Json
            $path = Join-Path (Join-Path $data.WowRoot $data.WowVersion) $data.WowExeName
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $label = $path
            } else { $label = 'Saved installation is missing. Choose your WoW installation.' }
        } catch { $label = 'Saved installation could not be read. Choose your WoW installation.' }
    }
    $script:InstallPath.Text = $label
}
function Open-Guide {
    $guidePath = Join-Path $PSScriptRoot 'OPTIONS-README.md'
    if (-not (Test-Path -LiteralPath $guidePath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show('OPTIONS-README.md is missing. Extract all toolkit files into the same folder.', 'Guide missing', 'OK', 'Warning') | Out-Null
        return
    }
    try {
        # Prefer the user's own default Markdown application when configured.
        Start-Process -FilePath $guidePath -ErrorAction Stop | Out-Null
        Add-Result 'Opened detailed options guide using the default Markdown application.'
    } catch {
        try {
            # Built-in Windows Notepad is the fallback; Notepad++ is never required.
            $notepad = Join-Path $env:WINDIR 'System32\notepad.exe'
            Start-Process -FilePath $notepad -ArgumentList ('"' + $guidePath + '"') -ErrorAction Stop | Out-Null
            Add-Result 'Opened detailed options guide in Windows Notepad.'
        } catch {
            [System.Windows.Forms.MessageBox]::Show(('Unable to open the options guide: ' + $_.Exception.Message), 'Guide error', 'OK', 'Error') | Out-Null
            Add-Result ('Unable to open detailed options guide: ' + $_.Exception.Message)
        }
    }
}
function Start-Action([string]$Id) {
    if ($script:Busy) { return }
    if ($Id -eq '15') {
        $supportUrl = 'https://ko-fi.com/rebeltortuga'
        $answer = [System.Windows.Forms.MessageBox]::Show("All toolkit features are free. Help this turtle get a new shell? Open $supportUrl in your browser?",'Optional RebelTortuga Support','YesNo','Question')
        if ($answer -eq 'Yes') {
            try { Start-Process -FilePath $supportUrl; Add-Result 'Opened the optional Ko-fi support page.' }
            catch { Add-Result ("Unable to open Ko-fi: " + $_.Exception.Message) }
        }
        return
    }
    if (!(Test-Path -LiteralPath $script:Engine)) {
        [System.Windows.Forms.MessageBox]::Show('WoW repair engine is missing. Extract all toolkit files.','Missing file','OK','Error') | Out-Null
        return
    }
    if ($Id -in @('7','8','9','10','11','13','14','3')) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            'This action can change or remove files/settings. Back up important data and completely exit WoW and Battle.net before continuing. The original repair engine will request any additional confirmations. Continue?',
            'Confirm selected action','YesNo','Warning')
        if ($answer -ne 'Yes') { return }
    }
    $script:Busy = $true
    try {
        $ps = Join-Path $PSHOME 'powershell.exe'
        $args = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + $script:Engine + '" -Action ' + $Id
        # Original workflows contain Read-Host prompts and are therefore run
        # in a visible console; the main graphical toolkit stays open.
        $p = Start-Process -FilePath $ps -ArgumentList $args -PassThru -ErrorAction Stop
        $script:LastProcess = $p
        Add-Result ("Started option {0} in its own PowerShell window. Follow its prompts." -f $Id)
        $script:Status.Text = 'Action launched. Follow the prompts in the PowerShell window.'
        if ($Id -eq '4') { Add-Result 'After choosing an installation, click Refresh Installation to update the displayed path.' }
    } catch {
        Add-Result ('Could not start option ' + $Id + ': ' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Could not launch action','OK','Error') | Out-Null
    } finally { $script:Busy = $false }
}
function Show-Section([string]$Name) {
    $script:ActionPanel.Controls.Clear()
    $script:SectionTitle.Text = $Name
    $items = @(switch ($Name) {
        'Diagnostics' { @{Id='1';Text='6.  Diagnostics Center — quick check, full scan, export'} }
        'Backup & Restore' { @{Id='2';Text='4.  Save a backup'}; @{Id='3';Text='5.  Restore a backup'} }
        'Installation & Folders' { @{Id='4';Text='1.  Choose WoW installation'}; @{Id='5';Text='2.  Open WoW folder'}; @{Id='6';Text='3.  Saved Logs'} }
        'Repair & Reset' { @{Id='7';Text='7.  Clear Battle.net files'}; @{Id='8';Text='8.  Reset AddOns and settings'}; @{Id='9';Text='9.  Clear WDB cache'}; @{Id='10';Text='10.  Rebuild game indexes'}; @{Id='11';Text='11.  Comprehensive repair'} }
        'Other Tools' { @{Id='12';Text='12.  Copy DirectX 11 argument'}; @{Id='13';Text='13.  Enable admin requirement'}; @{Id='14';Text='14.  Remove admin requirement'} }
        'Optional Support' { @{Id='15';Text='15.  Optional Ko-fi support'} }
    })
    foreach ($item in $items) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $item.Text
        $b.Tag = $item.Id
        if ($item.Id -eq '1') {
            $b.BackColor = [Drawing.Color]::ForestGreen
            $b.ForeColor = [Drawing.Color]::White
            $b.UseVisualStyleBackColor = $false
        }
        $b.Size = New-Object System.Drawing.Size(565,44)
        $b.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
        $b.TextAlign = 'MiddleLeft'
        $b.Add_Click({ Start-Action ([string]$this.Tag) })
        [void]$script:ActionPanel.Controls.Add($b)
    }
    foreach ($b in $script:NavButtons) {
        $b.BackColor = if ($b.Tag -eq 'Diagnostics') { [Drawing.Color]::ForestGreen } elseif ($b.Tag -eq 'Optional Support') { [Drawing.Color]::RoyalBlue } elseif ($b.Tag -eq $Name -and $b.Tag -ne 'Installation & Folders') { [Drawing.Color]::LightSteelBlue } else { [Drawing.SystemColors]::Control }
        $b.ForeColor = if ($b.Tag -eq 'Diagnostics' -or $b.Tag -eq 'Optional Support') { [Drawing.Color]::White } else { [Drawing.SystemColors]::ControlText }
        $b.UseVisualStyleBackColor = $false
    }
}
try {
    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = 'WoW Diagnostic and Repair Toolkit - Version 1.0.0 - RebelTortuga'
    $script:Form.Size = New-Object Drawing.Size(1080,900)
    $script:Form.MinimumSize = New-Object Drawing.Size(940,800)
    $script:Form.StartPosition = 'CenterScreen'
    $script:Form.Font = New-Object Drawing.Font('Segoe UI',10)
    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 2
    $layout.RowCount = 5
    $layout.Padding = New-Object System.Windows.Forms.Padding(18)
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',240)))
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    foreach ($height in @(112,102,255)) { [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',$height))) }
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',43)))
    $script:Form.Controls.Add($layout)
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "WoW Diagnostic and Repair Toolkit`r`nVersion 1.0.0 | RebelTortuga | Free to use`r`n`r`nCompletely exit World of Warcraft and Battle.net before repairs."
    $heading.Dock = 'Fill'
    $layout.Controls.Add($heading,0,0)
    $layout.SetColumnSpan($heading,2)
    $install = New-Object System.Windows.Forms.TableLayoutPanel
    $install.Dock = 'Fill'
    $install.ColumnCount = 2
    $install.RowCount = 2
    [void]$install.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    [void]$install.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',165)))
    [void]$install.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',40)))
    [void]$install.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $script:InstallPath = New-Object System.Windows.Forms.Label
    $script:InstallPath.Dock = 'Fill'
    $script:InstallPath.TextAlign = 'MiddleLeft'
    $script:InstallPath.AutoEllipsis = $true
    $pathRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $pathRow.Dock = 'Fill'
    $pathRow.WrapContents = $false
    $pathRow.AutoScroll = $false
    $script:InstallPath.AutoSize = $false
    $script:InstallPath.Size = New-Object System.Drawing.Size(510,34)
    $pathRow.Controls.Add($script:InstallPath)
    $refresh = New-Object System.Windows.Forms.Button
    $refresh.Text = 'Refresh Installation'
    $refresh.Size = New-Object System.Drawing.Size(160,34)
    $refresh.Margin = New-Object System.Windows.Forms.Padding(8,0,0,0)
    $refresh.Add_Click({ Update-Installation; Add-Result 'Installation display refreshed.' })
    $pathRow.Controls.Add($refresh)
    $install.Controls.Add($pathRow,0,0)
    $install.SetColumnSpan($pathRow,2)
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Installation: choose your WoW folder using option 1. The toolkit remembers your selection. Some actions open a PowerShell window to show detailed prompts and results.'
    $hint.Dock = 'Fill'
    $install.Controls.Add($hint,0,1)
    $install.SetColumnSpan($hint,2)
    $layout.Controls.Add($install,0,1)
    $layout.SetColumnSpan($install,2)
    # Explicitly position the sidebar using a vertical stack rather than
    # TableLayoutPanel rows, which can redistribute controls at different DPI.
    $script:Nav = New-Object System.Windows.Forms.Panel
    $script:Nav.Dock = 'Fill'
    $layout.Controls.Add($script:Nav,0,2)
    $layout.SetRowSpan($script:Nav,3)
    $script:NavButtons = @()
    $names = @('Installation & Folders','Backup & Restore','Diagnostics','Repair & Reset','Other Tools','Optional Support')
    $top = 0
    foreach ($name in $names) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $name
        $b.Tag = $name
        $b.Location = New-Object System.Drawing.Point(0,$top)
        $b.Size = New-Object System.Drawing.Size(224,40)
        $b.Anchor = 'Top,Left,Right'
        $b.Add_Click({ Show-Section ([string]$this.Tag) })
        $script:Nav.Controls.Add($b)
        $script:NavButtons += $b
        $top += 48
    }
    # Optional Support stays directly below Other Tools; the remaining
    # controls occupy their own bottom-aligned region.
    $exit = New-Object System.Windows.Forms.Button
    $exit.Text = 'Exit Toolkit'
    $exit.Size = New-Object System.Drawing.Size(224,42)
    $exit.Anchor = 'Top,Left,Right'
    $exit.BackColor = [Drawing.Color]::LightGoldenrodYellow
    $exit.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
    $exit.Add_Click({ $script:Form.Close() })
    $script:Nav.Controls.Add($exit)
    $guide = New-Object System.Windows.Forms.Button
    $guide.Text = 'Detailed Options Guide (H)'
    $guide.Size = New-Object System.Drawing.Size(224,42)
    $guide.Anchor = 'Top,Left,Right'
    $guide.Add_Click({ Open-Guide })
    $script:Nav.Controls.Add($guide)
    $script:Nav.Add_Resize({
        $w = [Math]::Max(120,$script:Nav.ClientSize.Width - 12)
        foreach ($b in $script:NavButtons) { $b.Width = $w }
        $exit.Width = $w
        $guide.Width = $w
        $exit.Top = [Math]::Max(298,$script:Nav.ClientSize.Height - 100)
        $guide.Top = [Math]::Max(346,$script:Nav.ClientSize.Height - 50)
    })
    $script:Nav.PerformLayout()
    $content=New-Object System.Windows.Forms.TableLayoutPanel
    $content.Dock='Fill';$content.RowCount=2
    [void]$content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',35)))
    [void]$content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $layout.Controls.Add($content,1,2)
    $script:SectionTitle=New-Object System.Windows.Forms.Label
    $script:SectionTitle.Dock='Fill'
    $script:SectionTitle.Font=New-Object Drawing.Font('Segoe UI',12,[Drawing.FontStyle]::Bold)
    $content.Controls.Add($script:SectionTitle,0,0)
    $script:ActionPanel=New-Object System.Windows.Forms.FlowLayoutPanel
    $script:ActionPanel.Dock='Fill'
    $script:ActionPanel.FlowDirection='TopDown'
    $script:ActionPanel.WrapContents=$false
    $script:ActionPanel.AutoScroll=$true
    $content.Controls.Add($script:ActionPanel,0,1)
    $resultsPanel=New-Object System.Windows.Forms.TableLayoutPanel
    $resultsPanel.Dock='Fill';$resultsPanel.RowCount=2
    [void]$resultsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',30)))
    [void]$resultsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $caption=New-Object System.Windows.Forms.Label
    $caption.Text='Results and messages appear here';$caption.Dock='Fill'
    $resultsPanel.Controls.Add($caption,0,0)
    $script:Results=New-Object System.Windows.Forms.TextBox
    $script:Results.Multiline=$true;$script:Results.ReadOnly=$true
    $script:Results.ScrollBars='Vertical';$script:Results.Dock='Fill'
    $script:Results.Font=New-Object Drawing.Font('Consolas',10)
    $resultsPanel.Controls.Add($script:Results,0,1)
    $layout.Controls.Add($resultsPanel,1,3)
    $script:Status=New-Object System.Windows.Forms.Label
    $script:Status.Dock='Fill'
    $script:Status.Text='Ready. Select a diagnostic or repair action.'
    $layout.Controls.Add($script:Status,1,4)
    $script:Form.KeyPreview=$true
    $script:Form.Add_KeyDown({ if ($_.KeyCode -eq 'H' -and !$_.Control -and !$_.Alt) { Open-Guide; $_.Handled=$true } })
    Update-Installation
    Show-Section 'Installation & Folders'
    Add-Result 'Toolkit opened. Choose your WoW installation if not already configured.'
    [void]$script:Form.ShowDialog()
    $script:Form.Dispose()
} catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'WoW Toolkit - Startup Failed','OK','Error') | Out-Null
    exit 1
}
