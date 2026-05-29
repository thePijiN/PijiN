# Exanima Cursor Color Utility
# Standalone tool to view and edit the in-game cursor colors and size
# that Exanima exposes only through its config file.
#
# It reads and writes ONLY these keys in %APPDATA%\Exanima\Exanima.ini:
#     CursorInt   (Interaction mode cursor color, RGBA hex e.g. ffeeddff)
#     CursorCom   (Combat mode cursor color,      RGBA hex e.g. ffb050ff)
#     CursorSize  (cursor scale as a percentage,  e.g. 150)
#
# The last 2 hex digits are the alpha channel. Size 100 is normal scale.
# No other files, registry keys, or settings are touched. Nothing is
# written until you click an Apply button.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# dark title bar support (silently ignored on older Windows)
try {
    Add-Type -Namespace Native -Name Dwm -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@
} catch { }

# ========== theme ==========
$script:ClrBg     = [System.Drawing.Color]::FromArgb(17,19,25)
$script:ClrCard   = [System.Drawing.Color]::FromArgb(28,31,41)
$script:ClrInput  = [System.Drawing.Color]::FromArgb(41,45,58)
$script:ClrText   = [System.Drawing.Color]::FromArgb(236,236,240)
$script:ClrMuted  = [System.Drawing.Color]::FromArgb(150,157,170)
$script:ClrEmber  = [System.Drawing.Color]::FromArgb(232,120,38)
$script:ClrFlame  = [System.Drawing.Color]::FromArgb(206,58,30)
$script:ClrGold   = [System.Drawing.Color]::FromArgb(240,186,54)
$script:ClrBorder = [System.Drawing.Color]::FromArgb(66,74,92)
$script:ClrBtnBg  = [System.Drawing.Color]::FromArgb(46,38,34)
$script:ClrBtnHot = [System.Drawing.Color]::FromArgb(74,52,38)

# ========== state ==========
$script:IniPath  = Join-Path $env:APPDATA 'Exanima\Exanima.ini'
$script:H        = 0.0
$script:S        = 0.0
$script:V        = 1.0
$script:A        = 255
$script:Target   = 'CursorInt'
$script:Updating = $false

# ========== color math ==========
function Convert-HsvToRgb {
    param([double]$Hue,[double]$Sat,[double]$Val)
    $c  = $Val * $Sat
    $hp = $Hue / 60.0
    $x  = $c * (1.0 - [Math]::Abs(($hp % 2.0) - 1.0))
    $r1 = 0.0; $g1 = 0.0; $b1 = 0.0
    if     ($hp -lt 1) { $r1 = $c; $g1 = $x; $b1 = 0  }
    elseif ($hp -lt 2) { $r1 = $x; $g1 = $c; $b1 = 0  }
    elseif ($hp -lt 3) { $r1 = 0;  $g1 = $c; $b1 = $x }
    elseif ($hp -lt 4) { $r1 = 0;  $g1 = $x; $b1 = $c }
    elseif ($hp -lt 5) { $r1 = $x; $g1 = 0;  $b1 = $c }
    else               { $r1 = $c; $g1 = 0;  $b1 = $x }
    $m = $Val - $c
    $r = [int][Math]::Round(($r1 + $m) * 255.0)
    $g = [int][Math]::Round(($g1 + $m) * 255.0)
    $b = [int][Math]::Round(($b1 + $m) * 255.0)
    return ,@($r,$g,$b)
}

function Convert-RgbToHsv {
    param([int]$R,[int]$G,[int]$B)
    $r = $R / 255.0; $g = $G / 255.0; $b = $B / 255.0
    $max = [Math]::Max($r,[Math]::Max($g,$b))
    $min = [Math]::Min($r,[Math]::Min($g,$b))
    $d = $max - $min
    $h = 0.0
    if ($d -ne 0) {
        if     ($max -eq $r) { $h = 60.0 * (((($g - $b) / $d)) % 6.0) }
        elseif ($max -eq $g) { $h = 60.0 * ((($b - $r) / $d) + 2.0) }
        else                 { $h = 60.0 * ((($r - $g) / $d) + 4.0) }
    }
    if ($h -lt 0) { $h += 360.0 }
    $s = 0.0
    if ($max -ne 0) { $s = $d / $max }
    $v = $max
    return ,@($h,$s,$v)
}

function Get-HexFromState {
    $rgb = Convert-HsvToRgb $script:H $script:S $script:V
    return ('{0:x2}{1:x2}{2:x2}{3:x2}' -f $rgb[0],$rgb[1],$rgb[2],$script:A)
}

function Set-StateFromRgba {
    param([int]$R,[int]$G,[int]$B,[int]$Alpha)
    $hsv = Convert-RgbToHsv $R $G $B
    if ($hsv[1] -gt 0) { $script:H = $hsv[0] }
    $script:S = $hsv[1]
    $script:V = $hsv[2]
    $script:A = $Alpha
}

function ConvertFrom-HexColor {
    param([string]$Hex)
    if ([string]::IsNullOrWhiteSpace($Hex)) { return $null }
    $h = $Hex.Trim()
    if ($h.StartsWith('#')) { $h = $h.Substring(1) }
    if ($h -notmatch '^[0-9a-fA-F]+$') { return $null }
    if ($h.Length -eq 6) { $h = $h + 'ff' }
    if ($h.Length -ne 8) { return $null }
    $r = [Convert]::ToInt32($h.Substring(0,2),16)
    $g = [Convert]::ToInt32($h.Substring(2,2),16)
    $b = [Convert]::ToInt32($h.Substring(4,2),16)
    $a = [Convert]::ToInt32($h.Substring(6,2),16)
    return ,@($r,$g,$b,$a)
}

# ========== ini access (System.IO, no cmdlet parameter sets) ==========
function Get-IniValue {
    param([string]$Path,[string]$Key)
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    $pattern = '^\s*' + [Regex]::Escape($Key) + '\s*=\s*(.+?)\s*$'
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match $pattern) { return $Matches[1] }
    }
    return $null
}

function Set-IniValue {
    param([string]$Path,[string]$Key,[string]$Value)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [System.IO.Directory]::Exists($dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $lines = New-Object System.Collections.Generic.List[string]
    if ([System.IO.File]::Exists($Path)) {
        $lines.AddRange([System.IO.File]::ReadAllLines($Path))
    }
    $pattern = '^\s*' + [Regex]::Escape($Key) + '\s*='
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = ('{0} = {1}' -f $Key,$Value)
            $found = $true
            break
        }
    }
    if (-not $found) { $lines.Add(('{0} = {1}' -f $Key,$Value)) }
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($Path, $lines, $enc)
}

# ========== drawing helpers ==========
function Enable-DoubleBuffer {
    param([System.Windows.Forms.Control]$Control)
    $prop = [System.Windows.Forms.Control].GetProperty('DoubleBuffered',
        [System.Reflection.BindingFlags]'Instance,NonPublic')
    $prop.SetValue($Control,$true,$null)
}

function DrawChecker {
    param($Graphics,[int]$W,[int]$H)
    $sz = 8
    $light = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70,74,86))
    $dark  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(46,50,60))
    for ($y = 0; $y -lt $H; $y += $sz) {
        for ($x = 0; $x -lt $W; $x += $sz) {
            $alt = (([Math]::Floor($x / $sz)) + ([Math]::Floor($y / $sz))) % 2
            if ($alt -eq 0) { $br = $light } else { $br = $dark }
            $Graphics.FillRectangle($br, $x, $y, $sz, $sz)
        }
    }
    $light.Dispose()
    $dark.Dispose()
}

# ========== themed control builders ==========
function NewCard {
    param([string]$Title,[int]$X,[int]$Y,[int]$W,[int]$H)
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point $X,$Y
    $p.Size = New-Object System.Drawing.Size $W,$H
    $p.BackColor = $script:ClrCard
    $p.Add_Paint({
        param($s,$e)
        $r = New-Object System.Drawing.Rectangle 0,0,($s.ClientSize.Width - 1),($s.ClientSize.Height - 1)
        $pen = New-Object System.Drawing.Pen $script:ClrBorder, ([single]1)
        $e.Graphics.DrawRectangle($pen, $r)
        $pen.Dispose()
    })
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Title
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point 10,6
    $lbl.ForeColor = $script:ClrEmber
    $lbl.BackColor = $script:ClrCard
    $lbl.Font = New-Object System.Drawing.Font 'Segoe UI',9,([System.Drawing.FontStyle]::Bold)
    $p.Controls.Add($lbl)
    return $p
}

function StyleButton {
    param($Btn)
    $Btn.FlatStyle = 'Flat'
    $Btn.BackColor = $script:ClrBtnBg
    $Btn.ForeColor = $script:ClrGold
    $Btn.Font = New-Object System.Drawing.Font 'Segoe UI',9,([System.Drawing.FontStyle]::Bold)
    $Btn.FlatAppearance.BorderColor = $script:ClrEmber
    $Btn.FlatAppearance.BorderSize = 1
    $Btn.FlatAppearance.MouseOverBackColor = $script:ClrBtnHot
    $Btn.FlatAppearance.MouseDownBackColor = $script:ClrFlame
    $Btn.Cursor = [System.Windows.Forms.Cursors]::Hand
}

function StyleInput {
    param($Ctrl)
    $Ctrl.BackColor = $script:ClrInput
    $Ctrl.ForeColor = $script:ClrText
    $Ctrl.BorderStyle = 'FixedSingle'
}

function StyleCardLabel {
    param($Lbl,$Color)
    $Lbl.BackColor = $script:ClrCard
    $Lbl.ForeColor = $Color
}

# ========== picker sync ==========
function UpdatePickerControls {
    $script:Updating = $true
    $rgb = Convert-HsvToRgb $script:H $script:S $script:V
    $script:txtHex.Text = Get-HexFromState
    $script:numR.Value = $rgb[0]
    $script:numG.Value = $rgb[1]
    $script:numB.Value = $rgb[2]
    $script:numA.Value = $script:A
    $script:Updating = $false
    $script:svBox.Invalidate()
    $script:hueBar.Invalidate()
    $script:alphaBar.Invalidate()
    $script:preview.Invalidate()
}

function LoadTargetIntoPicker {
    $val = Get-IniValue $script:IniPath $script:Target
    $parsed = $null
    if ($val -ne $null) { $parsed = ConvertFrom-HexColor $val }
    if ($parsed -eq $null) { $parsed = @(255,255,255,255) }
    Set-StateFromRgba $parsed[0] $parsed[1] $parsed[2] $parsed[3]
    UpdatePickerControls
}

function SetSwatch {
    param($Panel,$IniVal)
    $parsed = $null
    if ($IniVal -ne $null) { $parsed = ConvertFrom-HexColor $IniVal }
    $Panel.Tag = $parsed
    $Panel.Invalidate()
}

function RefreshCurrentSwatches {
    $vi = Get-IniValue $script:IniPath 'CursorInt'
    $vc = Get-IniValue $script:IniPath 'CursorCom'
    $vs = Get-IniValue $script:IniPath 'CursorSize'

    SetSwatch $script:swInt $vi
    SetSwatch $script:swCom $vc

    if ($vi -ne $null) { $script:lblInt.Text = "Interaction (CursorInt):  $vi" }
    else               { $script:lblInt.Text = 'Interaction (CursorInt):  not set (game default)' }

    if ($vc -ne $null) { $script:lblCom.Text = "Combat (CursorCom):  $vc" }
    else               { $script:lblCom.Text = 'Combat (CursorCom):  not set (game default)' }

    if ($vs -ne $null) {
        $script:lblSize.Text = "Size (CursorSize):  $vs%"
        $n = 0
        if ([int]::TryParse($vs,[ref]$n)) {
            if ($n -lt $script:numSize.Minimum) { $n = [int]$script:numSize.Minimum }
            if ($n -gt $script:numSize.Maximum) { $n = [int]$script:numSize.Maximum }
            $script:numSize.Value = $n
        }
    } else {
        $script:lblSize.Text = 'Size (CursorSize):  not set (default 100%)'
        $script:numSize.Value = 100
    }

    if ([System.IO.File]::Exists($script:IniPath)) {
        $script:lblPath.Text = "Editing:  $script:IniPath"
    } else {
        $script:lblPath.Text = "Not found yet:  $script:IniPath`r`nRun Exanima once first. Applying will create the file."
    }
}

# ========== form ==========
$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = 'Exanima Cursor Color Utility'
$script:form.FormBorderStyle = 'FixedDialog'
$script:form.MaximizeBox = $false
$script:form.StartPosition = 'CenterScreen'
$script:form.ClientSize = New-Object System.Drawing.Size 600,596
$script:form.Font = New-Object System.Drawing.Font 'Segoe UI',9
$script:form.BackColor = $script:ClrBg
$script:form.ForeColor = $script:ClrText

$script:lblPath = New-Object System.Windows.Forms.Label
$script:lblPath.Location = New-Object System.Drawing.Point 12,8
$script:lblPath.Size = New-Object System.Drawing.Size 576,32
$script:lblPath.BackColor = $script:ClrBg
$script:lblPath.ForeColor = $script:ClrMuted
$script:form.Controls.Add($script:lblPath)

# current values card
$cardCurrent = NewCard 'Current (.ini)' 12 44 576 86
$script:form.Controls.Add($cardCurrent)

$script:swInt = New-Object System.Windows.Forms.Panel
$script:swInt.Location = New-Object System.Drawing.Point 12,26
$script:swInt.Size = New-Object System.Drawing.Size 44,22
Enable-DoubleBuffer $script:swInt
$cardCurrent.Controls.Add($script:swInt)

$script:lblInt = New-Object System.Windows.Forms.Label
$script:lblInt.Location = New-Object System.Drawing.Point 64,29
$script:lblInt.Size = New-Object System.Drawing.Size 380,18
StyleCardLabel $script:lblInt $script:ClrText
$cardCurrent.Controls.Add($script:lblInt)

$script:swCom = New-Object System.Windows.Forms.Panel
$script:swCom.Location = New-Object System.Drawing.Point 12,54
$script:swCom.Size = New-Object System.Drawing.Size 44,22
Enable-DoubleBuffer $script:swCom
$cardCurrent.Controls.Add($script:swCom)

$script:lblCom = New-Object System.Windows.Forms.Label
$script:lblCom.Location = New-Object System.Drawing.Point 64,57
$script:lblCom.Size = New-Object System.Drawing.Size 380,18
StyleCardLabel $script:lblCom $script:ClrText
$cardCurrent.Controls.Add($script:lblCom)

$script:lblSize = New-Object System.Windows.Forms.Label
$script:lblSize.Location = New-Object System.Drawing.Point 448,29
$script:lblSize.Size = New-Object System.Drawing.Size 120,46
StyleCardLabel $script:lblSize $script:ClrText
$cardCurrent.Controls.Add($script:lblSize)

# edit card
$cardEdit = NewCard 'Edit color' 12 136 576 338
$script:form.Controls.Add($cardEdit)

$script:rbInt = New-Object System.Windows.Forms.RadioButton
$script:rbInt.Text = 'Interaction cursor'
$script:rbInt.Location = New-Object System.Drawing.Point 14,26
$script:rbInt.Size = New-Object System.Drawing.Size 150,20
$script:rbInt.BackColor = $script:ClrCard
$script:rbInt.ForeColor = $script:ClrText
$cardEdit.Controls.Add($script:rbInt)

$script:rbCom = New-Object System.Windows.Forms.RadioButton
$script:rbCom.Text = 'Combat cursor'
$script:rbCom.Location = New-Object System.Drawing.Point 180,26
$script:rbCom.Size = New-Object System.Drawing.Size 150,20
$script:rbCom.BackColor = $script:ClrCard
$script:rbCom.ForeColor = $script:ClrText
$cardEdit.Controls.Add($script:rbCom)

$script:svBox = New-Object System.Windows.Forms.Panel
$script:svBox.Location = New-Object System.Drawing.Point 14,54
$script:svBox.Size = New-Object System.Drawing.Size 240,240
$script:svBox.BorderStyle = 'FixedSingle'
$script:svBox.Cursor = [System.Windows.Forms.Cursors]::Cross
Enable-DoubleBuffer $script:svBox
$cardEdit.Controls.Add($script:svBox)

$script:hueBar = New-Object System.Windows.Forms.Panel
$script:hueBar.Location = New-Object System.Drawing.Point 264,54
$script:hueBar.Size = New-Object System.Drawing.Size 26,240
$script:hueBar.BorderStyle = 'FixedSingle'
Enable-DoubleBuffer $script:hueBar
$cardEdit.Controls.Add($script:hueBar)

$script:alphaBar = New-Object System.Windows.Forms.Panel
$script:alphaBar.Location = New-Object System.Drawing.Point 300,54
$script:alphaBar.Size = New-Object System.Drawing.Size 26,240
$script:alphaBar.BorderStyle = 'FixedSingle'
Enable-DoubleBuffer $script:alphaBar
$cardEdit.Controls.Add($script:alphaBar)

$lblHueCap = New-Object System.Windows.Forms.Label
$lblHueCap.Text = 'Hue'
$lblHueCap.Location = New-Object System.Drawing.Point 262,296
$lblHueCap.Size = New-Object System.Drawing.Size 30,16
StyleCardLabel $lblHueCap $script:ClrMuted
$cardEdit.Controls.Add($lblHueCap)

$lblAlphaCap = New-Object System.Windows.Forms.Label
$lblAlphaCap.Text = 'Alpha'
$lblAlphaCap.Location = New-Object System.Drawing.Point 298,296
$lblAlphaCap.Size = New-Object System.Drawing.Size 40,16
StyleCardLabel $lblAlphaCap $script:ClrMuted
$cardEdit.Controls.Add($lblAlphaCap)

$script:preview = New-Object System.Windows.Forms.Panel
$script:preview.Location = New-Object System.Drawing.Point 348,54
$script:preview.Size = New-Object System.Drawing.Size 200,46
Enable-DoubleBuffer $script:preview
$cardEdit.Controls.Add($script:preview)

$lblHex = New-Object System.Windows.Forms.Label
$lblHex.Text = 'Hex (RRGGBBAA)'
$lblHex.Location = New-Object System.Drawing.Point 348,112
$lblHex.Size = New-Object System.Drawing.Size 160,16
StyleCardLabel $lblHex $script:ClrText
$cardEdit.Controls.Add($lblHex)

$script:txtHex = New-Object System.Windows.Forms.TextBox
$script:txtHex.Location = New-Object System.Drawing.Point 348,130
$script:txtHex.Size = New-Object System.Drawing.Size 120,24
$script:txtHex.MaxLength = 8
$script:txtHex.CharacterCasing = 'Lower'
$script:txtHex.Font = New-Object System.Drawing.Font 'Consolas',10
StyleInput $script:txtHex
$script:txtHex.ForeColor = $script:ClrGold
$cardEdit.Controls.Add($script:txtHex)

function NewChannelBox {
    param([string]$Caption,[int]$Y)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Caption
    $lbl.Location = New-Object System.Drawing.Point 348,($Y + 4)
    $lbl.Size = New-Object System.Drawing.Size 22,18
    StyleCardLabel $lbl $script:ClrText
    $cardEdit.Controls.Add($lbl)
    $num = New-Object System.Windows.Forms.NumericUpDown
    $num.Location = New-Object System.Drawing.Point 374,$Y
    $num.Size = New-Object System.Drawing.Size 64,24
    $num.Minimum = 0
    $num.Maximum = 255
    StyleInput $num
    $cardEdit.Controls.Add($num)
    return $num
}

$script:numR = NewChannelBox 'R' 166
$script:numG = NewChannelBox 'G' 194
$script:numB = NewChannelBox 'B' 222
$script:numA = NewChannelBox 'A' 250

$script:btnApplyColor = New-Object System.Windows.Forms.Button
$script:btnApplyColor.Text = 'Apply color'
$script:btnApplyColor.Location = New-Object System.Drawing.Point 348,292
$script:btnApplyColor.Size = New-Object System.Drawing.Size 200,32
StyleButton $script:btnApplyColor
$cardEdit.Controls.Add($script:btnApplyColor)

# size card
$cardSize = NewCard 'Cursor size' 12 480 576 58
$script:form.Controls.Add($cardSize)

$lblSizeCap = New-Object System.Windows.Forms.Label
$lblSizeCap.Text = 'Scale (percent, 100 is normal):'
$lblSizeCap.Location = New-Object System.Drawing.Point 14,28
$lblSizeCap.Size = New-Object System.Drawing.Size 190,18
StyleCardLabel $lblSizeCap $script:ClrText
$cardSize.Controls.Add($lblSizeCap)

$script:numSize = New-Object System.Windows.Forms.NumericUpDown
$script:numSize.Location = New-Object System.Drawing.Point 206,25
$script:numSize.Size = New-Object System.Drawing.Size 80,24
$script:numSize.Minimum = 1
$script:numSize.Maximum = 1000
$script:numSize.Value = 100
StyleInput $script:numSize
$cardSize.Controls.Add($script:numSize)

$script:btnApplySize = New-Object System.Windows.Forms.Button
$script:btnApplySize.Text = 'Apply size'
$script:btnApplySize.Location = New-Object System.Drawing.Point 300,23
$script:btnApplySize.Size = New-Object System.Drawing.Size 120,28
StyleButton $script:btnApplySize
$cardSize.Controls.Add($script:btnApplySize)

# bottom buttons
$script:btnReload = New-Object System.Windows.Forms.Button
$script:btnReload.Text = 'Reload .ini'
$script:btnReload.Location = New-Object System.Drawing.Point 360,548
$script:btnReload.Size = New-Object System.Drawing.Size 110,32
StyleButton $script:btnReload
$script:form.Controls.Add($script:btnReload)

$script:btnClose = New-Object System.Windows.Forms.Button
$script:btnClose.Text = 'Close'
$script:btnClose.Location = New-Object System.Drawing.Point 478,548
$script:btnClose.Size = New-Object System.Drawing.Size 110,32
StyleButton $script:btnClose
$script:form.Controls.Add($script:btnClose)

$lblTip = New-Object System.Windows.Forms.Label
$lblTip.Text = 'Tip: edit while Exanima is closed. The game reads the .ini when it launches.'
$lblTip.Location = New-Object System.Drawing.Point 12,556
$lblTip.Size = New-Object System.Drawing.Size 340,32
$lblTip.BackColor = $script:ClrBg
$lblTip.ForeColor = $script:ClrMuted
$script:form.Controls.Add($lblTip)

# ========== paint handlers ==========
$script:svBox.Add_Paint({
    param($s,$e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    $rgb = Convert-HsvToRgb $script:H 1.0 1.0
    $hueColor = [System.Drawing.Color]::FromArgb(255,$rgb[0],$rgb[1],$rgb[2])
    $rect = New-Object System.Drawing.Rectangle 0,0,$w,$h
    $bh = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::White), $hueColor, ([single]0)
    $g.FillRectangle($bh, $rect)
    $bh.Dispose()
    $bv = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(0,0,0,0)), ([System.Drawing.Color]::Black), ([single]90)
    $g.FillRectangle($bv, $rect)
    $bv.Dispose()
    $mx = [int]($script:S * ($w - 1))
    $my = [int]((1.0 - $script:V) * ($h - 1))
    $pb = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), ([single]2)
    $pw = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([single]1)
    $g.DrawEllipse($pb, ($mx - 5), ($my - 5), 10, 10)
    $g.DrawEllipse($pw, ($mx - 4), ($my - 4), 8, 8)
    $pb.Dispose()
    $pw.Dispose()
})

$script:hueBar.Add_Paint({
    param($s,$e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    $rect = New-Object System.Drawing.Rectangle 0,0,$w,$h
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::Red), ([System.Drawing.Color]::Red), ([single]90)
    $cb = New-Object System.Drawing.Drawing2D.ColorBlend 7
    $cb.Colors = [System.Drawing.Color[]]@(
        [System.Drawing.Color]::FromArgb(255,0,0),
        [System.Drawing.Color]::FromArgb(255,255,0),
        [System.Drawing.Color]::FromArgb(0,255,0),
        [System.Drawing.Color]::FromArgb(0,255,255),
        [System.Drawing.Color]::FromArgb(0,0,255),
        [System.Drawing.Color]::FromArgb(255,0,255),
        [System.Drawing.Color]::FromArgb(255,0,0)
    )
    $cb.Positions = [single[]]@(0.0,0.1667,0.3333,0.5,0.6667,0.8333,1.0)
    $br.InterpolationColors = $cb
    $g.FillRectangle($br, $rect)
    $br.Dispose()
    $my = [int](($script:H / 360.0) * ($h - 1))
    $pb = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), ([single]2)
    $g.DrawRectangle($pb, 0, ($my - 2), ($w - 1), 4)
    $pb.Dispose()
    $pw = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([single]1)
    $g.DrawRectangle($pw, 1, ($my - 1), ($w - 3), 2)
    $pw.Dispose()
})

$script:alphaBar.Add_Paint({
    param($s,$e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    DrawChecker $g $w $h
    $rgb = Convert-HsvToRgb $script:H $script:S $script:V
    $top = [System.Drawing.Color]::FromArgb(255,$rgb[0],$rgb[1],$rgb[2])
    $bot = [System.Drawing.Color]::FromArgb(0,$rgb[0],$rgb[1],$rgb[2])
    $rect = New-Object System.Drawing.Rectangle 0,0,$w,$h
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bot, ([single]90)
    $g.FillRectangle($br, $rect)
    $br.Dispose()
    $my = [int]((1.0 - ($script:A / 255.0)) * ($h - 1))
    $pb = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), ([single]2)
    $g.DrawRectangle($pb, 0, ($my - 2), ($w - 1), 4)
    $pb.Dispose()
    $pw = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([single]1)
    $g.DrawRectangle($pw, 1, ($my - 1), ($w - 3), 2)
    $pw.Dispose()
})

$script:preview.Add_Paint({
    param($s,$e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    DrawChecker $g $w $h
    $rgb = Convert-HsvToRgb $script:H $script:S $script:V
    $col = [System.Drawing.Color]::FromArgb($script:A,$rgb[0],$rgb[1],$rgb[2])
    $br = New-Object System.Drawing.SolidBrush $col
    $g.FillRectangle($br, 0, 0, $w, $h)
    $br.Dispose()
    $pen = New-Object System.Drawing.Pen $script:ClrBorder, ([single]1)
    $g.DrawRectangle($pen, 0, 0, ($w - 1), ($h - 1))
    $pen.Dispose()
})

$swPaint = {
    param($s,$e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    DrawChecker $g $w $h
    $p = $s.Tag
    if ($p -ne $null) {
        $col = [System.Drawing.Color]::FromArgb([int]$p[3],[int]$p[0],[int]$p[1],[int]$p[2])
        $br = New-Object System.Drawing.SolidBrush $col
        $g.FillRectangle($br, 0, 0, $w, $h)
        $br.Dispose()
    }
    $pen = New-Object System.Drawing.Pen $script:ClrBorder, ([single]1)
    $g.DrawRectangle($pen, 0, 0, ($w - 1), ($h - 1))
    $pen.Dispose()
}
$script:swInt.Add_Paint($swPaint)
$script:swCom.Add_Paint($swPaint)

# ========== mouse handlers ==========
$svHandler = {
    param($s,$e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $w = $s.ClientSize.Width
        $h = $s.ClientSize.Height
        $sx = [Math]::Max(0,[Math]::Min($w - 1,$e.X))
        $sy = [Math]::Max(0,[Math]::Min($h - 1,$e.Y))
        $script:S = $sx / ($w - 1)
        $script:V = 1.0 - ($sy / ($h - 1))
        UpdatePickerControls
    }
}
$script:svBox.Add_MouseDown($svHandler)
$script:svBox.Add_MouseMove($svHandler)

$hueHandler = {
    param($s,$e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $h = $s.ClientSize.Height
        $sy = [Math]::Max(0,[Math]::Min($h - 1,$e.Y))
        $script:H = ($sy / ($h - 1)) * 360.0
        UpdatePickerControls
    }
}
$script:hueBar.Add_MouseDown($hueHandler)
$script:hueBar.Add_MouseMove($hueHandler)

$alphaHandler = {
    param($s,$e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $h = $s.ClientSize.Height
        $sy = [Math]::Max(0,[Math]::Min($h - 1,$e.Y))
        $script:A = [int][Math]::Round((1.0 - ($sy / ($h - 1))) * 255.0)
        UpdatePickerControls
    }
}
$script:alphaBar.Add_MouseDown($alphaHandler)
$script:alphaBar.Add_MouseMove($alphaHandler)

# ========== input handlers ==========
$numHandler = {
    if ($script:Updating) { return }
    Set-StateFromRgba ([int]$script:numR.Value) ([int]$script:numG.Value) ([int]$script:numB.Value) ([int]$script:numA.Value)
    UpdatePickerControls
}
$script:numR.Add_ValueChanged($numHandler)
$script:numG.Add_ValueChanged($numHandler)
$script:numB.Add_ValueChanged($numHandler)
$script:numA.Add_ValueChanged($numHandler)

$script:txtHex.Add_TextChanged({
    if ($script:Updating) { return }
    $parsed = ConvertFrom-HexColor $script:txtHex.Text
    if ($parsed -ne $null) {
        Set-StateFromRgba $parsed[0] $parsed[1] $parsed[2] $parsed[3]
        $script:Updating = $true
        $rgb = Convert-HsvToRgb $script:H $script:S $script:V
        $script:numR.Value = $rgb[0]
        $script:numG.Value = $rgb[1]
        $script:numB.Value = $rgb[2]
        $script:numA.Value = $script:A
        $script:Updating = $false
        $script:svBox.Invalidate()
        $script:hueBar.Invalidate()
        $script:alphaBar.Invalidate()
        $script:preview.Invalidate()
    }
})

$script:rbInt.Add_CheckedChanged({
    if ($script:rbInt.Checked) { $script:Target = 'CursorInt'; LoadTargetIntoPicker }
})
$script:rbCom.Add_CheckedChanged({
    if ($script:rbCom.Checked) { $script:Target = 'CursorCom'; LoadTargetIntoPicker }
})

$script:btnApplyColor.Add_Click({
    try {
        $hex = Get-HexFromState
        Set-IniValue $script:IniPath $script:Target $hex
        RefreshCurrentSwatches
        LoadTargetIntoPicker
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not write the file:`r`n$($_.Exception.Message)",
            'Error',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$script:btnApplySize.Add_Click({
    try {
        $sz = [int]$script:numSize.Value
        Set-IniValue $script:IniPath 'CursorSize' ([string]$sz)
        RefreshCurrentSwatches
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not write the file:`r`n$($_.Exception.Message)",
            'Error',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$script:btnReload.Add_Click({ RefreshCurrentSwatches; LoadTargetIntoPicker })
$script:btnClose.Add_Click({ $script:form.Close() })

$script:form.Add_Shown({
    try {
        $v = 1
        $res = [Native.Dwm]::DwmSetWindowAttribute($script:form.Handle, 20, [ref]$v, 4)
        if ($res -ne 0) {
            [Native.Dwm]::DwmSetWindowAttribute($script:form.Handle, 19, [ref]$v, 4) | Out-Null
        }
        $script:form.Invalidate($true)
    } catch { }
})

# ========== init ==========
RefreshCurrentSwatches
$script:rbInt.Checked = $true
[void]$script:form.ShowDialog()
$script:form.Dispose()