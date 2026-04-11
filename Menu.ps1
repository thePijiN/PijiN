#Requires -Version 5.1

# =============================================================================
#  MENU FRAMEWORK - Configuration Region
#  Add, remove, or modify menus and items here. Don't touch the engine below.
# =============================================================================

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
        '__   ______  ____ ____  __  __ ____ _   _ _   _ '
        '\ \ / /  _ \|  __|  _ \|  \/  |  __| \ | | | | |'
        ' \ V /| |_) | |_ | |_) | \  / | |_ |  \| | | | |'
        '  > < |  __/|  _||  _ /| |\/| |  _|| . ` | | | |'
        ' / . \| |   | |__| |\ \| |  | | |__| |\  | |_| |'
        '/_/ \_\_|   |____|_| \_\_|  |_|____|_| \_|\___/ '
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
        Automate    = { DetectLTAgent }
        Ninja       = { DetectNinjaAgent }
        PIA         = { DetectPiaAgent }
        CrowdStrike = { DetectCrowdstrike }
		Huntress    = { DetectHuntress }
        Blackpoint  = { DetectBlackpoint }
        CloudRadial = { DetectCloudRadial }
        Ninite      = { DetectNinite }
		ImmyBot     = { DetectImmyAgent }
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
    # Line 2: Join status (built differently — needs inline color)
    # Line 3: LT ID
    # Line 4: Agents row 1
    # Line 5: Agents row 2
    # Line 6: separator (printed after the zip)

    # Helper: pad a plain string to fixed width
    function PadTo([string]$s, [int]$w) { $s.PadRight($w) }

    # Pre-build the plain-text portions we CAN measure
    $infoW = $settings.SeparatorWidth

    # --- Render: zip art + info lines ---

    # Line 0 — art line 0 + separator
    Write-Host ($art[0].PadRight($artWidth)) -NoNewline -ForegroundColor DarkCyan
    Write-Host "  $sep"                                  -ForegroundColor DarkGray

    # Line 1 — art line 1 + Host/Serial
    $hostLabel   = '  Host : '
    $serialLabel = '  S/N  : '
    Write-Host ($art[1].PadRight($artWidth)) -NoNewline -ForegroundColor DarkCyan
    Write-Host $hostLabel   -NoNewline -ForegroundColor DarkGray
    Write-Host $hostname    -NoNewline -ForegroundColor Cyan
    # pad to align serial column
    $usedAfterArt = $hostLabel.Length + $hostname.Length
    $padNeeded    = ($infoW - $usedAfterArt - $serialLabel.Length - $serial.Length)
    if ($padNeeded -lt 1) { $padNeeded = 1 }
    Write-Host (' ' * $padNeeded) -NoNewline
    Write-Host $serialLabel -NoNewline -ForegroundColor DarkGray
    Write-Host $serial               -ForegroundColor Yellow

    # Line 2 — art line 2 + Join status
    Write-Host ($art[2].PadRight($artWidth)) -NoNewline -ForegroundColor DarkCyan
    Write-Host '  Join : ' -NoNewline -ForegroundColor DarkGray
    GetJoinStatus   # writes its colored word, no newline
    Write-Host ''   # close the line

    # Line 3 — art line 3 + LT Agent ID
    $ltLabel = '  LT ID: '
    $ltVal   = "$global:AgentID"
    $ltColor = if ($global:AgentID -eq 'N/A') { 'Red' } else { 'Green' }
    Write-Host ($art[3].PadRight($artWidth)) -NoNewline -ForegroundColor DarkCyan
    Write-Host $ltLabel -NoNewline -ForegroundColor DarkGray
    Write-Host $ltVal             -ForegroundColor $ltColor

    # Line 4 — art line 4 + Agents row 1
    Write-Host ($art[4].PadRight($artWidth)) -NoNewline -ForegroundColor DarkCyan
    Write-Host '  Agents: ' -NoNewline -ForegroundColor DarkGray
    foreach ($name in $row1agents) {
        $color = if ($agentResults[$name]) { 'Green' } else { 'DarkGray' }
        Write-Host "$name " -NoNewline -ForegroundColor $color
    }
    Write-Host ''

    # Line 5 — art line 5 + Agents row 2 (indented to align under row 1)
    $agentIndent = ' ' * ('  Agents: '.Length)
    Write-Host ($art[5].PadRight($artWidth)) -NoNewline -ForegroundColor DarkCyan
    Write-Host $agentIndent -NoNewline
    foreach ($name in $row2agents) {
        $color = if ($agentResults[$name]) { 'Green' } else { 'DarkGray' }
        Write-Host "$name " -NoNewline -ForegroundColor $color
    }
    Write-Host ''

    # Closing separator
    Write-Host (' ' * $artWidth) -NoNewline
    Write-Host "  $sep" -ForegroundColor DarkGray
}
#endregion 

$script:MenuConfig = @{

    # ----- MENUS -----
    # Each menu has a Title and an Items array.
    # Each item needs: Label, and either Action (a scriptblock) or Submenu (menu key string).
    # Optional: Separator = $true renders a visual divider (no selection).

    Menus = @{

        Main = @{
            Title = 'Show-Header'
            Items = @(
                @{ Label = 'Example Tools'; Submenu = 'ExampleMenu' ; Desc = 'DescreeepshuuunnDescreeepshuuunnDescreeepshuuunn' }
                @{ Label = 'Network Tools';   Submenu = 'NetworkTools' }
                @{ Label = 'Separator';       Separator = $true }
                @{ Label = 'About';           Action = { Show-About } }
            )
        }

        ExampleMenu = @{
            Title = 'Example Tools'
            Items = @(
				@{ Label = 'Run Spacegame';     Action = { RunExternalScript -ScriptUrl 'https://raw.githubusercontent.com/thePijiN/PijiN/refs/heads/main/Spacegame.ps1' } }
                @{ Label = 'Show Uptime';       Action = { Get-Uptime-Custom } }
                @{ Label = 'Show Disk Usage';   Action = { Get-DiskUsage } }
                @{ Label = 'List Running Services'; Action = {
                    Write-Host "`nRunning Services:" -ForegroundColor Cyan
                    Get-Service | Where-Object Status -eq 'Running' | Select-Object -ExpandProperty DisplayName | Sort-Object
                    Pause-Menu
                }}
				@{ Label = 'SubMenu';   Submenu = 'Submenu' }
            )
        }

        NetworkTools = @{
            Title = 'Network Tools'
            Items = @(
                @{ Label = 'Show IP Config';    Action = { Get-IPConfig } }
                @{ Label = 'Ping a Host';       Action = { Invoke-PingPrompt } }
            )
        }
		
    }

    # ####### SETTINGS PANEL #############
    Settings = @{
        RootMenu       = 'Main'          # Which menu key to start on
        ExitKey        = 'Q'             # Key to exit/go back
        Prompt         = '::'            # Prompt label
        ItemColor      = 'Gray' # Trumped in Show-Menu
        KeyColor       = 'DarkYellow'
        SeparatorChar  = '-'
        SeparatorWidth = 50
    }#####################################
}

# region === FUNCTIONS ========================================================

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

    $TableSAS = 'https://xperlogs.table.core.windows.net/XDUlogs?sv=2019-02-02&spr=https&st=2026-01-21T18%3A49%3A49Z&se=2031-01-22T18%3A49%3A00Z&sp=rau&sig=MDZDuzmNMZIU0eeTQc1NTpIXor5fKJZeqrPe4TO4%2BAM%3D&tn=XDUlogs'

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

    # Separate launcher for CMD/BAT — no PS wrapper needed, just cmd.exe
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
        $tempFolder = "C:\xpercare\scripts"
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
                # Re-launch via wrapper instead — notify caller
                Write-Warning "-Remove for batch files uses a wrapper. Launching wrapper instead of original."
                $tempPath = $wrapperPath
            }

            Write-Host "Done." -ForegroundColor Green
            return
        }

        # ==========================================================
        # POWERSHELL — HIDDEN MODE
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
        # POWERSHELL — VISIBLE MODE
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

function Get-Uptime-Custom {
    $uptime = (Get-Date) - (gcim Win32_OperatingSystem).LastBootUpTime
    Write-Host ("`nSystem Uptime: {0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes) -ForegroundColor Green
    Pause-Menu
}
function Get-DiskUsage {
    Write-Host "`nDisk Usage:" -ForegroundColor Cyan
    Get-PSDrive -PSProvider FileSystem | Select-Object Name,
        @{N='Used (GB)';  E={ [math]::Round($_.Used  / 1GB, 2) }},
        @{N='Free (GB)';  E={ [math]::Round($_.Free  / 1GB, 2) }},
        @{N='Total (GB)'; E={ [math]::Round(($_.Used + $_.Free) / 1GB, 2) }} |
        Format-Table -AutoSize
    Pause-Menu
}
function Get-IPConfig {
    Write-Host "`nNetwork Adapters:" -ForegroundColor Cyan
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
        Select-Object InterfaceAlias, IPAddress, PrefixLength |
        Format-Table -AutoSize
    Pause-Menu
}
function Invoke-PingPrompt {
    $target = Read-Host "`nEnter hostname or IP"
    if ($target) {
        Write-Host "Pinging $target..." -ForegroundColor Yellow
        Test-Connection -ComputerName $target -Count 3
    }
    Pause-Menu
}
function Show-About {
    Write-Host "`n  Menu Framework v1.0" -ForegroundColor Cyan
    Write-Host   "  PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Pause-Menu
} 
#endregion

# region === ENGINE - Don't modify below unless you're changing framework behavior ===

function Pause-Menu {
    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Get-MenuItems {
    param([hashtable]$Menu)
    # Returns only selectable items (no separators) with assigned keys
    $key = 1
    $items = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($item in $Menu.Items) {
        if ($item.Separator) {
            $items.Add(@{ Separator = $true })
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
        foreach ($item in $items) {
            if ($item.Separator) {
                Write-Host ("  " + ($settings.SeparatorChar * ($settings.SeparatorWidth - 2))) -ForegroundColor DarkGray
            } else {
                Write-Host "  [" -NoNewline -ForegroundColor DarkGray
                Write-Host $item.Key -NoNewline -ForegroundColor $settings.KeyColor
                Write-Host "] " -NoNewline -ForegroundColor DarkGray
                $suffix = if ($item.Submenu) { " =>" } else { "" }
                if ($item.Submenu) { $settings.ItemColor = "Gray" } else { $settings.ItemColor = "DarkCyan" }
                Write-Host "$($item.Label)" -NoNewline -ForegroundColor $settings.ItemColor
                Write-Host "$suffix" -NoNewline -ForegroundColor DarkCyan
                if ($item.Desc) {
                    Write-Host "  $($item.Desc)" -NoNewline -ForegroundColor DarkGray
                }
                Write-Host ""
            }
        }

        # Back / Exit
        Write-Host $sep -ForegroundColor DarkGray
        $backLabel = if ($isRoot) { "Exit" } else { "Back" }
        Write-Host "  [" -NoNewline -ForegroundColor DarkGray
        Write-Host $settings.ExitKey -NoNewline -ForegroundColor $settings.KeyColor
        Write-Host "] " -NoNewline -ForegroundColor DarkGray
		Write-Host "$backLabel" -ForegroundColor DarkRed
        Write-Host $sep -ForegroundColor DarkGray

        # Input
        $choice = (Read-Host "`n  $($settings.Prompt)").Trim()

        # Handle exit/back
        if ($choice -eq $settings.ExitKey -or $choice -eq $settings.ExitKey.ToLower()) {
            return
        }

        # Match against selectable items
        $selected = $items | Where-Object { -not $_.Separator -and $_.Key -eq $choice }

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