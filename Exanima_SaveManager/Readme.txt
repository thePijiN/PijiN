To compile the .ps1 as .exe yourself, you can use PS2EXE just as I did: 
ps2exe "$env:USERPROFILE\Downloads\Exanima_SaveManager.ps1" "$env:USERPROFILE\Downloads\Exanima_SaveManager.exe" -title "Exanima Save Manager" -description "Backup/Restore/Convert save to checkpoint" -version 1 -requireAdmin -DPIAware

Just change the source path to match wherever you downloaded the .ps1 to, and the output to wherever you want the .exe saved to.

If you want the custom icon too, download the .ico file, and append these arguments when you compile:
-iconFile "$env:USERPROFILE\Downloads\Exaniman_resized.ico"