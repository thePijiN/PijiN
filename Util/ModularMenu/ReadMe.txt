.        :       ...    :::::::-.   ...    ::: :::      :::.    :::::::..       .        :  .,:::::::::.    :::. ...    :::
;;,.    ;;;   .;;;;;;;.  ;;,   `';, ;;     ;;; ;;;      ;;`;;   ;;;;``;;;;      ;;,.    ;;; ;;;;''''`;;;;,  `;;; ;;     ;;;
[[[[, ,[[[[, ,[[     \[[,`[[     [[[['     [[[ [[[     ,[[ '[[,  [[[,/[[['      [[[[, ,[[[[, [[cccc   [[[[[. '[[[['     [[[
$$$$$$$$"$$$ $$$,     $$$ $$,    $$$$      $$$ $$'    c$$$cc$$$c $$$$$$c        $$$$$$$$"$$$ $$""""   $$$ "Y$c$$$$      $$$
888 Y88" 888o"888,_ _,88P 888_,o8P'88    .d888o88oo,.__888   888,888b "88bo,    888 Y88" 888o888oo,__ 888    Y8888    .d888
MMM  M'  "MMM  "YMMMMMP"  MMMMP"`   "YmmMMMM""""""YUMMMYMM   ""` MMMM   "W"     MMM  M'  "MMM""""YUMMMMMM     YM "YmmMMMM""

A modular menu framework in PowerShell. Make menus and point them to whatever. It includes Windows configuration functionality by default.

The executable is built from Invoke-ModularMenu.ps1. That launcher downloads, validates, caches, and runs the latest ModularMenu.ps1 from the raw GitHub URL.

Compile the launcher after correcting the source, destination, and icon paths:
ps2exe C:\Path\To\Invoke-ModularMenu.ps1 C:\Path\To\ModularMenu.exe -title "Menu" -description "A menu framework made in PowerShell 5.1" -iconFile C:\Path\To\ModularMenu.ico -requireAdmin -DPIAware
