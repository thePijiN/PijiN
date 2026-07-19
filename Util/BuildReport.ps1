<#
Author  : AlexanderDeMey@outlook.com
Script  : BuildReport.ps1
Version : 0.0.1
Summary : Client-aware PC build QA report.
          Pass -Client <name> for full compliance checking.
          Pass -Log to save output under $env:LOCALAPPDATA\PijiN\logs.
          Pass -NoEscrow to skip the default BitLocker escrow attempt.
#>
param(
    [string]$Client   = "",
    [string]$Location = "",
    [switch]$Log,
    [switch]$NoEscrow
)
$ScriptVersion = "0.0.1"
$workingDir    = Join-Path $env:LOCALAPPDATA "PijiN"

### CLIENT CONFIGURATIONS ###
$ClientConfigs = @{
    "Default" = [PSCustomObject]@{
        DisplayName        = "Generic (Default)"
        ExpectedDomainType = $null
        ExpectedDomainName = $null
        ExpectedTimezone   = $null
        RequireLocalAdmin  = $null
        RequireHello       = $null
        RequiredAgents     = @("Ninja","CrowdStrike","CloudRadial","Pia","Huntress", "BlackPoint")
        PowerBatteryScreen = $null
        PowerBatterySleep  = $null
        PowerACScreen      = $null
        PowerACSleep       = $null
        ExpectedApps       = @()
        ExpectedWiFi       = @()
        ExpectedPrinters   = @()
        ExpectedShortcuts  = @()
        ExpectedBookmarks  = @()
        ExpectedExtensions = @()
    }

    # Exhaustive reference showing every supported client and location option.
    "SampleCorp" = [PSCustomObject]@{
        DisplayName        = "Sample Corporation Inc."
        # Domain type: Entra, Local, or Hybrid.
        ExpectedDomainType = "Entra"
        ExpectedDomainName = "Sample Corporation"
        ExpectedTimezone   = "Eastern Standard Time"
        # Use $null for no preference.
        RequireLocalAdmin  = $false
        RequireHello       = $true
        # Supported agent names are handled by Test-AgentInstalled.
        RequiredAgents = @(
            "Ninja"
            "CrowdStrike"
            "CloudRadial"
            "Pia"
            "Huntress"
            "BlackPoint"
            "Ninite"
            "ActivTrack"
        )
        # Values are minutes. Use 0 for Never and $null for no preference.
        PowerBatteryScreen = 10
        PowerBatterySleep  = 30
        PowerACScreen      = $null # No preference 
        PowerACSleep       = 0     # Never
        # Application detection supports Path, Paths, UninstallName, and RegKey with optional RegName and Contains.
        ExpectedApps = @(
            [PSCustomObject]@{ Name = "7-Zip"; Path = "C:\Program Files\7-Zip\7z.exe" }
            [PSCustomObject]@{ Name = "ActivTrak Agent"; Path = "C:\Windows\SysWOW64\aamdata\atutil.exe" }
            [PSCustomObject]@{ Name = "Adobe Acrobat"; Paths = @(
                    "C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
                    "C:\Program Files (x86)\Adobe\Acrobat DC\Acrobat\Acrobat.exe") }
            [PSCustomObject]@{ Name = "Adobe Creative Cloud"; Path = "C:\Program Files\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe" }
            [PSCustomObject]@{ Name = "Advanced IP Scanner"; Path = "C:\Program Files (x86)\Advanced IP Scanner\advanced_ip_scanner.exe" }
            [PSCustomObject]@{ Name = "AutoCAD 2023"; Path = "C:\Program Files\Autodesk\AutoCAD 2023\acad.exe" }
            [PSCustomObject]@{ Name = "AutoCAD 2025"; Path = "C:\Program Files\Autodesk\AutoCAD 2025\acad.exe" }
            [PSCustomObject]@{ Name = "AutoCAD 2026"; Path = "C:\Program Files\Autodesk\AutoCAD 2026\acad.exe" }
            [PSCustomObject]@{ Name = "Autodesk Navisworks Freedom 2027"; Path = "C:\Program Files\Autodesk\Navisworks Freedom 2027\Roamer.exe" }
            [PSCustomObject]@{ Name = "Bitwarden"; Paths = @(
                    "C:\Program Files\Bitwarden\Bitwarden.exe"
                    "C:\Program Files (x86)\Bitwarden\Bitwarden.exe"
                    "$env:LOCALAPPDATA\Programs\Bitwarden\Bitwarden.exe"
                    "$env:LOCALAPPDATA\Packages\8bitSolutionsLLC.bitwardendesktop_h4e712dmw3xyy\LocalCache\Roaming\Bitwarden\Bitwarden.exe"
                    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Bitwarden.lnk") }
            [PSCustomObject]@{ Name = "Bluebeam Revu 21"; Path = "C:\Program Files\Bluebeam Software\Bluebeam Revu\21\Revu\Revu.exe" }
            [PSCustomObject]@{ Name = "Box"; Path = "C:\Program Files\Box\Box\Box.exe" }
            [PSCustomObject]@{ Name = "Citrix Workspace"; Path = "C:\Program Files (x86)\Citrix\ICA Client\SelfServicePlugin\SelfService.exe" }
            [PSCustomObject]@{ Name = "Claude"; Path = "C:\Program Files\WindowsApps\Claude_*\" }
            [PSCustomObject]@{ Name = "Crestron AirMedia"; Path = "C:\Program Files (x86)\Crestron\AirMediaV2\AirMedia\app-*\Airmedia.exe" }
            [PSCustomObject]@{ Name = "Dropbox"; Path = "C:\Program Files (x86)\Dropbox\Client\Dropbox.exe" }
            [PSCustomObject]@{ Name = "Duo Security"; Path = "C:\Program Files\Duo Security\WindowsLogon\" }
            [PSCustomObject]@{ Name = "Electrical Bid Manager"; Paths = @(
                    "\\Windsor-EBM\Vision\EBM3K\EBM3KSQL.EXE"
                    "C:\Users\Public\Desktop\EBM Network.lnk") }
            [PSCustomObject]@{ Name = "Enscape"; Paths = @("C:\Users\*\AppData\Local\Programs\Enscape\") }
            [PSCustomObject]@{ Name = "FileZilla"; Path = "C:\Program Files\FileZilla FTP Client\filezilla.exe" }
            [PSCustomObject]@{ Name = "Firefox"; Paths = @(
                    "C:\Program Files\Mozilla Firefox\firefox.exe"
                    "C:\Program Files\Mozilla Firefox\uninstall\helper.exe") }
            [PSCustomObject]@{ Name = "Foxit"; Path = "C:\Program Files\Foxit Software\Foxit PDF Editor\FoxitPDFEditor.exe" }
            [PSCustomObject]@{ Name = "GhostScript"; Path = "C:\Program Files\gs\gs*\bin\gswin64.exe" }
            [PSCustomObject]@{ Name = "Google Chrome"; Paths = @(
                    "C:\Program Files\Google\Chrome\Application\chrome.exe"
                    "C:\Users\*\AppData\Local\Google\Chrome\Application\chrome.exe") }
            [PSCustomObject]@{ Name = "Google Earth Pro"; Path = "C:\Program Files\Google\Google Earth Pro\client\googleearth.exe" }
            [PSCustomObject]@{ Name = "Kofax PDF"; Path = "C:\Program Files (x86)\Kofax\Power PDF-50\bin\PowerPDF.exe" }
            [PSCustomObject]@{ Name = "LawLogix Outlook Add-in"; UninstallName = "Outlook Integrator" }
            [PSCustomObject]@{ Name = "LawLogix Word Add-in"; UninstallName = "LawLogix Word" }
            [PSCustomObject]@{ Name = "Lumion"; Path = "C:\Program Files\Lumion 11.5\Lumion.exe" }
            [PSCustomObject]@{ Name = "Microsoft 365"; Path = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE" }
            [PSCustomObject]@{ Name = "Microsoft OneDrive"; Paths = @(
                    "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
                    "C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe"
                    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk") }
            [PSCustomObject]@{ Name = "Microsoft Project"; Paths = @(
                    "C:\Program Files\Microsoft Office\Office16\WINPROJ.EXE"
                    "C:\Program Files (x86)\Microsoft Office\Office16\WINPROJ.EXE"
                    "C:\Program Files\Microsoft Office\Office15\WINPROJ.EXE"
                    "C:\Program Files (x86)\Microsoft Office\Office15\WINPROJ.EXE"
                    "C:\Program Files\Microsoft Office\Office14\WINPROJ.EXE"
                    "C:\Program Files (x86)\Microsoft Office\Office14\WINPROJ.EXE"
                    "C:\Program Files\Microsoft Office\root\Office16\WINPROJ.EXE"
                    "C:\Program Files (x86)\Microsoft Office\root\Office16\WINPROJ.EXE") }
            [PSCustomObject]@{ Name = "Mimecast"; Paths = @(
                    "C:\Program Files\Mimecast"
                    "C:\Program Files (x86)\Mimecast") }
            [PSCustomObject]@{ Name = "Poly Studio"; Path = "C:\Program Files\Poly\Poly Studio\Poly Studio.exe" }
            [PSCustomObject]@{ Name = "PrinterLogic Client"; Path = "C:\Program Files (x86)\Printer Properties Pro\Printer Installer Client\PrinterInstallerClient.exe" }
            [PSCustomObject]@{ Name = "Procore Drive"; Paths = @(
                    "C:\Program Files (x86)\Procore Technologies\Procore Drive\app-*\Procore.Explorer.exe"
                    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Procore Drive.lnk") }
            [PSCustomObject]@{ Name = "Procore Extracts"; Path = "C:\Program Files (x86)\Procore Technologies\Procore Extracts\app-*\Procore.Ditto.exe" }
            [PSCustomObject]@{ Name = "Procore Imports"; Path = "C:\Program Files (x86)\Procore Technologies\Procore Imports\app-*\Imports.exe" }
            [PSCustomObject]@{ Name = "PuTTY"; Path = "C:\Program Files\PuTTY\putty.exe" }
            [PSCustomObject]@{ Name = "Revit 2023"; Path = "C:\Program Files\Autodesk\Revit 2023\revit.exe" }
            [PSCustomObject]@{ Name = "Revit 2024"; Path = "C:\Program Files\Autodesk\Revit 2024\Revit.exe" }
            [PSCustomObject]@{ Name = "Revit 2025"; Path = "C:\Program Files\Autodesk\Revit 2025\revit.exe" }
            [PSCustomObject]@{ Name = "Revit 2026"; Path = "C:\Program Files\Autodesk\Revit 2026\Revit.exe" }
            [PSCustomObject]@{ Name = "S&P Capital IQ Pro"; Paths = @(
                    "C:\Program Files\SP Global Market Intelligence\SP Capital IQ Office\SNL.Clients.Office.Host.exe"
                    "C:\Program Files\SP Global Market Intelligence\SP Capital IQ Office") }
            [PSCustomObject]@{ Name = "Sage 100 Contractor"; Path = "C:\Program Files (x86)\Sage\Sage 100 Contractor SQL\Sage.LogViewer.exe" }
            [PSCustomObject]@{ Name = "SketchUp 2024"; Path = "C:\Program Files\SketchUp\SketchUp 2024" }
            [PSCustomObject]@{ Name = "SonicWallNetExtender"; Paths = @(
                    "C:\Program Files (x86)\SonicWall"
                    "C:\Program Files\SonicWall") }
            [PSCustomObject]@{ Name = "Splashtop Business"; Path = "C:\Program Files (x86)\Splashtop\Splashtop Remote\Client for STB\strwinclt.exe" }
            [PSCustomObject]@{ Name = "Splashtop Streamer"; Path = "C:\Program Files (x86)\Splashtop\Splashtop Remote\Server\SRServer.exe" }
            [PSCustomObject]@{ Name = "UNIFI"; Path = "C:\Users\*\AppData\Local\Programs\UNIFI Labs\UNIFI" }
            [PSCustomObject]@{ Name = "Verizon OneTalk"; Path = "C:\Program Files (x86)\Verizon\One Talk\OneTalk.exe" }
            [PSCustomObject]@{ Name = "Vista Viewpoint"; Path = "C:\Program Files (x86)\Viewpoint Construction Software\Vista\bin\Viewpoint.Vista.Launcher.exe" }
            [PSCustomObject]@{ Name = "VLC Media Player"; Paths = @(
                    "C:\Program Files\VideoLAN\VLC\vlc.exe"
                    "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe") }
            [PSCustomObject]@{ Name = "Webex"; Paths = @(
                    "$env:LOCALAPPDATA\Programs\Cisco Spark\CiscoCollabHost.exe"
                    "C:\Program Files\Cisco Spark\CiscoCollabHost.exe") }
            [PSCustomObject]@{ Name = "Zoom"; Path = "C:\Program Files\Zoom\bin\Zoom.exe" }

            # Registry detection example. Remove this placeholder in a real client.
            [PSCustomObject]@{
                Name     = "Sample Registry App"
                RegKey   = "HKLM:\SOFTWARE\SampleCorp\SampleApp"
                RegName  = "Version"
                Contains = "1."
            }
        )

        ExpectedShortcuts = @(
            "C:\Users\Public\Desktop\SampleCorp Portal.url"
            "C:\Users\Public\Desktop\SampleCorp VPN.lnk"
        )

        ExpectedBookmarks = @(
            [PSCustomObject]@{ Browser = "Edge"; URLContains = "samplecorp.example" }
            [PSCustomObject]@{ Browser = "Chrome"; URLContains = "samplecorp.sharepoint.com" }
        )

        ExpectedExtensions = @(
            [PSCustomObject]@{ Browser = "Edge"; ID = "gmgoamodcdcjnbaobigkjelfplakmdhh"; Name = "AdBlockPlus" }
            [PSCustomObject]@{ Browser = "Chrome"; ID = "ppnbnpeolgkicgegkbkbjmhlideopiji"; Name = "MS SSO" }
            [PSCustomObject]@{ Browser = "Chrome"; ID = "cfhdojbkjhnklbpkdaibdccddilifddb"; Name = "AdBlockPlus" }
            [PSCustomObject]@{ Browser = "Edge"; ID = "cpbdlogdokiacaifpokijfinplmdiapa"; Name = "PrinterLogic" }
            [PSCustomObject]@{ Browser = "Chrome"; ID = "bfgjjammlemhdcocpejaompfoojnjjfn"; Name = "PrinterLogic" }
            [PSCustomObject]@{ Browser = "Chrome"; ID = "jnhgefjoahogmkkekdnafldkdgppfehd"; Name = "Printix" }
        )

        # Base expectations apply everywhere. Location expectations are appended.
        ExpectedWiFi     = @()
        ExpectedPrinters = @()
        Locations = [ordered]@{
            "Headquarters" = [PSCustomObject]@{
                ExpectedWiFi = @("SampleCorp-Corporate")
                ExpectedPrinters = @([PSCustomObject]@{ Name = "Headquarters MFP"; IP = "192.0.2.25" })
            }
            "BranchOffice" = [PSCustomObject]@{
                ExpectedWiFi = @("SampleCorp-Branch")
                ExpectedPrinters = @([PSCustomObject]@{ Name = "Branch Printix Queue"; IP = "https://localhost:21343/ipp/SAMPLE/queue" })
                ExpectedApps = @([PSCustomObject]@{ Name = "Branch VPN Client"; Path = "C:\Program Files\SampleCorp\Branch VPN\BranchVPN.exe" })
                ExpectedShortcuts = @("C:\Users\Public\Desktop\SampleCorp Branch Portal.url")
                ExpectedBookmarks = @([PSCustomObject]@{ Browser = "Edge"; URLContains = "branch.samplecorp.example" })
                ExpectedExtensions = @([PSCustomObject]@{ Browser = "Edge"; ID = "cpbdlogdokiacaifpokijfinplmdiapa"; Name = "PrinterLogic" })
            }
        }
    }

    # Lean working template: copy, rename, and replace the sample values.
    "PijiNco" = [PSCustomObject]@{
        DisplayName        = "PijiNco"
        ExpectedDomainType = "Entra"
        ExpectedDomainName = "PijiNco"
        ExpectedTimezone   = "Eastern Standard Time"
        RequireLocalAdmin  = $false
        RequireHello       = $null
        RequiredAgents     = @("Ninja","CrowdStrike","CloudRadial","Pia")
        PowerBatteryScreen = 10
        PowerBatterySleep  = 30
        PowerACScreen      = 15
        PowerACSleep       = 0
        ExpectedApps = @(
            [PSCustomObject]@{ Name = "7-Zip"; Path = "C:\Program Files\7-Zip\7z.exe" }
            [PSCustomObject]@{ Name = "Google Chrome"; Paths = @(
                    "C:\Program Files\Google\Chrome\Application\chrome.exe"
                    "C:\Users\*\AppData\Local\Google\Chrome\Application\chrome.exe") }
            [PSCustomObject]@{ Name = "Microsoft 365"; Path = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE" }
            [PSCustomObject]@{ Name = "Microsoft OneDrive"; Paths = @(
                    "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
                    "C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe") }
        )
        ExpectedWiFi      = @()
        ExpectedPrinters  = @()
        ExpectedShortcuts = @()
        ExpectedBookmarks = @()
        ExpectedExtensions = @(
            [PSCustomObject]@{ Browser = "Edge"; ID = "ppnbnpeolgkicgegkbkbjmhlideopiji"; Name = "MS SSO" }
            [PSCustomObject]@{ Browser = "Chrome"; ID = "ppnbnpeolgkicgegkbkbjmhlideopiji"; Name = "MS SSO" }
			[PSCustomObject]@{ Browser = "Edge"; ID = "gmgoamodcdcjnbaobigkjelfplakmdhh"; Name = "AdBlockPlus" }
            [PSCustomObject]@{ Browser = "Chrome"; ID = "cfhdojbkjhnklbpkdaibdccddilifddb"; Name = "AdBlockPlus" }
        )
        Locations = [ordered]@{
            "MainOffice" = [PSCustomObject]@{
                ExpectedWiFi = @("PijiNco-Corporate")
                ExpectedPrinters = @([PSCustomObject]@{ Name = "Main Office MFP"; IP = "192.0.2.25" })
            }
        }
    }

}

### OUTPUT HELPERS ###
$script:output      = ""
$script:reportData  = [System.Collections.Generic.List[object]]::new()
$script:pendingSegs = [System.Collections.Generic.List[hashtable]]::new()
$script:wfSkipLine  = $false

function OutputInfo {
    param(
        [string]$Text,
        [string]$ForegroundColor = $null,
        [string]$BackgroundColor = $null,
        [switch]$NoNewLine
    )
    if ($NoNewLine) { $script:output += $Text } else { $script:output += $Text + "`n" }
    $p = @{}
    if ($ForegroundColor) { $p['ForegroundColor'] = $ForegroundColor }
    if ($BackgroundColor) { $p['BackgroundColor'] = $BackgroundColor }
    if ($NoNewLine)       { $p['NoNewLine']        = $true }
    Write-Host $Text @p
    # WinForms segment capture
    if (-not $script:wfSkipLine) {
        $script:pendingSegs.Add(@{ Text = $Text; FG = $ForegroundColor; BG = $BackgroundColor })
        if (-not $NoNewLine) {
            $script:reportData.Add(@{ Kind = 'Line'; Segs = [array]$script:pendingSegs })
            $script:pendingSegs = [System.Collections.Generic.List[hashtable]]::new()
        }
    } else {
        if (-not $NoNewLine) { $script:wfSkipLine = $false }
    }
}

function Write-Section {
    param([string]$Title, [string]$Color = "Cyan")
    if ($script:pendingSegs.Count -gt 0) {
        $script:reportData.Add(@{ Kind = 'Line'; Segs = [array]$script:pendingSegs })
        $script:pendingSegs = [System.Collections.Generic.List[hashtable]]::new()
    }
    $script:reportData.Add(@{ Kind = 'Section'; Title = $Title; SectionColor = $Color })
    $script:wfSkipLine = $true
    OutputInfo "=== $Title ===" -ForegroundColor $Color -BackgroundColor DarkGray
}

function Write-Check {
    param(
        [string]$Label,
        [bool]$Pass,
        [string]$Info      = "",
        [string]$InfoColor = ""
    )
    $badge = if ($Pass) { "[OK]" } else { "[!!]" }
    $bc    = if ($Pass) { "Green" } else { "Red" }
    $ic    = if ($InfoColor) { $InfoColor } elseif ($Pass) { "Green" } else { "Yellow" }
    OutputInfo "  $badge  " -NoNewLine -ForegroundColor $bc
    OutputInfo $Label.PadRight(30) -NoNewLine
    OutputInfo " $Info" -ForegroundColor $ic
}

function Write-Warn {
    param(
        [string]$Label,
        [string]$Info      = "",
        [string]$InfoColor = "Yellow"
    )
    OutputInfo "  [??]  " -NoNewLine -ForegroundColor Yellow
    OutputInfo $Label.PadRight(30) -NoNewLine
    OutputInfo " $Info" -ForegroundColor $InfoColor
}

function Write-InfoLine {
    param(
        [string]$Label,
        [string]$Info      = "",
        [string]$InfoColor = "Gray"
    )
    OutputInfo "  [~~]  " -NoNewLine -ForegroundColor DarkGray
    OutputInfo $Label.PadRight(30) -NoNewLine
    OutputInfo " $Info" -ForegroundColor $InfoColor
}

function Show-PowerValue {
    param([string]$Label, [int]$Actual, $Expected)
    $display = if ($Actual -eq 0) { "Never" } else { "${Actual} min" }
    if ($null -eq $Expected) {
        $color = if ($Actual -eq 0) { "Green" } elseif ($Actual -le 15) { "DarkYellow" } else { "Yellow" }
        Write-InfoLine $Label $display $color
    } else {
        $expDisplay = if ($Expected -eq 0) { "Never" } else { "$Expected min" }
        Write-Check $Label ($Actual -eq $Expected) "$display  (expected: $expDisplay)"
    }
}

### EXECUTION CONTEXT ###
function Test-IsElevated {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsLocalAdminMember {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return @($identity.Groups | ForEach-Object { $_.Value }) -contains "S-1-5-32-544"
    } catch {
        return $null
    }
}

$script:ExecutionUser      = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$script:IsElevated         = Test-IsElevated
$script:IsLocalAdminMember = Test-IsLocalAdminMember
$script:IsRealUser         = $env:USERNAME -notin @("SYSTEM","LOCAL SERVICE","NETWORK SERVICE")

### AGENT DEFINITIONS ###
$AgentDefs = [ordered]@{
    "Ninja"       = [PSCustomObject]@{
        DisplayName = "Ninja RMM"
        Paths       = @("C:\Program Files (x86)\NinjaOne\NinjaRMMAgent.exe")
        RegKey      = $null
    }
    "CrowdStrike" = [PSCustomObject]@{
        DisplayName = "CrowdStrike"
        Paths       = @("C:\Program Files\CrowdStrike")
        RegKey      = $null
    }
    "CloudRadial" = [PSCustomObject]@{
        DisplayName = "CloudRadial"
        Paths       = @("C:\Program Files (x86)\CloudRadial Agent\unins000.exe")
        RegKey      = $null
    }
    "Pia"         = [PSCustomObject]@{
        DisplayName = "Pia"
        Paths       = @("C:\Program Files (x86)\OrchestratorAgent\OrchestratorAgent.exe")
        RegKey      = $null
    }
    "Huntress"    = [PSCustomObject]@{
        DisplayName = "Huntress"
        Paths       = @("C:\Program Files (x86)\Huntress")
        RegKey      = $null
    }
    "BlackPoint"  = [PSCustomObject]@{
        DisplayName = "BlackPoint Cyber"
        Paths       = @("C:\Program Files (x86)\Blackpoint")
        RegKey      = $null
    }
    "Ninite"      = [PSCustomObject]@{
        DisplayName = "Ninite"
        Paths       = @("C:\Program Files (x86)\Ninite Agent\NiniteAgent.exe")
        RegKey      = $null
    }
	"ActivTrack"  = [PSCustomObject]@{
        DisplayName = "ActivTrack"
        Paths       = @("C:\Windows\SysWOW64\aamdata\atutil.exe")
        RegKey      = $null
    }
}

### FORBIDDEN SOFTWARE DEFINITIONS ###
$ForbiddenDefs = @(
    [PSCustomObject]@{
        DisplayName = "ImmyBot Agent"
        Paths       = @("C:\Program Files (x86)\ImmyBot\Immybot.Agent.exe",
                        "C:\Program Files\ImmyBot")
        RegKey      = $null
        Services    = @("ImmybotAgent")
    }
    [PSCustomObject]@{
        DisplayName = "LabTech / ConnectWise Agent"
        Paths       = @("C:\Windows\LTSvc\LTService.exe",
                        "C:\Windows\LTSvc\LTSVC.exe")
        RegKey      = $null
        Services    = @("LTService","LTSvcMon")
    }
    [PSCustomObject]@{
        DisplayName = "Bitdefender"
        Paths       = @("C:\Program Files\Bitdefender",
                        "C:\Program Files (x86)\Bitdefender")
        RegKey      = "HKLM:\SOFTWARE\Bitdefender"
        Services    = @("VSSERV","bdredline","EPSecurityService")
    }
    [PSCustomObject]@{
        DisplayName = "Norton / McAfee"
        Paths       = @("C:\Program Files\Norton Security",
                        "C:\Program Files (x86)\Norton Security",
                        "C:\Program Files\McAfee",
                        "C:\Program Files (x86)\McAfee")
        RegKey      = $null
        Services    = @("NortonSecurity","mcshield","MfeEERM")
    }
    [PSCustomObject]@{
        DisplayName = "HP Wolf Security"
        Paths       = @("C:\Program Files\HP\HP Sure Click",
                        "C:\Program Files (x86)\HP\HP Wolf Security",
                        "C:\Program Files\HP\HP Wolf Security")
        RegKey      = $null
        Services    = @("HpSureClickService","WolfSecurityService","HpDeviceCheck")
    }
)

### CLIENT SELECTION ###
if ([string]::IsNullOrWhiteSpace($Client)) {
    $cfg = $ClientConfigs["Default"]
} elseif ($ClientConfigs.ContainsKey($Client)) {
    $cfg = $ClientConfigs[$Client]
} else {
    Write-Host "ERROR: Unknown client '$Client'." -ForegroundColor Red
    Write-Host "Valid client names:" -ForegroundColor Yellow
    $ClientConfigs.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$script:ClientSelected = -not [string]::IsNullOrWhiteSpace($Client)

# == Location resolution ==
# Base fields always checked; location fields APPENDED when -Location is supplied
$resolvedLocation   = $null
$resolvedWiFi       = @($cfg.ExpectedWiFi)
$resolvedPrinters   = @($cfg.ExpectedPrinters)
$resolvedApps       = @($cfg.ExpectedApps)
$resolvedShortcuts  = @($cfg.ExpectedShortcuts)
$resolvedBookmarks  = @($cfg.ExpectedBookmarks)
$resolvedExtensions = @($cfg.ExpectedExtensions)

if (-not [string]::IsNullOrWhiteSpace($Location)) {
    $hasLocations = $cfg.PSObject.Properties['Locations'] -and $cfg.Locations -and $cfg.Locations.Count -gt 0
    if ($hasLocations) {
        if ($cfg.Locations.Contains($Location)) {
            $resolvedLocation = $Location
            $locCfg = $cfg.Locations[$resolvedLocation]
            if ($locCfg.PSObject.Properties['ExpectedWiFi']       -and $locCfg.ExpectedWiFi)       { $resolvedWiFi       += $locCfg.ExpectedWiFi }
            if ($locCfg.PSObject.Properties['ExpectedPrinters']   -and $locCfg.ExpectedPrinters)   { $resolvedPrinters   += $locCfg.ExpectedPrinters }
            if ($locCfg.PSObject.Properties['ExpectedApps']       -and $locCfg.ExpectedApps)       { $resolvedApps       += $locCfg.ExpectedApps }
            if ($locCfg.PSObject.Properties['ExpectedShortcuts']  -and $locCfg.ExpectedShortcuts)  { $resolvedShortcuts  += $locCfg.ExpectedShortcuts }
            if ($locCfg.PSObject.Properties['ExpectedBookmarks']  -and $locCfg.ExpectedBookmarks)  { $resolvedBookmarks  += $locCfg.ExpectedBookmarks }
            if ($locCfg.PSObject.Properties['ExpectedExtensions'] -and $locCfg.ExpectedExtensions) { $resolvedExtensions += $locCfg.ExpectedExtensions }
        } else {
            Write-Host "  [??] Location '$Location' not found for '$($cfg.DisplayName)'." -ForegroundColor Yellow
            Write-Host "  Valid locations: $($cfg.Locations.Keys -join ', ')" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [~~] Location '$Location' specified but '$($cfg.DisplayName)' has no location config." -ForegroundColor DarkGray
    }
}

### DATA-GATHERING FUNCTIONS ###

function Get-DeviceName {
    $active  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
    $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
    return [PSCustomObject]@{
        Current    = $active
        Pending    = $pending
        HasPending = ($active -ne $pending)
    }
}

function Get-SerialNumber {
    try {
        $s = (Get-CimInstance Win32_BIOS -Property SerialNumber).SerialNumber
        if ($s) { return $s.Trim() } else { return "Not Found" }
    } catch { return "Not Found" }
}

function Get-OSInfo {
    try {
        $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $build  = [int]$p.CurrentBuild
        $name   = $p.ProductName
        if ($build -ge 22000) { $name = $name -replace "Windows 10","Windows 11" }
        $feat   = if ($p.DisplayVersion) { $p.DisplayVersion } elseif ($p.ReleaseId) { $p.ReleaseId } else { "?" }
        return "$name - $feat - $build.$($p.UBR)"
    } catch { return "Not Found" }
}

function Get-ActivationKey {
    try {
        $k = (Get-CimInstance -Query "SELECT OA3xOriginalProductKey FROM SoftwareLicensingService").OA3xOriginalProductKey
        if ($k) { return $k } else { return "Not Found" }
    } catch { return "Not Found" }
}

function Get-HWSummary {
    # CPU
    $cpu  = Get-CimInstance Win32_Processor -Property Name,MaxClockSpeed | Select-Object -First 1
    $cn   = $cpu.Name -replace '\(R\)|\(TM\)|CPU','' -replace '\s+',' '
    $ghz  = [math]::Round($cpu.MaxClockSpeed / 1000, 2)
    $cpuInfo = if ($cn -match 'GHz') { $cn.Trim() } else { "$($cn.Trim()) @ ${ghz}GHz" }
    # GPU
    $gpu  = Get-CimInstance Win32_VideoController -Property Name,AdapterRAM |
            Sort-Object AdapterRAM -Descending | Select-Object -First 1
    $gpuInfo = if ($gpu) {
        $gn   = $gpu.Name -replace '\(R\)|\(TM\)','' -replace '\s+',' '
        $vram = [math]::Round($gpu.AdapterRAM / 1MB)
        "$($gn.Trim()) (${vram}MB)"
    } else { "No GPU detected" }
    # RAM
    $totalBytes = (Get-CimInstance Win32_PhysicalMemory -Property Capacity | Measure-Object Capacity -Sum).Sum
    $totalGB    = if ($totalBytes) { [math]::Round($totalBytes / 1GB, 1) } else { "?" }
    $mod        = Get-CimInstance Win32_PhysicalMemory -Property SMBIOSMemoryType,MemoryType,FormFactor | Select-Object -First 1
    $typeMap    = @{
        0='Unknown';2='DRAM';17='SDRAM';20='DDR';21='DDR2';24='DDR3';26='DDR4';27='DDR5';
        29='LPDDR2';30='LPDDR3';31='LPDDR4';36='LPDDR5'
    }
    $ffMap      = @{ 8='SODIMM';12='DIMM';0='Onboard' }
    $ramType    = if ($mod -and $typeMap.ContainsKey([int]$mod.SMBIOSMemoryType)) { $typeMap[[int]$mod.SMBIOSMemoryType] } else { "RAM" }
    $ff         = if ($mod -and $ffMap.ContainsKey([int]$mod.FormFactor)) { $ffMap[[int]$mod.FormFactor] } else { "" }
    # Laptop chassis correction
    $chassis    = if ($script:CimSysEnc) { $script:CimSysEnc.ChassisTypes } else { (Get-CimInstance Win32_SystemEnclosure -Property ChassisTypes).ChassisTypes }
    if (@(8,9,10,11,12,14,18,21,30,31,32) -contains $chassis -and $ff -eq "DIMM") { $ff = "SODIMM" }
    $ramInfo    = if ($ff) { "${totalGB}GB $ramType ($ff)" } else { "${totalGB}GB $ramType" }
    return [PSCustomObject]@{ CPU = $cpuInfo; GPU = $gpuInfo; RAM = $ramInfo }
}

function Get-DomainInfo {
    $result = [PSCustomObject]@{ Type = "None"; Name = "" }
    try {
        $dsr  = dsregcmd /status
        $entra = ($dsr | Select-String "AzureAdJoined\s*:\s*(\w+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -eq 'YES'
        $local = ($dsr | Select-String "DomainJoined\s*:\s*(\w+)"  | ForEach-Object { $_.Matches[0].Groups[1].Value }) -eq 'YES'
        $localName = (Get-CimInstance Win32_ComputerSystem -Property Domain).Domain
        $entraName = ""
        if ($entra) {
            $tn = $dsr | Select-String "TenantName"
            if ($tn) { $entraName = ($tn.ToString() -replace 'TenantName\s*:\s*','').Trim() }
        }
        if ($entra -and $local) { $result.Type = "Hybrid"; $result.Name = "$localName / $entraName" }
        elseif ($entra)         { $result.Type = "Entra";  $result.Name = $entraName }
        elseif ($local)         { $result.Type = "Local";  $result.Name = $localName }
    } catch { }
    $global:DomainStatus = $result.Type
    return $result
}

function Get-ConsumerHelloAvailability {
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Runtime.WindowsRuntime")
        $verifierType = [Windows.Security.Credentials.UI.UserConsentVerifier,Windows.Security.Credentials.UI,ContentType=WindowsRuntime]
        $resultType = [Windows.Security.Credentials.UI.UserConsentVerifierAvailability,Windows.Security.Credentials.UI,ContentType=WindowsRuntime]
        $operation = $verifierType::CheckAvailabilityAsync()
        $asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object {
                $_.Name -eq "AsTask" -and
                $_.IsGenericMethod -and
                $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
            } | Select-Object -First 1
        if (-not $asTaskMethod) { return "Unknown" }
        $task = $asTaskMethod.MakeGenericMethod($resultType).Invoke($null,@($operation))
        if (-not $task.Wait(5000)) { return "TimedOut" }
        return $task.Result.ToString()
    } catch {
        return "Unknown"
    }
}

function Get-HelloStatus {
    function Get-RegSetting {
        param([string]$Path, [string]$Name)
        try {
            $item = Get-ItemProperty -Path $Path -ErrorAction Stop
            $prop = $item.PSObject.Properties[$Name]
            if ($null -ne $prop) {
                return [PSCustomObject]@{ Found = $true; Value = $prop.Value }
            }
        } catch { }
        return [PSCustomObject]@{ Found = $false; Value = $null }
    }

    function Convert-HelloPolicyValue {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [bool]) { return [bool]$Value }
        switch (([string]$Value).Trim().ToLower()) {
            "1"     { return $true }
            "true"  { return $true }
            "0"     { return $false }
            "false" { return $false }
            default { return $null }
        }
    }

    $dsr = @()
    try {
        $dsr = @(dsregcmd /status 2>$null)
    } catch { }

    $entraJoined = $false
    $entraLine = $dsr | Select-String "^\s*AzureAdJoined\s*:\s*(\w+)" | Select-Object -First 1
    if ($entraLine) { $entraJoined = $entraLine.Matches[0].Groups[1].Value -ieq "YES" }

    $tenantId = $null
    $tenantLine = $dsr | Select-String "^\s*TenantId\s*:\s*([0-9a-fA-F-]+)" | Select-Object -First 1
    if ($tenantLine) { $tenantId = $tenantLine.Matches[0].Groups[1].Value }

    $editionId = ""
    try {
        $editionId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop).EditionID
    } catch { }
    $isHomeEdition = $editionId -like "Core*"

    $identity        = [Security.Principal.WindowsIdentity]::GetCurrent()
    $executionUser   = $identity.Name
    $executionSid    = $identity.User.Value
    $interactiveUser = $null
    try {
        $interactiveUser = (Get-CimInstance Win32_ComputerSystem -Property UserName -ErrorAction Stop).UserName
    } catch { }

    $interactiveSid = $null
    if (-not [string]::IsNullOrWhiteSpace($interactiveUser)) {
        try {
            $interactiveSid = ([Security.Principal.NTAccount]$interactiveUser).Translate(
                [Security.Principal.SecurityIdentifier]).Value
        } catch { }
    }

    $contextMatches = $false
    if (-not [string]::IsNullOrWhiteSpace($interactiveUser)) {
        $contextMatches = ($interactiveUser -ieq $executionUser) -or
                          ($interactiveSid -and $interactiveSid -eq $executionSid)
    }
    $targetSid = if ($interactiveSid) { $interactiveSid } else { $executionSid }

    # --- HOME EDITION PATH ---
    # Home does not support WHfB or Group Policy. UserConsentVerifier is the only
    # reliable signal for both policy availability and provisioning state.
    if ($isHomeEdition) {
        $policyEnabled  = $null
        $policyState    = "Unknown"
        $policySource   = ""
        $keyProvisioned = $null
        $keyState       = "Unknown"
        $keySource      = ""

        if (-not $contextMatches) {
            $keyState = "Unknown (user context)"
        } else {
            $consumerState = Get-ConsumerHelloAvailability
            switch ($consumerState) {
                "Available" {
                    # Hello is enabled and a PIN/biometric is configured for this user.
                    $policyEnabled  = $true
                    $policyState    = "Enabled (consumer)"
                    $keyProvisioned = $true
                    $keyState       = "Provisioned"
                    $keySource      = "UserConsentVerifier"
                }
                "NotConfiguredForUser" {
                    # Hardware/TPM capable, Hello available, but user has not set up PIN/biometric.
                    $policyEnabled  = $true
                    $policyState    = "Enabled (consumer)"
                    $keyProvisioned = $false
                    $keyState       = "Not provisioned"
                    $keySource      = "UserConsentVerifier"
                }
                "DeviceNotPresent" {
                    # No Hello-capable hardware (no TPM, no biometric sensor).
                    $policyEnabled  = $false
                    $policyState    = "Unavailable (no hardware)"
                    $keyProvisioned = $false
                    $keyState       = "Not provisioned"
                    $keySource      = "UserConsentVerifier"
                }
                "DisabledByPolicy" {
                    $policyEnabled  = $false
                    $policyState    = "Disabled (policy)"
                    $keyProvisioned = $null
                    $keyState       = "Unknown (policy)"
                    $keySource      = "UserConsentVerifier"
                }
                "DeviceBusy" {
                    $policyState = "Unknown (device busy)"
                    $keyState    = "Unknown (device busy)"
                    $keySource   = "UserConsentVerifier"
                }
                default {
                    $policyState = "Unknown"
                    $keyState    = "Unknown"
                    $keySource   = "UserConsentVerifier"
                }
            }
        }

        return [PSCustomObject]@{
            Enabled         = $policyEnabled
            Provisioned     = $keyProvisioned
            PolicyState     = $policyState
            PolicySource    = $policySource
            KeyState        = $keyState
            KeySource       = $keySource
            ExecutionUser   = $executionUser
            InteractiveUser = $interactiveUser
        }
    }

    # --- PRO / ENTERPRISE PATH ---
    # Microsoft precedence: user GPO, device GPO, user CSP, then device CSP.
    $policyCandidates = @(
        [PSCustomObject]@{
            Path   = "Registry::HKEY_USERS\$targetSid\SOFTWARE\Policies\Microsoft\PassportForWork"
            Name   = "Enabled"
            Source = "User GPO"
        }
        [PSCustomObject]@{
            Path   = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
            Name   = "Enabled"
            Source = "Device GPO"
        }
    )

    $tenantRoots = @()
    $cspRoot = "HKLM:\SOFTWARE\Microsoft\Policies\PassportForWork"
    if ($tenantId) {
        $tenantRoots = @(Join-Path $cspRoot $tenantId)
    } elseif (Test-Path $cspRoot) {
        $tenantRoots = @(Get-ChildItem $cspRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSPath)
    }

    foreach ($tenantRoot in $tenantRoots) {
        $policyCandidates += [PSCustomObject]@{
            Path   = Join-Path $tenantRoot "$targetSid\Policies"
            Name   = "UsePassportForWork"
            Source = "User CSP"
        }
        $policyCandidates += [PSCustomObject]@{
            Path   = Join-Path $tenantRoot "UserSid\Policies"
            Name   = "UsePassportForWork"
            Source = "User CSP"
        }
    }
    foreach ($tenantRoot in $tenantRoots) {
        $policyCandidates += [PSCustomObject]@{
            Path   = Join-Path $tenantRoot "Device\Policies"
            Name   = "UsePassportForWork"
            Source = "Device CSP"
        }
    }

    $policyEnabled = $null
    $policyState   = "Unknown"
    $policySource  = ""
    $policyFound   = $false
    foreach ($candidate in $policyCandidates) {
        $setting = Get-RegSetting -Path $candidate.Path -Name $candidate.Name
        if (-not $setting.Found) { continue }
        $policyFound   = $true
        $policyEnabled = Convert-HelloPolicyValue $setting.Value
        $policySource  = $candidate.Source
        if ($null -ne $policyEnabled) {
            $policyState = if ($policyEnabled) { "Enabled" } else { "Disabled" }
        }
        break
    }

    if (-not $policyFound) {
        if ($entraJoined) {
            $policyEnabled = $true
            $policyState   = "Enabled"
            $policySource  = "Entra default"
        } else {
            $policyEnabled = $false
            $policyState   = "Not configured"
            $policySource  = ""
        }
    }

    $keyProvisioned = $null
    $keyState       = "Unknown"
    $keySource      = ""
    if (-not $contextMatches) {
        $keyState = "Unknown (user context)"
    } else {
        $ngcLine   = $dsr | Select-String "^\s*NgcSet\s*:\s*(\w+)"   | Select-Object -First 1
        $keyIdLine = $dsr | Select-String "^\s*NgcKeyId\s*:\s*(\S+)" | Select-Object -First 1
        if (($ngcLine -and $ngcLine.Matches[0].Groups[1].Value -ieq "YES") -or $keyIdLine) {
            $keyProvisioned = $true
            $keyState       = "Provisioned"
            $keySource      = "dsregcmd"
        } elseif ($ngcLine -and $ngcLine.Matches[0].Groups[1].Value -ieq "NO") {
            $keyProvisioned = $false
            $keyState       = "Not provisioned"
            $keySource      = "dsregcmd"
        }
    }

    return [PSCustomObject]@{
        Enabled         = $policyEnabled
        Provisioned     = $keyProvisioned
        PolicyState     = $policyState
        PolicySource    = $policySource
        KeyState        = $keyState
        KeySource       = $keySource
        ExecutionUser   = $executionUser
        InteractiveUser = $interactiveUser
    }
}

function Get-BitLockerInfo {
    param([bool]$Escrow = $true)

    if (-not $script:IsElevated) {
        return [PSCustomObject]@{
            Enabled = $null
            ID      = ""
            Key     = ""
            Escrow  = "Unavailable - elevated process required"
        }
    }
    $result = [PSCustomObject]@{
        Enabled = $false
        ID      = ""
        Key     = ""
        Escrow  = "Not applicable - BitLocker is disabled"
    }
    try {
        $bv = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
        if (-not $bv -or $bv.ProtectionStatus -ne 'On') { return $result }
        $result.Enabled = $true
        $rk = $bv.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -Last 1
        if ($rk) {
            $result.ID  = $rk.KeyProtectorId
            $result.Key = $rk.RecoveryPassword
            if (-not $Escrow) {
                $result.Escrow = "Skipped (-NoEscrow)"
            } elseif ($global:DomainStatus -in @("Entra","Hybrid")) {
                try {
                    BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $rk.KeyProtectorId -ErrorAction Stop | Out-Null
                    $result.Escrow = "Escrowed to Entra OK"
                } catch {
                    $result.Escrow = "Escrow failed: $($_.Exception.Message)"
                }
            } else {
                $result.Escrow = "Not applicable - device is not Entra joined"
            }
        } else {
            $result.Key = "No recovery key found"
            $result.Escrow = "Not applicable - no recovery password protector"
        }
    } catch { $result.Enabled = $false }
    return $result
}

function Get-OneDriveStatus {
    $isCommercial = -not [string]::IsNullOrWhiteSpace($env:OneDriveCommercial)
    $isPersonal   = -not $isCommercial -and -not [string]::IsNullOrWhiteSpace($env:OneDrive)
    if (-not $isCommercial -and -not $isPersonal) {
        if (-not (Get-Process OneDrive -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{ Status = "Not running"; Color = "Red" }
        }
    }
    $logRoot    = "$env:LOCALAPPDATA\Microsoft\OneDrive\logs"
    $subFolders = if ($isPersonal) { @("Personal","Business1","Business2","Business3") }
                  else             { @("Business1","Business2","Business3","Personal") }
    $logPath    = $null
    $abortedPath = $null
    foreach ($sub in $subFolders) {
        $candidate = Join-Path $logRoot "$sub\SyncDiagnostics.log"
        if (-not (Test-Path $candidate)) { continue }
        $peek = Get-Content $candidate -Tail 5 -ErrorAction SilentlyContinue
        if (($peek -join ' ') -like "*Aborting sync verification*") {
            if (-not $abortedPath) { $abortedPath = $candidate }
        } else {
            $logPath = $candidate; break
        }
    }
    if (-not $logPath) {
        $found = Get-ChildItem -Path $logRoot -Filter "SyncDiagnostics.log" -Recurse -ErrorAction SilentlyContinue |
                 Where-Object {
                     $peek = Get-Content $_.FullName -Tail 5 -ErrorAction SilentlyContinue
                     ($peek -join ' ') -notlike "*Aborting sync verification*"
                 } | Select-Object -First 1
        if ($found) { $logPath = $found.FullName }
    }
    if (-not $logPath -and $abortedPath) {
        return [PSCustomObject]@{ Status = "Signed in - diagnostics pending"; Color = "Yellow" }
    }
    if (-not $logPath) {
        return [PSCustomObject]@{ Status = "Log file not found"; Color = "Red" }
    }
    $lines = Get-Content $logPath -Tail 200 -ErrorAction SilentlyContinue
    $line  = $lines | Where-Object { $_ -like "*SyncProgressState*" } | Select-Object -Last 1
    if (-not $line) { return [PSCustomObject]@{ Status = "State not found in log"; Color = "Yellow" } }
    if ($line -match "SyncProgressState\D*(\d+)") {
        $state = [int]$matches[1]
    } else {
        return [PSCustomObject]@{ Status = "Unreadable log format"; Color = "Yellow" }
    }
    $map = @{ 16777216="Up-to-Date"; 0="Up-to-Date"; 65536="Paused"; 8194="Not Syncing"; 1854="Sync Issues" }
    $status = if ($map.ContainsKey($state)) { $map[$state] } else { "Unknown state: $state" }
    $color  = if ($status -eq "Up-to-Date") { "Green" } else { "Red" }
    return [PSCustomObject]@{ Status = $status; Color = $color }
}

function Get-PowerSettings {
    if (-not ("Win32.BRPower" -as [type])) {
        Add-Type -Namespace Win32 -Name BRPower -MemberDefinition @"
            [System.Runtime.InteropServices.DllImport("PowrProf.dll")]
            public static extern uint PowerGetActiveScheme(IntPtr UserRootPowerKey, out IntPtr ActivePolicyGuid);
            [System.Runtime.InteropServices.DllImport("PowrProf.dll")]
            public static extern uint PowerReadACValueIndex(IntPtr Root, ref System.Guid Scheme, ref System.Guid Sub, ref System.Guid Setting, out uint Value);
            [System.Runtime.InteropServices.DllImport("PowrProf.dll")]
            public static extern uint PowerReadDCValueIndex(IntPtr Root, ref System.Guid Scheme, ref System.Guid Sub, ref System.Guid Setting, out uint Value);
"@
    }
    $ptr = [IntPtr]::Zero
    [Win32.BRPower]::PowerGetActiveScheme([IntPtr]::Zero, [ref]$ptr) | Out-Null
    $scheme = [Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][Guid])
    [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    $subScreen  = [Guid]"7516b95f-f776-4464-8c53-06167f40cc99"
    $guidScreen = [Guid]"3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
    $subSleep   = [Guid]"238c9fa8-0aad-41ed-83f4-97be242c8f20"
    $guidSleep  = [Guid]"29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
    $acScr = 0; $dcScr = 0; $acSlp = 0; $dcSlp = 0
    [Win32.BRPower]::PowerReadACValueIndex([IntPtr]::Zero,[ref]$scheme,[ref]$subScreen,[ref]$guidScreen,[ref]$acScr) | Out-Null
    [Win32.BRPower]::PowerReadDCValueIndex([IntPtr]::Zero,[ref]$scheme,[ref]$subScreen,[ref]$guidScreen,[ref]$dcScr) | Out-Null
    [Win32.BRPower]::PowerReadACValueIndex([IntPtr]::Zero,[ref]$scheme,[ref]$subSleep, [ref]$guidSleep, [ref]$acSlp) | Out-Null
    [Win32.BRPower]::PowerReadDCValueIndex([IntPtr]::Zero,[ref]$scheme,[ref]$subSleep, [ref]$guidSleep, [ref]$dcSlp) | Out-Null
    return [PSCustomObject]@{
        BatScreen = [int]($dcScr / 60)
        ACScreen  = [int]($acScr / 60)
        BatSleep  = [int]($dcSlp / 60)
        ACSleep   = [int]($acSlp / 60)
    }
}

function Get-TZInfo {
    $tz = Get-TimeZone
    return [PSCustomObject]@{
        Id          = $tz.Id
        DisplayName = $tz.DisplayName
        Current     = (Get-Date -Format "h:mm tt, M/d/yyyy")
    }
}

function Get-UACLevel {
    $reg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $lua = Get-ItemPropertyValue -Path $reg -Name "EnableLUA" -ErrorAction SilentlyContinue
    if ($lua -eq 0) { return "OFF - Never notify (lvl 0)" }
    $a = [int](Get-ItemPropertyValue -Path $reg -Name "ConsentPromptBehaviorAdmin" -ErrorAction SilentlyContinue)
    $s = [int](Get-ItemPropertyValue -Path $reg -Name "PromptOnSecureDesktop"       -ErrorAction SilentlyContinue)
    switch ("$a-$s") {
        "2-1" { return "ON - Always notify (lvl 3)" }
        "5-1" { return "ON - Default, secure desktop (lvl 2)" }
        "5-0" { return "ON - Notify, no secure desktop (lvl 1)" }
        "0-0" { return "ON - Never notify (lvl 0)" }
        default { return "ON - Custom ($a / $s)" }
    }
}

function Get-WSIStatus {
    $p = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Authentication"
    if (-not (Test-Path $p)) { return $false }
    try { return ((Get-ItemPropertyValue -Path $p -Name "EnableWebSignIn" -ErrorAction Stop) -eq 1) }
    catch { return $false }
}

function Test-AgentInstalled {
    param([PSCustomObject]$Def)
    foreach ($path in $Def.Paths) { if (Test-Path $path) { return $true } }
    if ($Def.RegKey -and (Test-Path $Def.RegKey)) { return $true }
    return $false
}

function Test-ForbiddenInstalled {
    param([PSCustomObject]$Def)
    foreach ($path in $Def.Paths) { if (Test-Path $path) { return $true } }
    if ($Def.RegKey -and (Test-Path $Def.RegKey)) { return $true }
    foreach ($svc in $Def.Services) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $s) { continue }
        $svcInfo = Get-CimInstance Win32_Service -Filter "Name='$svc'" -Property PathName -ErrorAction SilentlyContinue
        if ($svcInfo -and $svcInfo.PathName) {
            $exe = $svcInfo.PathName.Trim('"') -replace '\s.*$', ''
            if (Test-Path $exe) { return $true }
        } elseif (-not $svcInfo) {
            return $true
        }
    }
    return $false
}

function Test-AppInstalled {
    param([PSCustomObject]$AppDef)
    if ($AppDef.Paths) {
        foreach ($p in $AppDef.Paths) { if (Test-Path $p) { return $true } }
    }
    if ($AppDef.Path -and (Test-Path $AppDef.Path)) { return $true }
    if ($AppDef.RegKey) {
        $val = Get-ItemProperty -Path $AppDef.RegKey -ErrorAction SilentlyContinue
        if ($val -and $AppDef.RegName) {
            $prop = $val.($AppDef.RegName)
            if ($AppDef.Contains) { return ($prop -like "*$($AppDef.Contains)*") }
            return ($null -ne $prop)
        }
        if ($val) { return $true }
    }
    if ($AppDef.UninstallName) {
        $uninstallRoots = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $hit = Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like "*$($AppDef.UninstallName)*" } |
               Select-Object -First 1
        if ($hit) { return $true }
    }
    return $false
}

function Get-DriverTool {
    $mfr        = "Unknown"
    $tool       = "Unknown"
    $inst       = $false
    $scriptPath = $null
    try {
        $enc = if ($script:CimSysEnc) { $script:CimSysEnc.Manufacturer } else { (Get-CimInstance Win32_SystemEnclosure -Property Manufacturer).Manufacturer }
        $mb  = if ($script:CimBaseBd) { $script:CimBaseBd.Manufacturer } else { (Get-CimInstance Win32_BaseBoard -Property Manufacturer).Manufacturer }
        $raw = "$enc $mb".ToLower()
        if ($raw -match "\bdell\b") {
            $mfr        = "Dell"
            $tool       = "Dell Command Update"
            $inst       = (Test-Path "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe") -or
                          (Test-Path "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe")
            $scriptPath = Join-Path $workingDir "scripts\Install_DCUandUpdates.ps1"
        } elseif ($raw -match "hp|hewlett") {
            $mfr        = "HP"
            $tool       = "HP Image Assistant"
            $inst       = $false
            if (Test-Path "C:\SWSETUP") {
                try {
                    $hit  = [System.IO.Directory]::EnumerateFiles("C:\SWSETUP", "HPImageAssistant.exe", [System.IO.SearchOption]::AllDirectories) |
                            Select-Object -First 1
                    $inst = $null -ne $hit
                } catch { }
            }
            $scriptPath = Join-Path $workingDir "scripts\Install_HPIAandUpdates.ps1"
        } elseif ($raw -match "lenovo") {
            $mfr        = "Lenovo"
            $tool       = "Lenovo System Update"
            $inst       = (Test-Path "C:\Program Files (x86)\Lenovo\System Update\tvsuShim.exe")
            $scriptPath = Join-Path $workingDir "scripts\Install_LSUandUpdates.ps1"
        } else {
            $mfr  = $enc
            $tool = "N/A (unrecognized manufacturer)"
        }
    } catch { }
    $scriptPresent = $scriptPath -and (Test-Path $scriptPath)
    return [PSCustomObject]@{ Mfr = $mfr; Tool = $tool; Installed = $inst; ScriptPath = $scriptPath; ScriptPresent = $scriptPresent }
}

function Get-PrintersWithIP {
    $result = @()
    try {
        $printers = Get-Printer | Where-Object { -not $_.Shared } | Sort-Object Name
        foreach ($p in $printers) {
            $ip = $null
            try {
                $port = Get-PrinterPort -Name $p.PortName -ErrorAction SilentlyContinue
                if ($port -and $port.PrinterHostAddress) { $ip = $port.PrinterHostAddress }
            } catch { }
            $result += [PSCustomObject]@{ Name = $p.Name; IP = $ip }
        }
    } catch { }
    return $result
}

function Get-WiFiSSIDs {
    function Resolve-SSID($profileName) {
        try {
            $detail = netsh wlan show profile name="$profileName" 2>$null
            $line   = $detail | Select-String "SSID name\s*:\s*`"(.+)`""
            if ($line) { return $line.Matches[0].Groups[1].Value }
        } catch { }
        return $profileName
    }
    $sysNames = @(netsh wlan show profiles | ForEach-Object {
        if ($_ -match "All User Profile\s*:\s*(.+)") { $matches[1].Trim() }
    } | Where-Object { $_ })
    $usrNames = @(netsh wlan show profiles interface=* | ForEach-Object {
        if ($_ -match "User Profile\s*:\s*(.+)") { $matches[1].Trim() }
    } | Where-Object { $_ -notin $sysNames -and $_ })
    return [PSCustomObject]@{
        System = @($sysNames | ForEach-Object { Resolve-SSID $_ })
        User   = @($usrNames | ForEach-Object { Resolve-SSID $_ })
    }
}

function Get-PubDesktopShortcuts {
    $p = "C:\Users\Public\Desktop"
    if (-not (Test-Path $p)) { return @() }
    return @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
}

function Test-BookmarkPresent {
    param([string]$Browser, [string]$URLContains)
    $paths = @()
    switch ($Browser.ToLower()) {
        "edge"   { $paths += "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks" }
        "chrome" { $paths += "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks" }
    }
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $c = Get-Content $p -Raw -ErrorAction SilentlyContinue
            if ($c -and $c -like "*$URLContains*") { return $true }
        }
    }
    return $false
}

function Get-DiskSummary {
    $disks = Get-CimInstance Win32_LogicalDisk -Property DeviceID,DriveType,Size,FreeSpace | Where-Object { $_.DriveType -in 2,3 }
    return @($disks | ForEach-Object {
        [PSCustomObject]@{
            Drive   = $_.DeviceID
            Type    = switch ($_.DriveType) { 2{"Removable"} 3{"Fixed"} default{"Other"} }
            TotalGB = [math]::Round($_.Size / 1GB, 1)
            FreeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
        }
    })
}

function Get-NetworkInfo {
    $jType  = Start-Job -ScriptBlock { Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1 }
    $jMAC   = Start-Job -ScriptBlock { (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1 -ExpandProperty MacAddress) }
    $jInt   = Start-Job -ScriptBlock {
        $iface = Get-NetIPConfiguration | Where-Object {
            $_.IPv4DefaultGateway -ne $null -and
            $_.NetAdapter.Status -eq 'Up' -and
            $_.IPv4Address.IPAddress -notlike '169.254.*'
        } | Sort-Object {
            if ($_.NetAdapter.InterfaceDescription -match "Ethernet") {0}
            elseif ($_.NetAdapter.InterfaceDescription -match "Wi-Fi|Wireless") {1}
            else {2}
        }
        if ($iface) { $iface[0].IPv4Address.IPAddress } else { $null }
    }
    $jExt   = Start-Job -ScriptBlock { try { Invoke-RestMethod -Uri "https://api.ipify.org" } catch { $null } }
    @($jType,$jMAC,$jInt,$jExt) | ForEach-Object { $_ | Wait-Job -Timeout 10 | Out-Null }
    $adapter  = if ($jType.State -eq 'Completed') { Receive-Job $jType } else { $null }
    $macVal   = if ($jMAC.State  -eq 'Completed') { Receive-Job $jMAC  } else { "Timeout" }
    $intVal   = if ($jInt.State  -eq 'Completed') { Receive-Job $jInt  } else { "Timeout" }
    $extVal   = if ($jExt.State  -eq 'Completed') { Receive-Job $jExt  } else { "Timeout" }
    @($jType,$jMAC,$jInt,$jExt) | ForEach-Object { Remove-Job $_ -Force -ErrorAction SilentlyContinue }
    $netType = "Unknown"
    if ($adapter) {
        if ($adapter.Name -match "Wi-Fi|Wireless") { $netType = "WiFi" }
        elseif ($adapter.Name -match "Ethernet")   { $netType = "Ethernet" }
        else { $netType = $adapter.Name }
    } elseif ($jType.State -ne 'Completed') { $netType = "Timeout" }
    else { $netType = "No Internet" }
    return [PSCustomObject]@{
        Type  = $netType
        MAC   = if ($macVal) { $macVal } else { "Not Found" }
        IntIP = if ($intVal) { $intVal } else { "N/A" }
        ExtIP = if ($extVal) { $extVal } else { "N/A" }
    }
}

# ~~~ EXTENSION DISPLAY DATA ~~~
$extensionDefinitions = @(
    [PSCustomObject]@{ Name = "MS SSO";                Chrome = "ppnbnpeolgkicgegkbkbjmhlideopiji"; Edge = "ppnbnpeolgkicgegkbkbjmhlideopiji" }
    [PSCustomObject]@{ Name = "AdBlockPlus";           Chrome = "cfhdojbkjhnklbpkdaibdccddilifddb"; Edge = "cfhdojbkjhnklbpkdaibdccddilifddb" }
    [PSCustomObject]@{ Name = "AdBlockPlus";           Edge   = "gmgoamodcdcjnbaobigkjelfplakmdhh" }
    [PSCustomObject]@{ Name = "uBlock";                Edge   = "nffknjpglkklphnibdiadeeeeailfnog" }
    [PSCustomObject]@{ Name = "uBlock Origin";         Chrome = "epcnnfbjfcgphgdmggkamkmgojdagdnn"; Edge = "odfafepnkmbhccpbejgmiehpchacaeak" }
    [PSCustomObject]@{ Name = "uBlock Lite";           Chrome = "ddkjiahejlhfcafbddmgiahcphecmpfh"; Edge = "cimighlppcgcoapaliogpjjdehbnofhn" }
    [PSCustomObject]@{ Name = "Grammarly";             Chrome = "kbfnbcaeplbcioakkpcpgfkobkghlhen"; Edge = "cnlefmmeadmemmdciolhbnfeacpdfbkd" }
    [PSCustomObject]@{ Name = "Adobe Acrobat";         Chrome = "efaidnbmnnnibpcajpcglclefindmkaj"; Edge = "elhekieabhbkpmcefcoobjddigjcaadp" }
    [PSCustomObject]@{ Name = "LastPass";              Chrome = "hdokiejnpimakedhajhdlcegeplioahd"; Edge = "bbcinlkgjjkejfdpemiealijmmooekmp" }
    [PSCustomObject]@{ Name = "BitWarden";             Chrome = "nngceckbapebfimnlniiiahkandclblb"; Edge = "jbkfoedolllekgbhcbcoahefnbanhhlh" }
    [PSCustomObject]@{ Name = "DarkReader";            Chrome = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; Edge = "ifoakfbpdcdoeenechcleahebpibofpc" }
    [PSCustomObject]@{ Name = "Honey";                 Chrome = "bmnlcjabgnpnenekpadlanbbkooimhnj"; Edge = "cldpoaekmmmjbdpmajhdenimdedecfam" }
    [PSCustomObject]@{ Name = "Google Translate";      Edge   = "bcbckhapfhbeiejelpbkappfjnichgdj" }
    [PSCustomObject]@{ Name = "PrinterLogic";          Chrome = "bfgjjammlemhdcocpejaompfoojnjjfn"; Edge = "cpbdlogdokiacaifpokijfinplmdiapa" }
    [PSCustomObject]@{ Name = "Google Docs Offline";   Chrome = "ghbmnnjooekpmoecnnnilnnbdlolhkhi"; Edge = "ghbmnnjooekpmoecnnnilnnbdlolhkhi" }
    [PSCustomObject]@{ Name = "Chrome Remote Desktop"; Chrome = "inomeogfingihgjfjlpeplalcfajhgai"; Edge = "inomeogfingihgjfjlpeplalcfajhgai" }
    [PSCustomObject]@{ Name = "Sentinel One";          Chrome = "iekfdmgbpmcklocjhlabimljddkeflgl"; Edge = "ogjmklkhajdbaannfffilmkpneihckoh" }
    [PSCustomObject]@{ Name = "Edge MS365 CoPilot";    Edge   = "ceffpgmgaoapphfijfinjppigbfibnnp" }
    [PSCustomObject]@{ Name = "CRX Extractor";         Chrome = "ajkhmmldknmfjnmeedkbkkojgobmljda" }
    [PSCustomObject]@{ Name = "Office";                Chrome = "gfdkimpbcpahaombhbimeihdjnejgicl" }
    [PSCustomObject]@{ Name = "Zoom Scheduler";        Chrome = "bkkbljpdapjnaaejjheefcglhbhpoebo" }
    [PSCustomObject]@{ Name = "Cisco Webex";           Chrome = "khmjakbcmllidkeacdoemldfpnkhlknk" }
    [PSCustomObject]@{ Name = "HP Wolf Security (!!)"; Edge   = "aoganjpeihhkhippgnniaclfocnihgln" }
    [PSCustomObject]@{ Name = "McAfee WebAdvisor (!!)"; Chrome = "fheoggkfdfchfphceeifdbepaooicaho" }
    [PSCustomObject]@{ Name = "Chrome PDF Viewer";     Chrome = "mhjfbmdgcfjbbpaeojofohoefgiehjai"; Exclude = $true }
    [PSCustomObject]@{ Name = "Chrome Web Store";      Chrome = "nmmhkkegccagdldgiimedpiccmgmieda"; Exclude = $true }
    [PSCustomObject]@{ Name = "Edge Internal";         Edge   = "jmjflgjpcpepeafmmgdpfkogkghcpiha";  Exclude = $true }
)

$script:friendlyExtensions = @{}
$script:excludedExtIds     = @{}
foreach ($def in $extensionDefinitions) {
    $isExclude = $def.PSObject.Properties['Exclude'] -and $def.Exclude
    foreach ($browser in @('Chrome','Edge')) {
        if ($def.PSObject.Properties[$browser] -and $def.$browser) {
            if ($isExclude) { $script:excludedExtIds[$def.$browser]     = $true }
            else            { $script:friendlyExtensions[$def.$browser] = $def.Name }
        }
    }
}

function Get-AllExtensions {
    function Read-ExtFolder($base) {
        $names_out = @()
        $ids_out   = @()
        if (-not (Test-Path $base)) {
            return [PSCustomObject]@{ Names = $names_out; IDs = $ids_out }
        }
        foreach ($d in Get-ChildItem $base -Directory -ErrorAction SilentlyContinue) {
            $id = $d.Name
            if ($script:excludedExtIds.ContainsKey($id)) { continue }
            $ids_out   += $id
            $names_out += if ($script:friendlyExtensions.ContainsKey($id)) { $script:friendlyExtensions[$id] } else { $id }
        }
        return [PSCustomObject]@{ Names = $names_out; IDs = $ids_out }
    }
    $edgePath   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
    $edgeData   = Read-ExtFolder $edgePath
    $chromeData = Read-ExtFolder $chromePath
    return [PSCustomObject]@{
        Edge      = $edgeData.Names
        Chrome    = $chromeData.Names
        EdgeIDs   = $edgeData.IDs
        ChromeIDs = $chromeData.IDs
    }
}

function Write-ExtList {
    param([string]$Label, [array]$Exts)
    OutputInfo "  $($Label.PadRight(8)): " -NoNewLine -ForegroundColor White
    if ($Exts -and $Exts.Count -gt 0) {
        $toggle = $true
        for ($i = 0; $i -lt $Exts.Count; $i++) {
            $c = if ($toggle) { "Gray" } else { "White" }
            $toggle = -not $toggle
            if ($i -lt $Exts.Count - 1) { OutputInfo "$($Exts[$i]), " -NoNewLine -ForegroundColor $c }
            else { OutputInfo $Exts[$i] -ForegroundColor $c }
        }
    } else { OutputInfo "None" -ForegroundColor DarkGray }
}

### DEFAULT APPLICATION AND USER REPORTING ###
function GetFriendlyDefaultApp {
    param([string]$Extension)
    function HasCustomEmailSignature {
        $sp = Join-Path $env:APPDATA "Microsoft\Signatures"
        if (Test-Path $sp) {
            return ((Get-ChildItem $sp -Include *.htm,*.rtf,*.txt -File -Recurse -ErrorAction SilentlyContinue).Count -gt 0)
        }
        return $false
    }
    $ucPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"
    $progId = $null
    try {
        if (Test-Path $ucPath) {
            $progId = (Get-ItemProperty $ucPath -ErrorAction SilentlyContinue).ProgId
        } else {
            if ($Extension -eq ".pst") {
                $sig = if (HasCustomEmailSignature) { " (has signature)" } else { " (no signature)" }
                $sigColor = if (HasCustomEmailSignature) { "Green" } else { "Yellow" }
                OutputInfo "Classic Outlook*" -NoNewLine
                OutputInfo " (Windows Default; never changed)" -ForegroundColor DarkGray -NoNewLine
                OutputInfo $sig -ForegroundColor $sigColor
                return
            } elseif ($Extension -eq ".html") {
                OutputInfo "Microsoft Edge" -NoNewLine
                OutputInfo " (Windows Default; never changed)" -ForegroundColor DarkGray
                return
            } elseif ($Extension -eq ".pdf") {
                OutputInfo "Microsoft Edge" -NoNewLine
                OutputInfo " (Windows Default; never changed)" -ForegroundColor DarkGray
                return
            }
        }
        if (-not $progId) {
            if ($Extension -eq ".pst") {
                OutputInfo "Classic Outlook*" -NoNewLine
                OutputInfo " (Windows Default)" -ForegroundColor DarkGray
                return
            } elseif ($Extension -eq ".html") {
                OutputInfo "Microsoft Edge" -NoNewLine
                OutputInfo " (Windows Default)" -ForegroundColor DarkGray
                return
            } elseif ($Extension -eq ".pdf") {
                OutputInfo "Microsoft Edge" -NoNewLine
                OutputInfo " (Windows Default)" -ForegroundColor DarkGray
                return
            }
        }
        $map = @{
            "MSEdgeHTM"             = "Microsoft Edge"
            "MSEdgeHTML"            = "Microsoft Edge"
            "MSEdgePDF"             = "Microsoft Edge"
            "ChromeHTML"            = "Google Chrome"
            "FirefoxHTML"           = "Firefox"
            "BraveHTML"             = "Brave"
            "Acrobat.Document.2020" = "Adobe Acrobat"
            "AcroExch.Document.DC"  = "Adobe Acrobat"
            "FoxitReader.Document"  = "Foxit PDF Reader"
            "PowerPDF.Document"     = "Kofax Power PDF"
            "htmlfile"              = "Internet Explorer"
            "Outlook.File.pst"      = "Classic Outlook"
        }
        $name = if ($map.ContainsKey($progId)) { $map[$progId] } else {
            $rk = "Registry::HKEY_CLASSES_ROOT\$progId"
            $fn = if (Test-Path $rk) { (Get-ItemProperty $rk -ErrorAction SilentlyContinue).'(Default)' } else { $null }
            if ($fn) { $fn } else { $progId }
        }
        if ($Extension -eq ".pst") {
            OutputInfo $name -NoNewLine
            if (HasCustomEmailSignature) { OutputInfo " (has signature)"  -ForegroundColor Green }
            else                         { OutputInfo " (no signature)"   -ForegroundColor Yellow }
        } else {
            OutputInfo $name
        }
    } catch {
        OutputInfo "Error reading association" -ForegroundColor Red
    }
}

function GetRealUserAccounts {
    Write-Section "USER ACCOUNTS"
    $excludedProfiles = @("Public","Default","Default User","WDAGUtilityAccount","wsiaccount","admin","defaultuser0")
    $profileRoot      = "C:\Users"
    $currentUser      = $env:USERNAME
    $ErrorActionPreference = "Stop"
    try {
        $adminNames = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | ForEach-Object {
            $n = $_.Name
            if ($n.Contains("\")) { $n.Split("\")[-1] } else { $n }
        }
        Get-ChildItem $profileRoot -Directory | Where-Object {
            ($excludedProfiles -notcontains $_.Name) -and (Test-Path (Join-Path $_.FullName "Downloads"))
        } | ForEach-Object {
            $pn        = $_.Name
            $isAdmin   = $adminNames -contains $pn
            $isCurrent = $pn -eq $currentUser
            $sep       = "  |  "
            OutputInfo "  $pn" -NoNewLine -ForegroundColor $(if ($isAdmin) {"White"} else {"Yellow"})
            OutputInfo $sep -NoNewLine -ForegroundColor DarkGray
            if ($isAdmin) { OutputInfo "Admin"     -NoNewLine -ForegroundColor Green }
            else          { OutputInfo "Not Admin" -NoNewLine -ForegroundColor Red }
            if ($isCurrent) {
                OutputInfo $sep           -NoNewLine -ForegroundColor DarkGray
                OutputInfo "Current User" -NoNewLine -ForegroundColor DarkYellow
                if ($script:odStatus) {
                    $odColor = if ($script:odStatus.Status -eq "Up-to-Date") {"Green"} else {"Red"}
                    OutputInfo $sep -NoNewLine -ForegroundColor DarkGray
                    OutputInfo "OneDrive: $($script:odStatus.Status)" -NoNewLine -ForegroundColor $odColor
                }
            }
            OutputInfo ""
        }
    } catch {
        $msg = if ($global:DomainStatus -eq "Local") {
            "Could not retrieve user list. VPN may be required."
        } else {
            "Could not retrieve user list."
        }
        OutputInfo "  $msg" -ForegroundColor Red
    }
    $ErrorActionPreference = "Continue"
}

function GetAdministrators {
    Write-Section "LOCAL ADMINISTRATORS"
    $machine = $env:COMPUTERNAME
    $ErrorActionPreference = "Stop"
    try {
        $admins   = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        $sidCount = 0
        $filtered = @()
        foreach ($adm in $admins) {
            if ($adm -like "S-1-12-1-*") { $sidCount++; continue }
            if ($adm -match "^(.+)\\(.+)$") {
                $dom  = $matches[1]
                $user = $matches[2]
                if (($user -ieq "Administrator" -or $user -like "WLaps*") -and $dom -ieq $machine) {
                    try {
                        $lu = Get-LocalUser -Name $user -ErrorAction Stop
                        if (-not $lu.Enabled) { continue }
                    } catch { }
                }
            }
            $filtered += $adm
        }
        if ($filtered.Count -eq 0) {
            OutputInfo "  No local administrators found." -ForegroundColor Gray
        } else {
            foreach ($adm in $filtered) {
                if ($adm -match "^(.+)\\(.+)$") {
                    $dom  = $matches[1]
                    $user = $matches[2]
                    if ($dom -ieq $machine) {
                        $isConcern = ($user -ieq "Administrator" -or $user -like "WLaps*")
                        OutputInfo "  $dom\" -NoNewLine -ForegroundColor Yellow
                        OutputInfo $user    -NoNewLine -ForegroundColor $(if ($isConcern) {"Red"} else {"White"})
                        if ($isConcern) { OutputInfo "  [ENABLED - disable before delivery]" -NoNewLine -ForegroundColor Red }
                        OutputInfo ""
                    } else {
                        OutputInfo "  $dom\" -NoNewLine -ForegroundColor Cyan
                        OutputInfo $user -ForegroundColor White
                    }
                } else {
                    OutputInfo "  $adm" -ForegroundColor White
                }
            }
        }
        if ($sidCount -gt 0) { OutputInfo "  SID Admins: $sidCount" -ForegroundColor DarkYellow }
    } catch {
        $msg = if ($DomainStatus -eq "Local") {
            "Could not retrieve admins list. VPN may be required."
        } else {
            "Could not retrieve admins list."
        }
        OutputInfo "  $msg" -ForegroundColor Red
    }
    $ErrorActionPreference = "Continue"
}

### BEGIN DATA GATHERING ###
$script:CimSysEnc = Get-CimInstance Win32_SystemEnclosure -Property Manufacturer,ChassisTypes -ErrorAction SilentlyContinue | Select-Object -First 1
$script:CimBaseBd = Get-CimInstance Win32_BaseBoard -Property Manufacturer -ErrorAction SilentlyContinue | Select-Object -First 1

$wuJob = Start-Job -ScriptBlock {
    try {
        $searcher = New-Object -ComObject Microsoft.Update.Searcher
        $res = $searcher.Search("IsInstalled=0 and Type='Software'")
        return $res.Updates.Count
    } catch { return -1 }
}

$deviceName = Get-DeviceName
$serial    = Get-SerialNumber
$osInfo    = Get-OSInfo
$actKey    = Get-ActivationKey
$hw        = Get-HWSummary
$domain    = Get-DomainInfo
$wsiOn     = Get-WSIStatus
$hello     = Get-HelloStatus
$bitlkr    = Get-BitLockerInfo -Escrow (-not $NoEscrow.IsPresent)
$tzInfo    = Get-TZInfo
$uac       = Get-UACLevel
try   { $power = Get-PowerSettings } catch { $power = $null }
$net       = Get-NetworkInfo
$disks     = Get-DiskSummary
$wifi      = Get-WiFiSSIDs
$printers  = Get-PrintersWithIP
$shortcuts = Get-PubDesktopShortcuts
foreach ($ex in $resolvedExtensions) {
    if (-not $ex.ID -or -not $ex.Name) { continue }
    if (-not $script:friendlyExtensions.ContainsKey($ex.ID)) { $script:friendlyExtensions[$ex.ID] = $ex.Name }
}
$allExts   = if ($script:IsRealUser) { Get-AllExtensions } else { $null }
$drv       = Get-DriverTool
$script:odStatus = if ($script:IsRealUser) { Get-OneDriveStatus } else { $null }

### REPORT ###

# Banner
OutputInfo "=== BuildReport v$ScriptVersion by PijiN ===" -ForegroundColor Black -BackgroundColor White -NoNewLine
$clientDisplayLine = "  Client: $($cfg.DisplayName)"
if ($resolvedLocation) { $clientDisplayLine += "  |  $resolvedLocation" }
OutputInfo $clientDisplayLine

if (-not $script:IsElevated) {
    OutputInfo "  [WARNING] Process is not elevated. Some results may be incomplete." -ForegroundColor Black -BackgroundColor Yellow
}

# >> SYSTEM IDENTITY
Write-Section "SYSTEM IDENTITY"
$hostname      = [System.Net.Dns]::GetHostName()
$hostTooLong   = $deviceName.Current.Length -gt 15
$hostNameColor = if ($hostTooLong) { "Red" } else { "Green" }
$hostBadge     = if ($deviceName.HasPending) { "[!!]" } else { "[~~]" }
$hostBadgeColor = if ($deviceName.HasPending) { "Red" } else { "DarkGray" }
OutputInfo "  $hostBadge  " -NoNewLine -ForegroundColor $hostBadgeColor
OutputInfo "Hostname".PadRight(30) -NoNewLine
OutputInfo " $($deviceName.Current)" -NoNewLine -ForegroundColor $(if ($deviceName.HasPending) { "Green" } else { $hostNameColor })
if ($deviceName.HasPending) {
    OutputInfo "  (pending: $($deviceName.Pending))" -NoNewLine -ForegroundColor Yellow
}
if ($hostTooLong) {
    OutputInfo "  (exceeds 15-char NetBIOS limit)" -NoNewLine -ForegroundColor DarkGray
}
if ($hostname -ine $deviceName.Current) {
    OutputInfo "  >>  " -NoNewLine -ForegroundColor DarkGray
    OutputInfo "DNS reports $hostname" -NoNewLine -ForegroundColor Red
    OutputInfo "  (reboot or re-enroll may be needed to sync)" -NoNewLine -ForegroundColor DarkGray
}
OutputInfo ""
Write-InfoLine "Serial Number"  $serial   $(if ($serial -eq "Not Found") {"Red"} else {"Green"})
Write-InfoLine "Current User"   $script:ExecutionUser $(if ($script:IsLocalAdminMember -eq $true) {"Green"} else {"Yellow"})
Write-InfoLine "Process Elevated" $(if ($script:IsElevated) {"Yes"} else {"No"}) $(if ($script:IsElevated) {"Green"} else {"Yellow"})
if ($null -eq $cfg.RequireLocalAdmin) {
    $adminMembership = if ($null -eq $script:IsLocalAdminMember) { "Unknown" } elseif ($script:IsLocalAdminMember) { "Yes" } else { "No" }
    $adminColor = if ($null -eq $script:IsLocalAdminMember) { "Yellow" } elseif ($script:IsLocalAdminMember) { "Green" } else { "White" }
    Write-InfoLine "Local Admin Membership" $adminMembership $adminColor
} elseif ($cfg.RequireLocalAdmin) {
    if ($null -eq $script:IsLocalAdminMember) { Write-Warn "Local Admin Membership" "Could not determine membership" }
    elseif ($script:IsLocalAdminMember)        { Write-Check "Local Admin Membership" $true  "Yes" }
    else                                       { Write-Check "Local Admin Membership" $false "User should have local admin" }
} else {
    if ($null -eq $script:IsLocalAdminMember) { Write-Warn "Local Admin Membership" "Could not determine membership" }
    elseif (-not $script:IsLocalAdminMember)  { Write-Check "Local Admin Membership" $true  "No" }
    else                                      { Write-Check "Local Admin Membership" $false "REVOKE LOCAL ADMIN BEFORE DELIVERY!" }
}
Write-InfoLine "Timestamp"      (Get-Date -Format "h:mm tt, dddd M/d/yyyy")

# >> OS AND HARDWARE
Write-Section "OS AND HARDWARE"
Write-InfoLine "OS"             $osInfo  "Cyan"
Write-InfoLine "Activation Key" $actKey  $(if ($actKey -eq "Not Found") {"Red"} else {"Green"})
Write-InfoLine "CPU"            $hw.CPU  "Cyan"
Write-InfoLine "GPU"            $hw.GPU  "Cyan"
Write-InfoLine "RAM"            $hw.RAM  "Cyan"
if ($wsiOn) { Write-Warn "Web Sign-In" "Enabled (should be disabled)" "Red" }

# >> DOMAIN
Write-Section "DOMAIN"
$expDomType = $cfg.ExpectedDomainType
if ($expDomType) {
    $typeMatch = $domain.Type -eq $expDomType
    $typeInfo  = if ($typeMatch) { $domain.Type } else { "$($domain.Type)  (expected: $expDomType)" }
    Write-Check "Domain Type" $typeMatch $typeInfo
    if ($expDomType -and $cfg.ExpectedDomainName) {
        $nameMatch = $domain.Name -like "*$($cfg.ExpectedDomainName)*"
        $nameInfo  = if ($nameMatch) { $domain.Name } else { "$($domain.Name)  (expected: $($cfg.ExpectedDomainName))" }
        Write-Check "Domain Name" $nameMatch $nameInfo
    } else {
        Write-InfoLine "Domain Name" $domain.Name "White"
    }
} else {
    $domColor = switch ($domain.Type) {
        "Entra"  {"Cyan"}   "Hybrid" {"Yellow"}
        "Local"  {"Green"}  default  {"Red"}
    }
    Write-InfoLine "Domain" "$($domain.Type): $($domain.Name)" $domColor
}

# >> AGENTS
Write-Section "AGENTS"
foreach ($key in $AgentDefs.Keys) {
    $def      = $AgentDefs[$key]
    $found    = Test-AgentInstalled $def
    $required = $cfg.RequiredAgents -contains $key
    if (-not $script:ClientSelected) {
        $color = if ($found) { "Green" } else { "Red" }
        Write-InfoLine $def.DisplayName $(if ($found) {"Detected"} else {"Not Found"}) $color
    } elseif ($required -and $found)          { Write-Check $def.DisplayName $true  "Detected" }
    elseif  ($required -and -not $found)      { Write-Check $def.DisplayName $false "Not Found" }
    elseif  (-not $required -and $found)      { Write-Check $def.DisplayName $false "Detected" }
}

# >> FORBIDDEN SOFTWARE
$foundForbidden = @($ForbiddenDefs | Where-Object { Test-ForbiddenInstalled $_ })
if ($foundForbidden.Count -gt 0) {
    Write-Section "FORBIDDEN SOFTWARE"
    foreach ($def in $foundForbidden) {
        Write-Check $def.DisplayName $false "DETECTED - REMOVE BEFORE DELIVERY"
    }
    OutputInfo "  !!!FORBIDDEN SOFTWARE DETECTED - REMOVE BEFORE DELIVERY!!!" -ForegroundColor Red -BackgroundColor Black
}

# >> SECURITY
Write-Section "SECURITY"
$helloPolicyInfo = $hello.PolicyState
if ($hello.PolicySource) { $helloPolicyInfo += " ($($hello.PolicySource))" }
$helloIsComplianceCheck = $script:ClientSelected -and $null -ne $cfg.RequireHello

if (-not $helloIsComplianceCheck) {
    $policyColor = if ($null -eq $hello.Enabled) { "Yellow" } elseif ($hello.Enabled) { "Green" } else { "Gray" }
    $keyColor    = if ($null -eq $hello.Provisioned) { "Yellow" } elseif ($hello.Provisioned) { "DarkYellow" } else { "Gray" }
    Write-InfoLine "Hello Policy"  $helloPolicyInfo $policyColor
    Write-InfoLine "Hello Key/PIN" $hello.KeyState  $keyColor
} else {
    if ($null -eq $hello.Enabled) {
        Write-Warn "Hello Policy" "Unknown - verify policy manually"
    } else {
        $policyMatches = $hello.Enabled -eq [bool]$cfg.RequireHello
        $policyExpected = if ($cfg.RequireHello) { "enabled" } else { "disabled" }
        $policyResult = if ($policyMatches) { $helloPolicyInfo } else { "$helloPolicyInfo  (expected: $policyExpected)" }
        Write-Check "Hello Policy" $policyMatches $policyResult
    }

    if ($null -eq $hello.Provisioned) {
        Write-Warn "Hello Key/PIN" $hello.KeyState
    } elseif ($hello.Provisioned) {
        Write-Check "Hello Key/PIN" $false "Provisioned - remove PIN before delivery"
    } else {
        Write-Check "Hello Key/PIN" $true "Not provisioned"
    }
}

if ($null -eq $bitlkr.Enabled) {
    Write-Warn "BitLocker (C:)" "Elevated process required to read BitLocker status"
} elseif ($bitlkr.Enabled) {
    Write-Check "BitLocker (C:)" $true "Enabled"
    OutputInfo "           Recovery ID  : " -NoNewLine -ForegroundColor DarkGray
    OutputInfo $bitlkr.ID  -ForegroundColor Cyan
    OutputInfo "           Recovery Key : " -NoNewLine -ForegroundColor DarkGray
    OutputInfo $bitlkr.Key -ForegroundColor Green
} else {
    Write-Check "BitLocker (C:)" $false "DISABLED - encrypt before delivery"
}
if ($bitlkr.Escrow) {
    $escrowColor = if ($bitlkr.Escrow -like "*OK*") { "Green" }
                   elseif ($bitlkr.Escrow -like "Skipped*" -or $bitlkr.Escrow -like "Unavailable*") { "Yellow" }
                   elseif ($bitlkr.Escrow -like "Not applicable*") { "DarkGray" }
                   else { "Red" }
    OutputInfo "           Key Escrow   : " -NoNewLine -ForegroundColor DarkGray
    OutputInfo $bitlkr.Escrow -ForegroundColor $escrowColor
}

$uacColor = if ($uac -like "*lvl 2*" -or $uac -like "*lvl 0*") {"Green"} else {"Yellow"}
Write-InfoLine "UAC Level" $uac $uacColor

# >> POWER AND SLEEP
Write-Section "POWER AND SLEEP"
if ($power) {
    Show-PowerValue "Battery Screen Timeout" $power.BatScreen $cfg.PowerBatteryScreen
    Show-PowerValue "Battery Sleep Timeout"  $power.BatSleep  $cfg.PowerBatterySleep
    Show-PowerValue "AC Screen Timeout"      $power.ACScreen  $cfg.PowerACScreen
    Show-PowerValue "AC Sleep Timeout"       $power.ACSleep   $cfg.PowerACSleep
} else {
    Write-Warn "Power Settings" "Could not read power settings (admin required)" "Red"
}

# >> CONFIGURATION
Write-Section "CONFIGURATION"
$mdsPath = Join-Path $workingDir "MDS"
if (Test-Path $mdsPath) {
    Write-Check "MDS Directory" $true  "Present ($mdsPath)"
} else {
    Write-Check "MDS Directory" $false "Not found - configuration scripts may not have run"
}
if ($cfg.ExpectedTimezone) {
    $tzMatch = $tzInfo.Id -eq $cfg.ExpectedTimezone
    $tzInfo2 = if ($tzMatch) { $tzInfo.Id } else { "$($tzInfo.Id)  (expected: $($cfg.ExpectedTimezone))" }
    Write-Check "Timezone" $tzMatch $tzInfo2
} else {
    $tzColor = if ($tzInfo.Id -like "*Eastern*") {"Green"} else {"Yellow"}
    Write-InfoLine "Timezone" $tzInfo.DisplayName $tzColor
}
# >> CLIENT APPLICATIONS
if ($resolvedApps.Count -gt 0) {
    Write-Section "CLIENT APPLICATIONS"
    foreach ($app in $resolvedApps) {
        $found = Test-AppInstalled $app
        Write-Check $app.Name $found $(if ($found) {"Detected"} else {"Not Found"})
    }
}

# >> WI-FI NETWORKS
Write-Section "WI-FI NETWORKS"
$allSSIDs = @($wifi.System) + @($wifi.User)
if ($resolvedWiFi.Count -gt 0) {
    foreach ($ssid in $resolvedWiFi) {
        $found = $allSSIDs -contains $ssid
        Write-Check $ssid $found $(if ($found) {"Found"} else {"Not in known networks"})
    }
}
$otherSystem = @($wifi.System | Where-Object { $resolvedWiFi -notcontains $_ })
$otherUser   = @($wifi.User   | Where-Object { $resolvedWiFi -notcontains $_ })
if ($otherSystem.Count -gt 0 -or $otherUser.Count -gt 0) {
    $label = if ($resolvedWiFi.Count -gt 0) { "  Other Known Networks:" } else { "  Known Networks:" }
    OutputInfo $label -ForegroundColor DarkGray
    $counter = 0
    foreach ($ssid in $otherSystem) {
        $counter++
        $color = if ($counter % 2 -eq 0) {"Gray"} else {"White"}
        OutputInfo "    `"$ssid`"" -ForegroundColor $color
    }
    foreach ($ssid in $otherUser) {
        OutputInfo "    `"$ssid`"*" -ForegroundColor Red
    }
    if ($otherUser.Count -gt 0) {
        OutputInfo "    (* = user-specific profile, not machine-wide)" -ForegroundColor DarkGray
    }
} elseif ($allSSIDs.Count -eq 0) {
    OutputInfo "  No known Wi-Fi networks." -ForegroundColor DarkGray
}

# >> MAPPED PRINTERS
if (-not $script:ClientSelected) {
    Write-Section "MAPPED PRINTERS"
    if ($printers.Count -gt 0) {
        foreach ($p in $printers) {
            $ip = if ($p.IP) { $p.IP } else { "N/A" }
            OutputInfo "  $($p.Name)  ($ip)" -ForegroundColor Gray
        }
    } else {
        OutputInfo "  No mapped printers found." -ForegroundColor DarkGray
    }
} elseif ($resolvedPrinters.Count -gt 0) {
    Write-Section "MAPPED PRINTERS"
    foreach ($exp in $resolvedPrinters) {
        $match   = $printers | Where-Object { $_.Name -ieq $exp.Name }
        $checkIP = $exp.IP -and $exp.IP -notmatch '^https?://'
        if (-not $match) {
            Write-Check $exp.Name $false "Not found"
        } elseif ($checkIP -and $match.IP -ne $exp.IP) {
            Write-Warn  $exp.Name "Found but wrong IP: $($match.IP)  (expected: $($exp.IP))"
        } else {
            Write-Check $exp.Name $true $(if ($match.IP) { $match.IP } else { "Found" })
        }
    }
}

# >> PUBLIC DESKTOP SHORTCUTS
if (-not $script:ClientSelected) {
    Write-Section "PUBLIC DESKTOP SHORTCUTS"
    if ($shortcuts.Count -gt 0) {
        $counter = 0
        foreach ($sc in $shortcuts) {
            $counter++
            $color = if ($counter % 2 -eq 0) {"Gray"} else {"White"}
            OutputInfo "  $sc" -ForegroundColor $color
        }
    } else {
        OutputInfo "  No shortcuts on public desktop." -ForegroundColor DarkGray
    }
} elseif ($resolvedShortcuts.Count -gt 0) {
    Write-Section "EXPECTED SHORTCUTS"
    foreach ($sc in $resolvedShortcuts) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables([string]$sc)
        if (-not [IO.Path]::IsPathRooted($expandedPath)) {
            $expandedPath = Join-Path "C:\Users\Public\Desktop" $expandedPath
        }
        $leaf  = Split-Path $expandedPath -Leaf
        $found = Test-Path -Path $expandedPath
        Write-Check $leaf $found $(if ($found) { "Found" } else { "Not found: $expandedPath" })
    }
}

# >> BROWSER BOOKMARKS
if ($script:IsRealUser -and $resolvedBookmarks.Count -gt 0) {
    Write-Section "BROWSER BOOKMARKS"
    foreach ($bm in $resolvedBookmarks) {
        $label = "$($bm.Browser) - $($bm.URLContains)"
        $found = Test-BookmarkPresent -Browser $bm.Browser -URLContains $bm.URLContains
        Write-Check $label $found $(if ($found) {"Found"} else {"Not found in bookmarks"})
    }
}

# >> UPDATES
Write-Section "UPDATES"
$wuJob | Wait-Job -Timeout 90 | Out-Null
if ($wuJob.State -eq 'Running') {
    Stop-Job $wuJob | Out-Null
    Write-Warn "Windows Updates" "Timed out checking for updates" "Yellow"
} else {
    $wuCount = Receive-Job $wuJob
    if ($wuCount -eq -1) {
        Write-Warn "Windows Updates" "Could not query Windows Update (admin/service may be required)" "Yellow"
    } elseif ($wuCount -eq 0) {
        Write-Check "Windows Updates" $true  "Up to date"
    } else {
        Write-Check "Windows Updates" $false "$wuCount update(s) available!"
    }
}
Remove-Job $wuJob -Force -ErrorAction SilentlyContinue

if ($drv.Mfr -like "Microsoft*") {
    # Microsoft Surface: Windows Update handles drivers
} elseif ($drv.Tool -ne "N/A (unrecognized manufacturer)") {
    if ($drv.Installed) {
        Write-Check $drv.Tool $true "Installed - Complete all updates before delivery"
    } elseif ($drv.ScriptPresent) {
        Write-Check $drv.Tool $true "Updates script present ($($drv.ScriptPath)) - Complete all updates before delivery"
    } else {
        Write-Check $drv.Tool $false "Not installed - Install and complete all updates before delivery"
    }
} else {
    Write-Warn "Driver Update Tool" "Unrecognized manufacturer ($($drv.Mfr)) - check manually" "Yellow"
}

# >> STORAGE
Write-Section "STORAGE"
foreach ($d in $disks) {
    $freeColor = if ($d.FreeGB -le 50) {"Red"} elseif ($d.FreeGB -le 100) {"Yellow"} else {"Green"}
    OutputInfo "  $($d.Drive)\ " -NoNewLine -ForegroundColor $freeColor
    OutputInfo "$($d.Type) | " -NoNewLine -ForegroundColor DarkGray
    OutputInfo "$($d.TotalGB)GB total | " -NoNewLine -ForegroundColor White
    OutputInfo "$($d.FreeGB)GB free" -ForegroundColor $freeColor
}

# >> NETWORK
Write-Section "NETWORK"
$netTypeColor = switch ($net.Type) { "Ethernet" {"Green"} "WiFi" {"Cyan"} "No Internet" {"Red"} default {"Yellow"} }
Write-InfoLine "Connection Type" $net.Type $netTypeColor
Write-InfoLine "MAC Address"     $net.MAC  $(if ($net.MAC -eq "Timeout" -or $net.MAC -eq "Not Found") {"Red"} else {"Green"})
Write-InfoLine "Internal IP"     $net.IntIP $(if ($net.IntIP -eq "N/A" -or $net.IntIP -eq "Timeout") {"Red"} else {"Green"})
Write-InfoLine "External IP"     $net.ExtIP $(if ($net.ExtIP -eq "N/A" -or $net.ExtIP -eq "Timeout") {"DarkGray"} else {"Green"})

# >> USER ACCOUNTS AND ADMINS
GetRealUserAccounts
GetAdministrators

# >> BROWSER EXTENSIONS
Write-Section "BROWSER EXTENSIONS (Current User)" "DarkCyan"
if ($script:IsRealUser -and $allExts) {
    if ($resolvedExtensions.Count -gt 0) {
        foreach ($ex in $resolvedExtensions) {
            $label = "$($ex.Name) ($($ex.Browser))"
            $found = switch ($ex.Browser.ToLower()) {
                "edge"   { $allExts.EdgeIDs   -contains $ex.ID }
                "chrome" { $allExts.ChromeIDs -contains $ex.ID }
                default  { $false }
            }
            Write-Check $label $found $(if ($found) {"Detected"} else {"Not installed"})
        }
    }
    Write-ExtList "Edge"   $allExts.Edge
    Write-ExtList "Chrome" $allExts.Chrome
} else {
    OutputInfo "  Skipped (running as service account)." -ForegroundColor DarkGray
}

# >> DEFAULT APPS
if ($script:IsRealUser) {
    Write-Section "DEFAULT APPS (Current User)" "DarkCyan"
    $appLabels = @{ ".html" = "Web Browser  "; ".pdf" = "PDF Viewer   "; ".pst" = "Email Client " }
    foreach ($ext in @(".html",".pdf",".pst")) {
        OutputInfo "  $($appLabels[$ext]): " -NoNewLine -ForegroundColor White
        GetFriendlyDefaultApp $ext
    }
}

# Flush any trailing partial line
if ($script:pendingSegs.Count -gt 0) {
    $script:reportData.Add(@{ Kind = 'Line'; Segs = [array]$script:pendingSegs })
    $script:pendingSegs = [System.Collections.Generic.List[hashtable]]::new()
}

# ##### WINFORMS REPORT WINDOW ######

# Type literals ([System.Drawing.Color] etc.) are blocked in ConstrainedLanguageMode.
# WDAC/AppLocker policies on production workstations commonly enforce CLM.
# Load WinForms only when the language mode permits it and the assemblies are available.
$winFormsAvailable = $false
$winFormsReason    = "LanguageMode: $($ExecutionContext.SessionState.LanguageMode)"
if ($ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage') {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $winFormsAvailable = $true
        $winFormsReason    = ""
    } catch {
        $winFormsReason = "WinForms unavailable: $($_.Exception.Message)"
    }
}

if ($winFormsAvailable) {

function ConvertTo-WFColor {
    param([string]$Name)
    switch ($Name) {
        'Black'       { return [System.Drawing.Color]::FromArgb(0,0,0)       }
        'DarkBlue'    { return [System.Drawing.Color]::FromArgb(0,0,139)     }
        'DarkGreen'   { return [System.Drawing.Color]::FromArgb(0,100,0)     }
        'DarkCyan'    { return [System.Drawing.Color]::FromArgb(0,139,139)   }
        'DarkRed'     { return [System.Drawing.Color]::FromArgb(139,0,0)     }
        'DarkMagenta' { return [System.Drawing.Color]::FromArgb(139,0,139)   }
        'DarkYellow'  { return [System.Drawing.Color]::FromArgb(160,160,0)   }
        'DarkGray'    { return [System.Drawing.Color]::FromArgb(105,105,105) }
        'Gray'        { return [System.Drawing.Color]::FromArgb(169,169,169) }
        'Blue'        { return [System.Drawing.Color]::FromArgb(80,80,255)   }
        'Green'       { return [System.Drawing.Color]::FromArgb(0,200,0)     }
        'Cyan'        { return [System.Drawing.Color]::FromArgb(0,210,210)   }
        'Red'         { return [System.Drawing.Color]::FromArgb(220,60,60)   }
        'Magenta'     { return [System.Drawing.Color]::FromArgb(200,0,200)   }
        'Yellow'      { return [System.Drawing.Color]::FromArgb(220,220,0)   }
        'White'       { return [System.Drawing.Color]::FromArgb(240,240,240) }
        default       { return [System.Drawing.Color]::FromArgb(200,200,200) }
    }
}

function ConvertTo-WFHeaderBG {
    param([string]$PSColor)
    switch ($PSColor) {
        'Cyan'     { return [System.Drawing.Color]::FromArgb(25,85,165)  }
        'DarkCyan' { return [System.Drawing.Color]::FromArgb(15,60,120)  }
        'Red'      { return [System.Drawing.Color]::FromArgb(140,0,0)    }
        'Yellow'   { return [System.Drawing.Color]::FromArgb(120,110,0)  }
        'Green'    { return [System.Drawing.Color]::FromArgb(0,105,0)    }
        default    { return [System.Drawing.Color]::FromArgb(55,55,55)   }
    }
}

# Parse reportData into section objects
$wfSections = [System.Collections.Generic.List[hashtable]]::new()
$wfCurrent  = $null
foreach ($entry in $script:reportData) {
    if ($entry.Kind -eq 'Section') {
        if ($null -ne $wfCurrent) { $wfSections.Add($wfCurrent) }
        $wfCurrent = @{
            Title = $entry.Title
            Color = $entry.SectionColor
            Lines = [System.Collections.Generic.List[object]]::new()
        }
    } elseif ($entry.Kind -eq 'Line' -and $null -ne $wfCurrent) {
        $wfCurrent.Lines.Add($entry.Segs)
    }
}
if ($null -ne $wfCurrent) { $wfSections.Add($wfCurrent) }

$wfSecByTitle = @{}
foreach ($s in $wfSections) { $wfSecByTitle[$s.Title] = $s }

$wfBGForm  = [System.Drawing.Color]::FromArgb(22,22,22)
$wfBGPanel = [System.Drawing.Color]::FromArgb(30,30,30)
$wfBGRTB   = [System.Drawing.Color]::FromArgb(38,38,38)
$wfFont    = New-Object System.Drawing.Font("Consolas", 8)
$wfFontHdr = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
$wfLineH   = $wfFont.Height

function New-WFSection {
    param($SecData, [int]$PanelWidth)

    $outer = New-Object System.Windows.Forms.Panel
    $outer.BackColor = $wfBGPanel
    $outer.Width     = $PanelWidth
    $outer.Margin    = New-Object System.Windows.Forms.Padding(0,0,0,3)

    $hdr = New-Object System.Windows.Forms.Label
    $hdr.Text      = " $($SecData.Title)"
    $hdr.Font      = $wfFontHdr
    $hdr.BackColor = ConvertTo-WFHeaderBG $SecData.Color
    $hdr.ForeColor = [System.Drawing.Color]::White
    $hdr.Height    = 18
    $hdr.Width     = $PanelWidth
    $hdr.Location  = New-Object System.Drawing.Point(0, 0)

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.ReadOnly    = $true
    $rtb.BorderStyle = 'None'
    $rtb.BackColor   = $wfBGRTB
    $rtb.Font        = $wfFont
    $rtb.ScrollBars  = 'None'
    $rtb.WordWrap    = $false
    $rtb.TabStop     = $false
    $rtb.Width       = $PanelWidth - 2
    $rtb.Location    = New-Object System.Drawing.Point(1, 19)

    for ($lineIndex = 0; $lineIndex -lt $SecData.Lines.Count; $lineIndex++) {
        $segs = $SecData.Lines[$lineIndex]
        foreach ($seg in $segs) {
            if ($null -ne $seg -and $null -ne $seg.Text) {
                $rtb.SelectionColor = ConvertTo-WFColor $seg.FG
                $rtb.AppendText($seg.Text)
            }
        }
        if ($lineIndex -lt ($SecData.Lines.Count - 1)) {
            $rtb.AppendText("`n")
        }
    }

    $lineCount  = [Math]::Max(1, $SecData.Lines.Count)
    $rtb.Height = $lineCount * $wfLineH + 3
    $rtb.SelectionStart  = 0
    $rtb.SelectionLength = 0

    $outer.Height = 19 + $rtb.Height + 1
    $outer.Controls.Add($hdr)
    $outer.Controls.Add($rtb)

    return $outer
}

function New-WFColumn {
    param([string[]]$Titles, [int]$X, [int]$Y, [int]$Width)

    $flp = New-Object System.Windows.Forms.FlowLayoutPanel
    $flp.FlowDirection = 'TopDown'
    $flp.WrapContents  = $false
    $flp.AutoScroll    = $false
    $flp.BackColor     = $wfBGForm
    $flp.Width         = $Width
    $flp.Location      = New-Object System.Drawing.Point($X, $Y)

    foreach ($title in $Titles) {
        if ($wfSecByTitle.ContainsKey($title)) {
            $sec = New-WFSection $wfSecByTitle[$title] ($Width - 2)
            $flp.Controls.Add($sec)
        }
    }

    $total = 0
    foreach ($ctrl in $flp.Controls) { $total += $ctrl.Height + 3 }
    $flp.Height = [Math]::Max(20, $total)

    return $flp
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# Layout constants
$wfColW0 = 560
$wfColW1 = 370
$wfColW2 = 560
$wfGap   = 6
$wfPad   = 4
$wfTopY  = 4

# Column section assignments
$wfLeftTitles   = @('SYSTEM IDENTITY','OS AND HARDWARE','DOMAIN','SECURITY','POWER AND SLEEP','CONFIGURATION','UPDATES','AGENTS')
$wfMiddleTitles = @('FORBIDDEN SOFTWARE','CLIENT APPLICATIONS','WI-FI NETWORKS','MAPPED PRINTERS','PUBLIC DESKTOP SHORTCUTS','EXPECTED SHORTCUTS')
$wfRightTitles  = @('BROWSER BOOKMARKS','STORAGE','NETWORK','USER ACCOUNTS','LOCAL ADMINISTRATORS','BROWSER EXTENSIONS (Current User)','DEFAULT APPS (Current User)')

$wfForm = New-Object System.Windows.Forms.Form
$wfFormTitle = "Build Report v$ScriptVersion  -  $($cfg.DisplayName)"
if ($resolvedLocation) { $wfFormTitle += "  |  $resolvedLocation" }
$wfForm.Text          = $wfFormTitle
$wfForm.BackColor     = $wfBGForm
$wfForm.StartPosition = 'CenterScreen'
$wfForm.AutoScroll    = $true
$wfForm.KeyPreview    = $true
$wfForm.Add_KeyDown({
    param($s,$e)
    if ($e.KeyCode -eq 'Escape') { $wfForm.Close() }
})

# Admin warning bar
$wfAdminLbl = $null
if (-not $script:IsElevated) {
    $wfAdminLbl = New-Object System.Windows.Forms.Label
    $wfAdminLbl.Text      = "  [WARNING] Process is not elevated - some results may be incomplete."
    $wfAdminLbl.BackColor = [System.Drawing.Color]::FromArgb(200,175,0)
    $wfAdminLbl.ForeColor = [System.Drawing.Color]::Black
    $wfAdminLbl.Font      = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
    $wfAdminLbl.Height    = 18
    $wfAdminLbl.Location  = New-Object System.Drawing.Point(0, 0)
    $wfForm.Controls.Add($wfAdminLbl)
    $wfTopY = 22
}

# Build the three columns
$wfCol0X = $wfPad
$wfCol1X = $wfPad + $wfColW0 + $wfGap
$wfCol2X = $wfPad + $wfColW0 + $wfGap + $wfColW1 + $wfGap

$wfCol0 = New-WFColumn $wfLeftTitles   $wfCol0X $wfTopY $wfColW0
$wfCol1 = New-WFColumn $wfMiddleTitles $wfCol1X $wfTopY $wfColW1
$wfCol2 = New-WFColumn $wfRightTitles  $wfCol2X $wfTopY $wfColW2

$wfForm.Controls.Add($wfCol0)
$wfForm.Controls.Add($wfCol1)
$wfForm.Controls.Add($wfCol2)

# Total width and form sizing
$wfTotalW  = $wfPad + $wfColW0 + $wfGap + $wfColW1 + $wfGap + $wfColW2 + $wfPad
$wfMaxColH = [Math]::Max($wfCol0.Height, [Math]::Max($wfCol1.Height, $wfCol2.Height))

# Set the warning bar to full width
if ($null -ne $wfAdminLbl) { $wfAdminLbl.Width = $wfTotalW }

# Size form to fit; AutoScroll handles overflow when window is resized smaller
$wfForm.ClientSize = New-Object System.Drawing.Size(
    $wfTotalW,
    ($wfTopY + $wfMaxColH + 8)
)

$wfForm.ShowDialog() | Out-Null
$wfForm.Dispose()
$wfFont.Dispose()
$wfFontHdr.Dispose()

} else {
    Write-Host ""
    Write-Host "  [~~] WinForms display skipped ($winFormsReason)." -ForegroundColor DarkGray
    Write-Host "       Full report is in the terminal above. Use -Log to save it." -ForegroundColor DarkGray
    if (-not $Log) { Write-Host ""; Read-Host "Press Enter to exit" }
}

# ##### LOG / EXIT ######
if ($Log) {
    $now     = Get-Date
    $logDir  = Join-Path $workingDir "logs"
    $logFile = Join-Path $logDir "BuildReport$([System.Net.Dns]::GetHostName())-$($now.ToString('MMddyy'))-$($now.ToString('HHmm')).log"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $script:output | Set-Content $logFile -Encoding UTF8
    Write-Host ""
    Write-Host "  Log saved: $logFile" -ForegroundColor Magenta
}

# CHANGELOG
# 0.0.1 - May-July 2026 - Release.
