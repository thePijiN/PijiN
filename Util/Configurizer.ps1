#Requires -Version 5.1

<#
.SYNOPSIS
Audits and configures a Windows workstation from one self-contained script.

.DESCRIPTION
With no action parameters, Configurizer audits every supported area and changes
nothing. Supplying one or more action switches applies only those operations.
Use -Audit with action switches to audit only the selected areas. Use -WhatIf
to exercise apply control flow without persisting Configurizer changes. A
WhatIf run still performs read-only discovery, including a Windows Update scan.

.EXAMPLE
.\Configurizer.ps1

.EXAMPLE
.\Configurizer.ps1 -Audit -ConfigurePower -ConfigureTaskbar

.EXAMPLE
.\Configurizer.ps1 -ConfigurePower -ConfigureTaskbar -Confirm:$false

.EXAMPLE
.\Configurizer.ps1 -All -WhatIf

.NOTES
Apply operations require an elevated Windows PowerShell 5.1 session. The -All
switch excludes theme selection and CleanupBitLockerDocuments, which must be
requested explicitly.
#>

#region ### Parameters ###
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [switch]$Audit, # Audit the selected operations instead of applying them. With no action switches, audit everything.
    [switch]$All, # Apply every standard operation. Theme selection and BitLocker document cleanup are excluded.
    [switch]$ConfigurePower, # Enforce the embedded AC and battery display, sleep, and disk timeout settings.
    [switch]$ConfigureContentDelivery, # Disable the selected current-user Windows suggestion and content-delivery settings.
    [switch]$ConfigureTeamsQoS, # Create or correct the embedded Teams audio, video, and sharing QoS policies.
    [switch]$ConfigureUAC, # Enforce the embedded UAC policy values. Changed values can require a restart.
    [switch]$ConfigureTime, # Set the time zone, start Windows Time, and request a clock resynchronization.
    [switch]$ConfigureTaskbar, # Enforce the embedded current-user taskbar, search, and Task View settings.
    [switch]$DarkMode, # Set the current-user Windows system and application theme to dark mode and refresh it live.
    [switch]$LightMode, # Set the current-user Windows system and application theme to light mode and refresh it live.
    [switch]$ConfigureTaskbarPins, # Deploy the embedded taskbar pin layout through the configured policy location.
    [switch]$ConfigureOfficeShortcuts, # Create desktop shortcuts for installed Microsoft Office applications.
    [switch]$ConfigureBitLocker, # Ensure system-drive encryption and protectors, then attempt Entra recovery-key backup when joined.
    [switch]$RemoveWindowsBloatware, # Remove Windows Appx and Win32 applications matching the embedded removal specification.
    [switch]$RemoveManufacturerBloatware, # Detect Dell, HP, or Lenovo and remove matching manufacturer applications.
    [switch]$InstallApps, # Install missing standard applications with winget.
    [switch]$InstallMicrosoft365, # Install Microsoft 365 Apps for enterprise without Visio or Project using the validated ODT.
    [switch]$InstallWindowsUpdates, # Search for, download, and install applicable software updates without forcing a reboot.
    [switch]$InstallManufacturerUpdates, # Install or invoke the supported Dell, HP, or Lenovo update workflow.
    [switch]$CleanupBitLockerDocuments, # Delete matching BitLocker recovery documents. Must be selected explicitly.
    [switch]$ListOperations, # Display the operation catalog and whether each operation is included in -All, then exit.
    [string]$ReportPath, # Write structured results to this JSON file or directory. Report writing is suppressed by -WhatIf.
    [switch]$PassThru # Emit result objects after the console tables for pipeline use.
)
#endregion # Parameters #

#region ### Runtime Policy ###
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:RootCmdlet = $PSCmdlet
$script:WhatIfPreference = $PSBoundParameters.ContainsKey('WhatIf') -and [bool]$PSBoundParameters['WhatIf']
$script:ExecutionMode = 'Audit'
$script:RestartRequired = $false
#endregion # Runtime Policy #

#region ### Embedded Specification ###
$script:Specification = [ordered]@{
    Name = 'Configurizer Workstation Specification'
    Version = '0.2.0'
    DataRoot = 'C:\ProgramData\Configurizer'
    ReportRoot = 'C:\ProgramData\Configurizer\Reports'

    Power = @(
        @{ Name = 'Monitor AC'; Subgroup = 'SUB_VIDEO'; Setting = 'VIDEOIDLE'; Source = 'AC'; Minutes = 0 }
        @{ Name = 'Monitor DC'; Subgroup = 'SUB_VIDEO'; Setting = 'VIDEOIDLE'; Source = 'DC'; Minutes = 0 }
        @{ Name = 'Standby AC'; Subgroup = 'SUB_SLEEP'; Setting = 'STANDBYIDLE'; Source = 'AC'; Minutes = 0 }
        @{ Name = 'Standby DC'; Subgroup = 'SUB_SLEEP'; Setting = 'STANDBYIDLE'; Source = 'DC'; Minutes = 0 }
        @{ Name = 'Disk AC'; Subgroup = 'SUB_DISK'; Setting = 'DISKIDLE'; Source = 'AC'; Minutes = 0 }
        @{ Name = 'Disk DC'; Subgroup = 'SUB_DISK'; Setting = 'DISKIDLE'; Source = 'DC'; Minutes = 0 }
    )

    ContentDelivery = @(
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338393Enabled'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Type = 'DWord'; Value = 0 }
    )

    TeamsQoS = @(
        @{ Name = 'Teams Audio'; AppPath = 'Teams.exe'; Protocol = 'Both'; SourcePortStart = 50000; SourcePortEnd = 50019; Dscp = 46; NetworkProfile = 'All' }
        @{ Name = 'Teams Video'; AppPath = 'Teams.exe'; Protocol = 'Both'; SourcePortStart = 50020; SourcePortEnd = 50039; Dscp = 34; NetworkProfile = 'All' }
        @{ Name = 'Teams Share'; AppPath = 'Teams.exe'; Protocol = 'Both'; SourcePortStart = 50040; SourcePortEnd = 50059; Dscp = 18; NetworkProfile = 'All' }
    )

    UAC = @{
        Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        Values = @(
            @{ Name = 'EnableLUA'; Type = 'DWord'; Value = 1 }
            @{ Name = 'ConsentPromptBehaviorAdmin'; Type = 'DWord'; Value = 0 }
            @{ Name = 'PromptOnSecureDesktop'; Type = 'DWord'; Value = 0 }
        )
    }

    Time = @{
        TimeZoneId = 'Eastern Standard Time'
        EnsureWindowsTimeServiceRunning = $true
        ResyncRetries = 3
    }

    Theme = @{
        Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        AppsValueName = 'AppsUseLightTheme'
        SystemValueName = 'SystemUsesLightTheme'
        ColorPrevalenceValueName = 'ColorPrevalence'
        ResetColorPrevalenceWhenLight = $true
        NotificationTimeoutMilliseconds = 5000
    }

    Taskbar = @{
        RestartExplorerOnChange = $false
        Values = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Type = 'DWord'; Value = 0 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Type = 'DWord'; Value = 0 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarMode'; Type = 'DWord'; Value = 1 }
        )
    }

    TaskbarPins = @{
        Destination = '%LocalAppData%\Microsoft\Windows\Shell\LayoutModification.xml'
        PolicyPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
        PolicyName = 'StartLayoutFile'
        RestartExplorerOnChange = $false
    }

    OfficeShortcuts = @{
        StartMenuDirectory = '%ProgramData%\Microsoft\Windows\Start Menu\Programs'
        PublicDesktopDirectory = '%Public%\Desktop'
        Names = @(
            'Outlook (classic).lnk'
            'Word.lnk'
            'Excel.lnk'
            'PowerPoint.lnk'
            'Project.lnk'
            'Visio.lnk'
        )
    }

    BitLocker = @{
        MountPoint = 'C:'
        EncryptionMethod = 'XtsAes128'
        UsedSpaceOnly = $true
        RequireTpmProtector = $true
        RequireRecoveryPasswordProtector = $true
        BackupRecoveryPasswordToEntraID = $true
    }

    WindowsAppxPatterns = @(
        '*3dbuilder*'
        '*3Dviewer*'
        '*Microsoft.BingWeather*'
        '*Microsoft.BingNews*'
        '*Microsoft.GamingApp*'
        '*Microsoft.MicrosoftSolitaireCollection*'
        '*Microsoft.SkypeApp*'
        '*Microsoft.Todos*'
        '*Microsoft.WindowsAlarms*'
        '*Microsoft.WindowsFeedbackHub*'
        '*Microsoft.Xbox.TCUI*'
        '*Microsoft.XboxApp*'
        '*Microsoft.XboxGameOverlay*'
        '*Microsoft.XboxGamingOverlay*'
        '*Microsoft.XboxIdentityProvider*'
        '*Microsoft.XboxSpeechToTextOverlay*'
        '*Microsoft.MixedReality.Portal*'
        '*Microsoft.Office.Sway*'
        '*Microsoft.MicrosoftOfficeHub*'
        '*Microsoft.OneConnect*'
        '*Microsoft.GetHelp*'
        '*Microsoft.Getstarted*'
        '*Microsoft.Advertising.Xaml*'
        '*Spotify*'
        '*Disney*'
        '*Twitter*'
        '*CandyCrush*'
        '*MinecraftUWP*'
        '*RoyalRevolt2*'
        '*MarchofEmpires*'
        '*Duolingo*'
        '*FreshPaint*'
        '*Print3D*'
        '*Flipboard*'
        '*AutodeskSketchBook*'
        '*KeeperSecurityInc*'
        '*NetworkSpeedTest*'
        '*RemoteDesktop*'
        '*AdobePhotoshopExpress*'
        '*EclipseManager*'
    )

    ManufacturerBloatware = @{
        HP = @{
            Win32Patterns = @(
                'HP Notifications'
                'HP Documentation'
                'HP Connection Optimizer'
                'HP Sure Run Module'
                'HP Wolf Security'
                'HP Sure Sense Service'
                'HP Sure Run'
                'HP Sure Recover'
                'HP Sure Click'
                'HP Client Security Manager'
                'HP Security Update Service'
                'HP Privacy Settings'
            )
            AppxPatterns = @(
                '*myHP*'
                '*HPSystemInformation*'
                '*HPSupportAssistant*'
                '*HPPrivacySettings*'
                '*HPPCHardwareDiagnosticsWindows*'
                '*HPEasyClean*'
            )
            SilentOverrides = @{}
        }
        Dell = @{
            Win32Patterns = @(
                'Dell SupportAssist OS Recovery Plugin for Dell Update'
                'Dell SupportAssist Remediation'
                'Dell Pair'
                'Dell SupportAssist'
                'Dell Optimizer'
                'Dell Display Manager'
                'Dell Peripheral Manager'
                'Dell Watchdog'
            )
            AppxPatterns = @(
                '*Dell.MobileConnect*'
                '*Dell.SA*'
                '*Dell.PremierColor*'
                '*Dell.ProductRegistration*'
                '*Dell.SARemediation*'
                '*DellInc.DellSupportAssistforPCs*'
                '*HONHAIPRECISIONINDUSTRYCO.DellWatchdogTimer*'
            )
            SilentOverrides = @{
                'Dell Optimizer Core' = '-remove -runfromtemp -silent'
                'Dell SupportAssist Remediation' = '/uninstall /quiet /norestart'
            }
        }
        Lenovo = @{
            Win32Patterns = @()
            AppxPatterns = @(
                '*lenovo*'
                '*E046963F*'
            )
            AppxExclusions = @(
                '*ELANTrackPoint*'
            )
            SilentOverrides = @{}
        }
    }

    WingetPackages = @(
        @{ Name = '7-Zip'; Id = '7zip.7zip'; DisplayNamePatterns = @('7-Zip*') }
        @{ Name = 'Google Chrome'; Id = 'Google.Chrome'; DisplayNamePatterns = @('Google Chrome*') }
        @{ Name = 'Adobe Acrobat Reader'; Id = 'Adobe.Acrobat.Reader.64-bit'; DisplayNamePatterns = @('Adobe Acrobat*', 'Adobe Acrobat Reader*') }
    )

    Microsoft365 = @{
        ProductId = 'O365ProPlusRetail'
        OdtUrl = 'https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20131-20090.exe'
        OdtSha256 = 'FA6CBE5B383F89B83F373C36C90EBDCC9ACFFA43D0CB47FB69062C41F46C0769'
        OdtVersion = '16.0.20131.20090'
    }

    ManufacturerUpdates = @{
        Dell = @{
            WingetId = 'Dell.CommandUpdate'
            CliCandidates = @(
                'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
                'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
            )
        }
        HP = @{
            WingetId = 'HP.ImageAssistant'
            CliCandidates = @(
                'C:\SWSetup\HPImageAssistant\HPImageAssistant.exe'
                'C:\Program Files\HP\HPIA\bin\HPImageAssistant.exe'
            )
        }
        Lenovo = @{
            ModuleName = 'LSUClient'
        }
    }

    Cleanup = @{
        Roots = @(
            'C:\ProgramData\Configurizer'
            '%UserProfile%\Documents'
        )
        FileNamePattern = '*BitLocker*'
        Extensions = @('.txt', '.pdf')
    }
}

$script:TaskbarLayoutXml = @'
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection>
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />
        <taskbar:DesktopApp DesktopApplicationID="MSEdge" />
        <taskbar:DesktopApp DesktopApplicationID="Chrome" />
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Office.OUTLOOK.EXE.15" />
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Office.WINWORD.EXE.15" />
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Office.EXCEL.EXE.15" />
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Office.POWERPNT.EXE.15" />
        <taskbar:DesktopApp DesktopApplicationID="MSTeams_8wekyb3d8bbwe!MSTeams" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
'@

$script:OfficeConfigurationXml = @'
<Configuration>
  <Add OfficeClientEdition="64" Channel="MonthlyEnterprise">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
    </Product>
  </Add>
  <Updates Enabled="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="FALSE" />
</Configuration>
'@
#endregion # Embedded Specification #

#region ### Result Framework ###
function New-ConfigurizerResult {
    param (
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Item,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Message,
        [bool]$RestartRequired = $false
    )

    [pscustomobject]@{
        Operation = $Operation
        Item = $Item
        Status = $Status
        RestartRequired = $RestartRequired
        Message = $Message
    }
}

function Invoke-ConfigurizerDesiredState {
    param (
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Item,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][scriptblock]$Test,
        [Parameter(Mandatory = $true)][scriptblock]$Set,
        [bool]$RestartRequired = $false
    )

    try {
        if ([bool](& $Test)) {
            return New-ConfigurizerResult -Operation $Operation -Item $Item -Status 'Compliant' -Message 'Already at the desired state.'
        }

        if ($script:ExecutionMode -eq 'Audit') {
            return New-ConfigurizerResult -Operation $Operation -Item $Item -Status 'NonCompliant' -Message $Action -RestartRequired $RestartRequired
        }

        if (-not $script:RootCmdlet.ShouldProcess($Target, $Action)) {
            return New-ConfigurizerResult -Operation $Operation -Item $Item -Status 'WouldChange' -Message ('WhatIf: ' + $Action) -RestartRequired $RestartRequired
        }

        & $Set | Out-Null
        if (-not [bool](& $Test)) {
            return New-ConfigurizerResult -Operation $Operation -Item $Item -Status 'Failed' -Message 'Post-change verification did not match the desired state.' -RestartRequired $RestartRequired
        }

        if ($RestartRequired) {
            $script:RestartRequired = $true
        }
        return New-ConfigurizerResult -Operation $Operation -Item $Item -Status 'Changed' -Message $Action -RestartRequired $RestartRequired
    }
    catch {
        return New-ConfigurizerResult -Operation $Operation -Item $Item -Status 'Failed' -Message $_.Exception.Message -RestartRequired $RestartRequired
    }
}
#endregion # Result Framework #

#region ### Discovery Helpers ###
function Test-ConfigurizerAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ConfigurizerExpandedPath {
    param ([Parameter(Mandatory = $true)][string]$Path)
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-ConfigurizerManufacturer {
    $manufacturer = ''
    try {
        $savedWhatIfPreference = $script:WhatIfPreference
        try {
            $script:WhatIfPreference = $false
            Import-Module CimCmdlets -ErrorAction SilentlyContinue | Out-Null
        }
        finally {
            $script:WhatIfPreference = $savedWhatIfPreference
        }
        $manufacturer = [string](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Manufacturer
    }
    catch {
        $bios = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue
        if ($null -ne $bios) {
            $property = $bios.PSObject.Properties['SystemManufacturer']
            if ($null -ne $property) {
                $manufacturer = [string]$property.Value
            }
        }
    }

    switch -Wildcard ($manufacturer) {
        'HP*' { return 'HP' }
        'Hewlett-Packard*' { return 'HP' }
        'Dell*' { return 'Dell' }
        'Alienware*' { return 'Dell' }
        'Lenovo*' { return 'Lenovo' }
        default { return 'Other' }
    }
}

function Get-ConfigurizerUninstallEntries {
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            $displayNameProperty = $_.PSObject.Properties['DisplayName']
            if ($null -eq $displayNameProperty -or [string]::IsNullOrWhiteSpace([string]$displayNameProperty.Value)) {
                return
            }
            $displayVersionProperty = $_.PSObject.Properties['DisplayVersion']
            $publisherProperty = $_.PSObject.Properties['Publisher']
            $uninstallProperty = $_.PSObject.Properties['UninstallString']
            $quietUninstallProperty = $_.PSObject.Properties['QuietUninstallString']
            [pscustomobject]@{
                DisplayName = [string]$displayNameProperty.Value
                DisplayVersion = if ($null -eq $displayVersionProperty) { '' } else { [string]$displayVersionProperty.Value }
                Publisher = if ($null -eq $publisherProperty) { '' } else { [string]$publisherProperty.Value }
                UninstallString = if ($null -eq $uninstallProperty) { '' } else { [string]$uninstallProperty.Value }
                QuietUninstallString = if ($null -eq $quietUninstallProperty) { '' } else { [string]$quietUninstallProperty.Value }
                KeyName = [string]$_.PSChildName
                KeyPath = [string]$_.PSPath
            }
        }
    }
}

function Test-ConfigurizerProgramInstalled {
    param ([Parameter(Mandatory = $true)][string[]]$DisplayNamePatterns)

    $entries = @(Get-ConfigurizerUninstallEntries)
    foreach ($pattern in $DisplayNamePatterns) {
        if ($entries | Where-Object { $_.DisplayName -like $pattern }) {
            return $true
        }
    }
    return $false
}

function Get-ConfigurizerWinget {
    $command = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $localAlias = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\winget.exe'
    try {
        if (Test-Path -LiteralPath $localAlias -PathType Leaf -ErrorAction Stop) {
            return $localAlias
        }
    }
    catch {
        # Continue to package discovery when the WindowsApps alias is inaccessible.
    }

    try {
        $savedWhatIfPreference = $script:WhatIfPreference
        try {
            $script:WhatIfPreference = $false
            Import-Module Appx -ErrorAction Stop | Out-Null
        }
        finally {
            $script:WhatIfPreference = $savedWhatIfPreference
        }
        $package = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1
    }
    catch {
        $package = $null
    }
    if ($null -ne $package) {
        $packageWinget = Join-Path -Path $package.InstallLocation -ChildPath 'winget.exe'
        try {
            if (Test-Path -LiteralPath $packageWinget -PathType Leaf -ErrorAction Stop) {
                return $packageWinget
            }
        }
        catch {
            # The package directory can be ACL restricted in an unelevated audit.
        }
    }
    return $null
}

function Find-ConfigurizerFile {
    param ([Parameter(Mandatory = $true)][string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}
#endregion # Discovery Helpers #

#region ### Desired State Helpers ###
function Test-ConfigurizerRegistryValue {
    param (
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $properties = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $properties) {
        return $false
    }
    $property = $properties.PSObject.Properties[$Name]
    return $null -ne $property -and $property.Value -eq $Value
}

function Set-ConfigurizerRegistryValue {
    param (
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')][string]$Type,
        [Parameter(Mandatory = $true)]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
}

function Invoke-ConfigurizerRegistryValues {
    param (
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][object[]]$Values,
        [bool]$RestartRequired = $false
    )

    foreach ($entry in $Values) {
        $path = [string]$entry.Path
        $name = [string]$entry.Name
        $type = [string]$entry.Type
        $value = $entry.Value
        Invoke-ConfigurizerDesiredState -Operation $Operation -Item ($path + ' :: ' + $name) -Target ($path + '\' + $name) -Action ('Set registry value to ' + [string]$value + ' (' + $type + ').') -RestartRequired $RestartRequired -Test {
            Test-ConfigurizerRegistryValue -Path $path -Name $name -Value $value
        } -Set {
            Set-ConfigurizerRegistryValue -Path $path -Name $name -Type $type -Value $value
        }
    }
}

function Get-ConfigurizerPowerSettingSeconds {
    param (
        [Parameter(Mandatory = $true)][string]$Subgroup,
        [Parameter(Mandatory = $true)][string]$Setting,
        [Parameter(Mandatory = $true)][ValidateSet('AC', 'DC')][string]$Source
    )

    $output = & powercfg.exe /query SCHEME_CURRENT $Subgroup $Setting 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'powercfg query failed: ' + ($output -join ' ')
    }
    $label = if ($Source -eq 'AC') { 'Current AC Power Setting Index' } else { 'Current DC Power Setting Index' }
    $match = [regex]::Match(($output -join "`n"), [regex]::Escape($label) + ':\s+0x([0-9a-fA-F]+)')
    if (-not $match.Success) {
        throw 'Could not parse the current power setting.'
    }
    return [Convert]::ToInt64($match.Groups[1].Value, 16)
}

function Set-ConfigurizerPowerSettingSeconds {
    param (
        [Parameter(Mandatory = $true)][string]$Subgroup,
        [Parameter(Mandatory = $true)][string]$Setting,
        [Parameter(Mandatory = $true)][ValidateSet('AC', 'DC')][string]$Source,
        [Parameter(Mandatory = $true)][long]$Seconds
    )

    $verb = if ($Source -eq 'AC') { '/setacvalueindex' } else { '/setdcvalueindex' }
    $output = & powercfg.exe $verb SCHEME_CURRENT $Subgroup $Setting $Seconds 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'powercfg update failed: ' + ($output -join ' ')
    }
    $output = & powercfg.exe /setactive SCHEME_CURRENT 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'powercfg could not reactivate the current scheme: ' + ($output -join ' ')
    }
}

function Restart-ConfigurizerExplorer {
    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath "$env:WINDIR\explorer.exe" | Out-Null
}

function Install-ConfigurizerWingetPackage {
    param (
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)]$Package
    )

    $patterns = @($Package.DisplayNamePatterns)
    $name = [string]$Package.Name
    $id = [string]$Package.Id
    return Invoke-ConfigurizerDesiredState -Operation $Operation -Item $name -Target $id -Action ('Install ' + $name + ' with winget when it is missing.') -Test {
        Test-ConfigurizerProgramInstalled -DisplayNamePatterns $patterns
    } -Set {
        $winget = Get-ConfigurizerWinget
        if ([string]::IsNullOrWhiteSpace($winget)) {
            throw 'winget.exe is unavailable. Install or repair Microsoft App Installer first.'
        }
        $output = & $winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw 'winget exited with code ' + [string]$LASTEXITCODE + ': ' + ($output -join ' ')
        }
    }
}
#endregion # Desired State Helpers #

#region ### Windows Configuration Operations ###
function Invoke-ConfigurizerPower {
    foreach ($setting in @($script:Specification.Power)) {
        $subgroup = [string]$setting.Subgroup
        $settingName = [string]$setting.Setting
        $source = [string]$setting.Source
        $seconds = [long]$setting.Minutes * 60
        $item = [string]$setting.Name
        Invoke-ConfigurizerDesiredState -Operation 'Power' -Item $item -Target 'Active power scheme' -Action ('Set timeout to ' + [string]$setting.Minutes + ' minute(s).') -Test {
            (Get-ConfigurizerPowerSettingSeconds -Subgroup $subgroup -Setting $settingName -Source $source) -eq $seconds
        } -Set {
            Set-ConfigurizerPowerSettingSeconds -Subgroup $subgroup -Setting $settingName -Source $source -Seconds $seconds
        }
    }
}

function Invoke-ConfigurizerContentDelivery {
    Invoke-ConfigurizerRegistryValues -Operation 'ContentDelivery' -Values @($script:Specification.ContentDelivery)
}

function Test-ConfigurizerQosPolicy {
    param ($Policy)

    $current = Get-NetQosPolicy -Name ([string]$Policy.Name) -ErrorAction SilentlyContinue
    if ($null -eq $current) {
        return $false
    }
    return (
        [string]$current.AppPathNameMatchCondition -eq [string]$Policy.AppPath -and
        [string]$current.IPProtocolMatchCondition -eq [string]$Policy.Protocol -and
        [int]$current.IPSrcPortStartMatchCondition -eq [int]$Policy.SourcePortStart -and
        [int]$current.IPSrcPortEndMatchCondition -eq [int]$Policy.SourcePortEnd -and
        [int]$current.DSCPAction -eq [int]$Policy.Dscp -and
        [string]$current.NetworkProfile -eq [string]$Policy.NetworkProfile
    )
}

function Set-ConfigurizerQosPolicy {
    param ($Policy)

    $parameters = @{
        Name = [string]$Policy.Name
        AppPathNameMatchCondition = [string]$Policy.AppPath
        IPProtocolMatchCondition = [string]$Policy.Protocol
        IPSrcPortStartMatchCondition = [int]$Policy.SourcePortStart
        IPSrcPortEndMatchCondition = [int]$Policy.SourcePortEnd
        DSCPAction = [int]$Policy.Dscp
        NetworkProfile = [string]$Policy.NetworkProfile
        ErrorAction = 'Stop'
    }
    if ($null -eq (Get-NetQosPolicy -Name ([string]$Policy.Name) -ErrorAction SilentlyContinue)) {
        New-NetQosPolicy @parameters | Out-Null
    }
    else {
        Set-NetQosPolicy @parameters | Out-Null
    }
}

function Invoke-ConfigurizerTeamsQoS {
    if ($null -eq (Get-Command Get-NetQosPolicy -ErrorAction SilentlyContinue)) {
        return New-ConfigurizerResult -Operation 'TeamsQoS' -Item 'NetQos module' -Status 'Failed' -Message 'The NetQos module is unavailable.'
    }
    foreach ($policyEntry in @($script:Specification.TeamsQoS)) {
        $policy = $policyEntry
        $name = [string]$policy.Name
        Invoke-ConfigurizerDesiredState -Operation 'TeamsQoS' -Item $name -Target $name -Action 'Create or reconcile the configured QoS policy.' -Test {
            Test-ConfigurizerQosPolicy -Policy $policy
        } -Set {
            Set-ConfigurizerQosPolicy -Policy $policy
        }
    }
}

function Invoke-ConfigurizerUAC {
    $path = [string]$script:Specification.UAC.Path
    $values = foreach ($entry in @($script:Specification.UAC.Values)) {
        @{ Path = $path; Name = [string]$entry.Name; Type = [string]$entry.Type; Value = $entry.Value }
    }
    Invoke-ConfigurizerRegistryValues -Operation 'UAC' -Values @($values) -RestartRequired $true
}

function Invoke-ConfigurizerTime {
    $configuration = $script:Specification.Time
    $timeZoneId = [string]$configuration.TimeZoneId
    $results = @()
    $results += Invoke-ConfigurizerDesiredState -Operation 'Time' -Item 'Time zone' -Target 'System time zone' -Action ('Set time zone to ' + $timeZoneId + '.') -Test {
        (Get-TimeZone).Id -eq $timeZoneId
    } -Set {
        Set-TimeZone -Id $timeZoneId
    }

    if ([bool]$configuration.EnsureWindowsTimeServiceRunning) {
        $results += Invoke-ConfigurizerDesiredState -Operation 'Time' -Item 'Windows Time service' -Target 'w32time' -Action 'Start the Windows Time service.' -Test {
            (Get-Service -Name 'w32time').Status -eq 'Running'
        } -Set {
            Start-Service -Name 'w32time'
        }
    }

    if ($script:ExecutionMode -eq 'Apply') {
        if ($script:RootCmdlet.ShouldProcess('Windows Time service', 'Resynchronize the system clock.')) {
            $success = $false
            $lastOutput = @()
            $retries = [Math]::Max(1, [int]$configuration.ResyncRetries)
            for ($attempt = 1; $attempt -le $retries; $attempt++) {
                $lastOutput = & w32tm.exe /resync 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $success = $true
                    break
                }
                Start-Sleep -Seconds 2
            }
            if ($success) {
                $results += New-ConfigurizerResult -Operation 'Time' -Item 'Clock resynchronization' -Status 'Changed' -Message 'The system clock was resynchronized.'
            }
            else {
                $results += New-ConfigurizerResult -Operation 'Time' -Item 'Clock resynchronization' -Status 'Failed' -Message ($lastOutput -join ' ')
            }
        }
        else {
            $results += New-ConfigurizerResult -Operation 'Time' -Item 'Clock resynchronization' -Status 'WouldChange' -Message 'WhatIf: Resynchronize the system clock.'
        }
    }
    return $results
}

function Get-ConfigurizerThemeState {
    $configuration = $script:Specification.Theme
    $current = Get-ItemProperty -LiteralPath ([string]$configuration.Path) -ErrorAction SilentlyContinue
    $appsProperty = if ($null -ne $current) { $current.PSObject.Properties[[string]$configuration.AppsValueName] } else { $null }
    $systemProperty = if ($null -ne $current) { $current.PSObject.Properties[[string]$configuration.SystemValueName] } else { $null }
    $appsValue = if ($null -eq $appsProperty) { 1 } else { [int]$appsProperty.Value }
    $systemValue = if ($null -eq $systemProperty) { 1 } else { [int]$systemProperty.Value }
    $mode = if ($appsValue -eq 0 -and $systemValue -eq 0) {
        'Dark'
    }
    elseif ($appsValue -eq 1 -and $systemValue -eq 1) {
        'Light'
    }
    else {
        'Mixed'
    }

    return [pscustomobject]@{
        Mode = $mode
        AppsUseLightTheme = $appsValue
        SystemUsesLightTheme = $systemValue
    }
}

function Initialize-ConfigurizerThemeInterop {
    if ($null -ne ('Configurizer.NativeTheme' -as [type])) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Configurizer
{
    public static class NativeTheme
    {
        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeoutString(
            IntPtr hWnd,
            UInt32 message,
            UIntPtr wParam,
            string lParam,
            UInt32 flags,
            UInt32 timeout,
            out UIntPtr result);

        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
        public static extern IntPtr SendMessageTimeoutPointer(
            IntPtr hWnd,
            UInt32 message,
            UIntPtr wParam,
            IntPtr lParam,
            UInt32 flags,
            UInt32 timeout,
            out UIntPtr result);
    }
}
'@
}

function Send-ConfigurizerThemeNotifications {
    Initialize-ConfigurizerThemeInterop
    $timeout = [uint32]$script:Specification.Theme.NotificationTimeoutMilliseconds
    $windowBroadcast = [intptr]0xffff
    $abortIfHung = [uint32]0x0002
    $messages = @(
        @{ Id = [uint32]0x001a; Parameter = 'ImmersiveColorSet' }
        @{ Id = [uint32]0x031a; Parameter = $null }
        @{ Id = [uint32]0x0320; Parameter = $null }
    )

    foreach ($message in $messages) {
        $result = [uintptr]::Zero
        if ($null -eq $message.Parameter) {
            $returnValue = [Configurizer.NativeTheme]::SendMessageTimeoutPointer(
                $windowBroadcast,
                [uint32]$message.Id,
                [uintptr]::Zero,
                [intptr]::Zero,
                $abortIfHung,
                $timeout,
                [ref]$result
            )
        }
        else {
            $returnValue = [Configurizer.NativeTheme]::SendMessageTimeoutString(
                $windowBroadcast,
                [uint32]$message.Id,
                [uintptr]::Zero,
                [string]$message.Parameter,
                $abortIfHung,
                $timeout,
                [ref]$result
            )
        }
        if ($returnValue -eq [intptr]::Zero) {
            Write-Verbose ('Theme notification 0x' + ([uint32]$message.Id).ToString('X4') + ' timed out or was not acknowledged.')
        }
    }
}

function Set-ConfigurizerTheme {
    param ([Parameter(Mandatory = $true)][ValidateSet('Dark', 'Light')][string]$Mode)

    $configuration = $script:Specification.Theme
    $value = if ($Mode -eq 'Light') { 1 } else { 0 }
    Set-ConfigurizerRegistryValue -Path ([string]$configuration.Path) -Name ([string]$configuration.AppsValueName) -Type 'DWord' -Value $value
    Set-ConfigurizerRegistryValue -Path ([string]$configuration.Path) -Name ([string]$configuration.SystemValueName) -Type 'DWord' -Value $value
    if ($Mode -eq 'Light' -and [bool]$configuration.ResetColorPrevalenceWhenLight) {
        Set-ConfigurizerRegistryValue -Path ([string]$configuration.Path) -Name ([string]$configuration.ColorPrevalenceValueName) -Type 'DWord' -Value 0
    }
    Send-ConfigurizerThemeNotifications
}

function Invoke-ConfigurizerTheme {
    param ([Parameter(Mandatory = $true)][ValidateSet('Observe', 'Dark', 'Light')][string]$Mode)

    if ($Mode -eq 'Observe') {
        $state = Get-ConfigurizerThemeState
        $status = if ($state.Mode -eq 'Mixed') { 'NonCompliant' } else { 'Compliant' }
        $message = if ($state.Mode -eq 'Mixed') {
            'Application and system theme values disagree. Select -DarkMode or -LightMode to reconcile them.'
        }
        else {
            'Current-user Windows system and application theme is ' + $state.Mode.ToLowerInvariant() + ' mode.'
        }
        return New-ConfigurizerResult -Operation 'WindowsTheme' -Item 'Current user' -Status $status -Message $message
    }

    $desiredValue = if ($Mode -eq 'Light') { 1 } else { 0 }
    return Invoke-ConfigurizerDesiredState -Operation 'WindowsTheme' -Item ($Mode + ' mode') -Target 'Current-user Windows theme' -Action ('Set Windows system and application theme to ' + $Mode.ToLowerInvariant() + ' mode and broadcast a live refresh.') -Test {
        $state = Get-ConfigurizerThemeState
        $state.AppsUseLightTheme -eq $desiredValue -and $state.SystemUsesLightTheme -eq $desiredValue
    } -Set {
        Set-ConfigurizerTheme -Mode $Mode
    }
}

function Invoke-ConfigurizerTaskbar {
    $configuration = $script:Specification.Taskbar
    $results = @(Invoke-ConfigurizerRegistryValues -Operation 'Taskbar' -Values @($configuration.Values))
    $drift = @($results | Where-Object { $_.Status -in @('Changed', 'WouldChange', 'NonCompliant') }).Count -gt 0
    if ([bool]$configuration.RestartExplorerOnChange -and $drift -and $script:ExecutionMode -eq 'Apply') {
        if ($script:RootCmdlet.ShouldProcess('explorer.exe', 'Restart Explorer to apply taskbar changes.')) {
            try {
                Restart-ConfigurizerExplorer
                $results += New-ConfigurizerResult -Operation 'Taskbar' -Item 'Explorer refresh' -Status 'Changed' -Message 'Explorer was restarted.'
            }
            catch {
                $results += New-ConfigurizerResult -Operation 'Taskbar' -Item 'Explorer refresh' -Status 'Failed' -Message $_.Exception.Message
            }
        }
    }
    return $results
}

function Invoke-ConfigurizerTaskbarPins {
    $configuration = $script:Specification.TaskbarPins
    $destination = Get-ConfigurizerExpandedPath -Path ([string]$configuration.Destination)
    $policyPath = [string]$configuration.PolicyPath
    $policyName = [string]$configuration.PolicyName
    $results = @()

    $results += Invoke-ConfigurizerDesiredState -Operation 'TaskbarPins' -Item 'Embedded taskbar layout' -Target $destination -Action 'Write the embedded taskbar layout XML.' -Test {
        (Test-Path -LiteralPath $destination -PathType Leaf) -and (Get-Content -LiteralPath $destination -Raw).Trim() -eq $script:TaskbarLayoutXml.Trim()
    } -Set {
        $parent = Split-Path -Path $destination -Parent
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
        Set-Content -LiteralPath $destination -Value $script:TaskbarLayoutXml -Encoding UTF8
    }

    $results += Invoke-ConfigurizerDesiredState -Operation 'TaskbarPins' -Item 'Layout policy' -Target ($policyPath + '\' + $policyName) -Action 'Point the Start layout policy to the embedded XML file.' -Test {
        Test-ConfigurizerRegistryValue -Path $policyPath -Name $policyName -Value $destination
    } -Set {
        Set-ConfigurizerRegistryValue -Path $policyPath -Name $policyName -Type 'String' -Value $destination
    }

    $drift = @($results | Where-Object { $_.Status -in @('Changed', 'WouldChange') }).Count -gt 0
    if ([bool]$configuration.RestartExplorerOnChange -and $drift -and $script:ExecutionMode -eq 'Apply') {
        if ($script:RootCmdlet.ShouldProcess('explorer.exe', 'Restart Explorer to apply taskbar pins.')) {
            Restart-ConfigurizerExplorer
        }
    }
    return $results
}

function Find-ConfigurizerStartMenuShortcut {
    param ([string]$Directory, [string]$Name)

    $direct = Join-Path -Path $Directory -ChildPath $Name
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }
    $match = Get-ChildItem -LiteralPath $Directory -Filter $Name -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $match) {
        return $match.FullName
    }
    return $null
}

function Invoke-ConfigurizerOfficeShortcuts {
    $configuration = $script:Specification.OfficeShortcuts
    $startMenu = Get-ConfigurizerExpandedPath -Path ([string]$configuration.StartMenuDirectory)
    $publicDesktop = Get-ConfigurizerExpandedPath -Path ([string]$configuration.PublicDesktopDirectory)
    if (-not (Test-Path -LiteralPath $startMenu -PathType Container)) {
        return New-ConfigurizerResult -Operation 'OfficeShortcuts' -Item 'Start menu' -Status 'Failed' -Message ('Directory not found: ' + $startMenu)
    }

    foreach ($nameEntry in @($configuration.Names)) {
        $name = [string]$nameEntry
        $source = Find-ConfigurizerStartMenuShortcut -Directory $startMenu -Name $name
        if ([string]::IsNullOrWhiteSpace($source)) {
            New-ConfigurizerResult -Operation 'OfficeShortcuts' -Item $name -Status 'Skipped' -Message 'The application shortcut is not present in the Start menu.'
            continue
        }
        $destination = Join-Path -Path $publicDesktop -ChildPath $name
        Invoke-ConfigurizerDesiredState -Operation 'OfficeShortcuts' -Item $name -Target $destination -Action 'Copy the shortcut to the Public Desktop.' -Test {
            Test-Path -LiteralPath $destination -PathType Leaf
        } -Set {
            if (-not (Test-Path -LiteralPath $publicDesktop -PathType Container)) {
                New-Item -Path $publicDesktop -ItemType Directory -Force | Out-Null
            }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
}
#endregion # Windows Configuration Operations #

#region ### BitLocker Operations ###
function Get-ConfigurizerBitLockerVolume {
    param ([Parameter(Mandatory = $true)][string]$MountPoint)

    if ($null -eq (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        throw 'The BitLocker PowerShell module is unavailable.'
    }
    return Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
}

function Get-ConfigurizerBitLockerProtectorTypes {
    param ($Volume)

    $types = @()
    foreach ($protector in @($Volume.KeyProtector)) {
        if ($null -ne $protector.KeyProtectorType) {
            $types += [string]$protector.KeyProtectorType
        }
        elseif ($protector.RecoveryPassword) {
            $types += 'RecoveryPassword'
        }
    }
    return $types
}

function Test-ConfigurizerEntraJoined {
    $output = & dsregcmd.exe /status 2>&1
    return ($output -join "`n") -match 'AzureAdJoined\s*:\s*YES'
}

function Invoke-ConfigurizerBitLocker {
    $configuration = $script:Specification.BitLocker
    $mountPoint = [string]$configuration.MountPoint
    $method = [string]$configuration.EncryptionMethod
    $usedSpaceOnly = [bool]$configuration.UsedSpaceOnly
    $results = @()

    if (-not (Test-ConfigurizerAdministrator)) {
        return New-ConfigurizerResult -Operation 'BitLocker' -Item $mountPoint -Status 'Skipped' -Message 'An elevated session is required to inspect BitLocker state.'
    }

    try {
        $volume = Get-ConfigurizerBitLockerVolume -MountPoint $mountPoint
    }
    catch {
        return New-ConfigurizerResult -Operation 'BitLocker' -Item $mountPoint -Status 'Failed' -Message $_.Exception.Message
    }

    $currentStatus = [string]$volume.VolumeStatus
    $currentMethod = [string]$volume.EncryptionMethod
    $encrypted = $currentStatus -in @('FullyEncrypted', 'EncryptionInProgress', 'EncryptionPaused')

    if ($encrypted -and $currentMethod -ne $method) {
        $status = if ($script:ExecutionMode -eq 'Apply') { 'Failed' } else { 'NonCompliant' }
        $results += New-ConfigurizerResult -Operation 'BitLocker' -Item 'Encryption method' -Status $status -Message ('Current method is ' + $currentMethod + '. Changing to ' + $method + ' requires decryption and is not automated.')
    }
    else {
        $results += Invoke-ConfigurizerDesiredState -Operation 'BitLocker' -Item 'Volume encryption' -Target $mountPoint -Action ('Enable BitLocker using ' + $method + '.') -Test {
            $check = Get-ConfigurizerBitLockerVolume -MountPoint $mountPoint
            ([string]$check.VolumeStatus -in @('FullyEncrypted', 'EncryptionInProgress', 'EncryptionPaused')) -and [string]$check.EncryptionMethod -eq $method
        } -Set {
            if ([bool]$configuration.RequireTpmProtector) {
                $tpm = Get-Tpm
                if (-not $tpm.TpmPresent -or -not $tpm.TpmReady) {
                    throw 'A ready TPM is required but was not found.'
                }
                Enable-BitLocker -MountPoint $mountPoint -EncryptionMethod $method -TpmProtector -UsedSpaceOnly:$usedSpaceOnly -SkipHardwareTest | Out-Null
            }
            elseif ([bool]$configuration.RequireRecoveryPasswordProtector) {
                Enable-BitLocker -MountPoint $mountPoint -EncryptionMethod $method -RecoveryPasswordProtector -UsedSpaceOnly:$usedSpaceOnly -SkipHardwareTest | Out-Null
            }
            else {
                throw 'At least one BitLocker protector must be required.'
            }
        }
    }

    if ([bool]$configuration.RequireTpmProtector) {
        $results += Invoke-ConfigurizerDesiredState -Operation 'BitLocker' -Item 'TPM protector' -Target $mountPoint -Action 'Add a TPM key protector.' -Test {
            $check = Get-ConfigurizerBitLockerVolume -MountPoint $mountPoint
            'Tpm' -in @(Get-ConfigurizerBitLockerProtectorTypes -Volume $check)
        } -Set {
            Add-BitLockerKeyProtector -MountPoint $mountPoint -TpmProtector | Out-Null
        }
    }

    if ([bool]$configuration.RequireRecoveryPasswordProtector) {
        $results += Invoke-ConfigurizerDesiredState -Operation 'BitLocker' -Item 'Recovery password protector' -Target $mountPoint -Action 'Add a recovery password key protector.' -Test {
            $check = Get-ConfigurizerBitLockerVolume -MountPoint $mountPoint
            'RecoveryPassword' -in @(Get-ConfigurizerBitLockerProtectorTypes -Volume $check)
        } -Set {
            Add-BitLockerKeyProtector -MountPoint $mountPoint -RecoveryPasswordProtector | Out-Null
        }
    }

    $results += Invoke-ConfigurizerDesiredState -Operation 'BitLocker' -Item 'Protection status' -Target $mountPoint -Action 'Resume BitLocker protection.' -Test {
        $check = Get-ConfigurizerBitLockerVolume -MountPoint $mountPoint
        [string]$check.ProtectionStatus -eq 'On'
    } -Set {
        Resume-BitLocker -MountPoint $mountPoint | Out-Null
    }

    if ([bool]$configuration.BackupRecoveryPasswordToEntraID) {
        if (-not (Test-ConfigurizerEntraJoined)) {
            $results += New-ConfigurizerResult -Operation 'BitLocker' -Item 'Entra ID recovery backup' -Status 'Skipped' -Message 'The device is not joined to Microsoft Entra ID.'
        }
        elseif ($script:ExecutionMode -eq 'Audit') {
            $results += New-ConfigurizerResult -Operation 'BitLocker' -Item 'Entra ID recovery backup' -Status 'NotAuditable' -Message 'Windows does not expose local confirmation of a previous Entra ID backup.'
        }
        elseif ($script:RootCmdlet.ShouldProcess($mountPoint, 'Back up recovery password protectors to Microsoft Entra ID.')) {
            try {
                $check = Get-ConfigurizerBitLockerVolume -MountPoint $mountPoint
                $protectors = @($check.KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' -or $_.RecoveryPassword })
                if ($protectors.Count -eq 0) {
                    throw 'No recovery password protector is available.'
                }
                foreach ($protector in $protectors) {
                    BackupToAAD-BitLockerKeyProtector -MountPoint $mountPoint -KeyProtectorId $protector.KeyProtectorId | Out-Null
                }
                $results += New-ConfigurizerResult -Operation 'BitLocker' -Item 'Entra ID recovery backup' -Status 'Changed' -Message 'Recovery protectors were submitted to Microsoft Entra ID.'
            }
            catch {
                $results += New-ConfigurizerResult -Operation 'BitLocker' -Item 'Entra ID recovery backup' -Status 'Failed' -Message $_.Exception.Message
            }
        }
        else {
            $results += New-ConfigurizerResult -Operation 'BitLocker' -Item 'Entra ID recovery backup' -Status 'WouldChange' -Message 'WhatIf: Back up recovery protectors to Microsoft Entra ID.'
        }
    }
    return $results
}

function Invoke-ConfigurizerBitLockerDocumentCleanup {
    $configuration = $script:Specification.Cleanup
    $extensions = @($configuration.Extensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $pattern = [string]$configuration.FileNamePattern
    $files = @()

    try {
        foreach ($rootEntry in @($configuration.Roots)) {
            $root = [IO.Path]::GetFullPath((Get-ConfigurizerExpandedPath -Path ([string]$rootEntry)))
            if ($root.TrimEnd('\') -eq [IO.Path]::GetPathRoot($root).TrimEnd('\')) {
                throw 'A cleanup root cannot be a drive root: ' + $root
            }
            if (Test-Path -LiteralPath $root -PathType Container) {
                $files += Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
                    $_.BaseName -like $pattern -and $_.Extension.ToLowerInvariant() -in $extensions
                }
            }
        }
    }
    catch {
        return New-ConfigurizerResult -Operation 'BitLockerDocumentCleanup' -Item 'Cleanup scope' -Status 'Failed' -Message $_.Exception.Message
    }

    if ($files.Count -eq 0) {
        return New-ConfigurizerResult -Operation 'BitLockerDocumentCleanup' -Item 'Recovery documents' -Status 'Compliant' -Message 'No matching files were found.'
    }

    foreach ($file in $files) {
        $fullName = $file.FullName
        if ($script:ExecutionMode -eq 'Audit') {
            New-ConfigurizerResult -Operation 'BitLockerDocumentCleanup' -Item $fullName -Status 'NonCompliant' -Message 'Delete the matching recovery document.'
        }
        elseif ($script:RootCmdlet.ShouldProcess($fullName, 'Delete the matching recovery document.')) {
            try {
                Remove-Item -LiteralPath $fullName -Force
                New-ConfigurizerResult -Operation 'BitLockerDocumentCleanup' -Item $fullName -Status 'Changed' -Message 'The matching recovery document was deleted.'
            }
            catch {
                New-ConfigurizerResult -Operation 'BitLockerDocumentCleanup' -Item $fullName -Status 'Failed' -Message $_.Exception.Message
            }
        }
        else {
            New-ConfigurizerResult -Operation 'BitLockerDocumentCleanup' -Item $fullName -Status 'WouldChange' -Message 'WhatIf: Delete the matching recovery document.'
        }
    }
}
#endregion # BitLocker Operations #

#region ### Bloatware Operations ###
function Get-ConfigurizerAppxMatches {
    param (
        [Parameter(Mandatory = $true)][string]$Pattern,
        [string[]]$Exclusions = @()
    )

    $savedWhatIfPreference = $script:WhatIfPreference
    try {
        $script:WhatIfPreference = $false
        Import-Module Appx -ErrorAction SilentlyContinue | Out-Null
    }
    finally {
        $script:WhatIfPreference = $savedWhatIfPreference
    }

    $installed = if (Test-ConfigurizerAdministrator) {
        @(Get-AppxPackage -AllUsers -Name $Pattern -ErrorAction SilentlyContinue)
    }
    else {
        @(Get-AppxPackage -Name $Pattern -ErrorAction SilentlyContinue)
    }
    $provisioned = if (Test-ConfigurizerAdministrator) {
        @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Pattern })
    }
    else {
        @()
    }

    $installed = @($installed)
    $provisioned = @($provisioned)

    foreach ($exclude in $Exclusions) {
        $installed = @($installed | Where-Object { $_.Name -notlike $exclude })
        $provisioned = @($provisioned | Where-Object { $_.DisplayName -notlike $exclude })
    }
    return [pscustomobject]@{
        Installed = $installed
        Provisioned = $provisioned
        Count = $installed.Count + $provisioned.Count
    }
}

function Remove-ConfigurizerAppxMatches {
    param (
        [Parameter(Mandatory = $true)][string]$Pattern,
        [string[]]$Exclusions = @()
    )

    $matches = Get-ConfigurizerAppxMatches -Pattern $Pattern -Exclusions $Exclusions
    foreach ($package in @($matches.Installed)) {
        if (Test-ConfigurizerAdministrator) {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
        }
        else {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
        }
    }
    foreach ($package in @($matches.Provisioned)) {
        Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
    }
}

function Invoke-ConfigurizerAppxRemoval {
    param (
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string[]]$Patterns,
        [string[]]$Exclusions = @()
    )

    foreach ($patternEntry in $Patterns) {
        $pattern = [string]$patternEntry
        Invoke-ConfigurizerDesiredState -Operation $Operation -Item $pattern -Target $pattern -Action 'Remove matching installed and provisioned Appx packages.' -Test {
            (Get-ConfigurizerAppxMatches -Pattern $pattern -Exclusions $Exclusions).Count -eq 0
        } -Set {
            Remove-ConfigurizerAppxMatches -Pattern $pattern -Exclusions $Exclusions
        }
    }
}

function Split-ConfigurizerCommandLine {
    param ([Parameter(Mandatory = $true)][string]$CommandLine)

    if ($CommandLine -match '^\s*"([^"]+\.exe)"\s*(.*)$') {
        return [pscustomobject]@{ FilePath = $matches[1]; Arguments = $matches[2] }
    }
    if ($CommandLine -match '^\s*([^\s]+\.exe)\s*(.*)$') {
        return [pscustomobject]@{ FilePath = $matches[1]; Arguments = $matches[2] }
    }
    throw 'Could not safely parse uninstall command: ' + $CommandLine
}

function Uninstall-ConfigurizerProgram {
    param (
        [Parameter(Mandatory = $true)]$Entry,
        [hashtable]$SilentOverrides
    )

    if ($Entry.KeyName -match '^\{[0-9A-Fa-f-]{36}\}$') {
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $Entry.KeyName, '/qn', '/norestart') -Wait -PassThru -WindowStyle Hidden
    }
    else {
        $commandLine = if (-not [string]::IsNullOrWhiteSpace($Entry.QuietUninstallString)) { $Entry.QuietUninstallString } else { $Entry.UninstallString }
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            throw 'No uninstall command is registered for ' + $Entry.DisplayName + '.'
        }
        $command = Split-ConfigurizerCommandLine -CommandLine $commandLine
        $arguments = [string]$command.Arguments
        if ($SilentOverrides.ContainsKey($Entry.DisplayName)) {
            $arguments = [string]$SilentOverrides[$Entry.DisplayName]
        }
        elseif ($command.FilePath -match '(?i)msiexec\.exe$') {
            $arguments = $arguments -replace '(?i)/I', '/X'
            if ($arguments -notmatch '(?i)/q') {
                $arguments += ' /qn /norestart'
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($Entry.QuietUninstallString)) {
            throw 'No verified silent uninstall arguments are configured for ' + $Entry.DisplayName + '.'
        }
        $process = Start-Process -FilePath $command.FilePath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    }
    if ($process.ExitCode -notin @(0, 1605, 1614, 1641, 3010)) {
        throw 'Uninstaller exited with code ' + [string]$process.ExitCode + '.'
    }
    if ($process.ExitCode -in @(1641, 3010)) {
        $script:RestartRequired = $true
    }
}

function Invoke-ConfigurizerWin32BloatwareRemoval {
    param (
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string[]]$Patterns,
        [hashtable]$SilentOverrides = @{}
    )

    $entries = @(Get-ConfigurizerUninstallEntries)
    $matches = @()
    foreach ($pattern in $Patterns) {
        $matches += @($entries | Where-Object { $_.DisplayName -like ('*' + $pattern + '*') })
    }
    $matches = @($matches | Sort-Object KeyPath -Unique)

    if ($matches.Count -eq 0) {
        return New-ConfigurizerResult -Operation $Operation -Item 'Win32 applications' -Status 'Compliant' -Message 'No matching applications were found.'
    }

    foreach ($entry in $matches) {
        $entryCopy = $entry
        Invoke-ConfigurizerDesiredState -Operation $Operation -Item $entry.DisplayName -Target $entry.DisplayName -Action 'Silently uninstall the matching application.' -Test {
            -not (@(Get-ConfigurizerUninstallEntries | Where-Object { $_.KeyPath -eq $entryCopy.KeyPath }).Count -gt 0)
        } -Set {
            Uninstall-ConfigurizerProgram -Entry $entryCopy -SilentOverrides $SilentOverrides
        }
    }
}

function Invoke-ConfigurizerWindowsBloatware {
    Invoke-ConfigurizerAppxRemoval -Operation 'WindowsBloatware' -Patterns @($script:Specification.WindowsAppxPatterns)
}

function Invoke-ConfigurizerManufacturerBloatware {
    $manufacturer = Get-ConfigurizerManufacturer
    if ($manufacturer -eq 'Other') {
        return New-ConfigurizerResult -Operation 'ManufacturerBloatware' -Item 'Manufacturer detection' -Status 'Skipped' -Message 'No supported manufacturer was detected.'
    }
    $configuration = $script:Specification.ManufacturerBloatware[$manufacturer]
    $results = @()
    if (@($configuration.Win32Patterns).Count -gt 0) {
        $results += Invoke-ConfigurizerWin32BloatwareRemoval -Operation 'ManufacturerBloatware' -Patterns @($configuration.Win32Patterns) -SilentOverrides $configuration.SilentOverrides
    }
    $exclusions = if ($configuration.ContainsKey('AppxExclusions')) { @($configuration.AppxExclusions) } else { @() }
    $results += Invoke-ConfigurizerAppxRemoval -Operation 'ManufacturerBloatware' -Patterns @($configuration.AppxPatterns) -Exclusions $exclusions
    return $results
}
#endregion # Bloatware Operations #

#region ### Application Deployment Operations ###
function Invoke-ConfigurizerApplications {
    $results = @()
    $winget = Get-ConfigurizerWinget
    if ([string]::IsNullOrWhiteSpace($winget)) {
        $status = if ($script:ExecutionMode -eq 'Audit') { 'NonCompliant' } elseif ($script:WhatIfPreference) { 'WouldChange' } else { 'Failed' }
        $results += New-ConfigurizerResult -Operation 'Applications' -Item 'winget' -Status $status -Message 'winget.exe is unavailable. Install or repair Microsoft App Installer.'
        if ($script:ExecutionMode -eq 'Apply' -and -not $script:WhatIfPreference) {
            return $results
        }
    }
    else {
        $results += New-ConfigurizerResult -Operation 'Applications' -Item 'winget' -Status 'Compliant' -Message ('Available at ' + $winget)
    }

    foreach ($package in @($script:Specification.WingetPackages)) {
        $results += Install-ConfigurizerWingetPackage -Operation 'Applications' -Package $package
    }
    return $results
}

function Test-ConfigurizerMicrosoft365Installed {
    $productId = [string]$script:Specification.Microsoft365.ProductId
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    )
    foreach ($path in $paths) {
        $configuration = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        if ($null -ne $configuration -and [string]$configuration.ProductReleaseIds -match [regex]::Escape($productId)) {
            return $true
        }
    }
    return $false
}

function Test-ConfigurizerMicrosoftSignature {
    param ([Parameter(Mandatory = $true)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    return $signature.Status -eq 'Valid' -and $null -ne $signature.SignerCertificate -and $signature.SignerCertificate.Subject -match 'O=Microsoft Corporation'
}

function Get-ConfigurizerOfficeDeploymentTool {
    $configuration = $script:Specification.Microsoft365
    $payloadRoot = Join-Path -Path ([string]$script:Specification.DataRoot) -ChildPath 'Payloads\Office'
    if (-not (Test-Path -LiteralPath $payloadRoot -PathType Container)) {
        New-Item -Path $payloadRoot -ItemType Directory -Force | Out-Null
    }

    $packagePath = Join-Path -Path $payloadRoot -ChildPath ('officedeploymenttool_' + [string]$configuration.OdtVersion + '.exe')
    $packageValid = (Test-Path -LiteralPath $packagePath -PathType Leaf) -and (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -eq [string]$configuration.OdtSha256 -and (Test-ConfigurizerMicrosoftSignature -Path $packagePath)
    if (-not $packageValid) {
        Invoke-WebRequest -Uri ([string]$configuration.OdtUrl) -OutFile $packagePath -UseBasicParsing
    }

    $actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$configuration.OdtSha256) {
        throw 'Office Deployment Tool hash mismatch. Expected ' + [string]$configuration.OdtSha256 + ' but received ' + $actualHash + '.'
    }
    if (-not (Test-ConfigurizerMicrosoftSignature -Path $packagePath)) {
        throw 'Office Deployment Tool does not have a valid Microsoft Authenticode signature.'
    }

    $extractRoot = Join-Path -Path $payloadRoot -ChildPath ('ODT-' + [string]$configuration.OdtVersion)
    $setupPath = Join-Path -Path $extractRoot -ChildPath 'setup.exe'
    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $extractRoot -PathType Container)) {
            New-Item -Path $extractRoot -ItemType Directory -Force | Out-Null
        }
        $arguments = @('/quiet', ('/extract:"' + $extractRoot + '"'))
        $process = Start-Process -FilePath $packagePath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            throw 'Office Deployment Tool extraction exited with code ' + [string]$process.ExitCode + '.'
        }
    }
    if (-not (Test-ConfigurizerMicrosoftSignature -Path $setupPath)) {
        throw 'Extracted Office setup.exe does not have a valid Microsoft Authenticode signature.'
    }
    return $setupPath
}

function Install-ConfigurizerMicrosoft365 {
    return Invoke-ConfigurizerDesiredState -Operation 'Microsoft365' -Item 'Microsoft 365 Apps for enterprise' -Target 'Microsoft 365' -Action 'Install Microsoft 365 Apps for enterprise without Visio or Project.' -Test {
        Test-ConfigurizerMicrosoft365Installed
    } -Set {
        $setupPath = Get-ConfigurizerOfficeDeploymentTool
        $configurationPath = Join-Path -Path ([string]$script:Specification.DataRoot) -ChildPath 'OfficeConfiguration.xml'
        Set-Content -LiteralPath $configurationPath -Value $script:OfficeConfigurationXml -Encoding UTF8
        $quotedConfigurationPath = '"' + $configurationPath + '"'
        $process = Start-Process -FilePath $setupPath -ArgumentList @('/configure', $quotedConfigurationPath) -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            throw 'Office setup exited with code ' + [string]$process.ExitCode + '.'
        }
    }
}
#endregion # Application Deployment Operations #

#region ### Windows Update Operations ###
function Get-ConfigurizerAvailableWindowsUpdates {
    $session = New-Object -ComObject 'Microsoft.Update.Session'
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $updates = @()
    for ($index = 0; $index -lt $result.Updates.Count; $index++) {
        $updates += $result.Updates.Item($index)
    }
    return $updates
}

function Invoke-ConfigurizerWindowsUpdates {
    try {
        $updates = @(Get-ConfigurizerAvailableWindowsUpdates)
    }
    catch {
        return New-ConfigurizerResult -Operation 'WindowsUpdates' -Item 'Update search' -Status 'Failed' -Message $_.Exception.Message
    }

    if ($updates.Count -eq 0) {
        return New-ConfigurizerResult -Operation 'WindowsUpdates' -Item 'Software updates' -Status 'Compliant' -Message 'No applicable software updates were found.'
    }

    if ($script:ExecutionMode -eq 'Audit') {
        foreach ($update in $updates) {
            New-ConfigurizerResult -Operation 'WindowsUpdates' -Item ([string]$update.Title) -Status 'NonCompliant' -Message 'An applicable Windows update is available.'
        }
        return
    }

    if (-not $script:RootCmdlet.ShouldProcess('Windows Update', ('Download and install ' + [string]$updates.Count + ' applicable update(s).'))) {
        return New-ConfigurizerResult -Operation 'WindowsUpdates' -Item 'Software updates' -Status 'WouldChange' -Message ('WhatIf: Install ' + [string]$updates.Count + ' applicable update(s).')
    }

    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session'
        $collection = New-Object -ComObject 'Microsoft.Update.UpdateColl'
        foreach ($update in $updates) {
            if (-not $update.EulaAccepted) {
                $update.AcceptEula()
            }
            [void]$collection.Add($update)
        }

        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $collection
        $downloadResult = $downloader.Download()
        if ([int]$downloadResult.ResultCode -notin @(2, 3)) {
            throw 'Windows Update download returned result code ' + [string]$downloadResult.ResultCode + '.'
        }

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $collection
        $installResult = $installer.Install()
        if ($installResult.RebootRequired) {
            $script:RestartRequired = $true
        }

        for ($index = 0; $index -lt $collection.Count; $index++) {
            $updateResult = $installResult.GetUpdateResult($index)
            $status = if ([int]$updateResult.ResultCode -in @(2, 3)) { 'Changed' } else { 'Failed' }
            New-ConfigurizerResult -Operation 'WindowsUpdates' -Item ([string]$collection.Item($index).Title) -Status $status -Message ('Installation result code: ' + [string]$updateResult.ResultCode + '.') -RestartRequired ([bool]$installResult.RebootRequired)
        }
    }
    catch {
        New-ConfigurizerResult -Operation 'WindowsUpdates' -Item 'Installation' -Status 'Failed' -Message $_.Exception.Message
    }
}
#endregion # Windows Update Operations #

#region ### Manufacturer Update Operations ###
function Install-ConfigurizerManufacturerTool {
    param (
        [Parameter(Mandatory = $true)][string]$Manufacturer,
        [Parameter(Mandatory = $true)]$Configuration
    )

    $name = if ($Manufacturer -eq 'Dell') { 'Dell Command Update' } else { 'HP Image Assistant' }
    $id = [string]$Configuration.WingetId
    $candidates = @($Configuration.CliCandidates)
    return Invoke-ConfigurizerDesiredState -Operation 'ManufacturerUpdates' -Item $name -Target $id -Action ('Install ' + $name + ' with winget when it is missing.') -Test {
        -not [string]::IsNullOrWhiteSpace((Find-ConfigurizerFile -Candidates $candidates))
    } -Set {
        $winget = Get-ConfigurizerWinget
        if ([string]::IsNullOrWhiteSpace($winget)) {
            throw 'winget.exe is unavailable. Install or repair Microsoft App Installer first.'
        }
        $output = & $winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw 'winget exited with code ' + [string]$LASTEXITCODE + ': ' + ($output -join ' ')
        }
    }
}

function Invoke-ConfigurizerDellUpdates {
    $configuration = $script:Specification.ManufacturerUpdates.Dell
    $cli = Find-ConfigurizerFile -Candidates @($configuration.CliCandidates)

    if ($script:ExecutionMode -eq 'Audit') {
        if ([string]::IsNullOrWhiteSpace($cli)) {
            return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Dell Command Update' -Status 'NonCompliant' -Message 'Dell Command Update is not installed.'
        }
        return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Dell Command Update' -Status 'NotAuditable' -Message ('Tool is available at ' + $cli + '. Use -InstallManufacturerUpdates to scan and apply critical and recommended updates.')
    }

    $results = @()
    if ([string]::IsNullOrWhiteSpace($cli)) {
        $results += Install-ConfigurizerManufacturerTool -Manufacturer 'Dell' -Configuration $configuration
        if ($script:WhatIfPreference) {
            $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Dell updates' -Status 'WouldChange' -Message 'WhatIf: Run Dell Command Update after installation.'
            return $results
        }
        $cli = Find-ConfigurizerFile -Candidates @($configuration.CliCandidates)
        if ([string]::IsNullOrWhiteSpace($cli)) {
            $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Dell Command Update' -Status 'Failed' -Message 'Dell Command Update CLI was not found after installation.'
            return $results
        }
    }

    if (-not $script:RootCmdlet.ShouldProcess('Dell Command Update', 'Install critical and recommended Dell updates.')) {
        $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Dell updates' -Status 'WouldChange' -Message 'WhatIf: Install critical and recommended Dell updates.'
        return $results
    }

    try {
        $logRoot = Join-Path -Path ([string]$script:Specification.DataRoot) -ChildPath 'ManufacturerUpdates\Dell'
        if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) {
            New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
        }
        $configurationOutput = & $cli /configure '-autoSuspendBitLocker=enable' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw 'Dell Command Update configuration failed: ' + ($configurationOutput -join ' ')
        }
        $logPath = Join-Path -Path $logRoot -ChildPath ('DCU-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
        $output = & $cli /applyUpdates '-updateSeverity=critical,recommended' '-reboot=disable' ('-outputLog=' + $logPath) 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -notin @(0, 1, 500)) {
            throw 'Dell Command Update exited with code ' + [string]$exitCode + ': ' + ($output -join ' ')
        }
        if ($exitCode -eq 1) {
            $script:RestartRequired = $true
        }
        $message = if ($exitCode -eq 500) { 'No applicable Dell updates were found.' } else { 'Dell Command Update completed.' }
        $status = if ($exitCode -eq 500) { 'Compliant' } else { 'Changed' }
        $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Dell updates' -Status $status -Message $message -RestartRequired ($exitCode -eq 1)
    }
    catch {
        $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Dell updates' -Status 'Failed' -Message $_.Exception.Message
    }
    return $results
}

function Invoke-ConfigurizerHPUpdates {
    $configuration = $script:Specification.ManufacturerUpdates.HP
    $cli = Find-ConfigurizerFile -Candidates @($configuration.CliCandidates)

    if ($script:ExecutionMode -eq 'Audit') {
        if ([string]::IsNullOrWhiteSpace($cli)) {
            return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'HP Image Assistant' -Status 'NonCompliant' -Message 'HP Image Assistant is not installed.'
        }
        return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'HP Image Assistant' -Status 'NotAuditable' -Message ('Tool is available at ' + $cli + '. Use -InstallManufacturerUpdates to analyze and install recommendations.')
    }

    $results = @()
    if ([string]::IsNullOrWhiteSpace($cli)) {
        $results += Install-ConfigurizerManufacturerTool -Manufacturer 'HP' -Configuration $configuration
        if ($script:WhatIfPreference) {
            $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'HP updates' -Status 'WouldChange' -Message 'WhatIf: Run HP Image Assistant after installation.'
            return $results
        }
        $cli = Find-ConfigurizerFile -Candidates @($configuration.CliCandidates)
        if ([string]::IsNullOrWhiteSpace($cli)) {
            $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'HP Image Assistant' -Status 'Failed' -Message 'HP Image Assistant was not found after installation.'
            return $results
        }
    }

    if (-not $script:RootCmdlet.ShouldProcess('HP Image Assistant', 'Analyze and install BIOS, driver, firmware, and accessory recommendations.')) {
        $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'HP updates' -Status 'WouldChange' -Message 'WhatIf: Analyze and install HP recommendations.'
        return $results
    }

    try {
        $reportRoot = Join-Path -Path ([string]$script:Specification.DataRoot) -ChildPath ('ManufacturerUpdates\HP\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -Path $reportRoot -ItemType Directory -Force | Out-Null
        $arguments = '/Operation:Analyze /Category:BIOS,Drivers,Firmware,Accessories /Selection:All /Action:Install /Silent /ReportFolder:"' + $reportRoot + '"'
        $process = Start-Process -FilePath $cli -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -notin @(0, 256, 257, 3010)) {
            throw 'HP Image Assistant exited with code ' + [string]$process.ExitCode + '.'
        }
        if ($process.ExitCode -eq 3010) {
            $script:RestartRequired = $true
        }
        $message = if ($process.ExitCode -in @(256, 257)) { 'No applicable HP recommendations were found.' } else { 'HP Image Assistant completed.' }
        $status = if ($process.ExitCode -in @(256, 257)) { 'Compliant' } else { 'Changed' }
        $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'HP updates' -Status $status -Message $message -RestartRequired ($process.ExitCode -eq 3010)
    }
    catch {
        $results += New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'HP updates' -Status 'Failed' -Message $_.Exception.Message
    }
    return $results
}

function Invoke-ConfigurizerLenovoUpdates {
    $moduleName = [string]$script:Specification.ManufacturerUpdates.Lenovo.ModuleName
    $module = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1

    if ($script:ExecutionMode -eq 'Audit') {
        if ($null -eq $module) {
            return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item $moduleName -Status 'NonCompliant' -Message 'The Lenovo update module is not installed.'
        }
        return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item $moduleName -Status 'NotAuditable' -Message ('Module version ' + [string]$module.Version + ' is installed. Use -InstallManufacturerUpdates to scan and install updates.')
    }

    if ($script:WhatIfPreference) {
        return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Lenovo updates' -Status 'WouldChange' -Message 'WhatIf: Install LSUClient, scan, and install Lenovo updates.'
    }
    if (-not $script:RootCmdlet.ShouldProcess('Lenovo System Update', 'Install LSUClient and apply Lenovo updates.')) {
        return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Lenovo updates' -Status 'WouldChange' -Message 'WhatIf: Install LSUClient and apply Lenovo updates.'
    }

    try {
        if ($null -eq $module) {
            Install-PackageProvider -Name 'NuGet' -Force -Scope AllUsers | Out-Null
            Install-Module -Name $moduleName -Force -Scope AllUsers -AllowClobber
        }
        Import-Module -Name $moduleName -Force
        $updates = @(Get-LSUpdate)
        if ($updates.Count -eq 0) {
            return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Lenovo updates' -Status 'Compliant' -Message 'No applicable Lenovo updates were found.'
        }
        $updates | Install-LSUpdate -Verbose
        return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Lenovo updates' -Status 'Changed' -Message ([string]$updates.Count + ' Lenovo update(s) were submitted for installation.')
    }
    catch {
        return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Lenovo updates' -Status 'Failed' -Message $_.Exception.Message
    }
}

function Invoke-ConfigurizerManufacturerUpdates {
    $manufacturer = Get-ConfigurizerManufacturer
    switch ($manufacturer) {
        'Dell' { return Invoke-ConfigurizerDellUpdates }
        'HP' { return Invoke-ConfigurizerHPUpdates }
        'Lenovo' { return Invoke-ConfigurizerLenovoUpdates }
        default { return New-ConfigurizerResult -Operation 'ManufacturerUpdates' -Item 'Manufacturer detection' -Status 'Skipped' -Message 'No supported manufacturer was detected.' }
    }
}
#endregion # Manufacturer Update Operations #

#region ### Operation Catalog and Dispatch ###
$operationCatalog = [ordered]@{
    ConfigurePower = @{ Name = 'Power'; Handler = { Invoke-ConfigurizerPower }; IncludedInAll = $true }
    ConfigureContentDelivery = @{ Name = 'ContentDelivery'; Handler = { Invoke-ConfigurizerContentDelivery }; IncludedInAll = $true }
    ConfigureTeamsQoS = @{ Name = 'TeamsQoS'; Handler = { Invoke-ConfigurizerTeamsQoS }; IncludedInAll = $true }
    ConfigureUAC = @{ Name = 'UAC'; Handler = { Invoke-ConfigurizerUAC }; IncludedInAll = $true }
    ConfigureTime = @{ Name = 'Time'; Handler = { Invoke-ConfigurizerTime }; IncludedInAll = $true }
    ConfigureTaskbar = @{ Name = 'Taskbar'; Handler = { Invoke-ConfigurizerTaskbar }; IncludedInAll = $true }
    DarkMode = @{ Name = 'WindowsTheme'; Handler = { if ($DarkMode) { Invoke-ConfigurizerTheme -Mode 'Dark' } else { Invoke-ConfigurizerTheme -Mode 'Observe' } }; IncludedInAll = $false; IncludedInDefaultAudit = $true }
    LightMode = @{ Name = 'WindowsTheme'; Handler = { Invoke-ConfigurizerTheme -Mode 'Light' }; IncludedInAll = $false; IncludedInDefaultAudit = $false }
    ConfigureTaskbarPins = @{ Name = 'TaskbarPins'; Handler = { Invoke-ConfigurizerTaskbarPins }; IncludedInAll = $true }
    ConfigureOfficeShortcuts = @{ Name = 'OfficeShortcuts'; Handler = { Invoke-ConfigurizerOfficeShortcuts }; IncludedInAll = $true }
    ConfigureBitLocker = @{ Name = 'BitLocker'; Handler = { Invoke-ConfigurizerBitLocker }; IncludedInAll = $true }
    RemoveWindowsBloatware = @{ Name = 'WindowsBloatware'; Handler = { Invoke-ConfigurizerWindowsBloatware }; IncludedInAll = $true }
    RemoveManufacturerBloatware = @{ Name = 'ManufacturerBloatware'; Handler = { Invoke-ConfigurizerManufacturerBloatware }; IncludedInAll = $true }
    InstallApps = @{ Name = 'Applications'; Handler = { Invoke-ConfigurizerApplications }; IncludedInAll = $true }
    InstallMicrosoft365 = @{ Name = 'Microsoft365'; Handler = { Install-ConfigurizerMicrosoft365 }; IncludedInAll = $true }
    InstallWindowsUpdates = @{ Name = 'WindowsUpdates'; Handler = { Invoke-ConfigurizerWindowsUpdates }; IncludedInAll = $true }
    InstallManufacturerUpdates = @{ Name = 'ManufacturerUpdates'; Handler = { Invoke-ConfigurizerManufacturerUpdates }; IncludedInAll = $true }
    CleanupBitLockerDocuments = @{ Name = 'BitLockerDocumentCleanup'; Handler = { Invoke-ConfigurizerBitLockerDocumentCleanup }; IncludedInAll = $false }
}

function Get-ConfigurizerSelectedOperations {
    $selected = @()
    foreach ($parameterName in $operationCatalog.Keys) {
        $value = Get-Variable -Name $parameterName -ValueOnly
        if ([bool]$value) {
            $selected += $parameterName
        }
    }

    if ($All) {
        $selected += @($operationCatalog.Keys | Where-Object { [bool]$operationCatalog[$_].IncludedInAll })
    }
    $selected = @($operationCatalog.Keys | Where-Object { $_ -in $selected })

    if ($selected.Count -eq 0) {
        return @($operationCatalog.Keys | Where-Object {
            -not $operationCatalog[$_].ContainsKey('IncludedInDefaultAudit') -or [bool]$operationCatalog[$_].IncludedInDefaultAudit
        })
    }
    return $selected
}
#endregion # Operation Catalog and Dispatch #

#region ### Entry Point ###
if ($DarkMode -and $LightMode) {
    Write-Error 'DarkMode and LightMode are mutually exclusive. Select only one theme.'
    exit 1
}

if ($ListOperations) {
    foreach ($parameterName in $operationCatalog.Keys) {
        [pscustomobject]@{
            Parameter = '-' + $parameterName
            Operation = [string]$operationCatalog[$parameterName].Name
            IncludedInAll = [bool]$operationCatalog[$parameterName].IncludedInAll
        }
    }
    return
}

$explicitAction = $All
foreach ($parameterName in $operationCatalog.Keys) {
    if ([bool](Get-Variable -Name $parameterName -ValueOnly)) {
        $explicitAction = $true
        break
    }
}
$script:ExecutionMode = if ($Audit -or -not $explicitAction) { 'Audit' } else { 'Apply' }
$selectedOperations = @(Get-ConfigurizerSelectedOperations)

if ($script:ExecutionMode -eq 'Apply' -and -not $script:WhatIfPreference -and -not (Test-ConfigurizerAdministrator)) {
    Write-Error 'Apply operations require an elevated Windows PowerShell session.'
    exit 1
}

Write-Host ('Configurizer ' + [string]$script:Specification.Version)
Write-Host ('Mode: ' + $script:ExecutionMode)
Write-Host ('Operations: ' + (($selectedOperations | ForEach-Object { [string]$operationCatalog[$_].Name }) -join ', '))
if ($All) {
    Write-Host 'Note: -All excludes theme selection and BitLocker document cleanup.'
}
Write-Host ''

$allResults = @()
foreach ($parameterName in $selectedOperations) {
    $operation = $operationCatalog[$parameterName]
    try {
        $results = @(& $operation.Handler)
        if ($results.Count -eq 0) {
            $allResults += New-ConfigurizerResult -Operation ([string]$operation.Name) -Item 'Operation' -Status 'Failed' -Message 'The operation returned no results.'
        }
        else {
            $allResults += $results
        }
    }
    catch {
        $allResults += New-ConfigurizerResult -Operation ([string]$operation.Name) -Item 'Operation' -Status 'Failed' -Message $_.Exception.Message
    }
}

$actualRestartRequired = [bool]$script:RestartRequired
$potentialRestartRequired = @($allResults | Where-Object {
        $_.RestartRequired -and $_.Status -in @('NonCompliant', 'WouldChange')
    }).Count -gt 0

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    try {
        $expandedReportPath = Get-ConfigurizerExpandedPath -Path $ReportPath
        if ([IO.Path]::GetExtension($expandedReportPath) -ne '.json') {
            if (-not (Test-Path -LiteralPath $expandedReportPath -PathType Container)) {
                New-Item -Path $expandedReportPath -ItemType Directory -Force | Out-Null
            }
            $expandedReportPath = Join-Path -Path $expandedReportPath -ChildPath ('Configurizer-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
        }
        $reportParent = Split-Path -Path $expandedReportPath -Parent
        if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) {
            New-Item -Path $reportParent -ItemType Directory -Force | Out-Null
        }
        if ($script:WhatIfPreference) {
            Write-Host ('WhatIf: Would write JSON report to ' + $expandedReportPath + '.')
        }
        else {
            $report = [ordered]@{
                Product = 'Configurizer'
                Version = [string]$script:Specification.Version
                Mode = $script:ExecutionMode
                ComputerName = $env:COMPUTERNAME
                UserName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
                Timestamp = (Get-Date).ToString('o')
                RestartRequired = $actualRestartRequired
                PotentialRestartRequired = $potentialRestartRequired
                Results = $allResults
            }
            $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $expandedReportPath -Encoding UTF8
            Write-Host ('Report: ' + $expandedReportPath)
        }
    }
    catch {
        $allResults += New-ConfigurizerResult -Operation 'Reporting' -Item $ReportPath -Status 'Failed' -Message $_.Exception.Message
    }
}

$restartColumnName = if ($script:ExecutionMode -eq 'Audit') {
    'RestartIfRemediated'
}
elseif ($script:WhatIfPreference) {
    'RestartIfApplied'
}
else {
    'RestartRequired'
}
$allResults |
    Select-Object Operation, Status, @{n = $restartColumnName; e = { $_.RestartRequired } }, Item, Message |
    Format-Table -AutoSize -Wrap |
    Out-Host
Write-Host ''
Write-Host 'Summary'
$allResults | Group-Object Status | Sort-Object Name | Select-Object @{n = 'Status'; e = { $_.Name } }, Count | Format-Table -AutoSize | Out-Host
if ($actualRestartRequired) {
    Write-Host 'Restart required by changes made: Yes' -ForegroundColor Yellow
}
elseif ($potentialRestartRequired -and $script:ExecutionMode -eq 'Audit') {
    Write-Host 'Restart if noncompliance is remediated: Yes' -ForegroundColor Yellow
}
elseif ($potentialRestartRequired) {
    Write-Host 'Restart if proposed changes are applied: Yes' -ForegroundColor Yellow
}
elseif ($script:ExecutionMode -eq 'Audit') {
    Write-Host 'Restart if noncompliance is remediated: No'
}
else {
    Write-Host 'Restart required by changes made: No'
}

if ($PassThru) {
    Write-Output $allResults
}

$failedCount = @($allResults | Where-Object { $_.Status -eq 'Failed' }).Count
$nonCompliantCount = @($allResults | Where-Object { $_.Status -eq 'NonCompliant' }).Count
if ($failedCount -gt 0) {
    exit 1
}
if ($script:ExecutionMode -eq 'Audit' -and $nonCompliantCount -gt 0) {
    exit 2
}
exit 0
#endregion # Entry Point #

# CHANGELOG
# 0.1.1 - 07.18.2026 - Fixed PowerShell 5.1 parsing, restart semantics, and narrow-host table layout.
# 0.1.0 - 07.18.2026 - Initial release.
