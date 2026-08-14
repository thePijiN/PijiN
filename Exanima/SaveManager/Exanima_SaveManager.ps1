#Requires -Version 5.1
<#
.SYNOPSIS
    Exanima Save Manager - standalone WinForms save backup utility.
.DESCRIPTION
    Creates labeled backups, restores one or more compatible backups, creates
    Dungeon checkpoints, and supports bulk backup deletion.
.NOTES
    Ctrl+click and Shift+click selection is enabled in both file lists.
    Multiple backups can be restored together only when no two selected backup
    folders contain the same destination filename.
#>

[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

try {
    Add-Type -Namespace Native -Name Dwm -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@
} catch { }

# Paths and save rules
$SaveDir = Join-Path $env:APPDATA 'Exanima'
$BackupRoot = Join-Path $SaveDir 'SaveManager'
$GameFilePattern = '^(Arena|Exanima)\d+\.(rsg|rcp)$'
$ReloadFolderPattern = '^(Arena_)?Reload_'
$MaxReloadBackups = 5

function Get-GameFiles([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $script:GameFilePattern } |
        Sort-Object Name)
}

function Get-CurrentFiles {
    return @(Get-GameFiles $script:SaveDir)
}

function Get-BackupDirectories {
    if (-not (Test-Path -LiteralPath $script:BackupRoot -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $script:BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch $script:ReloadFolderPattern } |
        Sort-Object Name -Descending)
}

function Get-ReloadDirectories {
    if (-not (Test-Path -LiteralPath $script:BackupRoot -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $script:BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $script:ReloadFolderPattern } |
        Sort-Object Name -Descending)
}

function Get-BackupType($Files) {
    $hasArena = [bool]($Files | Where-Object { $_.Name -match '^Arena' })
    $hasDungeon = [bool]($Files | Where-Object { $_.Name -match '^Exanima' })
    if ($hasArena -and $hasDungeon) { return 'Mixed' }
    if ($hasArena) { return 'Arena' }
    if ($hasDungeon) { return 'Dungeon' }
    return 'Empty'
}

function Get-BackupNameParts([string]$DirectoryName) {
    $isReload = $DirectoryName -match $script:ReloadFolderPattern
    $rest = $DirectoryName -replace '^(Arena_)?Reload_', ''
    $rest = $rest -replace '^Arena_', ''
    $dateText = ''
    $label = ''
    $dateValue = [datetime]::MinValue

    if ($rest -match '^(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})(?:_(.+))?$') {
        $dateText = "$($Matches[1])  $($Matches[2]):$($Matches[3]):$($Matches[4])"
        $timestamp = "$($Matches[1]) $($Matches[2]):$($Matches[3]):$($Matches[4])"
        [datetime]::TryParseExact(
            $timestamp,
            'yyyy-MM-dd HH:mm:ss',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$dateValue
        ) | Out-Null
        if ($Matches[5]) { $label = $Matches[5] }
    }

    return [pscustomobject]@{
        IsReload = $isReload
        DateText = $dateText
        DateValue = $dateValue
        Label = $label
    }
}

function Get-BackupInfo([System.IO.DirectoryInfo]$Directory) {
    $files = @(Get-GameFiles $Directory.FullName)
    $parts = Get-BackupNameParts $Directory.Name
    $bytes = [long]0
    foreach ($file in $files) { $bytes += $file.Length }

    $dateText = $parts.DateText
    $dateValue = $parts.DateValue
    if (-not $dateText) {
        $dateText = $Directory.LastWriteTime.ToString('yyyy-MM-dd  HH:mm:ss')
        $dateValue = $Directory.LastWriteTime
    }

    $displayLabel = if ($parts.IsReload) {
        '[automatic safety copy]'
    } elseif ($parts.Label) {
        $parts.Label
    } else {
        '(unlabeled)'
    }

    return [pscustomobject]@{
        Directory = $Directory
        Files = $files
        IsReload = $parts.IsReload
        Label = $displayLabel
        DateText = $dateText
        DateValue = $dateValue
        Type = Get-BackupType $files
        Bytes = $bytes
    }
}

function Format-FileSize([long]$Bytes) {
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N1} KB' -f ($Bytes / 1KB))
}

function ConvertTo-SafeLabel([string]$Label) {
    $safe = $Label.Trim() -replace '[\\/:*?"<>|]', '_'
    $safe = $safe -replace '\s+', ' '
    $safe = $safe.Trim([char[]]' .')
    if ($safe.Length -gt 48) { $safe = $safe.Substring(0, 48).Trim() }
    return $safe
}

function New-UniqueDirectory([string]$BaseName) {
    $candidate = Join-Path $script:BackupRoot $BaseName
    $suffix = 2
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $script:BackupRoot ("{0}_{1}" -f $BaseName, $suffix)
        $suffix++
    }
    return $candidate
}

function Get-SelectedTags([System.Windows.Forms.ListView]$ListView) {
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $ListView.SelectedItems) { $result.Add($item.Tag) }
    return @($result)
}

function Get-CurrentBackupInfo($Info) {
    if (-not $Info -or -not $Info.Directory) { return $null }
    if (-not (Test-Path -LiteralPath $Info.Directory.FullName -PathType Container)) { return $null }
    return Get-BackupInfo (Get-Item -LiteralPath $Info.Directory.FullName)
}

function Get-RestorePlan($BackupInfos, [switch]$RefreshFromDisk) {
    $entries = [System.Collections.Generic.List[object]]::new()
    $emptyNames = [System.Collections.Generic.List[string]]::new()
    $missingNames = [System.Collections.Generic.List[string]]::new()

    foreach ($info in @($BackupInfos)) {
        $currentInfo = if ($RefreshFromDisk) { Get-CurrentBackupInfo $info } else { $info }
        if (-not $currentInfo) {
            $missingNames.Add($info.Directory.Name)
            continue
        }
        if ($currentInfo.Files.Count -eq 0) {
            $emptyNames.Add($currentInfo.Directory.Name)
            continue
        }
        foreach ($file in $currentInfo.Files) {
            $entries.Add([pscustomobject]@{
                Source = $file
                Backup = $currentInfo
                DestinationName = $file.Name
            })
        }
    }

    $conflicts = @($entries |
        Group-Object { $_.DestinationName.ToLowerInvariant() } |
        Where-Object { $_.Count -gt 1 } |
        ForEach-Object { $_.Group[0].DestinationName } |
        Sort-Object)

    $reason = ''
    if (@($BackupInfos).Count -eq 0) {
        $reason = 'Select one or more backups.'
    } elseif ($missingNames.Count -gt 0) {
        $reason = 'One or more selected backup folders no longer exist.'
    } elseif ($emptyNames.Count -gt 0) {
        $reason = 'One or more selected backups contain no recognized save files.'
    } elseif ($conflicts.Count -gt 0) {
        $preview = ($conflicts | Select-Object -First 3) -join ', '
        if ($conflicts.Count -gt 3) { $preview += ', ...' }
        $reason = "Restore unavailable: selected backups overlap on $preview"
    }

    return [pscustomobject]@{
        IsValid = (@($BackupInfos).Count -gt 0 -and -not $reason)
        Entries = @($entries)
        Conflicts = $conflicts
        Reason = $reason
    }
}

$clrWindow = [System.Drawing.Color]::FromArgb(12, 13, 15)
$clrPanel = [System.Drawing.Color]::FromArgb(22, 24, 27)
$clrPanelAlt = [System.Drawing.Color]::FromArgb(28, 30, 34)
$clrInput = [System.Drawing.Color]::FromArgb(37, 40, 45)
$clrBorder = [System.Drawing.Color]::FromArgb(58, 62, 69)
$clrAccent = [System.Drawing.Color]::FromArgb(218, 126, 51)
$clrAccentHi = [System.Drawing.Color]::FromArgb(240, 151, 77)
$clrText = [System.Drawing.Color]::FromArgb(232, 232, 230)
$clrDim = [System.Drawing.Color]::FromArgb(151, 155, 160)
$clrDisabled = [System.Drawing.Color]::FromArgb(88, 91, 96)
$clrArena = [System.Drawing.Color]::FromArgb(235, 153, 82)
$clrGreen = [System.Drawing.Color]::FromArgb(103, 201, 126)
$clrRed = [System.Drawing.Color]::FromArgb(224, 92, 76)
$clrRedDim = [System.Drawing.Color]::FromArgb(79, 38, 34)
$clrWarnBg = [System.Drawing.Color]::FromArgb(103, 38, 28)
$clrWarnText = [System.Drawing.Color]::FromArgb(255, 222, 214)

$fntUI = New-Object System.Drawing.Font('Segoe UI', 9)
$fntSmall = New-Object System.Drawing.Font('Segoe UI', 8.25)
$fntBold = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$fntSection = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
$fntMono = New-Object System.Drawing.Font('Consolas', 8.5)

function Set-ButtonEnabled([System.Windows.Forms.Button]$Button, [bool]$Enabled) {
    $Button.Enabled = $Enabled
    $role = [string]$Button.Tag
    if (-not $Enabled) {
        $Button.BackColor = if ($role -eq 'Danger') { $script:clrRedDim } else { $script:clrInput }
        $Button.ForeColor = $script:clrDisabled
        $Button.FlatAppearance.BorderColor = $script:clrBorder
        $Button.FlatAppearance.BorderSize = 1
        return
    }
    switch ($role) {
        'Primary' {
            $Button.BackColor = $script:clrAccent
            $Button.ForeColor = [System.Drawing.Color]::Black
            $Button.FlatAppearance.BorderColor = $script:clrAccent
            $Button.FlatAppearance.MouseOverBackColor = $script:clrAccentHi
            $Button.FlatAppearance.BorderSize = 0
        }
        'Danger' {
            $Button.BackColor = $script:clrRedDim
            $Button.ForeColor = $script:clrRed
            $Button.FlatAppearance.BorderColor = $script:clrRed
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(101, 46, 40)
            $Button.FlatAppearance.BorderSize = 1
        }
        default {
            $Button.BackColor = $script:clrInput
            $Button.ForeColor = $script:clrText
            $Button.FlatAppearance.BorderColor = $script:clrBorder
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(49, 53, 59)
            $Button.FlatAppearance.BorderSize = 1
        }
    }
}

function New-FlatButton([string]$Text, [string]$Role, [int]$Width) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 32
    $button.FlatStyle = 'Flat'
    $button.Font = $script:fntBold
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = $Role
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    Set-ButtonEnabled $button $true
    return $button
}

function New-SectionLabel([string]$Text) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Font = $script:fntSection
    $label.ForeColor = $script:clrText
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleLeft'
    return $label
}

function New-DarkListView {
    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.HideSelection = $false
    $list.MultiSelect = $true
    $list.BackColor = $script:clrPanel
    $list.ForeColor = $script:clrText
    $list.BorderStyle = 'FixedSingle'
    $list.Font = $script:fntMono
    $list.Dock = 'Fill'
    $list.HeaderStyle = 'Nonclickable'
    try {
        $property = $list.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic')
        $property.SetValue($list, $true, $null)
    } catch { }
    return $list
}

function Get-AlternateRowColor([int]$Index) {
    if ($Index % 2 -eq 0) { return $script:clrPanel }
    return $script:clrPanelAlt
}

function Fit-LastColumn([System.Windows.Forms.ListView]$ListView) {
    if ($ListView.Columns.Count -eq 0) { return }
    $used = 0
    for ($index = 0; $index -lt ($ListView.Columns.Count - 1); $index++) { $used += $ListView.Columns[$index].Width }
    $available = $ListView.ClientSize.Width - $used - 6
    if ($available -gt 48) { $ListView.Columns[$ListView.Columns.Count - 1].Width = $available }
}

function Set-Status([string]$Message, $Color) {
    if (-not $Color) { $Color = $script:clrDim }
    $script:lblStatus.Text = $Message
    $script:lblStatus.ForeColor = $Color
}

function Show-Confirmation([string]$Text, [string]$Title, [string]$Icon) {
    $result = [System.Windows.Forms.MessageBox]::Show(
        $script:form,
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::$Icon,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

if (-not (Test-Path -LiteralPath $SaveDir -PathType Container)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Save directory not found:`r`n$SaveDir`r`n`r`nLaunch Exanima at least once to create it.",
        'Exanima Save Manager', 'OK', 'Error'
    ) | Out-Null
    exit 1
}

try {
    New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Could not create the backup directory:`r`n$BackupRoot`r`n`r`n$($_.Exception.Message)",
        'Exanima Save Manager', 'OK', 'Error'
    ) | Out-Null
    exit 1
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Exanima Save Manager'
$form.ClientSize = New-Object System.Drawing.Size(1200, 620)
$form.MinimumSize = New-Object System.Drawing.Size(960, 540)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $clrWindow
$form.ForeColor = $clrText
$form.Font = $fntUI
$form.KeyPreview = $true
$form.AutoScaleMode = 'Dpi'

try {
    $iconPath = Join-Path $PSScriptRoot 'Exaniman.ico'
    if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
} catch { }

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 10000
$toolTip.InitialDelay = 350

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 52
$header.BackColor = $clrWindow

$btnOpenFolder = New-FlatButton 'Open Save Folder' 'Secondary' 132
$btnRefresh = New-FlatButton 'Refresh' 'Secondary' 86
$btnRefresh.Anchor = 'Top,Right'
$btnOpenFolder.Anchor = 'Top,Right'
$btnRefresh.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 104), 10)
$btnOpenFolder.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 244), 10)
$header.Controls.AddRange(@($btnOpenFolder, $btnRefresh))
$header.Add_Resize({
    $script:btnRefresh.Left = $script:header.ClientSize.Width - $script:btnRefresh.Width - 18
    $script:btnOpenFolder.Left = $script:btnRefresh.Left - $script:btnOpenFolder.Width - 8
})

$pnlWarning = New-Object System.Windows.Forms.Panel
$pnlWarning.Dock = 'Top'
$pnlWarning.Height = 38
$pnlWarning.BackColor = $clrWarnBg
$pnlWarning.Visible = $false
$lblWarning = New-Object System.Windows.Forms.Label
$lblWarning.Dock = 'Fill'
$lblWarning.TextAlign = 'MiddleCenter'
$lblWarning.Font = $fntBold
$lblWarning.ForeColor = $clrWarnText
$lblWarning.Text = 'Exanima is running. Return to the main menu or close the game before changing save files.'
$pnlWarning.Controls.Add($lblWarning)

$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Dock = 'Bottom'
$pnlStatus.Height = 31
$pnlStatus.BackColor = $clrPanel
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Dock = 'Fill'
$lblStatus.TextAlign = 'MiddleLeft'
$lblStatus.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
$lblStatus.ForeColor = $clrDim
$lblStatus.Text = 'Ready.'
$pnlStatus.Controls.Add($lblStatus)

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 12)
$content.BackColor = $clrWindow
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Vertical'
$split.SplitterWidth = 8
$split.BackColor = $clrWindow
$content.Controls.Add($split)

$leftLayout = New-Object System.Windows.Forms.TableLayoutPanel
$leftLayout.Dock = 'Fill'
$leftLayout.ColumnCount = 1
$leftLayout.RowCount = 4
$leftLayout.Padding = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 34))) | Out-Null
$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100))) | Out-Null
$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 30))) | Out-Null
$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 92))) | Out-Null
$split.Panel1.Controls.Add($leftLayout)

$leftHeader = New-Object System.Windows.Forms.TableLayoutPanel
$leftHeader.Dock = 'Fill'
$leftHeader.ColumnCount = 2
$leftHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
$leftHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize'))) | Out-Null
$lblSavesTitle = New-SectionLabel 'CURRENT SAVE FILES'
$lblSavesCount = New-Object System.Windows.Forms.Label
$lblSavesCount.AutoSize = $true
$lblSavesCount.ForeColor = $clrDim
$lblSavesCount.Anchor = 'Right'
$leftHeader.Controls.Add($lblSavesTitle, 0, 0)
$leftHeader.Controls.Add($lblSavesCount, 1, 0)

$lvSaves = New-DarkListView
$lvSaves.Columns.Add('Mode', 76) | Out-Null
$lvSaves.Columns.Add('File', 108) | Out-Null
$lvSaves.Columns.Add('Kind', 76) | Out-Null
$lvSaves.Columns.Add('Modified', 112) | Out-Null
$lvSaves.Columns.Add('Size', 70) | Out-Null

$lblSaveHint = New-Object System.Windows.Forms.Label
$lblSaveHint.Dock = 'Fill'
$lblSaveHint.ForeColor = $clrDim
$lblSaveHint.Font = $fntSmall
$lblSaveHint.TextAlign = 'MiddleLeft'
$lblSaveHint.Text = 'Ctrl+click or Shift+click to select multiple files.'

$saveActions = New-Object System.Windows.Forms.Panel
$saveActions.Dock = 'Fill'
$saveActions.BackColor = $clrWindow
$lblLabel = New-Object System.Windows.Forms.Label
$lblLabel.Text = 'Backup label (optional)'
$lblLabel.AutoSize = $true
$lblLabel.ForeColor = $clrDim
$lblLabel.Location = New-Object System.Drawing.Point(0, 6)
$txtLabel = New-Object System.Windows.Forms.TextBox
$txtLabel.BackColor = $clrInput
$txtLabel.ForeColor = $clrText
$txtLabel.BorderStyle = 'FixedSingle'
$txtLabel.Location = New-Object System.Drawing.Point(0, 28)
$txtLabel.Anchor = 'Top,Left,Right'
$txtLabel.Size = New-Object System.Drawing.Size(188, 25)
$txtLabel.MaxLength = 64
$btnBackup = New-FlatButton 'Back Up' 'Primary' 116
$btnCheckpoint = New-FlatButton 'Checkpoint' 'Secondary' 116
$btnBackup.Anchor = 'Top,Right'
$btnCheckpoint.Anchor = 'Top,Right'
$btnCheckpoint.Location = New-Object System.Drawing.Point(($saveActions.ClientSize.Width - 116), 57)
$btnBackup.Location = New-Object System.Drawing.Point(($saveActions.ClientSize.Width - 240), 57)
$saveActions.Controls.AddRange(@($lblLabel, $txtLabel, $btnBackup, $btnCheckpoint))
$saveActions.Add_Resize({
    $script:btnCheckpoint.Left = $script:saveActions.ClientSize.Width - $script:btnCheckpoint.Width
    $script:btnBackup.Left = $script:btnCheckpoint.Left - $script:btnBackup.Width - 8
    $script:txtLabel.Width = $script:saveActions.ClientSize.Width
})

$leftLayout.Controls.Add($leftHeader, 0, 0)
$leftLayout.Controls.Add($lvSaves, 0, 1)
$leftLayout.Controls.Add($lblSaveHint, 0, 2)
$leftLayout.Controls.Add($saveActions, 0, 3)

$rightLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rightLayout.Dock = 'Fill'
$rightLayout.ColumnCount = 1
$rightLayout.RowCount = 4
$rightLayout.Padding = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 34))) | Out-Null
$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100))) | Out-Null
$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 32))) | Out-Null
$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 44))) | Out-Null
$split.Panel2.Controls.Add($rightLayout)

$rightHeader = New-Object System.Windows.Forms.TableLayoutPanel
$rightHeader.Dock = 'Fill'
$rightHeader.ColumnCount = 2
$rightHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
$rightHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize'))) | Out-Null
$lblBackupsTitle = New-SectionLabel 'BACKUPS'
$lblBackupsCount = New-Object System.Windows.Forms.Label
$lblBackupsCount.AutoSize = $true
$lblBackupsCount.ForeColor = $clrDim
$lblBackupsCount.Anchor = 'Right'
$rightHeader.Controls.Add($lblBackupsTitle, 0, 0)
$rightHeader.Controls.Add($lblBackupsCount, 1, 0)

$lvBackups = New-DarkListView
$lvBackups.Columns.Add('Label', 166) | Out-Null
$lvBackups.Columns.Add('Mode', 70) | Out-Null
$lvBackups.Columns.Add('Created', 142) | Out-Null
$lvBackups.Columns.Add('Size', 74) | Out-Null
$lvBackups.Columns.Add('Contents', 160) | Out-Null

$lblBackupHint = New-Object System.Windows.Forms.Label
$lblBackupHint.Dock = 'Fill'
$lblBackupHint.ForeColor = $clrDim
$lblBackupHint.Font = $fntSmall
$lblBackupHint.TextAlign = 'MiddleLeft'
$lblBackupHint.Text = 'Ctrl+click or Shift+click to select multiple backups. Ctrl+A selects all.'

$backupActions = New-Object System.Windows.Forms.FlowLayoutPanel
$backupActions.Dock = 'Fill'
$backupActions.FlowDirection = 'LeftToRight'
$backupActions.WrapContents = $false
$backupActions.Padding = New-Object System.Windows.Forms.Padding(0, 5, 0, 0)
$backupActions.BackColor = $clrWindow
$btnRestore = New-FlatButton 'Restore' 'Primary' 156
$btnDelete = New-FlatButton 'Delete' 'Danger' 132
$backupActions.Controls.AddRange(@($btnRestore, $btnDelete))

$rightLayout.Controls.Add($rightHeader, 0, 0)
$rightLayout.Controls.Add($lvBackups, 0, 1)
$rightLayout.Controls.Add($lblBackupHint, 0, 2)
$rightLayout.Controls.Add($backupActions, 0, 3)

$form.Controls.Add($content)
$form.Controls.Add($pnlStatus)
$form.Controls.Add($pnlWarning)
$form.Controls.Add($header)

$toolTip.SetToolTip($btnBackup, 'Create one snapshot containing every selected .rsg save.')
$toolTip.SetToolTip($btnCheckpoint, 'Copy one selected Dungeon .rsg file to its .rcp checkpoint.')
$toolTip.SetToolTip($btnRestore, 'Restore one backup, or several backups with no overlapping filenames.')
$toolTip.SetToolTip($btnDelete, 'Permanently delete every selected backup folder.')

function Refresh-Saves {
    $selectedPaths = @($script:lvSaves.SelectedItems | ForEach-Object { $_.Tag.FullName })
    $script:lvSaves.BeginUpdate()
    try {
        $script:lvSaves.Items.Clear()
        $files = @(Get-CurrentFiles)
        $index = 0

        foreach ($file in $files) {
            $isArena = $file.Name -match '^Arena'
            $isSave = $file.Extension -ieq '.rsg'
            $mode = if ($isArena) { 'Arena' } else { 'Dungeon' }
            $kind = if ($isSave) { 'Save' } else { 'Checkpoint' }

            $item = New-Object System.Windows.Forms.ListViewItem($mode)
            $item.SubItems.Add($file.Name) | Out-Null
            $item.SubItems.Add($kind) | Out-Null
            $item.SubItems.Add($file.LastWriteTime.ToString('MM-dd  HH:mm')) | Out-Null
            $item.SubItems.Add((Format-FileSize $file.Length)) | Out-Null
            $item.Tag = $file
            $item.BackColor = Get-AlternateRowColor $index
            $item.ForeColor = if (-not $isSave) { $script:clrDim } elseif ($isArena) { $script:clrArena } else { $script:clrText }
            $script:lvSaves.Items.Add($item) | Out-Null
            if ($selectedPaths -contains $file.FullName) { $item.Selected = $true }
            $index++
        }

        $saveCount = @($files | Where-Object { $_.Extension -ieq '.rsg' }).Count
        $checkpointCount = $files.Count - $saveCount
        $script:lblSavesCount.Text = "$saveCount saves  |  $checkpointCount checkpoints"
    } finally {
        $script:lvSaves.EndUpdate()
    }
    Fit-LastColumn $script:lvSaves
}

function Refresh-Backups {
    $selectedPaths = @($script:lvBackups.SelectedItems | ForEach-Object { $_.Tag.Directory.FullName })
    $script:lvBackups.BeginUpdate()
    try {
        $script:lvBackups.Items.Clear()
        $directories = @()
        $directories += @(Get-BackupDirectories)
        $directories += @(Get-ReloadDirectories)
        $infos = @($directories |
            Where-Object { $null -ne $_ } |
            ForEach-Object { Get-BackupInfo $_ } |
            Sort-Object DateValue -Descending)
        $index = 0

        foreach ($info in $infos) {
            $names = ($info.Files | ForEach-Object { $_.Name }) -join ', '
            if (-not $names) { $names = '(no recognized save files)' }

            $item = New-Object System.Windows.Forms.ListViewItem($info.Label)
            $item.SubItems.Add($info.Type) | Out-Null
            $item.SubItems.Add($info.DateText) | Out-Null
            $item.SubItems.Add((Format-FileSize $info.Bytes)) | Out-Null
            $item.SubItems.Add($names) | Out-Null
            $item.Tag = $info
            $item.BackColor = Get-AlternateRowColor $index
            $item.ForeColor = if ($info.IsReload) { $script:clrDim } elseif ($info.Type -eq 'Arena') { $script:clrArena } else { $script:clrText }
            $script:lvBackups.Items.Add($item) | Out-Null
            if ($selectedPaths -contains $info.Directory.FullName) { $item.Selected = $true }
            $index++
        }

        $normalCount = @($infos | Where-Object { -not $_.IsReload }).Count
        $reloadCount = $infos.Count - $normalCount
        $script:lblBackupsCount.Text = "$normalCount backups  |  $reloadCount safety copies"
    } finally {
        $script:lvBackups.EndUpdate()
    }
    Fit-LastColumn $script:lvBackups
}

function Update-SaveSelectionState {
    $selected = @(Get-SelectedTags $script:lvSaves)
    $saveFiles = @($selected | Where-Object { $_.Extension -ieq '.rsg' })
    $canBackup = ($selected.Count -gt 0 -and $saveFiles.Count -eq $selected.Count)
    $canCheckpoint = (
        $selected.Count -eq 1 -and
        $selected[0].Extension -ieq '.rsg' -and
        $selected[0].Name -match '^Exanima'
    )

    $script:btnBackup.Text = if ($selected.Count -gt 1) { "Back Up ($($selected.Count))" } else { 'Back Up' }
    Set-ButtonEnabled $script:btnBackup $canBackup
    Set-ButtonEnabled $script:btnCheckpoint $canCheckpoint

    if ($selected.Count -eq 0) {
        $script:lblSaveHint.Text = 'Ctrl+click or Shift+click to select multiple files.'
    } elseif ($canBackup) {
        $noun = if ($selected.Count -eq 1) { 'save' } else { 'saves in one snapshot' }
        $script:lblSaveHint.Text = "$($selected.Count) selected $noun."
    } else {
        $script:lblSaveHint.Text = 'Backups accept .rsg saves only; remove checkpoint files from the selection.'
    }
}

function Update-BackupSelectionState {
    $selected = @(Get-SelectedTags $script:lvBackups)
    $plan = Get-RestorePlan $selected
    $count = $selected.Count

    $script:btnRestore.Text = if ($count -gt 1) { "Restore ($count)" } else { 'Restore' }
    $script:btnDelete.Text = if ($count -gt 1) { "Delete ($count)" } else { 'Delete' }
    Set-ButtonEnabled $script:btnRestore $plan.IsValid
    Set-ButtonEnabled $script:btnDelete ($count -gt 0)

    if ($count -eq 0) {
        $script:lblBackupHint.Text = 'Ctrl+click or Shift+click to select multiple backups. Ctrl+A selects all.'
    } elseif (-not $plan.IsValid) {
        $script:lblBackupHint.Text = $plan.Reason
    } else {
        $noun = if ($count -eq 1) { 'backup' } else { 'compatible backups' }
        $script:lblBackupHint.Text = "$count $noun selected; $($plan.Entries.Count) files will be restored."
    }
}

function Refresh-All {
    Refresh-Saves
    Refresh-Backups
    Update-SaveSelectionState
    Update-BackupSelectionState
}

# Backup operation
function Invoke-BackupSelected {
    $selected = @(Get-SelectedTags $script:lvSaves)
    $files = @($selected | Where-Object {
        $_.Extension -ieq '.rsg' -and (Test-Path -LiteralPath $_.FullName -PathType Leaf)
    })

    if ($selected.Count -eq 0) {
        Set-Status 'Select one or more current save files.' $script:clrRed
        return
    }
    if ($files.Count -ne $selected.Count) {
        Set-Status 'Only current .rsg save files can be backed up.' $script:clrRed
        return
    }

    $label = ConvertTo-SafeLabel $script:txtLabel.Text
    $allArena = @($files | Where-Object { $_.Name -notmatch '^Arena' }).Count -eq 0
    $prefix = if ($allArena) { 'Arena_' } else { '' }
    $baseName = "${prefix}$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
    if ($label) { $baseName += "_$label" }
    $destination = New-UniqueDirectory $baseName

    try {
        New-Item -ItemType Directory -Path $destination -ErrorAction Stop | Out-Null
        foreach ($file in $files) {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
        }
        $script:txtLabel.Clear()
        Refresh-All
        Set-Status "Created backup '$([System.IO.Path]::GetFileName($destination))' with $($files.Count) save file(s)." $script:clrGreen
    } catch {
        if (Test-Path -LiteralPath $destination -PathType Container) {
            Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        Set-Status "Backup failed: $($_.Exception.Message)" $script:clrRed
    }
}

# Checkpoint operation
function Invoke-MakeCheckpoint {
    $selected = @(Get-SelectedTags $script:lvSaves)
    if ($selected.Count -ne 1) {
        Set-Status 'Select exactly one Dungeon save to make a checkpoint.' $script:clrRed
        return
    }

    $file = $selected[0]
    if ($file.Extension -ine '.rsg' -or $file.Name -notmatch '^Exanima') {
        Set-Status 'Checkpoints can only be made from a Dungeon Exanima*.rsg save.' $script:clrRed
        return
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $destinationName = "$baseName.rcp"
    $destinationPath = Join-Path $script:SaveDir $destinationName
    $message = "Create checkpoint $destinationName from $($file.Name)?`r`n`r`nThe original save will not be changed."
    if (Test-Path -LiteralPath $destinationPath) {
        $message = "Replace existing checkpoint $destinationName?`r`n`r`nThe original $($file.Name) save will not be changed."
    }
    if (-not (Show-Confirmation $message 'Make Dungeon Checkpoint' 'Question')) { return }

    try {
        Copy-Item -LiteralPath $file.FullName -Destination $destinationPath -Force -ErrorAction Stop
        Refresh-All
        Set-Status "Checkpoint created: $destinationName" $script:clrGreen
    } catch {
        Set-Status "Checkpoint failed: $($_.Exception.Message)" $script:clrRed
    }
}

# Restore operation
function New-ReloadBackup($RestoreEntries) {
    $existing = @($RestoreEntries | Where-Object {
        Test-Path -LiteralPath (Join-Path $script:SaveDir $_.DestinationName) -PathType Leaf
    })
    if ($existing.Count -eq 0) { return $null }

    $baseName = "Reload_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
    $directory = New-UniqueDirectory $baseName
    New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
    try {
        foreach ($entry in $existing) {
            $sourcePath = Join-Path $script:SaveDir $entry.DestinationName
            Copy-Item -LiteralPath $sourcePath -Destination $directory -Force -ErrorAction Stop
        }
        return $directory
    } catch {
        Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Remove-OldReloadBackups([string]$KeepPath) {
    $oldDirectories = @(Get-ReloadDirectories |
        Where-Object { $_.FullName -ne $KeepPath } |
        Select-Object -Skip ($script:MaxReloadBackups - 1))
    foreach ($directory in $oldDirectories) {
        Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-RestoreSelected {
    $selected = @(Get-SelectedTags $script:lvBackups)
    $plan = Get-RestorePlan $selected -RefreshFromDisk
    if (-not $plan.IsValid) {
        Set-Status $plan.Reason $script:clrRed
        Update-BackupSelectionState
        return
    }

    $backupNames = @($selected | ForEach-Object { $_.Directory.Name })
    $backupPreview = ($backupNames | Select-Object -First 6) -join "`r`n  "
    if ($backupNames.Count -gt 6) { $backupPreview += "`r`n  ... and $($backupNames.Count - 6) more" }
    $fileNames = @($plan.Entries | ForEach-Object { $_.DestinationName })
    $filePreview = ($fileNames | Select-Object -First 10) -join ', '
    if ($fileNames.Count -gt 10) { $filePreview += ', ...' }

    $message = "Restore $($backupNames.Count) selected backup(s)?`r`n`r`n  $backupPreview`r`n`r`nFiles: $filePreview`r`n`r`nExisting files with these names will be copied to an automatic safety backup first."
    if (-not (Show-Confirmation $message 'Confirm Restore' 'Warning')) { return }

    $reloadPath = $null
    try {
        $reloadPath = New-ReloadBackup $plan.Entries
        foreach ($entry in $plan.Entries) {
            $destination = Join-Path $script:SaveDir $entry.DestinationName
            Copy-Item -LiteralPath $entry.Source.FullName -Destination $destination -Force -ErrorAction Stop
        }
        if ($reloadPath) { Remove-OldReloadBackups $reloadPath }
        Refresh-All
        Set-Status "Restored $($plan.Entries.Count) file(s) from $($backupNames.Count) backup(s)." $script:clrGreen
    } catch {
        Refresh-All
        $safetyNote = if ($reloadPath) { " Safety copy: $([System.IO.Path]::GetFileName($reloadPath))." } else { '' }
        Set-Status "Restore stopped after an error: $($_.Exception.Message).$safetyNote" $script:clrRed
    }
}

# Delete operation
function Invoke-DeleteSelected {
    $selected = @(Get-SelectedTags $script:lvBackups)
    if ($selected.Count -eq 0) {
        Set-Status 'Select one or more backups to delete.' $script:clrRed
        return
    }

    $names = @($selected | ForEach-Object { $_.Directory.Name })
    $preview = ($names | Select-Object -First 10) -join "`r`n  "
    if ($names.Count -gt 10) { $preview += "`r`n  ... and $($names.Count - 10) more" }
    $message = "Permanently delete $($names.Count) selected backup folder(s)?`r`n`r`n  $preview`r`n`r`nThis cannot be undone."
    if (-not (Show-Confirmation $message 'Confirm Bulk Delete' 'Warning')) { return }

    $deleted = 0
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($info in $selected) {
        try {
            if (Test-Path -LiteralPath $info.Directory.FullName -PathType Container) {
                Remove-Item -LiteralPath $info.Directory.FullName -Recurse -Force -ErrorAction Stop
                $deleted++
            }
        } catch {
            $failed.Add($info.Directory.Name)
        }
    }

    Refresh-All
    if ($failed.Count -gt 0) {
        Set-Status "Deleted $deleted backup(s); $($failed.Count) could not be deleted." $script:clrRed
    } else {
        Set-Status "Deleted $deleted backup(s)." $script:clrGreen
    }
}

# Events and keyboard support
$lvSaves.Add_SelectedIndexChanged({ Update-SaveSelectionState })
$lvBackups.Add_SelectedIndexChanged({ Update-BackupSelectionState })
$lvSaves.Add_SizeChanged({ Fit-LastColumn $script:lvSaves })
$lvBackups.Add_SizeChanged({ Fit-LastColumn $script:lvBackups })

$btnBackup.Add_Click({ Invoke-BackupSelected })
$btnCheckpoint.Add_Click({ Invoke-MakeCheckpoint })
$btnRestore.Add_Click({ Invoke-RestoreSelected })
$btnDelete.Add_Click({ Invoke-DeleteSelected })
$btnRefresh.Add_Click({
    Refresh-All
    Set-Status 'Lists refreshed.' $script:clrDim
})
$btnOpenFolder.Add_Click({
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $script:SaveDir) -ErrorAction Stop
    } catch {
        Set-Status "Could not open the save folder: $($_.Exception.Message)" $script:clrRed
    }
})

$txtLabel.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $script:btnBackup.Enabled) {
        $_.SuppressKeyPress = $true
        Invoke-BackupSelected
    }
})

$lvSaves.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::A) {
        foreach ($item in $script:lvSaves.Items) { $item.Selected = $true }
        $_.SuppressKeyPress = $true
    }
})

$lvBackups.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::A) {
        foreach ($item in $script:lvBackups.Items) { $item.Selected = $true }
        $_.SuppressKeyPress = $true
    } elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and $script:btnDelete.Enabled) {
        $_.SuppressKeyPress = $true
        Invoke-DeleteSelected
    }
})

$form.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        $_.SuppressKeyPress = $true
        Refresh-All
        Set-Status 'Lists refreshed.' $script:clrDim
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    $script:pnlWarning.Visible = [bool](Get-Process -Name 'Exanima' -ErrorAction SilentlyContinue)
})
$timer.Start()

$script:wasDeactivated = $false
$form.Add_Deactivate({ $script:wasDeactivated = $true })
$form.Add_Activated({
    if ($script:wasDeactivated) {
        $script:wasDeactivated = $false
        Refresh-All
    }
})

$form.Add_FormClosing({ $script:timer.Stop() })
$form.Add_Shown({
    $targetDistance = [Math]::Max(390, [Math]::Min(480, [int]($script:split.ClientSize.Width * 0.40)))
    $script:split.SplitterDistance = $targetDistance
    $script:split.Panel1MinSize = 340
    $script:split.Panel2MinSize = 480
    try {
        $dark = 1
        $result = [Native.Dwm]::DwmSetWindowAttribute($script:form.Handle, 20, [ref]$dark, 4)
        if ($result -ne 0) {
            [Native.Dwm]::DwmSetWindowAttribute($script:form.Handle, 19, [ref]$dark, 4) | Out-Null
        }
    } catch { }
    Refresh-All
    $script:lvBackups.Focus()
})

if ($ValidateOnly) {
    Refresh-All
    Write-Output ("Validation OK: {0} current files, {1} backup folders." -f $lvSaves.Items.Count, $lvBackups.Items.Count)
} else {
    [void]$form.ShowDialog()
}

$timer.Dispose()
$toolTip.Dispose()
if ($form.Icon) { $form.Icon.Dispose() }
$fntUI.Dispose()
$fntSmall.Dispose()
$fntBold.Dispose()
$fntSection.Dispose()
$fntMono.Dispose()
$form.Dispose()
