Since these are PowerShell utilities you downloaded off the Internet - Windows WILL warn you/block them the first time you run them. You can use AI to analyze the .ps1 script and then compile the .exe yourself with the steps below. 

##### Exanima_SaveManager #####
This utility allows for making labeled backups of existing Exanima saves, and also for restoring/overwriting existing saves with those backups. Additionally, you can convert a Dungeon Save into a Checkpoint too, but you can only have one of these active per save file.
##########

##### Exanima_CursorConfig #####
This utility allows you to easily adjust your in-game cursor colors (for both Interaction and Combat modes) and size. 
##########

~~~ For the skeptics ~~~
If you're skeptical to run random PowerShell scripts - review the code or have an AI review it for you first, and compile the executable yourself.

To compile the .ps1 as .exe yourself, using PS2EXE: 
# Compile Exanima Save Manager
ps2exe "C:\Path\To\Exanima_SaveManager\Exanima_SaveManager.ps1" "C:\Path\To\Exanima_SaveManager\Exanima_SaveManager.exe" -title "Exanima Save Manager" -description "Backup/Restore/Convert save to checkpoint" -version 2 -requireAdmin -noConsole -DPIAware

# Compile Exanima Cursor Config
ps2exe "C:\Path\To\Exanima_SaveManager\Exanima_CursorConfig.ps1" "C:\Path\To\Exanima_SaveManager\Exanima_CursorConfig.exe" -title "Exanima Cursor Editor" -description "Change Interation/Combat cursor color & size." -version 2 -requireAdmin -noConsole -DPIAware

Just change the source path to match wherever you downloaded the .ps1 to, and the output to wherever you want the .exe saved to.

If you want the custom icons as well, download the .ico files, and append these arguments when you compile:
-iconFile "C:\Path\To\Exaniman.ico"
or
-iconFile "C:\Path\To\Exanicur.ico"


