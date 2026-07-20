[CmdletBinding()]
param(
    [switch] $SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:SchemaVersion = 1
$script:ScorePerFood = 100
$script:MinimumConsoleWidth = 50
$script:MinimumConsoleHeight = 16
$script:PersistenceWarning = ""
$script:Random = New-Object System.Random
$script:ColorNames = @(
    "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta",
    "DarkYellow", "Gray", "DarkGray", "Blue", "Green", "Cyan",
    "Red", "Magenta", "Yellow", "White"
)

$script:PresetDefinitions = @(
    [pscustomobject] @{
        Name             = "Classic"
        Mode             = "Solo"
        TickMilliseconds = 100
        Edges            = "Border"
        GrowthPerFood    = 3
        StartingLength   = 4
        PlayerCount      = 2
        CorpseObstacles  = $false
        RoundEndRule     = "OneLeft"
    },
    [pscustomobject] @{
        Name             = "Quick"
        Mode             = "Solo"
        TickMilliseconds = 65
        Edges            = "Border"
        GrowthPerFood    = 2
        StartingLength   = 4
        PlayerCount      = 2
        CorpseObstacles  = $false
        RoundEndRule     = "OneLeft"
    },
    [pscustomobject] @{
        Name             = "Wrap"
        Mode             = "Solo"
        TickMilliseconds = 90
        Edges            = "Wrap"
        GrowthPerFood    = 3
        StartingLength   = 5
        PlayerCount      = 2
        CorpseObstacles  = $false
        RoundEndRule     = "OneLeft"
    },
    [pscustomobject] @{
        Name             = "Battle"
        Mode             = "Battle"
        TickMilliseconds = 90
        Edges            = "Border"
        GrowthPerFood    = 2
        StartingLength   = 4
        PlayerCount      = 2
        CorpseObstacles  = $false
        RoundEndRule     = "OneLeft"
    },
    [pscustomobject] @{
        Name             = "Last Stand"
        Mode             = "Battle"
        TickMilliseconds = 85
        Edges            = "Wrap"
        GrowthPerFood    = 3
        StartingLength   = 4
        PlayerCount      = 3
        CorpseObstacles  = $true
        RoundEndRule     = "AllDead"
    }
)

function Initialize-NativeConsole {
    if ("PijiN.SnakeConsole" -as [type]) {
        return
    }

$nativeCode = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace PijiN
{
    public static class SnakeConsole
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct Coord
        {
            public short X;
            public short Y;

            public Coord(short x, short y)
            {
                X = x;
                Y = y;
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SmallRect
        {
            public short Left;
            public short Top;
            public short Right;
            public short Bottom;
        }

        [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
        private struct CharInfo
        {
            [FieldOffset(0)]
            public char UnicodeChar;

            [FieldOffset(2)]
            public short Attributes;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int handleType);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool WriteConsoleOutputW(
            IntPtr consoleOutput,
            [MarshalAs(UnmanagedType.LPArray), In] CharInfo[] buffer,
            Coord bufferSize,
            Coord bufferCoord,
            ref SmallRect writeRegion);

        private const int StdOutputHandle = -11;

        public static void WriteBuffer(
            int left,
            int top,
            int width,
            int height,
            char[] characters,
            short[] attributes)
        {
            int cellCount = checked(width * height);
            if (characters == null || characters.Length != cellCount)
            {
                throw new ArgumentException("Character buffer has the wrong size.");
            }
            if (attributes == null || attributes.Length != cellCount)
            {
                throw new ArgumentException("Attribute buffer has the wrong size.");
            }

            CharInfo[] cells = new CharInfo[cellCount];
            for (int index = 0; index < cellCount; index++)
            {
                cells[index].UnicodeChar = characters[index];
                cells[index].Attributes = attributes[index];
            }

            WriteCells(left, top, width, height, cells);
        }

        public static void WritePair(
            int left,
            int top,
            char first,
            char second,
            short attribute)
        {
            CharInfo[] cells = new CharInfo[2];
            cells[0].UnicodeChar = first;
            cells[0].Attributes = attribute;
            cells[1].UnicodeChar = second;
            cells[1].Attributes = attribute;
            WriteCells(left, top, 2, 1, cells);
        }

        private static void WriteCells(
            int left,
            int top,
            int width,
            int height,
            CharInfo[] cells)
        {
            SmallRect region = new SmallRect();
            region.Left = checked((short)left);
            region.Top = checked((short)top);
            region.Right = checked((short)(left + width - 1));
            region.Bottom = checked((short)(top + height - 1));

            bool succeeded = WriteConsoleOutputW(
                GetStdHandle(StdOutputHandle),
                cells,
                new Coord(checked((short)width), checked((short)height)),
                new Coord(0, 0),
                ref region);

            if (!succeeded)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $nativeCode
}

function Get-ConsoleSnapshot {
    [pscustomobject] @{
        Width      = [Console]::WindowWidth
        Height     = [Console]::WindowHeight
        WindowLeft = [Console]::WindowLeft
        WindowTop  = [Console]::WindowTop
    }
}

function Test-ConsoleSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot
    )

    return (
        [Console]::WindowWidth -eq $Snapshot.Width -and
        [Console]::WindowHeight -eq $Snapshot.Height -and
        [Console]::WindowLeft -eq $Snapshot.WindowLeft -and
        [Console]::WindowTop -eq $Snapshot.WindowTop
    )
}

function Get-ColorValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    return [ConsoleColor] ([Enum]::Parse([ConsoleColor], $Name, $true))
}

function Get-ConsoleAttribute {
    param(
        [ConsoleColor] $Foreground = [ConsoleColor]::Gray,
        [ConsoleColor] $Background = [ConsoleColor]::Black
    )

    return [int16] (([int] $Foreground) -bor (([int] $Background) -shl 4))
}

function Get-DimColorName {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    switch ($Name) {
        "Blue"       { return "DarkBlue" }
        "Green"      { return "DarkGreen" }
        "Cyan"       { return "DarkCyan" }
        "Red"        { return "DarkRed" }
        "Magenta"    { return "DarkMagenta" }
        "Yellow"     { return "DarkYellow" }
        "White"      { return "DarkGray" }
        "Gray"       { return "DarkGray" }
        default       { return $Name }
    }
}

function New-DefaultSettings {
    [pscustomobject] @{
        Preset           = "Classic"
        Mode             = "Solo"
        TickMilliseconds = 100
        Edges            = "Border"
        GrowthPerFood    = 3
        StartingLength   = 4
        PlayerCount      = 2
        CorpseObstacles  = $false
        RoundEndRule     = "OneLeft"
        Colors            = [pscustomobject] @{
            Snake1 = "Green"
            Snake2 = "Cyan"
            Snake3 = "Magenta"
            Food   = "Red"
            Border = "DarkGray"
        }
    }
}

function New-DefaultData {
    [pscustomobject] @{
        SchemaVersion = $script:SchemaVersion
        Settings      = New-DefaultSettings
        Runs          = @()
    }
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        $DefaultValue
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }

    return $property.Value
}

function Test-Choice {
    param(
        [string] $Value,
        [string[]] $Allowed,
        [string] $DefaultValue
    )

    if ($Allowed -contains $Value) {
        return $Value
    }

    return $DefaultValue
}

function Import-SnakeData {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $data = New-DefaultData
    if (-not [IO.File]::Exists($Path)) {
        return $data
    }

    try {
        $loaded = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $source = Get-ObjectPropertyValue -Object $loaded -Name "Settings" -DefaultValue $null
        $settings = $data.Settings

        $settings.Mode = Test-Choice -Value ([string] (Get-ObjectPropertyValue $source "Mode" $settings.Mode)) -Allowed @("Solo", "Battle") -DefaultValue $settings.Mode
        $settings.Edges = Test-Choice -Value ([string] (Get-ObjectPropertyValue $source "Edges" $settings.Edges)) -Allowed @("Border", "Wrap") -DefaultValue $settings.Edges
        $settings.RoundEndRule = Test-Choice -Value ([string] (Get-ObjectPropertyValue $source "RoundEndRule" $settings.RoundEndRule)) -Allowed @("OneLeft", "AllDead") -DefaultValue $settings.RoundEndRule
        $settings.TickMilliseconds = [Math]::Max(35, [Math]::Min(250, [int] (Get-ObjectPropertyValue $source "TickMilliseconds" $settings.TickMilliseconds)))
        $settings.GrowthPerFood = [Math]::Max(1, [Math]::Min(10, [int] (Get-ObjectPropertyValue $source "GrowthPerFood" $settings.GrowthPerFood)))
        $settings.StartingLength = [Math]::Max(3, [Math]::Min(10, [int] (Get-ObjectPropertyValue $source "StartingLength" $settings.StartingLength)))
        $settings.PlayerCount = [Math]::Max(2, [Math]::Min(3, [int] (Get-ObjectPropertyValue $source "PlayerCount" $settings.PlayerCount)))
        $settings.CorpseObstacles = [bool] (Get-ObjectPropertyValue $source "CorpseObstacles" $settings.CorpseObstacles)

        $loadedColors = Get-ObjectPropertyValue $source "Colors" $null
        foreach ($colorProperty in @("Snake1", "Snake2", "Snake3", "Food", "Border")) {
            $currentColor = [string] (Get-ObjectPropertyValue $settings.Colors $colorProperty "Gray")
            $loadedColor = [string] (Get-ObjectPropertyValue $loadedColors $colorProperty $currentColor)
            if ($script:ColorNames -contains $loadedColor) {
                $settings.Colors.$colorProperty = $loadedColor
            }
        }

        $loadedRuns = Get-ObjectPropertyValue -Object $loaded -Name "Runs" -DefaultValue @()
        $data.Runs = @($loadedRuns | Where-Object {
            $null -ne $_.PSObject.Properties["TimestampUtc"] -and
            $null -ne $_.PSObject.Properties["Mode"] -and
            $null -ne $_.PSObject.Properties["Score"]
        })

        Update-DetectedPreset -Settings $settings
    }
    catch {
        $script:PersistenceWarning = "Could not read Snake.json. Defaults are active: {0}" -f $_.Exception.Message
    }

    return $data
}

function Export-SnakeData {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $temporaryPath = "{0}.{1}.tmp" -f $Path, ([Guid]::NewGuid().ToString("N"))
    $backupPath = "{0}.{1}.bak" -f $Path, ([Guid]::NewGuid().ToString("N"))
    try {
        $directory = [IO.Path]::GetDirectoryName($Path)
        if (-not [IO.Directory]::Exists($directory)) {
            [void] [IO.Directory]::CreateDirectory($directory)
        }

        $json = $Data | ConvertTo-Json -Depth 8
        $utf8 = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($temporaryPath, $json, $utf8)

        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temporaryPath, $Path, $backupPath)
        }
        else {
            [IO.File]::Move($temporaryPath, $Path)
        }
        $script:PersistenceWarning = ""
    }
    catch {
        $script:PersistenceWarning = "Could not save Snake.json: {0}" -f $_.Exception.Message
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) {
            try {
                [IO.File]::Delete($temporaryPath)
            }
            catch {
            }
        }
        if ([IO.File]::Exists($backupPath)) {
            try {
                [IO.File]::Delete($backupPath)
            }
            catch {
            }
        }
    }
}

function Test-SettingsMatchPreset {
    param(
        [Parameter(Mandatory = $true)]
        $Settings,
        [Parameter(Mandatory = $true)]
        $Preset
    )

    return (
        $Settings.Mode -eq $Preset.Mode -and
        $Settings.TickMilliseconds -eq $Preset.TickMilliseconds -and
        $Settings.Edges -eq $Preset.Edges -and
        $Settings.GrowthPerFood -eq $Preset.GrowthPerFood -and
        $Settings.StartingLength -eq $Preset.StartingLength -and
        $Settings.PlayerCount -eq $Preset.PlayerCount -and
        $Settings.CorpseObstacles -eq $Preset.CorpseObstacles -and
        $Settings.RoundEndRule -eq $Preset.RoundEndRule
    )
}

function Update-DetectedPreset {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $Settings.Preset = "Custom"
    foreach ($preset in $script:PresetDefinitions) {
        if (Test-SettingsMatchPreset -Settings $Settings -Preset $preset) {
            $Settings.Preset = $preset.Name
            break
        }
    }
}

function Set-SettingsFromPreset {
    param(
        [Parameter(Mandatory = $true)]
        $Settings,
        [Parameter(Mandatory = $true)]
        $Preset
    )

    foreach ($property in @(
        "Mode", "TickMilliseconds", "Edges", "GrowthPerFood",
        "StartingLength", "PlayerCount", "CorpseObstacles", "RoundEndRule"
    )) {
        $Settings.$property = $Preset.$property
    }
    $Settings.Preset = $Preset.Name
}

function Get-RuleText {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $edgeText = $(if ($Settings.Edges -eq "Border") { "Border" } else { "Wrap" })
    if ($Settings.Mode -eq "Solo") {
        return "Solo {0} {1}ms G{2} L{3}" -f $edgeText, $Settings.TickMilliseconds, $Settings.GrowthPerFood, $Settings.StartingLength
    }

    $endText = $(if ($Settings.RoundEndRule -eq "OneLeft") { "OneLeft" } else { "AllDead" })
    $corpseText = ""
    if ($Settings.PlayerCount -eq 3) {
        $corpseText = " Corpses:{0}" -f $(if ($Settings.CorpseObstacles) { "On" } else { "Off" })
    }

    return "Battle {0}P {1} {2}ms G{3} L{4}{5} End:{6}" -f $Settings.PlayerCount, $edgeText, $Settings.TickMilliseconds, $Settings.GrowthPerFood, $Settings.StartingLength, $corpseText, $endText
}

function Copy-RunRules {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    [pscustomobject] @{
        Mode             = $Settings.Mode
        TickMilliseconds = $Settings.TickMilliseconds
        Edges            = $Settings.Edges
        GrowthPerFood    = $Settings.GrowthPerFood
        StartingLength   = $Settings.StartingLength
        PlayerCount      = $Settings.PlayerCount
        CorpseObstacles  = $Settings.CorpseObstacles
        RoundEndRule     = $Settings.RoundEndRule
    }
}

function New-Canvas {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot,
        [int16] $DefaultAttribute = 7
    )

    $cellCount = $Snapshot.Width * $Snapshot.Height
    $characters = New-Object "char[]" $cellCount
    $attributes = New-Object "int16[]" $cellCount
    for ($index = 0; $index -lt $cellCount; $index++) {
        $characters[$index] = [char] " "
        $attributes[$index] = $DefaultAttribute
    }

    [pscustomobject] @{
        Snapshot   = $Snapshot
        Characters = $characters
        Attributes = $attributes
    }
}

function Set-CanvasText {
    param(
        [Parameter(Mandatory = $true)]
        $Canvas,
        [Parameter(Mandatory = $true)]
        [int] $Row,
        [Parameter(Mandatory = $true)]
        [int] $Column,
        [Parameter(Mandatory = $true)]
        [string] $Text,
        [int16] $Attribute = 7
    )

    if ($Row -lt 0 -or $Row -ge $Canvas.Snapshot.Height) {
        return
    }

    for ($offset = 0; $offset -lt $Text.Length; $offset++) {
        $x = $Column + $offset
        if ($x -lt 0) {
            continue
        }
        if ($x -ge $Canvas.Snapshot.Width) {
            break
        }

        $bufferIndex = ($Row * $Canvas.Snapshot.Width) + $x
        $Canvas.Characters[$bufferIndex] = $Text[$offset]
        $Canvas.Attributes[$bufferIndex] = $Attribute
    }
}

function Set-CanvasCenteredText {
    param(
        [Parameter(Mandatory = $true)]
        $Canvas,
        [Parameter(Mandatory = $true)]
        [int] $Row,
        [Parameter(Mandatory = $true)]
        [string] $Text,
        [int16] $Attribute = 7
    )

    $column = [Math]::Max(0, [Math]::Floor(($Canvas.Snapshot.Width - $Text.Length) / 2))
    Set-CanvasText -Canvas $Canvas -Row $Row -Column $column -Text $Text -Attribute $Attribute
}

function Write-Canvas {
    param(
        [Parameter(Mandatory = $true)]
        $Canvas
    )

    $snapshot = $Canvas.Snapshot
    [PijiN.SnakeConsole]::WriteBuffer(
        $snapshot.WindowLeft,
        $snapshot.WindowTop,
        $snapshot.Width,
        $snapshot.Height,
        $Canvas.Characters,
        $Canvas.Attributes
    )
}

function Clear-InputBuffer {
    while ([Console]::KeyAvailable) {
        [void] [Console]::ReadKey($true)
    }
}

function Get-MenuNumberFromKey {
    param(
        [Parameter(Mandatory = $true)]
        [ConsoleKey] $Key
    )

    switch ($Key) {
        "D1"      { return 1 }
        "NumPad1" { return 1 }
        "D2"      { return 2 }
        "NumPad2" { return 2 }
        "D3"      { return 3 }
        "NumPad3" { return 3 }
        "D4"      { return 4 }
        "NumPad4" { return 4 }
        "D5"      { return 5 }
        "NumPad5" { return 5 }
        "D6"      { return 6 }
        "NumPad6" { return 6 }
        "D7"      { return 7 }
        "NumPad7" { return 7 }
        "D8"      { return 8 }
        "NumPad8" { return 8 }
        "D9"      { return 9 }
        "NumPad9" { return 9 }
    }

    return 0
}

function Get-SortedRuns {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [ValidateSet("All", "Solo", "Battle")]
        [string] $Filter = "All",
        [ValidateSet("Score", "Newest")]
        [string] $SortMode = "Score"
    )

    $runs = @($Data.Runs)
    if ($Filter -ne "All") {
        $runs = @($runs | Where-Object { [string] $_.Mode -eq $Filter })
    }

    if ($SortMode -eq "Newest") {
        return @($runs | Sort-Object -Property @{ Expression = { [string] $_.TimestampUtc }; Descending = $true })
    }

    return @($runs | Sort-Object -Property @(
        @{ Expression = { [int] $_.Score }; Descending = $true },
        @{ Expression = { [string] $_.TimestampUtc }; Descending = $true }
    ))
}

function Get-RunDateText {
    param(
        [Parameter(Mandatory = $true)]
        $Run
    )

    try {
        return ([DateTime]::Parse([string] $Run.TimestampUtc)).ToLocalTime().ToString("yyyy-MM-dd HH:mm")
    }
    catch {
        return [string] $Run.TimestampUtc
    }
}

function Get-RunResultText {
    param(
        [Parameter(Mandatory = $true)]
        $Run
    )

    if ([string] $Run.Mode -eq "Solo") {
        return "Score {0,7}" -f ([int] $Run.Score)
    }

    $winner = [int] (Get-ObjectPropertyValue $Run "WinnerNumber" 0)
    $playerScores = @((Get-ObjectPropertyValue $Run "PlayerScores" @()))
    $scoreParts = @()
    for ($index = 0; $index -lt $playerScores.Count; $index++) {
        $scoreParts += "P{0}:{1}" -f ($index + 1), ([int] $playerScores[$index])
    }
    $scoreText = $scoreParts -join "/"
    if ($winner -gt 0) {
        return "P{0} win {1}" -f $winner, $scoreText
    }

    return "Draw {0}" -f $scoreText
}

function Get-RunRuleText {
    param(
        [Parameter(Mandatory = $true)]
        $Run
    )

    $storedText = [string] (Get-ObjectPropertyValue $Run "RuleText" "")
    if (-not [string]::IsNullOrWhiteSpace($storedText)) {
        return $storedText
    }

    $rules = Get-ObjectPropertyValue $Run "Rules" $null
    if ($null -ne $rules) {
        return Get-RuleText -Settings $rules
    }

    return [string] $Run.Mode
}

function Show-Highscores {
    param(
        [Parameter(Mandatory = $true)]
        $Data
    )

    $filters = @("All", "Solo", "Battle")
    $filterIndex = 0
    $sortMode = "Score"
    $page = 0

    while ($true) {
        $snapshot = Get-ConsoleSnapshot
        $canvas = New-Canvas -Snapshot $snapshot -DefaultAttribute (Get-ConsoleAttribute -Foreground Gray)
        $titleAttribute = Get-ConsoleAttribute -Foreground Yellow
        $headingAttribute = Get-ConsoleAttribute -Foreground Cyan
        $dimAttribute = Get-ConsoleAttribute -Foreground DarkGray

        Set-CanvasCenteredText -Canvas $canvas -Row 1 -Text "SNAKE RUN HISTORY" -Attribute $titleAttribute
        Set-CanvasCenteredText -Canvas $canvas -Row 2 -Text ("Filter: {0}   Sort: {1}   Runs saved: {2}" -f $filters[$filterIndex], $sortMode, @($Data.Runs).Count) -Attribute $headingAttribute

        $pageSize = [Math]::Max(3, $snapshot.Height - 8)
        $runs = @(Get-SortedRuns -Data $Data -Filter $filters[$filterIndex] -SortMode $sortMode)
        $pageCount = [Math]::Max(1, [Math]::Ceiling($runs.Count / [double] $pageSize))
        if ($page -ge $pageCount) {
            $page = $pageCount - 1
        }
        if ($page -lt 0) {
            $page = 0
        }

        Set-CanvasText -Canvas $canvas -Row 4 -Column 1 -Text "Rank  Result                  Preset       Rules and settings | Date" -Attribute $headingAttribute
        $startIndex = $page * $pageSize
        for ($rowIndex = 0; $rowIndex -lt $pageSize; $rowIndex++) {
            $runIndex = $startIndex + $rowIndex
            if ($runIndex -ge $runs.Count) {
                break
            }

            $run = $runs[$runIndex]
            $resultText = Get-RunResultText -Run $run
            $presetText = [string] (Get-ObjectPropertyValue $run "Preset" "Custom")
            $ruleText = Get-RunRuleText -Run $run
            $dateText = Get-RunDateText -Run $run
            $line = "{0,4}  {1,-23} {2,-12} {3} | {4}" -f ($runIndex + 1), $resultText, $presetText, $ruleText, $dateText
            Set-CanvasText -Canvas $canvas -Row (5 + $rowIndex) -Column 1 -Text $line -Attribute (Get-ConsoleAttribute -Foreground Gray)
        }

        if ($runs.Count -eq 0) {
            Set-CanvasCenteredText -Canvas $canvas -Row ([Math]::Floor($snapshot.Height / 2)) -Text "No completed runs match this filter yet." -Attribute $dimAttribute
        }

        $footer = "LEFT/RIGHT or PGUP/PGDN: page   TAB: filter   T: sort   ENTER/ESC/H: back   Page {0}/{1}" -f ($page + 1), $pageCount
        Set-CanvasCenteredText -Canvas $canvas -Row ($snapshot.Height - 2) -Text $footer -Attribute $dimAttribute
        Write-Canvas -Canvas $canvas

        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            "LeftArrow" { $page-- }
            "PageUp"    { $page-- }
            "RightArrow" { $page++ }
            "PageDown"   { $page++ }
            "Home"       { $page = 0 }
            "End"        { $page = $pageCount - 1 }
            "Tab" {
                $filterIndex++
                if ($filterIndex -ge $filters.Count) {
                    $filterIndex = 0
                }
                $page = 0
            }
            "T" {
                if ($sortMode -eq "Score") {
                    $sortMode = "Newest"
                }
                else {
                    $sortMode = "Score"
                }
                $page = 0
            }
            "Enter"  { return }
            "Escape" { return }
            "H"      { return }
        }
    }
}

function Get-ColorMenuOptions {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $options = @(
        [pscustomobject] @{ Id = "Snake1"; Label = "Snake 1" }
    )
    if ($Settings.Mode -eq "Battle") {
        $options += [pscustomobject] @{ Id = "Snake2"; Label = "Snake 2" }
        if ($Settings.PlayerCount -eq 3) {
            $options += [pscustomobject] @{ Id = "Snake3"; Label = "Snake 3" }
        }
    }
    $options += @(
        [pscustomobject] @{ Id = "Food"; Label = "Food" },
        [pscustomobject] @{ Id = "Border"; Label = "Border" },
        [pscustomobject] @{ Id = "Back"; Label = "Back" }
    )

    return $options
}

function Step-ColorSetting {
    param(
        [Parameter(Mandatory = $true)]
        $Settings,
        [Parameter(Mandatory = $true)]
        [string] $Property,
        [int] $Delta
    )

    $current = [string] $Settings.Colors.$Property
    $index = [Array]::IndexOf($script:ColorNames, $current)
    if ($index -lt 0) {
        $index = 0
    }
    $index += $Delta
    if ($index -lt 0) {
        $index = $script:ColorNames.Count - 1
    }
    if ($index -ge $script:ColorNames.Count) {
        $index = 0
    }
    $Settings.Colors.$Property = $script:ColorNames[$index]
}

function Show-ColorMenu {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [string] $DataPath
    )

    $selected = 0
    while ($true) {
        $options = @(Get-ColorMenuOptions -Settings $Data.Settings)
        if ($selected -ge $options.Count) {
            $selected = $options.Count - 1
        }

        $snapshot = Get-ConsoleSnapshot
        $canvas = New-Canvas -Snapshot $snapshot -DefaultAttribute (Get-ConsoleAttribute -Foreground Gray)
        Set-CanvasCenteredText -Canvas $canvas -Row 1 -Text "COLORS" -Attribute (Get-ConsoleAttribute -Foreground Yellow)
        Set-CanvasCenteredText -Canvas $canvas -Row 2 -Text "Each logical game cell is two console columns wide." -Attribute (Get-ConsoleAttribute -Foreground DarkGray)

        $menuWidth = 44
        $menuColumn = [Math]::Max(1, [Math]::Floor(($snapshot.Width - $menuWidth) / 2))
        for ($index = 0; $index -lt $options.Count; $index++) {
            $option = $options[$index]
            $row = 5 + $index
            $isSelected = ($selected -eq $index)
            $lineAttribute = $(if ($isSelected) {
                Get-ConsoleAttribute -Foreground White -Background DarkBlue
            }
            else {
                Get-ConsoleAttribute -Foreground Gray
            })

            if ($option.Id -eq "Back") {
                $line = $(if ($isSelected) { "> Back" } else { "  Back" })
                Set-CanvasText -Canvas $canvas -Row $row -Column $menuColumn -Text $line.PadRight($menuWidth) -Attribute $lineAttribute
                continue
            }

            $colorName = [string] $Data.Settings.Colors.($option.Id)
            $line = "{0} {1,-12}: {2,-14}" -f $(if ($isSelected) { ">" } else { " " }), $option.Label, $colorName
            Set-CanvasText -Canvas $canvas -Row $row -Column $menuColumn -Text $line.PadRight($menuWidth) -Attribute $lineAttribute

            $color = Get-ColorValue -Name $colorName
            $previewAttribute = Get-ConsoleAttribute -Foreground Black -Background $color
            if ($option.Id -eq "Food" -or $option.Id -eq "Border") {
                $previewAttribute = Get-ConsoleAttribute -Foreground $color
            }
            $previewText = $(if ($option.Id -eq "Food") { "<>" } elseif ($option.Id -eq "Border") { "##" } else { "  " })
            Set-CanvasText -Canvas $canvas -Row $row -Column ($menuColumn + $menuWidth - 5) -Text $previewText -Attribute $previewAttribute
        }

        Set-CanvasCenteredText -Canvas $canvas -Row ($snapshot.Height - 2) -Text "UP/DOWN: select   LEFT/RIGHT: change   ENTER: choose   ESC: back" -Attribute (Get-ConsoleAttribute -Foreground DarkGray)
        Write-Canvas -Canvas $canvas

        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            "UpArrow" {
                $selected--
                if ($selected -lt 0) { $selected = $options.Count - 1 }
            }
            "W" {
                $selected--
                if ($selected -lt 0) { $selected = $options.Count - 1 }
            }
            "DownArrow" {
                $selected++
                if ($selected -ge $options.Count) { $selected = 0 }
            }
            "S" {
                $selected++
                if ($selected -ge $options.Count) { $selected = 0 }
            }
            "LeftArrow" {
                if ($options[$selected].Id -ne "Back") {
                    Step-ColorSetting -Settings $Data.Settings -Property $options[$selected].Id -Delta -1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "A" {
                if ($options[$selected].Id -ne "Back") {
                    Step-ColorSetting -Settings $Data.Settings -Property $options[$selected].Id -Delta -1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "RightArrow" {
                if ($options[$selected].Id -ne "Back") {
                    Step-ColorSetting -Settings $Data.Settings -Property $options[$selected].Id -Delta 1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "D" {
                if ($options[$selected].Id -ne "Back") {
                    Step-ColorSetting -Settings $Data.Settings -Property $options[$selected].Id -Delta 1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "Enter" {
                if ($options[$selected].Id -eq "Back") {
                    return
                }
                Step-ColorSetting -Settings $Data.Settings -Property $options[$selected].Id -Delta 1
                Export-SnakeData -Data $Data -Path $DataPath
            }
            "Spacebar" {
                if ($options[$selected].Id -eq "Back") {
                    return
                }
                Step-ColorSetting -Settings $Data.Settings -Property $options[$selected].Id -Delta 1
                Export-SnakeData -Data $Data -Path $DataPath
            }
            "Escape" { return }
        }
    }
}

function Get-MainMenuOptions {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $speed = 1000.0 / $Settings.TickMilliseconds
    $options = @(
        [pscustomobject] @{ Id = "Start"; Text = "[1] Start Game"; Adjustable = $false; Shortcut = 1 },
        [pscustomobject] @{ Id = "Preset"; Text = "[2] Preset: {0}" -f $Settings.Preset; Adjustable = $true; Shortcut = 2 },
        [pscustomobject] @{ Id = "Mode"; Text = "[3] Mode: {0}" -f $Settings.Mode; Adjustable = $true; Shortcut = 3 },
        [pscustomobject] @{ Id = "Speed"; Text = "[4] Speed: {0}ms ({1:N1} cells/sec)" -f $Settings.TickMilliseconds, $speed; Adjustable = $true; Shortcut = 4 },
        [pscustomobject] @{ Id = "Edges"; Text = "[5] Edges: {0}" -f $Settings.Edges; Adjustable = $true; Shortcut = 5 },
        [pscustomobject] @{ Id = "Growth"; Text = "[6] Growth per food: {0}" -f $Settings.GrowthPerFood; Adjustable = $true; Shortcut = 6 },
        [pscustomobject] @{ Id = "Length"; Text = "[7] Starting length: {0}" -f $Settings.StartingLength; Adjustable = $true; Shortcut = 7 }
    )

    if ($Settings.Mode -eq "Battle") {
        $options += [pscustomobject] @{ Id = "Players"; Text = "[8] Players: {0}" -f $Settings.PlayerCount; Adjustable = $true; Shortcut = 8 }
        if ($Settings.PlayerCount -eq 3) {
            $corpseText = $(if ($Settings.CorpseObstacles) { "Dimmed obstacles" } else { "Disappear" })
            $options += [pscustomobject] @{ Id = "Corpses"; Text = "[9] Eliminated bodies: {0}" -f $corpseText; Adjustable = $true; Shortcut = 9 }
        }
        $endText = $(if ($Settings.RoundEndRule -eq "OneLeft") { "When one snake remains" } else { "After the last snake dies" })
        $options += [pscustomobject] @{ Id = "RoundEnd"; Text = "[R] Round ends: {0}" -f $endText; Adjustable = $true; Shortcut = 0 }
    }

    $options += @(
        [pscustomobject] @{ Id = "Colors"; Text = "[C] Colors..."; Adjustable = $false; Shortcut = 0 },
        [pscustomobject] @{ Id = "Highscores"; Text = "[H] Run History..."; Adjustable = $false; Shortcut = 0 },
        [pscustomobject] @{ Id = "Reset"; Text = "[X] Reset settings"; Adjustable = $false; Shortcut = 0 }
    )

    return $options
}

function Step-Preset {
    param(
        [Parameter(Mandatory = $true)]
        $Settings,
        [int] $Delta
    )

    $names = @($script:PresetDefinitions | ForEach-Object { $_.Name })
    $index = [Array]::IndexOf($names, [string] $Settings.Preset)
    if ($index -lt 0) {
        $index = $(if ($Delta -lt 0) { 0 } else { -1 })
    }
    $index += $Delta
    if ($index -lt 0) { $index = $script:PresetDefinitions.Count - 1 }
    if ($index -ge $script:PresetDefinitions.Count) { $index = 0 }
    Set-SettingsFromPreset -Settings $Settings -Preset $script:PresetDefinitions[$index]
}

function Step-MainMenuSetting {
    param(
        [Parameter(Mandatory = $true)]
        $Settings,
        [Parameter(Mandatory = $true)]
        [string] $Id,
        [int] $Delta
    )

    switch ($Id) {
        "Preset" { Step-Preset -Settings $Settings -Delta $Delta; return }
        "Mode" {
            $Settings.Mode = $(if ($Settings.Mode -eq "Solo") { "Battle" } else { "Solo" })
        }
        "Speed" {
            $Settings.TickMilliseconds = [Math]::Max(35, [Math]::Min(250, $Settings.TickMilliseconds + (5 * $Delta)))
        }
        "Edges" {
            $Settings.Edges = $(if ($Settings.Edges -eq "Border") { "Wrap" } else { "Border" })
        }
        "Growth" {
            $Settings.GrowthPerFood += $Delta
            if ($Settings.GrowthPerFood -lt 1) { $Settings.GrowthPerFood = 10 }
            if ($Settings.GrowthPerFood -gt 10) { $Settings.GrowthPerFood = 1 }
        }
        "Length" {
            $Settings.StartingLength += $Delta
            if ($Settings.StartingLength -lt 3) { $Settings.StartingLength = 10 }
            if ($Settings.StartingLength -gt 10) { $Settings.StartingLength = 3 }
        }
        "Players" {
            $Settings.PlayerCount = $(if ($Settings.PlayerCount -eq 2) { 3 } else { 2 })
        }
        "Corpses" {
            $Settings.CorpseObstacles = -not $Settings.CorpseObstacles
        }
        "RoundEnd" {
            $Settings.RoundEndRule = $(if ($Settings.RoundEndRule -eq "OneLeft") { "AllDead" } else { "OneLeft" })
        }
    }

    Update-DetectedPreset -Settings $Settings
}

function Draw-MainMenu {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [object[]] $Options,
        [int] $Selected
    )

    $snapshot = Get-ConsoleSnapshot
    $canvas = New-Canvas -Snapshot $snapshot -DefaultAttribute (Get-ConsoleAttribute -Foreground Gray)
    $titleAttribute = Get-ConsoleAttribute -Foreground Green
    $dimAttribute = Get-ConsoleAttribute -Foreground DarkGray
    $selectedAttribute = Get-ConsoleAttribute -Foreground White -Background DarkBlue

    Set-CanvasCenteredText -Canvas $canvas -Row 0 -Text "S N A K E" -Attribute $titleAttribute
    Set-CanvasCenteredText -Canvas $canvas -Row 1 -Text "PowerShell 5.1" -Attribute (Get-ConsoleAttribute -Foreground White)

    $menuColumn = 3
    $menuWidth = [Math]::Min(55, [Math]::Max(30, $snapshot.Width - 6))
    if ($snapshot.Width -ge 100) {
        $menuWidth = 52
    }

    for ($index = 0; $index -lt $Options.Count; $index++) {
        $row = 3 + $index
        if ($row -ge ($snapshot.Height - 2)) {
            break
        }
        $isSelected = ($index -eq $Selected)
        $prefix = $(if ($isSelected) { "> " } else { "  " })
        $attribute = $(if ($isSelected) { $selectedAttribute } else { Get-ConsoleAttribute -Foreground Gray })
        $line = ($prefix + $Options[$index].Text).PadRight($menuWidth)
        Set-CanvasText -Canvas $canvas -Row $row -Column $menuColumn -Text $line -Attribute $attribute
    }

    if ($snapshot.Width -ge 100) {
        $historyColumn = 59
        Set-CanvasText -Canvas $canvas -Row 3 -Column $historyColumn -Text "TOP SOLO RUNS" -Attribute (Get-ConsoleAttribute -Foreground Yellow)
        $runs = @(Get-SortedRuns -Data $Data -Filter "Solo" -SortMode "Score")
        $runCount = [Math]::Min(5, $runs.Count)
        for ($index = 0; $index -lt $runCount; $index++) {
            $run = $runs[$index]
            $line = "{0}. {1,7}  {2,-10} {3}" -f ($index + 1), ([int] $run.Score), ([string] (Get-ObjectPropertyValue $run "Preset" "Custom")), (Get-RunRuleText $run)
            Set-CanvasText -Canvas $canvas -Row (5 + $index) -Column $historyColumn -Text $line -Attribute (Get-ConsoleAttribute -Foreground Gray)
        }
        if ($runCount -eq 0) {
            Set-CanvasText -Canvas $canvas -Row 5 -Column $historyColumn -Text "No completed solo runs yet." -Attribute $dimAttribute
        }
    }

    $ruleText = "Current rules: {0} | {1}" -f $Data.Settings.Preset, (Get-RuleText -Settings $Data.Settings)
    Set-CanvasCenteredText -Canvas $canvas -Row ($snapshot.Height - 3) -Text $ruleText -Attribute $dimAttribute
    Set-CanvasCenteredText -Canvas $canvas -Row ($snapshot.Height - 2) -Text "UP/DOWN or W/S: select   LEFT/RIGHT or A/D: adjust   ENTER: choose   ESC: quit" -Attribute $dimAttribute
    if (-not [string]::IsNullOrWhiteSpace($script:PersistenceWarning)) {
        Set-CanvasCenteredText -Canvas $canvas -Row ($snapshot.Height - 1) -Text $script:PersistenceWarning -Attribute (Get-ConsoleAttribute -Foreground Red)
    }

    Write-Canvas -Canvas $canvas
}

function Show-MainMenu {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [string] $DataPath
    )

    $selected = 0
    while ($true) {
        $snapshot = Get-ConsoleSnapshot
        if ($snapshot.Width -lt 40 -or $snapshot.Height -lt 20) {
            $canvas = New-Canvas -Snapshot $snapshot
            Set-CanvasCenteredText -Canvas $canvas -Row ([Math]::Max(0, [Math]::Floor($snapshot.Height / 2) - 1)) -Text "Enlarge the terminal to use the Snake menu." -Attribute (Get-ConsoleAttribute -Foreground Yellow)
            Set-CanvasCenteredText -Canvas $canvas -Row ([Math]::Max(0, [Math]::Floor($snapshot.Height / 2) + 1)) -Text "Press any key to retry or ESC to quit." -Attribute (Get-ConsoleAttribute -Foreground DarkGray)
            Write-Canvas -Canvas $canvas
            if ([Console]::ReadKey($true).Key -eq [ConsoleKey]::Escape) {
                return [pscustomobject] @{ Action = "Quit" }
            }
            continue
        }

        $options = @(Get-MainMenuOptions -Settings $Data.Settings)
        if ($selected -ge $options.Count) {
            $selected = $options.Count - 1
        }
        Draw-MainMenu -Data $Data -Options $options -Selected $selected

        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            "UpArrow" {
                $selected--
                if ($selected -lt 0) { $selected = $options.Count - 1 }
            }
            "W" {
                $selected--
                if ($selected -lt 0) { $selected = $options.Count - 1 }
            }
            "DownArrow" {
                $selected++
                if ($selected -ge $options.Count) { $selected = 0 }
            }
            "S" {
                $selected++
                if ($selected -ge $options.Count) { $selected = 0 }
            }
            "LeftArrow" {
                if ($options[$selected].Adjustable) {
                    Step-MainMenuSetting -Settings $Data.Settings -Id $options[$selected].Id -Delta -1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "A" {
                if ($options[$selected].Adjustable) {
                    Step-MainMenuSetting -Settings $Data.Settings -Id $options[$selected].Id -Delta -1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "RightArrow" {
                if ($options[$selected].Adjustable) {
                    Step-MainMenuSetting -Settings $Data.Settings -Id $options[$selected].Id -Delta 1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "D" {
                if ($options[$selected].Adjustable) {
                    Step-MainMenuSetting -Settings $Data.Settings -Id $options[$selected].Id -Delta 1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "Enter" {
                $id = $options[$selected].Id
                switch ($id) {
                    "Start"      { return [pscustomobject] @{ Action = "Start" } }
                    "Colors"     { Show-ColorMenu -Data $Data -DataPath $DataPath }
                    "Highscores" { Show-Highscores -Data $Data }
                    "Reset" {
                        $Data.Settings = New-DefaultSettings
                        Export-SnakeData -Data $Data -Path $DataPath
                    }
                    default {
                        if ($options[$selected].Adjustable) {
                            Step-MainMenuSetting -Settings $Data.Settings -Id $id -Delta 1
                            Export-SnakeData -Data $Data -Path $DataPath
                        }
                    }
                }
            }
            "Spacebar" {
                $id = $options[$selected].Id
                if ($id -eq "Start") { return [pscustomobject] @{ Action = "Start" } }
                if ($id -eq "Colors") { Show-ColorMenu -Data $Data -DataPath $DataPath }
                elseif ($id -eq "Highscores") { Show-Highscores -Data $Data }
                elseif ($id -eq "Reset") {
                    $Data.Settings = New-DefaultSettings
                    Export-SnakeData -Data $Data -Path $DataPath
                }
                elseif ($options[$selected].Adjustable) {
                    Step-MainMenuSetting -Settings $Data.Settings -Id $id -Delta 1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "H" { Show-Highscores -Data $Data }
            "C" { Show-ColorMenu -Data $Data -DataPath $DataPath }
            "R" {
                $roundOption = @($options | Where-Object { $_.Id -eq "RoundEnd" })
                if ($roundOption.Count -gt 0) {
                    $selected = [Array]::IndexOf($options, $roundOption[0])
                    Step-MainMenuSetting -Settings $Data.Settings -Id "RoundEnd" -Delta 1
                    Export-SnakeData -Data $Data -Path $DataPath
                }
            }
            "X" {
                $Data.Settings = New-DefaultSettings
                Export-SnakeData -Data $Data -Path $DataPath
            }
            "Escape" { return [pscustomobject] @{ Action = "Quit" } }
            default {
                $number = Get-MenuNumberFromKey -Key $key
                if ($number -gt 0) {
                    for ($index = 0; $index -lt $options.Count; $index++) {
                        if ($options[$index].Shortcut -eq $number) {
                            $selected = $index
                            if ($options[$index].Id -eq "Start") {
                                return [pscustomobject] @{ Action = "Start" }
                            }
                            if ($options[$index].Adjustable) {
                                Step-MainMenuSetting -Settings $Data.Settings -Id $options[$index].Id -Delta 1
                                Export-SnakeData -Data $Data -Path $DataPath
                            }
                            break
                        }
                    }
                }
            }
        }
    }
}

function New-SnakePlayer {
    param(
        [int] $Number,
        [int] $HeadX,
        [int] $HeadY,
        [int] $Dx,
        [int] $Dy,
        [int] $StartingLength,
        [int] $BoardWidth,
        [string] $ColorName
    )

    $body = New-Object "System.Collections.Generic.Queue[int]"
    for ($distance = $StartingLength - 1; $distance -ge 0; $distance--) {
        $x = $HeadX - ($Dx * $distance)
        $y = $HeadY - ($Dy * $distance)
        $body.Enqueue([int] (($y * $BoardWidth) + $x))
    }

    [pscustomobject] @{
        Number          = $Number
        X               = $HeadX
        Y               = $HeadY
        Dx              = $Dx
        Dy              = $Dy
        PendingDx       = $Dx
        PendingDy       = $Dy
        HeadIndex       = (($HeadY * $BoardWidth) + $HeadX)
        Body            = $body
        Active          = $true
        CorpseDim       = $false
        GrowthPending   = 0
        Score           = 0
        FoodEaten       = 0
        PeakLength      = $StartingLength
        FinalLength     = $StartingLength
        ColorName       = $ColorName
    }
}

function New-FoodIndex {
    param(
        [Parameter(Mandatory = $true)]
        $Game
    )

    $freeCells = New-Object "System.Collections.Generic.List[int]"
    $minimumX = $(if ($Game.Settings.Edges -eq "Border") { 1 } else { 0 })
    $maximumX = $(if ($Game.Settings.Edges -eq "Border") { $Game.BoardWidth - 2 } else { $Game.BoardWidth - 1 })
    $minimumY = $(if ($Game.Settings.Edges -eq "Border") { 1 } else { 0 })
    $maximumY = $(if ($Game.Settings.Edges -eq "Border") { $Game.BoardHeight - 2 } else { $Game.BoardHeight - 1 })

    for ($y = $minimumY; $y -le $maximumY; $y++) {
        $rowStart = $y * $Game.BoardWidth
        for ($x = $minimumX; $x -le $maximumX; $x++) {
            $cellIndex = $rowStart + $x
            if ($Game.Occupancy[$cellIndex] -eq 0) {
                $freeCells.Add($cellIndex)
            }
        }
    }

    if ($freeCells.Count -eq 0) {
        return -1
    }

    return $freeCells[$script:Random.Next($freeCells.Count)]
}

function New-GameState {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot,
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $boardWidth = [Math]::Floor($Snapshot.Width / 2)
    $boardHeight = $Snapshot.Height - 1
    $requiredWidth = [Math]::Max(18, ($Settings.StartingLength * 3))
    $requiredHeight = [Math]::Max(10, ($Settings.StartingLength + 4))
    if (
        $Snapshot.Width -lt $script:MinimumConsoleWidth -or
        $Snapshot.Height -lt $script:MinimumConsoleHeight -or
        $boardWidth -lt $requiredWidth -or
        $boardHeight -lt $requiredHeight
    ) {
        return [pscustomobject] @{
            Status  = "TooSmall"
            Message = "The terminal is too small for these rules. Enlarge it or reduce Starting Length."
        }
    }

    $boardCellCount = $boardWidth * $boardHeight
    $screenCellCount = $Snapshot.Width * $Snapshot.Height
    $occupancy = New-Object "int[]" $boardCellCount
    $screenCharacters = New-Object "char[]" $screenCellCount
    $screenAttributes = New-Object "int16[]" $screenCellCount
    for ($index = 0; $index -lt $screenCellCount; $index++) {
        $screenCharacters[$index] = [char] " "
        $screenAttributes[$index] = [int16] 0
    }

    $minimumX = $(if ($Settings.Edges -eq "Border") { 1 } else { 0 })
    $maximumX = $(if ($Settings.Edges -eq "Border") { $boardWidth - 2 } else { $boardWidth - 1 })
    $minimumY = $(if ($Settings.Edges -eq "Border") { 1 } else { 0 })
    $maximumY = $(if ($Settings.Edges -eq "Border") { $boardHeight - 2 } else { $boardHeight - 1 })
    $middleX = [Math]::Floor(($minimumX + $maximumX) / 2)
    $middleY = [Math]::Floor(($minimumY + $maximumY) / 2)

    $snakes = @()
    if ($Settings.Mode -eq "Solo") {
        $headX = [Math]::Max($minimumX + $Settings.StartingLength - 1, $middleX)
        $snakes += New-SnakePlayer -Number 1 -HeadX $headX -HeadY $middleY -Dx 1 -Dy 0 -StartingLength $Settings.StartingLength -BoardWidth $boardWidth -ColorName $Settings.Colors.Snake1
    }
    else {
        $upperY = [Math]::Max($minimumY + 2, [Math]::Floor($minimumY + (($maximumY - $minimumY) / 3)))
        $leftHeadX = [Math]::Max($minimumX + $Settings.StartingLength - 1, [Math]::Floor($minimumX + (($maximumX - $minimumX) / 4)))
        $rightHeadX = [Math]::Min($maximumX - $Settings.StartingLength + 1, [Math]::Floor($minimumX + ((($maximumX - $minimumX) * 3) / 4)))
        $snakes += New-SnakePlayer -Number 1 -HeadX $leftHeadX -HeadY $upperY -Dx 1 -Dy 0 -StartingLength $Settings.StartingLength -BoardWidth $boardWidth -ColorName $Settings.Colors.Snake1
        $snakes += New-SnakePlayer -Number 2 -HeadX $rightHeadX -HeadY $upperY -Dx -1 -Dy 0 -StartingLength $Settings.StartingLength -BoardWidth $boardWidth -ColorName $Settings.Colors.Snake2

        if ($Settings.PlayerCount -eq 3) {
            $lowerHeadY = [Math]::Min($maximumY - $Settings.StartingLength + 1, [Math]::Floor($minimumY + ((($maximumY - $minimumY) * 3) / 4)))
            $snakes += New-SnakePlayer -Number 3 -HeadX $middleX -HeadY $lowerHeadY -Dx 0 -Dy -1 -StartingLength $Settings.StartingLength -BoardWidth $boardWidth -ColorName $Settings.Colors.Snake3
        }
    }

    foreach ($snake in $snakes) {
        foreach ($cellIndex in $snake.Body.ToArray()) {
            if ($cellIndex -lt 0 -or $cellIndex -ge $occupancy.Length -or $occupancy[$cellIndex] -ne 0) {
                return [pscustomobject] @{
                    Status  = "TooSmall"
                    Message = "The terminal does not provide safe starting positions for these rules."
                }
            }
            $occupancy[$cellIndex] = $snake.Number
        }
    }

    $snakeCount = $snakes.Count
    $game = [pscustomobject] @{
        Status           = "Ready"
        Snapshot         = $Snapshot
        Settings         = $Settings
        BoardWidth       = $boardWidth
        BoardHeight      = $boardHeight
        Occupancy        = $occupancy
        Snakes           = @($snakes)
        FoodIndex        = -1
        ScreenCharacters = $screenCharacters
        ScreenAttributes = $screenAttributes
        HeaderCharacters = (New-Object "char[]" $Snapshot.Width)
        HeaderAttributes = (New-Object "int16[]" $Snapshot.Width)
        DirtyFlags       = (New-Object "bool[]" $boardCellCount)
        DirtyCells       = (New-Object "System.Collections.Generic.List[int]")
        NextX            = (New-Object "int[]" $snakeCount)
        NextY            = (New-Object "int[]" $snakeCount)
        NextIndex        = (New-Object "int[]" $snakeCount)
        Crashed          = (New-Object "bool[]" $snakeCount)
        EatsFood         = (New-Object "bool[]" $snakeCount)
        TailVacates      = (New-Object "bool[]" $snakeCount)
        TailIndexes      = (New-Object "int[]" $snakeCount)
        TickCount        = 0
        LastStanding     = 0
    }

    $game.FoodIndex = New-FoodIndex -Game $game
    return $game
}

function Set-LogicalCell {
    param(
        [Parameter(Mandatory = $true)]
        $Game,
        [Parameter(Mandatory = $true)]
        [int] $CellIndex,
        [switch] $Write
    )

    if ($CellIndex -lt 0 -or $CellIndex -ge $Game.Occupancy.Length) {
        return
    }

    $x = $CellIndex % $Game.BoardWidth
    $y = [Math]::Floor($CellIndex / $Game.BoardWidth)
    $first = [char] " "
    $second = [char] " "
    $attribute = [int16] 0

    $isBorder = (
        $Game.Settings.Edges -eq "Border" -and
        ($x -eq 0 -or $x -eq ($Game.BoardWidth - 1) -or $y -eq 0 -or $y -eq ($Game.BoardHeight - 1))
    )

    if ($isBorder) {
        $borderColor = Get-ColorValue -Name $Game.Settings.Colors.Border
        $attribute = Get-ConsoleAttribute -Foreground $borderColor
        if (($x -eq 0 -or $x -eq ($Game.BoardWidth - 1)) -and ($y -eq 0 -or $y -eq ($Game.BoardHeight - 1))) {
            $first = [char] "+"
            $second = [char] "+"
        }
        elseif ($y -eq 0 -or $y -eq ($Game.BoardHeight - 1)) {
            $first = [char] "-"
            $second = [char] "-"
        }
        else {
            $first = [char] "|"
            $second = [char] "|"
        }
    }
    elseif ($CellIndex -eq $Game.FoodIndex) {
        $foodColor = Get-ColorValue -Name $Game.Settings.Colors.Food
        $attribute = Get-ConsoleAttribute -Foreground $foodColor
        $first = [char] "<"
        $second = [char] ">"
    }
    elseif ($Game.Occupancy[$CellIndex] -gt 0) {
        $snake = $Game.Snakes[$Game.Occupancy[$CellIndex] - 1]
        if ($snake.CorpseDim) {
            $dimColor = Get-ColorValue -Name (Get-DimColorName -Name $snake.ColorName)
            $attribute = Get-ConsoleAttribute -Foreground $dimColor
            $first = [char] "."
            $second = [char] "."
        }
        elseif ($snake.Active -and $snake.HeadIndex -eq $CellIndex) {
            $snakeColor = Get-ColorValue -Name $snake.ColorName
            $attribute = Get-ConsoleAttribute -Foreground $snakeColor
            $first = [char] "["
            $second = [char] "]"
        }
        else {
            $snakeColor = Get-ColorValue -Name $snake.ColorName
            $attribute = Get-ConsoleAttribute -Foreground Black -Background $snakeColor
        }
    }

    $screenX = $x * 2
    $screenY = $y + 1
    $screenIndex = ($screenY * $Game.Snapshot.Width) + $screenX
    $Game.ScreenCharacters[$screenIndex] = $first
    $Game.ScreenCharacters[$screenIndex + 1] = $second
    $Game.ScreenAttributes[$screenIndex] = $attribute
    $Game.ScreenAttributes[$screenIndex + 1] = $attribute

    if ($Write) {
        [PijiN.SnakeConsole]::WritePair(
            $Game.Snapshot.WindowLeft + $screenX,
            $Game.Snapshot.WindowTop + $screenY,
            $first,
            $second,
            $attribute
        )
    }
}

function Add-DirtyCell {
    param(
        [Parameter(Mandatory = $true)]
        $Game,
        [int] $CellIndex
    )

    if ($CellIndex -lt 0 -or $CellIndex -ge $Game.DirtyFlags.Length) {
        return
    }
    if (-not $Game.DirtyFlags[$CellIndex]) {
        $Game.DirtyFlags[$CellIndex] = $true
        $Game.DirtyCells.Add($CellIndex)
    }
}

function Write-DirtyGameCells {
    param(
        [Parameter(Mandatory = $true)]
        $Game
    )

    foreach ($cellIndex in $Game.DirtyCells) {
        Set-LogicalCell -Game $Game -CellIndex $cellIndex -Write
        $Game.DirtyFlags[$cellIndex] = $false
    }
    $Game.DirtyCells.Clear()
}

function Add-HeaderText {
    param(
        [Parameter(Mandatory = $true)]
        $Game,
        [int] $Column,
        [Parameter(Mandatory = $true)]
        [string] $Text,
        [int16] $Attribute
    )

    for ($offset = 0; $offset -lt $Text.Length; $offset++) {
        $x = $Column + $offset
        if ($x -ge $Game.Snapshot.Width) {
            break
        }
        if ($x -ge 0) {
            $Game.HeaderCharacters[$x] = $Text[$offset]
            $Game.HeaderAttributes[$x] = $Attribute
        }
    }

    return $Column + $Text.Length
}

function Update-GameHeader {
    param(
        [Parameter(Mandatory = $true)]
        $Game,
        [string] $Message = "",
        [switch] $Write
    )

    for ($index = 0; $index -lt $Game.Snapshot.Width; $index++) {
        $Game.HeaderCharacters[$index] = [char] " "
        $Game.HeaderAttributes[$index] = Get-ConsoleAttribute -Foreground Gray
    }

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $column = [Math]::Max(0, [Math]::Floor(($Game.Snapshot.Width - $Message.Length) / 2))
        [void] (Add-HeaderText -Game $Game -Column $column -Text $Message -Attribute (Get-ConsoleAttribute -Foreground Yellow))
    }
    elseif ($Game.Settings.Mode -eq "Solo") {
        $snake = $Game.Snakes[0]
        $text = " SCORE {0:D7} | FOOD {1:D4} | LENGTH {2:D4} | {3}ms | P pause | ESC end run " -f $snake.Score, $snake.FoodEaten, $snake.Body.Count, $Game.Settings.TickMilliseconds
        [void] (Add-HeaderText -Game $Game -Column 0 -Text $text -Attribute (Get-ConsoleAttribute -Foreground (Get-ColorValue $snake.ColorName)))
    }
    else {
        $column = 0
        foreach ($snake in $Game.Snakes) {
            $stateText = $(if ($snake.Active) { "LIVE" } else { "OUT" })
            $text = " P{0}:{1:D6} {2} " -f $snake.Number, $snake.Score, $stateText
            $column = Add-HeaderText -Game $Game -Column $column -Text $text -Attribute (Get-ConsoleAttribute -Foreground (Get-ColorValue $snake.ColorName))
            $column = Add-HeaderText -Game $Game -Column $column -Text "|" -Attribute (Get-ConsoleAttribute -Foreground Gray)
        }
        [void] (Add-HeaderText -Game $Game -Column $column -Text " P pause | ESC end run " -Attribute (Get-ConsoleAttribute -Foreground Gray))
    }

    for ($index = 0; $index -lt $Game.Snapshot.Width; $index++) {
        $Game.ScreenCharacters[$index] = $Game.HeaderCharacters[$index]
        $Game.ScreenAttributes[$index] = $Game.HeaderAttributes[$index]
    }

    if ($Write) {
        [PijiN.SnakeConsole]::WriteBuffer(
            $Game.Snapshot.WindowLeft,
            $Game.Snapshot.WindowTop,
            $Game.Snapshot.Width,
            1,
            $Game.HeaderCharacters,
            $Game.HeaderAttributes
        )
    }
}

function Write-InitialGameScreen {
    param(
        [Parameter(Mandatory = $true)]
        $Game
    )

    for ($cellIndex = 0; $cellIndex -lt $Game.Occupancy.Length; $cellIndex++) {
        Set-LogicalCell -Game $Game -CellIndex $cellIndex
    }
    Update-GameHeader -Game $Game

    [PijiN.SnakeConsole]::WriteBuffer(
        $Game.Snapshot.WindowLeft,
        $Game.Snapshot.WindowTop,
        $Game.Snapshot.Width,
        $Game.Snapshot.Height,
        $Game.ScreenCharacters,
        $Game.ScreenAttributes
    )
}

function Show-GameCountdown {
    param(
        [Parameter(Mandatory = $true)]
        $Game
    )

    foreach ($number in @(3, 2, 1)) {
        if (-not (Test-ConsoleSnapshot -Snapshot $Game.Snapshot)) {
            return $false
        }
        Update-GameHeader -Game $Game -Message ("STARTING IN {0}" -f $number) -Write
        Start-Sleep -Milliseconds 450
    }
    Update-GameHeader -Game $Game -Write
    Clear-InputBuffer
    return $true
}

function Set-SnakeDirection {
    param(
        [Parameter(Mandatory = $true)]
        $Snake,
        [int] $Dx,
        [int] $Dy
    )

    if (-not $Snake.Active) {
        return
    }
    if (($Dx + $Snake.Dx) -eq 0 -and ($Dy + $Snake.Dy) -eq 0) {
        return
    }

    $Snake.PendingDx = $Dx
    $Snake.PendingDy = $Dy
}

function Read-GameInput {
    param(
        [Parameter(Mandatory = $true)]
        $Game
    )

    while ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            "W"          { Set-SnakeDirection -Snake $Game.Snakes[0] -Dx 0 -Dy -1 }
            "A"          { Set-SnakeDirection -Snake $Game.Snakes[0] -Dx -1 -Dy 0 }
            "S"          { Set-SnakeDirection -Snake $Game.Snakes[0] -Dx 0 -Dy 1 }
            "D"          { Set-SnakeDirection -Snake $Game.Snakes[0] -Dx 1 -Dy 0 }
            "UpArrow"    { if ($Game.Snakes.Count -ge 2) { Set-SnakeDirection -Snake $Game.Snakes[1] -Dx 0 -Dy -1 } }
            "LeftArrow"  { if ($Game.Snakes.Count -ge 2) { Set-SnakeDirection -Snake $Game.Snakes[1] -Dx -1 -Dy 0 } }
            "DownArrow"  { if ($Game.Snakes.Count -ge 2) { Set-SnakeDirection -Snake $Game.Snakes[1] -Dx 0 -Dy 1 } }
            "RightArrow" { if ($Game.Snakes.Count -ge 2) { Set-SnakeDirection -Snake $Game.Snakes[1] -Dx 1 -Dy 0 } }
            "I"          { if ($Game.Snakes.Count -ge 3) { Set-SnakeDirection -Snake $Game.Snakes[2] -Dx 0 -Dy -1 } }
            "J"          { if ($Game.Snakes.Count -ge 3) { Set-SnakeDirection -Snake $Game.Snakes[2] -Dx -1 -Dy 0 } }
            "K"          { if ($Game.Snakes.Count -ge 3) { Set-SnakeDirection -Snake $Game.Snakes[2] -Dx 0 -Dy 1 } }
            "L"          { if ($Game.Snakes.Count -ge 3) { Set-SnakeDirection -Snake $Game.Snakes[2] -Dx 1 -Dy 0 } }
            "P"          { return "Pause" }
            "Escape"     { return "Abort" }
        }
    }

    return "Continue"
}

function Wait-WhilePaused {
    param(
        [Parameter(Mandatory = $true)]
        $Game
    )

    Update-GameHeader -Game $Game -Message "PAUSED - P TO RESUME - ESC TO END RUN" -Write
    while ($true) {
        if (-not (Test-ConsoleSnapshot -Snapshot $Game.Snapshot)) {
            return "Resize"
        }
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).Key
            if ($key -eq [ConsoleKey]::P) {
                Update-GameHeader -Game $Game -Write
                Clear-InputBuffer
                return "Resume"
            }
            if ($key -eq [ConsoleKey]::Escape) {
                return "Abort"
            }
        }
        Start-Sleep -Milliseconds 20
    }
}

function Invoke-GameTick {
    param(
        [Parameter(Mandatory = $true)]
        $Game,
        [switch] $NoRender
    )

    $snakeCount = $Game.Snakes.Count
    $headerDirty = $false
    for ($index = 0; $index -lt $snakeCount; $index++) {
        $Game.NextX[$index] = 0
        $Game.NextY[$index] = 0
        $Game.NextIndex[$index] = -1
        $Game.Crashed[$index] = $false
        $Game.EatsFood[$index] = $false
        $Game.TailVacates[$index] = $false
        $Game.TailIndexes[$index] = -1
    }

    for ($index = 0; $index -lt $snakeCount; $index++) {
        $snake = $Game.Snakes[$index]
        if (-not $snake.Active) {
            continue
        }

        $snake.Dx = $snake.PendingDx
        $snake.Dy = $snake.PendingDy
        $nextX = $snake.X + $snake.Dx
        $nextY = $snake.Y + $snake.Dy

        if ($Game.Settings.Edges -eq "Wrap") {
            if ($nextX -lt 0) { $nextX = $Game.BoardWidth - 1 }
            elseif ($nextX -ge $Game.BoardWidth) { $nextX = 0 }
            if ($nextY -lt 0) { $nextY = $Game.BoardHeight - 1 }
            elseif ($nextY -ge $Game.BoardHeight) { $nextY = 0 }
        }
        elseif (
            $nextX -le 0 -or $nextX -ge ($Game.BoardWidth - 1) -or
            $nextY -le 0 -or $nextY -ge ($Game.BoardHeight - 1)
        ) {
            $Game.Crashed[$index] = $true
        }

        $Game.NextX[$index] = $nextX
        $Game.NextY[$index] = $nextY
        if (-not $Game.Crashed[$index]) {
            $nextCellIndex = ($nextY * $Game.BoardWidth) + $nextX
            $Game.NextIndex[$index] = $nextCellIndex
            $Game.EatsFood[$index] = ($Game.FoodIndex -ge 0 -and $nextCellIndex -eq $Game.FoodIndex)
        }

        if ($snake.Body.Count -gt 0) {
            $Game.TailIndexes[$index] = $snake.Body.Peek()
            $Game.TailVacates[$index] = ($snake.GrowthPending -le 0 -and -not $Game.EatsFood[$index])
        }
    }

    for ($index = 0; $index -lt $snakeCount; $index++) {
        $snake = $Game.Snakes[$index]
        if (-not $snake.Active -or $Game.Crashed[$index]) {
            continue
        }

        $targetIndex = $Game.NextIndex[$index]
        if ($Game.Occupancy[$targetIndex] -ne 0) {
            $vacatingTail = $false
            for ($tailOwnerIndex = 0; $tailOwnerIndex -lt $snakeCount; $tailOwnerIndex++) {
                if (
                    $Game.Snakes[$tailOwnerIndex].Active -and
                    $Game.TailVacates[$tailOwnerIndex] -and
                    $Game.TailIndexes[$tailOwnerIndex] -eq $targetIndex
                ) {
                    $vacatingTail = $true
                    break
                }
            }
            if (-not $vacatingTail) {
                $Game.Crashed[$index] = $true
            }
        }
    }

    for ($firstIndex = 0; $firstIndex -lt $snakeCount; $firstIndex++) {
        if (-not $Game.Snakes[$firstIndex].Active -or $Game.NextIndex[$firstIndex] -lt 0) {
            continue
        }
        for ($secondIndex = $firstIndex + 1; $secondIndex -lt $snakeCount; $secondIndex++) {
            if (-not $Game.Snakes[$secondIndex].Active -or $Game.NextIndex[$secondIndex] -lt 0) {
                continue
            }
            if ($Game.NextIndex[$firstIndex] -eq $Game.NextIndex[$secondIndex]) {
                $Game.Crashed[$firstIndex] = $true
                $Game.Crashed[$secondIndex] = $true
            }
        }
    }

    for ($index = 0; $index -lt $snakeCount; $index++) {
        $snake = $Game.Snakes[$index]
        if (-not $snake.Active -or -not $Game.TailVacates[$index]) {
            continue
        }
        if ($snake.Body.Count -gt 0) {
            $tailIndex = $snake.Body.Dequeue()
            $Game.Occupancy[$tailIndex] = 0
            Add-DirtyCell -Game $Game -CellIndex $tailIndex
        }
    }

    for ($index = 0; $index -lt $snakeCount; $index++) {
        $snake = $Game.Snakes[$index]
        if (-not $snake.Active -or -not $Game.Crashed[$index]) {
            continue
        }

        $snake.Active = $false
        $snake.FinalLength = $snake.Body.Count
        $headerDirty = $true
        Add-DirtyCell -Game $Game -CellIndex $snake.HeadIndex

        $keepCorpse = (
            $Game.Settings.Mode -eq "Battle" -and
            $Game.Settings.PlayerCount -eq 3 -and
            $Game.Settings.CorpseObstacles
        )
        if ($keepCorpse) {
            $snake.CorpseDim = $true
            foreach ($bodyIndex in $snake.Body.ToArray()) {
                Add-DirtyCell -Game $Game -CellIndex $bodyIndex
            }
        }
        elseif ($Game.Settings.Mode -eq "Battle") {
            foreach ($bodyIndex in $snake.Body.ToArray()) {
                $Game.Occupancy[$bodyIndex] = 0
                Add-DirtyCell -Game $Game -CellIndex $bodyIndex
            }
            $snake.Body.Clear()
        }
    }

    $foodConsumed = $false
    for ($index = 0; $index -lt $snakeCount; $index++) {
        $snake = $Game.Snakes[$index]
        if (-not $snake.Active -or $Game.Crashed[$index]) {
            continue
        }

        Add-DirtyCell -Game $Game -CellIndex $snake.HeadIndex
        $snake.X = $Game.NextX[$index]
        $snake.Y = $Game.NextY[$index]
        $snake.HeadIndex = $Game.NextIndex[$index]
        $snake.Body.Enqueue([int] $snake.HeadIndex)
        $Game.Occupancy[$snake.HeadIndex] = $snake.Number
        Add-DirtyCell -Game $Game -CellIndex $snake.HeadIndex

        if ($Game.EatsFood[$index]) {
            $snake.Score += $script:ScorePerFood
            $snake.FoodEaten++
            $snake.GrowthPending += $Game.Settings.GrowthPerFood
            $foodConsumed = $true
            $headerDirty = $true
        }
        if (-not $Game.TailVacates[$index] -and $snake.GrowthPending -gt 0) {
            $snake.GrowthPending--
        }

        $snake.FinalLength = $snake.Body.Count
        if ($snake.Body.Count -gt $snake.PeakLength) {
            $snake.PeakLength = $snake.Body.Count
        }
    }

    if ($foodConsumed) {
        $Game.FoodIndex = -1
    }
    if ($Game.FoodIndex -lt 0) {
        $newFoodIndex = New-FoodIndex -Game $Game
        if ($newFoodIndex -ge 0) {
            $Game.FoodIndex = $newFoodIndex
            Add-DirtyCell -Game $Game -CellIndex $newFoodIndex
        }
    }

    $Game.TickCount++
    if ($NoRender) {
        foreach ($cellIndex in $Game.DirtyCells) {
            $Game.DirtyFlags[$cellIndex] = $false
        }
        $Game.DirtyCells.Clear()
    }
    else {
        Write-DirtyGameCells -Game $Game
    }
    if ($headerDirty -and -not $NoRender) {
        Update-GameHeader -Game $Game -Write
    }

    $activeCount = 0
    $activeNumber = 0
    foreach ($snake in $Game.Snakes) {
        if ($snake.Active) {
            $activeCount++
            $activeNumber = $snake.Number
        }
    }

    if ($Game.Settings.Mode -eq "Solo") {
        if ($activeCount -eq 0) {
            return "SoloOver"
        }
        return "Continue"
    }

    if ($activeCount -eq 1 -and $Game.LastStanding -eq 0) {
        $Game.LastStanding = $activeNumber
    }

    if ($Game.Settings.RoundEndRule -eq "OneLeft") {
        if ($activeCount -eq 1) {
            return "Winner"
        }
        if ($activeCount -eq 0) {
            return "Draw"
        }
    }
    elseif ($activeCount -eq 0) {
        if ($Game.LastStanding -gt 0) {
            return "Winner"
        }
        return "Draw"
    }

    return "Continue"
}

function New-GameResult {
    param(
        [Parameter(Mandatory = $true)]
        $Game,
        [Parameter(Mandatory = $true)]
        [string] $Status,
        [string] $Outcome,
        [int] $WinnerNumber,
        [string] $Message,
        [double] $DurationMilliseconds
    )

    [pscustomobject] @{
        Status               = $Status
        Outcome              = $Outcome
        WinnerNumber         = $WinnerNumber
        Message              = $Message
        Snakes               = @($Game.Snakes)
        TickCount            = $Game.TickCount
        DurationMilliseconds = [Math]::Round($DurationMilliseconds)
    }
}

function Start-SnakeGame {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $snapshot = Get-ConsoleSnapshot
    $game = New-GameState -Snapshot $snapshot -Settings $Settings
    if ($game.Status -ne "Ready") {
        return [pscustomobject] @{
            Status               = $game.Status
            Outcome              = ""
            WinnerNumber         = 0
            Message              = $game.Message
            Snakes               = @()
            TickCount            = 0
            DurationMilliseconds = 0
        }
    }

    Write-InitialGameScreen -Game $game
    if (-not (Show-GameCountdown -Game $game)) {
        return New-GameResult -Game $game -Status "Resize" -Outcome "" -WinnerNumber 0 -Message "The terminal was resized before the run started." -DurationMilliseconds 0
    }

    $clock = [Diagnostics.Stopwatch]::StartNew()
    [double] $nextTick = $Settings.TickMilliseconds
    while ($true) {
        while ($clock.Elapsed.TotalMilliseconds -lt $nextTick) {
            if (-not (Test-ConsoleSnapshot -Snapshot $snapshot)) {
                return New-GameResult -Game $game -Status "Resize" -Outcome "" -WinnerNumber 0 -Message "The terminal was resized. The run was cancelled." -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
            }

            $inputAction = Read-GameInput -Game $game
            if ($inputAction -eq "Abort") {
                return New-GameResult -Game $game -Status "Aborted" -Outcome "" -WinnerNumber 0 -Message "Run ended by player." -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
            }
            if ($inputAction -eq "Pause") {
                $pauseAction = Wait-WhilePaused -Game $game
                if ($pauseAction -eq "Abort") {
                    return New-GameResult -Game $game -Status "Aborted" -Outcome "" -WinnerNumber 0 -Message "Run ended by player." -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
                }
                if ($pauseAction -eq "Resize") {
                    return New-GameResult -Game $game -Status "Resize" -Outcome "" -WinnerNumber 0 -Message "The terminal was resized. The run was cancelled." -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
                }
                $nextTick = $clock.Elapsed.TotalMilliseconds + $Settings.TickMilliseconds
            }
            Start-Sleep -Milliseconds 2
        }

        $inputAction = Read-GameInput -Game $game
        if ($inputAction -eq "Abort") {
            return New-GameResult -Game $game -Status "Aborted" -Outcome "" -WinnerNumber 0 -Message "Run ended by player." -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
        }
        if ($inputAction -eq "Pause") {
            $pauseAction = Wait-WhilePaused -Game $game
            if ($pauseAction -eq "Abort") {
                return New-GameResult -Game $game -Status "Aborted" -Outcome "" -WinnerNumber 0 -Message "Run ended by player." -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
            }
            if ($pauseAction -eq "Resize") {
                return New-GameResult -Game $game -Status "Resize" -Outcome "" -WinnerNumber 0 -Message "The terminal was resized. The run was cancelled." -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
            }
            $nextTick = $clock.Elapsed.TotalMilliseconds + $Settings.TickMilliseconds
            continue
        }

        $tickResult = Invoke-GameTick -Game $game
        if ($tickResult -eq "SoloOver") {
            return New-GameResult -Game $game -Status "Completed" -Outcome "GameOver" -WinnerNumber 0 -Message "GAME OVER" -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
        }
        if ($tickResult -eq "Winner") {
            $winnerNumber = $(if ($game.LastStanding -gt 0) { $game.LastStanding } else {
                $winner = @($game.Snakes | Where-Object { $_.Active })
                if ($winner.Count -gt 0) { $winner[0].Number } else { 0 }
            })
            return New-GameResult -Game $game -Status "Completed" -Outcome "Winner" -WinnerNumber $winnerNumber -Message ("PLAYER {0} WINS" -f $winnerNumber) -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
        }
        if ($tickResult -eq "Draw") {
            return New-GameResult -Game $game -Status "Completed" -Outcome "Draw" -WinnerNumber 0 -Message "DRAW" -DurationMilliseconds $clock.Elapsed.TotalMilliseconds
        }

        $nextTick += $Settings.TickMilliseconds
        if ($clock.Elapsed.TotalMilliseconds -gt ($nextTick + ($Settings.TickMilliseconds * 2.0))) {
            $nextTick = $clock.Elapsed.TotalMilliseconds + $Settings.TickMilliseconds
        }
    }
}

function Add-RunRecord {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        $Settings,
        [Parameter(Mandatory = $true)]
        $Result
    )

    if ($Result.Status -ne "Completed" -or $Result.Snakes.Count -eq 0) {
        return
    }

    $playerScores = @()
    $foodCounts = @()
    $peakLengths = @()
    foreach ($snake in $Result.Snakes) {
        $playerScores += [int] $snake.Score
        $foodCounts += [int] $snake.FoodEaten
        $peakLengths += [int] $snake.PeakLength
    }

    if ($Settings.Mode -eq "Solo") {
        $rankingScore = $playerScores[0]
    }
    elseif ($Result.WinnerNumber -gt 0 -and $Result.WinnerNumber -le $playerScores.Count) {
        $rankingScore = $playerScores[$Result.WinnerNumber - 1]
    }
    else {
        $rankingScore = 0
        foreach ($score in $playerScores) {
            if ($score -gt $rankingScore) {
                $rankingScore = $score
            }
        }
    }

    $run = [pscustomobject] @{
        Id                   = [Guid]::NewGuid().ToString("N")
        TimestampUtc         = [DateTime]::UtcNow.ToString("o")
        Mode                 = $Settings.Mode
        Preset               = $Settings.Preset
        Score                = $rankingScore
        Outcome              = $Result.Outcome
        WinnerNumber         = $Result.WinnerNumber
        PlayerScores         = @($playerScores)
        FoodCounts           = @($foodCounts)
        PeakLengths          = @($peakLengths)
        TickCount            = $Result.TickCount
        DurationMilliseconds = $Result.DurationMilliseconds
        RuleText             = Get-RuleText -Settings $Settings
        Rules                = Copy-RunRules -Settings $Settings
        Colors               = [pscustomobject] @{
            Snake1 = $Settings.Colors.Snake1
            Snake2 = $Settings.Colors.Snake2
            Snake3 = $Settings.Colors.Snake3
            Food   = $Settings.Colors.Food
            Border = $Settings.Colors.Border
        }
    }

    $Data.Runs = @($Data.Runs) + @($run)
}

function Show-GameResult {
    param(
        [Parameter(Mandatory = $true)]
        $Result,
        [Parameter(Mandatory = $true)]
        $Settings,
        [Parameter(Mandatory = $true)]
        $Data
    )

    while ($true) {
        $snapshot = Get-ConsoleSnapshot
        $canvas = New-Canvas -Snapshot $snapshot -DefaultAttribute (Get-ConsoleAttribute -Foreground Gray)
        $title = $Result.Message
        if ($Result.Status -eq "TooSmall") {
            $title = "CANNOT START"
        }
        elseif ($Result.Status -eq "Resize") {
            $title = "RUN CANCELLED"
        }
        elseif ($Result.Status -eq "Aborted") {
            $title = "RUN ENDED"
        }

        Set-CanvasCenteredText -Canvas $canvas -Row 2 -Text $title -Attribute (Get-ConsoleAttribute -Foreground Yellow)
        Set-CanvasCenteredText -Canvas $canvas -Row 4 -Text ("Preset: {0} | {1}" -f $Settings.Preset, (Get-RuleText -Settings $Settings)) -Attribute (Get-ConsoleAttribute -Foreground DarkGray)

        if ($Result.Snakes.Count -gt 0) {
            $startRow = 7
            foreach ($snake in $Result.Snakes) {
                $line = "P{0}   Score {1,7}   Food {2,4}   Peak length {3,4}" -f $snake.Number, $snake.Score, $snake.FoodEaten, $snake.PeakLength
                Set-CanvasCenteredText -Canvas $canvas -Row $startRow -Text $line -Attribute (Get-ConsoleAttribute -Foreground (Get-ColorValue -Name $snake.ColorName))
                $startRow += 2
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Result.Message)) {
            Set-CanvasCenteredText -Canvas $canvas -Row 7 -Text $Result.Message -Attribute (Get-ConsoleAttribute -Foreground Red)
        }

        if ($Result.Status -eq "Completed") {
            Set-CanvasCenteredText -Canvas $canvas -Row ($snapshot.Height - 5) -Text "This completed run was added to Snake.json." -Attribute (Get-ConsoleAttribute -Foreground DarkGray)
        }
        else {
            Set-CanvasCenteredText -Canvas $canvas -Row ($snapshot.Height - 5) -Text "Cancelled and abandoned runs are not added to history." -Attribute (Get-ConsoleAttribute -Foreground DarkGray)
        }

        Set-CanvasCenteredText -Canvas $canvas -Row ($snapshot.Height - 3) -Text "ENTER/SPACE: restart   M: main menu   H: run history   ESC/Q: quit" -Attribute (Get-ConsoleAttribute -Foreground White)
        Write-Canvas -Canvas $canvas

        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            "Enter"    { return "Restart" }
            "Spacebar" { return "Restart" }
            "M"        { return "Menu" }
            "H"        { Show-Highscores -Data $Data }
            "Escape"   { return "Quit" }
            "Q"        { return "Quit" }
        }
    }
}

function Clear-ViewportByRepaint {
    try {
        $snapshot = Get-ConsoleSnapshot
        $canvas = New-Canvas -Snapshot $snapshot -DefaultAttribute (Get-ConsoleAttribute -Foreground Gray)
        Write-Canvas -Canvas $canvas
        [Console]::SetCursorPosition($snapshot.WindowLeft, $snapshot.WindowTop)
    }
    catch {
    }
}

function Start-Snake {
    if ($env:OS -ne "Windows_NT") {
        throw "Snake.ps1 requires Windows and is intended for Windows Terminal or the Windows console host."
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not available. Snake cannot locate its settings and run history."
    }

    Initialize-NativeConsole
    $dataDirectory = Join-Path $env:LOCALAPPDATA "PijiN\Snake"
    $dataPath = Join-Path $dataDirectory "Snake.json"
    $data = Import-SnakeData -Path $dataPath

    $originalCursorVisible = [Console]::CursorVisible
    $originalForegroundColor = [Console]::ForegroundColor
    $originalBackgroundColor = [Console]::BackgroundColor
    $originalTitle = [Console]::Title
    $quitRequested = $false

    try {
        [Console]::CursorVisible = $false
        [Console]::Title = "SNAKE"

        while (-not $quitRequested) {
            $menuResult = Show-MainMenu -Data $data -DataPath $dataPath
            if ($menuResult.Action -eq "Quit") {
                break
            }

            while ($true) {
                $result = Start-SnakeGame -Settings $data.Settings
                if ($result.Status -eq "Completed") {
                    Add-RunRecord -Data $data -Settings $data.Settings -Result $result
                    Export-SnakeData -Data $data -Path $dataPath
                }

                $resultAction = Show-GameResult -Result $result -Settings $data.Settings -Data $data
                if ($resultAction -eq "Restart") {
                    continue
                }
                if ($resultAction -eq "Quit") {
                    $quitRequested = $true
                }
                break
            }
        }
    }
    finally {
        Clear-ViewportByRepaint
        [Console]::ForegroundColor = $originalForegroundColor
        [Console]::BackgroundColor = $originalBackgroundColor
        [Console]::CursorVisible = $originalCursorVisible
        [Console]::Title = $originalTitle
    }
}

function Assert-SnakeTest {
    param(
        [bool] $Condition,
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Condition) {
        throw "Self-test failed: {0}" -f $Message
    }
}

function Invoke-SnakeSelfTest {
    $settings = New-DefaultSettings
    Assert-SnakeTest -Condition ($settings.Preset -eq "Classic") -Message "Default preset should be Classic."
    Assert-SnakeTest -Condition ((Get-RuleText $settings) -eq "Solo Border 100ms G3 L4") -Message "Classic rule notation changed unexpectedly."

    $settings.GrowthPerFood = 4
    Update-DetectedPreset -Settings $settings
    Assert-SnakeTest -Condition ($settings.Preset -eq "Custom") -Message "A changed gameplay setting should produce Custom."

    $lastStand = @($script:PresetDefinitions | Where-Object { $_.Name -eq "Last Stand" })[0]
    Set-SettingsFromPreset -Settings $settings -Preset $lastStand
    Assert-SnakeTest -Condition ($settings.Mode -eq "Battle" -and $settings.PlayerCount -eq 3) -Message "Last Stand should configure three-player Battle."
    Assert-SnakeTest -Condition ($settings.CorpseObstacles -and $settings.RoundEndRule -eq "AllDead") -Message "Last Stand should keep corpses and run until all snakes die."
    Assert-SnakeTest -Condition ((Get-RuleText $settings) -match "Corpses:On End:AllDead") -Message "Battle notation should include conditional rules."

    $options = @(Get-MainMenuOptions -Settings $settings)
    Assert-SnakeTest -Condition (@($options | Where-Object { $_.Id -eq "Corpses" }).Count -eq 1) -Message "Three-player Battle should expose corpse behavior."
    $settings.PlayerCount = 2
    $options = @(Get-MainMenuOptions -Settings $settings)
    Assert-SnakeTest -Condition (@($options | Where-Object { $_.Id -eq "Corpses" }).Count -eq 0) -Message "Two-player Battle should hide corpse behavior."

    Set-SettingsFromPreset -Settings $settings -Preset $lastStand
    $fakeSnapshot = [pscustomobject] @{ Width = 120; Height = 30; WindowLeft = 0; WindowTop = 0 }
    $game = New-GameState -Snapshot $fakeSnapshot -Settings $settings
    Assert-SnakeTest -Condition ($game.Status -eq "Ready") -Message "A normal terminal should produce a playable game state."
    Assert-SnakeTest -Condition ($game.BoardWidth -eq 60 -and $game.BoardHeight -eq 29) -Message "Arena should fit the terminal at two columns per logical cell."
    Assert-SnakeTest -Condition ($game.Snakes.Count -eq 3) -Message "Last Stand should create three snakes."
    Assert-SnakeTest -Condition ($game.FoodIndex -ge 0 -and $game.Occupancy[$game.FoodIndex] -eq 0) -Message "Food should spawn on a free cell."
    Assert-SnakeTest -Condition ((Get-DimColorName "Green") -eq "DarkGreen") -Message "Bright corpse colors should dim predictably."

    $soloSettings = New-DefaultSettings
    $soloGame = New-GameState -Snapshot $fakeSnapshot -Settings $soloSettings
    $soloSnake = $soloGame.Snakes[0]
    $soloGame.FoodIndex = ($soloSnake.Y * $soloGame.BoardWidth) + ($soloSnake.X + 1)
    $oldLength = $soloSnake.Body.Count
    $tickResult = Invoke-GameTick -Game $soloGame -NoRender
    Assert-SnakeTest -Condition ($tickResult -eq "Continue") -Message "A safe Solo move should continue."
    Assert-SnakeTest -Condition ($soloSnake.Score -eq $script:ScorePerFood -and $soloSnake.Body.Count -eq ($oldLength + 1)) -Message "Eating should score and grow immediately."
    Assert-SnakeTest -Condition ($soloSnake.GrowthPending -eq ($soloSettings.GrowthPerFood - 1)) -Message "Growth should continue for the configured number of cells."

    $battleSettings = New-DefaultSettings
    $battlePreset = @($script:PresetDefinitions | Where-Object { $_.Name -eq "Battle" })[0]
    Set-SettingsFromPreset -Settings $battleSettings -Preset $battlePreset
    $battleSettings.RoundEndRule = "AllDead"
    Update-DetectedPreset -Settings $battleSettings
    $battleGame = New-GameState -Snapshot $fakeSnapshot -Settings $battleSettings
    $battleGame.FoodIndex = -1
    $battleGame.Snakes[0].PendingDx = -$battleGame.Snakes[0].Dx
    $battleGame.Snakes[0].PendingDy = -$battleGame.Snakes[0].Dy
    $tickResult = Invoke-GameTick -Game $battleGame -NoRender
    Assert-SnakeTest -Condition ($tickResult -eq "Continue" -and $battleGame.LastStanding -eq 2) -Message "AllDead should continue after one Battle snake remains."
    $battleGame.Snakes[1].PendingDx = -$battleGame.Snakes[1].Dx
    $battleGame.Snakes[1].PendingDy = -$battleGame.Snakes[1].Dy
    $tickResult = Invoke-GameTick -Game $battleGame -NoRender
    Assert-SnakeTest -Condition ($tickResult -eq "Winner" -and $battleGame.LastStanding -eq 2) -Message "AllDead should retain the last-standing winner after that snake dies."

    $oneLeftSettings = New-DefaultSettings
    Set-SettingsFromPreset -Settings $oneLeftSettings -Preset $battlePreset
    $oneLeftGame = New-GameState -Snapshot $fakeSnapshot -Settings $oneLeftSettings
    $oneLeftGame.FoodIndex = -1
    $oneLeftGame.Snakes[0].PendingDx = -$oneLeftGame.Snakes[0].Dx
    $oneLeftGame.Snakes[0].PendingDy = -$oneLeftGame.Snakes[0].Dy
    $tickResult = Invoke-GameTick -Game $oneLeftGame -NoRender
    Assert-SnakeTest -Condition ($tickResult -eq "Winner" -and $oneLeftGame.LastStanding -eq 2) -Message "OneLeft should stop as soon as one Battle snake remains."

    $corpseGame = New-GameState -Snapshot $fakeSnapshot -Settings $settings
    $corpseGame.FoodIndex = -1
    $corpseGame.Snakes[0].PendingDx = -$corpseGame.Snakes[0].Dx
    $corpseGame.Snakes[0].PendingDy = -$corpseGame.Snakes[0].Dy
    [void] (Invoke-GameTick -Game $corpseGame -NoRender)
    Assert-SnakeTest -Condition (-not $corpseGame.Snakes[0].Active -and $corpseGame.Snakes[0].CorpseDim) -Message "Enabled three-player corpses should dim on elimination."
    Assert-SnakeTest -Condition ($corpseGame.Snakes[0].Body.Count -gt 0) -Message "Dimmed corpses should remain in the occupancy grid."

    $disappearingSettings = New-DefaultSettings
    Set-SettingsFromPreset -Settings $disappearingSettings -Preset $lastStand
    $disappearingSettings.CorpseObstacles = $false
    Update-DetectedPreset -Settings $disappearingSettings
    $disappearingGame = New-GameState -Snapshot $fakeSnapshot -Settings $disappearingSettings
    $disappearingGame.FoodIndex = -1
    $disappearingGame.Snakes[0].PendingDx = -$disappearingGame.Snakes[0].Dx
    $disappearingGame.Snakes[0].PendingDy = -$disappearingGame.Snakes[0].Dy
    [void] (Invoke-GameTick -Game $disappearingGame -NoRender)
    Assert-SnakeTest -Condition ($disappearingGame.Snakes[0].Body.Count -eq 0 -and -not $disappearingGame.Snakes[0].CorpseDim) -Message "Disabled three-player corpses should disappear."

    $data = New-DefaultData
    $completedResult = New-GameResult -Game $soloGame -Status "Completed" -Outcome "GameOver" -WinnerNumber 0 -Message "GAME OVER" -DurationMilliseconds 1234
    Add-RunRecord -Data $data -Settings $soloSettings -Result $completedResult
    Assert-SnakeTest -Condition ($data.Runs.Count -eq 1 -and $data.Runs[0].Score -eq $script:ScorePerFood) -Message "Completed runs should be appended with their ranking score."
    $temporaryPath = [IO.Path]::GetTempFileName()
    try {
        Export-SnakeData -Data $data -Path $temporaryPath
        $loadedData = Import-SnakeData -Path $temporaryPath
        Assert-SnakeTest -Condition ($loadedData.Settings.Preset -eq "Classic") -Message "Persistence should round-trip default settings."
        Assert-SnakeTest -Condition ($loadedData.Runs.Count -eq 1 -and $loadedData.Runs[0].RuleText -match "Solo Border") -Message "Persistence should retain completed runs and rule notation."

        $data.Settings.GrowthPerFood = 4
        Update-DetectedPreset -Settings $data.Settings
        Export-SnakeData -Data $data -Path $temporaryPath
        $loadedData = Import-SnakeData -Path $temporaryPath
        Assert-SnakeTest -Condition ($loadedData.Settings.GrowthPerFood -eq 4 -and $loadedData.Settings.Preset -eq "Custom") -Message "Repeated saves should replace the existing JSON cleanly."
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) {
            [IO.File]::Delete($temporaryPath)
        }
    }

    Write-Output "Snake self-test passed."
}

if ($MyInvocation.InvocationName -ne ".") {
    if ($SelfTest) {
        Invoke-SnakeSelfTest
    }
    else {
        Start-Snake
    }
}
