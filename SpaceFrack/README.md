```text
   _____                       __________  ___   ________ __
  / ___/____  ____ _________  / ____/ __ \/   | / ____/ //_/
  \__ \/ __ \/ __ `/ ___/ _ \/ /_  / /_/ / /| |/ /   / ,<
 ___/ / /_/ / /_/ / /__/  __/ __/ / _, _/ ___ / /___/ /| |
/____/ .___/\__,_/\___/\___/_/   /_/ |_/_/  |_\____/_/ |_|
    /_/
```

# SpaceFRACK

A PowerShell 5.1 space-prospecting game about squeezing value out of hostile
planets, selling resources, buying supplies, completing contracts for upgrades,
and not dying in the process.

SpaceFRACK has two editions with the same gameplay and mechanics:

| File                | Edition             | Description
| `Spacegame.ps1`     | Terminal source     | Console menus, keyboard input, and ASCII art.
| `SpaceFrack.exe`    | Terminal executable | Packaged version of `Spacegame.ps1`.
| `SpaceFrack.ps1`    | UI source           | Mouse-driven WinForms interface and vector graphics.
| `SpaceFrack_UI.exe` | UI executable       | Packaged version of `SpaceFrack.ps1`.

Choose whichever interface you prefer. No install is required. 
Save files are created **manually** under `%APPDATA%`. 
The optional UI diagnostic log is stored there as well.

### For cautious pilots

Each edition is distributed as an inspectable `.ps1` and a compiled `.exe`. If
running a PowerShell script or an independently compiled executable makes you
wary, that is reasonable.

You can:

1. Inspect `Spacegame.ps1` for the Terminal Edition or `SpaceFrack.ps1` for the UI Edition.
2. Paste the relevant script into ChatGPT, Claude, or whatever and ask it
   to summarize what the script does and whether it touches files, network, or
   system settings, etc.
3. Build the matching `.exe` yourself from the reviewed `.ps1` using a PowerShell script
   compiler such as `ps2exe`.

# About

## The Three Big Numbers

Managing these three values is the key to not dying or getting stranded:

- `Health.` When this hits zero, that's the run. (Though you can Save/Load manually)
- `Fuel.` Travel, scanning, and survival all get awkward when this runs dry.
- `Weight.` Your cargo capacity has its limits.

All of which can be improved with upgrades from contracts, trading, or even fracking.

`CD` is currency. Use it to buy consumables, repair, refuel, and become more
powerful. Manage it wisely.

## Planets

Every planet has a `HZ` hazard rating, which approximates how often dangerous
events occur while prospecting. Higher hazard means more chances for the planet
to bite back.

Each planet also has:

- A unique resource pool.
- A list of possible hazards.
- Its own travel distance and conditions.
- Sometimes, a trader outpost.

Traders are essential for commerce. They buy resources, sell supplies and
upgrades, repair your ship, refuel your tanks, and hand out contracts.
Traders restock on the quarter hour, and their stock has weighted 
availability and quantity rolls.

Typhon is the harsher second system. It offers new resources, factions,
contracts, and upgrades - but is still currently WIP.

## The Loop

1. Frack planets to acquire materials.
2. Sell resources to trader outposts.
3. Buy consumables and upgrades.
4. Complete contracts for better rewards.
5. Explore the Sol system and beyond.

## Getting Started

Run either edition with PowerShell:

```powershell
# UI Edition
.\SpaceFrack.ps1

# Terminal Edition
.\Spacegame.ps1
```

Alternatively, launch `SpaceFrack_UI.exe` for the UI Edition or
`SpaceFrack.exe` for the Terminal Edition.

The repo also includes `SpaceFrackGuide.html`, a generated companion guide with
planet data, hazard math, resource tables, trader stock, and contract details.
Open it in a browser for a quick reference while playing for some insight.

If `Spacegame.ps1` changes, regenerate the guide with:

```powershell
.\generate-SpaceFrackGuide.ps1
```

You begin in Sol with a small ship, limited resources, and no reputation. 
Manage your `Health`, `Fuel`, `Weight`, and `Credits`, and frack strategically.

***Go forth and frack.***


## Some extra tips for you, Readme-Reader:
- Prune all but the latest save for each pilot by inputting Prune on the Load Menu.
- After installing the Shield Cell Auto-Injector, shield cells are auto-consumed when needed while fracking. Fuel cells are not.
- Cryo-Skipping can be utilized to skip the "idle" fracking mechanic, at the risk of HP depleting before FL does or WT capacity is reached.
- Use WT strategically to not 'bust' on a cryo-skip on riskier planets - just hope the juice is worth the squeeze.
- Fracking uninhabited Dwarf-class planets in Sol can yield upgrades.

### Terminal Edition shortcuts

- Append 'Q' to a sale selection to sell all of the selected item's quest surplus.
- You can press Q instead of C to view Your or a Trader's Contracts.
- Input `12` or `21` on the Trade Menu to both repair & refuel. 

### Vaguely related tips
- When compiling .ps1 as .exe via PS2EXE, to get the custom icon append args like: `-iconFile .\SpaceFrack.ico` 
- If you put an .exe file in `C:\Windows\System32` you can invoke it by name with Run (Win+R) for super-easy-access.

```text
                      ..-%@@@@%-.:                   
                @@@@@@@@@@@@@@@@@@@@%:               
             =%############%@.@@@@@@@@@#             
          .##.. ============.%@@@%+@@@@@@@#:         
        .#..==:-.------------.===.#####@@@@##        
       .#.=.--:.=============.--  .= *#######.       
      -# =---.==@###########==.  +.--.=.##+####      
      *- --.@@@############.   *====----:##*#-#      
      #=.-.@@@%#######         ####===---..#.=#.     
      =%=.:#@@@@@@##   #######   #####=.---.-#--+    
       +..@@#....@ #######@%##@   ####==----.-*.:    
       %=#.-------.%#####.-----  ##@%#+=----- :#:*   
       #.:+--------@@@.==----:  .---##%=-----.:..@@.@
       --.=-------@@@@=#=--:  -. .---*#.-----+#:#@.@@
       -.#=+-----@.-@###--- ---- ----+#------+::###@*
        .#@.==+.#:--:####.  ---- -  .##-----::..####%
       ####%#%###.---@##  @*:=-----. #%-----=.:#.%--:
      ..######+##.-:--@ #####@@@@@@% %#=..--#*-#--#-=
      .:#.====####--=--@###-#####-###   #=.-#+-#.--. 
      # -----:.##+.#--@##########:## ##:--##.#.-.    
    ..+..---- ###%#######@#=.=. -..+ =:--##.#*==@.   
      #===.--*+*##@%%%@#:@#-- ---+--=--.##=###+.##.  
      -#.==---.@:#.#=@.@. ++#+----==+--##.=#*##=:-.  
    .@:#.-=--:*%..#=%.%#.-.+=---%+@@@#..####@.+:     
      +@=*#-:-+=##.-# ###.%-==+.@@@@--:##.#####..    
      ..@#-##.==.=%##%%##. #####.--=@@%.###%-#+.     
      ==.@##=.############# --.##@@*:@@####.=+       
      #==.-- ########%%########.-.@@@@#%##.+         
       ==%.--------:...:---=%##+--:##.#==            
	                                           - PijiN
```

### Terminal Edition ASCII drill art

```text
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
```
