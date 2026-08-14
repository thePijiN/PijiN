param(
    [switch]$TestMode,
    [string]$ScreenshotPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:UpdatingUi = $false
$script:SelectedPitches = New-Object 'System.Collections.Generic.HashSet[int]'
$script:OpenStrings = @(4, 11, 7, 2, 9, 4, 11)
$script:HasOptionalString = $false
$script:OptionalStringWasConfigured = $false
$script:ShowInlays = $true
$script:ShowIntervals = $false
$script:RootPitch = 0
$script:UseSharps = $false
$script:SaveConfigEnabled = $false
$script:SuppressSaveConfirmation = $false
$script:CurrentTuningName = 'E standard'
$script:PitchButtons = @()
$script:OpenCombos = @()
$script:StringLabels = @()
$script:FretCells = @{}

$localAppDataPath = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($localAppDataPath)) {
    $localAppDataPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
}
$script:ConfigPath = if ($TestMode) {
    Join-Path ([System.IO.Path]::GetTempPath()) "FretVis-test-$PID.txt"
}
else {
    Join-Path $localAppDataPath 'PijiN\FretVis.txt'
}
if ($TestMode -and [System.IO.File]::Exists($script:ConfigPath)) {
    [System.IO.File]::Delete($script:ConfigPath)
}

$script:FlatNames = @('C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B')
$script:SharpNames = @('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B')
$script:IntervalLabels = @('R', 'b2', '2', 'b3', '3', '4', 'b5', '5', 'b6', '6', 'b7', '7')

$script:TuningPresets = [ordered]@{
    'E standard' = @{ Pitches = @(4, 11, 7, 2, 9, 4, 11); Notes = 'E A D G B E' }
    'Eb standard' = @{ Pitches = @(3, 10, 6, 1, 8, 3, 10); Notes = 'Eb Ab Db Gb Bb Eb' }
    'D standard' = @{ Pitches = @(2, 9, 5, 0, 7, 2, 9); Notes = 'D G C F A D' }
    'C# standard' = @{ Pitches = @(1, 8, 4, 11, 6, 1, 8); Notes = 'C# F# B E G# C#' }
    'C standard' = @{ Pitches = @(0, 7, 3, 10, 5, 0, 7); Notes = 'C F Bb Eb G C' }
    'Drop D' = @{ Pitches = @(4, 11, 7, 2, 9, 2, 9); Notes = 'D A D G B E' }
    'Drop C#' = @{ Pitches = @(3, 10, 6, 1, 8, 1, 8); Notes = 'C# G# C# F# A# D#' }
    'Drop C' = @{ Pitches = @(2, 9, 5, 0, 7, 0, 7); Notes = 'C G C F A D' }
    'Drop B' = @{ Pitches = @(1, 8, 4, 11, 6, 11, 6); Notes = 'B F# B E G# C#' }
    'Drop A (7-string)' = @{ Pitches = @(4, 11, 7, 2, 9, 4, 9); Notes = 'A E A D G B E' }
    'DADGAD' = @{ Pitches = @(2, 9, 7, 2, 9, 2, 9); Notes = 'D A D G A D' }
    'Open D' = @{ Pitches = @(2, 9, 6, 2, 9, 2, 9); Notes = 'D A D F# A D' }
    'Open G' = @{ Pitches = @(2, 11, 7, 2, 7, 2, 7); Notes = 'D G D G B D' }
    'Open E' = @{ Pitches = @(4, 11, 8, 4, 11, 4, 11); Notes = 'E B E G# B E' }
}

$script:RootPitches = @{
    'C' = 0
    'C#' = 1
    'Db' = 1
    'D' = 2
    'D#' = 3
    'Eb' = 3
    'E' = 4
    'Fb' = 4
    'E#' = 5
    'F' = 5
    'F#' = 6
    'Gb' = 6
    'G' = 7
    'G#' = 8
    'Ab' = 8
    'A' = 9
    'A#' = 10
    'Bb' = 10
    'B' = 11
    'Cb' = 11
    'B#' = 0
}

$script:ScaleIntervals = [ordered]@{
    'Major' = @(0, 2, 4, 5, 7, 9, 11)
    'Minor' = @(0, 2, 3, 5, 7, 8, 10)
    'Harmonic Minor' = @(0, 2, 3, 5, 7, 8, 11)
    'Ionian' = @(0, 2, 4, 5, 7, 9, 11)
    'Dorian' = @(0, 2, 3, 5, 7, 9, 10)
    'Phrygian' = @(0, 1, 3, 5, 7, 8, 10)
    'Lydian' = @(0, 2, 4, 6, 7, 9, 11)
    'Mixolydian' = @(0, 2, 4, 5, 7, 9, 10)
    'Aeolian' = @(0, 2, 3, 5, 7, 8, 10)
    'Locrian' = @(0, 1, 3, 5, 6, 8, 10)
    'Major Pentatonic' = @(0, 2, 4, 7, 9)
    'Minor Pentatonic' = @(0, 3, 5, 7, 10)
    'Major Blues' = @(0, 2, 3, 4, 7, 9)
    'Minor Blues' = @(0, 3, 5, 6, 7, 10)
    'Whole Tone' = @(0, 2, 4, 6, 8, 10)
    'Diminished W-H' = @(0, 2, 3, 5, 6, 8, 9, 11)
    'Diminished H-W' = @(0, 1, 3, 4, 6, 7, 9, 10)
    'Chromatic' = @(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
}

$majorRoots = @('C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B', 'C#', 'Gb', 'Cb')
$minorRoots = @('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B', 'Eb', 'Ab', 'A#')
$standardRoots = @('C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B')

$script:ScaleRoots = [ordered]@{
    'Major' = $majorRoots
    'Minor' = $minorRoots
    'Harmonic Minor' = $minorRoots
    'Ionian' = $majorRoots
    'Dorian' = @('C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B', 'Db', 'D#', 'Ab')
    'Phrygian' = @('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', 'Eb', 'E#', 'Bb')
    'Lydian' = @('C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B', 'Cb', 'Fb', 'F#')
    'Mixolydian' = @('C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B', 'Db', 'Gb', 'G#')
    'Aeolian' = $minorRoots
    'Locrian' = @('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', 'E#', 'Bb', 'B#')
    'Major Pentatonic' = $majorRoots
    'Minor Pentatonic' = $minorRoots
    'Major Blues' = $majorRoots
    'Minor Blues' = $minorRoots
    'Whole Tone' = $standardRoots
    'Diminished W-H' = $standardRoots
    'Diminished H-W' = $standardRoots
    'Chromatic' = $standardRoots
}

$script:WindowBack = [System.Drawing.Color]::FromArgb(4, 5, 7)
$script:PanelBack = [System.Drawing.Color]::FromArgb(21, 23, 28)
$script:ControlBack = [System.Drawing.Color]::FromArgb(31, 34, 40)
$script:EdgeColor = [System.Drawing.Color]::FromArgb(69, 73, 83)
$script:TextColor = [System.Drawing.Color]::FromArgb(235, 236, 239)
$script:MutedColor = [System.Drawing.Color]::FromArgb(171, 176, 188)
$script:DarkText = [System.Drawing.Color]::FromArgb(10, 12, 15)

$script:CellColors = @(
    [System.Drawing.Color]::FromArgb(54, 57, 64),
    [System.Drawing.Color]::FromArgb(45, 48, 55),
    [System.Drawing.Color]::FromArgb(34, 37, 43),
    [System.Drawing.Color]::FromArgb(42, 45, 52)
)

$script:PitchColors = @(
    [System.Drawing.Color]::FromArgb(211, 58, 62),
    [System.Drawing.Color]::FromArgb(207, 104, 47),
    [System.Drawing.Color]::FromArgb(203, 164, 42),
    [System.Drawing.Color]::FromArgb(153, 190, 42),
    [System.Drawing.Color]::FromArgb(96, 178, 57),
    [System.Drawing.Color]::FromArgb(49, 161, 75),
    [System.Drawing.Color]::FromArgb(43, 157, 126),
    [System.Drawing.Color]::FromArgb(42, 144, 162),
    [System.Drawing.Color]::FromArgb(48, 109, 173),
    [System.Drawing.Color]::FromArgb(80, 77, 182),
    [System.Drawing.Color]::FromArgb(137, 66, 174),
    [System.Drawing.Color]::FromArgb(186, 58, 121)
)

function Mix-Color {
    param(
        [System.Drawing.Color]$Foreground,
        [System.Drawing.Color]$Background,
        [double]$Weight
    )

    $red = [int][Math]::Round($Background.R + (($Foreground.R - $Background.R) * $Weight))
    $green = [int][Math]::Round($Background.G + (($Foreground.G - $Background.G) * $Weight))
    $blue = [int][Math]::Round($Background.B + (($Foreground.B - $Background.B) * $Weight))
    return [System.Drawing.Color]::FromArgb($red, $green, $blue)
}

function Get-ContrastColor {
    param([System.Drawing.Color]$Color)

    $luminance = (0.2126 * $Color.R) + (0.7152 * $Color.G) + (0.0722 * $Color.B)
    if ($luminance -gt 142) {
        return $script:DarkText
    }
    return $script:TextColor
}

function Set-DarkComboBox {
    param([System.Windows.Forms.ComboBox]$ComboBox)

    $ComboBox.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $ComboBox.ItemHeight = 21
    $ComboBox.Add_DrawItem({
        param($sender, $eventArgs)

        if ($eventArgs.Index -lt 0) {
            return
        }

        $background = $sender.BackColor
        if (($eventArgs.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected) {
            $background = Mix-Color -Foreground $script:EdgeColor -Background $sender.BackColor -Weight 0.55
        }

        $brush = New-Object System.Drawing.SolidBrush($background)
        $eventArgs.Graphics.FillRectangle($brush, $eventArgs.Bounds)
        $brush.Dispose()

        $textBounds = New-Object System.Drawing.Rectangle(
            ($eventArgs.Bounds.X + 6),
            $eventArgs.Bounds.Y,
            [Math]::Max(1, ($eventArgs.Bounds.Width - 6)),
            $eventArgs.Bounds.Height
        )
        $flags = [System.Windows.Forms.TextFormatFlags]::Left -bor
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
            [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText(
            $eventArgs.Graphics,
            [string]$sender.Items[$eventArgs.Index],
            $sender.Font,
            $textBounds,
            $sender.ForeColor,
            $flags
        )
    })
}

function Get-ConfigRecord {
    if ($null -ne $script:AccidentalCombo) {
        $script:UseSharps = $script:AccidentalCombo.SelectedIndex -eq 1
    }

    $selected = @($script:SelectedPitches | Sort-Object) -join ','
    $openStrings = @($script:OpenStrings | ForEach-Object { [int]$_ }) -join ','
    $saveValue = if ($script:SaveConfigEnabled) { 1 } else { 0 }
    $inlayValue = if ($script:ShowInlays) { 1 } else { 0 }
    $intervalValue = if ($script:ShowIntervals) { 1 } else { 0 }
    $accidentalValue = if ($script:UseSharps) { 1 } else { 0 }
    $stringValue = if ($script:HasOptionalString) { 1 } else { 0 }
    return "s=$saveValue|i=$inlayValue|v=$intervalValue|r=$($script:RootPitch)|a=$accidentalValue|x=$stringValue|t=$($script:CurrentTuningName)|o=$openStrings|n=$selected"
}

function Import-SavedConfig {
    if (-not [System.IO.File]::Exists($script:ConfigPath)) {
        return
    }

    try {
        $record = [System.IO.File]::ReadAllText($script:ConfigPath).Trim()
        $fields = @{}
        foreach ($part in ($record -split '\|')) {
            $separator = $part.IndexOf('=')
            if ($separator -le 0) {
                continue
            }
            $fields[$part.Substring(0, $separator)] = $part.Substring($separator + 1)
        }

        if ($fields.ContainsKey('s') -and $fields.s -in @('0', '1')) {
            $script:SaveConfigEnabled = $fields.s -eq '1'
        }
        if ($fields.ContainsKey('i') -and $fields.i -in @('0', '1')) {
            $script:ShowInlays = $fields.i -eq '1'
        }
        if ($fields.ContainsKey('v') -and $fields.v -in @('0', '1')) {
            $script:ShowIntervals = $fields.v -eq '1'
        }
        if ($fields.ContainsKey('r')) {
            $parsedRoot = 0
            if ([int]::TryParse($fields.r, [ref]$parsedRoot) -and $parsedRoot -ge 0 -and $parsedRoot -le 11) {
                $script:RootPitch = $parsedRoot
            }
        }
        if ($fields.ContainsKey('a') -and $fields.a -in @('0', '1')) {
            $script:UseSharps = $fields.a -eq '1'
        }
        if ($fields.ContainsKey('x') -and $fields.x -in @('0', '1')) {
            $script:HasOptionalString = $fields.x -eq '1'
        }

        $savedOpenStrings = $null
        if ($fields.ContainsKey('o')) {
            $pitchValues = @($fields.o -split ',')
            if ($pitchValues.Count -eq 7) {
                $validPitches = @()
                foreach ($pitchValue in $pitchValues) {
                    $parsedPitch = 0
                    if (-not [int]::TryParse($pitchValue, [ref]$parsedPitch) -or $parsedPitch -lt 0 -or $parsedPitch -gt 11) {
                        $validPitches = @()
                        break
                    }
                    $validPitches += $parsedPitch
                }
                if ($validPitches.Count -eq 7) {
                    $savedOpenStrings = $validPitches
                }
            }
        }

        if ($fields.ContainsKey('t')) {
            $savedTuning = [string]$fields.t
            if ($script:TuningPresets.Contains($savedTuning)) {
                $script:CurrentTuningName = $savedTuning
                $script:OpenStrings = if ($null -ne $savedOpenStrings) {
                    @($savedOpenStrings)
                }
                else {
                    @($script:TuningPresets[$savedTuning].Pitches | ForEach-Object { [int]$_ })
                }
            }
            elseif ($savedTuning -eq 'Custom' -and $null -ne $savedOpenStrings) {
                $script:CurrentTuningName = 'Custom'
                $script:OpenStrings = @($savedOpenStrings)
            }
        }
        elseif ($null -ne $savedOpenStrings) {
            $script:CurrentTuningName = 'Custom'
            $script:OpenStrings = @($savedOpenStrings)
        }
        if ($null -ne $savedOpenStrings) {
            $script:OptionalStringWasConfigured = $true
        }

        if ($fields.ContainsKey('n')) {
            $savedNotes = @()
            $notesAreValid = $true
            if (-not [string]::IsNullOrWhiteSpace($fields.n)) {
                foreach ($noteValue in ($fields.n -split ',')) {
                    $parsedNote = 0
                    if (-not [int]::TryParse($noteValue, [ref]$parsedNote) -or $parsedNote -lt 0 -or $parsedNote -gt 11) {
                        $notesAreValid = $false
                        break
                    }
                    $savedNotes += $parsedNote
                }
            }
            if ($notesAreValid) {
                $script:SelectedPitches.Clear()
                foreach ($savedNote in $savedNotes) {
                    [void]$script:SelectedPitches.Add($savedNote)
                }
            }
        }
    }
    catch {
        $script:SaveConfigEnabled = $false
    }
}

function Update-PurgeButtonVisibility {
    if ($null -eq $script:PurgeSaveButton -or $null -eq $script:KeyboardHeader) {
        return
    }

    $configExists = [System.IO.File]::Exists($script:ConfigPath)
    $script:PurgeSaveButton.Visible = $configExists
    $script:KeyboardHeader.ColumnStyles[4].Width = if ($configExists) { 78 } else { 0 }
}

function Set-SaveCheckboxState {
    param([bool]$Enabled)

    $script:SaveConfigEnabled = $Enabled
    if ($null -ne $script:SaveCheckbox -and $script:SaveCheckbox.Checked -ne $Enabled) {
        $wasUpdatingUi = $script:UpdatingUi
        $script:UpdatingUi = $true
        $script:SaveCheckbox.Checked = $Enabled
        $script:UpdatingUi = $wasUpdatingUi
    }
}

function Show-ConfigWriteError {
    param([string]$Message)

    if ($TestMode) {
        return
    }
    [void][System.Windows.Forms.MessageBox]::Show(
        $script:Form,
        $Message,
        'FretVis config',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Confirm-ConfigCreation {
    if ($script:SuppressSaveConfirmation) {
        return $true
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        $script:Form,
        "Save config to $($script:ConfigPath) ?",
        'Save config',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

function Write-SavedConfig {
    try {
        $configDirectory = [System.IO.Path]::GetDirectoryName($script:ConfigPath)
        if (-not [System.IO.Directory]::Exists($configDirectory)) {
            [void][System.IO.Directory]::CreateDirectory($configDirectory)
        }
        [System.IO.File]::WriteAllText($script:ConfigPath, (Get-ConfigRecord))
        Update-PurgeButtonVisibility
        return $true
    }
    catch {
        Show-ConfigWriteError -Message "Could not save config to $($script:ConfigPath).`r`n`r`n$($_.Exception.Message)"
        return $false
    }
}

function Save-ConfigIfEnabled {
    if (-not $script:SaveConfigEnabled) {
        return
    }

    if (-not [System.IO.File]::Exists($script:ConfigPath) -and -not (Confirm-ConfigCreation)) {
        Set-SaveCheckboxState -Enabled $false
        return
    }
    if (-not (Write-SavedConfig)) {
        Set-SaveCheckboxState -Enabled $false
    }
}

function Set-ConfigSaving {
    param([bool]$Enabled)

    if ($Enabled) {
        if (-not [System.IO.File]::Exists($script:ConfigPath) -and -not (Confirm-ConfigCreation)) {
            Set-SaveCheckboxState -Enabled $false
            return
        }
        Set-SaveCheckboxState -Enabled $true
        if (-not (Write-SavedConfig)) {
            Set-SaveCheckboxState -Enabled $false
        }
        return
    }

    Set-SaveCheckboxState -Enabled $false
    if ([System.IO.File]::Exists($script:ConfigPath)) {
        [void](Write-SavedConfig)
    }
}

function Purge-SavedConfig {
    try {
        if ([System.IO.File]::Exists($script:ConfigPath)) {
            [System.IO.File]::Delete($script:ConfigPath)
        }
    }
    catch {
        Show-ConfigWriteError -Message "Could not delete config at $($script:ConfigPath).`r`n`r`n$($_.Exception.Message)"
        return
    }

    Set-SaveCheckboxState -Enabled $false
    Update-PurgeButtonVisibility
}

Import-SavedConfig

function Get-NoteNames {
    if ($script:AccidentalCombo.SelectedIndex -eq 1) {
        return $script:SharpNames
    }
    return $script:FlatNames
}

function Get-NeutralCellColor {
    param(
        [int]$Row,
        [int]$Fret
    )

    if (($Row % 2) -eq 0) {
        if (($Fret % 2) -eq 0) {
            return $script:CellColors[0]
        }
        return $script:CellColors[1]
    }

    if (($Fret % 2) -eq 0) {
        return $script:CellColors[2]
    }
    return $script:CellColors[3]
}

function Set-GridCellAppearance {
    param(
        [System.Windows.Forms.Control]$Control,
        [int]$Pitch,
        [int]$Row,
        [int]$Fret
    )

    if ($script:SelectedPitches.Contains($Pitch)) {
        $activeColor = Mix-Color -Foreground $script:PitchColors[$Pitch] -Background $script:WindowBack -Weight 0.86
        $Control.BackColor = $activeColor
        $Control.ForeColor = $script:TextColor
    }
    else {
        $Control.BackColor = Get-NeutralCellColor -Row $Row -Fret $Fret
        $Control.ForeColor = $script:TextColor
    }
    $Control.Invalidate()
}

function Get-FretPitch {
    param(
        [int]$Row,
        [int]$Fret
    )

    return ($script:OpenStrings[$Row] + $Fret) % 12
}

function Get-FretCellPosition {
    param([System.Windows.Forms.Control]$Control)

    $parts = ([string]$Control.Tag) -split ','
    if ($parts.Count -ne 2) {
        throw 'Fret cell is missing its row and fret position.'
    }

    return @([int]$parts[0], [int]$parts[1])
}

function Get-InlayCenterUnits {
    param(
        [int]$Fret,
        [int]$StringCount
    )

    if ($Fret -notin @(3, 5, 7, 9, 12)) {
        return
    }

    if ($Fret -eq 12) {
        if ($StringCount -eq 7) {
            return @(2.5, 4.5)
        }
        return @(2.0, 4.0)
    }

    if ($StringCount -eq 7) {
        return @(3.5)
    }
    return @(3.0)
}

function Draw-FretCellInlays {
    param(
        [System.Windows.Forms.Control]$Control,
        [System.Drawing.Graphics]$Graphics
    )

    if (-not $script:ShowInlays -or $Control.ClientSize.Width -le 0 -or $Control.ClientSize.Height -le 0) {
        return
    }

    $position = Get-FretCellPosition -Control $Control
    $row = $position[0]
    $fret = $position[1]
    $stringCount = if ($script:HasOptionalString) { 7 } else { 6 }
    if ($row -ge $stringCount) {
        return
    }

    $centerUnits = @(Get-InlayCenterUnits -Fret $fret -StringCount $stringCount)
    if ($centerUnits.Count -eq 0) {
        return
    }

    $diameter = [Math]::Max(14, [Math]::Min(20, [int][Math]::Round($Control.ClientSize.Height * 0.48)))
    $radius = $diameter / 2.0
    $centerX = $Control.ClientSize.Width / 2.0
    $inlayColor = [System.Drawing.Color]::White
    $brush = New-Object System.Drawing.SolidBrush($inlayColor)
    $previousSmoothingMode = $Graphics.SmoothingMode
    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $redrawText = $false

    foreach ($centerUnit in $centerUnits) {
        $centerY = ([double]$centerUnit - $row) * $Control.ClientSize.Height
        if (($centerY + $radius) -lt 0 -or ($centerY - $radius) -gt $Control.ClientSize.Height) {
            continue
        }

        $bounds = [System.Drawing.RectangleF]::FromLTRB(
            [single]($centerX - $radius),
            [single]($centerY - $radius),
            [single]($centerX + $radius),
            [single]($centerY + $radius)
        )
        $Graphics.FillEllipse($brush, $bounds)
        if ([Math]::Abs($centerY - ($Control.ClientSize.Height / 2.0)) -le $radius) {
            $redrawText = $true
        }
    }

    $brush.Dispose()
    $Graphics.SmoothingMode = $previousSmoothingMode

    if ($redrawText) {
        $textFlags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
            [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
            [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText(
            $Graphics,
            $Control.Text,
            $Control.Font,
            $Control.ClientRectangle,
            [System.Drawing.Color]::Black,
            $textFlags
        )
    }
}

function Update-InlayCells {
    foreach ($row in 0..6) {
        foreach ($fret in @(3, 5, 7, 9, 12)) {
            $cell = $script:FretCells["$row,$fret"]
            if ($null -ne $cell) {
                $cell.Invalidate()
            }
        }
    }
}

function Update-InlayButtonAppearance {
    if ($null -eq $script:InlaysButton) {
        return
    }

    if ($script:ShowInlays) {
        $script:InlaysButton.Text = 'Inlays: On'
        $script:InlaysButton.BackColor = $script:EdgeColor
        $script:InlaysButton.FlatAppearance.BorderColor = $script:TextColor
        $script:InlaysButton.FlatAppearance.BorderSize = 2
    }
    else {
        $script:InlaysButton.Text = 'Inlays: Off'
        $script:InlaysButton.BackColor = $script:ControlBack
        $script:InlaysButton.FlatAppearance.BorderColor = $script:EdgeColor
        $script:InlaysButton.FlatAppearance.BorderSize = 1
    }
}

function Toggle-Inlays {
    $script:ShowInlays = -not $script:ShowInlays
    Update-InlayButtonAppearance
    Update-InlayCells
    Save-ConfigIfEnabled
}

function Get-IntervalLabel {
    param([int]$Pitch)

    $interval = ($Pitch - $script:RootPitch + 12) % 12
    return $script:IntervalLabels[$interval]
}

function Draw-FretCellInterval {
    param(
        [System.Windows.Forms.Control]$Control,
        [System.Drawing.Graphics]$Graphics
    )

    if (-not $script:ShowIntervals -or $Control.ClientSize.Width -le 0 -or $Control.ClientSize.Height -le 0) {
        return
    }

    $position = Get-FretCellPosition -Control $Control
    $pitch = Get-FretPitch -Row $position[0] -Fret $position[1]
    if (-not $script:SelectedPitches.Contains($pitch)) {
        return
    }

    $labelBounds = New-Object System.Drawing.Rectangle(
        3,
        1,
        [Math]::Max(1, ($Control.ClientSize.Width - 6)),
        [Math]::Min(16, $Control.ClientSize.Height)
    )
    $textFlags = [System.Windows.Forms.TextFormatFlags]::Left -bor
        [System.Windows.Forms.TextFormatFlags]::Top -bor
        [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
        [System.Windows.Forms.TextFormatFlags]::NoPadding -bor
        [System.Windows.Forms.TextFormatFlags]::NoPrefix
    $intervalFont = if ($null -ne $script:IntervalFont) { $script:IntervalFont } else { $Control.Font }
    [System.Windows.Forms.TextRenderer]::DrawText(
        $Graphics,
        (Get-IntervalLabel -Pitch $pitch),
        $intervalFont,
        $labelBounds,
        [System.Drawing.Color]::Black,
        $textFlags
    )
}

function Update-IntervalCells {
    foreach ($row in 0..6) {
        foreach ($fret in 1..12) {
            $cell = $script:FretCells["$row,$fret"]
            if ($null -ne $cell) {
                $cell.Invalidate()
            }
        }
    }
}

function Set-IntervalsEnabled {
    param([bool]$Enabled)

    $script:ShowIntervals = $Enabled
    Update-IntervalCells
    Save-ConfigIfEnabled
}

function Set-FretCellHoverAppearance {
    param([System.Windows.Forms.Control]$Control)

    $position = Get-FretCellPosition -Control $Control
    $row = $position[0]
    $fret = $position[1]
    $pitch = Get-FretPitch -Row $row -Fret $fret

    if ($script:SelectedPitches.Contains($pitch)) {
        Set-GridCellAppearance -Control $Control -Pitch $pitch -Row $row -Fret $fret
        return
    }

    $neutralColor = Get-NeutralCellColor -Row $row -Fret $fret
    $hoverColor = Mix-Color -Foreground $script:PitchColors[$pitch] -Background $neutralColor -Weight 0.33
    $Control.BackColor = $hoverColor
    $Control.ForeColor = $script:TextColor
    $Control.Invalidate()
}

function Restore-FretCellAppearance {
    param([System.Windows.Forms.Control]$Control)

    $position = Get-FretCellPosition -Control $Control
    $row = $position[0]
    $fret = $position[1]
    $pitch = Get-FretPitch -Row $row -Fret $fret
    Set-GridCellAppearance -Control $Control -Pitch $pitch -Row $row -Fret $fret
}

function Update-SelectedSummary {
    $names = Get-NoteNames
    $selectedNames = @(
        $script:SelectedPitches |
            Sort-Object |
            ForEach-Object { $names[[int]$_] }
    )

    if ($selectedNames.Count -eq 0) {
        $script:SelectedLabel.Text = 'No notes selected'
    }
    else {
        $script:SelectedLabel.Text = 'Selected: ' + ($selectedNames -join ' ')
    }

    Update-ScaleMatches
}

function Get-PossibleScaleNames {
    if ($script:SelectedPitches.Count -lt 5) {
        return @()
    }

    if ($script:SelectedPitches.Count -eq 12) {
        return @('Chromatic')
    }

    $rawCandidates = @()
    foreach ($scaleName in $script:ScaleIntervals.Keys) {
        if ($scaleName -eq 'Chromatic') {
            continue
        }

        $intervals = $script:ScaleIntervals[$scaleName]
        for ($rootPitch = 0; $rootPitch -lt 12; $rootPitch++) {
            $scalePitches = New-Object 'System.Collections.Generic.HashSet[int]'
            foreach ($interval in $intervals) {
                [void]$scalePitches.Add(($rootPitch + [int]$interval) % 12)
            }

            $containsSelection = $true
            foreach ($selectedPitch in $script:SelectedPitches) {
                if (-not $scalePitches.Contains([int]$selectedPitch)) {
                    $containsSelection = $false
                    break
                }
            }
            if (-not $containsSelection) {
                continue
            }

            $signature = @($scalePitches | Sort-Object) -join ','
            $rawCandidates += [pscustomobject]@{
                Root = $rootPitch
                Family = [string]$scaleName
                Signature = $signature
                NoteCount = $scalePitches.Count
            }
        }
    }

    $familyCandidates = @(
        $rawCandidates |
            Group-Object { "$($_.Root)|$($_.Signature)" } |
            ForEach-Object {
                $families = @($_.Group.Family | Select-Object -Unique)
                [pscustomobject]@{
                    Root = [int]$_.Group[0].Root
                    Family = $families -join '/'
                    Signature = [string]$_.Group[0].Signature
                    NoteCount = [int]$_.Group[0].NoteCount
                }
            }
    )

    $noteNames = Get-NoteNames
    $scaleNames = @(
        $familyCandidates |
            Group-Object { "$($_.Family)|$($_.Signature)" } |
            ForEach-Object {
                $roots = @(
                    $_.Group |
                        Sort-Object Root |
                        ForEach-Object { $noteNames[[int]$_.Root] }
                )
                [pscustomobject]@{
                    Name = (($roots -join '/') + ' ' + [string]$_.Group[0].Family)
                    NoteCount = [int]$_.Group[0].NoteCount
                }
            } |
            Sort-Object NoteCount, Name |
            ForEach-Object { $_.Name }
    )

    return $scaleNames
}

function Update-ScaleMatches {
    if ($null -eq $script:ScaleMatchesLabel) {
        return
    }

    $script:ScaleMatchesLabel.Text = ''
    if ([string]$script:ScaleCombo.SelectedItem -ne 'Custom') {
        return
    }

    $scaleNames = @(Get-PossibleScaleNames)
    if ($scaleNames.Count -eq 0) {
        return
    }

    $matchText = 'Possible: ' + ($scaleNames -join ' | ')
    $measureFlags = [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
        [System.Windows.Forms.TextFormatFlags]::NoPadding -bor
        [System.Windows.Forms.TextFormatFlags]::NoPrefix
    $measuredSize = [System.Windows.Forms.TextRenderer]::MeasureText(
        $matchText,
        $script:ScaleMatchesLabel.Font,
        [System.Drawing.Size]::Empty,
        $measureFlags
    )
    if ($script:ScaleMatchesLabel.ClientSize.Width -gt 0 -and $measuredSize.Width -le ($script:ScaleMatchesLabel.ClientSize.Width - 4)) {
        $script:ScaleMatchesLabel.Text = $matchText
    }
}

function Test-IsAccidentalPitch {
    param([int]$Pitch)

    return $Pitch -in @(1, 3, 6, 8, 10)
}

function Update-PitchKeyboardLayout {
    if ($null -eq $script:PitchKeyboardPanel -or $script:PitchButtons.Count -ne 12) {
        return
    }

    $leftPadding = 4
    $rightPadding = 4
    $topPadding = 2
    $bottomPadding = 2
    $contentWidth = [Math]::Max(7, $script:PitchKeyboardPanel.ClientSize.Width - $leftPadding - $rightPadding)
    $keyHeight = [Math]::Max(1, $script:PitchKeyboardPanel.ClientSize.Height - $topPadding - $bottomPadding)
    $naturalPitches = @(0, 2, 4, 5, 7, 9, 11)

    for ($naturalIndex = 0; $naturalIndex -lt $naturalPitches.Count; $naturalIndex++) {
        $pitch = $naturalPitches[$naturalIndex]
        $left = $leftPadding + [int][Math]::Round(($naturalIndex * $contentWidth) / 7.0)
        $right = $leftPadding + [int][Math]::Round((($naturalIndex + 1) * $contentWidth) / 7.0)
        $script:PitchButtons[$pitch].Bounds = New-Object System.Drawing.Rectangle(
            ($left + 1),
            $topPadding,
            [Math]::Max(1, ($right - $left - 2)),
            $keyHeight
        )
    }

    $averageNaturalWidth = $contentWidth / 7.0
    $accidentalWidth = [Math]::Max(28, [int][Math]::Round($averageNaturalWidth * 0.58))
    $accidentalHeight = [Math]::Max(24, [int][Math]::Round($keyHeight * 0.62))
    $accidentalKeys = @(
        @{ Pitch = 1; Boundary = 1 },
        @{ Pitch = 3; Boundary = 2 },
        @{ Pitch = 6; Boundary = 4 },
        @{ Pitch = 8; Boundary = 5 },
        @{ Pitch = 10; Boundary = 6 }
    )

    foreach ($accidentalKey in $accidentalKeys) {
        $boundaryX = $leftPadding + [int][Math]::Round(($accidentalKey.Boundary * $contentWidth) / 7.0)
        $button = $script:PitchButtons[[int]$accidentalKey.Pitch]
        $button.Bounds = New-Object System.Drawing.Rectangle(
            ($boundaryX - [int][Math]::Floor($accidentalWidth / 2.0)),
            $topPadding,
            $accidentalWidth,
            $accidentalHeight
        )
        $button.BringToFront()
    }
}

function Update-PitchButtons {
    $names = Get-NoteNames

    foreach ($button in $script:PitchButtons) {
        $pitch = [int]$button.Tag
        $button.Text = $names[$pitch]
        $button.FlatAppearance.BorderColor = $script:PitchColors[$pitch]

        if ($script:SelectedPitches.Contains($pitch)) {
            $activeColor = $script:PitchColors[$pitch]
            $button.BackColor = $activeColor
            $button.ForeColor = Get-ContrastColor -Color $activeColor
            if (Test-IsAccidentalPitch -Pitch $pitch) {
                $button.FlatAppearance.BorderColor = [System.Drawing.Color]::Black
            }
            else {
                $button.FlatAppearance.BorderColor = [System.Drawing.Color]::White
            }
            $button.FlatAppearance.BorderSize = 2
        }
        else {
            if (Test-IsAccidentalPitch -Pitch $pitch) {
                $button.BackColor = [System.Drawing.Color]::Black
                $button.ForeColor = [System.Drawing.Color]::White
            }
            else {
                $button.BackColor = [System.Drawing.Color]::White
                $button.ForeColor = [System.Drawing.Color]::Black
            }
            $button.FlatAppearance.BorderSize = 1
        }
    }
}

function Update-Fretboard {
    $names = Get-NoteNames
    $stringCount = if ($script:HasOptionalString) { 7 } else { 6 }

    for ($row = 0; $row -lt $stringCount; $row++) {
        for ($fret = 0; $fret -le 12; $fret++) {
            $pitch = Get-FretPitch -Row $row -Fret $fret
            $control = $script:FretCells["$row,$fret"]

            if ($fret -eq 0) {
                Set-GridCellAppearance -Control $control -Pitch $pitch -Row $row -Fret $fret
            }
            else {
                $control.Text = $names[$pitch]
                Set-GridCellAppearance -Control $control -Pitch $pitch -Row $row -Fret $fret
            }
        }
    }
}

function Update-OpenStringItems {
    $names = Get-NoteNames
    $script:UpdatingUi = $true
    $stringCount = if ($script:HasOptionalString) { 7 } else { 6 }

    for ($row = 0; $row -lt $stringCount; $row++) {
        $combo = $script:OpenCombos[$row]
        $combo.BeginUpdate()
        $combo.Items.Clear()
        [void]$combo.Items.AddRange([object[]]$names)
        $combo.SelectedIndex = $script:OpenStrings[$row]
        $combo.EndUpdate()
    }

    $script:UpdatingUi = $false
}

function Set-ScaleToCustom {
    if ($null -eq $script:ScaleCombo -or $script:ScaleCombo.SelectedIndex -eq 0) {
        return
    }

    $wasUpdatingUi = $script:UpdatingUi
    $script:UpdatingUi = $true
    $script:ScaleCombo.SelectedIndex = 0
    $script:UpdatingUi = $wasUpdatingUi
    Update-ScaleMatches
}

function Update-ScaleRootItems {
    $scaleName = [string]$script:ScaleCombo.SelectedItem
    if (-not $script:ScaleRoots.Contains($scaleName)) {
        return
    }

    $preferredRoot = [string]$script:ScaleRootCombo.SelectedItem
    $preferredPitch = $null
    if ($script:RootPitches.ContainsKey($preferredRoot)) {
        $preferredPitch = [int]$script:RootPitches[$preferredRoot]
    }

    $roots = [object[]]$script:ScaleRoots[$scaleName]
    $selectedIndex = 0
    for ($index = 0; $index -lt $roots.Count; $index++) {
        if ([string]$roots[$index] -eq $preferredRoot) {
            $selectedIndex = $index
            break
        }

        if ($null -ne $preferredPitch -and [int]$script:RootPitches[[string]$roots[$index]] -eq $preferredPitch) {
            $selectedIndex = $index
        }
    }

    $wasUpdatingUi = $script:UpdatingUi
    $script:UpdatingUi = $true
    $script:ScaleRootCombo.BeginUpdate()
    $script:ScaleRootCombo.Items.Clear()
    [void]$script:ScaleRootCombo.Items.AddRange($roots)
    $script:ScaleRootCombo.SelectedIndex = $selectedIndex
    $script:ScaleRootCombo.EndUpdate()
    $script:UpdatingUi = $wasUpdatingUi
}

function Apply-SelectedScale {
    $scaleName = [string]$script:ScaleCombo.SelectedItem
    $rootName = [string]$script:ScaleRootCombo.SelectedItem
    if (-not $script:ScaleIntervals.Contains($scaleName) -or -not $script:RootPitches.ContainsKey($rootName)) {
        return
    }

    $rootPitch = [int]$script:RootPitches[$rootName]
    $script:RootPitch = $rootPitch
    $script:SelectedPitches.Clear()
    foreach ($interval in $script:ScaleIntervals[$scaleName]) {
        [void]$script:SelectedPitches.Add(($rootPitch + [int]$interval) % 12)
    }

    Update-PitchButtons
    Update-Fretboard
    Update-SelectedSummary
    Save-ConfigIfEnabled
}

function Toggle-SelectedPitch {
    param([int]$Pitch)

    if ($script:SelectedPitches.Contains($Pitch)) {
        [void]$script:SelectedPitches.Remove($Pitch)
    }
    else {
        [void]$script:SelectedPitches.Add($Pitch)
    }

    Set-ScaleToCustom
    Update-PitchButtons
    Update-Fretboard
    Update-SelectedSummary
    Save-ConfigIfEnabled
}

function Clear-SelectedPitches {
    $script:SelectedPitches.Clear()
    Set-ScaleToCustom
    Update-PitchButtons
    Update-Fretboard
    Update-SelectedSummary
    Save-ConfigIfEnabled
}

function Update-StringLayout {
    $stringCount = if ($script:HasOptionalString) { 7 } else { 6 }

    $script:FretPanel.SuspendLayout()
    for ($row = 0; $row -lt 7; $row++) {
        $isVisible = $row -lt $stringCount
        $script:StringLabels[$row].Visible = $isVisible
        $script:FretPanel.RowStyles[$row + 1].SizeType = if ($isVisible) {
            [System.Windows.Forms.SizeType]::Percent
        }
        else {
            [System.Windows.Forms.SizeType]::Absolute
        }
        $script:FretPanel.RowStyles[$row + 1].Height = if ($isVisible) { 100.0 / $stringCount } else { 0 }

        for ($fret = 0; $fret -le 12; $fret++) {
            $script:FretCells["$row,$fret"].Visible = $isVisible
        }
    }

    $script:StringLabels[0].Text = '1 high'
    for ($row = 1; $row -lt ($stringCount - 1); $row++) {
        $script:StringLabels[$row].Text = [string]($row + 1)
    }
    $script:StringLabels[$stringCount - 1].Text = "${stringCount} low"
    $script:StringToggleButton.Text = if ($script:HasOptionalString) { 'Remove string' } else { 'Add string' }
    $script:FretPanel.ResumeLayout($true)
}

function Toggle-OptionalString {
    $addingString = -not $script:HasOptionalString
    $script:HasOptionalString = $addingString

    if ($addingString) {
        if ($script:TuningPresets.Contains($script:CurrentTuningName)) {
            $script:OpenStrings[6] = [int]$script:TuningPresets[$script:CurrentTuningName].Pitches[6]
        }
        elseif (-not $script:OptionalStringWasConfigured) {
            $script:OpenStrings[6] = 11
        }
    }
    Set-ScaleToCustom

    Update-StringLayout
    Update-OpenStringItems
    Update-Fretboard
    Save-ConfigIfEnabled
}

function Set-TuningToCustom {
    $script:CurrentTuningName = 'Custom'
    if ($null -eq $script:TuningCombo) {
        return
    }

    $wasUpdatingUi = $script:UpdatingUi
    $script:UpdatingUi = $true
    $script:TuningCombo.SelectedIndex = $script:TuningCombo.FindStringExact('Custom')
    $script:UpdatingUi = $wasUpdatingUi
}

function Apply-TuningPreset {
    param([string]$PresetName)

    if (-not $script:TuningPresets.Contains($PresetName)) {
        return
    }

    $script:CurrentTuningName = $PresetName
    $script:OpenStrings = @($script:TuningPresets[$PresetName].Pitches | ForEach-Object { [int]$_ })

    if ($null -ne $script:TuningCombo) {
        $wasUpdatingUi = $script:UpdatingUi
        $script:UpdatingUi = $true
        $script:TuningCombo.SelectedIndex = $script:TuningCombo.FindStringExact($PresetName)
        $script:UpdatingUi = $wasUpdatingUi
    }

    Set-ScaleToCustom
    Update-OpenStringItems
    Update-Fretboard
    Save-ConfigIfEnabled
}

$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = 'Fretboard Visualizer'
$script:Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$script:Form.ClientSize = New-Object System.Drawing.Size(1180, 572)
$script:Form.MinimumSize = New-Object System.Drawing.Size(900, 512)
$script:Form.BackColor = $script:WindowBack
$script:Form.ForeColor = $script:TextColor
$script:Form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Regular)
$script:IntervalFont = New-Object System.Drawing.Font('Segoe UI', 7.0, [System.Drawing.FontStyle]::Bold)
$script:Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$script:Form.KeyPreview = $true

$script:MainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$script:MainLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:MainLayout.Padding = New-Object System.Windows.Forms.Padding(16)
$script:MainLayout.BackColor = $script:WindowBack
$script:MainLayout.ColumnCount = 1
$script:MainLayout.RowCount = 4
[void]$script:MainLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$script:MainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 112)))
[void]$script:MainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
[void]$script:MainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 1)))
[void]$script:MainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:Form.Controls.Add($script:MainLayout)

$script:ControlBar = New-Object System.Windows.Forms.TableLayoutPanel
$script:ControlBar.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ControlBar.Margin = New-Object System.Windows.Forms.Padding(0)
$script:ControlBar.ColumnCount = 2
$script:ControlBar.RowCount = 1
$script:ControlBar.BackColor = $script:PanelBack
[void]$script:ControlBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 60)))
[void]$script:ControlBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 40)))
[void]$script:ControlBar.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:MainLayout.Controls.Add($script:ControlBar, 0, 0)

$script:LeftControls = New-Object System.Windows.Forms.TableLayoutPanel
$script:LeftControls.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LeftControls.Margin = New-Object System.Windows.Forms.Padding(0)
$script:LeftControls.Padding = New-Object System.Windows.Forms.Padding(10, 2, 4, 2)
$script:LeftControls.BackColor = $script:PanelBack
$script:LeftControls.ColumnCount = 1
$script:LeftControls.RowCount = 2
[void]$script:LeftControls.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$script:LeftControls.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$script:LeftControls.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$script:ControlBar.Controls.Add($script:LeftControls, 0, 0)

$script:InstrumentControls = New-Object System.Windows.Forms.FlowLayoutPanel
$script:InstrumentControls.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:InstrumentControls.Margin = New-Object System.Windows.Forms.Padding(0)
$script:InstrumentControls.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$script:InstrumentControls.WrapContents = $false
$script:InstrumentControls.BackColor = $script:PanelBack
$script:LeftControls.Controls.Add($script:InstrumentControls, 0, 0)

$script:MusicControls = New-Object System.Windows.Forms.FlowLayoutPanel
$script:MusicControls.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:MusicControls.Margin = New-Object System.Windows.Forms.Padding(0)
$script:MusicControls.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$script:MusicControls.WrapContents = $false
$script:MusicControls.BackColor = $script:PanelBack
$script:LeftControls.Controls.Add($script:MusicControls, 0, 1)

$script:TuningGroup = New-Object System.Windows.Forms.TableLayoutPanel
$script:TuningGroup.Width = 210
$script:TuningGroup.Height = 50
$script:TuningGroup.RowCount = 2
$script:TuningGroup.ColumnCount = 1
$script:TuningGroup.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
$script:TuningGroup.BackColor = $script:PanelBack
[void]$script:TuningGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 19)))
[void]$script:TuningGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 31)))
$script:InstrumentControls.Controls.Add($script:TuningGroup)

$script:TuningLabel = New-Object System.Windows.Forms.Label
$script:TuningLabel.Text = 'Tuning'
$script:TuningLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:TuningLabel.ForeColor = $script:MutedColor
$script:TuningLabel.TextAlign = [System.Drawing.ContentAlignment]::BottomLeft
$script:TuningGroup.Controls.Add($script:TuningLabel, 0, 0)

$script:TuningCombo = New-Object System.Windows.Forms.ComboBox
$script:TuningCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:TuningCombo.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 3)
$script:TuningCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:TuningCombo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:TuningCombo.BackColor = $script:ControlBack
$script:TuningCombo.ForeColor = $script:TextColor
Set-DarkComboBox -ComboBox $script:TuningCombo
$tuningItems = @($script:TuningPresets.Keys) + @('Custom')
[void]$script:TuningCombo.Items.AddRange([object[]]$tuningItems)
$script:TuningCombo.SelectedIndex = $script:TuningCombo.FindStringExact($script:CurrentTuningName)
$script:TuningGroup.Controls.Add($script:TuningCombo, 0, 1)

$script:ScaleGroup = New-Object System.Windows.Forms.TableLayoutPanel
$script:ScaleGroup.Width = 210
$script:ScaleGroup.Height = 50
$script:ScaleGroup.RowCount = 2
$script:ScaleGroup.ColumnCount = 1
$script:ScaleGroup.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$script:ScaleGroup.BackColor = $script:PanelBack
[void]$script:ScaleGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 19)))
[void]$script:ScaleGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 31)))
$script:MusicControls.Controls.Add($script:ScaleGroup)

$script:ScaleLabel = New-Object System.Windows.Forms.Label
$script:ScaleLabel.Text = 'Scale'
$script:ScaleLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ScaleLabel.ForeColor = $script:MutedColor
$script:ScaleLabel.TextAlign = [System.Drawing.ContentAlignment]::BottomLeft
$script:ScaleGroup.Controls.Add($script:ScaleLabel, 0, 0)

$script:ScaleCombo = New-Object System.Windows.Forms.ComboBox
$script:ScaleCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ScaleCombo.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 3)
$script:ScaleCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:ScaleCombo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:ScaleCombo.BackColor = $script:ControlBack
$script:ScaleCombo.ForeColor = $script:TextColor
Set-DarkComboBox -ComboBox $script:ScaleCombo
[void]$script:ScaleCombo.Items.Add('Custom')
[void]$script:ScaleCombo.Items.AddRange([object[]]@($script:ScaleIntervals.Keys))
$script:ScaleCombo.SelectedIndex = 0
$script:ScaleGroup.Controls.Add($script:ScaleCombo, 0, 1)

$script:ScaleRootGroup = New-Object System.Windows.Forms.TableLayoutPanel
$script:ScaleRootGroup.Width = 96
$script:ScaleRootGroup.Height = 50
$script:ScaleRootGroup.RowCount = 2
$script:ScaleRootGroup.ColumnCount = 1
$script:ScaleRootGroup.Margin = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)
$script:ScaleRootGroup.BackColor = $script:PanelBack
[void]$script:ScaleRootGroup.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$script:ScaleRootGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 19)))
[void]$script:ScaleRootGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 31)))
$script:MusicControls.Controls.Add($script:ScaleRootGroup)

$script:ScaleRootLabel = New-Object System.Windows.Forms.Label
$script:ScaleRootLabel.Text = 'Root'
$script:ScaleRootLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ScaleRootLabel.ForeColor = $script:MutedColor
$script:ScaleRootLabel.TextAlign = [System.Drawing.ContentAlignment]::BottomLeft
$script:ScaleRootGroup.Controls.Add($script:ScaleRootLabel, 0, 0)

$script:ScaleRootCombo = New-Object System.Windows.Forms.ComboBox
$script:ScaleRootCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ScaleRootCombo.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 3)
$script:ScaleRootCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:ScaleRootCombo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:ScaleRootCombo.BackColor = $script:ControlBack
$script:ScaleRootCombo.ForeColor = $script:TextColor
Set-DarkComboBox -ComboBox $script:ScaleRootCombo
[void]$script:ScaleRootCombo.Items.AddRange([object[]]$standardRoots)
$script:ScaleRootCombo.SelectedIndex = $script:RootPitch
$script:ScaleRootGroup.Controls.Add($script:ScaleRootCombo, 0, 1)

$script:AccidentalGroup = New-Object System.Windows.Forms.TableLayoutPanel
$script:AccidentalGroup.Width = 124
$script:AccidentalGroup.Height = 50
$script:AccidentalGroup.RowCount = 2
$script:AccidentalGroup.ColumnCount = 1
$script:AccidentalGroup.Margin = New-Object System.Windows.Forms.Padding(0)
$script:AccidentalGroup.BackColor = $script:PanelBack
[void]$script:AccidentalGroup.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$script:AccidentalGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 19)))
[void]$script:AccidentalGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 31)))
$script:InstrumentControls.Controls.Add($script:AccidentalGroup)

$script:AccidentalLabel = New-Object System.Windows.Forms.Label
$script:AccidentalLabel.Text = 'Accidentals'
$script:AccidentalLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:AccidentalLabel.ForeColor = $script:MutedColor
$script:AccidentalLabel.TextAlign = [System.Drawing.ContentAlignment]::BottomLeft
$script:AccidentalGroup.Controls.Add($script:AccidentalLabel, 0, 0)

$script:AccidentalCombo = New-Object System.Windows.Forms.ComboBox
$script:AccidentalCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:AccidentalCombo.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 3)
$script:AccidentalCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:AccidentalCombo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:AccidentalCombo.BackColor = $script:ControlBack
$script:AccidentalCombo.ForeColor = $script:TextColor
Set-DarkComboBox -ComboBox $script:AccidentalCombo
[void]$script:AccidentalCombo.Items.AddRange([object[]]@('Flats', 'Sharps'))
$script:AccidentalCombo.SelectedIndex = if ($script:UseSharps) { 1 } else { 0 }
$script:AccidentalGroup.Controls.Add($script:AccidentalCombo, 0, 1)

$script:StringGroup = New-Object System.Windows.Forms.TableLayoutPanel
$script:StringGroup.Width = 108
$script:StringGroup.Height = 50
$script:StringGroup.RowCount = 2
$script:StringGroup.ColumnCount = 1
$script:StringGroup.Margin = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)
$script:StringGroup.BackColor = $script:PanelBack
[void]$script:StringGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 19)))
[void]$script:StringGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 31)))
$script:InstrumentControls.Controls.Add($script:StringGroup)
$script:InstrumentControls.Controls.SetChildIndex($script:StringGroup, 1)

$script:StringLabel = New-Object System.Windows.Forms.Label
$script:StringLabel.Text = 'Strings'
$script:StringLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:StringLabel.ForeColor = $script:MutedColor
$script:StringLabel.TextAlign = [System.Drawing.ContentAlignment]::BottomLeft
$script:StringGroup.Controls.Add($script:StringLabel, 0, 0)

$script:StringToggleButton = New-Object System.Windows.Forms.Button
$script:StringToggleButton.Text = 'Add string'
$script:StringToggleButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:StringToggleButton.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 3)
$script:StringToggleButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:StringToggleButton.BackColor = $script:ControlBack
$script:StringToggleButton.ForeColor = $script:TextColor
$script:StringToggleButton.FlatAppearance.BorderColor = $script:EdgeColor
$script:StringToggleButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:StringToggleButton.UseVisualStyleBackColor = $false
$script:StringToggleButton.Add_Click({
    Toggle-OptionalString
})
$script:StringGroup.Controls.Add($script:StringToggleButton, 0, 1)

$script:ClearGroup = New-Object System.Windows.Forms.TableLayoutPanel
$script:ClearGroup.Width = 116
$script:ClearGroup.Height = 50
$script:ClearGroup.RowCount = 2
$script:ClearGroup.ColumnCount = 1
$script:ClearGroup.Margin = New-Object System.Windows.Forms.Padding(0)
$script:ClearGroup.BackColor = $script:PanelBack
[void]$script:ClearGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 19)))
[void]$script:ClearGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 31)))
$script:MusicControls.Controls.Add($script:ClearGroup)

$script:ClearLabel = New-Object System.Windows.Forms.Label
$script:ClearLabel.Text = 'Selection'
$script:ClearLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ClearLabel.ForeColor = $script:MutedColor
$script:ClearLabel.TextAlign = [System.Drawing.ContentAlignment]::BottomLeft
$script:ClearGroup.Controls.Add($script:ClearLabel, 0, 0)

$script:ClearSelectionButton = New-Object System.Windows.Forms.Button
$script:ClearSelectionButton.Text = 'Clear selection'
$script:ClearSelectionButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ClearSelectionButton.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 3)
$script:ClearSelectionButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:ClearSelectionButton.BackColor = $script:ControlBack
$script:ClearSelectionButton.ForeColor = $script:TextColor
$script:ClearSelectionButton.FlatAppearance.BorderColor = $script:EdgeColor
$script:ClearSelectionButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:ClearSelectionButton.UseVisualStyleBackColor = $false
$script:ClearSelectionButton.Add_Click({
    Clear-SelectedPitches
})
$script:ClearGroup.Controls.Add($script:ClearSelectionButton, 0, 1)

$script:KeyboardGroup = New-Object System.Windows.Forms.TableLayoutPanel
$script:KeyboardGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:KeyboardGroup.Margin = New-Object System.Windows.Forms.Padding(0)
$script:KeyboardGroup.Padding = New-Object System.Windows.Forms.Padding(8, 3, 10, 5)
$script:KeyboardGroup.BackColor = $script:PanelBack
$script:KeyboardGroup.ColumnCount = 1
$script:KeyboardGroup.RowCount = 2
[void]$script:KeyboardGroup.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$script:KeyboardGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 27)))
[void]$script:KeyboardGroup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:ControlBar.Controls.Add($script:KeyboardGroup, 1, 0)

$script:KeyboardHeader = New-Object System.Windows.Forms.TableLayoutPanel
$script:KeyboardHeader.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:KeyboardHeader.Margin = New-Object System.Windows.Forms.Padding(0)
$script:KeyboardHeader.BackColor = $script:PanelBack
$script:KeyboardHeader.ColumnCount = 5
$script:KeyboardHeader.RowCount = 1
[void]$script:KeyboardHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$script:KeyboardHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 86)))
[void]$script:KeyboardHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 88)))
[void]$script:KeyboardHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
[void]$script:KeyboardHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 0)))
[void]$script:KeyboardHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:KeyboardGroup.Controls.Add($script:KeyboardHeader, 0, 0)

$script:KeyboardLabel = New-Object System.Windows.Forms.Label
$script:KeyboardLabel.Text = 'Note selection'
$script:KeyboardLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:KeyboardLabel.ForeColor = $script:MutedColor
$script:KeyboardLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:KeyboardHeader.Controls.Add($script:KeyboardLabel, 0, 0)

$script:InlaysButton = New-Object System.Windows.Forms.Button
$script:InlaysButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:InlaysButton.Margin = New-Object System.Windows.Forms.Padding(4, 1, 0, 1)
$script:InlaysButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:InlaysButton.ForeColor = $script:TextColor
$script:InlaysButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:InlaysButton.UseVisualStyleBackColor = $false
$script:InlaysButton.Add_Click({
    Toggle-Inlays
})
$script:KeyboardHeader.Controls.Add($script:InlaysButton, 1, 0)
Update-InlayButtonAppearance

$script:IntervalsCheckbox = New-Object System.Windows.Forms.CheckBox
$script:IntervalsCheckbox.Text = 'Intervals'
$script:IntervalsCheckbox.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:IntervalsCheckbox.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
$script:IntervalsCheckbox.ForeColor = $script:TextColor
$script:IntervalsCheckbox.BackColor = $script:PanelBack
$script:IntervalsCheckbox.CheckAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:IntervalsCheckbox.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:IntervalsCheckbox.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:IntervalsCheckbox.Checked = $script:ShowIntervals
$script:IntervalsCheckbox.Add_CheckedChanged({
    if ($script:UpdatingUi) {
        return
    }
    Set-IntervalsEnabled -Enabled $this.Checked
})
$script:KeyboardHeader.Controls.Add($script:IntervalsCheckbox, 2, 0)

$script:SaveCheckbox = New-Object System.Windows.Forms.CheckBox
$script:SaveCheckbox.Text = 'Save'
$script:SaveCheckbox.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:SaveCheckbox.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
$script:SaveCheckbox.ForeColor = $script:TextColor
$script:SaveCheckbox.BackColor = $script:PanelBack
$script:SaveCheckbox.CheckAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:SaveCheckbox.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:SaveCheckbox.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:SaveCheckbox.Checked = $script:SaveConfigEnabled
$script:SaveCheckbox.Add_CheckedChanged({
    if ($script:UpdatingUi) {
        return
    }
    Set-ConfigSaving -Enabled $this.Checked
})
$script:KeyboardHeader.Controls.Add($script:SaveCheckbox, 3, 0)

$script:PurgeSaveButton = New-Object System.Windows.Forms.Button
$script:PurgeSaveButton.Text = 'Purge save'
$script:PurgeSaveButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:PurgeSaveButton.Margin = New-Object System.Windows.Forms.Padding(4, 1, 0, 1)
$script:PurgeSaveButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:PurgeSaveButton.BackColor = $script:ControlBack
$script:PurgeSaveButton.ForeColor = $script:TextColor
$script:PurgeSaveButton.FlatAppearance.BorderColor = $script:EdgeColor
$script:PurgeSaveButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:PurgeSaveButton.UseVisualStyleBackColor = $false
$script:PurgeSaveButton.Add_Click({
    Purge-SavedConfig
})
$script:KeyboardHeader.Controls.Add($script:PurgeSaveButton, 4, 0)
Update-PurgeButtonVisibility

$script:PitchKeyboardPanel = New-Object System.Windows.Forms.Panel
$script:PitchKeyboardPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:PitchKeyboardPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$script:PitchKeyboardPanel.BackColor = $script:PanelBack
$script:KeyboardGroup.Controls.Add($script:PitchKeyboardPanel, 0, 1)

$script:PitchPanel = New-Object System.Windows.Forms.TableLayoutPanel
$script:PitchPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:PitchPanel.BackColor = $script:PanelBack
$script:PitchPanel.Padding = New-Object System.Windows.Forms.Padding(10, 1, 10, 1)
$script:PitchPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$script:PitchPanel.ColumnCount = 1
$script:PitchPanel.RowCount = 1
[void]$script:PitchPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$script:PitchPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:MainLayout.Controls.Add($script:PitchPanel, 0, 1)

$script:SummaryPanel = New-Object System.Windows.Forms.TableLayoutPanel
$script:SummaryPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:SummaryPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$script:SummaryPanel.BackColor = $script:PanelBack
$script:SummaryPanel.ColumnCount = 2
$script:SummaryPanel.RowCount = 1
[void]$script:SummaryPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.333)))
[void]$script:SummaryPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 66.667)))
[void]$script:SummaryPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:PitchPanel.Controls.Add($script:SummaryPanel, 0, 0)

$script:SelectedLabel = New-Object System.Windows.Forms.Label
$script:SelectedLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:SelectedLabel.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
$script:SelectedLabel.Text = 'No notes selected'
$script:SelectedLabel.ForeColor = $script:MutedColor
$script:SelectedLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:SelectedLabel.AutoEllipsis = $true
$script:SummaryPanel.Controls.Add($script:SelectedLabel, 0, 0)

$script:ScaleMatchesLabel = New-Object System.Windows.Forms.Label
$script:ScaleMatchesLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ScaleMatchesLabel.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
$script:ScaleMatchesLabel.Text = ''
$script:ScaleMatchesLabel.ForeColor = $script:MutedColor
$script:ScaleMatchesLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$script:ScaleMatchesLabel.AutoEllipsis = $false
$script:SummaryPanel.Controls.Add($script:ScaleMatchesLabel, 1, 0)
$script:PitchPanel.Add_SizeChanged({
    Update-ScaleMatches
})
$script:Form.Add_ResizeEnd({
    Update-ScaleMatches
})

for ($pitch = 0; $pitch -lt 12; $pitch++) {
    $button = New-Object System.Windows.Forms.Button
    $button.AutoSize = $false
    $button.Tag = $pitch
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.TabStop = $false
    $button.UseVisualStyleBackColor = $false
    if (Test-IsAccidentalPitch -Pitch $pitch) {
        $button.TextAlign = [System.Drawing.ContentAlignment]::BottomCenter
        $button.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
    }
    else {
        $button.TextAlign = [System.Drawing.ContentAlignment]::BottomCenter
        $button.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    }
    $button.Add_Click({
        Toggle-SelectedPitch -Pitch ([int]$this.Tag)
    })
    $script:PitchButtons += $button
    $script:PitchKeyboardPanel.Controls.Add($button)
}

$script:PitchKeyboardPanel.Add_SizeChanged({
    Update-PitchKeyboardLayout
})
$script:Form.Add_Shown({
    Update-PitchKeyboardLayout
})
Update-PitchKeyboardLayout

$script:Divider = New-Object System.Windows.Forms.Panel
$script:Divider.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:Divider.Margin = New-Object System.Windows.Forms.Padding(0)
$script:Divider.BackColor = $script:EdgeColor
$script:MainLayout.Controls.Add($script:Divider, 0, 2)

$script:FretPanel = New-Object System.Windows.Forms.TableLayoutPanel
$script:FretPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:FretPanel.BackColor = $script:WindowBack
$script:FretPanel.Padding = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
$script:FretPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$script:FretPanel.ColumnCount = 14
$script:FretPanel.RowCount = 9
[void]$script:FretPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 62)))
for ($column = 1; $column -lt 14; $column++) {
    [void]$script:FretPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, (100.0 / 13.0))))
}
[void]$script:FretPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
for ($row = 1; $row -lt 7; $row++) {
    [void]$script:FretPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, (100.0 / 6.0))))
}
[void]$script:FretPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 0)))
[void]$script:FretPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
$script:MainLayout.Controls.Add($script:FretPanel, 0, 3)

$stringHeader = New-Object System.Windows.Forms.Label
$stringHeader.Text = 'String'
$stringHeader.Dock = [System.Windows.Forms.DockStyle]::Fill
$stringHeader.ForeColor = $script:MutedColor
$stringHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:FretPanel.Controls.Add($stringHeader, 0, 0)

$fretNumberFont = New-Object System.Drawing.Font($script:Form.Font, [System.Drawing.FontStyle]::Bold)

for ($fret = 0; $fret -le 12; $fret++) {
    $header = New-Object System.Windows.Forms.Label
    $header.Text = [string]$fret
    $header.Dock = [System.Windows.Forms.DockStyle]::Fill
    $header.Font = $fretNumberFont
    $header.ForeColor = $script:MutedColor
    $header.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $script:FretPanel.Controls.Add($header, ($fret + 1), 0)
}

for ($row = 0; $row -lt 7; $row++) {
    $rowLabel = New-Object System.Windows.Forms.Label
    if ($row -eq 0) {
        $rowLabel.Text = '1 high'
    }
    elseif ($row -eq 5) {
        $rowLabel.Text = '6 low'
    }
    else {
        $rowLabel.Text = [string]($row + 1)
    }
    $rowLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $rowLabel.ForeColor = $script:MutedColor
    $rowLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $script:StringLabels += $rowLabel
    $script:FretPanel.Controls.Add($rowLabel, 0, ($row + 1))

    for ($fret = 0; $fret -le 12; $fret++) {
        if ($fret -eq 0) {
            $openCombo = New-Object System.Windows.Forms.ComboBox
            $openCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
            $openCombo.Margin = New-Object System.Windows.Forms.Padding(2)
            $openCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $openCombo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $openCombo.Tag = $row
            Set-DarkComboBox -ComboBox $openCombo
            [void]$openCombo.Items.AddRange([object[]]$script:FlatNames)
            $openCombo.SelectedIndex = $script:OpenStrings[$row]
            $openCombo.Add_SelectedIndexChanged({
                if ($script:UpdatingUi) {
                    return
                }

                $changedRow = [int]$this.Tag
                if ($this.SelectedIndex -lt 0) {
                    return
                }

                $script:OpenStrings[$changedRow] = $this.SelectedIndex
                if ($changedRow -eq 6) {
                    $script:OptionalStringWasConfigured = $true
                }
                Set-TuningToCustom
                Set-ScaleToCustom
                Update-Fretboard
                Save-ConfigIfEnabled
            })
            $script:OpenCombos += $openCombo
            $script:FretCells["$row,$fret"] = $openCombo
            $script:FretPanel.Controls.Add($openCombo, ($fret + 1), ($row + 1))
        }
        else {
            $cell = New-Object System.Windows.Forms.Label
            $cell.Dock = [System.Windows.Forms.DockStyle]::Fill
            $cell.Margin = New-Object System.Windows.Forms.Padding(2)
            $cell.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $cell.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $cell.Tag = "$row,$fret"
            $cell.Cursor = [System.Windows.Forms.Cursors]::Hand
            $cell.Add_Click({
                $position = Get-FretCellPosition -Control $this
                $pitch = Get-FretPitch -Row $position[0] -Fret $position[1]
                Toggle-SelectedPitch -Pitch $pitch
                Set-FretCellHoverAppearance -Control $this
            })
            $cell.Add_MouseEnter({
                Set-FretCellHoverAppearance -Control $this
            })
            $cell.Add_MouseLeave({
                Restore-FretCellAppearance -Control $this
            })
            $cell.Add_Paint({
                param($sender, $eventArgs)
                Draw-FretCellInlays -Control $sender -Graphics $eventArgs.Graphics
                Draw-FretCellInterval -Control $sender -Graphics $eventArgs.Graphics
            })
            $script:FretCells["$row,$fret"] = $cell
            $script:FretPanel.Controls.Add($cell, ($fret + 1), ($row + 1))
        }
    }
}

$bottomStringHeader = New-Object System.Windows.Forms.Label
$bottomStringHeader.Text = 'String'
$bottomStringHeader.Dock = [System.Windows.Forms.DockStyle]::Fill
$bottomStringHeader.ForeColor = $script:MutedColor
$bottomStringHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:FretPanel.Controls.Add($bottomStringHeader, 0, 8)

for ($fret = 0; $fret -le 12; $fret++) {
    $bottomHeader = New-Object System.Windows.Forms.Label
    $bottomHeader.Text = [string]$fret
    $bottomHeader.Dock = [System.Windows.Forms.DockStyle]::Fill
    $bottomHeader.Font = $fretNumberFont
    $bottomHeader.ForeColor = $script:MutedColor
    $bottomHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $script:FretPanel.Controls.Add($bottomHeader, ($fret + 1), 8)
}

Update-StringLayout

$script:TuningCombo.Add_SelectedIndexChanged({
    if ($script:UpdatingUi) {
        return
    }

    $selectedTuning = [string]$script:TuningCombo.SelectedItem
    if ($selectedTuning -eq 'Custom') {
        $script:CurrentTuningName = 'Custom'
        Save-ConfigIfEnabled
        return
    }
    Apply-TuningPreset -PresetName $selectedTuning
})

$script:ScaleCombo.Add_SelectedIndexChanged({
    if ($script:UpdatingUi) {
        return
    }

    Update-ScaleRootItems
    Apply-SelectedScale
    Update-ScaleMatches
})

$script:ScaleRootCombo.Add_SelectedIndexChanged({
    if ($script:UpdatingUi) {
        return
    }

    $rootName = [string]$script:ScaleRootCombo.SelectedItem
    if ($script:RootPitches.ContainsKey($rootName)) {
        $script:RootPitch = [int]$script:RootPitches[$rootName]
    }
    Apply-SelectedScale
    Update-IntervalCells
    Save-ConfigIfEnabled
})

$script:AccidentalCombo.Add_SelectedIndexChanged({
    if ($script:UpdatingUi) {
        return
    }
    $script:UseSharps = $script:AccidentalCombo.SelectedIndex -eq 1
    Update-OpenStringItems
    Update-PitchButtons
    Update-Fretboard
    Update-SelectedSummary
    Save-ConfigIfEnabled
})

$script:Form.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:Form.Close()
    }
})

Update-PitchButtons
Update-Fretboard
Update-SelectedSummary

if ($TestMode) {
    if ($script:PitchButtons.Count -ne 12) {
        throw 'Expected 12 pitch buttons.'
    }
    if ($script:FretCells.Count -ne 91 -or $script:OpenCombos.Count -ne 7) {
        throw 'Expected controls for seven possible strings.'
    }
    if ($script:FretPanel.GetControlFromPosition(0, 8).Text -ne 'String' -or $script:FretPanel.GetControlFromPosition(13, 8).Text -ne '12') {
        throw 'Expected the fret-number reference below the fretboard.'
    }
    if (-not $script:FretPanel.GetControlFromPosition(1, 0).Font.Bold -or -not $script:FretPanel.GetControlFromPosition(13, 8).Font.Bold) {
        throw 'Expected bold fret numbers above and below the fretboard.'
    }
    if ($script:HasOptionalString -or $script:StringToggleButton.Text -ne 'Add string' -or
        $script:OpenStrings[6] -ne 11 -or [string]$script:TuningCombo.SelectedItem -ne 'E standard') {
        throw 'The fretboard did not initialize in six-string E standard tuning.'
    }
    $selectedPosition = $script:SummaryPanel.GetPositionFromControl($script:SelectedLabel)
    if ($selectedPosition.Row -ne 0 -or $selectedPosition.Column -ne 0 -or -not $script:SelectedLabel.AutoEllipsis) {
        throw 'Selected-note summary should occupy one line below the pitch buttons.'
    }
    $matchesPosition = $script:SummaryPanel.GetPositionFromControl($script:ScaleMatchesLabel)
    if ($matchesPosition.Row -ne 0 -or $matchesPosition.Column -ne 1 -or $script:ScaleMatchesLabel.TextAlign -ne [System.Drawing.ContentAlignment]::MiddleRight) {
        throw 'Possible scales should occupy the right side of the summary row.'
    }
    if (@($script:PitchButtons | Where-Object { $_.Parent -ne $script:PitchKeyboardPanel }).Count -ne 0) {
        throw 'Expected all pitch buttons inside the layered keyboard panel.'
    }
    if ($script:PitchButtons[0].BackColor.ToArgb() -ne [System.Drawing.Color]::White.ToArgb() -or
        $script:PitchButtons[1].BackColor.ToArgb() -ne [System.Drawing.Color]::Black.ToArgb()) {
        throw 'Unselected natural and accidental keys should use white and black fills.'
    }
    foreach ($pitch in 0..11) {
        if ($script:PitchButtons[$pitch].FlatAppearance.BorderColor.ToArgb() -ne $script:PitchColors[$pitch].ToArgb()) {
            throw 'Pitch key borders should retain their spectrum colors.'
        }
    }
    Toggle-SelectedPitch -Pitch 0
    if ($script:PitchButtons[0].BackColor.ToArgb() -ne $script:PitchColors[0].ToArgb() -or
        $script:PitchButtons[0].FlatAppearance.BorderColor.ToArgb() -ne [System.Drawing.Color]::White.ToArgb() -or
        $script:PitchButtons[0].FlatAppearance.BorderSize -ne 2) {
        throw 'A selected natural key should use its spectrum fill and a white border.'
    }
    if ($script:FretCells['0,8'].ForeColor.ToArgb() -ne $script:TextColor.ToArgb()) {
        throw 'Selected fret note labels should render in white.'
    }
    Toggle-SelectedPitch -Pitch 0
    if ($script:FretCells['0,8'].ForeColor.ToArgb() -ne $script:TextColor.ToArgb()) {
        throw 'Unselected fret note labels should render in white.'
    }
    Toggle-SelectedPitch -Pitch 1
    if ($script:PitchButtons[1].BackColor.ToArgb() -ne $script:PitchColors[1].ToArgb() -or
        $script:PitchButtons[1].FlatAppearance.BorderColor.ToArgb() -ne [System.Drawing.Color]::Black.ToArgb() -or
        $script:PitchButtons[1].FlatAppearance.BorderSize -ne 2) {
        throw 'A selected accidental key should use its spectrum fill and a black border.'
    }
    Toggle-SelectedPitch -Pitch 1
    if ($script:StringToggleButton.Parent -ne $script:StringGroup -or $script:ClearSelectionButton.Parent -ne $script:ClearGroup) {
        throw 'String and clear-selection actions should occupy their workflow groups.'
    }
    if ($script:LeftControls.GetPositionFromControl($script:InstrumentControls).Row -ne 0 -or
        $script:LeftControls.GetPositionFromControl($script:MusicControls).Row -ne 1) {
        throw 'Instrument setup should appear above the musical controls.'
    }
    if ($script:InstrumentControls.Controls.GetChildIndex($script:TuningGroup) -ne 0 -or
        $script:InstrumentControls.Controls.GetChildIndex($script:StringGroup) -ne 1 -or
        $script:InstrumentControls.Controls.GetChildIndex($script:AccidentalGroup) -ne 2) {
        throw 'Instrument controls should read Tuning, Strings, Accidentals.'
    }
    if ($script:MusicControls.Controls.GetChildIndex($script:ScaleGroup) -ne 0 -or
        $script:MusicControls.Controls.GetChildIndex($script:ScaleRootGroup) -ne 1 -or
        $script:MusicControls.Controls.GetChildIndex($script:ClearGroup) -ne 2) {
        throw 'Musical controls should read Scale, Root, Clear selection.'
    }
    if ($script:PitchKeyboardPanel.Parent -ne $script:KeyboardGroup -or
        $script:ControlBar.GetPositionFromControl($script:KeyboardGroup).Column -ne 1) {
        throw 'The compact note keyboard should occupy the right header area.'
    }
    if ($script:InlaysButton.Parent -ne $script:KeyboardHeader -or -not $script:ShowInlays -or $script:InlaysButton.Text -ne 'Inlays: On') {
        throw 'The inlay toggle should initialize on in the note-selection header.'
    }
    if ($script:ShowIntervals -or $script:IntervalsCheckbox.Checked -or
        (Get-IntervalLabel -Pitch 0) -ne 'R' -or (Get-IntervalLabel -Pitch 1) -ne 'b2' -or
        (Get-IntervalLabel -Pitch 7) -ne '5' -or (Get-IntervalLabel -Pitch 11) -ne '7') {
        throw 'Intervals should initialize off with the expected chromatic labels from C.'
    }
    if ($script:KeyboardHeader.GetPositionFromControl($script:InlaysButton).Column -ne 1 -or
        $script:KeyboardHeader.GetPositionFromControl($script:IntervalsCheckbox).Column -ne 2 -or
        $script:KeyboardHeader.GetPositionFromControl($script:SaveCheckbox).Column -ne 3 -or
        $script:KeyboardHeader.GetPositionFromControl($script:PurgeSaveButton).Column -ne 4) {
        throw 'Inlays, Intervals, Save, and Purge save should occupy the right header in order.'
    }
    if ($script:SaveConfigEnabled -or $script:SaveCheckbox.Checked -or
        $script:KeyboardHeader.ColumnStyles[4].Width -ne 0 -or [System.IO.File]::Exists($script:ConfigPath)) {
        throw 'Config saving should initialize off without a purge action.'
    }
    $script:SuppressSaveConfirmation = $true
    $script:SaveCheckbox.Checked = $true
    if (-not $script:SaveConfigEnabled -or -not [System.IO.File]::Exists($script:ConfigPath) -or
        $script:KeyboardHeader.ColumnStyles[4].Width -ne 78) {
        throw 'Enabling config saving did not create the config and expose its purge action.'
    }
    Toggle-Inlays
    $script:IntervalsCheckbox.Checked = $true
    $script:ScaleRootCombo.SelectedIndex = 2
    $script:AccidentalCombo.SelectedIndex = 1
    Toggle-OptionalString
    Apply-TuningPreset -PresetName 'Drop D'
    Toggle-SelectedPitch -Pitch 0
    $script:SaveCheckbox.Checked = $false
    $savedRecord = [System.IO.File]::ReadAllText($script:ConfigPath)
    $expectedRecord = 's=0|i=0|v=1|r=2|a=1|x=1|t=Drop D|o=4,11,7,2,9,2,9|n=0'
    if ($savedRecord -ne $expectedRecord) {
        throw "Config record was not lean or complete. Found: $savedRecord"
    }

    $script:ShowInlays = $true
    $script:ShowIntervals = $false
    $script:RootPitch = 0
    $script:UseSharps = $false
    $script:HasOptionalString = $false
    $script:CurrentTuningName = 'E standard'
    $script:OpenStrings = @(4, 11, 7, 2, 9, 4, 11)
    $script:SelectedPitches.Clear()
    Import-SavedConfig
    if ($script:SaveConfigEnabled -or $script:ShowInlays -or -not $script:ShowIntervals -or
        $script:RootPitch -ne 2 -or -not $script:UseSharps -or
        -not $script:HasOptionalString -or $script:CurrentTuningName -ne 'Drop D' -or
        (@($script:OpenStrings) -join ',') -ne '4,11,7,2,9,2,9' -or
        (@($script:SelectedPitches | Sort-Object) -join ',') -ne '0') {
        throw 'A config with Save off did not restore its saved launch state.'
    }

    Purge-SavedConfig
    if ([System.IO.File]::Exists($script:ConfigPath) -or $script:KeyboardHeader.ColumnStyles[4].Width -ne 0) {
        throw 'Purging config did not remove the file and conditional purge action.'
    }
    $script:ShowInlays = $true
    $script:ShowIntervals = $false
    $script:RootPitch = 0
    $script:UseSharps = $false
    $script:HasOptionalString = $false
    $script:OptionalStringWasConfigured = $false
    $script:CurrentTuningName = 'E standard'
    $script:OpenStrings = @(4, 11, 7, 2, 9, 4, 11)
    $script:SelectedPitches.Clear()
    $script:UpdatingUi = $true
    $script:TuningCombo.SelectedIndex = $script:TuningCombo.FindStringExact('E standard')
    $script:ScaleRootCombo.SelectedIndex = 0
    $script:AccidentalCombo.SelectedIndex = 0
    $script:IntervalsCheckbox.Checked = $false
    $script:SaveCheckbox.Checked = $false
    $script:UpdatingUi = $false
    Update-InlayButtonAppearance
    Update-StringLayout
    Update-OpenStringItems
    Update-PitchButtons
    Update-Fretboard
    Update-SelectedSummary
    $script:SuppressSaveConfirmation = $false
    $sixStringSingleCenters = @(Get-InlayCenterUnits -Fret 3 -StringCount 6)
    $sevenStringSingleCenters = @(Get-InlayCenterUnits -Fret 3 -StringCount 7)
    $sixStringDoubleCenters = @(Get-InlayCenterUnits -Fret 12 -StringCount 6)
    $sevenStringDoubleCenters = @(Get-InlayCenterUnits -Fret 12 -StringCount 7)
    if ($sixStringSingleCenters.Count -ne 1 -or $sixStringSingleCenters[0] -ne 3.0 -or
        $sevenStringSingleCenters.Count -ne 1 -or $sevenStringSingleCenters[0] -ne 3.5 -or
        ($sixStringDoubleCenters -join ',') -ne '2,4' -or
        ($sevenStringDoubleCenters -join ',') -ne '2.5,4.5') {
        throw 'Inlay centers do not match the six-string and seven-string layouts.'
    }
    if (@(Get-InlayCenterUnits -Fret 4 -StringCount 6).Count -ne 0) {
        throw 'Only frets 3, 5, 7, 9, and 12 should receive inlays.'
    }
    if ($script:TuningPresets.Count -ne 14 -or $script:TuningCombo.Items.Count -ne 15) {
        throw 'Expected 14 tuning presets plus Custom.'
    }

    foreach ($pitch in @(0, 2, 4, 7)) {
        [void]$script:SelectedPitches.Add($pitch)
    }
    if (@(Get-PossibleScaleNames).Count -ne 0) {
        throw 'Possible scales should not appear for only a few notes.'
    }
    $script:SelectedPitches.Clear()
    foreach ($pitch in @(1, 2, 4, 6, 7, 9, 11)) {
        [void]$script:SelectedPitches.Add($pitch)
    }
    $dMajorMatches = @(Get-PossibleScaleNames)
    if ($dMajorMatches.Count -ne 7 -or $dMajorMatches -notcontains 'D Major/Ionian' -or $dMajorMatches -notcontains 'B Minor/Aeolian') {
        throw 'D major pitches did not produce the expected modal scale possibilities.'
    }
    Update-PitchButtons
    Update-Fretboard
    Update-SelectedSummary
    $buttonFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $clearButtonClick = $script:ClearSelectionButton.GetType().GetMethod('OnClick', $buttonFlags)
    [void]$clearButtonClick.Invoke($script:ClearSelectionButton, @([System.EventArgs]::Empty))
    if ($script:SelectedPitches.Count -ne 0 -or $script:SelectedLabel.Text -ne 'No notes selected' -or $script:ScaleMatchesLabel.Text -ne '') {
        throw 'Clear selection button did not reset selected notes and scale possibilities.'
    }
    $inlaysButtonClick = $script:InlaysButton.GetType().GetMethod('OnClick', $buttonFlags)
    [void]$inlaysButtonClick.Invoke($script:InlaysButton, @([System.EventArgs]::Empty))
    if ($script:ShowInlays -or $script:InlaysButton.Text -ne 'Inlays: Off' -or
        $script:InlaysButton.FlatAppearance.BorderSize -ne 1) {
        throw 'The inlay button did not disable the inlays.'
    }
    [void]$inlaysButtonClick.Invoke($script:InlaysButton, @([System.EventArgs]::Empty))
    if (-not $script:ShowInlays -or $script:InlaysButton.Text -ne 'Inlays: On' -or
        $script:InlaysButton.FlatAppearance.BorderSize -ne 2) {
        throw 'The inlay button did not re-enable and expose its active state.'
    }

    $testFretCell = $script:FretCells['0,1']
    $controlFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $onMouseEnter = $testFretCell.GetType().GetMethod('OnMouseEnter', $controlFlags)
    $onMouseLeave = $testFretCell.GetType().GetMethod('OnMouseLeave', $controlFlags)
    $onClick = $testFretCell.GetType().GetMethod('OnClick', $controlFlags)
    $initialTestPitch = Get-FretPitch -Row 0 -Fret 1
    $initialTestName = (Get-NoteNames)[$initialTestPitch]
    $expectedHoverColor = Mix-Color -Foreground $script:PitchColors[$initialTestPitch] -Background (Get-NeutralCellColor -Row 0 -Fret 1) -Weight 0.33
    [void]$onMouseEnter.Invoke($testFretCell, @([System.EventArgs]::Empty))
    if ($testFretCell.BackColor.ToArgb() -ne $expectedHoverColor.ToArgb()) {
        throw 'Fret cell hover did not apply the expected note-color blend.'
    }
    [void]$onMouseLeave.Invoke($testFretCell, @([System.EventArgs]::Empty))
    if ($testFretCell.BackColor.ToArgb() -ne (Get-NeutralCellColor -Row 0 -Fret 1).ToArgb()) {
        throw 'Fret cell hover did not restore its neutral color.'
    }
    [void]$onClick.Invoke($testFretCell, @([System.EventArgs]::Empty))
    if (-not $script:SelectedPitches.Contains($initialTestPitch) -or $script:SelectedLabel.Text -ne "Selected: $initialTestName") {
        throw 'Clicking a fret cell did not toggle its corresponding pitch.'
    }
    [void]$onClick.Invoke($testFretCell, @([System.EventArgs]::Empty))
    if ($script:SelectedPitches.Contains($initialTestPitch) -or $script:SelectedLabel.Text -ne 'No notes selected') {
        throw 'Clicking a selected fret cell did not toggle its pitch off.'
    }
    $script:OpenCombos[0].SelectedIndex = 5
    [void]$onClick.Invoke($testFretCell, @([System.EventArgs]::Empty))
    if (-not $script:SelectedPitches.Contains(6)) {
        throw 'Fret cell click did not follow the retuned string pitch.'
    }
    [void]$onClick.Invoke($testFretCell, @([System.EventArgs]::Empty))
    $script:OpenCombos[0].SelectedIndex = 2

    if ($script:ScaleIntervals.Count -ne 18 -or $script:ScaleCombo.Items.Count -ne 19) {
        throw 'Expected Custom plus 18 Berklee scale families.'
    }
    if (-not $script:ScaleRootCombo.Enabled -or $script:ScaleRootCombo.Items.Count -ne 12) {
        throw 'Root selector should remain available while the scale is Custom.'
    }
    $script:ScaleRootCombo.SelectedIndex = 1
    if ([string]$script:ScaleRootCombo.SelectedItem -ne 'Db' -or $script:RootPitch -ne 1 -or
        $script:SelectedPitches.Count -ne 0 -or (Get-IntervalLabel -Pitch 8) -ne '5') {
        throw 'Root selector should update the interval reference without changing Custom notes.'
    }

    $scaleCombinationCount = 0
    foreach ($scaleName in $script:ScaleIntervals.Keys) {
        if (-not $script:ScaleRoots.Contains($scaleName)) {
            throw "Missing root list for $scaleName."
        }

        $roots = $script:ScaleRoots[$scaleName]
        $scaleCombinationCount += $roots.Count
        foreach ($rootName in $roots) {
            if (-not $script:RootPitches.ContainsKey([string]$rootName)) {
                throw "Missing pitch mapping for root $rootName."
            }
        }
    }
    if ($scaleCombinationCount -ne 258) {
        throw 'Expected 258 Berklee scale and root combinations.'
    }

    $script:ScaleCombo.SelectedIndex = $script:ScaleCombo.FindStringExact('Major')
    $script:ScaleRootCombo.SelectedIndex = $script:ScaleRootCombo.FindStringExact('D')
    $selectedPitchList = @($script:SelectedPitches | Sort-Object) -join ','
    if ($selectedPitchList -ne '1,2,4,6,7,9,11') {
        throw 'D Major did not select the expected pitches.'
    }

    Toggle-SelectedPitch -Pitch 0
    if ([string]$script:ScaleCombo.SelectedItem -ne 'Custom' -or -not $script:SelectedPitches.Contains(0) -or -not $script:ScaleRootCombo.Enabled) {
        throw 'Manual pitch selection did not switch the scale to Custom.'
    }

    $script:ScaleCombo.SelectedIndex = $script:ScaleCombo.FindStringExact('Major')
    Apply-TuningPreset -PresetName 'E standard'
    if ($script:OpenStrings[0] -ne 4 -or $script:OpenStrings[5] -ne 4) {
        throw 'E standard preset did not apply.'
    }
    if ([string]$script:ScaleCombo.SelectedItem -ne 'Custom') {
        throw 'Tuning change did not switch the scale to Custom.'
    }

    $script:ScaleCombo.SelectedIndex = $script:ScaleCombo.FindStringExact('Major')
    $script:OpenCombos[0].SelectedIndex = 5
    if ([string]$script:ScaleCombo.SelectedItem -ne 'Custom' -or [string]$script:TuningCombo.SelectedItem -ne 'Custom') {
        throw 'Manual string tuning did not switch the tuning and scale to Custom.'
    }

    Apply-TuningPreset -PresetName 'D standard'
    $script:ScaleCombo.SelectedIndex = $script:ScaleCombo.FindStringExact('Major')
    $script:ScaleRootCombo.SelectedIndex = $script:ScaleRootCombo.FindStringExact('D')

    Toggle-OptionalString
    if (-not $script:HasOptionalString -or $script:StringToggleButton.Text -ne 'Remove string' -or $script:StringLabels[6].Text -ne '7 low' -or $script:OpenStrings[6] -ne 9) {
        throw 'Optional string did not use the D standard low A pitch.'
    }
    Toggle-OptionalString

    Apply-TuningPreset -PresetName 'D standard'
    $script:OpenCombos[0].SelectedIndex = 5
    Toggle-OptionalString
    if ($script:OpenStrings[6] -ne 11) {
        throw 'Custom tuning did not default an unconfigured optional string to B.'
    }
    $script:OpenCombos[6].SelectedIndex = 0
    Toggle-OptionalString
    Toggle-OptionalString
    if ($script:OpenStrings[6] -ne 0 -or $script:OpenCombos[6].SelectedIndex -ne 0) {
        throw 'Optional string tuning did not persist after remove and add.'
    }

    Apply-TuningPreset -PresetName 'E standard'
    if ($script:OpenStrings[6] -ne 11 -or $script:CurrentTuningName -ne 'E standard') {
        throw 'Preset selection did not tune the visible optional string.'
    }
    $script:ScaleCombo.SelectedIndex = $script:ScaleCombo.FindStringExact('Major')
    $script:ScaleRootCombo.SelectedIndex = $script:ScaleRootCombo.FindStringExact('D')

    if ($ScreenshotPath) {
        $script:ScaleCombo.SelectedIndex = $script:ScaleCombo.FindStringExact('Major')
        $script:ScaleRootCombo.SelectedIndex = $script:ScaleRootCombo.FindStringExact('D')
        Set-ScaleToCustom
        $script:IntervalsCheckbox.Checked = $true
        $script:Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $script:Form.Location = New-Object System.Drawing.Point(-20000, -20000)
        $script:Form.ShowInTaskbar = $false
        $script:Form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        if (-not $script:ShowInlays) {
            Toggle-Inlays
        }
        [System.Windows.Forms.Application]::DoEvents()
        Update-PitchKeyboardLayout
        Update-ScaleMatches
        $inlayCell = $script:FretCells['3,3']
        if ($inlayCell.Parent -ne $script:FretPanel -or $inlayCell.Controls.Count -ne 0) {
            throw 'Inlays should paint directly on the clickable fret cells without overlay controls.'
        }
        $inlayPitch = Get-FretPitch -Row 3 -Fret 3
        $inlayPitchWasSelected = $script:SelectedPitches.Contains($inlayPitch)
        $inlayCellClick = $inlayCell.GetType().GetMethod('OnClick', $controlFlags)
        [void]$inlayCellClick.Invoke($inlayCell, @([System.EventArgs]::Empty))
        if ($script:SelectedPitches.Contains($inlayPitch) -eq $inlayPitchWasSelected) {
            throw 'An enabled inlay obstructed its fret cell click.'
        }
        [void]$inlayCellClick.Invoke($inlayCell, @([System.EventArgs]::Empty))
        if ($script:SelectedPitches.Contains($inlayPitch) -ne $inlayPitchWasSelected) {
            throw 'The marked fret cell did not toggle back to its original state.'
        }
        $inlayCellBitmap = New-Object System.Drawing.Bitmap($inlayCell.Width, $inlayCell.Height)
        $inlayCell.DrawToBitmap($inlayCellBitmap, (New-Object System.Drawing.Rectangle(0, 0, $inlayCellBitmap.Width, $inlayCellBitmap.Height)))
        $inlaySample = $inlayCellBitmap.GetPixel(
            ([int]($inlayCellBitmap.Width / 2) + 7),
            [int]($inlayCellBitmap.Height / 2)
        )
        $inlayCellBitmap.Dispose()
        if ($inlaySample.ToArgb() -ne [System.Drawing.Color]::White.ToArgb()) {
            throw 'The rendered inlay should use a solid white fill.'
        }
        $intervalCell = $script:FretCells['0,2']
        $intervalPitch = Get-FretPitch -Row 0 -Fret 2
        if (-not $script:SelectedPitches.Contains($intervalPitch) -or (Get-IntervalLabel -Pitch $intervalPitch) -ne '3') {
            throw 'The interval rendering test cell should be the selected major third above D.'
        }
        $script:ShowIntervals = $false
        $intervalCell.Invalidate()
        [System.Windows.Forms.Application]::DoEvents()
        $intervalOffBitmap = New-Object System.Drawing.Bitmap($intervalCell.Width, $intervalCell.Height)
        $intervalCell.DrawToBitmap($intervalOffBitmap, (New-Object System.Drawing.Rectangle(0, 0, $intervalOffBitmap.Width, $intervalOffBitmap.Height)))
        $script:ShowIntervals = $true
        $intervalCell.Invalidate()
        [System.Windows.Forms.Application]::DoEvents()
        $intervalOnBitmap = New-Object System.Drawing.Bitmap($intervalCell.Width, $intervalCell.Height)
        $intervalCell.DrawToBitmap($intervalOnBitmap, (New-Object System.Drawing.Rectangle(0, 0, $intervalOnBitmap.Width, $intervalOnBitmap.Height)))
        $intervalPixelDifferences = 0
        for ($sampleX = 0; $sampleX -lt [Math]::Min(24, $intervalCell.Width); $sampleX++) {
            for ($sampleY = 0; $sampleY -lt [Math]::Min(16, $intervalCell.Height); $sampleY++) {
                if ($intervalOffBitmap.GetPixel($sampleX, $sampleY).ToArgb() -ne $intervalOnBitmap.GetPixel($sampleX, $sampleY).ToArgb()) {
                    $intervalPixelDifferences++
                }
            }
        }
        $intervalOffBitmap.Dispose()
        $intervalOnBitmap.Dispose()
        if ($intervalPixelDifferences -eq 0) {
            throw 'Enabling Intervals did not render a visible corner label on a selected fret.'
        }
        $naturalKey = $script:PitchButtons[0]
        $accidentalKey = $script:PitchButtons[1]
        if ($accidentalKey.Width -ge $naturalKey.Width -or $accidentalKey.Height -ge $naturalKey.Height) {
            throw 'Accidental keys should be narrower and shorter than natural keys.'
        }
        if ($script:PitchKeyboardPanel.Controls.GetChildIndex($accidentalKey) -ge $script:PitchKeyboardPanel.Controls.GetChildIndex($naturalKey)) {
            throw 'Accidental keys should render above natural keys.'
        }
        $nextNaturalKey = $script:PitchButtons[2]
        if ($accidentalKey.Left -ge $naturalKey.Right -or $accidentalKey.Right -le $nextNaturalKey.Left) {
            throw 'Accidental keys should overlap both neighboring natural keys.'
        }
        if ($naturalKey.TextAlign -ne [System.Drawing.ContentAlignment]::BottomCenter -or $accidentalKey.TextAlign -ne [System.Drawing.ContentAlignment]::BottomCenter) {
            throw 'Keyboard key labels should be aligned near the bottoms of their keys.'
        }
        if ($script:ScaleRootCombo.Bounds.Right -gt $script:ScaleRootGroup.ClientRectangle.Right) {
            throw 'Root selector extends beyond its layout cell.'
        }
        foreach ($comboLayout in @(
            @($script:TuningCombo, $script:TuningGroup),
            @($script:ScaleCombo, $script:ScaleGroup),
            @($script:ScaleRootCombo, $script:ScaleRootGroup),
            @($script:AccidentalCombo, $script:AccidentalGroup)
        )) {
            $combo = $comboLayout[0]
            $group = $comboLayout[1]
            if ($combo.Bounds.Bottom -gt ($group.ClientRectangle.Bottom - 2)) {
                throw 'Header dropdown does not have enough lower-edge clearance.'
            }
            if ($combo.Bounds.Right -gt $group.ClientRectangle.Right) {
                throw 'Header dropdown extends beyond its layout cell.'
            }
        }
        if ($script:InstrumentControls.DisplayRectangle.Right -lt $script:AccidentalGroup.Bounds.Right -or
            $script:MusicControls.DisplayRectangle.Right -lt $script:ClearGroup.Bounds.Right) {
            throw 'A workflow control extends beyond the left header area.'
        }
        if ($script:KeyboardGroup.Bounds.Bottom -gt $script:ControlBar.ClientRectangle.Bottom -or
            $script:KeyboardGroup.Width -ge ($script:ControlBar.ClientSize.Width / 2)) {
            throw 'The note keyboard should fit compactly in the right header area.'
        }
        if ($naturalKey.Width -ge 90) {
            throw 'Natural keys should remain compact at the default window size.'
        }
        if ($script:SelectedLabel.Height -gt 22) {
            throw 'Selected-note summary exceeded its single-line row.'
        }
        if ([string]::IsNullOrWhiteSpace($script:ScaleMatchesLabel.Text)) {
            throw 'Expected fitting D major scale possibilities in the summary row.'
        }
        $script:SuppressSaveConfirmation = $true
        $script:SaveCheckbox.Checked = $true
        [System.Windows.Forms.Application]::DoEvents()
        if (-not $script:PurgeSaveButton.Visible -or
            $script:InlaysButton.Bounds.Right -gt $script:IntervalsCheckbox.Bounds.Left -or
            $script:IntervalsCheckbox.Bounds.Right -gt $script:SaveCheckbox.Bounds.Left -or
            $script:SaveCheckbox.Bounds.Right -gt $script:PurgeSaveButton.Bounds.Left -or
            $script:PurgeSaveButton.Bounds.Right -gt $script:KeyboardHeader.ClientSize.Width) {
            throw 'Visible save controls overlap or extend beyond the keyboard header.'
        }
        $wideClientSize = $script:Form.ClientSize
        $script:Form.Size = $script:Form.MinimumSize
        [System.Windows.Forms.Application]::DoEvents()
        Update-PitchKeyboardLayout
        Update-ScaleMatches
        if ($script:AccidentalGroup.Bounds.Right -gt $script:InstrumentControls.ClientSize.Width -or
            $script:ClearGroup.Bounds.Right -gt $script:MusicControls.ClientSize.Width) {
            throw 'Workflow controls should remain visible at the minimum window size.'
        }
        if ($script:PitchButtons[0].Width -ge 70) {
            throw 'The note keyboard should remain compact at the minimum window size.'
        }
        if ($script:PurgeSaveButton.Bounds.Right -gt $script:KeyboardHeader.ClientSize.Width -or
            $script:IntervalsCheckbox.Bounds.Right -gt $script:SaveCheckbox.Bounds.Left -or
            $script:SaveCheckbox.Bounds.Right -gt $script:PurgeSaveButton.Bounds.Left) {
            throw 'Save controls should remain usable at the minimum window size.'
        }
        if (-not [string]::IsNullOrWhiteSpace($script:ScaleMatchesLabel.Text)) {
            throw 'Scale possibilities should hide when the complete list does not fit.'
        }
        $script:Form.ClientSize = $wideClientSize
        [System.Windows.Forms.Application]::DoEvents()
        Update-ScaleMatches
        if ([string]::IsNullOrWhiteSpace($script:ScaleMatchesLabel.Text)) {
            throw 'Scale possibilities did not return after enough space became available.'
        }
        Purge-SavedConfig
        $script:SuppressSaveConfirmation = $false
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:PurgeSaveButton.Visible -or $script:KeyboardHeader.ColumnStyles[4].Width -ne 0) {
            throw 'Purge save should disappear and release its header space after deletion.'
        }
        Set-FretCellHoverAppearance -Control $script:FretCells['0,1']
        $bitmap = New-Object System.Drawing.Bitmap($script:Form.Width, $script:Form.Height)
        $script:Form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)))
        $bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        $script:Form.Hide()
    }

    Write-Output 'WinForms fretboard validation passed.'
    $script:Form.Dispose()
    return
}

[void][System.Windows.Forms.Application]::Run($script:Form)
