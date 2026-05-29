#Requires -Version 5.1
<#
.SYNOPSIS
    Exanima Save Manager - WinForms GUI
.NOTES
    Save file naming (enforced by Exanima):
        Arena###.rsg / Arena###.rcp
        Exanima###.rsg / Exanima###.rcp
    Backup folder naming:
        [Arena_]yyyy-MM-dd_HH-mm-ss[_Label]
        Reload_yyyy-MM-dd_HH-mm-ss
    Backup type is determined by the files inside the folder,
    not the folder name, so old backups without the Arena_ prefix
    are still correctly identified.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# dark title bar support (silently ignored on older Windows)
try {
    Add-Type -Namespace Native -Name Dwm -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@
} catch { }

# ---------------------------------------------------------------------------
# Paths & patterns
# ---------------------------------------------------------------------------
$SaveDir    = Join-Path $env:APPDATA 'Exanima'
$BackupRoot = Join-Path $SaveDir 'SaveManager'

$SavePatterns = 'Arena*.rsg', 'Exanima*.rsg'
$CkptPatterns = 'Arena*.rcp', 'Exanima*.rcp'

# ---------------------------------------------------------------------------
# Data helpers
# ---------------------------------------------------------------------------
function Get-CurrentSaves {
    $found = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($pat in $script:SavePatterns) {
        Get-ChildItem -Path $script:SaveDir -Filter $pat -ErrorAction SilentlyContinue |
            ForEach-Object { $found.Add($_) }
    }
    return @($found | Sort-Object Name)
}

function Get-CurrentCheckpoints {
    $found = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($pat in $script:CkptPatterns) {
        Get-ChildItem -Path $script:SaveDir -Filter $pat -ErrorAction SilentlyContinue |
            ForEach-Object { $found.Add($_) }
    }
    return @($found | Sort-Object Name)
}

function Get-Backups {
    if (-not (Test-Path $script:BackupRoot)) { return @() }
    return @(Get-ChildItem -Path $script:BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^Reload_' } |
        Sort-Object Name -Descending)
}

function Get-ReloadBackups {
    if (-not (Test-Path $script:BackupRoot)) { return @() }
    return @(Get-ChildItem -Path $script:BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Reload_' })
}

# Type is determined by the files inside the backup folder, not the folder name,
# so backups created before the Arena_ prefix convention are still handled correctly.
function Get-BackupType([System.IO.DirectoryInfo]$dir) {
    $files      = @(Get-ChildItem $dir.FullName -ErrorAction SilentlyContinue)
    $hasArena   = [bool]($files | Where-Object { $_.Name -match '^Arena' })
    $hasDungeon = [bool]($files | Where-Object { $_.Name -match '^Exanima' })
    if ($hasArena -and $hasDungeon) { return 'Mixed'   }
    if ($hasArena)                  { return 'Arena'   }
    return 'Dungeon'
}

function Parse-BackupDate([string]$dirName) {
    # Strip known prefixes then extract the timestamp portion
    $rest = $dirName -replace '^(Arena_|Reload_)', ''
    if ($rest -match '^(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})') {
        return "$($Matches[1])  $($Matches[2]):$($Matches[3]):$($Matches[4])"
    }
    return ''
}

function Parse-BackupLabel([string]$dirName) {
    $rest = $dirName -replace '^(Arena_|Reload_)', ''
    if ($rest -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_(.+)$') {
        return $Matches[1]
    }
    return ''
}

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
$clrBg        = [System.Drawing.Color]::FromArgb(  0,   0,   0)
$clrPanel     = [System.Drawing.Color]::FromArgb( 20,  20,  20)
$clrPanelAlt  = [System.Drawing.Color]::FromArgb( 30,  30,  30)  # alternating row
$clrInput     = [System.Drawing.Color]::FromArgb( 46,  46,  50)
$clrBorder    = [System.Drawing.Color]::FromArgb( 64,  64,  68)
$clrAccent    = [System.Drawing.Color]::FromArgb(212, 118,  42)
$clrAccentHi  = [System.Drawing.Color]::FromArgb(238, 148,  64)
$clrAccentDim = [System.Drawing.Color]::FromArgb( 88,  42,  18)
$clrText      = [System.Drawing.Color]::FromArgb(222, 222, 222)
$clrDim       = [System.Drawing.Color]::FromArgb(112, 112, 112)
$clrArena     = [System.Drawing.Color]::FromArgb(224, 138,  58)
$clrGreen     = [System.Drawing.Color]::FromArgb( 88, 196, 108)
$clrRed       = [System.Drawing.Color]::FromArgb(220,  78,  62)
$clrRedDim    = [System.Drawing.Color]::FromArgb( 92,  34,  24)
$clrWarnBg    = [System.Drawing.Color]::FromArgb(118,  20,  14)
$clrWarnText  = [System.Drawing.Color]::FromArgb(255, 214, 205)
$clrFire      = [System.Drawing.Color]::FromArgb(255, 210,  50)  # checkpoint active text

$fntUI   = New-Object System.Drawing.Font('Segoe UI',  9)
$fntBold = New-Object System.Drawing.Font('Segoe UI',  9, [System.Drawing.FontStyle]::Bold)
$fntMono = New-Object System.Drawing.Font('Consolas',  8.5)
$fntHead = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

# ---------------------------------------------------------------------------
# Form
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Exanima Save Manager'
$form.Size            = New-Object System.Drawing.Size(920, 400)
$form.MinimumSize     = New-Object System.Drawing.Size(600, 200)
$script:form.FormBorderStyle = 'FixedDialog'
$script:form.MaximizeBox = $false
$form.BackColor       = $clrBg
$form.ForeColor       = $clrText
$form.Font            = $fntUI
$form.StartPosition   = 'CenterScreen'

# ---------------------------------------------------------------------------
# Warning banner
# ---------------------------------------------------------------------------
$pnlWarn = New-Object System.Windows.Forms.Panel
$pnlWarn.Dock      = 'Top'
$pnlWarn.Height    = 36
$pnlWarn.BackColor = $clrWarnBg
$pnlWarn.Visible   = $false

$lblWarn = New-Object System.Windows.Forms.Label
$lblWarn.Dock      = 'Fill'
$lblWarn.TextAlign = 'MiddleCenter'
$lblWarn.Font      = $fntBold
$lblWarn.ForeColor = $clrWarnText
$lblWarn.Text      = 'Exanima is running.  Go to Main Menu or close the game before touching saves.  The game DELETES the active .rsg on death.'
$pnlWarn.Controls.Add($lblWarn)

# ---------------------------------------------------------------------------
# Status bar
# ---------------------------------------------------------------------------
$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Dock      = 'Bottom'
$pnlStatus.Height    = 28
$pnlStatus.BackColor = $clrPanel

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Dock      = 'Fill'
$lblStatus.TextAlign = 'MiddleLeft'
$lblStatus.ForeColor = $clrDim
$lblStatus.Padding   = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$lblStatus.Text      = 'Ready.'
$pnlStatus.Controls.Add($lblStatus)

# ---------------------------------------------------------------------------
# Main content
# ---------------------------------------------------------------------------
$pnlContent = New-Object System.Windows.Forms.Panel
$pnlContent.Dock      = 'Fill'
$pnlContent.Padding   = New-Object System.Windows.Forms.Padding(10, 8, 10, 6)
$pnlContent.BackColor = $clrBg

# Vertical split: saves left, backups right
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock             = 'Fill'
$split.Orientation      = 'Vertical'
$split.SplitterWidth    = 6
$split.SplitterDistance = 72
$split.BackColor        = $clrBg
$split.Panel1.BackColor = $clrBg
$split.Panel2.BackColor = $clrBg
$pnlContent.Controls.Add($split)

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
function Make-GroupBox([string]$title) {
    $gb = New-Object System.Windows.Forms.GroupBox
    $gb.Text      = $title
    $gb.Dock      = 'Fill'
    $gb.ForeColor = $script:clrAccent
    $gb.Font      = $script:fntHead
    $gb.BackColor = $script:clrBg
    $gb.Padding   = New-Object System.Windows.Forms.Padding(6, 4, 6, 6)
    return $gb
}

function Make-ListView {
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View          = 'Details'
    $lv.FullRowSelect = $true
    $lv.GridLines     = $false
    $lv.BackColor     = $script:clrPanel
    $lv.ForeColor     = $script:clrText
    $lv.BorderStyle   = 'None'
    $lv.MultiSelect   = $false
    $lv.Font          = $script:fntMono
    $lv.Dock          = 'Fill'
    $lv.HeaderStyle   = 'Nonclickable'
    return $lv
}

function Make-Button([string]$text, [bool]$primary, [int]$width) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text      = $text
    $btn.Width     = $width
    $btn.Height    = 27
    $btn.FlatStyle = 'Flat'
    if ($primary) {
        $btn.Font      = $script:fntBold
        $btn.BackColor = $script:clrAccent
        $btn.ForeColor = [System.Drawing.Color]::Black
        $btn.FlatAppearance.BorderSize          = 0
        $btn.FlatAppearance.MouseOverBackColor  = $script:clrAccentHi
    } else {
        $btn.Font      = $script:fntUI
        $btn.BackColor = $script:clrInput
        $btn.ForeColor = $script:clrText
        $btn.FlatAppearance.BorderSize          = 1
        $btn.FlatAppearance.BorderColor         = $script:clrBorder
    }
    return $btn
}

function Fit-LastCol([System.Windows.Forms.ListView]$lv) {
    if ($lv.Columns.Count -eq 0) { return }
    $used = 0
    for ($i = 0; $i -lt ($lv.Columns.Count - 1); $i++) { $used += $lv.Columns[$i].Width }
    $avail = $lv.ClientSize.Width - $used - 4
    if ($avail -gt 50) { $lv.Columns[$lv.Columns.Count - 1].Width = $avail }
}

function Set-Status([string]$msg, $color) {
    if (-not $color) { $color = $script:clrDim }
    $script:lblStatus.ForeColor = $color
    $script:lblStatus.Text      = $msg
}

function Get-AltColor([int]$index) {
    if ($index % 2 -eq 0) { return $script:clrPanel } else { return $script:clrPanelAlt }
}

# ---------------------------------------------------------------------------
# LEFT PANEL: action bar + Current Save Files
# ---------------------------------------------------------------------------

# Action bar above the saves list
$pnlActions = New-Object System.Windows.Forms.Panel
$pnlActions.Dock      = 'Bottom'
$pnlActions.Height    = 72
$pnlActions.BackColor = $clrBg
$pnlActions.Padding   = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

$lblLabelCap = New-Object System.Windows.Forms.Label
$lblLabelCap.Text      = 'Label:'
$lblLabelCap.AutoSize  = $true
$lblLabelCap.ForeColor = $clrDim
$lblLabelCap.Location  = New-Object System.Drawing.Point(2, 8)

$txtLabel = New-Object System.Windows.Forms.TextBox
$txtLabel.BackColor   = $clrInput
$txtLabel.ForeColor   = $clrText
$txtLabel.BorderStyle = 'FixedSingle'
$txtLabel.Location    = New-Object System.Drawing.Point(50, 5)
$txtLabel.Anchor      = 'Top,Left,Right'
$txtLabel.Size        = New-Object System.Drawing.Size(150, 24)

$btnBackup     = Make-Button 'Backup Selected' $true  130
$btnCheckpoint = Make-Button 'Make Checkpoint' $false 130

$btnBackup.Location     = New-Object System.Drawing.Point(2,  36)
$btnCheckpoint.Location = New-Object System.Drawing.Point(140, 36)

$pnlActions.Controls.AddRange(@($lblLabelCap, $txtLabel, $btnBackup, $btnCheckpoint))

# Saves GroupBox + ListView
$grpSaves = Make-GroupBox 'Current Save Files'
$grpSaves.Dock = 'Fill'

$lvSaves = Make-ListView
# Column order: Type, File, Modified, Size
$lvSaves.Columns.Add('Type',     100) | Out-Null
$lvSaves.Columns.Add('File',     100) | Out-Null
$lvSaves.Columns.Add('Modified', 120) | Out-Null
$lvSaves.Columns.Add('Size',      60) | Out-Null

$grpSaves.Controls.Add($lvSaves)
$grpSaves.Controls.Add($pnlActions)

$split.Panel1.Controls.Add($grpSaves)

# ---------------------------------------------------------------------------
# RIGHT PANEL: Backups list + action row
# ---------------------------------------------------------------------------
$grpBackups = Make-GroupBox 'Backups'
$split.Panel2.Controls.Add($grpBackups)

$lvBackups = Make-ListView
# Column order: Label, File, Type, Date
$lvBackups.Columns.Add('Label', 150) | Out-Null
$lvBackups.Columns.Add('File',  100) | Out-Null
$lvBackups.Columns.Add('Type',   55) | Out-Null
$lvBackups.Columns.Add('Date',  130) | Out-Null

$pnlBackupRow = New-Object System.Windows.Forms.Panel
$pnlBackupRow.Dock      = 'Bottom'
$pnlBackupRow.Height    = 42
$pnlBackupRow.BackColor = $clrBg

$btnRestore = Make-Button 'Restore Selected' $true  148
$btnDelete  = Make-Button 'Delete Backup'    $false 130

$btnRestore.Location = New-Object System.Drawing.Point(0,   7)
$btnDelete.Location  = New-Object System.Drawing.Point(156, 7)
$btnDelete.ForeColor = $clrRed
$btnDelete.FlatAppearance.BorderColor = $clrRed

$pnlBackupRow.Controls.AddRange(@($btnRestore, $btnDelete))
$grpBackups.Controls.Add($lvBackups)
$grpBackups.Controls.Add($pnlBackupRow)

# ---------------------------------------------------------------------------
# Assemble form (Fill first, then Bottom, then Top for correct dock order)
# ---------------------------------------------------------------------------
$form.Controls.Add($pnlContent)
$form.Controls.Add($pnlStatus)
$form.Controls.Add($pnlWarn)

# ---------------------------------------------------------------------------
# Populate saves list
# ---------------------------------------------------------------------------
function Refresh-Saves {
    $script:lvSaves.Items.Clear()
    $idx = 0

    foreach ($f in @(Get-CurrentSaves)) {
        $isArena = $f.Name -match '^Arena'
        $type    = if ($isArena) { 'Arena' } else { 'Dungeon' }
        $mod     = $f.LastWriteTime.ToString('MM-dd  HH:mm')
        $kb      = '{0:N1} KB' -f ($f.Length / 1KB)

        $item = New-Object System.Windows.Forms.ListViewItem($type)
        $item.SubItems.Add($f.Name) | Out-Null
        $item.SubItems.Add($mod)    | Out-Null
        $item.SubItems.Add($kb)     | Out-Null
        $item.Tag                    = $f
        $item.UseItemStyleForSubItems = $true
        $item.BackColor = Get-AltColor $idx
        $item.ForeColor = if ($isArena) { $script:clrArena } else { $script:clrText }
        $script:lvSaves.Items.Add($item) | Out-Null
        $idx++
    }

    foreach ($f in @(Get-CurrentCheckpoints)) {
        $isArena = $f.Name -match '^Arena'
        $type    = if ($isArena) { 'Arena' } else { 'Dungeon' }
        $mod     = $f.LastWriteTime.ToString('MM-dd  HH:mm')
        $kb      = '{0:N1} KB' -f ($f.Length / 1KB)

        $item = New-Object System.Windows.Forms.ListViewItem($type)
        $item.SubItems.Add($f.Name) | Out-Null
        $item.SubItems.Add($mod)    | Out-Null
        $item.SubItems.Add($kb)     | Out-Null
        $item.Tag                    = $f
        $item.UseItemStyleForSubItems = $true
        $item.BackColor = Get-AltColor $idx
        $item.ForeColor = $script:clrDim
        $script:lvSaves.Items.Add($item) | Out-Null
        $idx++
    }

    Fit-LastCol $script:lvSaves
}

# ---------------------------------------------------------------------------
# Populate backups list
# ---------------------------------------------------------------------------
function Refresh-Backups {
    $script:lvBackups.Items.Clear()
    $idx = 0

    foreach ($b in @(Get-Backups)) {
        $label = Parse-BackupLabel $b.Name
        $date  = Parse-BackupDate  $b.Name
        $type  = Get-BackupType    $b
        $files = @(Get-ChildItem $b.FullName -ErrorAction SilentlyContinue)
        $names = ($files | ForEach-Object { $_.Name }) -join ', '
        $displayLabel = if ($label) { $label } else { '(unlabeled)' }

        $item = New-Object System.Windows.Forms.ListViewItem($displayLabel)
        $item.SubItems.Add($names)  | Out-Null
        $item.SubItems.Add($type)   | Out-Null
        $item.SubItems.Add($date)   | Out-Null
        $item.Tag                    = $b
        $item.UseItemStyleForSubItems = $true
        $item.BackColor = Get-AltColor $idx
        $item.ForeColor = if ($type -eq 'Arena') { $script:clrArena } else { $script:clrText }
        $script:lvBackups.Items.Add($item) | Out-Null
        $idx++
    }

    foreach ($b in @(Get-ReloadBackups)) {
        $date  = Parse-BackupDate $b.Name
        $files = @(Get-ChildItem $b.FullName -ErrorAction SilentlyContinue)
        $names = ($files | ForEach-Object { $_.Name }) -join ', '

        $item = New-Object System.Windows.Forms.ListViewItem('[reload backup]')
        $item.SubItems.Add($names)  | Out-Null
        $item.SubItems.Add('Auto')  | Out-Null
        $item.SubItems.Add($date)   | Out-Null
        $item.Tag                    = $b
        $item.UseItemStyleForSubItems = $true
        $item.BackColor = Get-AltColor $idx
        $item.ForeColor = $script:clrDim
        $script:lvBackups.Items.Add($item) | Out-Null
        $idx++
    }

    Fit-LastCol $script:lvBackups
}

function Refresh-All {
    Refresh-Saves
    Refresh-Backups
    Set-SaveButtonStates
    Set-BackupButtonStates
}

# ---------------------------------------------------------------------------
# Grey out Make Checkpoint when an Arena save is selected
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Button active/dim helpers
# ---------------------------------------------------------------------------
function Set-SaveButtonStates {
    $sel = $script:lvSaves.SelectedItems
    if ($sel.Count -eq 0) {
        # Nothing selected - dim both
        $script:btnBackup.BackColor                        = $script:clrAccentDim
        $script:btnBackup.ForeColor                        = $script:clrDim
        $script:btnCheckpoint.BackColor                    = $script:clrInput
        $script:btnCheckpoint.ForeColor                    = $script:clrDim
        $script:btnCheckpoint.FlatAppearance.BorderColor   = $script:clrBorder
        return
    }
    $f = $sel[0].Tag
    $isRsg    = $f.Extension -eq '.rsg'
    $isDungeon = $f.Name -match '^Exanima'

    # Backup: active for any .rsg
    if ($isRsg) {
        $script:btnBackup.BackColor = $script:clrAccent
        $script:btnBackup.ForeColor = [System.Drawing.Color]::Black
    } else {
        $script:btnBackup.BackColor = $script:clrAccentDim
        $script:btnBackup.ForeColor = $script:clrDim
    }

    # Checkpoint: active only for Dungeon .rsg
    if ($isRsg -and $isDungeon) {
        $script:btnCheckpoint.BackColor                  = $script:clrInput
        $script:btnCheckpoint.ForeColor                  = $script:clrFire
        $script:btnCheckpoint.FlatAppearance.BorderColor = $script:clrBorder
        $script:btnCheckpoint.Enabled                    = $true
    } else {
        $script:btnCheckpoint.BackColor                  = $script:clrInput
        $script:btnCheckpoint.ForeColor                  = $script:clrDim
        $script:btnCheckpoint.FlatAppearance.BorderColor = $script:clrBorder
        $script:btnCheckpoint.Enabled                    = $false
    }
}

function Set-BackupButtonStates {
    $sel = $script:lvBackups.SelectedItems
    if ($sel.Count -eq 0) {
        $script:btnRestore.BackColor                     = $script:clrAccentDim
        $script:btnRestore.ForeColor                     = $script:clrDim
        $script:btnDelete.BackColor                      = $script:clrRedDim
        $script:btnDelete.ForeColor                      = $script:clrDim
        $script:btnDelete.FlatAppearance.BorderColor     = $script:clrRedDim
    } else {
        $script:btnRestore.BackColor                     = $script:clrAccent
        $script:btnRestore.ForeColor                     = [System.Drawing.Color]::Black
        $script:btnDelete.BackColor                      = $script:clrRed
        $script:btnDelete.ForeColor                      = [System.Drawing.Color]::Black
        $script:btnDelete.FlatAppearance.BorderColor     = $script:clrRed
    }
}

$lvSaves.Add_SelectedIndexChanged({   Set-SaveButtonStates })
$lvBackups.Add_SelectedIndexChanged({ Set-BackupButtonStates })

# ---------------------------------------------------------------------------
# BACKUP
# ---------------------------------------------------------------------------
$btnBackup.Add_Click({
    $sel = $script:lvSaves.SelectedItems
    if ($sel.Count -eq 0) {
        Set-Status 'Select a save file from the list.' $script:clrRed
        return
    }
    $f = $sel[0].Tag
    if ($f.Extension -ne '.rsg') {
        Set-Status 'Checkpoints (.rcp) are not backed up.  Select an .rsg save.' $script:clrRed
        return
    }

    $rawLabel   = ($script:txtLabel.Text.Trim()) -replace '[\\/:*?"<>|]', '_'
    $isArena    = $f.Name -match '^Arena'
    $prefix     = if ($isArena) { 'Arena_' } else { '' }
    $ts         = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $folderName = if ($rawLabel) { "${prefix}${ts}_${rawLabel}" } else { "${prefix}${ts}" }
    $dest       = Join-Path $script:BackupRoot $folderName

    try {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item -Path $f.FullName -Destination $dest -Force
        $script:txtLabel.Text = ''
        Refresh-All
        Set-Status "Backed up:  $($f.Name)   to   $folderName" $script:clrGreen
    } catch {
        Set-Status "Backup failed: $_" $script:clrRed
    }
})

# ---------------------------------------------------------------------------
# MAKE CHECKPOINT
# ---------------------------------------------------------------------------
$btnCheckpoint.Add_Click({
    $sel = $script:lvSaves.SelectedItems
    if ($sel.Count -eq 0) {
        Set-Status 'Select a Dungeon .rsg save to copy as a checkpoint.' $script:clrRed
        return
    }
    $f = $sel[0].Tag
    if ($f.Extension -ne '.rsg' -or $f.Name -notmatch '^Exanima') {
        Set-Status 'Checkpoints only apply to Dungeon (Exanima*.rsg) saves.' $script:clrRed
        return
    }

    $base     = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $destName = "$base.rcp"
    $destPath = Join-Path $script:SaveDir $destName

    $msg = "Copy  $($f.Name)  as checkpoint  $destName ?`n`nThe original .rsg save will not be modified."
    if (Test-Path $destPath) {
        $msg = "Overwrite existing checkpoint  $destName ?`n`nThe original $($f.Name) will not be modified."
    }

    if ([System.Windows.Forms.MessageBox]::Show($msg, 'Make Checkpoint', 'YesNo', 'Question') -ne 'Yes') { return }

    try {
        Copy-Item -Path $f.FullName -Destination $destPath -Force
        Refresh-All
        Set-Status "Checkpoint created: $destName" $script:clrGreen
    } catch {
        Set-Status "Failed: $_" $script:clrRed
    }
})

# ---------------------------------------------------------------------------
# RESTORE
# ---------------------------------------------------------------------------
$btnRestore.Add_Click({
    $sel = $script:lvBackups.SelectedItems
    if ($sel.Count -eq 0) {
        Set-Status 'Select a backup to restore.' $script:clrRed
        return
    }
    $b         = $sel[0].Tag
    $toRestore = @(Get-ChildItem -Path $b.FullName -ErrorAction SilentlyContinue)
    if ($toRestore.Count -eq 0) {
        Set-Status 'Backup folder is empty.' $script:clrRed
        return
    }

    $fileList = ($toRestore | ForEach-Object { $_.Name }) -join ', '
    if ([System.Windows.Forms.MessageBox]::Show(
        "Restore from backup:`n`n$($b.Name)`n`nFiles: $fileList`n`nCurrent .rsg saves will be replaced. A reload backup is created automatically first.",
        'Confirm Restore', 'YesNo', 'Warning'
    ) -ne 'Yes') { return }

    # Prune old reload backups
    @(Get-ReloadBackups) | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create reload backup containing only the files that are about to be overwritten.
    # Inherits Arena_ prefix if any of the files being restored are Arena saves.
    $willOverwrite = @($toRestore | Where-Object { Test-Path (Join-Path $script:SaveDir $_.Name) })
    if ($willOverwrite.Count -gt 0) {
        $hasArena   = [bool]($willOverwrite | Where-Object { $_.Name -match '^Arena' })
        $typePrefix = if ($hasArena) { 'Arena_' } else { '' }
        $safeDir    = Join-Path $script:BackupRoot ("${typePrefix}Reload_{0}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        New-Item -ItemType Directory -Path $safeDir -Force | Out-Null
        $willOverwrite | ForEach-Object {
            Copy-Item (Join-Path $script:SaveDir $_.Name) -Destination $safeDir -Force
        }
    }

    # Restore files
    $failed = $false
    foreach ($f in $toRestore) {
        try {
            Copy-Item -Path $f.FullName -Destination (Join-Path $script:SaveDir $f.Name) -Force
        } catch {
            $failed = $true
        }
    }

    Refresh-All
    if ($failed) {
        Set-Status 'Restore completed with errors. Some files may not have copied.' $script:clrRed
    } else {
        Set-Status "Restored: $fileList     Launch Exanima and hit Continue." $script:clrGreen
    }
})

# ---------------------------------------------------------------------------
# DELETE
# ---------------------------------------------------------------------------
$btnDelete.Add_Click({
    $sel = $script:lvBackups.SelectedItems
    if ($sel.Count -eq 0) {
        Set-Status 'Select a backup to delete.' $script:clrRed
        return
    }
    $b = $sel[0].Tag
    if ([System.Windows.Forms.MessageBox]::Show(
        "Permanently delete this backup?`n`n$($b.Name)",
        'Confirm Delete', 'YesNo', 'Warning'
    ) -ne 'Yes') { return }

    try {
        Remove-Item -Path $b.FullName -Recurse -Force
        Refresh-All
        Set-Status "Deleted: $($b.Name)" $script:clrGreen
    } catch {
        Set-Status "Delete failed: $_" $script:clrRed
    }
})

# ---------------------------------------------------------------------------
# Resize handlers
# ---------------------------------------------------------------------------
$lvSaves.Add_SizeChanged({   Fit-LastCol $script:lvSaves })
$lvBackups.Add_SizeChanged({ Fit-LastCol $script:lvBackups })

# ---------------------------------------------------------------------------
# Game running poll (every 2 seconds)
# ---------------------------------------------------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    $script:pnlWarn.Visible = [bool](Get-Process -Name 'Exanima' -ErrorAction SilentlyContinue)
})
$timer.Start()
$form.Add_FormClosing({ $script:timer.Stop() })

# ---------------------------------------------------------------------------
# Refresh on focus-return from another app (not on every click)
# ---------------------------------------------------------------------------
$script:wasDeactivated = $false
$form.Add_Deactivate({ $script:wasDeactivated = $true })
$form.Add_Activated({
    if ($script:wasDeactivated) {
        $script:wasDeactivated = $false
        Refresh-All
    }
})

# ---------------------------------------------------------------------------
# Entry guard
# ---------------------------------------------------------------------------
if (-not (Test-Path $SaveDir)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Save directory not found:`n$SaveDir`n`nLaunch Exanima at least once to create it.",
        'Exanima Save Manager', 'OK', 'Error'
    )
    exit 1
}
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
$form.Add_Shown({
	try {
        $v = 1
        $res = [Native.Dwm]::DwmSetWindowAttribute($script:form.Handle, 20, [ref]$v, 4)
        if ($res -ne 0) {
            [Native.Dwm]::DwmSetWindowAttribute($script:form.Handle, 19, [ref]$v, 4) | Out-Null
        }
        $script:form.Invalidate($true)
    } catch { }
    Refresh-All
    Set-SaveButtonStates
    Set-BackupButtonStates
})
[void]$form.ShowDialog()

$timer.Dispose()
$fntUI.Dispose()
$fntBold.Dispose()
$fntHead.Dispose()
$fntMono.Dispose()
$form.Dispose()