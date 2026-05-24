# MACHINE_INFO.ps1 - Displays information about the current Windows configuration

# Copyright (c) 2025 PijiN
# All rights reserved.
# This script is provided under a personal, non-transferable license.
# The author reserves the right to revoke, restrict, or deny usage, reproduction, or distribution
# of this script at any time, without prior notice, to any individual or organization.
# Licensed for use solely within the scope of current professional engagement.
# Any use, reproduction, or distribution outside of that scope shall require prior, written authorization from the author.

function Test-Admin { # return true/false depending on current user local admin rights
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}
if (-not (Test-Admin)) { # If not running as admin, prompt user to re-run as admin.
	Write-Host "WARNING: " -ForegroundColor Red -NoNewLine
    Write-Host "This script requires administrative privileges to function correctly." -ForegroundColor Yellow
    $response = Read-Host "Y/N - Would you like to attempt to re-run as Admin?"
    
    if ($response -eq 'Y') { # If Y, run as admin
        Start-Process powershell.exe -ArgumentList "-File `"$PSCommandPath`"" -Verb RunAs
        exit  # Exit current session after relaunching
    } elseif ($response -eq 'N') { # If N, run anyway...
        Write-Host "Proceeding without admin rights..." -ForegroundColor Red
    }
}

# CURRENT USER INFO
function GetCurrentUserIdentity { # Shows the current user's name, in green text if Admin, red if not.
    try {
        $userName = $null
        $isAdmin = $false

        # Try interactive session via explorer.exe (usually works when explorer is tied to an actual user)
        try {
            $explorerProc = Get-Process -Name explorer -ErrorAction Stop | Select-Object -First 1
            $owner = (Get-CimInstance Win32_Process -Filter "ProcessId = $($explorerProc.Id)").GetOwner()
            if ($owner.User) {
                $userName = "$($owner.Domain)\$($owner.User)"
            }
        } catch {
            # Suppress and fall back to token owner
        }

        # Fallback to current identity if explorer method fails
        if (-not $userName) {
            $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        }

        # Admin check based on current token
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        $color = if ($isAdmin) { "Green" } else { "Red" }
        Write-Host "$userName" -ForegroundColor $color -NoNewLine
    } catch {
        Write-Host "Unknown (identity detection failed)" -ForegroundColor DarkRed -BackgroundColor White -NoNewLine
    }
}
<#function ListAllUsersWithAdminStatus { # Lists Local and Domain/Azure accounts, as well as info on each. 
    $adminGroupMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
    $currentUserFull = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $currentUserShort = $currentUserFull.Split('\')[-1]

    $localUsers = Get-LocalUser
    $defaultAccounts = @('DefaultAccount', 'Guest', 'WDAGUtilityAccount', 'Administrator', 'WsiAccount') # Default users to omit, unless they are enabled.

    # Build set of local usernames (short names)
    $localUsernames = $localUsers.Name

    Write-Host "~~~" -NoNewline
    Write-Host "Local Users" -ForegroundColor Green -BackgroundColor DarkGray -NoNewline
    Write-Host "~~~"

    foreach ($user in $localUsers) {
        $username = $user.Name
        $isEnabled = $user.Enabled
        $isCurrent = $username -eq $currentUserShort
        $isAdmin = $false

        foreach ($admin in $adminGroupMembers) {
            $adminNameShort = $admin.Name.Split('\')[-1]
            if ($adminNameShort -eq $username) {
                $isAdmin = $true
                break
            }
        }

        if (-not $isEnabled -and ($defaultAccounts -contains $username)) {
            continue
        }

        if ($isCurrent) {
            Write-Host "* " -NoNewline -ForegroundColor Cyan
        } else {
            Write-Host "- " -NoNewline -ForegroundColor Gray
        }

        Write-Host "$username " -NoNewline -ForegroundColor White

        if ($isAdmin) {
            Write-Host "(Admin) " -NoNewline -ForegroundColor Green
        } else {
            Write-Host "(Not Admin) " -NoNewline -ForegroundColor Red
        }

        if ($isEnabled) {
            Write-Host "(ENABLED) " -NoNewline -ForegroundColor Green
        } else {
            Write-Host "(DISABLED) " -NoNewline -ForegroundColor Red
        }

        if ($defaultAccounts -contains $username) {
            Write-Host "(Default Account)" -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }
    }

    # Properly filter out only the non-local admin entries
    $nonLocalAdmins = $adminGroupMembers | Where-Object {
        $adminShortName = $_.Name.Split('\')[-1]
        return -not ($localUsernames -contains $adminShortName)
    }

    if ($nonLocalAdmins.Count -gt 0) {
        Write-Host "~~~" -NoNewline
        Write-Host "Azure AD / Domain Accounts in Administrators Group" -ForegroundColor Cyan -BackgroundColor DarkGray -NoNewline
        Write-Host "~~~"

        foreach ($member in $nonLocalAdmins) {
            $isCurrent = ($member.Name -eq $currentUserFull)

            if ($isCurrent) {
                Write-Host "* " -NoNewline -ForegroundColor Cyan
            } else {
                Write-Host "- " -NoNewline -ForegroundColor Gray
            }

            Write-Host "$($member.Name) " -NoNewline -ForegroundColor White
            Write-Host "(Admin) (AAD/Domain Account)" -ForegroundColor Green
        }
    }
}
#>
function Show-UserProfiles { # Lists all users in C:\users, classified by type, with additional info. 
    $excludedSystemProfiles = @('Public','Default','Default User','All Users','WDAGUtilityAccount')
    $excludedLocalAccounts  = @('Administrator','Guest','DefaultAccount','WDAGUtilityAccount')

    $adminMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
    $adminSIDs = $adminMembers.SID.Value
    $adminNames = $adminMembers.Name

    $localUsers = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin $excludedLocalAccounts
    }

    $localUserMap = @{}
    foreach ($user in $localUsers) {
        $localUserMap[$user.Name] = @{
            IsAdmin = $adminSIDs -contains $user.SID.Value
            Enabled = $user.Enabled
        }
    }

    $currentUser = $env:USERNAME
    $profiles = Get-ChildItem "C:\Users" -Directory | Where-Object {
		$_.Name -notin $excludedSystemProfiles -and
		(Test-Path (Join-Path $_.FullName "Downloads"))
	}

    $localOutput  = @()
    $domainOutput = @()
    $azureOutput  = @()
    $seenAccounts = @()

    foreach ($profile in $profiles) {
        $name = $profile.Name
        $isCurrent = $name -ieq $currentUser
        $prefix = if ($isCurrent) { "* " } else { "- " }

        if ($localUserMap.ContainsKey($name)) {
            $entry = @{
                Prefix = $prefix
                Name   = $name
                Admin  = $localUserMap[$name].IsAdmin
                Enabled = $localUserMap[$name].Enabled
                Current = $isCurrent
            }
            $localOutput += $entry
            $seenAccounts += $name
        }
        elseif ($name -match '\\' -or $name -match '^[\w-]+\.[\w-]+$') {
            $sid = try {
                (New-Object System.Security.Principal.NTAccount($name)).Translate([System.Security.Principal.SecurityIdentifier]).Value
            } catch { $null }

            $domainOutput += @{
                Prefix = $prefix
                Name   = $name
                Admin  = $sid -and ($adminSIDs -contains $sid)
                Current = $isCurrent
            }
            $seenAccounts += $name
        }
        else {
            $sid = try {
                (New-Object System.Security.Principal.NTAccount("AzureAD\$name")).Translate([System.Security.Principal.SecurityIdentifier]).Value
            } catch { $null }

            $azureOutput += @{
                Prefix = $prefix
                Name   = $name
                Admin  = $sid -and ($adminSIDs -contains $sid)
                Current = $isCurrent
            }
            $seenAccounts += $name
        }
    }

    if ($localOutput.Count -gt 0) {
        Write-Host "~~~" -NoNewLine
        Write-Host "Local Users" -NoNewLine -ForegroundColor Green
        Write-Host "~~~"
        foreach ($user in $localOutput) {
            if ($user.Current) {
                Write-Host "$($user.Prefix)" -ForegroundColor Cyan -NoNewline
				Write-Host "$($user.Name)" -NoNewLine
            } else {
                Write-Host "$($user.Prefix)$($user.Name)" -NoNewline
            }

            if (-not $user.Enabled) {
                Write-Host " (DISABLED)" -ForegroundColor Red
            } elseif ($user.Admin) {
                Write-Host " (" -NoNewline
                Write-Host "Admin" -ForegroundColor Green -NoNewline
                Write-Host ")"
            } else {
                Write-Host ""
            }
        }
    }

    if ($domainOutput.Count -gt 0) {
        Write-Host "~~~" -NoNewLine
        Write-Host "Domain Users" -NoNewLine -ForegroundColor Yellow
        Write-Host "~~~"
        foreach ($user in $domainOutput) {
            if ($user.Current) {
                Write-Host "$($user.Prefix)$($user.Name)" -ForegroundColor Cyan -NoNewline
            } else {
                Write-Host "$($user.Prefix)$($user.Name)" -NoNewline
            }

            if ($user.Admin) {
                Write-Host " (" -NoNewline
                Write-Host "Admin" -ForegroundColor Green -NoNewline
                Write-Host ")"
            } else {
                Write-Host ""
            }
        }
    }

    if ($azureOutput.Count -gt 0) {
        Write-Host "~~~" -NoNewLine
        Write-Host "Azure/Entra Users" -NoNewLine -ForegroundColor Cyan
        Write-Host "~~~"
        foreach ($user in $azureOutput) {
            if ($user.Current) {
                Write-Host "$($user.Prefix)$($user.Name)" -ForegroundColor Cyan -NoNewline
            } else {
                Write-Host "$($user.Prefix)$($user.Name)" -NoNewline
            }

            if ($user.Admin) {
                Write-Host " (" -NoNewline
                Write-Host "Admin" -ForegroundColor Green -NoNewline
                Write-Host ")"
            } else {
                Write-Host ""
            }
        }
    }

    # Show Admins injected by policy
    $policyAdmins = @()
    foreach ($admin in $adminMembers) {
        if (
            $admin.ObjectClass -ne 'User' -or
            ($admin.Name -notmatch '^.+\\.+$') -or
            ($admin.Name -in $seenAccounts)
        ) { continue }

        if ($admin.Name -notin $seenAccounts) {
            $policyAdmins += $admin.Name
        }
    }

    if ($policyAdmins.Count -gt 0) {
        Write-Host "~~~" -NoNewLine
        Write-Host "Admins by Policy" -NoNewLine -ForegroundColor Magenta
        Write-Host "~~~"
        foreach ($name in $policyAdmins) {
            Write-Host "- $name"
        }
    }
}
# HARDWARE INFO
function GetDeviceName { # $global:DeviceName
    $global:DeviceName = $env:COMPUTERNAME
    Write-Host "$($global:DeviceName)" -ForegroundColor Yellow -NoNewline
}
function GetSerialNumber { # $global:serialNumber
    $global:serialNumber = "Not Found"

    try {
        $serial = (Get-WmiObject Win32_BIOS).SerialNumber
        if ($serial) {
            $global:serialNumber = $serial.Trim()
        }
    } catch {
        $global:serialNumber = "Not Found"
    }

    if ($global:serialNumber -ne "Not Found") {
        Write-Host "$($global:serialNumber)" -ForegroundColor Yellow -NoNewline
    } else {
        Write-Host "Not Found" -ForegroundColor Red -NoNewline
    }
}
function GetStorageInfo { # Displays storage drives, and their free space in GB.
    Get-PSDrive -PSProvider 'FileSystem' | ForEach-Object {
        $drive = $_
        $freeGB = [math]::Round($drive.Free / 1GB, 0)

        # Determine color for free space
        if ($freeGB -lt 50) {
            $color = 'Red'
        } elseif ($freeGB -lt 100) {
            $color = 'Yellow'
        } else {
            $color = 'Green'
        }

        Write-Host "$($drive.Name):\" -ForegroundColor Cyan -NoNewline
        Write-Host " - " -ForegroundColor White -NoNewline
        Write-Host "$freeGB" -ForegroundColor $color -NoNewline
        Write-Host "GB Free"
    }
}
# NETWORK INFO
function GetNetworkType { # $global:NetworkType
    $global:NetworkType = "Unknown"
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and !$_.Virtual } | Select-Object -First 1

    if ($adapter) {
        if ($adapter.Name -match "Wi-Fi|Wireless") {
            $global:NetworkType = "WiFi"
            Write-Host "WiFi" -ForegroundColor Cyan -NoNewline
        } elseif ($adapter.Name -match "Ethernet") {
            $global:NetworkType = "Ethernet"
            Write-Host "Ethernet" -ForegroundColor Green -NoNewline
        } else {
            $global:NetworkType = $adapter.Name
            Write-Host "$($adapter.Name)" -ForegroundColor Yellow -NoNewline
        }
    } else {
        $global:NetworkType = "No Internet"
        Write-Host "No Internet" -ForegroundColor Red -NoNewline
    }
}
function GetDomainStatus { # Writes Domain Join Status ($global:DomainStatus), and Domain Name. 
    $global:DomainStatus = ""
    $dsregOutput = dsregcmd /status

    # Extract the values for AzureAdJoined and DomainJoined
    $azureAdJoined = ($dsregOutput | Select-String "AzureAdJoined\s*:\s*(\w+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -eq 'YES'
    $domainJoined  = ($dsregOutput | Select-String "DomainJoined\s*:\s*(\w+)"   | ForEach-Object { $_.Matches[0].Groups[1].Value }) -eq 'YES'

    # Local domain name (if any)
    $localDomain = (Get-WmiObject -Class Win32_ComputerSystem).Domain
    $entraDomain = ""

    # Only attempt to parse Entra domain if AzureAD joined
    if ($azureAdJoined) {
        $aadInfo = $dsregOutput | Select-String "TenantName"
        if ($aadInfo) {
            $entraDomain = ($aadInfo.ToString() -replace 'TenantName\s*:\s*', '').Trim()
        }
    }

    # Determine the domain status
    if ($azureAdJoined -and $domainJoined) {
        $global:DomainStatus = "Hybrid"
        Write-Host "Hybrid: $localDomain/$entraDomain" -ForegroundColor Yellow -NoNewline
    }
    elseif ($azureAdJoined) {
        $global:DomainStatus = "Entra"
        Write-Host "Entra: $entraDomain" -ForegroundColor Cyan -NoNewline
    }
    elseif ($domainJoined) {
        $global:DomainStatus = "Local"
        Write-Host "Local: $localDomain" -ForegroundColor Green -NoNewline
    }
    else {
        $global:DomainStatus = "None"
        Write-Host "None" -ForegroundColor Red -NoNewline
    }
}
function GetHardwareMAC { # Writes Hardware MAC Address ($global:HardwareMAC)
    $MAC = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and !$_.Virtual } | Select-Object -ExpandProperty MacAddress
    if ($MAC) {
        $global:HardwareMAC = $MAC
        Write-Host "$MAC" -ForegroundColor Green  -NoNewline
    } else {
        $global:HardwareMAC = "Not Found"
        Write-Host "Not Found" -ForegroundColor Red  -NoNewline
    }
}
function GetIPv4AddressInt { # Writes IPv4 address for first adapter w Internet access.
    # Get the interface index for the default route (0.0.0.0/0)
    $interfaces = Get-NetIPConfiguration |
        Where-Object {
            $_.IPv4DefaultGateway -ne $null -and
            $_.NetAdapter.Status -eq 'Up' -and
            $_.IPv4Address.IPAddress -notlike '169.254.*'
        }

    if ($interfaces.Count -eq 0) {
        Write-Host "No valid IPv4 address found for active interface" -ForegroundColor Red -NoNewline
        return
    }

    # Prefer Ethernet over Wi-Fi if both are valid
    $preferred = $interfaces | Sort-Object {
        if ($_.NetAdapter.InterfaceDescription -match "Ethernet") { 0 }
        elseif ($_.NetAdapter.InterfaceDescription -match "Wi-Fi|Wireless") { 1 }
        else { 2 }
    }

    $ipAddress = $preferred[0].IPv4Address.IPAddress

    if ($ipAddress) {
        Write-Host "$ipAddress" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "No valid IPv4 address found" -ForegroundColor Red -NoNewline
    }
}
function GetIPv4AddressExt {
	try {
        $ipExt = Invoke-RestMethod -Uri "https://api.ipify.org"
        Write-Host "$ipExt" -ForegroundColor Green -NoNewLine
    } catch {
        Write-Host "Unable to retrieve external IP." -ForegroundColor Red
    }
}
function Show-KnownWiFiNetworks { # Displays known WiFi connections. Specifies whether machine-wide or user-specific
    # Retrieve all profile lines
    $allProfilesOutput = netsh wlan show profiles

    # Parse system-wide profiles
    $systemProfiles = ($allProfilesOutput | Select-String "All User Profile") | ForEach-Object {
        if ($_ -match ":\s*(.+)$") { $matches[1].Trim() }
    }

    if ($systemProfiles.Count -gt 0) {
        Write-Host "~~~" -NoNewLine
		Write-Host "System-Wide" -NoNewLine -ForegroundColor green
		Write-Host "~~~"
        foreach ($profile in $systemProfiles) {
            Write-Host "- $profile"
        }
    } else {
        Write-Host "No system-wide profiles found."
    }

    # Parse user-specific profiles
    $userProfiles = ($allProfilesOutput | Select-String "User Profile") | ForEach-Object {
        if ($_ -match ":\s*(.+)$") { $matches[1].Trim() }
    }

    # Filter out system-wide entries to get user-only
    $userOnlyProfiles = $userProfiles | Where-Object { $systemProfiles -notcontains $_ }

    if ($userOnlyProfiles.Count -gt 0) {
		Write-Host "~~~" -NoNewLine
		Write-Host "User-Specific (Current User)" -NoNewLine -ForegroundColor cyan
		Write-Host "~~~"
        foreach ($profile in $userOnlyProfiles) {
            Write-Host "- $profile"
        }
    }
}
# SOFTWARE INFO
function GetWindowsVersion { # $global:WindowsVersion, contains OS Name, feature update version, and build number
    try {
        $winRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $props = Get-ItemProperty -Path $winRegPath

        $productName = $props.ProductName
        $releaseId = $props.ReleaseId
        $displayVersion = $props.DisplayVersion
        $currentBuild = [int]$props.CurrentBuild
        $ubr = $props.UBR  # Update Build Revision

        $osBuild = "$currentBuild.$ubr"

        # Determine proper base OS name based on build number
        $osName =
            if ($currentBuild -ge 22000) {  # Windows 11 starts at build 22000
                $productName -replace "Windows 10", "Windows 11"
            } else {
                $productName
            }

        # Choose either DisplayVersion or ReleaseId for feature update info
        $featureUpdate = if ($displayVersion) { $displayVersion } elseif ($releaseId) { $releaseId } else { "Unknown" }

        $global:WindowsVersion = "$osName - $featureUpdate - Build $osBuild"

        Write-Host $global:WindowsVersion -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        Write-Host "" -NoNewLine
    } catch {
        $global:WindowsVersion = "Not Found"
        Write-Host "Not Found" -ForegroundColor Red -NoNewline
    }
}
function GetWindowsActivationKey{ # Grabs your current Windows Activation key
	# Retrieve the Windows activation key
	$windowsKey = Get-WmiObject -Query "SELECT OA3xOriginalProductKey FROM SoftwareLicensingService" | Select-Object -ExpandProperty OA3xOriginalProductKey

	# Output the key
	Write-Host "$windowsKey" -ForegroundColor Yellow -NoNewLine
}
function GetLTAgentID { # $global:LTAgentID
    $global:LTAgentID = "Not Found"
    $LTErrorsPath = "C:\Windows\LTSvC\LTErrors.txt"
    $isInstalled = Test-Path $LTErrorsPath

    try {
        $LTagent = Get-ItemProperty -Path "HKLM:\SOFTWARE\LabTech\Service" -Name "ID" -ErrorAction Stop
        if ($LTagent.ID) {
            $global:LTAgentID = $LTagent.ID
        }
    } catch {
        # Silent fail
    }

    # Output with status-aware coloring
    $color = if ($isInstalled) { "Green" } else { "Red" }
    Write-Host $global:LTAgentID -ForegroundColor $color -NoNewline
}
function GetBitlockerRecovery { # Write-Hosts ID and Key for latest Bitlocker 
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

    # Use the last key, which is usually the valid one
    $latestKey = $recoveryKeys[-1]

    $bitlockerID = $latestKey.KeyProtectorId
    $bitlockerRecoveryKey = $latestKey.RecoveryPassword

    Write-Host "Identifier: " -NoNewLine
    Write-Host "$bitlockerID" -ForegroundColor Yellow
    Write-Host "Recovery Key: " -NoNewLine
    Write-Host "$bitlockerRecoveryKey" -ForegroundColor Green

    <# Optional: return as object
    return [PSCustomObject]@{
        Identifier    = $bitlockerID
        RecoveryKey   = $bitlockerRecoveryKey
        Status        = "Enabled"
    }
    #>
}
function GetCrowdstrikeInstallStatus { # Says "Detected" or "Not Found" based on Crowdstrike path existance.
    $exists = Test-Path "C:\Program Files\CrowdStrike"
    if ($exists) {
        Write-Host "Detected" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "Not Found" -ForegroundColor Red -NoNewline
    }
}
function GetCloudRadialInstallStatus { # Says "Detected" or "Not Found" based on CloudRadial executable existance.
    $exists = Test-Path "C:\Program Files (x86)\CloudRadial Agent\CloudRadial.Agent.exe"
    if ($exists) {
        Write-Host "Detected" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "Not Found" -ForegroundColor Red -NoNewline
    }
}
function Show-MappedPrinters { # Displays mapped printers. Specifies whether machine-wide or user-specific 
    # Get all installed printers and check for Microsoft Print to PDF
    $printers = Get-Printer -ErrorAction SilentlyContinue
    $hasPdfPrinter = $printers.Name -contains "Microsoft Print to PDF"
    $filteredPrinters = $printers | Where-Object { $_.Name -ne "Microsoft Print to PDF" }

    # Display system-wide printers
    if ($filteredPrinters) {
        Write-Host "~~~" -NoNewLine
		Write-Host "System-Wide" -NoNewLine -ForegroundColor green
		Write-Host "~~~"
        foreach ($printer in $filteredPrinters) {
            Write-Host "- $($printer.Name)"
        }
    } else {
        Write-Host "No non-PDF printers found."
    }

    # Display user-mapped printers
    try {
        $userPrinters = Get-ChildItem -Path "HKCU:\Printers\Connections" -ErrorAction Stop |
            ForEach-Object {
                ($_.Name -split "\\")[-1] -replace ",", "\"
            }

        if ($userPrinters.Count -gt 0) {
            Write-Host "~~~" -NoNewLine
		Write-Host "User-Specific (current user)" -NoNewLine -ForegroundColor cyan
		Write-Host "~~~"
            foreach ($printer in $userPrinters) {
                Write-Host "- $printer"
            }
        }
    } catch {
        # No user-mapped printers
    }

    if (-not $hasPdfPrinter) {
        Write-Host "`nWARNING: 'Microsoft Print to PDF' is missing from this system!" -ForegroundColor Red
    }
}

# DISPLAY INFO
function ShowExitSpinner { # Exit spinner - animation; continues on keystroke
    $spinnerChars = @('|', '/', '-', '\')
    $spinnerIndex = 0
    $promptBase = "Press any key to exit"
    $startLeft = [Console]::CursorLeft
    $startTop = [Console]::CursorTop

    [Console]::CursorVisible = $false
    try {
        while (-not [Console]::KeyAvailable) {
            $spinnerChar = $spinnerChars[$spinnerIndex]
            $fullText = "$spinnerChar $promptBase $spinnerChar"

            [Console]::SetCursorPosition($startLeft, $startTop)
            Write-Host $fullText -NoNewline

            Start-Sleep -Milliseconds 150
            $spinnerIndex = ($spinnerIndex + 1) % $spinnerChars.Length
        }

        # Clear spinner line after key press
        [Console]::SetCursorPosition($startLeft, $startTop)
        Write-Host (' ' * ($promptBase.Length + 4)) -NoNewline  # +4 for spinner chars + spaces
        [Console]::SetCursorPosition($startLeft, $startTop)
        [Console]::ReadKey($true) | Out-Null
    } finally {
        [Console]::CursorVisible = $true
    }
}
function ShowSystemSummary { # Displays system information to user
    Clear-Host
    Write-Host "==== System Info ====" -ForegroundColor White -BackgroundColor DarkBlue

    # General Info
    Write-Host (" GENERAL     ") -BackgroundColor DarkGray -ForegroundColor Cyan -NoNewline
    Write-Host (" Device Name: ") -NoNewline
    GetDeviceName
    Write-Host (" | S/N: ") -NoNewline
    GetSerialNumber
	Write-Host (" | Ran as: ") -NoNewline
    GetCurrentUserIdentity
	# General Info - line 2
	Write-Host "`n             " -BackgroundColor DarkGray -ForegroundColor Cyan -NoNewline
    Write-Host (" OS: ") -NoNewline
    GetWindowsVersion
    Write-Host " | Activation: " -NoNewLine
	GetWindowsActivationKey
	Write-Host ""

    # Network Info
    Write-Host (" NETWORK     ") -BackgroundColor DarkGray -ForegroundColor Cyan -NoNewline
    Write-Host (" MAC Address: ") -NoNewline
    GetHardwareMAC
    Write-Host (" | IPv4 - Int: ") -NoNewline
    GetIPv4AddressInt
	Write-Host (", Ext: ") -NoNewLine 
	GetIPv4AddressExt
	# Network Info - line 2
	Write-Host "`n             " -BackgroundColor DarkGray -ForegroundColor Cyan -NoNewline
    Write-Host (" Domain: ") -NoNewline
    GetDomainStatus
    Write-Host (" | Connection: ") -NoNewline
    GetNetworkType
    Write-Host ""

    # Software Info
    Write-Host (" SOFTWARE    ") -BackgroundColor DarkGray -ForegroundColor Cyan -NoNewline
    Write-Host (" LTAgent ID: ") -NoNewline
    GetLTAgentID
    Write-Host (" | Crowdstrike: ") -NoNewline
    GetCrowdstrikeInstallStatus
    Write-Host (" | CloudRadial: ") -NoNewline
    GetCloudRadialInstallStatus
    Write-Host ""

    # Storage
    Write-Host "`n==== Storage ====" -ForegroundColor White -BackgroundColor DarkBlue
    GetStorageInfo

    # Bitlocker
    Write-Host "`n==== BitLocker ====" -ForegroundColor White -BackgroundColor DarkBlue
    GetBitlockerRecovery

    # Users
	Write-Host "`n==== Users ====" -ForegroundColor White -BackgroundColor DarkBlue
    Show-UserProfiles
	# Legend
	Write-Host "(`"" -NoNewLine; Write-Host "*" -ForegroundColor Cyan -NoNewline; Write-host "`" = `"You`")"
	
	# WiFi profiles
	Write-Host "`n==== Wi-Fi Networks ====" -ForegroundColor White -BackgroundColor DarkBlue
	Show-KnownWiFiNetworks
	
	# Printers
	Write-Host "`n==== Printers ====" -ForegroundColor White -BackgroundColor DarkBlue
	Show-MappedPrinters

    # Exit
    Write-Host ""
    ShowExitSpinner
}

ShowSystemSummary

#CHANGELOG
# 0.0.0 - 5/3/25 - Created.
# 0.0.1 - 5/4/25 - Added TestAdmin and if statement to beginning to prompt user to re-run as admin, if not already done. Revised GetIPv4AddressInt function to grab IPv4 specifically for the first adapter w Internet access. Added GetStorageInfo function. Added ShowExitSpinner function. Re-worked ShowSystemSummary function output. Various formatting tweaks.
# 0.0.2 - 5/6/25 - Updated GetWindowsVersion function to now check build, and if above 22000 report "11" instead of "10". Updated GetLTAgentID function so color is based off a .txt file indicative of installation, to portray when installed but no ID. Added GetCurrentUserIdentity function to display who ran script, with color to indicate admin. Added GetWindowsActivationKey function to display current Windows Activation Key. Revised ShowSystemSummary function's output to better accomodate smaller screens and additional information. Revised opening if statement when running as non-admin. Added comments, improved formatting.
# 0.0.3 - 6/6/25 - Replaced ListAllUsersWithAdminStatus function with Show-UserProfiles function. Added Show-UserProfiles, Show-KnownWiFiNetworks, and Show-MappedPrinters functions to report additional information.
# 0.0.4 - 6/9/25 - Revised GetIPv4AddressInt function to be more robust/accurate.
# 0.0.5 - 6/9/25 - Added function GetIPv4AddressExt and renamed GetIPv4Address to GetIPv4AddressInt.
