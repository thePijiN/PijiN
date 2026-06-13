.        :       ...    :::::::-.   ...    ::: :::      :::.    :::::::..       .        :  .,:::::::::.    :::. ...    :::
;;,.    ;;;   .;;;;;;;.  ;;,   `';, ;;     ;;; ;;;      ;;`;;   ;;;;``;;;;      ;;,.    ;;; ;;;;''''`;;;;,  `;;; ;;     ;;;
[[[[, ,[[[[, ,[[     \[[,`[[     [[[['     [[[ [[[     ,[[ '[[,  [[[,/[[['      [[[[, ,[[[[, [[cccc   [[[[[. '[[[['     [[[
$$$$$$$$"$$$ $$$,     $$$ $$,    $$$$      $$$ $$'    c$$$cc$$$c $$$$$$c        $$$$$$$$"$$$ $$""""   $$$ "Y$c$$$$      $$$
888 Y88" 888o"888,_ _,88P 888_,o8P'88    .d888o88oo,.__888   888,888b "88bo,    888 Y88" 888o888oo,__ 888    Y8888    .d888
MMM  M'  "MMM  "YMMMMMP"  MMMMP"`   "YmmMMMM""""""YUMMMYMM   ""` MMMM   "W"     MMM  M'  "MMM""""YUMMMMMM     YM "YmmMMMM""

A modular menu-framework in Powershell. Make menus, and point them to whatever. It's got a lot of Windows-configuration functionality baked in by default. 

Compile the .ps1 as a .exe with this command, after modifying the source/destination/icon paths:
ps2exe C:\Path\To\ModularMenu.ps1 C:\Path\To\ModularMenu.exe -title "Modular Menu" -description "A menu framework made in PowerShell 5.1" -version 0.0.3 -iconFile C:\Path\To\ModularMenu.ico -requireAdmin -DPIAware