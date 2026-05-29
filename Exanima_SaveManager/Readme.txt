This utility allows for making labeled backups of existing Exanima saves, and also for restoring/overwriting existing saves with those backups. Additionally, you can convert a Dungeon Save into a Checkpoint too, but you can only have one of these active per save file.

If you're skeptical to run - review the code or have an AI review it for you first, and compile the executable yourself.

To compile the .ps1 as .exe yourself, using PS2EXE: 
ps2exe "$env:USERPROFILE\Downloads\Exanima_SaveManager.ps1" "$env:USERPROFILE\Downloads\Exanima_SaveManager.exe" -title "Exanima Save Manager" -description "Backup/Restore/Convert save to checkpoint" -version 1 -requireAdmin -noConsole -DPIAware

Just change the source path to match wherever you downloaded the .ps1 to, and the output to wherever you want the .exe saved to.

If you want the custom icon as well, download the .ico file, and append these arguments when you compile:
-iconFile "$env:USERPROFILE\Downloads\Exaniman_resized.ico"