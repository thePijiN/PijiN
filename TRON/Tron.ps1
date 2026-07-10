[CmdletBinding()]
param(
    [ValidateRange(25, 250)]
    [int] $TickMilliseconds = 60
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:TurboDurationTicks = 12
$script:TurboCooldownTicks = 80

function Initialize-NativeConsole {
    if ("Tron.NativeConsole" -as [type]) {
        return
    }

$nativeCode = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Tron
{
    public static class NativeConsole
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

        public static void WriteCell(int left, int top, char character, short attribute)
        {
            WriteBuffer(
                left,
                top,
                1,
                1,
                new char[] { character },
                new short[] { attribute });
        }

        public static void WriteText(int left, int top, string text, short attribute)
        {
            if (String.IsNullOrEmpty(text))
            {
                return;
            }

            char[] characters = text.ToCharArray();
            short[] attributes = new short[characters.Length];
            for (int index = 0; index < attributes.Length; index++)
            {
                attributes[index] = attribute;
            }

            WriteBuffer(left, top, characters.Length, 1, characters, attributes);
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

function Write-CenteredMenuLine {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [int] $Row,

        [ConsoleColor] $Color = [ConsoleColor]::Gray
    )

    $width = [Console]::WindowWidth
    $left = [Console]::WindowLeft
    $top = [Console]::WindowTop
    $visibleText = $Text

    if ($visibleText.Length -gt $width) {
        $visibleText = $visibleText.Substring(0, $width)
    }

    $column = [Math]::Max(0, [Math]::Floor(($width - $visibleText.Length) / 2))
    [Console]::SetCursorPosition($left + $column, $top + $Row)
    [Console]::ForegroundColor = $Color
    [Console]::Write($visibleText)
}

function Write-MenuSegmentsAtColumn {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Segments,

        [Parameter(Mandatory = $true)]
        [int] $Row,

        [Parameter(Mandatory = $true)]
        [int] $Column
    )

    $width = [Console]::WindowWidth
    $left = [Console]::WindowLeft
    $top = [Console]::WindowTop
    $safeColumn = [Math]::Max(0, [Math]::Min($Column, [Math]::Max(0, $width - 1)))
    $remaining = $width - $safeColumn

    [Console]::SetCursorPosition($left + $safeColumn, $top + $Row)

    foreach ($segment in $Segments) {
        if ($remaining -le 0) {
            break
        }

        $segmentText = [string] $segment.Text
        if ($segmentText.Length -gt $remaining) {
            $segmentText = $segmentText.Substring(0, $remaining)
        }

        [Console]::ForegroundColor = [ConsoleColor] $segment.Color
        [Console]::Write($segmentText)
        $remaining -= $segmentText.Length
    }
}

function Write-MenuOptionLine {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [int] $Row,

        [Parameter(Mandatory = $true)]
        [int] $Column,

        [Parameter(Mandatory = $true)]
        [bool] $Selected,

        [string] $Hint = ""
    )

    $segments = @(
        [pscustomobject] @{
            Text  = $Text
            Color = $(if ($Selected) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Gray })
        }
    )

    if ($Selected -and $Hint.Length -gt 0) {
        $segments += [pscustomobject] @{
            Text  = $Hint
            Color = [ConsoleColor]::DarkGray
        }
    }

    Write-MenuSegmentsAtColumn -Segments $segments -Row $Row -Column $Column
}

function Show-MainMenu {
    param(
        [int] $InitialPlayerCount,
        [int] $InitialTickMilliseconds,
        [bool] $InitialTurboEnabled = $true
    )

    $playerCount = $InitialPlayerCount
    if ($playerCount -lt 1 -or $playerCount -gt 3) {
        $playerCount = 2
    }
    $menuTickMilliseconds = [Math]::Min(250, [Math]::Max(25, $InitialTickMilliseconds))
    $turboEnabled = $InitialTurboEnabled
    $selectedItem = 0
    $art = @( <#
        "TTTTTT RRRRR   OOOOO  N   N",
        "  TT   R   R   O   O  NN  N",
        "  TT   RRRRR   O   O  N N N",
        "  TT   R  R    O   O  N  NN",
        "  TT   R   R   OOOOO  N   N"#>
		"*+=======++    .=++==================================++=:           :-===========:.       =*==+-               ++====+*",
		"#:       -*   =+-.                                     :=+-      :=+-:.        .:-==:     ++   -+-             #:    :#",
		"#-.......=#  *=      ..................................  :#+   .++:                .=+:   ++    .=+:           #:    -#",
		"-=========: -#     -+==========-------==-------------------=  -*:     .-=======:     .+=  ++      .=+:         #:    -#",
		"            -*     *=          .:::::.   :::::::::::::::::.. :#.     ++-.     :=+:     *= ++        .++.       #:    -#",
		"            -*     *=         -#:::::#- #=:-:::::------::-#+ *=     *=          .#-    .# ++          :*:-=====*:    -#",
		"            -*     *=         -*     *- #.              :+=  #:    :#            =*     #.++           #+#.          -#",
		"            -*     *=         -*     *- ++.      ::::-=+=:   *=    .#-           *=    .# ++    .*======:*-          -#",
		"            -*     *=         -*     *-  :+=.    :+#=.       :#.    .*=.      .-*-     *= ++    .#.      .=+:        -#",
		"            -*     *=         -*     *-    :++:    .==:       -*:     :========-.    .+=  ++    .#.        .=+:      -#",
		"            -*     *=         -*     *-      :++:    .=+-      .++:       ...      .=+:   ++    .#.          .++.    -#",
		"            -*     *=         -*     *-        :++:.    -+-      :=+-:.        .:-==-     ++     #.            :+=.  :#",
		"            :*=====*-         :*=====*:          :++====-+#*        :==============:.     =*=====*.              :+==+*"
    )

    while ($true) {
        Clear-Host
        $height = [Console]::WindowHeight
        $firstRow = [Math]::Max(1, [Math]::Floor(($height - $art.Count - 11) / 2))

        for ($index = 0; $index -lt $art.Count; $index++) {
            Write-CenteredMenuLine -Text $art[$index] -Row ($firstRow + $index) -Color Cyan
        }

        $cellsPerSecond = 1000.0 / $menuTickMilliseconds
        $startText = "[1] Start {0}" -f $(if ($playerCount -eq 1) { "Campaign" } else { "Game" })
        $playersText = "[2] Players: {0}" -f $playerCount
        $speedText = "[3] Speed: {0}ms ({1:N1} cells/sec)" -f $menuTickMilliseconds, $cellsPerSecond
        $turboText = "[4] Turbo: {0}" -f $(if ($turboEnabled) { "Enabled" } else { "Disabled" })
        $menuWidth = @($startText.Length, $playersText.Length, $speedText.Length, $turboText.Length) | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
        $menuColumn = [Math]::Max(0, [Math]::Floor(([Console]::WindowWidth - $menuWidth) / 2))

        Write-CenteredMenuLine -Text "Multiplayer TRON in PowerShell 5.1" -Row ($firstRow + $art.Count + 1) -Color White
        Write-MenuOptionLine `
            -Text $startText `
            -Row ($firstRow + $art.Count + 3) `
            -Column $menuColumn `
            -Selected ($selectedItem -eq 0) `
            -Hint " (ENTER)"
        Write-MenuOptionLine `
            -Text $playersText `
            -Row ($firstRow + $art.Count + 4) `
            -Column $menuColumn `
            -Selected ($selectedItem -eq 1) `
            -Hint " (LEFT/RIGHT)"
        Write-MenuOptionLine `
            -Text $speedText `
            -Row ($firstRow + $art.Count + 5) `
            -Column $menuColumn `
            -Selected ($selectedItem -eq 2) `
            -Hint " (LEFT faster, RIGHT slower)"
        Write-MenuOptionLine `
            -Text $turboText `
            -Row ($firstRow + $art.Count + 6) `
            -Column $menuColumn `
            -Selected ($selectedItem -eq 3) `
            -Hint " (LEFT/RIGHT)"
        Write-CenteredMenuLine -Text "UP/DOWN: select   1/2/3/4: quick actions   ENTER: start   ESC: quit" -Row ($firstRow + $art.Count + 12) -Color DarkGray

        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            "UpArrow" {
                $selectedItem--
                if ($selectedItem -lt 0) {
                    $selectedItem = 3
                }
            }
            "DownArrow" {
                $selectedItem++
                if ($selectedItem -gt 3) {
                    $selectedItem = 0
                }
            }
            "LeftArrow" {
                if ($selectedItem -eq 1) {
                    $playerCount--
                    if ($playerCount -lt 1) {
                        $playerCount = 3
                    }
                }
                elseif ($selectedItem -eq 2) {
                    $menuTickMilliseconds = [Math]::Max(25, $menuTickMilliseconds - 5)
                }
                elseif ($selectedItem -eq 3) {
                    $turboEnabled = -not $turboEnabled
                }
            }
            "RightArrow" {
                if ($selectedItem -eq 1) {
                    $playerCount++
                    if ($playerCount -gt 3) {
                        $playerCount = 1
                    }
                }
                elseif ($selectedItem -eq 2) {
                    $menuTickMilliseconds = [Math]::Min(250, $menuTickMilliseconds + 5)
                }
                elseif ($selectedItem -eq 3) {
                    $turboEnabled = -not $turboEnabled
                }
            }
            "Enter" {
                return [pscustomobject] @{
                    Action           = "Start"
                    PlayerCount      = $playerCount
                    TickMilliseconds = $menuTickMilliseconds
                    TurboEnabled     = $turboEnabled
                }
            }
            "D1" {
                $selectedItem = 0
                return [pscustomobject] @{
                    Action           = "Start"
                    PlayerCount      = $playerCount
                    TickMilliseconds = $menuTickMilliseconds
                    TurboEnabled     = $turboEnabled
                }
            }
            "NumPad1" {
                $selectedItem = 0
                return [pscustomobject] @{
                    Action           = "Start"
                    PlayerCount      = $playerCount
                    TickMilliseconds = $menuTickMilliseconds
                    TurboEnabled     = $turboEnabled
                }
            }
            "D2" {
                $selectedItem = 1
                $playerCount++
                if ($playerCount -gt 3) {
                    $playerCount = 1
                }
            }
            "NumPad2" {
                $selectedItem = 1
                $playerCount++
                if ($playerCount -gt 3) {
                    $playerCount = 1
                }
            }
            "D3" {
                $selectedItem = 2
                if (($menuTickMilliseconds - 5) -lt 25) {
                    $menuTickMilliseconds = 250
                }
                else {
                    $menuTickMilliseconds -= 5
                }
            }
            "NumPad3" {
                $selectedItem = 2
                if (($menuTickMilliseconds - 5) -lt 25) {
                    $menuTickMilliseconds = 250
                }
                else {
                    $menuTickMilliseconds -= 5
                }
            }
            "D4" {
                $selectedItem = 3
                $turboEnabled = -not $turboEnabled
            }
            "NumPad4" {
                $selectedItem = 3
                $turboEnabled = -not $turboEnabled
            }
            "Escape" {
                return [pscustomobject] @{
                    Action           = "Quit"
                    PlayerCount      = $playerCount
                    TickMilliseconds = $menuTickMilliseconds
                    TurboEnabled     = $turboEnabled
                }
            }
        }
    }
}

function Show-Countdown {
    Clear-Host
    $snapshot = Get-ConsoleSnapshot
    $row = [Math]::Floor($snapshot.Height / 2)
    $column = [Math]::Floor($snapshot.Width / 2)
    $screenX = $snapshot.WindowLeft + $column
    $screenY = $snapshot.WindowTop + $row

    foreach ($number in @("3", "2", "1")) {
        [Tron.NativeConsole]::WriteCell($screenX, $screenY, [char] $number, [int16] 14)
        Start-Sleep -Seconds 1
        [Tron.NativeConsole]::WriteCell($screenX, $screenY, [char] " ", [int16] 7)
    }
}

function Set-BufferText {
    param(
        [Parameter(Mandatory = $true)]
        [char[]] $Characters,

        [Parameter(Mandatory = $true)]
        [int16[]] $Attributes,

        [Parameter(Mandatory = $true)]
        [int] $Width,

        [Parameter(Mandatory = $true)]
        [int] $Row,

        [Parameter(Mandatory = $true)]
        [int] $Column,

        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [int16] $Attribute
    )

    for ($offset = 0; $offset -lt $Text.Length; $offset++) {
        $x = $Column + $offset
        if ($x -lt 0 -or $x -ge $Width) {
            continue
        }

        $bufferIndex = ($Row * $Width) + $x
        $Characters[$bufferIndex] = $Text[$offset]
        $Attributes[$bufferIndex] = $Attribute
    }
}

function New-Player {
    param(
        [int] $Number,
        [int] $X,
        [int] $Y,
        [int] $Dx,
        [int] $Dy,
        [int] $CellValue,
        [int16] $ColorAttribute,
        [int16] $TurboColorAttribute
    )

    [pscustomobject] @{
        Number         = $Number
        X              = $X
        Y              = $Y
        Dx             = $Dx
        Dy             = $Dy
        PendingDx      = $Dx
        PendingDy      = $Dy
        CellValue      = $CellValue
        ColorAttribute = $ColorAttribute
        TurboColorAttribute = $TurboColorAttribute
        Active         = $true
        TurboTicksRemaining = 0
        TurboCooldownTicksRemaining = 0
    }
}

function Set-PendingDirection {
    param(
        [Parameter(Mandatory = $true)]
        $Player,

        [int] $Dx,
        [int] $Dy
    )

    if (($Dx + $Player.Dx) -eq 0 -and ($Dy + $Player.Dy) -eq 0) {
        return
    }

    $Player.PendingDx = $Dx
    $Player.PendingDy = $Dy
}

function Invoke-PlayerTurbo {
    param(
        [Parameter(Mandatory = $true)]
        $Player,

        [bool] $TurboEnabled = $true
    )

    if (-not $TurboEnabled) {
        return
    }

    if (-not $Player.Active) {
        return
    }

    if ($Player.TurboTicksRemaining -gt 0 -or $Player.TurboCooldownTicksRemaining -gt 0) {
        return
    }

    $Player.TurboTicksRemaining = $script:TurboDurationTicks
}

function Update-TurboTimers {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Players
    )

    foreach ($player in $Players) {
        if ($player.TurboTicksRemaining -gt 0) {
            $player.TurboTicksRemaining--
            if ($player.TurboTicksRemaining -eq 0) {
                $player.TurboCooldownTicksRemaining = $script:TurboCooldownTicks
            }
        }
        elseif ($player.TurboCooldownTicksRemaining -gt 0) {
            $player.TurboCooldownTicksRemaining--
        }
    }
}

function Test-HumanPlayer {
    param(
        [Parameter(Mandatory = $true)]
        [int] $PlayerNumber,

        [int[]] $HumanPlayerNumbers = @(1, 2, 3)
    )

    return ($HumanPlayerNumbers -contains $PlayerNumber)
}

function Get-TurboKeyAttribute {
    param(
        [Parameter(Mandatory = $true)]
        [int] $PlayerIndex,

        [Parameter(Mandatory = $true)]
        [int16] $ReadyAttribute,

        [bool] $TurboEnabled = $true,

        [object[]] $Players = $null
    )

    if (-not $TurboEnabled) {
        return [int16] 8
    }

    if ($null -ne $Players -and $Players.Count -gt $PlayerIndex) {
        $player = $Players[$PlayerIndex]
        if ($player.TurboTicksRemaining -eq 0 -and $player.TurboCooldownTicksRemaining -gt 0) {
            return [int16] 8
        }
    }

    return $ReadyAttribute
}

function Get-HeaderSegments {
    param(
        [Parameter(Mandatory = $true)]
        [int[]] $Scores,

        [ValidateSet(2, 3)]
        [int] $PlayerCount,

        [bool] $TurboEnabled = $true,

        [string[]] $PlayerLabels = @("P1", "P2", "P3"),

        [int[]] $HumanPlayerNumbers = @(1, 2, 3),

        [object[]] $Players = $null
    )

    $playerOneAttribute = [int16] 11
    $playerTwoAttribute = [int16] 13
    $playerThreeAttribute = [int16] 10
    $labels = @("P1", "P2", "P3")

    for ($index = 0; $index -lt $PlayerLabels.Count -and $index -lt 3; $index++) {
        if (-not [string]::IsNullOrWhiteSpace($PlayerLabels[$index])) {
            $labels[$index] = $PlayerLabels[$index]
        }
    }

    $segments = @()

    if (Test-HumanPlayer -PlayerNumber 1 -HumanPlayerNumbers $HumanPlayerNumbers) {
        $segments += @(
            [pscustomobject] @{ Text = (" {0}: {1} WASD/" -f $labels[0], $Scores[0]); Attribute = $playerOneAttribute },
            [pscustomobject] @{ Text = "F "; Attribute = (Get-TurboKeyAttribute -PlayerIndex 0 -ReadyAttribute $playerOneAttribute -TurboEnabled $TurboEnabled -Players $Players) }
        )
    }
    else {
        $segments += @(
            [pscustomobject] @{ Text = (" {0}: {1} AI " -f $labels[0], $Scores[0]); Attribute = $playerOneAttribute }
        )
    }

    $segments += @(
        [pscustomobject] @{ Text = "|"; Attribute = [int16] 7 }
    )

    if (Test-HumanPlayer -PlayerNumber 2 -HumanPlayerNumbers $HumanPlayerNumbers) {
        $segments += @(
            [pscustomobject] @{ Text = (" {0}: {1} Arrows/" -f $labels[1], $Scores[1]); Attribute = $playerTwoAttribute },
            [pscustomobject] @{ Text = "Enter "; Attribute = (Get-TurboKeyAttribute -PlayerIndex 1 -ReadyAttribute $playerTwoAttribute -TurboEnabled $TurboEnabled -Players $Players) }
        )
    }
    else {
        $segments += @(
            [pscustomobject] @{ Text = (" {0}: {1} AI " -f $labels[1], $Scores[1]); Attribute = $playerTwoAttribute }
        )
    }

    if ($PlayerCount -eq 3) {
        $segments += @(
            [pscustomobject] @{ Text = "|"; Attribute = [int16] 7 }
        )

        if (Test-HumanPlayer -PlayerNumber 3 -HumanPlayerNumbers $HumanPlayerNumbers) {
            $segments += @(
                [pscustomobject] @{ Text = (" {0}: {1} IJKL/" -f $labels[2], $Scores[2]); Attribute = $playerThreeAttribute },
                [pscustomobject] @{ Text = "Space "; Attribute = (Get-TurboKeyAttribute -PlayerIndex 2 -ReadyAttribute $playerThreeAttribute -TurboEnabled $TurboEnabled -Players $Players) }
            )
        }
        else {
            $segments += @(
                [pscustomobject] @{ Text = (" {0}: {1} AI " -f $labels[2], $Scores[2]); Attribute = $playerThreeAttribute }
            )
        }
    }

    $segments += @(
        [pscustomobject] @{ Text = "| ESC: quit "; Attribute = [int16] 7 }
    )

    return $segments
}

function Set-HeaderBuffer {
    param(
        [Parameter(Mandatory = $true)]
        [char[]] $Characters,

        [Parameter(Mandatory = $true)]
        [int16[]] $Attributes,

        [Parameter(Mandatory = $true)]
        [int] $Width,

        [Parameter(Mandatory = $true)]
        [object[]] $Segments
    )

    for ($x = 0; $x -lt $Width; $x++) {
        $Characters[$x] = [char] " "
        $Attributes[$x] = [int16] 7
    }

    $headerColumn = 0
    foreach ($segment in $Segments) {
        Set-BufferText `
            -Characters $Characters `
            -Attributes $Attributes `
            -Width $Width `
            -Row 0 `
            -Column $headerColumn `
            -Text $segment.Text `
            -Attribute $segment.Attribute
        $headerColumn += $segment.Text.Length
    }
}

function Write-HeaderBuffer {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot,

        [Parameter(Mandatory = $true)]
        [char[]] $Characters,

        [Parameter(Mandatory = $true)]
        [int16[]] $Attributes
    )

    $rowCharacters = New-Object "char[]" $Snapshot.Width
    $rowAttributes = New-Object "int16[]" $Snapshot.Width
    [Array]::Copy($Characters, 0, $rowCharacters, 0, $Snapshot.Width)
    [Array]::Copy($Attributes, 0, $rowAttributes, 0, $Snapshot.Width)

    [Tron.NativeConsole]::WriteBuffer(
        $Snapshot.WindowLeft,
        $Snapshot.WindowTop,
        $Snapshot.Width,
        1,
        $rowCharacters,
        $rowAttributes
    )
}

function Update-Header {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot,

        [Parameter(Mandatory = $true)]
        $Arena,

        [Parameter(Mandatory = $true)]
        [int[]] $Scores,

        [ValidateSet(2, 3)]
        [int] $PlayerCount,

        [bool] $TurboEnabled = $true,

        [string[]] $PlayerLabels = @("P1", "P2", "P3"),

        [int[]] $HumanPlayerNumbers = @(1, 2, 3)
    )

    $headerSegments = Get-HeaderSegments -Scores $Scores -PlayerCount $PlayerCount -TurboEnabled $TurboEnabled -PlayerLabels $PlayerLabels -HumanPlayerNumbers $HumanPlayerNumbers -Players $Arena.Players
    Set-HeaderBuffer `
        -Characters $Arena.Characters `
        -Attributes $Arena.Attributes `
        -Width $Snapshot.Width `
        -Segments $headerSegments
    Write-HeaderBuffer -Snapshot $Snapshot -Characters $Arena.Characters -Attributes $Arena.Attributes
}

function Clear-GameInput {
    while ([Console]::KeyAvailable) {
        [void] [Console]::ReadKey($true)
    }
}

function Read-GameInput {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Players,

        [bool] $TurboEnabled = $true,

        [int[]] $HumanPlayerNumbers = @(1, 2, 3)
    )

    while ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true).Key

        switch ($key) {
            "W"          { if ((Test-HumanPlayer -PlayerNumber 1 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[0].Active) { Set-PendingDirection -Player $Players[0] -Dx 0 -Dy -1 } }
            "A"          { if ((Test-HumanPlayer -PlayerNumber 1 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[0].Active) { Set-PendingDirection -Player $Players[0] -Dx -1 -Dy 0 } }
            "S"          { if ((Test-HumanPlayer -PlayerNumber 1 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[0].Active) { Set-PendingDirection -Player $Players[0] -Dx 0 -Dy 1 } }
            "D"          { if ((Test-HumanPlayer -PlayerNumber 1 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[0].Active) { Set-PendingDirection -Player $Players[0] -Dx 1 -Dy 0 } }
            "F"          { if ((Test-HumanPlayer -PlayerNumber 1 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[0].Active) { Invoke-PlayerTurbo -Player $Players[0] -TurboEnabled $TurboEnabled } }
            "UpArrow"    { if ((Test-HumanPlayer -PlayerNumber 2 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[1].Active) { Set-PendingDirection -Player $Players[1] -Dx 0 -Dy -1 } }
            "LeftArrow"  { if ((Test-HumanPlayer -PlayerNumber 2 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[1].Active) { Set-PendingDirection -Player $Players[1] -Dx -1 -Dy 0 } }
            "DownArrow"  { if ((Test-HumanPlayer -PlayerNumber 2 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[1].Active) { Set-PendingDirection -Player $Players[1] -Dx 0 -Dy 1 } }
            "RightArrow" { if ((Test-HumanPlayer -PlayerNumber 2 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[1].Active) { Set-PendingDirection -Player $Players[1] -Dx 1 -Dy 0 } }
            "Enter"      { if ((Test-HumanPlayer -PlayerNumber 2 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players[1].Active) { Invoke-PlayerTurbo -Player $Players[1] -TurboEnabled $TurboEnabled } }
            "I"          { if ((Test-HumanPlayer -PlayerNumber 3 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players.Count -ge 3 -and $Players[2].Active) { Set-PendingDirection -Player $Players[2] -Dx 0 -Dy -1 } }
            "J"          { if ((Test-HumanPlayer -PlayerNumber 3 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players.Count -ge 3 -and $Players[2].Active) { Set-PendingDirection -Player $Players[2] -Dx -1 -Dy 0 } }
            "K"          { if ((Test-HumanPlayer -PlayerNumber 3 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players.Count -ge 3 -and $Players[2].Active) { Set-PendingDirection -Player $Players[2] -Dx 0 -Dy 1 } }
            "L"          { if ((Test-HumanPlayer -PlayerNumber 3 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players.Count -ge 3 -and $Players[2].Active) { Set-PendingDirection -Player $Players[2] -Dx 1 -Dy 0 } }
            "Spacebar"   { if ((Test-HumanPlayer -PlayerNumber 3 -HumanPlayerNumbers $HumanPlayerNumbers) -and $Players.Count -ge 3 -and $Players[2].Active) { Invoke-PlayerTurbo -Player $Players[2] -TurboEnabled $TurboEnabled } }
            "Escape"     { return $true }
        }
    }

    return $false
}

function New-Arena {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot,

        [Parameter(Mandatory = $true)]
        [int[]] $Scores,

        [ValidateSet(2, 3)]
        [int] $PlayerCount,

        [bool] $TurboEnabled = $true,

        [string[]] $PlayerLabels = @("P1", "P2", "P3"),

        [int[]] $HumanPlayerNumbers = @(1, 2, 3)
    )

    $width = $Snapshot.Width
    $height = $Snapshot.Height
    $cellCount = $width * $height
    $characters = New-Object "char[]" $cellCount
    $attributes = New-Object "int16[]" $cellCount
    $grid = [Array]::CreateInstance([int], $width, $height)

    for ($index = 0; $index -lt $cellCount; $index++) {
        $characters[$index] = [char] " "
        $attributes[$index] = [int16] 7
    }

    for ($x = 0; $x -lt $width; $x++) {
        foreach ($y in @(1, ($height - 1))) {
            $bufferIndex = ($y * $width) + $x
            $characters[$bufferIndex] = [char] "#"
            $attributes[$bufferIndex] = [int16] 8
            $grid[$x, $y] = 1
        }
    }

    for ($y = 1; $y -lt $height; $y++) {
        foreach ($x in @(0, ($width - 1))) {
            $bufferIndex = ($y * $width) + $x
            $characters[$bufferIndex] = [char] "#"
            $attributes[$bufferIndex] = [int16] 8
            $grid[$x, $y] = 1
        }
    }

    $playerOneX = [Math]::Max(2, [Math]::Floor($width / 4))
    $playerTwoX = [Math]::Min($width - 3, [Math]::Floor(($width * 3) / 4))
    if ($PlayerCount -eq 2) {
        $startY = [Math]::Floor($height / 2)
    }
    else {
        $startY = [Math]::Max(2, [Math]::Floor($height / 3))
    }

    $players = @(
        (New-Player -Number 1 -X $playerOneX -Y $startY -Dx 1 -Dy 0 -CellValue 2 -ColorAttribute ([int16] 176) -TurboColorAttribute ([int16] 48)),
        (New-Player -Number 2 -X $playerTwoX -Y $startY -Dx -1 -Dy 0 -CellValue 3 -ColorAttribute ([int16] 208) -TurboColorAttribute ([int16] 80))
    )

    if ($PlayerCount -eq 3) {
        $playerThreeX = [Math]::Floor($width / 2)
        $playerThreeY = [Math]::Min($height - 3, [Math]::Floor(($height * 3) / 4))
        $players += @(
            (New-Player -Number 3 -X $playerThreeX -Y $playerThreeY -Dx 0 -Dy -1 -CellValue 4 -ColorAttribute ([int16] 160) -TurboColorAttribute ([int16] 32))
        )
    }

    $headerSegments = Get-HeaderSegments -Scores $Scores -PlayerCount $PlayerCount -TurboEnabled $TurboEnabled -PlayerLabels $PlayerLabels -HumanPlayerNumbers $HumanPlayerNumbers -Players $players
    Set-HeaderBuffer `
        -Characters $characters `
        -Attributes $attributes `
        -Width $width `
        -Segments $headerSegments

    foreach ($player in $players) {
        $grid[$player.X, $player.Y] = $player.CellValue
        $bufferIndex = ($player.Y * $width) + $player.X
        $characters[$bufferIndex] = [char] " "
        $attributes[$bufferIndex] = $player.ColorAttribute
    }

    [pscustomobject] @{
        Grid       = $grid
        Characters = $characters
        Attributes = $attributes
        Players     = $players
    }
}

function New-AIProfile {
    param(
        [int] $PlayerNumber,
        [string] $Name,
        [int] $LookAhead,
        [int] $Jitter,
        [int] $Aggression,
        [int] $TurboChance,
        [int] $TurboMinimumSpace,
        [int] $SpaceWeight = 4,
        [int] $SpaceLimit = 160,
        [int] $TurnPenalty = 14,
        [int] $ForwardBias = 10
    )

    [pscustomobject] @{
        PlayerNumber      = $PlayerNumber
        Name              = $Name
        LookAhead         = $LookAhead
        Jitter            = $Jitter
        Aggression        = $Aggression
        TurboChance       = $TurboChance
        TurboMinimumSpace = $TurboMinimumSpace
        SpaceWeight       = $SpaceWeight
        SpaceLimit        = $SpaceLimit
        TurnPenalty       = $TurnPenalty
        ForwardBias       = $ForwardBias
    }
}

function Test-GridBlocked {
    param(
        [Parameter(Mandatory = $true)]
        $Arena,

        [Parameter(Mandatory = $true)]
        $Snapshot,

        [int] $X,
        [int] $Y
    )

    if ($X -lt 0 -or $X -ge $Snapshot.Width -or $Y -lt 1 -or $Y -ge $Snapshot.Height) {
        return $true
    }

    return ($Arena.Grid[$X, $Y] -ne 0)
}

function Get-SafeDistance {
    param(
        [Parameter(Mandatory = $true)]
        $Arena,

        [Parameter(Mandatory = $true)]
        $Snapshot,

        [int] $StartX,
        [int] $StartY,
        [int] $Dx,
        [int] $Dy,
        [int] $MaximumDistance
    )

    $distance = 0
    $x = $StartX
    $y = $StartY

    while ($distance -lt $MaximumDistance) {
        if (Test-GridBlocked -Arena $Arena -Snapshot $Snapshot -X $x -Y $y) {
            break
        }

        $distance++
        $x += $Dx
        $y += $Dy
    }

    return $distance
}

function Get-ReachableSpace {
    param(
        [Parameter(Mandatory = $true)]
        $Arena,

        [Parameter(Mandatory = $true)]
        $Snapshot,

        [int] $StartX,
        [int] $StartY,
        [int] $MaximumCells
    )

    if ($MaximumCells -le 0) {
        return 0
    }

    if (Test-GridBlocked -Arena $Arena -Snapshot $Snapshot -X $StartX -Y $StartY) {
        return 0
    }

    $visited = [Array]::CreateInstance([bool], $Snapshot.Width, $Snapshot.Height)
    $queueX = New-Object "int[]" $MaximumCells
    $queueY = New-Object "int[]" $MaximumCells
    $head = 0
    $tail = 0
    $count = 0

    $queueX[$tail] = $StartX
    $queueY[$tail] = $StartY
    $tail++
    $visited[$StartX, $StartY] = $true

    while ($head -lt $tail -and $count -lt $MaximumCells) {
        $x = $queueX[$head]
        $y = $queueY[$head]
        $head++
        $count++

        for ($directionIndex = 0; $directionIndex -lt 4; $directionIndex++) {
            switch ($directionIndex) {
                0 {
                    $nextX = $x
                    $nextY = $y - 1
                }
                1 {
                    $nextX = $x + 1
                    $nextY = $y
                }
                2 {
                    $nextX = $x
                    $nextY = $y + 1
                }
                default {
                    $nextX = $x - 1
                    $nextY = $y
                }
            }

            if ($nextX -lt 0 -or $nextX -ge $Snapshot.Width -or $nextY -lt 1 -or $nextY -ge $Snapshot.Height) {
                continue
            }

            if ($visited[$nextX, $nextY]) {
                continue
            }

            if ($Arena.Grid[$nextX, $nextY] -ne 0) {
                continue
            }

            $visited[$nextX, $nextY] = $true
            if ($tail -lt $MaximumCells) {
                $queueX[$tail] = $nextX
                $queueY[$tail] = $nextY
                $tail++
            }
        }
    }

    return $count
}

function Get-ManhattanDistance {
    param(
        [int] $X1,
        [int] $Y1,
        [int] $X2,
        [int] $Y2
    )

    return ([Math]::Abs($X1 - $X2) + [Math]::Abs($Y1 - $Y2))
}

function Get-AIDirectionChoice {
    param(
        [Parameter(Mandatory = $true)]
        $Player,

        [Parameter(Mandatory = $true)]
        [object[]] $Players,

        [Parameter(Mandatory = $true)]
        $Arena,

        [Parameter(Mandatory = $true)]
        $Snapshot,

        [Parameter(Mandatory = $true)]
        $Profile
    )

    $directions = @(
        [pscustomobject] @{ Dx = 0; Dy = -1 },
        [pscustomobject] @{ Dx = 1; Dy = 0 },
        [pscustomobject] @{ Dx = 0; Dy = 1 },
        [pscustomobject] @{ Dx = -1; Dy = 0 }
    )

    $target = $Players[0]
    $bestChoice = $null
    $bestScore = -1000000
    $lookAhead = [Math]::Max(1, $Profile.LookAhead)
    $spaceLimit = [Math]::Max(20, $Profile.SpaceLimit)

    foreach ($direction in $directions) {
        if (($direction.Dx + $Player.Dx) -eq 0 -and ($direction.Dy + $Player.Dy) -eq 0) {
            continue
        }

        $nextX = $Player.X + $direction.Dx
        $nextY = $Player.Y + $direction.Dy

        if (Test-GridBlocked -Arena $Arena -Snapshot $Snapshot -X $nextX -Y $nextY) {
            continue
        }

        $safeDistance = Get-SafeDistance `
            -Arena $Arena `
            -Snapshot $Snapshot `
            -StartX $nextX `
            -StartY $nextY `
            -Dx $direction.Dx `
            -Dy $direction.Dy `
            -MaximumDistance $lookAhead

        $openSpace = Get-ReachableSpace `
            -Arena $Arena `
            -Snapshot $Snapshot `
            -StartX $nextX `
            -StartY $nextY `
            -MaximumCells $spaceLimit

        $edgeDistanceX = [Math]::Min($nextX, ($Snapshot.Width - 1 - $nextX))
        $edgeDistanceY = [Math]::Min(($nextY - 1), ($Snapshot.Height - 1 - $nextY))
        $edgeDistance = [Math]::Max(0, [Math]::Min($edgeDistanceX, $edgeDistanceY))
        $currentTargetDistance = Get-ManhattanDistance -X1 $Player.X -Y1 $Player.Y -X2 $target.X -Y2 $target.Y
        $nextTargetDistance = Get-ManhattanDistance -X1 $nextX -Y1 $nextY -X2 $target.X -Y2 $target.Y
        $targetFutureX = $target.X + ($target.Dx * 3)
        $targetFutureY = $target.Y + ($target.Dy * 3)
        $currentFutureDistance = Get-ManhattanDistance -X1 $Player.X -Y1 $Player.Y -X2 $targetFutureX -Y2 $targetFutureY
        $nextFutureDistance = Get-ManhattanDistance -X1 $nextX -Y1 $nextY -X2 $targetFutureX -Y2 $targetFutureY
        $turning = -not ($direction.Dx -eq $Player.Dx -and $direction.Dy -eq $Player.Dy)

        $score = ($safeDistance * 12) + ($openSpace * $Profile.SpaceWeight) + ([Math]::Min($edgeDistance, 8) * 4)
        $score += (($currentTargetDistance - $nextTargetDistance) * $Profile.Aggression)
        $score += (($currentFutureDistance - $nextFutureDistance) * [Math]::Floor($Profile.Aggression / 2))

        if ($safeDistance -lt 3) {
            $score -= ((3 - $safeDistance) * 55)
        }

        if ($openSpace -lt 28) {
            $score -= ((28 - $openSpace) * 10)
        }

        if ($turning) {
            $score -= $Profile.TurnPenalty
        }
        else {
            $score += $Profile.ForwardBias
        }

        if ($Profile.Jitter -gt 0) {
            $score += (Get-Random -Minimum (-1 * $Profile.Jitter) -Maximum ($Profile.Jitter + 1))
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestChoice = [pscustomobject] @{
                Dx           = $direction.Dx
                Dy           = $direction.Dy
                SafeDistance = $safeDistance
                OpenSpace    = $openSpace
                Score        = $score
            }
        }
    }

    return $bestChoice
}

function Update-AIPlayers {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Players,

        [Parameter(Mandatory = $true)]
        $Arena,

        [Parameter(Mandatory = $true)]
        $Snapshot,

        [object[]] $AiProfiles = @(),

        [bool] $TurboEnabled = $true
    )

    foreach ($profile in $AiProfiles) {
        $playerIndex = $profile.PlayerNumber - 1
        if ($playerIndex -lt 0 -or $playerIndex -ge $Players.Count) {
            continue
        }

        $player = $Players[$playerIndex]
        if (-not $player.Active) {
            continue
        }

        $choice = Get-AIDirectionChoice `
            -Player $player `
            -Players $Players `
            -Arena $Arena `
            -Snapshot $Snapshot `
            -Profile $profile

        if ($null -eq $choice) {
            continue
        }

        Set-PendingDirection -Player $player -Dx $choice.Dx -Dy $choice.Dy

        if (
            $TurboEnabled -and
            $choice.SafeDistance -ge $profile.TurboMinimumSpace -and
            $profile.TurboChance -gt 0 -and
            (Get-Random -Minimum 0 -Maximum 100) -lt $profile.TurboChance
        ) {
            Invoke-PlayerTurbo -Player $player -TurboEnabled $TurboEnabled
        }
    }
}

function Start-Round {
    param(
        [Parameter(Mandatory = $true)]
        [int[]] $Scores,

        [ValidateSet(2, 3)]
        [int] $PlayerCount,

        [int] $RoundTickMilliseconds,

        [bool] $TurboEnabled = $true,

        [object[]] $AiProfiles = @(),

        [string[]] $PlayerLabels = @("P1", "P2", "P3"),

        [int[]] $HumanPlayerNumbers = @(1, 2, 3),

        [bool] $EndWhenPlayerOneEliminated = $false
    )

    $snapshot = Get-ConsoleSnapshot
    if ($snapshot.Width -lt 40 -or $snapshot.Height -lt 12) {
        return [pscustomobject] @{
            Status  = "TooSmall"
            Message = "The terminal must be at least 40 columns by 12 rows."
        }
    }

    $arena = New-Arena -Snapshot $snapshot -Scores $Scores -PlayerCount $PlayerCount -TurboEnabled $TurboEnabled -PlayerLabels $PlayerLabels -HumanPlayerNumbers $HumanPlayerNumbers
    [Tron.NativeConsole]::WriteBuffer(
        $snapshot.WindowLeft,
        $snapshot.WindowTop,
        $snapshot.Width,
        $snapshot.Height,
        $arena.Characters,
        $arena.Attributes
    )

    [object[]] $players = $arena.Players
    Clear-GameInput
    $clock = [Diagnostics.Stopwatch]::StartNew()
    [double] $frameMilliseconds = [Math]::Max(1.0, ([double] $RoundTickMilliseconds / 2.0))
    [double] $nextFrame = $frameMilliseconds
    [int] $frameNumber = 0

    while ($true) {
        while ($clock.Elapsed.TotalMilliseconds -lt $nextFrame) {
            if (-not (Test-ConsoleSnapshot -Snapshot $snapshot)) {
                return [pscustomobject] @{
                    Status  = "Resize"
                    Message = "The terminal was resized. The round was cancelled."
                }
            }

            if (Read-GameInput -Players $players -TurboEnabled $TurboEnabled -HumanPlayerNumbers $HumanPlayerNumbers) {
                return [pscustomobject] @{
                    Status  = "Quit"
                    Message = ""
                }
            }

            Start-Sleep -Milliseconds 2
        }

        if (Read-GameInput -Players $players -TurboEnabled $TurboEnabled -HumanPlayerNumbers $HumanPlayerNumbers) {
            return [pscustomobject] @{
                Status  = "Quit"
                Message = ""
            }
        }

        Update-AIPlayers `
            -Players $players `
            -Arena $arena `
            -Snapshot $snapshot `
            -AiProfiles $AiProfiles `
            -TurboEnabled $TurboEnabled

        $frameNumber++
        $baseTickFrame = (($frameNumber % 2) -eq 0)
        [int[]] $nextX = New-Object "int[]" $players.Count
        [int[]] $nextY = New-Object "int[]" $players.Count
        [bool[]] $crashed = New-Object "bool[]" $players.Count
        [bool[]] $willMove = New-Object "bool[]" $players.Count

        for ($index = 0; $index -lt $players.Count; $index++) {
            $player = $players[$index]
            if (-not $player.Active) {
                continue
            }

            $willMove[$index] = ($baseTickFrame -or ($TurboEnabled -and $player.TurboTicksRemaining -gt 0))
            if (-not $willMove[$index]) {
                continue
            }

            $player.Dx = $player.PendingDx
            $player.Dy = $player.PendingDy
            $nextX[$index] = $player.X + $player.Dx
            $nextY[$index] = $player.Y + $player.Dy

            $crashed[$index] = (
                $nextX[$index] -lt 0 -or $nextX[$index] -ge $snapshot.Width -or
                $nextY[$index] -lt 1 -or $nextY[$index] -ge $snapshot.Height -or
                $arena.Grid[$nextX[$index], $nextY[$index]] -ne 0
            )
        }

        for ($firstIndex = 0; $firstIndex -lt $players.Count; $firstIndex++) {
            if (-not $willMove[$firstIndex]) {
                continue
            }

            for ($secondIndex = $firstIndex + 1; $secondIndex -lt $players.Count; $secondIndex++) {
                if (-not $willMove[$secondIndex]) {
                    continue
                }

                if (
                    $nextX[$firstIndex] -eq $nextX[$secondIndex] -and
                    $nextY[$firstIndex] -eq $nextY[$secondIndex]
                ) {
                    $crashed[$firstIndex] = $true
                    $crashed[$secondIndex] = $true
                }
            }
        }

        $someoneCrashed = $false
        for ($index = 0; $index -lt $players.Count; $index++) {
            $player = $players[$index]
            if (-not $willMove[$index]) {
                continue
            }

            if ($crashed[$index]) {
                $player.Active = $false
                $someoneCrashed = $true
                continue
            }

            $player.X = $nextX[$index]
            $player.Y = $nextY[$index]
            $arena.Grid[$player.X, $player.Y] = $player.CellValue
            if ($TurboEnabled -and $player.TurboTicksRemaining -gt 0) {
                $cellAttribute = $player.TurboColorAttribute
            }
            else {
                $cellAttribute = $player.ColorAttribute
            }
            $bufferIndex = ($player.Y * $snapshot.Width) + $player.X
            $arena.Characters[$bufferIndex] = [char] " "
            $arena.Attributes[$bufferIndex] = $cellAttribute
            [Tron.NativeConsole]::WriteCell(
                $snapshot.WindowLeft + $player.X,
                $snapshot.WindowTop + $player.Y,
                [char] " ",
                $cellAttribute
            )
        }

        if ($baseTickFrame) {
            Update-TurboTimers -Players $players
            Update-Header -Snapshot $snapshot -Arena $arena -Scores $Scores -PlayerCount $PlayerCount -TurboEnabled $TurboEnabled -PlayerLabels $PlayerLabels -HumanPlayerNumbers $HumanPlayerNumbers
        }

        if ($someoneCrashed) {
            $activePlayers = @($players | Where-Object { $_.Active })
            if ($activePlayers.Count -eq 0) {
                return [pscustomobject] @{
                    Status       = "Draw"
                    Message      = "DRAW - No cycles survived."
                    WinnerNumber = 0
                }
            }
            if ($EndWhenPlayerOneEliminated -and -not $players[0].Active) {
                $winnerNumber = $activePlayers[0].Number
                return [pscustomobject] @{
                    Status       = "Winner"
                    Message      = "GRID WINS"
                    WinnerNumber = $winnerNumber
                }
            }
            if ($activePlayers.Count -eq 1) {
                $winnerNumber = $activePlayers[0].Number
                return [pscustomobject] @{
                    Status       = "Winner"
                    Message      = "PLAYER {0} WINS" -f $winnerNumber
                    WinnerNumber = $winnerNumber
                }
            }
        }

        $nextFrame += $frameMilliseconds
        if ($clock.Elapsed.TotalMilliseconds -gt ($nextFrame + ($frameMilliseconds * 2.0))) {
            $nextFrame = $clock.Elapsed.TotalMilliseconds + $frameMilliseconds
        }
    }
}

function Show-RoundResult {
    param(
        [Parameter(Mandatory = $true)]
        $Result
    )

    if ($Result.Status -eq "Resize" -or $Result.Status -eq "TooSmall") {
        Clear-Host
        $snapshot = Get-ConsoleSnapshot
        $messageRow = [Math]::Max(0, [Math]::Floor($snapshot.Height / 2) - 1)
        Write-CenteredMenuLine -Text $Result.Message -Row $messageRow -Color Yellow
        Write-CenteredMenuLine -Text "R: retry   M: main menu   ESC: quit" -Row ($messageRow + 2) -Color White
    }
    else {
        $snapshot = Get-ConsoleSnapshot
        $message = "  {0}  " -f $Result.Message
        $prompt = "  R: rematch   M: main menu   ESC: quit  "
        $messageX = $snapshot.WindowLeft + [Math]::Max(0, [Math]::Floor(($snapshot.Width - $message.Length) / 2))
        $promptX = $snapshot.WindowLeft + [Math]::Max(0, [Math]::Floor(($snapshot.Width - $prompt.Length) / 2))
        $messageY = $snapshot.WindowTop + [Math]::Floor($snapshot.Height / 2)
        $promptY = [Math]::Min(
            $snapshot.WindowTop + $snapshot.Height - 2,
            $messageY + 2
        )

        if ($message.Length -gt $snapshot.Width) {
            $message = $message.Substring(0, $snapshot.Width)
            $messageX = $snapshot.WindowLeft
        }
        if ($prompt.Length -gt $snapshot.Width) {
            $prompt = $prompt.Substring(0, $snapshot.Width)
            $promptX = $snapshot.WindowLeft
        }

        [Tron.NativeConsole]::WriteText($messageX, $messageY, $message, [int16] 14)
        [Tron.NativeConsole]::WriteText($promptX, $promptY, $prompt, [int16] 15)
    }

    while ($true) {
        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            "R"      { return "Restart" }
            "M"      { return "Menu" }
            "Escape" { return "Quit" }
        }
    }
}

function Wait-CampaignPrompt {
    param(
        [bool] $AllowRetry = $false,
        [bool] $AnyKeyContinues = $true
    )

    while ($true) {
        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            "Escape" { return "Quit" }
            "M"      { return "Menu" }
            "R"      {
                if ($AllowRetry) {
                    return "Retry"
                }
                if ($AnyKeyContinues) {
                    return "Continue"
                }
            }
            default  { if ($AnyKeyContinues) { return "Continue" } }
        }
    }
}

function Show-CampaignTextScreen {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Title,

        [string[]] $Lines = @(),

        [Parameter(Mandatory = $true)]
        [string] $Prompt,

        [bool] $AllowRetry = $false,

        [bool] $AnyKeyContinues = $true,

        [ConsoleColor] $TitleColor = [ConsoleColor]::Cyan
    )

    Clear-Host
    $snapshot = Get-ConsoleSnapshot
    $totalRows = 2 + $Lines.Count + 2
    $firstRow = [Math]::Max(0, [Math]::Floor(($snapshot.Height - $totalRows) / 2))

    Write-CenteredMenuLine -Text $Title -Row $firstRow -Color $TitleColor

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        Write-CenteredMenuLine -Text $Lines[$index] -Row ($firstRow + 2 + $index) -Color Gray
    }

    Write-CenteredMenuLine -Text $Prompt -Row ($firstRow + $Lines.Count + 4) -Color DarkGray
    return (Wait-CampaignPrompt -AllowRetry $AllowRetry -AnyKeyContinues $AnyKeyContinues)
}

function Get-ClampedTickMilliseconds {
    param(
        [int] $TickMilliseconds
    )

    return [Math]::Min(250, [Math]::Max(25, $TickMilliseconds))
}

function Get-CampaignLevels {
    param(
        [int] $BaseTickMilliseconds
    )

    @(
        [pscustomobject] @{
            Number           = 1
            Name             = "Sector 1: Training Grid"
            PlayerCount      = 2
            TickMilliseconds = (Get-ClampedTickMilliseconds -TickMilliseconds ($BaseTickMilliseconds + 10))
            PlayerLabels     = @("YOU", "SCOUT", "P3")
            AiProfiles       = @(
                (New-AIProfile -PlayerNumber 2 -Name "Scout" -LookAhead 8 -Jitter 18 -Aggression 0 -TurboChance 0 -TurboMinimumSpace 9 -SpaceWeight 5 -SpaceLimit 120 -TurnPenalty 18 -ForwardBias 18)
            )
        },
        [pscustomobject] @{
            Number           = 2
            Name             = "Sector 2: Hunter Grid"
            PlayerCount      = 2
            TickMilliseconds = (Get-ClampedTickMilliseconds -TickMilliseconds $BaseTickMilliseconds)
            PlayerLabels     = @("YOU", "HUNTER", "P3")
            AiProfiles       = @(
                (New-AIProfile -PlayerNumber 2 -Name "Hunter" -LookAhead 10 -Jitter 12 -Aggression 3 -TurboChance 7 -TurboMinimumSpace 10 -SpaceWeight 5 -SpaceLimit 170 -TurnPenalty 20 -ForwardBias 18)
            )
        },
        [pscustomobject] @{
            Number           = 3
            Name             = "Sector 3: Pincer Grid"
            PlayerCount      = 3
            TickMilliseconds = (Get-ClampedTickMilliseconds -TickMilliseconds ($BaseTickMilliseconds - 5))
            PlayerLabels     = @("YOU", "PINCR", "ROOK")
            AiProfiles       = @(
                (New-AIProfile -PlayerNumber 2 -Name "Pincer" -LookAhead 10 -Jitter 10 -Aggression 7 -TurboChance 12 -TurboMinimumSpace 10 -SpaceWeight 4 -SpaceLimit 210 -TurnPenalty 14 -ForwardBias 10),
                (New-AIProfile -PlayerNumber 3 -Name "Rook" -LookAhead 10 -Jitter 8 -Aggression 2 -TurboChance 6 -TurboMinimumSpace 11 -SpaceWeight 6 -SpaceLimit 220 -TurnPenalty 24 -ForwardBias 22)
            )
        },
        [pscustomobject] @{
            Number           = 4
            Name             = "Sector 4: MCP Core"
            PlayerCount      = 3
            TickMilliseconds = (Get-ClampedTickMilliseconds -TickMilliseconds ($BaseTickMilliseconds - 10))
            PlayerLabels     = @("YOU", "MCP", "GUARD")
            AiProfiles       = @(
                (New-AIProfile -PlayerNumber 2 -Name "MCP" -LookAhead 13 -Jitter 6 -Aggression 10 -TurboChance 18 -TurboMinimumSpace 11 -SpaceWeight 5 -SpaceLimit 280 -TurnPenalty 15 -ForwardBias 10),
                (New-AIProfile -PlayerNumber 3 -Name "Guard" -LookAhead 12 -Jitter 6 -Aggression 5 -TurboChance 12 -TurboMinimumSpace 12 -SpaceWeight 7 -SpaceLimit 260 -TurnPenalty 22 -ForwardBias 18)
            )
        }
    )
}

function Show-CampaignLevelIntro {
    param(
        [Parameter(Mandatory = $true)]
        $Level
    )

    $enemyText = if ($Level.PlayerCount -eq 2) {
        "Opponent: {0}" -f $Level.PlayerLabels[1]
    }
    else {
        "Opponents: {0} and {1}" -f $Level.PlayerLabels[1], $Level.PlayerLabels[2]
    }

    return Show-CampaignTextScreen `
        -Title ("CAMPAIGN LEVEL {0}" -f $Level.Number) `
        -Lines @(
            $Level.Name,
            $enemyText,
            "Best of 3. First side to 2 round wins advances.",
            "P1 controls: WASD to steer, F for turbo."
        ) `
        -Prompt "Press any key to launch   M: main menu   ESC: quit" `
        -TitleColor Cyan
}

function Show-CampaignRoundSummary {
    param(
        [Parameter(Mandatory = $true)]
        $Level,

        [Parameter(Mandatory = $true)]
        $Result,

        [int] $PlayerWins,
        [int] $EnemyWins
    )

    if ($Result.Status -eq "Draw") {
        $roundLine = "Round result: draw. No score awarded."
    }
    elseif ($Result.WinnerNumber -eq 1) {
        $roundLine = "Round result: YOU scored."
    }
    else {
        $roundLine = "Round result: GRID scored."
    }

    return Show-CampaignTextScreen `
        -Title $Level.Name `
        -Lines @(
            $roundLine,
            ("Match score: YOU {0}  GRID {1}" -f $PlayerWins, $EnemyWins)
        ) `
        -Prompt "Press any key for next round   M: main menu   ESC: quit" `
        -TitleColor Yellow
}

function Show-CampaignLevelCleared {
    param(
        [Parameter(Mandatory = $true)]
        $Level,

        [int] $PlayerWins,
        [int] $EnemyWins
    )

    return Show-CampaignTextScreen `
        -Title "SECTOR CLEARED" `
        -Lines @(
            $Level.Name,
            ("Final match score: YOU {0}  GRID {1}" -f $PlayerWins, $EnemyWins),
            "The next grid is faster and less forgiving."
        ) `
        -Prompt "Press any key to continue   M: main menu   ESC: quit" `
        -TitleColor Green
}

function Show-CampaignDefeat {
    param(
        [Parameter(Mandatory = $true)]
        $Level,

        [int] $PlayerWins,
        [int] $EnemyWins
    )

    return Show-CampaignTextScreen `
        -Title "DEREZZED" `
        -Lines @(
            $Level.Name,
            ("Final match score: YOU {0}  GRID {1}" -f $PlayerWins, $EnemyWins),
            "Campaign run terminated."
        ) `
        -Prompt "R: retry campaign   M: main menu   ESC: quit" `
        -AllowRetry $true `
        -AnyKeyContinues $false `
        -TitleColor Red
}

function Show-CampaignVictory {
    return Show-CampaignTextScreen `
        -Title "SYSTEM LIBERATED" `
        -Lines @(
            "You cleared every sector.",
            "The grid recognizes its new operator.",
            "Campaign complete."
        ) `
        -Prompt "R: replay campaign   M: main menu   ESC: quit" `
        -AllowRetry $true `
        -AnyKeyContinues $false `
        -TitleColor Cyan
}

function Invoke-CampaignRun {
    param(
        [int] $BaseTickMilliseconds,
        [bool] $TurboEnabled
    )

    $levels = Get-CampaignLevels -BaseTickMilliseconds $BaseTickMilliseconds

    foreach ($level in $levels) {
        $levelAction = Show-CampaignLevelIntro -Level $level
        if ($levelAction -eq "Menu" -or $levelAction -eq "Quit") {
            return $levelAction
        }

        [int[]] $scores = @(0, 0, 0)
        $playerWins = 0
        $enemyWins = 0

        while ($playerWins -lt 2 -and $enemyWins -lt 2) {
            Show-Countdown
            $result = Start-Round `
                -Scores $scores `
                -PlayerCount $level.PlayerCount `
                -RoundTickMilliseconds $level.TickMilliseconds `
                -TurboEnabled $TurboEnabled `
                -AiProfiles $level.AiProfiles `
                -PlayerLabels $level.PlayerLabels `
                -HumanPlayerNumbers @(1) `
                -EndWhenPlayerOneEliminated $true

            if ($result.Status -eq "Quit") {
                return "Quit"
            }

            if ($result.Status -eq "Resize" -or $result.Status -eq "TooSmall") {
                $resizeAction = Show-RoundResult -Result $result
                if ($resizeAction -eq "Restart") {
                    continue
                }
                return $resizeAction
            }

            if ($result.Status -eq "Winner") {
                if ($result.WinnerNumber -eq 1) {
                    $playerWins++
                }
                else {
                    $enemyWins++
                }

                $scores[$result.WinnerNumber - 1]++
            }

            if ($playerWins -lt 2 -and $enemyWins -lt 2) {
                $roundAction = Show-CampaignRoundSummary `
                    -Level $level `
                    -Result $result `
                    -PlayerWins $playerWins `
                    -EnemyWins $enemyWins
                if ($roundAction -eq "Menu" -or $roundAction -eq "Quit") {
                    return $roundAction
                }
            }
        }

        if ($enemyWins -ge 2) {
            return (Show-CampaignDefeat -Level $level -PlayerWins $playerWins -EnemyWins $enemyWins)
        }

        if ($level.Number -lt $levels.Count) {
            $clearAction = Show-CampaignLevelCleared `
                -Level $level `
                -PlayerWins $playerWins `
                -EnemyWins $enemyWins
            if ($clearAction -eq "Menu" -or $clearAction -eq "Quit") {
                return $clearAction
            }
        }
    }

    return (Show-CampaignVictory)
}

function Start-Campaign {
    param(
        [int] $BaseTickMilliseconds,
        [bool] $TurboEnabled
    )

    while ($true) {
        $campaignAction = Invoke-CampaignRun `
            -BaseTickMilliseconds $BaseTickMilliseconds `
            -TurboEnabled $TurboEnabled

        if ($campaignAction -eq "Retry") {
            continue
        }

        return $campaignAction
    }
}

function Start-Tron {
    if ($env:OS -ne "Windows_NT") {
        throw "Tron.ps1 requires Windows and is intended to run in Windows Terminal."
    }

    Initialize-NativeConsole

    $originalCursorVisible = [Console]::CursorVisible
    $originalForegroundColor = [Console]::ForegroundColor
    $originalBackgroundColor = [Console]::BackgroundColor
    $originalTitle = [Console]::Title
    [int[]] $scores = @(0, 0, 0)
    $playerCount = 2
    $currentTickMilliseconds = $TickMilliseconds
    $turboEnabled = $true
    $showMenu = $true

    try {
        [Console]::CursorVisible = $false
        [Console]::Title = "TRON"

        while ($true) {
            if ($showMenu) {
                $menuResult = Show-MainMenu `
                    -InitialPlayerCount $playerCount `
                    -InitialTickMilliseconds $currentTickMilliseconds `
                    -InitialTurboEnabled $turboEnabled
                if ($menuResult.Action -eq "Quit") {
                    break
                }

                $playerCount = $menuResult.PlayerCount
                $currentTickMilliseconds = $menuResult.TickMilliseconds
                $turboEnabled = $menuResult.TurboEnabled
                [int[]] $scores = @(0, 0, 0)
                $showMenu = $false
            }

            if ($playerCount -eq 1) {
                $campaignAction = Start-Campaign `
                    -BaseTickMilliseconds $currentTickMilliseconds `
                    -TurboEnabled $turboEnabled

                if ($campaignAction -eq "Quit") {
                    break
                }

                $showMenu = $true
                continue
            }

            Show-Countdown
            $result = Start-Round `
                -Scores $scores `
                -PlayerCount $playerCount `
                -RoundTickMilliseconds $currentTickMilliseconds `
                -TurboEnabled $turboEnabled

            if ($result.Status -eq "Quit") {
                break
            }

            if ($result.Status -eq "Winner") {
                $scores[$result.WinnerNumber - 1]++
            }

            $nextAction = Show-RoundResult -Result $result
            if ($nextAction -eq "Quit") {
                break
            }
            if ($nextAction -eq "Menu") {
                $showMenu = $true
            }
        }

        Clear-Host
    }
    finally {
        [Console]::ForegroundColor = $originalForegroundColor
        [Console]::BackgroundColor = $originalBackgroundColor
        [Console]::CursorVisible = $originalCursorVisible
        [Console]::Title = $originalTitle
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    Start-Tron
}
