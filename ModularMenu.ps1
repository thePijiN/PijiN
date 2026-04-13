#Requires -Version 5.1
#      ___           ___           ___           ___           ___       ___           ___                    ___           ___           ___           ___     
#     /  /\         /  /\         /  /\         /  /\         /  /\     /  /\         /  /\                  /  /\         /  /\         /  /\         /  /\    
#    /  /::|       /  /::\       /  /::\       /  /:/        /  /:/    /  /::\       /  /::\                /  /::|       /  /::\       /  /::|       /  /:/    
#   /  /:|:|      /  /:/\:\     /  /:/\:\     /  /:/        /  /:/    /  /:/\:\     /  /:/\:\              /  /:|:|      /  /:/\:\     /  /:|:|      /  /:/     
#  /  /:/|:|__   /  /:/  \:\   /  /:/  \:\   /  /:/        /  /:/    /  /::\ \:\   /  /::\ \:\            /  /:/|:|__   /  /::\ \:\   /  /:/|:|__   /  /:/      
# /__/:/_|::::\ /__/:/ \__\:\ /__/:/ \__\:| /__/:/     /\ /__/:/    /__/:/\:\_\:\ /__/:/\:\_\:\          /__/:/_|::::\ /__/:/\:\ \:\ /__/:/ |:| /\ /__/:/     /\
# \__\/  /~~/:/ \  \:\ /  /:/ \  \:\ /  /:/ \  \:\    /:/ \  \:\    \__\/  \:\/:/ \__\/~|::\/:/          \__\/  /~~/:/ \  \:\ \:\_\/ \__\/  |:|/:/ \  \:\    /:/
#       /  /:/   \  \:\  /:/   \  \:\  /:/   \  \:\  /:/   \  \:\        \__\::/     |  |:|::/                 /  /:/   \  \:\ \:\       |  |:/:/   \  \:\  /:/ 
#      /  /:/     \  \:\/:/     \  \:\/:/     \  \:\/:/     \  \:\       /  /:/      |  |:|\/                 /  /:/     \  \:\_\/       |__|::/     \  \:\/:/  
#     /__/:/       \  \::/       \__\::/       \  \::/       \  \:\     /__/:/       |__|:|~                 /__/:/       \  \:\         /__/:/       \  \::/   
#     \__\/         \__\/            ~~         \__\/         \__\/     \__\/         \__\|                  \__\/         \__\/         \__\/         \__\/    
# MODULAR MENU - Powershell 5.1 Utility by Alex DeMey
$ScriptVersion = '0.0.1' 

# region ### Mainmenu Header ###
function DetectLTAgent {return Test-Path "C:\Windows\LTSvC\LTErrors.txt"}
function DetectNinjaAgent {return Test-Path "C:\Program Files (x86)\NinjaOne\NinjaRMMAgent.exe"}
function DetectPiaAgent {return Test-Path "C:\Program Files (x86)\OrchestratorAgent\OrchestratorAgent.exe"}
function DetectCrowdstrike {return Test-Path "C:\Program Files\CrowdStrike"}
function DetectCloudRadial {return Test-Path "C:\Program Files (x86)\CloudRadial Agent\unins000.exe" }
function DetectNinite { return Test-Path "C:\Program Files (x86)\Ninite Agent\NiniteAgent.exe" }
function DetectImmyAgent { return Test-Path "C:\Program Files (x86)\ImmyBot\Immybot.Agent.exe" }
function DetectBlackpoint { return Test-Path "C:\Program Files (x86)\Blackpoint" }
function DetectHuntress { return Test-Path "C:\Program Files (x86)\Huntress" }
function GetJoinStatus { # Returns 1 word to indicate the Domain-Join status of the current device: Entra, Local, Hybrid, or None.
    try {
        $dsregOutput = dsregcmd /status
        # Extract the values for AzureAdJoined and DomainJoined
        $azureAdJoined = ($dsregOutput | Select-String "AzureAdJoined\s*:\s*(\w+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -eq 'YES'
        $domainJoined  = ($dsregOutput | Select-String "DomainJoined\s*:\s*(\w+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -eq 'YES'
        # Determine and display result
        if ($azureAdJoined -and $domainJoined) {
            Write-Host "Hybrid" -ForegroundColor Yellow -NoNewLine
        }
        elseif ($azureAdJoined) {
            Write-Host "Entra" -ForegroundColor Cyan -NoNewLine
        }
        elseif ($domainJoined) {
            Write-Host "Local" -ForegroundColor Green -NoNewLine
        }
        else {
            Write-Host "None" -ForegroundColor Red -NoNewLine
        }
    } catch {
        Write-Host "<ERROR>" -ForegroundColor Red -NoNewLine
    }
}
function GetAgentID { # Simplified version of PullAgentID - This just saves the Agent ID value (retrieved from registry) as $global:AgentID
    $global:AgentID = "N/A"
    try {
        $agentID = Get-ItemProperty -Path "HKLM:\SOFTWARE\LabTech\Service" -Name "ID" -ErrorAction Stop
        if ($agentID.ID -ne $null) {
            $global:AgentID = $agentID.ID
        }
    } catch {
        # Write-Host "Failed to retrieve Agent ID from registry: $_"
    }
}
function Show-Header {
    $cfg      = $script:MenuConfig
    $settings = $cfg.Settings
    $sep      = $settings.SeparatorChar * $settings.SeparatorWidth

    # --- ASCII Art (6 lines) ---
    $art = @(
        '______  ________  ______  ___'
        '| ___ \/  ___|  \/  ||  \/  |'
        '| |_/ /\ `--.| .  . || .  . |'
        '|  __/  `--. \ |\/| || |\/| |'
        '| |    /\__/ / |  | || |  | |'
        '\_|    \____/\_|  |_/\_|  |_/'
    )
    $artWidth = ($art | Measure-Object -Property Length -Maximum).Maximum

    # --- Collect data ---
    $hostname = $env:COMPUTERNAME

    $serial = try {
        (Get-CimInstance Win32_BIOS).SerialNumber.Trim()
    } catch { 'N/A' }

    GetAgentID  # populates $global:AgentID

    # --- Agent presence: Label => detect scriptblock ---
    $agentChecks = [ordered]@{
        NINJA1 = { DetectNinjaAgent }
        CRWDST = { DetectCrowdstrike }
		CLDRAD = { DetectCloudRadial }
        NINITE = { DetectNinite }
		PIA    = { DetectPiaAgent }
		LBTECH = { DetectLTAgent }
		HNTRSS = { DetectHuntress }
        BLKPNT = { DetectBlackpoint }
		IMMYBT = { DetectImmyAgent }
		
    }

    # Evaluate presence, split into two rows of ~5
    $agentResults = [ordered]@{}
    foreach ($name in $agentChecks.Keys) {
        $agentResults[$name] = (& $agentChecks[$name])
    }
    $agentNames = @($agentResults.Keys)
    $splitAt    = [math]::Ceiling($agentNames.Count / 2)
    $row1agents = $agentNames[0..($splitAt - 1)]
    $row2agents = $agentNames[$splitAt..($agentNames.Count - 1)]

    # --- Build right-column lines (same count as art = 6) ---
    # Line 0: separator
    # Line 1: Hostname + Serial
    # Line 2: Join status (built differently - needs inline color)
    # Line 3: LT ID
    # Line 4: Agents row 1
    # Line 5: Agents row 2
    # Line 6: separator (printed after the zip)

    # Helper: pad a plain string to fixed width
    function PadTo([string]$s, [int]$w) { $s.PadRight($w) }

    # Pre-build the plain-text portions we CAN measure
    $infoW = $settings.SeparatorWidth

    # --- Render: zip art + info lines ---

    # Line 0 - art line 0 + separator
    Write-Host ($art[0].PadRight($artWidth)) -NoNewLine -ForegroundColor DarkCyan
    Write-Host " $sep"                                  -ForegroundColor DarkGray

    # Line 1 - art line 1 + Host/Serial
    $hostLabel   = ' Host  : '
    $serialLabel = ' S/N: '
    Write-Host ($art[1].PadRight($artWidth)) -NoNewLine -ForegroundColor DarkCyan
    Write-Host $hostLabel   -NoNewLine -ForegroundColor DarkGray
    Write-Host $hostname    -NoNewLine -ForegroundColor Cyan
    # pad to align serial column
    $usedAfterArt = $hostLabel.Length + $hostname.Length
    $padNeeded    = ($infoW - $usedAfterArt - $serialLabel.Length - $serial.Length)
    if ($padNeeded -lt 1) { $padNeeded = 1 }
    Write-Host (' ' * $padNeeded) -NoNewLine
    Write-Host $serialLabel -NoNewLine -ForegroundColor DarkGray
    Write-Host $serial               -ForegroundColor Yellow

    # Line 2 - art line 2 + Join status
    Write-Host ($art[2].PadRight($artWidth)) -NoNewLine -ForegroundColor DarkCyan
    Write-Host ' Domain: ' -NoNewLine -ForegroundColor DarkGray
    GetJoinStatus   # writes its colored word, no newline
    Write-Host ''   # close the line

	# Line 3 - art line 3 + whoami + LT Agent ID
    $ltLabel = ' LT ID: '
    $ltVal   = "$global:AgentID"
    $ltColor = if ($global:AgentID -eq 'N/A') { 'Red' } else { 'Green' }
    $currentUserDomain, $currentUser = (whoami) -split '\\'
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $userColor = if ($isAdmin) { 'DarkYellow' } else { 'DarkCyan' }
    Write-Host ($art[3].PadRight($artWidth)) -NoNewLine -ForegroundColor DarkCyan
    Write-Host ' Ran As: ' -NoNewLine -ForegroundColor DarkGray
    Write-Host $currentUserDomain -NoNewLine -ForegroundColor Blue
    Write-Host '\' -NoNewLine -ForegroundColor DarkGray
    Write-Host $currentUser -NoNewLine -ForegroundColor $userColor
    Write-Host $ltLabel -NoNewLine -ForegroundColor DarkGray
    Write-Host $ltVal             -ForegroundColor $ltColor

    # Line 4 - art line 4 + Agents row 1
    Write-Host ($art[4].PadRight($artWidth)) -NoNewLine -ForegroundColor DarkCyan
    Write-Host ' Agents: ' -NoNewLine -ForegroundColor DarkGray
    foreach ($name in $row1agents) {
        $color = if ($agentResults[$name]) { 'Green' } else { 'DarkGray' }
        Write-Host "$name " -NoNewLine -ForegroundColor $color
    }
    Write-Host ''

    # Line 5 - art line 5 + Agents row 2 (indented to align under row 1)
    $agentIndent = ' ' * (' Agents: '.Length)
    Write-Host ($art[5].PadRight($artWidth)) -NoNewLine -ForegroundColor DarkCyan
    Write-Host $agentIndent -NoNewLine
    foreach ($name in $row2agents) {
        $color = if ($agentResults[$name]) { 'Green' } else { 'DarkGray' }
        Write-Host "$name " -NoNewLine -ForegroundColor $color
    }
    Write-Host ''

    # Closing separator
	Write-Host "------| " -NoNewLine -ForegroundColor DarkGray
	Write-Host "Version: " -NoNewLine -ForegroundColor Gray
	Write-Host "$ScriptVersion" -NoNewLine -ForegroundColor Green
	Write-Host " |" -NoNewLine -ForegroundColor DarkGray
    #Write-Host (' ' * $artWidth) -NoNewLine # Empty space
    Write-Host "-------$sep" -ForegroundColor DarkGray
}
#endregion 

$script:MenuConfig = @{

    # ----- MENUS -----
    # Each menu has a Title and an Items array.
    # Each item needs: Label, and either Action (a scriptblock) or Submenu (menu key string). Optional Desc for description. 
    # Optional: Separator = $true renders a visual divider (no selection).

    Menus = @{

		Main = @{
            Title = 'Main Menu'
            Items = @(
                @{ Label = 'Separator';     Color = 'DarkYellow'; Desc = '~ Main Menu ~';              Separator = $true }
                @{ Label = 'Reporting';     Color = 'Yellow';     Desc = '    - Gather information';   Submenu = 'Reporting' }
                @{ Label = 'Configuration'; Color = 'Yellow';     Desc = '- Change system settings'; Submenu = 'Configuration' }
                @{ Label = 'Utility';       Color = 'Yellow';     Desc = '      - Tools and cleanup'; Submenu = 'Utility' }
                @{ Label = 'Intune';        Color = 'Yellow';     Desc = '       - Intune tooling';  Submenu = 'Intune' }
                @{ Label = 'Separator';                                                               Separator = $true }
                @{ Label = 'About';         Color = 'White';      Desc = 'Info / help';              Action = { Show-About } }
                @{ Label = 'Report Bug';    Color = 'Red';        Desc = 'Submit feedback';          Action = { Report-Bug } }
                @{ Label = 'Spacegame';     Color = 'DarkCyan';   Desc = 'Try your luck';            Action = { RunExternalScript -noLog -ScriptURL "https://raw.githubusercontent.com/thePijiN/PijiN/refs/heads/main/Spacegame.ps1" } }
            )
        }
 
        Reporting = @{
            Title = 'Reporting'
            Items = @(
                @{ Label = 'Separator';             Color = 'Cyan'; Desc = 'System Info';                                               Separator = $true }
                @{ Label = 'Report Installed Apps'; Desc = 'Name, publisher, version, uninstall string';  Action = { Get-SystemReport } }
                @{ Label = 'Report Printer Info';   Desc = 'Name, driver, port, default, status';         Action = { Get-SystemReport -Printers } }
                @{ Label = 'Find App in Registry';  Desc = 'Search uninstall hives by display name';      Action = { FindAppRegHive } }
                @{ Label = 'Separator';             Color = 'Cyan'; Desc = 'Windows';                                                   Separator = $true }
                @{ Label = 'Show Activation Key';   Desc = 'OA3 firmware key (OEM/retail)';               Action = { Show-WindowsActivation } }
                @{ Label = 'Export WiFi Profiles';  Desc = 'Saves .xml files with plaintext passwords';   Action = { Export-WiFiProfiles } }
            )
        }
 
        Configuration = @{
            Title = 'Configuration'
            Items = @(
                @{ Label = 'Separator';                     Color = 'Cyan'; Desc = 'System';                                                            Separator = $true }
                @{ Label = 'Rename Computer';               Desc = 'Set hostname, prompt to reboot';                    Action = { Rename-Computer-Prompt } }
                @{ Label = 'Set Timezone';                  Desc = 'EST / CST / MST / PST and more';                    Action = { Set-TimezoneMenu } }
                @{ Label = 'Set Power Plan';                Desc = 'Always On, standard, or custom screen timeout';     Action = { Set-PowerPlan } }
                @{ Label = 'Toggle Taskbar Seconds';        Desc = 'Show/hide seconds in the clock';                    Action = { ToggleTaskbarSeconds } }
                @{ Label = 'Separator';                     Color = 'Cyan'; Desc = 'Sign-In';                                                           Separator = $true }
                @{ Label = 'Clear Windows HELLO PIN';       Desc = 'Requires SYSTEM - clears Ngc + disables policy';   Action = { ClearPin } }
                @{ Label = 'Disable Enrollment Checks';     Desc = 'Skip first sign-in status pages after Entra join';  Action = { DisableEnrollmentChecksOnSignIn } }
                @{ Label = 'Enable Web Sign-On';            Desc = 'Enable WSI + Windows HELLO + UAC via registry';     Action = { EnableWenSignOn } }
                @{ Label = 'Disable Web Sign-On';           Desc = 'Remove WSI registry keys, optionally disable UAC';  Action = { DisableWebSignOn } }
                @{ Label = 'Separator';                     Color = 'Cyan'; Desc = 'BitLocker';                                                         Separator = $true }
                @{ Label = 'Activate BitLocker';            Desc = 'Enable encryption on C:\, attempt Entra backup';    Action = { ActivateBitlocker } }
                @{ Label = 'Rotate BitLocker Recovery Key'; Desc = 'Replace protector without decrypting';              Action = { ResetBitlockerKey } }
            )
        }
 
        Utility = @{
            Title = 'Utility'
            Items = @(
                @{ Label = 'Separator';                      Color = 'Cyan'; Desc = 'Maintenance';                                                      Separator = $true }
                @{ Label = 'Clear Temp Files';               Desc = 'Purge temp folders with size preview';          Action = { Clear-TempFiles } }
                @{ Label = 'Reset Network Stack';            Desc = 'Flush DNS, Winsock reset, release/renew IP';    Action = { Reset-NetworkStack } }
                @{ Label = 'Reset Print Spooler';            Desc = 'Stop spooler, clear queue, restart';            Action = { Reset-PrintSpooler } }
                @{ Label = 'Remove All Printers';            Desc = 'Wipe printers/drivers (spares virtual ones)';   Action = { Reset-PrinterSubsystem } }
                @{ Label = 'Manage Startup Items';           Desc = 'View/disable reg, folder, and task startups';   Action = { Manage-StartupItems } }
                @{ Label = 'Separator';                      Color = 'Cyan'; Desc = 'Tools';                                                            Separator = $true }
				@{ Label = 'PS2EXE Compiler'; 				 Desc = 'Guided ps2exe wrapper'; 						 Action = { Invoke-PS2EXE } }
				@{ Label = 'Image Resizer'; 				 Desc = 'Supply image, redefine height/width'; 			 Action = { Invoke-ImageResizer } }
                @{ Label = 'Open Shell as SYSTEM';           Desc = 'Launch PS or CMD via scheduled task';           Action = { Open-AsSystem } }
                @{ Label = 'Fix WinGet';                     Desc = 'Reset sources, repair, reinstall if needed';    Action = { FixWinGet-New } }
                @{ Label = 'Scan for Illegal Characters';    Desc = 'Detect/remediate non-ASCII in a script file';   Action = { DetectIllegalCharacters } }
                @{ Label = 'Separator';                      Color = 'DarkRed'; Desc = 'Upgrades';                                                      Separator = $true }
                @{ Label = 'Upgrade to Windows 11';          Desc = 'Download and launch Update Assistant';          Action = { Invoke-Windows11Upgrade } }
                @{ Label = 'Upgrade to Windows 11 (Silent)'; Desc = 'Same, unattended';                              Action = { Invoke-Windows11Upgrade -Silent } }
            )
        }
 
        Intune = @{
            Title = 'Intune Tools'
            Items = @(
                @{ Label = 'Separator';                 Color = 'Cyan'; Desc = 'Device';                                                            Separator = $true }
                @{ Label = 'Sync Intune Now';           Desc = 'Trigger immediate Intune/Entra sync';              Action = { IntuneSyncNow } }
                @{ Label = 'Intune Diagnostic';         Desc = 'HTML report of recent Intune deployments';         Action = { IntuneDiagnostic } }
                @{ Label = 'Export AutoPilot CSV';      Desc = 'Save hardware hash to PSMM\AutopilotCSV.csv';      Action = { IntuneAutopilotCSV } }
                @{ Label = 'Separator';                 Color = 'Cyan'; Desc = 'Packaging';                                                         Separator = $true }
                @{ Label = 'IntuneWinAppUtil';          Desc = 'Create .intunewin packages';                       Action = { IntuneWinAppUtil } }
                @{ Label = 'IntuneWinAppUtil Decoder';  Desc = 'Inspect/decode .intunewin packages';               Action = { IntuneWinAppUtilDecoder } }
            )
        }
 
    }
 
    # ####### MENU SETTINGS PANEL ########
    Settings = @{                        #
        RootMenu       = 'Main'          # - Which menu key to start on
        ExitKey        = 'E'             # - Key to exit/go back
        Prompt         = '::'            # - Prompt label
        KeyColor       = 'DarkYellow'    #
        SeparatorChar  = '-'             #
        SeparatorWidth = 50              #
        ItemColor      = 'Gray' # ! ===> # Trumped in Show-Menu; Items/submenus are colored separately.
    }#####################################
}

# region === FUNCTIONS ===
# region *** Essential ***
function RunExternalScript {
    [CmdletBinding()]
    param (
		[Parameter(Mandatory = $true)]
		[string]$ScriptUrl,
		[switch]$Wait,
		[switch]$Remove,
		[switch]$Hidden,
		[switch]$NoLog
	)

    $TableSAS = 'URL_TO_AZURE_STORAGE_TABLE'

    function Start-PreferredShell {
        param (
            [string[]]$ArgumentList,
            [switch]$Wait,
            [switch]$PassThru,
            [switch]$Elevated,
            [switch]$ForceClassic
        )

        $wtCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
        if ($wtCommand) { $wtPath = $wtCommand.Source } else { $wtPath = $null }

        if ($wtPath -and -not $ForceClassic) {
            $filePath = $wtPath
            $args     = "powershell.exe " + ($ArgumentList -join ' ')
        } else {
            $filePath = "powershell.exe"
            $args     = $ArgumentList
        }

        $params = @{ FilePath = $filePath; ArgumentList = $args }
        if ($Elevated) { $params.Verb    = "RunAs" }
        if ($PassThru) { $params.PassThru = $true  }
        if ($Wait)     { $params.Wait     = $true  }

        return Start-Process @params
    }

    # Separate launcher for CMD/BAT - no PS wrapper needed, just cmd.exe
    function Start-CmdShell {
        param (
            [string]$FilePath,
            [switch]$Wait,
            [switch]$PassThru,
            [switch]$Elevated,
            [switch]$Hidden
        )

        $params = @{
            FilePath     = "cmd.exe"
            ArgumentList = "/c `"$FilePath`""
        }
        if ($Elevated) { $params.Verb        = "RunAs"  }
        if ($PassThru) { $params.PassThru    = $true    }
        if ($Wait)     { $params.Wait        = $true    }
        if ($Hidden)   { $params.WindowStyle = "Hidden" }

        return Start-Process @params
    }

    try {
        # ==========================================================
        # AUDIT LOGGING
        # ==========================================================
        if (-not $NoLog) {
            $estZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
            $estNow  = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $estZone)
            $Hostname = $env:COMPUTERNAME
            $Serial   = (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
            if (-not $Serial) { $Serial = "Unknown" }

            $IP = "Unknown"; $NetworkName = "Unknown"
            $netProfile = Get-NetConnectionProfile -ErrorAction SilentlyContinue |
                          Where-Object { $_.IPv4Connectivity -ne "Disconnected" } | Select-Object -First 1
            if ($netProfile) {
                $NetworkName = $netProfile.Name
                $ipObj = Get-NetIPAddress -InterfaceIndex $netProfile.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                         Where-Object { $_.IPAddress -notlike "169.254*" } | Select-Object -First 1
                if ($ipObj) { $IP = $ipObj.IPAddress }
            }

            $PartitionKey = $estNow.ToString("yyyy-MM")
            $RowKey       = $estNow.ToString("yyyyMMddHHmmss") + "_" + ([guid]::NewGuid().ToString("N"))
            $Entity = @{
                PartitionKey = $PartitionKey; RowKey       = $RowKey
                Hostname     = $Hostname;     SerialNumber = $Serial
                IPAddress    = $IP;           NetworkName  = $NetworkName
                ScriptUrl    = $ScriptUrl;    TimeEST      = $estNow.ToString("yyyy-MM-dd HH:mm:ss")
            }

            try {
                Invoke-RestMethod -Method Post -Uri $TableSAS `
                    -Headers @{ "Accept" = "application/json;odata=nometadata"; "Content-Type" = "application/json" } `
                    -Body ($Entity | ConvertTo-Json -Depth 5)
            } catch { Write-Warning "Audit logging failed: $_" }
        }

        # ==========================================================
        # DOWNLOAD TARGET SCRIPT
        # ==========================================================
        $tempFolder = "$env:TEMP\PSMM\scripts"
        if (-not (Test-Path $tempFolder)) { New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null }

        $uri      = [System.Uri]$ScriptUrl
        $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
        $ext      = [System.IO.Path]::GetExtension($fileName).ToLower()
        $tempPath = Join-Path $tempFolder $fileName

        # Validate extension
        if ($ext -notin @('.ps1', '.cmd', '.bat')) {
            throw "Unsupported file type '$ext'. Supported: .ps1, .cmd, .bat"
        }

        $isBatch = $ext -in @('.cmd', '.bat')

        Write-Host "Downloading $($ext.TrimStart('.').ToUpper()) from $ScriptUrl..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $ScriptUrl -OutFile $tempPath -UseBasicParsing
        Unblock-File -Path $tempPath -ErrorAction SilentlyContinue

        # ==========================================================
        # BATCH / CMD EXECUTION
        # ==========================================================
        if ($isBatch) {

            if ($Hidden) {
                Write-Host "Running hidden batch as admin..." -ForegroundColor Yellow
                if ($Wait) {
                    $proc = Start-CmdShell -FilePath $tempPath -PassThru -Elevated -Hidden
                    $proc.WaitForExit()
                    if ((Test-Path $tempPath) -and -not $Remove) { Remove-Item $tempPath -Force }
                } else {
                    Start-CmdShell -FilePath $tempPath -Elevated -Hidden
                }
            } else {
                Write-Host "Running batch as admin..." -ForegroundColor Yellow
                if ($Wait) {
                    $proc = Start-CmdShell -FilePath $tempPath -PassThru -Elevated
                    $proc.WaitForExit()
                    if ((Test-Path $tempPath) -and -not $Remove) { Remove-Item $tempPath -Force }
                } else {
                    Start-CmdShell -FilePath $tempPath -Elevated
                }
            }

            # Self-delete for batch: append a del command via a tiny wrapper bat
            # (can't inject mid-run and can't use $Remove footer like PS can)
            if ($Remove) {
                $wrapperPath = Join-Path $tempFolder "rm_$fileName"
                @"
@echo off
call "$tempPath"
del /f /q "$tempPath"
del /f /q "%~f0"
"@ | Out-File -FilePath $wrapperPath -Encoding ASCII
                # Re-launch via wrapper instead - notify caller
                Write-Warning "-Remove for batch files uses a wrapper. Launching wrapper instead of original."
                $tempPath = $wrapperPath
            }

            Write-Host "Done." -ForegroundColor Green
            return
        }

        # ==========================================================
        # POWERSHELL - HIDDEN MODE
        # ==========================================================
        if ($Hidden) {

            $hideConsole = @'
Add-Type -Name Window -Namespace Console -MemberDefinition @"
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
"@
function Hide-ConsoleWindow {
    $consolePtr = [Console.Window]::GetConsoleWindow()
    [Console.Window]::ShowWindow($consolePtr, 0) | Out-Null
}
Hide-ConsoleWindow
'@
            $launcherPath    = Join-Path $tempFolder "launcher_$fileName"
            $launcherContent = $hideConsole + "`n. `"$tempPath`""

            if ($Remove) {
                $launcherContent += "`nStart-Sleep -Seconds 2; Remove-Item -LiteralPath '$launcherPath' -Force"
            }

            $launcherContent | Out-File -FilePath $launcherPath -Encoding UTF8

            Write-Host "Running hidden PS script as admin..." -ForegroundColor Yellow
            $psArgs = @("-NoExit", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$launcherPath`"")

            if ($Wait) {
                $proc = Start-PreferredShell -ArgumentList $psArgs -PassThru -Elevated -ForceClassic
                $proc.WaitForExit()
                if ((Test-Path $tempPath)     -and -not $Remove) { Remove-Item $tempPath     -Force }
                if ((Test-Path $launcherPath) -and -not $Remove) { Remove-Item $launcherPath -Force }
            } else {
                Start-PreferredShell -ArgumentList $psArgs -Elevated -ForceClassic
            }
        }

        # ==========================================================
        # POWERSHELL - VISIBLE MODE
        # ==========================================================
        else {

            if ($Remove) {
                $footer = @'

Start-Sleep -Seconds 2
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force
'@
                Add-Content -Path $tempPath -Value $footer -Encoding UTF8
            }

            Write-Host "Running PS script as admin..." -ForegroundColor Yellow
            $psArgs = @("-ExecutionPolicy", "Bypass", "-File", "`"$tempPath`"")

            if ($Wait) {
                $proc = Start-PreferredShell -ArgumentList $psArgs -PassThru -Elevated
                $proc.WaitForExit()
                if ((Test-Path $tempPath) -and -not $Remove) { Remove-Item $tempPath -Force }
            } else {
                Start-PreferredShell -ArgumentList $psArgs -Elevated
            }
        }

        Write-Host "Done." -ForegroundColor Green
    }
    catch {
        Write-Error "Something went wrong: $_"
    }
}
function SmartDownload {
    param (
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination
    )
    $fileName = [System.IO.Path]::GetFileName($Destination)
    try {
        Add-Type -AssemblyName System.Net.Http
        $client  = [System.Net.Http.HttpClient]::new()
        $request = [System.Net.Http.HttpRequestMessage]::new('GET', $Url)
        $request.Headers.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        if (-not $response.IsSuccessStatusCode) { throw "HTTP $($response.StatusCode)" }
        $totalBytes = $response.Content.Headers.ContentLength
        if (-not $totalBytes) { throw "Content-Length unavailable" }
        $inStream  = $response.Content.ReadAsStreamAsync().Result
        $outStream = [System.IO.File]::Create($Destination)
        $buffer    = New-Object byte[] 8192
        $read      = 0; $lastPct = -1
        while (($n = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $n)
            $read += $n
            $pct  = [math]::Floor($read / $totalBytes * 100)
            if ($pct -ne $lastPct) {
                $lastPct = $pct
                Write-Progress -Activity "Downloading $fileName" -Status "$read / $totalBytes bytes" -PercentComplete $pct
            }
        }
        $outStream.Close(); $client.Dispose()
        Write-Progress -Activity "Downloading $fileName" -Completed
    } catch {
        Write-Host "[!] HttpClient failed ($($_.Exception.Message)), falling back to Invoke-WebRequest..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
    }
}
function Show-About {
    Clear-Host
    $sep  = '=' * 60
    $sep2 = '-' * 60

    Write-Host ""
    Write-Host "  $sep" -ForegroundColor DarkGray
    Write-Host "  Modular Menu " -NoNewLine -ForegroundColor Cyan
	Write-Host "v" -NoNewLine -ForegroundColor DarkGray
	Write-Host "$ScriptVersion" -NoNewLine -ForegroundColor DarkYellow
    Write-Host " - " -NoNewLine -Foregroundcolor DarkGray
	Write-Host "A Powershell utility by Alex DeMey" -ForegroundColor DarkCyan
    Write-Host "  PowerShell $($PSVersionTable.PSVersion)  |  Host: $env:COMPUTERNAME" -ForegroundColor DarkGray
	
    Write-Host "  $sep2" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  WHAT IT IS" -ForegroundColor White
    Write-Host "  A modular menu framework;`n  Add submenus or actions to do whatever you want." -ForegroundColor DarkGray
    Write-Host "  Includes some built-in functions for common IT-related tasks." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $sep2" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  NAVIGATION" -ForegroundColor White
    Write-Host "  Enter the " -NoNewLine -ForegroundColor DarkGray
    Write-Host "[number]" -NoNewLine -ForegroundColor Yellow
    Write-Host " or " -NoNewLine -ForegroundColor DarkGray
    Write-Host "[exact label]" -NoNewLine -ForegroundColor Yellow
    Write-Host " of any item to select it." -ForegroundColor DarkGray
    Write-Host "  Press " -NoNewLine -ForegroundColor DarkGray
    Write-Host "[$($script:MenuConfig.Settings.ExitKey)]" -NoNewLine -ForegroundColor Yellow
    Write-Host " at any menu to go back or exit." -ForegroundColor DarkGray
    Write-Host "  Items marked " -NoNewLine -ForegroundColor DarkGray
    Write-Host "=>" -NoNewLine -ForegroundColor DarkCyan
    Write-Host " open a submenu." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $sep2" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  MENUS" -ForegroundColor White
    $menuDescriptions = [ordered]@{
        Deployment    = "Deploy, image , provision"
        Intune        = "Sync, package apps, report Intune info, make Intune changes"
        Configuration = "Rename, timezone, power plan, BitLocker, PIN, WebSignOn"
        Reporting     = "App/printer reports, activation key, WiFi export"
        Utility       = "Startup mgr, SYSTEM shell, network reset, temp cleanup, Win11 upgrade"
		WhateverElse  = "Anything else you add"
    }
    foreach ($menu in $menuDescriptions.Keys) {
        Write-Host "  " -NoNewLine
        Write-Host $menu.PadRight(16) -NoNewLine -ForegroundColor Cyan
        Write-Host $menuDescriptions[$menu] -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  $sep2" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  HEADER" -ForegroundColor White
    Write-Host "  Hostname, serial, join status, LT agent ID, and running user." -ForegroundColor DarkGray
    Write-Host "  Running user is " -NoNewLine -ForegroundColor DarkGray
    Write-Host "DarkYellow" -NoNewLine -ForegroundColor DarkYellow
    Write-Host " if admin, " -NoNewLine -ForegroundColor DarkGray
    Write-Host "DarkCyan" -NoNewLine -ForegroundColor DarkCyan
    Write-Host " if standard." -ForegroundColor DarkGray
    Write-Host "  Detected agents shown inline: " -NoNewLine -ForegroundColor DarkGray
    Write-Host "Green" -NoNewLine -ForegroundColor Green
    Write-Host " = present" -NoNewLine -ForegroundColor Gray
    Write-Host ", DarkGray" -NoNewLine -ForegroundColor DarkGray
    Write-Host " = absent." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  $sep2" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  NOTES" -ForegroundColor White
    Write-Host "  - Most deployment actions require an internet connection." -ForegroundColor DarkGray
    Write-Host "  - RunExternalScript calls are logged to " -NoNewLine -ForegroundColor DarkGray
    Write-Host "Azure Table Storage" -NoNewLine -ForegroundColor Yellow
    Write-Host ",`n    unless invoked with -noLog." -ForegroundColor DarkGray
    Write-Host "  - Pretty much anything stored is in " -NoNewLine -ForegroundColor DarkGray
    Write-Host '$env:TEMP\PSMM\' -NoNewLine -ForegroundColor Cyan
    Write-Host "." -ForegroundColor DarkGray
    Write-Host "  - WinGet installs run in the current session window." -ForegroundColor DarkGray
    Write-Host "  - WebSignOn toggles and PIN clear affect the current user." -ForegroundColor DarkGray
	Write-Host "  - " -NoNewLine -ForegroundColor DarkGray
	Write-Host "Always read selections before selecting them" -NoNewLine -ForegroundColor Red
	Write-Host "!" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  $sep" -ForegroundColor DarkGray
    Write-Host ""

    Pause-Menu
}
function Report-Bug {
    $TableSAS = 'YOUR_SAS_URL_HERE'

    Write-Host "`n  Report a Bug" -ForegroundColor Cyan
    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray
    Write-Host "  Describe the issue briefly:" -ForegroundColor DarkGray
    Write-Host ""
    $message = (Read-Host "  >").Trim()

    if (-not $message) {
        Write-Host "`n  Nothing entered. Cancelled." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 800
        return
    }

    try {
        $serial   = (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
        $username = $env:USERNAME
        $hostname = $env:COMPUTERNAME
        $now      = Get-Date
        $when     = $now.ToString("dd/MM/yyyy, hh:mm:ss tt")

        $entity = @{
            PartitionKey = $now.ToString("yyyy-MM")
            RowKey       = $now.ToString("yyyyMMddHHmmss") + "_" + ([guid]::NewGuid().ToString("N").Substring(0, 8))
            Message      = $message
            When         = $when
            Who          = "$hostname, $serial ($username)"
        }

        Invoke-RestMethod -Method Post -Uri $TableSAS `
            -Headers @{ "Accept" = "application/json;odata=nometadata"; "Content-Type" = "application/json" } `
            -Body ($entity | ConvertTo-Json -Depth 5) | Out-Null

        Write-Host "`n  [+] Bug report submitted. Thanks!" -ForegroundColor Green
        Write-Host "      $when  |  $hostname ($username)" -ForegroundColor DarkGray

    } catch {
        Write-Host "`n  [!] Failed to submit: $_" -ForegroundColor Red
    }

    Start-Sleep -Seconds 2
}
#endregion 
# region == Reporting ==
function Get-SystemReport { # Generate .txt report on Installed Apps or Printers (using -Printers)
    param(
        [switch]$Printers
    )
	$hostname = $env:COMPUTERNAME
	$dir = "$env:TEMP\PSMM"
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dateStamp  = Get-Date -Format "MM-dd-yyyy"
    $reportType = if ($Printers) { "PrinterReport" } else { "AppReport" }
    $fileName = "${hostname}_${reportType}_${dateStamp}.txt"
    $outputPath = Join-Path $dir $fileName
    $outputDir  = Split-Path $outputPath
    $divider    = '=' * 80
    $divMinor   = '-' * 80
    $lines      = [System.Collections.Generic.List[string]]::new()
    $isISE      = $Host.Name -eq 'Windows PowerShell ISE Host'
	Write-Host "Generating " -NoNewLine -ForegroundColor DarkCyan
	Write-Host "$reportType" -NoNewLine -ForegroundColor DarkYellow
	Write-Host "... " -ForegroundColor DarkCyan

    try {
        if ($Printers) {

            $allPrinters    = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)
            $defaultPrinter = ($allPrinters | Where-Object { $_.Default } | Select-Object -First 1).Name

            if (-not $allPrinters) { throw "No printers found." }

            $lines.Add($divider)
            $lines.Add("  PRINTER REPORT")
            $lines.Add("  Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  Host: $env:COMPUTERNAME  |  Total: $($allPrinters.Count)")
            $lines.Add($divider)
            $lines.Add("")

            foreach ($p in ($allPrinters | Sort-Object Name)) {
                $isDefault  = $p.Name -eq $defaultPrinter
                $defaultTag = if ($isDefault) { '  [DEFAULT]' } else { '' }
                $portIP     = (Get-CimInstance -ClassName Win32_TCPIPPrinterPort -Filter "Name='$($p.PortName)'" -ErrorAction SilentlyContinue).HostAddress

                $lines.Add("  $($p.Name)$defaultTag")
                $lines.Add("  Driver : $($p.DriverName)")
                $lines.Add("  Port   : $($p.PortName)$(if ($portIP) { "  ($portIP)" })")
                if ($p.ShareName) { $lines.Add("  Share  : \\$env:COMPUTERNAME\$($p.ShareName)") }
                if ($p.Location)  { $lines.Add("  Loc    : $($p.Location)") }
                if ($p.Comment)   { $lines.Add("  Note   : $($p.Comment)") }

                $status = switch ($p.PrinterStatus) {
                    1 { 'Other' } 2 { 'Unknown' } 3 { 'Idle' } 4 { 'Printing' }
                    5 { 'Warmup' } 6 { 'Stopped' } 7 { 'Offline' } default { "$($p.PrinterStatus)" }
                }
                $lines.Add("  Status : $status  |  Type: $(if ($p.Local) { 'Local' } else { 'Network' })")
                $lines.Add($divMinor)
            }

            $lines.Add("")
            $lines.Add("  END OF REPORT  --  $($allPrinters.Count) entries")

        } else {

            $regPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )

            $apps = $regPaths | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
                Where-Object { $_.DisplayName -and $_.DisplayName.Trim() } |
                Select-Object DisplayName, Publisher, DisplayVersion, InstallLocation,
                    @{ N='UninstallCmd'; E={ if ($_.QuietUninstallString) { $_.QuietUninstallString } else { $_.UninstallString } }},
                    @{ N='Silent';       E={ [bool]$_.QuietUninstallString }} |
                Sort-Object DisplayName

            if (-not $apps) { throw "No installed applications found in registry." }

            $lines.Add($divider)
            $lines.Add("  INSTALLED APPLICATIONS REPORT")
            $lines.Add("  Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  Host: $env:COMPUTERNAME  |  Total: $($apps.Count)")
            $lines.Add($divider)
            $lines.Add("")

            foreach ($app in $apps) {
                $publisher  = if ($app.Publisher) { $app.Publisher } else { 'Unknown Publisher' }
                $hasVersion = $app.DisplayVersion -and $app.DisplayVersion.Trim()
                $silentTag  = if ($app.Silent) { ' | (Silent Uninstall)' } else { '' }

                $lines.Add("  $($app.DisplayName)")
                if ($hasVersion) {
                    $lines.Add("  $publisher | v$($app.DisplayVersion)$silentTag")
                } else {
                    $lines.Add("  $publisher$silentTag")
                }
                if ($app.InstallLocation) { $lines.Add("  $($app.InstallLocation.Trim())") }
                if ($app.UninstallCmd)    { $lines.Add("  $($app.UninstallCmd.Trim())")    }
                $lines.Add($divMinor)
            }

            $lines.Add("")
            $lines.Add("  END OF REPORT  --  $($apps.Count) entries")
        }

        $lines.Add($divider)

        if (-not (Test-Path $outputDir)) { New-Item -Path $outputDir -ItemType Directory -Force | Out-Null }
        $lines | Out-File -FilePath $outputPath -Encoding UTF8 -Force

		Write-Host "`n  [+] Report saved: $outputPath" -ForegroundColor Green
		Write-Host "   > Press " -NoNewLine -ForegroundColor DarkGray
		Write-Host "ENTER" -NoNewLine -ForegroundColor Yellow
		Write-Host " to open in " -NoNewLine -ForegroundColor DarkGray
		Write-Host "Notepad" -NoNewLine -ForegroundColor Cyan
		Write-Host "..." -ForegroundColor DarkGray
		
		Write-Host "   > Press " -NoNewLine -ForegroundColor DarkGray
		Write-Host "any other key" -NoNewLine -ForegroundColor Yellow
		Write-Host " to continue..." -ForegroundColor DarkGray

		if ($isISE) {
			$key = Read-Host
			if ($key -eq "") { Start-Process notepad.exe $outputPath }
		} else {
			$input = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
			
			if ($input.VirtualKeyCode -eq 13) { 
				Start-Process notepad.exe $outputPath 
			}
		}

    } catch {
        Write-Host "`n  [!] Failed to generate report: $_" -ForegroundColor Red
        Write-Host "      Press any key to continue..." -ForegroundColor DarkGray
        if ($isISE) { Read-Host } else { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
    }
}
function FindAppRegHive { # Accepts an appname string and searches registry hives - reports paths to any found that relate to app 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$AppName
    )

    if (-not $AppName) {
        $AppName = Read-Host "[?] Enter the Appname string to search for"
    }

    if ([string]::IsNullOrWhiteSpace($AppName)) {
        Write-Host "[!] No application name entered. Exiting..." -ForegroundColor Red
        return
    }

    $searchRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    # Include per-user hives under HKEY_USERS
    if (Test-Path "HKU:\") {
        $hkuRoots = Get-ChildItem -Path "HKU:\" -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -notin @("S-1-5-18","S-1-5-19","S-1-5-20") } |
                    ForEach-Object { Join-Path -Path $_.PSPath -ChildPath "Software\Microsoft\Windows\CurrentVersion\Uninstall" } |
                    Where-Object { Test-Path $_ }
        $searchRoots += $hkuRoots
    }

    $foundKeys = @{}

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }

        try { $subkeys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue } catch { continue }

        foreach ($sk in $subkeys) {
            try {
                $regKey = Get-Item -LiteralPath $sk.PSPath -ErrorAction Stop
            } catch { continue }

            try { $valueNames = $regKey.GetValueNames() } catch { continue }

            foreach ($vName in $valueNames) {
                try {
                    $vKind = $regKey.GetValueKind($vName)
                    if ($vKind -in @([Microsoft.Win32.RegistryValueKind]::String, [Microsoft.Win32.RegistryValueKind]::ExpandString)) {
                        $vData = $regKey.GetValue($vName)
                        if ($null -ne $vData -and $vData -ne "" -and ($vData -imatch [regex]::Escape($AppName))) {
                            # Use key path as the dictionary key
                            if (-not $foundKeys.ContainsKey($sk.PSPath)) {
                                $foundKeys[$sk.PSPath] = @()
                            }
                            $foundKeys[$sk.PSPath] += [PSCustomObject]@{
                                Name = $vName
                                Data = $vData
                            }
                        }
                    }
                } catch { continue }
            }
        }
    }

    if (-not $foundKeys.Keys.Count) {
        Write-Host "[!] No matches found for '$AppName'." -ForegroundColor Red
        return
    }

    # Output results
    Write-Host "`n[~] Found $($foundKeys.Keys.Count) matching entries:`n" -ForegroundColor Cyan
    $keyList = @($foundKeys.Keys)
    for ($i=0; $i -lt $keyList.Count; $i++) {
        $idx = $i + 1
        $keyPath = $keyList[$i]
        Write-Host ("[{0}] Key: {1}" -f $idx, $keyPath) -ForegroundColor White
        foreach ($val in $foundKeys[$keyPath]) {
            Write-Host ("     Value: {0} = {1}" -f $val.Name, $val.Data) -ForegroundColor DarkGray
        }
    }

    # Prompt for selection
	Write-Host ''
    $sel = Read-Host "[>] Enter a number to Registry Key Path to clipboard (or don't to exit)"
    if ([string]::IsNullOrWhiteSpace($sel)) {
        Write-Host "[~] No selection made. Exiting." -ForegroundColor Yellow
        return
    }

    if (-not ([int]::TryParse($sel, [ref]$null))) {
        Write-Host "[!] Invalid input. Exiting." -ForegroundColor Red
        return
    }

    $selInt = [int]$sel
    if ($selInt -lt 1 -or $selInt -gt $keyList.Count) {
        Write-Host "[!] Selection out of range. Exiting." -ForegroundColor Red
        return
    }

    # Clean key path for Regedit copy
    $selectedKey = $keyList[$selInt - 1] -replace "^Microsoft\.PowerShell\.Core\\Registry::", "Computer\"
    try {
        Set-Clipboard -Value $selectedKey
        Write-Host "[+] Copied to clipboard:" -ForegroundColor Green -NoNewLine
        Write-Host " $selectedKey" -ForegroundColor Yellow
    } catch {
        Write-Host "[!] Failed to copy to clipboard: $($_.Exception.Message)" -ForegroundColor Red
    }
}
function Show-WindowsActivation { # Display current Windows activation license key
	$key = (Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey
	if ($key) {
		Write-Host "`n  Product Key: " -NoNewLine -ForegroundColor DarkGray
		Write-Host $key -ForegroundColor Cyan
	} else {
		Write-Host "`n  No OA3 key found in firmware." -ForegroundColor Yellow
		Write-Host "  This machine may use a digital license or volume key not stored in BIOS." -ForegroundColor DarkGray
	}
	Pause-Menu
}
function Export-WiFiProfiles { # Exports the WiFi connections in Known Networks as .xml files at $env:TEMP\PSMM\temp
    param ([string]$outputDirectory = "$env:TEMP\PSMM\temp")
    if (-not (Test-Path -Path $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
    netsh wlan export profile key=clear folder=$outputDirectory # Export each WiFi profile to a separate XML file with plaintext passwords
    Write-Host "[+] WiFi profiles exported to " -NoNewLine -ForegroundColor Green
	Write-Host "$outputDirectory" -NoNewLine -ForegroundColor DarkYellow
	Write-Host " with plaintext passwords." -ForegroundColor Green
	Write-Host "[!] Do not leave file(s) on disk; contains sensative information!" -ForegroundColor DarkRed
	Write-Host "`n^^^ Press any key to acknowledge ^^^" -NoNewLine -ForegroundColor Red
	Pause-Menu
}
#endregion 
# region == Configuration ==
function Rename-Computer-Prompt { # Ez force rename, with optional reboot prompt
    $newName = Read-Host "`n  Enter new computer name"
    if (-not $newName) {
        Write-Host "  No name entered. Cancelled." -ForegroundColor DarkGray
        return
    }
    try {
        Rename-Computer -NewName $newName -Force -ErrorAction Stop
        Write-Host "`n  Computer will be renamed to '" -NoNewLine -ForegroundColor DarkGray
        Write-Host $newName -NoNewLine -ForegroundColor Cyan
        Write-Host "' on next boot." -ForegroundColor DarkGray
        Write-Host "`n  Press " -NoNewLine -ForegroundColor DarkGray
        Write-Host "R" -NoNewLine -ForegroundColor Yellow
        Write-Host " to reboot now, or any other key to continue..." -ForegroundColor DarkGray
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($key.Character -eq 'r' -or $key.Character -eq 'R') {
            Restart-Computer -Force
        }
    } catch {
        Write-Host "`n  [!] Rename failed: $_" -ForegroundColor Red
        Pause-Menu
    }
}
function ResetBitlockerKey { # Remove existing Bitlocker Protector (does not decrypt!) and adds a new one. Allows backing up Bitlocker info when the option is missing due to GPO or similar.
	# 1. Get the current protector
	$bitlockerVolume = Get-BitLockerVolume -MountPoint "C:"
	$protector = $bitlockerVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
	# 2. Remove the existing recovery protector (does not decrypt volume)
	Remove-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $protector.KeyProtectorId
	# 3. Add a new recovery password protector
	$newProtector = Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector
}
function ActivateBitlocker { # Attempts to activate Bitlocker Encryption on the C:\ Drive
	function DetectBitlocker {
		try {
			$volume = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop

			if ($volume.VolumeStatus -eq "EncryptionInProgress") {
				Write-Host "[~] Bitlocker is enabled on 'C:\' - " -NoNewLine -ForegroundColor Green 
				Write-Host "encryption is currently IN PROGRESS." -ForegroundColor Yellow
				return $true
			}
			if ($volume.ProtectionStatus -eq "On") {
				Write-Host "[~] Bitlocker is enabled on 'C:\' - " -NoNewLine -ForegroundColor Green 
				Write-Host "Fully encrypted" -ForegroundColor Cyan 
				return $true
			}
			else {
				Write-Host "[~] Bitlocker is NOT enabled on 'C:\'" -ForegroundColor Red 
				return $false
			}
		}
		catch {
			Write-Host "[!] Failed to detect Bitlocker Encryption Status! (Likely disabled)" -ForegroundColor Red  
			return $false
		}
	}

	function ConfigureBitlocker {
		[CmdletBinding()]
		param()

		function GetBitlockerRecovery {
			$bitlockerInfo = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
			if (-not $bitlockerInfo) { return }

			$recoveryKeys = $bitlockerInfo.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
			if ($recoveryKeys.Count -eq 0) { return }

			# Use the last key
			$latestKey = $recoveryKeys[-1]

			[PSCustomObject]@{
				ProtectorID = $latestKey.KeyProtectorId
				RecoveryKey = $latestKey.RecoveryPassword
			}
		}

		try {
			if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
				[Security.Principal.WindowsBuiltInRole]::Administrator)) {
				throw "This function must be run as Administrator."
			}

			$volume = Get-BitLockerVolume -MountPoint "C:"

			if ($volume.ProtectionStatus -eq "On") {
				Write-Host "[!] BitLocker is already enabled on C: drive." -ForegroundColor Red 
			} else {
				Write-Host "[~] Preparing to enable BitLocker on C: drive..." -ForegroundColor Cyan

				if ($volume.ProtectionStatus -eq "Off" -and $volume.KeyProtector.Count -gt 0) {
					Write-Host "[*] Clearing existing protectors..." -ForegroundColor Yellow
					foreach ($kp in $volume.KeyProtector) {
						Remove-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $kp.KeyProtectorId | Out-Null
					}
				}

				if (-not ($volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "Tpm" })) {
					Add-BitLockerKeyProtector -MountPoint "C:" -TpmProtector | Out-Null
					Write-Host "[+] TPM protector added." -ForegroundColor Green
				}

				if (-not ($volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" })) {
					Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector | Out-Null
					Write-Host "[+] Recovery key added." -ForegroundColor Green
				}

				Write-Host "[*] Starting encryption with manage-bde..." -ForegroundColor Yellow
				Start-Process -FilePath "manage-bde.exe" -ArgumentList " -on C: -UsedSpaceOnly -SkipHardwareTest" -Wait -NoNewWindow
			}

			# Poll until BitLocker reports active (avoid hardcoded sleep)
			$timeout = [DateTime]::UtcNow.AddMinutes(5)
			do {
				Start-Sleep -Seconds 5
				$volume = Get-BitLockerVolume -MountPoint "C:"
			} while (($volume.ProtectionStatus -ne "On") -and ($volume.VolumeStatus -ne "EncryptionInProgress") -and (Get-Date -lt $timeout))

			if ($volume.ProtectionStatus -eq "On" -or $volume.VolumeStatus -eq "EncryptionInProgress") {
				Write-Host "[~] BitLocker is active on C: drive." -ForegroundColor Cyan
				$recovery = GetBitlockerRecovery
				if ($recovery) {
					Write-Host "===== BitLocker Recovery Info =====" -ForegroundColor Cyan -BackgroundColor Black 
					Write-Host "Protector ID : " -NoNewLine 
					Write-Host "$($recovery.ProtectorID)" -ForegroundColor Green
					Write-Host "Recovery Key : " -NoNewLine 
					Write-Host "$($recovery.RecoveryKey)" -ForegroundColor Green
				}

				$infoToCopy = "Protector ID: $($recovery.ProtectorID)`nRecovery Key: $($recovery.RecoveryKey)"
			} else {
				Write-Warning "[!] BitLocker did not activate within timeout. Check manage-bde manually."
			}
		} catch {
			Write-Error "[!] Failed to enable BitLocker: $_"
		}
	}

	function GetDomainStatus {
		$global:DomainStatus = ""
		$dsregOutput = dsregcmd /status

		$azureAdJoined = ($dsregOutput | Select-String "AzureAdJoined\s*:\s*(\w+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -eq 'YES'
		$domainJoined  = ($dsregOutput | Select-String "DomainJoined\s*:\s*(\w+)"   | ForEach-Object { $_.Matches[0].Groups[1].Value }) -eq 'YES'

		$localDomain = (Get-WmiObject -Class Win32_ComputerSystem).Domain
		$entraDomain = ""

		if ($azureAdJoined) {
			$aadInfo = $dsregOutput | Select-String "TenantName"
			if ($aadInfo) {
				$entraDomain = ($aadInfo.ToString() -replace 'TenantName\s*:\s*', '').Trim()
			}
		}

		if ($azureAdJoined -and $domainJoined) {
			$global:DomainStatus = "Hybrid"
			Write-Host "Hybrid ($localDomain/$entraDomain)" -ForegroundColor Yellow -NoNewLine
		}
		elseif ($azureAdJoined) {
			$global:DomainStatus = "Entra"
			Write-Host "Entra ($entraDomain)" -ForegroundColor Cyan -NoNewLine
		}
		elseif ($domainJoined) {
			$global:DomainStatus = "Local"
			Write-Host "Local ($localDomain)" -ForegroundColor Green -NoNewLine
		}
		else {
			$global:DomainStatus = "None"
			Write-Host "None" -ForegroundColor Red -NoNewLine
		}
	}

	function BackupBitLockerIfEntra {
		Write-Host "[~] Domain : " -NoNewLine -ForegroundColor Gray 
		GetDomainStatus ; Write-Host ""
		$status = $global:DomainStatus

		if ($status -in @("Entra","Hybrid")) {
			$bitlocker = Get-BitLockerVolume -MountPoint $env:SystemDrive
			$recoveryProtector = $bitlocker.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }

			if ($recoveryProtector) {
				$kpId = $recoveryProtector.KeyProtectorId
				try {
					BackupToAAD-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId $kpId
					Write-Host "BitLocker Recovery Info was backed up to Entra/Azure AD." -ForegroundColor Green
					Start-Sleep -Seconds 3 	
				} catch {
					Write-Host "Backup to Entra/Azure AD FAILED.`nError: $($_.Exception.Message)" -ForegroundColor Red
					Start-Sleep -Seconds 3 	
				}
			} else {
				Write-Host "No existing recovery protector found to back up." -ForegroundColor Yellow
				Start-Sleep -Seconds 3 	
			}
		} else {
			Write-Host "Domain type is not Entra/Hybrid. No backup attempted." -ForegroundColor Cyan
			Start-Sleep -Seconds 3 		
		}
	}

	function GetBitlockerRecovery {
		Write-Host "=== Bitlocker Recovery ===" -ForegroundColor Cyan -BackgroundColor DarkGray
		$bitlockerInfo = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue

		if (-not $bitlockerInfo -or $bitlockerInfo.ProtectionStatus -ne 'On') {
			Write-Host "Disabled" -ForegroundColor Red
			return
		}

		$recoveryKeys = $bitlockerInfo.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
		if ($recoveryKeys.Count -eq 0) {
			Write-Host "Enabled - NoRecovery!" -ForegroundColor Red
			return
		}

		$latestKey = $recoveryKeys[-1]
		$bitlockerID = $latestKey.KeyProtectorId
		$bitlockerRecoveryKey = $latestKey.RecoveryPassword

		Write-Host "Identifier: " -NoNewLine
		Write-Host "$bitlockerID" -ForegroundColor Yellow
		Write-Host "Recovery Key: " -NoNewLine
		Write-Host "$bitlockerRecoveryKey" -ForegroundColor Green
		
		$infoToCopy = "Identifier: $bitlockerID`nRecovery Key: $bitlockerRecoveryKey"

		do {
			$inputYN = Read-Host "[?] Copy to clipboard? Y/N"
			if ($inputYN -match '^[YyNn]$') {
				if ($inputYN -match '^[Yy]$') {
					Set-Clipboard -Value $infoToCopy
					Write-Host "[+] Copied BitLocker info to clipboard." -ForegroundColor Green 
				} else {
					Write-Host "[~] Not copied." -ForegroundColor Yellow
				}
			} else {
				Write-Host "[!] Invalid input. Please enter Y or N." -ForegroundColor Red
			}
		} while ($inputYN -notmatch '^[YyNn]$')

		# NEW: Prompt to save .txt in $env:TEMP\PSMM\
		do {
			$saveYN = Read-Host "[?] Generate .txt with recovery info at $env:TEMP\PSMM\? Y/N"
			if ($saveYN -match '^[YyNn]$') {
				if ($saveYN -match '^[Yy]$') {
					$serial = (Get-WmiObject Win32_BIOS).SerialNumber
					$folder = "$env:TEMP\PSMM"
					if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory | Out-Null }
					$filePath = Join-Path $folder "$serial`_Bitlocker.txt"
					$infoToCopy | Out-File -FilePath $filePath -Encoding UTF8 -Force
					Write-Host "[+] Saved recovery info to $filePath" -ForegroundColor Green
				} else {
					Write-Host "[~] Not saved." -ForegroundColor Yellow
				}
			} else {
				Write-Host "[!] Invalid input. Please enter Y or N." -ForegroundColor Red
			}
		} while ($saveYN -notmatch '^[YyNn]$')
	}

	# Do it
	if (-not(DetectBitlocker)) { ConfigureBitlocker }
	BackupBitLockerIfEntra
	GetBitlockerRecovery
}
function ClearPin { # Clears HELLO PIN from all accounts (requires reboot, must be ran as SYSTEM)
    # Clears the current user's Windows HELLO PIN 
    $CurrentUser = whoami
    if ($CurrentUser -notmatch 'System') {
        Write-Host "YOU MUST RUN THIS AS THE SYSTEM ACCOUNT. Please switch to backstage to run this option." -ForegroundColor Red
        pause
    }

    try {
        # Check if the Ngc folder exists and remove it
        $ngcPath = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc"
        if (Test-Path $ngcPath) {
            Write-Host "Removing HELLO PIN data..." -ForegroundColor Yellow
            Get-ChildItem $ngcPath | Remove-Item -Recurse -Force
        } else {
            Write-Host "Ngc folder not found. PIN data may already be cleared." -ForegroundColor Cyan
        }

        # Define registry path and create if it doesn't exist
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
        if (-not (Test-Path $regPath)) {
            Write-Host "Registry path missing. Creating required path..." -ForegroundColor Yellow
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft" -Name "PassportForWork" -Force | Out-Null
        }

        # Set the policy to disable Windows Hello PIN
        Write-Host "Disabling Windows Hello PIN via policy..." -ForegroundColor Yellow
        Set-ItemProperty -Path $regPath -Name "Enabled" -Value 0 -Force

        # Completion message
        Write-Host "Please reboot to complete removing the sign-in PIN." -ForegroundColor Green
        Start-Sleep 5
    }
    catch {
        Write-Host "An error occurred: $_" -ForegroundColor Red
    }
}
function DisableEnrollmentChecksOnSignIn{ # Disables Enrollment Checks on the first sign in after Azure joining new PCs to save time
	$script = @'
$EnrollmentKey = Get-ChildItem HKLM:\Software\Microsoft\Enrollments -recurse | Where-Object { $_.name -like "*firstsync*" }
$EnrollmentKey | Set-Itemproperty -name SkipDeviceStatusPage -value 1 -Force
$EnrollmentKey | Set-Itemproperty -name SkipUserStatusPage -value 1 -Force
Get-Process "winlogon" | stop-process -Force
'@
	$bytes = [System.Text.Encoding]::Unicode.GetBytes($Script)
	$encodedCommand = [Convert]::ToBase64String($bytes)
	Start-Process powershell.exe -ArgumentList "-encodedCommand $encodedCommand" -Verb runas -Wait
	Write-Host "Ninite has been installed."
}
function Set-PowerPlan { 
    Clear-Host
    Write-Host "`n  Power Plan" -ForegroundColor Cyan
    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray
    Write-Host "  [1] " -NoNewLine -ForegroundColor DarkGray
    Write-Host "Always On" -NoNewLine -ForegroundColor White
    Write-Host "         Never sleep, no screen timeout" -ForegroundColor DarkGray
    Write-Host "  [2] " -NoNewLine -ForegroundColor DarkGray
    Write-Host "XperUtility" -NoNewLine -ForegroundColor Cyan
    Write-Host "       Never sleep, screen locks after 5 min" -ForegroundColor DarkGray
    Write-Host "  [3] " -NoNewLine -ForegroundColor DarkGray
    Write-Host "Custom" -NoNewLine -ForegroundColor White
    Write-Host "            Never sleep, custom screen timeout" -ForegroundColor DarkGray
    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray

    $choice = (Read-Host "`n  Select").Trim()

    $screenTimeout = switch ($choice) {
        '1' { 0    }
        '2' { 300  }
        '3' {
            $mins = Read-Host "  Screen lock timeout (minutes)"
            if ($mins -match '^\d+$') { [int]$mins * 60 } else {
                Write-Host "  Invalid input." -ForegroundColor Red
                Start-Sleep -Milliseconds 800
                return
            }
        }
        default {
            Write-Host "`n  Cancelled." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 800
            return
        }
    }

    try {
        # Set High Performance base
        powercfg /setactive SCHEME_MIN 2>$null

        # AC (plugged in) - never sleep, never hibernate
        powercfg /change standby-timeout-ac 0
        powercfg /change hibernate-timeout-ac 0
        powercfg /change disk-timeout-ac 0

        # DC (battery) - never sleep, never hibernate
        powercfg /change standby-timeout-dc 0
        powercfg /change hibernate-timeout-dc 0
        powercfg /change disk-timeout-dc 0

        # Screen timeout (0 = never)
        $screenMins = [math]::Ceiling($screenTimeout / 60)
        powercfg /change monitor-timeout-ac $screenMins
        powercfg /change monitor-timeout-dc $screenMins

        $label = switch ($choice) {
            '1' { 'Always On (no sleep, no screen timeout)' }
            '2' { 'XperUtility (no sleep, 5 min screen lock)' }
            '3' { "Custom (no sleep, $screenMins min screen timeout)" }
        }
        Write-Host "`n  [+] Power plan applied: " -NoNewLine -ForegroundColor Green
        Write-Host $label -ForegroundColor Cyan
    } catch {
        Write-Host "`n  [!] Failed: $_" -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}
function Set-TimezoneMenu {
    $zones = [ordered]@{
        '1' = @{ Label = 'Eastern';    Id = 'Eastern Standard Time'    }
        '2' = @{ Label = 'Central';    Id = 'Central Standard Time'    }
        '3' = @{ Label = 'Mountain';   Id = 'Mountain Standard Time'   }
        '4' = @{ Label = 'Pacific';    Id = 'Pacific Standard Time'    }
        '5' = @{ Label = 'Alaska';     Id = 'Alaskan Standard Time'    }
        '6' = @{ Label = 'Hawaii';     Id = 'Hawaiian Standard Time'   }
        '7' = @{ Label = 'Arizona';    Id = 'US Mountain Standard Time' } # No DST
    }

    Clear-Host
    Write-Host "`n  Set Timezone" -ForegroundColor Cyan
    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray
    foreach ($k in $zones.Keys) {
        Write-Host "  [" -NoNewLine -ForegroundColor DarkGray
        Write-Host $k -NoNewLine -ForegroundColor Yellow
        Write-Host "] " -NoNewLine -ForegroundColor DarkGray
        Write-Host $zones[$k].Label -ForegroundColor White
    }
    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray

    $choice = (Read-Host "`n  Select").Trim()
    if (-not $zones.Contains($choice)) {
        Write-Host "`n  Cancelled." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 800
        return
    }

    $selected = $zones[$choice]
    try {
        Set-TimeZone -Id $selected.Id -ErrorAction Stop
        Write-Host "`n  [+] Timezone set to " -NoNewLine -ForegroundColor Green
        Write-Host $selected.Label -ForegroundColor Cyan
    } catch {
        Write-Host "`n  [!] Failed: $_" -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}
# WSI Functions 
function EnableWenSignOn { # Enables Windows Web Sign On and Windows HELLO
	$Script = @'
Write-Host "[*] Enabling web sign in..." -foregroundcolor yellow
$RegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\current\device\Authentication"
New-Item registry::$RegPath -force
New-ItemProperty -path registry::$Regpath -Name 'EnableWebSignIn' -value 1 -Force
New-ItemProperty -path registry::$Regpath -Name 'EnableWebSignIn_ProviderSet' -value 1 -Force
#New-ItemProperty -path registry::$Regpath -Name 'EnableWebSignIn_WinningProvider' -value '3201EF00-E70D-49BA-8CFE-6D7048B31D47' -Force
Write-Host "[+] Enabled WebSignIn`n" -foregroundcolor Green

Write-Host "[*] Updating group policy..." -Foregroundcolor Yellow
$localgpo = 'C:\Windows\System32\GroupPolicy\Machine\Registry.pol'
if (test-path $localgpo){
remove-item $localgpo
}
gpupdate /force | out-null
Write-Host "[+] Updated group policy`n" -Foregroundcolor green

Write-Host "[*] Enabling Windows HELLO..." -Foregroundcolor Yellow
if (-not (Test-Path hklm:\SOFTWARE\Policies\Microsoft\PassportForWork)){
new-item hklm:\SOFTWARE\Policies\Microsoft\PassportForWork -force
}
Set-itemproperty hklm:\SOFTWARE\Policies\Microsoft\PassportForWork -name enabled -value 1 -Force 
Set-itemproperty hklm:\SOFTWARE\Policies\Microsoft\PassportForWork -Name DisablePostLogonProvisioning -value 0 -Force
Write-Host "[+] Enabled Windows HELLO`n" -foregroundcolor green

Write-Host "[*] Enabling/Configuring UAC..." -Foregroundcolor yellow 
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
New-ItemProperty -Path $regPath -Name 'EnableLUA' -PropertyType DWord -Value 1 -Force
New-ItemProperty -Path $regPath -Name 'ConsentPromptBehaviorAdmin' -PropertyType DWord -Value 0 -Force
New-ItemProperty -Path $regPath -Name 'ConsentPromptBehaviorUser' -PropertyType DWord -Value 3 -Force
New-ItemProperty -Path $regPath -Name 'PromptOnSecureDesktop' -PropertyType DWord -Value 0 -Force
Write-Host "[+] Configured UAC`n" -ForegroundColor Green 

Write-Host "Exiting in 5..." -NoNewLine ; start-sleep -seconds 1 ; Write-Host "4..." -NoNewLine ; start-sleep -seconds 1 ; Write-Host "3..." -NoNewLine ; start-sleep -seconds 1 ; Write-Host "2..." -NoNewLine ; start-sleep -seconds 1 ; Write-Host "1..." -NoNewLine ; start-sleep -seconds 1 ; 
'@
	$bytes = [System.Text.Encoding]::Unicode.GetBytes($Script)
	$encodedCommand = [Convert]::ToBase64String($bytes)
	Start-Process powershell.exe -ArgumentList "-encodedCommand $encodedCommand" -Verb runas -Wait
}
function DisableWebSignOn { # Disables Windows Web Sign On
	$Script = @'
Write-Host "[*] Disabling Web Sign-In..." -ForegroundColor Yellow
$WSIPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Authentication"
if (Test-Path $WSIPath) {
# Remove specific properties if they exist
$props = @(
"EnableWebSignIn",
"EnableWebSignIn_ProviderSet",
"EnableWebSignIn_WinningProvider"
)
foreach ($p in $props) {
if (Get-ItemProperty -Path $WSIPath -Name $p -ErrorAction SilentlyContinue) {
Remove-ItemProperty -Path $WSIPath -Name $p -ErrorAction SilentlyContinue
}
}
Write-Host "[-] Web Sign-In disabled" -ForegroundColor Green
} else {
Write-Host "[~] WSI registry hive not present. Nothing to disable." -ForegroundColor DarkGray
}

Write-Host "`n[*] Updating group policy..." -ForegroundColor Yellow
$localgpo = 'C:\Windows\System32\GroupPolicy\Machine\Registry.pol'
if (Test-Path $localgpo) {
Remove-Item $localgpo -Force -ErrorAction SilentlyContinue
}
gpupdate /force | Out-Null
Write-Host "[+] Group policy updated" -ForegroundColor Green

while ($true) {
$response = Read-Host "`n[?] Disable UAC? (Y/N)"

switch -Regex ($response.ToUpper()) {
'^Y$' {
$UACPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Write-Host "[*] Disabling UAC..." -ForegroundColor Yellow
Set-ItemProperty -Path $UACPath -Name 'EnableLUA' -Value 0 -Force
Write-Host "[+] UAC disabled" -ForegroundColor Green
break
}
'^N$' {
Write-Host "[~] Leaving UAC unchanged." -ForegroundColor DarkGray 
break
}
default {
Write-Host "[!] Invalid input. Enter Y or N." -ForegroundColor Red
}
}
if ($response -match '^[YyNn]$') { break }
}

Write-Host "Exiting in 5..." -NoNewLine ; start-sleep -seconds 1 ; Write-Host "4..." -NoNewLine ; start-sleep -seconds 1 ; Write-Host "3..." -NoNewLine ; start-sleep -seconds 1 ; Write-Host "2..." -NoNewLine ; start-sleep -seconds 1 ; Write-Host "1..." -NoNewLine ; start-sleep -seconds 1 ; 
'@
	$bytes = [System.Text.Encoding]::Unicode.GetBytes($Script)
	$encodedCommand = [Convert]::ToBase64String($bytes)
	Start-Process powershell.exe -ArgumentList "-encodedCommand $encodedCommand" -Verb runas -Wait
}
#endregion 
# region == Utility ==
function DetectIllegalCharacters {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    $isISE = $Host.Name -eq 'Windows PowerShell ISE Host'

    if (-not $Path) {
        $Path = (Read-Host "[>] Enter full path to script").Trim('"')
    } else {
        $Path = $Path.Trim('"')
    }

    if (-not (Test-Path $Path)) {
        Write-Host "[!] File not found at '$Path'" -ForegroundColor Red
        return
    }

    Write-Host "[*] Scanning file for illegal (non-ASCII) characters..." -ForegroundColor Gray

    $fileContent = Get-Content -Path $Path -Raw -Encoding UTF8
    $lines       = $fileContent -split "`r?`n"
    $found       = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line     = $lines[$i]
        $badChars = $line.ToCharArray() | Where-Object {
            $code = [int][char]$_
            ($code -lt 32 -and $code -ne 9) -or $code -gt 126
        }
        if ($badChars.Count -gt 0) {
            $found = $true
            $codes = ($badChars | ForEach-Object { "{0} (U+{1:X4})" -f $_, [int][char]$_ }) -join ", "
            Write-Host ("[!] Line {0}: {1}" -f ($i + 1), $codes) -ForegroundColor Yellow
        }
    }

    if (-not $found) {
        Write-Host "[+] No illegal characters found." -ForegroundColor Green
        Start-Sleep -Seconds 3
        return
    }

    # --- Illegal chars found ---
    Write-Host ""
    Write-Host "[!] Illegal characters detected." -ForegroundColor Red

    $remediate = $false

    if ($isISE) {
        $choice = Read-Host "    Type ENTER to remediate, or anything else to continue"
        $remediate = ($choice -eq '')
    } else {
        Write-Host "    Press " -NoNewLine -ForegroundColor DarkGray
        Write-Host "ENTER" -NoNewLine -ForegroundColor Yellow
        Write-Host " to remediate, or any other key to continue..." -ForegroundColor DarkGray
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $remediate = ($key.VirtualKeyCode -eq 13)  # 13 = Enter
    }

    if (-not $remediate) { return }

    # --- Remediation ---
    # Known hyphen-like characters to normalize rather than strip
    $hyphenMap = @{
        [char]0x2010 = '-'  # hyphen
        [char]0x2011 = '-'  # non-breaking hyphen
        [char]0x2012 = '-'  # figure dash
        [char]0x2013 = '-'  # en dash
        [char]0x2014 = '-'  # em dash
        [char]0x2015 = '-'  # horizontal bar
        [char]0x2212 = '-'  # minus sign
        [char]0xFE58 = '-'  # small em dash
        [char]0xFE63 = '-'  # small hyphen-minus
        [char]0xFF0D = '-'  # fullwidth hyphen-minus
    }

    $cleaned = $fileContent.ToCharArray() | ForEach-Object {
        $c    = $_
        $code = [int][char]$c
        if ($hyphenMap.ContainsKey($c)) {
            $hyphenMap[$c]
        } elseif (($code -lt 32 -and $code -ne 9 -and $code -ne 10 -and $code -ne 13) -or $code -gt 126) {
            ''  # strip it
        } else {
            $c
        }
    }

    $cleanedString = -join $cleaned
    [System.IO.File]::WriteAllText($Path, $cleanedString, [System.Text.Encoding]::UTF8)

    Write-Host "[+] Remediation complete. File saved: $Path" -ForegroundColor Green
    Start-Sleep -Seconds 2
}
function Invoke-Windows11Upgrade {
    param([switch]$Silent)

    $tempDir = "$env:TEMP\PSMM\temp"
    $UpdateAssistantPath = "$tempDir\Windows11UpdateAssistant.exe"
    $assistantUrl        = "https://go.microsoft.com/fwlink/?linkid=2171764"

    if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }

    if (-not (Test-Path $UpdateAssistantPath)) {
        Write-Host "`n  Downloading Windows 11 Update Assistant..." -ForegroundColor DarkGray
        try {
            SmartDownload -Url $assistantUrl -Destination $UpdateAssistantPath
        } catch {
            Write-Host "  [!] Download failed: $_" -ForegroundColor Red
            Pause-Menu
            return
        }
    } else {
        Write-Host "`n  Update Assistant already present, skipping download." -ForegroundColor DarkGray
    }

    Write-Host "  Launching Windows 11 upgrade..." -ForegroundColor Cyan

    $args = if ($Silent) { '/quietinstall /skipeula /auto upgrade' } else { '' }

    try {
        Start-Process -FilePath $UpdateAssistantPath -ArgumentList $args -Verb RunAs
        Write-Host "  [+] Upgrade process launched. This will run in the background." -ForegroundColor Green
    } catch {
        Write-Host "  [!] Failed to launch upgrade: $_" -ForegroundColor Red
    }

    Start-Sleep -Seconds 3
}
function Open-AsSystem {
	$tempPath   = "$env:TEMP\PSMM\temp"
    $psExecPath = "$tempPath\PsExec.exe"
    $psExecUrl  = "https://UseAValidURL/PSTools/PsExec.exe"

	if (-not (Test-Path $tempPath )) { mkdir $tempPath }

    if (-not (Test-Path $psExecPath)) {
        Write-Host "`n  PsExec not found, downloading..." -ForegroundColor DarkGray
        try {
            SmartDownload -Url $psExecUrl -Destination $psExecPath
        } catch {
            Write-Host "  [!] Failed to download PsExec: $_" -ForegroundColor Red
            Pause-Menu
            return
        }
    }

    Write-Host "`n  Open as SYSTEM:" -ForegroundColor DarkGray
    Write-Host "  [1] PowerShell"                        -ForegroundColor DarkCyan
    Write-Host "  [2] Command Prompt"                    -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Input " -NoNewLine -ForegroundColor DarkGray
    Write-Host "1" -NoNewLine -ForegroundColor Yellow
    Write-Host " or " -NoNewLine -ForegroundColor DarkGray
    Write-Host "2" -NoNewLine -ForegroundColor Yellow
    Write-Host "..." -ForegroundColor DarkGray

    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

    $target = switch ($key.Character) {
        # '1' { @{ Label = 'Windows Terminal'; Exe = "C:\Program Files\WindowsApps\Microsoft.WindowsTerminal_1.23.20211.0_x64__8wekyb3d8bbwe\wt.exe"          } } # don't work.
        '1' { @{ Label = 'PowerShell';       Exe = 'powershell.exe'  } }
        '2' { @{ Label = 'Command Prompt';   Exe = 'cmd.exe'         } }
        default {
            Write-Host "`n  Cancelled." -ForegroundColor DarkGray
            Start-Sleep -Seconds 1
            return
        }
    }

    Write-Host "`n  Launching $($target.Label) as SYSTEM..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath $psExecPath -ArgumentList "-i", "-s", "-accepteula", $target.Exe -Verb RunAs
        Write-Host ""
        Write-Host "  [!] PsExec.exe remains at " -NoNewLine -ForegroundColor Yellow
        Write-Host $psExecPath -NoNewLine -ForegroundColor Red
        Write-Host "." -ForegroundColor Yellow
        Write-Host "      Remove it manually or via " -NoNewLine -ForegroundColor DarkGray
        Write-Host "Utility > Clear Temp Files" -NoNewLine -ForegroundColor Cyan
        Write-Host " when done." -ForegroundColor DarkGray
        Pause-Menu
    } catch {
        Write-Host "  [!] Failed to launch: $_" -ForegroundColor Red
        Pause-Menu
    }
}
function Reset-PrinterSubsystem { # Removes all printers/ports/drivers. Leaves a few exempt common "virtual" printers such as Adobe PDF, Bluebeam PDF, etc.
    # Removes all printers and printer drivers from a machine, except for common virtual printers

    $script = @'
# Function to remove printers, excluding specific virtual printers
function Remove-AllPrinters {
    # Get a list of all installed printers
    $printers = Get-Printer

    # List of printers to exclude from removal
    $excludedPrinters = @(
        "Microsoft Print to PDF",
        "OneNote (Desktop)",
        "Bluebeam PDF",
        "Adobe PDF"
    )

    foreach ($printer in $printers) {
        # Check if the printer is in the excluded list
        if ($excludedPrinters -contains $printer.Name) {
            Write-Host "Skipping removal of printer: $($printer.Name)" -ForegroundColor Green
        } else {
            try {
                # Remove the printer
                Remove-Printer -Name $printer.Name -ErrorAction Stop
                Write-Host "Removed printer: $($printer.Name)" -ForegroundColor Yellow
            } catch {
                Write-Host "Failed to remove printer: $($printer.Name) - $_" -ForegroundColor Red
            }
        }
    }
}

# Function to remove printer drivers, excluding those related to the virtual printers
function Remove-AllPrinterDrivers {
    # Get a list of all installed printer drivers
    $printerDrivers = Get-PrinterDriver

    # List of driver names to exclude from removal (these may differ, adjust if necessary)
    $excludedDrivers = @(
        "Microsoft Print to PDF",
        "OneNote (Desktop)",
        "Bluebeam PDF",
        "Adobe PDF"
    )

    foreach ($driver in $printerDrivers) {
        # Check if the driver is in the excluded list
        if ($excludedDrivers -contains $driver.Name) {
            Write-Host "Skipping removal of driver: $($driver.Name)" -ForegroundColor Green
        } else {
            try {
                # Remove the printer driver
                Remove-PrinterDriver -Name $driver.Name -ErrorAction Stop
                Write-Host "Removed printer driver: $($driver.Name)" -ForegroundColor Yellow
            } catch {
                Write-Host "Failed to remove printer driver: $($driver.Name) - $_" -ForegroundColor Red
            }
        }
    }
}

# Function to prompt user and potentially delete directory contents
function Purge-PrinterDriversDirectory {
    param (
        [string]$directoryPath
    )

    # Prompt the user
    $response = Read-Host "Would you like to also purge contents of '$directoryPath'? Y/N"

    if ($response -eq 'Y') {
        try {
            # Remove all contents of the directory
            Remove-Item -Path "$directoryPath\*" -Force -Recurse
            Write-Host "Purged contents of '$directoryPath'" -ForegroundColor Yellow
        } catch {
            Write-Host "Failed to purge contents of '$directoryPath' - $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Directory purge aborted by user." -ForegroundColor Green
    }
}

# Run the functions to remove all printers and printer drivers
Remove-AllPrinters
Remove-AllPrinterDrivers

# Prompt the user and potentially delete the directory contents
Purge-PrinterDriversDirectory -directoryPath "$env:TEMP\PSMM\printerdrivers"

Write-Host "All printers and printer drivers (except for excluded ones) have been removed." -ForegroundColor Green
'@

    # Convert script to Base64 and run as admin
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    $encodedCommand = [Convert]::ToBase64String($bytes)
    Start-Process powershell.exe -ArgumentList "-encodedCommand $encodedCommand" -Verb runas -Wait
}
function Manage-StartupItems {
    $exitKey = $script:MenuConfig.Settings.ExitKey

    function Get-AllStartupItems {
        $items = [System.Collections.Generic.List[hashtable]]::new()
        $idx   = 1

        function Add-RegItems {
            param([string]$Path, [string]$Header, [string]$Color, [string]$Type)
            if (-not (Test-Path $Path)) { return }
            $entries = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
            if (-not $entries) { return }
            $vals = $entries.PSObject.Properties | Where-Object {
                $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider|Drive)$'
            }
            if (-not $vals) { return }
            foreach ($v in $vals) {
                $items.Add(@{
                    Index   = $idx++
                    Header  = $Header
                    Color   = $Color
                    Name    = $v.Name
                    Value   = $v.Value
                    Type    = $Type
                    Path    = $Path
                })
            }
        }

        # User Run
        Add-RegItems 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
            'User Startup (HKCU\Run)' 'Cyan' 'RegRun'
        # Machine Run
        Add-RegItems 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
            'Machine Startup (HKLM\Run)' 'DarkCyan' 'RegRun'
        Add-RegItems 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' `
            'Machine Startup x86 (HKLM\WOW6432\Run)' 'DarkCyan' 'RegRun'
        # RunOnce
        Add-RegItems 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' `
            'RunOnce (HKCU)' 'Blue' 'RegRunOnce'
        Add-RegItems 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' `
            'RunOnce (HKLM)' 'Blue' 'RegRunOnce'

        # User Startup folder
        $userStartup = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
        if (Test-Path $userStartup) {
            $files = Get-ChildItem $userStartup -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $items.Add(@{
                    Index   = $idx++
                    Header  = 'User Startup Folder'
                    Color   = 'Green'
                    Name    = $f.Name
                    Value   = $f.FullName
                    Type    = 'StartupFolder'
                    Path    = $f.FullName
                })
            }
        }

        # System Startup folder
        $sysStartup = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        if (Test-Path $sysStartup) {
            $files = Get-ChildItem $sysStartup -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $items.Add(@{
                    Index   = $idx++
                    Header  = 'System Startup Folder'
                    Color   = 'DarkGreen'
                    Name    = $f.Name
                    Value   = $f.FullName
                    Type    = 'StartupFolder'
                    Path    = $f.FullName
                })
            }
        }

        # Scheduled Tasks (LogonTrigger only)
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.Triggers | Where-Object { $_ -match 'LogonTrigger' }
        }
        foreach ($t in $tasks) {
            $items.Add(@{
                Index   = $idx++
                Header  = 'Scheduled Tasks (At Logon)'
                Color   = 'Yellow'
                Name    = "$($t.TaskPath)$($t.TaskName)"
                Value   = ($t.Actions | ForEach-Object { $_.Execute } | Select-Object -First 1)
                Type    = 'ScheduledTask'
                Path    = "$($t.TaskPath)$($t.TaskName)"
                Enabled = ($t.Settings.Enabled -and ($t.Triggers | Where-Object { $_.Enabled }))
            })
        }

        return $items
    }

    function Show-StartupItems {
        param($Items)
        Clear-Host
        Write-Host "  Startup Item Manager" -ForegroundColor White
        Write-Host "  $('=' * 60)" -ForegroundColor DarkGray
        Write-Host ""

        if (-not $Items -or $Items.Count -eq 0) {
            Write-Host "  No startup items found." -ForegroundColor DarkGray
            return
        }

        $currentHeader = $null
        $rowToggle     = $false

        foreach ($item in $Items) {
            if ($item.Header -ne $currentHeader) {
                $currentHeader = $item.Header
                $rowToggle     = $false
                Write-Host ""
                Write-Host "  $($item.Header)" -ForegroundColor $item.Color
            }

            $rowColor = if ($rowToggle) { 'Gray' } else { 'White' }
            $rowToggle = -not $rowToggle

            $disabledTag = if ($item.Type -eq 'ScheduledTask' -and -not $item.Enabled) { ' [DISABLED]' } else { '' }

            Write-Host "    [" -NoNewLine -ForegroundColor DarkGray
            Write-Host $item.Index -NoNewLine -ForegroundColor Yellow
            Write-Host "] " -NoNewLine -ForegroundColor DarkGray
            Write-Host "$($item.Name)$disabledTag" -NoNewLine -ForegroundColor $rowColor
            if ($item.Value -and $item.Value -ne $item.Name) {
                Write-Host "  " -NoNewLine
                Write-Host $item.Value -ForegroundColor DarkGray
            } else {
                Write-Host ""
            }
        }

        Write-Host ""
        Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
        Write-Host "  Enter a number to disable/delete an item, or " -NoNewLine -ForegroundColor DarkGray
        Write-Host "[$exitKey]" -NoNewLine -ForegroundColor Yellow
        Write-Host " to go back." -ForegroundColor DarkGray
    }

    function Disable-StartupItem {
        param([hashtable]$Item)

        Write-Host "`n  Selected: " -NoNewLine -ForegroundColor DarkGray
        Write-Host $Item.Name -ForegroundColor Cyan
        Write-Host "  Action  : " -NoNewLine -ForegroundColor DarkGray

        switch ($Item.Type) {
            'RegRun'        { Write-Host "Delete registry value" -ForegroundColor Yellow }
            'RegRunOnce'    { Write-Host "Delete registry value" -ForegroundColor Yellow }
            'StartupFolder' { Write-Host "Delete file from startup folder" -ForegroundColor Yellow }
            'ScheduledTask' {
                if ($Item.Enabled) { Write-Host "Disable scheduled task" -ForegroundColor Yellow }
                else               { Write-Host "Already disabled" -ForegroundColor DarkGray; Start-Sleep -Seconds 2; return }
            }
        }

        Write-Host ""
        Write-Host "  Press " -NoNewLine -ForegroundColor DarkGray
        Write-Host "Y" -NoNewLine -ForegroundColor Yellow
        Write-Host " to confirm, or any other key to cancel..." -ForegroundColor DarkGray
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        if ($key.Character -ne 'y' -and $key.Character -ne 'Y') {
            Write-Host "`n  Cancelled." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 800
            return
        }

        try {
            switch ($Item.Type) {
                { $_ -in 'RegRun','RegRunOnce' } {
                    Remove-ItemProperty -Path $Item.Path -Name $Item.Name -Force -ErrorAction Stop
                    Write-Host "`n  [+] Registry value removed." -ForegroundColor Green
                }
                'StartupFolder' {
                    Remove-Item -Path $Item.Path -Force -ErrorAction Stop
                    Write-Host "`n  [+] Startup file deleted." -ForegroundColor Green
                }
                'ScheduledTask' {
                    Disable-ScheduledTask -TaskPath ([System.IO.Path]::GetDirectoryName($Item.Path) + '\') `
                                          -TaskName  ([System.IO.Path]::GetFileName($Item.Path)) `
                                          -ErrorAction Stop | Out-Null
                    Write-Host "`n  [+] Scheduled task disabled." -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "`n  [!] Failed: $_" -ForegroundColor Red
        }

        Start-Sleep -Milliseconds 1200
    }

    # --- Main loop ---
    while ($true) {
        $items = Get-AllStartupItems
        Show-StartupItems -Items $items

        $choice = (Read-Host "`n  Select").Trim()

        if ($choice -ieq $exitKey) { return }

        $parsed = 0
        if (-not [int]::TryParse($choice, [ref]$parsed)) {
            Write-Host "  Invalid input." -ForegroundColor Red
            Start-Sleep -Milliseconds 800
            continue
        }

        $selected = $items | Where-Object { $_.Index -eq $parsed }
        if (-not $selected) {
            Write-Host "  No item with that number." -ForegroundColor Red
            Start-Sleep -Milliseconds 800
            continue
        }

        Disable-StartupItem -Item $selected
    }
}
function Reset-PrintSpooler {
    Write-Host "`n  Resetting Print Spooler..." -ForegroundColor DarkGray
    try {
        Stop-Service -Name Spooler -Force -ErrorAction Stop
        Write-Host "  Spooler stopped." -ForegroundColor DarkGray

        $spoolPath = 'C:\Windows\System32\spool\PRINTERS'
        if (Test-Path $spoolPath) {
            Get-ChildItem $spoolPath -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Write-Host "  Spool queue cleared." -ForegroundColor DarkGray
        }

        Start-Service -Name Spooler -ErrorAction Stop
        Write-Host "`n  [+] Print Spooler restarted successfully." -ForegroundColor Green
    } catch {
        Write-Host "`n  [!] Failed: $_" -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}
function Clear-TempFiles {
    $targets = [ordered]@{
        'User Temp'        = $env:TEMP
        'System Temp'      = 'C:\Windows\Temp'
        'Prefetch'         = 'C:\Windows\Prefetch'
        'SoftwareDistrib.' = 'C:\Windows\SoftwareDistribution\Download'
        'PSMM Temp'        = "$env:TEMP\PSMM\temp"
    }

    # --- Inventory pass ---
    $inventory = [ordered]@{}
    foreach ($label in $targets.Keys) {
        $path = $targets[$label]
        if (-not (Test-Path $path)) {
            $inventory[$label] = @{ Path = $path; Size = $null }
        } else {
            $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            $inventory[$label] = @{ Path = $path; Size = $size }
        }
    }

    # Build numbered list (keys only, for index lookup)
    $keys = @($inventory.Keys)  # [1] = Purge All offset by 1, so key index = choice - 2

    Write-Host "`n  Temp File Cleanup" -ForegroundColor Cyan
    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray

    Write-Host "  [" -NoNewLine -ForegroundColor DarkGray
    Write-Host "1" -NoNewLine -ForegroundColor Yellow
    Write-Host "] " -NoNewLine -ForegroundColor DarkGray
    Write-Host "Purge All" -ForegroundColor Red

    for ($i = 0; $i -lt $keys.Count; $i++) {
        $label = $keys[$i]
        $entry = $inventory[$label]
        $num   = $i + 2

        Write-Host "  [" -NoNewLine -ForegroundColor DarkGray
        Write-Host $num -NoNewLine -ForegroundColor Yellow
        Write-Host "] " -NoNewLine -ForegroundColor DarkGray
        Write-Host $label.PadRight(18) -NoNewLine -ForegroundColor DarkYellow

        if ($null -eq $entry.Size) {
            Write-Host "not found" -ForegroundColor DarkGray
        } else {
            $mb = [math]::Round($entry.Size / 1MB, 1)
            Write-Host "$mb MB" -ForegroundColor $(if ($mb -gt 0) { 'Yellow' } else { 'DarkGray' })
        }
    }

    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray
    Write-Host "  Any other input cancels." -ForegroundColor DarkGray

    $choice = (Read-Host "`n  Select").Trim()

    $parsed = 0
    if (-not [int]::TryParse($choice, [ref]$parsed)) {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 800
        return
    }

    # Resolve selection to a list of labels to purge
    $toPurge = @()
    if ($parsed -eq 1) {
        $toPurge = $keys
    } elseif ($parsed -ge 2 -and $parsed -le ($keys.Count + 1)) {
        $toPurge = @($keys[$parsed - 2])
    } else {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 800
        return
    }

    # Confirm
    Write-Host ""
    Write-Host "  Press " -NoNewLine -ForegroundColor DarkGray
    Write-Host "D" -NoNewLine -ForegroundColor Red
    Write-Host " to " -NoNewLine -ForegroundColor DarkGray
	Write-Host "delete" -NoNewLine -ForegroundColor Red
	Write-Host " all..." -ForegroundColor DarkGray
	Write-Host "  Press " -NoNewLine -ForegroundColor DarkGray
	Write-Host "any other key" -NoNewLine -ForegroundColor Yellow
	Write-Host " to cancel..." -ForegroundColor DarkGray
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    if ($key.Character -ne 'd' -and $key.Character -ne 'D') {
        Write-Host "`n  Cancelled." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 800
        return
    }

    # --- Deletion pass ---
    Write-Host ""
    $totalFreed = 0
    foreach ($label in $toPurge) {
        $entry = $inventory[$label]
        if ($null -eq $entry.Size -or $entry.Size -eq 0) {
            Write-Host "  $($label.PadRight(18))" -NoNewLine -ForegroundColor DarkGray
            Write-Host "nothing to clear" -ForegroundColor DarkGray
            continue
        }

        Get-ChildItem $entry.Path -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $after = (Get-ChildItem $entry.Path -Recurse -Force -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        $freed = [math]::Round(($entry.Size - $after) / 1MB, 1)
        $totalFreed += $freed

        Write-Host "  $($label.PadRight(18))" -NoNewLine -ForegroundColor DarkGray
        Write-Host "$freed MB freed" -ForegroundColor $(if ($freed -gt 0) { 'Green' } else { 'DarkGray' })
    }

    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray
    Write-Host "  Total freed: " -NoNewLine -ForegroundColor DarkGray
    Write-Host "$([math]::Round($totalFreed, 1)) MB" -ForegroundColor Cyan
    Pause-Menu
}
function Reset-NetworkStack {
    Write-Host "`n  Network Stack Reset" -ForegroundColor Cyan
    Write-Host "  This will flush DNS, reset Winsock, and release/renew IP." -ForegroundColor DarkGray
    Write-Host "  Connectivity will drop briefly. " -NoNewLine -ForegroundColor DarkGray
    Write-Host "No reboot required." -ForegroundColor Green
    Write-Host "`n  Press " -NoNewLine -ForegroundColor DarkGray
    Write-Host "Y" -NoNewLine -ForegroundColor Yellow
    Write-Host " to proceed, any other key to cancel..." -ForegroundColor DarkGray

    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    if ($key.Character -ne 'y' -and $key.Character -ne 'Y') {
        Write-Host "`n  Cancelled." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 800
        return
    }

    $steps = [ordered]@{
        'Flushing DNS cache'            = { ipconfig /flushdns        2>&1 | Out-Null }
        'Releasing IP'                  = { ipconfig /release         2>&1 | Out-Null }
        'Resetting Winsock catalog'     = { netsh winsock reset       2>&1 | Out-Null }
        'Resetting TCP/IP stack'        = { netsh int ip reset        2>&1 | Out-Null }
        'Resetting IPv6'                = { netsh int ipv6 reset      2>&1 | Out-Null }
        'Resetting firewall policy'     = { netsh advfirewall reset   2>&1 | Out-Null }
        'Renewing IP'                   = { ipconfig /renew           2>&1 | Out-Null }
        'Registering DNS'               = { ipconfig /registerdns     2>&1 | Out-Null }
    }

    Write-Host ""
    foreach ($step in $steps.Keys) {
        Write-Host "  $step..." -NoNewLine -ForegroundColor DarkGray
        try {
            & $steps[$step]
            Write-Host " done" -ForegroundColor Green
        } catch {
            Write-Host " failed ($_)" -ForegroundColor Yellow
        }
    }

    Write-Host "`n  [+] Network stack reset complete." -ForegroundColor Green
    Pause-Menu
}
function Invoke-PS2EXE {

    $cfg = [ordered]@{
        SourcePath   = $null
        DestPath     = $null
        Title        = $null
        Description  = $null
        Version      = $null
        IconFile     = $null
        RequireAdmin = $false
        HideConsole  = $false
        Wait         = $false
        ThreadModel  = $null
        NoProfile    = $false
        NoLogo       = $false
        NoOutput     = $false
        NoError      = $false
        ForceArch    = $null
        DPIAware     = $true
    }

    $threadCycle     = @($null, 'STA', 'MTA')
    $archCycle       = @($null, 'x86', 'x64')

    # Rows defined once at scope level - never inside a function that returns them
    $script:ps2exeRows = $null

    function CycleValue($current, $list) {
        $idx = [Array]::IndexOf($list, $current)
        return $list[($idx + 1) % $list.Count]
    }

    function ValueDisplay($val, $type) {
        switch ($type) {
            'bool'   {
                if ($val) { return @{ Text = 'Yes'; Color = 'Green'   } }
                else      { return @{ Text = 'No';  Color = 'Red'     } }
            }
            'path'   {
                if ($val) { return @{ Text = $val;  Color = 'DarkGray' } }
                else      { return @{ Text = '?';   Color = 'DarkRed'  } }
            }
            'string' {
                if ($val) { return @{ Text = $val;  Color = 'DarkGray' } }
                else      { return @{ Text = 'No';  Color = 'Red'      } }
            }
            'cycle'  {
                if ($val) { return @{ Text = $val;  Color = 'Cyan'    } }
                else      { return @{ Text = 'No';  Color = 'Red'     } }
            }
        }
    }

    function Build-Rows {
        $script:ps2exeRows = [System.Collections.Generic.List[hashtable]]::new()
        $script:ps2exeRows.Add(@{ Num = 1;    Label = 'Source Path       '; Val = $cfg.SourcePath;   Type = 'path';   Key = 'SourcePath'   })
        $script:ps2exeRows.Add(@{ Num = 2;    Label = 'Dest Path         '; Val = $cfg.DestPath;     Type = 'path';   Key = 'DestPath'     })
        $script:ps2exeRows.Add(@{ Num = $null; Sep = $true })
        $script:ps2exeRows.Add(@{ Num = 3;    Label = 'Title             '; Val = $cfg.Title;        Type = 'string'; Key = 'Title'        })
        $script:ps2exeRows.Add(@{ Num = 4;    Label = 'Description       '; Val = $cfg.Description;  Type = 'string'; Key = 'Description'  })
        $script:ps2exeRows.Add(@{ Num = 5;    Label = 'Version           '; Val = $cfg.Version;      Type = 'string'; Key = 'Version'      })
        $script:ps2exeRows.Add(@{ Num = 6;    Label = 'Icon File         '; Val = $cfg.IconFile;     Type = 'path';   Key = 'IconFile'     })
        $script:ps2exeRows.Add(@{ Num = $null; Sep = $true })
        $script:ps2exeRows.Add(@{ Num = 7;    Label = 'Force Architecture'; Val = $cfg.ForceArch;    Type = 'cycle';  Key = 'ForceArch'    })
        $script:ps2exeRows.Add(@{ Num = 8;   Label = 'Thread Model      '; Val = $cfg.ThreadModel;  Type = 'cycle';  Key = 'ThreadModel'  })
        $script:ps2exeRows.Add(@{ Num = $null; Sep = $true })
        $script:ps2exeRows.Add(@{ Num = 9;   Label = 'Require Admin     '; Val = $cfg.RequireAdmin; Type = 'bool';   Key = 'RequireAdmin' })
        $script:ps2exeRows.Add(@{ Num = 10;   Label = 'Hide Console      '; Val = $cfg.HideConsole;  Type = 'bool';   Key = 'HideConsole'  })
        $script:ps2exeRows.Add(@{ Num = 11;   Label = 'DPI Aware         '; Val = $cfg.DPIAware;     Type = 'bool';   Key = 'DPIAware'     })
        $script:ps2exeRows.Add(@{ Num = 12;   Label = 'Wait              '; Val = $cfg.Wait;         Type = 'bool';   Key = 'Wait'         })
        $script:ps2exeRows.Add(@{ Num = 13;   Label = 'No Profile        '; Val = $cfg.NoProfile;    Type = 'bool';   Key = 'NoProfile'    })
        $script:ps2exeRows.Add(@{ Num = 14;   Label = 'No Logo           '; Val = $cfg.NoLogo;       Type = 'bool';   Key = 'NoLogo'       })
        $script:ps2exeRows.Add(@{ Num = 15;   Label = 'No Output         '; Val = $cfg.NoOutput;     Type = 'bool';   Key = 'NoOutput'     })
        $script:ps2exeRows.Add(@{ Num = 16;   Label = 'No Error          '; Val = $cfg.NoError;      Type = 'bool';   Key = 'NoError'      })
        $script:ps2exeRows.Add(@{ Num = $null; Sep = $true })
    }

    function Show-PS2EXEMenu {
        Clear-Host
        Write-Host "  PS2EXE Wrapper" -ForegroundColor Cyan
        Write-Host "  $('-' * 52)" -ForegroundColor DarkGray
        Write-Host ""

        $ready  = $cfg.SourcePath -and $cfg.DestPath
        $maxNum = ($script:ps2exeRows | Where-Object { $_.Num } | ForEach-Object { "$($_.Num)".Length } | Measure-Object -Maximum).Maximum

        foreach ($row in $script:ps2exeRows) {
            if ($row.Sep) {
                Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
                continue
            }
            $numStr  = "$($row.Num)"
            $pad     = ' ' * ($maxNum - $numStr.Length)
            $display = ValueDisplay $row.Val $row.Type

            Write-Host "$pad  [" -NoNewline -ForegroundColor DarkGray
            Write-Host $numStr -NoNewline -ForegroundColor DarkYellow
            Write-Host "] " -NoNewline -ForegroundColor DarkGray
            Write-Host $row.Label -NoNewline -ForegroundColor Gray
            Write-Host "= " -NoNewline -ForegroundColor DarkGray
            Write-Host $display.Text -ForegroundColor $display.Color
        }

        Write-Host "  [" -NoNewline -ForegroundColor DarkGray
        Write-Host "C" -NoNewline -ForegroundColor $(if ($ready) { 'Green' } else { 'DarkGray' })
        Write-Host "] " -NoNewline -ForegroundColor DarkGray
        if ($ready) {
            Write-Host "CREATE" -ForegroundColor Green
        } else {
            Write-Host "CREATE  " -NoNewline -ForegroundColor DarkGray
            Write-Host "(set Source and Dest first)" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "  $('-' * 52)" -ForegroundColor DarkGray
        Write-Host "  Press " -NoNewline -ForegroundColor DarkGray
        Write-Host "[$($script:MenuConfig.Settings.ExitKey)]" -NoNewline -ForegroundColor DarkYellow
        Write-Host " to cancel." -ForegroundColor DarkGray
    }

    function Prompt-Value($label, $current) {
        Write-Host ""
        Write-Host "  $label" -ForegroundColor Cyan
        if ($current) {
            Write-Host "  Current: " -NoNewline -ForegroundColor DarkGray
            Write-Host $current -ForegroundColor DarkGray
            Write-Host "  (leave blank to clear)" -ForegroundColor DarkGray
        }
        $val = (Read-Host "  >").Trim().Trim('"')
        if ($val -eq '' -and $current) { return $null }
        if ($val -eq '')               { return $current }
        return $val
    }

    $exitKey = $script:MenuConfig.Settings.ExitKey

    # --- Main loop ---
    while ($true) {
        Build-Rows
        Show-PS2EXEMenu
        $choice = (Read-Host "`n  ::").Trim()

        if ($choice -ieq $exitKey) { return }

        if ($choice -ieq 'C') {
            if (-not ($cfg.SourcePath -and $cfg.DestPath)) {
                Write-Host "`n  Source and Dest paths are required." -ForegroundColor Red
                Start-Sleep -Milliseconds 800
                continue
            }

            # Build argument list as actual array for direct invocation
            $argList = [System.Collections.Generic.List[string]]::new()
            $argList.Add($cfg.SourcePath)
            $argList.Add($cfg.DestPath)
            if ($cfg.Title)               { $argList.Add('-title');       $argList.Add($cfg.Title)        }
            if ($cfg.Description)         { $argList.Add('-description'); $argList.Add($cfg.Description)  }
            if ($cfg.Version)             { $argList.Add('-version');     $argList.Add($cfg.Version)      }
            if ($cfg.IconFile)            { $argList.Add('-iconFile');    $argList.Add($cfg.IconFile)     }
            if ($cfg.RequireAdmin)        { $argList.Add('-requireAdmin')                                  }
            if ($cfg.HideConsole)         { $argList.Add('-noConsole')                                    }
            if ($cfg.Wait)                { $argList.Add('-wait')                                         }
            if ($cfg.ThreadModel)         { $argList.Add("-$($cfg.ThreadModel.ToLower())")                }
            if ($cfg.NoProfile)           { $argList.Add('-noProfile')                                    }
            if ($cfg.NoLogo)              { $argList.Add('-noLogo')                                       }
            if ($cfg.NoOutput)            { $argList.Add('-noOutput')                                     }
            if ($cfg.NoError)             { $argList.Add('-noError')                                      }
            if ($cfg.DPIAware)            { $argList.Add('-DPIAware')                                    }
            if ($cfg.ForceArch -eq 'x86') { $argList.Add('-x86')                                        }
            if ($cfg.ForceArch -eq 'x64') { $argList.Add('-x64')                                        }
			$argList.Add('-company')
			$argList.Add('COMPANY')
			$argList.Add('-product')
			$argList.Add('COMPANY')

            # Display the reconstructed command for review
            $previewArgs = $argList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
            Clear-Host
            Write-Host ""
            Write-Host "  Command preview:" -ForegroundColor DarkGray
            Write-Host "  ps2exe $($previewArgs -join ' ')" -ForegroundColor DarkCyan
            Write-Host ""
            Write-Host "  Press " -NoNewline -ForegroundColor DarkGray
            Write-Host "Y" -NoNewline -ForegroundColor Yellow
            Write-Host " to compile, any other key to go back..." -ForegroundColor DarkGray

            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if ($key.Character -ne 'y' -and $key.Character -ne 'Y') { continue }

            if (-not (Get-Command ps2exe -ErrorAction SilentlyContinue)) {
                Write-Host "`n  ps2exe not found. Attempting to install from PSGallery..." -ForegroundColor Yellow
                try {
                    Install-Module -Name ps2exe -Scope CurrentUser -Force -ErrorAction Stop
                    Write-Host "  [+] ps2exe installed." -ForegroundColor Green
                } catch {
                    Write-Host "  [!] Could not install ps2exe: $_" -ForegroundColor Red
                    Pause-Menu
                    continue
                }
            }

            Write-Host ""
            Write-Host "  Running ps2exe..." -ForegroundColor DarkGray

            # Build a scriptblock string with proper quoting, then encode it
            $sbParts = [System.Collections.Generic.List[string]]::new()
            $sbParts.Add('& ps2exe')
            foreach ($arg in $argList) {
                if ($arg.StartsWith('-')) {
                    $sbParts.Add($arg)
                } elseif ($arg -match '\s') {
                    $escaped = $arg -replace '"', '\"'
                    $sbParts.Add("`"$escaped`"")
                } else {
                    $sbParts.Add($arg)
                }
            }
            $sbString = $sbParts -join ' '
            $bytes    = [System.Text.Encoding]::Unicode.GetBytes($sbString)
            $encoded  = [Convert]::ToBase64String($bytes)
            try {
                $proc = Start-Process powershell.exe `
                    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" `
                    -Wait -PassThru -NoNewWindow
                if ($proc.ExitCode -eq 0) {
                    Write-Host "`n  [+] Done. Output: $($cfg.DestPath)" -ForegroundColor Green
                } else {
                    Write-Host "`n  [!] ps2exe exited with code $($proc.ExitCode)." -ForegroundColor Red
                }
            } catch {
                Write-Host "`n  [!] Failed to launch: $_" -ForegroundColor Red
            }
            Pause-Menu
            continue
        }

        $parsed = 0
        if (-not [int]::TryParse($choice, [ref]$parsed)) {
            Write-Host "`n  Invalid input." -ForegroundColor Red
            Start-Sleep -Milliseconds 800
            continue
        }

        $row = $script:ps2exeRows | Where-Object { $_.Num -eq $parsed }
        if (-not $row) {
            Write-Host "`n  No item with that number." -ForegroundColor Red
            Start-Sleep -Milliseconds 800
            continue
        }

        switch ($row.Type) {
            'path' {
                $val = Prompt-Value $row.Label $cfg[$row.Key]
                if ($val -and -not (Test-Path $val) -and $row.Key -notin @('DestPath','IconFile')) {
                    Write-Host "  [!] Path not found." -ForegroundColor Red
                    Start-Sleep -Milliseconds 800
                } else {
                    $cfg[$row.Key] = $val
                }
            }
            'string' {$cfg[$row.Key] = Prompt-Value $row.Label $cfg[$row.Key] }
            'bool'   { $cfg[$row.Key] = -not $cfg[$row.Key] }
            'cycle'  {
                $list = switch ($row.Key) {
                    'ThreadModel' { $threadCycle }
                    'ForceArch'   { $archCycle }
                }
                $cfg[$row.Key] = CycleValue $cfg[$row.Key] $list
            }
        }
    }
}
function Invoke-ImageResizer {
    # Load required assembly for image manipulation
    Add-Type -AssemblyName System.Drawing

    # --- State ---
    $cfg = [ordered]@{
        SourcePath = $null
        Height     = $null
        Width      = $null
    }

    $validExtensions = @('.png', '.jpg', '.jpeg', '.bmp', '.gif')

    function ValueDisplay($val) {
        if ($val) { return @{ Text = $val; Color = 'DarkGray' } }
        else      { return @{ Text = '?';   Color = 'DarkRed'  } }
    }

    function Show-ResizerMenu {
        Clear-Host
        Write-Host "  IMAGE RESIZER" -ForegroundColor Cyan
        Write-Host "  $('-' * 52)" -ForegroundColor DarkGray
        Write-Host ""

        # Check if all fields are populated
        $ready = $cfg.SourcePath -and $cfg.Height -and $cfg.Width

        $rows = @(
            @{ Num = 1; Label = 'Source Path'; Val = $cfg.SourcePath; Key = 'SourcePath' }
            @{ Num = 2; Label = 'New Height '; Val = $cfg.Height;     Key = 'Height'     }
            @{ Num = 3; Label = 'New Width  '; Val = $cfg.Width;      Key = 'Width'      }
        )

        foreach ($row in $rows) {
            $display = ValueDisplay $row.Val
            Write-Host "  [$($row.Num)] " -NoNewline -ForegroundColor DarkYellow
            Write-Host "$($row.Label) = " -NoNewline -ForegroundColor Gray
            Write-Host $display.Text -ForegroundColor $display.Color
        }

        Write-Host "  $('-' * 50)" -ForegroundColor DarkGray

        # CREATE option
        $cColor = if ($ready) { 'Green' } else { 'DarkGray' }
        Write-Host "  [" -NoNewline -ForegroundColor DarkGray
        Write-Host "C" -NoNewline -ForegroundColor $cColor
        Write-Host "] " -NoNewline -ForegroundColor DarkGray
        Write-Host "CREATE" -ForegroundColor $cColor

        Write-Host ""
        Write-Host "  $('-' * 52)" -ForegroundColor DarkGray
        Write-Host "  Press " -NoNewline -ForegroundColor DarkGray
        Write-Host "[E]" -NoNewline -ForegroundColor DarkYellow
        Write-Host " to cancel." -ForegroundColor DarkGray

        return $ready
    }

    # --- Main loop ---
    while ($true) {
        $isReady = Show-ResizerMenu
        $choice = (Read-Host "`n  ::").Trim()

        if ($choice -ieq 'E') { return }

        # CREATE logic
        if ($choice -ieq 'C') {
            if (-not $isReady) {
                Write-Host "  [!] All fields are required." -ForegroundColor Red
                Start-Sleep -Milliseconds 800
                continue
            }

            try {
                Write-Host "`n  Processing..." -ForegroundColor Cyan
                $img = [System.Drawing.Image]::FromFile($cfg.SourcePath)
                $bmp = New-Object System.Drawing.Bitmap([int]$cfg.Width, [int]$cfg.Height)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.DrawImage($img, 0, 0, [int]$cfg.Width, [int]$cfg.Height)
                
                $ext = [System.IO.Path]::GetExtension($cfg.SourcePath)
                $base = $cfg.SourcePath.Substring(0, $cfg.SourcePath.Length - $ext.Length)
                $dest = "${base}_resized${ext}"
                
                $bmp.Save($dest)
                
                # Cleanup
                $g.Dispose(); $bmp.Dispose(); $img.Dispose()
                
                Write-Host "  [+] Success: $dest" -ForegroundColor Green
                Pause
            } catch {
                Write-Host "  [!] Failed to resize: $_" -ForegroundColor Red
                Pause
            }
            continue
        }

        # Handle Inputs 1, 2, 3
        switch ($choice) {
            '1' {
                Write-Host "`n  Source Path" -ForegroundColor Cyan
                if ($cfg.SourcePath) { 
                    Write-Host "  Current: $($cfg.SourcePath)" -ForegroundColor DarkGray 
                    Write-Host "  (leave blank to clear)" -ForegroundColor DarkGray
                }
                $input = (Read-Host "  >").Trim().Trim('"')
                
                if ($input -eq '' -and $cfg.SourcePath) { $cfg.SourcePath = $null }
                elseif ($input -ne '') {
                    $ext = [System.IO.Path]::GetExtension($input).ToLower()
                    if (Test-Path $input -PathType Leaf) {
                        if ($validExtensions -contains $ext) { $cfg.SourcePath = $input }
                        else { Write-Host "  [!] Invalid file type ($($validExtensions -join ', '))" -ForegroundColor Red; Start-Sleep 1 }
                    } else { Write-Host "  [!] File not found." -ForegroundColor Red; Start-Sleep 1 }
                }
            }
            '2' {
                $val = (Read-Host "`n  Enter Height (px)").Trim()
                if ($val -match '^\d+$') { $cfg.Height = $val }
                elseif ($val -eq '') { $cfg.Height = $null }
            }
            '3' {
                $val = (Read-Host "`n  Enter Width (px)").Trim()
                if ($val -match '^\d+$') { $cfg.Width = $val }
                elseif ($val -eq '') { $cfg.Width = $null }
            }
        }
    }
}
#endregion
# region == Deployment ==
function FixWinGet-New { # Newer function for fix WinGet Out-Of-The-Box
    Write-Host "Resetting WinGet sources..." -ForegroundColor Yellow
    winget source reset --force
    winget source update
	Write-Host "Reinstalling Nuget..."
	Install-PackageProvider -Name NuGet -Force | Out-Null
	Write-Host "Reloading PSGallery module..."
	Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
	Repair-WinGetPackageManager -Force -Latest

    # Remove the State folder if it exists
    $wingetStatePath = "$env:LOCALAPPDATA\Microsoft\WinGet\State"
    if (Test-Path -Path $wingetStatePath) {
        Write-Host "Clearing WinGet cache..." -ForegroundColor Yellow
        Remove-Item -Path "$wingetStatePath\*" -Recurse -Force
    } else {
        Write-Host "WinGet state folder does not exist, skipping cache cleanup." -ForegroundColor Cyan
    }

    # Download the latest WinGet installer if necessary
    $wingetInstallerPath = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $wingetUri = "https://aka.ms/getwinget"
    
    Write-Host "Checking for existing WinGet installation..." -ForegroundColor Yellow
    if (-not (Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)) {
        Write-Host "Downloading and installing WinGet..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $wingetUri -OutFile $wingetInstallerPath -UseBasicParsing

        # Attempt to reinstall WinGet
        Add-AppxPackage -Path $wingetInstallerPath -ForceApplicationShutdown
    } else {
        Write-Host "WinGet is already installed, skipping reinstallation." -ForegroundColor Cyan
    }

    # Re-check WinGet functionality
    Write-Host "Validating WinGet functionality..." -ForegroundColor Green
    winget --info
    if ($LASTEXITCODE -eq 0) {
        Write-Host "WinGet is functioning properly." -ForegroundColor Green
    } else {
        Write-Host "WinGet is still facing issues. Manual inspection may be required." -ForegroundColor Red
    }
}
function ToggleTaskbarSeconds { # Toggles taskbar clock's seconds on/off. Can also accept -on or -off for definitively setting the setting.
    param(
        [ValidateSet("On", "Off")]
        [string]$State
    )
    
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $regName = "ShowSecondsInSystemClock"
    
    # Get current value (create if missing)
    $current = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    if ($current) {
        $currentValue = $current.ShowSecondsInSystemClock
    } else {
        $currentValue = 0  # Default off if missing
    }
    
    # Determine target value
    if ($State -eq "On") {
        $newValue = 1
    } elseif ($State -eq "Off") {
        $newValue = 0
    } else {
        $newValue = 1 - $currentValue  # Toggle if no param
    }
    
    # Set value
    Set-ItemProperty -Path $regPath -Name $regName -Value $newValue -Type DWord
    
    # Restart Explorer
    $stateText = if($newValue){'ON'}else{'OFF'}
    Write-Host "[~] Set taskbar seconds to: " -ForegroundColor Cyan -NoNewLine ; Write-Host "$stateText" -ForegroundColor Magenta
    #taskkill /f /im explorer.exe 2>$null
    #Start-Sleep 2
    #explorer.exe
}
# Intune Functions 
function IntuneSyncNow { # Initiates an Intune sync immediately
	Start-Process -FilePath "dsregcmd.exe" -ArgumentList "/sync" -NoNewWindow -Wait
	Write-Host "Intune/Entra sync initiated." -ForegroundColor cyan
}
function IntuneDiagnostic { # Creates an html report of Intune deployment/configuration tasks performed on a device
    param (
        [string]$ScriptUrl = "https://raw.githubusercontent.com/petripaavola/Get-IntuneManagementExtensionDiagnostics/refs/heads/main/Get-IntuneManagementExtensionDiagnostics.ps1",
        [string]$SavePath = "$env:TEMP\PSMM\scripts\Get-IntuneManagementExtensionDiagnostics.ps1"
    )

    # Ensure the destination directory exists
    $scriptDir = [System.IO.Path]::GetDirectoryName($SavePath)
    if (-not (Test-Path -Path $scriptDir)) {
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    }

    try {
        # Download the script
        Write-Output "Downloading script to $SavePath..."
        SmartDownload -Url $ScriptUrl -Destination $SavePath
        Write-Host "Script downloaded successfully." -ForegroundColor Green

        # Run the script as admin in a new PowerShell instance
        $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$SavePath`""
        Write-Output "Executing script as admin..."
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-File $SavePath" -Verb RunAs
    } catch {
        Write-Error "An error occurred: $_"
    }
}
function IntuneWinAppUtil { # Downloads IntuneWinAppUtil.exe if it isn't already in $env:TEMP\PSMM\, and then runs as admin
    $installerUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/blob/master/IntuneWinAppUtil.exe"
    $installPath = "$env:TEMP\PSMM\"
    $installerFile = "$installPath\IntuneWinAppUtil.exe"

    # Check if the file already exists
    if (!(Test-Path -Path $installerFile)) {
        Write-Host "[*] Downloading IntuneWinAppUtil.exe..." -ForegroundColor Yellow 
        SmartDownload -Url $installerUrl -Destination $installerFile # Invoke-WebRequest -Uri $installerUrl -OutFile $installerFile
    } else {
        Write-Host "[~] IntuneWinAppUtil.exe already exists. Skipping download." -foregroundcolor Cyan 
    }

    # Run the installer as admin
    Start-Process -FilePath $installerFile -Verb RunAs

    Write-Host "[+] IntuneWinAppUtil launched successfully." -ForegroundColor Green 
}
function IntuneWinAppUtilDecoder { # Downloads IntuneWinAppUtilDecoder.exe if it isn't already in $env:TEMP\PSMM\
    $installerUrl = "https://github.com/okieselbach/Intune/blob/master/IntuneWinAppUtilDecoder/IntuneWinAppUtilDecoder/bin/Release/IntuneWinAppUtilDecoder.exe"
    $installPath = "$env:TEMP\PSMM\"
    $installerFile = "$installPath\IntuneWinAppUtilDecoder.exe"

    # Check if the file already exists
    if (!(Test-Path -Path $installerFile)) {
        Write-Host "[*] Downloading IntuneWinAppUtil.exe..." -ForegroundColor Yellow 
        SmartDownload -Url $installerUrl -Destination $installerFile # Invoke-WebRequest -Uri $installerUrl -OutFile $installerFile
    } else {
        Write-Host "[~] IntuneWinAppUtil.exe already exists. Skipping download." -ForegroundColor Cyan
    }
	
	# Prompt for the .intunewin file path
    # Prompt for .intunewin path and sanitize quotes
    $inputPath = Read-Host -Prompt "[>] Enter the full path to the .intunewin file to decode"
    $intunewinPath = $inputPath.Trim('"')  # Removes surrounding double quotes if present

    if (!(Test-Path -Path $intunewinPath)) {
        Write-Host "[!] The specified .intunewin file does not exist: $intunewinPath" -ForegroundColor Red
        return
    }

    # Run the decoder utility
    Write-Host "[*] Decoding $intunewinPath ..." -foregroundcolor Yellow 
    Start-Process -FilePath $installerFile -ArgumentList "`"$intunewinPath`""
	Start-Sleep -seconds 2 
}
function IntuneAutopilotCSV { # Saves Intune Autopilot .csv info (for autopilot enrollment) to $env:TEMP\PSMM\
    # Define script URLs and paths
    $ScriptUrl 		 = "https://raw.githubusercontent.com/MikePohatu/Get-WindowsAutoPilotInfo/refs/heads/main/Get-WindowsAutoPilotInfo.ps1"
    $ScriptDirectory = "$env:TEMP\PSMM\scripts"
    $ScriptPath 	 = Join-Path -Path $ScriptDirectory -ChildPath "Get-WindowsAutoPilotInfo.ps1"
    $OutputFile      = "$env:TEMP\PSMM\AutopilotCSV.csv"

    # Create the $env:TEMP\PSMM\scripts directory if it doesn't exist
    if (-not(Test-Path $ScriptDirectory)) {mkdir $ScriptDirectory}

    # Download the script to the target location
    try {
        try { 
			SmartDownload -Url $ScriptUrl -Destination $ScriptPath 
		} catch {
			Invoke-WebRequest -Uri $ScriptUrl -OutFile $ScriptPath -ErrorAction Stop
		}
        Write-Host "Script downloaded to $ScriptPath" -ForegroundColor Green
    } catch {
        Write-Host "Error downloading the script: $_" -ForegroundColor Red
        return
    }

    # Verify if the script was downloaded successfully
    if (Test-Path -Path $ScriptPath) {
        try {
            & $ScriptPath -OutputFile $OutputFile
            Write-Host "Autopilot hash exported to $OutputFile" -ForegroundColor Green
        } catch {
            Write-Host "Error running the script: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Script not found at $ScriptPath" -ForegroundColor Red
    }
	Start-Sleep -Seconds 3
}
#endregion
#endregion -End of Function region-

# region === ENGINE  ===
function Pause-Menu {
    Write-Host "`nPress " -NoNewLine -ForegroundColor DarkGray
	Write-Host "any key" -NoNewLine -ForegroundColor Yellow
	Write-Host " to return..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
function Get-MenuItems {
    param([hashtable]$Menu)
    # Returns only selectable items (no separators) with assigned keys
    $key = 1
    $items = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($item in $Menu.Items) {
        if ($item.Separator) {
            $items.Add(@{ Separator = $true; Desc = $item.Desc; Color = $item.Color })
        } else {
            $items.Add($item + @{ Key = "$key" })
            $key++
        }
    }
    return $items
}
function Show-Menu {
    param([string]$MenuKey)

    $cfg      = $script:MenuConfig
    $settings = $cfg.Settings
    $menu     = $cfg.Menus[$MenuKey]

    if (-not $menu) {
        Write-Warning "Menu key '$MenuKey' not found in config."
        return
    }

    $isRoot = ($MenuKey -eq $settings.RootMenu)
    $sep    = $settings.SeparatorChar * $settings.SeparatorWidth

    while ($true) {
        Clear-Host

        $items = Get-MenuItems -Menu $menu

        # Title / Header
        if ($isRoot) {
            Show-Header
        } else {
			Write-Host "  $($menu.Title)" -ForegroundColor Blue
            Write-Host $sep -ForegroundColor DarkGray
        }

        # Render items
        $maxKeyLen = ($items | Where-Object { -not $_.Separator } | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum
        foreach ($item in $items) {
            if ($item.Separator) {
                $innerWidth = $settings.SeparatorWidth - 2
                if ($item.Desc) {
                    $label     = $item.Desc
                    $leftFill  = [math]::Floor(($innerWidth - $label.Length) / 2)
                    $rightFill = $innerWidth - $leftFill - $label.Length
                    if ($rightFill -lt 0) { $rightFill = 0 }
                    Write-Host "  " -NoNewLine
                    Write-Host ($settings.SeparatorChar * $leftFill) -NoNewLine -ForegroundColor DarkGray
                    $descColor = if ($item.Color) { $item.Color } else { "DarkYellow" }
                    Write-Host $label -NoNewLine -ForegroundColor $descColor
                    Write-Host ($settings.SeparatorChar * $rightFill) -ForegroundColor DarkGray
                } else {
                    Write-Host ("  " + ($settings.SeparatorChar * $innerWidth)) -ForegroundColor DarkGray
                }
            } else {
                $pad = ' ' * ($maxKeyLen - $item.Key.Length)
                Write-Host "$pad  [" -NoNewLine -ForegroundColor DarkGray
                Write-Host $item.Key -NoNewLine -ForegroundColor $settings.KeyColor
                Write-Host "] " -NoNewLine -ForegroundColor DarkGray
                $suffix    = if ($item.Submenu) { " =>" } else { "" }
                $autoColor = if ($item.Submenu) { "Gray" } else { "DarkCyan" }
                $itemColor = if ($item.Color)   { $item.Color } else { $autoColor }
                Write-Host "$($item.Label)" -NoNewLine -ForegroundColor $itemColor
                Write-Host "$suffix" -NoNewLine -ForegroundColor Cyan
                if ($item.Desc) {
                    Write-Host "  $($item.Desc)" -NoNewLine -ForegroundColor DarkGray
                }
                Write-Host ""
            }
        }

        # Back / Exit
        Write-Host $sep -ForegroundColor DarkGray
        $backLabel = if ($isRoot) { "Exit" } else { "Back" }
        Write-Host "  [" -NoNewLine -ForegroundColor DarkGray
        Write-Host $settings.ExitKey -NoNewLine -ForegroundColor $settings.KeyColor
        Write-Host "] " -NoNewLine -ForegroundColor DarkGray
		Write-Host "$backLabel" -ForegroundColor DarkRed
        Write-Host $sep -ForegroundColor DarkGray

        # Input
        $choice = (Read-Host "`n  $($settings.Prompt)").Trim()

        # Handle exit/back
        if ($choice -eq $settings.ExitKey -or $choice -eq $settings.ExitKey.ToLower()) {
            return
        }

        # Match against selectable items
        $selected = $items | Where-Object { -not $_.Separator -and ($_.Key -eq $choice -or $_.Label -ieq $choice) }

        if (-not $selected) {
            Write-Host "`n  Invalid selection." -ForegroundColor Red
            Start-Sleep -Milliseconds 800
            continue
        }

        if ($selected.Submenu) {
            Show-Menu -MenuKey $selected.Submenu
        } elseif ($selected.Action) {
            Write-Host ""
            & $selected.Action
        }
    }
} #endregion 

# === Execution Block === 
Show-Menu -MenuKey $script:MenuConfig.Settings.RootMenu

# CHANGELOG
# 0.0.1 - 04/12/2026 - Release
