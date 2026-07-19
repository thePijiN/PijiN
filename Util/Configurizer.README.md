# Configurizer

Configurizer is a single-file Windows workstation desired-state script. Its
specification, taskbar XML, Microsoft 365 configuration, application catalog,
bloatware patterns, and operation logic are all contained in
`Configurizer.ps1`.

The script is intended to make a machine conform to one visible specification,
while keeping audit, testing, and individual operation selection practical.

## Requirements

- Windows PowerShell 5.1
- Windows 10 or Windows 11
- An elevated session for real apply operations
- winget for standard application, Dell, and HP tool installation
- Internet access when installing applications, Microsoft 365, or updates

No-parameter audits and WhatIf runs can run without elevation, but an elevated
session provides more complete all-user Appx, BitLocker, policy, and system
inventory.

## Basic use

```powershell
# Audit every operation. This changes no Configurizer-managed settings.
.\Configurizer.ps1

# Show every operation and whether -All includes it.
.\Configurizer.ps1 -ListOperations

# Audit only selected operation families.
.\Configurizer.ps1 -Audit -ConfigurePower -ConfigureTaskbar

# Simulate the complete standard apply path.
.\Configurizer.ps1 -All -WhatIf

# Apply selected operations and suppress the high-impact confirmation prompt.
.\Configurizer.ps1 -ConfigurePower -ConfigureTaskbar -Confirm:$false

# Switch the current user's system and application colors without restarting Explorer.
.\Configurizer.ps1 -DarkMode
.\Configurizer.ps1 -LightMode

# Save an audit report.
.\Configurizer.ps1 -ReportPath $env:LOCALAPPDATA\PijiN\Configurizer\Before.json
```

Supplying one or more action switches selects Apply mode unless `-Audit` is
also supplied. Apply mode requires elevation unless `-WhatIf` is active.

## What WhatIf guarantees

`-WhatIf` prevents Configurizer from carrying out its persistent mutation
steps. In particular, `-All -WhatIf` does not:

- Change registry or policy values
- Change power, time, theme, taskbar, UAC, or QoS configuration
- Create taskbar layouts or Office shortcuts
- Enable, suspend, resume, or change BitLocker protection
- Download or install the Office Deployment Tool
- Invoke winget installation
- Remove Win32 or Appx applications
- Download or install Windows updates
- Run Dell, HP, or Lenovo update installation
- Delete BitLocker recovery documents
- Write a JSON report, even when `-ReportPath` is supplied

A WhatIf run still performs discovery so it can produce a useful plan. It reads
the registry and system configuration, loads PowerShell modules into the current
process, inventories applications, and performs a Windows Update search. Windows
can consequently record ordinary process, event, network, or scan metadata.
WhatIf is therefore a no-persistent-Configurizer-change guarantee, not a
forensic guarantee that no byte anywhere on Windows will be touched.

The script explicitly guards native executables and APIs that do not implement
PowerShell WhatIf themselves. The full `-All -WhatIf` path is part of the script
verification procedure.

## Operations

| Parameter | Purpose | Included in `-All` |
| --- | --- | --- |
| `-ConfigurePower` | Enforce embedded AC and battery timeouts | Yes |
| `-ConfigureContentDelivery` | Disable selected Windows suggestion settings | Yes |
| `-ConfigureTeamsQoS` | Enforce Teams QoS policies | Yes |
| `-ConfigureUAC` | Enforce the embedded UAC behavior | Yes |
| `-ConfigureTime` | Set time zone, start Windows Time, and resync | Yes |
| `-ConfigureTaskbar` | Configure taskbar, search, and Task View settings | Yes |
| `-DarkMode` | Set current-user system and application colors to dark | No |
| `-LightMode` | Set current-user system and application colors to light | No |
| `-ConfigureTaskbarPins` | Deploy the embedded taskbar pin layout | Yes |
| `-ConfigureOfficeShortcuts` | Create shortcuts for installed Office applications | Yes |
| `-ConfigureBitLocker` | Enforce system-drive BitLocker protection | Yes |
| `-RemoveWindowsBloatware` | Remove matching Windows Appx and Win32 software | Yes |
| `-RemoveManufacturerBloatware` | Remove matching Dell, HP, or Lenovo software | Yes |
| `-InstallApps` | Install missing standard applications with winget | Yes |
| `-InstallMicrosoft365` | Install Microsoft 365 Apps without Visio or Project | Yes |
| `-InstallWindowsUpdates` | Install applicable software updates without forced reboot | Yes |
| `-InstallManufacturerUpdates` | Run the supported manufacturer update workflow | Yes |
| `-CleanupBitLockerDocuments` | Delete matching recovery-key documents | No |

Theme selection and BitLocker document cleanup are deliberately excluded from
`-All` and must always be selected explicitly. `-DarkMode` and `-LightMode` are
mutually exclusive.

## Live theme switching

Windows theme personalization is stored per user. `-DarkMode` and `-LightMode`
set both `AppsUseLightTheme` and `SystemUsesLightTheme` under the current user's
`Themes\Personalize` registry key. Light mode also resets `ColorPrevalence` to
the Windows default value of zero.

After the registry values are written, Configurizer broadcasts these native
Windows messages to all top-level windows:

- `WM_SETTINGCHANGE` with `ImmersiveColorSet`
- `WM_THEMECHANGED`
- `WM_DWMCOLORIZATIONCOLORCHANGED`

This mirrors the approach used by Microsoft PowerToys Light Switch and normally
updates Explorer, the taskbar, Settings, and theme-aware applications without
restarting `explorer.exe`. An application that does not listen for Windows theme
notifications can still require its own restart.

The setting affects the current user profile, even when the system shell and
applications are both changed. It does not rewrite every local user's profile.

## Confirmation and exit codes

Configurizer declares a high confirmation impact. A real apply normally asks
for confirmation before each planned mutation. Use `-Confirm:$false` only after
reviewing the audit and WhatIf results.

Exit codes are:

- `0`: completed successfully, or the requested audit is fully compliant
- `1`: at least one operation failed
- `2`: audit completed successfully and found noncompliant state

Exit code `2` is an expected audit result and does not mean the script crashed.

## Reports

`-ReportPath` accepts either a JSON filename or a directory. A directory receives
a timestamped JSON filename. The report contains the operation, item, status,
message, restart indication, execution mode, machine, user, and timestamp.

The report is a compliance record. It is not a rollback package and it cannot
reinstall removed software, uninstall updates, or reverse firmware changes.

## Notable embedded defaults

Review the `Embedded Specification` region before any real apply. The current
defaults include:

- AC and battery display, standby, and disk timeouts set to zero, meaning never
- Time zone set to `Eastern Standard Time`
- UAC left enabled, but administrator consent prompting and secure-desktop
  prompting set to zero
- Widgets and Task View hidden, with taskbar search mode set to one
- No default light or dark choice; theme changes require `-DarkMode` or
  `-LightMode` and are excluded from `-All`
- System-drive BitLocker using `XtsAes128`, used-space-only encryption, TPM and
  recovery-password protectors, and Entra ID backup attempts when joined
- Windows and manufacturer application removal lists defined directly in the
  script
- Microsoft 365 Apps for enterprise with no Visio or Project product entry

The UAC defaults reduce interactive elevation prompting and are security
significant. They should be tested separately rather than casually included in
the first real server-PC apply.


## Cautious Windows 11 test procedure

A real `-All` run is intentionally broad. Do not use it as the first live test
on a machine that matters.

### 1. Establish recovery first

- Create and verify a current system image or other bare-metal recovery method.
- Confirm that Windows recovery media is available and bootable.
- Confirm that any existing BitLocker recovery key is accessible somewhere other
  than the computer being tested.
- Treat a restore point as useful convenience, not as a substitute for an image.
- Record the current BIOS version before manufacturer update testing.

Application removal, Windows updates, Microsoft 365 installation, BitLocker
changes, and BIOS or firmware updates are not reliably undone by a JSON report.

### 2. Capture a baseline

Run an elevated Windows PowerShell 5.1 session from the script directory:

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$testRoot = Join-Path (Join-Path $env:LOCALAPPDATA 'PijiN\Configurizer') $stamp
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

Start-Transcript -Path (Join-Path $testRoot 'Session.txt')
.\Configurizer.ps1 -ReportPath (Join-Path $testRoot 'Before.json')

powercfg.exe /query | Set-Content (Join-Path $testRoot 'Power.txt')
manage-bde.exe -status | Set-Content (Join-Path $testRoot 'BitLocker.txt')
Get-TimeZone | Format-List * | Out-File (Join-Path $testRoot 'TimeZone.txt')
Get-Service w32time | Format-List * | Out-File (Join-Path $testRoot 'WindowsTime.txt')
Get-NetQosPolicy -ErrorAction SilentlyContinue |
    Export-Clixml (Join-Path $testRoot 'QosPolicies.clixml')
Get-AppxPackage -AllUsers |
    Select-Object Name, PackageFullName, Version, InstallLocation |
    Export-Csv (Join-Path $testRoot 'AppxPackages.csv') -NoTypeInformation

$uninstallPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
    Where-Object DisplayName |
    Select-Object DisplayName, DisplayVersion, Publisher, UninstallString |
    Sort-Object DisplayName |
    Export-Csv (Join-Path $testRoot 'InstalledPrograms.csv') -NoTypeInformation

function Export-BaselineRegistryKey {
    param (
        [Parameter(Mandatory = $true)][string]$ProviderPath,
        [Parameter(Mandatory = $true)][string]$NativePath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path -LiteralPath $ProviderPath) {
        & reg.exe export $NativePath $Destination /y | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw ('Registry export failed for {0} with exit code {1}.' -f $NativePath, $LASTEXITCODE)
        }
        return
    }

    Set-Content -LiteralPath ($Destination + '.absent.txt') -Encoding UTF8 `
        -Value ('Registry key was absent at baseline: ' + $NativePath)
}

$registryExports = @(
    @{ Provider = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Native = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; File = 'ContentDeliveryManager.reg' }
    @{ Provider = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Native = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; File = 'ExplorerAdvanced.reg' }
    @{ Provider = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Native = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; File = 'Search.reg' }
    @{ Provider = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Native = 'HKCU\Software\Policies\Microsoft\Windows\Explorer'; File = 'ExplorerPolicy.reg' }
    @{ Provider = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Native = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; File = 'ThemePersonalize.reg' }
    @{ Provider = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Native = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; File = 'UAC.reg' }
)

foreach ($registryExport in $registryExports) {
    Export-BaselineRegistryKey -ProviderPath $registryExport.Provider `
        -NativePath $registryExport.Native `
        -Destination (Join-Path $testRoot $registryExport.File)
}
```

An `.absent.txt` marker is a valid baseline result. It records that Configurizer
may need to create that policy key during an apply run.

Do not export BitLocker recovery passwords into this general test directory.

### 3. Run the complete simulation

```powershell
.\Configurizer.ps1 -All -WhatIf
.\Configurizer.ps1 -ReportPath (Join-Path $testRoot 'After-All-WhatIf.json')
```

Review every `WouldChange` result. A WhatIf report is deliberately not written,
so the active transcript is the record of the simulation. The follow-up audit
should match `Before.json`; that confirms the WhatIf run changed nothing.

### 4. Apply reversible groups individually

Start with one family, audit it, simulate it, apply it, and audit it again:

```powershell
.\Configurizer.ps1 -Audit -ConfigureContentDelivery
.\Configurizer.ps1 -ConfigureContentDelivery -WhatIf
.\Configurizer.ps1 -ConfigureContentDelivery -Confirm:$false
.\Configurizer.ps1 -Audit -ConfigureContentDelivery -ReportPath (Join-Path $testRoot 'After-ContentDelivery.json')
```

A reasonable early sequence is:

1. Light or dark mode
2. Content delivery
3. Taskbar settings
4. Power settings
5. Time settings
6. Teams QoS
7. Taskbar pins and Office shortcuts
8. UAC, followed by a restart and validation

### 5. Test high-impact groups separately

Use separate maintenance windows for:

- Windows and manufacturer bloatware removal
- Standard application and Microsoft 365 installation
- Windows updates
- Manufacturer driver, BIOS, and firmware updates
- BitLocker configuration

Do not combine the first live test of these groups into one real `-All` run.
Stop and investigate any `Failed` result before moving to the next group.

### 6. Finish and compare

```powershell
.\Configurizer.ps1 -ReportPath (Join-Path $testRoot 'After-All-Tests.json')
Stop-Transcript
```

Retain the before and after reports, transcript, application inventories, registry
exports, and recovery image until the machine has completed several clean boots.

## Windows 11 privacy and unwanted-feature backlog

Additional Windows 11 privacy work should be added as separate desired-state
operations rather than as a large opaque debloat block. Candidate areas include:

- Diagnostic data and feedback policy
- Tailored experiences and advertising identifiers
- Consumer content, recommendations, and suggestion surfaces
- Activity history and cloud-backed search behavior
- Widgets, feeds, gaming capture, and other optional experiences
- Delivery Optimization behavior
- Browser and first-run promotional behavior
- Build-specific AI feature policy where present

Each addition should include an audit test, an apply action, WhatIf protection,
edition and build detection, a clear expected side effect, and preferably a
reversal path. Service deletion, broad firewall blocking, and blanket scheduled
task removal should be avoided until their effects on Windows Update, Microsoft
Store, Defender, activation, and management tooling have been tested.

## Office Deployment Tool validation

The embedded specification uses Microsoft 365 Apps for enterprise product ID
`O365ProPlusRetail`, 64-bit, Monthly Enterprise Channel, and `en-us`. It includes
no Visio or Project product entry.

The Office Deployment Tool package is downloaded only when Microsoft 365
installation is requested. Configurizer validates its pinned SHA-256 hash and a
valid Microsoft Corporation Authenticode signature before extraction, then
validates the extracted `setup.exe` signature before use.

Pinned package SHA-256:

```text
FA6CBE5B383F89B83F373C36C90EBDCC9ACFFA43D0CB47FB69062C41F46C0769
```
