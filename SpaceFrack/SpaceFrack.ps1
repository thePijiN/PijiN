#requires -Version 5.1

[CmdletBinding()]
param(
    [switch] $DiagnosticLog,
    [switch] $SmokeTest,
    [switch] $ParityTest,
    [switch] $RenderBenchmark,
    [int] $BenchmarkFrames = 12,
    [string] $CapturePath = "",
    [int] $SoakTestSeconds = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("SpaceFrackCanvas" -as [type])) {
    Add-Type -ReferencedAssemblies "System.Windows.Forms" -WarningAction SilentlyContinue -TypeDefinition @"
using System.Windows.Forms;

public sealed class SpaceFrackCanvas : Panel
{
    public SpaceFrackCanvas()
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

$script:Version = "0.4.18-alpha"
$script:VirtualWidth = 1280.0
$script:VirtualHeight = 720.0
$script:ViewportBottom = 510.0
$script:FrackPlanetRadius = 2850.0
$script:FrackPlanetCenterY = 2925.0
$script:XRFHoldSeconds = 0.85
$script:Form = $null
$script:Canvas = $null
$script:Timer = $null
$script:Clock = $null
$script:LastTick = 0L
$script:G = $null
$script:Assets = @{}
$script:HitTargets = New-Object System.Collections.ArrayList
$script:HitTargetPool = New-Object System.Collections.ArrayList
$script:MouseX = -1000.0
$script:MouseY = -1000.0
$script:Scale = 1.0
$script:OffsetX = 0.0
$script:OffsetY = 0.0
$script:FrameShakeX = 0.0
$script:FrameShakeY = 0.0
$script:FatalError = $null
$script:SmokePhase = 0
$script:IsPainting = $false
$script:Closing = $false
$script:ReducedRenderQuality = $false
$script:RenderSampleCount = 0
$script:RenderAverageMs = 0.0
$script:PlanetVisualCache = @{}
$script:PlanetBitmapCache = @{}
$script:PlanetBitmapCacheOrder = New-Object System.Collections.ArrayList
$script:PlanetBitmapCacheBytes = 0L
$script:PlanetTransitionBitmapCache = @{}
$script:PlanetTransitionCacheOrder = New-Object System.Collections.ArrayList
$script:PlanetTransitionCacheBytes = 0L
$script:ImageAlphaAttributes = @{}
$script:TraderVesselBitmapCache = @{}
$script:TraderVesselBitmapDeviceScale = 0.0
$script:HelmetBitmapCache = @{}
$script:HelmetBitmapDeviceScale = 0.0
$script:FrackPlanetBitmap = $null
$script:FrackPlanetBitmapKey = ""
$script:StarfieldPaths = @()
$script:TwinkleStars = @()
$script:Palette = @{
    Black = [Drawing.Color]::FromArgb(3, 4, 7)
    White = [Drawing.Color]::FromArgb(224, 232, 236)
    Gray = [Drawing.Color]::FromArgb(130, 142, 150)
    DarkGray = [Drawing.Color]::FromArgb(62, 70, 77)
    Red = [Drawing.Color]::FromArgb(210, 48, 49)
    DarkRed = [Drawing.Color]::FromArgb(117, 28, 30)
    Yellow = [Drawing.Color]::FromArgb(238, 192, 76)
    DarkYellow = [Drawing.Color]::FromArgb(148, 104, 39)
    Green = [Drawing.Color]::FromArgb(72, 204, 126)
    DarkGreen = [Drawing.Color]::FromArgb(35, 106, 70)
    Cyan = [Drawing.Color]::FromArgb(83, 218, 235)
    DarkCyan = [Drawing.Color]::FromArgb(38, 119, 133)
    Blue = [Drawing.Color]::FromArgb(73, 125, 222)
    DarkBlue = [Drawing.Color]::FromArgb(36, 59, 114)
    Magenta = [Drawing.Color]::FromArgb(205, 91, 213)
    DarkMagenta = [Drawing.Color]::FromArgb(104, 46, 113)
}
$script:RaritySortOrder = @{Upgrade=0;Consumable=1;SuperCommon=2;Common=3;Uncommon=4;Rare=5;SuperRare=6;UltraRare=7;Artifact=8;Oddity=9}

function Write-GameLog {
    param([string] $Message,[switch] $Critical)
    $displayLine="[SPACEFRACK] " + $Message
    Write-Verbose $displayLine
    if($DiagnosticLog -or $Critical){
        try{
            $appData=$env:APPDATA
            if([string]::IsNullOrWhiteSpace($appData)){$appData=[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)}
            if([string]::IsNullOrWhiteSpace($appData)){$appData=$env:TEMP}
            $logDirectory=Join-Path $appData "spacefrack"
            if(-not (Test-Path -LiteralPath $logDirectory)){New-Item -ItemType Directory -Path $logDirectory -Force|Out-Null}
            $level=if($Critical){"ERROR"}else{"INFO"}
            $logLine="{0} [{1}] {2}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff"),$level,$displayLine
            Add-Content -LiteralPath (Join-Path $logDirectory "spacefrack-debug.log") -Value $logLine -Encoding UTF8
        }catch{}
    }
}

function Assert-GameState {
    param([bool] $Condition,[string] $Message)
    if(-not $Condition){throw ("Parity assertion failed: " + $Message)}
    Write-GameLog ("PASS: " + $Message)
}

function New-ArrayList {
    return ,(New-Object System.Collections.ArrayList)
}

function Get-ClampedValue {
    param([double] $Value, [double] $Minimum, [double] $Maximum)
    return [Math]::Max($Minimum, [Math]::Min($Maximum, $Value))
}

function Get-RandomDouble {
    param([double] $Minimum = 0.0, [double] $Maximum = 1.0)
    return $Minimum + ((Get-Random -Minimum 0 -Maximum 1000000) / 1000000.0) * ($Maximum - $Minimum)
}

function Get-Lerp {
    param([double] $From, [double] $To, [double] $Amount)
    return $From + (($To - $From) * (Get-ClampedValue $Amount 0.0 1.0))
}

function Get-Ease {
    param([double] $Value)
    $v = Get-ClampedValue $Value 0.0 1.0
    return $v * $v * (3.0 - (2.0 * $v))
}

function Register-RenderPerformance {
    param([double] $Milliseconds)
    if($RenderBenchmark -or $SmokeTest -or $ParityTest -or $script:ReducedRenderQuality){return}
    $script:RenderSampleCount++
    if($script:RenderSampleCount -le 2){return}
    if($script:RenderAverageMs -le 0){$script:RenderAverageMs=$Milliseconds}else{$script:RenderAverageMs=($script:RenderAverageMs*0.84)+($Milliseconds*0.16)}
    $engage=($script:RenderSampleCount -ge 5 -and $script:RenderAverageMs -gt 75.0) -or ($script:RenderSampleCount -ge 14 -and $script:RenderAverageMs -gt 34.0)
    if($engage){
        $script:ReducedRenderQuality=$true
        if($null -ne $script:Timer){$script:Timer.Interval=33}
        Write-GameLog ("Adaptive renderer engaged at {0:N1} ms/frame." -f $script:RenderAverageMs)
    }
}

function Get-Color {
    param([string] $Name)
    if ($script:Palette.ContainsKey($Name)) { return $script:Palette[$Name] }
    return $script:Palette.White
}

function New-Brush {
    param([Drawing.Color] $Color)
    return (New-Object Drawing.SolidBrush($Color))
}

function Initialize-Assets {
    $script:Assets = @{
        FontTiny = New-Object Drawing.Font("Segoe UI", 8.0, [Drawing.FontStyle]::Regular)
        FontSmall = New-Object Drawing.Font("Segoe UI", 9.5, [Drawing.FontStyle]::Regular)
        FontSmallBold = New-Object Drawing.Font("Segoe UI Semibold", 9.5, [Drawing.FontStyle]::Bold)
        FontBody = New-Object Drawing.Font("Segoe UI", 11.0, [Drawing.FontStyle]::Regular)
        FontBodyBold = New-Object Drawing.Font("Segoe UI Semibold", 11.0, [Drawing.FontStyle]::Bold)
        FontHeading = New-Object Drawing.Font("Segoe UI Semibold", 20.0, [Drawing.FontStyle]::Bold)
        FontTitle = New-Object Drawing.Font("Segoe UI Semibold", 42.0, [Drawing.FontStyle]::Bold)
        FontMono = New-Object Drawing.Font("Consolas", 9.0, [Drawing.FontStyle]::Regular)
        FrameBrush = New-Object Drawing.SolidBrush([Drawing.Color]::Black)
        FramePen = New-Object Drawing.Pen([Drawing.Color]::White, 1.0)
        Center = New-Object Drawing.StringFormat
        NearCenter = New-Object Drawing.StringFormat
        Right = New-Object Drawing.StringFormat
    }
    $script:Assets.Center.Alignment = [Drawing.StringAlignment]::Center
    $script:Assets.Center.LineAlignment = [Drawing.StringAlignment]::Center
    $script:Assets.NearCenter.Alignment = [Drawing.StringAlignment]::Near
    $script:Assets.NearCenter.LineAlignment = [Drawing.StringAlignment]::Center
    $script:Assets.Right.Alignment = [Drawing.StringAlignment]::Far
}

function Remove-Assets {
    foreach($bitmap in @($script:PlanetBitmapCache.Values)){if($bitmap -is [IDisposable]){$bitmap.Dispose()}}
    $script:PlanetBitmapCache=@{};$script:PlanetBitmapCacheOrder.Clear();$script:PlanetBitmapCacheBytes=0L
    foreach($bitmap in @($script:PlanetTransitionBitmapCache.Values)){if($bitmap -is [IDisposable]){$bitmap.Dispose()}}
    $script:PlanetTransitionBitmapCache=@{};$script:PlanetTransitionCacheOrder.Clear();$script:PlanetTransitionCacheBytes=0L
    foreach($attributes in @($script:ImageAlphaAttributes.Values)){if($attributes -is [IDisposable]){$attributes.Dispose()}}
    $script:ImageAlphaAttributes=@{}
    foreach($bitmap in @($script:TraderVesselBitmapCache.Values)){if($bitmap -is [IDisposable]){$bitmap.Dispose()}}
    $script:TraderVesselBitmapCache=@{};$script:TraderVesselBitmapDeviceScale=0.0
    foreach($bitmap in @($script:HelmetBitmapCache.Values)){if($bitmap -is [IDisposable]){$bitmap.Dispose()}}
    $script:HelmetBitmapCache=@{};$script:HelmetBitmapDeviceScale=0.0
    if($script:FrackPlanetBitmap -is [IDisposable]){$script:FrackPlanetBitmap.Dispose()}
    $script:FrackPlanetBitmap=$null;$script:FrackPlanetBitmapKey=""
    foreach($path in @($script:StarfieldPaths)){if($path -is [IDisposable]){$path.Dispose()}}
    $script:StarfieldPaths=@();$script:TwinkleStars=@()
    foreach ($asset in @($script:Assets.Values)) {
        if ($asset -is [IDisposable]) { $asset.Dispose() }
    }
    $script:Assets = @{}
}

function Add-HitTarget {
    param(
        [string] $Action,
        [Drawing.RectangleF] $Rectangle,
        $Data = $null,
        [bool] $Enabled = $true,
        [double] $HoldSeconds = 0.0
    )
    $index=$script:HitTargets.Count
    if($index -ge $script:HitTargetPool.Count){
        [void]$script:HitTargetPool.Add([pscustomobject]@{Action="";Rectangle=[Drawing.RectangleF]::Empty;Data=$null;Enabled=$false;HoldSeconds=0.0})
    }
    $target=$script:HitTargetPool[$index]
    $target.Action=$Action;$target.Rectangle=$Rectangle;$target.Data=$Data;$target.Enabled=$Enabled;$target.HoldSeconds=[Math]::Max(0.0,$HoldSeconds)
    [void]$script:HitTargets.Add($target)
}

function Test-Hover {
    param([Drawing.RectangleF] $Rectangle)
    return $Rectangle.Contains([Drawing.PointF]::new([single]$script:MouseX, [single]$script:MouseY))
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
    $brush=$script:Assets.FrameBrush
    $brush.Color=$Color
    if ($null -eq $Format) { $Graphics.DrawString($Text, $Font, $brush, $Rectangle) }
    else { $Graphics.DrawString($Text, $Font, $brush, $Rectangle, $Format) }
}

function Fill-RectangleColor {
    param([Drawing.Graphics] $Graphics, [Drawing.Color] $Color, [Drawing.RectangleF] $Rectangle)
    $brush=$script:Assets.FrameBrush
    $brush.Color=$Color
    $Graphics.FillRectangle($brush,$Rectangle)
}

function Fill-EllipseColor {
    param([Drawing.Graphics] $Graphics, [Drawing.Color] $Color, [Drawing.RectangleF] $Rectangle)
    $brush=$script:Assets.FrameBrush
    $brush.Color=$Color
    $Graphics.FillEllipse($brush,$Rectangle)
}

function Fill-PolygonColor {
    param([Drawing.Graphics] $Graphics,[Drawing.Color] $Color,[Drawing.PointF[]] $Points)
    $brush=$script:Assets.FrameBrush
    $brush.Color=$Color
    $Graphics.FillPolygon($brush,$Points)
}

function Fill-ClosedCurveColor {
    param([Drawing.Graphics] $Graphics,[Drawing.Color] $Color,[Drawing.PointF[]] $Points,[single] $Tension=0.16)
    $brush=$script:Assets.FrameBrush
    $brush.Color=$Color
    $Graphics.FillClosedCurve($brush,$Points,[Drawing.Drawing2D.FillMode]::Winding,$Tension)
}

function Fill-PathColor {
    param([Drawing.Graphics] $Graphics,[Drawing.Color] $Color,[Drawing.Drawing2D.GraphicsPath] $Path)
    $brush=$script:Assets.FrameBrush
    $brush.Color=$Color
    $Graphics.FillPath($brush,$Path)
}

function Draw-Bar {
    param(
        [Drawing.Graphics] $Graphics,
        [double] $X, [double] $Y, [double] $Width, [double] $Height,
        [double] $Value, [double] $Maximum,
        [Drawing.Color] $Color
    )
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(180, 13, 20, 24)) ([Drawing.RectangleF]::new($X, $Y, $Width, $Height))
    $ratio = if ($Maximum -le 0) { 0.0 } else { Get-ClampedValue ($Value / $Maximum) 0.0 1.0 }
    if ($ratio -gt 0) {
        Fill-RectangleColor $Graphics $Color ([Drawing.RectangleF]::new($X, $Y, $Width * $ratio, $Height))
    }
}

function Draw-Button {
    param(
        [Drawing.Graphics] $Graphics,
        [Drawing.RectangleF] $Rectangle,
        [string] $Text,
        [string] $Action,
        $Data = $null,
        [bool] $Enabled = $true,
        [Drawing.Color] $Accent = ([Drawing.Color]::FromArgb(74, 190, 202)),
        [double] $HoldSeconds = 0.0
    )
    $hover = $Enabled -and (Test-Hover $Rectangle)
    $back = if (-not $Enabled) { [Drawing.Color]::FromArgb(125, 18, 23, 26) } elseif ($hover) { [Drawing.Color]::FromArgb(235, 34, 72, 76) } else { [Drawing.Color]::FromArgb(220, 21, 39, 43) }
    $line = if ($hover) { $Accent } elseif ($Enabled) { [Drawing.Color]::FromArgb(125, $Accent.R, $Accent.G, $Accent.B) } else { [Drawing.Color]::FromArgb(45, 68, 71, 74) }
    Fill-RectangleColor $Graphics $back $Rectangle
    if($Enabled -and $HoldSeconds -gt 0.0 -and $null -ne $script:G.HoldButton){
        $hold=$script:G.HoldButton
        if($hold.Action -eq $Action -and [string]$hold.Data -eq [string]$Data){
            $progress=Get-ClampedValue ([double]$hold.Elapsed/[Math]::Max(0.001,[double]$hold.Duration)) 0.0 1.0
            if($progress -gt 0.0){
                $fill=[Drawing.RectangleF]::new($Rectangle.X,$Rectangle.Y,$Rectangle.Width*$progress,$Rectangle.Height)
                Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(92,$Accent.R,$Accent.G,$Accent.B)) $fill
            }
        }
    }
    $pen=$script:Assets.FramePen
    $pen.Color=$line;$pen.Width=$(if($hover){2.0}else{1.0});$pen.DashStyle=[Drawing.Drawing2D.DashStyle]::Solid;$pen.StartCap=[Drawing.Drawing2D.LineCap]::Flat;$pen.EndCap=[Drawing.Drawing2D.LineCap]::Flat
    $Graphics.DrawRectangle($pen,$Rectangle.X,$Rectangle.Y,$Rectangle.Width,$Rectangle.Height)
    Draw-Text $Graphics $Text $script:Assets.FontSmallBold $(if ($Enabled) { (Get-Color White) } else { (Get-Color DarkGray) }) $Rectangle $script:Assets.Center
    Add-HitTarget $Action $Rectangle $Data $Enabled $HoldSeconds
}

function Draw-FrackPlanetButton {
    param([Drawing.Graphics] $Graphics,[Drawing.RectangleF] $Rectangle,$Planet,[bool] $Enabled)
    Draw-Button $Graphics $Rectangle "" "StartFrack" $null $Enabled (Get-Color Yellow)
    $prefix="FRACK ";$name=$Planet.Name.ToUpper();$font=$script:Assets.FontSmallBold
    $prefixWidth=$Graphics.MeasureString($prefix,$font).Width;$nameWidth=$Graphics.MeasureString($name,$font).Width;$total=$prefixWidth+$nameWidth;$start=$Rectangle.X+(($Rectangle.Width-$total)/2.0)
    $prefixColor=if($Enabled){Get-Color White}else{Get-Color DarkGray};$nameColor=if($Enabled){Get-Color $Planet.PlanetColor}else{Get-Color DarkGray}
    Draw-Text $Graphics $prefix $font $prefixColor ([Drawing.RectangleF]::new($start,$Rectangle.Y,$prefixWidth+2,$Rectangle.Height)) $script:Assets.NearCenter
    Draw-Text $Graphics $name $font $nameColor ([Drawing.RectangleF]::new($start+$prefixWidth,$Rectangle.Y,$nameWidth+3,$Rectangle.Height)) $script:Assets.NearCenter
}

function New-ResourceMaster {
    return @{
        "Silicates" = @{ Value = 3; Weight = 0.5; Rarity = "SuperCommon"; Description = "Raw silicate minerals." }
        "Carbon" = @{ Value = 4; Weight = 1.0; Rarity = "SuperCommon"; Description = "Compressed carbon mass." }
        "Water" = @{ Value = 5; Weight = 1.0; Rarity = "SuperCommon"; Description = "Frozen H2O blocks." }
        "Oxygen" = @{ Value = 6; Weight = 1.0; Rarity = "SuperCommon"; Description = "Oxygen canisters." }
        "Iron" = @{ Value = 8; Weight = 1.0; Rarity = "SuperCommon"; Description = "Raw iron ore." }
        "Hydrogen" = @{ Value = 12; Weight = 1.0; Rarity = "Common"; Description = "Hydrogen gas cylinders." }
        "Nitrogen" = @{ Value = 13; Weight = 1.0; Rarity = "Common"; Description = "Compressed nitrogen." }
        "Magnesium" = @{ Value = 14; Weight = 1.0; Rarity = "Common"; Description = "Raw magnesium ore." }
        "Calcium" = @{ Value = 16; Weight = 1.0; Rarity = "Common"; Description = "Raw calcium minerals." }
        "Aluminum" = @{ Value = 18; Weight = 1.0; Rarity = "Common"; Description = "Raw aluminum ore." }
        "Sulfur" = @{ Value = 20; Weight = 0.5; Rarity = "Common"; Description = "Crystalline sulfur." }
        "ScrapMetal" = @{ Value = 22; Weight = 2.0; Rarity = "Common"; Description = "Salvaged hull plating." }
        "Zinc" = @{ Value = 24; Weight = 1.0; Rarity = "Common"; Description = "Raw zinc ore." }
        "Tin" = @{ Value = 28; Weight = 1.0; Rarity = "Common"; Description = "Raw tin ore." }
        "Copper" = @{ Value = 30; Weight = 1.0; Rarity = "Common"; Description = "Raw copper ore." }
        "Silicon" = @{ Value = 35; Weight = 1.0; Rarity = "Uncommon"; Description = "Refined silicon-bearing ore." }
        "Nickel" = @{ Value = 40; Weight = 1.0; Rarity = "Uncommon"; Description = "Raw nickel ore." }
        "Biomass" = @{ Value = 42; Weight = 1.0; Rarity = "Uncommon"; Description = "Organic matter samples." }
        "Boron" = @{ Value = 45; Weight = 1.0; Rarity = "Uncommon"; Description = "Boron-rich samples." }
        "Argon" = @{ Value = 50; Weight = 1.0; Rarity = "Uncommon"; Description = "Argon cylinders." }
        "Neon" = @{ Value = 60; Weight = 1.0; Rarity = "Uncommon"; Description = "Neon cylinders." }
        "Helium" = @{ Value = 75; Weight = 1.0; Rarity = "Rare"; Description = "Helium cylinders." }
        "Silver" = @{ Value = 100; Weight = 1.0; Rarity = "Rare"; Description = "Raw silver ore." }
        "Uranium" = @{ Value = 150; Weight = 1.0; Rarity = "Rare"; Description = "Raw uranium ore." }
        "Warship Alloy" = @{ Value = 160; Weight = 2.0; Rarity = "Rare"; Description = "Recovered military alloy." }
        "Radium" = @{ Value = 175; Weight = 1.0; Rarity = "Rare"; Description = "Radioactive material." }
        "Deuterium" = @{ Value = 180; Weight = 1.0; Rarity = "Rare"; Description = "Heavy hydrogen fuel stock." }
        "Tungsten" = @{ Value = 220; Weight = 2.0; Rarity = "Rare"; Description = "Dense tungsten ore." }
        "Platinum" = @{ Value = 220; Weight = 1.0; Rarity = "Rare"; Description = "Raw platinum ore." }
        "Gold" = @{ Value = 250; Weight = 1.0; Rarity = "Rare"; Description = "Raw gold ore." }
        "MetallicHydrogen" = @{ Value = 260; Weight = 2.5; Rarity = "SuperRare"; Description = "Pressurized fuel precursor." }
        "Fossils" = @{ Value = 300; Weight = 1.5; Rarity = "SuperRare"; Description = "Unknown fossilized life." }
        "Plutonium" = @{ Value = 350; Weight = 1.0; Rarity = "SuperRare"; Description = "Weapons-grade bad idea." }
        "Neptunium" = @{ Value = 400; Weight = 1.0; Rarity = "SuperRare"; Description = "Rare transuranic material." }
        "Mythril" = @{ Value = 200; Weight = 1.5; Rarity = "SuperRare"; Description = "A remarkably resilient Typhon ore." }
        "Helium-3" = @{ Value = 475; Weight = 1.0; Rarity = "SuperRare"; Description = "Rare reactor-grade helium isotope." }
        "Cryophane" = @{ Value = 425; Weight = 1.5; Rarity = "SuperRare"; Description = "Cold-stable crystalline volatile." }
        "Ordnance Core" = @{ Value = 360; Weight = 1.5; Rarity = "SuperRare"; Description = "Recovered live munitions core." }
        "Promethium" = @{ Value = 500; Weight = 1.0; Rarity = "UltraRare"; Description = "Unstable promethium." }
        "Tantalum Hafnium Carbide" = @{ Value = 525; Weight = 1.0; Rarity = "UltraRare"; Description = "An extreme-temperature ceramic." }
        "Pyrestone" = @{ Value = 650; Weight = 1.0; Rarity = "UltraRare"; Description = "Star-baked refractory crystal." }
        "Iridium" = @{ Value = 750; Weight = 1.0; Rarity = "UltraRare"; Description = "Extremely rare iridium." }
        "Republic Flight Recorder" = @{ Value = 1500; Weight = 1.0; Rarity = "Artifact"; Description = "Encrypted Republic combat recorder." }
        "Fuel Cell (Small)" = @{ Value = 150; Weight = 0.5; Rarity = "Consumable"; Description = "Restores 50 fuel."; Effect = "Fuel"; EffectValue = 50.0 }
        "Fuel Cell (Medium)" = @{ Value = 300; Weight = 1.0; Rarity = "Consumable"; Description = "Restores 100 fuel."; Effect = "Fuel"; EffectValue = 100.0 }
        "Fuel Cell (Large)" = @{ Value = 500; Weight = 2.0; Rarity = "Consumable"; Description = "Restores 200 fuel."; Effect = "Fuel"; EffectValue = 200.0 }
        "Bastion Fuel Cell" = @{ Value = 1000; Weight = 3.0; Rarity = "Consumable"; Description = "Restores 400 fuel."; Effect = "Fuel"; EffectValue = 400.0 }
        "Shield Cell (Small)" = @{ Value = 100; Weight = 0.5; Rarity = "Consumable"; Description = "Restores 50 hull."; Effect = "HP"; EffectValue = 50.0 }
        "Shield Cell (Medium)" = @{ Value = 200; Weight = 1.0; Rarity = "Consumable"; Description = "Restores 100 hull."; Effect = "HP"; EffectValue = 100.0 }
        "Shield Cell (Large)" = @{ Value = 375; Weight = 2.0; Rarity = "Consumable"; Description = "Restores 200 hull."; Effect = "HP"; EffectValue = 200.0 }
        "Bastion Shield Cell" = @{ Value = 750; Weight = 2.0; Rarity = "Consumable"; Description = "Restores 500 hull."; Effect = "HP"; EffectValue = 500.0 }
        "Cargo Baffles" = @{ Value = 600; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 50 kg cargo capacity."; Effect = "MaxWeight"; EffectValue = 50.0 }
        "Premium Cargo Baffles" = @{ Value = 1200; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 100 kg cargo capacity."; Effect = "MaxWeight"; EffectValue = 100.0 }
        "Auxiliary Fuel Tank" = @{ Value = 750; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 50 fuel capacity."; Effect = "MaxFuel"; EffectValue = 50.0 }
        "Deluxe Auxiliary Fuel Tank" = @{ Value = 1400; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 100 fuel capacity."; Effect = "MaxFuel"; EffectValue = 100.0 }
        "U.C.E. Shield Generator MK I" = @{ Value = 1000; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 25 hull capacity."; Effect = "MaxHP"; EffectValue = 25.0 }
        "U.C.E. Shield Generator MK II" = @{ Value = 2000; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 50 hull capacity."; Effect = "MaxHP"; EffectValue = 50.0 }
        "U.C.E. Shield Generator MK III" = @{ Value = 3000; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 75 hull capacity."; Effect = "MaxHP"; EffectValue = 75.0 }
        "FFF Shield Generator" = @{ Value = 4000; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 100 hull capacity."; Effect = "MaxHP"; EffectValue = 100.0 }
        "Bastion Shield Generator" = @{ Value = 8000; Weight = 0.0; Rarity = "Upgrade"; Description = "Adds 200 hull capacity."; Effect = "MaxHP"; EffectValue = 200.0 }
        "Gas Giant Surveyor" = @{ Value = 3000; Weight = 1.0; Rarity = "Upgrade"; Description = "Halves Gas Giant hazards per stack."; Effect = "frackGas"; EffectValue = 1; HazardReduction = @{"Gas Giant"=0.50} }
        "Ice Giant Surveyor" = @{ Value = 4000; Weight = 1.0; Rarity = "Upgrade"; Description = "Halves Ice Giant hazards per stack."; Effect = "frackIce"; EffectValue = 1; HazardReduction = @{"Ice Giant"=0.50} }
        "Terrain Hardening Kit" = @{ Value = 2500; Weight = 1.0; Rarity = "Upgrade"; Description = "Reduces terrestrial hazards per stack."; Effect = "frackTerr"; EffectValue = 1; HazardReduction = @{"Terrestrial"=0.20} }
        "Asteroid Surveyer" = @{ Value = 2000; Weight = 1.0; Rarity = "Upgrade"; Description = "Halves asteroid hazards per stack."; Effect = "frackAst"; EffectValue = 1; HazardReduction = @{"Asteroid"=0.50} }
        "Dwarf-Class Surveyor" = @{ Value = 1500; Weight = 1.0; Rarity = "Upgrade"; Description = "Reduces dwarf-world hazards per stack."; Effect = "frackDwarf"; EffectValue = 1; HazardReduction = @{"Dwarf"=0.30} }
        "Rad-Shielding Exosuit" = @{ Value = 6000; Weight = 1.0; Rarity = "Upgrade"; Description = "Reduces hazards on HZ 80+ worlds."; Effect = "RadiationSuit"; EffectValue = 1; HazardThreshold = 80; HazardReduction = @{"_threshold"=0.25} }
        "Shield Cell Auto-Injector" = @{ Value = 1500; Weight = 1.0; Rarity = "Upgrade"; Description = "Automatically uses shield cells at lethal damage."; Effect = "AutoAdminister"; EffectValue = 1 }
        "XRF8 Scanner" = @{ Value = 3500; Weight = 3.0; Rarity = "Upgrade"; Description = "Scans approximate resource composition from orbit."; Effect = "XRFScanner"; EffectValue = 1 }
        "Cryo-Sleep Chamber" = @{ Value = 4500; Weight = 3.0; Rarity = "Upgrade"; Description = "Fast-forwards extraction by one simulated year."; Effect = "CryoSkip"; EffectValue = 1 }
        "HyperDrive Module" = @{ Value = 5000; Weight = 5.0; Rarity = "Upgrade"; Description = "Enables interstellar jumps."; Effect = "Hyperdrive"; EffectValue = 1 }
    }
}

function New-Planet {
    param(
        [string] $Name,
        [double] $Distance,
        [string] $Type,
        [double] $Danger,
        [string] $PlanetColor,
        [string] $Description,
        [bool] $Inhabited,
        [string] $TraderName,
        [hashtable] $Resources,
        [string[]] $Hazards,
        [hashtable] $Visual
    )
    return [pscustomobject]@{
        Name = $Name
        Distance = $Distance
        Type = $Type
        Danger = $Danger
        PlanetColor = $PlanetColor
        Description = $Description
        Inhabited = $Inhabited
        TraderName = $TraderName
        TraderCredits = 0
        FuelModifier = 1.0
        RepairModifier = 1.0
        TraderStockRules = @{}
        Quests = @()
        Dialog = @{}
        Greeting = ""
        Resources = $Resources
        HazardReasons = $Hazards
        Visual = $Visual
    }
}

function New-SolSystem {
    $planets = @{}
    $planets.Mercury = New-Planet "Mercury" 0 "Terrestrial" 8.3 "DarkYellow" "Sun-blasted rock with heavy metal seams." $false "" @{ Iron=100; Nickel=120; Copper=45; Sulfur=120; Silicates=60; Silicon=70; Tungsten=90; Silver=45; Gold=70; Uranium=35; Radium=32; Platinum=30; Iridium=2; Carbon=20 } @("Thermal shock cycling", "Solar flare radiation", "Magma spray") @{ Seed=11; Primary="DarkYellow"; Secondary="Gray"; Feature="Craters"; Rings=$false; Tilt=2 }
    $planets.Venus = New-Planet "Venus" 4.5 "Terrestrial" 4.2 "Yellow" "Acid clouds over jagged, reactive beds." $false "" @{ Sulfur=240; Carbon=90; Oxygen=73; Boron=145; Silicon=130; Calcium=45; Magnesium=45; Copper=85; Nickel=105; Silver=92; Gold=32; Platinum=16; Nitrogen=22 } @("Static discharge", "Atmospheric turbulence", "Acid rain corrosion") @{ Seed=22; Primary="Yellow"; Secondary="DarkYellow"; Feature="Clouds"; Rings=$false; Tilt=3 }
    $planets.Earth = New-Planet "Earth" 8.5 "Terrestrial" 1.2 "DarkGreen" "Blue cradle ringed by U.C.E. traffic." $true "U.C.E.O.C.S." @{ Water=260; Carbon=180; Oxygen=150; ScrapMetal=150; Silicates=90; Iron=70; Biomass=60; Nitrogen=25; Hydrogen=8; Argon=5; Copper=15; Silver=5; Gold=2 } @("Hull stress", "Micro-vibrations", "Static discharge") @{ Seed=33; Primary="Blue"; Secondary="Green"; Feature="Oceans"; Rings=$false; Tilt=12 }
    $planets.Mars = New-Planet "Mars" 13 "Terrestrial" 1.0 "DarkRed" "Red dust deserts cut by iron-rich seams." $true "Martian Colony" @{ Silicates=260; Iron=210; Carbon=120; Oxygen=90; Water=80; ScrapMetal=70; Magnesium=45; Calcium=35; Aluminum=35; Sulfur=10; Copper=15; Zinc=8; Tin=6; Nickel=5; Silicon=4; Biomass=20 } @("Hull stress", "Dust storm abrasion", "Tectonic shift") @{ Seed=44; Primary="DarkRed"; Secondary="DarkYellow"; Feature="Canyons"; Rings=$false; Tilt=8 }
    $planets.Ceres = New-Planet "Ceres" 17 "Asteroid" 2.6 "Gray" "Small belt world packed with workable ore." $false "" @{ Silicates=275; Iron=135; Nickel=95; Aluminum=100; Tin=70; Zinc=65; Copper=100; Water=80; Silver=35; Silicon=35; Boron=20; Tungsten=18; Gold=8; Uranium=10; Platinum=4 } @("Meteoroid bombardment", "Micrometeor swarm", "Dust abrasion") @{ Seed=55; Primary="Gray"; Secondary="DarkGray"; Feature="Jagged"; Rings=$false; Tilt=18 }
    $planets.Jupiter = New-Planet "Jupiter" 22 "Gas Giant" 22.0 "Red" "Sovereign mass of storm and crushing pressure." $false "" @{ Hydrogen=280; Helium=180; Nitrogen=120; Neon=100; Argon=95; MetallicHydrogen=110; Water=25; Carbon=20; Oxygen=15; Sulfur=12; Silver=40; Gold=8 } @("Atmospheric turbulence", "Gravity well shear", "Deep pressure crush") @{ Seed=66; Primary="Red"; Secondary="DarkYellow"; Feature="GreatStorm"; Rings=$false; Tilt=3 }
    $planets.Saturn = New-Planet "Saturn" 27 "Gas Giant" 23.0 "Yellow" "Pale, ringed behemoth of violent storms." $false "" @{ Hydrogen=220; Helium=165; Nitrogen=130; Water=95; Neon=100; Argon=95; MetallicHydrogen=105; Silicates=40; Iron=30; Nickel=25; Silver=25; Gold=15; Platinum=15 } @("Atmospheric turbulence", "Gravity well shear", "Ring shard impact") @{ Seed=77; Primary="Yellow"; Secondary="DarkYellow"; Feature="Bands"; Rings=$true; Tilt=9; RingTilt=0 }
    $planets.Uranus = New-Planet "Uranus" 32 "Ice Giant" 14.0 "DarkCyan" "Tilted frozen giant with radioactive traces." $false "" @{ Water=160; Hydrogen=190; Helium=110; Nitrogen=105; Neon=120; Argon=110; Carbon=45; Oxygen=45; Uranium=65; MetallicHydrogen=60; Radium=22; Plutonium=5 } @("Extreme cold stress", "Gravity well shear", "Auroral arc flash") @{ Seed=88; Primary="DarkCyan"; Secondary="Cyan"; Feature="Tilted"; Rings=$true; Tilt=78; RingTilt=82 }
    $planets.Neptune = New-Planet "Neptune" 37 "Ice Giant" 16.0 "Blue" "Distant blue abyss of rare chemistry." $false "" @{ Hydrogen=220; Helium=130; Neon=125; Argon=100; Water=110; Nitrogen=75; MetallicHydrogen=75; Oxygen=35; Carbon=35; Uranium=25; Radium=9; Neptunium=20; Plutonium=4 } @("Extreme cold stress", "Atmospheric turbulence", "Diamond rain impact") @{ Seed=99; Primary="Blue"; Secondary="DarkBlue"; Feature="DarkStorm"; Rings=$false; Tilt=24 }
    $planets.Pluto = New-Planet "Pluto" 49.5 "Dwarf" 4.5 "Gray" "Frigid vault of silicates and secrets." $true "A.M.O-8 Theta" @{ Water=156; Silicates=175; ScrapMetal=165; Iron=120; Carbon=105; Nitrogen=60; Oxygen=45; Copper=30; Nickel=22; Silver=10; Gold=5; Uranium=8; Plutonium=10; Fossils=10; Biomass=5 } @("Extreme cold stress", "Micrometeor swarm", "Static discharge") @{ Seed=110; Primary="Gray"; Secondary="White"; Feature="Icy"; Rings=$false; Tilt=17 }
    $planets.Haumea = New-Planet "Haumea" 52.5 "Dwarf" 4.5 "Gray" "Spinning shard-world with dense outer ore." $false "" @{ Iron=145; Nickel=98; Silicates=150; Water=92; Copper=52; Carbon=42; Aluminum=35; Tin=30; Zinc=21; Silver=22; Tungsten=36; Platinum=14; Uranium=25; Plutonium=15 } @("Rotational shear", "Micrometeor swarm", "Hull stress") @{ Seed=121; Primary="White"; Secondary="Gray"; Feature="Elongated"; Rings=$true; Tilt=28; RingTilt=45 }
    $planets.Makemake = New-Planet "Makemake" 58 "Dwarf" 6.8 "Gray" "Red ice crust with carbon-rich compounds." $false "" @{ Carbon=125; Nitrogen=95; Water=115; Silicates=120; Iron=95; Nickel=45; Copper=35; Aluminum=30; Zinc=42; Tin=40; Silver=22; Gold=10; Uranium=28; Promethium=6; Plutonium=4 } @("Extreme cold stress", "Regolith shear", "Static discharge") @{ Seed=132; Primary="DarkRed"; Secondary="Gray"; Feature="RedIce"; Rings=$false; Tilt=11 }
    $planets.Eris = New-Planet "Eris" 69 "Dwarf" 7.6 "Gray" "Far icy relic hiding heavy, raw veins." $false "" @{ Silicates=118; Iron=98; Water=98; ScrapMetal=72; Carbon=58; Nitrogen=52; Nickel=60; Copper=40; Silver=42; Tungsten=25; Platinum=22; Gold=12; Uranium=48; Radium=19; Fossils=7; Promethium=5; Neptunium=2; Iridium=3 } @("Extreme cold stress", "Radiation burst", "Micrometeor swarm") @{ Seed=143; Primary="White"; Secondary="DarkCyan"; Feature="Icy"; Rings=$false; Tilt=44 }
    Initialize-SolCommerce $planets
    return $planets
}

function New-Quest {
    param(
        [string] $Id, [string] $Name, [int] $RepReq, [string] $Description,
        [hashtable] $Requirements, [int] $RewardCredits, [hashtable] $RewardItems,
        [string] $KnownSystem = ""
    )
    return [pscustomobject]@{
        Id=$Id; Name=$Name; RepReq=$RepReq; Description=$Description
        Requirements=$Requirements; RewardCredits=$RewardCredits; RewardItems=$RewardItems
        KnownSystem=$KnownSystem
    }
}

function New-StockRule {
    param([int] $Chance,[int] $MinQty,[int] $MaxQty,[int] $DoubleChance=0)
    return @{Chance=$Chance;MinQty=$MinQty;MaxQty=$MaxQty;DoubleChance=$DoubleChance}
}

function Get-CanonicalTraderStockRules {
    param([Parameter(Mandatory=$true)][string] $TraderId)
    switch($TraderId){
        "Earth" { return @{
            "Auxiliary Fuel Tank"=New-StockRule 60 1 1 2
            "Cargo Baffles"=New-StockRule 10 1 1 2
            "Deluxe Auxiliary Fuel Tank"=New-StockRule 5 0 1 1
            "Fuel Cell (Medium)"=New-StockRule 85 0 5
            "Fuel Cell (Small)"=New-StockRule 75 0 7
            "Iridium"=New-StockRule 2 0 1 5
            "Shield Cell (Medium)"=New-StockRule 75 0 4
            "Shield Cell (Small)"=New-StockRule 75 0 6
            "U.C.E. Shield Generator MK I"=New-StockRule 80 1 1 6
            "U.C.E. Shield Generator MK II"=New-StockRule 15 1 1 3
            "U.C.E. Shield Generator MK III"=New-StockRule 5 1 1 1
        }}
        "Mars" { return @{
            "Auxiliary Fuel Tank"=New-StockRule 60 1 1 7
            "Cargo Baffles"=New-StockRule 70 1 1 6
            "Deluxe Auxiliary Fuel Tank"=New-StockRule 2 1 1 2
            "Fuel Cell (Medium)"=New-StockRule 75 0 3
            "Fuel Cell (Small)"=New-StockRule 90 0 5
            "Iridium"=New-StockRule 1 0 1 5
            "Premium Cargo Baffles"=New-StockRule 4 1 1 2
            "Shield Cell (Medium)"=New-StockRule 75 0 2
            "Shield Cell (Small)"=New-StockRule 90 0 3
        }}
        "Pluto" { return @{
            "Cargo Baffles"=New-StockRule 80 1 1 8
            "Fuel Cell (Large)"=New-StockRule 60 0 4
            "Fuel Cell (Medium)"=New-StockRule 70 0 6
            "Fuel Cell (Small)"=New-StockRule 50 0 5
            "Iridium"=New-StockRule 1 0 1 15
            "Premium Cargo Baffles"=New-StockRule 10 1 1 1
            "Shield Cell (Large)"=New-StockRule 50 0 3
            "Shield Cell (Medium)"=New-StockRule 50 0 3
            "Shield Cell (Small)"=New-StockRule 50 0 3
            "U.C.E. Shield Generator MK III"=New-StockRule 75 1 1 4
        }}
        "Bastion" { return @{
            "Bastion Shield Generator"=New-StockRule 95 1 1 4
            "Deluxe Auxiliary Fuel Tank"=New-StockRule 88 1 1 8
            "Fuel Cell (Large)"=New-StockRule 75 0 9
            "Fuel Cell (Medium)"=New-StockRule 60 0 6
            "Fuel Cell (Small)"=New-StockRule 30 0 8
            "Premium Cargo Baffles"=New-StockRule 88 1 1 8
            "Shield Cell (Large)"=New-StockRule 75 0 9
            "Shield Cell (Medium)"=New-StockRule 60 0 3
            "Shield Cell (Small)"=New-StockRule 30 0 8
        }}
        "Flotsam" { return @{
            "Auxiliary Fuel Tank"=New-StockRule 64 1 1 4
            "Bastion Fuel Cell"=New-StockRule 24 0 1 4
            "Bastion Shield Cell"=New-StockRule 24 0 1 2
            "Cargo Baffles"=New-StockRule 64 1 1 4
            "Deluxe Auxiliary Fuel Tank"=New-StockRule 33 1 1 1
            "FFF Shield Generator"=New-StockRule 33 0 1 5
            "Fuel Cell (Large)"=New-StockRule 75 0 5
            "Fuel Cell (Medium)"=New-StockRule 60 0 4
            "Fuel Cell (Small)"=New-StockRule 30 0 6
            "Premium Cargo Baffles"=New-StockRule 33 1 1 2
            "Shield Cell (Large)"=New-StockRule 75 0 5
            "Shield Cell (Medium)"=New-StockRule 60 0 4
            "Shield Cell (Small)"=New-StockRule 30 0 6
        }}
        default { throw ("Unknown canonical trader stock table: {0}" -f $TraderId) }
    }
}

function Get-CanonicalTraderDialogs {
    param([Parameter(Mandatory=$true)][string] $TraderId)
    switch($TraderId){
        "Earth" { return @{
            Greeting=@(
                "Welcome to United Countries of Earth Orbital Commerce Services. Your compliance makes prosperity possible."
                "U.C.E.O.C.S. transaction window open. Smile for the scanner."
                "Welcome back to Earth orbit. Please have your credits ready."
                "Orbital commerce services are currently experiencing expected delays."
            )
            TradeGreeting=@(
                "How may I assist you today, valued independent contractor?"
                "Buy, sell, repair, refuel. The menu has not changed since you looked at it."
                "What can the United Countries of Earth do to you today?"
                "May I take your order?"
            )
            Refuel=@(
                "Topped up. Try not to make that our problem again."
                "Fuel transfer complete. I noticed you didn't tip..."
                "Tank is full. Tip?"
            )
            Repair=@(
                "Structural integrity restored. Mostly."
                "Repairs processed. The hull is now legally spaceworthy."
                "Damage patched... Oh that? That's not covered under our policy."
            )
            Trade=@(
                "Credits transferred. It should post in 3-5 business days."
                "Transaction complete. We value your business."
                "Trade logged. Procurement will pretend this was planned."
            )
            InsufficientFunds=@(
                "Transaction declined. Credits aren't optional."
                "Insufficient funds. We don't barter here."
                "Your balance has failed the patriotism check."
            )
            InsufficientFundsTrader=@(
                "You have exceeded our budget for your cargo."
                "Procurement budget exhausted. Try a less important window."
                "The U.C.E. declines to buy that much reality at once."
            )
            Frustrated=@(
                "What? No."
                "We don't do that here."
                "Security, we may have an incident."
            )
        }}
        "Mars" { return @{
            Greeting=@(
                "Welcome back, scrapper."
                "Mars tower has you on approach. Dock easy."
                "Colony market is open. Mind the dust seals."
                "Back from the black? Good. We could use the business."
            )
            TradeGreeting=@(
                "What'll it be this time?"
                "Need fuel, patches, or here to trade?"
                "If it keeps a hull flying, we'll talk."
                "Let's see what you've hauled in."
            )
            Refuel=@(
                "Fuel's pumpin'."
                "Tanks topped. Keep some in reserve."
                "Fuel transfer done. No leaks on our side."
            )
            Repair=@(
                "Hull patched."
                "We sealed the worst of it. Watch the stress marks."
                "Repairs done. She's ugly, but she'll hold."
            )
            Trade=@(
                "Pleasure doin' business."
                "Credits sent. Cargo logged."
                "Good haul. Colony can use it."
            )
            InsufficientFunds=@(
                "Credits first, hero."
                "Can't run a colony on promises."
                "You're short. Happens."
            )
            InsufficientFundsTrader=@(
                "And what'll ya be wanting for that?"
                "We can't cover that much cargo right now."
                "Colony till is light. Come back after restock."
            )
            Frustrated=@(
                "Come again, now?"
                "That doesn't help either of us."
                "Slow down and try again."
            )
        }}
        "Pluto" { return @{
            Greeting=@(
                "Mining platform online. Commerce protocol active."
                "A.M.O.8 Theta acknowledges vessel telemetry."
                "Organic pilot detected. Commerce protocol initiated."
                "*System self-service in progress...*"
            )
            TradeGreeting=@(
                "Inventory reconciliation requested."
                "State desired exchange."
                "Commerce module awaiting material variance."
                "Awaiting selection."
            )
            Refuel=@(
                "Fuel transfer complete."
                "Propellant mass restored to requested threshold."
                "Energy reserve correction complete."
            )
            Repair=@(
                "Maintenance cycle complete."
                "Hull discontinuities reduced."
                "Structural risk returned to profitable range."
            )
            Trade=@(
                "Transaction recorded."
                "Inventory updated."
                "Exchange accepted."
            )
            InsufficientFunds=@(
                "Insufficient credits."
                "Credit mass below required threshold."
                "Request rejected. Currency absence detected."
            )
            InsufficientFundsTrader=@(
                "Reserve inventory depleted."
                "Purchase threshold exceeded."
                "Acquisition halted to preserve station solvency."
            )
            Frustrated=@(
                "Invalid request."
                "Input not recognized."
                "Clarify intent."
            )
        }}
        "Bastion" { return @{
            Greeting=@(
                "Docking authorization accepted. Deviation will be treated as intent."
                "Bastion control recognizes your vessel. Keep your channel clean."
                "You are entering Republic-controlled space. Conduct yourself usefully."
                "Transmit cargo manifest and await instruction."
            )
            TradeGreeting=@(
                "State your business."
                "Make it brief. The front does not pause for merchants."
                "We offer discounts if you enlist."
                "Republic logistics. What's your business?"
            )
            Refuel=@(
                "Fuel transfer complete."
                "Your range has been restored. Spend it in service of order."
                "Propellant issued."
            )
            Repair=@(
                "Repairs concluded."
                "Your hull is fit for redeployment."
                "Damage corrected."
            )
            Trade=@(
                "Credits transferred."
                "Republic acquision approved."
                "Logged. The republic acknowledges your contribution."
            )
            InsufficientFunds=@(
                "Got to pay or enlist."
                "We don't do loans."
                "Return with funds."
            )
            InsufficientFundsTrader=@(
                "Procurement budget exhausted."
                "Command wouldn't authorize."
                "Your cargo exceeds current strategic allocation."
            )
            Frustrated=@(
                "Come again?"
                "Do not waste my time."
                "You are testing my patience, not my authority."
            )
        }}
        "Flotsam" { return @{
            Greeting=@(
                "Didn't expect a fracker out here. Dock quiet and keep your beacon low."
                "Flotsam hears you. If Republic patrols followed, we cut the line."
                "You're clear to berth. You better not have been followed."
                "Welcome to what is left of free Typhon."
            )
            TradeGreeting=@(
                "Let's see what you've hauled in."
                "If it keeps lights on or shields up, we're interested."
                "Make it quick."
                "What can you spare for the outpost?"
            )
            Refuel=@(
                "Tanks topped off."
                "Fuel loaded. Don't burn it where Bastion can track you."
                "Range restored. Come back alive."
            )
            Repair=@(
                "Watch your ass out there."
                "Hull patched. It won't win a parade, but it will fly."
                "We sealed the holes. Keep the Republic from making new ones."
            )
            Trade=@(
                "Pleasure doing business."
                "Cargo received. That buys somebody another day."
                "Credits sent. Flotsam owes you more than that."
            )
            InsufficientFunds=@(
                "Wish we could front the credits."
                "We're short too. Everybody is."
                "Can't cover that from the outpost ledger."
            )
            InsufficientFundsTrader=@(
                "Can't afford that haul."
                "We need it, but we can't pay for all of it."
                "Our reserves are tapped. Try splitting the load."
            )
            Frustrated=@(
                "Easy there."
                "Pick a lane, pilot."
                "Keep it together. We have enough alarms."
            )
        }}
        default { throw ("Unknown canonical trader dialog table: {0}" -f $TraderId) }
    }
}

function Set-PlanetCommerce {
    param($Planet,[string] $TraderName,[int] $Credits,[double] $FuelModifier,[double] $RepairModifier,[hashtable] $Stock,[object[]] $Quests)
    $dialog=Get-CanonicalTraderDialogs $Planet.Name
    $Planet | Add-Member -NotePropertyName TraderName -NotePropertyValue $TraderName -Force
    $Planet | Add-Member -NotePropertyName TraderCredits -NotePropertyValue $Credits -Force
    $Planet | Add-Member -NotePropertyName FuelModifier -NotePropertyValue $FuelModifier -Force
    $Planet | Add-Member -NotePropertyName RepairModifier -NotePropertyValue $RepairModifier -Force
    $Planet | Add-Member -NotePropertyName TraderStockRules -NotePropertyValue $Stock -Force
    $Planet | Add-Member -NotePropertyName Quests -NotePropertyValue $Quests -Force
    $Planet | Add-Member -NotePropertyName Dialog -NotePropertyValue $dialog -Force
    $Planet | Add-Member -NotePropertyName Greeting -NotePropertyValue ([string]$dialog.Greeting[0]) -Force
}

function Initialize-SolCommerce {
    param([hashtable] $Planets)
    $earthQuests=@(
        New-Quest "earth_1" "Permit Pending" 0 "Premium permit processing accepts gold and silver." @{Gold=1;Silver=5} 500 @{"U.C.E. Shield Generator MK I"=1}
        New-Quest "earth_2" "Strategic Reserve Expansion" 1 "Earth needs off-world construction metals." @{Iron=30;Copper=25;Silver=10} 500 @{"Cargo Baffles"=1}
        New-Quest "earth_3" "A Silicate Matter" 2 "Orbital construction needs belt feedstock." @{Silicates=120;Aluminum=25;Zinc=20;Tin=20} 2500 @{"Auxiliary Fuel Tank"=1}
        New-Quest "earth_4" "Special Materials Contract" 3 "Energy research needs hot isotopes." @{Uranium=5;Radium=3;Sulfur=20} 2500 @{"Ice Giant Surveyor"=1}
        New-Quest "earth_5" "A Noble Endeavor" 3 "Atmospheric Services requires noble gases." @{Helium=30;Neon=30;Argon=30} 1000 @{"Cargo Baffles"=1;"U.C.E. Shield Generator MK III"=1}
        New-Quest "earth_6" "Project Horizon" 4 "High-pressure fuel work needs giant-world samples." @{MetallicHydrogen=25;Platinum=3;Tungsten=5} 0 @{"Terrain Hardening Kit"=1}
        New-Quest "earth_7" "Ring Audit" 5 "Audit Saturn shipments and recovered salvage." @{Neon=50;Argon=60;Silver=15;ScrapMetal=20} 2000 @{"Fuel Cell (Large)"=2;"Shield Cell (Large)"=2}
        New-Quest "earth_8" "Gaseous Venture" 6 "Procurement needs bulk Jovian gas." @{Hydrogen=150;Helium=100;Nitrogen=75;MetallicHydrogen=15} 1000 @{"Premium Cargo Baffles"=1}
    )
    $marsQuests=@(
        New-Quest "mars_1" "Dust and Rust" 0 "Iron is always in demand." @{Iron=35} 0 @{"U.C.E. Shield Generator MK I"=1;"Shield Cell (Small)"=2;"Fuel Cell (Medium)"=2}
        New-Quest "mars_2" "Spectral Calibration" 1 "Calibrate a scanner with Venusian sulfur." @{Sulfur=10} 0 @{"XRF8 Scanner"=1}
        New-Quest "mars_3" "Patchwork Fleet" 1 "Bring patch stock for an auto-injector." @{ScrapMetal=20;Iron=25;Copper=10} 750 @{"Shield Cell Auto-Injector"=1}
        New-Quest "mars_4" "Ceramic Scratch" 2 "Deliver heat-shielding inputs." @{Magnesium=25;Calcium=20;Boron=15;Silicon=20} 1000 @{"Auxiliary Fuel Tank"=1;"Cargo Baffles"=1}
        New-Quest "mars_5" "Biological Census" 2 "Even bad biomass samples matter." @{Biomass=25} 1000 @{"U.C.E. Shield Generator MK III"=1}
        New-Quest "mars_6" "Atmospheric Processor" 3 "Deliver a Venusian poison cocktail." @{Sulfur=35;Nitrogen=25;Argon=10} 0 @{"Gas Giant Surveyor"=1}
        New-Quest "mars_7" "Belt Hardening Trial" 5 "Deliver a Ceres-heavy ore order." @{Silicates=80;Iron=50;Copper=30;Nickel=30;Aluminum=30} 1000 @{"U.C.E. Shield Generator MK II"=1}
        New-Quest "mars_8" "Colony Stockpile" 6 "Boring cargo keeps winter boring." @{Iron=120;Water=80;Biomass=25;Zinc=20;Tin=20} 1500 @{"Deluxe Auxiliary Fuel Tank"=1}
        New-Quest "mars_9" "Blue Horizon" 7 "Supply rare chemistry for deep-range tests." @{Neon=35;Argon=35;MetallicHydrogen=20;Neptunium=3} 1500 @{"Fuel Cell (Large)"=5}
        New-Quest "mars_10" "Heavy Metals" 8 "Haumea should match this dense order." @{Iron=80;Nickel=40;Tungsten=20;Uranium=15;Platinum=5} 1800 @{"Premium Cargo Baffles"=1}
    )
    $plutoQuests=@(
        New-Quest "pluto_1" "Feed the Beast" 0 "Jovian energy samples are required." @{MetallicHydrogen=35;Hydrogen=50} 2000 @{"Auxiliary Fuel Tank"=1}
        New-Quest "pluto_2" "Crionics" 1 "Rebuild the station cryogenic system." @{Nitrogen=50;Neon=20;Water=80} 0 @{"Cryo-Sleep Chamber"=1}
        New-Quest "pluto_3" "Structural Maintenance" 2 "Deliver repair metals." @{Iron=80;Nickel=20;Zinc=20;Tin=20} 3000 @{"Shield Cell (Small)"=5}
        New-Quest "pluto_4" "Carbon Pangs" 3 "Acquire biological samples." @{Biomass=200;Carbon=100} 2500 @{"Fuel Cell (Large)"=2}
        New-Quest "pluto_5" "Kuiper Mapping Array" 3 "Repair the cold mapping array." @{Uranium=12;Platinum=5;Promethium=2;Tungsten=12} 1000 @{"Dwarf-Class Surveyor"=1;"Deluxe Auxiliary Fuel Tank"=1}
        New-Quest "pluto_6" "Debris Mitigation" 4 "Reassemble the interception grid." @{ScrapMetal=40;Aluminum=50;Silver=20;Tungsten=5} 1200 @{"Shield Cell (Large)"=4}
        New-Quest "pluto_7" "Resilient Alloy" 5 "Acquire near-impervious alloy precursors." @{Iridium=6;Radium=4;Neptunium=2} 3000 @{"Fuel Cell (Large)"=3}
        New-Quest "pluto_8" "Samples" 7 "Complete a representative Sol resource library." @{Silicates=60;Carbon=40;Oxygen=40;Water=40;Iron=50;Hydrogen=35;Nitrogen=30;Magnesium=20;Calcium=20;Aluminum=20;Sulfur=20;ScrapMetal=20;Zinc=15;Tin=15;Copper=15;Silicon=10;Nickel=10;Biomass=5;Boron=10;Argon=10;Neon=10;Helium=8;Silver=8;Tungsten=5;Platinum=3;Gold=3;MetallicHydrogen=5;Fossils=2;Plutonium=2;Uranium=5;Radium=4;Neptunium=2;Promethium=1;Iridium=1} 2000 @{"HyperDrive Module"=1} "Typhon"
        New-Quest "pluto_9" "Unauthorized Density" 8 "Obtain stronger off-system materials." @{Mythril=15;Deuterium=45} 5000 @{"Shield Cell (Large)"=2}
        New-Quest "pluto_10" "Elemental Fusion" 8 "Acquire Typhon reactor catalysts." @{"Helium-3"=25;Cryophane=15} 7000 @{"Fuel Cell (Large)"=4}
        New-Quest "pluto_11" "Next Generation Warfare" 10 "Recover Republic military technology." @{"Warship Alloy"=50;"Ordnance Core"=10} 8000 @{"Shield Cell (Large)"=4}
        New-Quest "pluto_12" "Intergalactic Refractory" 11 "Overcome Sol thermal limits." @{"Tantalum Hafnium Carbide"=40;Pyrestone=20} 10000 @{"U.C.E. Shield Generator MK III"=2}
    )
    Set-PlanetCommerce $Planets.Earth "U.C.E.O.C.S." 5000 1.3 1.4 (Get-CanonicalTraderStockRules "Earth") $earthQuests
    Set-PlanetCommerce $Planets.Mars "Martian Colony" 3000 1.1 1.2 (Get-CanonicalTraderStockRules "Mars") $marsQuests
    Set-PlanetCommerce $Planets.Pluto "A.M.O-8 Theta" 3000 1.6 1.1 (Get-CanonicalTraderStockRules "Pluto") $plutoQuests
}

function New-TyphonSystem {
    $planets=@{}
    $planets.Pyre=New-Planet "Pyre" 0 "Terrestrial" 60 "DarkRed" "A molten hellhole with abundant resources." $false "" @{Iron=250;Copper=200;Nickel=150;Gold=300;Uranium=500;Radium=300;Mythril=450;"Tantalum Hafnium Carbide"=500;Pyrestone=1000;Helium=200;Deuterium=100;Promethium=350;Iridium=150} @("Basalt flood wave","Mantle plume rupture","Gamma ray exposure") @{Seed=201;Primary="DarkRed";Secondary="Yellow";Feature="Lava";Rings=$false;Tilt=4}
    $planets.Bastion=New-Planet "Bastion" 5 "Terrestrial" 34 "DarkBlue" "Capital of the fractured Republic." $true "Bastion Republic" @{Iron=500;Copper=300;Silver=250;Gold=175;Mythril=225;Water=150;Biomass=125;"Tantalum Hafnium Carbide"=200;"Warship Alloy"=950;"Ordnance Core"=900;"Republic Flight Recorder"=2;Deuterium=75;Uranium=325;Promethium=150} @("Flak cloud","Drone strafing run","Missile volley") @{Seed=212;Primary="DarkBlue";Secondary="Gray";Feature="Cities";Rings=$false;Tilt=8}
    $planets.Shrapnel=New-Planet "Shrapnel" 27.5 "Asteroid" 45 "Gray" "A shattered belt littered with remnants of war." $false "" @{Silicates=50;Iron=250;ScrapMetal=505;Copper=225;Nickel=225;Silver=225;Gold=175;Mythril=550;"Warship Alloy"=950;"Ordnance Core"=950;"Republic Flight Recorder"=5;Tungsten=225;Uranium=225;Promethium=120} @("Munitions detonation","Railgun graze","Asteroid impact") @{Seed=223;Primary="Gray";Secondary="DarkGray";Feature="Jagged";Rings=$true;Tilt=32;RingTilt=-33}
    $planets.Hyperion=New-Planet "Hyperion" 35.5 "Gas Giant" 46 "DarkYellow" "Massive storms hide priceless fuel reserves." $false "" @{Nitrogen=500;Hydrogen=550;Helium=650;MetallicHydrogen=1050;Deuterium=950;"Helium-3"=450;Neon=150;Argon=135;Uranium=200;Promethium=75} @("Deep pressure crush","Super-cyclone vortex","Gamma ray exposure") @{Seed=234;Primary="DarkYellow";Secondary="Red";Feature="GreatStorm";Rings=$false;Tilt=7}
    $planets.Cocytus=New-Planet "Cocytus" 53 "Ice Giant" 36 "Cyan" "Frozen oceans beneath violent clouds." $false "" @{Uranium=400;Radium=120;Nitrogen=800;Hydrogen=525;Helium=600;Water=200;MetallicHydrogen=800;Deuterium=650;"Helium-3"=90;Cryophane=600;Neptunium=50;Promethium=35} @("Cryowake rupture","Auroral arc flash","Diamond Rain Ballistic Impact") @{Seed=245;Primary="Cyan";Secondary="Blue";Feature="Icy";Rings=$true;Tilt=19;RingTilt=10}
    $planets.Flotsam=New-Planet "Flotsam" 69 "Dwarf" 23 "White" "A Free Frontier Fighters rebel outpost." $true "FFF Rebels" @{Iron=600;ScrapMetal=650;Copper=450;Silver=475;Gold=300;Mythril=75;Water=500;Biomass=275;Nitrogen=175;Hydrogen=175;Helium=175;MetallicHydrogen=175;Deuterium=175;Uranium=200} @("Static ashfall","Flak cloud","Railgun graze") @{Seed=256;Primary="White";Secondary="DarkCyan";Feature="Outpost";Rings=$false;Tilt=14}
    $repQuests=@(
        New-Quest "rep_1" "Strategic Alloy Procurement" 0 "Provide mythril and warship components." @{Mythril=50;"Warship Alloy"=125} 5000 @{}
        New-Quest "rep_2" "Field Survey Arsenal" 1 "Provide strategic refractory stock." @{"Tantalum Hafnium Carbide"=30;Gold=50;Copper=250} 3000 @{"Asteroid Surveyer"=1}
        New-Quest "rep_3" "Isotope Tithe" 2 "The Republic accepts unstable isotopes." @{Uranium=150;Radium=75;Deuterium=100;Promethium=20} 7000 @{"Bastion Shield Cell"=2}
        New-Quest "rep_4" "Weapons Division Allocation" 3 "Munitions reserves are critically low." @{Uranium=100;Mythril=75;"Ordnance Core"=50} 8000 @{"Bastion Shield Generator"=1}
        New-Quest "rep_5" "Operation Sunforge" 4 "Acquire strategic fuel precursors." @{Deuterium=200;"Helium-3"=40;MetallicHydrogen=200} 10000 @{"Rad-Shielding Exosuit"=1}
        New-Quest "rep_6" "Thermal Research" 5 "Deliver extreme thermal materials." @{"Tantalum Hafnium Carbide"=100;Cryophane=50} 9000 @{"Bastion Shield Generator"=1}
        New-Quest "rep_7" "Mantle Claim" 6 "Claim Pyre mantle chemistry." @{Pyrestone=80;"Tantalum Hafnium Carbide"=100;Radium=100} 14000 @{"Bastion Fuel Cell"=3}
        New-Quest "rep_8" "Final Weapons Trial" 7 "Supply the final Republic prototype." @{Pyrestone=100;"Ordnance Core"=80;"Helium-3"=50;Iridium=25} 25000 @{"Bastion Shield Generator"=1}
    )
    $rebelQuests=@(
        New-Quest "rebel_1" "Keeping Us Flying" 0 "Keep the frontier freighters alive." @{ScrapMetal=80;Iron=80;Water=60} 2500 @{"Shield Cell (Large)"=4}
        New-Quest "rebel_2" "Esoterics" 0 "Recover a Republic flight recorder." @{"Republic Flight Recorder"=1} 8000 @{"Premium Cargo Baffles"=1}
        New-Quest "rebel_3" "Cold Signal" 1 "Build a shielded relay from Cocytus ice." @{Cryophane=25;Water=100;Nitrogen=150} 3500 @{"Shield Cell (Large)"=3}
        New-Quest "rebel_4" "Long Haul Logistics" 2 "Extend the rebel supply lines." @{Deuterium=80;MetallicHydrogen=60} 4000 @{"Deluxe Auxiliary Fuel Tank"=1}
        New-Quest "rebel_5" "Frontier Armor" 2 "Plate small ships with Mythril." @{Mythril=60;Gold=40;Nickel=100} 5000 @{"Fuel Cell (Large)"=4}
        New-Quest "rebel_6" "Break the Blockade" 3 "Recover Hyperion fuel stock." @{Deuterium=150;"Helium-3"=20;MetallicHydrogen=150} 6500 @{"Gas Giant Surveyor"=1}
        New-Quest "rebel_7" "Jammer Ice" 3 "Supply hidden Cocytus jammers." @{Cryophane=60;Deuterium=80;Uranium=80} 6500 @{"Ice Giant Surveyor"=1}
        New-Quest "rebel_8" "Shrapnel Run" 4 "Turn Republic wreckage into armor." @{"Warship Alloy"=150;"Ordnance Core"=60} 9000 @{"FFF Shield Generator"=1}
        New-Quest "rebel_9" "Sunward Sabotage" 5 "Break Bastion's Pyre project first." @{Pyrestone=50;"Tantalum Hafnium Carbide"=50;"Ordnance Core"=40} 15000 @{"Premium Cargo Baffles"=1;"Deluxe Auxiliary Fuel Tank"=1}
    )
    Set-PlanetCommerce $planets.Bastion "Bastion Republic" 9001 2.2 1.5 (Get-CanonicalTraderStockRules "Bastion") $repQuests
    Set-PlanetCommerce $planets.Flotsam "FFF Rebels" 4500 2.0 1.4 (Get-CanonicalTraderStockRules "Flotsam") $rebelQuests
    return $planets
}

function Set-ProspectingParityData {
    param([hashtable] $Systems)
    $data=@{
        Sol=@{
            Mercury=@{Resources=@{Iron=100;Nickel=120;Copper=45;Sulfur=120;Silicates=60;Silicon=70;Tungsten=90;Silver=45;Gold=70;Uranium=35;Radium=32;Platinum=30;Iridium=2;Carbon=20;Oxygen=20;Hydrogen=20;Helium=10;Neon=8;Argon=8;MetallicHydrogen=3;"U.C.E. Shield Generator MK II"=1};HazardReasons=@("Thermal shock cycling","Solar flare radiation","Magma spray","Tectonic plate collapse","Coronal particle surge")}
            Venus=@{Resources=@{Sulfur=240;Carbon=90;Oxygen=73;Boron=145;Silicon=130;Calcium=45;Magnesium=45;Copper=85;Nickel=105;Silver=92;Gold=32;Platinum=16;Nitrogen=22;Uranium=8;Radium=6;Argon=10;Neon=6;Hydrogen=8;Helium=2;MetallicHydrogen=1;"U.C.E. Shield Generator MK I"=1};HazardReasons=@("Static discharge","Atmospheric turbulence","Acid rain corrosion","Sulfuric acid deluge","Runaway greenhouse pressure","Tectonic plate collapse")}
            Earth=@{Resources=@{Water=260;Carbon=180;Oxygen=150;ScrapMetal=150;Silicates=90;Iron=70;Biomass=60;Nitrogen=25;Hydrogen=8;Argon=5;Neon=2;Copper=15;Nickel=8;Zinc=6;Aluminum=11;Tin=4;Sulfur=4;Uranium=1;Fossils=1;Helium=3;Silver=5;Gold=2};HazardReasons=@("Hull stress","Micro-vibrations","Static discharge","Atmospheric turbulence","Tectonic shift")}
            Mars=@{Resources=@{Silicates=260;Iron=210;Carbon=120;Oxygen=90;Water=80;ScrapMetal=70;Magnesium=45;Calcium=35;Aluminum=35;Sulfur=10;Copper=15;Zinc=8;Tin=6;Nickel=5;Silicon=4;Boron=2;Nitrogen=4;Hydrogen=4;Argon=2;Neon=1;Helium=1;Silver=5;Biomass=20};HazardReasons=@("Hull stress","Micro-vibrations","Static discharge","Dust storm abrasion","Tectonic shift")}
            Ceres=@{Resources=@{Silicates=275;Iron=135;Nickel=95;Aluminum=100;Tin=70;Zinc=65;Copper=100;Water=80;Silver=35;Silicon=35;Boron=20;Tungsten=18;Magnesium=16;Calcium=24;Gold=8;Uranium=10;Radium=3;Platinum=4;Iridium=2;"U.C.E. Shield Generator MK I"=1};HazardReasons=@("Hull stress","Micro-vibrations","Static discharge","Micrometeor swarm","Meteoroid bombardment","Debris field collision","Ring shard impact")}
            Jupiter=@{Resources=@{Hydrogen=280;Helium=180;Nitrogen=120;Neon=100;Argon=95;MetallicHydrogen=110;Water=25;Carbon=20;Oxygen=15;Sulfur=12;Uranium=4;Radium=2;Iridium=2;Silver=40;Gold=8;"U.C.E. Shield Generator MK II"=1};HazardReasons=@("Gravity well shear","Deep pressure crush","Lightning discharge","Extreme Lightning discharge","Super-cyclone vortex","Magnetosphere flux storm","Gamma ray exposure")}
            Saturn=@{Resources=@{Hydrogen=220;Helium=165;Nitrogen=130;Water=95;Neon=100;Argon=95;MetallicHydrogen=105;Silicates=40;Iron=30;ScrapMetal=20;Nickel=25;Carbon=25;Oxygen=20;Silver=25;Gold=15;Tungsten=15;Platinum=15;Iridium=2;Promethium=3;Uranium=15;"U.C.E. Shield Generator MK II"=1};HazardReasons=@("Ring shard impact","Deep pressure crush","Lightning discharge","Extreme Lightning discharge","Super-cyclone vortex","Magnetosphere flux storm","Gamma ray exposure")}
            Uranus=@{Resources=@{Water=160;Hydrogen=190;Helium=110;Nitrogen=105;Neon=120;Argon=110;Carbon=45;Oxygen=45;Uranium=65;MetallicHydrogen=60;Radium=22;Plutonium=5;Silver=8;Gold=3;Iridium=3;Promethium=2;"U.C.E. Shield Generator MK II"=1};HazardReasons=@("Extreme cold stress","Methane pressure spike","Cryovolcanic ejecta","Cryo-geyser eruption","Lightning discharge","Ring shard impact","Diamond Rain Ballistic Impact")}
            Neptune=@{Resources=@{Hydrogen=220;Helium=130;Neon=125;Argon=100;Water=110;Nitrogen=75;MetallicHydrogen=75;Oxygen=35;Carbon=35;Uranium=25;Radium=9;Neptunium=20;Plutonium=4;Iridium=2;"U.C.E. Shield Generator MK II"=1};HazardReasons=@("Extreme cold stress","Deep pressure crush","Supersonic wind shear","Lightning discharge","Super-cyclone vortex","Diamond Rain Ballistic Impact")}
            Pluto=@{Resources=@{Water=156;Silicates=175;ScrapMetal=165;Iron=120;Carbon=105;Nitrogen=60;Oxygen=45;Copper=30;Nickel=22;Tin=14;Zinc=14;Aluminum=13;Silver=10;Gold=5;Uranium=8;Radium=1;Plutonium=10;Fossils=10;MetallicHydrogen=4;Platinum=2;Tungsten=2;Promethium=1;Biomass=5};HazardReasons=@("Hull stress","Extreme cold stress","Cryovolcanic ejecta","Cryo-geyser eruption","Asteroid impact")}
            Haumea=@{Resources=@{Iron=145;Nickel=98;Silicates=150;Water=92;Copper=52;Carbon=42;Nitrogen=15;Aluminum=35;Tin=30;Zinc=21;Silver=22;Tungsten=36;Platinum=14;Gold=5;Uranium=25;Plutonium=15;Promethium=2;Iridium=2;"Cargo Baffles"=1};HazardReasons=@("Hull stress","Micro-vibrations","Static discharge","Micrometeor swarm","Ring shard impact")}
            Makemake=@{Resources=@{Carbon=125;Nitrogen=95;Water=115;Silicates=120;Iron=95;Nickel=45;Copper=35;Aluminum=30;Zinc=42;Tin=40;Silver=22;Gold=10;Tungsten=10;Platinum=5;Uranium=28;Promethium=6;Plutonium=4;Iridium=2;"Auxiliary Fuel Tank"=1};HazardReasons=@("Hull stress","Static discharge","Extreme cold stress","Cryovolcanic ejecta","Methane pressure spike")}
            Eris=@{Resources=@{Silicates=118;Iron=98;Water=98;ScrapMetal=72;Carbon=58;Nitrogen=52;Nickel=60;Copper=40;Silver=42;Tungsten=25;Platinum=22;Gold=12;Uranium=48;Radium=19;Fossils=7;Promethium=5;Neptunium=2;Iridium=3;"U.C.E. Shield Generator MK I"=1};HazardReasons=@("Hull stress","Micro-vibrations","Solar flare radiation","Supersonic wind shear","Asteroid impact")}
        }
        Typhon=@{
            Pyre=@{Resources=@{Iron=250;Copper=200;Nickel=150;Gold=300;Uranium=500;Radium=300;Mythril=450;"Tantalum Hafnium Carbide"=500;Pyrestone=1000;Nitrogen=25;Hydrogen=25;Helium=200;Deuterium=100;"Bastion Fuel Cell"=25;"Bastion Shield Cell"=25;Platinum=150;Promethium=350;Iridium=150;Plutonium=250;Neptunium=200};HazardReasons=@("Basalt flood wave","Crustal foundering","Mantle plume rupture","Plasma lash","Photospheric blowout","Fission Event","Gamma ray exposure","Critical gamma ray exposure")}
            Bastion=@{Resources=@{Iron=500;Copper=300;Silver=250;Gold=175;Mythril=225;Water=150;Biomass=125;"Tantalum Hafnium Carbide"=200;"Warship Alloy"=950;"Ordnance Core"=900;"Republic Flight Recorder"=2;"Bastion Fuel Cell"=50;"Bastion Shield Cell"=50;Deuterium=75;Nickel=75;Uranium=325;Radium=200;Promethium=150;Plutonium=120;Iridium=50};HazardReasons=@("Basalt flood wave","Crustal foundering","Flak cloud","Live ordnance ping","Drone strafing run","Munitions detonation","Railgun graze","Missile volley","Torpedo strike")}
            Shrapnel=@{Resources=@{Silicates=50;Iron=250;ScrapMetal=505;Copper=225;Nickel=225;Silver=225;Gold=175;Mythril=550;"Warship Alloy"=950;"Ordnance Core"=950;"Republic Flight Recorder"=5;"Bastion Fuel Cell"=25;"Bastion Shield Cell"=25;Tungsten=225;Uranium=225;Radium=125;Platinum=125;Iridium=20;Promethium=120};HazardReasons=@("Meteoroid bombardment","Micrometeor swarm","Dust-glass abrasion","Regolith shear front","Flak cloud","Live ordnance ping","Drone strafing run","Munitions detonation","Railgun graze","Torpedo strike","Asteroid impact")}
            Hyperion=@{Resources=@{Mythril=50;Nitrogen=500;Hydrogen=550;Helium=650;MetallicHydrogen=1050;Deuterium=950;"Helium-3"=450;"Bastion Fuel Cell"=15;"Bastion Shield Cell"=15;Neon=150;Argon=135;Platinum=40;Iridium=20;Uranium=200;Radium=125;Promethium=75;Neptunium=125;Plutonium=100};HazardReasons=@("Static discharge","Gravity well shear","Deep pressure crush","Hydrogen pressure inversion","Plasma lash","Photospheric blowout","Super-cyclone vortex","Gamma ray exposure","Railgun graze")}
            Cocytus=@{Resources=@{Mythril=50;Uranium=400;Radium=120;Nitrogen=800;Hydrogen=525;Helium=600;Water=200;MetallicHydrogen=800;Deuterium=650;"Helium-3"=90;Cryophane=600;"Bastion Fuel Cell"=25;"Bastion Shield Cell"=25;Neptunium=50;Promethium=35;Oxygen=100};HazardReasons=@("Extreme cold stress","Cryowake rupture","Auroral arc flash","Hydrogen pressure inversion","Railgun graze","Ring shard impact","Diamond Rain Ballistic Impact")}
            Flotsam=@{Resources=@{Iron=600;ScrapMetal=650;Copper=450;Silver=475;Gold=300;Mythril=75;Water=500;Biomass=275;Nitrogen=175;Hydrogen=175;Helium=175;MetallicHydrogen=175;Deuterium=175;Platinum=100;Tungsten=100;"Bastion Fuel Cell"=25;"Bastion Shield Cell"=25;Uranium=200;Radium=25;Nickel=200};HazardReasons=@("Static ashfall","Dust-glass abrasion","Regolith shear front","Flak cloud","Live ordnance ping","Railgun graze")}
        }
    }
    foreach($systemId in $data.Keys){
        foreach($planetName in $data[$systemId].Keys){
            $planet=$Systems[$systemId].Planets[$planetName]
            $planet.Resources=$data[$systemId][$planetName].Resources
            $planet.HazardReasons=@($data[$systemId][$planetName].HazardReasons)
        }
    }
}

function New-SystemMaster {
    $systems=@{
        Sol=[pscustomobject]@{Id="Sol";Name="The Sol System";Color="Green";StarColor="Yellow";Planets=(New-SolSystem);Order=@("Mercury","Venus","Earth","Mars","Ceres","Jupiter","Saturn","Uranus","Neptune","Pluto","Haumea","Makemake","Eris")}
        Typhon=[pscustomobject]@{Id="Typhon";Name="Typhon";Color="Blue";StarColor="Blue";Planets=(New-TyphonSystem);Order=@("Pyre","Bastion","Shrapnel","Hyperion","Cocytus","Flotsam")}
    }
    Set-ProspectingParityData $systems
    return $systems
}

function Get-RarityColor {
    param([string] $Rarity)
    switch ($Rarity) {
        "SuperCommon" { return (Get-Color DarkGray) }
        "Common" { return (Get-Color Gray) }
        "Consumable" { return (Get-Color Green) }
        "Uncommon" { return (Get-Color DarkCyan) }
        "Rare" { return (Get-Color Cyan) }
        "SuperRare" { return (Get-Color Magenta) }
        "UltraRare" { return (Get-Color DarkYellow) }
        "Artifact" { return (Get-Color DarkYellow) }
        "Oddity" { return (Get-Color White) }
        "Upgrade" { return (Get-Color DarkGreen) }
        default { return (Get-Color Gray) }
    }
}

function Draw-RarityText {
    param(
        [Drawing.Graphics] $Graphics,
        [string] $Text,
        [Drawing.Font] $Font,
        [string] $Rarity,
        [Drawing.RectangleF] $Rectangle,
        [Drawing.StringFormat] $Format = $null
    )
    if($null -eq $Format){$Format=$script:Assets.NearCenter}
    $background=switch($Rarity){"Artifact"{Get-Color DarkYellow};"Oddity"{Get-Color White};"Upgrade"{Get-Color DarkGreen};default{$null}}
    $foreground=if($null -ne $background){Get-Color Black}else{Get-RarityColor $Rarity}
    if($null -ne $background){
        $measured=$Graphics.MeasureString($Text,$Font)
        $highlightWidth=[Math]::Min($Rectangle.Width,[Math]::Ceiling($measured.Width)+2.0)
        $highlightHeight=[Math]::Min($Rectangle.Height,[Math]::Ceiling($measured.Height))
        $highlightY=$Rectangle.Y+(($Rectangle.Height-$highlightHeight)/2.0)
        Fill-RectangleColor $Graphics $background ([Drawing.RectangleF]::new($Rectangle.X,$highlightY,$highlightWidth,$highlightHeight))
    }
    Draw-Text $Graphics $Text $Font $foreground $Rectangle $Format
}

function New-HazardMaster {
    return @{
        "Hull stress"=0.75;"Micro-vibrations"=0.9;"Static discharge"=1.2;"Atmospheric turbulence"=1.4
        "Gravity well shear"=2.0;"Dust storm abrasion"=1.6;"Tectonic shift"=1.9;"Solar flare radiation"=2.5;"Acid rain corrosion"=2.7;"Extreme cold stress"=2.8;"Meteoroid bombardment"=1.4;"Micrometeor swarm"=1.7
        "Tectonic plate collapse"=3.4;"Methane pressure spike"=3.4;"Supersonic wind shear"=4.2;"Cryo-geyser eruption"=4.7;"Lightning discharge"=4.6;"Ring shard impact"=5.8;"Thermal shock cycling"=3.0;"Coronal particle surge"=3.4;"Sulfuric acid deluge"=3.1;"Runaway greenhouse pressure"=3.6;"Debris field collision"=4.8
        "Magma spray"=6.0;"Extreme Lightning discharge"=8.5;"Asteroid impact"=7.8;"Super-cyclone vortex"=9.0;"Deep pressure crush"=6.0;"Cryovolcanic ejecta"=5.5
        "Fission Event"=10.0;"Ion cannon blast"=8.0;"Magnetosphere flux storm"=12.0;"Diamond Rain Ballistic Impact"=14.2;"Gamma ray exposure"=18.0;"Critical gamma ray exposure"=30.0;"Singularity"=1000.0
        "Stray projectile"=6.0;"EMP pulse"=7.0;"Orbital mine detonation"=9.5;"Hull breach"=12.6;"Gatling barrage"=16.0;"Missile volley"=18.0;"Torpedo strike"=20.0;"Flak cloud"=11.5;"Live ordnance ping"=14.0;"Railgun graze"=16.0;"Drone strafing run"=12.0;"Munitions detonation"=24.6
        "Plasma lash"=24.0;"Photospheric blowout"=28.0;"Cryowake rupture"=17.0;"Auroral arc flash"=15.0;"Hydrogen pressure inversion"=22.0;"Basalt flood wave"=18.0;"Crustal foundering"=23.0;"Mantle plume rupture"=30.0;"Dust-glass abrasion"=7.5;"Regolith shear front"=9.4;"Static ashfall"=6.2
    }
}

$script:HazardMaster=New-HazardMaster

function Get-HazardMultiplier {
    param([string] $Reason)
    if($script:HazardMaster.ContainsKey($Reason)){return [double]$script:HazardMaster[$Reason]}
    return 1.0
}

function Get-HazardMeanDamage {
    param($Planet)
    $reasons=@($Planet.HazardReasons)
    if($reasons.Count -eq 0){$reasons=@("Hull stress")}
    $total=0.0
    foreach($reason in $reasons){
        $multiplier=Get-HazardMultiplier $reason
        foreach($baseDamage in 2..9){$total+=[int][Math]::Max(1,$baseDamage*$multiplier)}
    }
    return $total/($reasons.Count*8)
}

function Get-BaseHazard {
    param($Planet)
    $meanDamage=[Math]::Max(1.0,(Get-HazardMeanDamage $Planet))
    return [int][Math]::Min(100,[Math]::Max(1,[Math]::Ceiling(([double]$Planet.Danger*100.0)/($meanDamage*0.75))))
}

function Get-HazardEventChance {
    param([int] $EffectiveHazard)
    return [int][Math]::Min(100,[Math]::Max(0,[Math]::Floor($EffectiveHazard*0.75)))
}

function Get-PlayerUpgradeStack {
    param([string] $Flag)
    if(-not $script:G.Player.ContainsKey($Flag) -or $null -eq $script:G.Player[$Flag]){return 0}
    $value=$script:G.Player[$Flag]
    if($value -is [bool]){return $(if($value){1}else{0})}
    return [Math]::Max(0,[int]$value)
}

function Test-StackingHazardUpgrade {
    param([string] $Effect)
    return $Effect -in @("frackGas","frackIce","frackTerr","frackAst","frackDwarf")
}

function Get-EffectiveHazard {
    param($Planet)
    $hazard=[double](Get-BaseHazard $Planet)
    $baseHazard=[double]$hazard
    foreach($itemName in $script:G.ResourceMaster.Keys){
        $item=$script:G.ResourceMaster[$itemName]
        if(-not $item.ContainsKey("HazardReduction")){continue}
        $stacks=if(Test-StackingHazardUpgrade $item.Effect){Get-PlayerUpgradeStack $item.Effect}else{if((Get-PlayerUpgradeStack $item.Effect) -gt 0){1}else{0}}
        if($stacks -le 0){continue}
        if($item.HazardReduction.ContainsKey("_threshold")){
            if($baseHazard -ge [double]$item.HazardThreshold){$hazard*=1.0-[double]$item.HazardReduction["_threshold"]}
        }elseif($item.HazardReduction.ContainsKey($Planet.Type)){
            for($i=0;$i -lt $stacks;$i++){$hazard*=1.0-[double]$item.HazardReduction[$Planet.Type]}
        }
    }
    return [int][Math]::Floor($hazard)
}

function Add-InventoryItem {
    param([string] $Name,[int] $Quantity=1)
    if($Quantity -le 0){return}
    if($script:G.Inventory.ContainsKey($Name)){$script:G.Inventory[$Name]+=$Quantity}else{$script:G.Inventory[$Name]=$Quantity}
}

function Get-CurrentWeight {
    $weight = 0.0
    foreach ($name in $script:G.Inventory.Keys) {
        if ($script:G.ResourceMaster.ContainsKey($name)) {
            $weight += [double]$script:G.ResourceMaster[$name].Weight * [int]$script:G.Inventory[$name]
        }
    }
    return $weight
}

function Get-TravelFuelCost {
    param([double] $Distance)
    return [Math]::Ceiling([Math]::Abs($Distance) / 0.1)
}

function Get-Planet {
    param([string] $Name = "")
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $script:G.Player.Location }
    return $script:G.Planets[$Name]
}

function New-Starfield {
    $stars = New-ArrayList
    for ($i = 0; $i -lt 190; $i++) {
        [void]$stars.Add([pscustomobject]@{
            X = Get-RandomDouble 0 $script:VirtualWidth
            Y = Get-RandomDouble 0 $script:ViewportBottom
            Size = Get-RandomDouble 0.5 2.2
            Alpha = Get-Random -Minimum 35 -Maximum 190
            Layer = Get-RandomDouble 0.15 1.0
            Twinkle = Get-RandomDouble 0 6.283
        })
    }
    return ,$stars
}

function Reset-StarfieldCache {
    foreach($path in @($script:StarfieldPaths)){if($path -is [IDisposable]){$path.Dispose()}}
    $script:StarfieldPaths=@()
    if($null -eq $script:G){$script:TwinkleStars=@();return}
    $paths=@(
        (New-Object Drawing.Drawing2D.GraphicsPath),
        (New-Object Drawing.Drawing2D.GraphicsPath),
        (New-Object Drawing.Drawing2D.GraphicsPath)
    )
    $twinkle=New-Object System.Collections.ArrayList
    for($index=0;$index -lt $script:G.Stars.Count;$index++){
        $star=$script:G.Stars[$index]
        $bucket=if($star.Alpha -lt 85){0}elseif($star.Alpha -lt 140){1}else{2}
        $paths[$bucket].AddEllipse([single]$star.X,[single]$star.Y,[single]$star.Size,[single]$star.Size)
        if(($index%14)-eq 0 -or $star.Size -ge 2.1){[void]$twinkle.Add($star)}
    }
    $script:StarfieldPaths=$paths
    $script:TwinkleStars=@($twinkle)
}

function New-GameState {
    $systems=New-SystemMaster
    $state = @{
        Mode = "Title"
        ReturnMode = "Orbit"
        WorldMode = "Orbit"
        Player = @{
            PilotName = "Independent"
            Credits = 350
            CreditsAcquired = 0
            HP = 100.0
            MaxHP = 100.0
            Fuel = 100.0
            MaxFuel = 100.0
            MaxWeight = 100.0
            Location = "Mars"
            System = "The Sol System"
            SystemId = "Sol"
            Known = @("Sol","Typhon","Mars")
            Hyperdrive = 0
            XRFScanner = 0
            CryoSkip = 0
            AutoAdminister = 0
            RadiationSuit = 0
            frackGas = 0
            frackIce = 0
            frackTerr = 0
            frackAst = 0
            frackDwarf = 0
            TimeFracked = 0
            RealTimeFracked = 0
            TimeSlept = 0
            TimesSlept = 0
            SaveName = ""
        }
        Inventory = @{ "Fuel Cell (Small)" = 1; "Shield Cell (Small)" = 1 }
        ResourceMaster = New-ResourceMaster
        Systems = $systems
        Planets = $systems.Sol.Planets
        PlanetOrder = $systems.Sol.Order
        TraderState = @{}
        TraderRestockPoll = 1.0
        TraderRestockBoundary = Get-LocalQuarterHourBoundary
        QuestState = @{}
        GameStarted = (Get-Date)
        Stars = New-Starfield
        Particles = New-ArrayList
        Log = New-ArrayList
        Notices = New-ArrayList
        HoveredPlanet = ""
        SelectedPlanet = ""
        SelectedCargo = ""
        ConfirmTravel = $false
        SystemBlend = 0.0
        TargetSystemBlend = 0.0
        CloseZoom = 0.0
        TargetCloseZoom = 0.0
        TraderBlend = 0.0
        TargetTraderBlend = 0.0
        PanelExpand = 0.0
        TargetPanelExpand = 0.0
        Travel = $null
        FrackingActive = $false
        FrackAccumulator = 0.0
        NextFrackTick = 0.0
        FrackStartClock = 0.0
        FrackTimingCommitted = $false
        FrackElapsed = 0.0
        FrackResources = 0
        FrackDamage = 0
        FrackFuelUsed = 0.0
        FrackAutoHeal = 0
        CargoScroll = 0
        TraderScroll = 0
        TraderSellScroll = 0
        TraderBuyScroll = 0
        TradeScroll = 0
        QuestScroll = 0
        ContractRequirementScroll = 0
        SaveScroll = 0
        TraderTab = "Comms"
        TraderDialog = ""
        TraderDialogKey = ""
        TraderDialogPlanet = ""
        TradeSell = @{}
        TradeBuy = @{}
        QuantityPicker = $null
        QuantityDragging = $false
        HoldButton = $null
        SelectedQuest = ""
        ContractContext = "Log"
        ContractTab = "Active"
        SelectedSystem = ""
        SelectedSave = ""
        SaveFiles = @()
        XRFResults = @()
        ConfirmAction = $null
        DistressRemaining = 0.0
        CryoTicksRemaining = 0
        CryoActive = $false
        Shake = 0.0
        RedFlash = 0.0
        ImpactFlash = 0.0
        GreenFlash = 0.0
        CyanFlash = 0.0
        DrillVibration = $true
        DrillVibrationIntensity = 1.0
        VibrationDragging = $false
        VibrationSliderRect = [Drawing.RectangleF]::Empty
        Time = 0.0
        Notice = ""
        NoticeClock = 0.0
        InputLocked = 0.0
    }
    $script:G = $state
    Reset-StarfieldCache
}

function Add-Notice {
    param([string] $Text)
    $script:G.Notice = $Text
    $script:G.NoticeClock = 4.0
    Write-GameLog $Text
}

function Add-LogEntry {
    param([string] $Text, [Drawing.Color] $Color)
    [void]$script:G.Log.Insert(0, [pscustomobject]@{ Text=$Text; Color=$Color; Age=0.0 })
    while ($script:G.Log.Count -gt 24) { $script:G.Log.RemoveAt($script:G.Log.Count - 1) }
}

function Start-NewRun {
    New-GameState
    $script:G.Mode = "Orbit"
    $script:G.WorldMode = "Orbit"
    Add-Notice "Flight systems online. Holding Mars orbit."
}

function Open-SystemMap {
    if ($script:G.FrackingActive) {
        Add-Notice "Stop fracking before plotting a course."
        return
    }
    $script:G.Mode = "System"
    $script:G.WorldMode = "System"
    $script:G.TargetSystemBlend = 1.0
    $script:G.TargetCloseZoom = 0.0
    $script:G.TargetTraderBlend = 0.0
    $script:G.SelectedPlanet = ""
    $script:G.ConfirmTravel = $false
}

function Open-Orbit {
    if ($script:G.FrackingActive) {
        Add-Notice "Extraction is active. Stop the drill first."
        return
    }
    $script:G.Mode = "Orbit"
    $script:G.WorldMode = "Orbit"
    $script:G.TargetSystemBlend = 0.0
    $script:G.TargetCloseZoom = 0.0
    $script:G.TargetTraderBlend = 0.0
    $script:G.ConfirmTravel = $false
}

function Start-Travel {
    param([string] $Destination)
    if (-not $script:G.Planets.ContainsKey($Destination)) { return }
    $from = Get-Planet
    $to = Get-Planet $Destination
    $distance = [Math]::Abs($to.Distance - $from.Distance)
    $fuelCost = Get-TravelFuelCost $distance
    if ($Destination -eq $script:G.Player.Location) {
        Open-Orbit
        return
    }
    if ($fuelCost -gt $script:G.Player.Fuel) {
        Add-Notice ("Insufficient fuel. Need {0:0.0} FL." -f $fuelCost)
        $script:G.ConfirmTravel = $false
        return
    }
    $script:G.Player.Fuel = [Math]::Round($script:G.Player.Fuel - $fuelCost, 1)
    $script:G.Travel = [pscustomobject]@{
        From = $script:G.Player.Location
        To = $Destination
        Cost = $fuelCost
        Time = 0.0
        Duration = Get-ClampedValue (0.95 + ($distance * 0.035)) 1.1 2.8
    }
    $script:G.Mode = "Travel"
    $script:G.WorldMode = "Travel"
    $script:G.TargetSystemBlend = 0.0
    $script:G.InputLocked = $script:G.Travel.Duration
    Write-GameLog ("Departed {0} for {1}. Cost {2:0.0} FL." -f $script:G.Travel.From, $Destination, $fuelCost)
}

function Complete-Travel {
    if ($null -eq $script:G.Travel) { return }
    $destination = $script:G.Travel.To
    $script:G.Player.Location = $destination
    if($destination -notin @($script:G.Player.Known)){$script:G.Player.Known+=@($destination)}
    $script:G.Travel = $null
    $script:G.Mode = "Orbit"
    $script:G.WorldMode = "Orbit"
    $script:G.TargetSystemBlend = 0.0
    Add-Notice ("Arrived in {0} orbit." -f $destination)
}

function Start-Fracking {
    if ($script:G.FrackingActive) { return }
    if([double]$script:G.Player.Fuel -lt 0.5){Add-Notice "Fuel feed is empty. Fracking requires 0.5 FL per tick.";return}
    if((Get-CurrentWeight) -ge [double]$script:G.Player.MaxWeight){Add-Notice "Cargo hull is full. Clear space before fracking.";return}
    $script:G.FrackingActive = $true
    $script:G.Mode = "Frack"
    $script:G.WorldMode = "Frack"
    $script:G.TargetSystemBlend = 0.0
    $script:G.TargetCloseZoom = 1.0
    $script:G.TargetTraderBlend = 0.0
    $script:G.FrackAccumulator = 0.0
    $script:G.FrackStartClock=$script:Clock.Elapsed.TotalSeconds
    $script:G.NextFrackTick=$script:G.FrackStartClock+1.0
    $script:G.FrackTimingCommitted=$false
    $script:G.FrackElapsed = 0.0
    $script:G.FrackResources = 0
    $script:G.FrackDamage = 0
    $script:G.FrackFuelUsed = 0.0
    $script:G.FrackAutoHeal = 0
    $script:G.CryoActive=$false
    $script:G.CryoTicksRemaining=0
    $script:G.Log.Clear()
    Add-LogEntry ("Bore contact established at {0}." -f $script:G.Player.Location) (Get-Color Cyan)
}

function Commit-FrackRealTime {
    if($script:G.FrackTimingCommitted){return}
    $script:G.FrackElapsed=[Math]::Max(0.0,$script:Clock.Elapsed.TotalSeconds-$script:G.FrackStartClock)
    $script:G.Player.RealTimeFracked += [int][Math]::Floor($script:G.FrackElapsed)
    $script:G.FrackTimingCommitted=$true
}

function Stop-Fracking {
    if (-not $script:G.FrackingActive) { return }
    Commit-FrackRealTime
    $script:G.FrackingActive = $false
    $script:G.CryoActive=$false
    $script:G.CryoTicksRemaining=0
    $script:G.Mode = "Orbit"
    $script:G.WorldMode = "Orbit"
    $script:G.TargetCloseZoom = 0.0
    $autoText=if($script:G.FrackAutoHeal -gt 0){", +$($script:G.FrackAutoHeal) HP auto-administered"}else{""}
    Add-Notice ("Fracking stopped. +{0} resources, -{1} HP{2}." -f $script:G.FrackResources, $script:G.FrackDamage, $autoText)
}

function Get-WeightedResource {
    param($Planet)
    $total = 0
    foreach ($value in $Planet.Resources.Values) { $total += [int]$value }
    if ($total -le 0) { return $null }
    $roll = Get-Random -Minimum 1 -Maximum ($total + 1)
    $current = 0
    foreach ($entry in $Planet.Resources.GetEnumerator()) {
        $current += [int]$entry.Value
        if ($roll -le $current) { return [string]$entry.Key }
    }
    return $null
}

function Invoke-FrackTick {
    if (-not $script:G.FrackingActive) { return @{Status="Stopped";Damage=0;AutoHealed=$false} }
    $planet = Get-Planet
    if ($script:G.Player.Fuel -lt 0.5) {
        Add-LogEntry "Fuel feed exhausted." (Get-Color Red)
        Stop-Fracking
        return @{Status="Empty";Damage=0;AutoHealed=$false}
    }
    if ((Get-CurrentWeight) -ge $script:G.Player.MaxWeight) {
        Add-LogEntry "Cargo hull is full." (Get-Color Yellow)
        Stop-Fracking
        return @{Status="Full";Damage=0;AutoHealed=$false}
    }

    $script:G.Player.Fuel = [Math]::Round([Math]::Max(0.0, ([double]$script:G.Player.Fuel - 0.5)), 1)
    $script:G.FrackFuelUsed = [Math]::Round($script:G.FrackFuelUsed + 0.5,1)
    $effectiveHazard=Get-EffectiveHazard $planet
    $hazardChance=Get-HazardEventChance $effectiveHazard
    if ((Get-Random -Minimum 1 -Maximum 101) -le $hazardChance) {
        $reason=if($planet.HazardReasons){$planet.HazardReasons|Get-Random}else{"Hull stress"}
        $damage = [int][Math]::Max(1,((Get-Random -Minimum 2 -Maximum 10)*(Get-HazardMultiplier $reason)))
        $hpBeforeDamage=[Math]::Max(0,[int]$script:G.Player.HP)
        $actualDamage=[Math]::Min($damage,$hpBeforeDamage)
        $script:G.Player.HP -= $damage
        $script:G.FrackDamage += $actualDamage
        $impactShake=if($damage -ge 150){28.0}elseif($damage -ge 100){24.0}elseif($damage -ge 50){19.0}elseif($damage -ge 10){14.0}else{7.0}
        $script:G.Shake = [Math]::Max($script:G.Shake,$impactShake)
        if ($damage -ge 10) { $script:G.RedFlash = if($damage -ge 100){0.72}elseif($damage -ge 50){0.64}else{0.55} }
        if($damage -ge 100){
            $script:G.ImpactFlash=[Math]::Max($script:G.ImpactFlash,$(if($damage -ge 150){0.72}else{0.48}))
            Add-FrackImpactSparks $(if($damage -ge 150){28}else{16})
        }
        Add-LogEntry ("-{0} HP  {1}" -f $damage, $reason) (Get-Color Red)
        $autoHealed=$false
        if ($script:G.Player.HP -le 0) {
            $autoHealed=Invoke-AutoAdminister
            if(-not $autoHealed){
                $script:G.Player.HP = 0
                $script:G.FrackingActive = $false
                $script:G.CryoActive=$false
                Commit-FrackRealTime
                $script:G.Mode = "Death"
                $script:G.WorldMode = "Frack"
                return @{Status="Death";Damage=$damage;AutoHealed=$false}
            }
        }
        return @{Status="Continue";Damage=$damage;AutoHealed=$autoHealed}
    }

    $resource = Get-WeightedResource $planet
    if ($null -eq $resource) { return @{Status="Continue";Damage=0;AutoHealed=$false} }
    $item = $script:G.ResourceMaster[$resource]
    if ($script:G.Inventory.ContainsKey($resource)) { $script:G.Inventory[$resource]++ }
    else { $script:G.Inventory[$resource] = 1 }
    $script:G.FrackResources++
    Add-LogEntry ("+1 {0}" -f $resource) (Get-RarityColor $item.Rarity)
    if(-not $script:G.CryoActive){
        for ($i = 0; $i -lt 5; $i++) {
            [void]$script:G.Particles.Add([pscustomobject]@{
                Kind = "Debris"
                X = 640.0 + (Get-RandomDouble -18 18)
                Y = 162.0 + (Get-RandomDouble -8 8)
                VX = Get-RandomDouble -85 85
                VY = Get-RandomDouble -120 -35
                Life = Get-RandomDouble 0.35 0.8
                MaxLife = 0.8
                Color = Get-RarityColor $item.Rarity
                Size = Get-RandomDouble 2 5
            })
        }
    }
    return @{Status="Continue";Damage=0;AutoHealed=$false}
}

function Add-FrackImpactSparks {
    param([int] $Count)
    if($script:G.CryoActive){return}
    $originX=Get-RandomDouble 250 1030
    for($i=0;$i -lt $Count;$i++){
        $life=Get-RandomDouble 0.24 0.62
        [void]$script:G.Particles.Add([pscustomobject]@{
            Kind = "Spark"
            X = $originX + (Get-RandomDouble -45 45)
            Y = Get-RandomDouble 376 402
            VX = Get-RandomDouble -150 150
            VY = Get-RandomDouble -260 -85
            Life = $life
            MaxLife = $life
            Color = $(if(($i % 4) -eq 0){Get-Color White}else{Get-Color Yellow})
            Size = Get-RandomDouble 1.2 2.8
        })
    }
}

function Use-CargoItem {
    param([string] $Name)
    if (-not $script:G.Inventory.ContainsKey($Name)) { return }
    $item = $script:G.ResourceMaster[$Name]
    if (-not $item.ContainsKey("Effect")) {
        Add-Notice "$Name is raw cargo."
        return
    }
    if ($item.Effect -eq "HP") {
        if ($script:G.Player.HP -ge $script:G.Player.MaxHP) { Add-Notice "Hull is already at maximum."; return }
        $script:G.Player.HP = [Math]::Min($script:G.Player.MaxHP, $script:G.Player.HP + $item.EffectValue)
    }
    elseif ($item.Effect -eq "Fuel") {
        if ($script:G.Player.Fuel -ge $script:G.Player.MaxFuel) { Add-Notice "Fuel tanks are already full."; return }
        $script:G.Player.Fuel = [Math]::Min($script:G.Player.MaxFuel, $script:G.Player.Fuel + $item.EffectValue)
    }
    elseif($item.Effect -eq "MaxHP"){
        $script:G.Player.MaxHP=[double]$script:G.Player.MaxHP+[double]$item.EffectValue
        $script:G.Player.HP=[double]$script:G.Player.HP+[double]$item.EffectValue
    }
    elseif($item.Effect -eq "MaxFuel"){
        $script:G.Player.MaxFuel=[Math]::Round([double]$script:G.Player.MaxFuel+[double]$item.EffectValue,1)
        $script:G.Player.Fuel=[Math]::Round([double]$script:G.Player.Fuel+[double]$item.EffectValue,1)
    }
    elseif($item.Effect -eq "MaxWeight"){
        $script:G.Player.MaxWeight=[double]$script:G.Player.MaxWeight+[double]$item.EffectValue
    }
    elseif($item.Effect -in @("frackGas","frackIce","frackTerr","frackAst","frackDwarf")){
        $script:G.Player[$item.Effect]=[int]$script:G.Player[$item.Effect]+1
    }
    else{$script:G.Player[$item.Effect]=1}
    if ($script:G.Inventory[$Name] -le 1) { $script:G.Inventory.Remove($Name) }
    else { $script:G.Inventory[$Name]-- }
    Add-Notice ("Used {0}." -f $Name)
    if (-not $script:G.Inventory.ContainsKey($Name)) { $script:G.SelectedCargo = "" }
}

function Jettison-CargoItem {
    param([string] $Name)
    if (-not $script:G.Inventory.ContainsKey($Name)) { return }
    $maximum=[int]$script:G.Inventory[$Name]
    if($maximum -le 1){Jettison-CargoQuantity $Name 1}
    else{Open-JettisonQuantityPicker $Name $maximum}
}

function Jettison-CargoQuantity {
    param([string] $Name,[int] $Quantity)
    if(-not $script:G.Inventory.ContainsKey($Name)){return}
    $quantity=[int](Get-ClampedValue $Quantity 1 ([int]$script:G.Inventory[$Name]))
    if($script:G.Inventory[$Name] -le $quantity){$script:G.Inventory.Remove($Name)}else{$script:G.Inventory[$Name]-=$quantity}
    Add-Notice ("Jettisoned {0} unit(s) of {1}." -f $quantity,$Name)
    if (-not $script:G.Inventory.ContainsKey($Name)) { $script:G.SelectedCargo = "" }
}

function Open-Cargo {
    if ($script:G.Mode -ne "Cargo") { $script:G.ReturnMode = $script:G.Mode }
    $script:G.Mode = "Cargo"
    if ($script:G.FrackingActive) {
        $script:G.WorldMode = "Frack"
        $script:G.TargetCloseZoom = 1.0
    }
}

function Close-Cargo {
    if ($script:G.FrackingActive) {
        $script:G.Mode = "Frack"
        $script:G.WorldMode = "Frack"
    }
    else {
        $script:G.Mode = if ($script:G.ReturnMode -in @("Orbit", "System", "Trader")) { $script:G.ReturnMode } else { "Orbit" }
        $script:G.WorldMode = $script:G.Mode
    }
}

function Get-TraderDialogLine {
    param($Planet,[string] $Key,[switch] $First)
    if($null -eq $Planet -or $null -eq $Planet.Dialog -or -not $Planet.Dialog.ContainsKey($Key)){return ""}
    $lines=@($Planet.Dialog[$Key])
    if($lines.Count -eq 0){return ""}
    if($First -or $lines.Count -eq 1){return [string]$lines[0]}
    return [string]($lines|Get-Random)
}

function Set-TraderDialog {
    param([string] $Key,[switch] $First)
    $planet=Get-Planet
    $line=Get-TraderDialogLine $planet $Key -First:$First
    $script:G.TraderDialog=$line
    $script:G.TraderDialogKey=$Key
    $script:G.TraderDialogPlanet=[string]$planet.Name
    return $line
}

function Get-ActiveTraderDialog {
    param([string] $DefaultKey="Greeting")
    $planet=Get-Planet
    $validKeys=if($DefaultKey -eq "TradeGreeting"){@("TradeGreeting","Trade","Frustrated","InsufficientFunds","InsufficientFundsTrader")}else{@("Greeting","Repair","Refuel","Frustrated","InsufficientFunds")}
    if([string]::IsNullOrWhiteSpace($script:G.TraderDialog) -or $script:G.TraderDialogPlanet -ne $planet.Name -or $script:G.TraderDialogKey -notin $validKeys){[void](Set-TraderDialog $DefaultKey -First)}
    return [string]$script:G.TraderDialog
}

function Set-TraderGreetingDialog {
    $planet=Get-Planet
    $factionKey="Trader:$($planet.TraderName)"
    $firstContact=-not (@($script:G.Player.Known) -contains $factionKey)
    [void](Set-TraderDialog "Greeting" -First:$firstContact)
    if($firstContact){$script:G.Player.Known=@($script:G.Player.Known)+$factionKey}
}

function Set-TraderTab {
    param([string] $Tab)
    $script:G.TraderTab=$Tab
    $script:G.TraderScroll=0
    $script:G.QuantityPicker=$null
    if($Tab -eq "Trade"){[void](Set-TraderDialog "TradeGreeting")}
    elseif($Tab -eq "Comms"){[void](Set-TraderDialog "Greeting")}
}

function Open-Trader {
    $planet = Get-Planet
    if (-not $planet.Inhabited) { Add-Notice "No inhabited station responds."; return }
    if ($script:G.FrackingActive) { Add-Notice "Stop fracking before opening comms."; return }
    $script:G.Mode = "Trader"
    $script:G.WorldMode = "Trader"
    $script:G.TargetTraderBlend = 1.0
    $script:G.TargetCloseZoom = 0.0
    Clear-TradeLedger
    $script:G.TraderTab = "Comms"
    Set-TraderGreetingDialog
}

function Close-Trader {
    Clear-TradeLedger
    $script:G.Mode = "Orbit"
    $script:G.WorldMode = "Orbit"
    $script:G.TargetTraderBlend = 0.0
}

function Invoke-Repair {
    $planet = Get-Planet
    $trader=Get-CurrentTraderState
    $missing = $script:G.Player.MaxHP - $script:G.Player.HP
    $modifier=if($null -ne $planet.RepairModifier){[double]$planet.RepairModifier}else{1.2}
    $cost = [int][Math]::Ceiling($missing * $modifier)
    if($missing -le 0){[void](Set-TraderDialog "Frustrated");Add-Notice "Hull reports nominal.";return}
    if($script:G.Player.Credits -ge $cost){
        $script:G.Player.Credits-=$cost;$trader.Credits+=$cost;$script:G.Player.HP=$script:G.Player.MaxHP
        [void](Set-TraderDialog "Repair");Add-Notice ("{0} completed hull repairs for {1} CD." -f $planet.TraderName,$cost);return
    }
    if($script:G.Player.Credits -le 0){[void](Set-TraderDialog "InsufficientFunds");Add-Notice "Insufficient credits for repairs.";return}
    $repairableHP=[int][Math]::Floor([double]$script:G.Player.Credits/$modifier)
    if($repairableHP -le 0){[void](Set-TraderDialog "InsufficientFunds");Add-Notice "Insufficient credits for repairs.";return}
    $spent=[int]$script:G.Player.Credits;$script:G.Player.Credits=0;$trader.Credits+=$spent
    $script:G.Player.HP=[Math]::Min($script:G.Player.MaxHP,$script:G.Player.HP+$repairableHP)
    [void](Set-TraderDialog "Repair");Add-Notice ("{0} completed partial hull repairs for {1} CD." -f $planet.TraderName,$spent)
}

function Invoke-Refuel {
    $planet = Get-Planet
    $trader=Get-CurrentTraderState
    $missing = $script:G.Player.MaxFuel - $script:G.Player.Fuel
    $modifier=if($null -ne $planet.FuelModifier){[double]$planet.FuelModifier}else{1.1}
    $cost = [int][Math]::Ceiling($missing * 3.0 * $modifier)
    if($missing -le 0){[void](Set-TraderDialog "Frustrated");Add-Notice "Fuel tanks report full.";return}
    if($script:G.Player.Credits -ge $cost){
        $script:G.Player.Credits-=$cost;$trader.Credits+=$cost;$script:G.Player.Fuel=$script:G.Player.MaxFuel
        [void](Set-TraderDialog "Refuel");Add-Notice ("{0} transferred fuel for {1} CD." -f $planet.TraderName,$cost);return
    }
    if($script:G.Player.Credits -le 0){[void](Set-TraderDialog "InsufficientFunds");Add-Notice "Insufficient credits for fuel.";return}
    $unitPrice=3.0*$modifier
    $affordableFuel=[Math]::Floor(([double]$script:G.Player.Credits/$unitPrice)*10.0)/10.0
    $affordableFuel=[Math]::Min([double]$missing,[double]$affordableFuel)
    if($affordableFuel -le 0){[void](Set-TraderDialog "InsufficientFunds");Add-Notice "Insufficient credits for fuel.";return}
    $spent=[int]$script:G.Player.Credits;$script:G.Player.Credits=0;$trader.Credits+=$spent
    $script:G.Player.Fuel=[Math]::Round([Math]::Min([double]$script:G.Player.MaxFuel,[double]$script:G.Player.Fuel+$affordableFuel),1)
    [void](Set-TraderDialog "Refuel");Add-Notice ("{0} transferred partial fuel for {1} CD." -f $planet.TraderName,$spent)
}

function Buy-Supply {
    param([string] $Name)
    $trader=Get-CurrentTraderState
    if($null -eq $trader -or -not $trader.Stock.ContainsKey($Name) -or [int]$trader.Stock[$Name] -le 0){Add-Notice "Item is out of stock.";return}
    $item = $script:G.ResourceMaster[$Name]
    if ($script:G.Player.Credits -lt $item.Value) { Add-Notice "Insufficient credits."; return }
    if ((Get-CurrentWeight) + $item.Weight -gt $script:G.Player.MaxWeight) { Add-Notice "Cargo hold has no room."; return }
    $script:G.Player.Credits -= $item.Value
    Add-InventoryItem $Name 1
    $trader.Stock[$Name]--
    $trader.Credits+=[int]$item.Value
    Add-Notice ("Purchased {0} for {1} CD." -f $Name, $item.Value)
}

function Sell-Cargo {
    param([string] $Name)
    if (-not $script:G.Inventory.ContainsKey($Name)) { return }
    $item = $script:G.ResourceMaster[$Name]
    $value = [int][Math]::Floor($item.Value * 0.69)
    $trader=Get-CurrentTraderState
    if($null -eq $trader -or $trader.Credits -lt $value){Add-Notice "Trader budget cannot cover that item.";return}
    $script:G.Player.Credits += $value
    $script:G.Player.CreditsAcquired += $value
    $trader.Credits-=$value
    if($trader.Stock.ContainsKey($Name)){$trader.Stock[$Name]++}else{$trader.Stock[$Name]=1}
    if ($script:G.Inventory[$Name] -le 1) { $script:G.Inventory.Remove($Name) } else { $script:G.Inventory[$Name]-- }
    Add-Notice ("Sold one {0} for {1} CD." -f $Name, $value)
}

function Get-QuestCargoLabel {
    param([string] $Name,[int] $Quantity,[hashtable] $Requirements)
    if($null -eq $Requirements){$Requirements=Get-ActiveQuestRequirements}
    if(-not $Requirements.ContainsKey($Name)){return $Name}
    $reserved=[int]$Requirements[$Name]
    if($Quantity -gt $reserved){return ("{0}*({1})" -f $Name,$reserved)}
    return ($Name+"*")
}

function Add-TraderPurchaseStock {
    param($Trader,[string] $Name,[int] $Quantity)
    if($Trader.Stock.ContainsKey($Name)){$Trader.Stock[$Name]+=$Quantity}else{$Trader.Stock[$Name]=$Quantity}
}

function Sell-NonQuestCargo {
    $trader=Get-CurrentTraderState;if($null -eq $trader){return}
    $requirements=Get-ActiveQuestRequirements;$sold=0;$credits=0
    foreach($name in @($script:G.Inventory.Keys)){
        $item=$script:G.ResourceMaster[$name]
        if($item.Rarity -in @("Consumable","Upgrade","UltraRare","Artifact","Oddity")){continue}
        $owned=[int]$script:G.Inventory[$name];$reserved=if($requirements.ContainsKey($name)){[int]$requirements[$name]}else{0};$sellable=[Math]::Max(0,$owned-$reserved)
        $unit=[int][Math]::Floor($item.Value*0.69);if($sellable -le 0 -or $unit -le 0){continue}
        $quantity=[Math]::Min($sellable,[int][Math]::Floor($trader.Credits/$unit));if($quantity -le 0){continue}
        $total=$quantity*$unit;$script:G.Player.Credits+=$total;$script:G.Player.CreditsAcquired+=$total;$trader.Credits-=$total;Add-TraderPurchaseStock $trader $name $quantity
        if($owned -le $quantity){$script:G.Inventory.Remove($name)}else{$script:G.Inventory[$name]-=$quantity};$sold+=$quantity;$credits+=$total
    }
    Add-Notice $(if($sold -gt 0){"Sold $sold non-quest resource items for $credits CD."}else{"No non-quest resources can be sold."})
}

function Sell-QuestSurplus {
    $trader=Get-CurrentTraderState;if($null -eq $trader){return}
    $requirements=Get-ActiveQuestRequirements;$sold=0;$credits=0
    foreach($name in @($requirements.Keys)){
        if(-not $script:G.Inventory.ContainsKey($name)){continue};$item=$script:G.ResourceMaster[$name]
        if($item.Rarity -in @("Consumable","Upgrade")){continue}
        $owned=[int]$script:G.Inventory[$name];$sellable=[Math]::Max(0,$owned-[int]$requirements[$name]);$unit=[int][Math]::Floor($item.Value*0.69)
        if($sellable -le 0 -or $unit -le 0){continue};$quantity=[Math]::Min($sellable,[int][Math]::Floor($trader.Credits/$unit));if($quantity -le 0){continue}
        $total=$quantity*$unit;$script:G.Player.Credits+=$total;$script:G.Player.CreditsAcquired+=$total;$trader.Credits-=$total;Add-TraderPurchaseStock $trader $name $quantity
        if($owned -le $quantity){$script:G.Inventory.Remove($name)}else{$script:G.Inventory[$name]-=$quantity};$sold+=$quantity;$credits+=$total
    }
    Add-Notice $(if($sold -gt 0){"Sold $sold surplus contract items for $credits CD."}else{"No surplus contract items can be sold."})
}

function Invoke-AutoAdminister {
    if([int]$script:G.Player.AutoAdminister -le 0){return $false}
    while($script:G.Player.HP -le 0){
        $cells=@($script:G.Inventory.Keys|ForEach-Object{
            $name=$_;$item=$script:G.ResourceMaster[$name]
            if($item.ContainsKey("Effect") -and $item.Effect -eq "HP"){[pscustomobject]@{Name=$name;EffectValue=[int]$item.EffectValue;Value=[int]$item.Value}}
        }|Sort-Object EffectValue,Value,Name)
        if($cells.Count -eq 0){return $false}
        $selected=$cells[0];$before=[Math]::Max(0,[int]$script:G.Player.HP)
        $script:G.Player.HP=[Math]::Min($script:G.Player.MaxHP,$before+$selected.EffectValue)
        $restored=[int]($script:G.Player.HP-$before);$script:G.FrackAutoHeal+=$restored
        if($script:G.Inventory[$selected.Name] -le 1){$script:G.Inventory.Remove($selected.Name)}else{$script:G.Inventory[$selected.Name]--}
        Add-LogEntry ("AUTO-INJECT  {0}" -f $selected.Name) (Get-Color Green)
    }
    $script:G.RedFlash=0.0;$script:G.GreenFlash=0.55
    return $true
}

function Get-TraderKey {
    return ("{0}|{1}" -f $script:G.Player.SystemId,$script:G.Player.Location)
}

function New-TraderStock {
    param([hashtable] $Rules)
    $stock=@{}
    if($null -eq $Rules){return $stock}
    foreach($name in $Rules.Keys){
        $rule=$Rules[$name]
        if(-not ($rule -is [System.Collections.IDictionary])){
            $quantity=[int]$rule
            if($quantity -gt 0){$stock[$name]=$quantity}
            continue
        }
        $chance=if($rule.ContainsKey("Chance")){[int]$rule.Chance}else{100}
        if($chance -lt 0){$chance=0}elseif($chance -gt 100){$chance=100}
        if((Get-Random -Minimum 1 -Maximum 101) -gt $chance){continue}
        $minQty=if($rule.ContainsKey("MinQty")){[int]$rule.MinQty}else{1}
        $maxQty=if($rule.ContainsKey("MaxQty")){[int]$rule.MaxQty}else{$minQty}
        if($maxQty -lt $minQty){$swap=$minQty;$minQty=$maxQty;$maxQty=$swap}
        $quantity=Get-Random -Minimum $minQty -Maximum ($maxQty+1)
        $doubleChance=if($rule.ContainsKey("DoubleChance")){[int]$rule.DoubleChance}else{0}
        if($doubleChance -lt 0){$doubleChance=0}elseif($doubleChance -gt 100){$doubleChance=100}
        if($doubleChance -gt 0 -and (Get-Random -Minimum 1 -Maximum 101) -le $doubleChance){$quantity++}
        if($quantity -gt 0){$stock[$name]=$quantity}
    }
    return $stock
}

function Get-LocalQuarterHourBoundary {
    param([datetime] $Now=(Get-Date))
    if($Now.Kind -eq [DateTimeKind]::Utc){$Now=$Now.ToLocalTime()}
    $minute=[int]([Math]::Floor($Now.Minute/15.0)*15)
    return $Now.Date.AddHours($Now.Hour).AddMinutes($minute)
}

function Get-NextLocalQuarterHour {
    param([datetime] $Now=(Get-Date))
    return (Get-LocalQuarterHourBoundary $Now).AddMinutes(15)
}

function ConvertTo-LocalTraderTime {
    param($Value)
    if($null -eq $Value){return $null}
    if($Value -is [datetimeoffset]){return ([datetimeoffset]$Value).LocalDateTime}
    if($Value -is [datetime]){
        $date=[datetime]$Value
        if($date.Kind -eq [DateTimeKind]::Utc){return $date.ToLocalTime()}
        if($date.Kind -eq [DateTimeKind]::Local){return $date}
        return [datetime]::SpecifyKind($date,[DateTimeKind]::Local)
    }
    if($Value -is [System.Collections.IDictionary]){
        if($Value.Contains("value")){return ConvertTo-LocalTraderTime $Value["value"]}
        if($Value.Contains("DateTime")){return ConvertTo-LocalTraderTime $Value["DateTime"]}
        return $null
    }
    $text=[string]$Value
    if($text -match '^/Date\((-?\d+)(?:[+-]\d{4})?\)/$'){
        try{return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$matches[1]).LocalDateTime}catch{return $null}
    }
    try{
        $parsed=[DateTimeOffset]::Parse($text,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
        return $parsed.LocalDateTime
    }catch{}
    try{
        $date=[datetime]::Parse($text)
        if($date.Kind -eq [DateTimeKind]::Utc){return $date.ToLocalTime()}
        if($date.Kind -eq [DateTimeKind]::Local){return $date}
        return [datetime]::SpecifyKind($date,[DateTimeKind]::Local)
    }catch{return $null}
}

function Reset-TraderStateRecord {
    param($State,$Planet,[datetime] $Boundary)
    $State.Stock=New-TraderStock $Planet.TraderStockRules
    $State.Credits=[int]$Planet.TraderCredits
    $State.LastRestock=[datetime]::SpecifyKind($Boundary,[DateTimeKind]::Local)
}

function Update-TraderStateRecord {
    param($State,$Planet,[datetime] $Boundary)
    if(-not $State.ContainsKey("LastRestock") -and $State.ContainsKey("LastTrade")){$State.LastRestock=$State.LastTrade}
    $last=if($State.ContainsKey("LastRestock")){ConvertTo-LocalTraderTime $State.LastRestock}else{$null}
    if($null -eq $last -or $last -lt $Boundary -or $last -gt $Boundary){
        Reset-TraderStateRecord $State $Planet $Boundary
        return $true
    }
    $State.LastRestock=$last
    return $false
}

function Reset-TradeSelection {
    $script:G.TradeSell=@{};$script:G.TradeBuy=@{};$script:G.TradeScroll=0;$script:G.TraderSellScroll=0;$script:G.TraderBuyScroll=0
    $script:G.QuantityPicker=$null;$script:G.QuantityDragging=$false
}

function Refresh-DueTraderStates {
    param([datetime] $Now=(Get-Date))
    $boundary=Get-LocalQuarterHourBoundary $Now
    $refreshed=New-ArrayList
    foreach($systemId in @($script:G.Systems.Keys)){
        $system=$script:G.Systems[$systemId]
        foreach($planetName in @($system.Order)){
            $planet=$system.Planets[$planetName]
            if(-not $planet.Inhabited){continue}
            $key=("{0}|{1}" -f $systemId,$planetName)
            $legacyKey=[string]$planetName
            if(-not $script:G.TraderState.ContainsKey($key) -and $script:G.TraderState.ContainsKey($legacyKey)){
                $script:G.TraderState[$key]=$script:G.TraderState[$legacyKey]
                $script:G.TraderState.Remove($legacyKey)
            }
            if($script:G.TraderState.ContainsKey($key) -and (Update-TraderStateRecord $script:G.TraderState[$key] $planet $boundary)){
                [void]$refreshed.Add($key)
            }
        }
    }
    if($refreshed.Count -gt 0){Reset-TradeSelection}
    return @($refreshed)
}

function Initialize-TraderState {
    param([datetime] $Now=(Get-Date))
    $planet=Get-Planet
    if(-not $planet.Inhabited){return $null}
    $key=Get-TraderKey
    $legacyKey=[string]$planet.Name
    if(-not $script:G.TraderState.ContainsKey($key) -and $script:G.TraderState.ContainsKey($legacyKey)){
        $script:G.TraderState[$key]=$script:G.TraderState[$legacyKey]
        $script:G.TraderState.Remove($legacyKey)
    }
    $boundary=Get-LocalQuarterHourBoundary $Now
    $needsRefresh=-not $script:G.TraderState.ContainsKey($key)
    if($needsRefresh){
        $script:G.TraderState[$key]=@{Stock=@{};Credits=0;LastRestock=$boundary}
        Reset-TraderStateRecord $script:G.TraderState[$key] $planet $boundary
    }else{$needsRefresh=Update-TraderStateRecord $script:G.TraderState[$key] $planet $boundary}
    if($needsRefresh){Reset-TradeSelection}
    return $script:G.TraderState[$key]
}

function Get-CurrentTraderState {
    $planet=Get-Planet
    if(-not $planet.Inhabited){return $null}
    return Initialize-TraderState
}

function Get-TraderStockRows {
    $state=Get-CurrentTraderState
    if($null -eq $state){return @()}
    return @($state.Stock.Keys|Where-Object{[int]$state.Stock[$_] -gt 0}|ForEach-Object{[pscustomobject]@{Name=$_;Quantity=[int]$state.Stock[$_];Item=$script:G.ResourceMaster[$_]}}|Sort-Object @{Expression={if($script:RaritySortOrder.ContainsKey($_.Item.Rarity)){$script:RaritySortOrder[$_.Item.Rarity]}else{99}}},Name)
}

function Clear-TradeLedger {
    Reset-TradeSelection
}

function Get-TradePendingQuantity {
    param([string] $Side,[string] $Name)
    $ledger=if($Side -eq "Sell"){$script:G.TradeSell}else{$script:G.TradeBuy}
    if($ledger.ContainsKey($Name)){return [int]$ledger[$Name]}
    return 0
}

function Get-TradeAvailableQuantity {
    param([string] $Side,[string] $Name)
    $pending=Get-TradePendingQuantity $Side $Name
    if($Side -eq "Sell"){
        $owned=if($script:G.Inventory.ContainsKey($Name)){[int]$script:G.Inventory[$Name]}else{0}
        return [Math]::Max(0,$owned-$pending)
    }
    $trader=Get-CurrentTraderState
    $stock=if($null -ne $trader -and $trader.Stock.ContainsKey($Name)){[int]$trader.Stock[$Name]}else{0}
    return [Math]::Max(0,$stock-$pending)
}

function Add-TradeItem {
    param([string] $Side,[string] $Name,[int] $Quantity=1)
    if($Quantity -le 0 -or -not $script:G.ResourceMaster.ContainsKey($Name)){return 0}
    $available=Get-TradeAvailableQuantity $Side $Name;$add=[Math]::Min($Quantity,$available);if($add -le 0){return 0}
    $ledger=if($Side -eq "Sell"){$script:G.TradeSell}else{$script:G.TradeBuy}
    if($ledger.ContainsKey($Name)){$ledger[$Name]+=$add}else{$ledger[$Name]=$add}
    return $add
}

function Remove-TradeItem {
    param([string] $Side,[string] $Name,[int] $Quantity=1)
    $ledger=if($Side -eq "Sell"){$script:G.TradeSell}else{$script:G.TradeBuy}
    if($Quantity -le 0 -or -not $ledger.ContainsKey($Name)){return 0}
    $remove=[Math]::Min($Quantity,[int]$ledger[$Name]);$ledger[$Name]-=$remove;if($ledger[$Name] -le 0){$ledger.Remove($Name)}
    return $remove
}

function Get-PendingTradeRows {
    $rows=@()
    foreach($name in $script:G.TradeSell.Keys){$item=$script:G.ResourceMaster[$name];$rows+=,[pscustomobject]@{Side="Sell";Name=$name;Quantity=[int]$script:G.TradeSell[$name];Item=$item;Amount=([int][Math]::Floor($item.Value*0.69)*[int]$script:G.TradeSell[$name])}}
    foreach($name in $script:G.TradeBuy.Keys){$item=$script:G.ResourceMaster[$name];$rows+=,[pscustomobject]@{Side="Buy";Name=$name;Quantity=[int]$script:G.TradeBuy[$name];Item=$item;Amount=([int]$item.Value*[int]$script:G.TradeBuy[$name])}}
    return @($rows|Sort-Object Side,Name)
}

function Get-TradeTotals {
    $trader=Get-CurrentTraderState;$sellTotal=0;$buyTotal=0;$weightAfter=[double](Get-CurrentWeight);$valid=$true;$reason="";$failureDialog="Frustrated"
    foreach($name in @($script:G.TradeSell.Keys)){
        $quantity=[int]$script:G.TradeSell[$name];$owned=if($script:G.Inventory.ContainsKey($name)){[int]$script:G.Inventory[$name]}else{0};$item=$script:G.ResourceMaster[$name]
        if($quantity -le 0 -or $quantity -gt $owned){$valid=$false;$reason="Cargo availability changed.";break}
        $sellTotal+=[int][Math]::Floor($item.Value*0.69)*$quantity;$weightAfter-=[double]$item.Weight*$quantity
    }
    if($valid){foreach($name in @($script:G.TradeBuy.Keys)){
        $quantity=[int]$script:G.TradeBuy[$name];$stock=if($null -ne $trader -and $trader.Stock.ContainsKey($name)){[int]$trader.Stock[$name]}else{0};$item=$script:G.ResourceMaster[$name]
        if($quantity -le 0 -or $quantity -gt $stock){$valid=$false;$reason="Trader stock changed.";break}
        $buyTotal+=[int]$item.Value*$quantity;$weightAfter+=[double]$item.Weight*$quantity
    }}
    $net=$sellTotal-$buyTotal;$playerAfter=[int]$script:G.Player.Credits+$net;$traderAfter=if($null -ne $trader){[int]$trader.Credits-$net}else{-1};$hasItems=($script:G.TradeSell.Count+$script:G.TradeBuy.Count) -gt 0
    if($valid -and -not $hasItems){$valid=$false;$reason="No items staged."}
    elseif($valid -and $playerAfter -lt 0){$valid=$false;$reason="Pilot cannot afford this trade.";$failureDialog="InsufficientFunds"}
    elseif($valid -and $traderAfter -lt 0){$valid=$false;$reason="Trader cannot afford this trade.";$failureDialog="InsufficientFundsTrader"}
    elseif($valid -and $weightAfter -gt [double]$script:G.Player.MaxWeight){$valid=$false;$reason="Trade exceeds cargo capacity."}
    return [pscustomobject]@{SellTotal=$sellTotal;BuyTotal=$buyTotal;Net=$net;PlayerAfter=$playerAfter;TraderAfter=$traderAfter;WeightAfter=$weightAfter;CanTrade=$valid;Reason=$reason;HasItems=$hasItems;FailureDialog=$failureDialog}
}

function Commit-Trade {
    $trader=Get-CurrentTraderState;$totals=Get-TradeTotals
    if($null -eq $trader -or -not $totals.CanTrade){
        $dialogKey=if($null -ne $totals -and -not [string]::IsNullOrWhiteSpace($totals.FailureDialog)){[string]$totals.FailureDialog}else{"Frustrated"}
        [void](Set-TraderDialog $dialogKey);Add-Notice $(if([string]::IsNullOrWhiteSpace($totals.Reason)){"Trade request rejected."}else{$totals.Reason});return
    }
    foreach($name in @($script:G.TradeSell.Keys)){
        $quantity=[int]$script:G.TradeSell[$name];if($script:G.Inventory[$name] -le $quantity){$script:G.Inventory.Remove($name)}else{$script:G.Inventory[$name]-=$quantity};Add-TraderPurchaseStock $trader $name $quantity
    }
    foreach($name in @($script:G.TradeBuy.Keys)){
        $quantity=[int]$script:G.TradeBuy[$name];$trader.Stock[$name]-=$quantity;if($trader.Stock[$name] -le 0){$trader.Stock.Remove($name)};Add-InventoryItem $name $quantity
    }
    $script:G.Player.Credits=$totals.PlayerAfter;$script:G.Player.CreditsAcquired+=$totals.SellTotal;$trader.Credits=$totals.TraderAfter
    $summary=if($totals.Net -ge 0){"+$($totals.Net) CD"}else{"$($totals.Net) CD"};Clear-TradeLedger;[void](Set-TraderDialog "Trade");Add-Notice ("Trade complete. Net {0}." -f $summary)
}

function Test-QuickSellEligibleItem {
    param([hashtable] $Item)
    if($null -eq $Item -or $Item.ContainsKey("Effect")){return $false}
    return [string]$Item.Rarity -notin @("Consumable","Upgrade","UltraRare","Artifact","Oddity")
}

function Stage-QuickSell {
    $trader=Get-CurrentTraderState
    if($null -eq $trader){return}
    $requirements=Get-ActiveQuestRequirements;$staged=0;$alreadyCommitted=0
    foreach($name in @($script:G.TradeSell.Keys)){$alreadyCommitted+=[int][Math]::Floor($script:G.ResourceMaster[$name].Value*0.69)*[int]$script:G.TradeSell[$name]}
    $remainingBudget=[Math]::Max(0,[int]$trader.Credits-$alreadyCommitted)
    foreach($row in @(Get-SortedCargo)){
        $name=$row.Name
        $item=$script:G.ResourceMaster[$name];if(-not (Test-QuickSellEligibleItem $item)){continue}
        $owned=[int]$script:G.Inventory[$name];$reserved=if($requirements.ContainsKey($name)){[int]$requirements[$name]}else{0};$sellable=[Math]::Max(0,$owned-$reserved)
        $current=Get-TradePendingQuantity "Sell" $name;$unit=[int][Math]::Floor($item.Value*0.69)
        if($unit -le 0 -or $sellable -le $current -or $remainingBudget -lt $unit){continue}
        $quantity=[Math]::Min($sellable-$current,[int][Math]::Floor($remainingBudget/$unit))
        if($quantity -gt 0){$added=Add-TradeItem "Sell" $name $quantity;$staged+=$added;$remainingBudget-=$added*$unit}
    }
    Add-Notice $(if($staged -gt 0){"Staged $staged quest-safe resource items within trader budget."}elseif($remainingBudget -le 0){"Trader budget is already fully committed."}else{"No additional quest-safe resources to stage."})
}

function Open-TradeQuantityPicker {
    param([string] $Side,[string] $Name,[string] $Direction,[int] $Maximum)
    if($Maximum -le 0){return}
    $unit=if($Side -eq "Sell"){[int][Math]::Floor($script:G.ResourceMaster[$Name].Value*0.69)}else{[int]$script:G.ResourceMaster[$Name].Value}
    $sign=if(($Direction -eq "Add" -and $Side -eq "Sell") -or ($Direction -eq "Remove" -and $Side -eq "Buy")){1}else{-1}
    $script:G.QuantityPicker=[pscustomobject]@{Purpose="Trade";Side=$Side;Name=$Name;Direction=$Direction;Maximum=$Maximum;Value=1;Input="";TypingStarted=$false;UnitValue=$unit;ValueSign=$sign;SliderRect=[Drawing.RectangleF]::Empty}
    $script:G.QuantityDragging=$false
}

function Open-JettisonQuantityPicker {
    param([string] $Name,[int] $Maximum)
    if($Maximum -le 0){return}
    $unit=[int]$script:G.ResourceMaster[$Name].Value
    $script:G.QuantityPicker=[pscustomobject]@{Purpose="Jettison";Side="Cargo";Name=$Name;Direction="Jettison";Maximum=$Maximum;Value=1;Input="";TypingStarted=$false;UnitValue=$unit;ValueSign=-1;SliderRect=[Drawing.RectangleF]::Empty}
    $script:G.QuantityDragging=$false
}

function Set-QuantityPickerFromX {
    param([double] $X)
    $picker=$script:G.QuantityPicker;if($null -eq $picker -or $picker.SliderRect.Width -le 0){return}
    $ratio=Get-ClampedValue (($X-$picker.SliderRect.X)/$picker.SliderRect.Width) 0 1
    $picker.Value=[int][Math]::Max(1,[Math]::Round(1+(($picker.Maximum-1)*$ratio)))
    $picker.Input="";$picker.TypingStarted=$false
}

function Apply-QuantityPicker {
    $picker=$script:G.QuantityPicker;if($null -eq $picker){return}
    $quantity=[int](Get-ClampedValue ([double]$picker.Value) 1 $picker.Maximum)
    if($picker.Purpose -eq "Jettison"){Jettison-CargoQuantity $picker.Name $quantity}
    elseif($picker.Direction -eq "Add"){[void](Add-TradeItem $picker.Side $picker.Name $quantity)}else{[void](Remove-TradeItem $picker.Side $picker.Name $quantity)}
    $script:G.QuantityPicker=$null;$script:G.QuantityDragging=$false
}

function Get-PlanetReputation {
    param([string] $SystemId,[string] $PlanetName)
    $count=0
    foreach($entry in $script:G.QuestState.Values){if($entry.SystemId -eq $SystemId -and $entry.Planet -eq $PlanetName -and $entry.Status -eq "Complete"){$count++}}
    return $count
}

function Get-AllQuestRows {
    $rows=@()
    foreach($system in $script:G.Systems.Values){
        foreach($planetName in $system.Order){
            $planet=$system.Planets[$planetName]
            if($null -eq $planet.Quests){continue}
            foreach($quest in $planet.Quests){$rows+=,[pscustomobject]@{Quest=$quest;SystemId=$system.Id;Planet=$planetName;Trader=$planet.TraderName}}
        }
    }
    return $rows
}

function Get-QuestRow {
    param([string] $QuestId)
    return @(Get-AllQuestRows|Where-Object{$_.Quest.Id -eq $QuestId}|Select-Object -First 1)[0]
}

function Get-QuestStatus {
    param($Row)
    if($script:G.QuestState.ContainsKey($Row.Quest.Id)){return [string]$script:G.QuestState[$Row.Quest.Id].Status}
    $rep=Get-PlanetReputation $Row.SystemId $Row.Planet
    if($rep -lt [int]$Row.Quest.RepReq){return "Locked"}
    return "Available"
}

function Test-QuestRequirements {
    param($Quest)
    foreach($name in $Quest.Requirements.Keys){if(-not $script:G.Inventory.ContainsKey($name) -or [int]$script:G.Inventory[$name] -lt [int]$Quest.Requirements[$name]){return $false}}
    return $true
}

function Get-ActiveQuestRequirements {
    $requirements=@{}
    foreach($row in Get-AllQuestRows){
        if(-not $script:G.QuestState.ContainsKey($row.Quest.Id) -or $script:G.QuestState[$row.Quest.Id].Status -ne "Active"){continue}
        foreach($name in $row.Quest.Requirements.Keys){if($requirements.ContainsKey($name)){$requirements[$name]+=[int]$row.Quest.Requirements[$name]}else{$requirements[$name]=[int]$row.Quest.Requirements[$name]}}
    }
    return $requirements
}

function Get-ContractDisplayRows {
    if($script:G.ContractContext -eq "Trader"){
        $rep=Get-PlanetReputation $script:G.Player.SystemId $script:G.Player.Location
        return @(Get-AllQuestRows|Where-Object{
            $_.SystemId -eq $script:G.Player.SystemId -and $_.Planet -eq $script:G.Player.Location -and
            (Get-QuestStatus $_) -ne "Complete" -and
            ((Get-QuestStatus $_) -ne "Locked" -or [int]$_.Quest.RepReq -le ($rep+1))
        }|Sort-Object {$_.Quest.RepReq},{$_.Quest.Name})
    }
    $wanted=if($script:G.ContractTab -eq "Complete"){"Complete"}else{"Active"}
    return @(Get-AllQuestRows|Where-Object{(Get-QuestStatus $_) -eq $wanted}|Sort-Object SystemId,Planet,{$_.Quest.Name})
}

function Invoke-QuestAction {
    param([string] $QuestId)
    $row=Get-QuestRow $QuestId
    if($null -eq $row){return}
    if($script:G.ContractContext -ne "Trader" -or $script:G.Player.SystemId -ne $row.SystemId -or $script:G.Player.Location -ne $row.Planet){Add-Notice "Contracts can only be accepted or turned in at their issuing trader.";return}
    $status=Get-QuestStatus $row
    if($status -eq "Available"){
        $script:G.QuestState[$QuestId]=@{Status="Active";Planet=$row.Planet;SystemId=$row.SystemId}
        Add-Notice ("Contract accepted: {0}" -f $row.Quest.Name)
        return
    }
    if($status -ne "Active"){return}
    if($script:G.Player.SystemId -ne $row.SystemId -or $script:G.Player.Location -ne $row.Planet){Add-Notice "Return to the issuing trader to complete this contract.";return}
    if(-not (Test-QuestRequirements $row.Quest)){Add-Notice "Contract cargo requirements are incomplete.";return}
    foreach($name in $row.Quest.Requirements.Keys){
        $script:G.Inventory[$name]-=[int]$row.Quest.Requirements[$name]
        if($script:G.Inventory[$name] -le 0){$script:G.Inventory.Remove($name)}
    }
    $script:G.Player.Credits+=[int]$row.Quest.RewardCredits
    $script:G.Player.CreditsAcquired+=[int]$row.Quest.RewardCredits
    foreach($name in $row.Quest.RewardItems.Keys){Add-InventoryItem $name ([int]$row.Quest.RewardItems[$name])}
    if(-not [string]::IsNullOrWhiteSpace($row.Quest.KnownSystem) -and $row.Quest.KnownSystem -notin @($script:G.Player.Known)){$script:G.Player.Known+=@($row.Quest.KnownSystem)}
    $script:G.QuestState[$QuestId].Status="Complete"
    Add-Notice ("Contract complete: {0}" -f $row.Quest.Name)
}

function Open-Contracts {
    param([ValidateSet("Auto","Log","Trader")][string] $Context="Auto")
    if($script:G.Mode -ne "Contracts"){$script:G.ReturnMode=$script:G.Mode}
    $script:G.ContractContext=if($Context -ne "Auto"){$Context}elseif($script:G.ReturnMode -eq "Trader"){"Trader"}else{"Log"}
    $script:G.ContractTab="Active"
    $script:G.Mode="Contracts";$script:G.TargetPanelExpand=1.0;$script:G.QuestScroll=0;$script:G.ContractRequirementScroll=0;$script:G.SelectedQuest=""
}

function Close-Contracts {
    if($script:G.FrackingActive -and $script:G.ReturnMode -eq "Frack"){$script:G.Mode="Frack";return}
    $script:G.Mode=if($script:G.ReturnMode -in @("Orbit","System","Trader","Cargo","Settings")){$script:G.ReturnMode}else{"Orbit"}
}

function Get-XRFScanResults {
    param($Planet)
    $resources=@($Planet.Resources.GetEnumerator()|Where-Object{$script:G.ResourceMaster[[string]$_.Key].Rarity -notin @("Consumable","Upgrade")})
    $total=[double](($resources|ForEach-Object{[double]$_.Value}|Measure-Object -Sum).Sum)
    return @($resources|ForEach-Object{[pscustomobject]@{Name=[string]$_.Key;Percent=if($total -gt 0){([double]$_.Value/$total)*100.0}else{0};Rarity=$script:G.ResourceMaster[[string]$_.Key].Rarity}}|Sort-Object Percent -Descending)
}

function Start-XRFScan {
    if([int]$script:G.Player.XRFScanner -le 0){Add-Notice "XRF8 Scanner is not installed.";return}
    if($script:G.Player.Fuel -lt 75.0){Add-Notice "XRF8 scan requires 75.0 FL.";return}
    $script:G.Player.Fuel=[Math]::Round($script:G.Player.Fuel-75.0,1)
    $planet=Get-Planet
    $script:G.XRFResults=@(Get-XRFScanResults $planet)
    $script:G.ReturnMode="Orbit";$script:G.Mode="XRF"
    Add-Notice ("XRF8 survey completed at {0}." -f $planet.Name)
}

function Start-CryoSleep {
    if(-not $script:G.FrackingActive -or [int]$script:G.Player.CryoSkip -le 0){return}
    if($script:G.CryoActive){return}
    $script:G.CryoActive=$true
    $script:G.CryoTicksRemaining=-1
    $script:G.Player.TimesSlept++
    $script:G.CyanFlash=0.55
    Add-LogEntry "CRYO-SLEEP CYCLE ENGAGED" (Get-Color Cyan)
}

function Open-Galaxy {
    if([int]$script:G.Player.Hyperdrive -le 0){Add-Notice "HyperDrive Module is not installed.";return}
    $script:G.Mode="Galaxy";$script:G.ReturnMode="System";$script:G.SelectedSystem=""
}

function Start-Hyperjump {
    param([string] $SystemId)
    if(-not $script:G.Systems.ContainsKey($SystemId) -or $SystemId -eq $script:G.Player.SystemId){return}
    if($script:G.Player.Fuel -lt 1000.0){Add-Notice "Hyperjump requires 1000.0 FL.";return}
    $script:G.Player.Fuel=[Math]::Round($script:G.Player.Fuel-1000.0,1)
    $destination=$script:G.Systems[$SystemId]
    $script:G.Player.SystemId=$SystemId;$script:G.Player.System=$destination.Name
    $script:G.Planets=$destination.Planets;$script:G.PlanetOrder=$destination.Order
    $script:G.Player.Location=$destination.Order[-1]
    if($script:G.Player.Location -notin @($script:G.Player.Known)){$script:G.Player.Known+=@($script:G.Player.Location)}
    $script:G.SelectedSystem="";$script:G.SelectedPlanet="";$script:G.ConfirmTravel=$false
    $script:G.Mode="Orbit";$script:G.WorldMode="Orbit";$script:G.SystemBlend=0.0;$script:G.TargetSystemBlend=0.0
    Add-Notice ("Hyperjump complete. Arrived at {0}, {1}." -f $script:G.Player.Location,$destination.Name)
}

function Test-ReachableInhabitedPlanet {
    $current=Get-Planet
    foreach($planet in $script:G.Planets.Values){if($planet.Inhabited -and (Get-TravelFuelCost ([Math]::Abs($planet.Distance-$current.Distance))) -le $script:G.Player.Fuel){return $true}}
    return $false
}

function Start-DistressSignal {
    $script:G.Mode="Distress";$script:G.ReturnMode="System";$script:G.DistressRemaining=10.0
    Add-Notice "Emergency beacon activated. Recovery inbound."
}

function Cancel-DistressSignal {
    $script:G.DistressRemaining=0.0;$script:G.Mode="System";Add-Notice "Distress signal cancelled."
}

function Complete-DistressSignal {
    $script:G.Player.Credits=[Math]::Floor($script:G.Player.Credits/2)
    foreach($name in @($script:G.Inventory.Keys)){if(-not $script:G.ResourceMaster[$name].ContainsKey("Effect")){$script:G.Inventory.Remove($name)}}
    $current=Get-Planet;$nearest=$null;$distance=[double]::MaxValue
    foreach($planet in $script:G.Planets.Values){if($planet.Inhabited){$d=[Math]::Abs($planet.Distance-$current.Distance);if($d -lt $distance){$distance=$d;$nearest=$planet}}}
    if($null -ne $nearest){$script:G.Player.Location=$nearest.Name}
    $script:G.Player.Fuel=[Math]::Min($script:G.Player.MaxFuel,10.0);$script:G.Player.HP=[Math]::Min($script:G.Player.MaxHP,50.0)
    $script:G.Mode="Orbit";$script:G.WorldMode="Orbit";$script:G.TargetSystemBlend=0.0;$script:G.DistressRemaining=0.0
    Add-Notice "Scrapper Union recovery complete. Raw cargo and half your credits were forfeited."
}

function ConvertTo-Hashtable {
    param($Object)
    if($Object -is [Management.Automation.PSCustomObject]){$table=@{};foreach($property in $Object.PSObject.Properties){$table[$property.Name]=ConvertTo-Hashtable $property.Value};return $table}
    if($Object -is [Object[]]){return @($Object|ForEach-Object{ConvertTo-Hashtable $_})}
    return $Object
}

function Get-SaveDirectory {
    $path=Join-Path $env:APPDATA "spacefrack"
    if(-not (Test-Path -LiteralPath $path)){New-Item -ItemType Directory -Path $path -Force|Out-Null}
    return $path
}

function Get-SaveFiles {
    $path=Get-SaveDirectory
    return @(Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -like "spacefrack_*" -or $_.Name -like "spacegame_*"}|Sort-Object LastWriteTime -Descending)
}

function Show-TextInputDialog {
    param([string] $Title,[string] $Prompt,[string] $Default="")
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text=$Title;$dialog.ClientSize=[Drawing.Size]::new(420,142);$dialog.StartPosition="CenterParent";$dialog.FormBorderStyle="FixedDialog";$dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false;$dialog.BackColor=[Drawing.Color]::FromArgb(15,22,26);$dialog.ForeColor=[Drawing.Color]::White
    $label=New-Object Windows.Forms.Label;$label.Text=$Prompt;$label.Location=[Drawing.Point]::new(16,16);$label.Size=[Drawing.Size]::new(385,24)
    $box=New-Object Windows.Forms.TextBox;$box.Text=$Default;$box.Location=[Drawing.Point]::new(16,46);$box.Size=[Drawing.Size]::new(385,25);$box.BackColor=[Drawing.Color]::FromArgb(30,42,46);$box.ForeColor=[Drawing.Color]::White
    $ok=New-Object Windows.Forms.Button;$ok.Text="OK";$ok.Location=[Drawing.Point]::new(235,91);$ok.Size=[Drawing.Size]::new(78,32);$ok.DialogResult=[Windows.Forms.DialogResult]::OK
    $cancel=New-Object Windows.Forms.Button;$cancel.Text="CANCEL";$cancel.Location=[Drawing.Point]::new(323,91);$cancel.Size=[Drawing.Size]::new(78,32);$cancel.DialogResult=[Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.AddRange(@($label,$box,$ok,$cancel));$dialog.AcceptButton=$ok;$dialog.CancelButton=$cancel
    try{if($dialog.ShowDialog($script:Form) -eq [Windows.Forms.DialogResult]::OK){return $box.Text.Trim()};return ""}finally{$dialog.Dispose()}
}

function Get-TraderStateSaveCopy {
    $copy=@{}
    foreach($key in @($script:G.TraderState.Keys)){
        $source=$script:G.TraderState[$key]
        $state=@{}
        foreach($field in @($source.Keys)){$state[$field]=$source[$field]}
        $last=if($state.ContainsKey("LastRestock")){ConvertTo-LocalTraderTime $state.LastRestock}elseif($state.ContainsKey("LastTrade")){ConvertTo-LocalTraderTime $state.LastTrade}else{$null}
        if($null -eq $last){$last=Get-LocalQuarterHourBoundary}
        $state.LastRestock=$last.ToString("o")
        if($state.ContainsKey("LastTrade")){$state.Remove("LastTrade")}
        $copy[$key]=$state
    }
    return $copy
}

function Save-Game {
    if([string]::IsNullOrWhiteSpace($script:G.Player.SaveName)){$name=Show-TextInputDialog "SPACEFRACK SAVE" "Pilot name:" $script:G.Player.PilotName;if([string]::IsNullOrWhiteSpace($name)){return};$script:G.Player.SaveName=$name;$script:G.Player.PilotName=$name}
    $safe=($script:G.Player.SaveName -replace '[^A-Za-z0-9 _-]','').Trim();if([string]::IsNullOrWhiteSpace($safe)){$safe="Pilot"}
    $path=Join-Path (Get-SaveDirectory) ("spacefrack_{0}_{1}.json" -f $safe,(Get-Date -Format "ddMMyy-HHmmss"))
    $data=@{Version=$script:Version;SavedAt=(Get-Date).ToString("o");GameStarted=([datetime]$script:G.GameStarted).ToString("o");SystemId=$script:G.Player.SystemId;Player=$script:G.Player;Inventory=$script:G.Inventory;TraderState=(Get-TraderStateSaveCopy);QuestState=$script:G.QuestState}
    $data|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -Encoding UTF8
    Add-Notice ("Saved flight: {0}" -f [IO.Path]::GetFileName($path))
}

function Load-Game {
    param([string] $Path)
    $data=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json|ForEach-Object{ConvertTo-Hashtable $_}
    New-GameState
    $defaults=$script:G.Player
    foreach($key in $data.Player.Keys){$defaults[$key]=$data.Player[$key]}
    if($data.Player.ContainsKey("autoadminister") -and -not $data.Player.ContainsKey("AutoAdminister")){$defaults.AutoAdminister=$data.Player.autoadminister}
    foreach($numericName in @("Fuel","MaxFuel","HP","MaxHP","MaxWeight")){$defaults[$numericName]=[double]$defaults[$numericName]}
    $systemId=if($data.ContainsKey("SystemId")){$data.SystemId}elseif($data.ContainsKey("SystemName")){$data.SystemName}else{"Sol"}
    if(-not $script:G.Systems.ContainsKey($systemId)){$systemId="Sol"}
    $defaults.SystemId=$systemId;$defaults.System=$script:G.Systems[$systemId].Name
    $script:G.Planets=$script:G.Systems[$systemId].Planets;$script:G.PlanetOrder=$script:G.Systems[$systemId].Order
    $script:G.Inventory=$data.Inventory
    if($data.ContainsKey("TraderState")){$script:G.TraderState=$data.TraderState}
    if($data.ContainsKey("QuestState")){$script:G.QuestState=$data.QuestState}
    foreach($questId in @($script:G.QuestState.Keys)){
        $row=Get-QuestRow $questId;if($null -eq $row){continue};$entry=$script:G.QuestState[$questId]
        if(-not $entry.ContainsKey("SystemId")){$entry.SystemId=$row.SystemId}
        if(-not $entry.ContainsKey("Planet")){$entry.Planet=$row.Planet}
    }
    if($data.ContainsKey("GameStarted")){try{$script:G.GameStarted=[datetime]$data.GameStarted}catch{}}
    $now=Get-Date
    [void](Refresh-DueTraderStates $now)
    $script:G.TraderRestockBoundary=Get-LocalQuarterHourBoundary $now
    $script:G.TraderRestockPoll=1.0
    $script:G.Mode="Orbit";$script:G.WorldMode="Orbit"
    Add-Notice ("Loaded flight: {0}" -f [IO.Path]::GetFileName($Path))
}

function Refresh-SaveFiles {
    $script:G.SaveFiles=@(Get-SaveFiles);$script:G.SaveScroll=0;$script:G.SelectedSave=""
}

function Open-Saves {
    if($script:G.Mode -ne "Saves"){$script:G.ReturnMode=$script:G.Mode}
    Refresh-SaveFiles;$script:G.Mode="Saves"
}

function Close-Saves {
    if($script:G.ReturnMode -eq "Title"){$script:G.Mode="Title"}else{$script:G.Mode="Settings"}
}

function Remove-SelectedSave {
    if([string]::IsNullOrWhiteSpace($script:G.SelectedSave) -or -not (Test-Path -LiteralPath $script:G.SelectedSave)){return}
    $answer=[Windows.Forms.MessageBox]::Show($script:Form,"Delete the selected save?","SPACEFRACK",[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
    if($answer -eq [Windows.Forms.DialogResult]::Yes){Remove-Item -LiteralPath $script:G.SelectedSave -Force;Refresh-SaveFiles;Add-Notice "Save deleted."}
}

function Prune-SaveFiles {
    $files=@(Get-SaveFiles);$groups=$files|Group-Object{if($_.BaseName -match '^space(?:game|frack)_([^_]+)'){$matches[1]}else{$_.BaseName}};$remove=@()
    foreach($group in $groups){$remove+=@($group.Group|Sort-Object LastWriteTime -Descending|Select-Object -Skip 1)}
    if($remove.Count -eq 0){Add-Notice "No older pilot saves to prune.";return}
    $answer=[Windows.Forms.MessageBox]::Show($script:Form,("Delete {0} older save(s)?" -f $remove.Count),"SPACEFRACK",[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
    if($answer -eq [Windows.Forms.DialogResult]::Yes){foreach($file in $remove){Remove-Item -LiteralPath $file.FullName -Force};Refresh-SaveFiles;Add-Notice ("Pruned {0} old save(s)." -f $remove.Count)}
}

function Rename-Pilot {
    $name=Show-TextInputDialog "PILOT ID" "Pilot name:" $script:G.Player.PilotName
    if(-not [string]::IsNullOrWhiteSpace($name)){$script:G.Player.PilotName=$name;$script:G.Player.SaveName=$name;Add-Notice ("Pilot ID set to {0}." -f $name)}
}

function Open-Settings {
    if($script:G.Mode -ne "Settings"){$script:G.ReturnMode=$script:G.Mode}
    $script:G.Mode="Settings"
}

function Set-VibrationIntensityFromX {
    param([double] $X)
    $rect=$script:G.VibrationSliderRect
    if($rect.Width -le 0){return}
    $ratio=Get-ClampedValue (($X-$rect.Left)/$rect.Width) 0.0 1.0
    $script:G.DrillVibrationIntensity=[Math]::Round($ratio*100.0)
    $script:G.DrillVibration=$script:G.DrillVibrationIntensity -gt 0
}

function Close-Settings {
    if($script:G.FrackingActive -and $script:G.ReturnMode -eq "Frack"){$script:G.Mode="Frack";$script:G.WorldMode="Frack";$script:G.TargetCloseZoom=1.0;return}
    $script:G.Mode=if($script:G.ReturnMode -in @("Orbit","System","Trader","Title","Cargo","Contracts","Frack")){$script:G.ReturnMode}else{"Orbit"}
}

function Open-Status {
    $script:G.Mode="Status"
}

function Format-GameDuration {
    param([double] $Seconds)
    $span=[TimeSpan]::FromSeconds([Math]::Max(0,$Seconds))
    if($span.TotalHours -ge 1){return ("{0}h {1}m {2}s" -f [int]$span.TotalHours,$span.Minutes,$span.Seconds)}
    if($span.TotalMinutes -ge 1){return ("{0}m {1}s" -f $span.Minutes,$span.Seconds)}
    return ("{0}s" -f $span.Seconds)
}

function Get-AlphaColor {
    param([Drawing.Color] $Color, [int] $Alpha)
    return [Drawing.Color]::FromArgb((Get-ClampedValue $Alpha 0 255), $Color.R, $Color.G, $Color.B)
}

function Cancel-HoldButton {
    if($null -ne $script:G){$script:G.HoldButton=$null}
    if($null -ne $script:Canvas -and -not $script:Canvas.IsDisposed -and $script:Canvas.Capture){$script:Canvas.Capture=$false}
}

function Start-HoldButton {
    param($Target)
    if($null -eq $Target -or -not $Target.Enabled -or [double]$Target.HoldSeconds -le 0.0){return $false}
    if($script:G.InputLocked -gt 0.0 -or $script:G.CryoActive){return $false}
    $script:G.HoldButton=@{
        Action=[string]$Target.Action
        Data=$Target.Data
        Duration=[double]$Target.HoldSeconds
        Elapsed=0.0
        Rectangle=[Drawing.RectangleF]$Target.Rectangle
        Mode=[string]$script:G.Mode
    }
    return $true
}

function Update-HoldButton {
    param([double] $Delta)
    if($null -eq $script:G.HoldButton){return}
    $hold=$script:G.HoldButton
    $point=[Drawing.PointF]::new([single]$script:MouseX,[single]$script:MouseY)
    if($script:G.Mode -ne $hold.Mode -or $script:G.InputLocked -gt 0.0 -or $script:G.CryoActive -or -not $hold.Rectangle.Contains($point)){
        Cancel-HoldButton
        return
    }
    $hold.Elapsed=[Math]::Min([double]$hold.Duration,[double]$hold.Elapsed+[Math]::Max(0.0,$Delta))
    if($hold.Elapsed -ge $hold.Duration){
        $action=[string]$hold.Action;$data=$hold.Data
        Cancel-HoldButton
        Invoke-Action $action $data
    }
}

function Update-Game {
    param([double] $Delta)
    if ($null -eq $script:G) { return }

    $script:G.Time += $Delta
    $script:G.NoticeClock = [Math]::Max(0.0, $script:G.NoticeClock - $Delta)
    $script:G.InputLocked = [Math]::Max(0.0, $script:G.InputLocked - $Delta)
    $script:G.Shake = [Math]::Max(0.0, $script:G.Shake - (35.0 * $Delta))
    $script:G.RedFlash = [Math]::Max(0.0, $script:G.RedFlash - (1.5 * $Delta))
    $script:G.ImpactFlash = [Math]::Max(0.0, $script:G.ImpactFlash - (4.8 * $Delta))
    $script:G.GreenFlash = [Math]::Max(0.0, $script:G.GreenFlash - (1.5 * $Delta))
    $script:G.CyanFlash = [Math]::Max(0.0, $script:G.CyanFlash - (1.5 * $Delta))
    Update-HoldButton $Delta
    $script:G.TraderRestockPoll=[Math]::Max(0.0,[double]$script:G.TraderRestockPoll-$Delta)
    if($script:G.TraderRestockPoll -le 0.0){
        $script:G.TraderRestockPoll=1.0
        $now=Get-Date
        $boundary=Get-LocalQuarterHourBoundary $now
        $knownBoundary=ConvertTo-LocalTraderTime $script:G.TraderRestockBoundary
        if($null -eq $knownBoundary -or $knownBoundary -ne $boundary){
            $currentTraderKey=Get-TraderKey
            $refreshed=@(Refresh-DueTraderStates $now)
            $script:G.TraderRestockBoundary=$boundary
            if($script:G.Mode -eq "Trader" -and $refreshed -contains $currentTraderKey){
                if($script:G.TraderTab -eq "Trade"){[void](Set-TraderDialog "TradeGreeting" -First)}
                Add-Notice "Trader inventory and budget restocked."
            }
        }
    }
    $cameraAmount = 1.0 - [Math]::Exp(-5.5 * $Delta)
    $navigationRate=2.4
    if($script:G.TargetSystemBlend -ge 0.99){
        $remaining=[Math]::Abs(1.0-$script:G.SystemBlend);$tail=1.0-(Get-ClampedValue ($remaining/0.16) 0.0 1.0)
        $navigationRate*=1.0+(2.2*$tail*$tail)
    }
    $navigationAmount = 1.0 - [Math]::Exp(-$navigationRate * $Delta)
    $script:G.SystemBlend = Get-Lerp $script:G.SystemBlend $script:G.TargetSystemBlend $navigationAmount
    if([Math]::Abs($script:G.SystemBlend-$script:G.TargetSystemBlend) -lt 0.0008){$script:G.SystemBlend=$script:G.TargetSystemBlend}
    $script:G.CloseZoom = Get-Lerp $script:G.CloseZoom $script:G.TargetCloseZoom $cameraAmount
    $script:G.TraderBlend = Get-Lerp $script:G.TraderBlend $script:G.TargetTraderBlend $cameraAmount
    $script:G.TargetPanelExpand = if($script:G.Mode -in @("Cargo","Trader","Contracts","XRF","Status","Settings","Saves","Galaxy","Frack","Death")){1.0}else{0.0}
    $script:G.PanelExpand = Get-Lerp $script:G.PanelExpand $script:G.TargetPanelExpand $cameraAmount

    foreach ($star in $script:TwinkleStars) {
        $star.Twinkle += $Delta * (0.7 + $star.Layer)
    }
    foreach ($entry in $script:G.Log) { $entry.Age += $Delta }

    for ($i = $script:G.Particles.Count - 1; $i -ge 0; $i--) {
        $particle = $script:G.Particles[$i]
        $particle.X += $particle.VX * $Delta
        $particle.Y += $particle.VY * $Delta
        $particle.VY += 55.0 * $Delta
        $particle.Life -= $Delta
        if ($particle.Life -le 0.0) { $script:G.Particles.RemoveAt($i) }
    }

    if ($null -ne $script:G.Travel) {
        $script:G.Travel.Time += $Delta
        if ($script:G.Travel.Time -ge $script:G.Travel.Duration) { Complete-Travel }
    }

    if ($script:G.FrackingActive) {
        $clockNow=$script:Clock.Elapsed.TotalSeconds
        $script:G.FrackElapsed=[Math]::Max(0.0,$clockNow-$script:G.FrackStartClock)
        if($script:G.CryoActive){
            for($tick=0;$tick -lt 50 -and $script:G.FrackingActive -and $script:G.CryoActive;$tick++){
                $result=Invoke-FrackTick;$script:G.Player.TimeFracked++;$script:G.Player.TimeSlept++
                if($result.Status -ne "Continue"){$script:G.CryoActive=$false;$script:G.CryoTicksRemaining=0;break}
            }
        }elseif($clockNow -ge $script:G.NextFrackTick){
            $result=Invoke-FrackTick
            $script:G.Player.TimeFracked++
            do{$script:G.NextFrackTick+=1.0}while($script:G.NextFrackTick -le $clockNow)
        }
    }
    if($script:G.Mode -eq "Distress"){
        $script:G.DistressRemaining=[Math]::Max(0.0,$script:G.DistressRemaining-$Delta)
        if($script:G.DistressRemaining -le 0.0){Complete-DistressSignal}
    }
}

function Draw-Starfield {
    param([Drawing.Graphics] $Graphics, [double] $TravelFactor = 0.0)
    if($TravelFactor -le 0.01){
        Fill-RectangleColor $Graphics (Get-Color Black) ([Drawing.RectangleF]::new(0,0,$script:VirtualWidth,$script:ViewportBottom+5))
        $oldSmoothing=$Graphics.SmoothingMode
        try{
            $Graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::None
            $starBrush=$script:Assets.FrameBrush
            $starAlphas=@(48,82,118)
            for($bucket=0;$bucket -lt $script:StarfieldPaths.Count;$bucket++){
                $starBrush.Color=[Drawing.Color]::FromArgb($starAlphas[$bucket],178,204,219)
                $Graphics.FillPath($starBrush,$script:StarfieldPaths[$bucket])
            }
        }finally{$Graphics.SmoothingMode=$oldSmoothing}
        if(-not $script:ReducedRenderQuality){
            foreach($star in $script:TwinkleStars){
                $pulse=[Math]::Max(0.0,[Math]::Sin($star.Twinkle))*0.35
                $alpha=[int](Get-ClampedValue ($star.Alpha*$pulse) 0 75)
                if($alpha -gt 1){Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb($alpha,205,225,236)) ([Drawing.RectangleF]::new($star.X,$star.Y,$star.Size,$star.Size))}
            }
        }
        return
    }
    Fill-RectangleColor $Graphics (Get-Color Black) ([Drawing.RectangleF]::new(0, 0, $script:VirtualWidth, $script:ViewportBottom + 5))
    $starIndex=0
    foreach ($star in $script:G.Stars) {
        if($script:ReducedRenderQuality -and (($starIndex++ % 2) -ne 0)){continue}
        $twinkle = 0.65 + ([Math]::Sin($star.Twinkle) * 0.25)
        $alpha = [int](Get-ClampedValue ($star.Alpha * $twinkle) 10 220)
        $color = [Drawing.Color]::FromArgb($alpha, 178, 204, 219)
        if($TravelFactor -gt 0.01){
            $length = 2.0 + (65.0 * $TravelFactor * $star.Layer)
            $pen=$script:Assets.FramePen
            $pen.Color=$color;$pen.Width=[single][Math]::Max(0.5,$star.Size);$pen.DashStyle=[Drawing.Drawing2D.DashStyle]::Solid;$pen.StartCap=[Drawing.Drawing2D.LineCap]::Flat;$pen.EndCap=[Drawing.Drawing2D.LineCap]::Flat
            $Graphics.DrawLine($pen,$star.X-$length,$star.Y,$star.X+$length,$star.Y)
        }else{
            Fill-EllipseColor $Graphics $color ([Drawing.RectangleF]::new($star.X,$star.Y,$star.Size,$star.Size))
        }
    }
}

function Draw-VectorHelmetVector {
    param([Drawing.Graphics] $Graphics, [double] $CenterX, [double] $CenterY, [double] $Scale = 1.0)

    $saved = $Graphics.Save()
    $Graphics.TranslateTransform([single]$CenterX, [single]$CenterY)
    $Graphics.ScaleTransform([single]$Scale, [single]$Scale)

    # Smooth EVA shell with a diagonal value shift to give it a rounded body.
    $shell = New-Object Drawing.Drawing2D.GraphicsPath
    $shell.AddBezier([Drawing.PointF]::new(-145,-56),[Drawing.PointF]::new(-137,-151),[Drawing.PointF]::new(-69,-181),[Drawing.PointF]::new(5,-178))
    $shell.AddBezier([Drawing.PointF]::new(5,-178),[Drawing.PointF]::new(83,-178),[Drawing.PointF]::new(140,-137),[Drawing.PointF]::new(153,-64))
    $shell.AddBezier([Drawing.PointF]::new(153,-64),[Drawing.PointF]::new(174,5),[Drawing.PointF]::new(151,101),[Drawing.PointF]::new(87,142))
    $shell.AddBezier([Drawing.PointF]::new(87,142),[Drawing.PointF]::new(38,171),[Drawing.PointF]::new(-35,171),[Drawing.PointF]::new(-88,145))
    $shell.AddBezier([Drawing.PointF]::new(-88,145),[Drawing.PointF]::new(-157,109),[Drawing.PointF]::new(-177,26),[Drawing.PointF]::new(-145,-56))
    $shell.CloseFigure()
    $shellBounds=[Drawing.RectangleF]::new(-180,-185,360,360)
    $shellBrush=[Drawing.Drawing2D.LinearGradientBrush]::new($shellBounds,[Drawing.Color]::FromArgb(194,204,211),[Drawing.Color]::FromArgb(62,70,77),[single]125.0)
    $shellPen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(224,232,236),7)
    try { $Graphics.FillPath($shellBrush, $shell); $Graphics.DrawPath($shellPen, $shell) }
    finally { $shellBrush.Dispose(); $shellPen.Dispose(); $shell.Dispose() }

    # Curved shell bands replace the old angular lower panel.
    $lowerBand=New-Object Drawing.Pen([Drawing.Color]::FromArgb(31,37,42),17)
    $redBand=New-Object Drawing.Pen([Drawing.Color]::FromArgb(151,35,38),8)
    $topHighlight=New-Object Drawing.Pen([Drawing.Color]::FromArgb(180,237,243,246),5)
    try{
        $Graphics.DrawArc($lowerBand,-146,-153,292,310,12,156)
        $Graphics.DrawArc($redBand,-139,-146,278,296,20,139)
        $Graphics.DrawArc($topHighlight,-151,-166,304,320,202,91)
    }
    finally{$lowerBand.Dispose();$redBand.Dispose();$topHighlight.Dispose()}

    # Round side hardware keeps the silhouette recognizably astronaut-like.
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(38,44,49)) ([Drawing.RectangleF]::new(136,-20,39,72))
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(173,184,191)) ([Drawing.RectangleF]::new(145,-7,19,45))
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(45,52,58)) ([Drawing.RectangleF]::new(150,1,10,29))

    # Recessed visor with layered translucent values for a convex glass read.
    $visor = New-Object Drawing.Drawing2D.GraphicsPath
    $visor.AddBezier([Drawing.PointF]::new(-118,-73),[Drawing.PointF]::new(-92,-130),[Drawing.PointF]::new(-27,-143),[Drawing.PointF]::new(34,-132))
    $visor.AddBezier([Drawing.PointF]::new(34,-132),[Drawing.PointF]::new(99,-121),[Drawing.PointF]::new(128,-75),[Drawing.PointF]::new(132,-18))
    $visor.AddBezier([Drawing.PointF]::new(132,-18),[Drawing.PointF]::new(138,51),[Drawing.PointF]::new(94,108),[Drawing.PointF]::new(27,126))
    $visor.AddBezier([Drawing.PointF]::new(27,126),[Drawing.PointF]::new(-40,139),[Drawing.PointF]::new(-103,108),[Drawing.PointF]::new(-127,55))
    $visor.AddBezier([Drawing.PointF]::new(-127,55),[Drawing.PointF]::new(-141,15),[Drawing.PointF]::new(-135,-39),[Drawing.PointF]::new(-118,-73))
    $visor.CloseFigure()
    $visorBounds=[Drawing.RectangleF]::new(-140,-145,280,285)
    $visorBrush=[Drawing.Drawing2D.LinearGradientBrush]::new($visorBounds,[Drawing.Color]::FromArgb(52,67,77),[Drawing.Color]::FromArgb(3,7,11),[single]132.0)
    $visorPen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(25,31,36),13)
    try{$Graphics.FillPath($visorBrush,$visor)}finally{$visorBrush.Dispose()}

    $clipState=$Graphics.Save()
    $Graphics.SetClip($visor)
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(27,201,219,230)) ([Drawing.RectangleF]::new(-119,-118,225,215))
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(17,225,235,241)) ([Drawing.RectangleF]::new(-96,-97,160,150))
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb(15,181,38,42)) ([Drawing.RectangleF]::new(22,38,105,82))

    $reflection=New-Object Drawing.Drawing2D.GraphicsPath
    $reflection.AddBezier([Drawing.PointF]::new(-101,-69),[Drawing.PointF]::new(-70,-112),[Drawing.PointF]::new(-16,-128),[Drawing.PointF]::new(43,-105))
    $reflection.AddLine([Drawing.PointF]::new(43,-105),[Drawing.PointF]::new(18,-90))
    $reflection.AddBezier([Drawing.PointF]::new(18,-90),[Drawing.PointF]::new(-26,-105),[Drawing.PointF]::new(-68,-88),[Drawing.PointF]::new(-91,-54))
    $reflection.CloseFigure()
    $reflectionBrush=New-Brush ([Drawing.Color]::FromArgb(25,239,245,248))
    try{$Graphics.FillPath($reflectionBrush,$reflection)}finally{$reflectionBrush.Dispose();$reflection.Dispose()}
    $Graphics.Restore($clipState)

    $glassGlow=New-Object Drawing.Pen([Drawing.Color]::FromArgb(75,232,241,245),13)
    $glassEdge=New-Object Drawing.Pen([Drawing.Color]::FromArgb(205,242,247,249),4)
    $glassBounce=New-Object Drawing.Pen([Drawing.Color]::FromArgb(72,212,225,232),6)
    try{
        $Graphics.DrawArc($glassGlow,-112,-116,232,231,201,98)
        $Graphics.DrawArc($glassEdge,-109,-113,226,225,211,49)
        $Graphics.DrawArc($glassBounce,-112,-111,229,226,7,50)
    }
    finally{$glassGlow.Dispose();$glassEdge.Dispose();$glassBounce.Dispose()}

    try{$Graphics.DrawPath($visorPen,$visor)}finally{$visorPen.Dispose();$visor.Dispose()}

    # An off-center impact sends splinters out with deliberately varied weights.
    $topCrack=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(19,-4),[Drawing.PointF]::new(7,-23),
        [Drawing.PointF]::new(20,-39),[Drawing.PointF]::new(4,-58),
        [Drawing.PointF]::new(22,-74),[Drawing.PointF]::new(13,-91),
        [Drawing.PointF]::new(33,-108),[Drawing.PointF]::new(27,-128)
    )
    $bottomCrack=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(20,-4),[Drawing.PointF]::new(36,12),
        [Drawing.PointF]::new(27,28),[Drawing.PointF]::new(44,43),
        [Drawing.PointF]::new(35,61),[Drawing.PointF]::new(51,75),
        [Drawing.PointF]::new(43,91),[Drawing.PointF]::new(59,111)
    )
    $leftCrack=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(13,-7),[Drawing.PointF]::new(-8,-14),
        [Drawing.PointF]::new(-22,-5),[Drawing.PointF]::new(-42,-12),
        [Drawing.PointF]::new(-58,-4),[Drawing.PointF]::new(-78,-10),
        [Drawing.PointF]::new(-96,0)
    )
    $rightCrack=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(25,-8),[Drawing.PointF]::new(42,-22),
        [Drawing.PointF]::new(60,-18),[Drawing.PointF]::new(75,-34),
        [Drawing.PointF]::new(91,-31),[Drawing.PointF]::new(109,-48)
    )
    $lowerLeftCrack=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(16,2),[Drawing.PointF]::new(2,20),
        [Drawing.PointF]::new(-15,25),[Drawing.PointF]::new(-27,44),
        [Drawing.PointF]::new(-49,49),[Drawing.PointF]::new(-62,65)
    )
    $lowerTwig=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(43,43),[Drawing.PointF]::new(24,52),
        [Drawing.PointF]::new(29,66),[Drawing.PointF]::new(13,80)
    )
    $upperTwig=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(8,-23),[Drawing.PointF]::new(-8,-34),
        [Drawing.PointF]::new(-18,-49)
    )
    $impact=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(8,-12),[Drawing.PointF]::new(17,-18),
        [Drawing.PointF]::new(29,-13),[Drawing.PointF]::new(34,-4),
        [Drawing.PointF]::new(28,5),[Drawing.PointF]::new(19,11),
        [Drawing.PointF]::new(8,5),[Drawing.PointF]::new(3,-2)
    )
    $impactHole=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(13,-8),[Drawing.PointF]::new(21,-12),
        [Drawing.PointF]::new(28,-6),[Drawing.PointF]::new(25,2),
        [Drawing.PointF]::new(17,7),[Drawing.PointF]::new(9,1)
    )
    $fractureShadow=New-Object Drawing.Pen([Drawing.Color]::FromArgb(2,4,6),9)
    $mainFracture=New-Object Drawing.Pen([Drawing.Color]::FromArgb(196,37,41),5)
    $branchShadow=New-Object Drawing.Pen([Drawing.Color]::FromArgb(2,4,6),5)
    $branchFracture=New-Object Drawing.Pen([Drawing.Color]::FromArgb(211,43,46),2)
    $hotEdge=New-Object Drawing.Pen([Drawing.Color]::FromArgb(238,70,72),1)
    foreach($pen in @($fractureShadow,$mainFracture,$branchShadow,$branchFracture,$hotEdge)){
        $pen.LineJoin=[Drawing.Drawing2D.LineJoin]::Miter
        $pen.StartCap=[Drawing.Drawing2D.LineCap]::Flat
        $pen.EndCap=[Drawing.Drawing2D.LineCap]::Flat
    }
    try{
        $Graphics.DrawLines($fractureShadow,$topCrack)
        $Graphics.DrawLines($mainFracture,$topCrack)
        $fractureShadow.Width=7
        $mainFracture.Width=4
        $Graphics.DrawLines($fractureShadow,$bottomCrack)
        $Graphics.DrawLines($mainFracture,$bottomCrack)
        foreach($branch in @($leftCrack,$rightCrack,$lowerLeftCrack,$lowerTwig,$upperTwig)){
            $Graphics.DrawLines($branchShadow,$branch)
            $Graphics.DrawLines($branchFracture,$branch)
        }
        $Graphics.DrawLines($hotEdge,[Drawing.PointF[]]@([Drawing.PointF]::new(5,-58),[Drawing.PointF]::new(22,-74),[Drawing.PointF]::new(13,-91)))
        $Graphics.DrawLines($hotEdge,[Drawing.PointF[]]@([Drawing.PointF]::new(35,61),[Drawing.PointF]::new(51,75),[Drawing.PointF]::new(43,91)))
        $impactBrush=New-Brush ([Drawing.Color]::FromArgb(213,43,46))
        $holeBrush=New-Brush ([Drawing.Color]::FromArgb(2,4,6))
        try{
            $Graphics.FillPolygon($impactBrush,$impact)
            $Graphics.FillPolygon($holeBrush,$impactHole)
        }
        finally{$impactBrush.Dispose();$holeBrush.Dispose()}
    }
    finally{
        $fractureShadow.Dispose();$mainFracture.Dispose();$branchShadow.Dispose();$branchFracture.Dispose();$hotEdge.Dispose()
    }

    $rimPen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(30,36,41),8)
    $rimLight=New-Object Drawing.Pen([Drawing.Color]::FromArgb(214,225,231),4)
    try{
        $Graphics.DrawArc($rimPen,-154,-166,310,326,182,176)
        $Graphics.DrawArc($rimLight,-151,-163,304,320,205,68)
    }
    finally{$rimPen.Dispose();$rimLight.Dispose()}
    $Graphics.Restore($saved)
}

function Get-VectorHelmetBitmap {
    param([double] $DeviceScale)
    $renderScale=[Math]::Max(0.2,$DeviceScale)
    $key=("{0:N3}" -f $renderScale)
    if($script:HelmetBitmapCache.ContainsKey($key)){return $script:HelmetBitmapCache[$key]}
    $size=[Math]::Max(100,[int][Math]::Ceiling(420.0*$renderScale))
    $bitmap=New-Object Drawing.Bitmap($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        Draw-VectorHelmetVector $graphics ($size/2.0) ($size/2.0) $renderScale
    }finally{$graphics.Dispose()}
    $script:HelmetBitmapCache[$key]=$bitmap
    return $bitmap
}

function Draw-VectorHelmet {
    param([Drawing.Graphics] $Graphics,[double] $CenterX,[double] $CenterY,[double] $Scale=1.0)
    if([Math]::Abs($script:HelmetBitmapDeviceScale-$script:Scale) -gt 0.002){
        foreach($cachedBitmap in @($script:HelmetBitmapCache.Values)){$cachedBitmap.Dispose()}
        $script:HelmetBitmapCache=@{};$script:HelmetBitmapDeviceScale=$script:Scale
    }
    $bitmap=Get-VectorHelmetBitmap ($Scale*$script:Scale)
    Draw-DeviceBitmap $Graphics $bitmap $CenterX $CenterY
}

function Get-PlanetVisualGeometry {
    param($Planet)
    $key="{0}|{1}|{2}" -f $Planet.Visual.Seed,$Planet.Type,$Planet.Visual.Feature
    if($script:PlanetVisualCache.ContainsKey($key)){return $script:PlanetVisualCache[$key]}
    $random=New-Object Random([int]$Planet.Visual.Seed)
    $bands=New-ArrayList
    for($i=0;$i -lt 15;$i++){
        [void]$bands.Add([pscustomobject]@{
            Y=-0.88+(1.76*($i/14.0))+(($random.NextDouble()-0.5)*0.035)
            Height=0.025+($random.NextDouble()*0.085)
            Wave=0.014+($random.NextDouble()*0.045)
            Frequency=1.15+($random.NextDouble()*2.2)
            Phase=$random.NextDouble()*6.283185
            Alpha=0.14+($random.NextDouble()*0.28)
            Light=(($i+$Planet.Visual.Seed)%3 -eq 0)
        })
    }
    $patches=New-ArrayList
    for($i=0;$i -lt 20;$i++){
        $angle=($i*2.399963)+(($random.NextDouble()-0.5)*0.65);$distance=0.12+(0.80*[Math]::Sqrt(($i+0.5)/20.0));$shape=New-Object double[] 11
        for($pointIndex=0;$pointIndex -lt $shape.Length;$pointIndex++){$shape[$pointIndex]=0.72+($random.NextDouble()*0.48)}
        [void]$patches.Add([pscustomobject]@{
            X=[Math]::Cos($angle)*$distance
            Y=[Math]::Sin($angle)*$distance
            RX=0.07+($random.NextDouble()*0.19)
            RY=0.035+($random.NextDouble()*0.12)
            Rotation=$random.NextDouble()*6.283185
            Alpha=0.30+($random.NextDouble()*0.42)
            Shape=$shape
        })
    }
    $craters=New-ArrayList
    for($i=0;$i -lt 12;$i++){
        $angle=($i*2.399963)+(($random.NextDouble()-0.5)*0.72);$distance=0.10+(0.78*[Math]::Sqrt(($i+0.5)/12.0))
        [void]$craters.Add([pscustomobject]@{X=[Math]::Cos($angle)*$distance;Y=[Math]::Sin($angle)*$distance;R=0.025+($random.NextDouble()*0.075)})
    }
    $fractures=New-ArrayList
    for($i=0;$i -lt 8;$i++){
        $startX=($random.NextDouble()-0.5)*1.72;$startY=($random.NextDouble()-0.5)*1.72;$points=New-Object Drawing.PointF[] 6
        for($pointIndex=0;$pointIndex -lt 6;$pointIndex++){
            $points[$pointIndex]=[Drawing.PointF]::new([single]($startX+(($random.NextDouble()-0.48)*0.12*$pointIndex)),[single]($startY+(0.055*$pointIndex)))
        }
        [void]$fractures.Add($points)
    }
    $outline=New-Object double[] 17
    for($i=0;$i -lt $outline.Length;$i++){$outline[$i]=0.76+($random.NextDouble()*0.25)}
    $geometry=[pscustomobject]@{Bands=$bands;Patches=$patches;Craters=$craters;Fractures=$fractures;Outline=$outline}
    $script:PlanetVisualCache[$key]=$geometry
    return $geometry
}

function Get-EarthVisualGeometry {
    $key="EarthGeographyV2"
    if($script:PlanetVisualCache.ContainsKey($key)){return $script:PlanetVisualCache[$key]}
    $continents=New-ArrayList
    [void]$continents.Add([pscustomobject]@{Name="North America";Tone=0;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(-0.92,-0.42),[Drawing.PointF]::new(-0.82,-0.58),[Drawing.PointF]::new(-0.66,-0.63),
        [Drawing.PointF]::new(-0.57,-0.55),[Drawing.PointF]::new(-0.43,-0.58),[Drawing.PointF]::new(-0.29,-0.50),
        [Drawing.PointF]::new(-0.20,-0.37),[Drawing.PointF]::new(-0.25,-0.26),[Drawing.PointF]::new(-0.18,-0.17),
        [Drawing.PointF]::new(-0.22,-0.08),[Drawing.PointF]::new(-0.31,-0.05),[Drawing.PointF]::new(-0.37,0.08),
        [Drawing.PointF]::new(-0.29,0.17),[Drawing.PointF]::new(-0.35,0.21),[Drawing.PointF]::new(-0.45,0.08),
        [Drawing.PointF]::new(-0.53,-0.01),[Drawing.PointF]::new(-0.58,-0.13),[Drawing.PointF]::new(-0.70,-0.18),
        [Drawing.PointF]::new(-0.79,-0.29)
    )})
    [void]$continents.Add([pscustomobject]@{Name="South America";Tone=1;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(-0.34,0.17),[Drawing.PointF]::new(-0.20,0.13),[Drawing.PointF]::new(-0.08,0.22),
        [Drawing.PointF]::new(-0.02,0.35),[Drawing.PointF]::new(-0.08,0.51),[Drawing.PointF]::new(-0.15,0.68),
        [Drawing.PointF]::new(-0.22,0.82),[Drawing.PointF]::new(-0.29,0.69),[Drawing.PointF]::new(-0.32,0.52),
        [Drawing.PointF]::new(-0.40,0.35),[Drawing.PointF]::new(-0.43,0.24)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Greenland";Tone=2;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(-0.33,-0.67),[Drawing.PointF]::new(-0.23,-0.82),[Drawing.PointF]::new(-0.10,-0.76),
        [Drawing.PointF]::new(-0.07,-0.62),[Drawing.PointF]::new(-0.15,-0.50),[Drawing.PointF]::new(-0.27,-0.54)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Europe";Tone=0;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(-0.08,-0.31),[Drawing.PointF]::new(0.00,-0.40),[Drawing.PointF]::new(0.13,-0.42),
        [Drawing.PointF]::new(0.20,-0.34),[Drawing.PointF]::new(0.14,-0.27),[Drawing.PointF]::new(0.22,-0.21),
        [Drawing.PointF]::new(0.15,-0.14),[Drawing.PointF]::new(0.05,-0.18),[Drawing.PointF]::new(-0.03,-0.12),
        [Drawing.PointF]::new(-0.10,-0.20)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Scandinavia";Tone=1;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(0.03,-0.43),[Drawing.PointF]::new(0.08,-0.60),[Drawing.PointF]::new(0.17,-0.67),
        [Drawing.PointF]::new(0.20,-0.54),[Drawing.PointF]::new(0.15,-0.40)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Africa";Tone=1;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(-0.10,-0.13),[Drawing.PointF]::new(0.08,-0.18),[Drawing.PointF]::new(0.21,-0.10),
        [Drawing.PointF]::new(0.28,0.04),[Drawing.PointF]::new(0.22,0.21),[Drawing.PointF]::new(0.14,0.42),
        [Drawing.PointF]::new(0.03,0.58),[Drawing.PointF]::new(-0.07,0.41),[Drawing.PointF]::new(-0.13,0.22),
        [Drawing.PointF]::new(-0.19,0.05),[Drawing.PointF]::new(-0.17,-0.06)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Middle East";Tone=0;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(0.14,-0.21),[Drawing.PointF]::new(0.25,-0.27),[Drawing.PointF]::new(0.37,-0.20),
        [Drawing.PointF]::new(0.44,-0.10),[Drawing.PointF]::new(0.39,0.02),[Drawing.PointF]::new(0.31,0.10),
        [Drawing.PointF]::new(0.24,0.00),[Drawing.PointF]::new(0.18,-0.07)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Asia";Tone=0;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(0.15,-0.41),[Drawing.PointF]::new(0.32,-0.53),[Drawing.PointF]::new(0.53,-0.52),
        [Drawing.PointF]::new(0.73,-0.45),[Drawing.PointF]::new(0.89,-0.34),[Drawing.PointF]::new(0.94,-0.22),
        [Drawing.PointF]::new(0.81,-0.13),[Drawing.PointF]::new(0.66,-0.16),[Drawing.PointF]::new(0.57,-0.05),
        [Drawing.PointF]::new(0.47,-0.08),[Drawing.PointF]::new(0.40,0.05),[Drawing.PointF]::new(0.34,0.22),
        [Drawing.PointF]::new(0.25,0.12),[Drawing.PointF]::new(0.23,-0.03),[Drawing.PointF]::new(0.13,-0.15),
        [Drawing.PointF]::new(0.21,-0.28)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Southeast Asia";Tone=1;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(0.46,0.02),[Drawing.PointF]::new(0.57,0.08),[Drawing.PointF]::new(0.64,0.20),
        [Drawing.PointF]::new(0.58,0.28),[Drawing.PointF]::new(0.49,0.19),[Drawing.PointF]::new(0.42,0.11)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Australia";Tone=1;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(0.53,0.39),[Drawing.PointF]::new(0.70,0.34),[Drawing.PointF]::new(0.84,0.43),
        [Drawing.PointF]::new(0.86,0.55),[Drawing.PointF]::new(0.74,0.66),[Drawing.PointF]::new(0.57,0.62),
        [Drawing.PointF]::new(0.48,0.51)
    )})
    [void]$continents.Add([pscustomobject]@{Name="Antarctica";Tone=2;Points=[Drawing.PointF[]]@(
        [Drawing.PointF]::new(-0.76,0.84),[Drawing.PointF]::new(-0.53,0.80),[Drawing.PointF]::new(-0.28,0.86),
        [Drawing.PointF]::new(-0.04,0.82),[Drawing.PointF]::new(0.21,0.87),[Drawing.PointF]::new(0.46,0.81),
        [Drawing.PointF]::new(0.70,0.86),[Drawing.PointF]::new(0.62,0.97),[Drawing.PointF]::new(0.26,1.01),
        [Drawing.PointF]::new(-0.12,0.98),[Drawing.PointF]::new(-0.48,1.01)
    )})
    $islands=@(
        [pscustomobject]@{Name="United Kingdom";X=-0.12;Y=-0.30;RX=0.025;RY=0.055;Tone=0},
        [pscustomobject]@{Name="Madagascar";X=0.30;Y=0.44;RX=0.025;RY=0.065;Tone=1},
        [pscustomobject]@{Name="Japan";X=0.78;Y=-0.08;RX=0.020;RY=0.060;Tone=0},
        [pscustomobject]@{Name="Indonesia";X=0.68;Y=0.29;RX=0.050;RY=0.022;Tone=1},
        [pscustomobject]@{Name="New Zealand";X=0.88;Y=0.68;RX=0.018;RY=0.050;Tone=1}
    )
    $earth=[pscustomobject]@{Continents=$continents;Islands=$islands}
    $script:PlanetVisualCache[$key]=$earth
    return $earth
}

function Draw-EarthSurface {
    param([Drawing.Graphics] $Graphics,[double] $CenterX,[double] $CenterY,[double] $Radius,[double] $WidthScale,[int] $Alpha,[bool] $Detailed)
    $earth=Get-EarthVisualGeometry
    $tones=@(
        [Drawing.Color]::FromArgb([int]($Alpha*0.82),40,142,72),
        [Drawing.Color]::FromArgb([int]($Alpha*0.78),65,163,82),
        [Drawing.Color]::FromArgb([int]($Alpha*0.86),130,177,151)
    )
    foreach($continent in $earth.Continents){
        $offsetX=0.0;$offsetY=0.0
        switch([string]$continent.Name){
            "Greenland" {$offsetY=-0.10}
            "Africa" {$offsetX=0.12}
            "Australia" {$offsetX=0.10}
        }
        $points=New-Object Drawing.PointF[] $continent.Points.Length
        for($i=0;$i -lt $continent.Points.Length;$i++){
            $pointOffsetX=$offsetX
            if($continent.Name -eq "Asia"){
                $eastFactor=Get-ClampedValue (($continent.Points[$i].X-0.13)/0.81) 0.0 1.0
                $pointOffsetX=0.10+(0.22*$eastFactor)
            }elseif($continent.Name -eq "Southeast Asia"){
                $eastFactor=Get-ClampedValue (($continent.Points[$i].X-0.42)/0.22) 0.0 1.0
                $pointOffsetX=0.12+(0.12*$eastFactor)
            }
            $points[$i]=[Drawing.PointF]::new([single]($CenterX+(($continent.Points[$i].X+$pointOffsetX)*$Radius*$WidthScale)),[single]($CenterY+(($continent.Points[$i].Y+$offsetY)*$Radius)))
        }
        Fill-ClosedCurveColor $Graphics $tones[[int]$continent.Tone] $points 0.14
        if($Detailed){
            $coastPen=$script:Assets.FramePen
            $coastPen.Color=[Drawing.Color]::FromArgb([int]($Alpha*0.48),111,196,119);$coastPen.Width=[single][Math]::Min(4.0,[Math]::Max(0.8,$Radius*0.008));$coastPen.DashStyle=[Drawing.Drawing2D.DashStyle]::Solid;$coastPen.StartCap=[Drawing.Drawing2D.LineCap]::Round;$coastPen.EndCap=[Drawing.Drawing2D.LineCap]::Round
            $Graphics.DrawClosedCurve($coastPen,$points,0.14,[Drawing.Drawing2D.FillMode]::Winding)
        }
    }
    if($Detailed){
        foreach($island in $earth.Islands){
            $offsetX=0.0
            switch([string]$island.Name){
                "Madagascar" {$offsetX=0.12}
                "Japan" {$offsetX=0.28}
                "Indonesia" {$offsetX=0.24}
                "New Zealand" {$offsetX=0.10}
            }
            $islandRect=[Drawing.RectangleF]::new($CenterX+((($island.X+$offsetX)-$island.RX)*$Radius*$WidthScale),$CenterY+(($island.Y-$island.RY)*$Radius),$island.RX*2*$Radius*$WidthScale,$island.RY*2*$Radius)
            Fill-EllipseColor $Graphics $tones[[int]$island.Tone] $islandRect
        }
    }
}

function Draw-PlanetRingLayer {
    param(
        [Drawing.Graphics] $Graphics,
        $Planet,
        [double] $CenterX,
        [double] $CenterY,
        [double] $Radius,
        [int] $Alpha,
        [bool] $Front
    )
    $ringTilt=if($Planet.Visual.ContainsKey("RingTilt")){[double]$Planet.Visual.RingTilt}else{0.0}
    $saved=$Graphics.Save()
    $Graphics.TranslateTransform([single]$CenterX,[single]$CenterY)
    $Graphics.RotateTransform([single]$ringTilt)
    $Graphics.TranslateTransform([single](-$CenterX),[single](-$CenterY))
    if($Front){
        $pen=New-Object Drawing.Pen((Get-AlphaColor (Get-Color White) ([int]($Alpha*0.4))),[single][Math]::Max(1.0,$Radius*0.055))
        try{$Graphics.DrawArc($pen,$CenterX-($Radius*1.75),$CenterY-($Radius*0.42),$Radius*3.5,$Radius*0.84,0,180)}finally{$pen.Dispose();$Graphics.Restore($saved)}
    }else{
        $pen=New-Object Drawing.Pen((Get-AlphaColor (Get-Color $Planet.Visual.Secondary) ([int]($Alpha*0.48))),[single][Math]::Max(1.0,$Radius*0.12))
        try{$Graphics.DrawEllipse($pen,$CenterX-($Radius*1.75),$CenterY-($Radius*0.42),$Radius*3.5,$Radius*0.84)}finally{$pen.Dispose();$Graphics.Restore($saved)}
    }
}

function Draw-PlanetVector {
    param(
        [Drawing.Graphics] $Graphics,
        $Planet,
        [double] $CenterX,
        [double] $CenterY,
        [double] $Radius,
        [int] $Alpha = 255,
        [bool] $Detailed = $true
    )
    if ($Radius -le 1 -or $Alpha -le 0) { return }
    $geometry=Get-PlanetVisualGeometry $Planet
    if($Planet.Name -eq "Earth"){
        $primary=[Drawing.Color]::FromArgb($Alpha,31,117,192)
        $secondary=[Drawing.Color]::FromArgb($Alpha,8,49,112)
    }else{
        $primary = Get-AlphaColor (Get-Color $Planet.Visual.Primary) $Alpha
        $secondary = Get-AlphaColor (Get-Color $Planet.Visual.Secondary) $Alpha
    }
    $widthScale = if ($Planet.Visual.Feature -eq "Elongated") { 1.32 } else { 1.0 }
    $width = $Radius * 2.0 * $widthScale
    $rect = [Drawing.RectangleF]::new($CenterX - ($width / 2), $CenterY - $Radius, $width, $Radius*2.0)
    $showRings=[bool]$Planet.Visual.Rings -and $Radius -lt 700

    if ($showRings) { Draw-PlanetRingLayer $Graphics $Planet $CenterX $CenterY $Radius $Alpha $false }

    if ($Planet.Type -eq "Asteroid") {
        $outlinePoints=New-Object Drawing.PointF[] $geometry.Outline.Length
        for($i=0;$i -lt $geometry.Outline.Length;$i++){
            $angle=($i/[double]$geometry.Outline.Length)*6.283185;$localRadius=$Radius*$geometry.Outline[$i]
            $outlinePoints[$i]=[Drawing.PointF]::new([single]($CenterX+[Math]::Cos($angle)*$localRadius),[single]($CenterY+[Math]::Sin($angle)*$localRadius))
        }
        $asteroidPath=New-Object Drawing.Drawing2D.GraphicsPath
        $asteroidPath.AddPolygon($outlinePoints)
        Fill-PathColor $Graphics $primary $asteroidPath
        if($Detailed){
            for($i=0;$i -lt $outlinePoints.Length;$i++){
                $next=($i+1)%$outlinePoints.Length
                $facet=[Drawing.PointF[]]@([Drawing.PointF]::new([single]($CenterX+$Radius*0.08),[single]($CenterY-$Radius*0.05)),$outlinePoints[$i],$outlinePoints[$next])
                $facetColor=if(($i%3)-eq 0){Get-Color White}elseif(($i%2)-eq 0){Get-Color $Planet.Visual.Secondary}else{Get-Color DarkGray}
                Fill-PolygonColor $Graphics (Get-AlphaColor $facetColor ([int]($Alpha*(0.08+(($i%4)*0.035))))) $facet
            }
            foreach($crater in $geometry.Craters | Select-Object -First 8){
                $cr=$Radius*$crater.R;$cx=$CenterX+($crater.X*$Radius);$cy=$CenterY+($crater.Y*$Radius)
                Fill-EllipseColor $Graphics (Get-AlphaColor (Get-Color DarkGray) ([int]($Alpha*0.75))) ([Drawing.RectangleF]::new($cx-$cr,$cy-$cr*0.65,$cr*2,$cr*1.3))
                $craterPen=New-Object Drawing.Pen((Get-AlphaColor (Get-Color White) ([int]($Alpha*0.22))),[single][Math]::Max(1,$Radius*0.012))
                try{$Graphics.DrawArc($craterPen,$cx-$cr,$cy-$cr*0.65,$cr*2,$cr*1.3,195,155)}finally{$craterPen.Dispose()}
            }
        }
        $outlinePen=New-Object Drawing.Pen((Get-AlphaColor (Get-Color White) ([int]($Alpha*0.34))),[single][Math]::Max(1,$Radius*0.025))
        try{$Graphics.DrawPolygon($outlinePen,$outlinePoints)}finally{$outlinePen.Dispose();$asteroidPath.Dispose()}
        if($showRings){Draw-PlanetRingLayer $Graphics $Planet $CenterX $CenterY $Radius $Alpha $true}
        return
    }

    $planetPath = New-Object Drawing.Drawing2D.GraphicsPath
    $planetPath.AddEllipse($rect)
    $gradient = New-Object Drawing.Drawing2D.LinearGradientBrush([Drawing.PointF]::new($rect.Left, $rect.Top), [Drawing.PointF]::new($rect.Right, $rect.Bottom), $secondary, $primary)
    try { $Graphics.FillPath($gradient, $planetPath) }
    finally { $gradient.Dispose() }

    $surfaceState = $Graphics.Save()
    $Graphics.SetClip($planetPath)
    $Graphics.TranslateTransform([single]$CenterX,[single]$CenterY)
    $Graphics.RotateTransform([single]$Planet.Visual.Tilt)
    $Graphics.TranslateTransform([single](-$CenterX),[single](-$CenterY))
    if ($Planet.Type -in @("Gas Giant", "Ice Giant")) {
        $bandStep=if($Detailed){1}else{4}
        for($bandIndex=0;$bandIndex -lt $geometry.Bands.Count;$bandIndex+=$bandStep){
            $band=$geometry.Bands[$bandIndex];$lim=[Math]::Sqrt([Math]::Max(0.02,1.0-($band.Y*$band.Y)));$samples=if($Detailed){28}else{12}
            $points=New-Object Drawing.PointF[] (($samples+1)*2)
            for($pointIndex=0;$pointIndex -le $samples;$pointIndex++){
                $xNorm=-$lim+(2.0*$lim*($pointIndex/[double]$samples));$wave=[Math]::Sin(($xNorm*$band.Frequency*3.141593)+$band.Phase)*$band.Wave
                $points[$pointIndex]=[Drawing.PointF]::new([single]($CenterX+($xNorm*$Radius*$widthScale)),[single]($CenterY+(($band.Y+$wave-$band.Height*0.5)*$Radius)))
                $reverse=(($samples+1)*2)-1-$pointIndex
                $points[$reverse]=[Drawing.PointF]::new([single]($CenterX+($xNorm*$Radius*$widthScale)),[single]($CenterY+(($band.Y+$wave+$band.Height*0.5)*$Radius)))
            }
            $bandColor=if($band.Light){Get-Color White}else{Get-Color $Planet.Visual.Secondary}
            Fill-PolygonColor $Graphics (Get-AlphaColor $bandColor ([int]($Alpha*$band.Alpha))) $points
        }
        if ($Planet.Visual.Feature -in @("GreatStorm", "DarkStorm")) {
            $stormColor = if ($Planet.Visual.Feature -eq "GreatStorm") { Get-Color DarkRed } else { Get-Color DarkBlue }
            Fill-EllipseColor $Graphics (Get-AlphaColor $stormColor ([int]($Alpha * 0.78))) ([Drawing.RectangleF]::new($CenterX+$Radius*0.10,$CenterY+$Radius*0.12,$Radius*0.66,$Radius*0.26))
            $stormPen=New-Object Drawing.Pen((Get-AlphaColor (Get-Color White) ([int]($Alpha*0.28))),[single][Math]::Max(1,$Radius*0.018))
            try{$Graphics.DrawArc($stormPen,$CenterX+$Radius*0.13,$CenterY+$Radius*0.14,$Radius*0.57,$Radius*0.20,190,300)}finally{$stormPen.Dispose()}
        }
    } else {
        if($Planet.Name -eq "Earth"){
            Draw-EarthSurface $Graphics $CenterX $CenterY $Radius $widthScale $Alpha $Detailed
        }else{
            $featureCount=if($Detailed){$geometry.Patches.Count}else{4}
            $featureColor=if($Planet.Visual.Feature -eq "Oceans"){Get-Color Green}elseif($Planet.Visual.Feature -eq "Lava"){Get-Color Yellow}else{Get-Color $Planet.Visual.Secondary}
            for($patchIndex=0;$patchIndex -lt $featureCount;$patchIndex++){
                $patch=$geometry.Patches[$patchIndex];$shapePoints=New-Object Drawing.PointF[] $patch.Shape.Length
                for($pointIndex=0;$pointIndex -lt $patch.Shape.Length;$pointIndex++){
                    $angle=$patch.Rotation+(($pointIndex/[double]$patch.Shape.Length)*6.283185);$shapeRadius=$patch.Shape[$pointIndex]
                    $shapePoints[$pointIndex]=[Drawing.PointF]::new([single]($CenterX+(($patch.X+[Math]::Cos($angle)*$patch.RX*$shapeRadius)*$Radius*$widthScale)),[single]($CenterY+(($patch.Y+[Math]::Sin($angle)*$patch.RY*$shapeRadius)*$Radius)))
                }
                Fill-PolygonColor $Graphics (Get-AlphaColor $featureColor ([int]($Alpha*$patch.Alpha))) $shapePoints
            }
        }
        if($Detailed -and $Planet.Visual.Feature -in @("Craters","Icy","RedIce")){
            foreach($crater in $geometry.Craters){
                $cr=$Radius*$crater.R;$cx=$CenterX+($crater.X*$Radius*$widthScale);$cy=$CenterY+($crater.Y*$Radius)
                Fill-EllipseColor $Graphics (Get-AlphaColor (Get-Color DarkGray) ([int]($Alpha*0.34))) ([Drawing.RectangleF]::new($cx-$cr,$cy-$cr*0.62,$cr*2,$cr*1.24))
            }
        }
        if($Detailed -and $Planet.Visual.Feature -in @("Canyons","Lava","Icy","RedIce","Outpost")){
            $lineColor=if($Planet.Visual.Feature -eq "Lava"){Get-Color Yellow}elseif($Planet.Visual.Feature -in @("Icy","RedIce")){Get-Color White}else{Get-Color DarkGray}
            $featurePen=New-Object Drawing.Pen((Get-AlphaColor $lineColor ([int]($Alpha*0.48))),[single][Math]::Max(1,$Radius*0.012))
            try{
                foreach($fracture in $geometry.Fractures){
                    $linePoints=New-Object Drawing.PointF[] $fracture.Length
                    for($pointIndex=0;$pointIndex -lt $fracture.Length;$pointIndex++){$linePoints[$pointIndex]=[Drawing.PointF]::new([single]($CenterX+($fracture[$pointIndex].X*$Radius*$widthScale)),[single]($CenterY+($fracture[$pointIndex].Y*$Radius)))}
                    $Graphics.DrawLines($featurePen,$linePoints)
                }
            }finally{$featurePen.Dispose()}
        }
        if($Detailed -and $Planet.Visual.Feature -in @("Clouds","Oceans")){
            $cloudPen=New-Object Drawing.Pen((Get-AlphaColor (Get-Color White) ([int]($Alpha*0.24))),[single][Math]::Max(1,$Radius*0.025))
            try{
                for($bandIndex=1;$bandIndex -lt $geometry.Bands.Count;$bandIndex+=3){
                    $band=$geometry.Bands[$bandIndex];$lim=[Math]::Sqrt([Math]::Max(0.02,1.0-($band.Y*$band.Y)));$cloudPoints=New-Object Drawing.PointF[] 18
                    for($pointIndex=0;$pointIndex -lt 18;$pointIndex++){$xNorm=-$lim+(2.0*$lim*($pointIndex/17.0));$wave=[Math]::Sin(($xNorm*$band.Frequency*3.141593)+$band.Phase)*$band.Wave;$cloudPoints[$pointIndex]=[Drawing.PointF]::new([single]($CenterX+($xNorm*$Radius*$widthScale)),[single]($CenterY+(($band.Y+$wave)*$Radius)))}
                    $Graphics.DrawLines($cloudPen,$cloudPoints)
                }
            }finally{$cloudPen.Dispose()}
        }
    }
    $Graphics.Restore($surfaceState)

    $shade = New-Object Drawing.Drawing2D.LinearGradientBrush([Drawing.PointF]::new($rect.Left, $CenterY), [Drawing.PointF]::new($rect.Right, $CenterY), [Drawing.Color]::FromArgb([int]($Alpha*0.72),0,0,0), [Drawing.Color]::FromArgb(0,0,0,0))
    try { $Graphics.FillPath($shade, $planetPath) }
    finally { $shade.Dispose() }
    $planetPath.Dispose()

    $atmosphereWidth=[Math]::Min(12.0,[Math]::Max(1.0,$Radius*0.035))
    $atmosphere = New-Object Drawing.Pen((Get-AlphaColor $primary ([int]($Alpha * 0.58))), [single]$atmosphereWidth)
    try { $Graphics.DrawEllipse($atmosphere, $rect) }
    finally { $atmosphere.Dispose() }

    if ($showRings) { Draw-PlanetRingLayer $Graphics $Planet $CenterX $CenterY $Radius $Alpha $true }
}

function Get-PlanetBitmap {
    param($Planet,[bool] $Detailed,[double] $Radius,[double] $DeviceScale)
    $pixelRadius=[Math]::Max(2,[int][Math]::Round($Radius*$DeviceScale))
    $key=("{0}|{1}|{2}" -f $Planet.Name,$Detailed,$pixelRadius)
    if($script:PlanetBitmapCache.ContainsKey($key)){return $script:PlanetBitmapCache[$key]}
    $size=[Math]::Max(16,[int][Math]::Ceiling($pixelRadius*4.0))
    $bitmap=New-Object Drawing.Bitmap($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        Draw-PlanetVector $graphics $Planet ($size/2.0) ($size/2.0) $pixelRadius 255 $Detailed
    }finally{$graphics.Dispose()}
    $script:PlanetBitmapCache[$key]=$bitmap
    $script:PlanetBitmapCacheBytes+=[long]$bitmap.Width*[long]$bitmap.Height*4L
    [void]$script:PlanetBitmapCacheOrder.Add($key)
    while($script:PlanetBitmapCacheOrder.Count -gt 18 -or ($script:PlanetBitmapCacheBytes -gt 48MB -and $script:PlanetBitmapCacheOrder.Count -gt 1)){
        $oldKey=[string]$script:PlanetBitmapCacheOrder[0];$script:PlanetBitmapCacheOrder.RemoveAt(0)
        if($script:PlanetBitmapCache.ContainsKey($oldKey)){
            $oldBitmap=$script:PlanetBitmapCache[$oldKey]
            $script:PlanetBitmapCacheBytes-=[long]$oldBitmap.Width*[long]$oldBitmap.Height*4L
            $oldBitmap.Dispose();$script:PlanetBitmapCache.Remove($oldKey)
        }
    }
    return $bitmap
}

function Get-FrackPlanetBitmap {
    param($Planet,[double] $DeviceScale)
    $renderScale=[Math]::Max(0.25,$DeviceScale)
    $key=("{0}|{1:N3}" -f $Planet.Name,$renderScale)
    if($script:FrackPlanetBitmap -is [Drawing.Bitmap] -and $script:FrackPlanetBitmapKey -eq $key){return $script:FrackPlanetBitmap}
    if($script:FrackPlanetBitmap -is [IDisposable]){$script:FrackPlanetBitmap.Dispose()}
    $width=[Math]::Max(1,[int][Math]::Ceiling($script:VirtualWidth*$renderScale))
    $height=[Math]::Max(1,[int][Math]::Ceiling(($script:ViewportBottom+5)*$renderScale))
    $bitmap=New-Object Drawing.Bitmap($width,$height,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        Draw-PlanetVector $graphics $Planet (640.0*$renderScale) ($script:FrackPlanetCenterY*$renderScale) ($script:FrackPlanetRadius*$renderScale) 255 $true
    }finally{$graphics.Dispose()}
    $script:FrackPlanetBitmap=$bitmap
    $script:FrackPlanetBitmapKey=$key
    return $bitmap
}

function Get-PlanetTransitionBitmap {
    param($Planet,[bool] $Detailed)
    $key=("{0}|{1}" -f $Planet.Name,$Detailed)
    if($script:PlanetTransitionBitmapCache.ContainsKey($key)){return $script:PlanetTransitionBitmapCache[$key]}
    $size=if($Detailed){760}else{160}
    $radius=if($Detailed){190.0}else{40.0}
    $bitmap=New-Object Drawing.Bitmap($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        Draw-PlanetVector $graphics $Planet ($size/2.0) ($size/2.0) $radius 255 $Detailed
    }finally{$graphics.Dispose()}
    $script:PlanetTransitionBitmapCache[$key]=$bitmap
    $script:PlanetTransitionCacheBytes+=[long]$bitmap.Width*[long]$bitmap.Height*4L
    [void]$script:PlanetTransitionCacheOrder.Add($key)
    while($script:PlanetTransitionCacheOrder.Count -gt 32 -or ($script:PlanetTransitionCacheBytes -gt 32MB -and $script:PlanetTransitionCacheOrder.Count -gt 1)){
        $oldKey=[string]$script:PlanetTransitionCacheOrder[0];$script:PlanetTransitionCacheOrder.RemoveAt(0)
        if($script:PlanetTransitionBitmapCache.ContainsKey($oldKey)){
            $oldBitmap=$script:PlanetTransitionBitmapCache[$oldKey]
            $script:PlanetTransitionCacheBytes-=[long]$oldBitmap.Width*[long]$oldBitmap.Height*4L
            $oldBitmap.Dispose();$script:PlanetTransitionBitmapCache.Remove($oldKey)
        }
    }
    return $bitmap
}

function Get-ImageAlphaAttributes {
    param([int] $Alpha)
    $bucket=[int](Get-ClampedValue ([Math]::Round($Alpha/16.0)*16.0) 16 240)
    if($script:ImageAlphaAttributes.ContainsKey($bucket)){return $script:ImageAlphaAttributes[$bucket]}
    $matrix=New-Object Drawing.Imaging.ColorMatrix
    $matrix.Matrix33=[single]($bucket/255.0)
    $attributes=New-Object Drawing.Imaging.ImageAttributes
    $attributes.SetColorMatrix($matrix,[Drawing.Imaging.ColorMatrixFlag]::Default,[Drawing.Imaging.ColorAdjustType]::Bitmap)
    $script:ImageAlphaAttributes[$bucket]=$attributes
    return $attributes
}

function Draw-DeviceBitmap {
    param([Drawing.Graphics] $Graphics,[Drawing.Bitmap] $Bitmap,[double] $LogicalCenterX,[double] $LogicalCenterY)
    $physicalX=$script:OffsetX+(($LogicalCenterX+$script:FrameShakeX)*$script:Scale)
    $physicalY=$script:OffsetY+(($LogicalCenterY+$script:FrameShakeY)*$script:Scale)
    $saved=$Graphics.Save()
    try{
        $Graphics.ResetTransform()
        $Graphics.CompositingMode=[Drawing.Drawing2D.CompositingMode]::SourceOver
        $Graphics.DrawImageUnscaled($Bitmap,[int][Math]::Round($physicalX-($Bitmap.Width/2.0)),[int][Math]::Round($physicalY-($Bitmap.Height/2.0)))
    }finally{$Graphics.Restore($saved)}
}

function Draw-Planet {
    param(
        [Drawing.Graphics] $Graphics,
        $Planet,
        [double] $CenterX,
        [double] $CenterY,
        [double] $Radius,
        [int] $Alpha = 255,
        [bool] $Detailed = $true
    )
    if($Radius -le 1 -or $Alpha -le 0){return}
    $cameraStable=$null -ne $script:G -and $null -eq $script:G.Travel -and [Math]::Abs($script:G.SystemBlend-$script:G.TargetSystemBlend) -lt 0.001 -and [Math]::Abs($script:G.TraderBlend-$script:G.TargetTraderBlend) -lt 0.001 -and [Math]::Abs($script:G.CloseZoom-$script:G.TargetCloseZoom) -lt 0.001
    if($cameraStable -and $Alpha -ge 250 -and [Math]::Abs($CenterX-640.0) -lt 2.0 -and [Math]::Abs($CenterY-$script:FrackPlanetCenterY) -lt 3.0 -and [Math]::Abs($Radius-$script:FrackPlanetRadius) -lt 3.0){
        $bitmap=Get-FrackPlanetBitmap $Planet $script:Scale
        $originX=$script:OffsetX+($script:FrameShakeX*$script:Scale)
        $originY=$script:OffsetY+($script:FrameShakeY*$script:Scale)
        $saved=$Graphics.Save()
        try{$Graphics.ResetTransform();$Graphics.DrawImageUnscaled($bitmap,[int][Math]::Round($originX),[int][Math]::Round($originY))}finally{$Graphics.Restore($saved)}
        return
    }
    if($cameraStable -and $Alpha -ge 250 -and -not $Detailed -and $Radius -le 22.0){
        $bitmap=Get-PlanetBitmap $Planet $false $Radius 1.0
        $Graphics.DrawImage($bitmap,[Drawing.RectangleF]::new([single]($CenterX-($bitmap.Width/2.0)),[single]($CenterY-($bitmap.Height/2.0)),[single]$bitmap.Width,[single]$bitmap.Height))
        return
    }
    if($cameraStable -and $Alpha -ge 250 -and $Radius -le 220.0){
        $bitmap=Get-PlanetBitmap $Planet $Detailed $Radius $script:Scale
        Draw-DeviceBitmap $Graphics $bitmap $CenterX $CenterY
        return
    }
    if(-not $cameraStable -and $script:Scale -le 1.25 -and $Radius -le 300.0){
        $bitmap=Get-PlanetTransitionBitmap $Planet $Detailed
        $baseRadius=if($Detailed){190.0}else{40.0}
        $bitmapScale=$Radius/$baseRadius
        $width=[Math]::Max(1,[int][Math]::Round($bitmap.Width*$bitmapScale));$height=[Math]::Max(1,[int][Math]::Round($bitmap.Height*$bitmapScale))
        $destination=[Drawing.Rectangle]::new([int][Math]::Round($CenterX-($width/2.0)),[int][Math]::Round($CenterY-($height/2.0)),$width,$height)
        if($Alpha -ge 250){$Graphics.DrawImage($bitmap,$destination)}
        else{$Graphics.DrawImage($bitmap,$destination,0,0,$bitmap.Width,$bitmap.Height,[Drawing.GraphicsUnit]::Pixel,(Get-ImageAlphaAttributes $Alpha))}
        return
    }
    Draw-PlanetVector $Graphics $Planet $CenterX $CenterY $Radius $Alpha $Detailed
}

function Draw-TraderVesselVector {
    param([Drawing.Graphics] $Graphics, [double] $X, [double] $Y, [double] $Scale, [Drawing.Color] $Accent)
    $saved=$Graphics.Save()
    $Graphics.TranslateTransform([single]$X, [single]$Y)
    $Graphics.ScaleTransform([single]$Scale, [single]$Scale)
    $alpha=[int]$Accent.A
    $grayDark=[Drawing.Color]::FromArgb($alpha,31,37,41)
    $grayMid=[Drawing.Color]::FromArgb($alpha,78,86,91)
    $grayLight=[Drawing.Color]::FromArgb($alpha,150,159,164)
    $accentDark=[Drawing.Color]::FromArgb($alpha,[int]($Accent.R*0.42),[int]($Accent.G*0.42),[int]($Accent.B*0.42))
    $darkPen=New-Object Drawing.Pen($grayDark,5)
    $midPen=New-Object Drawing.Pen($grayMid,3)
    $lightPen=New-Object Drawing.Pen($grayLight,2)
    $accentPen=New-Object Drawing.Pen($Accent,3)
    try{
        # Lower spindle behind the orbital ring.
        Fill-RectangleColor $Graphics $grayMid ([Drawing.RectangleF]::new(-43,30,86,83))
        Fill-EllipseColor $Graphics $grayLight ([Drawing.RectangleF]::new(-43,20,86,27))
        Fill-EllipseColor $Graphics $grayDark ([Drawing.RectangleF]::new(-43,99,86,28))
        $Graphics.DrawRectangle($darkPen,-43,33,86,77)
        Fill-RectangleColor $Graphics $grayDark ([Drawing.RectangleF]::new(-29,112,58,25))
        Fill-EllipseColor $Graphics $grayMid ([Drawing.RectangleF]::new(-29,126,58,22))
        Fill-RectangleColor $Graphics $grayMid ([Drawing.RectangleF]::new(-15,139,30,18))
        Fill-EllipseColor $Graphics $Accent ([Drawing.RectangleF]::new(-5,153,10,12))

        # Radial braces and the three-layer orbital ring.
        foreach($brace in @(@(-47,8,-145,-2),@(47,8,145,-2),@(-43,31,-132,54),@(43,31,132,54))){
            $Graphics.DrawLine($darkPen,$brace[0],$brace[1],$brace[2],$brace[3])
            $Graphics.DrawLine($lightPen,$brace[0],$brace[1],$brace[2],$brace[3])
        }
        $ringRect=[Drawing.RectangleF]::new(-164,-35,328,103)
        $ringOuter=New-Object Drawing.Pen($grayDark,28)
        $ringLight=New-Object Drawing.Pen($grayLight,22)
        $ringCore=New-Object Drawing.Pen($grayMid,14)
        try{$Graphics.DrawEllipse($ringOuter,$ringRect);$Graphics.DrawEllipse($ringLight,$ringRect);$Graphics.DrawEllipse($ringCore,$ringRect)}finally{$ringOuter.Dispose();$ringLight.Dispose();$ringCore.Dispose()}
        foreach($dashX in @(-128,-88,-48,48,88,128)){Fill-RectangleColor $Graphics $Accent ([Drawing.RectangleF]::new($dashX,49,25,5))}
        Fill-RectangleColor $Graphics $accentDark ([Drawing.RectangleF]::new(-10,55,20,6))

        # Mirrored docking gantries and cargo pods.
        foreach($side in @(-1,1)){
            $moduleX=if($side -lt 0){-222}else{142}
            $bridgeX=if($side -lt 0){-181}else{142}
            Fill-RectangleColor $Graphics $grayDark ([Drawing.RectangleF]::new($bridgeX,7,39,38))
            Fill-RectangleColor $Graphics $grayLight ([Drawing.RectangleF]::new($bridgeX+3,10,33,8))
            Fill-RectangleColor $Graphics $Accent ([Drawing.RectangleF]::new($(if($side -lt 0){$bridgeX+30}else{$bridgeX}),8,6,35))
            Fill-RectangleColor $Graphics $grayMid ([Drawing.RectangleF]::new($moduleX,-2,80,58))
            $Graphics.DrawRectangle($darkPen,$moduleX,-2,80,58)
            Fill-RectangleColor $Graphics $grayLight ([Drawing.RectangleF]::new($moduleX+5,3,70,8))
            Fill-RectangleColor $Graphics $accentDark ([Drawing.RectangleF]::new($(if($side -lt 0){$moduleX+5}else{$moduleX+57}),20,18,24))
            Fill-RectangleColor $Graphics $Accent ([Drawing.RectangleF]::new($(if($side -lt 0){$moduleX+7}else{$moduleX+59}),23,14,18))
            foreach($podOffset in @(10,35)){Fill-RectangleColor $Graphics $Accent ([Drawing.RectangleF]::new($moduleX+$podOffset,-18,21,17));$Graphics.DrawRectangle($midPen,$moduleX+$podOffset,-18,21,17)}
            foreach($lampOffset in @(30,41,52)){Fill-EllipseColor $Graphics $Accent ([Drawing.RectangleF]::new($moduleX+$lampOffset,28,7,7))}
        }

        # Stacked command hub and illuminated observation band.
        Fill-RectangleColor $Graphics $grayMid ([Drawing.RectangleF]::new(-67,-47,134,70))
        Fill-EllipseColor $Graphics $grayLight ([Drawing.RectangleF]::new(-67,-62,134,42))
        Fill-EllipseColor $Graphics $grayDark ([Drawing.RectangleF]::new(-67,7,134,35))
        $Graphics.DrawRectangle($darkPen,-67,-43,134,63)
        Fill-RectangleColor $Graphics $grayDark ([Drawing.RectangleF]::new(-62,-29,124,25))
        for($i=0;$i -lt 7;$i++){Fill-RectangleColor $Graphics $Accent ([Drawing.RectangleF]::new(-55+($i*17),-25,12,17))}
        Fill-EllipseColor $Graphics $grayLight ([Drawing.RectangleF]::new(-50,-78,100,34))
        Fill-EllipseColor $Graphics $grayMid ([Drawing.RectangleF]::new(-38,-90,76,29))
        Fill-RectangleColor $Graphics $grayMid ([Drawing.RectangleF]::new(-20,-111,40,28))
        Fill-EllipseColor $Graphics $grayLight ([Drawing.RectangleF]::new(-20,-119,40,17))

        # Communications mast and offset dish.
        Fill-RectangleColor $Graphics $grayDark ([Drawing.RectangleF]::new(-5,-158,10,43))
        Fill-RectangleColor $Graphics $grayLight ([Drawing.RectangleF]::new(-2,-158,4,31))
        Fill-RectangleColor $Graphics $Accent ([Drawing.RectangleF]::new(-5,-170,10,17))
        $dishState=$Graphics.Save()
        try{
            $Graphics.TranslateTransform(45,-112)
            $Graphics.RotateTransform(28)
            Fill-EllipseColor $Graphics $grayLight ([Drawing.RectangleF]::new(-25,-12,50,25))
            $Graphics.DrawEllipse($darkPen,-25,-12,50,25)
            $Graphics.DrawLine($darkPen,0,0,0,-23)
            Fill-EllipseColor $Graphics $Accent ([Drawing.RectangleF]::new(-6,-29,12,12))
        }finally{$Graphics.Restore($dishState)}
        $Graphics.DrawArc($accentPen,-158,-31,316,95,8,164)
    }finally{
        $darkPen.Dispose();$midPen.Dispose();$lightPen.Dispose();$accentPen.Dispose()
        $Graphics.Restore($saved)
    }
}

function Get-TraderVesselBitmap {
    param([Drawing.Color] $Accent,[double] $DeviceScale)
    $renderScale=[Math]::Max(0.08,$DeviceScale)
    $key=("{0}|{1}|{2}|{3:N3}" -f $Accent.R,$Accent.G,$Accent.B,$renderScale)
    if($script:TraderVesselBitmapCache.ContainsKey($key)){return $script:TraderVesselBitmapCache[$key]}
    # The docking modules extend to roughly +/-222 local units. Keep transparent
    # padding around the complete painted bounds so the stationary cache matches
    # the unclipped transition vector.
    $size=[Math]::Max(32,[int][Math]::Ceiling(480.0*$renderScale))
    $bitmap=New-Object Drawing.Bitmap($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        Draw-TraderVesselVector $graphics ($size/2.0) ($size/2.0) $renderScale ([Drawing.Color]::FromArgb(255,$Accent.R,$Accent.G,$Accent.B))
    }finally{$graphics.Dispose()}
    $script:TraderVesselBitmapCache[$key]=$bitmap
    return $bitmap
}

function Draw-TraderVessel {
    param([Drawing.Graphics] $Graphics,[double] $X,[double] $Y,[double] $Scale,[Drawing.Color] $Accent)
    $cameraStable=$null -ne $script:G -and $null -eq $script:G.Travel -and [Math]::Abs($script:G.SystemBlend-$script:G.TargetSystemBlend) -lt 0.001 -and [Math]::Abs($script:G.TraderBlend-$script:G.TargetTraderBlend) -lt 0.001 -and [Math]::Abs($script:G.CloseZoom-$script:G.TargetCloseZoom) -lt 0.001
    if($cameraStable -and $Accent.A -ge 250){
        if([Math]::Abs($script:TraderVesselBitmapDeviceScale-$script:Scale) -gt 0.002){
            foreach($cachedBitmap in @($script:TraderVesselBitmapCache.Values)){$cachedBitmap.Dispose()}
            $script:TraderVesselBitmapCache=@{};$script:TraderVesselBitmapDeviceScale=$script:Scale
        }
        $bitmap=Get-TraderVesselBitmap $Accent ($Scale*$script:Scale)
        Draw-DeviceBitmap $Graphics $bitmap $X $Y
        return
    }
    Draw-TraderVesselVector $Graphics $X $Y $Scale $Accent
}

function Draw-SystemView {
    param([Drawing.Graphics] $Graphics, [int] $Alpha)
    if ($Alpha -le 0) { return }
    $system=$script:G.Systems[$script:G.Player.SystemId]
    $starColor=Get-Color $system.StarColor
    $starX = 74.0; $centerY = 245.0
    for ($i = 3; $i -ge 1; $i--) {
        Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb([int](12*$i*($Alpha/255.0)),$starColor.R,$starColor.G,$starColor.B)) ([Drawing.RectangleF]::new($starX-(42+$i*10),$centerY-(42+$i*10),(84+$i*20),(84+$i*20)))
    }
    Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb($Alpha,$starColor.R,$starColor.G,$starColor.B)) ([Drawing.RectangleF]::new($starX-40,$centerY-40,80,80))
    Draw-Text $Graphics $system.Id.ToUpper() $script:Assets.FontSmallBold ([Drawing.Color]::FromArgb($Alpha,$starColor.R,$starColor.G,$starColor.B)) ([Drawing.RectangleF]::new(35,300,80,22)) $script:Assets.Center

    $linePen = New-Object Drawing.Pen([Drawing.Color]::FromArgb([int]($Alpha*0.2),91,130,139),1)
    try { $Graphics.DrawLine($linePen,118,$centerY,1218,$centerY) }
    finally { $linePen.Dispose() }

    foreach ($name in $script:G.PlanetOrder) {
        $planet = $script:G.Planets[$name]
        $x = 135.0 + (($planet.Distance / 69.0) * 1065.0)
        $radius = switch ($planet.Type) { "Gas Giant" { 16.0 } "Ice Giant" { 13.0 } "Asteroid" { 7.0 } "Dwarf" { 7.0 } default { 9.0 } }
        Draw-Planet $Graphics $planet $x $centerY $radius $Alpha $false
        if ($name -eq $script:G.Player.Location) {
            $currentPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb($Alpha,78,232,236),2)
            try { $Graphics.DrawEllipse($currentPen,$x-$radius-7,$centerY-$radius-7,($radius+7)*2,($radius+7)*2) }
            finally { $currentPen.Dispose() }
        }
        $labelRect = [Drawing.RectangleF]::new($x-42,$centerY+28,84,20)
        Draw-Text $Graphics $name $script:Assets.FontTiny ([Drawing.Color]::FromArgb($Alpha,148,164,169)) $labelRect $script:Assets.Center
        $hit = [Drawing.RectangleF]::new($x-24,$centerY-28,48,82)
        Add-HitTarget "SelectPlanet" $hit $name $true
        if (Test-Hover $hit) { $script:G.HoveredPlanet = $name }
    }
}

function Draw-OrbitView {
    param([Drawing.Graphics] $Graphics, [int] $Alpha)
    if ($Alpha -le 0) { return }
    $planet = Get-Planet
    $trader = $script:G.TraderBlend
    $close = $script:G.CloseZoom
    $cx = Get-Lerp 640.0 395.0 $trader
    $cy = Get-Lerp 240.0 244.0 $trader
    $radius = Get-Lerp 166.0 126.0 $trader
    if ($close -gt 0.01) {
        $cx = Get-Lerp $cx 640.0 $close
        $cy = Get-Lerp $cy $script:FrackPlanetCenterY $close
        $radius = Get-Lerp $radius $script:FrackPlanetRadius $close
    }
    Draw-Planet $Graphics $planet $cx $cy $radius $Alpha $true

    if ($planet.Inhabited -and $close -lt 0.3 -and $Alpha -gt 35) {
        $vesselX = Get-Lerp 885.0 850.0 $trader
        $vesselScale = Get-Lerp 0.28 1.0 $trader
        Draw-TraderVessel $Graphics $vesselX 225 $vesselScale (Get-AlphaColor (Get-Color $planet.PlanetColor) $Alpha)
    }

    if ($close -gt 0.12) { Draw-FrackingDebris $Graphics }
}

function Draw-FrackingDebris {
    param([Drawing.Graphics] $Graphics)
    foreach ($particle in $script:G.Particles) {
        $alpha = [int](Get-ClampedValue (($particle.Life/$particle.MaxLife)*255) 0 255)
        $kind=if($particle.PSObject.Properties["Kind"]){[string]$particle.Kind}else{"Debris"}
        if($kind -eq "Spark"){
            $sparkPen=New-Object Drawing.Pen((Get-AlphaColor $particle.Color $alpha),[single]$particle.Size)
            try{
                $sparkPen.StartCap=[Drawing.Drawing2D.LineCap]::Round
                $sparkPen.EndCap=[Drawing.Drawing2D.LineCap]::Round
                $Graphics.DrawLine($sparkPen,[single]$particle.X,[single]$particle.Y,[single]($particle.X-($particle.VX*0.035)),[single]($particle.Y-($particle.VY*0.035)))
            }finally{$sparkPen.Dispose()}
        }else{
            Fill-EllipseColor $Graphics (Get-AlphaColor $particle.Color $alpha) ([Drawing.RectangleF]::new($particle.X-$particle.Size/2,$particle.Y-$particle.Size/2,$particle.Size,$particle.Size))
        }
    }
}

function Draw-TravelView {
    param([Drawing.Graphics] $Graphics)
    if ($null -eq $script:G.Travel) { return }
    $progress = Get-Ease ($script:G.Travel.Time / $script:G.Travel.Duration)
    $from = Get-Planet $script:G.Travel.From
    $to = Get-Planet $script:G.Travel.To
    Draw-Planet $Graphics $from (300 - ($progress*760)) 240 (155 - ($progress*70)) ([int](255*(1-$progress))) $true
    Draw-Planet $Graphics $to (1430 - ($progress*790)) 240 (90 + ($progress*75)) ([int](255*$progress)) $true
}

function Get-SystemPlanetX {
    param($Planet)
    return 135.0 + (($Planet.Distance / 69.0) * 1065.0)
}

function Get-SystemPlanetRadius {
    param($Planet)
    switch($Planet.Type){
        "Gas Giant" {return 16.0}
        "Ice Giant" {return 13.0}
        "Asteroid" {return 7.0}
        "Dwarf" {return 7.0}
        default {return 9.0}
    }
}

function Draw-CameraNavigation {
    param([Drawing.Graphics] $Graphics)
    $system=$script:G.Systems[$script:G.Player.SystemId]
    $starColor=Get-Color $system.StarColor
    $systemBlend=Get-ClampedValue $script:G.SystemBlend 0 1
    $current=Get-Planet
    $cameraStable=$null -eq $script:G.Travel -and [Math]::Abs($script:G.SystemBlend-$script:G.TargetSystemBlend) -lt 0.001 -and [Math]::Abs($script:G.TraderBlend-$script:G.TargetTraderBlend) -lt 0.001 -and [Math]::Abs($script:G.CloseZoom-$script:G.TargetCloseZoom) -lt 0.001
    if($cameraStable -and $systemBlend -lt 0.001){
        $x=Get-Lerp 640.0 395.0 $script:G.TraderBlend
        $y=Get-Lerp 245.0 $script:FrackPlanetCenterY $script:G.CloseZoom
        $radius=Get-Lerp (Get-Lerp 166.0 126.0 $script:G.TraderBlend) $script:FrackPlanetRadius $script:G.CloseZoom
        Draw-Planet $Graphics $current $x $y $radius 255 $true
        if($current.Inhabited -and $script:G.CloseZoom -lt 0.3){
            Draw-TraderVessel $Graphics (Get-Lerp 885.0 850.0 $script:G.TraderBlend) 225 (Get-Lerp 0.28 1.0 $script:G.TraderBlend) (Get-Color $current.PlanetColor)
        }
        return
    }
    $currentSystemX=Get-SystemPlanetX $current
    $travelProgress=-1.0
    $destinationName=""
    if($null -ne $script:G.Travel){
        $travelProgress=Get-Ease ($script:G.Travel.Time/$script:G.Travel.Duration)
        $destinationName=$script:G.Travel.To
        $destination=Get-Planet $destinationName
        $cameraCenter=Get-Lerp 640.0 (Get-SystemPlanetX $destination) $travelProgress
        $cameraZoom=Get-Lerp 1.0 7.0 $travelProgress
        $mapAlpha=[int](255*(1.0-$travelProgress))
    }
    else{
        $focusScreenX=Get-Lerp 640.0 $currentSystemX $systemBlend
        $cameraZoom=Get-Lerp 7.0 1.0 $systemBlend
        $mapAlpha=[int](255*$systemBlend)
    }

    if($travelProgress -ge 0){
        $lineStart=640.0+((118.0-$cameraCenter)*$cameraZoom)
        $lineEnd=640.0+((1218.0-$cameraCenter)*$cameraZoom)
    }
    else{
        $lineStart=$focusScreenX+((118.0-$currentSystemX)*$cameraZoom)
        $lineEnd=$focusScreenX+((1218.0-$currentSystemX)*$cameraZoom)
    }
    if($mapAlpha -gt 2){
        $linePen=$script:Assets.FramePen
        $linePen.Color=[Drawing.Color]::FromArgb([int]($mapAlpha*0.22),91,130,139);$linePen.Width=1;$linePen.DashStyle=[Drawing.Drawing2D.DashStyle]::Solid
        $Graphics.DrawLine($linePen,$lineStart,245,$lineEnd,245)
        $starX=if($travelProgress -ge 0){640.0+((74.0-$cameraCenter)*$cameraZoom)}else{$focusScreenX+((74.0-$currentSystemX)*$cameraZoom)}
        $starRadius=40.0*$cameraZoom
        if($starX+$starRadius -gt -20 -and $starX-$starRadius -lt 1300){
            Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb([int]($mapAlpha*0.12),$starColor.R,$starColor.G,$starColor.B)) ([Drawing.RectangleF]::new($starX-$starRadius*1.55,245-$starRadius*1.55,$starRadius*3.1,$starRadius*3.1))
            Fill-EllipseColor $Graphics ([Drawing.Color]::FromArgb($mapAlpha,$starColor.R,$starColor.G,$starColor.B)) ([Drawing.RectangleF]::new($starX-$starRadius,245-$starRadius,$starRadius*2,$starRadius*2))
        }
    }

    foreach($name in $script:G.PlanetOrder){
        $planet=$script:G.Planets[$name]
        $systemX=Get-SystemPlanetX $planet
        $baseRadius=Get-SystemPlanetRadius $planet
        $x=if($travelProgress -ge 0){640.0+(($systemX-$cameraCenter)*$cameraZoom)}else{$focusScreenX+(($systemX-$currentSystemX)*$cameraZoom)}
        $y=245.0
        $radius=$baseRadius*$cameraZoom
        $alpha=$mapAlpha

        if($travelProgress -ge 0){
            if($name -eq $destinationName){
                $radius=Get-Lerp $baseRadius 166.0 $travelProgress
                $alpha=255
            }
            elseif($travelProgress -gt 0.55){$alpha=[int](255*(1.0-$travelProgress))}
        }
        elseif($name -eq $script:G.Player.Location){
            $radius=Get-Lerp 166.0 $baseRadius $systemBlend
            $alpha=255
            if($script:G.TraderBlend -gt 0.01){
                $x=Get-Lerp $x 395.0 $script:G.TraderBlend
                $radius=Get-Lerp $radius 126.0 $script:G.TraderBlend
            }
            if($script:G.CloseZoom -gt 0.01){
                $x=Get-Lerp $x 640.0 $script:G.CloseZoom
                $y=Get-Lerp $y $script:FrackPlanetCenterY $script:G.CloseZoom
                $radius=Get-Lerp $radius $script:FrackPlanetRadius $script:G.CloseZoom
            }
        }
        else{
            $alpha=[int](255*$systemBlend*(1.0-$script:G.TraderBlend)*(1.0-$script:G.CloseZoom))
        }

        if($alpha -gt 2 -and $x+$radius -gt -80 -and $x-$radius -lt 1360){
            $transitionFocus=$script:Scale -le 1.25 -and ($name -eq $script:G.Player.Location -or ($travelProgress -ge 0 -and $name -eq $destinationName)) -and $radius -gt 50 -and $radius -le 300
            Draw-Planet $Graphics $planet $x $y $radius $alpha (($cameraStable -and $radius -gt 22) -or $transitionFocus)
        }

        if($script:G.Mode -eq "System" -and $systemBlend -gt 0.86){
            $labelRect=[Drawing.RectangleF]::new($systemX-42,273,84,20)
            Draw-Text $Graphics $name $script:Assets.FontTiny (Get-AlphaColor (Get-Color Gray) $mapAlpha) $labelRect $script:Assets.Center
            $hit=[Drawing.RectangleF]::new($systemX-24,217,48,79)
            Add-HitTarget "SelectPlanet" $hit $name $true
            if(Test-Hover $hit){$script:G.HoveredPlanet=$name}
            if($name -eq $script:G.Player.Location){
                $ring=$script:Assets.FramePen
                $ring.Color=[Drawing.Color]::FromArgb($mapAlpha,78,232,236);$ring.Width=2;$ring.DashStyle=[Drawing.Drawing2D.DashStyle]::Solid
                $Graphics.DrawEllipse($ring,$systemX-$baseRadius-7,245-$baseRadius-7,($baseRadius+7)*2,($baseRadius+7)*2)
            }
        }
    }

    if($travelProgress -lt 0 -and $systemBlend -lt 0.35 -and $current.Inhabited -and $script:G.CloseZoom -lt 0.3){
        $vesselX=Get-Lerp 885.0 850.0 $script:G.TraderBlend
        $vesselScale=Get-Lerp 0.28 1.0 $script:G.TraderBlend
        Draw-TraderVessel $Graphics $vesselX 225 $vesselScale (Get-Color $current.PlanetColor)
    }
}

function Draw-World {
    param([Drawing.Graphics] $Graphics)
    $travelFactor = if ($null -ne $script:G.Travel) { [Math]::Sin([Math]::PI * (Get-ClampedValue ($script:G.Travel.Time/$script:G.Travel.Duration) 0 1)) } else { 0.0 }
    Draw-Starfield $Graphics $travelFactor
    Draw-CameraNavigation $Graphics
}

function Draw-CockpitShell {
    param([Drawing.Graphics] $Graphics)
    $top = Get-Lerp $script:ViewportBottom 378.0 $script:G.PanelExpand
    $script:G.MfdTop = Get-Lerp 539.0 407.0 $script:G.PanelExpand
    $metal = [Drawing.Color]::FromArgb(235,31,38,42)
    $dark = [Drawing.Color]::FromArgb(245,11,16,19)
    Fill-RectangleColor $Graphics $metal ([Drawing.RectangleF]::new(0,$top,1280,$script:VirtualHeight-$top))
    $rimPen=$script:Assets.FramePen
    $rimPen.Color=[Drawing.Color]::FromArgb(103,124,130);$rimPen.Width=5;$rimPen.DashStyle=[Drawing.Drawing2D.DashStyle]::Solid
    $Graphics.DrawLine($rimPen,0,$top,1280,$top)

    $mfd = [Drawing.RectangleF]::new(220,$script:G.MfdTop,790,696-$script:G.MfdTop)
    Fill-RectangleColor $Graphics $dark $mfd
    $mfdPen=$script:Assets.FramePen
    $mfdPen.Color=[Drawing.Color]::FromArgb(53,132,139);$mfdPen.Width=2;$mfdPen.DashStyle=[Drawing.Drawing2D.DashStyle]::Solid
    $Graphics.DrawRectangle($mfdPen,$mfd.X,$mfd.Y,$mfd.Width,$mfd.Height)
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(160,37,93,99)) ([Drawing.RectangleF]::new(220,$script:G.MfdTop,790,3))

    $cockpitInputEnabled=-not $script:G.CryoActive
    Draw-Button $Graphics ([Drawing.RectangleF]::new(26,535,87,27)) "ORBIT" "Orbit" $null ($cockpitInputEnabled -and $script:G.Mode -ne "Orbit")
    Draw-Button $Graphics ([Drawing.RectangleF]::new(113,535,87,27)) "SYSTEM" "System" $null ($cockpitInputEnabled -and $script:G.Mode -ne "System" -and -not $script:G.FrackingActive)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(26,582,174,27)) "CARGO" "Cargo" $null ($cockpitInputEnabled -and $script:G.Mode -ne "Cargo")
    $contractLogOpen=$script:G.Mode -eq "Contracts" -and $script:G.ContractContext -eq "Log"
    Draw-Button $Graphics ([Drawing.RectangleF]::new(26,615,174,27)) "CONTRACTS" "ContractLog" $null ($cockpitInputEnabled -and -not $contractLogOpen)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(26,662,174,27)) "SETTINGS" "Settings" $null ($cockpitInputEnabled -and $script:G.Mode -ne "Settings")

    Draw-ShipStatus $Graphics
    if (-not $script:G.FrackingActive -and $script:G.NoticeClock -gt 0 -and -not [string]::IsNullOrWhiteSpace($script:G.Notice)) {
        $noticeRect = [Drawing.RectangleF]::new(300,$top+2,680,25)
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(220,9,22,25)) $noticeRect
        Draw-Text $Graphics $script:G.Notice $script:Assets.FontSmall (Get-Color Cyan) $noticeRect $script:Assets.Center
    }
}

function Draw-FrackingMarquee {
    param([Drawing.Graphics] $Graphics)
    if(-not $script:G.FrackingActive){return}
    $expand=Get-ClampedValue $script:G.PanelExpand 0.0 1.0
    $top=(Get-Lerp $script:ViewportBottom 378.0 $expand)-(6.0*$expand)
    $height=4.0+(25.0*$expand)
    $yellow=Get-Color Yellow;$black=[Drawing.Color]::FromArgb(248,8,10,10)
    Fill-RectangleColor $Graphics $yellow ([Drawing.RectangleF]::new(0,$top,1280,$height))
    if($height -lt 17){return}
    $saved=$Graphics.Save()
    $Graphics.SetClip([Drawing.RectangleF]::new(0,$top,1280,$height))
    $cycle=520.0;$offset=(($script:G.Time*46.0)%$cycle)-$cycle
    $planet=Get-Planet;$planetLabel=$planet.Name.ToUpper();$hazardLabel="HZ: {0}" -f (Get-EffectiveHazard $planet)
    for($baseX=$offset;$baseX -lt 1280+$cycle;$baseX+=$cycle){
        foreach($groupOffset in @(0.0,180.0,360.0)){
            for($stripe=0;$stripe -lt 4;$stripe++){
                $stripeX=$baseX+$groupOffset+($stripe*17.0)
                $chevron=[Drawing.PointF[]]@(
                    [Drawing.PointF]::new([single]($stripeX+7),[single]$top),
                    [Drawing.PointF]::new([single]($stripeX+18),[single]$top),
                    [Drawing.PointF]::new([single]($stripeX+7),[single]($top+$height)),
                    [Drawing.PointF]::new([single]($stripeX-4),[single]($top+$height))
                )
                Fill-PolygonColor $Graphics $black $chevron
            }
        }
        Draw-Text $Graphics "FRACKING" $script:Assets.FontSmallBold $black ([Drawing.RectangleF]::new($baseX+76,$top+1,96,$height-2)) $script:Assets.Center
        Draw-Text $Graphics $planetLabel $script:Assets.FontSmallBold $black ([Drawing.RectangleF]::new($baseX+256,$top+1,96,$height-2)) $script:Assets.Center
        Draw-Text $Graphics $hazardLabel $script:Assets.FontSmallBold $black ([Drawing.RectangleF]::new($baseX+436,$top+1,76,$height-2)) $script:Assets.Center
    }
    $Graphics.Restore($saved)
    $edgePen=$script:Assets.FramePen
    $edgePen.Color=[Drawing.Color]::FromArgb(210,10,12,12);$edgePen.Width=1;$edgePen.DashStyle=[Drawing.Drawing2D.DashStyle]::Solid
    $Graphics.DrawLine($edgePen,0,$top,1280,$top);$Graphics.DrawLine($edgePen,0,$top+$height-1,1280,$top+$height-1)
}

function Draw-ShipStatus {
    param([Drawing.Graphics] $Graphics)
    $x=1032.0; $w=218.0
    Draw-Text $Graphics "SHIP STATUS" $script:Assets.FontSmallBold (Get-Color White) ([Drawing.RectangleF]::new($x,540,$w,20)) $script:Assets.Center
    Draw-Text $Graphics ("HULL  {0}/{1}" -f [int]$script:G.Player.HP,[int]$script:G.Player.MaxHP) $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new($x,566,$w,17))
    Draw-Bar $Graphics $x 583 $w 8 $script:G.Player.HP $script:G.Player.MaxHP (Get-Color Red)
    Draw-Text $Graphics ("FUEL  {0:0.0}/{1:0.0} FL" -f $script:G.Player.Fuel,$script:G.Player.MaxFuel) $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new($x,601,$w,17))
    Draw-Bar $Graphics $x 618 $w 8 $script:G.Player.Fuel $script:G.Player.MaxFuel (Get-Color Yellow)
    $weight=Get-CurrentWeight
    Draw-Text $Graphics ("CARGO  {0:0.0}/{1:0.0} KG" -f $weight,$script:G.Player.MaxWeight) $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new($x,636,$w,17))
    Draw-Bar $Graphics $x 653 $w 8 $weight $script:G.Player.MaxWeight (Get-Color Cyan)
    Draw-Text $Graphics ("{0:N0} CD" -f $script:G.Player.Credits) $script:Assets.FontBodyBold (Get-Color Yellow) ([Drawing.RectangleF]::new($x,670,$w,24)) $script:Assets.Center
    $shipClock=(Get-Date).AddYears(300+[int]$script:G.Player.TimesSlept).ToString("MM/dd/yyyy HH:mm:ss")
    Draw-Text $Graphics $shipClock $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new($x,699,$w,16)) $script:Assets.Center
}

function Draw-MfdHeader {
    param([Drawing.Graphics] $Graphics,[string] $Title,[string] $Subtitle="")
    $top=if($script:G.ContainsKey("MfdTop")){$script:G.MfdTop}else{539.0}
    Draw-Text $Graphics $Title $script:Assets.FontSmallBold (Get-Color Cyan) ([Drawing.RectangleF]::new(236,$top+9,350,20))
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Draw-Text $Graphics $Subtitle $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new(590,$top+11,400,18)) $script:Assets.Right
    }
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(70,76,184,193)) ([Drawing.RectangleF]::new(235,$top+31,760,1))
}

function Draw-MfdOrbit {
    param([Drawing.Graphics] $Graphics)
    $planet=Get-Planet
    $hazard=Get-EffectiveHazard $planet
    Draw-MfdHeader $Graphics ("ORBIT: {0}" -f $planet.Name.ToUpper()) ("{0} | HZ {1}" -f $planet.Type,$hazard)
    Draw-Text $Graphics $planet.Description $script:Assets.FontSmall (Get-Color White) ([Drawing.RectangleF]::new(238,577,380,42))
    $traderText=if($planet.Inhabited){"COMMS: $($planet.TraderName)"}else{"NO INHABITED SIGNALS"}
    Draw-Text $Graphics $traderText $script:Assets.FontTiny $(if($planet.Inhabited){Get-Color Green}else{Get-Color DarkGray}) ([Drawing.RectangleF]::new(238,624,380,18))
    $canFrack=([double]$script:G.Player.Fuel -ge 0.5) -and ((Get-CurrentWeight) -lt [double]$script:G.Player.MaxWeight) -and ([double]$script:G.Player.HP -gt 0)
    Draw-FrackPlanetButton $Graphics ([Drawing.RectangleF]::new(844,575,145,42)) $planet $canFrack
    if($planet.Inhabited){Draw-Button $Graphics ([Drawing.RectangleF]::new(844,628,145,42)) "TRADER" "Trader" $null $true (Get-Color Green)}
    if([int]$script:G.Player.XRFScanner -gt 0){Draw-Button $Graphics ([Drawing.RectangleF]::new(687,575,145,42)) "HOLD XRF8 SCAN" "XRF" $null ($script:G.Player.Fuel -ge 75) (Get-Color Magenta) -HoldSeconds $script:XRFHoldSeconds}
}

function Get-SystemDetailPlanet {
    if (-not [string]::IsNullOrWhiteSpace($script:G.SelectedPlanet)) { return Get-Planet $script:G.SelectedPlanet }
    if (-not [string]::IsNullOrWhiteSpace($script:G.HoveredPlanet)) { return Get-Planet $script:G.HoveredPlanet }
    return Get-Planet
}

function Draw-MfdSystem {
    param([Drawing.Graphics] $Graphics)
    $planet=Get-SystemDetailPlanet
    $current=Get-Planet
    $distance=[Math]::Abs($planet.Distance-$current.Distance)
    $cost=Get-TravelFuelCost $distance
    $system=$script:G.Systems[$script:G.Player.SystemId]
    Draw-MfdHeader $Graphics ("{0} NAVIGATION" -f $system.Name.ToUpper()) "SELECT DESTINATION"
    Draw-Text $Graphics $planet.Name.ToUpper() $script:Assets.FontHeading (Get-Color $planet.PlanetColor) ([Drawing.RectangleF]::new(238,575,245,34))
    Draw-Text $Graphics ("{0} | HZ {1} | {2:0.00} AU" -f $planet.Type,(Get-EffectiveHazard $planet),$distance) $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new(240,613,300,18))
    Draw-Text $Graphics $planet.Description $script:Assets.FontSmall (Get-Color White) ([Drawing.RectangleF]::new(493,579,300,54))
    $costColor=if($cost -le $script:G.Player.Fuel){Get-Color Green}else{Get-Color Red}
    Draw-Text $Graphics ("TRAVEL COST  {0:0.0} FL" -f $cost) $script:Assets.FontSmallBold $costColor ([Drawing.RectangleF]::new(240,641,300,22))

    if ($script:G.ConfirmTravel) {
        Draw-Text $Graphics "CONFIRM COURSE?" $script:Assets.FontSmallBold (Get-Color Yellow) ([Drawing.RectangleF]::new(809,574,180,22)) $script:Assets.Center
        Draw-Button $Graphics ([Drawing.RectangleF]::new(809,603,86,52)) "CONFIRM" "ConfirmTravel" $planet.Name ($planet.Name -ne $script:G.Player.Location -and $cost -le $script:G.Player.Fuel) (Get-Color Green)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(903,603,86,52)) "CANCEL" "CancelTravel" $null $true (Get-Color Red)
    }
    else {
        Draw-Button $Graphics ([Drawing.RectangleF]::new(809,584,180,50)) $(if($planet.Name -eq $script:G.Player.Location){"RETURN TO ORBIT"}else{"SET COURSE"}) "PrepareTravel" $planet.Name $true (Get-Color Cyan)
        if([int]$script:G.Player.Hyperdrive -gt 0){Draw-Button $Graphics ([Drawing.RectangleF]::new(809,642,88,27)) "GALAXY" "Galaxy" $null $true (Get-Color Magenta)}
        if(-not (Test-ReachableInhabitedPlanet)){Draw-Button $Graphics ([Drawing.RectangleF]::new(903,642,86,27)) "DISTRESS" "Distress" $null $true (Get-Color Red)}
    }
}

function Get-SortedCargo {
    return @($script:G.Inventory.Keys|ForEach-Object{$item=$script:G.ResourceMaster[$_];[pscustomobject]@{Name=$_;Quantity=$script:G.Inventory[$_];Item=$item;Order=if($script:RaritySortOrder.ContainsKey($item.Rarity)){$script:RaritySortOrder[$item.Rarity]}else{99}}}|Sort-Object Order,Name)
}

function Draw-MfdCargo {
    param([Drawing.Graphics] $Graphics)
    $status=if($script:G.FrackingActive){"EXTRACTION CONTINUES IN REAL TIME"}else{"MANIFEST STABLE"}
    Draw-MfdHeader $Graphics "CARGO MANIFEST" $status
    $rows=@(Get-SortedCargo)
    $activeRequirements=Get-ActiveQuestRequirements
    $top=if($script:G.ContainsKey("MfdTop")){$script:G.MfdTop}else{539.0}
    $visible=5+[int][Math]::Floor($script:G.PanelExpand*6.0)
    $maxScroll=[Math]::Max(0,$rows.Count-$visible)
    $script:G.CargoScroll=[int](Get-ClampedValue $script:G.CargoScroll 0 $maxScroll)
    for($i=0;$i -lt $visible;$i++){
        $index=$i+$script:G.CargoScroll
        if($index -ge $rows.Count){break}
        $row=$rows[$index]
        $rect=[Drawing.RectangleF]::new(238,$top+38+($i*21),425,20)
        $selected=($script:G.SelectedCargo -eq $row.Name)
        if($selected){Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(110,31,70,75)) $rect}
        elseif(Test-Hover $rect){Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(75,26,49,52)) $rect}
        Draw-Text $Graphics ("x{0}" -f $row.Quantity) $script:Assets.FontTiny (Get-Color Cyan) ([Drawing.RectangleF]::new($rect.X+4,$rect.Y,38,$rect.Height)) $script:Assets.NearCenter
        $cargoLabel=Get-QuestCargoLabel $row.Name ([int]$row.Quantity) $activeRequirements
        Draw-RarityText $Graphics $cargoLabel $script:Assets.FontTiny $row.Item.Rarity ([Drawing.RectangleF]::new($rect.X+44,$rect.Y,190,$rect.Height)) $script:Assets.NearCenter
        if($row.Item.ContainsKey("Effect") -and $row.Item.Effect -in @("HP","Fuel")){
            $effectLabel=if($row.Item.Effect -eq "HP"){"+{0} HP" -f ([int]$row.Item.EffectValue*[int]$row.Quantity)}else{"+{0:0.0} FL" -f ([double]$row.Item.EffectValue*[int]$row.Quantity)}
            Draw-Text $Graphics $effectLabel $script:Assets.FontTiny (Get-Color Green) ([Drawing.RectangleF]::new($rect.Right-185,$rect.Y,85,$rect.Height)) $script:Assets.Right
        }
        Draw-Text $Graphics ("{0:0.0} kg" -f ($row.Item.Weight*$row.Quantity)) $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new($rect.Right-95,$rect.Y,90,$rect.Height)) $script:Assets.Right
        Add-HitTarget "SelectCargo" $rect $row.Name $true
    }
    if($rows.Count -gt $visible){Draw-Text $Graphics ("SCROLL {0}/{1}" -f ($script:G.CargoScroll+1),($maxScroll+1)) $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new(565,681,98,14)) $script:Assets.Right}

    $selected=$script:G.SelectedCargo
    if(-not [string]::IsNullOrWhiteSpace($selected) -and $script:G.Inventory.ContainsKey($selected)){
        $item=$script:G.ResourceMaster[$selected]
        Draw-RarityText $Graphics $selected $script:Assets.FontSmallBold $item.Rarity ([Drawing.RectangleF]::new(686,$top+40,300,22))
        Draw-Text $Graphics $item.Description $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new(686,$top+66,300,54))
        $canUse=$item.ContainsKey("Effect")
        Draw-Button $Graphics ([Drawing.RectangleF]::new(686,646,91,32)) "USE" "UseCargo" $selected $canUse (Get-Color Green)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(785,646,101,32)) "JETTISON" "Jettison" $selected (-not $canUse) (Get-Color Red)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(894,646,91,32)) "BACK" "CloseCargo" $null $true (Get-Color Cyan)
    }
    else{
        Draw-Text $Graphics "Select cargo for details and available actions." $script:Assets.FontSmall (Get-Color DarkGray) ([Drawing.RectangleF]::new(686,$top+54,295,70)) $script:Assets.Center
        Draw-Button $Graphics ([Drawing.RectangleF]::new(840,646,145,32)) "BACK" "CloseCargo" $null $true (Get-Color Cyan)
    }
}

function Draw-MfdFrack {
    param([Drawing.Graphics] $Graphics)
    $top=if($script:G.ContainsKey("MfdTop")){$script:G.MfdTop}else{539.0}
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(70,76,184,193)) ([Drawing.RectangleF]::new(670,$top+8,1,250))
    $feedRows=7+[int][Math]::Round($script:G.PanelExpand*7.0);$truncated=$script:G.Log.Count -gt $feedRows;$entryRows=if($truncated){$feedRows-1}else{[Math]::Min($feedRows,$script:G.Log.Count)}
    for($i=0;$i -lt $entryRows;$i++){
        $entry=$script:G.Log[$i]
        Draw-Text $Graphics $entry.Text $script:Assets.FontTiny $entry.Color ([Drawing.RectangleF]::new(238,$top+10+($i*18),420,17))
    }
    if($truncated){
        $hidden=$script:G.Log.Count-$entryRows
        Draw-Text $Graphics ("({0} more...)" -f $hidden) $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new(238,$top+10+($entryRows*18),420,17))
    }
    $elapsed=[TimeSpan]::FromSeconds($script:G.FrackElapsed)
    Draw-Text $Graphics ("TIME  {0:mm\:ss}" -f $elapsed) $script:Assets.FontSmallBold (Get-Color Cyan) ([Drawing.RectangleF]::new(684,$top+17,145,22))
    Draw-Text $Graphics ("YIELD  +{0}" -f $script:G.FrackResources) $script:Assets.FontSmall (Get-Color Green) ([Drawing.RectangleF]::new(684,$top+47,145,20))
    Draw-Text $Graphics ("DAMAGE  -{0} HP" -f $script:G.FrackDamage) $script:Assets.FontSmall (Get-Color Red) ([Drawing.RectangleF]::new(684,$top+74,145,20))
    Draw-Text $Graphics ("FUEL  -{0:0.0} FL" -f $script:G.FrackFuelUsed) $script:Assets.FontSmall (Get-Color Yellow) ([Drawing.RectangleF]::new(684,$top+101,145,20))
    if($script:G.FrackAutoHeal -gt 0){Draw-Text $Graphics ("AUTO  +{0} HP" -f $script:G.FrackAutoHeal) $script:Assets.FontTiny (Get-Color Green) ([Drawing.RectangleF]::new(684,$top+127,145,18))}
    Draw-Button $Graphics ([Drawing.RectangleF]::new(846,$top+18,143,40)) "OPEN CARGO" "Cargo" $null (-not $script:G.CryoActive) (Get-Color Cyan)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(846,$top+69,143,40)) "STOP FRACKING" "StopFrack" $null (-not $script:G.CryoActive) (Get-Color Red)
    if([int]$script:G.Player.CryoSkip -gt 0){Draw-Button $Graphics ([Drawing.RectangleF]::new(846,$top+120,143,40)) $(if($script:G.CryoActive){"CRYO ACTIVE"}else{"CRYO-SLEEP"}) "Cryo" $null (-not $script:G.CryoActive) (Get-Color Cyan)}
}

function Draw-MfdTrader {
    param([Drawing.Graphics] $Graphics)
    $planet=Get-Planet
    $state=Get-CurrentTraderState
    $dialog=Get-ActiveTraderDialog $(if($script:G.TraderTab -eq "Trade"){"TradeGreeting"}else{"Greeting"})
    $headerTitle="COMMS: {0}" -f $planet.TraderName.ToUpper()
    if($script:G.TraderTab -eq "Trade"){
        Draw-MfdHeader $Graphics $headerTitle
        $dialogX=248.0+[Math]::Ceiling($Graphics.MeasureString($headerTitle,$script:Assets.FontSmallBold).Width)
        Draw-Text $Graphics ("| {0}" -f $dialog) $script:Assets.FontTiny (Get-Color $planet.PlanetColor) ([Drawing.RectangleF]::new($dialogX,$script:G.MfdTop+11,990-$dialogX,18))
    }else{Draw-MfdHeader $Graphics $headerTitle "ORBITAL LINK | COMMS"}
    $top=if($script:G.ContainsKey("MfdTop")){$script:G.MfdTop}else{539.0}
    if($script:G.TraderTab -eq "Comms"){
        $missingHP=$script:G.Player.MaxHP-$script:G.Player.HP;$repairCost=[int][Math]::Ceiling($missingHP*$planet.RepairModifier)
        $missingFuel=$script:G.Player.MaxFuel-$script:G.Player.Fuel;$fuelCost=[int][Math]::Ceiling($missingFuel*3.0*$planet.FuelModifier)
        Draw-Text $Graphics $dialog $script:Assets.FontBody (Get-Color White) ([Drawing.RectangleF]::new(238,$top+44,470,55))
        Draw-Text $Graphics ("TRADER BUDGET  {0:N0} CD" -f $state.Credits) $script:Assets.FontSmallBold (Get-Color Yellow) ([Drawing.RectangleF]::new(238,$top+105,300,22))
        Draw-Text $Graphics ("NEXT RESTOCK  {0}" -f (Get-NextLocalQuarterHour).ToString("hh:mm tt")) $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new(238,$top+132,320,18))
        Draw-Button $Graphics ([Drawing.RectangleF]::new(725,$top+42,122,42)) ("REPAIR {0} CD" -f $repairCost) "Repair" $null ($missingHP -gt 0) (Get-Color Red)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(860,$top+42,122,42)) ("REFUEL {0} CD" -f $fuelCost) "Refuel" $null ($missingFuel -gt 0) (Get-Color Yellow)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(725,$top+94,122,42)) "TRADE" "TraderTab" "Trade" $true (Get-Color Green)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(860,$top+94,122,42)) "CONTRACTS" "TraderContracts" $null ($planet.Quests.Count -gt 0) (Get-Color Yellow)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(880,$top+204,102,38)) "CLOSE" "CloseTrader" $null $true (Get-Color Gray)
    }
    else{
        $sellX=236.0;$sellW=218.0;$tradeX=462.0;$tradeW=306.0;$buyX=776.0;$buyW=218.0;$rowTop=$top+63;$rowHeight=19.0;$visible=8
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(42,31,91,96)) ([Drawing.RectangleF]::new(457,$top+37,1,242))
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(42,31,91,96)) ([Drawing.RectangleF]::new(771,$top+37,1,242))
        Draw-Text $Graphics "SELL" $script:Assets.FontSmallBold (Get-Color Cyan) ([Drawing.RectangleF]::new($sellX,$top+38,$sellW,22)) $script:Assets.Center
        Draw-Text $Graphics "TRADE" $script:Assets.FontSmallBold (Get-Color White) ([Drawing.RectangleF]::new($tradeX,$top+38,$tradeW,22)) $script:Assets.Center
        Draw-Text $Graphics "BUY" $script:Assets.FontSmallBold (Get-Color Green) ([Drawing.RectangleF]::new($buyX,$top+38,$buyW,22)) $script:Assets.Center

        $activeRequirements=Get-ActiveQuestRequirements;$sellRows=@(Get-SortedCargo);$sellMax=[Math]::Max(0,$sellRows.Count-$visible);$script:G.TraderSellScroll=[int](Get-ClampedValue $script:G.TraderSellScroll 0 $sellMax)
        for($i=0;$i -lt $visible;$i++){
            $index=$i+$script:G.TraderSellScroll;if($index -ge $sellRows.Count){break};$row=$sellRows[$index];$available=Get-TradeAvailableQuantity "Sell" $row.Name;$rect=[Drawing.RectangleF]::new($sellX,$rowTop+($i*$rowHeight),$sellW,$rowHeight-1)
            if(Test-Hover $rect){Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(75,26,49,52)) $rect}
            $label=Get-QuestCargoLabel $row.Name ([int]$row.Quantity) $activeRequirements
            Draw-RarityText $Graphics ("x{0} {1}" -f $available,$label) $script:Assets.FontTiny $row.Item.Rarity ([Drawing.RectangleF]::new($rect.X+3,$rect.Y,158,$rect.Height)) $script:Assets.NearCenter
            Draw-Text $Graphics ("{0}" -f [int][Math]::Floor($row.Item.Value*0.69)) $script:Assets.FontTiny (Get-Color Yellow) ([Drawing.RectangleF]::new($rect.Right-53,$rect.Y,49,$rect.Height)) $script:Assets.Right
            Add-HitTarget "TradePickSell" $rect $row.Name ($available -gt 0 -or (Get-TradePendingQuantity "Sell" $row.Name) -gt 0)
        }

        $buyRows=@(Get-TraderStockRows);$buyMax=[Math]::Max(0,$buyRows.Count-$visible);$script:G.TraderBuyScroll=[int](Get-ClampedValue $script:G.TraderBuyScroll 0 $buyMax)
        for($i=0;$i -lt $visible;$i++){
            $index=$i+$script:G.TraderBuyScroll;if($index -ge $buyRows.Count){break};$row=$buyRows[$index];$available=Get-TradeAvailableQuantity "Buy" $row.Name;$rect=[Drawing.RectangleF]::new($buyX,$rowTop+($i*$rowHeight),$buyW,$rowHeight-1)
            if(Test-Hover $rect){Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(75,26,49,52)) $rect}
            Draw-RarityText $Graphics ("x{0} {1}" -f $available,$row.Name) $script:Assets.FontTiny $row.Item.Rarity ([Drawing.RectangleF]::new($rect.X+3,$rect.Y,158,$rect.Height)) $script:Assets.NearCenter
            Draw-Text $Graphics ("{0}" -f [int]$row.Item.Value) $script:Assets.FontTiny (Get-Color Yellow) ([Drawing.RectangleF]::new($rect.Right-53,$rect.Y,49,$rect.Height)) $script:Assets.Right
            Add-HitTarget "TradePickBuy" $rect $row.Name ($available -gt 0 -or (Get-TradePendingQuantity "Buy" $row.Name) -gt 0)
        }

        $tradeRows=@(Get-PendingTradeRows);$tradeVisible=7;$tradeMax=[Math]::Max(0,$tradeRows.Count-$tradeVisible);$script:G.TradeScroll=[int](Get-ClampedValue $script:G.TradeScroll 0 $tradeMax)
        Draw-Button $Graphics ([Drawing.RectangleF]::new($tradeX+4,$top+39,30,20)) "<" "TradePaneScroll" "Trade|-1" ($script:G.TradeScroll -gt 0) (Get-Color Gray)
        Draw-Button $Graphics ([Drawing.RectangleF]::new($tradeX+$tradeW-34,$top+39,30,20)) ">" "TradePaneScroll" "Trade|1" ($script:G.TradeScroll -lt $tradeMax) (Get-Color Gray)
        for($i=0;$i -lt $tradeVisible;$i++){
            $index=$i+$script:G.TradeScroll;if($index -ge $tradeRows.Count){break};$row=$tradeRows[$index];$rect=[Drawing.RectangleF]::new($tradeX,$rowTop+($i*$rowHeight),$tradeW,$rowHeight-1)
            $back=if($row.Side -eq "Sell"){[Drawing.Color]::FromArgb(105,22,92,56)}else{[Drawing.Color]::FromArgb(105,111,31,36)};Fill-RectangleColor $Graphics $back $rect
            Draw-RarityText $Graphics ("x{0} {1}" -f $row.Quantity,$row.Name) $script:Assets.FontTiny $row.Item.Rarity ([Drawing.RectangleF]::new($rect.X+4,$rect.Y,205,$rect.Height)) $script:Assets.NearCenter
            $amount=if($row.Side -eq "Sell"){"+$($row.Amount)"}else{"-$($row.Amount)"};Draw-Text $Graphics $amount $script:Assets.FontTiny $(if($row.Side -eq "Sell"){Get-Color Green}else{Get-Color Red}) ([Drawing.RectangleF]::new($rect.Right-88,$rect.Y,83,$rect.Height)) $script:Assets.Right
            Add-HitTarget "TradePickPending" $rect ("{0}|{1}" -f $row.Side,$row.Name) $true
        }

        $totals=Get-TradeTotals;$netColor=if($totals.Net -gt 0){Get-Color Green}elseif($totals.Net -lt 0){Get-Color Red}else{Get-Color Gray};$netBack=if($totals.Net -gt 0){[Drawing.Color]::FromArgb(90,22,92,56)}elseif($totals.Net -lt 0){[Drawing.Color]::FromArgb(90,111,31,36)}else{[Drawing.Color]::FromArgb(80,45,52,56)}
        Fill-RectangleColor $Graphics $netBack ([Drawing.RectangleF]::new($tradeX,$top+202,$tradeW,23));Draw-Text $Graphics ("NET {0}{1} CD" -f $(if($totals.Net -ge 0){"+"}else{""}),$totals.Net) $script:Assets.FontSmallBold $netColor ([Drawing.RectangleF]::new($tradeX,$top+202,$tradeW,23)) $script:Assets.Center
        Draw-Text $Graphics $(if($totals.CanTrade){"PLAYER $($totals.PlayerAfter) | TRADER $($totals.TraderAfter)"}else{$totals.Reason}) $script:Assets.FontTiny $(if($totals.CanTrade){Get-Color Gray}else{Get-Color DarkRed}) ([Drawing.RectangleF]::new($tradeX,$top+226,$tradeW,17)) $script:Assets.Center
        $makeTradeRect=[Drawing.RectangleF]::new($tradeX,$top+246,210,31)
        Draw-Button $Graphics $makeTradeRect "MAKE TRADE" "CommitTrade" $null $totals.CanTrade (Get-Color Green)
        if(-not $totals.CanTrade){Add-HitTarget "CommitTrade" $makeTradeRect $null $true}
        Draw-Button $Graphics ([Drawing.RectangleF]::new($tradeX+218,$top+246,88,31)) "CLEAR" "ClearTrade" $null $totals.HasItems (Get-Color Gray)

        Draw-Button $Graphics ([Drawing.RectangleF]::new($sellX,$top+218,34,21)) "<" "TradePaneScroll" "Sell|-1" ($script:G.TraderSellScroll -gt 0) (Get-Color Cyan)
        Draw-Text $Graphics ("{0}/{1}" -f ($script:G.TraderSellScroll+1),($sellMax+1)) $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new($sellX+38,$top+218,108,21)) $script:Assets.Center
        Draw-Button $Graphics ([Drawing.RectangleF]::new($sellX+150,$top+218,34,21)) ">" "TradePaneScroll" "Sell|1" ($script:G.TraderSellScroll -lt $sellMax) (Get-Color Cyan)
        Draw-Button $Graphics ([Drawing.RectangleF]::new($sellX,$top+246,$sellW,31)) "QUICK SELL" "QuickStageSell" $null $true (Get-Color Yellow)
        Draw-Button $Graphics ([Drawing.RectangleF]::new($buyX,$top+218,34,21)) "<" "TradePaneScroll" "Buy|-1" ($script:G.TraderBuyScroll -gt 0) (Get-Color Green)
        Draw-Text $Graphics ("{0}/{1}" -f ($script:G.TraderBuyScroll+1),($buyMax+1)) $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new($buyX+38,$top+218,108,21)) $script:Assets.Center
        Draw-Button $Graphics ([Drawing.RectangleF]::new($buyX+150,$top+218,34,21)) ">" "TradePaneScroll" "Buy|1" ($script:G.TraderBuyScroll -lt $buyMax) (Get-Color Green)
        Draw-Button $Graphics ([Drawing.RectangleF]::new($buyX,$top+246,$buyW,31)) "BACK TO COMMS" "TraderTab" "Comms" $true (Get-Color Cyan)

    }
}

function Draw-QuantityPicker {
    param([Drawing.Graphics] $Graphics)
    $picker=$script:G.QuantityPicker;if($null -eq $picker){return};$top=$script:G.MfdTop;$rect=[Drawing.RectangleF]::new(405,$top+57,420,174)
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(252,10,16,19)) $rect;$pen=New-Object Drawing.Pen((Get-Color Cyan),2);try{$Graphics.DrawRectangle($pen,$rect.X,$rect.Y,$rect.Width,$rect.Height)}finally{$pen.Dispose()}
    $verb=if($picker.Purpose -eq "Jettison"){"JETTISON"}elseif($picker.Direction -eq "Add"){"STAGE"}else{"RETURN"};Draw-Text $Graphics ("{0} {1}" -f $verb,$picker.Name.ToUpper()) $script:Assets.FontSmallBold (Get-Color White) ([Drawing.RectangleF]::new($rect.X+14,$rect.Y+8,$rect.Width-28,22)) $script:Assets.Center
    Draw-Text $Graphics ("QUANTITY  {0} / {1}" -f $picker.Value,$picker.Maximum) $script:Assets.FontBodyBold (Get-Color Yellow) ([Drawing.RectangleF]::new($rect.X+14,$rect.Y+39,$rect.Width-28,25)) $script:Assets.Center
    $selectionValue=[int]$picker.ValueSign*[int]$picker.UnitValue*[int]$picker.Value
    $valueText=if($picker.Purpose -eq "Jettison"){"CARGO VALUE DISCARDED  {0} CD" -f ([Math]::Abs($selectionValue))}elseif($selectionValue -ge 0){"SELECTION VALUE  +{0} CD" -f $selectionValue}else{"SELECTION VALUE  {0} CD" -f $selectionValue}
    Draw-Text $Graphics $valueText $script:Assets.FontTiny $(if($selectionValue -ge 0){Get-Color Green}else{Get-Color Red}) ([Drawing.RectangleF]::new($rect.X+14,$rect.Y+66,$rect.Width-28,17)) $script:Assets.Center
    $slider=[Drawing.RectangleF]::new($rect.X+30,$rect.Y+88,$rect.Width-60,16);$picker.SliderRect=$slider;Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(255,26,35,39)) $slider
    $ratio=if($picker.Maximum -le 1){1.0}else{($picker.Value-1)/[double]($picker.Maximum-1)};Fill-RectangleColor $Graphics (Get-Color Cyan) ([Drawing.RectangleF]::new($slider.X,$slider.Y,[Math]::Max(3,$slider.Width*$ratio),$slider.Height));Fill-EllipseColor $Graphics (Get-Color White) ([Drawing.RectangleF]::new($slider.X+($slider.Width*$ratio)-6,$slider.Y-3,12,22))
    Draw-Text $Graphics "TYPE A VALUE AND PRESS ENTER, OR USE THE SLIDER" $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new($rect.X+20,$rect.Y+111,$rect.Width-40,17)) $script:Assets.Center
    Draw-Button $Graphics ([Drawing.RectangleF]::new($rect.X+105,$rect.Y+136,98,27)) "CONFIRM" "PickerConfirm" $null $true (Get-Color Green)
    Draw-Button $Graphics ([Drawing.RectangleF]::new($rect.X+217,$rect.Y+136,98,27)) "CANCEL" "PickerCancel" $null $true (Get-Color Red)
}

function Draw-MfdContracts {
    param([Drawing.Graphics] $Graphics)
    $top=$script:G.MfdTop
    if($script:G.ContractContext -eq "Trader"){
        $planet=Get-Planet;$rep=Get-PlanetReputation $script:G.Player.SystemId $script:G.Player.Location
        Draw-MfdHeader $Graphics ("{0} CONTRACTS" -f $planet.TraderName.ToUpper()) ("REPUTATION {0}" -f $rep)
    }else{
        Draw-MfdHeader $Graphics "YOUR CONTRACTS" ("FLIGHT LOG | {0}" -f $script:G.ContractTab.ToUpper())
    }
    $rows=@(Get-ContractDisplayRows)
    $visible=10;$maxScroll=[Math]::Max(0,$rows.Count-$visible);$script:G.QuestScroll=[int](Get-ClampedValue $script:G.QuestScroll 0 $maxScroll)
    for($i=0;$i -lt $visible;$i++){
        $index=$i+$script:G.QuestScroll;if($index -ge $rows.Count){break};$row=$rows[$index];$status=Get-QuestStatus $row;$rect=[Drawing.RectangleF]::new(238,$top+39+($i*21),355,20)
        if($script:G.SelectedQuest -eq $row.Quest.Id){Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(110,31,70,75)) $rect}elseif(Test-Hover $rect){Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(75,26,49,52)) $rect}
        $ready=$status -eq "Active" -and (Test-QuestRequirements $row.Quest)
        $label=switch($status){"Available"{"ACCEPT"};"Active"{if($ready -and $script:G.ContractContext -eq "Trader"){"TURN IN"}else{"ACTIVE"}};default{$status.ToUpper()}}
        $color=switch($status){"Active"{if($ready){Get-Color Green}else{Get-Color Yellow}};"Complete"{Get-Color DarkGreen};"Available"{Get-Color Cyan};"Locked"{Get-Color Red};default{Get-Color DarkGray}}
        Draw-Text $Graphics ("{0,-8} {1}" -f $label,$row.Quest.Name) $script:Assets.FontTiny $color ([Drawing.RectangleF]::new($rect.X+4,$rect.Y,347,$rect.Height)) $script:Assets.NearCenter
        Add-HitTarget "SelectQuest" $rect $row.Quest.Id $true
    }
    if($rows.Count -eq 0){
        $empty=if($script:G.ContractContext -eq "Trader"){"No contracts are currently offered at this reputation level."}elseif($script:G.ContractTab -eq "Complete"){"No completed contracts."}else{"No active contracts. Visit a trader contract board to accept work."}
        Draw-Text $Graphics $empty $script:Assets.FontSmall (Get-Color DarkGray) ([Drawing.RectangleF]::new(238,$top+62,355,80)) $script:Assets.Center
    }
    if(-not [string]::IsNullOrWhiteSpace($script:G.SelectedQuest)){
        $row=Get-QuestRow $script:G.SelectedQuest
        if($null -ne $row -and $row.Quest.Id -in @($rows|ForEach-Object{$_.Quest.Id})){
            $status=Get-QuestStatus $row;$quest=$row.Quest
            Draw-Text $Graphics $quest.Name.ToUpper() $script:Assets.FontSmallBold (Get-Color Yellow) ([Drawing.RectangleF]::new(615,$top+40,365,22))
            Draw-Text $Graphics ("{0} | {1} | REP {2}" -f $row.SystemId,$row.Planet,$quest.RepReq) $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new(615,$top+64,365,18))
            Draw-Text $Graphics $quest.Description $script:Assets.FontTiny (Get-Color White) ([Drawing.RectangleF]::new(615,$top+83,365,36))
            $requirements=@($quest.Requirements.Keys|Sort-Object)
            $reqMax=[Math]::Max(0,$requirements.Count-5)
            $script:G.ContractRequirementScroll=[int](Get-ClampedValue $script:G.ContractRequirementScroll 0 $reqMax)
            $line=0
            foreach($name in @($requirements|Select-Object -Skip $script:G.ContractRequirementScroll -First 5)){
                $have=if($script:G.Inventory.ContainsKey($name)){[int]$script:G.Inventory[$name]}else{0};$need=[int]$quest.Requirements[$name]
                $requirementY=$top+121+($line*17)
                Draw-RarityText $Graphics $name $script:Assets.FontTiny $script:G.ResourceMaster[$name].Rarity ([Drawing.RectangleF]::new(615,$requirementY,220,17))
                Draw-Text $Graphics ("{0}/{1}" -f $have,$need) $script:Assets.FontTiny $(if($have -ge $need){Get-Color Green}else{Get-Color Gray}) ([Drawing.RectangleF]::new(838,$requirementY,85,17)) $script:Assets.Right;$line++
            }
            if($reqMax -gt 0){
                Draw-Button $Graphics ([Drawing.RectangleF]::new(932,$top+121,22,20)) "<" "ContractReqScroll" -1 ($script:G.ContractRequirementScroll -gt 0) (Get-Color Cyan)
                Draw-Button $Graphics ([Drawing.RectangleF]::new(958,$top+121,22,20)) ">" "ContractReqScroll" 1 ($script:G.ContractRequirementScroll -lt $reqMax) (Get-Color Cyan)
            }
            $rewardHeader="REWARD"
            if([int]$quest.RewardCredits -gt 0){$rewardHeader+="  $([int]$quest.RewardCredits) CD"}
            if(-not [string]::IsNullOrWhiteSpace($quest.KnownSystem)){$rewardHeader+=" | DISCOVER $($quest.KnownSystem)"}
            Draw-Text $Graphics $rewardHeader $script:Assets.FontTiny (Get-Color Yellow) ([Drawing.RectangleF]::new(615,$top+209,365,16))
            $rewardX=615.0
            foreach($name in @($quest.RewardItems.Keys|Sort-Object)){
                $rewardText=("{0} x{1}" -f $name,[int]$quest.RewardItems[$name]);$rewardWidth=[Math]::Min(365.0,[Math]::Max(55.0,$Graphics.MeasureString($rewardText,$script:Assets.FontTiny).Width+9.0))
                Draw-RarityText $Graphics $rewardText $script:Assets.FontTiny $script:G.ResourceMaster[$name].Rarity ([Drawing.RectangleF]::new($rewardX,$top+225,$rewardWidth,16));$rewardX+=$rewardWidth
                if($rewardX -ge 975){break}
            }
            if($script:G.ContractContext -eq "Trader"){
                $requirementsReady=Test-QuestRequirements $quest
                if($status -eq "Available"){
                    Draw-Button $Graphics ([Drawing.RectangleF]::new(615,$top+247,175,31)) "ACCEPT CONTRACT" "QuestAction" $quest.Id $true (Get-Color Yellow)
                }elseif($status -eq "Active" -and $requirementsReady){
                    Draw-Button $Graphics ([Drawing.RectangleF]::new(615,$top+247,175,31)) "TURN IN CONTRACT" "QuestAction" $quest.Id $true (Get-Color Yellow)
                }elseif($status -eq "Locked"){
                    Draw-Button $Graphics ([Drawing.RectangleF]::new(615,$top+247,175,31)) "LOCKED" "QuestAction" $quest.Id $false (Get-Color DarkGray)
                }
            }
        }
    }else{Draw-Text $Graphics "Select a contract to inspect requirements and rewards." $script:Assets.FontSmall (Get-Color DarkGray) ([Drawing.RectangleF]::new(615,$top+70,365,80)) $script:Assets.Center}
    if($script:G.ContractContext -eq "Log"){
        Draw-Button $Graphics ([Drawing.RectangleF]::new(615,$top+247,112,31)) "ACTIVE" "ContractTab" "Active" ($script:G.ContractTab -ne "Active") (Get-Color Yellow)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(735,$top+247,112,31)) "COMPLETED" "ContractTab" "Complete" ($script:G.ContractTab -ne "Complete") (Get-Color Green)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(855,$top+247,125,31)) "BACK" "CloseContracts" $null $true (Get-Color Cyan)
    }else{
        Draw-Button $Graphics ([Drawing.RectangleF]::new(805,$top+247,175,31)) "BACK TO COMMS" "CloseContracts" $null $true (Get-Color Cyan)
    }
}

function Draw-MfdXRF {
    param([Drawing.Graphics] $Graphics)
    $top=$script:G.MfdTop;$planet=Get-Planet
    Draw-MfdHeader $Graphics ("XRF8 SURVEY: {0}" -f $planet.Name.ToUpper()) "APPROXIMATE COMPOSITION"
    $count=[Math]::Min(8,$script:G.XRFResults.Count)
    for($i=0;$i -lt $count;$i++){
        $row=$script:G.XRFResults[$i];$y=$top+42+($i*20)
        Draw-RarityText $Graphics $row.Name $script:Assets.FontTiny $row.Rarity ([Drawing.RectangleF]::new(238,$y,230,18))
        Draw-Bar $Graphics 475 ($y+4) 330 9 $row.Percent 30.0 (Get-RarityColor $row.Rarity)
        Draw-Text $Graphics ("{0:0.0}%" -f $row.Percent) $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new(815,$y,65,18)) $script:Assets.Right
    }
    $traceOrder=@{SuperCommon=1;Common=2;Uncommon=3;Rare=4;SuperRare=5;UltraRare=6;Artifact=7;Oddity=8;Consumable=9;Upgrade=10}
    $traceRows=@($script:G.XRFResults|Select-Object -Skip 8|Sort-Object @{Expression={if($traceOrder.ContainsKey($_.Rarity)){$traceOrder[$_.Rarity]}else{99}}},Name)
    if($traceRows.Count -gt 0){
        $traceY=$top+247.0;$traceX=238.0;$traceRight=982.0
        Draw-Text $Graphics "TRACE:" $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new($traceX,$traceY,47,17));$traceX+=48.0
        for($i=0;$i -lt $traceRows.Count;$i++){
            $row=$traceRows[$i];$traceText=$row.Name+$(if($i -lt $traceRows.Count-1){", "}else{""});$traceWidth=[Math]::Ceiling($Graphics.MeasureString($traceText,$script:Assets.FontTiny).Width)+2.0
            if($traceX+$traceWidth -gt $traceRight){$traceY+=17.0;$traceX=238.0}
            Draw-RarityText $Graphics $traceText $script:Assets.FontTiny $row.Rarity ([Drawing.RectangleF]::new($traceX,$traceY,$traceWidth,17));$traceX+=$traceWidth
        }
    }
    Draw-Button $Graphics ([Drawing.RectangleF]::new(850,$top+211,132,34)) "BACK TO ORBIT" "Orbit" $null $true (Get-Color Cyan)
}

function Draw-MfdGalaxy {
    param([Drawing.Graphics] $Graphics)
    $top=$script:G.MfdTop
    Draw-MfdHeader $Graphics "KNOWN GALAXY" "HYPERDRIVE NAVIGATION | 1000.0 FL"
    $x=238
    foreach($systemId in @("Sol","Typhon")){
        $system=$script:G.Systems[$systemId];$known=$systemId -in @($script:G.Player.Known);$current=$systemId -eq $script:G.Player.SystemId;$rect=[Drawing.RectangleF]::new($x,$top+48,260,92)
        Draw-Button $Graphics $rect ($system.Name.ToUpper()+$(if($current){" | CURRENT"}else{""})) "SelectSystem" $systemId ($known -and -not $current) (Get-Color $system.Color)
        Draw-Text $Graphics ("{0} WORLDS" -f $system.Order.Count) $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new($x,$top+145,260,18)) $script:Assets.Center
        $x+=280
    }
    if(-not [string]::IsNullOrWhiteSpace($script:G.SelectedSystem)){
        $target=$script:G.Systems[$script:G.SelectedSystem]
        Draw-Text $Graphics ("CONFIRM JUMP TO {0}?" -f $target.Name.ToUpper()) $script:Assets.FontSmallBold (Get-Color Magenta) ([Drawing.RectangleF]::new(238,$top+180,400,24))
        Draw-Button $Graphics ([Drawing.RectangleF]::new(650,$top+178,155,38)) "JUMP 1000 FL" "Hyperjump" $target.Id ($script:G.Player.Fuel -ge 1000) (Get-Color Magenta)
        Draw-Button $Graphics ([Drawing.RectangleF]::new(816,$top+178,120,38)) "CANCEL" "SelectSystem" "" $true (Get-Color Gray)
    }
    Draw-Button $Graphics ([Drawing.RectangleF]::new(837,$top+225,145,32)) "BACK" "System" $null $true (Get-Color Cyan)
}

function Draw-MfdSettings {
    param([Drawing.Graphics] $Graphics)
    $top=$script:G.MfdTop
    Draw-MfdHeader $Graphics "FLIGHT COMPUTER" ("PILOT: {0}" -f $script:G.Player.PilotName.ToUpper())
    Draw-Button $Graphics ([Drawing.RectangleF]::new(238,$top+48,210,42)) "SAVE FLIGHT" "Save" $null ($script:G.Mode -ne "Title") (Get-Color Green)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(462,$top+48,210,42)) "LOAD FLIGHT" "Saves" $null $true (Get-Color Cyan)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(686,$top+48,210,42)) "STATUS REPORT" "Status" $null ($script:G.Mode -ne "Title") (Get-Color Yellow)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(238,$top+105,210,42)) "RENAME PILOT" "RenamePilot" $null ($script:G.Mode -ne "Title") (Get-Color Cyan)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(462,$top+105,210,42)) "TOGGLE FULLSCREEN" "Fullscreen" $null $true (Get-Color Gray)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(686,$top+105,210,42)) "RETURN TO TITLE" "Title" $null ($script:G.ReturnMode -ne "Title") (Get-Color Red)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(238,$top+162,210,38)) $(if($script:G.DrillVibration){"DRILL VIBRATION: ON"}else{"DRILL VIBRATION: OFF"}) "ToggleVibration" $null $true (Get-Color Yellow)
    $vibrationValue=Get-ClampedValue $script:G.DrillVibrationIntensity 0.0 100.0
    Draw-Text $Graphics ("VIBRATION INTENSITY  {0}%" -f [int]$vibrationValue) $script:Assets.FontTiny $(if($script:G.DrillVibration){Get-Color Yellow}else{Get-Color DarkGray}) ([Drawing.RectangleF]::new(462,$top+158,330,18))
    $script:G.VibrationSliderRect=[Drawing.RectangleF]::new(462,$top+174,330,28)
    $track=[Drawing.RectangleF]::new(462,$top+184,330,8)
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(220,15,22,25)) $track
    if($vibrationValue -gt 0){Fill-RectangleColor $Graphics $(if($script:G.DrillVibration){Get-Color Yellow}else{Get-Color DarkYellow}) ([Drawing.RectangleF]::new($track.X,$track.Y,$track.Width*($vibrationValue/100.0),$track.Height))}
    $knobX=$track.X+($track.Width*($vibrationValue/100.0))
    Fill-EllipseColor $Graphics $(if($script:G.DrillVibration){Get-Color White}else{Get-Color Gray}) ([Drawing.RectangleF]::new($knobX-6,$track.Y-3,12,14))
    Add-HitTarget "None" $script:G.VibrationSliderRect $null $true
    $rendererLabel=if($script:ReducedRenderQuality){"AUTO REDUCED"}else{"AUTO FULL"}
    Draw-Text $Graphics ("Version {0} | Renderer: {1} | Saves: APPDATA/spacefrack" -f $script:Version,$rendererLabel) $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new(462,$top+204,370,16))
    Draw-Button $Graphics ([Drawing.RectangleF]::new(837,$top+216,145,34)) "BACK" "CloseSettings" $null $true (Get-Color Cyan)
}

function Draw-MfdStatus {
    param([Drawing.Graphics] $Graphics)
    $top=$script:G.MfdTop;$elapsed=((Get-Date)-[datetime]$script:G.GameStarted).TotalSeconds
    Draw-MfdHeader $Graphics "PILOT STATUS REPORT" $script:G.Player.PilotName.ToUpper()
    $left=@("LOCATION  $($script:G.Player.SystemId) / $($script:G.Player.Location)","CREDITS ACQUIRED  $($script:G.Player.CreditsAcquired)","FLIGHT TIME  $(Format-GameDuration $elapsed)","TIME FRACKED  $(Format-GameDuration $script:G.Player.TimeFracked)","REAL FRACK TIME  $(Format-GameDuration $script:G.Player.RealTimeFracked)","CRYO TIME  $(Format-GameDuration $script:G.Player.TimeSlept)")
    for($i=0;$i -lt $left.Count;$i++){Draw-Text $Graphics $left[$i] $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new(238,$top+44+($i*24),355,20))}
    $flags=@("Hyperdrive","XRFScanner","CryoSkip","AutoAdminister","RadiationSuit","frackGas","frackIce","frackTerr","frackAst","frackDwarf")
    for($i=0;$i -lt $flags.Count;$i++){$value=[int]$script:G.Player[$flags[$i]];Draw-Text $Graphics ("{0,-18} {1}" -f $flags[$i].ToUpper(),$value) $script:Assets.FontTiny $(if($value -gt 0){Get-Color Green}else{Get-Color DarkGray}) ([Drawing.RectangleF]::new(615,$top+44+($i*19),300,18))}
    Draw-Button $Graphics ([Drawing.RectangleF]::new(837,$top+216,145,34)) "BACK" "Settings" $null $true (Get-Color Cyan)
}

function Draw-MfdSaves {
    param([Drawing.Graphics] $Graphics)
    $top=$script:G.MfdTop
    Draw-MfdHeader $Graphics "SAVE ARCHIVE" ("{0} FILES" -f $script:G.SaveFiles.Count)
    $visible=8;$maxScroll=[Math]::Max(0,$script:G.SaveFiles.Count-$visible);$script:G.SaveScroll=[int](Get-ClampedValue $script:G.SaveScroll 0 $maxScroll)
    for($i=0;$i -lt $visible;$i++){
        $index=$i+$script:G.SaveScroll;if($index -ge $script:G.SaveFiles.Count){break};$file=$script:G.SaveFiles[$index];$rect=[Drawing.RectangleF]::new(238,$top+42+($i*25),550,23)
        if($script:G.SelectedSave -eq $file.FullName){Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(110,31,70,75)) $rect}elseif(Test-Hover $rect){Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(75,26,49,52)) $rect}
        Draw-Text $Graphics $file.BaseName $script:Assets.FontTiny (Get-Color White) ([Drawing.RectangleF]::new($rect.X+4,$rect.Y,390,$rect.Height)) $script:Assets.NearCenter
        Draw-Text $Graphics $file.LastWriteTime.ToString("MM/dd/yy HH:mm") $script:Assets.FontTiny (Get-Color Gray) ([Drawing.RectangleF]::new($rect.Right-145,$rect.Y,140,$rect.Height)) $script:Assets.Right
        Add-HitTarget "SelectSave" $rect $file.FullName $true
    }
    $selected=-not [string]::IsNullOrWhiteSpace($script:G.SelectedSave)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(805,$top+48,177,36)) "LOAD SELECTED" "LoadSelected" $null $selected (Get-Color Green)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(805,$top+94,177,36)) "DELETE SELECTED" "DeleteSave" $null $selected (Get-Color Red)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(805,$top+140,177,36)) "PRUNE OLD SAVES" "PruneSaves" $null ($script:G.SaveFiles.Count -gt 1) (Get-Color Yellow)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(805,$top+211,177,34)) "BACK" "CloseSaves" $null $true (Get-Color Cyan)
}

function Draw-MfdDistress {
    param([Drawing.Graphics] $Graphics)
    Draw-MfdHeader $Graphics "EMERGENCY BEACON" "SCRAPPER UNION RECOVERY"
    Draw-Text $Graphics ("RECOVERY ARRIVAL IN {0:0.0} SECONDS" -f $script:G.DistressRemaining) $script:Assets.FontHeading (Get-Color Red) ([Drawing.RectangleF]::new(238,580,745,42)) $script:Assets.Center
    Draw-Text $Graphics "RAW CARGO FORFEITED | 50% CREDIT SURCHARGE" $script:Assets.FontSmallBold (Get-Color DarkRed) ([Drawing.RectangleF]::new(238,630,745,24)) $script:Assets.Center
    Draw-Button $Graphics ([Drawing.RectangleF]::new(535,662,180,28)) "CANCEL SIGNAL" "CancelDistress" $null $true (Get-Color Cyan)
}

function Draw-MfdTravel {
    param([Drawing.Graphics] $Graphics)
    Draw-MfdHeader $Graphics "AUTOPILOT TRANSIT" "FLIGHT CONTROLS LOCKED"
    if($null -ne $script:G.Travel){
        $ratio=Get-ClampedValue ($script:G.Travel.Time/$script:G.Travel.Duration) 0 1
        Draw-Text $Graphics ("{0}  ->  {1}" -f $script:G.Travel.From.ToUpper(),$script:G.Travel.To.ToUpper()) $script:Assets.FontHeading (Get-Color White) ([Drawing.RectangleF]::new(238,582,470,35))
        Draw-Bar $Graphics 240 635 730 12 $ratio 1 (Get-Color Cyan)
        Draw-Text $Graphics ("FUEL COMMITTED  {0:0.0} FL" -f $script:G.Travel.Cost) $script:Assets.FontSmall (Get-Color Yellow) ([Drawing.RectangleF]::new(240,655,730,20)) $script:Assets.Center
    }
}

function Draw-Mfd {
    param([Drawing.Graphics] $Graphics)
    switch($script:G.Mode){
        "Orbit" {Draw-MfdOrbit $Graphics}
        "System" {Draw-MfdSystem $Graphics}
        "Cargo" {Draw-MfdCargo $Graphics}
        "Frack" {Draw-MfdFrack $Graphics}
        "Trader" {Draw-MfdTrader $Graphics}
        "Contracts" {Draw-MfdContracts $Graphics}
        "XRF" {Draw-MfdXRF $Graphics}
        "Galaxy" {Draw-MfdGalaxy $Graphics}
        "Settings" {Draw-MfdSettings $Graphics}
        "Status" {Draw-MfdStatus $Graphics}
        "Saves" {Draw-MfdSaves $Graphics}
        "Distress" {Draw-MfdDistress $Graphics}
        "Travel" {Draw-MfdTravel $Graphics}
        "Death" {Draw-MfdFrack $Graphics}
        default {Draw-MfdOrbit $Graphics}
    }
    if($null -ne $script:G.QuantityPicker){Draw-QuantityPicker $Graphics}
}

function Draw-MainMenu {
    param([Drawing.Graphics] $Graphics)
    Draw-Starfield $Graphics 0
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(245,3,4,7)) ([Drawing.RectangleF]::new(0,500,1280,220))
    $drift=[Math]::Sin($script:G.Time*0.65)*6
    Draw-VectorHelmet $Graphics 395 (285+$drift) 1.12
    Draw-Text $Graphics "SPACEFRACK" $script:Assets.FontTitle (Get-Color White) ([Drawing.RectangleF]::new(635,165,535,70))
    Draw-Text $Graphics "INDEPENDENT ORBITAL EXTRACTION" $script:Assets.FontSmallBold (Get-Color DarkCyan) ([Drawing.RectangleF]::new(641,240,440,24))
    Draw-Text $Graphics "UI EDITION" $script:Assets.FontBody (Get-Color Gray) ([Drawing.RectangleF]::new(642,286,410,26))
    Draw-Button $Graphics ([Drawing.RectangleF]::new(642,345,300,52)) "NEW FLIGHT" "NewRun" $null $true (Get-Color Cyan)
    Draw-Button $Graphics ([Drawing.RectangleF]::new(642,412,300,42)) "LOAD FLIGHT" "TitleSaves" $null ($script:G.SaveFiles.Count -gt 0) (Get-Color Green)
    Draw-Text $Graphics ("By PijiN | Version {0}" -f $script:Version) $script:Assets.FontTiny (Get-Color DarkGray) ([Drawing.RectangleF]::new(642,475,430,20))
}

function Draw-DeathOverlay {
    param([Drawing.Graphics] $Graphics)
    Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb(205,42,3,7)) ([Drawing.RectangleF]::new(0,0,1280,720))
    Draw-VectorHelmet $Graphics 640 275 0.82
    Draw-Text $Graphics "HULL FAILURE" $script:Assets.FontHeading (Get-Color Red) ([Drawing.RectangleF]::new(0,442,1280,42)) $script:Assets.Center
    Draw-Button $Graphics ([Drawing.RectangleF]::new(515,585,250,48)) "RETURN TO TITLE" "Title" $null $true (Get-Color Red)
}

function Paint-Game {
    param([Drawing.Graphics] $Graphics)
    # Text and geometry quality stay consistent on every renderer tier. The adaptive
    # path reduces cadence and decorative animation, not legibility or edge quality.
    $Graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.TextRenderingHint=[Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $script:HitTargets.Clear()
    $script:G.HoveredPlanet=""
    $clientW=[double]$script:Canvas.ClientSize.Width
    $clientH=[double]$script:Canvas.ClientSize.Height
    $script:Scale=[Math]::Min($clientW/$script:VirtualWidth,$clientH/$script:VirtualHeight)
    $script:OffsetX=($clientW-($script:VirtualWidth*$script:Scale))/2.0
    $script:OffsetY=($clientH-($script:VirtualHeight*$script:Scale))/2.0
    $Graphics.Clear([Drawing.Color]::Black)
    $saved=$Graphics.Save()
    $Graphics.TranslateTransform([single]$script:OffsetX,[single]$script:OffsetY)
    $Graphics.ScaleTransform([single]$script:Scale,[single]$script:Scale)
    $vibrationX=0.0;$vibrationY=0.0
    if($script:G.FrackingActive -and $script:G.DrillVibration){
        $vibrationScale=(Get-ClampedValue $script:G.DrillVibrationIntensity 0.0 100.0)/35.0
        $vibrationX=(([Math]::Sin($script:G.Time*25.0)*0.36)+([Math]::Sin(($script:G.Time*41.0)+1.1)*0.16))*$vibrationScale
        $vibrationY=(([Math]::Sin(($script:G.Time*29.0)+0.7)*0.25)+([Math]::Sin($script:G.Time*47.0)*0.10))*$vibrationScale
    }
    $shakeX=$vibrationX+$(if($script:G.Shake -gt 0){Get-RandomDouble (-$script:G.Shake) $script:G.Shake}else{0})
    $shakeY=$vibrationY+$(if($script:G.Shake -gt 0){Get-RandomDouble (-$script:G.Shake*0.6) ($script:G.Shake*0.6)}else{0})
    $script:FrameShakeX=$shakeX;$script:FrameShakeY=$shakeY
    $Graphics.TranslateTransform([single]$shakeX,[single]$shakeY)

    if($script:G.Mode -eq "Title"){
        Draw-MainMenu $Graphics
    }
    else{
        Draw-World $Graphics
        Draw-CockpitShell $Graphics
        Draw-FrackingMarquee $Graphics
        Draw-Mfd $Graphics
        if($script:G.Mode -eq "Death"){Draw-DeathOverlay $Graphics}
    }
    if($script:G.RedFlash -gt 0){
        $alpha=[int](Get-ClampedValue ($script:G.RedFlash*210) 0 130)
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb($alpha,187,12,18)) ([Drawing.RectangleF]::new(0,0,1280,720))
    }
    if($script:G.ImpactFlash -gt 0){
        $alpha=[int](Get-ClampedValue ($script:G.ImpactFlash*245) 0 150)
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb($alpha,255,224,132)) ([Drawing.RectangleF]::new(0,0,1280,720))
    }
    if($script:G.GreenFlash -gt 0){
        $alpha=[int](Get-ClampedValue ($script:G.GreenFlash*190) 0 115)
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb($alpha,16,150,55)) ([Drawing.RectangleF]::new(0,0,1280,720))
    }
    if($script:G.CyanFlash -gt 0){
        $alpha=[int](Get-ClampedValue ($script:G.CyanFlash*190) 0 115)
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb($alpha,0,154,190)) ([Drawing.RectangleF]::new(0,0,1280,720))
    }
    if($script:G.Mode -eq "Distress"){
        $pulse=[int](20+(25*(0.5+0.5*[Math]::Sin($script:G.Time*7.0))))
        Fill-RectangleColor $Graphics ([Drawing.Color]::FromArgb($pulse,180,0,8)) ([Drawing.RectangleF]::new(0,0,1280,720))
    }
    $Graphics.Restore($saved)
}

function Invoke-RenderBenchmark {
    $frameCount=[Math]::Max(3,$BenchmarkFrames)
    $scenarios=@(
        @{Name="Title";Mode="Title";SystemBlend=0.0;CloseZoom=0.0;TraderBlend=0.0;Fracking=$false},
        @{Name="Orbit";Mode="Orbit";SystemBlend=0.0;CloseZoom=0.0;TraderBlend=0.0;Fracking=$false},
        @{Name="SystemPan";Mode="System";SystemBlend=0.5;CloseZoom=0.0;TraderBlend=0.0;Fracking=$false},
        @{Name="System";Mode="System";SystemBlend=1.0;CloseZoom=0.0;TraderBlend=0.0;Fracking=$false},
        @{Name="Trader";Mode="Trader";SystemBlend=0.0;CloseZoom=0.0;TraderBlend=1.0;Fracking=$false},
        @{Name="FrackZoom";Mode="Frack";SystemBlend=0.0;CloseZoom=0.5;TraderBlend=0.0;Fracking=$true},
        @{Name="Frack";Mode="Frack";SystemBlend=0.0;CloseZoom=1.0;TraderBlend=0.0;Fracking=$true}
    )
    foreach($size in @([Drawing.Size]::new(1280,720),[Drawing.Size]::new(2560,1440))){
        $script:Form.ClientSize=$size
        $script:Form.PerformLayout()
        $bitmap=New-Object Drawing.Bitmap($size.Width,$size.Height)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        try{
            foreach($scenario in $scenarios){
                $script:G.Mode=$scenario.Mode
                $script:G.SystemBlend=$scenario.SystemBlend
                $script:G.TargetSystemBlend=$(if($scenario.Name -eq "SystemPan"){1.0}else{$scenario.SystemBlend})
                $script:G.CloseZoom=$scenario.CloseZoom
                $script:G.TargetCloseZoom=$(if($scenario.Name -eq "FrackZoom"){1.0}else{$scenario.CloseZoom})
                $script:G.TraderBlend=$scenario.TraderBlend
                $script:G.TargetTraderBlend=$scenario.TraderBlend
                $script:G.FrackingActive=$scenario.Fracking
                Paint-Game $graphics
                $stopwatch=[Diagnostics.Stopwatch]::StartNew()
                for($frame=0;$frame -lt $frameCount;$frame++){
                    $script:G.Time+=0.0166667
                    Paint-Game $graphics
                }
                $stopwatch.Stop()
                Write-GameLog ("BENCH {0} {1}x{2}: {3:N2} ms/frame ({4:N1} fps)" -f $scenario.Name,$size.Width,$size.Height,($stopwatch.Elapsed.TotalMilliseconds/$frameCount),($frameCount/[Math]::Max(0.001,$stopwatch.Elapsed.TotalSeconds)))
            }
            if($size.Width -eq 1280){
                $components=@(
                    @{Name="Starfield";Run={Draw-Starfield $graphics 0.0}},
                    @{Name="Camera";Run={Draw-CameraNavigation $graphics}},
                    @{Name="Cockpit";Run={Draw-CockpitShell $graphics}},
                    @{Name="Marquee";Run={Draw-FrackingMarquee $graphics}},
                    @{Name="FrackMFD";Run={Draw-MfdFrack $graphics}}
                )
                foreach($component in $components){
                    & $component.Run
                    $stopwatch=[Diagnostics.Stopwatch]::StartNew()
                    for($frame=0;$frame -lt $frameCount;$frame++){& $component.Run}
                    $stopwatch.Stop()
                    Write-GameLog ("BENCH PART {0}: {1:N2} ms" -f $component.Name,($stopwatch.Elapsed.TotalMilliseconds/$frameCount))
                }
            }
        }finally{$graphics.Dispose();$bitmap.Dispose()}
    }
}

function Invoke-Action {
    param([string] $Action,$Data)
    if($script:G.InputLocked -gt 0 -and $Action -notin @("None")){return}
    if($script:G.CryoActive -and $Action -notin @("None")){return}
    switch($Action){
        "NewRun" {Start-NewRun}
        "Title" {New-GameState;Refresh-SaveFiles}
        "TitleSaves" {$script:G.ReturnMode="Title";Open-Saves}
        "Orbit" {Open-Orbit}
        "System" {Open-SystemMap}
        "Cargo" {Open-Cargo}
        "CloseCargo" {Close-Cargo}
        "SelectPlanet" {
            $script:G.SelectedPlanet=[string]$Data
            if($script:G.SelectedPlanet -eq $script:G.Player.Location){Open-Orbit}
            else{$script:G.ConfirmTravel=$true}
        }
        "PrepareTravel" {
            $script:G.SelectedPlanet=[string]$Data
            if($script:G.SelectedPlanet -eq $script:G.Player.Location){Open-Orbit}
            else{$script:G.ConfirmTravel=$true}
        }
        "CancelTravel" {$script:G.ConfirmTravel=$false}
        "ConfirmTravel" {Start-Travel ([string]$Data)}
        "StartFrack" {Start-Fracking}
        "StopFrack" {Stop-Fracking}
        "SelectCargo" {$script:G.SelectedCargo=[string]$Data}
        "UseCargo" {Use-CargoItem ([string]$Data)}
        "Jettison" {Jettison-CargoItem ([string]$Data)}
        "Trader" {Open-Trader}
        "CloseTrader" {Close-Trader}
        "TraderTab" {Set-TraderTab ([string]$Data)}
        "Repair" {Invoke-Repair}
        "Refuel" {Invoke-Refuel}
        "BuySupply" {Buy-Supply ([string]$Data)}
        "SellCargo" {Sell-Cargo ([string]$Data)}
        "SellNonQuest" {Sell-NonQuestCargo}
        "SellSurplus" {Sell-QuestSurplus}
        "TradePickSell" {$name=[string]$Data;$maximum=Get-TradeAvailableQuantity "Sell" $name;if($maximum -le 1){if($maximum -eq 1){[void](Add-TradeItem "Sell" $name 1)}}else{Open-TradeQuantityPicker "Sell" $name "Add" $maximum}}
        "TradePickBuy" {$name=[string]$Data;$maximum=Get-TradeAvailableQuantity "Buy" $name;if($maximum -le 1){if($maximum -eq 1){[void](Add-TradeItem "Buy" $name 1)}}else{Open-TradeQuantityPicker "Buy" $name "Add" $maximum}}
        "TradePickPending" {$parts=([string]$Data)-split '\|',2;$maximum=Get-TradePendingQuantity $parts[0] $parts[1];if($maximum -le 1){[void](Remove-TradeItem $parts[0] $parts[1] 1)}else{Open-TradeQuantityPicker $parts[0] $parts[1] "Remove" $maximum}}
        "CommitTrade" {Commit-Trade}
        "ClearTrade" {Clear-TradeLedger}
        "QuickStageSell" {Stage-QuickSell}
        "TradePaneScroll" {$parts=([string]$Data)-split '\|',2;$amount=[int]$parts[1];if($parts[0] -eq "Sell"){$script:G.TraderSellScroll+=$amount}elseif($parts[0] -eq "Buy"){$script:G.TraderBuyScroll+=$amount}else{$script:G.TradeScroll+=$amount}}
        "PickerConfirm" {Apply-QuantityPicker}
        "PickerCancel" {$script:G.QuantityPicker=$null;$script:G.QuantityDragging=$false}
        "Contracts" {Open-Contracts}
        "ContractLog" {Open-Contracts "Log"}
        "TraderContracts" {Open-Contracts "Trader"}
        "CloseContracts" {Close-Contracts}
        "SelectQuest" {$script:G.SelectedQuest=[string]$Data;$script:G.ContractRequirementScroll=0}
        "ContractTab" {$script:G.ContractTab=[string]$Data;$script:G.QuestScroll=0;$script:G.ContractRequirementScroll=0;$script:G.SelectedQuest=""}
        "ContractReqScroll" {$script:G.ContractRequirementScroll+=[int]$Data}
        "QuestAction" {Invoke-QuestAction ([string]$Data)}
        "XRF" {Start-XRFScan}
        "Cryo" {Start-CryoSleep}
        "Galaxy" {Open-Galaxy}
        "SelectSystem" {$script:G.SelectedSystem=[string]$Data}
        "Hyperjump" {Start-Hyperjump ([string]$Data)}
        "Distress" {Start-DistressSignal}
        "CancelDistress" {Cancel-DistressSignal}
        "Settings" {Open-Settings}
        "CloseSettings" {Close-Settings}
        "ToggleVibration" {$script:G.DrillVibration=-not $script:G.DrillVibration}
        "Status" {Open-Status}
        "Save" {Save-Game}
        "Saves" {Open-Saves}
        "CloseSaves" {Close-Saves}
        "SelectSave" {$script:G.SelectedSave=[string]$Data}
        "LoadSelected" {if(-not [string]::IsNullOrWhiteSpace($script:G.SelectedSave)){Load-Game $script:G.SelectedSave}}
        "DeleteSave" {Remove-SelectedSave}
        "PruneSaves" {Prune-SaveFiles}
        "RenamePilot" {Rename-Pilot}
        "Fullscreen" {if($script:Form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized){$script:Form.WindowState=[Windows.Forms.FormWindowState]::Normal}else{$script:Form.WindowState=[Windows.Forms.FormWindowState]::Maximized}}
    }
}

function Invoke-LogicalClick {
    param([double] $X,[double] $Y)
    $pickerOpen=$null -ne $script:G.QuantityPicker
    for($i=$script:HitTargets.Count-1;$i -ge 0;$i--){
        $target=$script:HitTargets[$i]
        if($target.Enabled -and $target.Rectangle.Contains([Drawing.PointF]::new([single]$X,[single]$Y))){
            if($pickerOpen -and $target.Action -notin @("PickerConfirm","PickerCancel")){$script:G.QuantityPicker=$null;$script:G.QuantityDragging=$false;return}
            if([double]$target.HoldSeconds -gt 0.0){return}
            Invoke-Action $target.Action $target.Data
            return
        }
    }
    if($pickerOpen){$script:G.QuantityPicker=$null;$script:G.QuantityDragging=$false}
}

function Get-HitTargetAtPoint {
    param([double] $X,[double] $Y)
    for($i=$script:HitTargets.Count-1;$i -ge 0;$i--){$target=$script:HitTargets[$i];if($target.Enabled -and $target.Rectangle.Contains([Drawing.PointF]::new([single]$X,[single]$Y))){return $target}}
    return $null
}

function Invoke-TradeRightClick {
    param([double] $X,[double] $Y)
    if($script:G.Mode -ne "Trader" -or $script:G.TraderTab -ne "Trade" -or $null -ne $script:G.QuantityPicker){return}
    $target=Get-HitTargetAtPoint $X $Y
    if($null -eq $target){return}
    if($target.Action -eq "TradePickSell"){[void](Remove-TradeItem "Sell" ([string]$target.Data) 1)}
    elseif($target.Action -eq "TradePickBuy"){[void](Remove-TradeItem "Buy" ([string]$target.Data) 1)}
    elseif($target.Action -eq "TradePickPending"){$parts=([string]$target.Data)-split '\|',2;[void](Remove-TradeItem $parts[0] $parts[1] 1)}
}

function Convert-MousePoint {
    param([int] $X,[int] $Y)
    if($script:Scale -le 0){return [Drawing.PointF]::new(-1000,-1000)}
    return [Drawing.PointF]::new([single](($X-$script:OffsetX)/$script:Scale),[single](($Y-$script:OffsetY)/$script:Scale))
}

function Invoke-KeyDown {
    param([Windows.Forms.KeyEventArgs] $Event)
    if($script:G.CryoActive){$Event.Handled=$true;$Event.SuppressKeyPress=$true;return}
    if($null -ne $script:G.QuantityPicker){
        $picker=$script:G.QuantityPicker;$digit=-1
        if($Event.KeyCode -ge [Windows.Forms.Keys]::D0 -and $Event.KeyCode -le [Windows.Forms.Keys]::D9){$digit=[int]$Event.KeyCode-[int][Windows.Forms.Keys]::D0}
        elseif($Event.KeyCode -ge [Windows.Forms.Keys]::NumPad0 -and $Event.KeyCode -le [Windows.Forms.Keys]::NumPad9){$digit=[int]$Event.KeyCode-[int][Windows.Forms.Keys]::NumPad0}
        if($digit -ge 0){
            if(-not $picker.TypingStarted){$picker.Input=[string]$digit;$picker.TypingStarted=$true}
            elseif($picker.Input.Length -lt 7){$picker.Input+=([string]$digit)}
            $parsed=0;if([int]::TryParse($picker.Input,[ref]$parsed)){$picker.Value=[int](Get-ClampedValue $parsed 1 $picker.Maximum)}
        }elseif($Event.KeyCode -eq [Windows.Forms.Keys]::Back){
            if(-not $picker.TypingStarted){$picker.Input="";$picker.TypingStarted=$true}elseif($picker.Input.Length -gt 0){$picker.Input=$picker.Input.Substring(0,$picker.Input.Length-1)};$parsed=0;if([int]::TryParse($picker.Input,[ref]$parsed)){$picker.Value=[int](Get-ClampedValue $parsed 1 $picker.Maximum)}
        }elseif($Event.KeyCode -eq [Windows.Forms.Keys]::Enter){Apply-QuantityPicker}
        elseif($Event.KeyCode -eq [Windows.Forms.Keys]::Escape){$script:G.QuantityPicker=$null;$script:G.QuantityDragging=$false}
        $Event.Handled=$true;$Event.SuppressKeyPress=$true;return
    }
    switch($Event.KeyCode){
        ([Windows.Forms.Keys]::Escape){
            if($script:G.Mode -eq "Cargo"){Close-Cargo}
            elseif($script:G.Mode -eq "Trader"){Close-Trader}
            elseif($script:G.Mode -eq "System"){Open-Orbit}
            elseif($script:G.Mode -eq "Frack"){Stop-Fracking}
            elseif($script:G.Mode -eq "Contracts"){Close-Contracts}
            elseif($script:G.Mode -eq "XRF"){Open-Orbit}
            elseif($script:G.Mode -eq "Galaxy"){Open-SystemMap}
            elseif($script:G.Mode -eq "Settings"){Close-Settings}
            elseif($script:G.Mode -eq "Status"){$script:G.Mode="Settings"}
            elseif($script:G.Mode -eq "Saves"){Close-Saves}
            elseif($script:G.Mode -eq "Distress"){Cancel-DistressSignal}
        }
        ([Windows.Forms.Keys]::I){Open-Cargo}
        ([Windows.Forms.Keys]::M){Open-SystemMap}
        ([Windows.Forms.Keys]::Q){Open-Contracts "Log"}
        ([Windows.Forms.Keys]::S){Open-Settings}
        ([Windows.Forms.Keys]::F11){
            if($script:Form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized){$script:Form.WindowState=[Windows.Forms.FormWindowState]::Normal}
            else{$script:Form.WindowState=[Windows.Forms.FormWindowState]::Maximized}
        }
    }
}

function Save-SmokeCapture {
    param([string] $Path)
    if([string]::IsNullOrWhiteSpace($Path)){return}
    $bitmap=New-Object Drawing.Bitmap($script:Canvas.ClientSize.Width,$script:Canvas.ClientSize.Height)
    try{
        $script:Canvas.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height))
        $bitmap.Save($Path,[Drawing.Imaging.ImageFormat]::Png)
    }
    finally{$bitmap.Dispose()}
}

function Get-CaptureVariantPath {
    param([string] $Path,[string] $Variant)
    if([string]::IsNullOrWhiteSpace($Path)){return ""}
    $directory=[IO.Path]::GetDirectoryName($Path)
    $name=[IO.Path]::GetFileNameWithoutExtension($Path)
    return [IO.Path]::Combine($directory,("{0}-{1}.png" -f $name,$Variant))
}

function Start-SpaceFrack {
    try{[Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::SystemAware)|Out-Null}catch{}
    [Windows.Forms.Application]::EnableVisualStyles()
    $textRenderingKey="SpaceFrack.CompatibleTextRenderingInitialized"
    if(-not [AppDomain]::CurrentDomain.GetData($textRenderingKey)){
        try{[Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)}catch{}
        [AppDomain]::CurrentDomain.SetData($textRenderingKey,$true)
    }
    $script:Form=New-Object Windows.Forms.Form
    $script:Form.Text="SpaceFrack - UI Edition"
    $script:Form.StartPosition=[Windows.Forms.FormStartPosition]::CenterScreen
    $script:Form.ClientSize=[Drawing.Size]::new(1280,720)
    $script:Form.MinimumSize=[Drawing.Size]::new(1024,615)
    $script:Form.BackColor=[Drawing.Color]::Black
    $script:Form.KeyPreview=$true
    if($SoakTestSeconds -gt 0 -or $ParityTest){
        $script:Form.ShowInTaskbar=$false
        $script:Form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
        $script:Form.Location=[Drawing.Point]::new(-3000,-3000)
    }

    $script:Canvas=New-Object SpaceFrackCanvas
    $script:Canvas.Dock=[Windows.Forms.DockStyle]::Fill
    $script:Canvas.BackColor=[Drawing.Color]::Black
    $script:Canvas.Cursor=[Windows.Forms.Cursors]::Hand
    $script:Form.Controls.Add($script:Canvas)

    Initialize-Assets
    New-GameState
    Refresh-SaveFiles
    if($RenderBenchmark){
        Start-NewRun
        Invoke-RenderBenchmark
        Remove-Assets
        $script:Form.Dispose()
        return
    }
    $script:Clock=[Diagnostics.Stopwatch]::StartNew()
    $script:LastTick=$script:Clock.ElapsedTicks
    $script:Timer=New-Object Windows.Forms.Timer
    $script:Timer.Interval=16
    $script:Timer.Add_Tick({
        if($script:Closing -or $script:Canvas.IsDisposed -or -not $script:Canvas.IsHandleCreated){return}
        $now=$script:Clock.ElapsedTicks
        $delta=($now-$script:LastTick)/[double][Diagnostics.Stopwatch]::Frequency
        $script:LastTick=$now
        $delta=Get-ClampedValue $delta 0 0.05
        try{Update-Game $delta}
        catch{
            $script:Timer.Stop();$script:FatalError=$_.Exception
            Write-GameLog ("Update failure: "+$_.Exception.Message) -Critical
            if($SmokeTest){$script:Form.Close()}
            else{[Windows.Forms.MessageBox]::Show($_.Exception.Message,"SpaceFrack update failure")|Out-Null}
        }
        if(-not $script:Canvas.IsDisposed){$script:Canvas.Invalidate()}
    })

    $script:Canvas.Add_Paint({
        param($sender,$eventArgs)
        if($script:IsPainting -or $script:Closing){return}
        $script:IsPainting=$true
        $paintStarted=[Diagnostics.Stopwatch]::GetTimestamp()
        try{Paint-Game $eventArgs.Graphics}
        catch{
            if($null -eq $script:FatalError){
                $script:FatalError=$_.Exception
                Write-GameLog ("Paint failure: "+$_.Exception.Message) -Critical
                if($SmokeTest){$script:Form.Close()}
            }
        }
        finally{
            $paintElapsed=([Diagnostics.Stopwatch]::GetTimestamp()-$paintStarted)*1000.0/[Diagnostics.Stopwatch]::Frequency
            Register-RenderPerformance $paintElapsed
            $script:IsPainting=$false
        }
    })
    $script:Canvas.Add_MouseMove({
        param($sender,$eventArgs)
        $point=Convert-MousePoint $eventArgs.X $eventArgs.Y
        $script:MouseX=$point.X;$script:MouseY=$point.Y
        if($script:G.VibrationDragging){Set-VibrationIntensityFromX $point.X}
        elseif($script:G.QuantityDragging -and $null -ne $script:G.QuantityPicker){Set-QuantityPickerFromX $point.X}
    })
    $script:Canvas.Add_MouseDown({
        param($sender,$eventArgs)
        if($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left){
            $point=Convert-MousePoint $eventArgs.X $eventArgs.Y
            $script:MouseX=$point.X;$script:MouseY=$point.Y
            if($script:G.Mode -eq "Settings" -and $script:G.VibrationSliderRect.Contains($point)){
                Set-VibrationIntensityFromX $point.X;$script:G.VibrationDragging=$true;$script:Canvas.Capture=$true;$script:Canvas.Focus();return
            }
            if($null -ne $script:G.QuantityPicker -and $script:G.QuantityPicker.SliderRect.Contains($point)){
                Set-QuantityPickerFromX $point.X;$script:G.QuantityDragging=$true;$script:Canvas.Capture=$true;$script:Canvas.Focus();return
            }
            $target=Get-HitTargetAtPoint $point.X $point.Y
            if($null -ne $target -and [double]$target.HoldSeconds -gt 0.0){
                if($null -ne $script:G.QuantityPicker){$script:G.QuantityPicker=$null;$script:G.QuantityDragging=$false;$script:Canvas.Focus();return}
                if(Start-HoldButton $target){$script:Canvas.Capture=$true}
                $script:Canvas.Focus();return
            }
            Invoke-LogicalClick $point.X $point.Y
            $script:Canvas.Focus()
        }
        elseif($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Right){
            $point=Convert-MousePoint $eventArgs.X $eventArgs.Y
            Invoke-TradeRightClick $point.X $point.Y
            $script:Canvas.Focus()
        }
    })
    $script:Canvas.Add_MouseUp({
        param($sender,$eventArgs)
        if($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left){$script:G.QuantityDragging=$false;$script:G.VibrationDragging=$false;Cancel-HoldButton;$script:Canvas.Capture=$false}
    })
    $script:Canvas.Add_MouseWheel({
        param($sender,$eventArgs)
        if($null -ne $script:G.QuantityPicker){
            $change=if($eventArgs.Delta -lt 0){1}else{-1};$script:G.QuantityPicker.Value=[int](Get-ClampedValue ($script:G.QuantityPicker.Value+$change) 1 $script:G.QuantityPicker.Maximum);$script:G.QuantityPicker.Input="";$script:G.QuantityPicker.TypingStarted=$false
        }
        elseif($script:G.Mode -eq "Settings" -and $script:G.VibrationSliderRect.Contains([Drawing.PointF]::new([single]$script:MouseX,[single]$script:MouseY))){
            $change=if($eventArgs.Delta -gt 0){5}else{-5};$script:G.DrillVibrationIntensity=Get-ClampedValue ($script:G.DrillVibrationIntensity+$change) 0.0 100.0;$script:G.DrillVibration=$script:G.DrillVibrationIntensity -gt 0
        }
        elseif($script:G.Mode -eq "Trader" -and $script:G.TraderTab -eq "Trade"){
            if($script:MouseX -lt 458){if($eventArgs.Delta -lt 0){$script:G.TraderSellScroll++}else{$script:G.TraderSellScroll--}}
            elseif($script:MouseX -gt 772){if($eventArgs.Delta -lt 0){$script:G.TraderBuyScroll++}else{$script:G.TraderBuyScroll--}}
            else{if($eventArgs.Delta -lt 0){$script:G.TradeScroll++}else{$script:G.TradeScroll--}}
        }
        elseif($script:G.Mode -eq "Cargo"){
            if($eventArgs.Delta -lt 0){$script:G.CargoScroll++}else{$script:G.CargoScroll--}
        }
        elseif($script:G.Mode -eq "Trader"){
            if($eventArgs.Delta -lt 0){$script:G.TraderScroll++}else{$script:G.TraderScroll--}
        }
        elseif($script:G.Mode -eq "Contracts"){
            if($script:MouseX -ge 615 -and -not [string]::IsNullOrWhiteSpace($script:G.SelectedQuest)){
                if($eventArgs.Delta -lt 0){$script:G.ContractRequirementScroll++}else{$script:G.ContractRequirementScroll--}
            }elseif($eventArgs.Delta -lt 0){$script:G.QuestScroll++}else{$script:G.QuestScroll--}
        }
        elseif($script:G.Mode -eq "Saves"){
            if($eventArgs.Delta -lt 0){$script:G.SaveScroll++}else{$script:G.SaveScroll--}
        }
    })
    $script:Form.Add_KeyDown({param($sender,$eventArgs)Invoke-KeyDown $eventArgs})
    $script:Form.Add_Deactivate({Cancel-HoldButton})
    $script:Form.Add_FormClosing({$script:Closing=$true;$script:Timer.Stop()})
    $script:Form.Add_FormClosed({$script:Clock.Stop();$script:Timer.Dispose();Remove-Assets})
    $script:Form.Add_Shown({
        $script:Canvas.Focus();$script:Timer.Start()
        if($ParityTest){
            try{
                Start-NewRun
                Assert-GameState ($script:G.Systems.Count -eq 2) "Sol and Typhon systems loaded"
                Assert-GameState ((Get-AllQuestRows).Count -eq 47) "all 47 faction contracts loaded"
                Assert-GameState ($script:G.ResourceMaster.Count -ge 60) "complete resource and upgrade catalog loaded"
                $frackEdgeRise=$script:FrackPlanetRadius-[Math]::Sqrt(($script:FrackPlanetRadius*$script:FrackPlanetRadius)-(640.0*640.0))
                Assert-GameState ([Math]::Abs(($script:FrackPlanetCenterY-$script:FrackPlanetRadius)-75.0) -lt 0.01 -and $frackEdgeRise -lt 75.0) "fracking camera holds a shallow planetary horizon"
                Assert-GameState ($script:G.DrillVibration -and [int]$script:G.DrillVibrationIntensity -eq 1) "drill vibration defaults on at one percent"
                $script:G.VibrationSliderRect=[Drawing.RectangleF]::new(0,0,100,20);Set-VibrationIntensityFromX 72
                Assert-GameState ($script:G.DrillVibration -and [int]$script:G.DrillVibrationIntensity -eq 72) "vibration intensity slider maps pointer position"
                $script:G.DrillVibration=$true;$script:G.DrillVibrationIntensity=1
                $holdTestTarget=[pscustomobject]@{Action="None";Data=$null;Enabled=$true;HoldSeconds=$script:XRFHoldSeconds;Rectangle=[Drawing.RectangleF]::new(0,0,100,30)}
                $script:MouseX=20;$script:MouseY=15;[void](Start-HoldButton $holdTestTarget);Update-HoldButton 0.25
                Assert-GameState ($null -ne $script:G.HoldButton -and [Math]::Abs([double]$script:G.HoldButton.Elapsed-0.25) -lt 0.001) "hold button accumulates progress while pressed inside"
                $holdBitmap=[Drawing.Bitmap]::new(120,40);$holdGraphics=[Drawing.Graphics]::FromImage($holdBitmap)
                try{
                    $holdGraphics.Clear([Drawing.Color]::Black);$script:HitTargets.Clear()
                    Draw-Button $holdGraphics $holdTestTarget.Rectangle "" "None" $null $true (Get-Color Magenta) -HoldSeconds $script:XRFHoldSeconds
                    $registeredHold=$script:HitTargets[$script:HitTargets.Count-1]
                    Assert-GameState ($holdBitmap.GetPixel(10,15).ToArgb() -ne $holdBitmap.GetPixel(90,15).ToArgb() -and [Math]::Abs([double]$registeredHold.HoldSeconds-$script:XRFHoldSeconds) -lt 0.001) "hold button renders progress fill and registers duration"
                }finally{$holdGraphics.Dispose();$holdBitmap.Dispose()}
                Cancel-HoldButton
                Assert-GameState ($null -eq $script:G.HoldButton) "hold button release cancels pending action"
                $script:MouseX=20;$script:MouseY=15;[void](Start-HoldButton $holdTestTarget);$script:MouseX=120;Update-HoldButton 0.05
                Assert-GameState ($null -eq $script:G.HoldButton) "hold button pointer exit cancels pending action"
                $samplesExpected=@{Silicates=60;Carbon=40;Oxygen=40;Water=40;Iron=50;Hydrogen=35;Nitrogen=30;Magnesium=20;Calcium=20;Aluminum=20;Sulfur=20;ScrapMetal=20;Zinc=15;Tin=15;Copper=15;Silicon=10;Nickel=10;Biomass=5;Boron=10;Argon=10;Neon=10;Helium=8;Silver=8;Tungsten=5;Platinum=3;Gold=3;MetallicHydrogen=5;Fossils=2;Plutonium=2;Uranium=5;Radium=4;Neptunium=2;Promethium=1;Iridium=1}
                $samplesQuest=(Get-QuestRow "pluto_8").Quest;$samplesMatch=$samplesQuest.Requirements.Count -eq $samplesExpected.Count
                foreach($name in $samplesExpected.Keys){if(-not $samplesQuest.Requirements.ContainsKey($name) -or [int]$samplesQuest.Requirements[$name] -ne [int]$samplesExpected[$name]){$samplesMatch=$false;break}}
                Assert-GameState $samplesMatch "complete Pluto Samples requirement library"

                $traderExpectations=@{
                    Earth=@(5000,11);Mars=@(3000,9);Pluto=@(3000,10);Bastion=@(9001,9);Flotsam=@(4500,13)
                }
                foreach($traderName in $traderExpectations.Keys){
                    $traderPlanet=if($traderName -in @("Bastion","Flotsam")){$script:G.Systems.Typhon.Planets[$traderName]}else{$script:G.Systems.Sol.Planets[$traderName]}
                    Assert-GameState ([int]$traderPlanet.TraderCredits -eq $traderExpectations[$traderName][0] -and $traderPlanet.TraderStockRules.Count -eq $traderExpectations[$traderName][1]) ("canonical trader budget and stock table for {0}" -f $traderName)
                    $dialogValid=$traderPlanet.Dialog.Count -eq 8
                    foreach($dialogKey in @("Greeting","TradeGreeting","Refuel","Repair","Trade","InsufficientFunds","InsufficientFundsTrader","Frustrated")){if(-not $traderPlanet.Dialog.ContainsKey($dialogKey) -or @($traderPlanet.Dialog[$dialogKey]).Count -lt 3){$dialogValid=$false;break}}
                    Assert-GameState $dialogValid ("canonical trader dialog table for {0}" -f $traderName)
                }
                Assert-GameState ([int]$script:G.Systems.Sol.Planets.Earth.TraderStockRules["U.C.E. Shield Generator MK I"].DoubleChance -eq 6 -and [int]$script:G.Systems.Typhon.Planets.Flotsam.TraderStockRules["Bastion Fuel Cell"].DoubleChance -eq 4) "canonical trader double-roll chances"
                $forcedStock=New-TraderStock @{Forced=@{Chance=100;MinQty=1;MaxQty=1;DoubleChance=100};Never=@{Chance=0;MinQty=9;MaxQty=9};Fixed=3}
                Assert-GameState ($forcedStock.Forced -eq 2 -and $forcedStock.Fixed -eq 3 -and -not $forcedStock.ContainsKey("Never")) "canonical trader stock roll semantics"
                $quarterTest=[datetime]::new(2026,7,13,10,7,49)
                Assert-GameState ((Get-LocalQuarterHourBoundary $quarterTest) -eq [datetime]::new(2026,7,13,10,0,0) -and (Get-NextLocalQuarterHour $quarterTest) -eq [datetime]::new(2026,7,13,10,15,0)) "local quarter-hour restock boundaries"
                Assert-GameState ((Get-NextLocalQuarterHour ([datetime]::new(2026,7,13,23,59,59))) -eq [datetime]::new(2026,7,14,0,0,0)) "midnight restock boundary rollover"
                $script:G.TraderState=@{}
                $quarterTrader=Initialize-TraderState $quarterTest
                Assert-GameState ([datetime]$quarterTrader.LastRestock -eq [datetime]::new(2026,7,13,10,0,0)) "new trader state records the current quarter boundary"
                $quarterTrader.Credits=17;$quarterTrader.Stock=@{Sentinel=1}
                [void](Initialize-TraderState ([datetime]::new(2026,7,13,10,14,59)))
                Assert-GameState ($quarterTrader.Credits -eq 17 -and $quarterTrader.Stock.ContainsKey("Sentinel")) "trader stock remains stable within a quarter hour"
                $quarterTrader=Initialize-TraderState ([datetime]::new(2026,7,13,10,15,0))
                Assert-GameState ($quarterTrader.Credits -eq 3000 -and -not $quarterTrader.Stock.ContainsKey("Sentinel") -and [datetime]$quarterTrader.LastRestock -eq [datetime]::new(2026,7,13,10,15,0)) "trader stock and budget reset on the local quarter hour"
                $quarterTrader.Credits=11;$quarterTrader.Stock=@{Sentinel=2}
                $quarterTrader=Initialize-TraderState ([datetime]::new(2026,7,13,10,30,0))
                Assert-GameState ($quarterTrader.Credits -eq 3000 -and -not $quarterTrader.Stock.ContainsKey("Sentinel") -and [datetime]$quarterTrader.LastRestock -eq [datetime]::new(2026,7,13,10,30,0)) "trader restock repeats across consecutive quarter hours"
                $quarterTrader.Credits=9;$quarterTrader.Stock=@{Sentinel=3};$quarterTrader.LastRestock=[datetime]::new(2026,7,13,14,45,0)
                $quarterTrader=Initialize-TraderState ([datetime]::new(2026,7,13,10,45,0))
                Assert-GameState ($quarterTrader.Credits -eq 3000 -and -not $quarterTrader.Stock.ContainsKey("Sentinel") -and [datetime]$quarterTrader.LastRestock -eq [datetime]::new(2026,7,13,10,45,0)) "invalid future trader timestamp self-heals"
                $localWall=[datetime]::new(2026,7,13,21,15,0,[DateTimeKind]::Unspecified)
                $localOffset=[TimeZoneInfo]::Local.GetUtcOffset($localWall)
                $legacyOffset=[DateTimeOffset]::new($localWall,$localOffset)
                $legacyJsonStamp=("/Date({0})/" -f $legacyOffset.ToUnixTimeMilliseconds())
                $legacyExpected=$legacyOffset.LocalDateTime
                $nestedLegacyStamp=@{DisplayHint=2;DateTime="Monday, July 13, 2026 9:15:00 PM";value=$legacyJsonStamp}
                Assert-GameState ((ConvertTo-LocalTraderTime $legacyJsonStamp) -eq $legacyExpected -and (ConvertTo-LocalTraderTime $nestedLegacyStamp) -eq $legacyExpected) "Windows PowerShell and nested legacy trader timestamps normalize to local time"
                $quarterTrader.LastRestock=$legacyExpected
                $saveTraderCopy=Get-TraderStateSaveCopy
                $savedStamp=[string]$saveTraderCopy["Sol|Mars"].LastRestock
                Assert-GameState ($saveTraderCopy["Sol|Mars"].LastRestock -is [string] -and (ConvertTo-LocalTraderTime $savedStamp) -eq $legacyExpected) "trader timestamps save as unambiguous ISO text"
                $script:G.TraderState["Sol|Earth"]=@{Stock=@{Sentinel=4};Credits=4;LastRestock=[datetime]::new(2026,7,13,10,45,0)}
                $refreshedKeys=@(Refresh-DueTraderStates ([datetime]::new(2026,7,13,11,0,0)))
                Assert-GameState ($refreshedKeys -contains "Sol|Earth" -and $script:G.TraderState["Sol|Earth"].Credits -eq 5000 -and -not $script:G.TraderState["Sol|Earth"].Stock.ContainsKey("Sentinel")) "offscreen trader states refresh at a clock boundary"
                $runtimeBoundary=Get-LocalQuarterHourBoundary
                $script:G.TraderState["Sol|Mars"]=@{Stock=@{Sentinel=5};Credits=5;LastRestock=$runtimeBoundary.AddMinutes(-15)}
                $script:G.TraderRestockBoundary=$runtimeBoundary.AddMinutes(-15);$script:G.TraderRestockPoll=0.0
                Update-Game 0.001
                Assert-GameState ($script:G.TraderState["Sol|Mars"].Credits -eq 3000 -and -not $script:G.TraderState["Sol|Mars"].Stock.ContainsKey("Sentinel") -and [datetime]$script:G.TraderState["Sol|Mars"].LastRestock -eq $runtimeBoundary) "running clock poll applies due trader restocks"
                $script:G.TraderState=@{Mars=@{Stock=@{Legacy=1};Credits=123;LastTrade=[datetime]::new(2026,7,13,10,0,0)}}
                $legacyTrader=Initialize-TraderState $quarterTest
                Assert-GameState ($script:G.TraderState.ContainsKey("Sol|Mars") -and -not $script:G.TraderState.ContainsKey("Mars") -and $legacyTrader.Credits -eq 123 -and [datetime]$legacyTrader.LastRestock -eq [datetime]::new(2026,7,13,10,0,0)) "legacy Spacegame trader state migration"
                $script:G.TraderState=@{}

                $expectedProspecting=@{
                    Sol=@{Mercury=@(55,5,21,909);Venus=@(40,6,21,1162);Earth=@(24,5,22,1060);Mars=@(20,5,23,1032);Ceres=@(27,7,20,1096);Jupiter=@(63,7,16,1014);Saturn=@(62,7,21,1161);Uranus=@(58,7,17,1054);Neptune=@(58,6,15,966);Pluto=@(26,5,23,977);Haumea=@(53,5,19,802);Makemake=@(61,5,19,830);Eris=@(58,5,19,782)}
                    Typhon=@{Pyre=@(65,8,20,5150);Bastion=@(48,9,20,4872);Shrapnel=@(96,11,19,5000);Hyperion=@(80,9,18,5200);Cocytus=@(66,7,16,5070);Flotsam=@(52,6,20,4875)}
                }
                foreach($systemId in $expectedProspecting.Keys){foreach($planetName in $expectedProspecting[$systemId].Keys){
                    $planet=$script:G.Systems[$systemId].Planets[$planetName];$expected=$expectedProspecting[$systemId][$planetName]
                    Assert-GameState ((Get-BaseHazard $planet) -eq $expected[0]) ("canonical HZ for {0}" -f $planetName)
                    Assert-GameState (@($planet.HazardReasons).Count -eq $expected[1]) ("canonical hazard table for {0}" -f $planetName)
                    Assert-GameState ($planet.Resources.Count -eq $expected[2] -and [int](($planet.Resources.Values|Measure-Object -Sum).Sum) -eq $expected[3]) ("canonical resource table for {0}" -f $planetName)
                }}
                Assert-GameState ((Get-HazardEventChance 63) -eq 47 -and (Get-HazardEventChance 0) -eq 0) "integer hazard event chance boundaries"
                $script:G.Player.frackGas=1;Assert-GameState ((Get-EffectiveHazard $script:G.Systems.Sol.Planets.Jupiter) -eq 31) "single stacked gas hazard reduction"
                $script:G.Player.frackGas=2;Assert-GameState ((Get-EffectiveHazard $script:G.Systems.Sol.Planets.Jupiter) -eq 15) "multiplicative stacked gas hazard reduction";$script:G.Player.frackGas=0
                $script:G.Player.RadiationSuit=1;Assert-GameState ((Get-EffectiveHazard $script:G.Systems.Typhon.Planets.Shrapnel) -eq 72) "HZ threshold radiation reduction";$script:G.Player.RadiationSuit=0

                $testPlanet=Get-Planet;$savedTestResources=$testPlanet.Resources;$savedTestHazards=$testPlanet.HazardReasons;$savedTestDanger=$testPlanet.Danger;$savedMaxWeight=$script:G.Player.MaxWeight;$savedFuel=$script:G.Player.Fuel
                $testPlanet.Resources=@{Iron=1};$testPlanet.HazardReasons=@("Hull stress");$testPlanet.Danger=0.0;$script:G.Player.MaxWeight=(Get-CurrentWeight)+0.5;$script:G.Player.Fuel=10.0
                Start-Fracking;[void](Invoke-FrackTick)
                Assert-GameState ($script:G.Inventory.ContainsKey("Iron") -and (Get-CurrentWeight) -gt $script:G.Player.MaxWeight) "final resource may push cargo over capacity"
                Stop-Fracking;$script:G.Inventory.Remove("Iron");$script:G.Player.MaxWeight=$savedMaxWeight;$script:G.Player.Fuel=$savedFuel;$testPlanet.Resources=$savedTestResources;$testPlanet.HazardReasons=$savedTestHazards;$testPlanet.Danger=$savedTestDanger

                $script:G.Player.HP=40;$script:G.Player.MaxHP=100;Add-InventoryItem "U.C.E. Shield Generator MK I" 1;Use-CargoItem "U.C.E. Shield Generator MK I"
                Assert-GameState ($script:G.Player.MaxHP -eq 125 -and $script:G.Player.HP -eq 65) "shield upgrade adds equally to current and maximum HP"
                $script:G.Player.Fuel=10;$script:G.Player.MaxFuel=100;Add-InventoryItem "Auxiliary Fuel Tank" 1;Use-CargoItem "Auxiliary Fuel Tank"
                Assert-GameState ($script:G.Player.MaxFuel -eq 150 -and $script:G.Player.Fuel -eq 60) "fuel tank adds equally to current and maximum fuel"
                $script:G.Player.HP=100;$script:G.Player.MaxHP=100;$script:G.Player.Fuel=100;$script:G.Player.MaxFuel=100

                foreach($upgrade in @("HyperDrive Module","XRF8 Scanner","Cryo-Sleep Chamber","Shield Cell Auto-Injector","Gas Giant Surveyor")){Add-InventoryItem $upgrade 1;Use-CargoItem $upgrade}
                Assert-GameState ([int]$script:G.Player.Hyperdrive -eq 1) "HyperDrive installation"
                Assert-GameState ([int]$script:G.Player.XRFScanner -eq 1) "XRF8 installation"
                $filteredXRF=@(Get-XRFScanResults $script:G.Systems.Typhon.Planets.Flotsam)
                Assert-GameState (@($filteredXRF|Where-Object{$_.Rarity -in @("Consumable","Upgrade")}).Count -eq 0 -and "Bastion Fuel Cell" -notin @($filteredXRF.Name) -and "Bastion Shield Cell" -notin @($filteredXRF.Name)) "XRF omits consumables and upgrades"
                Assert-GameState ([int]$script:G.Player.CryoSkip -eq 1) "cryo chamber installation"
                Assert-GameState ([int]$script:G.Player.AutoAdminister -eq 1) "auto-injector installation"
                Assert-GameState ([int]$script:G.Player.frackGas -eq 1) "stacking hazard upgrade"

                Open-Trader
                Assert-GameState ($script:G.TraderDialogKey -eq "Greeting" -and $script:G.TraderDialog -eq [string](Get-Planet).Dialog.Greeting[0]) "first trader contact uses the canonical Greeting line"
                Set-TraderTab "Trade"
                Assert-GameState ($script:G.TraderDialogKey -eq "TradeGreeting" -and $script:G.TraderDialog -in @((Get-Planet).Dialog.TradeGreeting)) "opening the trade pane uses TradeGreeting dialog"
                Set-TraderTab "Comms";Close-Trader

                $script:G.Player.Credits=10000
                $trader=Initialize-TraderState
                Assert-GameState ($trader.Stock.Count -gt 0) "dynamic trader stock generation"
                $script:G.Player.HP=80;$script:G.Player.Fuel=80;$serviceCreditsBefore=$script:G.Player.Credits;$traderCreditsBefore=$trader.Credits;$serviceTotal=[int][Math]::Ceiling(20*[double](Get-Planet).RepairModifier)+[int][Math]::Ceiling(20*3.0*[double](Get-Planet).FuelModifier)
                Invoke-Repair
                Assert-GameState ($script:G.TraderDialogKey -eq "Repair" -and $script:G.TraderDialog -in @((Get-Planet).Dialog.Repair)) "repair replaces the comms Greeting dialog"
                Invoke-Refuel
                Assert-GameState ($script:G.TraderDialogKey -eq "Refuel" -and $script:G.TraderDialog -in @((Get-Planet).Dialog.Refuel)) "refuel replaces the comms Greeting dialog"
                Assert-GameState ($script:G.Player.HP -eq 100 -and $script:G.Player.Fuel -eq 100) "trader repair and refuel restore ship systems"
                Assert-GameState ($script:G.Player.Credits -eq ($serviceCreditsBefore-$serviceTotal) -and $trader.Credits -eq ($traderCreditsBefore+$serviceTotal)) "service payments increase trader budget"
                $postServiceCredits=[int]$script:G.Player.Credits;$postServiceTraderCredits=[int]$trader.Credits
                $script:G.Player.HP=90;$script:G.Player.Credits=5;Invoke-Repair
                Assert-GameState ($script:G.Player.HP -eq 94 -and $script:G.Player.Credits -eq 0 -and $trader.Credits -eq ($postServiceTraderCredits+5)) "partial repair spends available credits"
                $trader.Credits=$postServiceTraderCredits;$script:G.Player.HP=100;$script:G.Player.Fuel=90;$script:G.Player.Credits=5;Invoke-Refuel
                Assert-GameState ([Math]::Abs($script:G.Player.Fuel-91.5) -lt 0.01 -and $script:G.Player.Credits -eq 0 -and $trader.Credits -eq ($postServiceTraderCredits+5)) "partial refuel spends available credits"
                $trader.Credits=$postServiceTraderCredits;$script:G.Player.Fuel=100;$script:G.Player.Credits=$postServiceCredits
                $stockOrder=@{Upgrade=0;Consumable=1;SuperCommon=2;Common=3;Uncommon=4;Rare=5;SuperRare=6;UltraRare=7;Artifact=8;Oddity=9};$lastOrder=-1
                foreach($stockRow in @(Get-TraderStockRows)){$currentOrder=if($stockOrder.ContainsKey($stockRow.Item.Rarity)){$stockOrder[$stockRow.Item.Rarity]}else{99};Assert-GameState ($currentOrder -ge $lastOrder) "trader buy stock rarity ordering";$lastOrder=$currentOrder}
                Add-InventoryItem "Premium Cargo Baffles" 1
                Assert-GameState ((Get-SortedCargo)[0].Item.Rarity -eq "Upgrade") "cargo lists upgrades before consumables and resources"
                $script:G.Inventory.Remove("Premium Cargo Baffles")
                Add-InventoryItem "Water" 10;$beforeCredits=$script:G.Player.Credits;$beforeFuelCells=[int]$script:G.Inventory["Fuel Cell (Small)"]
                Open-TradeQuantityPicker "Sell" "Water" "Add" 10;$script:G.QuantityPicker.SliderRect=[Drawing.RectangleF]::new(0,0,100,10);Set-QuantityPickerFromX 100
                Assert-GameState ($script:G.QuantityPicker.Value -eq 10) "quantity slider reaches full available stack"
                Invoke-KeyDown ([Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::D2))
                Assert-GameState ($script:G.QuantityPicker.Value -eq 2) "typed quantity replaces prior slider value"
                $script:G.QuantityPicker=$null
                Open-TradeQuantityPicker "Sell" "Water" "Add" 10;Invoke-KeyDown ([Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::D2));Invoke-KeyDown ([Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Enter));if(-not $trader.Stock.ContainsKey("Fuel Cell (Small)") -or [int]$trader.Stock["Fuel Cell (Small)"] -lt 1){$trader.Stock["Fuel Cell (Small)"]=1};[void](Add-TradeItem "Buy" "Fuel Cell (Small)" 1)
                Assert-GameState ((Get-TradeTotals).CanTrade) "staged mixed trade affordability"
                Commit-Trade
                Assert-GameState ($script:G.Inventory["Water"] -eq 8 -and $script:G.Inventory["Fuel Cell (Small)"] -eq ($beforeFuelCells+1) -and $script:G.Player.Credits -lt $beforeCredits) "atomic three-pane trade commit"
                Assert-GameState ($script:G.TraderDialogKey -eq "Trade" -and $script:G.TraderDialog -in @((Get-Planet).Dialog.Trade)) "completed trade uses Trade dialog"
                Commit-Trade
                Assert-GameState ($script:G.TraderDialogKey -eq "Frustrated" -and $script:G.TraderDialog -in @((Get-Planet).Dialog.Frustrated)) "invalid empty trade uses Frustrated dialog"
                $savedPlayerCredits=[int]$script:G.Player.Credits;$hadFuelStock=$trader.Stock.ContainsKey("Fuel Cell (Small)");$savedFuelStock=if($hadFuelStock){[int]$trader.Stock["Fuel Cell (Small)"]}else{0}
                $trader.Stock["Fuel Cell (Small)"]=1;$script:G.Player.Credits=0;[void](Add-TradeItem "Buy" "Fuel Cell (Small)" 1);Commit-Trade
                Assert-GameState ($script:G.TraderDialogKey -eq "InsufficientFunds" -and $script:G.TraderDialog -in @((Get-Planet).Dialog.InsufficientFunds)) "unaffordable purchase uses pilot InsufficientFunds dialog"
                Clear-TradeLedger;$script:G.Player.Credits=$savedPlayerCredits;if($hadFuelStock){$trader.Stock["Fuel Cell (Small)"]=$savedFuelStock}else{$trader.Stock.Remove("Fuel Cell (Small)")}
                $savedTraderCredits=[int]$trader.Credits;$trader.Credits=0;[void](Add-TradeItem "Sell" "Water" 1);Commit-Trade
                Assert-GameState ($script:G.TraderDialogKey -eq "InsufficientFundsTrader" -and $script:G.TraderDialog -in @((Get-Planet).Dialog.InsufficientFundsTrader)) "unaffordable cargo sale uses trader InsufficientFunds dialog"
                Clear-TradeLedger;$trader.Credits=$savedTraderCredits
                Add-InventoryItem "Iron" 4
                $savedJettisonMode=$script:G.Mode;$savedJettisonSelection=$script:G.SelectedCargo;$savedJettisonTop=if($script:G.ContainsKey("MfdTop")){$script:G.MfdTop}else{539.0};$savedJettisonExpand=$script:G.PanelExpand
                $script:G.Mode="Cargo";$script:G.SelectedCargo="Iron";$script:G.MfdTop=407.0;$script:G.PanelExpand=1.0
                $jettisonBitmap=[Drawing.Bitmap]::new(1280,720);$jettisonGraphics=[Drawing.Graphics]::FromImage($jettisonBitmap)
                try{
                    $script:HitTargets.Clear();Draw-Mfd $jettisonGraphics
                    $jettisonTarget=@($script:HitTargets|Where-Object{$_.Action -eq "Jettison"})[0]
                    Assert-GameState ($null -ne $jettisonTarget -and $jettisonTarget.Enabled) "cargo resource exposes enabled jettison button"
                    Invoke-LogicalClick ($jettisonTarget.Rectangle.X+($jettisonTarget.Rectangle.Width/2.0)) ($jettisonTarget.Rectangle.Y+($jettisonTarget.Rectangle.Height/2.0))
                    Assert-GameState ($null -ne $script:G.QuantityPicker -and $script:G.QuantityPicker.Purpose -eq "Jettison" -and $script:G.QuantityPicker.Maximum -eq 4) "cargo jettison button opens stack quantity picker"
                    $script:HitTargets.Clear();Draw-Mfd $jettisonGraphics
                    $confirmJettison=@($script:HitTargets|Where-Object{$_.Action -eq "PickerConfirm"})[0]
                    Assert-GameState ($script:G.QuantityPicker.SliderRect.Width -gt 0 -and $null -ne $confirmJettison) "cargo renders jettison slider and confirmation controls"
                    $script:G.QuantityPicker.Value=3
                    Invoke-LogicalClick ($confirmJettison.Rectangle.X+($confirmJettison.Rectangle.Width/2.0)) ($confirmJettison.Rectangle.Y+($confirmJettison.Rectangle.Height/2.0))
                    Assert-GameState ($script:G.Inventory["Iron"] -eq 1 -and $null -eq $script:G.QuantityPicker) "jettison confirmation deletes selected stack amount"
                    Add-InventoryItem "Iron" 3;Jettison-CargoItem "Iron";$script:G.QuantityPicker.Value=4;Invoke-Action "PickerCancel" $null
                    Assert-GameState ($script:G.Inventory["Iron"] -eq 4 -and $null -eq $script:G.QuantityPicker) "jettison cancellation preserves cargo"
                    Jettison-CargoQuantity "Iron" 3
                }finally{$jettisonGraphics.Dispose();$jettisonBitmap.Dispose();$script:G.Mode=$savedJettisonMode;$script:G.SelectedCargo=$savedJettisonSelection;$script:G.MfdTop=$savedJettisonTop;$script:G.PanelExpand=$savedJettisonExpand;$script:G.QuantityPicker=$null}
                Assert-GameState ((Get-RarityColor "Rare").ToArgb() -eq (Get-Color Cyan).ToArgb()) "rarity colors match the original game palette"
                $savedTraderBudget=$trader.Credits;$savedWater=[int]$script:G.Inventory["Water"];$savedIron=[int]$script:G.Inventory["Iron"];Clear-TradeLedger;$trader.Credits=30;$script:G.Inventory["Water"]=100;$script:G.Inventory.Remove("Iron");Stage-QuickSell
                Assert-GameState ($script:G.TradeSell.Count -eq 1 -and $script:G.TradeSell["Water"] -eq 10 -and (Get-TradeTotals).SellTotal -eq 30) "quick sell never exceeds current trader budget"
                Clear-TradeLedger;$trader.Credits=$savedTraderBudget;$script:G.Inventory["Water"]=$savedWater;$script:G.Inventory["Iron"]=$savedIron
                $script:G.ResourceMaster["Parity Oddity"]=@{Value=900;Weight=1.0;Rarity="Oddity";Description="Parity-only protected cargo."}
                Add-InventoryItem "Promethium" 1;Add-InventoryItem "Republic Flight Recorder" 1;Add-InventoryItem "Parity Oddity" 1;Stage-QuickSell
                Assert-GameState (-not $script:G.TradeSell.ContainsKey("Promethium") -and -not $script:G.TradeSell.ContainsKey("Republic Flight Recorder") -and -not $script:G.TradeSell.ContainsKey("Parity Oddity")) "quick sell protects UltraRare, Artifact, and Oddity cargo"
                Clear-TradeLedger;$script:G.Inventory.Remove("Republic Flight Recorder");$script:G.Inventory.Remove("Parity Oddity");$script:G.ResourceMaster.Remove("Parity Oddity")
                $script:G.Inventory.Remove("Promethium")

                Open-Trader;Open-Contracts "Log";Assert-GameState ($script:G.ContractContext -eq "Log") "cockpit contracts opens the flight log from trader mode";Close-Contracts
                Open-Contracts "Trader";Assert-GameState ($script:G.ContractContext -eq "Trader") "trader MFD contracts opens the local trader board";Invoke-QuestAction "mars_1";Add-InventoryItem "Iron" 35;Invoke-QuestAction "mars_1"
                Assert-GameState ($script:G.QuestState["mars_1"].Status -eq "Complete") "contract acceptance and turn-in"
                Invoke-QuestAction "mars_3";Add-InventoryItem "ScrapMetal" 25;Stage-QuickSell
                Assert-GameState ($script:G.TradeSell["ScrapMetal"] -eq 5 -and -not $script:G.TradeSell.ContainsKey("Fuel Cell (Small)")) "quick sell stages only quest-safe resources"
                Commit-Trade
                Assert-GameState ($script:G.Inventory["ScrapMetal"] -eq 20) "quick trade preserves active requirements"
                Add-InventoryItem "ScrapMetal" 10;Stage-QuickSell;Commit-Trade
                Assert-GameState ($script:G.Inventory["ScrapMetal"] -eq 20) "surplus trade preserves reserved quantity"
                Close-Contracts;Close-Trader;Open-Contracts
                Assert-GameState ("mars_3" -in @((Get-ContractDisplayRows)|ForEach-Object{$_.Quest.Id})) "flight log shows active contracts only"
                $script:G.ContractTab="Complete"
                Assert-GameState ("mars_1" -in @((Get-ContractDisplayRows)|ForEach-Object{$_.Quest.Id})) "completed-contract log view"
                $script:G.ContractTab="Active";Invoke-QuestAction "pluto_1"
                Assert-GameState (-not $script:G.QuestState.ContainsKey("pluto_1")) "flight log cannot accept remote contracts"
                Close-Contracts

                $script:G.Player.Fuel=1200.0;$script:G.Player.MaxFuel=1200.0
                $xrfHoldTarget=[pscustomobject]@{Action="XRF";Data=$null;Enabled=$true;HoldSeconds=$script:XRFHoldSeconds;Rectangle=[Drawing.RectangleF]::new(0,0,100,30)}
                $script:MouseX=20;$script:MouseY=15;[void](Start-HoldButton $xrfHoldTarget);Update-HoldButton ($script:XRFHoldSeconds-0.01)
                Assert-GameState ($script:G.Mode -ne "XRF" -and [Math]::Abs($script:G.Player.Fuel-1200.0) -lt 0.01) "partial XRF hold does not spend fuel"
                Update-HoldButton 0.02
                Assert-GameState ($script:G.Mode -eq "XRF" -and $script:G.XRFResults.Count -gt 5 -and [Math]::Abs($script:G.Player.Fuel-1125.0) -lt 0.01) "completed XRF hold invokes survey once"
                Start-Hyperjump "Typhon"
                Assert-GameState ($script:G.Player.SystemId -eq "Typhon" -and $script:G.Player.Location -eq "Flotsam") "interstellar hyperjump"

                Open-Trader;Open-Contracts;Invoke-QuestAction "rebel_1";Add-InventoryItem "ScrapMetal" 80;Add-InventoryItem "Iron" 80;Add-InventoryItem "Water" 60;Invoke-QuestAction "rebel_1";Close-Contracts;Close-Trader
                Assert-GameState ($script:G.QuestState["rebel_1"].Status -eq "Complete") "Typhon faction progression"

                $script:G.Player.HP=-1;Add-InventoryItem "Shield Cell (Small)" 1
                Assert-GameState (Invoke-AutoAdminister) "lethal-damage auto-injection"
                $script:G.Player.HP=10000;$script:G.Player.MaxHP=10000;$originalMaxWeight=$script:G.Player.MaxWeight;$script:G.Player.Fuel=0;Start-Fracking
                Assert-GameState (-not $script:G.FrackingActive) "empty fuel blocks fracking start"
                $script:G.Player.Fuel=20;$script:G.Player.MaxWeight=Get-CurrentWeight;Start-Fracking
                Assert-GameState (-not $script:G.FrackingActive) "full cargo blocks fracking start"
                $script:G.Player.MaxWeight=$originalMaxWeight
                Start-Fracking;$fuelBeforeTick=$script:G.Player.Fuel;Invoke-FrackTick
                Assert-GameState ([Math]::Abs($script:G.Player.Fuel-($fuelBeforeTick-0.5)) -lt 0.01) "0.5 FL extraction tick cost"
                $script:G.NextFrackTick=$script:Clock.Elapsed.TotalSeconds-10.0;$fuelBeforeDeadline=$script:G.Player.Fuel;Update-Game 0.016
                Assert-GameState ([Math]::Abs($script:G.Player.Fuel-($fuelBeforeDeadline-0.5)) -lt 0.01) "delayed scheduler resolves one tick without catch-up"
                Open-Settings;Close-Settings
                Assert-GameState ($script:G.Mode -eq "Frack") "settings returns to active fracking display"
                Start-CryoSleep;Assert-GameState ($script:G.CryoActive -and $script:G.CryoTicksRemaining -eq -1) "cryo uses natural completion without an estimated cap";Update-Game 0.016
                Assert-GameState ($script:G.Player.TimeSlept -gt 0) "accelerated cryo extraction"
                Assert-GameState ($script:G.CyanFlash -gt 0) "cryo-sleep cyan feedback flash"
                if($script:G.FrackingActive){Stop-Fracking}

                $script:G.Player.SaveName="ParityTest";$script:G.Player.PilotName="ParityTest";Save-Game
                $save=@(Get-SaveFiles|Where-Object{$_.BaseName -like "spacefrack_ParityTest_*"}|Select-Object -First 1)[0]
                Assert-GameState ($null -ne $save) "save file creation"
                Load-Game $save.FullName
                Assert-GameState ($script:G.Player.SystemId -eq "Typhon") "save file restoration"
                Remove-Item -LiteralPath $save.FullName -Force

                $script:G.Player.Location="Pyre";$script:G.Player.Fuel=0;Complete-DistressSignal
                Assert-GameState ($script:G.Player.Location -eq "Bastion" -and $script:G.Player.HP -gt 0) "distress recovery penalties and relocation"
                Write-GameLog "PARITY TEST COMPLETE"
            }catch{$script:FatalError=$_.Exception;Write-GameLog $_.Exception.Message -Critical}
            $script:Form.Close()
        }
        elseif($SoakTestSeconds -gt 0){
            Start-NewRun
            $soakTimer=New-Object Windows.Forms.Timer
            $soakTimer.Interval=1000
            $script:SoakRemaining=$SoakTestSeconds
            $script:SoakElapsed=0
            $soakTimer.Add_Tick({
                $script:SoakRemaining--
                $script:SoakElapsed++
                switch($script:SoakElapsed){
                    10{Open-SystemMap}
                    20{Start-Travel "Earth"}
                    35{if($script:G.Mode -eq "Orbit"){Start-Fracking}}
                    50{Open-Cargo}
                    65{Close-Cargo;Stop-Fracking;Open-Trader}
                    80{$script:G.TraderTab="Trade";Stage-QuickSell}
                    90{Close-Trader;Open-Contracts}
                    100{Close-Contracts;Open-Settings}
                    110{Open-Status}
                    115{$script:G.Mode="Settings";Close-Settings;Open-SystemMap}
                }
                if(($script:SoakRemaining % 10) -eq 0){
                    $process=[Diagnostics.Process]::GetCurrentProcess()
                    Write-GameLog ("Soak remaining={0}s workingSet={1:0.0}MB private={2:0.0}MB handles={3}" -f $script:SoakRemaining,($process.WorkingSet64/1MB),($process.PrivateMemorySize64/1MB),$process.HandleCount)
                }
                if($script:SoakRemaining -le 0){$this.Stop();$script:Form.Close()}
            })
            $soakTimer.Start()
        }
        elseif($SmokeTest){
            $script:Canvas.Refresh()
            Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "title")
            Start-NewRun
            $smokeTimer=New-Object Windows.Forms.Timer
            $smokeTimer.Interval=700
            $smokeTimer.Add_Tick({
                $script:SmokePhase++
                switch($script:SmokePhase){
                    1{
                        $savedSmokeScanner=[int]$script:G.Player.XRFScanner;$script:G.Player.XRFScanner=1
                        $script:G.HoldButton=@{Action="XRF";Data=$null;Duration=$script:XRFHoldSeconds;Elapsed=$script:XRFHoldSeconds*0.55;Rectangle=[Drawing.RectangleF]::new(687,575,145,42);Mode="Orbit"}
                        $script:MouseX=750;$script:MouseY=596;$script:Canvas.Refresh()
                        Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "orbit")
                        Cancel-HoldButton;$script:G.Player.XRFScanner=$savedSmokeScanner;Open-SystemMap
                    }
                    2{$script:G.SelectedPlanet="Earth";$script:G.ConfirmTravel=$true}
                    4{$script:Canvas.Refresh();Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "system")}
                    5{Start-Travel "Earth"}
                    8{if($script:G.Mode -eq "Orbit"){Start-Fracking}}
                    9{for($feedIndex=1;$feedIndex -le 18;$feedIndex++){Add-LogEntry ("SMOKE FEED LINE {0}" -f $feedIndex) (Get-Color Gray)};Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "frack")}
                    10{Open-Cargo}
                    12{Save-SmokeCapture $CapturePath}
                    13{Close-Cargo}
                    14{Stop-Fracking}
                    15{Open-Trader;$script:Canvas.Refresh();Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "comms")}
                    16{Set-TraderTab "Trade";Add-InventoryItem "Water" 5}
                    17{Open-TradeQuantityPicker "Sell" "Water" "Add" 5}
                    18{Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "quantity")}
                    19{$script:G.QuantityPicker.Value=3;Apply-QuantityPicker;[void](Add-TradeItem "Buy" "Shield Cell (Small)" 1);Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "trader")}
                    20{Open-Contracts}
                    21{$script:G.SelectedQuest="earth_1";Invoke-QuestAction "earth_1"}
                    22{Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "contracts")}
                    23{Invoke-QuestAction "earth_1";Close-Contracts;Set-TraderTab "Trade";Clear-TradeLedger;Add-InventoryItem "Gold" 2;Add-InventoryItem "Silver" 7;Stage-QuickSell}
                    24{Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "trade-quest")}
                    25{Close-Trader;Open-Contracts;$script:G.SelectedQuest="earth_1"}
                    26{Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "contract-log")}
                    27{Close-Contracts;Add-InventoryItem "XRF8 Scanner" 1;Use-CargoItem "XRF8 Scanner";$script:G.Player.Fuel=200;Start-XRFScan}
                    28{Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "xrf")}
                    29{Open-Orbit;Add-InventoryItem "HyperDrive Module" 1;Use-CargoItem "HyperDrive Module";$script:G.Player.MaxFuel=1200;$script:G.Player.Fuel=1200;Open-SystemMap}
                    30{Open-Galaxy;$script:G.SelectedSystem="Typhon"}
                    31{Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "galaxy")}
                    32{Start-Hyperjump "Typhon"}
                    34{Open-Settings}
                    35{Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "settings")}
                    36{Open-Status}
                    37{Save-SmokeCapture (Get-CaptureVariantPath $CapturePath "status");$this.Stop();$script:Form.Close()}
                }
            })
            $smokeTimer.Start()
        }
    })
    Write-GameLog ("Launching {0}. All interaction is contained in WinForms." -f $script:Version)
    [Windows.Forms.Application]::Run($script:Form)
    if(($SmokeTest -or $ParityTest) -and $null -ne $script:FatalError){throw $script:FatalError}
}

Start-SpaceFrack
