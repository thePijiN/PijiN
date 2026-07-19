# Get-MachineWorth

`Get-MachineWorth.ps1` is a read-only Windows PowerShell 5.1 script that inventories a computer and estimates what an equivalent machine would cost new in USD.

It reports an itemized estimate for detected processors, graphics adapters, mainboards, memory modules, physical storage, optical drives, batteries, and built-in laptop displays. On desktops it also estimates the parts Windows normally cannot identify: the power supply, CPU cooler, enclosure, and included fans.

Recognized CPU and GPU models use published launch MSRP. Commodity and hidden components use transparent replacement MSRP-equivalent heuristics. Every line shows its pricing basis and confidence, and the report includes a plausible low/high range.

## Run it

From Windows PowerShell 5.1:

```powershell
Set-Location C:\path\to\Get-MachineWorth
.\Get-MachineWorth.ps1
```

If local execution policy prevents direct script execution, this one-time invocation does not change the machine policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-MachineWorth.ps1
```

No elevation is required. The default run does not write files, alter settings, install anything, or contact the Internet.

## Console colors

Interactive text reports use color to make the output easier to scan. Category dividers are magenta, section and component headers are cyan, prices are green, notes and ranges are yellow, and confidence is green, yellow, or red according to its level.

Colors are never added to JSON, CSV, object output, or text written with `-OutputPath`. Use `-NoColor` for a plain text console report or when capturing text through a PowerShell pipeline:

```powershell
.\Get-MachineWorth.ps1 -NoColor
```

## Optional scope

External displays, external storage, identifiable peripherals, and a Windows retail license are not in the default computer-only total. They can be added explicitly:

```powershell
.\Get-MachineWorth.ps1 -IncludeDisplays -IncludeExternalStorage -IncludePeripherals -IncludeWindowsLicense
```

Export a report only when you want a file:

```powershell
.\Get-MachineWorth.ps1 -Format Json -OutputPath .\machine-worth.json
.\Get-MachineWorth.ps1 -Format Csv -OutputPath .\machine-worth.csv
.\Get-MachineWorth.ps1 -Format Text -OutputPath .\machine-worth.txt
```

For automation, request a PowerShell object:

```powershell
$report = .\Get-MachineWorth.ps1 -Format Object
$report.Summary
$report.Components | Sort-Object ExtendedEstimateUSD -Descending
```

## Correct a guess

Windows cannot read the label on a power supply, identify most CPU coolers, or reliably distinguish every premium model. Override a component label or detected model with a known unit price:

```powershell
.\Get-MachineWorth.ps1 -PriceOverride @{
    'Power supply' = 149.99
    'CPU cooling' = 119.99
    'Case and included fans' = 139.99
}
```

The matching line changes to 100 percent confidence and identifies the user override as its basis.

## What the number means

The total is a new MSRP-equivalent estimate before tax, shipping, assembly labor, and scarcity premiums. It is not an appraisal, insurance valuation, or used resale estimate. Launch MSRP can also differ significantly from present street price, especially for discontinued or collectible hardware.

The embedded price catalog is dated 2026-07-18. Exact CPU/GPU matches have the highest confidence. Capacity and chipset estimates are medium confidence. Hidden desktop parts and soldered laptop allocations are intentionally marked low confidence.
