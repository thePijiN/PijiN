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
# MODULAR MENU - Powershell 5.1 Utility by PijiN
$ScriptVersion = '0.0.3' 

Start-Sleep -seconds 10
# region ### Mainmenu Header ###
function DetectActivTrak { return Test-Path "C:\Windows\SysWOW64\aamdata\atutil.exe" }
function DetectBlackpoint { return Test-Path "C:\Program Files (x86)\Blackpoint" }
function DetectCloudRadial {return Test-Path "C:\Program Files (x86)\CloudRadial Agent\unins000.exe"}
function DetectCrowdstrike {return Test-Path "C:\Program Files\CrowdStrike"}
function DetectImmyAgent { return Test-Path "C:\Program Files (x86)\ImmyBot\Immybot.Agent.exe" }
function DetectHuntress { return Test-Path "C:\Program Files (x86)\Huntress" }
function DetectLTAgent {return Test-Path "C:\Windows\LTSvC\LTErrors.txt"}
function DetectNinjaAgent {return Test-Path "C:\Program Files (x86)\NinjaOne\NinjaRMMAgent.exe"}
function DetectNinite { return Test-Path "C:\Program Files (x86)\Ninite Agent\NiniteAgent.exe" }
function DetectPiaAgent {return Test-Path "C:\Program Files (x86)\OrchestratorAgent\OrchestratorAgent.exe"}
function Initialize-DomainInfo {
    $script:DomainInfoCached = $false
    $script:JoinType         = $null
    $script:DomainName       = $null
    $script:TenantName       = $null

    try {
        $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $IsAdmin) {
            $script:JoinType       = 'PermissionError'
            $script:DomainInfoCached = $true
            return
        }

        $dsreg          = dsregcmd /status 2>$null
        $AzureAdJoined  = $dsreg -match "AzureAdJoined\s*:\s*YES"
        $DomainJoined   = $dsreg -match "DomainJoined\s*:\s*YES"

        $tenantLine     = $dsreg | Where-Object { $_ -match "TenantName\s*:\s*\S" } | Select-Object -First 1
        $domainLine     = $dsreg | Where-Object { $_ -match "DomainName\s*:\s*\S" } | Select-Object -First 1

        $script:TenantName = if ($tenantLine) { ($tenantLine -replace '.*TenantName\s*:\s*', '').Trim() } else { $null }
        $script:DomainName = if ($domainLine) { ($domainLine -replace '.*DomainName\s*:\s*', '').Trim()  } else { $null }

        $script:JoinType = if    ($AzureAdJoined -and $DomainJoined) { 'Hybrid' }
                           elseif ($AzureAdJoined)                    { 'Entra'  }
                           elseif ($DomainJoined)                     { 'Local'  }
                           else                                        { 'None'   }

        $script:DomainInfoCached = $true
    } catch {
        $script:JoinType         = 'Error'
        $script:DomainInfoCached = $true
    }
}
function GetJoinStatus {
    if (-not $script:DomainInfoCached) { Initialize-DomainInfo }

    switch ($script:JoinType) {
        'PermissionError' {
            Write-Host "<INSUFFICIENT PERMISSIONS>" -ForegroundColor DarkRed -NoNewline
        }
        'Hybrid' {
            Write-Host "Hybrid" -ForegroundColor Yellow -NoNewline
            if ($script:DomainName -or $script:TenantName) {
                Write-Host " (" -ForegroundColor DarkGray -NoNewline
                if ($script:DomainName) { Write-Host $script:DomainName -ForegroundColor Green  -NoNewline }
                if ($script:DomainName -and $script:TenantName) { Write-Host " / " -ForegroundColor DarkGray -NoNewline }
                if ($script:TenantName) { Write-Host $script:TenantName -ForegroundColor Cyan   -NoNewline }
                Write-Host ")" -ForegroundColor DarkGray -NoNewline
            }
        }
        'Entra' {
            Write-Host "Entra" -ForegroundColor Cyan -NoNewline
            if ($script:TenantName) { Write-Host " (" -ForegroundColor DarkGray -NoNewline ; Write-Host $script:TenantName -ForegroundColor Cyan -NoNewline ; Write-Host ")" -ForegroundColor DarkGray -NoNewline }
        }
        'Local' {
            Write-Host "Local" -ForegroundColor Green -NoNewline
            if ($script:DomainName) { Write-Host " (" -ForegroundColor DarkGray -NoNewline ; Write-Host $script:DomainName -ForegroundColor Green -NoNewline ; Write-Host ")" -ForegroundColor DarkGray -NoNewline }
        }
        'None'  { Write-Host "None"    -ForegroundColor Red -NoNewline }
        'Error' { Write-Host "<ERROR>" -ForegroundColor Red -NoNewline }
    }
}
function GetLTAgentID { # Simplified version of PullAgentID - This just saves the Agent ID value (retrieved from registry) as $global:AgentID
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
	$art = @( # Standard Art
		'\----------\  '
		' \          \ '
		'Modular Menu \'
		' by: PijiN   /'
		' /   #####  / '
		'/----------/  '
	)
    # --- Collect data ---
    $hostname = $env:COMPUTERNAME

    $serial = try {
        (Get-CimInstance Win32_BIOS).SerialNumber.Trim()
    } catch { 'N/A' }

    GetLTAgentID  # populates $global:AgentID

    # --- Agent presence: Label => detect scriptblock ---
	$agentChecks = [ordered]@{
        NINJA1 = { DetectNinjaAgent }
        CRWDST = { DetectCrowdstrike }
        CLDRAD = { DetectCloudRadial }
        NINITE = { DetectNinite }
        HNTRSS = { DetectHuntress }
        BLKPNT = { DetectBlackpoint }
        ACVTRK = { DetectActivTrak }
        IMMYBT = { DetectImmyAgent }
        PIA    = { DetectPiaAgent }
        LBTECH = { DetectLTAgent }
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
    Write-Host $currentUser -ForegroundColor $userColor #-NoNewLine
	<# LT ID
    Write-Host $ltLabel -NoNewLine -ForegroundColor DarkGray
    Write-Host $ltVal             -ForegroundColor $ltColor 
	#>

	# Build detected-only list in defined priority order
    $agentOrder = @('NINJA1','CRWDST','CLDRAD','NINITE','HNTRSS','BLKPNT','ACVTRK','IMMYBT','PIA','LBTECH')
    $detected   = @($agentOrder | Where-Object { $agentResults[$_] })

    # Split detected agents across two rows
    $splitAt    = if ($detected.Count -gt 0) { [math]::Ceiling($detected.Count / 2) } else { 0 }
    $row1agents = if ($detected.Count -gt 0) { @($detected[0..($splitAt - 1)]) }                          else { @() }
    $row2agents = if ($detected.Count -gt $splitAt) { @($detected[$splitAt..($detected.Count - 1)]) }     else { @() }
	
    # Line 4 - art line 4 + Agents row 1
    Write-Host ($art[4].PadRight($artWidth)) -NoNewLine -ForegroundColor DarkCyan
    Write-Host ' Agents: ' -NoNewLine -ForegroundColor DarkGray
    foreach ($name in $row1agents) {
        if ($name -eq 'LBTECH' -and $global:AgentID -ne 'N/A') {
            Write-Host $name -NoNewLine -ForegroundColor Green
            Write-Host ':'   -NoNewLine -ForegroundColor DarkGray
            Write-Host "$global:AgentID " -NoNewLine -ForegroundColor Yellow
        } else {
            $padded = $name.PadRight(6)
            Write-Host "$padded " -NoNewLine -ForegroundColor Green
        }
    }
    Write-Host ''

    # Line 5 - art line 5 + Agents row 2
    $agentIndent = ' ' * (' Agents: '.Length)
    Write-Host ($art[5].PadRight($artWidth)) -NoNewLine -ForegroundColor DarkCyan
    if ($row2agents.Count -gt 0) {
        Write-Host $agentIndent -NoNewLine
        foreach ($name in $row2agents) {
            if ($name -eq 'LBTECH' -and $global:AgentID -ne 'N/A') {
                Write-Host $name -NoNewLine -ForegroundColor Green
                Write-Host ':'   -NoNewLine -ForegroundColor DarkGray
                Write-Host "$global:AgentID " -NoNewLine -ForegroundColor Yellow
            } else {
                $padded = $name.PadRight(6)
                Write-Host "$padded " -NoNewLine -ForegroundColor Green
            }
        }
    }
    Write-Host ''

    # Closing separator
	Write-Host "-----------------| " -NoNewLine -ForegroundColor DarkGray
	$verColor = if ($OnLatest) { 'Green' } else { 'Yellow' }
    Write-Host "Version: " -NoNewLine -ForegroundColor Gray
    Write-Host $ScriptVersion -NoNewLine -ForegroundColor $verColor
	Write-Host " |--------------|..............." -ForegroundColor DarkGray
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
                @{ Label = 'Spacegame';     Color = 'DarkCyan';   Desc = 'Far out';            Action = { RunExternalScript -noLog -ScriptURL "https://raw.githubusercontent.com/thePijiN/PijiN/refs/heads/main/Spacegame.ps1" } }
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
                @{ Label = 'Separator';                      Color = 'Yellow'; Desc = '\  Maintenance  /';                                                      Separator = $true }
                @{ Label = 'Clear Temp Files';               Desc = 'Purge temp folders with size preview';          Action = { Clear-TempFiles } }
                @{ Label = 'Reset Network Stack';            Desc = 'Flush DNS, Winsock reset, release/renew IP';    Action = { Reset-NetworkStack } }
                @{ Label = 'Reset Print Spooler';            Desc = 'Stop spooler, clear queue, restart';            Action = { Reset-PrintSpooler } }
                @{ Label = 'Remove All Printers';            Desc = 'Wipe printers/drivers (spares virtual ones)';   Action = { Reset-PrinterSubsystem } }
                @{ Label = 'Manage Startup Items';           Desc = 'View/disable reg, folder, and task startups';   Action = { Manage-StartupItems } }
                @{ Label = 'Separator';                      Color = 'Red'; Desc = '==>  Tools  <==';                                                            Separator = $true }
				@{ Label = 'PS2EXE Compiler'; 				 Desc = 'Guided ps2exe wrapper'; 						 Action = { Invoke-PS2EXE } }
				@{ Label = 'Image Resizer'; 				 Desc = 'Supply image, redefine height/width'; 			 Action = { Invoke-ImageResizer } }
                @{ Label = 'Open Shell as SYSTEM';           Desc = 'Launch PS or CMD via scheduled task';           Action = { Open-AsSystem } }
                @{ Label = 'Fix WinGet';                     Desc = 'Reset sources, repair, reinstall if needed';    Action = { FixWinGet-New } }
                @{ Label = 'Scan for Illegal Characters';    Desc = 'Detect/remediate non-ASCII in a script file';   Action = { DetectIllegalCharacters } }
				@{ Label = 'Watch Log File'; 				 Desc = 'Stream a log/txt/json in a live tail window';	 Action = { Watch-LogFile } }
				@{ Label = 'Separator';						 Color = 'Cyan'; Desc = '~*  Scheduled Tasks / Startup  *~'; Separator = $true }
				@{ Label = 'Create New Task';				 Desc = 'Create Scheduled Task';						 Action = { Invoke-TaskCreator } }
				@{ Label = 'Startup App Manager'; 			 Desc = 'Startup App Manager';					 Action = { Invoke-LaunchScriptManager } }
                @{ Label = 'Separator';                      Color = 'DarkRed'; Desc = '-=#  Major Version Update  #+-';                                                      Separator = $true }
                @{ Label = 'Upgrade to Windows 11';          Desc = 'Download and launch Update Assistant';          Action = { Invoke-Windows11Upgrade } }
                @{ Label = 'Upgrade to Windows 11 (Silent)'; Desc = 'Same, unattended';                              Action = { Invoke-Windows11Upgrade -Silent } }
            )
        }
 
        Intune = @{
            Title = 'Intune Tools'
            Items = @(
				@{ Label = 'Separator';                 Color = 'Cyan'; Desc = '~  App Packaging  ~';                                                         Separator = $true }
                @{ Label = 'IntuneWinAppUtil';          Desc = 'Create .intunewin packages';                       Action = { IntuneWinAppUtil } }
                @{ Label = 'IntuneWinAppUtil Decoder';  Desc = 'Inspect/decode .intunewin packages';               Action = { IntuneWinAppUtilDecoder } }
                @{ Label = 'Separator';                 Color = 'DarkYellow'; Desc = '>  Device  <';                                                            Separator = $true }
                @{ Label = 'Sync Intune Now';           Desc = 'Trigger immediate Intune/Entra sync';              Action = { IntuneSyncNow } }
                @{ Label = 'Intune Diagnostic';         Desc = 'HTML report of recent Intune deployments';         Action = { IntuneDiagnostic } }
                @{ Label = 'Export AutoPilot CSV';      Desc = 'Save hardware hash to PSMM\AutopilotCSV.csv';      Action = { IntuneAutopilotCSV } }
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
	Write-Host "A Powershell utility by PijiN" -ForegroundColor DarkCyan
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
function Send-ToastNotification { # Use -Title & -Body to customize/send a Windows toast notification
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [string]$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    )

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]         | Out-Null

    $template = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$Title</text>
            <text>$Body</text>
        </binding>
    </visual>
</toast>
"@

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($template)

    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
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

    function Invoke-PowerCfg {
        param (
            [string]$Arguments
        )

        cmd /c "powercfg $Arguments" *> $null

        if ($LASTEXITCODE -ne 0) {
            throw "powercfg failed: $Arguments"
        }
    }

    Clear-Host

    Write-Host "`n  Power Plan" -ForegroundColor Cyan
    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray

    Write-Host "  [1] " -NoNewLine -ForegroundColor DarkGray
    Write-Host "Always On" -NoNewLine -ForegroundColor White
    Write-Host "         No sleep, no display timeout, no lock" -ForegroundColor DarkGray

    Write-Host "  [2] " -NoNewLine -ForegroundColor DarkGray
    Write-Host "Custom" -NoNewLine -ForegroundColor White
    Write-Host "            No sleep, custom display + lock timeout" -ForegroundColor DarkGray

    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray

    $choice = (Read-Host "`n  Select").Trim()

    switch ($choice) {

        '1' {
            $timeoutMins = 0
        }

        '2' {

            $inputValue = Read-Host "  Timeout (minutes)"

            if ($inputValue -notmatch '^\d+$') {
                Write-Host "`n  Invalid input." -ForegroundColor Red
                Start-Sleep -Milliseconds 1200
                return
            }

            $timeoutMins = [int]$inputValue
        }

        default {
            Write-Host "`n  Cancelled." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 800
            return
        }
    }

    try {

        # High Performance
        Invoke-PowerCfg "/setactive SCHEME_MAX"

        # Disable sleep / hibernate
        Invoke-PowerCfg "/change standby-timeout-ac 0"
        Invoke-PowerCfg "/change standby-timeout-dc 0"

        Invoke-PowerCfg "/change hibernate-timeout-ac 0"
        Invoke-PowerCfg "/change hibernate-timeout-dc 0"

        # Disable disk timeout
        Invoke-PowerCfg "/change disk-timeout-ac 0"
        Invoke-PowerCfg "/change disk-timeout-dc 0"

        # Display timeout
        Invoke-PowerCfg "/change monitor-timeout-ac $timeoutMins"
        Invoke-PowerCfg "/change monitor-timeout-dc $timeoutMins"

        # Console lock display timeout
        # (helps prevent automatic lock behavior tied to display timeout)
        Invoke-PowerCfg "/setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK $timeoutMins"
        Invoke-PowerCfg "/setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK $timeoutMins"

        # Re-apply scheme so advanced settings commit
        Invoke-PowerCfg "/setactive SCHEME_CURRENT"

        $label = if ($timeoutMins -eq 0) {
            "Always On"
        }
        else {
            "Custom ($timeoutMins minute timeout)"
        }

        Write-Host "`n  [+] Power plan applied: " -NoNewLine -ForegroundColor Green
        Write-Host $label -ForegroundColor Cyan

    }
    catch {
        Write-Host "`n  [!] $_" -ForegroundColor Red
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
function Reset-PrinterSubsystem {

    # --- STATE ---
    $cfg = [ordered]@{
        CleanDriverStore = $false
    }

    $exitKey = $script:MenuConfig.Settings.ExitKey

    # --- HELPERS ---
    function ValueDisplay($val, $type) {
        switch ($type) {
            'bool' {
                if ($val) { return @{ Text = 'Yes'; Color = 'Green' } }
                else      { return @{ Text = 'No';  Color = 'Red'   } }
            }
        }
    }

    function Show-PrinterResetMenu {
        Clear-Host
        Write-Host "  Reset Printer Subsystem" -ForegroundColor Cyan
        Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Removes all printers, ports, and drivers." -ForegroundColor DarkGray
        Write-Host "  Cleans registry entries to prevent ghost printers in Settings." -ForegroundColor DarkGray
        Write-Host "  Skips: Microsoft Print to PDF, OneNote, Bluebeam PDF, Adobe PDF." -ForegroundColor DarkGray
        Write-Host ""

        $rows = @(
            @{ Num = 1; Label = 'Clean DriverStore '; Val = $cfg.CleanDriverStore; Type = 'bool'; Key = 'CleanDriverStore' }
        )

        $maxNum = ($rows | Where-Object { $_.Num } |
            ForEach-Object { "$($_.Num)".Length } |
            Measure-Object -Maximum).Maximum

        foreach ($row in $rows) {
            $display = ValueDisplay $row.Val $row.Type
            $pad     = ' ' * ($maxNum - "$($row.Num)".Length)
            Write-Host "$pad  [" -NoNewline -ForegroundColor DarkGray
            Write-Host $row.Num  -NoNewline -ForegroundColor DarkYellow
            Write-Host "] "      -NoNewline -ForegroundColor DarkGray
            Write-Host $row.Label -NoNewline -ForegroundColor Gray
            Write-Host "= "      -NoNewline -ForegroundColor DarkGray
            Write-Host $display.Text -ForegroundColor $display.Color
        }

        Write-Host ""
        Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
        Write-Host "  [" -NoNewline -ForegroundColor DarkGray
        Write-Host "Z"   -NoNewline -ForegroundColor Green
        Write-Host "] "  -NoNewline -ForegroundColor DarkGray
        Write-Host "RESET" -ForegroundColor Green

        Write-Host ""
        Write-Host "  $('-' * 52)" -ForegroundColor DarkGray
        Write-Host "  Press "     -NoNewline -ForegroundColor DarkGray
        Write-Host "[$exitKey]"   -NoNewline -ForegroundColor DarkYellow
        Write-Host " to cancel."  -ForegroundColor DarkGray

        return $true
    }

    # --- MAIN LOOP ---
    while ($true) {
        $isReady = Show-PrinterResetMenu
        $choice  = (Read-Host "`n  ::").Trim()

        if ($choice -ieq $exitKey) { return }

        if ($choice -ieq 'Z') {

            $cleanDS = $cfg.CleanDriverStore

            $script = @"
`$ErrorActionPreference = "SilentlyContinue"

`$excludedPrinters = @(
    "Microsoft Print to PDF",
    "OneNote (Desktop)",
    "Bluebeam PDF",
    "Adobe PDF"
)

`$protectedDrivers = @(
    "Microsoft Print To PDF",
    "Microsoft Software Printer Driver",
    "Send to Microsoft OneNote 16 Driver",
    "Microsoft enhanced Point and Print compatibility driver"
)

`$protectedRegKeys = @(
    "Microsoft Print to PDF",
    "OneNote (Desktop)",
    "Bluebeam PDF",
    "Adobe PDF"
)

function Restart-Spooler {
    Stop-Service spooler -Force
    Start-Sleep 2
    Start-Service spooler
}

Write-Host ""
Write-Host "=== Printer Cleanup Starting ===" -ForegroundColor Cyan

# --- STEP 1: REMOVE PRINTERS (WMI fallback if Remove-Printer fails) ---
Restart-Spooler

Get-Printer | ForEach-Object {
    if (`$excludedPrinters -contains `$_.Name) {
        Write-Host "Skipping printer: `$(`$_.Name)" -ForegroundColor Green
    } else {
        try {
            Remove-Printer -Name `$_.Name -ErrorAction Stop
            Write-Host "Removed printer: `$(`$_.Name)" -ForegroundColor Yellow
        } catch {
            # WMI fallback
            `$wmiPrinter = Get-WmiObject Win32_Printer -Filter "Name='`$(`$_.Name -replace "'","''")'"
            if (`$wmiPrinter) {
                `$wmiPrinter.Delete() | Out-Null
                Write-Host "Removed printer (WMI): `$(`$_.Name)" -ForegroundColor Yellow
            } else {
                Write-Host "Could not remove printer: `$(`$_.Name)" -ForegroundColor Red
            }
        }
    }
}

Restart-Spooler

# --- STEP 2: CLEAN SPOOL FOLDER ---
Write-Host "Cleaning spool folder..." -ForegroundColor Cyan
`$spoolPath = "C:\Windows\System32\spool\PRINTERS"
Get-ChildItem -Path `$spoolPath -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

# --- STEP 3: REMOVE PORTS ---
Get-PrinterPort | ForEach-Object {
    if (`$_.Name -match "^(COM\d+|LPT\d+|FILE:|PORTPROMPT:|nul:|SHRFAX:|XPSPort:)$") { return }
    if (`$_.Name -like "Microsoft.Office.OneNote*") { return }
    try {
        Remove-PrinterPort -Name `$_.Name -ErrorAction Stop
        Write-Host "Removed port: `$(`$_.Name)" -ForegroundColor Yellow
    } catch {}
}

Restart-Spooler

# --- STEP 4: REMOVE DRIVERS (spooler stopped for clean removal) ---
Stop-Service spooler -Force
Start-Sleep 2

Get-PrinterDriver | Where-Object { -not (`$protectedDrivers -contains `$_.Name) } | ForEach-Object {
    try {
        Remove-PrinterDriver -Name `$_.Name -ErrorAction Stop
        Write-Host "Removed driver: `$(`$_.Name)" -ForegroundColor Yellow
    } catch {
        # Try with RemoveFromDriverStore flag
        try {
            Remove-PrinterDriver -Name `$_.Name -RemoveFromDriverStore -ErrorAction Stop
            Write-Host "Removed driver (+ store): `$(`$_.Name)" -ForegroundColor Yellow
        } catch {}
    }
}

Start-Service spooler
Start-Sleep 2

# --- STEP 5: REGISTRY CLEANUP (prevents ghost printers in Settings) ---
Write-Host "Cleaning printer registry keys..." -ForegroundColor Cyan

# HKLM local printer keys
`$hklmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers"
if (Test-Path `$hklmPath) {
    Get-ChildItem `$hklmPath | ForEach-Object {
        `$printerName = `$_.PSChildName
        if (`$protectedRegKeys -contains `$printerName) { return }
        Remove-Item -Path `$_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed registry key: `$printerName" -ForegroundColor Yellow
    }
}

# Per-user network printer connections (all loaded user hives)
`$huPath = "Registry::HKEY_USERS"
Get-ChildItem `$huPath -ErrorAction SilentlyContinue | ForEach-Object {
    `$sid = `$_.PSChildName
    if (`$sid -notmatch "^S-1-5-21") { return }  # skip built-in accounts
    `$connPath = "Registry::HKEY_USERS\`$sid\Printers\Connections"
    if (-not (Test-Path `$connPath)) { return }
    Get-ChildItem `$connPath -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path `$_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed connection key: `$(`$_.PSChildName)" -ForegroundColor Yellow
    }
}

# --- STEP 6: DRIVERSTORE CLEAN ---
if (`$CleanDriverStore) {
    Write-Host "Cleaning DriverStore..." -ForegroundColor Cyan

    `$raw = pnputil /enum-drivers
    `$drivers = @()
    `$current = @{}

    foreach (`$line in `$raw) {
        if (`$line -match "Published Name\s*:\s*(.+)") {
            if (`$current.Count -gt 0) { `$drivers += [PSCustomObject]`$current }
            `$current = @{ PublishedName = `$matches[1].Trim() }
        } elseif (`$line -match "Provider Name\s*:\s*(.+)") {
            `$current.Provider = `$matches[1].Trim()
        } elseif (`$line -match "Class Name\s*:\s*(.+)") {
            `$current.Class = `$matches[1].Trim()
        }
    }
    if (`$current.Count -gt 0) { `$drivers += [PSCustomObject]`$current }

    foreach (`$drv in `$drivers) {
        if (`$drv.Class -ne "Printer") { continue }
        if (`$drv.Provider -match "Microsoft") { continue }
        pnputil /delete-driver `$drv.PublishedName /uninstall /force | Out-Null
        Write-Host "Removed driver package: `$(`$drv.PublishedName)" -ForegroundColor Yellow
    }
}

Restart-Spooler
Write-Host ""
Write-Host "=== Cleanup Complete ===" -ForegroundColor Green
Write-Host ""
"@

            # Pass CleanDriverStore as a param to the spawned script
            $paramBlock = "`$CleanDriverStore = `$$($cleanDS.ToString().ToLower())`n"
            $fullScript  = $paramBlock + $script

            $bytes   = [System.Text.Encoding]::Unicode.GetBytes($fullScript)
            $encoded = [Convert]::ToBase64String($bytes)

            try {
                $wtArgs = @("-p", '"PowerShell"', 'powershell.exe', "-EncodedCommand", $encoded)
                Start-Process wt.exe -ArgumentList $wtArgs -Verb RunAs -Wait
            } catch {
                Start-Process powershell.exe -ArgumentList "-EncodedCommand $encoded" -Verb RunAs -Wait
            }

            Write-Host ""
            Write-Host "  [+] Printer subsystem reset complete." -ForegroundColor Green
            Pause-Menu
            return
        }

        # --- FIELD DISPATCH ---
        $parsed = 0
        if (-not [int]::TryParse($choice, [ref]$parsed)) {
            Write-Host "`n  Invalid input." -ForegroundColor Red
            Start-Sleep -Milliseconds 800
            continue
        }

        $rows = @(
            @{ Num = 1; Key = 'CleanDriverStore'; Type = 'bool' }
        )

        $row = $rows | Where-Object { $_.Num -eq $parsed }
        if (-not $row) {
            Write-Host "`n  No item with that number." -ForegroundColor Red
            Start-Sleep -Milliseconds 800
            continue
        }

        if ($row.Type -eq 'bool') {
            $cfg[$row.Key] = -not $cfg[$row.Key]
        }
    }
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
function Watch-LogFile {
    $validExtensions = @('.log', '.txt', '.json', '.csv', '.xml', '.out')

    while ($true) {
        Clear-Host
        Write-Host "  WATCH LOG FILE" -ForegroundColor Cyan
        Write-Host "  $('-' * 52)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Drop a file path below (or " -NoNewLine -ForegroundColor DarkGray
        Write-Host "[E]" -NoNewLine -ForegroundColor DarkYellow
        Write-Host " to cancel)" -ForegroundColor DarkGray
        Write-Host ""

        $raw = (Read-Host "  >>").Trim().Trim('"').Trim("'")

        if ($raw -ieq 'E' -or $raw -eq '') { return }

        $ext = [System.IO.Path]::GetExtension($raw).ToLower()

        if (-not (Test-Path $raw -PathType Leaf)) {
            Write-Host "`n  [!] File not found: $raw" -ForegroundColor Red
            Start-Sleep -Milliseconds 900
            continue
        }

        if ($validExtensions -notcontains $ext) {
            Write-Host "`n  [!] Unsupported type ($ext). Allowed: $($validExtensions -join ', ')" -ForegroundColor Red
            Start-Sleep -Milliseconds 900
            continue
        }

        $title  = [System.IO.Path]::GetFileName($raw)
        $script = "
            `$host.UI.RawUI.WindowTitle = 'Watching: $title'
            Write-Host '  Watching: $raw' -ForegroundColor Cyan
            Write-Host '  $('-' * 60)' -ForegroundColor DarkGray
            Get-Content -Path '$raw' -Wait -Tail 40
        "

        Start-Process powershell -ArgumentList '-NoExit', '-Command', $script
        Write-Host "`n  [+] Spawned watcher for: $title" -ForegroundColor Green
        Start-Sleep -Milliseconds 700
        return
    }
}
function Invoke-LaunchScriptManager {
    param(
        [string]$LaunchScriptPath = "$env:APPDATA\Open-OnStartup.ps1",
        [string]$TaskName         = 'PSMM_AutoLaunch'
    )
 
    $entries = [System.Collections.Generic.List[hashtable]]::new()
 
    $dir = [System.IO.Path]::GetDirectoryName($LaunchScriptPath)
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
 
    function Import-LaunchScript {
        if (-not (Test-Path $LaunchScriptPath)) { return }
        foreach ($line in (Get-Content $LaunchScriptPath | Where-Object { $_ -match '#ENTRY:' })) {
            if ($line -match '#ENTRY:(.+)') {
                try {
                    $d = $matches[1] | ConvertFrom-Json
                    $entries.Add([ordered]@{
                        Path     = $d.Path
                        Args     = $d.Args
                        Elevated = [bool]$d.Elevated
                        Delay    = [int]$d.Delay
                    })
                } catch {}
            }
        }
    }
 
    function Export-LaunchScript {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('# PSMM AutoLaunch Script - managed by Invoke-LaunchScriptManager')
        $lines.Add('# Do not hand-edit ENTRY lines; use the menu.')
        $lines.Add('')
        foreach ($e in $entries) {
            $meta   = [pscustomobject]@{
                Path     = $e.Path
                Args     = $e.Args
                Elevated = $e.Elevated
                Delay    = $e.Delay
            } | ConvertTo-Json -Compress
            $spArgs = "-FilePath `"$($e.Path)`""
            if ($e.Args)       { $spArgs += " -ArgumentList `"$($e.Args)`"" }
            if ($e.Elevated)   { $spArgs += ' -Verb RunAs' }
            $spArgs += ' -WindowStyle Normal'
            $lines.Add("#ENTRY:$meta")
            if ($e.Delay -gt 0) { $lines.Add("Start-Sleep -Seconds $($e.Delay)") }
            $lines.Add("Start-Process $spArgs")
            $lines.Add('')
        }
        Set-Content -Path $LaunchScriptPath -Value $lines -Encoding UTF8
    }
 
    function Register-LaunchTask {
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$LaunchScriptPath`""
        $trigger   = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit 0 `
            -MultipleInstances IgnoreNew
        try {
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
                -Principal $principal -Settings $settings -Force -ErrorAction Stop
            return $true
        } catch { return $_ }
    }
 
    function Show-LaunchMenu {
        Clear-Host
        Write-Host "`n  MULTI-APP LAUNCH MANAGER" -ForegroundColor Cyan
        Write-Host "  $('=' * 54)" -ForegroundColor DarkCyan
        $t      = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $status = if ($t) { "[REGISTERED - $($t.State)]" } else { '[NOT REGISTERED]' }
        $sColor = if ($t) { 'Green' } else { 'DarkRed' }
        Write-Host "  Task '$TaskName': " -NoNewline -ForegroundColor DarkGray
        Write-Host $status -ForegroundColor $sColor
        Write-Host "  Script: $LaunchScriptPath`n" -ForegroundColor DarkGray
 
        if ($entries.Count -eq 0) {
            Write-Host '  (no entries yet)' -ForegroundColor DarkGray
        } else {
            $i = 1
            foreach ($e in $entries) {
                $tags = @()
                if ($e.Elevated)    { $tags += 'ELEVATED' }
                if ($e.Delay -gt 0) { $tags += "+$($e.Delay)s delay" }
                $tag = if ($tags) { " [$($tags -join ', ')]" } else { '' }
                Write-Host "  [$i] " -NoNewline -ForegroundColor DarkYellow
                Write-Host "$([System.IO.Path]::GetFileName($e.Path))$tag" -ForegroundColor Gray
                Write-Host "      $($e.Path)" -ForegroundColor DarkGray
                if ($e.Args) { Write-Host "      Args: $($e.Args)" -ForegroundColor DarkGray }
                $i++
            }
        }
 
        Write-Host "`n  $('-' * 54)" -ForegroundColor DarkGray
        Write-Host '  [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'A'   -NoNewline -ForegroundColor Green
        Write-Host '] Add    [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'R'   -NoNewline -ForegroundColor Red
        Write-Host '] Remove    [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'S'   -NoNewline -ForegroundColor Cyan
        Write-Host '] Save    [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'P'   -NoNewline -ForegroundColor Magenta
        Write-Host '] Preview' -ForegroundColor DarkGray
        Write-Host '  [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'C'   -NoNewline -ForegroundColor Green
        Write-Host '] Create Task        [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'X'   -NoNewline -ForegroundColor Red
        Write-Host '] Remove Task' -ForegroundColor DarkGray
        Write-Host "  $('-' * 54)" -ForegroundColor DarkGray
        Write-Host '  Press [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'E'          -NoNewline -ForegroundColor DarkYellow
        Write-Host "] to cancel.`n" -ForegroundColor DarkGray
    }
 
    Import-LaunchScript
 
    while ($true) {
        Show-LaunchMenu
        $choice = (Read-Host '  ::').Trim().ToUpper()
 
        switch ($choice) {
 
            'E' { return }
 
            'A' {
                Clear-Host
                Write-Host "`n  ADD ENTRY`n  $('-' * 44)`n" -ForegroundColor Cyan
                $path = (Read-Host '  Executable path').Trim().Trim('"')
                if ($path -eq '') { break }
                if (-not (Test-Path $path -PathType Leaf)) {
                    Write-Host '  [!] File not found.' -ForegroundColor Red
                    Start-Sleep -Milliseconds 900; break
                }
                $a     = (Read-Host '  Arguments        (blank = none)').Trim()
                $elev  = (Read-Host '  Run elevated?    [Y/N]').Trim().ToUpper() -eq 'Y'
                $dStr  = (Read-Host '  Delay in secs    (blank = 0)').Trim()
                $delay = if ($dStr -match '^\d+$') { [int]$dStr } else { 0 }
                $entries.Add([ordered]@{
                    Path     = $path
                    Args     = if ($a) { $a } else { $null }
                    Elevated = $elev
                    Delay    = $delay
                })
                Write-Host "`n  [+] Added: $([System.IO.Path]::GetFileName($path))" -ForegroundColor Green
                Start-Sleep -Milliseconds 700
            }
 
            'R' {
                if ($entries.Count -eq 0) {
                    Write-Host '  [!] Nothing to remove.' -ForegroundColor Red; Start-Sleep -Milliseconds 800; break
                }
                $idxStr = (Read-Host '  Entry number to remove').Trim()
                if ($idxStr -match '^\d+$') {
                    $idx = [int]$idxStr - 1
                    if ($idx -ge 0 -and $idx -lt $entries.Count) {
                        $name = [System.IO.Path]::GetFileName($entries[$idx].Path)
                        $entries.RemoveAt($idx)
                        Write-Host "  [-] Removed: $name" -ForegroundColor DarkYellow
                    } else { Write-Host '  [!] Out of range.' -ForegroundColor Red }
                    Start-Sleep -Milliseconds 700
                }
            }
 
            'S' {
                Export-LaunchScript
                Write-Host "`n  [+] Saved: $LaunchScriptPath" -ForegroundColor Green
                Start-Sleep -Milliseconds 900
            }
 
            'P' {
                if (-not (Test-Path $LaunchScriptPath)) {
                    Write-Host '  [!] Not saved yet. Press [S] first.' -ForegroundColor Red
                    Start-Sleep -Milliseconds 900; break
                }
                Clear-Host
                Write-Host "`n  SCRIPT PREVIEW`n  $('-' * 54)`n" -ForegroundColor Cyan
                Get-Content $LaunchScriptPath | Where-Object { $_ -notmatch '^#ENTRY:' } | ForEach-Object {
                    Write-Host "  $_" -ForegroundColor DarkGray
                }
                Write-Host "`n  Press any key..." -ForegroundColor DarkGray
                $null = [System.Console]::ReadKey($true)
            }
 
            'C' {
                if (-not (Test-Path $LaunchScriptPath)) {
                    Write-Host '  [!] Save the script first.' -ForegroundColor Red; Start-Sleep -Milliseconds 900; break
                }
                $result = Register-LaunchTask
                Write-Host ''
                if ($result -eq $true) { Write-Host "  [+] Task '$TaskName' registered." -ForegroundColor Green }
                else                   { Write-Host "  [!] Failed: $result" -ForegroundColor Red }
                Start-Sleep -Milliseconds 1100
            }
 
            'X' {
                $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
                if (-not $t) {
                    Write-Host "  [!] Task not found." -ForegroundColor Red; Start-Sleep -Milliseconds 800; break
                }
                try {
                    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
                    Write-Host "  [-] Task '$TaskName' removed." -ForegroundColor DarkYellow
                } catch { Write-Host "  [!] Failed: $_" -ForegroundColor Red }
                Start-Sleep -Milliseconds 900
            }
        }
    }
}
function Invoke-TaskCreator {
 
    $TriggerTypes = [ordered]@{
        'L' = 'At Logon'
        'S' = 'At Startup'
        'D' = 'Daily'
        'W' = 'Weekly'
    }
 
    $DayMap = [ordered]@{
        '1' = 'Monday'; '2' = 'Tuesday';  '3' = 'Wednesday'; '4' = 'Thursday'
        '5' = 'Friday'; '6' = 'Saturday'; '7' = 'Sunday'
    }
 
    $cfg = [ordered]@{
        TaskName    = $null
        Executable  = $null
        Arguments   = $null
        Trigger     = $null
        RunElevated = $true
        AtTime      = $null
        DayOfWeek   = $null
        UserScope   = 'Current'
    }
 
    function Write-MenuRow {
        param([string]$Key, [string]$Label, $Val, [switch]$Required, [switch]$Separator)
        if ($Separator) { Write-Host "  $('-' * 54)" -ForegroundColor DarkGray; return }
        $text  = if ($null -ne $Val -and $Val -ne '') { "$Val" } elseif ($Required) { '(required)' } else { '(optional)' }
        $color = if ($null -ne $Val -and $Val -ne '') { 'DarkGray' } elseif ($Required) { 'DarkRed' } else { 'DarkGray' }
        Write-Host "  [" -NoNewline -ForegroundColor DarkGray
        Write-Host $Key  -NoNewline -ForegroundColor DarkYellow
        Write-Host "] $($Label.PadRight(22)) = " -NoNewline -ForegroundColor Gray
        Write-Host $text -ForegroundColor $color
    }
 
    function Show-TaskMenu {
        Clear-Host
        Write-Host "`n  SCHEDULED TASK CREATOR" -ForegroundColor Cyan
        Write-Host "  $('=' * 54)" -ForegroundColor DarkCyan
        Write-Host ''
        Write-MenuRow -Key 'N' -Label 'Task Name'        -Val $cfg.TaskName   -Required
        Write-MenuRow -Key 'P' -Label 'Executable'       -Val $cfg.Executable -Required
        Write-MenuRow -Key 'A' -Label 'Arguments'        -Val $cfg.Arguments
        $triggerVal = if ($cfg.Trigger)    { $TriggerTypes[$cfg.Trigger]  } else { $null }
        $elevVal    = if ($cfg.RunElevated) { 'Yes' }                          else { 'No'   }
        Write-MenuRow -Key 'T' -Label 'Trigger'          -Val $triggerVal -Required
        Write-MenuRow -Key 'U' -Label 'User Scope'       -Val $cfg.UserScope
        Write-MenuRow -Key 'R' -Label 'Run Elevated'     -Val $elevVal
        if ($cfg.Trigger -in @('D','W')) { Write-MenuRow -Key 'X' -Label 'Run Time (HH:MM)' -Val $cfg.AtTime -Required }
        if ($cfg.Trigger -eq 'W') {
            $dowVal = if ($cfg.DayOfWeek) { $DayMap[$cfg.DayOfWeek] } else { $null }
            Write-MenuRow -Key 'Y' -Label 'Day of Week' -Val $dowVal -Required
        }
        Write-Host ''
 
        $allRequired = $cfg.TaskName -and $cfg.Executable -and $cfg.Trigger
        if ($cfg.Trigger -in @('D','W')) { $allRequired = $allRequired -and $cfg.AtTime }
        if ($cfg.Trigger -eq 'W')        { $allRequired = $allRequired -and $cfg.DayOfWeek }
 
        Write-MenuRow -Separator
        $regColor = if ($allRequired) { 'Green' } else { 'DarkGray' }
        Write-Host "  [" -NoNewline -ForegroundColor DarkGray
        Write-Host 'G'   -NoNewline -ForegroundColor $regColor
        Write-Host '] '  -NoNewline -ForegroundColor DarkGray
        Write-Host 'REGISTER TASK'   -ForegroundColor $regColor
        Write-Host ''
        Write-MenuRow -Separator
        Write-Host '  Press [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'E'         -NoNewline -ForegroundColor DarkYellow
        Write-Host "] to cancel.`n" -ForegroundColor DarkGray
        return $allRequired
    }
 
    while ($true) {
        $ready  = Show-TaskMenu
        $choice = (Read-Host '  ::').Trim().ToUpper()
 
        switch ($choice) {
 
            'E' { return }
 
            'N' {
                $v = (Read-Host '  Task Name').Trim()
                $cfg.TaskName = if ($v -ne '') { $v } else { $null }
            }
 
            'P' {
                $v = (Read-Host '  Executable path').Trim().Trim('"')
                if ($v -eq '') { $cfg.Executable = $null; break }
                if ([System.IO.Path]::GetExtension($v).ToLower() -notin @('.exe','.ps1','.bat','.cmd')) {
                    Write-Host '  [!] Must be .exe, .ps1, .bat, or .cmd' -ForegroundColor Red
                    Start-Sleep -Milliseconds 900; break
                }
                if (-not (Test-Path $v -PathType Leaf)) {
                    Write-Host '  [!] File not found.' -ForegroundColor Red
                    Start-Sleep -Milliseconds 900; break
                }
                $cfg.Executable = $v
            }
 
            'A' {
                $v = (Read-Host '  Arguments (blank to clear)').Trim()
                $cfg.Arguments = if ($v -ne '') { $v } else { $null }
            }
 
            'T' {
                Write-Host "`n  Select trigger:" -ForegroundColor Cyan
                $TriggerTypes.GetEnumerator() | ForEach-Object { Write-Host "    [$($_.Key)] $($_.Value)" -ForegroundColor Gray }
                $t = (Read-Host '  >').Trim().ToUpper()
                if ($TriggerTypes.Contains($t)) {
                    $cfg.Trigger = $t
                    if ($t -notin @('D','W')) { $cfg.AtTime = $null; $cfg.DayOfWeek = $null }
                    if ($t -ne 'W')           { $cfg.DayOfWeek = $null }
                } else { Write-Host '  [!] Invalid.' -ForegroundColor Red; Start-Sleep -Milliseconds 800 }
            }
 
            'U' {
                Write-Host "`n  [1] Current User`n  [2] All Users (requires elevation to register)`n" -ForegroundColor Gray
                switch ((Read-Host '  >').Trim()) {
                    '1' { $cfg.UserScope = 'Current' }
                    '2' { $cfg.UserScope = 'All' }
                    default { Write-Host '  [!] Invalid.' -ForegroundColor Red; Start-Sleep -Milliseconds 800 }
                }
            }
 
            'R' { $cfg.RunElevated = -not $cfg.RunElevated }
 
            'X' {
                $v = (Read-Host '  Run Time (HH:MM, 24hr)').Trim()
                if     ($v -match '^\d{1,2}:\d{2}$') { $cfg.AtTime = $v }
                elseif ($v -eq '')                    { $cfg.AtTime = $null }
                else   { Write-Host '  [!] Format must be HH:MM' -ForegroundColor Red; Start-Sleep -Milliseconds 800 }
            }
 
            'Y' {
                Write-Host "`n  Select day:" -ForegroundColor Cyan
                $DayMap.GetEnumerator() | ForEach-Object { Write-Host "    [$($_.Key)] $($_.Value)" -ForegroundColor Gray }
                $d = (Read-Host '  >').Trim()
                if ($DayMap.Contains($d)) { $cfg.DayOfWeek = $d }
                else { Write-Host '  [!] Invalid.' -ForegroundColor Red; Start-Sleep -Milliseconds 800 }
            }
 
            'G' {
                if (-not $ready) {
                    Write-Host '  [!] Fill required fields first.' -ForegroundColor Red
                    Start-Sleep -Milliseconds 800; continue
                }
 
                $ext = [System.IO.Path]::GetExtension($cfg.Executable).ToLower()
                if ($ext -eq '.ps1') {
                    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
                        -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($cfg.Executable)`"$(if ($cfg.Arguments) { " $($cfg.Arguments)" })"
                } else {
                    $action = New-ScheduledTaskAction -Execute $cfg.Executable -Argument (if ($cfg.Arguments) { $cfg.Arguments } else { '' })
                }
 
                $trigger = switch ($cfg.Trigger) {
                    'L' { New-ScheduledTaskTrigger -AtLogOn }
                    'S' { New-ScheduledTaskTrigger -AtStartup }
                    'D' { New-ScheduledTaskTrigger -Daily  -At ([datetime]::ParseExact($cfg.AtTime, 'H:mm', $null)) }
                    'W' { New-ScheduledTaskTrigger -Weekly -At ([datetime]::ParseExact($cfg.AtTime, 'H:mm', $null)) -DaysOfWeek $DayMap[$cfg.DayOfWeek] }
                }
 
                $runLevel  = if ($cfg.RunElevated) { 'Highest' } else { 'Limited' }
                $principal = if ($cfg.UserScope -eq 'All') {
                    New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel $runLevel
                } else {
                    New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel $runLevel
                }
 
                $settings = New-ScheduledTaskSettingsSet `
                    -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit 0 `
                    -MultipleInstances IgnoreNew
 
                try {
                    Register-ScheduledTask -TaskName $cfg.TaskName -Action $action -Trigger $trigger `
                        -Principal $principal -Settings $settings -Force -ErrorAction Stop
                    Write-Host "`n  [+] Task '$($cfg.TaskName)' registered." -ForegroundColor Green
                } catch {
                    Write-Host "`n  [!] Failed: $_" -ForegroundColor Red
                }
                Write-Host "`n  Press any key..." -ForegroundColor DarkGray
                $null = [System.Console]::ReadKey($true)
                return
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
#Send-ToastNotification -Title "Modular Menu" -Body "Thou hast opened the menu. What be thy plea?"
Show-Menu -MenuKey $script:MenuConfig.Settings.RootMenu

# CHANGELOG
# 0.0.1 - 04/12/2026 - Release
# 0.0.2 - 05/24/2026 - Improved Header formatting, improved Set-PowerPlan function
# 0.0.3 - 06/12/2026 - Improved header. Improved some functions. Added some new functions(Send-ToastNotification, Watch-LogFile, Invoke-LaunchScriptManager, Invoke-TaskCreator)/options to invoke them. Tweaked some menus.