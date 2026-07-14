#requires -Version 5.1

[CmdletBinding()]
param(
    [switch] $Quiet,
    [switch] $SmokeTest,
    [string] $CapturePath = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("NullwakeCanvas" -as [type])) {
    Add-Type -ReferencedAssemblies "System.Windows.Forms" -WarningAction SilentlyContinue -TypeDefinition @"
using System;
using System.Windows.Forms;

public sealed class NullwakeCanvas : Panel
{
    public NullwakeCanvas()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
        TabStop = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.UserPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw, true);
        UpdateStyles();
    }
}
"@
}

$script:GameVersion = "1.0.2"
$script:ProfilePath = Join-Path $PSScriptRoot ".nullwake_profile.json"
$script:G = $null
$script:Form = $null
$script:Canvas = $null
$script:Timer = $null
$script:Clock = $null
$script:LastTick = 0L
$script:Keys = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
$script:MouseX = 0.0
$script:MouseY = 0.0
$script:MouseDown = $false
$script:Assets = @{}
$script:PaintFailureReported = $false
$script:FatalError = $null

function Write-GameLog {
    param([string] $Message)

    if (-not $Quiet) {
        Write-Host ("[NULLWAKE] " + $Message) -ForegroundColor DarkCyan
    }
}

function New-ArrayList {
    return ,(New-Object System.Collections.ArrayList)
}

function Get-ClampedValue {
    param(
        [double] $Value,
        [double] $Minimum,
        [double] $Maximum
    )

    return [Math]::Max($Minimum, [Math]::Min($Maximum, $Value))
}

function Get-RandomDouble {
    param(
        [double] $Minimum = 0.0,
        [double] $Maximum = 1.0
    )

    return $Minimum + ((Get-Random -Minimum 0 -Maximum 1000000) / 1000000.0) * ($Maximum - $Minimum)
}

function Get-DistanceSquared {
    param(
        [double] $X1,
        [double] $Y1,
        [double] $X2,
        [double] $Y2
    )

    $dx = $X1 - $X2
    $dy = $Y1 - $Y2
    return ($dx * $dx) + ($dy * $dy)
}

function Get-NormalizedVector {
    param(
        [double] $X,
        [double] $Y
    )

    $length = [Math]::Sqrt(($X * $X) + ($Y * $Y))
    if ($length -lt 0.0001) {
        return [pscustomobject]@{ X = 0.0; Y = 0.0; Length = 0.0 }
    }

    return [pscustomobject]@{ X = $X / $length; Y = $Y / $length; Length = $length }
}

function Get-ArenaWidth {
    if ($null -eq $script:Canvas) {
        return 900.0
    }

    return [Math]::Max(620.0, $script:Canvas.ClientSize.Width - 270.0)
}

function Get-ArenaHeight {
    if ($null -eq $script:Canvas) {
        return 700.0
    }

    return [Math]::Max(500.0, $script:Canvas.ClientSize.Height)
}

function Import-Profile {
    $profile = @{
        BestScore = 0
        BestWave = 0
        Victories = 0
        Runs = 0
        TotalKills = 0
    }

    if (-not (Test-Path -LiteralPath $script:ProfilePath)) {
        return $profile
    }

    try {
        $loaded = Get-Content -LiteralPath $script:ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in @("BestScore", "BestWave", "Victories", "Runs", "TotalKills")) {
            if ($null -ne $loaded.$name) {
                $profile[$name] = [int]$loaded.$name
            }
        }
    }
    catch {
        Write-GameLog ("Profile could not be read: " + $_.Exception.Message)
    }

    return $profile
}

function Export-Profile {
    if ($null -eq $script:G -or $SmokeTest) {
        return
    }

    try {
        $script:G.Profile | ConvertTo-Json | Set-Content -LiteralPath $script:ProfilePath -Encoding UTF8
    }
    catch {
        Write-GameLog ("Profile could not be saved: " + $_.Exception.Message)
    }
}

function Initialize-Assets {
    $script:Assets = @{
        FontTiny = New-Object System.Drawing.Font("Segoe UI", 8.5, [Drawing.FontStyle]::Regular)
        FontSmall = New-Object System.Drawing.Font("Segoe UI", 10.0, [Drawing.FontStyle]::Regular)
        FontSmallBold = New-Object System.Drawing.Font("Segoe UI Semibold", 10.0, [Drawing.FontStyle]::Bold)
        FontBody = New-Object System.Drawing.Font("Segoe UI", 12.0, [Drawing.FontStyle]::Regular)
        FontBodyBold = New-Object System.Drawing.Font("Segoe UI Semibold", 12.0, [Drawing.FontStyle]::Bold)
        FontCard = New-Object System.Drawing.Font("Segoe UI Semibold", 15.0, [Drawing.FontStyle]::Bold)
        FontHeading = New-Object System.Drawing.Font("Segoe UI Semibold", 21.0, [Drawing.FontStyle]::Bold)
        FontTitle = New-Object System.Drawing.Font("Segoe UI Semibold", 42.0, [Drawing.FontStyle]::Bold)
        FontHuge = New-Object System.Drawing.Font("Segoe UI Semibold", 54.0, [Drawing.FontStyle]::Bold)
        StringCenter = New-Object System.Drawing.StringFormat
        StringRight = New-Object System.Drawing.StringFormat
    }

    $script:Assets.StringCenter.Alignment = [Drawing.StringAlignment]::Center
    $script:Assets.StringCenter.LineAlignment = [Drawing.StringAlignment]::Center
    $script:Assets.StringRight.Alignment = [Drawing.StringAlignment]::Far
}

function Remove-Assets {
    foreach ($item in @($script:Assets.Values)) {
        if ($item -is [System.IDisposable]) {
            $item.Dispose()
        }
    }
    $script:Assets = @{}
}

function New-GameState {
    $profile = Import-Profile
    $state = @{
        Mode = "Title"
        PreviousMode = "Title"
        Profile = $profile
        Stars = New-ArrayList
        Enemies = New-ArrayList
        Bullets = New-ArrayList
        EnemyBullets = New-ArrayList
        Particles = New-ArrayList
        Pickups = New-ArrayList
        Floaters = New-ArrayList
        UpgradeChoices = @()
        UpgradeRanks = @{}
        Wave = 0
        MaxWaves = 12
        WaveToSpawn = 0
        WaveTotal = 0
        SpawnClock = 0.0
        SpawnInterval = 0.8
        BossRequired = $false
        BossSpawned = $false
        BossArrivalClock = -1.0
        RunTime = 0.0
        Score = 0
        Kills = 0
        Combo = 0
        ComboClock = 0.0
        ScreenShake = 0.0
        Message = ""
        MessageClock = 0.0
        HelpFrom = "Title"
        Core = $null
        Player = $null
    }

    $script:G = $state
    Initialize-Starfield
}

function Initialize-Starfield {
    $script:G.Stars.Clear()
    $width = [Math]::Max(1100, $script:Canvas.ClientSize.Width)
    $height = [Math]::Max(700, $script:Canvas.ClientSize.Height)
    for ($i = 0; $i -lt 150; $i++) {
        [void]$script:G.Stars.Add([pscustomobject]@{
            X = Get-RandomDouble 0 $width
            Y = Get-RandomDouble 0 $height
            Size = Get-RandomDouble 0.5 2.2
            Alpha = Get-Random -Minimum 35 -Maximum 155
            Drift = Get-RandomDouble 1.0 8.0
        })
    }
}

function Get-UpgradeCatalog {
    return @(
        [pscustomobject]@{ Id = "Accelerant"; Name = "Accelerant Loop"; Max = 5; Color = [Drawing.Color]::FromArgb(255, 91, 172); Description = "Fire 12 percent faster per rank." },
        [pscustomobject]@{ Id = "Fork"; Name = "Forked Signal"; Max = 3; Color = [Drawing.Color]::FromArgb(100, 220, 255); Description = "Add one projectile with a wider spread." },
        [pscustomobject]@{ Id = "Hardlight"; Name = "Hardlight Lens"; Max = 5; Color = [Drawing.Color]::FromArgb(255, 203, 92); Description = "Projectiles deal 25 percent more base damage." },
        [pscustomobject]@{ Id = "Overclock"; Name = "Vector Overclock"; Max = 4; Color = [Drawing.Color]::FromArgb(117, 255, 183); Description = "Move 10 percent faster per rank." },
        [pscustomobject]@{ Id = "Hull"; Name = "Recursive Hull"; Max = 4; Color = [Drawing.Color]::FromArgb(255, 120, 132); Description = "Gain 25 max hull and restore hull." },
        [pscustomobject]@{ Id = "Beacon"; Name = "Beacon Lattice"; Max = 4; Color = [Drawing.Color]::FromArgb(144, 189, 255); Description = "Gain 90 beacon integrity and repair it." },
        [pscustomobject]@{ Id = "Magnet"; Name = "Gravimetric Net"; Max = 4; Color = [Drawing.Color]::FromArgb(196, 130, 255); Description = "Pull charge shards from farther away." },
        [pscustomobject]@{ Id = "Feedback"; Name = "Violent Feedback"; Max = 4; Color = [Drawing.Color]::FromArgb(255, 91, 172); Description = "Gain 7 percent critical chance." },
        [pscustomobject]@{ Id = "Phase"; Name = "Phase Capacitor"; Max = 4; Color = [Drawing.Color]::FromArgb(99, 242, 228); Description = "Dash recovers faster and releases damage." },
        [pscustomobject]@{ Id = "Static"; Name = "Static Halo"; Max = 5; Color = [Drawing.Color]::FromArgb(132, 153, 255); Description = "Damage and slow enemies close to the drone." },
        [pscustomobject]@{ Id = "Pierce"; Name = "Ghost Ammunition"; Max = 3; Color = [Drawing.Color]::FromArgb(225, 225, 245); Description = "Projectiles pass through one more target." },
        [pscustomobject]@{ Id = "Repair"; Name = "Patient Machines"; Max = 4; Color = [Drawing.Color]::FromArgb(121, 255, 147); Description = "Regenerate hull and beacon integrity." }
    )
}

function Get-UpgradeRank {
    param([string] $Id)

    if ($script:G.UpgradeRanks.ContainsKey($Id)) {
        return [int]$script:G.UpgradeRanks[$Id]
    }
    return 0
}

function New-Run {
    $arenaWidth = Get-ArenaWidth
    $arenaHeight = Get-ArenaHeight

    foreach ($name in @("Enemies", "Bullets", "EnemyBullets", "Particles", "Pickups", "Floaters")) {
        $script:G[$name].Clear()
    }

    $script:G.UpgradeRanks = @{}
    $script:G.UpgradeChoices = @()
    $script:G.Wave = 0
    $script:G.RunTime = 0.0
    $script:G.Score = 0
    $script:G.Kills = 0
    $script:G.Combo = 0
    $script:G.ComboClock = 0.0
    $script:G.ScreenShake = 0.0
    $script:G.Core = [pscustomobject]@{
        X = $arenaWidth * 0.5
        Y = $arenaHeight * 0.5
        HP = 700.0
        MaxHP = 700.0
        Radius = 42.0
        HitFlash = 0.0
        Rotation = 0.0
    }
    $script:G.Player = [pscustomobject]@{
        X = ($arenaWidth * 0.5)
        Y = ($arenaHeight * 0.5) + 105.0
        HP = 125.0
        MaxHP = 125.0
        Radius = 14.0
        Speed = 260.0
        Angle = -1.5708
        FireClock = 0.0
        DashClock = 0.0
        DashTime = 0.0
        DashX = 0.0
        DashY = -1.0
        Invulnerable = 0.0
        HitFlash = 0.0
        Energy = 0.0
        Down = $false
        RespawnClock = 0.0
        RegenClock = 0.0
    }

    $script:G.Profile.Runs = [int]$script:G.Profile.Runs + 1
    $script:G.Mode = "Playing"
    Start-Wave -WaveNumber 1
    Export-Profile
    Write-GameLog "New defense shift started."
}

function Start-Wave {
    param([int] $WaveNumber)

    $script:G.Wave = $WaveNumber
    $script:G.WaveTotal = 9 + ($WaveNumber * 4)
    $script:G.WaveToSpawn = $script:G.WaveTotal
    $script:G.SpawnInterval = [Math]::Max(0.24, 0.78 - ($WaveNumber * 0.035))
    $script:G.SpawnClock = 0.65
    $script:G.BossRequired = (($WaveNumber % 4) -eq 0)
    $script:G.BossSpawned = $false
    $script:G.BossArrivalClock = -1.0
    $script:G.Message = if ($script:G.BossRequired) { "ANOMALY WAVE $WaveNumber" } else { "WAVE $WaveNumber" }
    $script:G.MessageClock = 2.2
    Write-GameLog ("Wave {0} started with {1} contacts." -f $WaveNumber, $script:G.WaveTotal)

}

function Get-RandomEnemyKind {
    param([int] $Wave)

    $roll = Get-Random -Minimum 0 -Maximum 100
    $bulwarkChance = if ($Wave -ge 4) { [Math]::Min(18, 8 + $Wave) } else { 0 }
    $spitterChance = if ($Wave -ge 6) { [Math]::Min(16, 4 + $Wave) } else { 0 }
    $spitterCap = 1 + [int][Math]::Floor($Wave / 4.0)
    $activeSpitters = @($script:G.Enemies | Where-Object { -not $_.Dead -and $_.Kind -eq "Spitter" }).Count
    if ($activeSpitters -ge $spitterCap) {
        $spitterChance = 0
    }

    if ($roll -lt $bulwarkChance) { return "Bulwark" }
    if ($roll -lt ($bulwarkChance + $spitterChance)) { return "Spitter" }
    if ($Wave -ge 2 -and $roll -lt ($bulwarkChance + $spitterChance + 30)) { return "Skitter" }
    return "Drifter"
}

function New-Enemy {
    param(
        [string] $Kind = "",
        [double] $X = -9999.0,
        [double] $Y = -9999.0
    )

    $arenaWidth = Get-ArenaWidth
    $arenaHeight = Get-ArenaHeight
    if ([string]::IsNullOrWhiteSpace($Kind)) {
        $Kind = Get-RandomEnemyKind $script:G.Wave
    }

    if ($X -lt -9000.0) {
        $spawnCenterX = if ($null -ne $script:G.Core) { $script:G.Core.X } else { $arenaWidth * 0.5 }
        $spawnCenterY = if ($null -ne $script:G.Core) { $script:G.Core.Y } else { $arenaHeight * 0.5 }
        $spawnHalfWidth = [Math]::Min(455.0, $arenaWidth * 0.5)
        $spawnHalfHeight = [Math]::Min(360.0, $arenaHeight * 0.5)
        $spawnLeft = $spawnCenterX - $spawnHalfWidth
        $spawnRight = $spawnCenterX + $spawnHalfWidth
        $spawnTop = $spawnCenterY - $spawnHalfHeight
        $spawnBottom = $spawnCenterY + $spawnHalfHeight
        $edge = Get-Random -Minimum 0 -Maximum 4
        switch ($edge) {
            0 { $X = Get-RandomDouble ($spawnLeft + 25) ($spawnRight - 25); $Y = $spawnTop - 24 }
            1 { $X = $spawnRight + 24; $Y = Get-RandomDouble ($spawnTop + 25) ($spawnBottom - 25) }
            2 { $X = Get-RandomDouble ($spawnLeft + 25) ($spawnRight - 25); $Y = $spawnBottom + 24 }
            default { $X = $spawnLeft - 24; $Y = Get-RandomDouble ($spawnTop + 25) ($spawnBottom - 25) }
        }
    }

    $waveScale = 1.0 + (($script:G.Wave - 1) * 0.105)
    $enemy = [pscustomobject]@{
        Kind = $Kind
        X = [double]$X
        Y = [double]$Y
        VX = 0.0
        VY = 0.0
        HP = 30.0 * $waveScale
        MaxHP = 30.0 * $waveScale
        Speed = 72.0 + ($script:G.Wave * 1.8)
        Radius = 13.0
        Damage = 13.0 + ($script:G.Wave * 0.7)
        Value = 80
        Color = [Drawing.Color]::FromArgb(235, 94, 116)
        HitFlash = 0.0
        AttackClock = Get-RandomDouble 0.0 0.5
        ShootClock = Get-RandomDouble 0.2 1.1
        TelegraphClock = 0.0
        TelegraphAngle = 0.0
        SpawnClock = Get-RandomDouble 2.0 4.0
        Phase = Get-RandomDouble 0.0 6.283
        IsBoss = $false
        Dead = $false
    }

    switch ($Kind) {
        "Skitter" {
            $enemy.HP = 20.0 * $waveScale
            $enemy.MaxHP = $enemy.HP
            $enemy.Speed = 128.0 + ($script:G.Wave * 2.2)
            $enemy.Radius = 9.0
            $enemy.Damage = 9.0 + ($script:G.Wave * 0.55)
            $enemy.Value = 105
            $enemy.Color = [Drawing.Color]::FromArgb(255, 163, 84)
        }
        "Spitter" {
            $enemy.HP = 42.0 * $waveScale
            $enemy.MaxHP = $enemy.HP
            $enemy.Speed = 58.0 + $script:G.Wave
            $enemy.Radius = 15.0
            $enemy.Damage = 6.0 + $script:G.Wave
            $enemy.Value = 145
            $enemy.Color = [Drawing.Color]::FromArgb(195, 112, 255)
            $enemy.ShootClock = Get-RandomDouble 1.2 2.3
        }
        "Bulwark" {
            $enemy.HP = 115.0 * $waveScale
            $enemy.MaxHP = $enemy.HP
            $enemy.Speed = 39.0 + $script:G.Wave
            $enemy.Radius = 22.0
            $enemy.Damage = 24.0 + $script:G.Wave
            $enemy.Value = 240
            $enemy.Color = [Drawing.Color]::FromArgb(103, 174, 220)
        }
        "Eclipser" {
            $enemy.HP = (570.0 + ($script:G.Wave * 152.0))
            $enemy.MaxHP = $enemy.HP
            $enemy.Speed = 30.0 + $script:G.Wave
            $enemy.Radius = 45.0
            $enemy.Damage = 35.0 + ($script:G.Wave * 1.4)
            $enemy.Value = 2500
            $enemy.Color = [Drawing.Color]::FromArgb(255, 72, 148)
            $enemy.IsBoss = $true
            $enemy.ShootClock = 1.0
            $enemy.SpawnClock = 4.0
        }
    }

    [void]$script:G.Enemies.Add($enemy)
    Add-SpawnBurst -X $X -Y $Y -Color $enemy.Color -Count 12
    return $enemy
}

function Add-Particle {
    param(
        [double] $X,
        [double] $Y,
        [double] $VX,
        [double] $VY,
        [double] $Life,
        [double] $Size,
        [Drawing.Color] $Color
    )

    [void]$script:G.Particles.Add([pscustomobject]@{
        X = $X; Y = $Y; VX = $VX; VY = $VY
        Life = $Life; MaxLife = $Life; Size = $Size; Color = $Color
    })
}

function Add-SpawnBurst {
    param(
        [double] $X,
        [double] $Y,
        [Drawing.Color] $Color,
        [int] $Count = 8
    )

    for ($i = 0; $i -lt $Count; $i++) {
        $angle = Get-RandomDouble 0.0 6.283185
        $speed = Get-RandomDouble 35.0 155.0
        Add-Particle $X $Y ([Math]::Cos($angle) * $speed) ([Math]::Sin($angle) * $speed) (Get-RandomDouble 0.28 0.72) (Get-RandomDouble 2.0 5.0) $Color
    }
}

function Add-Floater {
    param(
        [double] $X,
        [double] $Y,
        [string] $Text,
        [Drawing.Color] $Color
    )

    [void]$script:G.Floaters.Add([pscustomobject]@{
        X = $X; Y = $Y; Text = $Text; Color = $Color; Life = 0.8; MaxLife = 0.8
    })
}

function Add-PlayerBullet {
    param([double] $Angle)

    $player = $script:G.Player
    $rankHardlight = Get-UpgradeRank "Hardlight"
    $damage = 18.0 * (1.0 + (0.25 * $rankHardlight))
    $critical = ((Get-RandomDouble) -lt (0.05 + (0.07 * (Get-UpgradeRank "Feedback"))))
    if ($critical) {
        $damage *= 2.0
    }

    [void]$script:G.Bullets.Add([pscustomobject]@{
        X = $player.X + ([Math]::Cos($Angle) * 19.0)
        Y = $player.Y + ([Math]::Sin($Angle) * 19.0)
        VX = [Math]::Cos($Angle) * 760.0
        VY = [Math]::Sin($Angle) * 760.0
        Radius = if ($critical) { 5.0 } else { 3.5 }
        Damage = $damage
        Pierce = Get-UpgradeRank "Pierce"
        Critical = $critical
    })
}

function Fire-PlayerWeapon {
    $player = $script:G.Player
    $shots = 1 + (Get-UpgradeRank "Fork")
    $spread = 0.115
    for ($i = 0; $i -lt $shots; $i++) {
        $offset = ($i - (($shots - 1) / 2.0)) * $spread
        Add-PlayerBullet ($player.Angle + $offset)
    }

    $rank = Get-UpgradeRank "Accelerant"
    $player.FireClock = [Math]::Max(0.065, 0.19 * [Math]::Pow(0.88, $rank))
    for ($i = 0; $i -lt 3; $i++) {
        $angle = $player.Angle + (Get-RandomDouble -0.18 0.18)
        $speed = Get-RandomDouble 40 100
        Add-Particle $player.X $player.Y ([Math]::Cos($angle) * $speed) ([Math]::Sin($angle) * $speed) 0.18 2.2 ([Drawing.Color]::FromArgb(111, 236, 255))
    }
}

function Add-EnemyBullet {
    param(
        [double] $X,
        [double] $Y,
        [double] $Angle,
        [double] $Speed = 250.0,
        [double] $Damage = 12.0,
        [double] $Radius = 6.0
    )

    [void]$script:G.EnemyBullets.Add([pscustomobject]@{
        X = $X; Y = $Y
        VX = [Math]::Cos($Angle) * $Speed
        VY = [Math]::Sin($Angle) * $Speed
        Life = 5.0; Damage = $Damage; Radius = $Radius
    })
}

function Invoke-PlayerDamage {
    param([double] $Amount)

    $player = $script:G.Player
    if ($player.Down -or $player.Invulnerable -gt 0.0) {
        return
    }

    $player.HP -= $Amount
    $player.HitFlash = 0.16
    $player.Invulnerable = 0.35
    $script:G.ScreenShake = [Math]::Max($script:G.ScreenShake, 8.0)
    Add-Floater $player.X ($player.Y - 22) ("-{0}" -f [int][Math]::Ceiling($Amount)) ([Drawing.Color]::FromArgb(255, 102, 118))

    if ($player.HP -le 0.0) {
        $player.HP = 0.0
        $player.Down = $true
        $player.RespawnClock = 3.5
        $coreLoss = [Math]::Min(80.0, $script:G.Core.HP)
        $script:G.Core.HP -= $coreLoss
        $script:G.Message = "DRONE LOST - BEACON RECONSTRUCTING"
        $script:G.MessageClock = 2.4
        Add-SpawnBurst $player.X $player.Y ([Drawing.Color]::FromArgb(102, 231, 255)) 28
    }
}

function Invoke-CoreDamage {
    param([double] $Amount)

    $script:G.Core.HP -= $Amount
    $script:G.Core.HitFlash = 0.2
    $script:G.ScreenShake = [Math]::Max($script:G.ScreenShake, 10.0)
    Add-Floater $script:G.Core.X ($script:G.Core.Y - 52) ("CORE -{0}" -f [int][Math]::Ceiling($Amount)) ([Drawing.Color]::FromArgb(255, 88, 108))
    if ($script:G.Core.HP -le 0.0) {
        $script:G.Core.HP = 0.0
        Complete-Run -Victory $false
    }
}

function Invoke-EnemyDeath {
    param($Enemy)

    if ($Enemy.Dead) { return }
    $Enemy.Dead = $true
    $script:G.Kills++
    $script:G.Combo++
    $script:G.ComboClock = 2.3
    $multiplier = 1.0 + ([Math]::Min(20, $script:G.Combo) * 0.025)
    $gain = [int][Math]::Round($Enemy.Value * $multiplier)
    $script:G.Score += $gain
    $script:G.ScreenShake = [Math]::Max($script:G.ScreenShake, $(if ($Enemy.IsBoss) { 18.0 } else { 3.5 }))
    Add-Floater $Enemy.X ($Enemy.Y - $Enemy.Radius) ("+{0}" -f $gain) ([Drawing.Color]::FromArgb(255, 220, 105))
    Add-SpawnBurst $Enemy.X $Enemy.Y $Enemy.Color $(if ($Enemy.IsBoss) { 55 } else { 13 })

    $dropChance = if ($Enemy.IsBoss) { 1.0 } else { 0.42 }
    if ((Get-RandomDouble) -lt $dropChance) {
        $dropCount = if ($Enemy.IsBoss) { 10 } else { 1 }
        for ($d = 0; $d -lt $dropCount; $d++) {
            [void]$script:G.Pickups.Add([pscustomobject]@{
                X = $Enemy.X + (Get-RandomDouble -18 18)
                Y = $Enemy.Y + (Get-RandomDouble -18 18)
                VX = Get-RandomDouble -45 45
                VY = Get-RandomDouble -45 45
                Life = 14.0
                Value = if ($Enemy.IsBoss) { 10.0 } else { 8.0 }
                Phase = Get-RandomDouble 0 6.283
            })
        }
    }
}

function Invoke-Dash {
    $player = $script:G.Player
    if ($script:G.Mode -ne "Playing" -or $player.Down -or $player.DashClock -gt 0.0) {
        return
    }

    $dx = 0.0; $dy = 0.0
    if ($script:Keys.Contains("A") -or $script:Keys.Contains("Left")) { $dx -= 1.0 }
    if ($script:Keys.Contains("D") -or $script:Keys.Contains("Right")) { $dx += 1.0 }
    if ($script:Keys.Contains("W") -or $script:Keys.Contains("Up")) { $dy -= 1.0 }
    if ($script:Keys.Contains("S") -or $script:Keys.Contains("Down")) { $dy += 1.0 }
    $vector = Get-NormalizedVector $dx $dy
    if ($vector.Length -eq 0.0) {
        $vector = [pscustomobject]@{ X = [Math]::Cos($player.Angle); Y = [Math]::Sin($player.Angle); Length = 1.0 }
    }

    $player.DashX = $vector.X
    $player.DashY = $vector.Y
    $player.DashTime = 0.16
    $player.Invulnerable = 0.3
    $player.DashClock = [Math]::Max(0.65, 2.2 - ((Get-UpgradeRank "Phase") * 0.32))
    $script:G.ScreenShake = 5.0

    $phaseRank = Get-UpgradeRank "Phase"
    if ($phaseRank -gt 0) {
        foreach ($enemy in @($script:G.Enemies)) {
            if ((Get-DistanceSquared $player.X $player.Y $enemy.X $enemy.Y) -lt (115.0 * 115.0)) {
                $enemy.HP -= 20.0 * $phaseRank
                $enemy.HitFlash = 0.12
                if ($enemy.HP -le 0.0) { Invoke-EnemyDeath $enemy }
            }
        }
    }

    Add-SpawnBurst $player.X $player.Y ([Drawing.Color]::FromArgb(91, 231, 255)) 15
}

function Invoke-Pulse {
    $player = $script:G.Player
    if ($script:G.Mode -ne "Playing" -or $player.Down -or $player.Energy -lt 100.0) {
        return
    }

    $player.Energy = 0.0
    $script:G.ScreenShake = 16.0
    $script:G.Message = "NULL PULSE"
    $script:G.MessageClock = 1.0
    foreach ($enemy in @($script:G.Enemies)) {
        $dx = $enemy.X - $player.X
        $dy = $enemy.Y - $player.Y
        $distance = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
        if ($distance -lt 330.0) {
            $factor = 1.0 - ($distance / 440.0)
            $enemy.HP -= (72.0 + ($script:G.Wave * 4.0)) * $factor
            if ($distance -gt 0.1) {
                $enemy.VX += ($dx / $distance) * 320.0 * $factor
                $enemy.VY += ($dy / $distance) * 320.0 * $factor
            }
            $enemy.HitFlash = 0.25
            if ($enemy.HP -le 0.0) { Invoke-EnemyDeath $enemy }
        }
    }

    for ($i = 0; $i -lt 64; $i++) {
        $angle = ($i / 64.0) * 6.283185
        $speed = Get-RandomDouble 240 520
        Add-Particle $player.X $player.Y ([Math]::Cos($angle) * $speed) ([Math]::Sin($angle) * $speed) 0.7 3.5 ([Drawing.Color]::FromArgb(106, 239, 255))
    }
}

function Update-Player {
    param([double] $Delta)

    $player = $script:G.Player
    $arenaWidth = Get-ArenaWidth
    $arenaHeight = Get-ArenaHeight
    $player.FireClock = [Math]::Max(0.0, $player.FireClock - $Delta)
    $player.DashClock = [Math]::Max(0.0, $player.DashClock - $Delta)
    $player.Invulnerable = [Math]::Max(0.0, $player.Invulnerable - $Delta)
    $player.HitFlash = [Math]::Max(0.0, $player.HitFlash - $Delta)

    if ($player.Down) {
        $player.RespawnClock -= $Delta
        if ($player.RespawnClock -le 0.0 -and $script:G.Core.HP -gt 0.0) {
            $player.Down = $false
            $player.HP = $player.MaxHP
            $player.X = $script:G.Core.X
            $player.Y = $script:G.Core.Y + 105.0
            $player.Invulnerable = 2.0
            Add-SpawnBurst $player.X $player.Y ([Drawing.Color]::FromArgb(98, 238, 255)) 24
        }
        return
    }

    $aim = Get-NormalizedVector ($script:MouseX - $player.X) ($script:MouseY - $player.Y)
    if ($aim.Length -gt 0.0) {
        $player.Angle = [Math]::Atan2($aim.Y, $aim.X)
    }

    if ($player.DashTime -gt 0.0) {
        $player.DashTime -= $Delta
        $player.X += $player.DashX * 950.0 * $Delta
        $player.Y += $player.DashY * 950.0 * $Delta
        Add-Particle $player.X $player.Y (Get-RandomDouble -20 20) (Get-RandomDouble -20 20) 0.25 5.0 ([Drawing.Color]::FromArgb(75, 218, 255))
    }
    else {
        $dx = 0.0; $dy = 0.0
        if ($script:Keys.Contains("A") -or $script:Keys.Contains("Left")) { $dx -= 1.0 }
        if ($script:Keys.Contains("D") -or $script:Keys.Contains("Right")) { $dx += 1.0 }
        if ($script:Keys.Contains("W") -or $script:Keys.Contains("Up")) { $dy -= 1.0 }
        if ($script:Keys.Contains("S") -or $script:Keys.Contains("Down")) { $dy += 1.0 }
        $move = Get-NormalizedVector $dx $dy
        $speed = $player.Speed * (1.0 + ((Get-UpgradeRank "Overclock") * 0.1))
        $player.X += $move.X * $speed * $Delta
        $player.Y += $move.Y * $speed * $Delta
    }

    $player.X = Get-ClampedValue $player.X ($player.Radius + 4.0) ($arenaWidth - $player.Radius - 4.0)
    $player.Y = Get-ClampedValue $player.Y ($player.Radius + 4.0) ($arenaHeight - $player.Radius - 4.0)

    if ($script:MouseDown -and $script:MouseX -lt $arenaWidth -and $player.FireClock -le 0.0) {
        Fire-PlayerWeapon
    }

    $repairRank = Get-UpgradeRank "Repair"
    if ($repairRank -gt 0) {
        $player.RegenClock += $Delta
        if ($player.RegenClock -ge 1.0) {
            $player.RegenClock -= 1.0
            $player.HP = [Math]::Min($player.MaxHP, $player.HP + (0.7 * $repairRank))
            $script:G.Core.HP = [Math]::Min($script:G.Core.MaxHP, $script:G.Core.HP + (0.4 * $repairRank))
        }
    }
}

function Update-Projectiles {
    param([double] $Delta)

    $arenaWidth = Get-ArenaWidth
    $arenaHeight = Get-ArenaHeight

    for ($i = $script:G.Bullets.Count - 1; $i -ge 0; $i--) {
        $bullet = $script:G.Bullets[$i]
        $bullet.X += $bullet.VX * $Delta
        $bullet.Y += $bullet.VY * $Delta
        $remove = ($bullet.X -lt -30 -or $bullet.Y -lt -30 -or $bullet.X -gt ($arenaWidth + 30) -or $bullet.Y -gt ($arenaHeight + 30))

        if (-not $remove) {
            foreach ($enemy in @($script:G.Enemies)) {
                if ($enemy.Dead) { continue }
                $radius = $bullet.Radius + $enemy.Radius
                if ((Get-DistanceSquared $bullet.X $bullet.Y $enemy.X $enemy.Y) -le ($radius * $radius)) {
                    $enemy.HP -= $bullet.Damage
                    $enemy.HitFlash = 0.1
                    Add-Floater $enemy.X ($enemy.Y - $enemy.Radius) ([int][Math]::Round($bullet.Damage)).ToString() $(if ($bullet.Critical) { [Drawing.Color]::FromArgb(255, 224, 102) } else { [Drawing.Color]::FromArgb(158, 238, 255) })
                    if ($enemy.HP -le 0.0) { Invoke-EnemyDeath $enemy }
                    if ($bullet.Pierce -gt 0) {
                        $bullet.Pierce--
                        $bullet.Damage *= 0.82
                        $bullet.X += ($bullet.VX / 760.0) * ($enemy.Radius + 7.0)
                        $bullet.Y += ($bullet.VY / 760.0) * ($enemy.Radius + 7.0)
                    }
                    else {
                        $remove = $true
                    }
                    break
                }
            }
        }

        if ($remove) { $script:G.Bullets.RemoveAt($i) }
    }

    for ($i = $script:G.EnemyBullets.Count - 1; $i -ge 0; $i--) {
        $bullet = $script:G.EnemyBullets[$i]
        $bullet.X += $bullet.VX * $Delta
        $bullet.Y += $bullet.VY * $Delta
        $bullet.Life -= $Delta
        $remove = ($bullet.Life -le 0.0 -or $bullet.X -lt -40 -or $bullet.Y -lt -40 -or $bullet.X -gt ($arenaWidth + 40) -or $bullet.Y -gt ($arenaHeight + 40))

        if (-not $remove -and -not $script:G.Player.Down) {
            $radius = $bullet.Radius + $script:G.Player.Radius
            if ((Get-DistanceSquared $bullet.X $bullet.Y $script:G.Player.X $script:G.Player.Y) -le ($radius * $radius)) {
                Invoke-PlayerDamage $bullet.Damage
                $remove = $true
            }
        }
        if (-not $remove) {
            $radius = $bullet.Radius + $script:G.Core.Radius
            if ((Get-DistanceSquared $bullet.X $bullet.Y $script:G.Core.X $script:G.Core.Y) -le ($radius * $radius)) {
                Invoke-CoreDamage ($bullet.Damage * 0.75)
                $remove = $true
            }
        }

        if ($remove) { $script:G.EnemyBullets.RemoveAt($i) }
    }
}

function Update-Enemies {
    param([double] $Delta)

    $player = $script:G.Player
    $core = $script:G.Core
    $staticRank = Get-UpgradeRank "Static"

    for ($i = $script:G.Enemies.Count - 1; $i -ge 0; $i--) {
        $enemy = $script:G.Enemies[$i]
        if ($enemy.Dead) {
            $script:G.Enemies.RemoveAt($i)
            continue
        }

        $enemy.HitFlash = [Math]::Max(0.0, $enemy.HitFlash - $Delta)
        $enemy.AttackClock = [Math]::Max(0.0, $enemy.AttackClock - $Delta)
        $enemy.ShootClock -= $Delta
        $enemy.SpawnClock -= $Delta
        $enemy.Phase += $Delta * 2.0

        $targetPlayer = (-not $player.Down) -and ((Get-DistanceSquared $enemy.X $enemy.Y $player.X $player.Y) -lt (310.0 * 310.0))
        if ($enemy.Kind -eq "Skitter") { $targetPlayer = -not $player.Down }
        $targetX = if ($targetPlayer) { $player.X } else { $core.X }
        $targetY = if ($targetPlayer) { $player.Y } else { $core.Y }
        $toTarget = Get-NormalizedVector ($targetX - $enemy.X) ($targetY - $enemy.Y)
        $speedMultiplier = 1.0

        if ($staticRank -gt 0 -and -not $player.Down) {
            $haloRadius = 95.0 + ($staticRank * 18.0)
            if ((Get-DistanceSquared $enemy.X $enemy.Y $player.X $player.Y) -lt ($haloRadius * $haloRadius)) {
                $enemy.HP -= (4.5 * $staticRank) * $Delta
                $speedMultiplier = [Math]::Max(0.42, 1.0 - ($staticRank * 0.09))
                if ($enemy.HP -le 0.0) {
                    Invoke-EnemyDeath $enemy
                    continue
                }
            }
        }

        if ($enemy.Kind -eq "Spitter") {
            if ($toTarget.Length -gt 285.0) {
                $enemy.VX += $toTarget.X * $enemy.Speed * 3.0 * $Delta
                $enemy.VY += $toTarget.Y * $enemy.Speed * 3.0 * $Delta
            }
            elseif ($toTarget.Length -lt 205.0) {
                $enemy.VX -= $toTarget.X * $enemy.Speed * 2.5 * $Delta
                $enemy.VY -= $toTarget.Y * $enemy.Speed * 2.5 * $Delta
            }
            if ($enemy.TelegraphClock -gt 0.0) {
                $enemy.TelegraphClock -= $Delta
                $speedMultiplier *= 0.55
                if ($enemy.TelegraphClock -le 0.0) {
                    $angle = $enemy.TelegraphAngle
                    $shotSpeed = 205.0 + ($script:G.Wave * 5.0)
                    Add-EnemyBullet $enemy.X $enemy.Y $angle $shotSpeed $enemy.Damage 5.0
                    $enemy.ShootClock = [Math]::Max(1.45, 2.55 - ($script:G.Wave * 0.085))
                }
            }
            elseif ($enemy.ShootClock -le 0.0) {
                $enemy.TelegraphAngle = [Math]::Atan2($targetY - $enemy.Y, $targetX - $enemy.X)
                $enemy.TelegraphClock = 0.72
            }
        }
        elseif ($enemy.IsBoss) {
            $enemy.VX += $toTarget.X * $enemy.Speed * 2.0 * $Delta
            $enemy.VY += $toTarget.Y * $enemy.Speed * 2.0 * $Delta
            if ($enemy.ShootClock -le 0.0) {
                $count = 7 + [int]($script:G.Wave / 2)
                $base = $enemy.Phase
                for ($shot = 0; $shot -lt $count; $shot++) {
                    $bossShotSpeed = 183.0 + ($script:G.Wave * 3.5)
                    $bossShotDamage = 5.0 + ($script:G.Wave * 1.55)
                    Add-EnemyBullet $enemy.X $enemy.Y ($base + (($shot / [double]$count) * 6.283185)) $bossShotSpeed $bossShotDamage 7.0
                }
                $enemy.ShootClock = [Math]::Max(1.7, 2.5 - ($script:G.Wave * 0.0625))
                $script:G.ScreenShake = [Math]::Max($script:G.ScreenShake, 7.0)
            }
            if ($enemy.SpawnClock -le 0.0 -and $script:G.Enemies.Count -lt 55) {
                $reinforcementCount = if ($script:G.Wave -lt 8) { 1 } else { 2 }
                for ($spawn = 0; $spawn -lt $reinforcementCount; $spawn++) {
                    $angle = Get-RandomDouble 0 6.283
                    [void](New-Enemy -Kind $(if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { "Skitter" } else { "Drifter" }) -X ($enemy.X + [Math]::Cos($angle) * 70) -Y ($enemy.Y + [Math]::Sin($angle) * 70))
                }
                $enemy.SpawnClock = [Math]::Max(4.3, 8.0 - ($script:G.Wave * 0.3))
            }
        }
        else {
            $wobble = [Math]::Sin($enemy.Phase) * $(if ($enemy.Kind -eq "Skitter") { 0.55 } else { 0.14 })
            $perpX = -$toTarget.Y
            $perpY = $toTarget.X
            $enemy.VX += (($toTarget.X + ($perpX * $wobble)) * $enemy.Speed * 3.2 * $Delta)
            $enemy.VY += (($toTarget.Y + ($perpY * $wobble)) * $enemy.Speed * 3.2 * $Delta)
        }

        $velocityLength = [Math]::Sqrt(($enemy.VX * $enemy.VX) + ($enemy.VY * $enemy.VY))
        $maximumSpeed = $enemy.Speed * $speedMultiplier
        if ($velocityLength -gt $maximumSpeed -and $velocityLength -gt 0.0) {
            $enemy.VX = ($enemy.VX / $velocityLength) * $maximumSpeed
            $enemy.VY = ($enemy.VY / $velocityLength) * $maximumSpeed
        }
        $enemy.X += $enemy.VX * $Delta
        $enemy.Y += $enemy.VY * $Delta
        $enemy.VX *= [Math]::Pow(0.12, $Delta)
        $enemy.VY *= [Math]::Pow(0.12, $Delta)

        if (-not $player.Down) {
            $touchRadius = $enemy.Radius + $player.Radius
            if ((Get-DistanceSquared $enemy.X $enemy.Y $player.X $player.Y) -lt ($touchRadius * $touchRadius) -and $enemy.AttackClock -le 0.0) {
                Invoke-PlayerDamage $enemy.Damage
                $enemy.AttackClock = 0.8
                $knock = Get-NormalizedVector ($enemy.X - $player.X) ($enemy.Y - $player.Y)
                $enemy.VX += $knock.X * 180.0
                $enemy.VY += $knock.Y * 180.0
            }
        }

        $coreRadius = $enemy.Radius + $core.Radius
        if ((Get-DistanceSquared $enemy.X $enemy.Y $core.X $core.Y) -lt ($coreRadius * $coreRadius) -and $enemy.AttackClock -le 0.0) {
            Invoke-CoreDamage $enemy.Damage
            $enemy.AttackClock = 0.9
            $push = Get-NormalizedVector ($enemy.X - $core.X) ($enemy.Y - $core.Y)
            $enemy.VX += $push.X * 240.0
            $enemy.VY += $push.Y * 240.0
        }
    }
}

function Update-PickupsAndEffects {
    param([double] $Delta)

    $player = $script:G.Player
    $magnetRadius = 110.0 + ((Get-UpgradeRank "Magnet") * 85.0)
    for ($i = $script:G.Pickups.Count - 1; $i -ge 0; $i--) {
        $pickup = $script:G.Pickups[$i]
        $pickup.Life -= $Delta
        $pickup.Phase += $Delta * 4.0
        if (-not $player.Down) {
            $toPlayer = Get-NormalizedVector ($player.X - $pickup.X) ($player.Y - $pickup.Y)
            if ($toPlayer.Length -lt $magnetRadius) {
                $pull = 260.0 + (($magnetRadius - $toPlayer.Length) * 2.0)
                $pickup.VX += $toPlayer.X * $pull * $Delta
                $pickup.VY += $toPlayer.Y * $pull * $Delta
            }
        }
        $pickup.X += $pickup.VX * $Delta
        $pickup.Y += $pickup.VY * $Delta
        $pickup.VX *= [Math]::Pow(0.08, $Delta)
        $pickup.VY *= [Math]::Pow(0.08, $Delta)

        $collected = -not $player.Down -and ((Get-DistanceSquared $pickup.X $pickup.Y $player.X $player.Y) -lt (24.0 * 24.0))
        if ($collected) {
            $player.Energy = [Math]::Min(100.0, $player.Energy + $pickup.Value)
            $script:G.Score += 15
            Add-Particle $pickup.X $pickup.Y 0 -55 0.35 5 ([Drawing.Color]::FromArgb(137, 244, 255))
            $script:G.Pickups.RemoveAt($i)
        }
        elseif ($pickup.Life -le 0.0) {
            $script:G.Pickups.RemoveAt($i)
        }
    }

    for ($i = $script:G.Particles.Count - 1; $i -ge 0; $i--) {
        $particle = $script:G.Particles[$i]
        $particle.X += $particle.VX * $Delta
        $particle.Y += $particle.VY * $Delta
        $particle.VX *= [Math]::Pow(0.16, $Delta)
        $particle.VY *= [Math]::Pow(0.16, $Delta)
        $particle.Life -= $Delta
        if ($particle.Life -le 0.0) { $script:G.Particles.RemoveAt($i) }
    }

    for ($i = $script:G.Floaters.Count - 1; $i -ge 0; $i--) {
        $floater = $script:G.Floaters[$i]
        $floater.Y -= 32.0 * $Delta
        $floater.Life -= $Delta
        if ($floater.Life -le 0.0) { $script:G.Floaters.RemoveAt($i) }
    }
}

function Update-Spawning {
    param([double] $Delta)

    if ($script:G.WaveToSpawn -gt 0) {
        $script:G.SpawnClock -= $Delta
        if ($script:G.SpawnClock -le 0.0) {
            [void](New-Enemy)
            $script:G.WaveToSpawn--
            $script:G.SpawnClock = $script:G.SpawnInterval * (Get-RandomDouble 0.72 1.22)
        }
    }
    elseif ($script:G.BossRequired -and -not $script:G.BossSpawned) {
        $bossGateMaximum = 3 + [int]($script:G.Wave / 4)
        if ($script:G.Enemies.Count -le $bossGateMaximum) {
            if ($script:G.BossArrivalClock -lt 0.0) {
                $script:G.BossArrivalClock = 2.8
                $script:G.Message = "ANOMALY COALESCING - CLEAR THE CENTER"
                $script:G.MessageClock = 2.4
            }
            else {
                $script:G.BossArrivalClock -= $Delta
                if ($script:G.BossArrivalClock -le 0.0) {
                    $script:G.BossSpawned = $true
                    [void](New-Enemy -Kind "Eclipser")
                    $script:G.Message = "ECLIPSER SIGNATURE"
                    $script:G.MessageClock = 2.2
                }
            }
        }
    }
}

function Complete-Wave {
    if ($script:G.Wave -ge $script:G.MaxWaves) {
        Complete-Run -Victory $true
        return
    }

    $repair = $script:G.Core.MaxHP * 0.06
    $script:G.Core.HP = [Math]::Min($script:G.Core.MaxHP, $script:G.Core.HP + $repair)
    $script:G.Player.HP = [Math]::Min($script:G.Player.MaxHP, $script:G.Player.HP + ($script:G.Player.MaxHP * 0.3))
    $script:G.Score += 500 * $script:G.Wave
    Open-UpgradeDraft
}

function Open-UpgradeDraft {
    $available = @(Get-UpgradeCatalog | Where-Object { (Get-UpgradeRank $_.Id) -lt $_.Max })
    if ($available.Count -eq 0) {
        Start-Wave ($script:G.Wave + 1)
        return
    }

    $count = [Math]::Min(3, $available.Count)
    $script:G.UpgradeChoices = @($available | Sort-Object { Get-Random } | Select-Object -First $count)
    $script:G.Mode = "Upgrade"
    $script:G.Message = ""
    $script:MouseDown = $false
}

function Select-Upgrade {
    param([int] $Index)

    if ($script:G.Mode -ne "Upgrade" -or $Index -lt 0 -or $Index -ge $script:G.UpgradeChoices.Count) {
        return
    }

    $upgrade = $script:G.UpgradeChoices[$Index]
    $newRank = (Get-UpgradeRank $upgrade.Id) + 1
    $script:G.UpgradeRanks[$upgrade.Id] = $newRank
    switch ($upgrade.Id) {
        "Hull" {
            $script:G.Player.MaxHP += 25.0
            $script:G.Player.HP = $script:G.Player.MaxHP
        }
        "Beacon" {
            $script:G.Core.MaxHP += 90.0
            $script:G.Core.HP = [Math]::Min($script:G.Core.MaxHP, $script:G.Core.HP + 150.0)
        }
    }
    Write-GameLog ("Upgrade selected: {0}, rank {1}." -f $upgrade.Name, $newRank)
    $script:G.Mode = "Playing"
    Start-Wave ($script:G.Wave + 1)
}

function Complete-Run {
    param([bool] $Victory)

    if ($script:G.Mode -eq "GameOver" -or $script:G.Mode -eq "Victory") { return }
    $script:G.Mode = if ($Victory) { "Victory" } else { "GameOver" }
    $script:G.Profile.BestScore = [Math]::Max([int]$script:G.Profile.BestScore, [int]$script:G.Score)
    $script:G.Profile.BestWave = [Math]::Max([int]$script:G.Profile.BestWave, [int]$script:G.Wave)
    $script:G.Profile.TotalKills = [int]$script:G.Profile.TotalKills + [int]$script:G.Kills
    if ($Victory) { $script:G.Profile.Victories = [int]$script:G.Profile.Victories + 1 }
    Export-Profile
    Write-GameLog ("Run ended. Victory={0}; Score={1}; Wave={2}; Kills={3}." -f $Victory, $script:G.Score, $script:G.Wave, $script:G.Kills)
}

function Update-Game {
    param([double] $Delta)

    if ($null -eq $script:G) { return }

    foreach ($star in $script:G.Stars) {
        $star.Y += $star.Drift * $Delta
        if ($star.Y -gt $script:Canvas.ClientSize.Height) { $star.Y = 0.0 }
    }

    if ($script:G.Mode -ne "Playing") { return }

    $script:G.RunTime += $Delta
    $script:G.Core.Rotation += $Delta * 0.5
    $script:G.Core.HitFlash = [Math]::Max(0.0, $script:G.Core.HitFlash - $Delta)
    $script:G.ScreenShake = [Math]::Max(0.0, $script:G.ScreenShake - (28.0 * $Delta))
    $script:G.MessageClock = [Math]::Max(0.0, $script:G.MessageClock - $Delta)
    if ($script:G.ComboClock -gt 0.0) {
        $script:G.ComboClock -= $Delta
        if ($script:G.ComboClock -le 0.0) { $script:G.Combo = 0 }
    }

    Update-Spawning $Delta
    Update-Player $Delta
    Update-Projectiles $Delta
    Update-Enemies $Delta
    Update-PickupsAndEffects $Delta

    if ($script:G.Mode -eq "Playing" -and $script:G.WaveToSpawn -eq 0 -and (-not $script:G.BossRequired -or $script:G.BossSpawned) -and $script:G.Enemies.Count -eq 0) {
        Complete-Wave
    }
}

function New-Brush {
    param([Drawing.Color] $Color)
    return (New-Object Drawing.SolidBrush($Color))
}

function Draw-Text {
    param(
        [Drawing.Graphics] $Graphics,
        [string] $Text,
        [Drawing.Font] $Font,
        [Drawing.Color] $Color,
        [Drawing.RectangleF] $Rectangle,
        [Drawing.StringFormat] $Format = $null
    )

    $brush = New-Brush $Color
    try {
        if ($null -eq $Format) {
            $Graphics.DrawString($Text, $Font, $brush, $Rectangle)
        }
        else {
            $Graphics.DrawString($Text, $Font, $brush, $Rectangle, $Format)
        }
    }
    finally {
        $brush.Dispose()
    }
}

function Fill-RectangleColor {
    param(
        [Drawing.Graphics] $Graphics,
        [Drawing.Color] $Color,
        [Drawing.RectangleF] $Rectangle
    )

    $brush = New-Brush $Color
    try { $Graphics.FillRectangle($brush, $Rectangle) }
    finally { $brush.Dispose() }
}

function Fill-EllipseColor {
    param(
        [Drawing.Graphics] $Graphics,
        [Drawing.Color] $Color,
        [Drawing.RectangleF] $Rectangle
    )

    $brush = New-Brush $Color
    try { $Graphics.FillEllipse($brush, $Rectangle) }
    finally { $brush.Dispose() }
}

function Draw-Bar {
    param(
        [Drawing.Graphics] $Graphics,
        [double] $X,
        [double] $Y,
        [double] $Width,
        [double] $Height,
        [double] $Value,
        [double] $Maximum,
        [Drawing.Color] $FillColor,
        [Drawing.Color] $BackColor = ([Drawing.Color]::FromArgb(45, 48, 65))
    )

    Fill-RectangleColor $Graphics $BackColor ([Drawing.RectangleF]::new($X, $Y, $Width, $Height))
    $ratio = if ($Maximum -le 0.0) { 0.0 } else { Get-ClampedValue ($Value / $Maximum) 0.0 1.0 }
    if ($ratio -gt 0.0) {
        Fill-RectangleColor $Graphics $FillColor ([Drawing.RectangleF]::new($X, $Y, $Width * $ratio, $Height))
    }
}

function Draw-Background {
    param([Drawing.Graphics] $Graphics)

    $width = $script:Canvas.ClientSize.Width
    $height = $script:Canvas.ClientSize.Height
    $gradient = New-Object Drawing.Drawing2D.LinearGradientBrush(
        [Drawing.Point]::new(0, 0),
        [Drawing.Point]::new($width, $height),
        [Drawing.Color]::FromArgb(7, 10, 23),
        [Drawing.Color]::FromArgb(15, 11, 29)
    )
    try { $Graphics.FillRectangle($gradient, 0, 0, $width, $height) }
    finally { $gradient.Dispose() }

    foreach ($star in $script:G.Stars) {
        $color = [Drawing.Color]::FromArgb([int]$star.Alpha, 157, 199, 235)
        Fill-EllipseColor $Graphics $color ([Drawing.RectangleF]::new($star.X, $star.Y, $star.Size, $star.Size))
    }
}

function Draw-Button {
    param(
        [Drawing.Graphics] $Graphics,
        [Drawing.RectangleF] $Rectangle,
        [string] $Text,
        [bool] $Active = $true
    )

    $hover = $Rectangle.Contains([Drawing.PointF]::new([single]$script:MouseX, [single]$script:MouseY))
    $back = if (-not $Active) { [Drawing.Color]::FromArgb(45, 45, 58) } elseif ($hover) { [Drawing.Color]::FromArgb(45, 119, 143) } else { [Drawing.Color]::FromArgb(25, 69, 91) }
    $line = if ($hover -and $Active) { [Drawing.Color]::FromArgb(125, 241, 255) } else { [Drawing.Color]::FromArgb(65, 151, 174) }
    Fill-RectangleColor $Graphics $back $Rectangle
    $pen = New-Object Drawing.Pen($line, 1.5)
    try { $Graphics.DrawRectangle($pen, $Rectangle.X, $Rectangle.Y, $Rectangle.Width, $Rectangle.Height) }
    finally { $pen.Dispose() }
    Draw-Text $Graphics $Text $script:Assets.FontBodyBold $(if ($Active) { [Drawing.Color]::FromArgb(221, 249, 255) } else { [Drawing.Color]::FromArgb(112, 116, 130) }) $Rectangle $script:Assets.StringCenter
}

function Draw-TitleScreen {
    param([Drawing.Graphics] $Graphics)

    $width = $script:Canvas.ClientSize.Width
    $height = $script:Canvas.ClientSize.Height
    $center = $width * 0.5

    $haloPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(45, 75, 227, 255), 2.0)
    try {
        for ($i = 0; $i -lt 5; $i++) {
            $radius = 92 + ($i * 31) + ([Math]::Sin(($script:Clock.Elapsed.TotalSeconds * 1.5) + $i) * 5)
            $Graphics.DrawEllipse($haloPen, $center - $radius, 150 - $radius, $radius * 2, $radius * 2)
        }
    }
    finally { $haloPen.Dispose() }

    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(24, 180, 217)) ([Drawing.RectangleF]::new($center - 34, 116, 68, 68))
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(180, 101, 239, 255)) ([Drawing.RectangleF]::new($center - 12, 138, 24, 24))
    Draw-Text $Graphics "NULLWAKE" $script:Assets.FontTitle ([Drawing.Color]::FromArgb(222, 249, 255)) ([Drawing.RectangleF]::new(0, 245, $width, 68)) $script:Assets.StringCenter
    Draw-Text $Graphics "THE LAST BEACON IS NOT A PLACE. IT IS A PROMISE." $script:Assets.FontSmallBold ([Drawing.Color]::FromArgb(101, 198, 216)) ([Drawing.RectangleF]::new(0, 311, $width, 28)) $script:Assets.StringCenter
    Draw-Text $Graphics "A mouse-aimed arena defense roguelite in twelve escalating waves." $script:Assets.FontBody ([Drawing.Color]::FromArgb(170, 179, 201)) ([Drawing.RectangleF]::new(0, 350, $width, 30)) $script:Assets.StringCenter

    $buttonWidth = 270.0
    Draw-Button $Graphics ([Drawing.RectangleF]::new($center - ($buttonWidth / 2), 410, $buttonWidth, 52)) "BEGIN DEFENSE SHIFT"
    Draw-Button $Graphics ([Drawing.RectangleF]::new($center - ($buttonWidth / 2), 478, $buttonWidth, 44)) "HOW TO PLAY"

    $record = "BEST SCORE  {0:N0}     BEST WAVE  {1}     VICTORIES  {2}" -f $script:G.Profile.BestScore, $script:G.Profile.BestWave, $script:G.Profile.Victories
    Draw-Text $Graphics $record $script:Assets.FontSmallBold ([Drawing.Color]::FromArgb(120, 151, 177)) ([Drawing.RectangleF]::new(0, $height - 98, $width, 28)) $script:Assets.StringCenter
    Draw-Text $Graphics ("Version {0}  |  vector art rendered live by System.Drawing" -f $script:GameVersion) $script:Assets.FontTiny ([Drawing.Color]::FromArgb(75, 89, 111)) ([Drawing.RectangleF]::new(0, $height - 58, $width, 22)) $script:Assets.StringCenter
}

function Draw-Core {
    param([Drawing.Graphics] $Graphics)

    $core = $script:G.Core
    $pulse = [Math]::Sin($script:G.RunTime * 3.0) * 4.0
    $outer = $core.Radius + 22.0 + $pulse
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(50, 83, 220, 255), 2.0)
    try {
        $Graphics.DrawEllipse($pen, $core.X - $outer, $core.Y - $outer, $outer * 2, $outer * 2)
        $Graphics.DrawArc($pen, $core.X - ($outer + 13), $core.Y - ($outer + 13), ($outer + 13) * 2, ($outer + 13) * 2, [single]($core.Rotation * 90), 115)
    }
    finally { $pen.Dispose() }

    $coreColor = if ($core.HitFlash -gt 0.0) { [Drawing.Color]::White } else { [Drawing.Color]::FromArgb(45, 168, 202) }
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(35, 67, 105)) ([Drawing.RectangleF]::new($core.X - $core.Radius, $core.Y - $core.Radius, $core.Radius * 2, $core.Radius * 2))
    Fill-EllipseColor $Graphics $coreColor ([Drawing.RectangleF]::new($core.X - 23, $core.Y - 23, 46, 46))
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(198, 250, 255)) ([Drawing.RectangleF]::new($core.X - 8, $core.Y - 8, 16, 16))
}

function Draw-Player {
    param([Drawing.Graphics] $Graphics)

    $player = $script:G.Player
    if ($player.Down) { return }
    if ($player.Invulnerable -gt 0.0 -and ([int]($script:G.RunTime * 16) % 2) -eq 0) { return }

    $angle = $player.Angle
    $points = [Drawing.PointF[]]@(
        [Drawing.PointF]::new([single]($player.X + [Math]::Cos($angle) * 21), [single]($player.Y + [Math]::Sin($angle) * 21)),
        [Drawing.PointF]::new([single]($player.X + [Math]::Cos($angle + 2.45) * 15), [single]($player.Y + [Math]::Sin($angle + 2.45) * 15)),
        [Drawing.PointF]::new([single]($player.X + [Math]::Cos($angle + 3.14159) * 7), [single]($player.Y + [Math]::Sin($angle + 3.14159) * 7)),
        [Drawing.PointF]::new([single]($player.X + [Math]::Cos($angle - 2.45) * 15), [single]($player.Y + [Math]::Sin($angle - 2.45) * 15))
    )
    $color = if ($player.HitFlash -gt 0.0) { [Drawing.Color]::White } else { [Drawing.Color]::FromArgb(94, 225, 245) }
    $brush = New-Brush $color
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(205, 251, 255), 1.5)
    try {
        $Graphics.FillPolygon($brush, $points)
        $Graphics.DrawPolygon($pen, $points)
    }
    finally { $brush.Dispose(); $pen.Dispose() }
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(225, 255, 255)) ([Drawing.RectangleF]::new($player.X - 3.5, $player.Y - 3.5, 7, 7))

    $staticRank = Get-UpgradeRank "Static"
    if ($staticRank -gt 0) {
        $radius = 95 + ($staticRank * 18)
        $halo = New-Object Drawing.Pen([Drawing.Color]::FromArgb(35 + ($staticRank * 5), 109, 163, 255), 1.0)
        try { $Graphics.DrawEllipse($halo, $player.X - $radius, $player.Y - $radius, $radius * 2, $radius * 2) }
        finally { $halo.Dispose() }
    }
}

function Draw-Enemy {
    param(
        [Drawing.Graphics] $Graphics,
        $Enemy
    )

    $color = if ($Enemy.HitFlash -gt 0.0) { [Drawing.Color]::White } else { $Enemy.Color }
    $x = $Enemy.X; $y = $Enemy.Y; $r = $Enemy.Radius
    if ($Enemy.Kind -eq "Spitter" -and $Enemy.TelegraphClock -gt 0.0) {
        $charge = Get-ClampedValue (1.0 - ($Enemy.TelegraphClock / 0.72)) 0.0 1.0
        $alpha = [int](55 + ($charge * 160))
        $length = 360.0
        $endX = $x + ([Math]::Cos($Enemy.TelegraphAngle) * $length)
        $endY = $y + ([Math]::Sin($Enemy.TelegraphAngle) * $length)
        $telegraphPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb($alpha, 218, 132, 255), 1.5)
        $telegraphPen.DashStyle = [Drawing.Drawing2D.DashStyle]::Dash
        try {
            $Graphics.DrawLine($telegraphPen, $x, $y, $endX, $endY)
            $ringRadius = $r + 5.0 + ($charge * 7.0)
            $Graphics.DrawEllipse($telegraphPen, $x - $ringRadius, $y - $ringRadius, $ringRadius * 2, $ringRadius * 2)
        }
        finally { $telegraphPen.Dispose() }
    }
    $brush = New-Brush $color
    $outline = New-Object Drawing.Pen([Drawing.Color]::FromArgb(210, $color.R, $color.G, $color.B), 1.5)
    try {
        switch ($Enemy.Kind) {
            "Skitter" {
                $points = [Drawing.PointF[]]@(
                    [Drawing.PointF]::new($x, $y - $r),
                    [Drawing.PointF]::new($x + $r, $y),
                    [Drawing.PointF]::new($x, $y + $r),
                    [Drawing.PointF]::new($x - $r, $y)
                )
                $Graphics.FillPolygon($brush, $points)
                $Graphics.DrawPolygon($outline, $points)
            }
            "Bulwark" {
                $Graphics.FillRectangle($brush, $x - $r, $y - $r, $r * 2, $r * 2)
                $Graphics.DrawRectangle($outline, $x - $r, $y - $r, $r * 2, $r * 2)
                $Graphics.DrawLine($outline, $x - $r, $y, $x + $r, $y)
                $Graphics.DrawLine($outline, $x, $y - $r, $x, $y + $r)
            }
            "Spitter" {
                $Graphics.FillEllipse($brush, $x - $r, $y - $r, $r * 2, $r * 2)
                $Graphics.DrawEllipse($outline, $x - $r, $y - $r, $r * 2, $r * 2)
                Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(33, 13, 45)) ([Drawing.RectangleF]::new($x - 5, $y - 5, 10, 10))
            }
            "Eclipser" {
                $Graphics.FillEllipse($brush, $x - $r, $y - $r, $r * 2, $r * 2)
                $Graphics.DrawEllipse($outline, $x - $r, $y - $r, $r * 2, $r * 2)
                for ($i = 0; $i -lt 8; $i++) {
                    $angle = $Enemy.Phase + (($i / 8.0) * 6.283185)
                    $Graphics.DrawLine($outline, $x + [Math]::Cos($angle) * ($r + 4), $y + [Math]::Sin($angle) * ($r + 4), $x + [Math]::Cos($angle) * ($r + 18), $y + [Math]::Sin($angle) * ($r + 18))
                }
                Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(25, 8, 28)) ([Drawing.RectangleF]::new($x - 16, $y - 16, 32, 32))
            }
            default {
                $points = [Drawing.PointF[]]@(
                    [Drawing.PointF]::new($x, $y - $r),
                    [Drawing.PointF]::new($x + ($r * 0.86), $y + ($r * 0.55)),
                    [Drawing.PointF]::new($x - ($r * 0.86), $y + ($r * 0.55))
                )
                $Graphics.FillPolygon($brush, $points)
                $Graphics.DrawPolygon($outline, $points)
            }
        }
    }
    finally { $brush.Dispose(); $outline.Dispose() }

    if ($Enemy.HP -lt $Enemy.MaxHP -or $Enemy.IsBoss) {
        $barWidth = if ($Enemy.IsBoss) { 90.0 } else { $r * 2.2 }
        Draw-Bar $Graphics ($x - ($barWidth / 2)) ($y - $r - 12) $barWidth 4 $Enemy.HP $Enemy.MaxHP $Enemy.Color ([Drawing.Color]::FromArgb(80, 12, 15, 25))
    }
}

function Draw-World {
    param([Drawing.Graphics] $Graphics)

    $arenaWidth = Get-ArenaWidth
    $arenaHeight = Get-ArenaHeight
    $Graphics.SetClip([Drawing.RectangleF]::new(0, 0, $arenaWidth, $arenaHeight))

    $gridPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(22, 82, 119, 147), 1.0)
    try {
        for ($x = 0; $x -lt $arenaWidth; $x += 64) { $Graphics.DrawLine($gridPen, $x, 0, $x, $arenaHeight) }
        for ($y = 0; $y -lt $arenaHeight; $y += 64) { $Graphics.DrawLine($gridPen, 0, $y, $arenaWidth, $y) }
    }
    finally { $gridPen.Dispose() }

    $shakeX = if ($script:G.ScreenShake -gt 0.0) { Get-RandomDouble (-$script:G.ScreenShake) $script:G.ScreenShake } else { 0.0 }
    $shakeY = if ($script:G.ScreenShake -gt 0.0) { Get-RandomDouble (-$script:G.ScreenShake) $script:G.ScreenShake } else { 0.0 }
    $saved = $Graphics.Save()
    $Graphics.TranslateTransform([single]$shakeX, [single]$shakeY)

    Draw-Core $Graphics

    foreach ($pickup in $script:G.Pickups) {
        $size = 5.0 + ([Math]::Sin($pickup.Phase) * 1.5)
        Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(75, 219, 255)) ([Drawing.RectangleF]::new($pickup.X - $size, $pickup.Y - $size, $size * 2, $size * 2))
        Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(225, 255, 255)) ([Drawing.RectangleF]::new($pickup.X - 2, $pickup.Y - 2, 4, 4))
    }

    foreach ($bullet in $script:G.Bullets) {
        $color = if ($bullet.Critical) { [Drawing.Color]::FromArgb(255, 218, 87) } else { [Drawing.Color]::FromArgb(112, 238, 255) }
        $trail = New-Object Drawing.Pen([Drawing.Color]::FromArgb(100, $color.R, $color.G, $color.B), $bullet.Radius)
        try { $Graphics.DrawLine($trail, $bullet.X, $bullet.Y, $bullet.X - ($bullet.VX * 0.018), $bullet.Y - ($bullet.VY * 0.018)) }
        finally { $trail.Dispose() }
        Fill-EllipseColor $Graphics $color ([Drawing.RectangleF]::new($bullet.X - $bullet.Radius, $bullet.Y - $bullet.Radius, $bullet.Radius * 2, $bullet.Radius * 2))
    }

    foreach ($bullet in $script:G.EnemyBullets) {
        Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(230, 94, 181)) ([Drawing.RectangleF]::new($bullet.X - $bullet.Radius, $bullet.Y - $bullet.Radius, $bullet.Radius * 2, $bullet.Radius * 2))
        Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(255, 194, 222)) ([Drawing.RectangleF]::new($bullet.X - 2, $bullet.Y - 2, 4, 4))
    }

    foreach ($enemy in $script:G.Enemies) { Draw-Enemy $Graphics $enemy }
    Draw-Player $Graphics

    foreach ($particle in $script:G.Particles) {
        $alpha = [int](Get-ClampedValue (($particle.Life / $particle.MaxLife) * 255.0) 0 255)
        $color = [Drawing.Color]::FromArgb($alpha, $particle.Color.R, $particle.Color.G, $particle.Color.B)
        Fill-EllipseColor $Graphics $color ([Drawing.RectangleF]::new($particle.X - ($particle.Size / 2), $particle.Y - ($particle.Size / 2), $particle.Size, $particle.Size))
    }

    foreach ($floater in $script:G.Floaters) {
        $alpha = [int](Get-ClampedValue (($floater.Life / $floater.MaxLife) * 255.0) 0 255)
        $color = [Drawing.Color]::FromArgb($alpha, $floater.Color.R, $floater.Color.G, $floater.Color.B)
        Draw-Text $Graphics $floater.Text $script:Assets.FontSmallBold $color ([Drawing.RectangleF]::new($floater.X - 50, $floater.Y - 10, 100, 24)) $script:Assets.StringCenter
    }

    $Graphics.Restore($saved)
    $Graphics.ResetClip()

    $border = New-Object Drawing.Pen([Drawing.Color]::FromArgb(70, 92, 190, 215), 1.0)
    try { $Graphics.DrawRectangle($border, 1, 1, $arenaWidth - 2, $arenaHeight - 2) }
    finally { $border.Dispose() }
}

function Draw-Hud {
    param([Drawing.Graphics] $Graphics)

    $arenaWidth = Get-ArenaWidth
    $height = $script:Canvas.ClientSize.Height
    $hudWidth = $script:Canvas.ClientSize.Width - $arenaWidth
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(225, 10, 14, 29)) ([Drawing.RectangleF]::new($arenaWidth, 0, $hudWidth, $height))
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(110, 73, 184, 210)) ([Drawing.RectangleF]::new($arenaWidth, 0, 1, $height))

    $x = $arenaWidth + 23
    $w = $hudWidth - 46
    Draw-Text $Graphics "NULLWAKE" $script:Assets.FontHeading ([Drawing.Color]::FromArgb(205, 246, 255)) ([Drawing.RectangleF]::new($x, 20, $w, 38))
    Draw-Text $Graphics ("WAVE {0} / {1}" -f $script:G.Wave, $script:G.MaxWaves) $script:Assets.FontSmallBold ([Drawing.Color]::FromArgb(99, 211, 232)) ([Drawing.RectangleF]::new($x, 68, $w, 22))
    $pendingBoss = if ($script:G.BossRequired -and -not $script:G.BossSpawned) { 1 } else { 0 }
    $remaining = $script:G.WaveToSpawn + $script:G.Enemies.Count + $pendingBoss
    Draw-Text $Graphics ("CONTACTS  {0}" -f $remaining) $script:Assets.FontTiny ([Drawing.Color]::FromArgb(115, 137, 160)) ([Drawing.RectangleF]::new($x, 91, $w, 18))

    Draw-Text $Graphics "BEACON INTEGRITY" $script:Assets.FontTiny ([Drawing.Color]::FromArgb(113, 158, 179)) ([Drawing.RectangleF]::new($x, 126, $w, 18))
    Draw-Bar $Graphics $x 146 $w 12 $script:G.Core.HP $script:G.Core.MaxHP ([Drawing.Color]::FromArgb(69, 196, 222))
    Draw-Text $Graphics ("{0} / {1}" -f [int]$script:G.Core.HP, [int]$script:G.Core.MaxHP) $script:Assets.FontTiny ([Drawing.Color]::FromArgb(166, 214, 224)) ([Drawing.RectangleF]::new($x, 161, $w, 18))

    Draw-Text $Graphics "DRONE HULL" $script:Assets.FontTiny ([Drawing.Color]::FromArgb(153, 128, 140)) ([Drawing.RectangleF]::new($x, 191, $w, 18))
    Draw-Bar $Graphics $x 211 $w 10 $script:G.Player.HP $script:G.Player.MaxHP ([Drawing.Color]::FromArgb(238, 91, 111))
    $hullText = if ($script:G.Player.Down) { "REBUILDING  {0:0.0}s" -f $script:G.Player.RespawnClock } else { "{0} / {1}" -f [int]$script:G.Player.HP, [int]$script:G.Player.MaxHP }
    Draw-Text $Graphics $hullText $script:Assets.FontTiny ([Drawing.Color]::FromArgb(203, 162, 171)) ([Drawing.RectangleF]::new($x, 225, $w, 18))

    Draw-Text $Graphics "NULL CHARGE" $script:Assets.FontTiny ([Drawing.Color]::FromArgb(122, 178, 196)) ([Drawing.RectangleF]::new($x, 254, $w, 18))
    Draw-Bar $Graphics $x 274 $w 10 $script:G.Player.Energy 100 ([Drawing.Color]::FromArgb(132, 102, 240))
    Draw-Text $Graphics $(if ($script:G.Player.Energy -ge 100) { "E  PULSE READY" } else { "{0}%" -f [int]$script:G.Player.Energy }) $script:Assets.FontTiny $(if ($script:G.Player.Energy -ge 100) { [Drawing.Color]::FromArgb(195, 155, 255) } else { [Drawing.Color]::FromArgb(140, 142, 171) }) ([Drawing.RectangleF]::new($x, 288, $w, 18))

    Draw-Text $Graphics "DASH" $script:Assets.FontTiny ([Drawing.Color]::FromArgb(125, 151, 163)) ([Drawing.RectangleF]::new($x, 321, $w, 18))
    $dashMaximum = [Math]::Max(0.65, 2.2 - ((Get-UpgradeRank "Phase") * 0.32))
    Draw-Bar $Graphics $x 341 $w 7 ($dashMaximum - $script:G.Player.DashClock) $dashMaximum ([Drawing.Color]::FromArgb(67, 203, 216))

    Draw-Text $Graphics ("SCORE  {0:N0}" -f $script:G.Score) $script:Assets.FontBodyBold ([Drawing.Color]::FromArgb(255, 218, 106)) ([Drawing.RectangleF]::new($x, 376, $w, 26))
    Draw-Text $Graphics ("KILLS  {0}" -f $script:G.Kills) $script:Assets.FontSmall ([Drawing.Color]::FromArgb(151, 162, 183)) ([Drawing.RectangleF]::new($x, 405, $w, 22))
    if ($script:G.Combo -gt 1) {
        Draw-Text $Graphics ("CHAIN x{0}" -f $script:G.Combo) $script:Assets.FontSmallBold ([Drawing.Color]::FromArgb(255, 132, 169)) ([Drawing.RectangleF]::new($x, 428, $w, 22))
    }

    $upgradeY = 468
    Draw-Text $Graphics "ACTIVE SYSTEMS" $script:Assets.FontTiny ([Drawing.Color]::FromArgb(86, 119, 142)) ([Drawing.RectangleF]::new($x, $upgradeY, $w, 20))
    $shown = 0
    foreach ($upgrade in Get-UpgradeCatalog) {
        $rank = Get-UpgradeRank $upgrade.Id
        if ($rank -gt 0 -and $shown -lt 6) {
            Draw-Text $Graphics ("{0}  {1}/{2}" -f $upgrade.Name, $rank, $upgrade.Max) $script:Assets.FontTiny $upgrade.Color ([Drawing.RectangleF]::new($x, $upgradeY + 23 + ($shown * 19), $w, 19))
            $shown++
        }
    }
    if ($shown -eq 0) {
        Draw-Text $Graphics "No modifications yet" $script:Assets.FontTiny ([Drawing.Color]::FromArgb(71, 79, 99)) ([Drawing.RectangleF]::new($x, $upgradeY + 23, $w, 19))
    }

    Draw-Text $Graphics "WASD MOVE   MOUSE FIRE" $script:Assets.FontTiny ([Drawing.Color]::FromArgb(72, 102, 120)) ([Drawing.RectangleF]::new($x, $height - 76, $w, 18))
    Draw-Text $Graphics "SPACE DASH   E PULSE   P PAUSE" $script:Assets.FontTiny ([Drawing.Color]::FromArgb(72, 102, 120)) ([Drawing.RectangleF]::new($x, $height - 55, $w, 18))
}

function Draw-GameScreen {
    param([Drawing.Graphics] $Graphics)

    Draw-World $Graphics
    Draw-Hud $Graphics

    if ($script:G.MessageClock -gt 0.0 -and -not [string]::IsNullOrWhiteSpace($script:G.Message)) {
        $arenaWidth = Get-ArenaWidth
        $alpha = [int](Get-ClampedValue ($script:G.MessageClock * 155.0) 0 220)
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb([Math]::Min(145, $alpha), 7, 12, 25)) ([Drawing.RectangleF]::new(0, 62, $arenaWidth, 74))
        Draw-Text $Graphics $script:G.Message $script:Assets.FontHeading ([Drawing.Color]::FromArgb($alpha, 200, 244, 255)) ([Drawing.RectangleF]::new(0, 67, $arenaWidth, 62)) $script:Assets.StringCenter
    }
}

function Get-UpgradeCardRectangles {
    $width = $script:Canvas.ClientSize.Width
    $height = $script:Canvas.ClientSize.Height
    $cardWidth = [Math]::Min(290.0, ($width - 150.0) / 3.0)
    $gap = 24.0
    $total = ($cardWidth * $script:G.UpgradeChoices.Count) + ($gap * ($script:G.UpgradeChoices.Count - 1))
    $startX = ($width - $total) / 2.0
    $rectangles = @()
    for ($i = 0; $i -lt $script:G.UpgradeChoices.Count; $i++) {
        $rectangles += [Drawing.RectangleF]::new($startX + (($cardWidth + $gap) * $i), ($height * 0.5) - 105, $cardWidth, 250)
    }
    return $rectangles
}

function Draw-UpgradeScreen {
    param([Drawing.Graphics] $Graphics)

    Draw-GameScreen $Graphics
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(218, 5, 7, 17)) ([Drawing.RectangleF]::new(0, 0, $script:Canvas.ClientSize.Width, $script:Canvas.ClientSize.Height))
    Draw-Text $Graphics "SIGNAL RECOMPILED" $script:Assets.FontHeading ([Drawing.Color]::FromArgb(204, 246, 255)) ([Drawing.RectangleF]::new(0, 62, $script:Canvas.ClientSize.Width, 42)) $script:Assets.StringCenter
    Draw-Text $Graphics "Choose one modification. The next wave begins immediately." $script:Assets.FontBody ([Drawing.Color]::FromArgb(139, 158, 181)) ([Drawing.RectangleF]::new(0, 108, $script:Canvas.ClientSize.Width, 30)) $script:Assets.StringCenter

    $rectangles = @(Get-UpgradeCardRectangles)
    for ($i = 0; $i -lt $script:G.UpgradeChoices.Count; $i++) {
        $upgrade = $script:G.UpgradeChoices[$i]
        $rect = $rectangles[$i]
        $hover = $rect.Contains([Drawing.PointF]::new([single]$script:MouseX, [single]$script:MouseY))
        $back = if ($hover) { [Drawing.Color]::FromArgb(35, 40, 65) } else { [Drawing.Color]::FromArgb(23, 27, 46) }
        Fill-RectangleColor $Graphics $back $rect
        Fill-RectangleColor $Graphics $upgrade.Color ([Drawing.RectangleF]::new($rect.X, $rect.Y, $rect.Width, 5))
        $pen = New-Object Drawing.Pen($(if ($hover) { $upgrade.Color } else { [Drawing.Color]::FromArgb(68, 76, 101) }), $(if ($hover) { 2.0 } else { 1.0 }))
        try { $Graphics.DrawRectangle($pen, $rect.X, $rect.Y, $rect.Width, $rect.Height) }
        finally { $pen.Dispose() }
        Draw-Text $Graphics ("[{0}]" -f ($i + 1)) $script:Assets.FontSmallBold $upgrade.Color ([Drawing.RectangleF]::new($rect.X + 18, $rect.Y + 20, $rect.Width - 36, 24))
        Draw-Text $Graphics $upgrade.Name $script:Assets.FontCard ([Drawing.Color]::FromArgb(228, 238, 249)) ([Drawing.RectangleF]::new($rect.X + 18, $rect.Y + 57, $rect.Width - 36, 58))
        Draw-Text $Graphics $upgrade.Description $script:Assets.FontBody ([Drawing.Color]::FromArgb(154, 166, 189)) ([Drawing.RectangleF]::new($rect.X + 18, $rect.Y + 121, $rect.Width - 36, 68))
        $nextRank = (Get-UpgradeRank $upgrade.Id) + 1
        Draw-Text $Graphics ("RANK {0} / {1}" -f $nextRank, $upgrade.Max) $script:Assets.FontSmallBold $upgrade.Color ([Drawing.RectangleF]::new($rect.X + 18, $rect.Bottom - 43, $rect.Width - 36, 24))
    }
}

function Draw-PauseScreen {
    param([Drawing.Graphics] $Graphics)

    Draw-GameScreen $Graphics
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(205, 4, 6, 15)) ([Drawing.RectangleF]::new(0, 0, $script:Canvas.ClientSize.Width, $script:Canvas.ClientSize.Height))
    Draw-Text $Graphics "SIGNAL SUSPENDED" $script:Assets.FontHeading ([Drawing.Color]::FromArgb(214, 245, 255)) ([Drawing.RectangleF]::new(0, 185, $script:Canvas.ClientSize.Width, 54)) $script:Assets.StringCenter
    Draw-Text $Graphics "Press P or Escape to resume" $script:Assets.FontBody ([Drawing.Color]::FromArgb(142, 161, 186)) ([Drawing.RectangleF]::new(0, 247, $script:Canvas.ClientSize.Width, 30)) $script:Assets.StringCenter
    $center = $script:Canvas.ClientSize.Width * 0.5
    Draw-Button $Graphics ([Drawing.RectangleF]::new($center - 130, 310, 260, 46)) "HOW TO PLAY"
    Draw-Button $Graphics ([Drawing.RectangleF]::new($center - 130, 372, 260, 46)) "ABANDON RUN"
}

function Draw-HelpScreen {
    param([Drawing.Graphics] $Graphics)

    $width = $script:Canvas.ClientSize.Width
    $height = $script:Canvas.ClientSize.Height
    Draw-Text $Graphics "HOW TO HOLD THE LIGHT" $script:Assets.FontHeading ([Drawing.Color]::FromArgb(207, 247, 255)) ([Drawing.RectangleF]::new(0, 55, $width, 45)) $script:Assets.StringCenter
    Draw-Text $Graphics "Protect the central beacon through twelve waves. The drone can be rebuilt; the beacon cannot." $script:Assets.FontBody ([Drawing.Color]::FromArgb(155, 171, 196)) ([Drawing.RectangleF]::new(100, 111, $width - 200, 45)) $script:Assets.StringCenter

    $left = ($width * 0.5) - 370
    $right = ($width * 0.5) + 35
    $top = 185
    Draw-Text $Graphics "FLIGHT" $script:Assets.FontCard ([Drawing.Color]::FromArgb(94, 224, 244)) ([Drawing.RectangleF]::new($left, $top, 320, 30))
    Draw-Text $Graphics "WASD or arrows       Move`nMouse                 Aim`nLeft mouse            Fire`nSpace                 Phase dash`nE                     Null Pulse`nP or Escape           Pause" $script:Assets.FontBody ([Drawing.Color]::FromArgb(187, 198, 216)) ([Drawing.RectangleF]::new($left, $top + 45, 335, 190))

    Draw-Text $Graphics "SURVIVAL" $script:Assets.FontCard ([Drawing.Color]::FromArgb(255, 130, 168)) ([Drawing.RectangleF]::new($right, $top, 320, 30))
    Draw-Text $Graphics "Collect cyan shards to charge the Null Pulse. Draft one modification after each cleared wave. Boss signatures arrive every fourth wave. Chained kills improve score. Regroup around the beacon when pressure becomes too high." $script:Assets.FontBody ([Drawing.Color]::FromArgb(187, 198, 216)) ([Drawing.RectangleF]::new($right, $top + 45, 335, 190))

    Draw-Text $Graphics "Enemy silhouettes are intentional placeholder vector art. Every visual is drawn in real time and can later be replaced with sprites without changing the game model." $script:Assets.FontSmall ([Drawing.Color]::FromArgb(95, 116, 142)) ([Drawing.RectangleF]::new($left, 470, 740, 58)) $script:Assets.StringCenter
    Draw-Button $Graphics ([Drawing.RectangleF]::new(($width / 2) - 120, $height - 105, 240, 46)) "BACK"
}

function Draw-EndScreen {
    param(
        [Drawing.Graphics] $Graphics,
        [bool] $Victory
    )

    $width = $script:Canvas.ClientSize.Width
    $height = $script:Canvas.ClientSize.Height
    $title = if ($Victory) { "THE LIGHT HOLDS" } else { "THE SIGNAL IS DARK" }
    $color = if ($Victory) { [Drawing.Color]::FromArgb(119, 244, 223) } else { [Drawing.Color]::FromArgb(255, 94, 124) }
    Draw-Text $Graphics $title $script:Assets.FontHeading $color ([Drawing.RectangleF]::new(0, 120, $width, 54)) $script:Assets.StringCenter
    Draw-Text $Graphics $(if ($Victory) { "Twelve waves answered. The wake belongs to you." } else { "The beacon failed, but its record remains." }) $script:Assets.FontBody ([Drawing.Color]::FromArgb(156, 171, 195)) ([Drawing.RectangleF]::new(0, 180, $width, 35)) $script:Assets.StringCenter

    $minutes = [int]($script:G.RunTime / 60)
    $seconds = [int]($script:G.RunTime % 60)
    $summary = "SCORE`n{0:N0}`n`nWAVE`n{1} / {2}`n`nKILLS`n{3}`n`nSHIFT TIME`n{4:00}:{5:00}" -f $script:G.Score, $script:G.Wave, $script:G.MaxWaves, $script:G.Kills, $minutes, $seconds
    Draw-Text $Graphics $summary $script:Assets.FontBodyBold ([Drawing.Color]::FromArgb(215, 224, 239)) ([Drawing.RectangleF]::new(($width / 2) - 170, 247, 340, 255)) $script:Assets.StringCenter
    Draw-Button $Graphics ([Drawing.RectangleF]::new(($width / 2) - 135, $height - 145, 270, 48)) "DEFEND AGAIN"
    Draw-Button $Graphics ([Drawing.RectangleF]::new(($width / 2) - 135, $height - 82, 270, 38)) "RETURN TO TITLE"
}

function Paint-Game {
    param([Drawing.Graphics] $Graphics)

    $Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    Draw-Background $Graphics

    switch ($script:G.Mode) {
        "Title" { Draw-TitleScreen $Graphics }
        "Playing" { Draw-GameScreen $Graphics }
        "Upgrade" { Draw-UpgradeScreen $Graphics }
        "Paused" { Draw-PauseScreen $Graphics }
        "Help" { Draw-HelpScreen $Graphics }
        "GameOver" { Draw-EndScreen $Graphics $false }
        "Victory" { Draw-EndScreen $Graphics $true }
    }
}

function Test-PointInRectangle {
    param(
        [double] $X,
        [double] $Y,
        [Drawing.RectangleF] $Rectangle
    )
    return $Rectangle.Contains([Drawing.PointF]::new([single]$X, [single]$Y))
}

function Invoke-Click {
    param(
        [double] $X,
        [double] $Y
    )

    $width = $script:Canvas.ClientSize.Width
    $height = $script:Canvas.ClientSize.Height
    $center = $width * 0.5
    switch ($script:G.Mode) {
        "Title" {
            if (Test-PointInRectangle $X $Y ([Drawing.RectangleF]::new($center - 135, 410, 270, 52))) {
                New-Run
            }
            elseif (Test-PointInRectangle $X $Y ([Drawing.RectangleF]::new($center - 135, 478, 270, 44))) {
                $script:G.HelpFrom = "Title"
                $script:G.Mode = "Help"
            }
        }
        "Upgrade" {
            $rectangles = @(Get-UpgradeCardRectangles)
            for ($i = 0; $i -lt $rectangles.Count; $i++) {
                if (Test-PointInRectangle $X $Y $rectangles[$i]) {
                    Select-Upgrade $i
                    break
                }
            }
        }
        "Paused" {
            if (Test-PointInRectangle $X $Y ([Drawing.RectangleF]::new($center - 130, 310, 260, 46))) {
                $script:G.HelpFrom = "Paused"
                $script:G.Mode = "Help"
            }
            elseif (Test-PointInRectangle $X $Y ([Drawing.RectangleF]::new($center - 130, 372, 260, 46))) {
                $script:G.Mode = "Title"
            }
        }
        "Help" {
            if (Test-PointInRectangle $X $Y ([Drawing.RectangleF]::new(($width / 2) - 120, $height - 105, 240, 46))) {
                $script:G.Mode = $script:G.HelpFrom
            }
        }
        { $_ -eq "GameOver" -or $_ -eq "Victory" } {
            if (Test-PointInRectangle $X $Y ([Drawing.RectangleF]::new(($width / 2) - 135, $height - 145, 270, 48))) {
                New-Run
            }
            elseif (Test-PointInRectangle $X $Y ([Drawing.RectangleF]::new(($width / 2) - 135, $height - 82, 270, 38))) {
                $script:G.Mode = "Title"
            }
        }
    }
}

function Invoke-KeyDown {
    param([System.Windows.Forms.KeyEventArgs] $Event)

    [void]$script:Keys.Add($Event.KeyCode.ToString())
    switch ($Event.KeyCode) {
        ([Windows.Forms.Keys]::Space) { Invoke-Dash; $Event.SuppressKeyPress = $true }
        ([Windows.Forms.Keys]::E) { Invoke-Pulse }
        ([Windows.Forms.Keys]::P) {
            if ($script:G.Mode -eq "Playing") { $script:G.Mode = "Paused" }
            elseif ($script:G.Mode -eq "Paused") { $script:G.Mode = "Playing" }
        }
        ([Windows.Forms.Keys]::Escape) {
            if ($script:G.Mode -eq "Playing") { $script:G.Mode = "Paused" }
            elseif ($script:G.Mode -eq "Paused") { $script:G.Mode = "Playing" }
            elseif ($script:G.Mode -eq "Help") { $script:G.Mode = $script:G.HelpFrom }
        }
        ([Windows.Forms.Keys]::D1) { Select-Upgrade 0 }
        ([Windows.Forms.Keys]::D2) { Select-Upgrade 1 }
        ([Windows.Forms.Keys]::D3) { Select-Upgrade 2 }
        ([Windows.Forms.Keys]::NumPad1) { Select-Upgrade 0 }
        ([Windows.Forms.Keys]::NumPad2) { Select-Upgrade 1 }
        ([Windows.Forms.Keys]::NumPad3) { Select-Upgrade 2 }
        ([Windows.Forms.Keys]::F1) {
            if ($script:G.Mode -eq "Title" -or $script:G.Mode -eq "Paused") {
                $script:G.HelpFrom = $script:G.Mode
                $script:G.Mode = "Help"
            }
        }
    }
}

function Update-BattlefieldLayout {
    if ($null -eq $script:G -or $null -eq $script:Canvas) {
        return
    }

    Initialize-Starfield
    if ($null -eq $script:G.Core) {
        return
    }

    $arenaWidth = Get-ArenaWidth
    $arenaHeight = Get-ArenaHeight
    $newCoreX = $arenaWidth * 0.5
    $newCoreY = $arenaHeight * 0.5
    $offsetX = $newCoreX - $script:G.Core.X
    $offsetY = $newCoreY - $script:G.Core.Y

    if ([Math]::Abs($offsetX) -lt 0.01 -and [Math]::Abs($offsetY) -lt 0.01) {
        return
    }

    if ($null -ne $script:G.Player) {
        $script:G.Player.X += $offsetX
        $script:G.Player.Y += $offsetY
        $script:G.Player.X = Get-ClampedValue $script:G.Player.X ($script:G.Player.Radius + 4.0) ($arenaWidth - $script:G.Player.Radius - 4.0)
        $script:G.Player.Y = Get-ClampedValue $script:G.Player.Y ($script:G.Player.Radius + 4.0) ($arenaHeight - $script:G.Player.Radius - 4.0)
    }

    foreach ($collectionName in @("Enemies", "Bullets", "EnemyBullets", "Particles", "Pickups", "Floaters")) {
        foreach ($item in $script:G[$collectionName]) {
            $item.X += $offsetX
            $item.Y += $offsetY
        }
    }

    $script:G.Core.X = $newCoreX
    $script:G.Core.Y = $newCoreY
}

function Start-Nullwake {
    try { [Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::SystemAware) | Out-Null } catch { }
    [Windows.Forms.Application]::EnableVisualStyles()
    [Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

    $script:Form = New-Object Windows.Forms.Form
    $script:Form.Text = "NULLWAKE - The Last Beacon"
    $script:Form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
    $script:Form.ClientSize = [Drawing.Size]::new(1180, 720)
    $script:Form.MinimumSize = [Drawing.Size]::new(980, 650)
    $script:Form.BackColor = [Drawing.Color]::FromArgb(7, 9, 18)
    $script:Form.KeyPreview = $true

    $script:Canvas = New-Object NullwakeCanvas
    $script:Canvas.Dock = [Windows.Forms.DockStyle]::Fill
    $script:Canvas.BackColor = [Drawing.Color]::FromArgb(7, 9, 18)
    $script:Canvas.Cursor = [Windows.Forms.Cursors]::Cross
    $script:Form.Controls.Add($script:Canvas)

    Initialize-Assets
    New-GameState

    $script:Clock = [Diagnostics.Stopwatch]::StartNew()
    $script:LastTick = $script:Clock.ElapsedTicks
    $script:Timer = New-Object Windows.Forms.Timer
    $script:Timer.Interval = 16

    $script:Timer.Add_Tick({
        $now = $script:Clock.ElapsedTicks
        $delta = ($now - $script:LastTick) / [double][Diagnostics.Stopwatch]::Frequency
        $script:LastTick = $now
        $delta = Get-ClampedValue $delta 0.0 0.04
        try {
            Update-Game $delta
        }
        catch {
            $script:Timer.Stop()
            $script:FatalError = $_.Exception
            Write-GameLog ("Update loop stopped: " + $_.Exception.Message)
            if ($SmokeTest) {
                $script:Form.Close()
            }
            else {
                [Windows.Forms.MessageBox]::Show("The update loop encountered an error.`r`n`r`n$($_.Exception.Message)", "NULLWAKE", [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }
        $script:Canvas.Invalidate()
    })

    $script:Canvas.Add_Paint({
        param($sender, $eventArgs)
        try {
            Paint-Game $eventArgs.Graphics
        }
        catch {
            if (-not $script:PaintFailureReported) {
                $script:PaintFailureReported = $true
                $script:FatalError = $_.Exception
                Write-GameLog ("Paint error: " + $_.Exception.Message)
                if ($SmokeTest) { $script:Form.Close() }
            }
        }
    })
    $script:Canvas.Add_MouseMove({
        param($sender, $eventArgs)
        $script:MouseX = [double]$eventArgs.X
        $script:MouseY = [double]$eventArgs.Y
    })
    $script:Canvas.Add_MouseDown({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) {
            $script:MouseDown = $true
            Invoke-Click $eventArgs.X $eventArgs.Y
            $script:Canvas.Focus()
        }
    })
    $script:Canvas.Add_MouseUp({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) { $script:MouseDown = $false }
    })
    $script:Form.Add_KeyDown({ param($sender, $eventArgs) Invoke-KeyDown $eventArgs })
    $script:Form.Add_KeyUp({ param($sender, $eventArgs) [void]$script:Keys.Remove($eventArgs.KeyCode.ToString()) })
    $script:Form.Add_Deactivate({
        $script:Keys.Clear()
        $script:MouseDown = $false
        if ($script:G.Mode -eq "Playing") { $script:G.Mode = "Paused" }
    })
    $script:Canvas.Add_Resize({
        Update-BattlefieldLayout
    })
    $script:Form.Add_FormClosing({
        $script:Timer.Stop()
        Export-Profile
    })
    $script:Form.Add_FormClosed({
        $script:Clock.Stop()
        $script:Timer.Dispose()
        Remove-Assets
    })
    $script:Form.Add_Shown({
        $script:Canvas.Focus()
        $script:Timer.Start()
        if ($SmokeTest) {
            New-Run
            [void](New-Enemy -Kind "Skitter" -X 120 -Y 120)
            [void](New-Enemy -Kind "Spitter" -X 190 -Y 120)
            [void](New-Enemy -Kind "Bulwark" -X 260 -Y 120)
            [void](New-Enemy -Kind "Eclipser" -X 360 -Y 120)
            $script:SmokePhase = 0
            $smokeTimer = New-Object Windows.Forms.Timer
            $smokeTimer.Interval = 700
            $smokeTimer.Add_Tick({
                $script:SmokePhase++
                if ($script:SmokePhase -eq 1) {
                    $relativePlayerX = $script:G.Player.X - $script:G.Core.X
                    $relativePlayerY = $script:G.Player.Y - $script:G.Core.Y
                    $script:Form.ClientSize = [Drawing.Size]::new(1420, 820)
                    $centerError = [Math]::Abs($script:G.Core.X - ((Get-ArenaWidth) * 0.5)) + [Math]::Abs($script:G.Core.Y - ((Get-ArenaHeight) * 0.5))
                    $geometryError = [Math]::Abs(($script:G.Player.X - $script:G.Core.X) - $relativePlayerX) + [Math]::Abs(($script:G.Player.Y - $script:G.Core.Y) - $relativePlayerY)
                    if ($centerError -gt 0.1 -or $geometryError -gt 0.1) {
                        $script:FatalError = New-Object InvalidOperationException("Battlefield resize geometry test failed.")
                        $this.Stop()
                        $script:Form.Close()
                        return
                    }
                    if (-not [string]::IsNullOrWhiteSpace($CapturePath)) {
                        $bitmap = New-Object Drawing.Bitmap($script:Canvas.ClientSize.Width, $script:Canvas.ClientSize.Height)
                        try {
                            $script:Canvas.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height))
                            $bitmap.Save($CapturePath, [Drawing.Imaging.ImageFormat]::Png)
                        }
                        finally {
                            $bitmap.Dispose()
                        }
                    }
                    Open-UpgradeDraft
                }
                elseif ($script:SmokePhase -eq 2) {
                    Select-Upgrade 0
                }
                elseif ($script:SmokePhase -ge 3) {
                    $this.Stop()
                    $script:Form.Close()
                }
            })
            $smokeTimer.Start()
        }
    })

    Write-GameLog ("Launching version {0}. Console output is optional; all play occurs in WinForms." -f $script:GameVersion)
    [Windows.Forms.Application]::Run($script:Form)
    if ($SmokeTest -and $null -ne $script:FatalError) {
        throw $script:FatalError
    }
}

Start-Nullwake
