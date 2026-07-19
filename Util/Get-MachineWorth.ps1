#requires -Version 5.1

<#
.SYNOPSIS
    Inventories a Windows computer and estimates its new MSRP-equivalent value.

.DESCRIPTION
    Get-MachineWorth is a read-only hardware inventory and pricing estimator.
    It uses published launch MSRP for recognized CPU and GPU models, then uses
    transparent replacement-cost heuristics for memory, storage, the mainboard,
    enclosure, cooling, power, and other parts.

    The default run does not write files, change settings, require elevation, or
    contact the Internet. Use -OutputPath only when you explicitly want a report
    file. This estimates new replacement value, not current used resale value.

.PARAMETER IncludeDisplays
    Includes attached external monitors in the total. A detected built-in laptop
    display is included automatically.

.PARAMETER IncludePeripherals
    Includes identifiable keyboards, mice, and cameras in the total. Generic and
    built-in input devices are omitted to avoid double counting.

.PARAMETER IncludeExternalStorage
    Includes attached USB and other external storage devices in the total. They
    are detected and listed, but excluded from the default computer-only total.

.PARAMETER IncludeWindowsLicense
    Includes an estimated retail Windows license in the total.

.PARAMETER Format
    Selects Text, Json, Csv, or Object output. The default is Text.

.PARAMETER OutputPath
    Writes the selected report format to this file. No file is written by default.

.PARAMETER PriceOverride
    Supplies unit-price overrides as a hashtable. Keys match a detected model or
    component label, without regard to case.

.PARAMETER NoColor
    Disables interactive console colors. Structured output and reports written to
    files never contain color formatting.

.EXAMPLE
    .\Get-MachineWorth.ps1

.EXAMPLE
    .\Get-MachineWorth.ps1 -IncludeDisplays -IncludePeripherals

.EXAMPLE
    .\Get-MachineWorth.ps1 -Format Json -OutputPath .\machine-worth.json

.EXAMPLE
    .\Get-MachineWorth.ps1 -PriceOverride @{ 'Power supply' = 149.99 }

.NOTES
    Pricing catalog date: 2026-07-18. Prices are estimates in USD before tax,
    shipping, assembly, and scarcity premiums.
#>

[CmdletBinding()]
param(
    [switch]$IncludeDisplays,
    [switch]$IncludePeripherals,
    [switch]$IncludeExternalStorage,
    [switch]$IncludeWindowsLicense,

    [ValidateSet('Text', 'Json', 'Csv', 'Object')]
    [string]$Format = 'Text',

    [string]$OutputPath,

    [hashtable]$PriceOverride = @{},

    [switch]$NoColor
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:CatalogDate = '2026-07-18'
$script:Usd = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')

function Get-PropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    if ($null -eq $InputObject) {
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }

    return $property.Value
}

function Get-SafeCimInstance {
    param(
        [Parameter(Mandatory = $true)][string]$ClassName,
        [string]$Namespace = 'root\cimv2',
        [string]$Filter
    )

    try {
        $arguments = @{
            ClassName   = $ClassName
            Namespace   = $Namespace
            ErrorAction = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($Filter)) {
            $arguments.Filter = $Filter
        }
        return @(Get-CimInstance @arguments)
    }
    catch {
        return @()
    }
}

function ConvertTo-NormalizedText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $value = $Text.ToUpperInvariant()
    $value = $value -replace '\(R\)|\(TM\)|\(C\)', ''
    $value = $value -replace '[^A-Z0-9]+', ' '
    return ($value -replace '\s+', ' ').Trim()
}

function ConvertTo-FriendlyBytes {
    param([double]$Bytes)

    if ($Bytes -ge 1PB) { return ('{0:N2} PB' -f ($Bytes / 1PB)) }
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} bytes' -f $Bytes)
}

function ConvertTo-NearestCapacityGB {
    param([double]$Bytes)

    if ($Bytes -le 0) {
        return 0
    }

    $rawGB = $Bytes / 1GB
    $commonSizes = @(32, 64, 120, 128, 240, 250, 256, 480, 500, 512, 960, 1000, 1024,
        1920, 2000, 2048, 3840, 4000, 4096, 6000, 6144, 8000, 8192, 10000, 10240,
        12000, 12288, 14000, 14336, 16000, 16384, 18000, 18432, 20000, 20480,
        22000, 22528, 24000, 24576, 30000, 32000)

    $best = $commonSizes[0]
    $bestDifference = [math]::Abs($rawGB - $best)
    foreach ($size in $commonSizes) {
        $difference = [math]::Abs($rawGB - $size)
        if ($difference -lt $bestDifference) {
            $best = $size
            $bestDifference = $difference
        }
    }

    if (($bestDifference / [math]::Max($rawGB, 1)) -le 0.12) {
        return [int]$best
    }

    return [int][math]::Round($rawGB)
}

function Get-CapacityPrice {
    param(
        [Parameter(Mandatory = $true)][double]$Capacity,
        [Parameter(Mandatory = $true)][hashtable]$PricePoints
    )

    $points = @($PricePoints.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{ Capacity = [double]$_.Key; Price = [double]$_.Value }
        } | Sort-Object Capacity)
    if ($points.Count -eq 0) {
        return 0.0
    }

    if ($Capacity -le $points[0].Capacity) {
        return [double]$points[0].Price
    }

    for ($index = 1; $index -lt $points.Count; $index++) {
        if ($Capacity -le $points[$index].Capacity) {
            $lowKey = $points[$index - 1].Capacity
            $highKey = $points[$index].Capacity
            $position = ($Capacity - $lowKey) / ($highKey - $lowKey)
            $lowPrice = [double]$points[$index - 1].Price
            $highPrice = [double]$points[$index].Price
            return $lowPrice + (($highPrice - $lowPrice) * $position)
        }
    }

    $lastPoint = $points[$points.Count - 1]
    return [double]$lastPoint.Price * ($Capacity / $lastPoint.Capacity)
}

function New-EstimateResult {
    param(
        [Parameter(Mandatory = $true)][double]$Price,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100)][int]$Confidence,
        [Parameter(Mandatory = $true)][string]$Basis,
        [string]$Notes = ''
    )

    return [pscustomobject]@{
        Price      = [math]::Round($Price, 2)
        Confidence = $Confidence
        Basis      = $Basis
        Notes      = $Notes
    }
}

function Get-UncertaintyFraction {
    param([ValidateRange(0, 100)][int]$Confidence)

    if ($Confidence -ge 95) { return 0.03 }
    if ($Confidence -ge 85) { return 0.10 }
    if ($Confidence -ge 70) { return 0.18 }
    if ($Confidence -ge 50) { return 0.28 }
    return 0.40
}

function New-ComponentItem {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Component,
        [Parameter(Mandatory = $true)][string]$DetectedModel,
        [int]$Quantity = 1,
        [Parameter(Mandatory = $true)][double]$UnitPrice,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100)][int]$Confidence,
        [Parameter(Mandatory = $true)][string]$Basis,
        [bool]$IncludedInTotal = $true,
        [string]$Notes = ''
    )

    $effectivePrice = $UnitPrice
    $overrideKey = $null
    foreach ($key in @($PriceOverride.Keys)) {
        $keyText = [string]$key
        $normalizedKey = ConvertTo-NormalizedText $keyText
        $normalizedModel = ConvertTo-NormalizedText $DetectedModel
        if ($keyText -ieq $DetectedModel -or $keyText -ieq $Component -or
            ($normalizedKey.Length -ge 8 -and $normalizedModel.Contains($normalizedKey))) {
            $overrideKey = $key
            break
        }
    }

    if ($null -ne $overrideKey) {
        $effectivePrice = [double]$PriceOverride[$overrideKey]
        $Confidence = 100
        $Basis = 'User price override'
        $Notes = ('{0} Price supplied by -PriceOverride.' -f $Notes).Trim()
    }

    $extended = [math]::Round($effectivePrice * $Quantity, 2)
    $uncertainty = Get-UncertaintyFraction -Confidence $Confidence
    $low = [math]::Round([math]::Max(0, $extended * (1 - $uncertainty)), 2)
    $high = [math]::Round($extended * (1 + $uncertainty), 2)

    if (-not $IncludedInTotal) {
        $low = 0.0
        $high = 0.0
    }

    return [pscustomobject][ordered]@{
        Category            = $Category
        Component           = $Component
        DetectedModel       = $DetectedModel
        Quantity            = $Quantity
        UnitEstimateUSD     = [math]::Round($effectivePrice, 2)
        ExtendedEstimateUSD = $extended
        LowEstimateUSD      = $low
        HighEstimateUSD     = $high
        ConfidencePercent   = $Confidence
        Basis               = $Basis
        IncludedInTotal     = $IncludedInTotal
        Notes               = $Notes
    }
}

function Find-CatalogEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object[]]$Catalog
    )

    $normalizedName = ConvertTo-NormalizedText $Name
    foreach ($entry in $Catalog) {
        if ($normalizedName -match $entry.Pattern) {
            return $entry
        }
    }
    return $null
}

function Get-CpuCatalog {
    $rows = @(
        @('AMD Ryzen 9 9950X3D', 699), @('AMD Ryzen 9 9900X3D', 599),
        @('AMD Ryzen 7 9850X3D', 499), @('AMD Ryzen 7 9800X3D', 479),
        @('AMD Ryzen 9 9950X', 649), @('AMD Ryzen 9 9900X', 499),
        @('AMD Ryzen 7 9700X', 359), @('AMD Ryzen 5 9600X', 279),
        @('AMD Ryzen 9 7950X3D', 699), @('AMD Ryzen 9 7900X3D', 599),
        @('AMD Ryzen 7 7800X3D', 449), @('AMD Ryzen 9 7950X', 699),
        @('AMD Ryzen 9 7900X', 549), @('AMD Ryzen 7 7700X', 399),
        @('AMD Ryzen 5 7600X', 299), @('AMD Ryzen 7 7700', 329),
        @('AMD Ryzen 5 7600', 229), @('AMD Ryzen 5 7500F', 179),
        @('AMD Ryzen 9 5950X', 799), @('AMD Ryzen 9 5900X', 549),
        @('AMD Ryzen 7 5800X3D', 449), @('AMD Ryzen 7 5800X', 449),
        @('AMD Ryzen 7 5700X', 299), @('AMD Ryzen 5 5600X', 299),
        @('AMD Ryzen 5 5600', 199), @('AMD Ryzen 5 5500', 159),
        @('AMD Ryzen 9 3950X', 749), @('AMD Ryzen 9 3900X', 499),
        @('AMD Ryzen 7 3800X', 399), @('AMD Ryzen 7 3700X', 329),
        @('AMD Ryzen 5 3600X', 249), @('AMD Ryzen 5 3600', 199),
        @('Intel Core Ultra 9 285K', 589), @('Intel Core Ultra 7 265KF', 379),
        @('Intel Core Ultra 7 265K', 394), @('Intel Core Ultra 5 245KF', 294),
        @('Intel Core Ultra 5 245K', 309), @('Intel Core i9-14900KS', 699),
        @('Intel Core i9-14900KF', 564), @('Intel Core i9-14900K', 589),
        @('Intel Core i9-14900F', 524), @('Intel Core i9-14900', 549),
        @('Intel Core i7-14700KF', 384), @('Intel Core i7-14700K', 409),
        @('Intel Core i7-14700F', 359), @('Intel Core i7-14700', 384),
        @('Intel Core i5-14600KF', 294), @('Intel Core i5-14600K', 319),
        @('Intel Core i5-14500', 232), @('Intel Core i5-14400F', 196),
        @('Intel Core i5-14400', 221), @('Intel Core i9-13900KS', 699),
        @('Intel Core i9-13900KF', 564), @('Intel Core i9-13900K', 589),
        @('Intel Core i7-13700KF', 384), @('Intel Core i7-13700K', 409),
        @('Intel Core i5-13600KF', 294), @('Intel Core i5-13600K', 319),
        @('Intel Core i5-13500', 232), @('Intel Core i5-13400F', 196),
        @('Intel Core i5-13400', 221), @('Intel Core i9-12900KS', 739),
        @('Intel Core i9-12900KF', 564), @('Intel Core i9-12900K', 589),
        @('Intel Core i7-12700KF', 384), @('Intel Core i7-12700K', 409),
        @('Intel Core i5-12600KF', 264), @('Intel Core i5-12600K', 289),
        @('Intel Core i5-12400F', 174), @('Intel Core i5-12400', 192),
        @('Intel Core i9-11900K', 539), @('Intel Core i7-11700K', 399),
        @('Intel Core i5-11600K', 262), @('Intel Core i9-10900K', 488),
        @('Intel Core i7-10700K', 374), @('Intel Core i5-10600K', 262),
        @('Intel Core i9-9900K', 488), @('Intel Core i7-9700K', 374),
        @('Intel Core i5-9600K', 262)
    )

    $catalog = @()
    foreach ($row in $rows) {
        $normalizedModel = ConvertTo-NormalizedText ([string]$row[0])
        $words = $normalizedModel -split '\s+' | ForEach-Object { [regex]::Escape($_) }
        $catalog += [pscustomobject]@{
            Pattern = ($words -join '\s*') + '(?![A-Z0-9])'
            Model   = [string]$row[0]
            Price   = [double]$row[1]
        }
    }
    return $catalog
}

function Get-GpuCatalog {
    $rows = @(
        @('NVIDIA GeForce RTX 5090', 1999), @('NVIDIA GeForce RTX 5080', 999),
        @('NVIDIA GeForce RTX 5070 Ti', 749), @('NVIDIA GeForce RTX 5070', 549),
        @('NVIDIA GeForce RTX 5060 Ti 16GB', 429), @('NVIDIA GeForce RTX 5060 Ti', 379),
        @('NVIDIA GeForce RTX 5060', 299), @('NVIDIA GeForce RTX 4090', 1599),
        @('NVIDIA GeForce RTX 4080 SUPER', 999), @('NVIDIA GeForce RTX 4080', 1199),
        @('NVIDIA GeForce RTX 4070 Ti SUPER', 799), @('NVIDIA GeForce RTX 4070 Ti', 799),
        @('NVIDIA GeForce RTX 4070 SUPER', 599), @('NVIDIA GeForce RTX 4070', 599),
        @('NVIDIA GeForce RTX 4060 Ti 16GB', 499), @('NVIDIA GeForce RTX 4060 Ti', 399),
        @('NVIDIA GeForce RTX 4060', 299), @('NVIDIA GeForce RTX 3090 Ti', 1999),
        @('NVIDIA GeForce RTX 3090', 1499), @('NVIDIA GeForce RTX 3080 Ti', 1199),
        @('NVIDIA GeForce RTX 3080', 699), @('NVIDIA GeForce RTX 3070 Ti', 599),
        @('NVIDIA GeForce RTX 3070', 499), @('NVIDIA GeForce RTX 3060 Ti', 399),
        @('NVIDIA GeForce RTX 3060', 329), @('NVIDIA GeForce RTX 3050', 249),
        @('NVIDIA GeForce RTX 2080 Ti', 999), @('NVIDIA GeForce RTX 2080 SUPER', 699),
        @('NVIDIA GeForce RTX 2080', 699), @('NVIDIA GeForce RTX 2070 SUPER', 499),
        @('NVIDIA GeForce RTX 2070', 499), @('NVIDIA GeForce RTX 2060 SUPER', 399),
        @('NVIDIA GeForce RTX 2060', 349), @('NVIDIA GeForce GTX 1660 Ti', 279),
        @('NVIDIA GeForce GTX 1660 SUPER', 229), @('NVIDIA GeForce GTX 1660', 219),
        @('NVIDIA GeForce GTX 1650 SUPER', 159), @('NVIDIA GeForce GTX 1650', 149),
        @('AMD Radeon RX 9070 XT', 599), @('AMD Radeon RX 9070', 549),
        @('AMD Radeon RX 9060 XT 16GB', 349), @('AMD Radeon RX 9060 XT', 299),
        @('AMD Radeon RX 7900 XTX', 999), @('AMD Radeon RX 7900 XT', 899),
        @('AMD Radeon RX 7900 GRE', 549), @('AMD Radeon RX 7800 XT', 499),
        @('AMD Radeon RX 7700 XT', 449), @('AMD Radeon RX 7600 XT', 329),
        @('AMD Radeon RX 7600', 269), @('AMD Radeon RX 6950 XT', 1099),
        @('AMD Radeon RX 6900 XT', 999), @('AMD Radeon RX 6800 XT', 649),
        @('AMD Radeon RX 6800', 579), @('AMD Radeon RX 6750 XT', 549),
        @('AMD Radeon RX 6700 XT', 479), @('AMD Radeon RX 6650 XT', 399),
        @('AMD Radeon RX 6600 XT', 379), @('AMD Radeon RX 6600', 329),
        @('AMD Radeon RX 6500 XT', 199), @('AMD Radeon RX 5700 XT', 399),
        @('AMD Radeon RX 5700', 349), @('Intel Arc B580', 249),
        @('Intel Arc B570', 219), @('Intel Arc A770', 349),
        @('Intel Arc A750', 289), @('Intel Arc A580', 179), @('Intel Arc A380', 139)
    )

    $catalog = @()
    foreach ($row in $rows) {
        $normalizedModel = ConvertTo-NormalizedText ([string]$row[0])
        $words = ($normalizedModel -split '\s+') | ForEach-Object { [regex]::Escape($_) }
        $pattern = ($words -join '\s*') + '(?![A-Z0-9])'
        $catalog += [pscustomobject]@{
            Pattern = $pattern
            Model   = [string]$row[0]
            Price   = [double]$row[1]
        }
    }
    return $catalog
}

$script:CpuCatalog = @(Get-CpuCatalog)
$script:GpuCatalog = @(Get-GpuCatalog)

function Test-IsPortableChassis {
    param([object[]]$Enclosures)

    $portableTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    foreach ($enclosure in $Enclosures) {
        foreach ($type in @(Get-PropertyValue -InputObject $enclosure -Name 'ChassisTypes' -Default @())) {
            if ($portableTypes -contains [int]$type) {
                return $true
            }
        }
    }
    return $false
}

function Get-ChassisName {
    param([object[]]$Enclosures)

    $names = @{
        3 = 'Desktop'; 4 = 'Low-profile desktop'; 5 = 'Pizza box'; 6 = 'Mini tower'
        7 = 'Tower'; 8 = 'Portable'; 9 = 'Laptop'; 10 = 'Notebook'; 11 = 'Hand-held'
        12 = 'Docking station'; 13 = 'All-in-one'; 14 = 'Subnotebook'; 15 = 'Space-saving'
        16 = 'Lunch box'; 17 = 'Main system chassis'; 18 = 'Expansion chassis'
        19 = 'Subchassis'; 20 = 'Bus expansion chassis'; 21 = 'Peripheral chassis'
        23 = 'Rack mount'; 24 = 'Sealed-case PC'; 30 = 'Tablet'; 31 = 'Convertible'; 32 = 'Detachable'
        35 = 'Mini PC'; 36 = 'Stick PC'
    }

    foreach ($enclosure in $Enclosures) {
        foreach ($type in @(Get-PropertyValue -InputObject $enclosure -Name 'ChassisTypes' -Default @())) {
            if ($names.ContainsKey([int]$type)) {
                return [string]$names[[int]$type]
            }
        }
    }
    return 'Unknown chassis'
}

function Test-IsMobileCpu {
    param([string]$Name)

    $normalized = ConvertTo-NormalizedText $Name
    return ($normalized -match '\b([0-9]{4,5})(U|H|HS|HX|HK|P|Y|G[1-7])\b' -or
        $normalized -match '\bMOBILE\b')
}

function Get-CpuEstimate {
    param(
        [Parameter(Mandatory = $true)]$Cpu,
        [Parameter(Mandatory = $true)][bool]$IsPortable
    )

    $name = [string](Get-PropertyValue -InputObject $Cpu -Name 'Name' -Default 'Unknown processor')
    $cores = [int](Get-PropertyValue -InputObject $Cpu -Name 'NumberOfCores' -Default 4)
    $normalized = ConvertTo-NormalizedText $name
    $mobile = $IsPortable -or (Test-IsMobileCpu -Name $name)

    if (-not $mobile) {
        $entry = Find-CatalogEntry -Name $name -Catalog $script:CpuCatalog
        if ($null -ne $entry) {
            return New-EstimateResult -Price $entry.Price -Confidence 92 `
                -Basis ('Published launch MSRP catalog: {0}' -f $entry.Model) `
                -Notes 'Exact model-family match.'
        }
    }

    $tier = 5
    if ($normalized -match 'RYZEN 9|CORE I9|CORE ULTRA 9|XEON|THREADRIPPER') { $tier = 9 }
    elseif ($normalized -match 'RYZEN 7|CORE I7|CORE ULTRA 7') { $tier = 7 }
    elseif ($normalized -match 'RYZEN 5|CORE I5|CORE ULTRA 5') { $tier = 5 }
    elseif ($normalized -match 'RYZEN 3|CORE I3|CORE ULTRA 3') { $tier = 3 }

    if ($mobile) {
        $prices = @{ 3 = 90; 5 = 150; 7 = 230; 9 = 340 }
        $price = [double]$prices[$tier]
        if ($normalized -match 'HX|HK') { $price *= 1.18 }
        if ($normalized -match 'X3D') { $price *= 1.15 }
        return New-EstimateResult -Price $price -Confidence 48 `
            -Basis 'Laptop platform CPU allocation by product tier' `
            -Notes 'Mobile processors generally have no standalone retail MSRP.'
    }

    $prices = @{ 3 = 130; 5 = 260; 7 = 390; 9 = 590 }
    $price = [double]$prices[$tier]
    if ($normalized -match 'X3D|KS') { $price *= 1.15 }
    elseif ($normalized -match 'K|X') { $price *= 1.05 }
    if ($cores -ge 24) { $price = [math]::Max($price, 1100) }
    elseif ($cores -ge 16) { $price = [math]::Max($price, 600) }

    return New-EstimateResult -Price $price -Confidence 42 `
        -Basis 'Desktop CPU tier and core-count heuristic' `
        -Notes 'The exact model was not in the embedded MSRP catalog.'
}

function Test-IsSoftwareDisplayAdapter {
    param([string]$Name)

    return ($Name -match 'Microsoft Basic|Remote Display|Indirect Display|DisplayLink|Citrix|VMware|VirtualBox|Hyper-V|Parsec')
}

function Test-IsIntegratedGpu {
    param([string]$Name)

    if ($Name -match 'Intel.*(UHD|HD Graphics|Iris)|AMD Radeon\(TM\) Graphics|AMD Radeon Graphics|Radeon Vega [0-9]+ Graphics') {
        return $true
    }
    return $false
}

function Get-MobileGpuEstimate {
    param([string]$Name)

    $normalized = ConvertTo-NormalizedText $Name
    $price = 180.0
    if ($normalized -match '5090') { $price = 700 }
    elseif ($normalized -match '5080|4090') { $price = 600 }
    elseif ($normalized -match '5070 TI|4080') { $price = 480 }
    elseif ($normalized -match '5070|4070|3080 TI') { $price = 360 }
    elseif ($normalized -match '5060|4060|3070') { $price = 270 }
    elseif ($normalized -match '5050|4050|3060') { $price = 205 }
    elseif ($normalized -match '3050|2050|1660|1650') { $price = 150 }
    elseif ($normalized -match 'RX 7[0-9]{3}|RX 6[0-9]{3}') { $price = 260 }
    elseif ($normalized -match 'ARC') { $price = 220 }

    return New-EstimateResult -Price $price -Confidence 45 `
        -Basis 'Laptop discrete-GPU platform allocation by tier' `
        -Notes 'Laptop GPUs are soldered modules without a standalone retail MSRP.'
}

function Get-DesktopGpuEstimate {
    param([string]$Name)

    $entry = Find-CatalogEntry -Name $Name -Catalog $script:GpuCatalog
    if ($null -ne $entry) {
        return New-EstimateResult -Price $entry.Price -Confidence 90 `
            -Basis ('Published reference-card launch MSRP catalog: {0}' -f $entry.Model) `
            -Notes 'Board-partner models may have launched above reference MSRP.'
    }

    $normalized = ConvertTo-NormalizedText $Name
    $price = 250.0
    if ($normalized -match 'RTX [45]090|RX [89][0-9]50') { $price = 1500 }
    elseif ($normalized -match 'RTX [45]080|RX [89][0-9]00') { $price = 900 }
    elseif ($normalized -match 'RTX [45]070|RX [78][0-9]00') { $price = 600 }
    elseif ($normalized -match 'RTX [45]060|RX [67][0-9]00') { $price = 350 }
    elseif ($normalized -match 'RTX [23]0[5-6]0|GTX 16') { $price = 260 }
    elseif ($normalized -match 'QUADRO|RTX A[0-9]|RTX [0-9]{4} ADA') { $price = 900 }

    return New-EstimateResult -Price $price -Confidence 40 `
        -Basis 'Desktop GPU family and performance-tier heuristic' `
        -Notes 'The exact model was not in the embedded MSRP catalog.'
}

function Get-MemoryTypeName {
    param($Memory)

    $smbiosType = [int](Get-PropertyValue -InputObject $Memory -Name 'SMBIOSMemoryType' -Default 0)
    $memoryType = [int](Get-PropertyValue -InputObject $Memory -Name 'MemoryType' -Default 0)
    $type = $smbiosType
    if ($type -eq 0) { $type = $memoryType }

    $types = @{
        20 = 'DDR'; 21 = 'DDR2'; 22 = 'DDR2 FB-DIMM'; 24 = 'DDR3'; 26 = 'DDR4'
        27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5'
    }
    if ($types.ContainsKey($type)) {
        return [string]$types[$type]
    }
    return 'Memory'
}

function Get-MemoryEstimate {
    param($Memory)

    $capacityGB = [math]::Max(1, [math]::Round(([double](Get-PropertyValue -InputObject $Memory -Name 'Capacity' -Default 0)) / 1GB))
    $type = Get-MemoryTypeName -Memory $Memory
    $speed = [int](Get-PropertyValue -InputObject $Memory -Name 'ConfiguredClockSpeed' -Default 0)
    if ($speed -eq 0) { $speed = [int](Get-PropertyValue -InputObject $Memory -Name 'Speed' -Default 0) }

    if ($type -match 'DDR5|LPDDR5') {
        $points = @{ 4 = 22; 8 = 32; 16 = 55; 24 = 78; 32 = 100; 48 = 145; 64 = 190; 96 = 285; 128 = 375 }
        $basis = 'DDR5 replacement MSRP-equivalent by module capacity'
    }
    elseif ($type -match 'DDR4|LPDDR4') {
        $points = @{ 4 = 18; 8 = 27; 16 = 47; 32 = 82; 64 = 155; 128 = 300 }
        $basis = 'DDR4 replacement MSRP-equivalent by module capacity'
    }
    elseif ($type -match 'DDR3') {
        $points = @{ 2 = 14; 4 = 22; 8 = 34; 16 = 62; 32 = 115 }
        $basis = 'DDR3 replacement MSRP-equivalent by module capacity'
    }
    else {
        $points = @{ 4 = 20; 8 = 35; 16 = 60; 32 = 105; 64 = 195; 128 = 380 }
        $basis = 'Memory replacement MSRP-equivalent by module capacity'
    }

    $price = Get-CapacityPrice -Capacity $capacityGB -PricePoints $points
    if (($type -match 'DDR5') -and $speed -ge 7200) { $price *= 1.18 }
    elseif (($type -match 'DDR5') -and $speed -ge 6400) { $price *= 1.10 }
    elseif (($type -match 'DDR4') -and $speed -ge 4000) { $price *= 1.12 }

    return New-EstimateResult -Price $price -Confidence 68 -Basis $basis `
        -Notes 'Memory pricing varies by timings, heat spreader, ECC support, and kit packaging.'
}

function Get-PhysicalDiskDetails {
    $physicalDisks = @(Get-SafeCimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName 'MSFT_PhysicalDisk')
    $details = @()
    foreach ($disk in $physicalDisks) {
        $details += [pscustomobject]@{
            FriendlyName = [string](Get-PropertyValue -InputObject $disk -Name 'FriendlyName' -Default '')
            Model        = [string](Get-PropertyValue -InputObject $disk -Name 'Model' -Default '')
            SerialNumber = ([string](Get-PropertyValue -InputObject $disk -Name 'SerialNumber' -Default '')).Trim()
            MediaType    = [int](Get-PropertyValue -InputObject $disk -Name 'MediaType' -Default 0)
            BusType      = [int](Get-PropertyValue -InputObject $disk -Name 'BusType' -Default 0)
            Size         = [double](Get-PropertyValue -InputObject $disk -Name 'Size' -Default 0)
            SpindleSpeed = [int64](Get-PropertyValue -InputObject $disk -Name 'SpindleSpeed' -Default 0)
        }
    }
    return $details
}

function Find-PhysicalDiskDetail {
    param(
        $Disk,
        [object[]]$PhysicalDiskDetails
    )

    $serial = ([string](Get-PropertyValue -InputObject $Disk -Name 'SerialNumber' -Default '')).Trim()
    $model = ConvertTo-NormalizedText ([string](Get-PropertyValue -InputObject $Disk -Name 'Model' -Default ''))
    $size = [double](Get-PropertyValue -InputObject $Disk -Name 'Size' -Default 0)

    foreach ($detail in $PhysicalDiskDetails) {
        if (-not [string]::IsNullOrWhiteSpace($serial) -and $detail.SerialNumber -eq $serial) {
            return $detail
        }
    }

    foreach ($detail in $PhysicalDiskDetails) {
        $detailName = ConvertTo-NormalizedText ($detail.FriendlyName + ' ' + $detail.Model)
        $sizeDifference = [math]::Abs([double]$detail.Size - $size)
        if ($detailName -and $model -and ($detailName.Contains($model) -or $model.Contains($detailName)) -and
            $sizeDifference -le [math]::Max($size * 0.05, 1GB)) {
            return $detail
        }
    }
    return $null
}

function Get-StorageKind {
    param(
        $Disk,
        $PhysicalDetail
    )

    $model = [string](Get-PropertyValue -InputObject $Disk -Name 'Model' -Default '')
    $interface = [string](Get-PropertyValue -InputObject $Disk -Name 'InterfaceType' -Default '')
    $media = [string](Get-PropertyValue -InputObject $Disk -Name 'MediaType' -Default '')
    $pnpDeviceId = [string](Get-PropertyValue -InputObject $Disk -Name 'PNPDeviceID' -Default '')
    $busType = 0
    $physicalMediaType = 0
    if ($null -ne $PhysicalDetail) {
        $busType = [int]$PhysicalDetail.BusType
        $physicalMediaType = [int]$PhysicalDetail.MediaType
    }

    $isExternal = ($busType -eq 7 -or $interface -match 'USB' -or $pnpDeviceId -match '^USBSTOR' -or
        $model -match 'EXTERNAL|PORTABLE')
    if ($isExternal -and ($physicalMediaType -eq 3 -or $media -match 'hard disk' -and $model -notmatch 'SSD|SOLID STATE')) {
        return 'External HDD'
    }
    if ($isExternal) { return 'External SSD' }
    if ($busType -eq 17 -or $model -match 'NVME|NVM EXPRESS') { return 'NVMe SSD' }
    if ($physicalMediaType -eq 4 -or $model -match 'SSD|SOLID STATE') {
        return 'SATA SSD'
    }
    if ($physicalMediaType -eq 3 -or $media -match 'hard disk' -or $model -match 'WDC|WD[0-9]|ST[0-9]|TOSHIBA|HITACHI|HGST') {
        return 'Hard disk drive'
    }
    return 'Storage drive'
}

function Get-StorageEstimate {
    param(
        [string]$Kind,
        [int]$CapacityGB,
        [string]$Model
    )

    $capacityTB = $CapacityGB / 1000.0
    switch -Regex ($Kind) {
        'NVMe' {
            $points = @{ 128 = 30; 256 = 40; 512 = 62; 1000 = 105; 2000 = 185; 4000 = 350; 8000 = 760 }
            $price = Get-CapacityPrice -Capacity $CapacityGB -PricePoints $points
            if ($Model -match 'PRO|BLACK|FIRECUDA|PLATINUM|GEN5|PCIe 5') { $price *= 1.25 }
            return New-EstimateResult -Price $price -Confidence 64 `
                -Basis 'NVMe SSD replacement MSRP-equivalent by capacity and tier' `
                -Notes 'Controller, NAND type, endurance, and PCIe generation affect price.'
        }
        'SATA SSD|External SSD' {
            $points = @{ 128 = 28; 256 = 38; 512 = 58; 1000 = 95; 2000 = 170; 4000 = 330; 8000 = 700 }
            $price = Get-CapacityPrice -Capacity $CapacityGB -PricePoints $points
            if ($Kind -eq 'External SSD') { $price *= 1.18 }
            return New-EstimateResult -Price $price -Confidence 62 `
                -Basis ('{0} replacement MSRP-equivalent by capacity' -f $Kind) `
                -Notes 'Flash type, endurance, enclosure, and interface speed affect price.'
        }
        'Hard disk|External HDD' {
            $points = @{ 0.5 = 45; 1 = 55; 2 = 75; 4 = 110; 6 = 145; 8 = 185; 10 = 220; 12 = 255; 14 = 290; 16 = 330; 18 = 370; 20 = 415; 22 = 460; 24 = 510; 30 = 650 }
            $price = Get-CapacityPrice -Capacity $capacityTB -PricePoints $points
            if ($Model -match 'IRONWOLF|RED|GOLD|EXOS|ULTRASTAR|ENTERPRISE|NAS') { $price *= 1.18 }
            if ($Kind -eq 'External HDD') { $price *= 0.95 }
            return New-EstimateResult -Price $price -Confidence 64 `
                -Basis ('{0} replacement MSRP-equivalent by capacity' -f $Kind) `
                -Notes 'Workload rating, warranty, RPM, and enclosure affect price.'
        }
        default {
            $points = @{ 128 = 30; 256 = 45; 512 = 65; 1000 = 100; 2000 = 180; 4000 = 330; 8000 = 650 }
            $price = Get-CapacityPrice -Capacity $CapacityGB -PricePoints $points
            return New-EstimateResult -Price $price -Confidence 35 `
                -Basis 'Unknown storage type; blended capacity heuristic' `
                -Notes 'Windows did not expose whether this device is solid-state or mechanical.'
        }
    }
}

function Get-MotherboardEstimate {
    param(
        $Board,
        [bool]$IsPortable,
        [string]$ComputerManufacturer
    )

    $manufacturer = [string](Get-PropertyValue -InputObject $Board -Name 'Manufacturer' -Default '')
    $product = [string](Get-PropertyValue -InputObject $Board -Name 'Product' -Default 'Unknown mainboard')
    $text = ConvertTo-NormalizedText ($manufacturer + ' ' + $product)

    if ($IsPortable) {
        return New-EstimateResult -Price 240 -Confidence 38 `
            -Basis 'Laptop mainboard and platform-electronics allocation' `
            -Notes 'Includes soldered controllers; replacement boards are model-specific.'
    }

    $price = 150.0
    $basis = 'Mainboard chipset and product-tier heuristic'
    if ($text -match 'WRX90') { $price = 850 }
    elseif ($text -match 'TRX50') { $price = 600 }
    elseif ($text -match 'X870E|Z890') { $price = 350 }
    elseif ($text -match 'X870|X670E|Z790') { $price = 300 }
    elseif ($text -match 'X670|Z690|X570') { $price = 250 }
    elseif ($text -match 'B850|B650E|B860|B760') { $price = 210 }
    elseif ($text -match 'B650|B660|B550') { $price = 175 }
    elseif ($text -match 'H870|H770|H670|Q870|Q770|Q670') { $price = 180 }
    elseif ($text -match 'A620|A520|H810|H610|H510') { $price = 110 }
    elseif ($text -match 'X399|X299') { $price = 400 }

    if ($text -match 'EXTREME|GODLIKE|AORUS MASTER|AORUS XTREME|MAXIMUS|TAICHI CARRARA') { $price *= 1.65 }
    elseif ($text -match 'HERO|ACE|CREATOR|DESIGNARE|AORUS PRO') { $price *= 1.30 }
    elseif ($text -match 'ITX|MINI ITX') { $price *= 1.20 }

    if (($ComputerManufacturer -match 'Dell|HP|Hewlett|Lenovo|Acer') -and
        ($manufacturer -match 'Dell|HP|Hewlett|Lenovo|Acer|Intel')) {
        $price = [math]::Min($price, 160)
        $basis = 'OEM replacement mainboard allocation'
    }

    return New-EstimateResult -Price $price -Confidence 52 -Basis $basis `
        -Notes 'Exact board revisions, connectivity, and bundled accessories can move MSRP substantially.'
}

function Get-DesktopPlatformEstimates {
    param(
        [string]$ChassisName,
        [object[]]$Cpus,
        [object[]]$Gpus,
        [string]$ComputerManufacturer
    )

    $maxCpuPrice = 0.0
    foreach ($cpu in $Cpus) {
        $cpuEstimate = Get-CpuEstimate -Cpu $cpu -IsPortable $false
        $maxCpuPrice = [math]::Max($maxCpuPrice, $cpuEstimate.Price)
    }

    $maxGpuPrice = 0.0
    foreach ($gpu in $Gpus) {
        $gpuName = [string](Get-PropertyValue -InputObject $gpu -Name 'Name' -Default '')
        if (-not (Test-IsIntegratedGpu $gpuName) -and -not (Test-IsSoftwareDisplayAdapter $gpuName)) {
            $gpuEstimate = Get-DesktopGpuEstimate -Name $gpuName
            $maxGpuPrice = [math]::Max($maxGpuPrice, $gpuEstimate.Price)
        }
    }

    $systemWatts = 450
    if ($maxGpuPrice -ge 1400) { $systemWatts = 1000 }
    elseif ($maxGpuPrice -ge 850) { $systemWatts = 850 }
    elseif ($maxGpuPrice -ge 550) { $systemWatts = 750 }
    elseif ($maxGpuPrice -ge 300) { $systemWatts = 650 }
    elseif ($maxGpuPrice -gt 0) { $systemWatts = 550 }
    if ($maxCpuPrice -ge 700) { $systemWatts += 100 }
    $systemWatts = [int]([math]::Ceiling($systemWatts / 50.0) * 50)

    $psuPrice = 70 + ([math]::Max(0, $systemWatts - 450) * 0.14)
    if ($systemWatts -ge 850) { $psuPrice += 25 }

    $coolerPrice = 35
    $coolerDescription = 'Entry tower air cooler or stock-cooler allocation'
    if ($maxCpuPrice -ge 550) {
        $coolerPrice = 150
        $coolerDescription = 'High-end air cooler or 280/360 mm liquid-cooler allocation'
    }
    elseif ($maxCpuPrice -ge 350) {
        $coolerPrice = 85
        $coolerDescription = 'Performance air cooler or 240 mm liquid-cooler allocation'
    }
    elseif ($maxCpuPrice -ge 230) {
        $coolerPrice = 55
        $coolerDescription = 'Mainstream tower air-cooler allocation'
    }

    $casePrice = 105
    if ($ChassisName -match 'Tower') { $casePrice = 125 }
    elseif ($ChassisName -match 'Mini|Space|Low-profile') { $casePrice = 100 }
    elseif ($ChassisName -match 'Rack') { $casePrice = 180 }
    if ($ComputerManufacturer -match 'Dell|HP|Hewlett|Lenovo|Acer') { $casePrice = 85 }

    return [pscustomobject]@{
        PowerSupply = New-EstimateResult -Price $psuPrice -Confidence 32 `
            -Basis ('Estimated {0} W quality power supply from CPU/GPU class' -f $systemWatts) `
            -Notes 'Windows normally cannot identify PSU model, wattage, efficiency, or age.'
        Cooler = New-EstimateResult -Price $coolerPrice -Confidence 30 `
            -Basis $coolerDescription `
            -Notes 'Windows normally cannot identify the installed CPU cooler.'
        Case = New-EstimateResult -Price $casePrice -Confidence 36 `
            -Basis ('Replacement enclosure heuristic for chassis type: {0}' -f $ChassisName) `
            -Notes 'Case brand, materials, included fans, and lighting are not exposed by Windows.'
        EstimatedWatts = $systemWatts
    }
}

function Get-PortablePlatformEstimates {
    param(
        [object[]]$Cpus,
        [object[]]$Gpus,
        [string]$ChassisName
    )

    $maxCpuPrice = 0.0
    foreach ($cpu in $Cpus) {
        $cpuEstimate = Get-CpuEstimate -Cpu $cpu -IsPortable $true
        $maxCpuPrice = [math]::Max($maxCpuPrice, $cpuEstimate.Price)
    }

    $maxGpuPrice = 0.0
    foreach ($gpu in $Gpus) {
        $gpuName = [string](Get-PropertyValue -InputObject $gpu -Name 'Name' -Default '')
        if (-not (Test-IsIntegratedGpu $gpuName) -and -not (Test-IsSoftwareDisplayAdapter $gpuName)) {
            $gpuEstimate = Get-MobileGpuEstimate -Name $gpuName
            $maxGpuPrice = [math]::Max($maxGpuPrice, $gpuEstimate.Price)
        }
    }

    $chassisPrice = 175
    if ($ChassisName -match 'Tablet|Convertible|Detachable') { $chassisPrice = 230 }
    elseif ($maxGpuPrice -ge 250) { $chassisPrice = 240 }

    $coolerPrice = 55
    if ($maxGpuPrice -ge 300 -or $maxCpuPrice -ge 300) { $coolerPrice = 105 }
    elseif ($maxGpuPrice -gt 0 -or $maxCpuPrice -ge 200) { $coolerPrice = 80 }

    $adapterPrice = 60
    $adapterWatts = 90
    if ($maxGpuPrice -ge 450) { $adapterPrice = 150; $adapterWatts = 330 }
    elseif ($maxGpuPrice -ge 300) { $adapterPrice = 125; $adapterWatts = 240 }
    elseif ($maxGpuPrice -gt 0) { $adapterPrice = 95; $adapterWatts = 180 }
    elseif ($maxCpuPrice -ge 250) { $adapterPrice = 75; $adapterWatts = 120 }

    return [pscustomobject]@{
        Chassis = New-EstimateResult -Price $chassisPrice -Confidence 35 `
            -Basis 'Portable chassis, hinges, keyboard, touchpad, speakers, camera, and cabling allocation' `
            -Notes 'These integrated assemblies do not have reliable standalone MSRP data.'
        Cooler = New-EstimateResult -Price $coolerPrice -Confidence 32 `
            -Basis 'Portable heat-pipe, heatsink, and fan allocation by CPU/GPU tier' `
            -Notes 'The installed thermal assembly model is not exposed by Windows.'
        PowerAdapter = New-EstimateResult -Price $adapterPrice -Confidence 40 `
            -Basis ('Estimated {0} W OEM AC power adapter by platform tier' -f $adapterWatts) `
            -Notes 'Adapter wattage and exact part number are not consistently exposed.'
        AdapterWatts = $adapterWatts
    }
}

function Convert-EdidText {
    param($Values)

    if ($null -eq $Values) { return '' }
    $characters = foreach ($value in @($Values)) {
        if ([int]$value -gt 0 -and [int]$value -lt 128) {
            [char][int]$value
        }
    }
    return (-join $characters).Trim()
}

function Get-MonitorInventory {
    $ids = @(Get-SafeCimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorID')
    $parameters = @(Get-SafeCimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorBasicDisplayParams')
    $connections = @(Get-SafeCimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorConnectionParams')
    $modes = @(Get-SafeCimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorListedSupportedSourceModes')
    $monitors = @()

    foreach ($id in $ids) {
        if (-not [bool](Get-PropertyValue -InputObject $id -Name 'Active' -Default $true)) { continue }
        $instance = [string](Get-PropertyValue -InputObject $id -Name 'InstanceName' -Default '')
        $friendly = Convert-EdidText (Get-PropertyValue -InputObject $id -Name 'UserFriendlyName' -Default @())
        $manufacturer = Convert-EdidText (Get-PropertyValue -InputObject $id -Name 'ManufacturerName' -Default @())
        $serial = Convert-EdidText (Get-PropertyValue -InputObject $id -Name 'SerialNumberID' -Default @())
        if ([string]::IsNullOrWhiteSpace($friendly)) { $friendly = 'Unidentified monitor' }

        $widthCm = 0
        $heightCm = 0
        $parameter = @($parameters | Where-Object { [string](Get-PropertyValue -InputObject $_ -Name 'InstanceName' -Default '') -eq $instance } | Select-Object -First 1)
        if ($parameter.Count -gt 0) {
            $widthCm = [int](Get-PropertyValue -InputObject $parameter[0] -Name 'MaxHorizontalImageSize' -Default 0)
            $heightCm = [int](Get-PropertyValue -InputObject $parameter[0] -Name 'MaxVerticalImageSize' -Default 0)
        }
        $diagonal = 0.0
        if ($widthCm -gt 0 -and $heightCm -gt 0) {
            $diagonal = [math]::Round(([math]::Sqrt(($widthCm * $widthCm) + ($heightCm * $heightCm))) / 2.54, 1)
        }

        $isInternal = $false
        $connection = @($connections | Where-Object { [string](Get-PropertyValue -InputObject $_ -Name 'InstanceName' -Default '') -eq $instance } | Select-Object -First 1)
        if ($connection.Count -gt 0) {
            $technology = [uint32](Get-PropertyValue -InputObject $connection[0] -Name 'VideoOutputTechnology' -Default 0)
            if ($technology -eq [uint32]2147483648) { $isInternal = $true }
        }

        $maxWidth = 0
        $maxHeight = 0
        $modeSet = @($modes | Where-Object { [string](Get-PropertyValue -InputObject $_ -Name 'InstanceName' -Default '') -eq $instance } | Select-Object -First 1)
        if ($modeSet.Count -gt 0) {
            foreach ($mode in @(Get-PropertyValue -InputObject $modeSet[0] -Name 'MonitorSourceModes' -Default @())) {
                $width = [int](Get-PropertyValue -InputObject $mode -Name 'HorizontalActivePixels' -Default 0)
                $height = [int](Get-PropertyValue -InputObject $mode -Name 'VerticalActivePixels' -Default 0)
                if (($width * $height) -gt ($maxWidth * $maxHeight)) {
                    $maxWidth = $width
                    $maxHeight = $height
                }
            }
        }

        $monitors += [pscustomobject]@{
            InstanceName = $instance
            FriendlyName = $friendly
            Manufacturer = $manufacturer
            SerialNumber = $serial
            DiagonalInch = $diagonal
            MaxWidth      = $maxWidth
            MaxHeight     = $maxHeight
            IsInternal    = $isInternal
        }
    }
    return $monitors
}

function Get-MonitorEstimate {
    param(
        $Monitor,
        [bool]$BuiltIn
    )

    $pixels = [int64]$Monitor.MaxWidth * [int64]$Monitor.MaxHeight
    $diagonal = [double]$Monitor.DiagonalInch
    if ($BuiltIn) {
        $price = 160
        if ($pixels -ge 8000000) { $price = 420 }
        elseif ($pixels -ge 3500000) { $price = 280 }
        elseif ($pixels -ge 2000000) { $price = 190 }
        if ($diagonal -ge 17) { $price *= 1.12 }
        return New-EstimateResult -Price $price -Confidence 42 `
            -Basis 'Built-in display-assembly allocation by size and resolution' `
            -Notes 'Panel technology, refresh rate, HDR, touch, and color gamut may not be exposed.'
    }

    $price = 150
    if ($pixels -ge 8000000) { $price = 480 }
    elseif ($pixels -ge 3500000) { $price = 300 }
    elseif ($pixels -ge 2000000) { $price = 180 }
    if ($diagonal -ge 40) { $price *= 1.55 }
    elseif ($diagonal -ge 32) { $price *= 1.28 }
    elseif ($diagonal -ge 27) { $price *= 1.12 }
    elseif ($diagonal -gt 0 -and $diagonal -le 22) { $price *= 0.82 }

    return New-EstimateResult -Price $price -Confidence 45 `
        -Basis 'External monitor replacement MSRP-equivalent by size and resolution' `
        -Notes 'Refresh rate, panel type, HDR, connectivity, and professional calibration affect price.'
}

function Get-PeripheralInventory {
    $entities = @(Get-SafeCimInstance -ClassName 'Win32_PnPEntity')
    $results = @()
    $seen = @{}
    foreach ($entity in $entities) {
        $class = [string](Get-PropertyValue -InputObject $entity -Name 'PNPClass' -Default '')
        if ($class -notmatch '^(Keyboard|Mouse|Camera|Image)$') { continue }
        $name = [string](Get-PropertyValue -InputObject $entity -Name 'Name' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -match 'HID-compliant|Standard PS/2|Integrated Camera|Virtual|Remote|System') { continue }
        $key = ConvertTo-NormalizedText ($class + ' ' + $name)
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $results += [pscustomobject]@{ Class = $class; Name = $name }
    }
    return $results
}

function Get-PeripheralEstimate {
    param($Peripheral)

    $name = [string]$Peripheral.Name
    $class = [string]$Peripheral.Class
    switch -Regex ($class) {
        'Keyboard' {
            $price = 45
            if ($name -match 'Gaming|Mechanical|MX|G[0-9]{3}|BlackWidow|K[0-9]{2,3}') { $price = 110 }
            return New-EstimateResult -Price $price -Confidence 40 -Basis 'Keyboard product-tier heuristic'
        }
        'Mouse' {
            $price = 35
            if ($name -match 'Gaming|MX|G[0-9]{3}|DeathAdder|Basilisk|Naga') { $price = 80 }
            return New-EstimateResult -Price $price -Confidence 40 -Basis 'Mouse product-tier heuristic'
        }
        default {
            $price = 65
            if ($name -match '4K|Brio|Stream') { $price = 150 }
            return New-EstimateResult -Price $price -Confidence 38 -Basis 'Camera product-tier heuristic'
        }
    }
}

function Get-WindowsLicenseEstimate {
    param($OperatingSystem)

    $caption = [string](Get-PropertyValue -InputObject $OperatingSystem -Name 'Caption' -Default 'Windows')
    if ($caption -match 'Enterprise|Education|Server') {
        return New-EstimateResult -Price 0 -Confidence 20 `
            -Basis 'Volume-license edition; no transferable retail license estimated' `
            -Notes 'Enterprise, Education, and Server licensing varies by agreement.'
    }
    if ($caption -match ' Pro') {
        return New-EstimateResult -Price 199.99 -Confidence 80 `
            -Basis 'Estimated Windows Pro retail license MSRP' `
            -Notes 'An OEM license may be non-transferable and cost less than retail.'
    }
    return New-EstimateResult -Price 139.99 -Confidence 80 `
        -Basis 'Estimated Windows Home retail license MSRP' `
        -Notes 'An OEM license may be non-transferable and cost less than retail.'
}

function Get-ConfidenceLabel {
    param([int]$Confidence)
    if ($Confidence -ge 85) { return 'High' }
    if ($Confidence -ge 60) { return 'Medium' }
    return 'Low'
}

function Format-Usd {
    param([double]$Value)
    return $Value.ToString('C2', $script:Usd)
}

function Format-TextReport {
    param($Report)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('MACHINE WORTH REPORT')
    $lines.Add(('=' * 80))
    $lines.Add(('Computer:       {0}' -f $Report.Configuration.Computer))
    $lines.Add(('Manufacturer:   {0}' -f $Report.Configuration.Manufacturer))
    $lines.Add(('Chassis:        {0}' -f $Report.Configuration.Chassis))
    $lines.Add(('Operating sys:  {0}' -f $Report.Configuration.OperatingSystem))
    $lines.Add(('Firmware:       {0}' -f $Report.Configuration.Firmware))
    $lines.Add(('Report time:    {0}' -f $Report.GeneratedAt))
    $lines.Add(('Price catalog:  {0}' -f $Report.PricingCatalogDate))
    $lines.Add('')
    $lines.Add('This is estimated new MSRP-equivalent value in USD, not used resale value.')
    $lines.Add('Tax, shipping, assembly labor, and scarcity premiums are not included.')
    $lines.Add('')

    $index = 0
    $lastCategory = ''
    foreach ($item in $Report.Components) {
        if ($item.Category -ne $lastCategory) {
            $lastCategory = $item.Category
            $lines.Add(('[ {0} ]' -f $lastCategory.ToUpperInvariant()))
        }
        $index++
        $included = 'included'
        if (-not $item.IncludedInTotal) { $included = 'not in total' }
        $lines.Add(('{0,2}. {1}: {2}' -f $index, $item.Component, $item.DetectedModel))
        $lines.Add(('    Estimate: {0} x {1} = {2} ({3}, {4}% confidence, {5})' -f
                (Format-Usd $item.UnitEstimateUSD), $item.Quantity,
                (Format-Usd $item.ExtendedEstimateUSD),
                (Get-ConfidenceLabel $item.ConfidencePercent),
                $item.ConfidencePercent, $included))
        $lines.Add(('    Basis: {0}' -f $item.Basis))
        if (-not [string]::IsNullOrWhiteSpace($item.Notes)) {
            $lines.Add(('    Note:  {0}' -f $item.Notes))
        }
        $lines.Add('')
    }

    $lines.Add(('=' * 80))
    $lines.Add(('ESTIMATED TOTAL:  {0}' -f (Format-Usd $Report.Summary.EstimatedTotalUSD)))
    $lines.Add(('PLAUSIBLE RANGE:   {0} to {1}' -f
            (Format-Usd $Report.Summary.LowEstimateUSD),
            (Format-Usd $Report.Summary.HighEstimateUSD)))
    $lines.Add(('ITEMS IN TOTAL:    {0}' -f $Report.Summary.IncludedLineItems))
    $lines.Add(('OVERALL CONFIDENCE: {0}% ({1})' -f
            $Report.Summary.WeightedConfidencePercent,
            (Get-ConfidenceLabel $Report.Summary.WeightedConfidencePercent)))
    $lines.Add('')
    $lines.Add('Accuracy notes:')
    $lines.Add('  - High confidence usually means an exact CPU/GPU MSRP catalog match.')
    $lines.Add('  - Medium confidence means capacity- or chipset-based replacement pricing.')
    $lines.Add('  - Low confidence means Windows could not expose the exact installed part.')
    $lines.Add('  - Use -PriceOverride to replace any guessed component or model price.')
    $lines.Add('  - Use the Include switches to count attached storage, displays, peripherals, or Windows.')

    return ($lines -join [Environment]::NewLine)
}

function Get-ConfidenceColor {
    param([int]$Confidence)

    if ($Confidence -ge 85) { return 'Green' }
    if ($Confidence -ge 60) { return 'Yellow' }
    return 'Red'
}

function Write-ColorLabelValue {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [AllowEmptyString()][string]$Value,
        [int]$Width = 16,
        [ConsoleColor]$LabelColor = [ConsoleColor]::DarkCyan,
        [ConsoleColor]$ValueColor = [ConsoleColor]::Gray
    )

    Write-Host ($Label.PadRight($Width)) -NoNewline -ForegroundColor $LabelColor
    Write-Host $Value -ForegroundColor $ValueColor
}

function Write-ColorTextReport {
    param($Report)

    Write-Host 'MACHINE WORTH REPORT' -ForegroundColor Cyan
    Write-Host ('=' * 80) -ForegroundColor DarkCyan
    Write-ColorLabelValue -Label 'Computer:' -Value $Report.Configuration.Computer -ValueColor White
    Write-ColorLabelValue -Label 'Manufacturer:' -Value $Report.Configuration.Manufacturer
    Write-ColorLabelValue -Label 'Chassis:' -Value $Report.Configuration.Chassis
    Write-ColorLabelValue -Label 'Operating sys:' -Value $Report.Configuration.OperatingSystem
    Write-ColorLabelValue -Label 'Firmware:' -Value $Report.Configuration.Firmware
    Write-ColorLabelValue -Label 'Report time:' -Value $Report.GeneratedAt -ValueColor DarkGray
    Write-ColorLabelValue -Label 'Price catalog:' -Value $Report.PricingCatalogDate -ValueColor DarkGray
    Write-Host ''
    Write-Host 'This is estimated new MSRP-equivalent value in USD, not used resale value.' -ForegroundColor Yellow
    Write-Host 'Tax, shipping, assembly labor, and scarcity premiums are not included.' -ForegroundColor DarkYellow
    Write-Host ''

    $index = 0
    $lastCategory = ''
    foreach ($item in $Report.Components) {
        if ($item.Category -ne $lastCategory) {
            $lastCategory = $item.Category
            Write-Host ('[ {0} ]' -f $lastCategory.ToUpperInvariant()) -ForegroundColor Magenta
        }
        $index++
        $included = 'included'
        $includedColor = [ConsoleColor]::Green
        if (-not $item.IncludedInTotal) {
            $included = 'not in total'
            $includedColor = [ConsoleColor]::DarkYellow
        }
        $confidenceColor = [ConsoleColor](Get-ConfidenceColor $item.ConfidencePercent)

        Write-Host ('{0,2}. ' -f $index) -NoNewline -ForegroundColor DarkCyan
        Write-Host ($item.Component + ': ') -NoNewline -ForegroundColor Cyan
        Write-Host $item.DetectedModel -ForegroundColor White

        Write-Host '    Estimate: ' -NoNewline -ForegroundColor DarkCyan
        Write-Host (Format-Usd $item.UnitEstimateUSD) -NoNewline -ForegroundColor Green
        Write-Host (' x {0} = ' -f $item.Quantity) -NoNewline -ForegroundColor Gray
        Write-Host (Format-Usd $item.ExtendedEstimateUSD) -NoNewline -ForegroundColor Green
        Write-Host ' (' -NoNewline -ForegroundColor Gray
        Write-Host (Get-ConfidenceLabel $item.ConfidencePercent) -NoNewline -ForegroundColor $confidenceColor
        Write-Host (', {0}% confidence, ' -f $item.ConfidencePercent) -NoNewline -ForegroundColor Gray
        Write-Host $included -NoNewline -ForegroundColor $includedColor
        Write-Host ')' -ForegroundColor Gray

        Write-Host '    Basis: ' -NoNewline -ForegroundColor DarkCyan
        Write-Host $item.Basis -ForegroundColor Gray
        if (-not [string]::IsNullOrWhiteSpace($item.Notes)) {
            Write-Host '    Note:  ' -NoNewline -ForegroundColor DarkYellow
            Write-Host $item.Notes -ForegroundColor Yellow
        }
        Write-Host ''
    }

    Write-Host ('=' * 80) -ForegroundColor DarkCyan
    Write-Host 'ESTIMATED TOTAL:   ' -NoNewline -ForegroundColor Cyan
    Write-Host (Format-Usd $Report.Summary.EstimatedTotalUSD) -ForegroundColor Green
    Write-Host 'PLAUSIBLE RANGE:   ' -NoNewline -ForegroundColor Cyan
    Write-Host ('{0} to {1}' -f
        (Format-Usd $Report.Summary.LowEstimateUSD),
        (Format-Usd $Report.Summary.HighEstimateUSD)) -ForegroundColor Yellow
    Write-Host 'ITEMS IN TOTAL:    ' -NoNewline -ForegroundColor Cyan
    Write-Host $Report.Summary.IncludedLineItems -ForegroundColor White
    Write-Host 'OVERALL CONFIDENCE: ' -NoNewline -ForegroundColor Cyan
    $overallConfidenceColor = [ConsoleColor](Get-ConfidenceColor $Report.Summary.WeightedConfidencePercent)
    Write-Host ('{0}% ({1})' -f
        $Report.Summary.WeightedConfidencePercent,
        (Get-ConfidenceLabel $Report.Summary.WeightedConfidencePercent)) -ForegroundColor $overallConfidenceColor
    Write-Host ''

    Write-Host 'Accuracy notes:' -ForegroundColor Cyan
    Write-Host '  - High confidence usually means an exact CPU/GPU MSRP catalog match.' -ForegroundColor Gray
    Write-Host '  - Medium confidence means capacity- or chipset-based replacement pricing.' -ForegroundColor Gray
    Write-Host '  - Low confidence means Windows could not expose the exact installed part.' -ForegroundColor Gray
    Write-Host '  - Use -PriceOverride to replace any guessed component or model price.' -ForegroundColor Gray
    Write-Host '  - Use the Include switches to count attached storage, displays, peripherals, or Windows.' -ForegroundColor Gray
}

function Get-MachineWorthReport {
    $computerSystems = @(Get-SafeCimInstance -ClassName 'Win32_ComputerSystem')
    $computer = $null
    if ($computerSystems.Count -gt 0) { $computer = $computerSystems[0] }
    $operatingSystems = @(Get-SafeCimInstance -ClassName 'Win32_OperatingSystem')
    $operatingSystem = $null
    if ($operatingSystems.Count -gt 0) { $operatingSystem = $operatingSystems[0] }
    $biosItems = @(Get-SafeCimInstance -ClassName 'Win32_BIOS')
    $bios = $null
    if ($biosItems.Count -gt 0) { $bios = $biosItems[0] }
    $enclosures = @(Get-SafeCimInstance -ClassName 'Win32_SystemEnclosure')
    $cpus = @(Get-SafeCimInstance -ClassName 'Win32_Processor')
    $gpus = @(Get-SafeCimInstance -ClassName 'Win32_VideoController')
    $boards = @(Get-SafeCimInstance -ClassName 'Win32_BaseBoard')
    $memoryModules = @(Get-SafeCimInstance -ClassName 'Win32_PhysicalMemory')
    $diskDrives = @(Get-SafeCimInstance -ClassName 'Win32_DiskDrive')
    $opticalDrives = @(Get-SafeCimInstance -ClassName 'Win32_CDROMDrive')
    $batteries = @(Get-SafeCimInstance -ClassName 'Win32_Battery')
    $networkAdapters = @(Get-SafeCimInstance -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter = True')
    $soundDevices = @(Get-SafeCimInstance -ClassName 'Win32_SoundDevice')
    $tpmItems = @(Get-SafeCimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName 'Win32_Tpm')
    $physicalDiskDetails = @(Get-PhysicalDiskDetails)

    if ($cpus.Count -eq 0 -and $boards.Count -eq 0 -and $memoryModules.Count -eq 0 -and $diskDrives.Count -eq 0) {
        throw 'Windows Management Instrumentation returned no core hardware. Confirm the Windows Management Instrumentation service is running and that your account can read root\cimv2.'
    }

    $isPortable = Test-IsPortableChassis -Enclosures $enclosures
    $chassisName = Get-ChassisName -Enclosures $enclosures
    $computerManufacturer = [string](Get-PropertyValue -InputObject $computer -Name 'Manufacturer' -Default 'Unknown')
    $computerModel = [string](Get-PropertyValue -InputObject $computer -Name 'Model' -Default 'Unknown')
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($cpu in $cpus) {
        $name = [string](Get-PropertyValue -InputObject $cpu -Name 'Name' -Default 'Unknown processor')
        $cores = [int](Get-PropertyValue -InputObject $cpu -Name 'NumberOfCores' -Default 0)
        $threads = [int](Get-PropertyValue -InputObject $cpu -Name 'NumberOfLogicalProcessors' -Default 0)
        $description = ('{0} ({1} cores, {2} threads)' -f $name.Trim(), $cores, $threads)
        $estimate = Get-CpuEstimate -Cpu $cpu -IsPortable $isPortable
        $items.Add((New-ComponentItem -Category 'Core' -Component 'Processor' -DetectedModel $description `
                -UnitPrice $estimate.Price -Confidence $estimate.Confidence -Basis $estimate.Basis -Notes $estimate.Notes))
    }

    $seenGpus = @{}
    foreach ($gpu in $gpus) {
        $name = [string](Get-PropertyValue -InputObject $gpu -Name 'Name' -Default 'Unknown display adapter')
        if (Test-IsSoftwareDisplayAdapter $name) { continue }
        $normalized = ConvertTo-NormalizedText $name
        if ($seenGpus.ContainsKey($normalized)) { continue }
        $seenGpus[$normalized] = $true
        $adapterRam = [double](Get-PropertyValue -InputObject $gpu -Name 'AdapterRAM' -Default 0)
        $displayName = $name
        if ($adapterRam -gt 0) { $displayName += (' ({0} reported VRAM)' -f (ConvertTo-FriendlyBytes $adapterRam)) }

        if (Test-IsIntegratedGpu $name) {
            $items.Add((New-ComponentItem -Category 'Core' -Component 'Integrated graphics' -DetectedModel $displayName `
                    -UnitPrice 0 -Confidence 90 -Basis 'Included in processor or mainboard price' -IncludedInTotal $false `
                    -Notes 'Listed for configuration completeness; not double counted.'))
        }
        else {
            $isMobileGpu = $isPortable -or $name -match 'Laptop GPU|Mobile'
            if ($isMobileGpu) { $estimate = Get-MobileGpuEstimate -Name $name }
            else { $estimate = Get-DesktopGpuEstimate -Name $name }
            $items.Add((New-ComponentItem -Category 'Core' -Component 'Graphics adapter' -DetectedModel $displayName `
                    -UnitPrice $estimate.Price -Confidence $estimate.Confidence -Basis $estimate.Basis -Notes $estimate.Notes))
        }
    }

    foreach ($board in $boards) {
        $manufacturer = [string](Get-PropertyValue -InputObject $board -Name 'Manufacturer' -Default 'Unknown')
        $product = [string](Get-PropertyValue -InputObject $board -Name 'Product' -Default 'Unknown mainboard')
        $version = [string](Get-PropertyValue -InputObject $board -Name 'Version' -Default '')
        $description = ($manufacturer + ' ' + $product + ' ' + $version).Trim()
        $estimate = Get-MotherboardEstimate -Board $board -IsPortable $isPortable -ComputerManufacturer $computerManufacturer
        $items.Add((New-ComponentItem -Category 'Core' -Component 'Mainboard' -DetectedModel $description `
                -UnitPrice $estimate.Price -Confidence $estimate.Confidence -Basis $estimate.Basis -Notes $estimate.Notes))
    }

    $memoryIndex = 0
    foreach ($memory in $memoryModules) {
        $memoryIndex++
        $manufacturer = [string](Get-PropertyValue -InputObject $memory -Name 'Manufacturer' -Default 'Unknown')
        $partNumber = ([string](Get-PropertyValue -InputObject $memory -Name 'PartNumber' -Default '')).Trim()
        $capacity = [double](Get-PropertyValue -InputObject $memory -Name 'Capacity' -Default 0)
        $speed = [int](Get-PropertyValue -InputObject $memory -Name 'ConfiguredClockSpeed' -Default 0)
        if ($speed -eq 0) { $speed = [int](Get-PropertyValue -InputObject $memory -Name 'Speed' -Default 0) }
        $memoryType = Get-MemoryTypeName -Memory $memory
        $description = ('{0} {1}, {2} {3}' -f $manufacturer, $partNumber, (ConvertTo-FriendlyBytes $capacity), $memoryType).Trim()
        if ($speed -gt 0) { $description += (', {0} MT/s configured' -f $speed) }
        $estimate = Get-MemoryEstimate -Memory $memory
        $items.Add((New-ComponentItem -Category 'Memory' -Component ('Memory module {0}' -f $memoryIndex) `
                -DetectedModel $description -UnitPrice $estimate.Price -Confidence $estimate.Confidence `
                -Basis $estimate.Basis -Notes $estimate.Notes))
    }

    $diskIndex = 0
    foreach ($disk in $diskDrives) {
        $model = [string](Get-PropertyValue -InputObject $disk -Name 'Model' -Default 'Unknown drive')
        if ($model -match 'Virtual|VHD|Storage Space|Msft Virtual') { continue }
        $diskIndex++
        $size = [double](Get-PropertyValue -InputObject $disk -Name 'Size' -Default 0)
        $capacityGB = ConvertTo-NearestCapacityGB -Bytes $size
        $detail = Find-PhysicalDiskDetail -Disk $disk -PhysicalDiskDetails $physicalDiskDetails
        $kind = Get-StorageKind -Disk $disk -PhysicalDetail $detail
        $description = ('{0}, {1}, {2}' -f $model.Trim(), (ConvertTo-FriendlyBytes $size), $kind)
        $estimate = Get-StorageEstimate -Kind $kind -CapacityGB $capacityGB -Model $model
        $includeStorage = $true
        if ($kind -match '^External') { $includeStorage = [bool]$IncludeExternalStorage }
        $storageNotes = $estimate.Notes
        if (-not $includeStorage) {
            $storageNotes = ($storageNotes + ' External storage is listed but excluded; use -IncludeExternalStorage to count it.').Trim()
        }
        $items.Add((New-ComponentItem -Category 'Storage' -Component ('Storage drive {0}' -f $diskIndex) `
                -DetectedModel $description -UnitPrice $estimate.Price -Confidence $estimate.Confidence `
                -Basis $estimate.Basis -IncludedInTotal $includeStorage -Notes $storageNotes))
    }

    $opticalIndex = 0
    foreach ($drive in $opticalDrives) {
        $opticalIndex++
        $name = [string](Get-PropertyValue -InputObject $drive -Name 'Name' -Default 'Optical drive')
        $price = 28
        if ($name -match 'BD|Blu') { $price = 85 }
        $items.Add((New-ComponentItem -Category 'Storage' -Component ('Optical drive {0}' -f $opticalIndex) `
                -DetectedModel $name -UnitPrice $price -Confidence 58 `
                -Basis 'Optical-drive replacement MSRP-equivalent by media support'))
    }

    if ($isPortable) {
        $batteryIndex = 0
        foreach ($battery in $batteries) {
            $batteryIndex++
            $name = [string](Get-PropertyValue -InputObject $battery -Name 'Name' -Default 'Internal battery')
            $items.Add((New-ComponentItem -Category 'Platform' -Component ('Battery pack {0}' -f $batteryIndex) `
                    -DetectedModel $name -UnitPrice 95 -Confidence 35 `
                    -Basis 'Portable-computer battery replacement allocation' `
                    -Notes 'Battery capacity and exact manufacturer part number may not be exposed.'))
        }
        $portablePlatform = Get-PortablePlatformEstimates -Cpus $cpus -Gpus $gpus -ChassisName $chassisName
        $items.Add((New-ComponentItem -Category 'Platform' -Component 'Laptop chassis and input assembly' `
                -DetectedModel ($computerManufacturer + ' ' + $computerModel).Trim() `
                -UnitPrice $portablePlatform.Chassis.Price -Confidence $portablePlatform.Chassis.Confidence `
                -Basis $portablePlatform.Chassis.Basis -Notes $portablePlatform.Chassis.Notes))
        $items.Add((New-ComponentItem -Category 'Platform' -Component 'Laptop cooling system' `
                -DetectedModel 'Exact thermal assembly not exposed by Windows' `
                -UnitPrice $portablePlatform.Cooler.Price -Confidence $portablePlatform.Cooler.Confidence `
                -Basis $portablePlatform.Cooler.Basis -Notes $portablePlatform.Cooler.Notes))
        $items.Add((New-ComponentItem -Category 'Platform' -Component 'AC power adapter' `
                -DetectedModel ('Exact adapter not exposed; estimated {0} W class' -f $portablePlatform.AdapterWatts) `
                -UnitPrice $portablePlatform.PowerAdapter.Price -Confidence $portablePlatform.PowerAdapter.Confidence `
                -Basis $portablePlatform.PowerAdapter.Basis -Notes $portablePlatform.PowerAdapter.Notes))
    }
    else {
        $platform = Get-DesktopPlatformEstimates -ChassisName $chassisName -Cpus $cpus -Gpus $gpus `
            -ComputerManufacturer $computerManufacturer
        $items.Add((New-ComponentItem -Category 'Platform' -Component 'Power supply' `
                -DetectedModel ('Model not exposed; estimated requirement {0} W' -f $platform.EstimatedWatts) `
                -UnitPrice $platform.PowerSupply.Price -Confidence $platform.PowerSupply.Confidence `
                -Basis $platform.PowerSupply.Basis -Notes $platform.PowerSupply.Notes))
        $items.Add((New-ComponentItem -Category 'Platform' -Component 'CPU cooling' `
                -DetectedModel 'Exact cooler not exposed by Windows' `
                -UnitPrice $platform.Cooler.Price -Confidence $platform.Cooler.Confidence `
                -Basis $platform.Cooler.Basis -Notes $platform.Cooler.Notes))
        $items.Add((New-ComponentItem -Category 'Platform' -Component 'Case and included fans' `
                -DetectedModel $chassisName -UnitPrice $platform.Case.Price -Confidence $platform.Case.Confidence `
                -Basis $platform.Case.Basis -Notes $platform.Case.Notes))
    }

    $monitors = @(Get-MonitorInventory)
    $builtInAdded = $false
    foreach ($monitor in $monitors) {
        $builtIn = [bool]$monitor.IsInternal
        if ($isPortable -and -not $builtInAdded -and -not ($monitors | Where-Object { $_.IsInternal })) {
            $builtIn = $true
        }
        if ($builtIn) { $builtInAdded = $true }
        $description = $monitor.FriendlyName
        if ($monitor.DiagonalInch -gt 0) { $description += (', {0:N1} inch' -f $monitor.DiagonalInch) }
        if ($monitor.MaxWidth -gt 0) { $description += (', {0}x{1} max mode' -f $monitor.MaxWidth, $monitor.MaxHeight) }
        $estimate = Get-MonitorEstimate -Monitor $monitor -BuiltIn $builtIn
        $component = 'External display'
        if ($builtIn) { $component = 'Built-in display assembly' }
        $includeMonitor = ($builtIn -or [bool]$IncludeDisplays)
        $monitorNotes = $estimate.Notes
        if (-not $includeMonitor) {
            $monitorNotes = ($monitorNotes + ' External display is listed but excluded; use -IncludeDisplays to count it.').Trim()
        }
        $items.Add((New-ComponentItem -Category 'Display' -Component $component -DetectedModel $description `
                -UnitPrice $estimate.Price -Confidence $estimate.Confidence -Basis $estimate.Basis `
                -IncludedInTotal $includeMonitor -Notes $monitorNotes))
    }

    if ($IncludePeripherals) {
        foreach ($peripheral in @(Get-PeripheralInventory)) {
            $estimate = Get-PeripheralEstimate -Peripheral $peripheral
            $items.Add((New-ComponentItem -Category 'Peripheral' -Component $peripheral.Class `
                    -DetectedModel $peripheral.Name -UnitPrice $estimate.Price -Confidence $estimate.Confidence `
                    -Basis $estimate.Basis -Notes $estimate.Notes))
        }
    }

    $onboardNetworkNames = @()
    $externalNetworkNames = @()
    foreach ($adapter in $networkAdapters) {
        $adapterName = [string](Get-PropertyValue -InputObject $adapter -Name 'Name' -Default '')
        if ([string]::IsNullOrWhiteSpace($adapterName) -or $adapterName -match 'Virtual|VPN|Loopback|TAP|Host-Only|Debug') {
            continue
        }
        $adapterPnpId = [string](Get-PropertyValue -InputObject $adapter -Name 'PNPDeviceID' -Default '')
        if ($adapterPnpId -match '^USB') { $externalNetworkNames += $adapterName }
        else { $onboardNetworkNames += $adapterName }
    }
    $onboardNetworkNames = @($onboardNetworkNames | Sort-Object -Unique)
    $externalNetworkNames = @($externalNetworkNames | Sort-Object -Unique)
    if ($onboardNetworkNames.Count -gt 0) {
        $items.Add((New-ComponentItem -Category 'Connectivity' -Component 'Network and wireless controllers' `
                -DetectedModel ($onboardNetworkNames -join '; ') -UnitPrice 0 -Confidence 80 `
                -Basis 'Included in mainboard or laptop platform estimate' -IncludedInTotal $false `
                -Notes 'Listed for configuration completeness; not double counted.'))
    }
    foreach ($externalNetworkName in $externalNetworkNames) {
        $includeNetworkAdapter = [bool]$IncludePeripherals
        $networkNotes = 'External adapter estimate.'
        if (-not $includeNetworkAdapter) {
            $networkNotes += ' Listed but excluded; use -IncludePeripherals to count it.'
        }
        $items.Add((New-ComponentItem -Category 'Peripheral' -Component 'External network adapter' `
                -DetectedModel $externalNetworkName -UnitPrice 30 -Confidence 45 `
                -Basis 'USB network-adapter replacement MSRP-equivalent' `
                -IncludedInTotal $includeNetworkAdapter -Notes $networkNotes))
    }

    $soundNames = @($soundDevices | ForEach-Object {
            [string](Get-PropertyValue -InputObject $_ -Name 'Name' -Default '')
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($soundNames.Count -gt 0) {
        $items.Add((New-ComponentItem -Category 'Audio' -Component 'Audio controllers and codecs' `
                -DetectedModel ($soundNames -join '; ') -UnitPrice 0 -Confidence 80 `
                -Basis 'Included in mainboard, graphics adapter, or laptop platform estimate' `
                -IncludedInTotal $false -Notes 'Listed for configuration completeness; not double counted.'))
    }

    if ($IncludeWindowsLicense -and $null -ne $operatingSystem) {
        $estimate = Get-WindowsLicenseEstimate -OperatingSystem $operatingSystem
        $caption = [string](Get-PropertyValue -InputObject $operatingSystem -Name 'Caption' -Default 'Windows')
        $items.Add((New-ComponentItem -Category 'Software' -Component 'Windows license' -DetectedModel $caption `
                -UnitPrice $estimate.Price -Confidence $estimate.Confidence -Basis $estimate.Basis `
                -IncludedInTotal ($estimate.Price -gt 0) -Notes $estimate.Notes))
    }

    $includedItems = @($items | Where-Object { $_.IncludedInTotal })
    $total = [math]::Round(($includedItems | Measure-Object -Property ExtendedEstimateUSD -Sum).Sum, 2)
    $lowTotal = [math]::Round(($includedItems | Measure-Object -Property LowEstimateUSD -Sum).Sum, 2)
    $highTotal = [math]::Round(($includedItems | Measure-Object -Property HighEstimateUSD -Sum).Sum, 2)
    $weightedConfidence = 0
    if ($total -gt 0) {
        $weightedPoints = 0.0
        foreach ($item in $includedItems) {
            $weightedPoints += $item.ExtendedEstimateUSD * $item.ConfidencePercent
        }
        $weightedConfidence = [int][math]::Round($weightedPoints / $total)
    }

    $osCaption = [string](Get-PropertyValue -InputObject $operatingSystem -Name 'Caption' -Default 'Unknown Windows edition')
    $osVersion = [string](Get-PropertyValue -InputObject $operatingSystem -Name 'Version' -Default '')
    $biosManufacturer = [string](Get-PropertyValue -InputObject $bios -Name 'Manufacturer' -Default 'Unknown')
    $biosVersion = [string](Get-PropertyValue -InputObject $bios -Name 'SMBIOSBIOSVersion' -Default '')
    $installedMemory = [double](Get-PropertyValue -InputObject $computer -Name 'TotalPhysicalMemory' -Default 0)
    $tpmDescription = 'Not detected or not exposed'
    if ($tpmItems.Count -gt 0) {
        $tpmManufacturer = [string](Get-PropertyValue -InputObject $tpmItems[0] -Name 'ManufacturerIdTxt' -Default 'Unknown manufacturer')
        $tpmVersion = [string](Get-PropertyValue -InputObject $tpmItems[0] -Name 'SpecVersion' -Default 'Unknown version')
        $tpmDescription = ($tpmManufacturer + ' TPM ' + $tpmVersion).Trim()
    }

    return [pscustomobject][ordered]@{
        ReportType         = 'New MSRP-equivalent machine value estimate'
        Currency           = 'USD'
        GeneratedAt        = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
        PricingCatalogDate = $script:CatalogDate
        Configuration      = [pscustomobject][ordered]@{
            Computer           = ($env:COMPUTERNAME + ' - ' + $computerModel).Trim(' ', '-')
            Manufacturer       = $computerManufacturer
            Chassis            = $chassisName
            IsPortable         = $isPortable
            OperatingSystem    = ($osCaption + ' ' + $osVersion).Trim()
            Firmware           = ($biosManufacturer + ' ' + $biosVersion).Trim()
            InstalledMemory    = ConvertTo-FriendlyBytes $installedMemory
            ProcessorCount     = $cpus.Count
            DisplayAdapterCount = @($gpus | Where-Object { -not (Test-IsSoftwareDisplayAdapter ([string]$_.Name)) }).Count
            PhysicalDriveCount = $diskIndex
            NetworkAdapters    = @($onboardNetworkNames + $externalNetworkNames)
            AudioDevices       = $soundNames
            TrustedPlatformModule = $tpmDescription
        }
        Options            = [pscustomobject][ordered]@{
            ExternalDisplaysIncluded = [bool]$IncludeDisplays
            PeripheralsIncluded      = [bool]$IncludePeripherals
            ExternalStorageIncluded  = [bool]$IncludeExternalStorage
            WindowsLicenseIncluded   = [bool]$IncludeWindowsLicense
        }
        Components         = $items.ToArray()
        Summary            = [pscustomobject][ordered]@{
            EstimatedTotalUSD          = $total
            LowEstimateUSD             = $lowTotal
            HighEstimateUSD            = $highTotal
            WeightedConfidencePercent  = $weightedConfidence
            IncludedLineItems          = $includedItems.Count
            ReportedLineItems           = $items.Count
        }
        Disclaimer         = 'Estimates new MSRP-equivalent value, not used resale value. Excludes tax, shipping, assembly, and scarcity premiums.'
    }
}

try {
    if ($Format -eq 'Object' -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
        throw 'OutputPath cannot be used with Format Object. Use Text, Json, or Csv for file output.'
    }

    $report = Get-MachineWorthReport
    switch ($Format) {
        'Object' {
            Write-Output $report
        }
        'Json' {
            $content = $report | ConvertTo-Json -Depth 7
            if ([string]::IsNullOrWhiteSpace($OutputPath)) { Write-Output $content }
            else { Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8 }
        }
        'Csv' {
            if ([string]::IsNullOrWhiteSpace($OutputPath)) {
                $report.Components | ConvertTo-Csv -NoTypeInformation
            }
            else {
                $report.Components | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
            }
        }
        default {
            $content = Format-TextReport -Report $report
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
            }
            elseif ($NoColor) {
                Write-Output $content
            }
            else {
                Write-ColorTextReport -Report $report
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        Write-Output ('Report written to: {0}' -f (Convert-Path -LiteralPath $OutputPath))
    }
}
catch {
    $failureDetail = $_.Exception.Message
    if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
        $failureDetail += [Environment]::NewLine + $_.ScriptStackTrace
    }
    Write-Error ('Get-MachineWorth failed: {0}' -f $failureDetail)
    exit 1
}
