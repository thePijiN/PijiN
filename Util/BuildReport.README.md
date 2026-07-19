# BuildReport

BuildReport is a client-aware Windows PC build quality-assurance report. It gathers the information normally checked before a workstation is delivered, presents it as a color-coded terminal report, and opens a compact graphical summary when Windows Forms is available.

Run it without a client name for a general inventory and health review. Supply a configured client and optional location to compare the machine against that client's build requirements. BuildReport reports what it finds; it does not install applications, remove software, change power settings, join domains, or otherwise remediate failed checks.

## Running the report

Use an elevated Windows PowerShell 5.1 session for the most complete results:

```powershell
.\BuildReport.ps1
```

Run a client compliance report:

```powershell
.\BuildReport.ps1 -Client PijiNco
```

Add a location when the selected client has location-specific requirements:

```powershell
.\BuildReport.ps1 -Client PijiNco -Location MainOffice
```

Save the terminal report to a log:

```powershell
.\BuildReport.ps1 -Client PijiNco -Location MainOffice -Log
```

Logs are written beneath:

```text
%LOCALAPPDATA%\PijiN\logs
```

Client and location names must match entries defined in the script's `$ClientConfigs` table. A location adds its requirements to the client's base requirements rather than replacing them.

## What it checks

BuildReport gathers and evaluates:

- System identity, hostname state, serial number, current user, elevation, and local administrator membership.
- Windows edition, build, activation details, CPU, GPU, and installed memory.
- Local, Active Directory, Entra, or hybrid join state and the expected client domain.
- Required management and security agents, plus software that must not be present before delivery.
- Windows Hello policy and provisioning, BitLocker status and recovery protector, and UAC level.
- Battery and AC display and sleep timeouts, time zone, and evidence that configuration tooling has run.
- Client applications, known Wi-Fi networks, mapped printers, public desktop shortcuts, and expected shortcuts.
- Browser bookmarks, Edge and Chrome extensions, and current-user default browser, PDF, and email associations.
- Available Windows updates and the appropriate manufacturer driver-update utility or script.
- Fixed and removable storage capacity, free space, active network details, user profiles, OneDrive state, and local administrators.

Without `-Client`, most client-specific requirements are shown as informational inventory. With `-Client`, configured expectations are shown as pass or fail checks. Output markers are:

- `[OK]` - requirement passed.
- `[!!]` - requirement failed or needs attention.
- `[??]` - uncertain result or manual verification recommended.
- `[~~]` - informational result without a configured requirement.

## Parameters

`-Client <name>` selects an embedded client compliance profile.

`-Location <name>` adds the selected client's location-specific Wi-Fi, printer, application, shortcut, bookmark, and extension requirements.

`-Log` saves a plain-text copy of the report under `%LOCALAPPDATA%\PijiN\logs`.

`-NoEscrow` prevents BuildReport from attempting to back up an existing BitLocker recovery protector to Entra.

## BitLocker and privacy notes

By default, an elevated run attempts BitLocker escrow only when the operating-system volume is protected, a recovery-password protector exists, and the device is Entra joined or hybrid joined. Use `-NoEscrow` when you want a strictly observational run or when escrow is handled elsewhere:

```powershell
.\BuildReport.ps1 -Client PijiNco -NoEscrow
```

The report can display sensitive information, including the Windows activation key, BitLocker recovery password, usernames, administrator membership, IP addresses, installed software, and browser configuration. Treat saved logs as confidential support records and remove them when they are no longer required.

BuildReport queries Windows Update and contacts `api.ipify.org` to determine the public IP address. If those checks are blocked or time out, the remaining report continues with an unavailable or warning result.

If the process is not elevated, BuildReport still runs but clearly warns that protected checks may be incomplete. If Windows Forms is unavailable or PowerShell is running in Constrained Language Mode, the graphical window is skipped and the complete report remains available in the terminal or log.
