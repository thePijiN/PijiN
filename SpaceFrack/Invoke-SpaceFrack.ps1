#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(DontShow = $true)]
    [switch]$LauncherElevated,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-WindowsCommandLineArgument {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        $Value = ''
    }

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $Builder = New-Object System.Text.StringBuilder
    [void]$Builder.Append('"')
    $BackslashCount = 0

    foreach ($Character in $Value.ToCharArray()) {
        if ($Character -eq '\') {
            $BackslashCount++
            continue
        }

        if ($Character -eq '"') {
            [void]$Builder.Append(('\' * (($BackslashCount * 2) + 1)))
            [void]$Builder.Append('"')
            $BackslashCount = 0
            continue
        }

        if ($BackslashCount -gt 0) {
            [void]$Builder.Append(('\' * $BackslashCount))
            $BackslashCount = 0
        }

        [void]$Builder.Append($Character)
    }

    if ($BackslashCount -gt 0) {
        [void]$Builder.Append(('\' * ($BackslashCount * 2)))
    }

    [void]$Builder.Append('"')
    return $Builder.ToString()
}

# Per-launcher settings. These are the only values to change when cloning it.
$LauncherName = 'SpaceFrack'
$ScriptUri = 'https://raw.githubusercontent.com/thePijiN/PijiN/refs/heads/main/SpaceFrack/SpaceFrack.ps1'
$RequireAdministrator = $false
$SuppressTerminal = $true

$scriptUriObject = New-Object System.Uri -ArgumentList $ScriptUri
if (-not $scriptUriObject.IsAbsoluteUri -or $scriptUriObject.Scheme -ne 'https') {
    throw 'ScriptUri must be an absolute HTTPS URL.'
}

$CachedScriptFileName = [System.IO.Path]::GetFileName($scriptUriObject.AbsolutePath)
if ([string]::IsNullOrWhiteSpace($CachedScriptFileName) -or
    [System.IO.Path]::GetExtension($CachedScriptFileName) -ine '.ps1') {
    throw 'ScriptUri must identify a .ps1 file.'
}

if ([string]::IsNullOrWhiteSpace($LauncherName)) {
    $LauncherName = [System.IO.Path]::GetFileNameWithoutExtension($CachedScriptFileName)
}

$ScriptDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'PijiN'
$ScriptPath = Join-Path -Path $ScriptDirectory -ChildPath $CachedScriptFileName
$DownloadPath = Join-Path -Path $ScriptDirectory -ChildPath ($CachedScriptFileName + '.download')
$BackupPath = Join-Path -Path $ScriptDirectory -ChildPath ($CachedScriptFileName + '.previous')
$ExitCode = 1
$script:CachedScriptError = $null
$script:ElevationError = $null

function Test-LauncherAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsTerminalPath {
    $terminalCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($null -eq $terminalCommand) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($terminalCommand.Source)) {
        return $null
    }

    return $terminalCommand.Source
}

function Test-CurrentWindowsTerminalSession {
    return -not [string]::IsNullOrWhiteSpace($env:WT_SESSION)
}

function Test-ElevationWasCanceled {
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )

    $currentException = $Exception
    while ($null -ne $currentException) {
        if ($currentException -is [System.ComponentModel.Win32Exception] -and
            $currentException.NativeErrorCode -eq 1223) {
            return $true
        }

        if ($currentException.HResult -eq -2147023673) {
            return $true
        }

        $currentException = $currentException.InnerException
    }

    return $false
}

function Assert-ValidPowerShellScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Script file was not found at $Path."
    }

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -eq 0) {
        throw 'The script file is empty.'
    }

    $scriptText = [System.IO.File]::ReadAllText($Path)
    if ($scriptText -match '^\s*<(?:!doctype|html)') {
        throw 'The file contains HTML instead of a PowerShell script.'
    }

    $parseTokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$parseTokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -gt 0) {
        throw ('The script has {0} PowerShell syntax error(s).' -f $parseErrors.Count)
    }
}

function Test-CachedPowerShellScript {
    try {
        Assert-ValidPowerShellScript -Path $ScriptPath
        $script:CachedScriptError = $null
        return $true
    }
    catch {
        $script:CachedScriptError = $_.Exception.Message
        return $false
    }
}

function Show-LauncherError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($SuppressTerminal) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            [System.Windows.Forms.MessageBox]::Show(
                $Message,
                $LauncherName,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }
        catch {
        }
    }

    Write-Host $Message -ForegroundColor Red
}

function Invoke-LocalPowerShellScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$Arguments = @()
    )

    $powerShellPath = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
        throw "Windows PowerShell was not found at $powerShellPath."
    }

    $powerShellArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $Path
    ) + @($Arguments)

    $argumentString = (($powerShellArguments | ForEach-Object {
        ConvertTo-WindowsCommandLineArgument -Value $_
    }) -join ' ')

    $terminalPath = Get-WindowsTerminalPath
    if (-not $SuppressTerminal -and
        -not (Test-CurrentWindowsTerminalSession) -and
        $null -ne $terminalPath) {
        $terminalArguments = @(
            'new-tab'
            '--title'
            $LauncherName
            '--startingDirectory'
            ([Environment]::CurrentDirectory)
            $powerShellPath
        ) + $powerShellArguments

        $terminalArgumentString = (($terminalArguments | ForEach-Object {
            ConvertTo-WindowsCommandLineArgument -Value $_
        }) -join ' ')

        try {
            Start-Process -FilePath $terminalPath `
                -ArgumentList $terminalArgumentString `
                -ErrorAction Stop | Out-Null

            return 0
        }
        catch {
            Write-Host ("Windows Terminal could not be started: $($_.Exception.Message)") -ForegroundColor Yellow
            Write-Host 'Falling back to classic Windows PowerShell.' -ForegroundColor Yellow
        }
    }

    $startParameters = @{
        FilePath = $powerShellPath
        ArgumentList = $argumentString
        Wait = $true
        PassThru = $true
        ErrorAction = 'Stop'
    }
    if ($SuppressTerminal) {
        $startParameters.WindowStyle = 'Hidden'
    }
    else {
        $startParameters.NoNewWindow = $true
    }

    $process = Start-Process @startParameters

    return $process.ExitCode
}

function Start-ElevatedLauncher {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LauncherPath,

        [string[]]$Arguments = @()
    )

    if ([string]::IsNullOrWhiteSpace($LauncherPath) -or
        -not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
        $script:ElevationError = 'The launcher path could not be resolved for elevation.'
        return $false
    }

    $powerShellPath = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
        $script:ElevationError = "Windows PowerShell was not found at $powerShellPath."
        return $false
    }

    $relaunchArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $LauncherPath
        '-LauncherElevated'
    ) + @($Arguments)

    $terminalPath = Get-WindowsTerminalPath
    if (-not $SuppressTerminal -and $null -ne $terminalPath) {
        $terminalArguments = @(
            'new-tab'
            '--title'
            ($LauncherName + ' (Administrator)')
            '--startingDirectory'
            ([Environment]::CurrentDirectory)
            $powerShellPath
        ) + $relaunchArguments

        $terminalArgumentString = (($terminalArguments | ForEach-Object {
            ConvertTo-WindowsCommandLineArgument -Value $_
        }) -join ' ')

        try {
            Start-Process -FilePath $terminalPath `
                -ArgumentList $terminalArgumentString `
                -Verb RunAs `
                -ErrorAction Stop | Out-Null

            return $true
        }
        catch {
            if (Test-ElevationWasCanceled -Exception $_.Exception) {
                $script:ElevationError = $_.Exception.Message
                return $false
            }

            Write-Host ("Elevated Windows Terminal could not be started: $($_.Exception.Message)") -ForegroundColor Yellow
            Write-Host 'Falling back to elevated classic Windows PowerShell.' -ForegroundColor Yellow
        }
    }

    $argumentString = (($relaunchArguments | ForEach-Object {
        ConvertTo-WindowsCommandLineArgument -Value $_
    }) -join ' ')

    try {
        $startParameters = @{
            FilePath = $powerShellPath
            ArgumentList = $argumentString
            Verb = 'RunAs'
            ErrorAction = 'Stop'
        }
        if ($SuppressTerminal) {
            $startParameters.WindowStyle = 'Hidden'
        }

        Start-Process @startParameters | Out-Null

        return $true
    }
    catch {
        $script:ElevationError = $_.Exception.Message
        return $false
    }
}

function Invoke-CachedScriptFallback {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [switch]$Automatic
    )

    if (-not $SuppressTerminal) {
        Write-Host $Reason -ForegroundColor Red
    }

    if (-not (Test-CachedPowerShellScript)) {
        Show-LauncherError -Message ($Reason + [Environment]::NewLine + [Environment]::NewLine + "No valid cached script is available: $script:CachedScriptError")
        return 1
    }

    if ($Automatic) {
        if (-not $SuppressTerminal) {
            Write-Host 'Running the validated cached script instead.' -ForegroundColor Yellow
            Write-Host ("Cached script: $ScriptPath") -ForegroundColor Cyan
        }

        try {
            return Invoke-LocalPowerShellScript -Path $ScriptPath -Arguments $ScriptArguments
        }
        catch {
            Show-LauncherError -Message ("The cached script could not be started: $($_.Exception.Message)")
            return 1
        }
    }

    if (-not $SuppressTerminal) {
        Write-Host ("Cached script: $ScriptPath") -ForegroundColor Cyan
    }
    if ($RequireAdministrator -and -not (Test-LauncherAdministrator)) {
        if (-not $SuppressTerminal) {
            Write-Host 'The cached script will run without administrator rights and some actions may fail.' -ForegroundColor Yellow
        }
    }

    if ($SuppressTerminal) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $message = $Reason + [Environment]::NewLine + [Environment]::NewLine +
                'Run the validated cached script instead?'
            $choice = [System.Windows.Forms.MessageBox]::Show(
                $message,
                $LauncherName,
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
                return 1
            }

            return Invoke-LocalPowerShellScript -Path $ScriptPath -Arguments $ScriptArguments
        }
        catch {
            Show-LauncherError -Message ("The cached script could not be started: $($_.Exception.Message)")
            return 1
        }
    }

    while ($true) {
        Write-Host ''
        Write-Host '[L] Run the cached local script' -ForegroundColor Yellow
        Write-Host '[X] Exit' -ForegroundColor DarkGray

        try {
            $choice = (Read-Host 'Choose an option').Trim().ToUpperInvariant()
        }
        catch {
            return 1
        }

        switch ($choice) {
            'L' {
                try {
                    return Invoke-LocalPowerShellScript -Path $ScriptPath -Arguments $ScriptArguments
                }
                catch {
                    Write-Host ("The cached script could not be started: $($_.Exception.Message)") -ForegroundColor Red
                    return 1
                }
            }
            'X' { return 1 }
            default { Write-Host 'Invalid choice.' -ForegroundColor Red }
        }
    }
}

$runningAsPowerShellScript = -not [string]::IsNullOrWhiteSpace($PSCommandPath) -and
    [System.IO.Path]::GetExtension($PSCommandPath) -ieq '.ps1'

if ($RequireAdministrator -and $runningAsPowerShellScript -and -not (Test-LauncherAdministrator)) {
    if (-not $LauncherElevated) {
        Write-Host "$LauncherName requires administrator rights. Requesting elevation..." -ForegroundColor Yellow
        if (Start-ElevatedLauncher -LauncherPath $PSCommandPath -Arguments $ScriptArguments) {
            exit 0
        }
    }
    else {
        $script:ElevationError = 'The relaunched PowerShell process did not receive administrator rights.'
    }

    $ExitCode = Invoke-CachedScriptFallback -Reason ("Administrator relaunch failed or was canceled: $script:ElevationError")
    exit $ExitCode
}

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    if (-not (Test-Path -LiteralPath $ScriptDirectory -PathType Container)) {
        New-Item -Path $ScriptDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $CacheBuster = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $uriBuilder = New-Object System.UriBuilder -ArgumentList $ScriptUri
    $existingQuery = $uriBuilder.Query.TrimStart('?')
    $cacheQuery = 'cachebust={0}' -f $CacheBuster
    $uriBuilder.Query = if ([string]::IsNullOrWhiteSpace($existingQuery)) {
        $cacheQuery
    }
    else {
        $existingQuery + '&' + $cacheQuery
    }
    $DownloadUri = $uriBuilder.Uri.AbsoluteUri

    Write-Host ("Downloading the latest $LauncherName...") -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUri `
        -OutFile $DownloadPath `
        -UseBasicParsing `
        -TimeoutSec 20 `
        -Headers @{ 'Cache-Control' = 'no-cache' } `
        -ErrorAction Stop

    Assert-ValidPowerShellScript -Path $DownloadPath

    $installDownloadedScript = $true
    if ([System.IO.File]::Exists($ScriptPath)) {
        try {
            Assert-ValidPowerShellScript -Path $ScriptPath
            $downloadedHash = (Get-FileHash -LiteralPath $DownloadPath -Algorithm SHA256 -ErrorAction Stop).Hash
            $cachedHash = (Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($downloadedHash -eq $cachedHash) {
                $installDownloadedScript = $false
                [System.IO.File]::Delete($DownloadPath)
                if (-not $SuppressTerminal) {
                    Write-Host "$LauncherName is already current." -ForegroundColor Green
                }
            }
        }
        catch {
            $installDownloadedScript = $true
        }
    }

    if ($installDownloadedScript) {
        if ([System.IO.File]::Exists($ScriptPath)) {
            if ([System.IO.File]::Exists($BackupPath)) {
                [System.IO.File]::Delete($BackupPath)
            }
            [System.IO.File]::Replace($DownloadPath, $ScriptPath, $BackupPath, $true)
        }
        else {
            [System.IO.File]::Move($DownloadPath, $ScriptPath)
        }
    }

    $ExitCode = Invoke-LocalPowerShellScript -Path $ScriptPath -Arguments $ScriptArguments
}
catch {
    $ExitCode = Invoke-CachedScriptFallback `
        -Reason ("The latest script could not be downloaded or installed: $($_.Exception.Message)") `
        -Automatic
}
finally {
    if (Test-Path -LiteralPath $DownloadPath) {
        Remove-Item -LiteralPath $DownloadPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $BackupPath) {
        Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
    }
}

exit $ExitCode
