#Requires -Version 5.1
<#
.SYNOPSIS
    Exanima Save Manager - Backup and restore Exanima save files.

.DESCRIPTION
    Manages Arena and Dungeon save files located in %APPDATA%\Exanima.
    Supports named backups, selective Arena/Dungeon restore, and
    auto-safety-backup before any restore to prevent accidental loss.

    File types:
        Arena*.rsg    - Arena saved game state      [backed up]
        Exanima*.rsg  - Dungeon saved game state    [backed up]
        Arena*.rcp    - Arena checkpoint            [listed only, not backed up]
        Exanima*.rcp  - Dungeon checkpoint          [listed only, not backed up]

    Naming convention (enforced by the game):
        Files MUST follow the Arena### / Exanima### + extension pattern.
        The game uses the filename to identify save slots.
        Arbitrary names like "MyRun.rsg" will be ignored by the game.

.NOTES
    Always quit Exanima to the desktop BEFORE backing up.
    The game only flushes .rsg saves to disk on exit.
    For restores you can be at the main menu, then alt-tab here,
    restore, switch back and hit Continue.
#>

#Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$SaveDir    = Join-Path $env:APPDATA 'Exanima'
$BackupRoot = Join-Path $SaveDir 'SaveManager'

# Only .rsg files are backed up/restored - they are the saved game states.
# .rcp are checkpoints: same data format, but the game manages them separately.
# They do not expire and are not something we need to back up.
$SavePatterns       = 'Arena*.rsg', 'Exanima*.rsg'
$CheckpointPatterns = 'Arena*.rcp', 'Exanima*.rcp'

# ---------------------------------------------------------------------------
# Console helpers
# ---------------------------------------------------------------------------
function Write-Header {
    Clear-Host
    $border = '=' * 64

    Write-Host $border                              -ForegroundColor Cyan
    Write-Host '  EXANIMA SAVE MANAGER'  -ForegroundColor Cyan
    Write-Host $border                              -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  Save dir   : $SaveDir"    -ForegroundColor DarkGray
    Write-Host "  Backup dir : $BackupRoot" -ForegroundColor DarkGray
    Write-Host ''
}

function Write-ClosedWarning {
    Write-Host '  [!] Exanima must be CLOSED (or at Main Menu) before' -ForegroundColor Yellow
    Write-Host '      touching saves. The game only writes .rsg on exit.' -ForegroundColor DarkYellow
    Write-Host ''
}

function Pause-Menu {
    Write-Host ''
    Read-Host '  Press Enter to return to the menu'
}

# ---------------------------------------------------------------------------
# Save / checkpoint discovery
# ---------------------------------------------------------------------------
function Get-CurrentSaves {
    $found = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($pat in $SavePatterns) {
        Get-ChildItem -Path $SaveDir -Filter $pat -ErrorAction SilentlyContinue |
            ForEach-Object { $found.Add($_) }
    }
    return @($found | Sort-Object Name)
}

function Get-CurrentCheckpoints {
    $found = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($pat in $CheckpointPatterns) {
        Get-ChildItem -Path $SaveDir -Filter $pat -ErrorAction SilentlyContinue |
            ForEach-Object { $found.Add($_) }
    }
    return @($found | Sort-Object Name)
}

function Get-Backups {
    if (-not (Test-Path $BackupRoot)) { return @() }
    return @(Get-ChildItem -Path $BackupRoot -Directory |
        Where-Object { $_.Name -notmatch '^PRE-RESTORE_' } |
        Sort-Object Name -Descending)
}

function Get-SafetyBackups {
    if (-not (Test-Path $BackupRoot)) { return @() }
    return @(Get-ChildItem -Path $BackupRoot -Directory |
        Where-Object { $_.Name -match '^PRE-RESTORE_' } |
        Sort-Object Name -Descending)
}

# ---------------------------------------------------------------------------
# Display current saves and checkpoints (shown on main menu)
# ---------------------------------------------------------------------------
function Show-CurrentSaves {
    $saves  = @(Get-CurrentSaves)
    $ckpts  = @(Get-CurrentCheckpoints)
    $any    = ($saves.Count + $ckpts.Count) -gt 0

    if (-not $any) {
        Write-Host '  No save files detected in save directory.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host '  Active files:' -ForegroundColor White

    foreach ($f in $saves) {
        $kb   = [math]::Round($f.Length / 1KB, 1)
        $mod  = $f.LastWriteTime.ToString('yyyy-MM-dd  HH:mm:ss')
        $mode = if ($f.Name -match '^Arena') { 'Arena  ' } else { 'Dungeon' }
        Write-Host ('  [Save][{0}]  {1,-22}  {2,6} KB   {3}' -f $mode, $f.Name, $kb, $mod) -ForegroundColor Gray
    }

    foreach ($f in $ckpts) {
        $kb   = [math]::Round($f.Length / 1KB, 1)
        $mod  = $f.LastWriteTime.ToString('yyyy-MM-dd  HH:mm:ss')
        $mode = if ($f.Name -match '^Arena') { 'Arena  ' } else { 'Dungeon' }
        Write-Host ('  [Ckpt][{0}]  {1,-22}  {2,6} KB   {3}' -f $mode, $f.Name, $kb, $mod) -ForegroundColor DarkGray
    }

    if ($ckpts.Count -gt 0) {
        Write-Host '             Checkpoints are listed for reference only; they are not backed up.' -ForegroundColor DarkGray
    }

    Write-Host ''
}

# ---------------------------------------------------------------------------
# BACKUP  (saves only - .rsg)
# ---------------------------------------------------------------------------
function Invoke-Backup {
    Write-Header
    Write-ClosedWarning

    $saves = @(Get-CurrentSaves)
    if ($saves.Count -eq 0) {
        Write-Host '  No .rsg save files found. Nothing to back up.' -ForegroundColor Red
        Write-Host '  (Checkpoints are not backed up by this tool.)' -ForegroundColor DarkGray
        Pause-Menu
        return
    }

    Write-Host '  Select a save to back up:' -ForegroundColor White
    Write-Host ''
    for ($i = 0; $i -lt $saves.Count; $i++) {
        $f    = $saves[$i]
        $kb   = [math]::Round($f.Length / 1KB, 1)
        $mod  = $f.LastWriteTime.ToString('yyyy-MM-dd  HH:mm:ss')
        $mode = if ($f.Name -match '^Arena') { 'Arena  ' } else { 'Dungeon' }
        Write-Host ('  [{0,2}]  [{1}]  {2,-22}  {3,6} KB   {4}' -f ($i + 1), $mode, $f.Name, $kb, $mod) -ForegroundColor Yellow
    }
    Write-Host '  [  0]  Cancel' -ForegroundColor DarkGray
    Write-Host ''

    $raw = Read-Host '  Select'
    if ($raw -notmatch '^\d+$') { return }
    $idx = [int]$raw
    if ($idx -eq 0) { return }
    if ($idx -lt 1 -or $idx -gt $saves.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        Pause-Menu
        return
    }

    $selected = $saves[$idx - 1]

    Write-Host ''
    Write-Host '  Enter a label for this backup (optional, Enter to skip):' -ForegroundColor White
    $raw   = (Read-Host '  Label').Trim()
    $label = $raw -replace '[\\/:*?"<>|]', '_'

    $ts         = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $folderName = if ($label) { "${ts}_${label}" } else { $ts }
    $dest       = Join-Path $BackupRoot $folderName

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path $selected.FullName -Destination $dest -Force

    Write-Host ''
    Write-Host "  Backed up : $($selected.Name)  [Saved Game]" -ForegroundColor Green
    Write-Host "  Saved to  : $dest"                            -ForegroundColor Cyan
    Pause-Menu
}

# ---------------------------------------------------------------------------
# RESTORE
# ---------------------------------------------------------------------------
function Invoke-Restore {
    Write-Header
    Write-ClosedWarning

    $backups = @(Get-Backups)
    if ($backups.Count -eq 0) {
        Write-Host '  No backups found. Create one first.' -ForegroundColor Red
        Pause-Menu
        return
    }

    Write-Host '  Available backups  (newest first):' -ForegroundColor White
    Write-Host ''
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b     = $backups[$i]
        $files = Get-ChildItem -Path $b.FullName -ErrorAction SilentlyContinue
        $names = ($files | ForEach-Object { $_.Name }) -join '  '
        Write-Host ('  [{0,2}]  {1}' -f ($i + 1), $b.Name) -ForegroundColor Yellow
        Write-Host ('         {0}'   -f $names)              -ForegroundColor DarkGray
        Write-Host ''
    }
    Write-Host '  [  0]  Cancel' -ForegroundColor DarkGray
    Write-Host ''

    $raw = Read-Host '  Select backup number'
    if ($raw -notmatch '^\d+$') { return }
    $idx = [int]$raw
    if ($idx -eq 0) { return }
    if ($idx -lt 1 -or $idx -gt $backups.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        Pause-Menu
        return
    }

    $selected    = $backups[$idx - 1]
    $backupFiles = @(Get-ChildItem -Path $selected.FullName -ErrorAction SilentlyContinue)

    Write-Host ''
    Write-Host "  Selected : $($selected.Name)" -ForegroundColor Cyan
    Write-Host '  Contents :' -ForegroundColor White
    foreach ($f in $backupFiles) {
        Write-Host "    $($f.Name)  [Saved Game]" -ForegroundColor Gray
    }
    Write-Host ''

    Write-Host '  Restore scope:' -ForegroundColor White
    Write-Host '  [1]  All saves from this backup'  -ForegroundColor White
    Write-Host '  [2]  Arena saves only'             -ForegroundColor White
    Write-Host '  [3]  Dungeon saves only'           -ForegroundColor White
    Write-Host '  [0]  Cancel'                       -ForegroundColor DarkGray
    Write-Host ''
    $scope = (Read-Host '  Choice').Trim()

    $toRestore = @(switch ($scope) {
        '1' { $backupFiles }
        '2' { $backupFiles | Where-Object { $_.Name -match '^Arena' } }
        '3' { $backupFiles | Where-Object { $_.Name -match '^Exanima' } }
        '0' { return }
        default {
            Write-Host '  Invalid choice.' -ForegroundColor Red
            Pause-Menu
            return
        }
    })

    if (-not $toRestore -or $toRestore.Count -eq 0) {
        Write-Host '  No matching files in this backup for that scope.' -ForegroundColor Red
        Pause-Menu
        return
    }

    Write-Host ''
    Write-Host '  Files that will be OVERWRITTEN in your save directory:' -ForegroundColor Yellow
    foreach ($f in $toRestore) { Write-Host "    $($f.Name)" -ForegroundColor Gray }
    Write-Host ''
    Write-Host '  Confirm restore? (Y / N)' -ForegroundColor Yellow
    $confirm = (Read-Host '  ').Trim()
    if ($confirm -notmatch '^[Yy]') {
        Write-Host '  Restore cancelled.' -ForegroundColor DarkGray
        Pause-Menu
        return
    }

    # Auto safety-backup of current .rsg saves before overwriting
    $current = @(Get-CurrentSaves)
    if ($current.Count -gt 0) {
        $safeDir = Join-Path $BackupRoot ("PRE-RESTORE_{0}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        New-Item -ItemType Directory -Path $safeDir -Force | Out-Null
        foreach ($f in $current) {
            Copy-Item -Path $f.FullName -Destination $safeDir -Force
        }
        Write-Host ''
        Write-Host '  Safety backup of current saves created:' -ForegroundColor DarkGray
        Write-Host "  $safeDir"                                -ForegroundColor DarkGray
    }

    Write-Host ''
    foreach ($f in $toRestore) {
        $target = Join-Path $SaveDir $f.Name
        Copy-Item -Path $f.FullName -Destination $target -Force
        Write-Host "  Restored  : $($f.Name)  [Saved Game]" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  Restore complete.' -ForegroundColor Green
    Write-Host '  Switch back to Exanima and hit Continue (or launch the game).' -ForegroundColor Cyan
    Pause-Menu
}

# ---------------------------------------------------------------------------
# MAKE SAVE INTO CHECKPOINT
# Copies a .rsg saved game to a .rcp checkpoint file (same base name).
# The original .rsg is left untouched.
# Extension is the only difference the game cares about.
# ---------------------------------------------------------------------------
function Invoke-MakeCheckpoint {
    Write-Header
    Write-ClosedWarning

    $saves = @(Get-CurrentSaves)
    if ($saves.Count -eq 0) {
        Write-Host '  No .rsg save files found. Nothing to promote.' -ForegroundColor Red
        Pause-Menu
        return
    }

    Write-Host '  Select a save to copy as checkpoint (.rcp):' -ForegroundColor White
    Write-Host ''
    for ($i = 0; $i -lt $saves.Count; $i++) {
        $f    = $saves[$i]
        $kb   = [math]::Round($f.Length / 1KB, 1)
        $mod  = $f.LastWriteTime.ToString('yyyy-MM-dd  HH:mm:ss')
        $mode = if ($f.Name -match '^Arena') { 'Arena  ' } else { 'Dungeon' }
        Write-Host ('  [{0,2}]  [{1}]  {2,-22}  {3,6} KB   {4}' -f ($i + 1), $mode, $f.Name, $kb, $mod) -ForegroundColor Yellow
    }
    Write-Host '  [  0]  Cancel' -ForegroundColor DarkGray
    Write-Host ''

    $raw = Read-Host '  Select'
    if ($raw -notmatch '^\d+$') { return }
    $idx = [int]$raw
    if ($idx -eq 0) { return }
    if ($idx -lt 1 -or $idx -gt $saves.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        Pause-Menu
        return
    }

    $src      = $saves[$idx - 1]
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($src.Name)
    $destName = "$baseName.rcp"
    $destPath = Join-Path $SaveDir $destName

    Write-Host ''
    Write-Host "  Source      : $($src.Name)  [Saved Game]"  -ForegroundColor Gray
    Write-Host "  Will create : $destName  [Checkpoint]"      -ForegroundColor Cyan

    if (Test-Path $destPath) {
        $existing = Get-Item $destPath
        $mod      = $existing.LastWriteTime.ToString('yyyy-MM-dd  HH:mm:ss')
        Write-Host ''
        Write-Host "  [!] A checkpoint already exists for this slot:" -ForegroundColor Yellow
        Write-Host ("      {0}   last modified {1}" -f $destName, $mod) -ForegroundColor Yellow
        Write-Host '      It will be overwritten.' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '  Confirm? (Y / N)' -ForegroundColor White
    $confirm = (Read-Host '  ').Trim()
    if ($confirm -notmatch '^[Yy]') {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        Pause-Menu
        return
    }

    Copy-Item -Path $src.FullName -Destination $destPath -Force
    Write-Host ''
    Write-Host "  Done. $destName is now your checkpoint for slot $baseName." -ForegroundColor Green
    Write-Host '  The original .rsg save is unchanged.'                        -ForegroundColor DarkGray
    Pause-Menu
}

# ---------------------------------------------------------------------------
# DELETE BACKUP
# ---------------------------------------------------------------------------
function Invoke-DeleteBackup {
    Write-Header

    $all = @(@(Get-Backups) + @(Get-SafetyBackups)) | Sort-Object Name -Descending

    if ($all.Count -eq 0) {
        Write-Host '  No backups found.' -ForegroundColor Red
        Pause-Menu
        return
    }

    Write-Host '  Select a backup to permanently DELETE:' -ForegroundColor White
    Write-Host ''
    for ($i = 0; $i -lt $all.Count; $i++) {
        $tag = if ($all[$i].Name -match '^PRE-RESTORE_') { '[auto]  ' } else { '        ' }
        Write-Host ('  [{0,2}]  {1}{2}' -f ($i + 1), $tag, $all[$i].Name) -ForegroundColor Yellow
    }
    Write-Host '  [  0]  Cancel' -ForegroundColor DarkGray
    Write-Host ''

    $raw = Read-Host '  Select'
    if ($raw -notmatch '^\d+$') { return }
    $idx = [int]$raw
    if ($idx -eq 0) { return }
    if ($idx -lt 1 -or $idx -gt $all.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        Pause-Menu
        return
    }

    $target = $all[$idx - 1]
    Write-Host ''
    Write-Host ("  Permanently delete '{0}'? (Y / N)" -f $target.Name) -ForegroundColor Yellow
    $confirm = (Read-Host '  ').Trim()
    if ($confirm -notmatch '^[Yy]') {
        Write-Host '  Deletion cancelled.' -ForegroundColor DarkGray
        Pause-Menu
        return
    }

    Remove-Item -Path $target.FullName -Recurse -Force
    Write-Host "  Deleted: $($target.Name)" -ForegroundColor Green
    Pause-Menu
}

# ---------------------------------------------------------------------------
# LIST ALL BACKUPS
# ---------------------------------------------------------------------------
function Invoke-ListBackups {
    Write-Header

    $reg  = @(Get-Backups)
    $safe = @(Get-SafetyBackups)

    if ($reg.Count -eq 0 -and $safe.Count -eq 0) {
        Write-Host '  No backups found.' -ForegroundColor DarkGray
        Pause-Menu
        return
    }

    if ($reg.Count -gt 0) {
        Write-Host '  Named backups:' -ForegroundColor White
        Write-Host ''
        foreach ($b in $reg) {
            $files = Get-ChildItem -Path $b.FullName -ErrorAction SilentlyContinue
            $names = ($files | ForEach-Object { $_.Name }) -join '  '
            Write-Host "  $($b.Name)"  -ForegroundColor Yellow
            Write-Host "    $names"    -ForegroundColor DarkGray
            Write-Host ''
        }
    }

    if ($safe.Count -gt 0) {
        Write-Host '  Auto safety backups (created before each restore):' -ForegroundColor White
        Write-Host ''
        foreach ($b in $safe) {
            $files = Get-ChildItem -Path $b.FullName -ErrorAction SilentlyContinue
            $names = ($files | ForEach-Object { $_.Name }) -join '  '
            Write-Host "  $($b.Name)"  -ForegroundColor DarkGray
            Write-Host "    $names"    -ForegroundColor DarkGray
            Write-Host ''
        }
    }

    Pause-Menu
}

# ---------------------------------------------------------------------------
# Entry guard
# ---------------------------------------------------------------------------
if (-not (Test-Path $SaveDir)) {
    Write-Host "ERROR: Save directory not found:" -ForegroundColor Red
    Write-Host "  $SaveDir"                        -ForegroundColor Red
    Write-Host ''
    Write-Host 'Launch Exanima at least once so the folder is created, then re-run.' -ForegroundColor Yellow
    exit 1
}

New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while ($true) {
    Write-Header
    Show-CurrentSaves

    Write-Host '  ==> MENU <=='                              -ForegroundColor Magenta
    Write-Host ''
    Write-Host -NoNewline '  [1]  ' -ForegroundColor Green
    Write-Host 'Backup a save'                               -ForegroundColor Cyan
    Write-Host -NoNewline '  [2]  ' -ForegroundColor DarkGreen
    Write-Host 'Restore a backup'                            -ForegroundColor DarkCyan
    Write-Host -NoNewline '  [3]  ' -ForegroundColor Green
    Write-Host 'List all backups'                            -ForegroundColor Cyan
    Write-Host -NoNewline '  [4]  ' -ForegroundColor DarkGreen
    Write-Host 'Delete a backup'                             -ForegroundColor DarkCyan
    Write-Host -NoNewline '  [5]  ' -ForegroundColor Green
    Write-Host 'Make save into checkpoint (.rcp)'            -ForegroundColor Cyan
    Write-Host -NoNewline '  [Q]  ' -ForegroundColor DarkGreen
    Write-Host 'Quit'                                        -ForegroundColor DarkCyan
    Write-Host ''

    $choice = (Read-Host '  >').Trim().ToUpper()

    switch ($choice) {
        '1'     { Invoke-Backup }
        '2'     { Invoke-Restore }
        '3'     { Invoke-ListBackups }
        '4'     { Invoke-DeleteBackup }
        '5'     { Invoke-MakeCheckpoint }
        'Q'     { Clear-Host; exit 0 }
        default { }
    }
}