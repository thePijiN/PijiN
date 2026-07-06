$frames = @(
@"
@--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%\ 
##/  ######/  ######/  ######/  ######/  #####\
###   ######   ######   ######   ######   ####/
%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%/ 
"@,
@"
%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%\ 
###/  ######/  ######/  ######/  ######/  ####\
####   ######   ######   ######   ######   ###/
%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-*/ 
"@,
@"
%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%\ 
####/  ######/  ######/  ######/  ######/  ###\
#####   ######   ######   ######   ######   ##/
%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/"/ 
"@,
@"
%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%\ 
#####/  ######/  ######/  ######/  ######/  ##\
######   ######   ######   ######   ######   #/
-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/' 
"@,
@"
%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%\ 
######/  ######/  ######/  ######/  ######/  #\
#######   ######   ######   ######   ######   /
/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/ 
"@,
@"
%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/\ 
 ######/  ######/  ######/  ######/  ######/  \
  ######   ######   ######   ######   ######  /
_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%/ 
"@,
@"
/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%-/\ 
  ######/  ######/  ######/  ######/  ######/ \
   ######   ######   ######   ######   ###### /
%%_/%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%/ 
"@,
@"
-/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%,\ 
/  ######/  ######/  ######/  ######/  ######/\
#   ######   ######   ######   ######   ######/
%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%/ 
"@,
@"
--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%. 
#/  ######/  ######/  ######/  ######/  ######\
##   ######   ######   ######   ######   #####/
%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%/ 
"@,
@"
%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%%--/%%%%%\ 
##/  ######/  ######/  ######/  ######/  #####\
###   ######   ######   ######   ######   ####/
%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%%%%%_/-%%/ 
"@
)

$delay = 50
$typed = ''
$status = 'Type 1-1000 and press Enter to set ms/frame. Empty Enter exits.'
$frame = 0
$done = $false
$oldCursor = [Console]::CursorVisible

function Write-FixedLine([string]$s) {
    $w = [Math]::Max(1, [Console]::BufferWidth - 1)
    if ($s.Length -gt $w) { $s = $s.Substring(0, $w) }
    [Console]::WriteLine($s.PadRight($w))
}

try {
    [Console]::CursorVisible = $false
    Clear-Host

    while (-not $done) {
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            if ($key.Key -eq [ConsoleKey]::Enter) {
                $raw = $typed.Trim()
                if ($raw.Length -eq 0) { $done = $true; break }

                $newDelay = 0
                if ([int]::TryParse($raw, [ref]$newDelay) -and $newDelay -ge 1 -and $newDelay -le 1000) {
                    $delay = $newDelay
                    $status = "Speed set to $delay ms/frame."
                } else {
                    $status = 'Invalid input. Use 1-1000, or blank Enter to exit.'
                }
                $typed = ''
            } elseif ($key.Key -eq [ConsoleKey]::Backspace) {
                if ($typed.Length -gt 0) { $typed = $typed.Substring(0, $typed.Length - 1) }
            } elseif (-not [char]::IsControl($key.KeyChar)) {
                $typed += $key.KeyChar
            }
        }

        if ($done) { break }

        [Console]::SetCursorPosition(0, 0)
        $frameText = $frames[$frame].TrimEnd([char[]]"`r`n")
        foreach ($line in ($frameText -split '\r?\n')) { Write-FixedLine $line }
        Write-FixedLine ''
        Write-FixedLine ("Speed: $delay ms/frame")
        Write-FixedLine 'Input: type 1-1000, Enter to apply, Backspace to edit, blank Enter to exit.'
        Write-FixedLine ("> $typed")
        Write-FixedLine $status

        $frame = ($frame + 1) % $frames.Count
        Start-Sleep -Milliseconds $delay
    }
} finally {
    [Console]::CursorVisible = $oldCursor
    $exitTop = [Math]::Min(9, [Console]::BufferHeight - 1)
    [Console]::SetCursorPosition(0, $exitTop)
    [Console]::WriteLine()
}
