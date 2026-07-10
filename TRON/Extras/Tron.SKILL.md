---
name: modify-tron-ps1
description: Use when modifying, reviewing, debugging, or extending Tron.ps1, a Windows PowerShell 5.1 Windows Terminal Tron light-cycle game, including menu flow, rendering, input, turbo, colors, AI profiles, campaign levels, versus mode, validation, and release-safe changes.
---

# Modify Tron.ps1

## Core rules

- Keep `Tron.ps1` compatible with Windows PowerShell 5.1.
- Keep script content ASCII-only. Do not add emoji, smart quotes, special dashes, box drawing characters, or hidden Unicode.
- Keep `$ErrorActionPreference = "Stop"` and `Set-StrictMode -Version 2.0` friendly: initialize variables, avoid relying on missing properties, and wrap pipeline results with `@(...)` when count or indexing may be needed.
- Do not use `Clear-Host` during active round movement. It is acceptable in menus, countdowns, result screens, and campaign or versus text screens.
- Do not reintroduce low-level console input P/Invoke, keyboard hooks, or global key state checks. Input should use `[Console]::KeyAvailable` and `[Console]::ReadKey($true)`.
- Native console P/Invoke should remain output-only unless the user explicitly accepts a wider security footprint. The current native helper uses `WriteConsoleOutputW` for fast repainting.
- Preserve user changes. Inspect before patching and make narrow edits.

## Repository map

- `Tron.ps1` is the release script and primary edit target.
- `Legacy/` contains backups. Do not modify it unless the user asks.
- `Spacegame_reference.ps1` is reference material. Do not modify it unless the user asks.
- `SKILL.md` is this modification guide.

## Architecture map

- Startup and main loop: `Start-Tron`
- Native repaint setup: `Initialize-NativeConsole`
- Menu helpers: `Write-CenteredMenuLine`, `Write-MenuSegmentsAtColumn`, `Write-MenuOptionLine`, `Get-MenuNumberFromKey`
- Main menu: `Show-MainMenu`
- Countdown: `Show-Countdown`
- Arena/player setup: `New-Arena`, `New-Player`
- Active round engine: `Start-Round`
- Gameplay input: `Clear-GameInput`, `Read-GameInput`
- Header rendering: `Get-HeaderSegments`, `Set-HeaderBuffer`, `Write-HeaderBuffer`, `Update-Header`
- Turbo: `Invoke-PlayerTurbo`, `Update-TurboTimers`, `Get-TurboKeyAttribute`
- AI profiles and decisions: `New-AIProfile`, `Get-AIDirectionChoice`, `Test-AIEmergencyReaction`, `Update-AIPlayers`
- Color mapping: `Get-PlayerColorSet`, `Get-PlayerColorArrays`
- Campaign: `Get-CampaignLevels`, `Invoke-CampaignRun`, `Start-Campaign`
- Versus: `Get-VersusOpponents`, `New-VersusOpponentSelection`, `Show-VersusMenu`, `Start-VersusMatch`

## Gameplay invariants

- Row 0 is the header. The arena begins at row 1.
- Arena perimeter walls use `#`.
- Arrays for scores, labels, and color attributes assume a maximum of three player slots unless deliberately refactored.
- Player numbers are one-based in profiles and labels. Array indexes are zero-based.
- In campaign and single-player versus, P1 is human and AI profiles normally target player slots 2 and 3.
- `Start-Round` returns status objects. Preserve existing status names: `Winner`, `Draw`, `Quit`, `Resize`, and `TooSmall`.
- `Esc` is the quit key. Do not restore `Q` as a quit key because P1 uses WASD.

## Rendering rules

- During active gameplay, update cells and the header through the repaint path. Do not clear and redraw the whole terminal with `Clear-Host`.
- Existing trail cells are drawn as spaces with background color attributes.
- Normal trails use `ColorAttribute`; turbo trails use `TurboColorAttribute`.
- The header uses foreground color attributes and dark gray turbo keys when turbo is unavailable or disabled.
- If changing arena dimensions or header layout, preserve resize detection and too-small handling in `Start-Round`.

## Input rules

- Gameplay input is non-blocking and uses `[Console]::KeyAvailable` inside `Read-GameInput`.
- Menu input is blocking and uses `[Console]::ReadKey($true)`.
- Main menu should support arrows, WASD, Enter, Space, and number shortcuts where applicable.
- Versus menu uses Up/Down or W/S for selection. Left/Right or A/D marks and unmarks the highlighted AI for 3-player versus.
- Current gameplay controls:
  - P1: WASD to steer, F for turbo
  - P2: arrow keys to steer, Enter for turbo
  - P3: IJKL to steer, Space for turbo

## Color rules

Console attributes use this pattern:

```powershell
attribute = (background * 16) + foreground
```

Header values are usually foreground colors. Trail values are usually background colors with black foreground.

Common color constants:

- Black: 0
- DarkBlue: 1
- DarkGreen: 2
- DarkCyan: 3
- DarkRed: 4
- DarkMagenta: 5
- DarkYellow: 6
- Gray: 7
- DarkGray: 8
- Blue: 9
- Green: 10
- Cyan: 11
- Red: 12
- Magenta: 13
- Yellow: 14
- White: 15

Examples:

- Cyan trail: `176`, because `11 * 16 + 0`
- Gray trail: `112`, because `7 * 16 + 0`
- DarkGray trail: `128`, because `8 * 16 + 0`
- White trail: `240`, because `15 * 16 + 0`

When adding a named player or AI, add a label case in `Get-PlayerColorSet` before relying on it in campaign or versus.

## AI tuning

Use existing profile fields before adding new AI mechanics.

- `LookAhead`: straight-line safety scan. Higher improves survival and costs more CPU.
- `Jitter`: random score noise. Lower is more consistent and less human.
- `Aggression`: reward for closing on P1 and P1 future position.
- `TurboChance`: chance to turbo when a chosen direction has enough safe space.
- `TurboMinimumSpace`: minimum safe distance required before turbo can fire.
- `SpaceWeight`: weight for reachable-space scoring.
- `SpaceLimit`: maximum cells sampled by reachable-space scoring.
- `TurnPenalty`: penalty for turning.
- `ForwardBias`: reward for continuing straight.
- `DecisionIntervalTicks`: planned reaction interval. `1` means decide every base tick.
- `EmergencyLookAhead`: how close danger must be before emergency reaction can override delay.
- `EmergencyChance`: chance that emergency reaction actually happens.

Higher difficulty usually means higher `LookAhead`, higher `Aggression`, higher `SpaceWeight`, higher `SpaceLimit`, lower `Jitter`, lower `DecisionIntervalTicks`, and stronger emergency reaction. Do not assume every higher value is more fun; test the resulting behavior.

## Adding or changing AI opponents

1. Add or update the AI color in `Get-PlayerColorSet`.
2. Add or update the profile in `Get-CampaignLevels`.
3. Use player slot 2 for 1v1 AI and slots 2 plus 3 for 3-player campaign levels.
4. Use `Get-PlayerColorArrays` with labels such as `@("YOU", "BOSS", "P3")`.
5. For 2-player levels, keep a placeholder third label such as `P3` so the fixed arrays remain populated.
6. Versus mode is generated from campaign profiles by `Get-VersusOpponents`. A new campaign AI normally appears in Versus automatically.
7. If remapping an AI profile to another slot, use `Copy-AIProfileForPlayer`.

## Changing menus

- Main menu layout lives in `Show-MainMenu`.
- Versus menu layout lives in `Show-VersusMenu`.
- Use `Write-MenuOptionLine` for selectable rows so selected color and hint behavior stay consistent.
- Keep number shortcuts aligned and predictable.
- Keep Enter and Space equivalent for starting or choosing items unless there is a specific reason not to.
- `Clear-Host` is acceptable in menu code.

## Validation checklist

Run parser validation after every script change:

```powershell
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\Tron.ps1'), [ref] $tokens, [ref] $errors) > $null
if ($errors.Count -eq 0) { 'PARSE_OK' } else { $errors | ForEach-Object { $_.Message } }
```

Run ASCII validation after every script or skill change:

```powershell
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path '.\Tron.ps1'))
$bad = $bytes | Where-Object { $_ -gt 127 }
if ($bad.Count -eq 0) { 'ASCII_OK' } else { 'NON_ASCII_BYTES=' + $bad.Count }
```

For skill changes, run the same ASCII check against `SKILL.md`.

Dot-source the script for helper checks. Dot-sourcing loads functions without starting the game because the script only calls `Start-Tron` when it is not dot-sourced.

```powershell
. .\Tron.ps1
$levels = @(Get-CampaignLevels -BaseTickMilliseconds 60)
$versus = @(Get-VersusOpponents -BaseTickMilliseconds 60)
"LEVELS=$($levels.Count)"
"VERSUS=$($versus.Count)"
```

For color checks:

```powershell
. .\Tron.ps1
$color = Get-PlayerColorSet -Name 'BOSS'
"BOSS=$($color.Header),$($color.Trail),$($color.TurboTrail)"
```

For AI or gameplay-affecting changes, also run the game manually in Windows Terminal:

```powershell
.\Tron.ps1
```

Do not run the interactive game as an automated validation step unless the user explicitly asks.

## PowerShell 5.1 pitfalls

- A single pipeline result may be a scalar, not an array. Wrap with `@(...)` before using `.Count` or indexes.
- StrictMode can turn missing properties into fatal errors. Check object shapes when adding menu or match objects.
- Keep color attributes as `[int16]` values.
- Avoid relying on PowerShell 7-only syntax or behavior.
- Keep Add-Type C# code compatible with the Windows PowerShell 5.1 runtime.
