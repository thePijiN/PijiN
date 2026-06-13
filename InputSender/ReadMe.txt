8888888 888b    888 8888888b.  888     888 88888888888   Y88b           
  888   8888b   888 888   Y88b 888     888     888        Y88b          
  888   88888b  888 888    888 888     888     888         Y88b         
  888   888Y88b 888 888   d88P 888     888     888          Y88b        
  888   888 Y88b888 8888888P"  888     888     888          d88P        
  888   888  Y88888 888        888     888     888         d88P         
  888   888   Y8888 888        Y88b. .d88P     888        d88P          
8888888 888    Y888 888         "Y88888P"      888       d88P  88888888 
                                                                           
 .d8888b.  8888888888 888b    888 8888888b.  8888888888 8888888b.          
d88P  Y88b 888        8888b   888 888  "Y88b 888        888   Y88b         
Y88b.      888        88888b  888 888    888 888        888    888         
 "Y888b.   8888888    888Y88b 888 888    888 8888888    888   d88P         
    "Y88b. 888        888 Y88b888 888    888 888        8888888P"          
      "888 888        888  Y88888 888    888 888        888 T88b           
Y88b  d88P 888        888   Y8888 888  .d88P 888        888  T88b          
 "Y8888P"  8888888888 888    Y888 8888888P"  8888888888 888   T88b         
 
A PowerShell 5.1 WinForms application that renders a full virtual keyboard and mouse interface as a GUI, and when you click any button it fires the corresponding real input event to Windows via the `SendInput` API - so the OS treats it as genuine hardware input.
Use it to bind buttons you don't have, like F13-24, numpad, etc.

**What's under the hood:**

The C# inline type `NativeInputSender` handles all the low-level Win32 work - `SendInput` structs for both keyboard (`KEYBDINPUT`) and mouse (`MOUSEINPUT`), covering keys, mouse buttons, and scroll wheel in all four directions. `ResizableDarkForm` is a borderless form subclass that restores resize hit-testing that `FormBorderStyle.None` strips out.

The layout is entirely data-driven - `$Layout` is a list of `pscustomobject` entries built by `Add-LayoutKey` / `Add-Row`, each describing a button's label, position, size, and color. Adding or moving a key is a one-liner in that config section with no logic changes needed.

The config panel on the left exposes three behavioral modes:
- **Delay before send** - inserts an optional sleep before firing input, useful if the target app needs a moment
- **Execution mode** - a three-position slider toggling between press+release, hold-only, or release-only, with a configurable release delay
- **Auto-repeat** - holds a `System.Windows.Forms.Timer` that re-fires the action at a set interval for as long as the button is physically held down