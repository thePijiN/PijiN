<#
InputSender.ps1

A PowerShell 5.1 WinForms utility for sending virtual keyboard and mouse input
through the Windows SendInput API. The UI is data-driven: tweak the $Layout
entries near the middle of the file to move, resize, relabel, or recolor buttons.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$sendInputSource = @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class NativeInputSender
{
    private const int INPUT_MOUSE = 0;
    private const int INPUT_KEYBOARD = 1;

    private const uint KEYEVENTF_KEYUP = 0x0002;

    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    private const uint MOUSEEVENTF_XDOWN = 0x0080;
    private const uint MOUSEEVENTF_XUP = 0x0100;
    private const uint MOUSEEVENTF_WHEEL = 0x0800;
    private const uint MOUSEEVENTF_HWHEEL = 0x1000;

    private const uint XBUTTON1 = 0x0001;
    private const uint XBUTTON2 = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public int type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public MOUSEINPUT mi;

        [FieldOffset(0)]
        public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, int lParam);

    public const int WM_NCLBUTTONDOWN = 0xA1;
    public const int HTCAPTION = 0x2;

    public static void KeyDown(ushort vk)
    {
        SendKeyboard(vk, 0);
    }

    public static void KeyUp(ushort vk)
    {
        SendKeyboard(vk, KEYEVENTF_KEYUP);
    }

    public static void MouseButtonDown(string button)
    {
        SendMouse(ButtonFlag(button, true), ButtonData(button));
    }

    public static void MouseButtonUp(string button)
    {
        SendMouse(ButtonFlag(button, false), ButtonData(button));
    }

    public static void MouseWheel(int delta)
    {
        SendMouse(MOUSEEVENTF_WHEEL, unchecked((uint)delta));
    }

    public static void MouseHWheel(int delta)
    {
        SendMouse(MOUSEEVENTF_HWHEEL, unchecked((uint)delta));
    }

    private static void SendKeyboard(ushort vk, uint flags)
    {
        INPUT input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.U.ki.wVk = vk;
        input.U.ki.wScan = 0;
        input.U.ki.dwFlags = flags;
        input.U.ki.time = 0;
        input.U.ki.dwExtraInfo = IntPtr.Zero;

        SendSingle(input);
    }

    private static void SendMouse(uint flags, uint data)
    {
        INPUT input = new INPUT();
        input.type = INPUT_MOUSE;
        input.U.mi.dx = 0;
        input.U.mi.dy = 0;
        input.U.mi.mouseData = data;
        input.U.mi.dwFlags = flags;
        input.U.mi.time = 0;
        input.U.mi.dwExtraInfo = IntPtr.Zero;

        SendSingle(input);
    }

    private static void SendSingle(INPUT input)
    {
        INPUT[] inputs = new INPUT[] { input };
        uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 1)
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    private static uint ButtonFlag(string button, bool down)
    {
        switch (button)
        {
            case "Left": return down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
            case "Right": return down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
            case "Middle": return down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
            case "X1":
            case "X2": return down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
            default: throw new ArgumentException("Unknown mouse button: " + button);
        }
    }

    private static uint ButtonData(string button)
    {
        switch (button)
        {
            case "X1": return XBUTTON1;
            case "X2": return XBUTTON2;
            default: return 0;
        }
    }
}

public class ResizableDarkForm : Form
{
    private const int WM_NCHITTEST = 0x0084;
    private const int HTLEFT = 10;
    private const int HTRIGHT = 11;
    private const int HTTOP = 12;
    private const int HTTOPLEFT = 13;
    private const int HTTOPRIGHT = 14;
    private const int HTBOTTOM = 15;
    private const int HTBOTTOMLEFT = 16;
    private const int HTBOTTOMRIGHT = 17;
    private const int ResizeGripSize = 8;

    protected override void WndProc(ref Message m)
    {
        base.WndProc(ref m);

        if (m.Msg != WM_NCHITTEST || this.WindowState != FormWindowState.Normal)
        {
            return;
        }

        int x = unchecked((short)((long)m.LParam & 0xffff));
        int y = unchecked((short)(((long)m.LParam >> 16) & 0xffff));
        Point clientPoint = this.PointToClient(new Point(x, y));

        bool left = clientPoint.X <= ResizeGripSize;
        bool right = clientPoint.X >= this.ClientSize.Width - ResizeGripSize;
        bool top = clientPoint.Y <= ResizeGripSize;
        bool bottom = clientPoint.Y >= this.ClientSize.Height - ResizeGripSize;

        if (top && left) m.Result = (IntPtr)HTTOPLEFT;
        else if (top && right) m.Result = (IntPtr)HTTOPRIGHT;
        else if (bottom && left) m.Result = (IntPtr)HTBOTTOMLEFT;
        else if (bottom && right) m.Result = (IntPtr)HTBOTTOMRIGHT;
        else if (left) m.Result = (IntPtr)HTLEFT;
        else if (right) m.Result = (IntPtr)HTRIGHT;
        else if (top) m.Result = (IntPtr)HTTOP;
        else if (bottom) m.Result = (IntPtr)HTBOTTOM;
    }
}
"@

if (-not ([System.Management.Automation.PSTypeName]'NativeInputSender').Type) {
    Add-Type -TypeDefinition $sendInputSource -Language CSharp -ReferencedAssemblies 'System.Windows.Forms','System.Drawing'
}

# region ########## INPUT LOOKUP TABLE ##########
function New-KeyInput {
    param([int]$VK)
    [pscustomobject]@{ Kind = 'Key'; VK = $VK }
}

function New-MouseButtonInput {
    param([string]$Button)
    [pscustomobject]@{ Kind = 'MouseButton'; Button = $Button }
}

function New-WheelInput {
    param(
        [ValidateSet('Vertical', 'Horizontal')]
        [string]$Axis,
        [int]$Delta
    )
    [pscustomobject]@{ Kind = 'Wheel'; Axis = $Axis; Delta = $Delta }
}

$InputMap = @{
    'Esc' = New-KeyInput 0x1B
    'F1' = New-KeyInput 0x70; 'F2' = New-KeyInput 0x71; 'F3' = New-KeyInput 0x72; 'F4' = New-KeyInput 0x73
    'F5' = New-KeyInput 0x74; 'F6' = New-KeyInput 0x75; 'F7' = New-KeyInput 0x76; 'F8' = New-KeyInput 0x77
    'F9' = New-KeyInput 0x78; 'F10' = New-KeyInput 0x79; 'F11' = New-KeyInput 0x7A; 'F12' = New-KeyInput 0x7B
    'F13' = New-KeyInput 0x7C; 'F14' = New-KeyInput 0x7D; 'F15' = New-KeyInput 0x7E; 'F16' = New-KeyInput 0x7F
    'F17' = New-KeyInput 0x80; 'F18' = New-KeyInput 0x81; 'F19' = New-KeyInput 0x82; 'F20' = New-KeyInput 0x83
    'F21' = New-KeyInput 0x84; 'F22' = New-KeyInput 0x85; 'F23' = New-KeyInput 0x86; 'F24' = New-KeyInput 0x87

    'PrintScreen' = New-KeyInput 0x2C; 'ScrollLock' = New-KeyInput 0x91; 'Pause' = New-KeyInput 0x13
    'Insert' = New-KeyInput 0x2D; 'Delete' = New-KeyInput 0x2E; 'Home' = New-KeyInput 0x24
    'End' = New-KeyInput 0x23; 'PageUp' = New-KeyInput 0x21; 'PageDown' = New-KeyInput 0x22
    'Up' = New-KeyInput 0x26; 'Down' = New-KeyInput 0x28; 'Left' = New-KeyInput 0x25; 'Right' = New-KeyInput 0x27

    '`' = New-KeyInput 0xC0; '1' = New-KeyInput 0x31; '2' = New-KeyInput 0x32; '3' = New-KeyInput 0x33
    '4' = New-KeyInput 0x34; '5' = New-KeyInput 0x35; '6' = New-KeyInput 0x36; '7' = New-KeyInput 0x37
    '8' = New-KeyInput 0x38; '9' = New-KeyInput 0x39; '0' = New-KeyInput 0x30; '-' = New-KeyInput 0xBD
    '=' = New-KeyInput 0xBB; 'Backspace' = New-KeyInput 0x08

    'Tab' = New-KeyInput 0x09; 'Q' = New-KeyInput 0x51; 'W' = New-KeyInput 0x57; 'E' = New-KeyInput 0x45
    'R' = New-KeyInput 0x52; 'T' = New-KeyInput 0x54; 'Y' = New-KeyInput 0x59; 'U' = New-KeyInput 0x55
    'I' = New-KeyInput 0x49; 'O' = New-KeyInput 0x4F; 'P' = New-KeyInput 0x50; '[' = New-KeyInput 0xDB
    ']' = New-KeyInput 0xDD; '\' = New-KeyInput 0xDC

    'CapsLock' = New-KeyInput 0x14; 'A' = New-KeyInput 0x41; 'S' = New-KeyInput 0x53; 'D' = New-KeyInput 0x44
    'F' = New-KeyInput 0x46; 'G' = New-KeyInput 0x47; 'H' = New-KeyInput 0x48; 'J' = New-KeyInput 0x4A
    'K' = New-KeyInput 0x4B; 'L' = New-KeyInput 0x4C; ';' = New-KeyInput 0xBA; 'Quote' = New-KeyInput 0xDE
    'Enter' = New-KeyInput 0x0D

    'LShift' = New-KeyInput 0xA0; 'Z' = New-KeyInput 0x5A; 'X' = New-KeyInput 0x58; 'C' = New-KeyInput 0x43
    'V' = New-KeyInput 0x56; 'B' = New-KeyInput 0x42; 'N' = New-KeyInput 0x4E; 'M' = New-KeyInput 0x4D
    ',' = New-KeyInput 0xBC; '.' = New-KeyInput 0xBE; '/' = New-KeyInput 0xBF; 'RShift' = New-KeyInput 0xA1

    'LCtrl' = New-KeyInput 0xA2; 'LWin' = New-KeyInput 0x5B; 'LAlt' = New-KeyInput 0xA4
    'Space' = New-KeyInput 0x20; 'RAlt' = New-KeyInput 0xA5; 'RWin' = New-KeyInput 0x5C
    'Menu' = New-KeyInput 0x5D; 'RCtrl' = New-KeyInput 0xA3

    'NumLock' = New-KeyInput 0x90; 'Numpad/' = New-KeyInput 0x6F; 'Numpad*' = New-KeyInput 0x6A; 'Numpad-' = New-KeyInput 0x6D
    'Numpad7' = New-KeyInput 0x67; 'Numpad8' = New-KeyInput 0x68; 'Numpad9' = New-KeyInput 0x69; 'Numpad+' = New-KeyInput 0x6B
    'Numpad4' = New-KeyInput 0x64; 'Numpad5' = New-KeyInput 0x65; 'Numpad6' = New-KeyInput 0x66
    'Numpad1' = New-KeyInput 0x61; 'Numpad2' = New-KeyInput 0x62; 'Numpad3' = New-KeyInput 0x63; 'NumpadEnter' = New-KeyInput 0x0D
    'Numpad0' = New-KeyInput 0x60; 'Numpad.' = New-KeyInput 0x6E

    'LMB' = New-MouseButtonInput 'Left'
    'RMB' = New-MouseButtonInput 'Right'
    'MMB' = New-MouseButtonInput 'Middle'
    'Mouse4' = New-MouseButtonInput 'X1'
    'Mouse5' = New-MouseButtonInput 'X2'
    'WheelUp' = New-WheelInput 'Vertical' 120
    'WheelDown' = New-WheelInput 'Vertical' -120
    'WheelLeft' = New-WheelInput 'Horizontal' -120
    'WheelRight' = New-WheelInput 'Horizontal' 120
}
#endregion ########## INPUT LOOKUP TABLE ##########

# region ########## BUTTON CONFIG ##########
$Layout = New-Object System.Collections.Generic.List[object]

function Add-LayoutKey {
    param(
        [string]$Label,
        [int]$X,
        [int]$Y,
        [int]$Width = 48,
        [int]$Height = 40,
        [string]$Color = 'DimGray',
        [string]$Text = $Label
    )

    $script:Layout.Add([pscustomobject]@{
        Label = $Label
        Text = $Text
        X = $X
        Y = $Y
        Width = $Width
        Height = $Height
        Color = $Color
    }) | Out-Null
}

function Add-Row {
    param(
        [string[]]$Labels,
        [int]$X,
        [int]$Y,
        [int]$Width = 48,
        [int]$Height = 40,
        [int]$Gap = 6,
        [string]$Color = 'DimGray'
    )

    $cursor = $X
    foreach ($label in $Labels) {
        Add-LayoutKey $label $cursor $Y $Width $Height $Color
        $cursor += $Width + $Gap
    }
}

$keyW = 48
$keyH = 40
$gap = 6
$mainX = 300
$topY = 56

Add-Row @('F13','F14','F15','F16') $($mainX + 78) $topY $keyW $keyH $gap 'DarkMagenta'
Add-Row @('F17','F18','F19','F20') $($mainX + 318) $topY $keyW $keyH $gap 'DarkMagenta'
Add-Row @('F21','F22','F23','F24') $($mainX + 558) $topY $keyW $keyH $gap 'DarkMagenta'

$functionY = $topY + 50
Add-LayoutKey 'Esc' $mainX $functionY $keyW $keyH 'Magenta'
Add-Row @('F1','F2','F3','F4') $($mainX + 78) $functionY $keyW $keyH $gap 'Magenta'
Add-Row @('F5','F6','F7','F8') $($mainX + 318) $functionY $keyW $keyH $gap 'Magenta'
Add-Row @('F9','F10','F11','F12') $($mainX + 558) $functionY $keyW $keyH $gap 'Magenta'
Add-Row @('PrintScreen','ScrollLock','Pause') $($mainX + 800) $functionY 78 $keyH $gap 'DarkViolet'

$rowY = $topY + 106
Add-Row @('`','1','2','3','4','5','6','7','8','9','0','-','=') $mainX $rowY $keyW $keyH $gap 'Gold'
Add-LayoutKey 'Backspace' $($mainX + 13 * ($keyW + $gap)) $rowY 88 $keyH 'Gold'

$rowY += 48
Add-LayoutKey 'Tab' $mainX $rowY 76 $keyH 'DarkCyan'
Add-Row @('Q','W','E','R','T','Y','U','I','O','P','[',']') $($mainX + 82) $rowY $keyW $keyH $gap 'Yellow'
Add-LayoutKey '\' $($mainX + 82 + 12 * ($keyW + $gap)) $rowY 60 $keyH 'Yellow'

$rowY += 48
Add-LayoutKey 'CapsLock' $mainX $rowY 90 $keyH 'DarkCyan'
Add-Row @('A','S','D','F','G','H','J','K','L',';','Quote') $($mainX + 96) $rowY $keyW $keyH $gap 'YellowGreen'
Add-LayoutKey 'Enter' $($mainX + 96 + 11 * ($keyW + $gap)) $rowY 100 $keyH 'DarkCyan'

$rowY += 48
Add-LayoutKey 'LShift' $mainX $rowY 116 $keyH 'DarkCyan'
Add-Row @('Z','X','C','V','B','N','M',',','.','/') $($mainX + 122) $rowY $keyW $keyH $gap 'Orange'
Add-LayoutKey 'RShift' $($mainX + 122 + 10 * ($keyW + $gap)) $rowY 128 $keyH 'DarkCyan'

$rowY += 48
Add-LayoutKey 'LCtrl' $mainX $rowY 64 $keyH 'DodgerBlue'
Add-LayoutKey 'LWin' $($mainX + 70) $rowY 64 $keyH 'DodgerBlue'
Add-LayoutKey 'LAlt' $($mainX + 140) $rowY 64 $keyH 'DodgerBlue'
Add-LayoutKey 'Space' $($mainX + 210) $rowY 300 $keyH 'DodgerBlue'
Add-LayoutKey 'RAlt' $($mainX + 516) $rowY 64 $keyH 'DodgerBlue'
Add-LayoutKey 'RWin' $($mainX + 586) $rowY 64 $keyH 'DodgerBlue'
Add-LayoutKey 'Menu' $($mainX + 656) $rowY 64 $keyH 'DodgerBlue'
Add-LayoutKey 'RCtrl' $($mainX + 726) $rowY 64 $keyH 'DodgerBlue'

$navX = $mainX + 800
Add-Row @('Insert','Home','PageUp') $navX $($topY + 106) 78 $keyH $gap 'DarkViolet'
Add-Row @('Delete','End','PageDown') $navX $($topY + 154) 78 $keyH $gap 'DarkViolet'
Add-LayoutKey 'Up' $($navX + 84) $($topY + 250) 78 $keyH 'LimeGreen'
Add-LayoutKey 'Left' $navX $($topY + 298) 78 $keyH 'LimeGreen'
Add-LayoutKey 'Down' $($navX + 84) $($topY + 298) 78 $keyH 'LimeGreen'
Add-LayoutKey 'Right' $($navX + 168) $($topY + 298) 78 $keyH 'LimeGreen'

$numX = $mainX
$numY = 410
Add-Row @('NumLock','Numpad/','Numpad*','Numpad-') $numX $numY 72 $keyH $gap 'SeaGreen'
Add-Row @('Numpad7','Numpad8','Numpad9') $numX $($numY + 48) 72 $keyH $gap 'SeaGreen'
Add-LayoutKey 'Numpad+' $($numX + 3 * (72 + $gap)) $($numY + 48) 72 88 'SeaGreen'
Add-Row @('Numpad4','Numpad5','Numpad6') $numX $($numY + 96) 72 $keyH $gap 'SeaGreen'
Add-Row @('Numpad1','Numpad2','Numpad3') $numX $($numY + 144) 72 $keyH $gap 'SeaGreen'
Add-LayoutKey 'NumpadEnter' $($numX + 3 * (72 + $gap)) $($numY + 144) 72 88 'SeaGreen'
Add-LayoutKey 'Numpad0' $numX $($numY + 192) 150 $keyH 'SeaGreen'
Add-LayoutKey 'Numpad.' $($numX + 2 * (72 + $gap)) $($numY + 192) 72 $keyH 'SeaGreen'

$mouseX = $numX + 330
$mouseY = $numY
$mouseButtonW = 116
$mouseButtonH = 96
$mouseTile = 34
$mouseGap = 8
$mouseInnerGap = 6
$mouseMiddleX = $mouseX + $mouseButtonW + $mouseInnerGap
$mouseRightX = $mouseMiddleX + (3 * $mouseTile) + $mouseInnerGap
$mouseCenterY = $mouseY + [int](($mouseButtonH - $mouseTile) / 2)

Add-LayoutKey 'LMB' $mouseX $mouseY $mouseButtonW $mouseButtonH 'Crimson'
Add-LayoutKey 'RMB' $mouseRightX $mouseY $mouseButtonW $mouseButtonH 'Crimson'

Add-LayoutKey 'WheelUp' $($mouseMiddleX + $mouseTile) $mouseY $mouseTile $mouseTile 'Crimson' 'S^'
Add-LayoutKey 'WheelLeft' $mouseMiddleX $mouseCenterY $mouseTile $mouseTile 'Crimson' 'S<'
Add-LayoutKey 'MMB' $($mouseMiddleX + $mouseTile) $mouseCenterY $mouseTile $mouseTile 'Crimson' 'MB'
Add-LayoutKey 'WheelRight' $($mouseMiddleX + (2 * $mouseTile)) $mouseCenterY $mouseTile $mouseTile 'Crimson' 'S>'
Add-LayoutKey 'WheelDown' $($mouseMiddleX + $mouseTile) $($mouseY + $mouseButtonH - $mouseTile) $mouseTile $mouseTile 'Crimson' 'Sv'

Add-LayoutKey 'Mouse4' $mouseX $($mouseY + $mouseButtonH + $mouseGap) 64 38 'Crimson'
Add-LayoutKey 'Mouse5' $mouseX $($mouseY + $mouseButtonH + $mouseGap + 44) 64 38 'Crimson'
#endregion ########## BUTTON CONFIG ##########

# region ~~~~~~~~~~ FUNCTIONS ~~~~~~~~~~
function Write-InputLog {
    param([string]$Message)

    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    if ($script:LogBox) {
        $script:LogBox.AppendText($line + [Environment]::NewLine)
        $script:LogBox.SelectionStart = $script:LogBox.Text.Length
        $script:LogBox.ScrollToCaret()
    }
}

function Send-KeyDown {
    param([int]$VK)
    [NativeInputSender]::KeyDown([uint16]$VK)
}

function Send-KeyUp {
    param([int]$VK)
    [NativeInputSender]::KeyUp([uint16]$VK)
}

function Send-KeyPress {
    param(
        [int]$VK,
        [int]$ReleaseDelay = 50
    )

    Send-KeyDown $VK
    Start-Sleep -Milliseconds ([Math]::Max(0, $ReleaseDelay))
    Send-KeyUp $VK
}

function Send-MouseDown {
    param([string]$Button)
    [NativeInputSender]::MouseButtonDown($Button)
}

function Send-MouseUp {
    param([string]$Button)
    [NativeInputSender]::MouseButtonUp($Button)
}

function Send-MouseClick {
    param(
        [string]$Button,
        [int]$ReleaseDelay = 50
    )

    Send-MouseDown $Button
    Start-Sleep -Milliseconds ([Math]::Max(0, $ReleaseDelay))
    Send-MouseUp $Button
}

function Send-Wheel {
    param(
        [ValidateSet('Vertical', 'Horizontal')]
        [string]$Axis,
        [int]$Delta
    )

    if ($Axis -eq 'Horizontal') {
        [NativeInputSender]::MouseHWheel($Delta)
    } else {
        [NativeInputSender]::MouseWheel($Delta)
    }
}

function Get-ExecutionMode {
    switch ($script:ModeSlider.Value) {
        0 { 'Press + Release' }
        1 { 'Press only' }
        2 { 'Release only' }
        default { 'Press + Release' }
    }
}

function Update-ConfigState {
    $mode = Get-ExecutionMode
    $script:ModeValueLabel.Text = $mode
    $script:ReleaseDelayInput.Enabled = ($mode -eq 'Press + Release')
    $script:ClickDelayInput.Enabled = $script:ClickDelayCheck.Checked
    $script:RepeatDelayInput.Enabled = $script:RepeatCheck.Checked
}

function Invoke-InputAction {
    param([string]$Label)

    if (-not $InputMap.ContainsKey($Label)) {
        Write-InputLog "No input map entry for '$Label'"
        return
    }

    if ($script:ClickDelayCheck.Checked) {
        Start-Sleep -Milliseconds ([int]$script:ClickDelayInput.Value)
    }

    $inputSpec = $InputMap[$Label]
    $mode = Get-ExecutionMode
    $releaseDelay = [int]$script:ReleaseDelayInput.Value

    try {
        switch ($inputSpec.Kind) {
            'Key' {
                switch ($mode) {
                    'Press only' { Send-KeyDown $inputSpec.VK }
                    'Release only' { Send-KeyUp $inputSpec.VK }
                    default { Send-KeyPress $inputSpec.VK $releaseDelay }
                }
            }
            'MouseButton' {
                switch ($mode) {
                    'Press only' { Send-MouseDown $inputSpec.Button }
                    'Release only' { Send-MouseUp $inputSpec.Button }
                    default { Send-MouseClick $inputSpec.Button $releaseDelay }
                }
            }
            'Wheel' {
                Send-Wheel $inputSpec.Axis $inputSpec.Delta
            }
        }

        Write-InputLog "Sent $Label ($mode)"
    } catch {
        Write-InputLog "FAILED $Label - $($_.Exception.Message)"
    }
}

function New-DarkLabel {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 160,
        [int]$Height = 22
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.ForeColor = [System.Drawing.Color]::White
    $label.BackColor = [System.Drawing.Color]::Black
    $label
}

function New-BorderedSection {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [System.Drawing.Color]$BorderColor
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Width, $Height)
    $panel.BackColor = [System.Drawing.Color]::Black
    $panel.Tag = $BorderColor
    $panel.Add_Paint({
        $pen = New-Object System.Drawing.Pen($this.Tag, 2)
        try {
            $rect = New-Object System.Drawing.Rectangle(0, 0, $($this.Width - 1), $($this.Height - 1))
            $_.Graphics.DrawRectangle($pen, $rect)
        } finally {
            $pen.Dispose()
        }
    })

    $label = New-DarkLabel $Text 10 6 $($Width - 20) 22
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $label.ForeColor = $BorderColor
    $panel.Controls.Add($label)

    $panel
}

function Set-NativeWindowIcon {
    param([System.Windows.Forms.Form]$Form)

    try {
        $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($processPath)
        if ($icon) {
            $Form.Icon = $icon
        }
    } catch {
        Write-Verbose "Could not load process icon: $($_.Exception.Message)"
    }
}

function New-TitleButton {
    param(
        [string]$Text,
        [int]$X
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $button.Location = New-Object System.Drawing.Point($X, 0)
    $button.Size = New-Object System.Drawing.Size(44, 32)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = [System.Drawing.Color]::DimGray
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $button.UseVisualStyleBackColor = $false
    $button
}

function New-InputButton {
    param([pscustomobject]$LayoutItem)

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $LayoutItem.Text
    $button.Location = New-Object System.Drawing.Point($LayoutItem.X, $LayoutItem.Y)
    $button.Size = New-Object System.Drawing.Size($LayoutItem.Width, $LayoutItem.Height)
    $button.BackColor = [System.Drawing.Color]::Black
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 2
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromName($LayoutItem.Color)
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $button.UseVisualStyleBackColor = $false

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 500
    $timer.Tag = $LayoutItem.Label
    $timer.Add_Tick({
        Invoke-InputAction -Label ([string]$sender.Tag)
    })

    $button.Tag = [pscustomobject]@{
        Label = $LayoutItem.Label
        Timer = $timer
    }

    $button.Add_MouseDown({
        if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
            return
        }

        $state = $this.Tag
        Invoke-InputAction -Label $state.Label

        if ($script:RepeatCheck.Checked) {
            $state.Timer.Interval = [Math]::Max(25, [int]$script:RepeatDelayInput.Value)
            $state.Timer.Start()
        }
    })

    $button.Add_MouseUp({
        $this.Tag.Timer.Stop()
    })

    $button.Add_MouseLeave({
        if (-not [System.Windows.Forms.Control]::MouseButtons.HasFlag([System.Windows.Forms.MouseButtons]::Left)) {
            $this.Tag.Timer.Stop()
        }
    })

    $button
}
#endregion ~~~~~~~~~~ FUNCTIONS ~~~~~~~~~~

# region @@@@@@@@@@ UI @@@@@@@@@@
[System.Windows.Forms.Application]::EnableVisualStyles()

# Section border colors live here so you can tweak the config panel quickly.
$ConfigBorderColors = @{
    DelayBeforeSend = [System.Drawing.Color]::DarkCyan
    ExecutionMode   = [System.Drawing.Color]::FromArgb(47,162,36)
    AutoRepeat      = [System.Drawing.Color]::SeaGreen
}

$TitleBarColor = [System.Drawing.Color]::FromArgb(66, 66, 66)
$ConfigPanelWidth = 270
$ConfigContentWidth = $ConfigPanelWidth - 22

$form = New-Object ResizableDarkForm
$form.Text = 'Input Sender'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1360, 700)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 500)
$form.BackColor = [System.Drawing.Color]::Black
$form.ForeColor = [System.Drawing.Color]::White
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.AutoScroll = $true
Set-NativeWindowIcon $form

$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock = [System.Windows.Forms.DockStyle]::Top
$titleBar.Height = 32
$titleBar.BackColor = $TitleBarColor
$titleBar.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        [NativeInputSender]::ReleaseCapture() | Out-Null
        [NativeInputSender]::SendMessage($form.Handle, [NativeInputSender]::WM_NCLBUTTONDOWN, [NativeInputSender]::HTCAPTION, 0) | Out-Null
    }
})
$form.Controls.Add($titleBar)

$iconBox = New-Object System.Windows.Forms.PictureBox
$iconBox.Location = New-Object System.Drawing.Point(9, 7)
$iconBox.Size = New-Object System.Drawing.Size(18, 18)
$iconBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
if ($form.Icon) {
    $iconBox.Image = $form.Icon.ToBitmap()
}
$titleBar.Controls.Add($iconBox)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = $form.Text
$titleLabel.Location = New-Object System.Drawing.Point(34, 6)
$titleLabel.Size = New-Object System.Drawing.Size(240, 21)
$titleLabel.ForeColor = [System.Drawing.Color]::Black
$titleLabel.BackColor = $TitleBarColor
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$titleLabel.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        [NativeInputSender]::ReleaseCapture() | Out-Null
        [NativeInputSender]::SendMessage($form.Handle, [NativeInputSender]::WM_NCLBUTTONDOWN, [NativeInputSender]::HTCAPTION, 0) | Out-Null
    }
})
$titleBar.Controls.Add($titleLabel)

$minButton = New-TitleButton '_' 1210
$maxButton = New-TitleButton ' []' 1255
$closeButton = New-TitleButton ' X' 1300
$closeButton.BackColor = [System.Drawing.Color]::FromArgb(96, 32, 32)
$minButton.Add_Click({ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized })
$maxButton.Add_Click({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    } else {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
    }
})
$closeButton.Add_Click({ $form.Close() })
$titleBar.Controls.Add($minButton)
$titleBar.Controls.Add($maxButton)
$titleBar.Controls.Add($closeButton)

$configPanel = New-Object System.Windows.Forms.Panel
$configPanel.Location = New-Object System.Drawing.Point(10, 48)
$configPanel.Size = New-Object System.Drawing.Size($ConfigPanelWidth, 645)
$configPanel.BackColor = [System.Drawing.Color]::Black
$configPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($configPanel)

$title = New-DarkLabel 'Configuration' 12 12 $($ConfigContentWidth - 12) 26
$title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$configPanel.Controls.Add($title)

$delaySection = New-BorderedSection 'Delay before send (ms)' 10 48 $ConfigContentWidth 96 $ConfigBorderColors.DelayBeforeSend
$configPanel.Controls.Add($delaySection)

$script:ClickDelayCheck = New-Object System.Windows.Forms.CheckBox
$script:ClickDelayCheck.Text = 'Enabled'
$script:ClickDelayCheck.Location = New-Object System.Drawing.Point(12, 34)
$script:ClickDelayCheck.Size = New-Object System.Drawing.Size(130, 24)
$script:ClickDelayCheck.ForeColor = [System.Drawing.Color]::White
$script:ClickDelayCheck.BackColor = [System.Drawing.Color]::Black
$delaySection.Controls.Add($script:ClickDelayCheck)

$script:ClickDelayInput = New-Object System.Windows.Forms.NumericUpDown
$script:ClickDelayInput.Location = New-Object System.Drawing.Point(12, 62)
$script:ClickDelayInput.Size = New-Object System.Drawing.Size(110, 22)
$script:ClickDelayInput.Minimum = 0
$script:ClickDelayInput.Maximum = 60000
$script:ClickDelayInput.Value = 0
$delaySection.Controls.Add($script:ClickDelayInput)

$modeSection = New-BorderedSection 'Execution mode' 10 158 $ConfigContentWidth 194 $ConfigBorderColors.ExecutionMode
$configPanel.Controls.Add($modeSection)

$script:ModeSlider = New-Object System.Windows.Forms.TrackBar
$script:ModeSlider.Location = New-Object System.Drawing.Point(8, 34)
$script:ModeSlider.Size = New-Object System.Drawing.Size($($ConfigContentWidth - 18), 45)
$script:ModeSlider.Minimum = 0
$script:ModeSlider.Maximum = 2
$script:ModeSlider.TickStyle = [System.Windows.Forms.TickStyle]::BottomRight
$script:ModeSlider.BackColor = [System.Drawing.Color]::Black
$script:ModeSlider.Value = 0
$modeSection.Controls.Add($script:ModeSlider)

$script:ModeValueLabel = New-DarkLabel 'Press + Release' 12 80 $($ConfigContentWidth - 24) 22
$script:ModeValueLabel.ForeColor = [System.Drawing.Color]::Gainsboro
$modeSection.Controls.Add($script:ModeValueLabel)

$releaseDelayLabel = New-DarkLabel 'Release delay (ms)' 12 116 $($ConfigContentWidth - 24) 22
$modeSection.Controls.Add($releaseDelayLabel)

$script:ReleaseDelayInput = New-Object System.Windows.Forms.NumericUpDown
$script:ReleaseDelayInput.Location = New-Object System.Drawing.Point(12, 140)
$script:ReleaseDelayInput.Size = New-Object System.Drawing.Size(110, 22)
$script:ReleaseDelayInput.Minimum = 0
$script:ReleaseDelayInput.Maximum = 60000
$script:ReleaseDelayInput.Value = 50
$modeSection.Controls.Add($script:ReleaseDelayInput)

$repeatSection = New-BorderedSection 'Auto-repeat' 10 366 $ConfigContentWidth 118 $ConfigBorderColors.AutoRepeat
$configPanel.Controls.Add($repeatSection)

$script:RepeatCheck = New-Object System.Windows.Forms.CheckBox
$script:RepeatCheck.Text = 'Auto-repeat while held'
$script:RepeatCheck.Location = New-Object System.Drawing.Point(12, 34)
$script:RepeatCheck.Size = New-Object System.Drawing.Size($($ConfigContentWidth - 24), 24)
$script:RepeatCheck.ForeColor = [System.Drawing.Color]::White
$script:RepeatCheck.BackColor = [System.Drawing.Color]::Black
$repeatSection.Controls.Add($script:RepeatCheck)

$repeatDelayLabel = New-DarkLabel 'Repeat delay (ms)' 12 62 $($ConfigContentWidth - 24) 22
$repeatSection.Controls.Add($repeatDelayLabel)

$script:RepeatDelayInput = New-Object System.Windows.Forms.NumericUpDown
$script:RepeatDelayInput.Location = New-Object System.Drawing.Point(12, 86)
$script:RepeatDelayInput.Size = New-Object System.Drawing.Size(110, 22)
$script:RepeatDelayInput.Minimum = 25
$script:RepeatDelayInput.Maximum = 60000
$script:RepeatDelayInput.Value = 150
$repeatSection.Controls.Add($script:RepeatDelayInput)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(10, 502)
$script:LogBox.Size = New-Object System.Drawing.Size($ConfigContentWidth, 126)
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 12)
$script:LogBox.ForeColor = [System.Drawing.Color]::Gainsboro
$script:LogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$configPanel.Controls.Add($script:LogBox)

$script:ModeSlider.Add_ValueChanged({ Update-ConfigState })
$script:ClickDelayCheck.Add_CheckedChanged({ Update-ConfigState })
$script:RepeatCheck.Add_CheckedChanged({ Update-ConfigState })

foreach ($item in $Layout) {
    $form.Controls.Add((New-InputButton $item))
}

Update-ConfigState
Write-InputLog 'Ready'

[void]$form.ShowDialog()
#endregion @@@@@@@@@@ UI @@@@@@@@@@
