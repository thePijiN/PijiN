$SpacegameVersion = "0.0.4"

#region ~~~ Pre-Flight ~~~
$script:SpaceFrackLayoutWidth = 120
$script:SpaceFrackExeWindowPaddingColumns = 1
$script:SpaceFrackLaunchPath = $MyInvocation.MyCommand.Path

function Test-SpaceFrackExecutableHost {
    $launchExtension = ""
    try {
        if (-not [string]::IsNullOrWhiteSpace($script:SpaceFrackLaunchPath)) {
            $launchExtension = [System.IO.Path]::GetExtension($script:SpaceFrackLaunchPath).ToLowerInvariant()
        }
    } catch {}

    if ($launchExtension -eq ".exe") { return $true }

    try {
        $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([string]::IsNullOrWhiteSpace($processPath)) { return $false }

        $processName = [System.IO.Path]::GetFileNameWithoutExtension($processPath).ToLowerInvariant()
        if (@("powershell", "pwsh", "powershell_ise") -contains $processName) { return $false }

        return ([System.IO.Path]::GetExtension($processPath).ToLowerInvariant() -eq ".exe")
    } catch {}

    if ($launchExtension -eq ".ps1") { return $false }

    return $false
}

function Resize-SpaceFrackExecutableConsole {
    $targetWidth = $script:SpaceFrackLayoutWidth + $script:SpaceFrackExeWindowPaddingColumns

    try {
        $rawUi = $Host.UI.RawUI
        $maxWidth = $rawUi.MaxPhysicalWindowSize.Width
        if ($maxWidth -gt 0) {
            $targetWidth = [Math]::Min($targetWidth, $maxWidth)
        }
        if ($targetWidth -le 0) { return }

        $bufferSize = $rawUi.BufferSize
        if ($bufferSize.Width -lt $targetWidth) {
            $bufferSize.Width = $targetWidth
            $rawUi.BufferSize = $bufferSize
        }

        $windowSize = $rawUi.WindowSize
        if ($windowSize.Width -lt $targetWidth) {
            $windowSize.Width = $targetWidth
            $rawUi.WindowSize = $windowSize
        }
    } catch {}
}

function Clear-CurrentConsoleLine {
    try {
        $top = [Console]::CursorTop
        $clearWidth = $script:SpaceFrackLayoutWidth
        try {
            if ([Console]::BufferWidth -gt 1) {
                $clearWidth = [Math]::Min($clearWidth, [Console]::BufferWidth - 1)
            }
        } catch {}

        [Console]::SetCursorPosition(0, $top)
        [Console]::Write(" " * [Math]::Max(1, $clearWidth))
        [Console]::SetCursorPosition(0, $top)
    } catch {}
}

if (Test-SpaceFrackExecutableHost) {
    Resize-SpaceFrackExecutableConsole
}
Clear-Host
#endregion Pre-Flight

# region ##### GAME INITIALIZER #####
function Start-NewGame {
    # Set the global start time for the survival clock
    $global:GameStartTime = Get-Date

##### PLAYER #####
    $global:Player = @{
        Credits    = 350
        HP         = 100
		MaxHP	   = 100
        Fuel       = 100.0
        MaxFuel    = 100.0
		MaxWeight  = 100
		System	   = $null
        SaveName   = $null
        CreditsAcquired = 0
        TimeFracked = 0
        RealTimeFracked = 0
        TimeSlept = 0
        TimesSlept = 0
        AnimationMode = "Repaint"
        AnimationSpeed = 25
        Location   = "Mars"
        Dialog     = $null
		Message	   = $null
		Hyperdrive    = $null # Unlocked by acquiring HyperDrive Module upgrade; allows for inter-galactic travel
		frackGas       = 0 # Gas Giant Surveyor stacks; each stack reduces matching hazard frequency multiplicatively
		frackIce       = 0 # Ice Giant Surveyor stacks; each stack reduces matching hazard frequency multiplicatively
		frackTerr      = 0 # Terrain Hardening Kit stacks; each stack reduces matching hazard frequency multiplicatively
		frackAst       = 0 # Asteroid Surveyer stacks; each stack reduces matching hazard frequency multiplicatively
		frackDwarf     = 0 # Dwarf-Class Surveyor stacks; each stack reduces matching hazard frequency multiplicatively
		RadiationSuit = $null # Unlocked by acquiring Rad-Shielding Exosuit; 25% hazard reduction on any HZ >= 80 planet
		XRFScanner    = $null # Unlocked by acquiring XRF8 Scanner; reveals approximate resource composition from orbit
		CryoSkip      = $null # Unlocked by acquiring Cryo-Sleep Chamber; allows fast-forwarding prospecting sessions
		autoadminister = $false # Unlocked by acquiring Shield Cell Auto-Injector; allows shield cells to auto-administer while fracking
		Known      = [System.Collections.Generic.List[string]]@( "Sol", "Typhon", "Mars")
    }

    $global:Inventory = @{
		#"HeavyObject" = 1
        "Fuel Cell (Small)"   = 1
        "Shield Cell (Small)" = 1
		
		#"Gas Giant Surveyor"= 1
		#"Ice Giant Surveyor"= 1
		#"Terrain Hardening Kit"= 1
		#"Asteroid Surveyer"   = 1
		#"Dwarf-Class Surveyor"= 1
		#"Rad-Shielding Exosuit"= 1
		#"XRF8 Scanner"= 1
		#"Cryo-Sleep Chamber"= 1
		#"HyperDrive Module"     = 1
		
		#"Gold" = 1 # Rare
		#"Fossils" = 1 # SuperRare
		#"Promethium" = 1 # UltraRare
    }

    # Initialize/Reset the Trader State (Prevents persistence after death)
    $global:TraderState = @{}
	$global:QuestState  = @{}
	
	##### Values for Resources #####
	$global:ResourceMaster = @{
        # --- Resources ---
		# Debug
		"HeavyObject"      = @{ Value = 1000; Weight = 999; Rarity = "SuperRare"; Description = "Shit's heavy."; Consumable = $false }

        # SuperCommon
        "Silicates"        = @{ Value = 3;  Weight = .5; Rarity = "SuperCommon"; Description = "Raw silicate minerals."; Consumable = $false }
        "Carbon"           = @{ Value = 4;  Weight = 1;  Rarity = "SuperCommon"; Description = "Compressed carbon mass."; Consumable = $false }
        "Water"            = @{ Value = 5;  Weight = 1;  Rarity = "SuperCommon"; Description = "Frozen H2O blocks."; Consumable = $false }
        "Oxygen"           = @{ Value = 6;  Weight = 1;  Rarity = "SuperCommon"; Description = "Oxygen canisters."; Consumable = $false }
		"Iron"             = @{ Value = 8;  Weight = 1;  Rarity = "SuperCommon"; Description = "Raw iron ore."; Consumable = $false }

        # Common
        "Hydrogen"         = @{ Value = 12; Weight = 1;  Rarity = "Common"; Description = "Hydrogen gas cylinders."; Consumable = $false }
		"Nitrogen"         = @{ Value = 13; Weight = 1;  Rarity = "Common"; Description = "Compressed nitrogen canisters."; Consumable = $false }
		"Magnesium"        = @{ Value = 14; Weight = 1;  Rarity = "Common"; Description = "Raw magnesium ore."; Consumable = $false }
		"Calcium"          = @{ Value = 16; Weight = 1;  Rarity = "Common"; Description = "Raw calcium minerals."; Consumable = $false }
		"Aluminum"         = @{ Value = 18; Weight = 1;  Rarity = "Common"; Description = "Raw aluminum ore."; Consumable = $false }
        "Sulfur"           = @{ Value = 20; Weight = .5; Rarity = "Common"; Description = "Crystalline sulfur."; Consumable = $false }
		"ScrapMetal"       = @{ Value = 22; Weight = 2;  Rarity = "Common"; Description = "Salvaged hull plating."; Consumable = $false }
		"Zinc"             = @{ Value = 24; Weight = 1;  Rarity = "Common"; Description = "Raw zinc ore."; Consumable = $false }
		"Tin"              = @{ Value = 28; Weight = 1;  Rarity = "Common"; Description = "Raw tin ore."; Consumable = $false }
		"Copper"           = @{ Value = 30; Weight = 1;  Rarity = "Common"; Description = "Raw copper ore."; Consumable = $false }

        # Uncommon
		"Silicon"          = @{ Value = 35; Weight = 1; Rarity = "Uncommon"; Description = "Refined silicon-bearing ore."; Consumable = $false }
		"Nickel"           = @{ Value = 40; Weight = 1; Rarity = "Uncommon"; Description = "Raw nickel ore."; Consumable = $false }
        "Biomass"          = @{ Value = 42; Weight = 1; Rarity = "Uncommon"; Description = "Organic matter samples."; Consumable = $false }
		"Boron"            = @{ Value = 45; Weight = 1; Rarity = "Uncommon"; Description = "Boron-rich mineral samples."; Consumable = $false }
		"Argon"            = @{ Value = 50; Weight = 1; Rarity = "Uncommon"; Description = "Argon gas cylinders."; Consumable = $false }
		"Neon"             = @{ Value = 60; Weight = 1; Rarity = "Uncommon"; Description = "Neon gas cylinders."; Consumable = $false }

		# Rare
		"Helium"           = @{ Value = 75;  Weight = 1; Rarity = "Rare"; Description = "Helium gas cylinders."; Consumable = $false }
		"Silver"           = @{ Value = 100; Weight = 1; Rarity = "Rare"; Description = "Raw silver ore. (Shiny!)"; Consumable = $false }
		"Tungsten"         = @{ Value = 220; Weight = 2; Rarity = "Rare"; Description = "Dense tungsten ore."; Consumable = $false }
		"Uranium"          = @{ Value = 150; Weight = 1; Rarity = "Rare"; Description = "Raw uranium ore. (Spicy!)"; Consumable = $false }
		"Radium"           = @{ Value = 175; Weight = 1; Rarity = "Rare"; Description = "Radioactive radium-bearing material."; Consumable = $false }
		"Deuterium"        = @{ Value = 180; Weight = 1; Rarity = "Rare"; Description = "Heavy hydrogen fuel stock."; Consumable = $false }
		"Warship Alloy"    = @{ Value = 160; Weight = 2; Rarity = "Rare"; Description = "Recovered military hull alloy."; Consumable = $false }
		"Platinum"         = @{ Value = 220; Weight = 1; Rarity = "Rare"; Description = "Raw platinum ore."; Consumable = $false }
		"Gold"			   = @{ Value = 250; Weight = 1; Rarity = "Rare"; Description = "Raw gold ore. (We're rich!)"; Consumable = $false }

		# SuperRare
		"MetallicHydrogen" = @{ Value = 260; Weight = 2.5; Rarity = "SuperRare"; Description = "Highly pressurized fuel precursor."; Consumable = $false }
		"Fossils"		   = @{ Value = 300; Weight = 1.5; Rarity = "SuperRare"; Description = "Unknown fossilized alien lifeform."; Consumable = $false }
		"Plutonium"        = @{ Value = 350; Weight = 1; Rarity = "SuperRare"; Description = "Weapons-grade bad idea."; Consumable = $false }
		"Neptunium"        = @{ Value = 400; Weight = 1; Rarity = "SuperRare"; Description = "Rare neptunium-bearing material."; Consumable = $false }
		"Mythril"          = @{ Value = 200; Weight = 1.5; Rarity = "SuperRare"; Description = "Raw Mythril ore. (Sturdy!)"; Consumable = $false }
		"Helium-3"         = @{ Value = 475; Weight = 1; Rarity = "SuperRare"; Description = "Rare helium isotope for advanced reactors."; Consumable = $false }
		"Cryophane"        = @{ Value = 425; Weight = 1.5; Rarity = "SuperRare"; Description = "Cold-stable crystalline volatile."; Consumable = $false }
		"Ordnance Core"    = @{ Value = 360; Weight = 1.5; Rarity = "SuperRare"; Description = "Recovered live munitions core."; Consumable = $false }

		# UltraRare
		"Promethium"       = @{ Value = 500; Weight = 1; Rarity = "UltraRare"; Description = "Unstable promethium samples."; Consumable = $false }
		"Tantalum Hafnium Carbide" = @{ Value = 525; Weight = 1; Rarity = "UltraRare"; Description = "As heat-resistant as it gets."; Consumable = $false }
		"Pyrestone"        = @{ Value = 650; Weight = 1; Rarity = "UltraRare"; Description = "Star-baked refractory crystal."; Consumable = $false }
		"Iridium"          = @{ Value = 750; Weight = 1; Rarity = "UltraRare"; Description = "Extremely rare iridium ore."; Consumable = $false }

		# Artifact
		"Republic Flight Recorder" = @{ Value = 1500; Weight = 1; Rarity = "Artifact"; Description = "Encrypted Republic combat recorder."; Consumable = $false }

        # --- Consumables ---
        "Fuel Cell (Small)" 	= @{ Value = 150;  Weight = .5; Rarity = "Consumable";  Consumable = $true; Effect = "Fuel"; EffectValue = 50.0 ; Description = "A small fuel cell.";  UseMessage = "+50.0 Fuel" }
		"Fuel Cell (Medium)"	= @{ Value = 300;  Weight = 1; Rarity = "Consumable";  Consumable = $true; Effect = "Fuel"; EffectValue = 100.0 ; Description = "A medium fuel cell.";  UseMessage = "+100.0 Fuel" }
		"Fuel Cell (Large)"		= @{ Value = 500; Weight = 2; Rarity = "Consumable";  Consumable = $true; Effect = "Fuel"; EffectValue = 200.0 ; Description = "A large fuel cell.";  UseMessage = "+200.0 Fuel" }
		"Bastion Fuel Cell"		= @{ Value = 1000; Weight = 3; Rarity = "Consumable";  Consumable = $true; Effect = "Fuel"; EffectValue = 400.0 ; Description = "A Republic Armada fuel cell.";  UseMessage = "+400.0 Fuel" }
        "Shield Cell (Small)"   = @{ Value = 100;  Weight = .5; Rarity = "Consumable";  Consumable = $true; Effect = "HP"; EffectValue = 50 ; Description = "A small shield recharge cell."; UseMessage = "+50 HP" }
		"Shield Cell (Medium)"  = @{ Value = 200; Weight = 1; Rarity = "Consumable";  Consumable = $true; Effect = "HP"; EffectValue = 100 ; Description = "A medium shield recharge cell."; UseMessage = "+100 HP" }
        "Shield Cell (Large)"   = @{ Value = 375; Weight = 2; Rarity = "Consumable";  Consumable = $true; Effect = "HP"; EffectValue = 200 ; Description = "A large shield recharge cell."; UseMessage = "+200 HP" }
		"Bastion Shield Cell"   = @{ Value = 750; Weight = 2; Rarity = "Consumable";  Consumable = $true; Effect = "HP"; EffectValue = 500 ; Description = "A Republic Armada shield recharge cell."; UseMessage = "+500 HP" }

        # --- Upgrades ---
		# Stat Boosters
        "Cargo Baffles"    				= @{ Value = 600;  Weight = 0; Rarity = "Upgrade";     Description = "Optimized storage racks.";   Consumable = $true; Effect = "MaxWeight"; EffectValue = 50 }
		"Premium Cargo Baffles" 		= @{ Value = 1200; Weight = 0; Rarity = "Upgrade";     Description = "Superbly optimized storage racks."; Consumable = $true; Effect = "MaxWeight"; EffectValue = 100 }
		"Auxiliary Fuel Tank"  			= @{ Value = 750;  Weight = 0; Rarity = "Upgrade";     Description = "Additional fuel capacity.";  Consumable = $true; Effect = "MaxFuel"; EffectValue = 50.0; UseMessage = "+50.0 MaxFuel" }
		"Deluxe Auxiliary Fuel Tank"  	= @{ Value = 1400; Weight = 0; Rarity = "Upgrade";     Description = "Additional fuel capacity.";  Consumable = $true; Effect = "MaxFuel"; EffectValue = 100.0; UseMessage = "+100.0 MaxFuel" }
		"U.C.E. Shield Generator MK I"  = @{ Value = 1000; Weight = 0; Rarity = "Upgrade";    Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 25 }
		"U.C.E. Shield Generator MK II" = @{ Value = 2000; Weight = 0; Rarity = "Upgrade";    Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 50 }
		"U.C.E. Shield Generator MK III"= @{ Value = 3000; Weight = 0; Rarity = "Upgrade";    Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 75 }
		"FFF Shield Generator"    = @{ Value = 4000; Weight = 0; Rarity = "Upgrade";    Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 100 }
		"Bastion Shield Generator"= @{ Value = 8000; Weight = 0; Rarity = "Upgrade";  Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 200 }
		# Hazard-Reduction Gadgets
		"Gas Giant Surveyor"  	= @{ Value = 3000; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Gas Giants.";          Consumable = $true; Effect = "frackGas";       EffectValue = 1; HazardReduction = @{ "Gas Giant"    = 0.50 } }
		"Ice Giant Surveyor"  	= @{ Value = 4000; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Ice Giants.";          Consumable = $true; Effect = "frackIce";       EffectValue = 1; HazardReduction = @{ "Ice Giant"    = 0.50 } }
		"Terrain Hardening Kit" = @{ Value = 2500; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Terrestrial planets."; Consumable = $true; Effect = "frackTerr";      EffectValue = 1; HazardReduction = @{ "Terrestrial"  = 0.20 } }
		"Asteroid Surveyer"     = @{ Value = 2000; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Asteroid bodies.";     Consumable = $true; Effect = "frackAst";       EffectValue = 1; HazardReduction = @{ "Asteroid"     = 0.50 } }
		"Dwarf-Class Surveyor"  = @{ Value = 1500; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Dwarf-class planets."; Consumable = $true; Effect = "frackDwarf";     EffectValue = 1; HazardReduction = @{ "Dwarf"        = 0.30 } }
		"Rad-Shielding Exosuit" = @{ Value = 6000; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards by 25% on HZ80+ planets.";Consumable = $true; Effect = "RadiationSuit";  EffectValue = 1; HazardThreshold = 80; HazardReduction = @{ "_threshold" = 0.25 } }
		# Abilities
		"Shield Cell Auto-Injector" = @{ Value = 1500; Weight = 1; Rarity = "Upgrade"; Description = ""; Consumable = $true; Effect = "autoadminister"; EffectValue = 1; UseMessage = "Shield cell auto-injection online" }
		"XRF8 Scanner"          = @{ Value = 3500; Weight = 3; Rarity = "Upgrade"; Description = "Approximate resources from orbit.";       Consumable = $true; Effect = "XRFScanner";     EffectValue = 1 }
		"Cryo-Sleep Chamber"    = @{ Value = 4500; Weight = 3; Rarity = "Upgrade"; Description = "Only operates in 1 year increments...";   Consumable = $true; Effect = "CryoSkip";       EffectValue = 1 }
		"HyperDrive Module"     = @{ Value = 5000; Weight = 5; Rarity = "Upgrade"; Description = "Enables interstellar travel.";            Consumable = $true; Effect = "Hyperdrive";     EffectValue = 1 }
	}
	
	##### Damage multipliers for Hazards #####
	$global:HazardMaster = @{
		# Universal / Low Severity
		"Hull stress"                = 0.75
		"Micro-vibrations"           = 0.9
		"Static discharge"           = 1.2
		"Atmospheric turbulence"     = 1.4

		# Moderate Severity
		"Gravity well shear"         = 2.0
		"Dust storm abrasion"        = 1.6
		"Tectonic shift"			 = 1.9
		"Solar flare radiation"      = 2.5
		"Acid rain corrosion"        = 2.7
		"Extreme cold stress"        = 2.8
		"Meteoroid bombardment"      = 1.4 
		"Micrometeor swarm"          = 1.7

		# High Severity
		"Tectonic plate collapse"	 = 3.4
		"Methane pressure spike"     = 3.4
		"Supersonic wind shear"      = 4.2
		"Cryo-geyser eruption"       = 4.7
		"Lightning discharge"        = 4.6
		"Ring shard impact"          = 5.8
		"Thermal shock cycling"      = 3.0
		"Coronal particle surge"     = 3.4
		"Sulfuric acid deluge"       = 3.1
		"Runaway greenhouse pressure"= 3.6
		"Debris field collision"     = 4.8
		
		# Catastrophic Severity
		"Magma spray"                = 6.0
		"Extreme Lightning discharge"= 8.5
		"Asteroid impact"			 = 7.8
		"Super-cyclone vortex"       = 9.0
		"Deep pressure crush"        = 6.0
		"Cryovolcanic ejecta"        = 5.5
		
		# Cataclysmic Severity
		"Fission Event"				 = 10
		"Ion cannon blast"           = 8.0
		"Magnetosphere flux storm"   = 12.0
		"Diamond Rain Ballistic Impact"= 14.2
		"Gamma ray exposure"		 = 18
		"Critical gamma ray exposure"= 30
		"Singularity"				 = 1000

		# Typhon War Events
		"Stray projectile"           = 6.0
		"EMP pulse"                  = 7.0
		"Orbital mine detonation"    = 9.5
		"Hull breach"                = 12.6
		"Gatling barrage"            = 16.0
		"Missile volley"             = 18.0
		"Torpedo strike"             = 20.0
		"Flak cloud"                 = 11.5
		"Live ordnance ping"         = 14.0
		"Railgun graze"              = 16.0
		"Drone strafing run"         = 12.0
		"Munitions detonation"       = 24.6
		
		# Typhon Env Events
		"Plasma lash"                = 24.0
		"Photospheric blowout"       = 28.0
		"Cryowake rupture"           = 17.0
		"Auroral arc flash"          = 15.0
		"Hydrogen pressure inversion"= 22.0
		"Basalt flood wave"          = 18.0
		"Crustal foundering"         = 23.0
		"Mantle plume rupture"       = 30.0
		"Dust-glass abrasion"        = 7.5
		"Regolith shear front"       = 9.4
		"Static ashfall"             = 6.2
	}

    # Define rarity order for sorting logic
    $global:RarityOrder = @{
        "SuperCommon" = 1
        "Common"      = 2
        "Uncommon"    = 3
        "Rare"        = 4
        "SuperRare"   = 5
        "UltraRare"   = 6
        "Artifact"    = 7
        "Oddity"      = 8
        "Consumable"  = 9
        "Upgrade"     = 10
    }

	$global:SolSystem = @{
		_Metadata = @{ Id = "Sol"; Name = "The Sol System"; Color = "Green" }
		Mercury  = @{
			Distance = 0; Inhabited = $false; Type = "Terrestrial"; Danger = 8.3; PlanetColor = "DarkYellow"
			Description = "Sun-blasted rock with heavy metal seams."
			Resources = @{ "Iron" = 100; "Nickel" = 120; "Copper" = 45; "Sulfur" = 120; "Silicates" = 60; "Silicon" = 70; "Tungsten" = 90; "Silver" = 45; "Gold" = 70; "Uranium" = 35; "Radium" = 32; "Platinum" = 30; "Iridium" = 2; "Carbon" = 20; "Oxygen" = 20; "Hydrogen" = 20; "Helium" = 10; "Neon" = 8; "Argon" = 8; "MetallicHydrogen" = 3; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Thermal shock cycling", "Solar flare radiation", "Magma spray", "Tectonic plate collapse", "Coronal particle surge")
		}
		Venus    = @{
			Distance = 4.5; Inhabited = $false; Type = "Terrestrial"; Danger = 4.2; PlanetColor = "Yellow"
			Description = "Acid clouds over jagged, reactive beds."
			Resources = @{ "Sulfur" = 240; "Carbon" = 90; "Oxygen" = 73; "Boron" = 145; "Silicon" = 130; "Calcium" = 45; "Magnesium" = 45; "Copper" = 85; "Nickel" = 105; "Silver" = 92; "Gold" = 32; "Platinum" = 16; "Nitrogen" = 22; "Uranium" = 8; "Radium" = 6; "Argon" = 10; "Neon" = 6; "Hydrogen" = 8; "Helium" = 2; "MetallicHydrogen" = 1; "U.C.E. Shield Generator MK I" = 1}
			HazardReasons = @("Static discharge", "Atmospheric turbulence", "Acid rain corrosion", "Sulfuric acid deluge", "Runaway greenhouse pressure", "Tectonic plate collapse")
		}
		Earth    = @{
			Distance = 8.5; Inhabited = $true; Type = "Terrestrial"; Danger = 1.2; PlanetColor = "DarkGreen"
			Description = "Blue cradle ringed by U.C.E. traffic."
			Resources = @{ "Water" = 260; "Carbon" = 180; "Oxygen" = 150; "ScrapMetal" = 150; "Silicates" = 90; "Iron" = 70; "Biomass" = 60; "Nitrogen" = 25; "Hydrogen" = 8; "Argon" = 5; "Neon" = 2; "Copper" = 15; "Nickel" = 8; "Zinc" = 6; "Aluminum" = 11; "Tin" = 4; "Sulfur" = 4; "Uranium" = 1; "Fossils" = 1; "Helium" = 3; "Silver" = 5; "Gold" = 2 }
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "Atmospheric turbulence", "Tectonic shift")
			TraderName = "U.C.E.O.C.S."; TotalTraderCredits = 5000; FuelModifier = 1.3; RepairModifier = 1.4
			Dialog = @{
				Greeting = @(
					"Welcome to United Countries of Earth Orbital Commerce Services. Your compliance makes prosperity possible."
					"U.C.E.O.C.S. transaction window open. Smile for the scanner."
					"Welcome back to Earth orbit. Please have your credits ready."
					"Orbital commerce services are currently experiencing expected delays."
				)
				TradeGreeting = @(
					"How may I assist you today, valued independent contractor?"
					"Buy, sell, repair, refuel. The menu has not changed since you looked at it."
					"What can the United Countries of Earth do to you today?"
					"May I take your order?"
				)
				Refuel = @(
					"Topped up. Try not to make that our problem again."
					"Fuel transfer complete. I noticed you didn't tip..."
					"Tank is full. Tip?"
				)
				Repair = @(
					"Structural integrity restored. Mostly."
					"Repairs processed. The hull is now legally spaceworthy."
					"Damage patched... Oh that? That's not covered under our policy."
				)
				Trade = @(
					"Credits transferred. It should post in 3-5 business days."
					"Transaction complete. We value your business."
					"Trade logged. Procurement will pretend this was planned."
				)
				InsufficientFunds = @(
					"Transaction declined. Credits aren't optional."
					"Insufficient funds. We don't barter here."
					"Your balance has failed the patriotism check."
				)
				InsufficientFundsTrader = @(
					"You have exceeded our budget for your cargo."
					"Procurement budget exhausted. Try a less important window."
					"The U.C.E. declines to buy that much reality at once."
				)
				Frustrated = @(
					"What? No."
					"We don't do that here."
					"Security, we may have an incident."
				)
			}
			TraderStock = @{
				"Fuel Cell (Small)" = @{ Chance = 75; MinQty = 0; MaxQty = 7 }
				"Fuel Cell (Medium)" = @{ Chance = 85; MinQty = 0; MaxQty = 5 }
				"Shield Cell (Small)" = @{ Chance = 75; MinQty = 0; MaxQty = 6 }
				"Shield Cell (Medium)" = @{ Chance = 75; MinQty = 0; MaxQty = 4 }
				"Cargo Baffles" = @{ Chance = 10; MinQty = 1; MaxQty = 1; DoubleChance = 2 }
				"Auxiliary Fuel Tank" = @{ Chance = 60; MinQty = 1; MaxQty = 1; DoubleChance = 2 }
				"Deluxe Auxiliary Fuel Tank" = @{ Chance = 5; MinQty = 0; MaxQty = 1; DoubleChance = 1 }
				"U.C.E. Shield Generator MK I" = @{ Chance = 80; MinQty = 1; MaxQty = 1; DoubleChance = 6 }
				"U.C.E. Shield Generator MK II" = @{ Chance = 15; MinQty = 1; MaxQty = 1; DoubleChance = 3 }
				"U.C.E. Shield Generator MK III" = @{ Chance = 5; MinQty = 1; MaxQty = 1; DoubleChance = 1 }
				"Iridium" = @{ Chance = 2; MinQty = 0; MaxQty = 1; DoubleChance = 5 }
			}
			Quests = @(
				@{
					Id = "earth_1"; Name = "Permit Pending"; RepReq = 0
					Desc = "Your U.C.E. Fracking Permit is under review. Premium processing accepts gold and silver."
					Requirements = @(@{ Item = "Gold"; Qty = 1 }; @{ Item = "Silver"; Qty = 5 })
					RewardCD = 500; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK I"; Qty = 1 })
				}
				@{
					Id = "earth_2"; Name = "Strategic Reserve Expansion"; RepReq = 1
					Desc = "Earthside reserves need off-world iron, copper, and silver stock."
					Requirements = @(
						@{ Item = "Iron"; Qty = 30 }
						@{ Item = "Copper"; Qty = 25 }
						@{ Item = "Silver"; Qty = 10 }
					)
					RewardCD = 500; RewardItems = @(@{ Item = "Cargo Baffles"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK I"; Qty = 1 })
				}
				@{
					Id = "earth_3"; Name = "A Silicate Matter"; RepReq = 2
					Desc = "Orbital construction needs bulk feedstock. Ceres has the boring minerals they love."
					Requirements = @(
						@{ Item = "Silicates"; Qty = 120 }
						@{ Item = "Aluminum"; Qty = 25 }
						@{ Item = "Zinc"; Qty = 20 }
						@{ Item = "Tin"; Qty = 20 }
					)
					RewardCD = 2500; RewardItems = @(@{ Item = "Auxiliary Fuel Tank"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK II"; Qty = 1 })
				}
				@{
					Id = "earth_4"; Name = "Special Materials Contract"; RepReq = 3
					Desc = "Energy research needs hot isotopes and sulfur. Mercury has the useful glow."
					Requirements = @(@{ Item = "Uranium"; Qty = 5 }; @{ Item = "Radium"; Qty = 3 }; @{ Item = "Sulfur"; Qty = 20 })
					RewardCD = 2500; RewardItems = @(@{ Item = "Ice Giant Surveyor"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK II"; Qty = 1 })
				}
				@{
					Id = "earth_5"; Name = "A Noble Endeavor"; RepReq = 3
					Desc = "Atmospheric Services needs noble gases at volume. Larger worlds are approved."
					Requirements = @(
						@{ Item = "Helium"; Qty = 30 }
						@{ Item = "Neon"; Qty = 30 }
						@{ Item = "Argon"; Qty = 30 }
					)
					RewardCD = 1000; RewardItems = @(@{ Item = "Cargo Baffles"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK III"; Qty = 1 })
				}
				@{
					Id = "earth_6"; Name = "Project Horizon"; RepReq = 4
					Desc = "High-pressure fuel work needs giant-world samples and dense catalysts."
					Requirements = @(@{ Item = "MetallicHydrogen"; Qty = 25 }; @{ Item = "Platinum"; Qty = 3 }; @{ Item = "Tungsten"; Qty = 5 })
					RewardCD = 0; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK II"; Qty = 1 }; @{ Item = "Terrain Hardening Kit"; Qty = 1 })
				}
				@{
					Id = "earth_7"; Name = "Ring Audit"; RepReq = 5
					Desc = "Saturn ring shipments are not matching invoices. Recover gas stock and salvage metal."
					Requirements = @(
						@{ Item = "Neon"; Qty = 50 }
						@{ Item = "Argon"; Qty = 60 }
						@{ Item = "Silver"; Qty = 15 }
						@{ Item = "ScrapMetal"; Qty = 20 }
					)
					RewardCD = 2000; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 2 }; @{ Item = "Shield Cell (Large)"; Qty = 2 })
				}
				@{
					Id = "earth_8"; Name = "Gaseous Venture"; RepReq = 6
					Desc = "Procurement needs bulk gas. Jupiter or Saturn can meet volume if you can meet risk."
					Requirements = @(
						@{ Item = "Hydrogen"; Qty = 150 }
						@{ Item = "Helium"; Qty = 100 }
						@{ Item = "Nitrogen"; Qty = 75 }
						@{ Item = "MetallicHydrogen"; Qty = 15 }
					)
					RewardCD = 1000; RewardItems = @(@{ Item = "Premium Cargo Baffles"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK III"; Qty = 1 })
				}
			)
		}
		Mars     = @{
			Distance = 13; Inhabited = $true; Type = "Terrestrial"; Danger = 1.0; PlanetColor = "DarkRed"
			Description = "Red dust deserts cut by iron-rich seams."
			Resources = @{ "Silicates" = 260; "Iron" = 210; "Carbon" = 120; "Oxygen" = 90; "Water" = 80; "ScrapMetal" = 70; "Magnesium" = 45; "Calcium" = 35; "Aluminum" = 35; "Sulfur" = 10; "Copper" = 15; "Zinc" = 8; "Tin" = 6; "Nickel" = 5; "Silicon" = 4; "Boron" = 2; "Nitrogen" = 4; "Hydrogen" = 4; "Argon" = 2; "Neon" = 1; "Helium" = 1; "Silver" = 5; "Biomass" = 20}
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "Dust storm abrasion", "Tectonic shift")
			TraderName = "Martian Colony"; TotalTraderCredits = 3000; FuelModifier = 1.1; RepairModifier = 1.2
			Dialog = @{
				Greeting = @(
					"Welcome back, scrapper."
					"Mars tower has you on approach. Dock easy."
					"Colony market is open. Mind the dust seals."
					"Back from the black? Good. We could use the business."
				)
				TradeGreeting = @(
					"What'll it be this time?"
					"Need fuel, patches, or here to trade?"
					"If it keeps a hull flying, we'll talk."
					"Let's see what you've hauled in."
				)
				Refuel = @(
					"Fuel's pumpin'."
					"Tanks topped. Keep some in reserve."
					"Fuel transfer done. No leaks on our side."
				)
				Repair = @(
					"Hull patched."
					"We sealed the worst of it. Watch the stress marks."
					"Repairs done. She's ugly, but she'll hold."
				)
				Trade = @(
					"Pleasure doin' business."
					"Credits sent. Cargo logged."
					"Good haul. Colony can use it."
				)
				InsufficientFunds = @(
					"Credits first, hero."
					"Can't run a colony on promises."
					"You're short. Happens."
				)
				InsufficientFundsTrader = @(
					"And what'll ya be wanting for that?"
					"We can't cover that much cargo right now."
					"Colony till is light. Come back after restock."
				)
				Frustrated = @(
					"Come again, now?"
					"That doesn't help either of us."
					"Slow down and try again."
				)
			}
			TraderStock = @{
				"Fuel Cell (Small)" = @{ Chance = 90; MinQty = 0; MaxQty = 5 }
				"Fuel Cell (Medium)" = @{ Chance = 75; MinQty = 0; MaxQty = 3 }
				"Shield Cell (Small)" = @{ Chance = 90; MinQty = 0; MaxQty = 3 }
				"Shield Cell (Medium)" = @{ Chance = 75; MinQty = 0; MaxQty = 2 }
				"Cargo Baffles" = @{ Chance = 70; MinQty = 1; MaxQty = 1; DoubleChance = 6 }
				"Premium Cargo Baffles" = @{ Chance = 4; MinQty = 1; MaxQty = 1; DoubleChance = 2 }
				"Auxiliary Fuel Tank" = @{ Chance = 60; MinQty = 1; MaxQty = 1; DoubleChance = 7 }
				"Deluxe Auxiliary Fuel Tank" = @{ Chance = 2; MinQty = 1; MaxQty = 1; DoubleChance = 2 }
				"Iridium" = @{ Chance = 1; MinQty = 0; MaxQty = 1; DoubleChance = 5 }
			}
			Quests = @(
				@{
					Id = "mars_1"; Name = "Dust and Rust"; RepReq = 0
					Desc = "Iron is always in demand, and lucky for us, it is everywhere. All up front."
					Requirements = @(@{ Item = "Iron"; Qty = 35 })
					RewardCD = 0; RewardItems = @( @{ Item = "U.C.E. Shield Generator MK I"; Qty = 1 } ; @{ Item = "Shield Cell (Small)"; Qty = 2 } ; @{ Item = "Fuel Cell (Medium)"; Qty = 2 } )
				}
				@{
					Id = "mars_2"; Name = "Spectral Calibration"; RepReq = 1
					Desc = "Lab crew are offering a planetary-composition scanner for Venus samples."
					Requirements = @(@{ Item = "Sulfur"; Qty = 10 })
					RewardCD = 0; RewardItems = @(@{ Item = "XRF8 Scanner"; Qty = 1 })
				}
				@{
					Id = "mars_3"; Name = "Patchwork Fleet"; RepReq = 1
					Desc = "Mars has iron and scrap. Copper, less so. Bring patch stock, get an Auto-Injector."
					Requirements = @(
						@{ Item = "ScrapMetal"; Qty = 20 }
						@{ Item = "Iron"; Qty = 25 }
						@{ Item = "Copper"; Qty = 10 }
					)
					RewardCD = 750; RewardItems = @(@{ Item = "Shield Cell (Medium)"; Qty = 3 }; @{ Item = "Shield Cell Auto-Injector"; Qty = 1 })
				}
				@{
					Id = "mars_4"; Name = "Ceramic Scratch"; RepReq = 2
					Desc = "Venus and Ceres carry ceramic inputs for lighter heat shielding."
					Requirements = @(
						@{ Item = "Magnesium"; Qty = 25 }
						@{ Item = "Calcium"; Qty = 25 }
						@{ Item = "Boron"; Qty = 15 }
						@{ Item = "Silicon"; Qty = 20 }
					)
					RewardCD = 1000; RewardItems = @(@{ Item = "Auxiliary Fuel Tank"; Qty = 1 };@{ Item = "Cargo Baffles"; Qty = 1 })
				}
				@{
					Id = "mars_5"; Name = "Biological Census"; RepReq = 2
					Desc = "Biomass is scarce enough that even bad samples matter. Earth has plenty."
					Requirements = @(@{ Item = "Biomass"; Qty = 25 })
					RewardCD = 1000; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK III"; Qty = 1 })
				}
				@{
					Id = "mars_6"; Name = "Atmospheric Processor"; RepReq = 3
					Desc = "Order is for a Venusian poison cocktail. The payout is a Gas Giant Surveyor."
					Requirements = @(@{ Item = "Sulfur"; Qty = 35 }; @{ Item = "Nitrogen"; Qty = 25 }; @{ Item = "Argon"; Qty = 10 })
					RewardCD = 0; RewardItems = @(@{ Item = "Gas Giant Surveyor"; Qty = 1 }; @{ Item = "Shield Cell (Medium)"; Qty = 2 })
				}
				@{
					Id = "mars_7"; Name = "Belt Hardening Trial"; RepReq = 5
					Desc = "Logistics wants a Ceres-heavy order. Bring it up front and they reinforce the hull."
					Requirements = @(
						@{ Item = "Silicates"; Qty = 80 }
						@{ Item = "Iron"; Qty = 50 }
						@{ Item = "Copper"; Qty = 30 }
						@{ Item = "Nickel"; Qty = 30 }
						@{ Item = "Aluminum"; Qty = 30 }
					)
					RewardCD = 1000; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK II"; Qty = 1 }; @{ Item = "Shield Cell (Large)"; Qty = 1 })
				}
				@{
					Id = "mars_8"; Name = "Colony Stockpile"; RepReq = 6
					Desc = "Iron, water, biomass, zinc, and tin. Boring cargo keeps winter boring."
					Requirements = @(
						@{ Item = "Iron"; Qty = 120 }
						@{ Item = "Water"; Qty = 80 }
						@{ Item = "Biomass"; Qty = 25 }
						@{ Item = "Zinc"; Qty = 20 }
						@{ Item = "Tin"; Qty = 20 }
					)
					RewardCD = 1500; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 2 }; @{ Item = "Shield Cell (Large)"; Qty = 2 }; @{ Item = "Deluxe Auxiliary Fuel Tank"; Qty = 1 })
				}
				@{
					Id = "mars_9"; Name = "Blue Horizon"; RepReq = 7
					Desc = "Need some rare chemistry for deep-range fuel tests. Neptune should have the stuff."
					Requirements = @(
						@{ Item = "Neon"; Qty = 35 }
						@{ Item = "Argon"; Qty = 35 }
						@{ Item = "MetallicHydrogen"; Qty = 20 }
						@{ Item = "Neptunium"; Qty = 3 }
					)
					RewardCD = 1500; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 5 })
				}
				@{
					Id = "mars_10"; Name = "Heavy Metals"; RepReq = 8
					Desc = "Order's dense as. All up front as usual. Haumea's composition should be the best match."
					Requirements = @(
						@{ Item = "Iron"; Qty = 80 }
						@{ Item = "Nickel"; Qty = 40 }
						@{ Item = "Tungsten"; Qty = 20 }
						@{ Item = "Uranium"; Qty = 15 }
						@{ Item = "Platinum"; Qty = 5 }
					)
					RewardCD = 1800; RewardItems = @(@{ Item = "Premium Cargo Baffles"; Qty = 1 }; @{ Item = "Shield Cell (Small)"; Qty = 8 })
				}
			)
		}
		Ceres    = @{
			Distance = 17; Inhabited = $false; Type = "Asteroid"; Danger = 2.6; PlanetColor = "Gray"
			Description = "Small belt world packed with workable ore."
			Resources = @{ "Silicates" = 275; "Iron" = 135; "Nickel" = 95; "Aluminum" = 100; "Tin" = 70; "Zinc" = 65; "Copper" = 100; "Water" = 80; "Silver" = 35; "Silicon" = 35; "Boron" = 20; "Tungsten" = 18; "Magnesium" = 16; "Calcium" = 24; "Gold" = 8; "Uranium" = 10; "Radium" = 3; "Platinum" = 4; "Iridium" = 2; "U.C.E. Shield Generator MK I" = 1}
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "Micrometeor swarm", "Meteoroid bombardment", "Debris field collision", "Ring shard impact")
		}
		Jupiter  = @{
			Distance = 22; Inhabited = $false; Type = "Gas Giant"; Danger = 22.0; PlanetColor = "Red"
			Description = "Sovereign mass of storm and crushing pressure."
			Resources = @{ "Hydrogen" = 280; "Helium" = 180; "Nitrogen" = 120; "Neon" = 100; "Argon" = 95; "MetallicHydrogen" = 110; "Water" = 25; "Carbon" = 20; "Oxygen" = 15; "Sulfur" = 12; "Uranium" = 4; "Radium" = 2; "Iridium" = 2; "Silver" = 40; "Gold" = 8; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Gravity well shear", "Deep pressure crush", "Lightning discharge", "Extreme Lightning discharge", "Super-cyclone vortex", "Magnetosphere flux storm", "Gamma ray exposure")
		}
		Saturn   = @{
			Distance = 27; Inhabited = $false; Type = "Gas Giant"; Danger = 23.0; PlanetColor = "Yellow"
			Description = "Pale, ringed behemoth of violent storms."
			Resources = @{ "Hydrogen" = 220; "Helium" = 165; "Nitrogen" = 130; "Water" = 95; "Neon" = 100; "Argon" = 95; "MetallicHydrogen" = 105; "Silicates" = 40; "Iron" = 30; "ScrapMetal" = 20; "Nickel" = 25; "Carbon" = 25; "Oxygen" = 20; "Silver" = 25; "Gold" = 15; "Tungsten" = 15; "Platinum" = 15; "Iridium" = 2; "Promethium" = 3; "Uranium" = 15; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Ring shard impact", "Deep pressure crush", "Lightning discharge", "Extreme Lightning discharge", "Super-cyclone vortex", "Magnetosphere flux storm", "Gamma ray exposure")
		}
		Uranus   = @{
			Distance = 32; Inhabited = $false; Type = "Ice Giant"; Danger = 14.0; PlanetColor = "DarkCyan"
			Description = "Tilted frozen giant with radioactive traces."
			Resources = @{ "Water" = 160; "Hydrogen" = 190; "Helium" = 110; "Nitrogen" = 105; "Neon" = 120; "Argon" = 110; "Carbon" = 45; "Oxygen" = 45; "Uranium" = 65; "MetallicHydrogen" = 60; "Radium" = 22; "Plutonium" = 5; "Silver" = 8; "Gold" = 3; "Iridium" = 3; "Promethium" = 2; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Extreme cold stress", "Methane pressure spike", "Cryovolcanic ejecta", "Cryo-geyser eruption", "Lightning discharge", "Ring shard impact", "Diamond Rain Ballistic Impact")
		}
		Neptune  = @{
			Distance = 37; Inhabited = $false; Type = "Ice Giant"; Danger = 16.0; PlanetColor = "Blue"
			Description = "Distant blue abyss of rare chemistry."
			Resources = @{ "Hydrogen" = 220; "Helium" = 130; "Neon" = 125; "Argon" = 100; "Water" = 110; "Nitrogen" = 75; "MetallicHydrogen" = 75; "Oxygen" = 35; "Carbon" = 35; "Uranium" = 25; "Radium" = 9; "Neptunium" = 20; "Plutonium" = 4; "Iridium" = 2; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Extreme cold stress", "Deep pressure crush", "Supersonic wind shear", "Lightning discharge", "Super-cyclone vortex", "Diamond Rain Ballistic Impact")
		}
		Pluto    = @{
			Distance = 49.5; Inhabited = $true; Type = "Dwarf"; Danger = 4.5; PlanetColor = "Gray"
			Description = "Frigid vault of silicates and secrets."
			Resources = @{ "Water" = 156; "Silicates" = 175; "ScrapMetal" = 165; "Iron" = 120; "Carbon" = 105; "Nitrogen" = 60; "Oxygen" = 45; "Copper" = 30; "Nickel" = 22; "Tin" = 14; "Zinc" = 14; "Aluminum" = 13; "Silver" = 10; "Gold" = 5; "Uranium" = 8; "Radium" = 1; "Plutonium" = 10; "Fossils" = 10; "MetallicHydrogen" = 4; "Platinum" = 2; "Tungsten" = 2; "Promethium" = 1; "Biomass" = 5}
			HazardReasons = @("Hull stress", "Extreme cold stress", "Cryovolcanic ejecta", "Cryo-geyser eruption", "Asteroid impact")
			TraderName = "A.M.O-8 `"Theta`""; TotalTraderCredits = 3000; FuelModifier = 1.6; RepairModifier = 1.1
			Dialog = @{
				Greeting = @(
					"Mining platform online. Commerce protocol active."
					"A.M.O.8 Theta acknowledges vessel telemetry."
					"Organic pilot detected. Commerce protocol initiated."
					"*System self-service in progress...*"
				)
				TradeGreeting = @(
					"Inventory reconciliation requested."
					"State desired exchange."
					"Commerce module awaiting material variance."
					"Awaiting selection."
				)
				Refuel = @(
					"Fuel transfer complete."
					"Propellant mass restored to requested threshold."
					"Energy reserve correction complete."
				)
				Repair = @(
					"Maintenance cycle complete."
					"Hull discontinuities reduced."
					"Structural risk returned to profitable range."
				)
				Trade = @(
					"Transaction recorded."
					"Inventory updated."
					"Exchange accepted."
				)
				InsufficientFunds = @(
					"Insufficient credits."
					"Credit mass below required threshold."
					"Request rejected. Currency absence detected."
				)
				InsufficientFundsTrader = @(
					"Reserve inventory depleted."
					"Purchase threshold exceeded."
					"Acquisition halted to preserve station solvency."
				)
				Frustrated = @(
					"Invalid request."
					"Input not recognized."
					"Clarify intent."
				)
			}
			TraderStock = @{
				"Fuel Cell (Small)" = @{ Chance = 50; MinQty = 0; MaxQty = 5 }
				"Fuel Cell (Medium)" = @{ Chance = 70; MinQty = 0; MaxQty = 6 }
				"Fuel Cell (Large)" = @{ Chance = 60; MinQty = 0; MaxQty = 4 }
				"Shield Cell (Small)" = @{ Chance = 50; MinQty = 0; MaxQty = 3 }
				"Shield Cell (Medium)" = @{ Chance = 50; MinQty = 0; MaxQty = 3 }
				"Shield Cell (Large)" = @{ Chance = 50; MinQty = 0; MaxQty = 3 }
				"Cargo Baffles" = @{ Chance = 80; MinQty = 1; MaxQty = 1; DoubleChance = 8 }
				"Premium Cargo Baffles" = @{ Chance = 10; MinQty = 1; MaxQty = 1; DoubleChance = 1 }
				"U.C.E. Shield Generator MK III" = @{ Chance = 75; MinQty = 1; MaxQty = 1; DoubleChance = 4 }
				"Iridium" = @{ Chance = 1; MinQty = 0; MaxQty = 1; DoubleChance = 15 }
			}
			Quests = @(
				@{
					Id = "pluto_1"; Name = "Feed the Beast"; RepReq = 0
					Desc = "Low-power mode engaged. Jovian energy samples are required."
					Requirements = @(@{ Item = "MetallicHydrogen"; Qty = 35 }; @{ Item = "Hydrogen"; Qty = 50 })
					RewardCD = 2000; RewardItems = @(@{ Item = "Auxiliary Fuel Tank"; Qty = 1 })
				}
				@{
					Id = "pluto_2"; Name = "Crionics"; RepReq = 1
					Desc = "Cryogenic systems need cleaner nitrogen, neon, and water. Ice giants preferred."
					Requirements = @(
						@{ Item = "Nitrogen"; Qty = 50 }
						@{ Item = "Neon"; Qty = 20 }
						@{ Item = "Water"; Qty = 80 }
					)
					RewardCD = 0; RewardItems = @(@{ Item = "Cryo-Sleep Chamber"; Qty = 1 })
				}
				@{
					Id = "pluto_3"; Name = "Structural Maintenance"; RepReq = 2
					Desc = "Exterior shielding degraded. Deliver repair metals to preserve autonomy."
					Requirements = @(@{ Item = "Iron"; Qty = 80 }; @{ Item = "Nickel"; Qty = 20 }; @{ Item = "Zinc"; Qty = 20 }; @{ Item = "Tin"; Qty = 20 })
					RewardCD = 3000; RewardItems = @(@{ Item = "Shield Cell (Small)"; Qty = 5 })
				}
				@{
					Id = "pluto_4"; Name = "Carbon Pangs"; RepReq = 3
					Desc = "Acquire biological samples. Compensation will be provided."
					Requirements = @(@{ Item = "Biomass"; Qty = 200 }; @{ Item = "Carbon"; Qty = 100 })
					RewardCD = 2500; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 2 })
				}
				@{
					Id = "pluto_5"; Name = "Kuiper Mapping Array"; RepReq = 3
					Desc = "The array needs cold-stable metals and active elements from nearby dwarfs."
					Requirements = @(
						@{ Item = "Uranium"; Qty = 12 }
						@{ Item = "Platinum"; Qty = 5 }
						@{ Item = "Promethium"; Qty = 2 }
						@{ Item = "Tungsten"; Qty = 12 }
					)
					RewardCD = 1000; RewardItems = @(@{ Item = "Deluxe Auxiliary Fuel Tank"; Qty = 1 };@{ Item = "Dwarf-Class Surveyor"; Qty = 1 })
				}
				@{
					Id = "pluto_6"; Name = "Debris Mitigation"; RepReq = 4
					Desc = "Impact variance suggests a design flaw. Reassemble the interception grid."
					Requirements = @(@{ Item = "ScrapMetal"; Qty = 40 }; @{ Item = "Aluminum"; Qty = 50 }; @{ Item = "Silver"; Qty = 20 }; @{ Item = "Tungsten"; Qty = 5 })
					RewardCD = 1200; RewardItems = @(@{ Item = "Shield Cell (Large)"; Qty = 4 }; @{ Item = "Fuel Cell (Large)"; Qty = 3 })
				}
				@{
					Id = "pluto_7"; Name = "Resilient Alloy"; RepReq = 5
					Desc = "Acquire precursor elements for a near-impervious alloy for ore processing."
					Requirements = @(@{ Item = "Iridium"; Qty = 6 }; @{ Item = "Radium"; Qty = 4 }; @{ Item = "Neptunium"; Qty = 2 })
					RewardCD = 3000; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 3 }; @{ Item = "Shield Cell (Medium)"; Qty = 5 })
				}
				@{
					Id = "pluto_8"; Name = "Samples"; RepReq = 7
					Desc = "Complete Sol resource library."
					Requirements = @(
						@{ Item = "Silicates"; Qty = 60 }
						@{ Item = "Carbon"; Qty = 40 }
						@{ Item = "Oxygen"; Qty = 40 }
						@{ Item = "Water"; Qty = 40 }
						@{ Item = "Iron"; Qty = 50 }
						@{ Item = "Hydrogen"; Qty = 35 }
						@{ Item = "Nitrogen"; Qty = 30 }
						@{ Item = "Magnesium"; Qty = 20 }
						@{ Item = "Calcium"; Qty = 20 }
						@{ Item = "Aluminum"; Qty = 20 }
						@{ Item = "Sulfur"; Qty = 20 }
						@{ Item = "ScrapMetal"; Qty = 20 }
						@{ Item = "Zinc"; Qty = 15 }
						@{ Item = "Tin"; Qty = 15 }
						@{ Item = "Copper"; Qty = 15 }
						@{ Item = "Silicon"; Qty = 10 }
						@{ Item = "Nickel"; Qty = 10 }
						@{ Item = "Biomass"; Qty = 5 }
						@{ Item = "Boron"; Qty = 10 }
						@{ Item = "Argon"; Qty = 10 }
						@{ Item = "Neon"; Qty = 10 }
						@{ Item = "Helium"; Qty = 8 }
						@{ Item = "Silver"; Qty = 8 }
						@{ Item = "Tungsten"; Qty = 5 }
						@{ Item = "Platinum"; Qty = 3 }
						@{ Item = "Gold"; Qty = 3 }
						@{ Item = "MetallicHydrogen"; Qty = 5 }
						@{ Item = "Fossils"; Qty = 2 }
						@{ Item = "Plutonium"; Qty = 2 }
						@{ Item = "Uranium"; Qty = 5 }
						@{ Item = "Radium"; Qty = 4 }
						@{ Item = "Neptunium"; Qty = 2 }
						@{ Item = "Promethium"; Qty = 1 }
						@{ Item = "Iridium"; Qty = 1 }
					)
					RewardCD = 2000; RewardItems = @(@{ Item = "HyperDrive Module"; Qty = 1 })
				}
				@{
					Id = "pluto_9"; Name = "Unauthorized Density"; RepReq = 8
					Desc = "There are stronger materials yet. Do not involve the U.C.E."
					Requirements = @(
						@{ Item = "Mythril"; Qty = 15 }
						@{ Item = "Deuterium"; Qty = 45 }
					)
					RewardCD = 5000; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 4 }; @{ Item = "Shield Cell (Large)"; Qty = 2 })
				}
				@{
					Id = "pluto_10"; Name = "Elemental Fusion"; RepReq = 8
					Desc = "Typhon system jovian-class bodies harbor fusion reactor catalyst candidates."
					Requirements = @(
						@{ Item = "Helium-3"; Qty = 25 }
						@{ Item = "Cryophane"; Qty = 15 }
					)
					RewardCD = 7000; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 4 }; @{ Item = "Shield Cell (Large)"; Qty = 2 })
				}
				@{
					Id = "pluto_11"; Name = "Next Generation Warfare"; RepReq = 10
					Desc = "Recover Bastion Republic military tech samples for analysis."
					Requirements = @(
						@{ Item = "Warship Alloy"; Qty = 50 }
						@{ Item = "Ordnance Core"; Qty = 10 }
					)
					RewardCD = 8000; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 5 }; @{ Item = "Shield Cell (Large)"; Qty = 4 })
				}
				@{
					Id = "pluto_12"; Name = "Intergalactic Refractory"; RepReq = 11
					Desc = "Thermal insulation limitations of the Sol system can be overcome."
					Requirements = @(
						@{ Item = "Tantalum Hafnium Carbide"; Qty = 40 }
						@{ Item = "Pyrestone"; Qty = 20 }
					)
					RewardCD = 10000; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK III"; Qty = 2 }; @{ Item = "Fuel Cell (Large)"; Qty = 5 })
				}
			)
		}
		Haumea   = @{
			Distance = 52.5; Inhabited = $false; Type = "Dwarf"; Danger = 4.5; PlanetColor = "Gray"
			Description = "Spinning shard-world with dense outer ore."
			Resources = @{ "Iron" = 145; "Nickel" = 98; "Silicates" = 150; "Water" = 92; "Copper" = 52; "Carbon" = 42; "Nitrogen" = 15; "Aluminum" = 35; "Tin" = 30; "Zinc" = 21; "Silver" = 22; "Tungsten" = 36; "Platinum" = 14; "Gold" = 5; "Uranium" = 25; "Plutonium" = 15; "Promethium" = 2; "Iridium" = 2; "Cargo Baffles" = 1}
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "Micrometeor swarm", "Ring shard impact")
		}
		Makemake = @{
			Distance = 58.0; Inhabited = $false; Type = "Dwarf"; Danger = 6.8; PlanetColor = "Gray"
			Description = "Red ice crust with carbon-rich compounds."
			Resources = @{ "Carbon" = 125; "Nitrogen" = 95; "Water" = 115; "Silicates" = 120; "Iron" = 95; "Nickel" = 45; "Copper" = 35; "Aluminum" = 30; "Zinc" = 42; "Tin" = 40; "Silver" = 22; "Gold" = 10; "Tungsten" = 10; "Platinum" = 5; "Uranium" = 28; "Promethium" = 6; "Plutonium" = 4; "Iridium" = 2; "Auxiliary Fuel Tank" = 1 } # "Fuel Cell (Small)" = 00; "Fuel Cell (Medium)" = 00; "Fuel Cell (Large)" = 00; "Shield Cell (Small)" = 00; "Shield Cell (Medium)" = 00; "Shield Cell (Large)" = 00
			HazardReasons = @("Hull stress", "Static discharge", "Extreme cold stress", "Cryovolcanic ejecta", "Methane pressure spike")
		}
		Eris     = @{
			Distance = 69; Inhabited = $false; Type = "Dwarf"; Danger = 7.6; PlanetColor = "Gray"
			Description = "Far icy relic hiding heavy, raw veins."
			Resources = @{ "Silicates" = 118; "Iron" = 98; "Water" = 98; "ScrapMetal" = 72; "Carbon" = 58; "Nitrogen" = 52; "Nickel" = 60; "Copper" = 40; "Silver" = 42; "Tungsten" = 25; "Platinum" = 22; "Gold" = 12; "Uranium" = 48; "Radium" = 19; "Fossils" = 7; "Promethium" = 5; "Neptunium" = 2; "Iridium" = 3; "U.C.E. Shield Generator MK I" = 1 }
			HazardReasons = @("Hull stress", "Micro-vibrations", "Solar flare radiation", "Supersonic wind shear", "Asteroid impact")
		}
	}

	$global:SolSystem2 = @{
		_Metadata = @{ Id = "Typhon"; Name = "Typhon"; Color = "Blue" }
		Pyre     = @{
			Distance = 0; Inhabited = $false; Type = "Terrestrial"; Danger = 60.0; PlanetColor = "DarkRed"
			Description = "A molten hellhole with abundant resources."
			Resources = @{ "Iron" = 250; "Copper" = 200; "Nickel" = 150; "Gold" = 300; "Uranium" = 500; "Radium" = 300; "Mythril" = 450; "Tantalum Hafnium Carbide" = 500; "Pyrestone" = 1000; "Nitrogen" = 25; "Hydrogen" = 25; "Helium" = 200; "Deuterium" = 100; "Bastion Fuel Cell" = 25; "Bastion Shield Cell" = 25; "Platinum" = 150; "Promethium" = 350; "Iridium" = 150; "Plutonium" = 250; "Neptunium" = 200 }
			HazardReasons = @("Basalt flood wave", "Crustal foundering", "Mantle plume rupture", "Plasma lash", "Photospheric blowout", "Fission Event", "Gamma ray exposure", "Critical gamma ray exposure")
		}
		Bastion  = @{
			Distance = 5.0; Inhabited = $true; Type = "Terrestrial"; Danger = 34.0; PlanetColor = "DarkBlue"
			Description = "Capital of the fractured Republic."
			Resources = @{ "Iron" = 500; "Copper" = 300; "Silver" = 250; "Gold" = 175; "Mythril" = 225; "Water" = 150; "Biomass" = 125; "Tantalum Hafnium Carbide" = 200; "Warship Alloy" = 950; "Ordnance Core" = 900; "Republic Flight Recorder" = 2; "Bastion Fuel Cell" = 50; "Bastion Shield Cell" = 50; "Deuterium" = 75; "Nickel" = 75; "Uranium" = 325; "Radium" = 200; "Promethium" = 150; "Plutonium" = 120; "Iridium" = 50 }
			HazardReasons = @("Basalt flood wave", "Crustal foundering", "Flak cloud", "Live ordnance ping", "Drone strafing run", "Munitions detonation", "Railgun graze", "Missile volley", "Torpedo strike")
			TraderName = "Bastion Republic"; TotalTraderCredits = 9001; FuelModifier = 2.2; RepairModifier = 1.5
			Dialog = @{
				Greeting = @(
					"Docking authorization accepted. Deviation will be treated as intent."
					"Bastion control recognizes your vessel. Keep your channel clean."
					"You are entering Republic-controlled space. Conduct yourself usefully."
					"Transmit cargo manifest and await instruction."
				)
				TradeGreeting = @(
					"State your business."
					"Make it brief. The front does not pause for merchants."
					"We offer discounts if you enlist."
					"Republic logistics. What's your business?"
				)
				Refuel = @(
					"Fuel transfer complete."
					"Your range has been restored. Spend it in service of order."
					"Propellant issued."
				)
				Repair = @(
					"Repairs concluded."
					"Your hull is fit for redeployment."
					"Damage corrected."
				)
				Trade = @(
					"Credits transferred."
					"Republic acquision approved."
					"Materiel logged. Continue supplying the war effort."
				)
				InsufficientFunds = @(
					"Got to pay or enlist."
					"We don't do loans."
					"Return with funds."
				)
				InsufficientFundsTrader = @(
					"Procurement budget exhausted."
					"Command wouldn't authorize."
					"Your cargo exceeds current strategic allocation."
				)
				Frustrated = @(
					"Come again?"
					"Do not waste my time."
					"You are testing my patience, not my authority."
				)
			}
			TraderStock = @{
				"Fuel Cell (Small)" = @{ Chance = 30; MinQty = 0; MaxQty = 8 }
				"Fuel Cell (Medium)" = @{ Chance = 60; MinQty = 0; MaxQty = 6 }
				"Fuel Cell (Large)" = @{ Chance = 75; MinQty = 0; MaxQty = 9 }
				"Shield Cell (Small)" = @{ Chance = 30; MinQty = 0; MaxQty = 8 }
				"Shield Cell (Medium)" = @{ Chance = 60; MinQty = 0; MaxQty = 3 }
				"Shield Cell (Large)" = @{ Chance = 75; MinQty = 0; MaxQty = 9 }
				"Premium Cargo Baffles" = @{ Chance = 88; MinQty = 1; MaxQty = 1; DoubleChance = 8 }
				"Deluxe Auxiliary Fuel Tank" = @{ Chance = 88; MinQty = 1; MaxQty = 1; DoubleChance = 8 }
				"Bastion Shield Generator" = @{ Chance = 95; MinQty = 1; MaxQty = 1; DoubleChance = 4 }
			}
			Quests = @(
				@{
					Id = "rep_1"; Name = "Strategic Alloy Procurement"; RepReq = 0
					Desc = "Not interested in scrap. Provide mythril ore and recover downed warship components."
					Requirements = @(@{ Item = "Mythril"; Qty = 50 }; @{ Item = "Warship Alloy"; Qty = 125 })
					RewardCD = 5000; RewardItems = @()
				}
				@{
					Id = "rep_2"; Name = "Field Survey Arsenal"; RepReq = 1
					Desc = "Command wants asteroid extraction data and strategic refractory stock."
					Requirements = @(
						@{ Item = "Tantalum Hafnium Carbide"; Qty = 30 }
						@{ Item = "Gold"; Qty = 50 }
						@{ Item = "Copper"; Qty = 250 }
					)
					RewardCD = 3000; RewardItems = @(@{ Item = "Asteroid Surveyer"; Qty = 1 })
				}
				@{
					Id = "rep_3"; Name = "Isotope Tithe"; RepReq = 2
					Desc = "The Republic accepts isotopes in all forms. Clean, unstable, or otherwise."
					Requirements = @(@{ Item = "Uranium"; Qty = 150 }; @{ Item = "Radium"; Qty = 75 }; @{ Item = "Deuterium"; Qty = 100 }; @{ Item = "Promethium"; Qty = 20 })
					RewardCD = 7000; RewardItems = @(@{ Item = "Bastion Shield Cell"; Qty = 2 })
				}
				@{
					Id = "rep_4"; Name = "Weapons Division Allocation"; RepReq = 3
					Desc = "Fissile reserves and munitions cores remain critically below operational requirements."
					Requirements = @(@{ Item = "Uranium"; Qty = 100 }; @{ Item = "Mythril"; Qty = 75 }; @{ Item = "Ordnance Core"; Qty = 50 })
					RewardCD = 8000; RewardItems = @(@{ Item = "Bastion Shield Generator"; Qty = 1 })
				}
				@{
					Id = "rep_5"; Name = "Operation Sunforge"; RepReq = 4
					Desc = "Command has authorized civilian acquisition of strategic fuel precursors. No questions."
					Requirements = @(@{ Item = "Deuterium"; Qty = 200 }; @{ Item = "Helium-3"; Qty = 40 }; @{ Item = "MetallicHydrogen"; Qty = 200 })
					RewardCD = 10000; RewardItems = @(@{ Item = "Rad-Shielding Exosuit"; Qty = 1 })
				}
				@{
					Id = "rep_6"; Name = "Thermal Research"; RepReq = 5
					Desc = "Engineering requires ultra-high-temperature ceramics and cold-stable superconductors."
					Requirements = @(@{ Item = "Tantalum Hafnium Carbide"; Qty = 100 }; @{ Item = "Cryophane"; Qty = 50 })
					RewardCD = 9000; RewardItems = @(@{ Item = "Bastion Shield Generator"; Qty = 1 }; @{ Item = "Bastion Fuel Cell"; Qty = 2 })
				}
				@{
					Id = "rep_7"; Name = "Mantle Claim"; RepReq = 6
					Desc = "Pyre's mantle chemistry is the next frontier of Republic weapons research."
					Requirements = @(@{ Item = "Pyrestone"; Qty = 80 }; @{ Item = "Tantalum Hafnium Carbide"; Qty = 100 }; @{ Item = "Radium"; Qty = 100 })
					RewardCD = 14000; RewardItems = @(@{ Item = "Bastion Fuel Cell"; Qty = 3 }; @{ Item = "Bastion Shield Cell"; Qty = 3 })
				}
				@{
					Id = "rep_8"; Name = "Final Weapons Trial"; RepReq = 7
					Desc = "The final prototype needs star-baked cores, heavy isotopes, and recovered ordnance."
					Requirements = @(@{ Item = "Pyrestone"; Qty = 100 }; @{ Item = "Ordnance Core"; Qty = 80 }; @{ Item = "Helium-3"; Qty = 50 }; @{ Item = "Iridium"; Qty = 25 })
					RewardCD = 25000; RewardItems = @(@{ Item = "Bastion Shield Generator"; Qty = 1 }; @{ Item = "Bastion Fuel Cell"; Qty = 5 }; @{ Item = "Bastion Shield Cell"; Qty = 5 })
				}
			)
		}
		Shrapnel = @{
			Distance = 27.5; Inhabited = $false; Type = "Asteroid"; Danger = 45.0; PlanetColor = "Gray"
			Description = "A shattered asteroid belt littered with remnants of war."
			Resources = @{ "Silicates" = 50; "Iron" = 250; "ScrapMetal" = 505; "Copper" = 225; "Nickel" = 225; "Silver" = 225; "Gold" = 175; "Mythril" = 550; "Warship Alloy" = 950; "Ordnance Core" = 950; "Republic Flight Recorder" = 5; "Bastion Fuel Cell" = 25; "Bastion Shield Cell" = 25; "Tungsten" = 225; "Uranium" = 225; "Radium" = 125; "Platinum" = 125; "Iridium" = 20; "Promethium" = 120 }
			HazardReasons = @("Meteoroid bombardment", "Micrometeor swarm", "Dust-glass abrasion", "Regolith shear front", "Flak cloud", "Live ordnance ping", "Drone strafing run", "Munitions detonation", "Railgun graze", "Torpedo strike", "Asteroid impact")
		}
		Hyperion = @{
			Distance = 35.5; Inhabited = $false; Type = "Gas Giant"; Danger = 46.0; PlanetColor = "DarkYellow"
			Description = "Massive storms hide priceless fuel reserves."
			Resources = @{ "Mythril" = 50; "Nitrogen" = 500; "Hydrogen" = 550; "Helium" = 650; "MetallicHydrogen" = 1050; "Deuterium" = 950; "Helium-3" = 450; "Bastion Fuel Cell" = 15; "Bastion Shield Cell" = 15; "Neon" = 150; "Argon" = 135; "Platinum" = 40; "Iridium" = 20; "Uranium" = 200; "Radium" = 125; "Promethium" = 75; "Neptunium" = 125; "Plutonium" = 100 }
			HazardReasons = @("Static discharge", "Gravity well shear", "Deep pressure crush", "Hydrogen pressure inversion", "Plasma lash", "Photospheric blowout", "Super-cyclone vortex", "Gamma ray exposure", "Railgun graze")
		}
		Cocytus  = @{
			Distance = 53.0; Inhabited = $false; Type = "Ice Giant"; Danger = 36.0; PlanetColor = "Cyan"
			Description = "Frozen oceans beneath violent clouds."
			Resources = @{ "Mythril" = 50; "Uranium" = 400; "Radium" = 120; "Nitrogen" = 800; "Hydrogen" = 525; "Helium" = 600; "Water" = 200; "MetallicHydrogen" = 800; "Deuterium" = 650; "Helium-3" = 90; "Cryophane" = 600; "Bastion Fuel Cell" = 25; "Bastion Shield Cell" = 25; "Neptunium" = 50; "Promethium" = 35; "Oxygen" = 100 }
			HazardReasons = @("Extreme cold stress", "Cryowake rupture", "Auroral arc flash", "Hydrogen pressure inversion", "Railgun graze", "Ring shard impact", "Diamond Rain Ballistic Impact")
		}
		Flotsam  = @{
			Distance = 69.0; Inhabited = $true; Type = "Dwarf"; Danger = 23.0; PlanetColor = "White"
			Description = "A Free Frontier Fighters rebel outpost."
			Resources = @{ "Iron" = 600; "ScrapMetal" = 650; "Copper" = 450; "Silver" = 475; "Gold" = 300; "Mythril" = 75; "Water" = 500; "Biomass" = 275; "Nitrogen" = 175; "Hydrogen" = 175; "Helium" = 175; "MetallicHydrogen" = 175; "Deuterium" = 175; "Platinum" = 100; "Tungsten" = 100; "Bastion Fuel Cell" = 25; "Bastion Shield Cell" = 25; "Uranium" = 200; "Radium" = 25; "Nickel" = 200 }
			HazardReasons = @("Static ashfall", "Dust-glass abrasion", "Regolith shear front", "Flak cloud", "Live ordnance ping", "Railgun graze")
			TraderName = "FFF Rebels"; TotalTraderCredits = 4500; FuelModifier = 2.0; RepairModifier = 1.4
			Dialog = @{
				Greeting = @(
					"Didn't expect a fracker out here. Dock quiet and keep your beacon low."
					"Flotsam hears you. If Republic patrols followed, we cut the line."
					"You're clear to berth. You better not have been followed."
					"Welcome to what is left of free Typhon."
				)
				TradeGreeting = @(
					"Let's see what you've hauled in."
					"If it keeps lights on or shields up, we're interested."
					"Make it quick."
					"What can you spare for the outpost?"
				)
				Refuel = @(
					"Tanks topped off."
					"Fuel loaded. Don't burn it where Bastion can track you."
					"Range restored. Come back alive."
				)
				Repair = @(
					"Watch your ass out there."
					"Hull patched. It won't win a parade, but it will fly."
					"We sealed the holes. Keep the Republic from making new ones."
				)
				Trade = @(
					"Pleasure doing business."
					"Cargo received. That buys somebody another day."
					"Credits sent. Flotsam owes you more than that."
				)
				InsufficientFunds = @(
					"Wish we could front the credits."
					"We're short too. Everybody is."
					"Can't cover that from the outpost ledger."
				)
				InsufficientFundsTrader = @(
					"Can't afford that haul."
					"We need it, but we can't pay for all of it."
					"Our reserves are tapped. Try splitting the load."
				)
				Frustrated = @(
					"Easy there."
					"Pick a lane, pilot."
					"Keep it together. We have enough alarms."
				)
			}
			TraderStock = @{
				"Fuel Cell (Small)" = @{ Chance = 30; MinQty = 0; MaxQty = 6 }
				"Fuel Cell (Medium)" = @{ Chance = 60; MinQty = 0; MaxQty = 4 }
				"Fuel Cell (Large)" = @{ Chance = 75; MinQty = 0; MaxQty = 5 }
				"Bastion Fuel Cell" = @{ Chance = 24; MinQty = 0; MaxQty = 1; DoubleChance = 4 }
				"Shield Cell (Small)" = @{ Chance = 30; MinQty = 0; MaxQty = 6 }
				"Shield Cell (Medium)" = @{ Chance = 60; MinQty = 0; MaxQty = 4 }
				"Shield Cell (Large)" = @{ Chance = 75; MinQty = 0; MaxQty = 5 }
				"Bastion Shield Cell" = @{ Chance = 24; MinQty = 0; MaxQty = 1; DoubleChance = 2 }
				"Cargo Baffles" = @{ Chance = 64; MinQty = 1; MaxQty = 1; DoubleChance = 4 }
				"Premium Cargo Baffles" = @{ Chance = 33; MinQty = 1; MaxQty = 1; DoubleChance = 2 }
				"Auxiliary Fuel Tank" = @{ Chance = 64; MinQty = 1; MaxQty = 1; DoubleChance = 4 }
				"Deluxe Auxiliary Fuel Tank" = @{ Chance = 33; MinQty = 1; MaxQty = 1; DoubleChance = 1 }
				"FFF Shield Generator" = @{ Chance = 33; MinQty = 0; MaxQty = 1; DoubleChance = 5 }
			}
			Quests = @(
				@{
					Id = "rebel_1"; Name = "Keeping Us Flying"; RepReq = 0
					Desc = "Every plate we weld onto a freighter is one saved grunt."
					Requirements = @(@{ Item = "ScrapMetal"; Qty = 80 }; @{ Item = "Iron"; Qty = 80 }; @{ Item = "Water"; Qty = 60 })
					RewardCD = 2500; RewardItems = @(@{ Item = "Shield Cell (Large)"; Qty = 4 }) # @{ Item = "Dwarf-Class Surveyor"; Qty = 1 }
				}
				@{
					Id = "rebel_2"; Name = "Esoterics"; RepReq = 0
					Desc = "Republic warship blackboxes can hold valuable information. If you find one bring it to us."
					Requirements = @(@{ Item = "Republic Flight Recorder"; Qty = 1 })
					RewardCD = 8000; RewardItems = @(@{ Item = "Premium Cargo Baffles"; Qty = 1 })
				}
				@{
					Id = "rebel_3"; Name = "Cold Signal"; RepReq = 1
					Desc = "Cocytus ice carries a signal we can bend into a shielded relay."
					Requirements = @(@{ Item = "Cryophane"; Qty = 25 }; @{ Item = "Water"; Qty = 100 }; @{ Item = "Nitrogen"; Qty = 150 })
					RewardCD = 3500; RewardItems = @(@{ Item = "Shield Cell (Large)"; Qty = 3 })
				}
				@{
					Id = "rebel_4"; Name = "Long Haul Logistics"; RepReq = 2
					Desc = "Our supply lines stretch farther every month. More range means more survivors."
					Requirements = @(@{ Item = "Deuterium"; Qty = 80 }; @{ Item = "MetallicHydrogen"; Qty = 60 })
					RewardCD = 4000; RewardItems = @(@{ Item = "Deluxe Auxiliary Fuel Tank"; Qty = 1 })
				}
				@{
					Id = "rebel_5"; Name = "Frontier Armor"; RepReq = 2
					Desc = "Mythril plating keeps the small ships alive when the big guns start talking."
					Requirements = @(@{ Item = "Mythril"; Qty = 60 }; @{ Item = "Gold"; Qty = 40 }; @{ Item = "Nickel"; Qty = 100 })
					RewardCD = 5000; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 4 }; @{ Item = "Shield Cell (Large)"; Qty = 4 })
				}
				@{
					Id = "rebel_6"; Name = "Break the Blockade"; RepReq = 3
					Desc = "We need Hyperion fuel stock to keep relay windows open."
					Requirements = @(@{ Item = "Deuterium"; Qty = 150 }; @{ Item = "Helium-3"; Qty = 20 }; @{ Item = "MetallicHydrogen"; Qty = 150 })
					RewardCD = 6500; RewardItems = @(@{ Item = "Gas Giant Surveyor"; Qty = 1 }; @{ Item = "Fuel Cell (Large)"; Qty = 5 })
				}
				@{
					Id = "rebel_7"; Name = "Jammer Ice"; RepReq = 3
					Desc = "Jammers on Cocytus need cold-stable cores and enough fuel to stay hidden."
					Requirements = @(@{ Item = "Cryophane"; Qty = 60 }; @{ Item = "Deuterium"; Qty = 80 }; @{ Item = "Uranium"; Qty = 80 })
					RewardCD = 6500; RewardItems = @(@{ Item = "Ice Giant Surveyor"; Qty = 1 }; @{ Item = "Shield Cell (Large)"; Qty = 5 })
				}
				@{
					Id = "rebel_8"; Name = "Shrapnel Run"; RepReq = 4
					Desc = "If it used to be a Republic gunship, we can turn it into armor."
					Requirements = @(@{ Item = "Warship Alloy"; Qty = 150 }; @{ Item = "Ordnance Core"; Qty = 60 })
					RewardCD = 9000; RewardItems = @(@{ Item = "Premium Cargo Baffles"; Qty = 1 }; @{ Item = "FFF Shield Generator"; Qty = 1 })
				}
				@{
					Id = "rebel_9"; Name = "Sunward Sabotage"; RepReq = 5
					Desc = "Bastion is building something at Pyre. Bring us the same materials and we will break it first."
					Requirements = @(@{ Item = "Pyrestone"; Qty = 50 }; @{ Item = "Tantalum Hafnium Carbide"; Qty = 50 }; @{ Item = "Ordnance Core"; Qty = 40 })
					RewardCD = 15000; RewardItems = @(@{ Item = "Deluxe Auxiliary Fuel Tank"; Qty = 1 }; @{ Item = "Premium Cargo Baffles"; Qty = 1 }; @{ Item = "Bastion Shield Cell"; Qty = 3 })
				}
			)
		}
	}

	## >> Solar Systems << ##
    $global:PlanetTypeColors = @{
        "Terrestrial" = "DarkYellow"
        "Gas Giant"   = "Yellow"
        "Ice Giant"   = "Cyan"
        "Asteroid"    = "DarkGray"
        "Dwarf"       = "DarkGray"
    }

	$global:AllSystems = @(
        @{ Id = $global:SolSystem._Metadata.Id;    Name = $global:SolSystem._Metadata.Name;  Data = $global:SolSystem  }
        @{ Id = $global:SolSystem2._Metadata.Id;   Name = $global:SolSystem2._Metadata.Name; Data = $global:SolSystem2 }
    )

	$global:CurrentSolarSystem = $global:SolSystem
    if ($CurrentSolarSystem.ContainsKey("_Metadata")) {
        $global:Player.System = $CurrentSolarSystem._Metadata.Name
    }
}

function New-TraderStock {
    param([hashtable]$Rules)

    $stock = @{}
    if ($null -eq $Rules) { return $stock }

    foreach ($name in $Rules.Keys) {
        $rule = $Rules[$name]

        if (-not ($rule -is [System.Collections.IDictionary])) {
            $qty = [int]$rule
            if ($qty -gt 0) { $stock[$name] = $qty }
            continue
        }

        $chance = if ($rule.ContainsKey("Chance")) { [int]$rule.Chance } else { 100 }
        if ($chance -lt 0) { $chance = 0 }
        elseif ($chance -gt 100) { $chance = 100 }

        if ((Get-Random -Minimum 1 -Maximum 101) -gt $chance) { continue }

        $minQty = if ($rule.ContainsKey("MinQty")) { [int]$rule.MinQty } else { 1 }
        $maxQty = if ($rule.ContainsKey("MaxQty")) { [int]$rule.MaxQty } else { $minQty }
        if ($maxQty -lt $minQty) {
            $tmp = $minQty
            $minQty = $maxQty
            $maxQty = $tmp
        }

        $qty = Get-Random -Minimum $minQty -Maximum ($maxQty + 1)

        $doubleChance = if ($rule.ContainsKey("DoubleChance")) { [int]$rule.DoubleChance } else { 0 }
        if ($doubleChance -lt 0) { $doubleChance = 0 }
        elseif ($doubleChance -gt 100) { $doubleChance = 100 }

        if ($doubleChance -gt 0 -and (Get-Random -Minimum 1 -Maximum 101) -le $doubleChance) {
            $qty++
        }

        if ($qty -gt 0) { $stock[$name] = $qty }
    }

    return $stock
}
function Initialize-Trader($planetName) {
    $planet = $CurrentSolarSystem[$planetName]
    if (-not $planet.Inhabited) { return }
    if ($null -eq $global:TraderState) { $global:TraderState = @{} }

    $now         = Get-Date
	$boundaryMin = [math]::Floor($now.Minute / 15) * 15
    $boundary    = [datetime]($now.ToString("yyyy-MM-dd HH:") + $boundaryMin.ToString("00") + ":00")

    if (-not $global:TraderState.ContainsKey($planetName)) {
        $global:TraderState[$planetName] = @{
            Stock     = New-TraderStock $planet.TraderStock
            Credits   = $planet.TotalTraderCredits
            LastTrade = $boundary
            Rep       = 0
        }
    }
    else {
        $lastTrade = [datetime]$global:TraderState[$planetName].LastTrade
        if ($lastTrade -lt $boundary) {
            $global:TraderState[$planetName].Stock     = New-TraderStock $planet.TraderStock
            $global:TraderState[$planetName].Credits   = $planet.TotalTraderCredits
            $global:TraderState[$planetName].LastTrade = $boundary
        }
    }
}
#endregion

#region ##### UTILITIES #####
function Get-Clock {
    $sleptYears = if ($global:Player -and $global:Player.ContainsKey("TimesSlept")) { [int]$global:Player.TimesSlept } else { 0 }
    (Get-Date).AddYears(300 + $sleptYears).ToString("MM/dd/yyyy hh:mm:ss tt")
}

function Format-Fuel {
    param([double]$Value)

    return "{0:0.0}" -f ([math]::Round($Value, 1))
}

function Get-TravelFuelCost {
    param([double]$DistanceAU)

    return [double]([math]::Ceiling([math]::Abs($DistanceAU) / 0.1))
}

function Get-HyperdriveFuelCost {
    return 1000.0
}

function Get-RefuelPrice {
    param([double]$MissingFuel, [double]$FuelModifier)

    return [int][math]::Ceiling(([math]::Max(0.0, $MissingFuel) * 3.0) * $FuelModifier) # 3 CD/FL base
}

function Get-ItemEffectText {
    param($ItemMaster)

    if ($ItemMaster.UseMessage) { return [string]$ItemMaster.UseMessage }
    return "+$($ItemMaster.EffectValue) $($ItemMaster.Effect)"
}

function Get-DialogLine {
    param(
        $PlanetData,
        [string]$Key,
        [switch]$First
    )

    if (-not $PlanetData -or -not $PlanetData.ContainsKey("Dialog") -or -not $PlanetData.Dialog.ContainsKey($Key)) {
        return $null
    }

    $lines = @($PlanetData.Dialog[$Key])
    if ($lines.Count -eq 0) { return $null }
    if ($First -or $lines.Count -eq 1) { return [string]$lines[0] }
    return [string]($lines | Get-Random)
}

function Set-TraderDialog {
    param(
        $PlanetData,
        [string]$Key,
        [switch]$First
    )

    $global:Player.Dialog = Get-DialogLine -PlanetData $PlanetData -Key $Key -First:$First
}

function Set-GreetingDialog {
    param($PlanetName, $PlanetData)

    if (-not $PlanetData -or -not $PlanetData.Inhabited) {
        $global:Player.Dialog = $null
        return
    }

    $factionKey = if ($PlanetData.TraderName) { "Trader:$($PlanetData.TraderName)" } else { "Trader:$PlanetName" }
    $firstContact = -not ($global:Player.Known -contains $factionKey)
    Set-TraderDialog -PlanetData $PlanetData -Key "Greeting" -First:$firstContact

    if ($firstContact) {
        $global:Player.Known.Add($factionKey)
    }
}

function Get-HazardDamageMultiplier {
    param([string]$Reason)

    if ($global:HazardMaster.ContainsKey($Reason)) { return [double]$global:HazardMaster[$Reason] }
    return 1.0
}

function Get-HazardMeanDamage {
    param($PlanetData)

    $reasons = if ($PlanetData.HazardReasons) { @($PlanetData.HazardReasons) } else { @("Hull stress") }
    $total = 0.0
    foreach ($reason in $reasons) {
        $multiplier = Get-HazardDamageMultiplier $reason
        foreach ($baseDmg in 2..9) {
            $total += [int][math]::Max(1, ($baseDmg * $multiplier))
        }
    }

    return $total / ($reasons.Count * 8)
}

function Get-PlanetDanger {
    param($PlanetData)

    if ($PlanetData.ContainsKey("Danger")) { return [double]$PlanetData.Danger }

    $legacyHz = if ($PlanetData.ContainsKey("Hazard")) { [double]$PlanetData.Hazard } else { 1.0 }
    return ([math]::Floor($legacyHz * 0.75) / 100) * (Get-HazardMeanDamage $PlanetData)
}

function Get-BaseHazard {
    param($PlanetData)

    if (-not $PlanetData.ContainsKey("Danger") -and $PlanetData.ContainsKey("Hazard")) {
        return [int]$PlanetData.Hazard
    }

    $meanDamage = [math]::Max(1.0, (Get-HazardMeanDamage $PlanetData))
    $danger = Get-PlanetDanger $PlanetData
    return [int][math]::Min(100, [math]::Max(1, [math]::Ceiling(($danger * 100) / ($meanDamage * 0.75))))
}

function Get-HazardEventChance {
    param([int]$EffectiveHazard)

    return [int][math]::Min(100, [math]::Max(0, [math]::Floor($EffectiveHazard * 0.75)))
}

function Get-PlayerUpgradeStack {
    param([string]$Flag)

    if (-not $global:Player -or -not $global:Player.ContainsKey($Flag) -or $null -eq $global:Player[$Flag]) {
        return 0
    }

    $value = $global:Player[$Flag]
    if ($value -is [bool]) {
        if ($value) { return 1 }
        return 0
    }

    return [math]::Max(0, [int]$value)
}

function Add-PlayerUpgradeStack {
    param([string]$Flag, [int]$Amount = 1)

    $global:Player[$Flag] = (Get-PlayerUpgradeStack $Flag) + [math]::Max(1, $Amount)
}

function Test-StackingHazardUpgrade {
    param([string]$Effect)

    return @("frackGas", "frackIce", "frackTerr", "frackAst", "frackDwarf") -contains $Effect
}

function Get-EffectiveHazard($planetData) {
    $hz      = [double](Get-BaseHazard $planetData)
    $baseHz  = [double]$hz
    foreach ($itemName in $ResourceMaster.Keys) {
        $item = $ResourceMaster[$itemName]
        if (-not $item.HazardReduction) { continue }
        $stacks = if (Test-StackingHazardUpgrade $item.Effect) {
            Get-PlayerUpgradeStack $item.Effect
        } else {
            if ($Player[$item.Effect]) { 1 } else { 0 }
        }
        if ($stacks -le 0) { continue }

        # Threshold-based: applies to any planet whose base HZ meets the minimum
        if ($item.HazardReduction.ContainsKey("_threshold")) {
            if ($baseHz -ge $item.HazardThreshold) {
                $hz = $hz * (1 - $item.HazardReduction["_threshold"])
            }
        # Type-based: applies only to matching planet type
        } elseif ($item.HazardReduction.ContainsKey($planetData.Type)) {
            for ($i = 0; $i -lt $stacks; $i++) {
                $hz = $hz * (1 - $item.HazardReduction[$planetData.Type])
            }
        }
    }
    return [int][math]::Floor($hz)
}

function Get-CurrentWeight {
    $total = 0
    foreach ($name in $Inventory.Keys) {
        $itemMaster = $ResourceMaster[$name]
        $total += ($itemMaster.Weight * $Inventory[$name])
    }
    return $total
}

function Format-Duration {
    param([TimeSpan]$Span)

    if ($null -eq $Span) { return "0s" }
    if ($Span.TotalSeconds -lt 0) { $Span = [TimeSpan]::Zero }

    $h = [math]::Floor($Span.TotalHours)
    $m = $Span.Minutes
    $s = $Span.Seconds
    if ($h -gt 0) { return "{0}h {1}m {2}s" -f $h, $m, $s }
    if ($m -gt 0) { return "{0}m {1}s" -f $m, $s }
    return "{0}s" -f $s
}

function Get-SurvivedTime {
    if (-not $global:GameStartTime) { return "0s" }
    return Format-Duration -Span ((Get-Date) - $global:GameStartTime)
}

function Get-TimeFracked {
    return Get-PlayerDurationStat -Name "TimeFracked"
}

function Get-RealTimeFracked {
    return Get-PlayerDurationStat -Name "RealTimeFracked"
}

function Get-TimeSlept {
    return Get-PlayerDurationStat -Name "TimeSlept"
}

function Get-PlayerDurationStatSeconds {
    param([string]$Name)

    if (-not $global:Player -or -not $global:Player.ContainsKey($Name)) { return 0 }
    $seconds = 0
    if (-not [int]::TryParse(([string]$global:Player[$Name]), [ref]$seconds)) { return 0 }
    return [math]::Max(0, $seconds)
}

function Get-PlayerDurationStat {
    param([string]$Name)

    return Format-Duration -Span ([TimeSpan]::FromSeconds((Get-PlayerDurationStatSeconds -Name $Name)))
}

function Add-ProspectTime {
    param(
        [int]$Ticks = 1,
        [switch]$Skipped
    )

    if ($Ticks -le 0 -or -not $global:Player) { return }
    if (-not $global:Player.ContainsKey("TimeFracked")) { $global:Player.TimeFracked = 0 }
    if (-not $global:Player.ContainsKey("TimeSlept")) { $global:Player.TimeSlept = 0 }

    $timeFracked = 0
    if (-not [int]::TryParse(([string]$global:Player.TimeFracked), [ref]$timeFracked)) { $timeFracked = 0 }
    $global:Player.TimeFracked = $timeFracked + $Ticks

    if ($Skipped) {
        $timeSlept = 0
        if (-not [int]::TryParse(([string]$global:Player.TimeSlept), [ref]$timeSlept)) { $timeSlept = 0 }
        $global:Player.TimeSlept = $timeSlept + $Ticks
    }
}

function Get-ActiveQuestRequirements {
    $activeRequirements = @{}

    foreach ($sysEntry in $global:AllSystems) {
        $sysData = $sysEntry.Data
        foreach ($pKey in $sysData.Keys) {
            if ($pKey -eq "_Metadata") { continue }
            $pData = $sysData[$pKey]
            if (-not $pData.ContainsKey("Quests")) { continue }

            foreach ($quest in $pData.Quests) {
                if (-not $global:QuestState.ContainsKey($quest.Id)) { continue }
                if ($global:QuestState[$quest.Id].Status -ne "Active") { continue }

                foreach ($req in $quest.Requirements) {
                    if (-not $activeRequirements.ContainsKey($req.Item)) { $activeRequirements[$req.Item] = 0 }
                    $activeRequirements[$req.Item] += [int]$req.Qty
                }
            }
        }
    }

    return $activeRequirements
}

function Get-PercentColor {
    param(
        [double]$Current, 
        [double]$Max, 
        [switch]$Inverted # If true, high percentage = Red (useful for Weight/Hazard)
    )
    if ($Max -le 0) { return "White" }
    $pct = ($Current / $Max) * 100

    if ($Inverted) {
        if ($pct -ge 91) { "DarkRed" }
        elseif ($pct -ge 76) { "Red" }
        elseif ($pct -ge 51) { "Yellow" }
        #elseif ($pct -ge 11) { "Green" }
        else { "Green" }
    } else {
        if ($pct -ge 51) { "Green" }
        elseif ($pct -ge 26) { "Yellow" }
        elseif ($pct -ge 11) { "Red" }
        else { "DarkRed" }
    }
}

function Get-HazardColor($Value) {
    if ($Value -ge 80) { "DarkRed" }
    elseif ($Value -ge 60) { "Red" }
    elseif ($Value -ge 33) { "Yellow" }
    elseif ($Value -eq 1 ) { "DarkCyan" }
    else { "Green" }
}

function Get-PlanetTypeColor {
    param([string]$Type)

    if ($global:PlanetTypeColors -and $global:PlanetTypeColors.ContainsKey($Type)) {
        return $global:PlanetTypeColors[$Type]
    }

    return "Magenta"
}

function Get-ProspectDrillAnimationInterval {
    $speed = if ($global:Player -and $global:Player.ContainsKey("AnimationSpeed")) { $global:Player.AnimationSpeed } else { 125 }
    $numericSpeed = 0

    if (-not [int]::TryParse(([string]$speed), [ref]$numericSpeed)) {
        return 125
    }

    return [math]::Min(1000, [math]::Max(5, $numericSpeed))
}

function Get-ProspectAnimationMode {
    $mode = if ($global:Player -and $global:Player.ContainsKey("AnimationMode")) { [string]$global:Player.AnimationMode } else { "Repaint" }

    if (@("Repaint", "Off") -contains $mode) {
        return $mode
    }

    return "Repaint"
}

$ProspectDrillFrames = @(
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

function ConvertTo-InvertedProspectDrillFrame {
    param(
        [Parameter(Mandatory)]
        [string]$Frame
    )

    $lines = ($Frame -replace "`r`n", "`n" -replace "`r", "`n") -split "`n"
    $first = 0
    $last = $lines.Count - 1

    while ($first -le $last -and $lines[$first].Length -eq 0) { $first++ }
    while ($last -ge $first -and $lines[$last].Length -eq 0) { $last-- }
    if ($last -lt $first) { return "" }

    $invertedLines = for ($lineIndex = $first; $lineIndex -le $last; $lineIndex++) {
        $chars = $lines[$lineIndex].ToCharArray()
        [Array]::Reverse($chars)
        -join ($chars | ForEach-Object {
            switch ($_) {
                "/" { "\" }
                "\" { "/" }
                "<" { ">" }
                ">" { "<" }
                default { $_ }
            }
        })
    }

    return ($invertedLines -join "`n")
}

$ProspectInvertedDrillFrames = @($ProspectDrillFrames | ForEach-Object { ConvertTo-InvertedProspectDrillFrame -Frame $_ })

function ConvertTo-ProspectAsciiFrameLines {
    param(
        [Parameter(Mandatory)]
        [string]$Frame
    )

    $lines = ($Frame -replace "`r`n", "`n" -replace "`r", "`n") -split "`n"
    $first = 0
    $last = $lines.Count - 1

    while ($first -le $last -and $lines[$first].Length -eq 0) { $first++ }
    while ($last -ge $first -and $lines[$last].Length -eq 0) { $last-- }

    if ($last -lt $first) { return @("") }
    return @($lines[$first..$last])
}

function Get-UniqueProspectAsciiFrameCount {
    param(
        [Parameter(Mandatory)]
        [string[]]$Frames
    )

    if ($Frames.Count -gt 1 -and $Frames[0] -eq $Frames[$Frames.Count - 1]) {
        return ($Frames.Count - 1)
    }

    return $Frames.Count
}

function New-ProspectAsciiSegment {
    param(
        [AllowEmptyString()]
        [string]$Text,

        [string]$Color = "Gray"
    )

    [pscustomobject]@{
        Text  = if ($null -eq $Text) { "" } else { $Text }
        Color = $Color
    }
}

function ConvertTo-ProspectDrillAsciiSegments {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return @() }

    $segments = @()
    $start = 0
    $currentColor = if ($Text[0] -eq "#") { "Gray" } else { "DarkGray" }

    for ($i = 1; $i -lt $Text.Length; $i++) {
        $color = if ($Text[$i] -eq "#") { "Gray" } else { "DarkGray" }
        if ($color -eq $currentColor) { continue }

        $segments += New-ProspectAsciiSegment -Text $Text.Substring($start, $i - $start) -Color $currentColor
        $start = $i
        $currentColor = $color
    }

    $segments += New-ProspectAsciiSegment -Text $Text.Substring($start) -Color $currentColor
    return $segments
}

function Get-ProspectAsciiSegmentTextLength {
    param(
        [object[]]$Segments
    )

    $length = 0
    foreach ($segment in $Segments) {
        $length += ([string]$segment.Text).Length
    }
    return $length
}

function Format-CenteredProspectAsciiSegments {
    param(
        [object[]]$Segments,
        [int]$Width
    )

    if ($Width -le 0) { return @() }
    if ($null -eq $Segments) { $Segments = @() }

    $textLength = Get-ProspectAsciiSegmentTextLength -Segments $Segments
    if ($textLength -gt $Width) {
        $plainText = -join ($Segments | ForEach-Object { $_.Text })
        return @(New-ProspectAsciiSegment -Text $plainText.Substring(0, $Width) -Color "Gray")
    }

    $leftPadding = [Math]::Floor(($Width - $textLength) / 2)
    $rightPadding = $Width - $textLength - $leftPadding
    $centered = @()

    if ($leftPadding -gt 0) {
        $centered += New-ProspectAsciiSegment -Text (" " * $leftPadding) -Color "DarkGray"
    }
    foreach ($segment in $Segments) {
        $centered += $segment
    }
    if ($rightPadding -gt 0) {
        $centered += New-ProspectAsciiSegment -Text (" " * $rightPadding) -Color "DarkGray"
    }

    return $centered
}

function Get-ProspectDrillHeaderFrameSegments {
    param(
        [int]$FrameIndex = 0,
        [string]$PlanetName = "URANUS",
        [string]$PlanetColor = "White",
        [string]$PlanetType = "Terrestrial",
        [string]$PlanetTypeColor = "DarkYellow",
        [int]$EffectiveHazard = 1,
        [int]$BaseHazard = 1,
        [object]$FrackingFrameIndex = $null,
        [int]$TotalWidth = $script:SpaceFrackLayoutWidth
    )

    $leftFrames = @($script:ProspectDrillFrames)
    $rightFrames = @($script:ProspectInvertedDrillFrames)
    if ($leftFrames.Count -eq 0 -or $rightFrames.Count -eq 0) { return @() }

    $leftFrameCount = Get-UniqueProspectAsciiFrameCount -Frames $leftFrames
    $rightFrameCount = Get-UniqueProspectAsciiFrameCount -Frames $rightFrames
    $leftIndex = (($FrameIndex % $leftFrameCount) + $leftFrameCount) % $leftFrameCount
    $rightIndex = (($FrameIndex % $rightFrameCount) + $rightFrameCount) % $rightFrameCount
    $leftLines = @(ConvertTo-ProspectAsciiFrameLines -Frame $leftFrames[$leftIndex])
    $rightLines = @(ConvertTo-ProspectAsciiFrameLines -Frame $rightFrames[$rightIndex])
    $planet = if ([string]::IsNullOrWhiteSpace($PlanetName)) { "URANUS" } else { $PlanetName.ToUpper() }
    $typeText = if ([string]::IsNullOrWhiteSpace($PlanetType)) { "Unknown" } else { $PlanetType }
    $frackingIndex = if ($null -eq $FrackingFrameIndex) { $FrameIndex } else { [int]$FrackingFrameIndex }
    $frackingColor = if (($frackingIndex % 2) -eq 0) { "Yellow" } else { "DarkYellow" }

    $hazardSegments = @(
        (New-ProspectAsciiSegment -Text "(" -Color "DarkGray"),
        (New-ProspectAsciiSegment -Text $typeText -Color $PlanetTypeColor),
        (New-ProspectAsciiSegment -Text ", " -Color "DarkGray"),
        (New-ProspectAsciiSegment -Text "HZ:" -Color "Gray"),
        (New-ProspectAsciiSegment -Text " " -Color "Gray"),
        (New-ProspectAsciiSegment -Text ([string]$EffectiveHazard) -Color (Get-HazardColor $EffectiveHazard))
    )
    if ($EffectiveHazard -lt $BaseHazard) {
        $hazardSegments += New-ProspectAsciiSegment -Text "/" -Color "DarkGray"
        $hazardSegments += New-ProspectAsciiSegment -Text ([string]$BaseHazard) -Color (Get-HazardColor $BaseHazard)
    }
    $hazardSegments += New-ProspectAsciiSegment -Text ")" -Color "DarkGray"

    $frackingSegments = @(
        (New-ProspectAsciiSegment -Text "FRACKING" -Color $frackingColor),
        (New-ProspectAsciiSegment -Text ":" -Color "Gray")
    )
    $frackingTextLength = Get-ProspectAsciiSegmentTextLength -Segments $frackingSegments
    $frackingLineIndex = 1
    $frackingLeft = if ($frackingLineIndex -lt $leftLines.Count) { $leftLines[$frackingLineIndex] } else { "" }
    $frackingRight = if ($frackingLineIndex -lt $rightLines.Count) { $rightLines[$frackingLineIndex] } else { "" }
    $frackingCenterWidth = [Math]::Max(1, $TotalWidth - $frackingLeft.Length - $frackingRight.Length)
    $frackingAbsoluteStart = $frackingLeft.Length + [Math]::Max(0, [Math]::Floor(($frackingCenterWidth - $frackingTextLength) / 2))

    $centerRows = @(
        @(),
        $frackingSegments,
        @(
            (New-ProspectAsciiSegment -Text $planet -Color $PlanetColor)
        ),
        $hazardSegments
    )

    $rows = @()
    for ($lineIndex = 0; $lineIndex -lt $centerRows.Count; $lineIndex++) {
        $left = if ($lineIndex -lt $leftLines.Count) { $leftLines[$lineIndex] } else { "" }
        $right = if ($lineIndex -lt $rightLines.Count) { $rightLines[$lineIndex] } else { "" }
        $centerWidth = [Math]::Max(1, $TotalWidth - $left.Length - $right.Length)
        $segments = @()
        $segments += ConvertTo-ProspectDrillAsciiSegments -Text $left
        if ($lineIndex -eq 2) {
            $planetTextLength = Get-ProspectAsciiSegmentTextLength -Segments $centerRows[$lineIndex]
            if ($planetTextLength -gt $centerWidth) {
                $segments += Format-CenteredProspectAsciiSegments -Segments $centerRows[$lineIndex] -Width $centerWidth
            } else {
                $desiredAbsoluteStart = $frackingAbsoluteStart + [Math]::Floor(($frackingTextLength - $planetTextLength) / 2)
                $leftPadding = [Math]::Max(0, [Math]::Min(($centerWidth - $planetTextLength), ($desiredAbsoluteStart - $left.Length)))
                $rightPadding = $centerWidth - $planetTextLength - $leftPadding
                if ($leftPadding -gt 0) { $segments += New-ProspectAsciiSegment -Text (" " * $leftPadding) -Color "DarkGray" }
                $segments += $centerRows[$lineIndex]
                if ($rightPadding -gt 0) { $segments += New-ProspectAsciiSegment -Text (" " * $rightPadding) -Color "DarkGray" }
            }
        } else {
            $segments += Format-CenteredProspectAsciiSegments -Segments $centerRows[$lineIndex] -Width $centerWidth
        }
        $segments += ConvertTo-ProspectDrillAsciiSegments -Text $right

        $rowLength = Get-ProspectAsciiSegmentTextLength -Segments $segments
        if ($rowLength -lt $TotalWidth) {
            $segments += New-ProspectAsciiSegment -Text (" " * ($TotalWidth - $rowLength)) -Color "DarkGray"
        }

        $rows += [pscustomobject]@{
            Segments = $segments
        }
    }

    return [pscustomobject]@{
        Rows = $rows
    }
}

function Write-ProspectAsciiSegmentRow {
    param(
        [Parameter(Mandatory)]
        [object[]]$Segments,
        [switch]$ClearLine
    )

    if ($ClearLine) { Clear-CurrentConsoleLine }
    foreach ($segment in $Segments) {
        if ([string]::IsNullOrEmpty($segment.Text)) { continue }
        Write-Host -NoNewline $segment.Text -ForegroundColor $segment.Color
    }
    Write-Host ""
}

function Write-ProspectDrillHeader {
    param(
        [int]$FrameIndex = 0,
        [string]$PlanetName = "URANUS",
        [string]$PlanetColor = "White",
        [string]$PlanetType = "Terrestrial",
        [string]$PlanetTypeColor = "DarkYellow",
        [int]$EffectiveHazard = 1,
        [int]$BaseHazard = 1,
        [object]$FrackingFrameIndex = $null,
        [switch]$ClearLines
    )

    $frame = Get-ProspectDrillHeaderFrameSegments `
        -FrameIndex $FrameIndex `
        -PlanetName $PlanetName `
        -PlanetColor $PlanetColor `
        -PlanetType $PlanetType `
        -PlanetTypeColor $PlanetTypeColor `
        -EffectiveHazard $EffectiveHazard `
        -BaseHazard $BaseHazard `
        -FrackingFrameIndex $FrackingFrameIndex

    foreach ($row in $frame.Rows) {
        Write-ProspectAsciiSegmentRow -Segments $row.Segments -ClearLine:$ClearLines
    }
}

function Get-RarityColor {
    param(
        [string]$Rarity,
        [switch]$Background,
        [switch]$OnBackground
    )

    if ($OnBackground) {
        switch ($Rarity) {
            "Artifact"   { "Black" }
            "Oddity"     { "Black" }
            "Upgrade"    { "Black" }
            default      { Get-RarityColor $Rarity }
        }
        return
    }

    if ($Background) {
        switch ($Rarity) {
            "Artifact"   { "DarkYellow" }
            "Oddity"     { "White" }
            "Upgrade"    { "DarkGreen" }
            default      { $null }
        }
        return
    }

    switch ($Rarity) {
        "SuperCommon" { "DarkGray" }
        "Common"      { "Gray" }
        "Uncommon"    { "DarkCyan" }
        "Rare"        { "Cyan" }
        "SuperRare"   { "Magenta" }
        "UltraRare"   { "DarkYellow" }
        "Artifact"    { "DarkYellow" }
        "Oddity"      { "White" }
        "Consumable"  { "Green" } 
        "Upgrade"     { "DarkGreen" }
        default        { "Gray" }
    }
}

function Write-RarityText {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$Rarity,
        [switch]$NoNewline
    )

    $foreground = Get-RarityColor $Rarity
    $background = Get-RarityColor $Rarity -Background
    $writeParams = @{ ForegroundColor = $foreground }

    if ($background) {
        $writeParams.ForegroundColor = Get-RarityColor $Rarity -OnBackground
        $writeParams.BackgroundColor = $background
    }
    if ($NoNewline) { $writeParams.NoNewline = $true }

    Write-Host $Text @writeParams
}

function Flash-DamageBackground {
    param(
        [System.ConsoleColor]$FlashColor,
        [scriptblock]$RedrawAction,
        [switch]$NoClear
    )
    # Store current color
    $originalColor = $host.UI.RawUI.BackgroundColor
    
    # Trigger flash
    $host.UI.RawUI.BackgroundColor = $FlashColor
    if (-not $NoClear) { Clear-Host }
    
    # Execute the redraw so the screen isn't empty during the flash
    if ($RedrawAction) { &$RedrawAction }
    
    Start-Sleep -Milliseconds 100
    
    # Revert to original color
    $host.UI.RawUI.BackgroundColor = $originalColor
    if (-not $NoClear) { Clear-Host }

    # Re-execute the redraw immediately so the screen isn't empty after the flash
    if ($RedrawAction) { &$RedrawAction }
}

function Pause { Read-Host "Press Enter" | Out-Null }

function ConvertTo-Hashtable($obj) {
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $ht = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            $ht[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $ht
    } elseif ($obj -is [System.Object[]] -or $obj -is [System.Collections.ArrayList]) {
        return @($obj | ForEach-Object { ConvertTo-Hashtable $_ })
    } else {
        return $obj
    }
}

function Test-SaveName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalidChars -contains $ch) { return $false }
    }

    return $true
}

function Read-SaveName {
    while ($true) {
        Write-Host ""
        Write-Host "Enter pilot name for save files:" -ForegroundColor DarkGray
        $name = Read-Host ">"

        if (Test-SaveName $name) { return $name.Trim() }

        Write-Host "Invalid save name. Do not use characters Windows forbids in filenames." -ForegroundColor Red
    }
}

function Get-SaveDirectory {
    return (Join-Path $env:APPDATA "spacefrack")
}

function Ensure-SaveDirectory {
    $saveDir = Get-SaveDirectory
    if (-not (Test-Path -LiteralPath $saveDir)) {
        New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
    }
    return $saveDir
}

function Get-SaveFiles {
    $saveDir = Ensure-SaveDirectory
    @(Get-ChildItem -Path $saveDir -Filter "spacegame_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
}

function Get-SaveFileInfo {
    param($SaveFile)

    $json = Get-Content $SaveFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

    [PSCustomObject]@{
        File     = $SaveFile
        SaveName = [string]$json.Player.SaveName
        SavedAt  = [datetime]::Parse($json.SavedAt)
    }
}

function Prune-Saves {
    param([array]$Saves)

    if (-not $Saves -or $Saves.Count -eq 0) {
        $global:Player.Message = "No save files to prune."
        return
    }

    Write-Host ""
    Write-Host "Type PRUNE to keep only the newest save for each pilot:" -ForegroundColor DarkGray
    $confirm = (Read-Host ">").Trim()
    if ($confirm -ne "PRUNE") {
        $global:Player.Message = "Prune cancelled."
        return
    }

    $saveInfos = @($Saves | ForEach-Object { Get-SaveFileInfo $_ })
    $toDelete = @()
    foreach ($group in ($saveInfos | Group-Object SaveName)) {
        $ordered = @($group.Group | Sort-Object SavedAt -Descending)
        if ($ordered.Count -gt 1) {
            $toDelete += $ordered | Select-Object -Skip 1
        }
    }

    foreach ($entry in $toDelete) {
        Remove-Item -LiteralPath $entry.File.FullName -Force
    }

    $global:Player.Message = "Pruned $($toDelete.Count) old save file(s)."
}

function Delete-AllSaves {
    param([array]$Saves)

    if (-not $Saves -or $Saves.Count -eq 0) {
        $global:Player.Message = "No save files to delete."
        return
    }

    Write-Host ""
    Write-Host "Type DELETE to remove all save files:" -ForegroundColor Red
    $confirm = (Read-Host ">").Trim()
    if ($confirm -ne "DELETE") {
        $global:Player.Message = "Delete cancelled."
        return
    }

    foreach ($save in $Saves) {
        Remove-Item -LiteralPath $save.FullName -Force
    }

    $global:Player.Message = "Deleted $($Saves.Count) save file(s)."
}

function Delete-SaveFile {
    param($SaveFile)

    if (-not $SaveFile -or -not (Test-Path -LiteralPath $SaveFile.FullName)) {
        $global:Player.Message = "Save file not found."
        return
    }

    Write-Host ""
    Write-Host -NoNewline "Type DELETE to remove " -ForegroundColor Red
    Write-Host $SaveFile.BaseName -ForegroundColor DarkRed
    $confirm = (Read-Host ">").Trim()
    if ($confirm -ne "DELETE") {
        $global:Player.Message = "Delete cancelled."
        return
    }

    Remove-Item -LiteralPath $SaveFile.FullName -Force
    $global:Player.Message = "Deleted: $($SaveFile.Name)"
}

function Save-Game {
    if (-not $global:Player.ContainsKey("SaveName") -or [string]::IsNullOrWhiteSpace($global:Player.SaveName)) {
        $global:Player.SaveName = Read-SaveName
    }

    $timestamp = (Get-Date).ToString("ddMMyy-HHmmss")
    $saveFileName = "spacegame_$($global:Player.SaveName)_$timestamp.txt"
    $savePath  = Join-Path (Ensure-SaveDirectory) $saveFileName
    $sysName   = if ($global:CurrentSolarSystem.ContainsKey("_Metadata") -and $global:CurrentSolarSystem._Metadata.Id) { $global:CurrentSolarSystem._Metadata.Id } else { "Sol" }

    $playerCopy = $global:Player.Clone()
    $playerCopy.Known = @($global:Player.Known)

    # Normalize TraderState LastTrade to plain ISO strings so ConvertTo-Json
    # doesn't serialize the PS5.1 decorated DateTime PSObject with DisplayHint.
    $traderStateCopy = @{}
    foreach ($planet in $global:TraderState.Keys) {
        $ts = $global:TraderState[$planet].Clone()
        if ($ts.ContainsKey("LastTrade") -and $ts.LastTrade -ne $null) {
            $ts.LastTrade = ([datetime]$ts.LastTrade).ToString("o")
        }
        $traderStateCopy[$planet] = $ts
    }

    $saveData = @{
        Version       = $SpacegameVersion
        SavedAt       = (Get-Date).ToString("o")
        GameStartTime = $global:GameStartTime.ToString("o")
        SystemName    = $sysName
        Player        = $playerCopy
        Inventory     = $global:Inventory
        TraderState   = $traderStateCopy
        QuestState    = $global:QuestState
    }

    $saveData | ConvertTo-Json -Depth 10 | Set-Content $savePath -Encoding UTF8
    $global:Player.Message = "Saved: $savePath"
    return $savePath
}

function Load-Game($path) {
    $data = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { ConvertTo-Hashtable $_ }

    $global:CurrentSolarSystem = if ($data.SystemName -eq "Typhon") { $global:SolSystem2 } else { $global:SolSystem }
    $global:GameStartTime = [datetime]::Parse($data.GameStartTime)

    $global:Player           = $data.Player
    $global:Player.Known     = [System.Collections.Generic.List[string]]@($data.Player.Known)
    $global:Player.System    = $global:CurrentSolarSystem._Metadata.Name

    $global:Inventory   = $data.Inventory
    $global:TraderState = $data.TraderState
    $global:QuestState  = $data.QuestState

    foreach ($planet in @($global:TraderState.Keys)) {
        $ts = $global:TraderState[$planet]
        if ($ts.ContainsKey("LastTrade") -and $ts.LastTrade -ne $null) {
            $ts.LastTrade = [datetime]::Parse([string]$ts.LastTrade)
        }
    }

    $global:Player.Message = "Save loaded."
}

function Write-MenuKey($Key, $KeyColor, $Label, $LabelColor = "DarkCyan") {
    Write-Host -NoNewline "[" -ForegroundColor DarkGray
    Write-Host -NoNewline $Key -ForegroundColor $KeyColor
    Write-Host -NoNewline "] " -ForegroundColor DarkGray
    if ($Label) { Write-Host $Label -ForegroundColor $LabelColor }
}

function Write-SettingsOptionPrefix {
    param([string]$Key, [string]$Label)

    Write-Host -NoNewline "[" -ForegroundColor DarkGray
    Write-Host -NoNewline $Key -ForegroundColor Cyan
    Write-Host -NoNewline "] " -ForegroundColor DarkGray
    Write-Host -NoNewline $Label -ForegroundColor DarkCyan
    Write-Host -NoNewline ": " -ForegroundColor Gray
}

function Write-SettingsSection {
    param([string]$Label)

    Write-Host -NoNewline " ~~~ " -ForegroundColor DarkGray
    Write-Host -NoNewline $Label -ForegroundColor Gray
    Write-Host " ~~~" -ForegroundColor DarkGray
}

function Write-SettingsModeLine {
    $activeMode = Get-ProspectAnimationMode
    $modes = @("Repaint", "Off")

    Write-SettingsOptionPrefix "3" "Mode"
    for ($i = 0; $i -lt $modes.Count; $i++) {
        $mode = $modes[$i]
        $color = if ($mode -eq $activeMode) { "Green" } else { "DarkGray" }
        Write-Host -NoNewline $mode -ForegroundColor $color
        if ($i -lt ($modes.Count - 1)) {
            Write-Host -NoNewline " | " -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

function Set-NextProspectAnimationMode {
    $modes = @("Repaint", "Off")
    $current = Get-ProspectAnimationMode
    $index = [array]::IndexOf($modes, $current)
    if ($index -lt 0) { $index = 0 }
    $global:Player.AnimationMode = $modes[(($index + 1) % $modes.Count)]
}

function Read-ProspectAnimationSpeed {
    Write-Host ""
    Write-Host "Enter drill animation interval in ms (5-1000):" -ForegroundColor DarkGray
    $inputText = (Read-Host ">").Trim()
    if ([string]::IsNullOrWhiteSpace($inputText)) { return }

    $speed = 0
    if (-not [int]::TryParse($inputText, [ref]$speed)) {
        $global:Player.Message = "Animation speed must be a number."
        return
    }

    $global:Player.AnimationSpeed = [math]::Min(1000, [math]::Max(5, $speed))
}

function Add-CreditsAcquired {
    param([int]$Amount)

    if ($Amount -le 0) { return }
    if (-not $global:Player.ContainsKey("CreditsAcquired")) { $global:Player.CreditsAcquired = 0 }
    $global:Player.CreditsAcquired += $Amount
}
#endregion

#region ##### Mechanics #####

function Invoke-AutoAdministerHPConsumable {
    param([System.Collections.Generic.List[PSObject]]$SessionLog)

    while ($Player.HP -le 0) {
        $hpConsumables = @(
            $Inventory.Keys | ForEach-Object {
                $itemName = $_
                $itemMaster = $ResourceMaster[$itemName]
                if ($itemMaster.Consumable -and $itemMaster.Effect -eq "HP") {
                    [PSCustomObject]@{
                        Name        = $itemName
                        EffectValue = [int]$itemMaster.EffectValue
                        Value       = [int]$itemMaster.Value
                    }
                }
            } | Sort-Object EffectValue, Value, Name
        )

        if ($hpConsumables.Count -eq 0) { return $false }

        $currentHP = [Math]::Max(0, [int]$Player.HP)
        $neededHP = 1 - $currentHP
        $selected = @($hpConsumables | Where-Object { $_.EffectValue -ge $neededHP } | Select-Object -First 1)
        if ($selected.Count -eq 0) {
            $selected = @($hpConsumables | Sort-Object EffectValue, Value, Name -Descending | Select-Object -First 1)
        }
        $selected = $selected[0]

        $newHP = [Math]::Min($Player.MaxHP, $currentHP + $selected.EffectValue)
        $healAmount = [Math]::Max(0, $newHP - $currentHP)
        $Player.HP = $newHP
        if ($Inventory[$selected.Name] -le 1) { $Inventory.Remove($selected.Name) }
        else { $Inventory[$selected.Name]-- }

        $SessionLog.Insert(0, @{
            Style      = "AutoHP"
            HealAmount = $healAmount
            ItemName   = $selected.Name
            Rarity     = $ResourceMaster[$selected.Name].Rarity
        })
    }

    return $true
}

function Invoke-ProspectTick {
    param($PlanetData, [System.Collections.Generic.List[PSObject]]$SessionLog)

    $prospectFuelCost = 0.5
    if ([double]($Player.Fuel) -lt $prospectFuelCost) { return @{ Status = "Empty"; Damage = 0; AutoHealed = $false } }

    if ((Get-CurrentWeight) -ge $Player.MaxWeight) {
        $Player.Message = "Cargo hull is full!"
        return @{ Status = "Full"; Damage = 0; AutoHealed = $false }
    }

    $Player.Fuel = [math]::Max(0.0, [math]::Round(([double]($Player.Fuel) - $prospectFuelCost), 1))

    # --- Balanced Hazard Logic ---
    $finalDmg = 0
    $autoHealed = $false
    $effectiveHazard = Get-EffectiveHazard $PlanetData
    if ((Get-Random -Min 1 -Max 101) -le (Get-HazardEventChance $effectiveHazard)) {
        $reason = if ($PlanetData.HazardReasons) { $PlanetData.HazardReasons | Get-Random } else { "Hull stress" }
        $multiplier = Get-HazardDamageMultiplier $reason

        $baseDmg = Get-Random -Min 2 -Max 10
        $finalDmg = [int][math]::Max(1, ($baseDmg * $multiplier))
        $hpBeforeDamage = [Math]::Max(0, [int]$Player.HP)
        $actualDmg = [Math]::Min($finalDmg, $hpBeforeDamage)

        $Player.HP -= $finalDmg
        $SessionLog.Insert(0, @{ Text = "   -$finalDmg HP - $reason"; Color = "Red"; DamageAmount = $actualDmg })
    }

    if ($Player.HP -le 0) {
        if (-not ($Player.ContainsKey("autoadminister") -and $Player.autoadminister)) {
            return @{ Status = "Death"; Damage = $finalDmg; AutoHealed = $false }
        }

        $autoHealed = Invoke-AutoAdministerHPConsumable -SessionLog $SessionLog
        if (-not $autoHealed) {
            return @{ Status = "Death"; Damage = $finalDmg; AutoHealed = $false }
        }
    }
    if ($finalDmg -gt 0) { return @{ Status = "Continue"; Damage = $finalDmg; AutoHealed = $autoHealed } }

    $resourceTotal = ($PlanetData.Resources.Values | Measure-Object -Sum).Sum
    if ($resourceTotal -le 0) {
        return @{ Status = "Continue"; Damage = 0; AutoHealed = $autoHealed }
    }

    $roll = Get-Random -Minimum 1 -Maximum ($resourceTotal + 1)
    $cumulative = 0
    $resName = $null
    foreach ($kvp in $PlanetData.Resources.GetEnumerator()) {
        $cumulative += $kvp.Value
        if ($roll -le $cumulative) {
            $resName = $kvp.Key
            break
        }
    }

    if ($resName) {
        if ($Inventory.ContainsKey($resName)) { $Inventory[$resName]++ }
        else { $Inventory[$resName] = 1 }

        $SessionLog.Insert(0, @{
            Text           = "   +1 $resName"
            Color          = (Get-RarityColor $ResourceMaster[$resName].Rarity)
            ResourceAmount = 1
            ResourceName   = $resName
            Rarity         = $ResourceMaster[$resName].Rarity
        })
    }

    return @{ Status = "Continue"; Damage = 0; AutoHealed = $autoHealed }
}

function Get-ProspectLogValue {
    param($Entry, [string]$Name)

    if ($null -eq $Entry) { return $null }

    if ($Entry -is [System.Collections.IDictionary]) {
        if ($Entry.Contains($Name)) { return $Entry[$Name] }
        return $null
    }

    $property = $Entry.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }

    return $null
}

function Get-ProspectSessionSummary {
    param([System.Collections.Generic.List[PSObject]]$SessionLog)

    $resourceCount = 0
    $damageTotal = 0
    $healTotal = 0

    for ($i = 0; $i -lt $SessionLog.Count; $i++) {
        $entry = $SessionLog[$i]
        $style = Get-ProspectLogValue -Entry $entry -Name "Style"
        if ($style -eq "AutoHP") {
            $healTotal += [int](Get-ProspectLogValue -Entry $entry -Name "HealAmount")
            continue
        }

        $resourceAmount = Get-ProspectLogValue -Entry $entry -Name "ResourceAmount"
        if ($null -ne $resourceAmount) {
            $resourceCount += [int]$resourceAmount
            continue
        }

        $damageAmount = Get-ProspectLogValue -Entry $entry -Name "DamageAmount"
        if ($null -ne $damageAmount) {
            $damageTotal += [int]$damageAmount
            continue
        }

        $text = [string](Get-ProspectLogValue -Entry $entry -Name "Text")
        if ($text -match '^\s*\+(\d+)\s+') {
            $resourceCount += [int]$matches[1]
        } elseif ($text -match '^\s*-(\d+)\s+HP\b') {
            $damageTotal += [int]$matches[1]
        }
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add("+$resourceCount resources")
    if ($damageTotal -gt 0) { $parts.Add("-$damageTotal HP") }
    if ($healTotal -gt 0) { $parts.Add("+$healTotal HP auto-administered") }

    return " ( $($parts -join ', ') )"
}


function Prospect {
    $planetData = $CurrentSolarSystem[$Player.Location]
    $startTime = Get-Date
    $frackingEndTime = $null
    $sessionLog = New-Object System.Collections.Generic.List[PSObject]
    $targetScreenLines = 29
    $cryoSkipAvailable = [bool]$Player.CryoSkip
    $prospectComplete = $false
    $waitingToWake = $false
    $drillAnimationIntervalMs = Get-ProspectDrillAnimationInterval
    $animationMode = Get-ProspectAnimationMode
    $prospectTickIntervalMs = 1000
    $inputPollIntervalMs = 25
    $nextProspectTick = ([datetime]::new($startTime.Year, $startTime.Month, $startTime.Day, $startTime.Hour, $startTime.Minute, $startTime.Second)).AddMilliseconds($prospectTickIntervalMs)
    $nextAnimationRedraw = $startTime.AddMilliseconds($drillAnimationIntervalMs)
    $prospectRenderState = @{
        HeaderTop       = 0
        CanRepaint      = $false
        ScreenTop       = 0
        CanRedrawScreen = $false
        LastDrawLines   = 0
    }

    $WriteCurrentProspectHeader = {
        param([switch]$RepaintOnly, [switch]$ClearLines)

        if ($RepaintOnly -and -not $prospectRenderState.CanRepaint) { return $false }

        $restoreLeft = 0
        $restoreTop = 0
        if ($RepaintOnly) {
            try {
                $restoreLeft = [Console]::CursorLeft
                $restoreTop = [Console]::CursorTop
                [Console]::SetCursorPosition(0, [int]$prospectRenderState.HeaderTop)
            } catch {
                $prospectRenderState.CanRepaint = $false
                return $false
            }
        }

        $now = Get-Date
        $elapsed = $now - $startTime
        $effHz = Get-EffectiveHazard $planetData
        $baseHz = Get-BaseHazard $planetData
        $planetNameColor = if ($planetData.PlanetColor) { $planetData.PlanetColor } else { "White" }
        $planetType = if ($planetData.Type) { $planetData.Type } else { "Unknown" }
        $planetTypeColor = Get-PlanetTypeColor $planetType
        $drillFrameIndex = [int][math]::Floor($elapsed.TotalMilliseconds / $drillAnimationIntervalMs)
        $frackingRenderFrameIndex = [int][math]::Floor($elapsed.TotalMilliseconds / 500)

        Write-ProspectDrillHeader `
            -FrameIndex $drillFrameIndex `
            -FrackingFrameIndex $frackingRenderFrameIndex `
            -PlanetName $Player.Location `
            -PlanetColor $planetNameColor `
            -PlanetType $planetType `
            -PlanetTypeColor $planetTypeColor `
            -EffectiveHazard $effHz `
            -BaseHazard $baseHz `
            -ClearLines:$ClearLines

        if ($RepaintOnly) {
            try {
                [Console]::SetCursorPosition($restoreLeft, $restoreTop)
            } catch {
                $prospectRenderState.CanRepaint = $false
                return $false
            }
        }

        return $true
    }

    $DrawUI = {
        if ($prospectRenderState.CanRedrawScreen) {
            try {
                [Console]::SetCursorPosition(0, [int]$prospectRenderState.ScreenTop)
            } catch {
                $prospectRenderState.CanRedrawScreen = $false
                $prospectRenderState.CanRepaint = $false
                Clear-Host
                try { $prospectRenderState.ScreenTop = [Console]::CursorTop } catch { $prospectRenderState.ScreenTop = 0 }
            }
        } else {
            Clear-Host
            try { $prospectRenderState.ScreenTop = [Console]::CursorTop } catch { $prospectRenderState.ScreenTop = 0 }
        }

        $ClearProspectLine = {
            if ($prospectRenderState.CanRedrawScreen) { Clear-CurrentConsoleLine }
        }

        $headerExtraLines = 0
        if ($Player.Message -or $Player.LastLoot) { $headerExtraLines += 1 }
        if ($Player.Dialog) { $headerExtraLines += 2 }
        $showControls = -not $prospectComplete
        $footerLines = 2
        if ($waitingToWake) {
            $footerLines += 1
        } elseif ($showControls) {
            $footerLines += 1
            if ($cryoSkipAvailable) { $footerLines += 1 }
        }
        $fixedLines = 1 + $headerExtraLines + 4 + 1 + $footerLines
        $maxVisibleLines = [math]::Max(1, $targetScreenLines - $fixedLines)

        Show-Header -Prospecting -NoClear
        try {
            $prospectRenderState.HeaderTop = [Console]::CursorTop
            $prospectRenderState.CanRepaint = $true
        } catch {
            $prospectRenderState.CanRepaint = $false
        }
        $null = &$WriteCurrentProspectHeader -ClearLines:([bool]$prospectRenderState.CanRedrawScreen)

        for ($i = 0; $i -lt $maxVisibleLines; $i++) {
            &$ClearProspectLine
            if ($i -lt $sessionLog.Count) { 
                $entry = $sessionLog[$i]
                if ($entry.Style -eq "AutoHP") {
                    Write-Host -NoNewline "   "
                    Write-Host -NoNewline "   +$($entry.HealAmount) HP - " -ForegroundColor Green
                    Write-RarityText -Text $entry.ItemName -Rarity $entry.Rarity -NoNewline
                    Write-Host " auto-administered." -ForegroundColor DarkGray
                } elseif (Get-ProspectLogValue -Entry $entry -Name "ResourceName") {
                    $resourceName = Get-ProspectLogValue -Entry $entry -Name "ResourceName"
                    $resourceAmount = Get-ProspectLogValue -Entry $entry -Name "ResourceAmount"
                    $resourceRarity = Get-ProspectLogValue -Entry $entry -Name "Rarity"
                    if ($null -eq $resourceAmount) { $resourceAmount = 1 }
                    Write-Host -NoNewline "   "#                                            
                    Write-Host -NoNewline "   +$resourceAmount " -ForegroundColor $entry.Color
                    Write-RarityText -Text $resourceName -Rarity $resourceRarity
                } else {
                    Write-Host "   $($entry.Text)" -ForegroundColor $entry.Color
                }
            } 
            else { Write-Host "" }
        }

        &$ClearProspectLine
        if ($sessionLog.Count -gt $maxVisibleLines) {
            $hiddenCount = $sessionLog.Count - $maxVisibleLines
            Write-Host "      ($hiddenCount more...)" -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }
        &$ClearProspectLine
        Write-Host -NoNewLine "   Fracking for: "
        $elapsed = (Get-Date) - $startTime
        Write-Host -NoNewline "$($elapsed.ToString('mm\:ss'))" -ForegroundColor Cyan
        Write-Host (Get-ProspectSessionSummary -SessionLog $sessionLog) -ForegroundColor DarkGray
        if ($waitingToWake) {
            &$ClearProspectLine
            Write-Host -NoNewline "   Press "
            Write-Host -NoNewline "[ANY KEY]" -ForegroundColor DarkCyan
            Write-Host " to wake up..."
        } elseif ($showControls) {
			if ($cryoSkipAvailable) {
                &$ClearProspectLine
                Write-Host -NoNewline "   Press "
                Write-Host -NoNewline "[" -ForegroundColor DarkGray
				Write-Host -NoNewline "C" -ForegroundColor Cyan
				Write-Host -NoNewline "]" -ForegroundColor DarkGray
                Write-Host -NoNewline " to "
				Write-Host -NoNewline "Cryo-Sleep" -ForegroundColor Cyan
				Write-Host -NoNewline " for "
                Write-Host -NoNewline "1 year" -ForegroundColor Red
				Write-Host "... "
            }
            &$ClearProspectLine
            Write-Host -NoNewline "   Press "
            $stopKeyLabel = if ($cryoSkipAvailable) { "[ANY OTHER KEY]" } else { "[ANY KEY]" }
            Write-Host -NoNewline $stopKeyLabel -ForegroundColor DarkCyan
            Write-Host " to stop fracking..."
        }

        try {
            $drawEndTop = [Console]::CursorTop
            $drawnLines = [Math]::Max(0, $drawEndTop - [int]$prospectRenderState.ScreenTop)
            if ([int]$prospectRenderState.LastDrawLines -gt $drawnLines) {
                for ($lineOffset = $drawnLines; $lineOffset -lt [int]$prospectRenderState.LastDrawLines; $lineOffset++) {
                    [Console]::SetCursorPosition(0, [int]$prospectRenderState.ScreenTop + $lineOffset)
                    Clear-CurrentConsoleLine
                }
                [Console]::SetCursorPosition(0, $drawEndTop)
            }

            $prospectRenderState.LastDrawLines = $drawnLines
            $prospectRenderState.CanRedrawScreen = $true
        } catch {
            $prospectRenderState.CanRedrawScreen = $false
        }
    }

    $previousCursorVisible = $true
    $hadCursorState = $false
    try {
        $previousCursorVisible = [Console]::CursorVisible
        [Console]::CursorVisible = $false
        $hadCursorState = $true
    } catch {
        $hadCursorState = $false
    }

    try {
        $null = &$DrawUI

    while ($true) {
        $now = Get-Date
        if ($now -ge $nextProspectTick) {
            $tick = Invoke-ProspectTick -PlanetData $planetData -SessionLog $sessionLog
            Add-ProspectTime

            $redrewAfterTick = $false
            if ($tick.AutoHealed) {
                Flash-DamageBackground -FlashColor "Green" -RedrawAction $DrawUI -NoClear
                $redrewAfterTick = $true
            } elseif ($tick.Damage -ge 10) {
                Flash-DamageBackground -FlashColor "DarkRed" -RedrawAction $DrawUI -NoClear
                $redrewAfterTick = $true
            }

            if ($tick.Status -ne "Continue") {
                $frackingEndTime = Get-Date
                break
            }

            if (-not $redrewAfterTick) {
                $null = &$DrawUI
            }

            $afterTick = Get-Date
            do {
                $nextProspectTick = $nextProspectTick.AddMilliseconds($prospectTickIntervalMs)
            } while ($nextProspectTick -le $afterTick)
        }

        $exitLoop = $false
        $cryoSkip = $false

        if ([Console]::KeyAvailable) {
            $keyInfo = [Console]::ReadKey($true)
            if ($cryoSkipAvailable -and $keyInfo.Key -eq [System.ConsoleKey]::C) { $cryoSkip = $true }
            else { $exitLoop = $true }
        }

        if (-not $exitLoop -and -not $cryoSkip -and (Get-Date) -ge $nextAnimationRedraw) {
            switch ($animationMode) {
                "Repaint" {
                    $repainted = &$WriteCurrentProspectHeader -RepaintOnly
                    if (-not $repainted) {
                        $null = &$DrawUI
                    }
                }
                "Off" {}
            }

            $afterAnimation = Get-Date
            do {
                $nextAnimationRedraw = $nextAnimationRedraw.AddMilliseconds($drillAnimationIntervalMs)
            } while ($nextAnimationRedraw -le $afterAnimation)
        }

        if (-not $exitLoop -and -not $cryoSkip) {
            $now = Get-Date
            $sleepMs = $inputPollIntervalMs
            $tickWaitMs = [int][math]::Ceiling(($nextProspectTick - $now).TotalMilliseconds)
            if ($tickWaitMs -le 0) { $sleepMs = 1 }
            else { $sleepMs = [math]::Min($sleepMs, $tickWaitMs) }

            if ($animationMode -eq "Repaint") {
                $animationWaitMs = [int][math]::Ceiling(($nextAnimationRedraw - $now).TotalMilliseconds)
                if ($animationWaitMs -le 0) { $sleepMs = 1 }
                else { $sleepMs = [math]::Min($sleepMs, $animationWaitMs) }
            }

            Start-Sleep -Milliseconds ([math]::Max(1, $sleepMs))
        }

        if ($cryoSkip) {
            if (-not $Player.ContainsKey("TimesSlept")) { $Player.TimesSlept = 0 }
            $Player.TimesSlept++
            Flash-DamageBackground -FlashColor "Cyan" -RedrawAction $DrawUI -NoClear

            # Cryo-Skip: resolve all remaining ticks instantly until a natural end condition
            $finalStatus = "Continue"
            while ($true) {
                $tick = Invoke-ProspectTick -PlanetData $planetData -SessionLog $sessionLog
                Add-ProspectTime -Skipped
                $finalStatus = $tick.Status
                if ($tick.Status -ne "Continue") { break }
            }
            $prospectComplete = $true
            $frackingEndTime = Get-Date
            if ($finalStatus -eq "Death") {
                &$DrawUI
            } else {
                $waitingToWake = $true
                &$DrawUI
                [Console]::ReadKey($true) | Out-Null
                $waitingToWake = $false
            }
            break
        }

        if ($exitLoop) {
            $frackingEndTime = Get-Date
            break
        }
    }
    } finally {
        if ($null -eq $frackingEndTime) { $frackingEndTime = Get-Date }
        if (-not $Player.ContainsKey("RealTimeFracked")) { $Player.RealTimeFracked = 0 }

        $existingRealTimeFracked = 0
        if (-not [int]::TryParse(([string]$Player.RealTimeFracked), [ref]$existingRealTimeFracked)) {
            $existingRealTimeFracked = 0
        }
        $sessionSecondsFracked = [int][math]::Max(0, [math]::Floor(($frackingEndTime - $startTime).TotalSeconds))
        $Player.RealTimeFracked = $existingRealTimeFracked + $sessionSecondsFracked

        if ($hadCursorState) {
            try {
                [Console]::CursorVisible = $previousCursorVisible
            } catch {}
        }
    }
}

function Add-Item {
    param([string]$ItemName, [int]$Qty = 1)
    if ($Inventory.ContainsKey($ItemName)) { $Inventory[$ItemName] += $Qty }
    else { $Inventory[$ItemName] = $Qty }
}

function Use-Item($ItemName) {
    if (-not $Inventory.ContainsKey($ItemName)) { return }
    $itemMaster = $ResourceMaster[$ItemName]
    if (-not $itemMaster.Consumable) { return }

    switch ($itemMaster.Effect) {
        "Fuel"      { $Player.Fuel = [Math]::Min($Player.MaxFuel, [math]::Round(([double]($Player.Fuel) + [double]($itemMaster.EffectValue)), 1)) }
        "MaxFuel"   { $Player.MaxFuel = [math]::Round(([double]($Player.MaxFuel) + [double]($itemMaster.EffectValue)), 1); $Player.Fuel = [math]::Round(([double]($Player.Fuel) + [double]($itemMaster.EffectValue)), 1) }
        "HP"        { $Player.HP   = [Math]::Min($player.MaxHP, $Player.HP   + $itemMaster.EffectValue) }
		"MaxHP"        { $Player.MaxHP += $itemMaster.EffectValue; $Player.HP += $itemMaster.EffectValue }
        "MaxWeight"  { $Player.MaxWeight += $itemMaster.EffectValue }
        "frackGas"       { Add-PlayerUpgradeStack "frackGas" $itemMaster.EffectValue }
        "frackIce"       { Add-PlayerUpgradeStack "frackIce" $itemMaster.EffectValue }
        "frackTerr"      { Add-PlayerUpgradeStack "frackTerr" $itemMaster.EffectValue }
        "frackAst"       { Add-PlayerUpgradeStack "frackAst" $itemMaster.EffectValue }
        "frackDwarf"     { Add-PlayerUpgradeStack "frackDwarf" $itemMaster.EffectValue }
        "RadiationSuit"   { $Player.RadiationSuit   = $true }
        "autoadminister"  { $Player.autoadminister  = $true }
        "XRFScanner"      { $Player.XRFScanner      = $true }
        "CryoSkip"        { $Player.CryoSkip        = $true }
        "Hyperdrive"      { $Player.Hyperdrive       = $true }
    }

    if ($Inventory[$ItemName] -le 1) { $Inventory.Remove($ItemName) }
    else { $Inventory[$ItemName]-- }
    $effectText = if ($itemMaster.Effect) { " ($(Get-ItemEffectText $itemMaster))" } else { "" }
    $Player.Message = "Used $ItemName$effectText."
}

function Confirm-InventoryConsumableUse {
    param([string]$ItemName)

    if (-not $Inventory.ContainsKey($ItemName)) { return $false }
    $itemMaster = $ResourceMaster[$ItemName]
    if (-not $itemMaster.Consumable) { return $false }

    $maxUnits = 0.0
    $appliedUnits = 0.0

    switch ($itemMaster.Effect) {
        "Fuel" {
            $maxUnits = [double]$itemMaster.EffectValue
            $missingFuel = [math]::Max(0.0, [double]$Player.MaxFuel - [double]$Player.Fuel)
            $appliedUnits = [math]::Round([math]::Min($maxUnits, $missingFuel), 1)
        }
        "HP" {
            $maxUnits = [double]$itemMaster.EffectValue
            $missingHP = [math]::Max(0, [int]$Player.MaxHP - [int]$Player.HP)
            $appliedUnits = [math]::Min($maxUnits, $missingHP)
        }
        default {
            return $true
        }
    }

    if ($appliedUnits -ge $maxUnits) { return $true }

    $appliedText = if (($appliedUnits % 1) -eq 0) { [string][int]$appliedUnits } else { Format-Fuel $appliedUnits }
    $maxText = if (($maxUnits % 1) -eq 0) { [string][int]$maxUnits } else { Format-Fuel $maxUnits }

    Write-Host -NoNewline "Use " -ForegroundColor Gray
    Write-RarityText -Text $ItemName -Rarity $itemMaster.Rarity -NoNewline
    Write-Host -NoNewline " for " -ForegroundColor Gray
    Write-Host -NoNewline $appliedText -ForegroundColor Yellow
    Write-Host -NoNewline "/" -ForegroundColor DarkGray
    Write-Host -NoNewline $maxText -ForegroundColor Yellow
    Write-Host -NoNewline " Units? Press " -ForegroundColor Gray
    Write-Host -NoNewline "Y" -ForegroundColor Yellow
    Write-Host -NoNewline " to confirm... " -ForegroundColor Gray

    try {
        $confirm = [Console]::ReadKey($true)
        return (([string]$confirm.KeyChar).ToUpper() -eq "Y")
    } catch {
        $confirm = Read-Host
        return ($null -ne $confirm -and $confirm.ToUpper().Trim() -eq "Y")
    }
}

function Invoke-JettisonCargo {
    param(
        [string]$ItemName,
        [hashtable]$ActiveRequirements
    )

    if (-not $Inventory.ContainsKey($ItemName)) { return }
    $itemMaster = $ResourceMaster[$ItemName]
    if ($itemMaster.Consumable) { return }

    $ownedQty = [int]$Inventory[$ItemName]
    if ($ownedQty -le 0) { return }

    Write-Host -NoNewline "Jettison quantity " -ForegroundColor Gray
    Write-Host -NoNewline "(" -ForegroundColor DarkGray
    Write-Host -NoNewline "A" -ForegroundColor Yellow
    Write-Host -NoNewline " all" -ForegroundColor Gray
    Write-Host -NoNewline ", " -ForegroundColor DarkGray
    Write-Host -NoNewline "Q" -ForegroundColor Yellow
    Write-Host -NoNewline " quest surplus" -ForegroundColor Gray
    Write-Host -NoNewline "): " -ForegroundColor DarkGray
    $quantityInput = [Console]::ReadLine()
    if ($null -eq $quantityInput) { return }
    $quantityInput = $quantityInput.ToUpper().Trim()
    if ([string]::IsNullOrWhiteSpace($quantityInput)) { return }

    $jettisonQty = 0
    if ($quantityInput -eq "A") {
        $jettisonQty = $ownedQty
    } elseif ($quantityInput -eq "Q") {
        $reservedQty = if ($ActiveRequirements -and $ActiveRequirements.ContainsKey($ItemName)) { [int]$ActiveRequirements[$ItemName] } else { 0 }
        $jettisonQty = [math]::Max(0, $ownedQty - $reservedQty)
    } else {
        $parsedQty = 0
        if (-not [int]::TryParse($quantityInput, [ref]$parsedQty)) { return }
        $jettisonQty = $parsedQty
    }

    if ($jettisonQty -le 0 -or $jettisonQty -gt $ownedQty) { return }

    Write-Host -NoNewline "Jettison" -ForegroundColor DarkRed
    Write-Host -NoNewline " " -ForegroundColor Gray
    Write-Host -NoNewline $jettisonQty -ForegroundColor (Get-RarityColor $itemMaster.Rarity)
    Write-Host -NoNewline " " -ForegroundColor Gray
    Write-RarityText -Text $ItemName -Rarity $itemMaster.Rarity -NoNewline
    Write-Host -NoNewline "? " -ForegroundColor Gray
    Write-Host -NoNewline "Y" -ForegroundColor Yellow
    Write-Host -NoNewline " to confirm... " -ForegroundColor Gray
    $confirm = [Console]::ReadLine()
    if ($null -eq $confirm -or $confirm.ToUpper().Trim() -ne "Y") { return }

    if ($Inventory[$ItemName] -le $jettisonQty) { $Inventory.Remove($ItemName) }
    else { $Inventory[$ItemName] -= $jettisonQty }

    $Player.Message = "Jettisoned $jettisonQty $ItemName."
}
#endregion 

#region ##### Menu functions #####
function Write-PlayerNotice {
    if ($Player.Message) {
        Write-Host "   $($Player.Message)" -ForegroundColor DarkGray
        $Player.Message = $null
        return $true
    }

    if ($Player.LastLoot) {
        Write-Host -NoNewline "   "
        Write-Host -NoNewline "+$($Player.LastLoot.Quantity) " -ForegroundColor Green
        Write-RarityText -Text $Player.LastLoot.Name -Rarity $Player.LastLoot.Rarity
        $Player.LastLoot = $null
        return $true
    }

    return $false
}

function Write-TraderContextLine {
    param([string]$Mode, [string]$TraderName, [int]$Credits, [string]$Notice = $null)

    Write-Host -NoNewline "   $Mode $TraderName" -ForegroundColor DarkGray
    Write-Host -NoNewline " | Trader wealth: " -ForegroundColor DarkGray
    Write-Host -NoNewline $Credits -ForegroundColor DarkYellow
    Write-Host -NoNewline " CD" -ForegroundColor Yellow
    if ($Notice) {
        Write-Host -NoNewline " **$Notice**" -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Show-Header {
    param([switch]$Prospecting, [switch]$SuppressNotice, [switch]$NoTrailingBlank, [switch]$NoClear)
    if (-not $NoClear) { Clear-Host }
    $planetData = $CurrentSolarSystem[$Player.Location]
    $weight = Get-CurrentWeight
    $hpCol = Get-PercentColor -Current $Player.HP -Max $player.MaxHP
    $fuelCol = Get-PercentColor -Current $Player.Fuel -Max $Player.MaxFuel
    $wtCol = Get-PercentColor -Current $weight -Max $Player.MaxWeight -Inverted
    $headerWidth = $script:SpaceFrackLayoutWidth
    $headerHz = Get-EffectiveHazard $planetData

    $leftSegments = @(
		(New-ProspectAsciiSegment -Text "Credits" -Color "White"),
        (New-ProspectAsciiSegment -Text "="),
        (New-ProspectAsciiSegment -Text ([string]$Player.Credits) -Color "Yellow"),
        (New-ProspectAsciiSegment -Text "|" -Color "DarkGray"),
		(New-ProspectAsciiSegment -Text "Health" -Color "White"),
        (New-ProspectAsciiSegment -Text "="),
        (New-ProspectAsciiSegment -Text ([string]$Player.HP) -Color $hpCol),
        (New-ProspectAsciiSegment -Text "/$($Player.MaxHP)"),
        (New-ProspectAsciiSegment -Text "|" -Color "DarkGray"),
		(New-ProspectAsciiSegment -Text "Fuel" -Color "White"),
        (New-ProspectAsciiSegment -Text "="),
        (New-ProspectAsciiSegment -Text "$(Format-Fuel $Player.Fuel)" -Color $fuelCol),
        (New-ProspectAsciiSegment -Text "/$(Format-Fuel $Player.MaxFuel)"),
        (New-ProspectAsciiSegment -Text "|" -Color "DarkGray"),
		(New-ProspectAsciiSegment -Text "Weight" -Color "White"),
        (New-ProspectAsciiSegment -Text "="),
        (New-ProspectAsciiSegment -Text ([string]$weight) -Color $wtCol),
        (New-ProspectAsciiSegment -Text "/$($Player.MaxWeight)")
    )

    if ($Prospecting) {
        $rightSegments = @(
            (New-ProspectAsciiSegment -Text (Get-Clock))
        )
    } else {
        $rightSegments = @(
            (New-ProspectAsciiSegment -Text "Orbiting:"),
            (New-ProspectAsciiSegment -Text $Player.Location -Color ($planetData.PlanetColor)),
			(New-ProspectAsciiSegment -Text " (" -Color "DarkGray"),
            (New-ProspectAsciiSegment -Text "HZ="),
            (New-ProspectAsciiSegment -Text ([string]$headerHz) -Color (Get-HazardColor $headerHz)),
            (New-ProspectAsciiSegment -Text ") " -Color "DarkGray"),
            (New-ProspectAsciiSegment -Text (Get-Clock))
        )
    }

    $leftLength = Get-ProspectAsciiSegmentTextLength -Segments $leftSegments
    $rightLength = Get-ProspectAsciiSegmentTextLength -Segments $rightSegments
    $paddingWidth = [Math]::Max(1, $headerWidth - $leftLength - $rightLength)
    $headerSegments = @($leftSegments)
    $headerSegments += New-ProspectAsciiSegment -Text (" " * $paddingWidth) -Color "DarkGray"
    $headerSegments += $rightSegments
    Write-ProspectAsciiSegmentRow -Segments $headerSegments -ClearLine:$NoClear

    if (-not $SuppressNotice) {
        if ($NoClear -and ($Player.Message -or $Player.LastLoot)) { Clear-CurrentConsoleLine }
        Write-PlayerNotice | Out-Null
    }

    if ($Player.Dialog) {
        if ($NoClear) { Clear-CurrentConsoleLine }
        Write-Host ""
        if ($NoClear) { Clear-CurrentConsoleLine }
        $PlanetColor = if ($planetData.Inhabited -and $planetData.ContainsKey("PlanetColor")) { $planetData.PlanetColor } else { "Gray" }
        Write-Host -NoNewline "> Incoming transmission from "
        Write-Host -NoNewline "$($planetData.TraderName)" -ForegroundColor $PlanetColor
        Write-Host ":"
        if ($NoClear) { Clear-CurrentConsoleLine }
        Write-Host -NoNewline "   `"" 
        Write-Host -NoNewline $Player.Dialog -ForegroundColor $PlanetColor
        Write-Host "`""
        $Player.Dialog = $null
    }
    if (-not $NoTrailingBlank) {
        if ($NoClear) { Clear-CurrentConsoleLine }
        Write-Host ""
    }
}

function Show-XRFScan {
    $scanCost = 75.0
    $planetData = $CurrentSolarSystem[$Player.Location]

    if ($Player.Fuel -lt $scanCost) {
        $Player.Message = "Insufficient fuel for XRF8 scan ($(Format-Fuel $scanCost) FL required)."
        return
    }

    $Player.Fuel = [math]::Round(([double]($Player.Fuel) - $scanCost), 1)

    # Build noisy readings: multiply each resource weight by a random factor 0.72-1.28
    $noisyResources = @{}
    foreach ($kvp in $planetData.Resources.GetEnumerator()) {
        if ($ResourceMaster[$kvp.Key].Rarity -eq "Upgrade") { continue }
        $factor = (Get-Random -Minimum 75 -Maximum 126) / 100.0
        $noisyResources[$kvp.Key] = [math]::Max(1, [int]($kvp.Value * $factor))
    }
    $noisyTotal = ($noisyResources.Values | Measure-Object -Sum).Sum

    # Sort by noisy weight descending (order itself has noise)
    $sorted = $noisyResources.GetEnumerator() | Sort-Object Value -Descending
    $maxReading = [math]::Max(1, ($noisyResources.Values | Measure-Object -Maximum).Maximum)

    $planetColor = $planetData.PlanetColor

    while ($true) {
        Show-Header
        Write-Host -NoNewline "##### XRF8 SCAN - " -ForegroundColor Cyan
        Write-Host -NoNewline $Player.Location.ToUpper() -ForegroundColor $planetColor
        Write-Host " #####" -ForegroundColor Cyan
        Write-Host ""

        foreach ($kvp in $sorted) {
            $pct = [math]::Round($kvp.Value / $noisyTotal * 100)
            $barLen = [math]::Max(1, [math]::Round(($kvp.Value / $maxReading) * 20))
            $bar = ("#" * $barLen).PadRight(20)
            $rarColor = Get-RarityColor $ResourceMaster[$kvp.Key].Rarity
            Write-Host -NoNewline "   "
            Write-RarityText -Text $kvp.Key.PadRight(24) -Rarity $ResourceMaster[$kvp.Key].Rarity -NoNewline
            Write-Host -NoNewline "[" -ForegroundColor DarkGray
            Write-Host -NoNewline $bar -ForegroundColor $rarColor
            Write-Host -NoNewline "] " -ForegroundColor DarkGray
            Write-Host "~$pct%" -ForegroundColor Gray
        }

        Write-Host ""
        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"
        $choice = (Read-Host ">").ToUpper().Trim()
        if ($choice -eq "E" -or $choice -eq "") { return }
    }
}

function Show-StatusReport {
    $gadgetUpgrades = @(
        @{ Flag = "XRFScanner";    Name = "XRF8 Scanner";                 Effect = "Reveals approximate resource composition from orbit (75.0 FL)." }
        @{ Flag = "CryoSkip";      Name = "Cryo-Sleep Chamber";           Effect = "Cryo-sleep chamber operates in 1 year increments only. Sleep smart." }
        @{ Flag = "Hyperdrive";    Name = "HyperDrive Module";            Effect = "Enables interstellar travel." }
        @{ Flag = "autoadminister"; Name = "Shield Cell Auto-Injector";    Effect = "Automatically administers shield cells while fracking." }
        @{ Flag = "frackGas";       Name = "Gas Giant Surveyor";  Effect = "50% hazard reduction per stack on Gas Giants." }
        @{ Flag = "frackIce";       Name = "Ice Giant Surveyor";  Effect = "50% hazard reduction per stack on Ice Giants." }
        @{ Flag = "frackTerr";      Name = "Terrain Hardening Kit";        Effect = "20% hazard reduction per stack on Terrestrial planets." }
        @{ Flag = "frackAst";       Name = "Asteroid Surveyer";          Effect = "50% hazard reduction per stack on Asteroid bodies." }
        @{ Flag = "frackDwarf";     Name = "Dwarf-Class Surveyor";         Effect = "30% hazard reduction per stack on Dwarf planets." }
        @{ Flag = "RadiationSuit"; Name = "Rad-Shielding Exosuit";        Effect = "25% hazard reduction on any planet with base HZ80+." }
    )
    $labelW = 22

    while ($true) {
        Show-Header
        Write-Host "##### " -ForegroundColor DarkGray -NoNewLine
		Write-Host "STATUS REPORT" -ForegroundColor DarkCyan -NoNewLine
		Write-Host " #####" -ForegroundColor DarkGray
        Write-Host ""

        # -- Session --
        Write-Host "   --- Session ---" -ForegroundColor DarkGray
        Write-Host -NoNewline ("   Version").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host $SpacegameVersion -ForegroundColor White
        Write-Host -NoNewline ("   System").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host $Player.System -ForegroundColor Cyan
        $locColor = if ($global:CurrentSolarSystem.ContainsKey($Player.Location)) { $global:CurrentSolarSystem[$Player.Location].PlanetColor } else { "White" }
        Write-Host -NoNewline ("   Location").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host $Player.Location -ForegroundColor $locColor
        Write-Host -NoNewline ("   Credits Acquired").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host -NoNewline $Player.CreditsAcquired -ForegroundColor Yellow
        Write-Host " CD" -ForegroundColor DarkYellow
        Write-Host -NoNewline ("   Session Time").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host (Get-SurvivedTime) -ForegroundColor Yellow
        $timeFrackedSeconds = Get-PlayerDurationStatSeconds -Name "TimeFracked"
        $realTimeFrackedSeconds = Get-PlayerDurationStatSeconds -Name "RealTimeFracked"
        $timeSleptSeconds = Get-PlayerDurationStatSeconds -Name "TimeSlept"
        if ($realTimeFrackedSeconds -ne $timeFrackedSeconds) {
            Write-Host -NoNewline ("   Real Fracking Time").PadRight($labelW) -ForegroundColor DarkGray
            Write-Host (Get-RealTimeFracked) -ForegroundColor Yellow
        }
        Write-Host -NoNewline ("   Time Fracked").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host (Get-TimeFracked) -ForegroundColor Yellow
        if ($timeSleptSeconds -gt 0) {
            Write-Host -NoNewline ("   Cryo Time Skipped").PadRight($labelW) -ForegroundColor DarkGray
            Write-Host (Get-TimeSlept) -ForegroundColor Yellow
        }
        $yearsSlept = if ($Player.ContainsKey("TimesSlept")) { [int]$Player.TimesSlept } else { 0 }
        if ($yearsSlept -gt 0) {
            Write-Host -NoNewline ("   Years elapsed").PadRight($labelW) -ForegroundColor DarkGray
            Write-Host $yearsSlept -ForegroundColor Yellow
        }
        Write-Host ""

        # -- Installed Upgrades --
        Write-Host "   --- Installed Upgrades ---" -ForegroundColor DarkGray
        $installedAny = $false
        foreach ($upg in $gadgetUpgrades) {
            $stackCount = if (Test-StackingHazardUpgrade $upg.Flag) { Get-PlayerUpgradeStack $upg.Flag } else { if ($Player.ContainsKey($upg.Flag) -and $Player[$upg.Flag]) { 1 } else { 0 } }
            if ($stackCount -gt 0) {
                $installedAny = $true
                Write-Host -NoNewline "   "
                $nameText = if ($stackCount -gt 1) { "$($upg.Name) x$stackCount" } else { $upg.Name }
                Write-Host -NoNewline $nameText.PadRight(34) -ForegroundColor DarkGreen
                Write-Host $upg.Effect -ForegroundColor DarkGray
            }
        }
        if (-not $installedAny) {
            Write-Host "   None installed." -ForegroundColor DarkGray
        }
        Write-Host ""

        # -- Contract Summary --
        Write-Host "   --- Contract Summary ---" -ForegroundColor DarkGray
        $qActive = 0; $qComplete = 0; $qNA = 0
        foreach ($sys in @($global:SolSystem, $global:SolSystem2)) {
            foreach ($pKey in $sys.Keys) {
                if ($pKey -eq "_Metadata") { continue }
                $pData = $sys[$pKey]
                if (-not $pData.ContainsKey("Quests")) { continue }
                foreach ($quest in $pData.Quests) {
                    if ($global:QuestState.ContainsKey($quest.Id)) {
                        $qs = $global:QuestState[$quest.Id].Status
                        if ($qs -eq "Active")    { $qActive++ }
                        elseif ($qs -eq "Complete") { $qComplete++ }
                    } else { $qNA++ }
                }
            }
        }
        Write-Host -NoNewline ("   Active").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host $qActive -ForegroundColor Cyan
        Write-Host -NoNewline ("   Complete").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host $qComplete -ForegroundColor Green
        Write-Host -NoNewline ("   Not Accepted").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host $qNA -ForegroundColor DarkGray
        Write-Host ""

        # -- Known Locations --
        Write-Host "   --- Known Locations ---" -ForegroundColor DarkGray
        $knownList = @($Player.Known | Where-Object { $_ -notlike "Trader:*" }) -join ", "
        Write-Host "   $knownList" -ForegroundColor DarkCyan
        Write-Host ""

        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"
        $choice = (Read-Host ">").ToUpper().Trim()
        if ($choice -eq "E" -or $choice -eq "") { return }
    }
}

function Show-SettingsMenu {
    $settingsNotice = $null

    while ($true) {
        Show-Header -SuppressNotice -NoTrailingBlank
        if ($settingsNotice) {
            Write-Host "   $settingsNotice" -ForegroundColor DarkGray
            $settingsNotice = $null
        } else {
            $noticeShown = Write-PlayerNotice
            if (-not $noticeShown) { Write-Host "" }
        }
        #Write-Host ""
        Write-Host "##### " -ForegroundColor DarkGray -NoNewLine
		Write-Host "Settings Menu" -ForegroundColor White -NoNewLine
		Write-Host " #####" -ForegroundColor DarkGray
        Write-Host ""

        Write-SettingsSection "Persistence"
        Write-MenuKey "1" "Cyan" "Save game"
        Write-MenuKey "2" "Cyan" "Load game"
        Write-Host ""

        Write-SettingsSection "Drill Animation"
        Write-SettingsModeLine
        Write-SettingsOptionPrefix "4" "Speed"
        Write-Host "$(Get-ProspectDrillAnimationInterval) ms" -ForegroundColor Green
        Write-Host ""

        Write-SettingsSection "Other"
        Write-Host -NoNewline "[" -ForegroundColor DarkGray
        Write-Host -NoNewline "R" -ForegroundColor Cyan
        Write-Host -NoNewline "] " -ForegroundColor DarkGray
        Write-Host -NoNewline "Rename Pilot" -ForegroundColor DarkCyan
        Write-Host -NoNewline ":" -ForegroundColor Gray
        $pilotName = if ($global:Player.ContainsKey("SaveName") -and -not [string]::IsNullOrWhiteSpace($global:Player.SaveName)) { $global:Player.SaveName } else { "(unset)" }
        Write-Host " $pilotName" -ForegroundColor DarkGray
        Write-MenuKey "F" "DarkCyan" "Status Report"
        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"

        $choice = (Read-Host ">").ToUpper().Trim()
        if ($choice -eq "1" -or $choice -eq "S") {
            $savedPath = Save-Game
            if ($savedPath) { $settingsNotice = "Saved: $savedPath" }
            elseif ($global:Player.Message) { $settingsNotice = $global:Player.Message }
            $global:Player.Message = $null
            continue
        } elseif ($choice -eq "2" -or $choice -eq "L")  {
            $loaded = Show-LoadMenu
            if ($loaded -eq "Loaded") { return "Loaded" }
            continue
        } elseif ($choice -eq "3") {
            Set-NextProspectAnimationMode
            continue
        } elseif ($choice -eq "4") {
            Read-ProspectAnimationSpeed
            continue
        } elseif ($choice -eq "R") {
            $global:Player.SaveName = Read-SaveName
            $global:Player.Message = "Pilot renamed: $($global:Player.SaveName)"
            continue
        } elseif ($choice -eq "F") {
            Show-StatusReport
            continue
        } elseif ($choice -eq "E" -or $choice -eq "") {
            return "Back"
        }
    }
}

function Show-Inventory {
    while ($true) {
        $activeRequirements = Get-ActiveQuestRequirements

        $inventoryWorth = 0
        $maxQtyLength = 1

        foreach ($name in $Inventory.Keys) {
            $inventoryWorth += ($ResourceMaster[$name].Value * $Inventory[$name])
            $len = ($Inventory[$name]).ToString().Length
            if ($len -gt $maxQtyLength) { $maxQtyLength = $len }
        }

        $inventoryRarityOrder = @{
            "Upgrade"     = 1
            "Consumable"  = 2
            "SuperCommon" = 3
            "Common"      = 4
            "Uncommon"    = 5
            "Rare"        = 6
            "SuperRare"   = 7
            "UltraRare"   = 8
            "Artifact"    = 9
            "Oddity"      = 10
        }

        # Explicitly wrap in @() to ensure it's ALWAYS an array, even with 1 item
        $sortedKeys = @(
            $Inventory.Keys | ForEach-Object {
                $m = $ResourceMaster[$_]
                [PSCustomObject]@{
                    Name        = $_
                    RarityOrder = $inventoryRarityOrder[$m.Rarity]
                    Master      = $m
                }
            } | Sort-Object RarityOrder, Name
        )
        $maxNameLength = 15
        $maxDescLength = 32
        foreach ($item in $sortedKeys) {
            if ($item.Name.Length -gt $maxNameLength) { $maxNameLength = $item.Name.Length }
            if ($item.Master.Description.Length -gt $maxDescLength) { $maxDescLength = $item.Master.Description.Length }
        }

        Show-Header -SuppressNotice
        Write-Host "##### " -ForegroundColor DarkGray -NoNewLine
		Write-Host "CARGO HOLD" -ForegroundColor DarkCyan -NoNewLine
		Write-Host " #####" -ForegroundColor DarkGray -NoNewLine
        if ($Player.Message) {
            Write-Host -NoNewline "  > " -ForegroundColor DarkGray
            Write-Host -NoNewline $Player.Message -ForegroundColor DarkGray
            $Player.Message = $null
        }
        Write-Host ""
        Write-Host "Value: $inventoryWorth CD | Weight: $(Get-CurrentWeight)/$($Player.MaxWeight) kg"
        Write-Host ""

        Write-MenuKey "E" "Gray" "Back" "Gray"

        $i = 1
        foreach ($item in $sortedKeys) {
            $qtyString = "x" + $Inventory[$item.Name]
            $itemWeight = [int]($item.Master.Weight * $Inventory[$item.Name])
            $weightString = "$itemWeight kg"

            Write-Host -NoNewline ("[$i]").PadRight(5) -ForegroundColor Cyan
            Write-Host -NoNewline ($qtyString.PadRight($maxQtyLength + 2)) -ForegroundColor Cyan
            $markerWidth = 0
            $neededQty = 0
            $hasActiveRequirement = $activeRequirements.ContainsKey($item.Name)
            $hasSurplusRequirement = $false
            if ($hasActiveRequirement) {
                $neededQty = [int]$activeRequirements[$item.Name]
                $hasSurplusRequirement = $Inventory[$item.Name] -gt $neededQty
                $markerWidth = if ($hasSurplusRequirement) { 3 + $neededQty.ToString().Length } else { 1 }
            }
            Write-RarityText -Text $item.Name -Rarity $item.Master.Rarity -NoNewline
            if ($hasActiveRequirement) {
                Write-Host -NoNewline "*" -ForegroundColor Green
                if ($hasSurplusRequirement) {
                    Write-Host -NoNewline "(" -ForegroundColor DarkGray
                    Write-Host -NoNewline $neededQty -ForegroundColor DarkCyan
                    Write-Host -NoNewline ")" -ForegroundColor DarkGray
                }
            }
            Write-Host -NoNewline (" " * [math]::Max(1, ($maxNameLength + 1) - $item.Name.Length - $markerWidth))

            $desc = $item.Master.Description
            Write-Host -NoNewline "| "
            Write-Host -NoNewline ($weightString.PadLeft(6)) -ForegroundColor (Get-PercentColor -Current $itemWeight -Max $Player.MaxWeight -Inverted)
            Write-Host -NoNewline "| "

            if ($item.Master.Effect) {
                $effectText = Get-ItemEffectText $item.Master
                Write-Host -NoNewline "{Consumable: "
                Write-Host -NoNewline $effectText -ForegroundColor (Get-RarityColor $item.Master.Rarity)
                if ($item.Master.Rarity -eq "Consumable" -and $Inventory[$item.Name] -gt 1 -and $null -ne $item.Master.EffectValue) {
                    $stackEffectValue = [double]$item.Master.EffectValue * [int]$Inventory[$item.Name]
                    $stackEffectText = if (($stackEffectValue % 1) -eq 0) { [string][int]$stackEffectValue } else { Format-Fuel $stackEffectValue }
                    Write-Host -NoNewline "(" -ForegroundColor DarkGray
                    Write-Host -NoNewline $stackEffectText -ForegroundColor DarkGreen
                    Write-Host -NoNewline ")" -ForegroundColor DarkGray
                }
                Write-Host -NoNewline "} "
            }
            else {
                Write-Host -NoNewline "["
                Write-Host -NoNewline $item.Master.Rarity -ForegroundColor (Get-RarityColor $item.Master.Rarity)
                Write-Host -NoNewline "] "
            }
            #Write-Host -NoNewline "| "
            Write-Host $desc -ForegroundColor DarkGray

            $i++
        }

        Write-Host ""
        Write-MenuKey "F" "DarkCyan" "Status Report"

        $choice = (Read-Host ">").ToUpper().Trim()

        switch ($choice) {
            "E" { return }
            "F" { Show-StatusReport }
        }

        if ($choice -as [int]) {
            $index = [int]$choice - 1

            if ($index -ge 0 -and $index -lt $sortedKeys.Count) {
                $selected = $sortedKeys[$index].Name

                if ($ResourceMaster[$selected].Consumable) {
                    if (Confirm-InventoryConsumableUse $selected) {
                        Use-Item $selected
                    }
                } elseif ($ResourceMaster[$selected].Rarity -in @("Artifact", "Oddity")) {
                    $Player.Message = "You can't bring yourself to jettison $selected."
                }
                else {
                    Invoke-JettisonCargo -ItemName $selected -ActiveRequirements $activeRequirements
                }
            }
        }
    }
}

function Show-TraderMenu {
    $planetName = $Player.Location
    Initialize-Trader $planetName
    $trader = $global:TraderState[$planetName]
    $planetData = $CurrentSolarSystem[$planetName]

    while ($true) {
        Show-Header

        $missingFuel = $Player.MaxFuel - $Player.Fuel
        $fuelPrice   = Get-RefuelPrice -MissingFuel $missingFuel -FuelModifier $planetData.FuelModifier
        $missingHP   = $Player.MaxHP - $Player.HP
        $repairPrice = [math]::Ceiling(($missingHP * 1.0) * $planetData.RepairModifier)
        $fuelColor   = if ($Player.Credits -ge $fuelPrice)   { "Green" } else { "Red" }
        $repairColor = if ($Player.Credits -ge $repairPrice) { "Green" } else { "Red" }
        $writeServicePrice = {
            param(
                [int]$Price,
                [string]$PriceColor
            )

            Write-Host -NoNewline $Price -ForegroundColor $PriceColor
            if ($Price -gt $Player.Credits -and $Player.Credits -gt 0) {
                Write-Host -NoNewline " (" -ForegroundColor DarkGray
                Write-Host -NoNewline $Player.Credits -ForegroundColor Yellow
                Write-Host -NoNewline ")" -ForegroundColor DarkGray
            }
            Write-Host " CD" -ForegroundColor $PriceColor
        }

        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"
		Write-Host ""
        Write-MenuKey "1" "Gray" -Label $null
        Write-Host -NoNewline "Repair   " -ForegroundColor Cyan
        & $writeServicePrice $repairPrice $repairColor
        Write-MenuKey "2" "Gray" -Label $null
        Write-Host -NoNewline "Refuel   " -ForegroundColor Cyan
        & $writeServicePrice $fuelPrice $fuelColor
        Write-MenuKey "3" "DarkYellow"   "Buy"
        Write-MenuKey "4" "Green"  "Sell"
		Write-Host ""
        Write-Host -NoNewline "[" -ForegroundColor DarkGray
        Write-Host -NoNewline "C" -ForegroundColor DarkYellow
        Write-Host -NoNewline "] " -ForegroundColor DarkGray
        Write-Host -NoNewline "View " -ForegroundColor DarkCyan
        Write-Host "Trader's Contracts" -ForegroundColor DarkYellow

        $choice = (Read-Host ">").ToUpper().Trim()
        $repairAction = {
            $currentMissingHP = $Player.MaxHP - $Player.HP
            $currentRepairPrice = [math]::Ceiling(($currentMissingHP * 1.0) * $planetData.RepairModifier)
            if ($Player.HP -ge $Player.MaxHP) { Set-TraderDialog -PlanetData $planetData -Key "Frustrated" }
            else {
                if ($Player.Credits -ge $currentRepairPrice) {
                    $Player.Credits -= $currentRepairPrice; $trader.Credits += $currentRepairPrice
                    $Player.HP = $Player.MaxHP; Set-TraderDialog -PlanetData $planetData -Key "Repair"
                } elseif ($Player.Credits -gt 0) {
                    $repairableHP = [int][math]::Floor([double]$Player.Credits / [double]$planetData.RepairModifier)
                    if ($repairableHP -le 0) { Set-TraderDialog -PlanetData $planetData -Key "InsufficientFunds" }
                    else {
                        $spentCredits = [int]$Player.Credits
                        $Player.Credits = 0
                        $trader.Credits += $spentCredits
                        $Player.HP = [Math]::Min($Player.MaxHP, $Player.HP + $repairableHP)
                        Set-TraderDialog -PlanetData $planetData -Key "Repair"
                    }
                } else { Set-TraderDialog -PlanetData $planetData -Key "InsufficientFunds" }
            }
        }
        $refuelAction = {
            $currentMissingFuel = $Player.MaxFuel - $Player.Fuel
            $currentFuelPrice = Get-RefuelPrice -MissingFuel $currentMissingFuel -FuelModifier $planetData.FuelModifier
            if ($Player.Fuel -ge $Player.MaxFuel) { Set-TraderDialog -PlanetData $planetData -Key "Frustrated" }
            else {
                if ($Player.Credits -ge $currentFuelPrice) {
                    $Player.Credits -= $currentFuelPrice; $trader.Credits += $currentFuelPrice
                    $Player.Fuel = $Player.MaxFuel; Set-TraderDialog -PlanetData $planetData -Key "Refuel"
                } elseif ($Player.Credits -gt 0) {
                    $fuelUnitPrice = 3.0 * [double]$planetData.FuelModifier
                    $affordableFuel = [math]::Floor(([double]$Player.Credits / $fuelUnitPrice) * 10.0) / 10.0
                    $affordableFuel = [math]::Min([double]$currentMissingFuel, [double]$affordableFuel)
                    if ($affordableFuel -le 0) { Set-TraderDialog -PlanetData $planetData -Key "InsufficientFunds" }
                    else {
                        $spentCredits = [int]$Player.Credits
                        $Player.Credits = 0
                        $trader.Credits += $spentCredits
                        $Player.Fuel = [math]::Round([math]::Min([double]$Player.MaxFuel, [double]$Player.Fuel + $affordableFuel), 1)
                        Set-TraderDialog -PlanetData $planetData -Key "Refuel"
                    }
                } else { Set-TraderDialog -PlanetData $planetData -Key "InsufficientFunds" }
            }
        }
        switch ($choice) {
            "E" { return }
            "1" { & $repairAction }
            "2" { & $refuelAction }
            "12" { & $repairAction; & $refuelAction }
            "21" { & $refuelAction; & $repairAction }
            "3" { Show-BuyMenu }
            "4" { Show-SellMenu }
            "C" { Show-QuestMenu -TraderContext }
			"Q" { Show-QuestMenu -TraderContext }
            default { Set-TraderDialog -PlanetData $planetData -Key "Frustrated" }
        }
    }
}

function Show-BuyMenu {
    $planetName = $Player.Location
    Initialize-Trader $planetName
    $trader = $global:TraderState[$planetName]
    $buyRarityOrder = @{
        "Upgrade"     = 1
        "Consumable"  = 2
        "SuperCommon" = 3
        "Common"      = 4
        "Uncommon"    = 5
        "Rare"        = 6
        "SuperRare"   = 7
        "UltraRare"   = 8
        "Artifact"    = 9
        "Oddity"      = 10
    }

    while ($true) {
        # Explicitly wrap in @() to fix "single item selection" bug
        $sortedStock = @($trader.Stock.Keys | ForEach-Object {
            $m = $ResourceMaster[$_]
            $rarityOrder = if ($buyRarityOrder.ContainsKey($m.Rarity)) { $buyRarityOrder[$m.Rarity] } else { 99 }
            [PSCustomObject]@{ Name = $_; RarityOrder = $rarityOrder; Master = $m }
        } | Sort-Object RarityOrder, Name)

        if ($null -eq $trader -or $sortedStock.Count -eq 0) { 
            $Player.Message = "Trader is out of stock."
            return 
        }
        $maxQtyLength = 1
        foreach ($name in $trader.Stock.Keys) {
            $len = ($trader.Stock[$name]).ToString().Length
            if ($len -gt $maxQtyLength) { $maxQtyLength = $len }
        }
        
        if (-not $Player.Dialog) { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Trade" }
        Show-Header -NoTrailingBlank
        Write-Host ""
        Write-TraderContextLine "Buying from" ($CurrentSolarSystem[$planetName]).TraderName $trader.Credits
        Write-Host ""
        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"

        $selectionColumnWidth = "[$($sortedStock.Count)]".Length + 1
        $priceWidth = 0
        foreach ($item in $sortedStock) {
            $candidateWidth = ("$($item.Master.Value) CD").Length
            if ($candidateWidth -gt $priceWidth) { $priceWidth = $candidateWidth }
        }

        $i = 1
        foreach ($item in $sortedStock) {
            $qtyString = "x" + $trader.Stock[$item.Name]
            $priceColor = if ($Player.Credits -ge $item.Master.Value) { "Green" } else { "Red" }
            $selectionText = "[$i]"
            $priceText = "$($item.Master.Value) CD"

            # Dynamic Description with Effects
            $desc = $item.Master.Description
            if ($item.Master.Effect) {
                $desc = "$desc ($($item.Master.Rarity) - $(Get-ItemEffectText $item.Master))"
            } else {
                $desc = "$desc ($($item.Master.Rarity))"
            }

            Write-Host -NoNewline ($selectionText.PadRight($selectionColumnWidth)) -ForegroundColor Cyan
            Write-Host -NoNewline ($priceText.PadLeft($priceWidth)) -ForegroundColor $priceColor
            Write-Host -NoNewline " | "
            Write-Host -NoNewline ($qtyString.PadRight($maxQtyLength + 2)) -ForegroundColor Cyan
            Write-RarityText -Text ($item.Name.PadRight(15)) -Rarity $item.Master.Rarity -NoNewline
            $desc = $item.Master.Description
            if ($item.Master.Effect) { Write-Host -NoNewline " | $desc"; Write-Host -NoNewline " (";Write-Host -NoNewline "$($item.Master.Rarity)" -ForegroundColor (Get-RarityColor $item.Master.Rarity); Write-Host ": $(Get-ItemEffectText $item.Master))" }
			else { Write-Host -NoNewline " | $desc"; Write-Host -NoNewline "(";Write-Host -NoNewline "$($item.Master.Rarity)" -ForegroundColor (Get-RarityColor $item.Master.Rarity);Write-Host ")"}
            $i++
        }

        $input = (Read-Host ">").ToUpper().Trim()
        if ($input -eq "E" -or $input -eq "") { return }
        if ($input -match "^(\d+)(A?)$") {
            $selection = [int]$matches[1]
            $allRequested = ($matches[2] -eq "A")
            $index = $selection - 1
            if ($index -ge 0 -and $index -lt $sortedStock.Count) {
                $selectedName = $sortedStock[$index].Name
                $m = $ResourceMaster[$selectedName]
                $stockQty = $trader.Stock[$selectedName]
                
                $qty = 1
                if ($allRequested) {
                    $qty = $stockQty
                } elseif ($stockQty -gt 1) {
                    Write-Host -NoNewline "[?] Buy how many "
                    Write-RarityText -Text "$selectedName" -Rarity $m.Rarity -NoNewline
                    Write-Host " (A for all)?"
                    $qtyInput = Read-Host ">"
                    if ($qtyInput -match "^[aA]$") { $qty = $stockQty }
                    elseif ($qtyInput -as [int]) { $qty = [int]$qtyInput }
                    else { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Frustrated"; continue }
                }

                if ($qty -le 0 -or $qty -gt $stockQty) { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Frustrated"; continue }
                $totalCost = $m.Value * $qty
                if ($Player.Credits -lt $totalCost) { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "InsufficientFunds"; continue }
                
				$global:TraderState[$planetName].LastTrade = Get-Date # Last Trade marker for Trader Restock 
				
                $Player.Credits -= $totalCost
                $trader.Credits += $totalCost
                if ($trader.Stock[$selectedName] -le $qty) { $trader.Stock.Remove($selectedName) }
                else { $trader.Stock[$selectedName] -= $qty }
                Add-Item -ItemName $selectedName -Qty $qty
                $trader.LastTrade = Get-Date
                Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Trade"
            }
            else { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Frustrated" }
        }
        else { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Frustrated" }
    }
}

function Show-SellMenu {
    $planetName = $Player.Location
    Initialize-Trader $planetName
    $trader = $global:TraderState[$planetName]
    $sellNotice = $null
    while ($true) {
        $activeRequirements = Get-ActiveQuestRequirements

        # Explicitly wrap in @() to fix "single item selection" bug
        $sortedInv = @($Inventory.Keys | ForEach-Object {
            $m = $ResourceMaster[$_]
            [PSCustomObject]@{ Name = $_; RarityOrder = $global:RarityOrder[$m.Rarity]; Master = $m }
        } | Sort-Object RarityOrder, Name)

        if ($null -eq $trader -or $sortedInv.Count -eq 0) { 
            $Player.Message = "Your cargo hold is empty."
            return 
        }
        $maxQtyLength = 1
        foreach ($name in $Inventory.Keys) {
            $len = ($Inventory[$name]).ToString().Length
            if ($len -gt $maxQtyLength) { $maxQtyLength = $len }
        }
        
        if (-not $Player.Dialog) { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Trade" }
        Show-Header -NoTrailingBlank
        Write-Host ""
        Write-TraderContextLine "Selling to" ($CurrentSolarSystem[$planetName]).TraderName $trader.Credits $sellNotice
        $sellNotice = $null
        Write-Host ""
        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"

        $selectionColumnWidth = "[$($sortedInv.Count)]".Length + 1
        $i = 1
        foreach ($item in $sortedInv) {
            $sellValue = [math]::Floor($item.Master.Value * 0.69)
            $priceWidth = if ($sellValue -ge 1000) { $sellValue.ToString().Length } else { 3 }
            $selectionText = "[$i]"
            $selectionWidth = if ($sellValue -ge 1000) { $selectionText.Length + 1 } else { $selectionColumnWidth }
            $priceColor = if ($trader.Credits -ge $sellValue) { "Green" } else { "Red" }
            $qtyString = "x" + $Inventory[$item.Name]

            # Dynamic Description with Effects
            $desc = $item.Master.Description
            if ($item.Master.Effect) {
                $desc = "$desc ($($item.Master.Rarity) - $(Get-ItemEffectText $item.Master))"
            } else {
                $desc = "$desc ($($item.Master.Rarity))"
            }

            Write-Host -NoNewline ($selectionText.PadRight($selectionWidth)) -ForegroundColor Cyan
            Write-Host -NoNewline ("{0,$priceWidth}" -f $sellValue + " CD") -ForegroundColor $priceColor
            Write-Host -NoNewline " | "
            Write-Host -NoNewline ($qtyString.PadRight($maxQtyLength + 2)) -ForegroundColor Cyan
            $markerWidth = 0
            $neededQty = 0
            $hasActiveRequirement = $activeRequirements.ContainsKey($item.Name)
            $hasSurplusRequirement = $false
            if ($hasActiveRequirement) {
                $neededQty = [int]$activeRequirements[$item.Name]
                $hasSurplusRequirement = $Inventory[$item.Name] -gt $neededQty
                $markerWidth = if ($hasSurplusRequirement) { 3 + $neededQty.ToString().Length } else { 1 }
            }
            Write-RarityText -Text $item.Name -Rarity $item.Master.Rarity -NoNewline
            if ($hasActiveRequirement) {
                Write-Host -NoNewline "*" -ForegroundColor Green
                if ($hasSurplusRequirement) {
                    Write-Host -NoNewline "(" -ForegroundColor DarkGray
                    Write-Host -NoNewline $neededQty -ForegroundColor DarkCyan
                    Write-Host -NoNewline ")" -ForegroundColor DarkGray
                }
            }
            Write-Host -NoNewline (" " * [math]::Max(1, 15 - $item.Name.Length - $markerWidth))
            $desc = $item.Master.Description
            if ($item.Master.Effect) { Write-Host -NoNewline " | $desc"; Write-Host -NoNewline " (";Write-Host -NoNewline "$($item.Master.Rarity)" -ForegroundColor (Get-RarityColor $item.Master.Rarity); Write-Host ": $(Get-ItemEffectText $item.Master))" }
			else { Write-Host -NoNewline " | $desc"; Write-Host -NoNewline "(";Write-Host -NoNewline "$($item.Master.Rarity)" -ForegroundColor (Get-RarityColor $item.Master.Rarity);Write-Host ")"}
            $i++
        }

        if ($sortedInv.Count -le 16) {
            $hasQuestSurplusItems = $false
            $hasQuestSafeSellItems = $false
            foreach ($item in $sortedInv) {
                if ($item.Master.Rarity -eq "Consumable" -or $item.Master.Rarity -eq "Upgrade" -or $item.Master.Rarity -eq "UltraRare" -or $item.Master.Rarity -eq "Artifact" -or $item.Master.Rarity -eq "Oddity") { continue }

                if (-not $activeRequirements.ContainsKey($item.Name)) {
                    $hasQuestSafeSellItems = $true
                    break
                }

                if ($Inventory[$item.Name] -gt [int]$activeRequirements[$item.Name]) {
                    $hasQuestSafeSellItems = $true
                    break
                }
            }
            foreach ($reqItem in $activeRequirements.Keys) {
                if ($Inventory.ContainsKey($reqItem) -and $Inventory[$reqItem] -gt [int]$activeRequirements[$reqItem]) {
                    $hasQuestSurplusItems = $true
                    break
                }
            }

            Write-Host ""
            Write-Host '   Append "A" to sell all' -ForegroundColor DarkGray
            if ($hasQuestSafeSellItems) {
                Write-Host '   Input "Q" to sell all non-quest resources' -ForegroundColor DarkGray
            }
            if ($hasQuestSurplusItems) {
                Write-Host '   Input "Surplus" to sell quest surplus.' -ForegroundColor DarkGray
            }
        }

        $input = (Read-Host ">").ToUpper().Trim()
        if ($input -eq "E" -or $input -eq "") { return }
        if ($input -eq "Q") {
            $soldAny = $false
            $soldCount = 0
            foreach ($item in $sortedInv) {
                if ($item.Master.Rarity -eq "Consumable" -or $item.Master.Rarity -eq "Upgrade" -or $item.Master.Rarity -eq "UltraRare" -or $item.Master.Rarity -eq "Artifact" -or $item.Master.Rarity -eq "Oddity") { continue }

                $playerQty = [int]$Inventory[$item.Name]
                $reservedQty = if ($activeRequirements.ContainsKey($item.Name)) { [int]$activeRequirements[$item.Name] } else { 0 }
                $sellableQty = [math]::Max(0, $playerQty - $reservedQty)
                if ($sellableQty -le 0) { continue }

                $sellValue = [math]::Floor($item.Master.Value * 0.69)
                if ($sellValue -le 0) { continue }
                $affordableQty = [math]::Floor($trader.Credits / $sellValue)
                $qty = [math]::Min($sellableQty, $affordableQty)
                if ($qty -le 0) { continue }

                $total = $sellValue * $qty
                $Player.Credits += $total
                Add-CreditsAcquired $total
                $trader.Credits -= $total
                if (-not $trader.Stock.ContainsKey($item.Name)) { $trader.Stock[$item.Name] = 0 }
                $trader.Stock[$item.Name] += $qty
                if ($Inventory[$item.Name] -le $qty) { $Inventory.Remove($item.Name) }
                else { $Inventory[$item.Name] -= $qty }

                $soldAny = $true
                $soldCount += $qty
            }

            if ($soldAny) {
                $trader.LastTrade = Get-Date
                Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Trade"
                $sellNotice = "Sold $soldCount non-quest resource items."
            } else {
                $sellNotice = "No non-quest resources to sell."
            }
            continue
        }
        if ($input -eq "SURPLUS") {
            $soldAny = $false
            $soldCount = 0
            foreach ($item in $sortedInv) {
                if (-not $activeRequirements.ContainsKey($item.Name)) { continue }
                if ($item.Master.Rarity -eq "Consumable" -or $item.Master.Rarity -eq "Upgrade") { continue }

                $neededQty = [int]$activeRequirements[$item.Name]
                $playerQty = [int]$Inventory[$item.Name]
                $surplusQty = [math]::Max(0, $playerQty - $neededQty)
                if ($surplusQty -le 0) { continue }

                $sellValue = [math]::Floor($item.Master.Value * 0.69)
                if ($sellValue -le 0) { continue }
                $affordableQty = [math]::Floor($trader.Credits / $sellValue)
                $qty = [math]::Min($surplusQty, $affordableQty)
                if ($qty -le 0) { continue }

                $total = $sellValue * $qty
                $Player.Credits += $total
                Add-CreditsAcquired $total
                $trader.Credits -= $total
                if (-not $trader.Stock.ContainsKey($item.Name)) { $trader.Stock[$item.Name] = 0 }
                $trader.Stock[$item.Name] += $qty
                if ($Inventory[$item.Name] -le $qty) { $Inventory.Remove($item.Name) }
                else { $Inventory[$item.Name] -= $qty }

                $soldAny = $true
                $soldCount += $qty
            }

            if ($soldAny) {
                $trader.LastTrade = Get-Date
                Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Trade"
                $sellNotice = "Sold $soldCount surplus contract items."
            } else {
                $sellNotice = "No surplus contract items to sell."
            }
            continue
        }
        if ($input -match "^(\d+)([AQ]?)$") {
            $selection = [int]$matches[1]
            $allRequested = ($matches[2] -eq "A")
            $contractSafeAllRequested = ($matches[2] -eq "Q")
            $index = $selection - 1
            if ($index -ge 0 -and $index -lt $sortedInv.Count) {
                $selectedName = $sortedInv[$index].Name
                $m = $ResourceMaster[$selectedName]
                $playerQty = $Inventory[$selectedName]
                $sellValue = [math]::Floor($m.Value * 0.69)
                
                $qty = 1
                if ($allRequested -or $contractSafeAllRequested) {
                    $sellableQty = $playerQty
                    if ($contractSafeAllRequested -and $activeRequirements.ContainsKey($selectedName)) {
                        $sellableQty = [math]::Max(0, $playerQty - [int]$activeRequirements[$selectedName])
                    }

                    if ($sellableQty -eq 0) {
                        $Player.Dialog = "$selectedName reserved for active contracts."
                        continue
                    }

                    $affordableQty = [math]::Floor($trader.Credits / $sellValue)
                    $qty = [math]::Min($sellableQty, $affordableQty)

                    if ($qty -eq 0) {
                        Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "InsufficientFundsTrader"
                        continue
                    }
                    if ($qty -lt $sellableQty) {
                        $Player.Dialog = "Trader could only afford $qty units."
                    }
                } elseif ($playerQty -gt 1) {
                    Write-Host -NoNewline "[?] Sell how many "
                    Write-RarityText -Text "$selectedName" -Rarity $m.Rarity -NoNewline
                    Write-Host " (A for all)?"
                    $qtyInput = Read-Host ">"
                    if ($qtyInput -match "^[aA]$") { 
                        # Calculate how many the trader can actually afford
                        $affordableQty = [math]::Floor($trader.Credits / $sellValue)
                        $qty = [math]::Min($playerQty, $affordableQty)
                        
                        if ($qty -eq 0) {
                            Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "InsufficientFundsTrader"
                            continue
                        }
                        if ($qty -lt $playerQty) {
                            $Player.Dialog = "Trader could only afford $qty units."
                        }
                    }
                    elseif ($qtyInput -as [int]) { $qty = [int]$qtyInput }
                    else { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Frustrated"; continue }
                }

                if ($qty -le 0 -or $qty -gt $playerQty) { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Frustrated"; continue }
                $total = $sellValue * $qty
                if ($trader.Credits -lt $total) { 
                    Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "InsufficientFundsTrader"
                    continue 
                }
                
				#$global:TraderState[$planetName].LastTrade = Get-Date # Last Trade marker for Trader Restock
				
                $Player.Credits += $total
                Add-CreditsAcquired $total
                $trader.Credits -= $total
                if (-not $trader.Stock.ContainsKey($selectedName)) { $trader.Stock[$selectedName] = 0 }
                $trader.Stock[$selectedName] += $qty
                if ($Inventory[$selectedName] -le $qty) { $Inventory.Remove($selectedName) }
                else { $Inventory[$selectedName] -= $qty }
                $trader.LastTrade = Get-Date
                Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Trade"
            }
            else { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Frustrated" }
        }
        else { Set-TraderDialog -PlanetData $CurrentSolarSystem[$planetName] -Key "Frustrated" }
    }
}

function Write-QuestLogSection {
    param([array]$ActiveEntries, [array]$CompleteEntries, [string]$EmptyMsg = "No contracts accepted yet.")
    if ($ActiveEntries.Count -eq 0 -and $CompleteEntries.Count -eq 0) {
        Write-Host "   $EmptyMsg" -ForegroundColor DarkGray
        return
    }
    foreach ($entry in $ActiveEntries) {
        $pColor = $entry.PlanetData.PlanetColor
        Write-Host -NoNewline "   [$($entry.PlanetData.TraderName)] " -ForegroundColor $pColor
        Write-Host $entry.Quest.Name -ForegroundColor White
        foreach ($req in $entry.Quest.Requirements) {
            $have = if ($Inventory.ContainsKey($req.Item)) { $Inventory[$req.Item] } else { 0 }
            $progColor = if ($have -ge $req.Qty) { "Green" } elseif ($have -gt 0) { "Yellow" } else { "DarkGray" }
            Write-Host -NoNewline "     "
            Write-RarityText -Text $req.Item.PadRight(28) -Rarity $ResourceMaster[$req.Item].Rarity -NoNewline
            Write-Host "$have/$($req.Qty)" -ForegroundColor $progColor
        }
        Write-QuestRewardLine $entry.Quest "     "
        Write-Host ""
    }
    foreach ($entry in $CompleteEntries) {
        Write-Host -NoNewline "   [$($entry.PlanetData.TraderName)] " -ForegroundColor $entry.PlanetData.PlanetColor
        Write-Host -NoNewline $entry.Quest.Name -ForegroundColor DarkGray
        Write-Host " [COMPLETE]" -ForegroundColor DarkGreen
        foreach ($req in $entry.Quest.Requirements) {
            Write-Host -NoNewline "     "
            Write-Host -NoNewline $req.Item.PadRight(28) -ForegroundColor DarkGray
            Write-Host "$($req.Qty)/$($req.Qty)" -ForegroundColor DarkGray
        }
        Write-QuestRewardLine $entry.Quest "     "
        Write-Host ""
    }
}

function Write-QuestRewardLine($quest, [string]$Indent = "      ") {
    $hasReward = $quest.RewardCD -gt 0 -or ($quest.RewardItems -and $quest.RewardItems.Count -gt 0) -or ($quest.RewardKnown -and $quest.RewardKnown.Count -gt 0)
    if (-not $hasReward) { return }

    Write-Host -NoNewline $Indent
    Write-Host -NoNewline "Reward" -ForegroundColor DarkYellow
    Write-Host -NoNewline ": " -ForegroundColor White
    $needsSeparator = $false

    if ($quest.RewardCD -gt 0) {
        Write-Host -NoNewline "$($quest.RewardCD) CD" -ForegroundColor Yellow
        $needsSeparator = $true
    }

    if ($quest.RewardItems -and $quest.RewardItems.Count -gt 0) {
        foreach ($ri_obj in $quest.RewardItems) {
            if ($needsSeparator) { Write-Host -NoNewline ", " -ForegroundColor DarkGray }
            Write-RarityText -Text $ri_obj.Item -Rarity $ResourceMaster[$ri_obj.Item].Rarity -NoNewline
            if ($ri_obj.Qty -gt 1) { Write-Host -NoNewline " x$($ri_obj.Qty)" }
            $needsSeparator = $true
        }
    }

    if ($quest.RewardKnown -and $quest.RewardKnown.Count -gt 0) {
        foreach ($known in $quest.RewardKnown) {
            if ($needsSeparator) { Write-Host -NoNewline ", " -ForegroundColor DarkGray }
            Write-Host -NoNewline "[DISCOVER: $known]" -ForegroundColor Magenta
            $needsSeparator = $true
        }
    }

    Write-Host ""
}

function Show-QuestMenu {
    param([switch]$TraderContext)
    $planetName = $Player.Location
    $planetData = $CurrentSolarSystem[$planetName]
    $hasTraderQuests = $TraderContext -and $planetData.ContainsKey("Quests") -and $planetData.Quests.Count -gt 0

    if ($hasTraderQuests) {
        Initialize-Trader $planetName
        $trader = $global:TraderState[$planetName]
    }

    while ($true) {
        Show-Header

        # - Trader quests section (only in trader context) -
        $questList        = @()
        $questIndexMap    = @{}   # displayed number -> quest object (excludes completed)
        if ($hasTraderQuests) {
            $questList   = @($planetData.Quests)
            $currentRep  = $trader.Rep

			Write-Host -NoNewline "##### " -ForegroundColor DarkGray
            #Write-Host -NoNewline "CONTRACTS" -ForegroundColor DarkCyan
			#Write-Host -NoNewline " | " -ForegroundColor Cyan
            Write-Host -NoNewline $planetData.TraderName -ForegroundColor $planetData.PlanetColor
			Write-Host -NoNewline " Contracts" -ForegroundColor Yellow
            Write-Host -NoNewline " | " -ForegroundColor Gray
			Write-Host -NoNewline "Reputation" -ForegroundColor DarkCyan
			Write-Host -NoNewline ": " -ForegroundColor Gray
            Write-Host -NoNewline $currentRep -ForegroundColor DarkYellow
            Write-Host " #####" -ForegroundColor DarkGray
            Write-Host ""

            $i = 1
            foreach ($quest in $questList) {
                $repReq    = if ($quest.ContainsKey("RepReq")) { $quest.RepReq } else { 0 }
                $repMet    = $currentRep -ge $repReq
                $rawStatus = if ($global:QuestState.ContainsKey($quest.Id)) { $global:QuestState[$quest.Id].Status } else { "Available" }
                $status    = if ($rawStatus -eq "Available" -and -not $repMet) { "Locked" } else { $rawStatus }

                # Completed trader quests go to the log section below; skip here
                if ($status -eq "Complete") { continue }
                if ($status -eq "Locked" -and $repReq -gt ($currentRep + 1)) { continue }

                $questIndexMap[$i] = $quest
                $readyToTurnIn = $false
                if ($status -eq "Active") {
                    $readyToTurnIn = $true
                    foreach ($req in $quest.Requirements) {
                        $have = if ($Inventory.ContainsKey($req.Item)) { $Inventory[$req.Item] } else { 0 }
                        if ($have -lt $req.Qty) {
                            $readyToTurnIn = $false
                            break
                        }
                    }
                }

                $statusColor = switch ($status) {
                    "Locked"    { "Red" }
                    "Available" { "Cyan"     }
                    "Active"    { if ($readyToTurnIn) { "Green" } else { "DarkCyan" } }
                }
                $statusLabel = switch ($status) {
                    "Available" { "Accept" }
                    "Active"    { if ($readyToTurnIn) { "TurnIn" } else { "Active" } }
                    default     { $status }
                }

                # Line 1: [N] [Status] Quest Name Description
                Write-Host -NoNewline "[$i] " -ForegroundColor Cyan
                Write-Host -NoNewline ("[" + $statusLabel.PadRight(6) + "] ") -ForegroundColor $statusColor
                Write-Host -NoNewline $quest.Name -ForegroundColor White
                if ($quest.Desc) {
                    Write-Host -NoNewline " "
                    Write-Host -NoNewline $quest.Desc -ForegroundColor DarkGray
                }
                Write-Host ""

                # Line 2: all requirements on one line separated by  |
                Write-Host -NoNewline "      Provide"
				Write-Host -NoNewline ": " -ForegroundColor White
                for ($r = 0; $r -lt $quest.Requirements.Count; $r++) {
                    $req  = $quest.Requirements[$r]
                    $have = if ($Inventory.ContainsKey($req.Item)) { $Inventory[$req.Item] } else { 0 }
                    $progColor = if ($have -ge $req.Qty) { "Green" } elseif ($have -gt 0) { "Yellow" } else { "DarkGray" }
                    Write-RarityText -Text $req.Item -Rarity $ResourceMaster[$req.Item].Rarity -NoNewline
                    Write-Host -NoNewline " "
                    Write-Host -NoNewline "$have/$($req.Qty)" -ForegroundColor $progColor
                    if ($r -lt $quest.Requirements.Count - 1) { Write-Host -NoNewline ", " -ForegroundColor DarkGray }
                }
                Write-Host ""

                # Line 3: reward
                Write-QuestRewardLine $quest
                $i++
				Write-Host ""
            }
        } else {
            Write-Host "##### " -ForegroundColor DarkGray -NoNewLine
			Write-Host "Your Contracts" -ForegroundColor Yellow -NoNewLine
			Write-Host " #####" -ForegroundColor DarkGray
            Write-Host ""
        }

        # - Rest-of-log section -
        $activeEntries   = @()
        $completeEntries = @()
        foreach ($sysEntry in $global:AllSystems) {
            $sysData = $sysEntry.Data
            foreach ($pKey in ($sysData.Keys | Sort-Object)) {
            if ($pKey -eq "_Metadata") { continue }
            $pData = $sysData[$pKey]
            if (-not $pData.ContainsKey("Quests")) { continue }
            foreach ($quest in $pData.Quests) {
                if (-not $global:QuestState.ContainsKey($quest.Id)) { continue }
                $entryStatus = $global:QuestState[$quest.Id].Status
                $entry = [PSCustomObject]@{ Quest = $quest; Planet = $pKey; PlanetData = $pData; Status = $entryStatus }
                if ($entry.Status -eq "Active")       { $activeEntries   += $entry }
                elseif ($entry.Status -eq "Complete") { $completeEntries += $entry }
            }
            }
        }

        if (-not $hasTraderQuests) {
            Write-QuestLogSection -ActiveEntries $activeEntries -CompleteEntries @()
        }

        $completedLabel = if ($completeEntries.Count -gt 0) { "Completed Contracts ($($completeEntries.Count))" } else { "Completed Contracts" }
        $completedColor = if ($completeEntries.Count -gt 0) { "DarkCyan" } else { "DarkGray" }
        Write-MenuKey "C" $completedColor $completedLabel "DarkGray"
        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"
        $choice = (Read-Host ">").ToUpper().Trim()
        if ($choice -eq "E" -or $choice -eq "") { return }

        if ($choice -eq "C") {
            if ($completeEntries.Count -eq 0) {
                $Player.Message = "No completed contracts yet."
            } else {
                while ($true) {
                    Show-Header
                    Write-Host "##### " -ForegroundColor DarkGray -NoNewLine
					Write-Host "Completed Contracts" -ForegroundColor Green -NoNewLine
					Write-Host " #####" -ForegroundColor DarkGray
                    Write-Host ""
                    foreach ($entry in $completeEntries) {
                        Write-Host -NoNewline "   [$($entry.PlanetData.TraderName)] " -ForegroundColor $entry.PlanetData.PlanetColor
                        Write-Host -NoNewline $entry.Quest.Name -ForegroundColor DarkGray
                        Write-Host " [COMPLETE]" -ForegroundColor DarkGreen
                        foreach ($req in $entry.Quest.Requirements) {
                            Write-Host -NoNewline "     "
                            Write-Host -NoNewline $req.Item.PadRight(28) -ForegroundColor DarkGray
                            Write-Host "$($req.Qty)/$($req.Qty)" -ForegroundColor DarkGray
                        }
                        Write-Host ""
                    }
                    Write-MenuKey "E" "DarkGray" "Back" "DarkGray"
                    $sub = (Read-Host ">").ToUpper().Trim()
                    if ($sub -eq "E" -or $sub -eq "") { break }
                }
            }
            continue
        }

        # Quest selection (trader context only)
        if ($hasTraderQuests -and ($choice -as [int])) {
            $num = [int]$choice
            if ($questIndexMap.ContainsKey($num)) {
                $quest     = $questIndexMap[$num]
                $repReq    = if ($quest.ContainsKey("RepReq")) { $quest.RepReq } else { 0 }
                $repMet    = $currentRep -ge $repReq
                $rawStatus = if ($global:QuestState.ContainsKey($quest.Id)) { $global:QuestState[$quest.Id].Status } else { "Available" }
                $status    = if ($rawStatus -eq "Available" -and -not $repMet) { "Locked" } else { $rawStatus }

                switch ($status) {
                    "Locked"    { $Player.Message = "Complete more contracts for $($planetData.TraderName) first." }
                    "Available" {
                        $global:QuestState[$quest.Id] = @{ Status = "Active"; Planet = $planetName }
                        $Player.Message = "Contract accepted: $($quest.Name)"
                    }
                    "Active" {
                        $allMet = $true; $missing = @()
                        foreach ($req in $quest.Requirements) {
                            $have = if ($Inventory.ContainsKey($req.Item)) { $Inventory[$req.Item] } else { 0 }
                            if ($have -lt $req.Qty) { $allMet = $false; $missing += "$($req.Item) ($have/$($req.Qty))" }
                        }
                        if ($allMet) {
                            foreach ($req in $quest.Requirements) {
                                if ($Inventory[$req.Item] -le $req.Qty) { $Inventory.Remove($req.Item) }
                                else { $Inventory[$req.Item] -= $req.Qty }
                            }
                            $Player.Credits += $quest.RewardCD
                            Add-CreditsAcquired $quest.RewardCD
                            foreach ($ri_obj in $quest.RewardItems) { Add-Item -ItemName $ri_obj.Item -Qty $ri_obj.Qty }
                            if ($quest.RewardKnown) {
                                foreach ($known in $quest.RewardKnown) {
                                    if (-not ($Player.Known -contains $known)) { $Player.Known.Add($known) }
                                }
                            }
                            $global:QuestState[$quest.Id].Status = "Complete"
                            $trader.Rep++
                            $msg = "Contract complete: $($quest.Name)!"
                            if ($quest.RewardCD -gt 0) { $msg += " +$($quest.RewardCD) CD" }
                            foreach ($ri_obj in $quest.RewardItems) { $msg += " + $($ri_obj.Item)" }
                            if ($quest.RewardKnown) { foreach ($known in $quest.RewardKnown) { $msg += " + [DISCOVERED: $known]" } }
                            $msg += "  [REP now $($trader.Rep)]"
                            $Player.Message = $msg
                        } else { $Player.Message = "Still need: $($missing -join ', ')" }
                    }
                    "Complete" { $Player.Message = "Contract already completed." }
                }
            }
        }
    }
}

function Show-Death {
	# Calculate Total Value:
	$total=$Player.Credits
    foreach ($item in $Inventory.Keys) { $total += ($ResourceMaster[$item].Value * $Inventory[$item]) }
	
Write-Host "                      ..-%@@@@%-.:                   " -ForegroundColor DarkRed
Write-Host "                @@@@@@@@@@@@@@@@@@@@%:               " -ForegroundColor DarkRed
Write-Host "             =%############%@.@@@@@@@@@#             " -ForegroundColor DarkRed
Write-Host "          .##.. ============.%@@@%+@@@@@@@#:         " -ForegroundColor DarkRed
Write-Host "        .#..==:-.------------.===.#####@@@@##        " -ForegroundColor DarkRed -NoNewline;Write-Host "    >=>      >=>     >===>      >=>     >=>  " -ForegroundColor Red
Write-Host "       .#.=.--:.=============.--  .= *#######.       " -ForegroundColor DarkRed -NoNewline;Write-Host "     >=>    >=>    >=>    >=>   >=>     >=>  " -ForegroundColor Red
Write-Host "      -# =---.==@###########==.  +.--.=.##+####      " -ForegroundColor DarkRed -NoNewline;Write-Host "     >=>    >=>   >=>      >=>  >=>     >=>  " -ForegroundColor Red
Write-Host "      *- --.@@@############.   *====----:##*#-#      " -ForegroundColor DarkRed -NoNewline;Write-Host "        >=>      >=>        >=> >=>     >=>  " -ForegroundColor Red
Write-Host "      #=.-.@@@%#######         ####===---..#.=#.     " -ForegroundColor DarkRed -NoNewline;Write-Host "        >=>      >=>        >=> >=>     >=>  " -ForegroundColor Red
Write-Host "      =%=.:#@@@@@@##   #######   #####=.---.-#--+    " -ForegroundColor DarkRed -NoNewline;Write-Host "        >=>      >=>        >=> >=>     >=>  " -ForegroundColor Red
Write-Host "       +..@@#....@ #######@%##@   ####==----.-*.:    " -ForegroundColor DarkRed -NoNewline;Write-Host "        >=>        >=>     >=>  >=>     >=>  " -ForegroundColor Red
Write-Host "       %=#.-------.%#####.-----  ##@%#+=----- :#:*   " -ForegroundColor DarkRed -NoNewline;Write-Host "        >=>          >===>        >====>     " -ForegroundColor Red
Write-Host "       #.:+--------@@@.==----:  .---##%=-----.:..@@.@" -ForegroundColor DarkRed -NoNewline;Write-Host "                                             " -ForegroundColor Red
Write-Host "       --.=-------@@@@=#=--:  -. .---*#.-----+#:#@.@@" -ForegroundColor DarkRed -NoNewline;Write-Host "       >====>     >=> >=======> >====>       " -ForegroundColor Red
Write-Host "       -.#=+-----@.-@###--- ---- ----+#------+::###@*" -ForegroundColor DarkRed -NoNewline;Write-Host "       >=>   >=>  >=> >=>       >=>   >=>    " -ForegroundColor Red
Write-Host "        .#@.==+.#:--:####.  ---- -  .##-----::..####%" -ForegroundColor DarkRed -NoNewline;Write-Host "       >=>    >=> >=> >=>       >=>    >=>   " -ForegroundColor Red
Write-Host "       ####%#%###.---@##  @*:=-----. #%-----=.:#.%--:" -ForegroundColor DarkRed -NoNewline;Write-Host "       >=>    >=> >=> >=====>   >=>    >=>   " -ForegroundColor Red
Write-Host "      ..######+##.-:--@ #####@@@@@@% %#=..--#*-#--#-=" -ForegroundColor DarkRed -NoNewline;Write-Host "       >=>    >=> >=> >==       >=>    >=>   " -ForegroundColor Red
Write-Host "      .:#.====####--=--@###-#####-###   #=.-#+-#.--. " -ForegroundColor DarkRed -NoNewline;Write-Host "       >=>   >=>  >=> >=>       >=>   >=>    " -ForegroundColor Red
Write-Host "      # -----:.##+.#--@##########:## ##:--##.#.-.    " -ForegroundColor DarkRed -NoNewline;Write-Host "       >====>     >=> >=======> >====>       " -ForegroundColor Red
Write-Host "    ..+..---- ###%#######@#=.=. -..+ =:--##.#*==@.   " -ForegroundColor DarkRed
Write-Host "      #===.--*+*##@%%%@#:@#-- ---+--=--.##=###+.##.  " -ForegroundColor DarkRed -NoNewline;Write-Host -NoNewline "              Final Credits: ";Write-Host "$total" -ForegroundColor Yellow
Write-Host "      -#.==---.@:#.#=@.@. ++#+----==+--##.=#*##=:-.  " -ForegroundColor DarkRed -NoNewline;Write-Host -NoNewline "          Total Flight Time: ";Write-Host (Get-SurvivedTime) -ForegroundColor Cyan
Write-Host "    .@:#.-=--:*%..#=%.%#.-.+=---%+@@@#..####@.+:     " -ForegroundColor DarkRed
Write-Host "      +@=*#-:-+=##.-# ###.%-==+.@@@@--:##.#####..    " -ForegroundColor DarkRed
Write-Host "      ..@#-##.==.=%##%%##. #####.--=@@%.###%-#+.     " -ForegroundColor DarkRed  -NoNewline;Write-Host -NoNewline "               Game version: ";Write-Host $SpacegameVersion -ForegroundColor Green
Write-Host "      ==.@##=.############# --.##@@*:@@####.=+       " -ForegroundColor DarkRed
Write-Host "      #==.-- ########%%########.-.@@@@#%##.+         " -ForegroundColor DarkRed
Write-Host "       ==%.--------:...:---=%##+--:##.#==            " -ForegroundColor DarkRed
#Write-Host "                +:##...:---------.#%.##%.=.          " -ForegroundColor DarkRed
#Write-Host "                    =.-:.-+#######:-..               " -ForegroundColor DarkRed
    Pause
}

function Show-DistressSignal {
    Clear-Host
    Write-Host ""
    Write-Host "!!! EMERGENCY BEACON ACTIVATED !!!" -ForegroundColor DarkRed
    Write-Host "Signal broadcast in progress... standby for recovery." -ForegroundColor Red
    $seconds = 10 
    while ($seconds -gt 0) {
        $blink = if ($seconds % 2 -eq 0) { " [ SIGNAL PULSE ] " } else { " (             ) " }
        Show-Header
        Write-Host ""
        Write-Host "        $blink" -ForegroundColor DarkRed
        Write-Host ""
        Write-Host -NoNewline "   RESCUE ARRIVAL IN: " -ForegroundColor DarkYellow
		Write-Host -NoNewline "$seconds" -ForegroundColor Yellow
		Write-Host " SECONDS" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "   !!! ALL RAW CARGO WILL BE FORFEIT !!!" -ForegroundColor DarkGray
        Write-Host "   !!! 50% CREDIT SURCHARGE APPLIED  !!!" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host -NoNewline "   Press "
        Write-Host -NoNewline "[ANY KEY]" -ForegroundColor DarkCyan
        Write-Host " to cancel" -ForegroundColor DarkGray

        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 100
            if ([Console]::KeyAvailable) {
                [Console]::ReadKey($true) | Out-Null
                $Player.Message = "Distress signal cancelled."
                return $false
            }
        }
        $seconds--
    }
    $Player.Credits = [math]::Floor($Player.Credits / 2)
    $keys = @($Inventory.Keys)
    foreach ($k in $keys) { if (-not $ResourceMaster[$k].Consumable) { $Inventory.Remove($k) } }
    $nearest = "Mars"; $minDist = 999; $currentDist = $CurrentSolarSystem[$Player.Location].Distance
    foreach ($key in $CurrentSolarSystem.Keys) {
        if ($key -ne "_Metadata" -and $CurrentSolarSystem[$key].Inhabited) {
            $dist = [math]::Abs($CurrentSolarSystem[$key].Distance - $currentDist)
            if ($dist -lt $minDist) { $minDist = $dist; $nearest = $key }
        }
    }
    $Player.Location = $nearest; $Player.Fuel = [math]::Min($Player.MaxFuel, 10.0); $Player.HP = 50   
    $Player.Dialog = "You were towed to orbit by a Scrapper Union vessel. Don't make them come out again."
    return $true
}

function Show-SolarSystem {
    while ($true) {
        Show-Header
        if ($Player.System) { Write-Host "--- $($Player.System) ---" -ForegroundColor Green }
        
        $currentDist = $CurrentSolarSystem[$Player.Location].Distance
        $planetList = $CurrentSolarSystem.Keys | Where-Object { $_ -ne "_Metadata" } | ForEach-Object {
                $data = $CurrentSolarSystem[$_]
                [PSCustomObject]@{ Name = $_; DistFromSun = $data.Distance; DistFromPlayer = [math]::Abs($data.Distance - $currentDist); Data = $data }
            } | Sort-Object DistFromSun

        $i = 1
        $canReachInhabitedPlanet = [bool]$CurrentSolarSystem[$Player.Location].Inhabited
		$maxNameLength = ($planetList.Name | Measure-Object -Property Length -Maximum).Maximum
		foreach ($entry in $planetList) {
			$planet = $entry.Name; $data = $entry.Data; $distanceAU = [math]::Round($entry.DistFromPlayer, 2)
			$fuelCost = Get-TravelFuelCost $distanceAU
            $distanceText = if ($distanceAU -ge 100) { "{0:000.0}" -f $distanceAU } else { "{0:00.00}" -f $distanceAU }
            $fuelText = ("$(Format-Fuel $fuelCost) FL").PadRight(8)
            $remainingFuel = $Player.Fuel - $fuelCost
            $isCurrent = ($planet -eq $Player.Location)
            $fuelStatusColor = "DarkGray"
            
            if (-not $isCurrent) {
                if ($fuelCost -gt $Player.Fuel) { $fuelStatusColor = "DarkRed" }
                else {
                    if ($data.Inhabited) { $canReachInhabitedPlanet = $true }
                    $remPct = ($remainingFuel / $Player.MaxFuel) * 100
                    if ($remPct -gt 50) { $fuelStatusColor = "Green" }
                    elseif ($remPct -ge 26) { $fuelStatusColor = "Yellow" }
                    else { $fuelStatusColor = "Red" }
                }
            }

			Write-Host -NoNewline ("[" + $i + "]").PadRight(5) -ForegroundColor Cyan
			# Planet Name in its PlanetColor
            Write-Host -NoNewline $planet.PadRight($maxNameLength + 1) -ForegroundColor ($data.PlanetColor)
            
            # Hazard Rating (effective - reflects player upgrades)
            $effHzMap = Get-EffectiveHazard $data
            Write-Host -NoNewline "("
			Write-Host -NoNewline "$effHzMap" -ForegroundColor (Get-HazardColor $effHzMap)
            Write-Host -NoNewline "HZ" -ForegroundColor DarkGray
			if ($effHzMap -ge 100) { Write-Host -NoNewline ")".PadRight(1) }
			elseif ($effHzMap -ge 10) { Write-Host -NoNewline ")".PadRight(2) }
			else { Write-Host -NoNewline ")".PadRight(3) }
            
            # Distance Info
            Write-Host -NoNewline "| "
			Write-Host -NoNewline $distanceText -ForegroundColor DarkGray
            Write-Host -NoNewline " AU / "
			Write-Host -NoNewline $fuelText -ForegroundColor $fuelStatusColor
            Write-Host -NoNewline " | "
            
            # Type and Description
			$typeCol = Get-PlanetTypeColor $data.Type
            Write-Host -NoNewline $data.Type -ForegroundColor $typeCol
			Write-Host -NoNewLine " - $($data.Description)"
			if ($data.Inhabited -and ($Player.Known -contains $planet)) { Write-Host -NoNewline " ($($data.TraderName))" -ForegroundColor $data.PlanetColor }
			Write-Host ""
			$i++
        }
        
        $distressIndex = -1
        if (-not $canReachInhabitedPlanet) {
            $distressIndex = $i
            Write-Host -NoNewline "[$distressIndex] " -ForegroundColor Red
            Write-Host "Send Distress Signal" -ForegroundColor DarkRed
        }

        if ($Player.Hyperdrive) {
            Write-Host ""
            Write-MenuKey "H" "Magenta" "Hyperdrive Jump"
        }
		Write-Host -NoNewline "[" -ForegroundColor DarkGray
        Write-Host -NoNewline "E" -ForegroundColor Green
        Write-Host -NoNewline "]  Return to " -ForegroundColor DarkGray
		Write-Host -NoNewline "$($Player.Location)" -ForegroundColor ($CurrentSolarSystem[$Player.Location].PlanetColor)
		Write-Host " orbit" -ForegroundColor DarkGray
        Write-Host ""
        Write-MenuKey "C" "Yellow" "Contracts"
        Write-Host ""
        Write-MenuKey "S" "DarkGray" "Settings"

        $choice = (Read-Host ">").ToUpper().Trim()
        if ($choice -eq "E" -or $choice -eq "") { return }
        if ($choice -eq "H" -and $Player.Hyperdrive) { Show-GalaxyMenu; return }
        if ($choice -eq "C") { Show-QuestMenu; continue }
		if ($choice -eq "Q") { Show-QuestMenu; continue }
        if ($choice -eq "S") { Show-SettingsMenu; continue }
        if ($distressIndex -ne -1 -and $choice -eq [string]$distressIndex) {
            if (Show-DistressSignal) { return }
            continue
        }
        if ($choice -match "^\d+$") {
            $index = [int]$choice
            if ($index -ge 1 -and $index -lt ($planetList.Count + 1)) {
				$selected = $planetList[$index - 1]
                if ($selected.Name -eq $Player.Location) { return }
					$fuelCost = Get-TravelFuelCost $selected.DistFromPlayer
                if ($fuelCost -le $Player.Fuel) {
                    $Player.Fuel = [math]::Round(([double]($Player.Fuel) - $fuelCost), 1); $Player.Location = $selected.Name
                    if (-not ($Player.Known -contains $selected.Name)) { $Player.Known.Add($selected.Name) }
                    Set-GreetingDialog -PlanetName $selected.Name -PlanetData $CurrentSolarSystem[$selected.Name]
                    return
                }
            }
        }
    }
}

function Show-GalaxyMenu {

    while ($true) {
        Show-Header
        Write-Host "##### " -ForegroundColor DarkGray -NoNewLine
		Write-Host "*Known* Galaxy Map" -ForegroundColor Magenta -NoNewLine
		Write-Host " #####" -ForegroundColor DarkGray
        Write-Host ""

        $currentSystemId = if ($global:CurrentSolarSystem.ContainsKey("_Metadata") -and $global:CurrentSolarSystem._Metadata.Id) { $global:CurrentSolarSystem._Metadata.Id } else { "Sol" }
        $currentSystemName = if ($global:CurrentSolarSystem.ContainsKey("_Metadata")) { $global:CurrentSolarSystem._Metadata.Name } else { $currentSystemId }

        Write-Host -NoNewline "[" -ForegroundColor DarkGray
        Write-Host -NoNewline "E" -ForegroundColor DarkGray
        Write-Host -NoNewline "]  Return to " -ForegroundColor DarkGray
        Write-Host -NoNewline $Player.Location -ForegroundColor ($global:CurrentSolarSystem[$Player.Location].PlanetColor)
        Write-Host " ($currentSystemName)" -ForegroundColor DarkGray

        $jumpCost = Get-HyperdriveFuelCost
        Write-Host ""
        Write-Host -NoNewline "   Jump Cost: "
        $costColor = if ([double]$Player.Fuel -ge [double]$jumpCost) { "Yellow" } else { "DarkRed" }
        Write-Host "$(Format-Fuel $jumpCost) FL" -ForegroundColor $costColor
        if ([double]$Player.Fuel -lt [double]$jumpCost) { Write-Host "   !! Insufficient fuel for jump ($(Format-Fuel $jumpCost) FL required)" -ForegroundColor DarkRed }
        Write-Host ""

        $i = 1
        $knownSystems = @()
        foreach ($sys in $global:AllSystems) {
            if (($Player.Known -contains $sys.Id) -or ($Player.Known -contains $sys.Name)) { $knownSystems += $sys }
        }

        foreach ($sys in $knownSystems) {
            $isCurrent = ($sys.Id -eq $currentSystemId)
            $label = $sys.Name
            if ($isCurrent) {
                Write-Host -NoNewline "[$i] " -ForegroundColor DarkGray
                Write-Host -NoNewline $label -ForegroundColor DarkGray
                Write-Host " (current)" -ForegroundColor DarkGray
            } else {
                Write-Host -NoNewline "[$i] " -ForegroundColor Cyan
                Write-Host $label -ForegroundColor White
            }
            $i++
        }

        Write-Host ""
        $choice = (Read-Host ">").ToUpper().Trim()
        if ($choice -eq "E" -or $choice -eq "") { return }

        if ($choice -match "^\d+$") {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $knownSystems.Count) {
                $selected = $knownSystems[$idx]
                if ($selected.Id -eq $currentSystemId) { continue }

                $jumpCost = Get-HyperdriveFuelCost
                if ([double]$Player.Fuel -lt [double]$jumpCost) {
                    $Player.Message = "Not enough fuel for a hyperjump. Need $(Format-Fuel $jumpCost) FL."
                    continue
                }

                $Player.Fuel = [math]::Round(([double]($Player.Fuel) - $jumpCost), 1)

                $global:CurrentSolarSystem = $selected.Data
                $Player.System = $selected.Data._Metadata.Name

                # Land on outermost planet of destination system
                $outermost = $selected.Data.Keys | Where-Object { $_ -ne "_Metadata" } | ForEach-Object {
                    [PSCustomObject]@{ Name = $_; Distance = $selected.Data[$_].Distance }
                } | Sort-Object Distance -Descending | Select-Object -First 1
                $Player.Location = $outermost.Name

                # Discover the landing planet
                if (-not ($Player.Known -contains $outermost.Name)) {
                    $Player.Known.Add($outermost.Name)
                }

                $landedData = $global:CurrentSolarSystem[$outermost.Name]
                Set-GreetingDialog -PlanetName $outermost.Name -PlanetData $landedData
                $Player.Message = "Hyperjump complete. Arrived at $($outermost.Name), $($selected.Data._Metadata.Name)."
                return
            }
        }
    }
}

function Show-MainMenu {
    $asciiLogo = @(
        '                   ..-%@@@@%-.:                   '
        '             @@@@@@@@@@@@@@@@@@@@%:               '
        '          =%############%@.@@@@@@@@@#             '
        '       .##.. ============.%@@@%+@@@@@@@#:         '
        '     .#..==:-.------------.===.#####@@@@##        '
        '    .#.=.--:.=============.--  .= *#######.       '
        '   -# =---.==@###########==.  +.--.=.##+####      '
        '   *- --.@@@############.   *====----:##*#-#      '
        '   #=.-.@@@%#######         ####===---..#.=#.     '
        '   =%=.:#@@@@@@##   #######   #####=.---.-#--+    '
        '    +..@@#....@ #######@%##@   ####==----.-*.:    '
        '    %=#.-------.%#####.-----  ##@%#+=----- :#:*   '
        '    #.:+--------@@@.==----:  .---##%=-----.:..@@.@'
        '    --.=-------@@@@=#=--:  -. .---*#.-----+#:#@.@@'
        '    -.#=+-----@.-@###--- ---- ----+#------+::###@*'
        '     .#@.==+.#:--:####.  ---- -  .##-----::..####%'
        '    ####%#%###.---@##  @*:=-----. #%-----=.:#.%--:'
        '   ..######+##.-:--@ #####@@@@@@% %#=..--#*-#--#-='
        '   .:#.====####--=--@###-#####-###   #=.-#+-#.--. '
        '   # -----:.##+.#--@##########:## ##:--##.#.-.    '
        ' ..+..---- ###%#######@#=.=. -..+ =:--##.#*==@.   '
        '   #===.--*+*##@%%%@#:@#-- ---+--=--.##=###+.##.  '
        '   -#.==---.@:#.#=@.@. ++#+----==+--##.=#*##=:-.  '
        ' .@:#.-=--:*%..#=%.%#.-.+=---%+@@@#..####@.+:     '
        '   +@=*#-:-+=##.-# ###.%-==+.@@@@--:##.#####..    '
        '   ..@#-##.==.=%##%%##. #####.--=@@%.###%-#+.     '
        '   ==.@##=.############# --.##@@*:@@####.=+       '
        '   #==.-- ########%%########.-.@@@@#%##.+         '
        '    ==%.--------:...:---=%##+--:##.#==            '
    )
    $asciiText = @(
        '     _____                       __________  ___   ________ __'
        '    / ___/____  ____ _________  / ____/ __ \/   | / ____/ //_/'
        '    \__ \/ __ \/ __ `/ ___/ _ \/ /_  / /_/ / /| |/ /   / ,<'
        '   ___/ / /_/ / /_/ / /__/  __/ __/ / _, _/ ___ / /___/ /| |  '
        '  /____/ .___/\__,_/\___/\___/_/   /_/ |_/_/  |_\____/_/ |_|  '
        '      /_/ '
    )
    $asciiLogoColors = @("DarkCyan", "DarkBlue", "DarkGray")
    $asciiTextColors = @("DarkCyan", "Cyan", "White", "Gray", "Yellow", "DarkYellow", "Green")
    $mainMenuDrillColorPairs = @(
        @{ Bright = "Blue";    Dark = "DarkBlue" },
        @{ Bright = "Green";   Dark = "DarkGreen" },
        @{ Bright = "Cyan";    Dark = "DarkCyan" },
        #@{ Bright = "Red";     Dark = "DarkRed" },
        #@{ Bright = "Magenta"; Dark = "DarkMagenta" },
        @{ Bright = "Yellow";  Dark = "DarkYellow" },
        @{ Bright = "Gray";    Dark = "DarkGray" }
		@{ Bright = "White";    Dark = "Gray" }
    )
    $mainMenuDrillIndent = 19
    $mainMenuDrillMinIntervalMs = 1
    $mainMenuDrillMaxIntervalMs = 50
    $mainMenuDrillSourceFrames = @($script:ProspectInvertedDrillFrames)
    $mainMenuDrillFrameCount = if ($mainMenuDrillSourceFrames.Count -gt 0) { Get-UniqueProspectAsciiFrameCount -Frames $mainMenuDrillSourceFrames } else { 0 }
    $mainMenuDrillFrames = @()
    $mainMenuDrillWidth = 0
    for ($frameIndex = 0; $frameIndex -lt $mainMenuDrillFrameCount; $frameIndex++) {
        $frameLines = @(ConvertTo-ProspectAsciiFrameLines -Frame $mainMenuDrillSourceFrames[$frameIndex])
        $mainMenuDrillFrames += ,$frameLines
        foreach ($line in $frameLines) {
            $mainMenuDrillWidth = [Math]::Max($mainMenuDrillWidth, $line.Length)
        }
    }

    $WriteMainMenuOption = {
        param(
            [string]$KeyText,
            [string]$KeyColor,
            [string]$Label
        )

        Write-Host -NoNewline "[" -ForegroundColor DarkGray
        Write-Host -NoNewline $KeyText -ForegroundColor $KeyColor
        Write-Host -NoNewline "] " -ForegroundColor DarkGray
        Write-Host -NoNewline $Label -ForegroundColor DarkCyan
    }

    $WriteMainMenuDrillText = {
        param(
            [string]$Text,
            [int]$ClearWidth = 0,
            [string]$BrightColor = "Gray",
            [string]$DarkColor = "DarkGray"
        )

        $lineText = if ($null -eq $Text) { "" } else { $Text }
        foreach ($segment in (ConvertTo-ProspectDrillAsciiSegments -Text $lineText)) {
            if ([string]::IsNullOrEmpty($segment.Text)) { continue }
            $segmentColor = if ($segment.Color -eq "Gray") { $BrightColor } else { $DarkColor }
            Write-Host -NoNewline $segment.Text -ForegroundColor $segmentColor
        }

        $padding = $ClearWidth - $lineText.Length
        if ($padding -gt 0) {
            Write-Host -NoNewline (" " * $padding) -ForegroundColor $DarkColor
        }
    }

    $RepaintMainMenuDrill = {
        param(
            [hashtable]$DrillPositions,
            [object[]]$DrillFrames,
            [int]$DrillWidth,
            [int]$FrameIndex,
            [string]$BrightColor = "Gray",
            [string]$DarkColor = "DarkGray"
        )

        if (-not $DrillPositions -or -not $DrillFrames -or $DrillFrames.Count -eq 0) { return $false }

        try {
            $restoreLeft = [Console]::CursorLeft
            $restoreTop = [Console]::CursorTop
            $frame = @($DrillFrames[$FrameIndex % $DrillFrames.Count])

            for ($lineIndex = 0; $lineIndex -lt $frame.Count; $lineIndex++) {
                if (-not $DrillPositions.ContainsKey($lineIndex)) { continue }
                [Console]::SetCursorPosition([int]$DrillPositions[$lineIndex].Left, [int]$DrillPositions[$lineIndex].Top)
                &$WriteMainMenuDrillText $frame[$lineIndex] $DrillWidth $BrightColor $DarkColor
            }

            [Console]::SetCursorPosition($restoreLeft, $restoreTop)
            return $true
        } catch {
            return $false
        }
    }.GetNewClosure()

    $RepaintMainMenuShortcuts = {
        param(
            [hashtable]$OptionPositions,
            [bool]$UseNumberShortcuts
        )

        try {
            $restoreLeft = [Console]::CursorLeft
            $restoreTop = [Console]::CursorTop

            if ($OptionPositions.ContainsKey("New")) {
                [Console]::SetCursorPosition([int]$OptionPositions["New"].Left, [int]$OptionPositions["New"].Top)
                if ($UseNumberShortcuts) { &$WriteMainMenuOption "1" "Cyan" "New game" }
                else { &$WriteMainMenuOption "N" "Cyan" "New game" }
            }

            if ($OptionPositions.ContainsKey("Load")) {
                [Console]::SetCursorPosition([int]$OptionPositions["Load"].Left, [int]$OptionPositions["Load"].Top)
                if ($UseNumberShortcuts) { &$WriteMainMenuOption "2" "Green" "Load game" }
                else { &$WriteMainMenuOption "L" "Green" "Load game" }
            }

            [Console]::SetCursorPosition($restoreLeft, $restoreTop)
            return $true
        } catch {
            return $false
        }
    }.GetNewClosure()

    $ReadMainMenuChoice = {
        param(
            [hashtable]$OptionPositions,
            [hashtable]$DrillPositions,
            [object[]]$DrillFrames,
            [int]$DrillWidth,
            [int]$DrillAnimationIntervalMs,
            [int]$InitialDrillFrameIndex = 0,
            [string]$DrillBrightColor = "Gray",
            [string]$DrillDarkColor = "DarkGray"
        )

        try {
            if ([Console]::IsInputRedirected) {
                return (Read-Host ">").ToUpper().Trim()
            }
        } catch {}

        $previousCursorVisible = $true
        $hadCursorState = $false

        try {
            try {
                $previousCursorVisible = [Console]::CursorVisible
                [Console]::CursorVisible = $false
                $hadCursorState = $true
            } catch {
                $hadCursorState = $false
            }

            Write-Host -NoNewline ">"
            $useNumberShortcuts = $false
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $nextShortcutSwapMs = 2000.0
            $drillFrameIndex = $InitialDrillFrameIndex
            $drillFrameCount = if ($DrillFrames) { $DrillFrames.Count } else { 0 }
            $drillAnimationIntervalMs = [Math]::Max(1, $DrillAnimationIntervalMs)
            $nextDrillFrameMs = [double]$drillAnimationIntervalMs

            while ($true) {
                if ([Console]::KeyAvailable) {
                    $keyInfo = [Console]::ReadKey($true)
                    if ($keyInfo.Key -eq [System.ConsoleKey]::Enter -or $keyInfo.Key -eq [System.ConsoleKey]::Backspace) { continue }
                    if ([int][char]$keyInfo.KeyChar -eq 0) { continue }

                    $choice = ([string]$keyInfo.KeyChar).ToUpper().Trim()
                    if ($choice.Length -gt 0) { return $choice.Substring(0, 1) }
                }

                $nowMs = $timer.Elapsed.TotalMilliseconds
                if ($nowMs -ge $nextShortcutSwapMs) {
                    $useNumberShortcuts = -not $useNumberShortcuts
                    $null = &$RepaintMainMenuShortcuts $OptionPositions $useNumberShortcuts

                    $afterRepaintMs = $timer.Elapsed.TotalMilliseconds
                    do {
                        $nextShortcutSwapMs += 1500.0
                    } while ($nextShortcutSwapMs -le $afterRepaintMs)
                }

                $nowMs = $timer.Elapsed.TotalMilliseconds
                if ($drillFrameCount -gt 0 -and $nowMs -ge $nextDrillFrameMs) {
                    $drillFrameIndex = ($drillFrameIndex + 1) % $drillFrameCount
                    $null = &$RepaintMainMenuDrill $DrillPositions $DrillFrames $DrillWidth $drillFrameIndex $DrillBrightColor $DrillDarkColor

                    $afterDrillRepaintMs = $timer.Elapsed.TotalMilliseconds
                    do {
                        $nextDrillFrameMs += $drillAnimationIntervalMs
                    } while ($nextDrillFrameMs -le $afterDrillRepaintMs)
                }

                $nextWakeMs = $nextShortcutSwapMs
                if ($drillFrameCount -gt 0) {
                    $nextWakeMs = [Math]::Min($nextWakeMs, $nextDrillFrameMs)
                }
                $remainingMs = $nextWakeMs - $timer.Elapsed.TotalMilliseconds
                $sleepMs = if ($remainingMs -gt 1) { [int][Math]::Min(5, [Math]::Floor($remainingMs)) } else { 1 }
                Start-Sleep -Milliseconds $sleepMs
            }
        } finally {
            if ($hadCursorState) {
                try { [Console]::CursorVisible = $previousCursorVisible } catch {}
            }
        }
    }.GetNewClosure()

    while ($true) {
        Clear-Host
        $saves = @(Get-SaveFiles)
        $logoColor = $asciiLogoColors | Get-Random
        $textColor = $asciiTextColors | Get-Random
        $textStart = 6
        $drillStart = $textStart - 4
        $menuStart = 14
        $drillAnimationIntervalMs = Get-Random -Minimum $mainMenuDrillMinIntervalMs -Maximum ($mainMenuDrillMaxIntervalMs + 1)
        $drillFrameIndex = if ($mainMenuDrillFrames.Count -gt 0) { Get-Random -Minimum 0 -Maximum $mainMenuDrillFrames.Count } else { 0 }
        $drillColorPair = $mainMenuDrillColorPairs | Get-Random
        $drillBrightColor = $drillColorPair.Bright
        $drillDarkColor = $drillColorPair.Dark
        $drillPositions = @{}
        $optionPositions = @{}

        for ($i = 0; $i -lt $asciiLogo.Count; $i++) {
            Write-Host -NoNewline $asciiLogo[$i] -ForegroundColor $logoColor
            $textIndex = $i - $textStart
            $drillLineIndex = $i - $drillStart
            if ($textIndex -ge 0 -and $textIndex -lt $asciiText.Count) {
                Write-Host -NoNewline "   "
                Write-Host -NoNewline $asciiText[$textIndex] -ForegroundColor $textColor
                if ($textIndex -eq ($asciiText.Count - 1)) {
                    Write-Host -NoNewline "By PijiN" -ForegroundColor DarkGray
					Write-Host -NoNewline " | " -ForegroundColor Gray
					Write-Host -NoNewline "Version" -ForegroundColor DarkGray
					Write-Host -NoNewline ": " -ForegroundColor Gray
					Write-Host -NoNewline $SpacegameVersion -ForegroundColor DarkCyan
					
                }
            } elseif ($drillLineIndex -ge 0 -and $drillLineIndex -lt 4 -and $mainMenuDrillFrames.Count -gt 0) {
                $drillRows = @($mainMenuDrillFrames[$drillFrameIndex])
                Write-Host -NoNewline "   "
                Write-Host -NoNewline (" " * $mainMenuDrillIndent)
                try { $drillPositions[$drillLineIndex] = @{ Left = [Console]::CursorLeft; Top = [Console]::CursorTop } } catch {}
                if ($drillLineIndex -lt $drillRows.Count) {
                    &$WriteMainMenuDrillText $drillRows[$drillLineIndex] $mainMenuDrillWidth $drillBrightColor $drillDarkColor
                }
            } elseif ($i -eq $menuStart) {
                Write-Host -NoNewline "                        "
                $optionPositions["New"] = @{ Left = [Console]::CursorLeft; Top = [Console]::CursorTop }
                &$WriteMainMenuOption "N" "Cyan" "New game"
            } elseif ($i -eq ($menuStart + 1) -and $saves.Count -gt 0) {
                Write-Host -NoNewline "                        "
                $optionPositions["Load"] = @{ Left = [Console]::CursorLeft; Top = [Console]::CursorTop }
                &$WriteMainMenuOption "L" "Green" "Load game"
            }
            Write-Host ""
        }
        $choice = &$ReadMainMenuChoice $optionPositions $drillPositions $mainMenuDrillFrames $mainMenuDrillWidth $drillAnimationIntervalMs $drillFrameIndex $drillBrightColor $drillDarkColor
        switch ($choice) {
            { $_ -in @("N", "1") } { return "New" }
            { $_ -in @("L", "2") -and $saves.Count -gt 0 } {
                $loaded = Show-LoadMenu
                if ($loaded -eq "Loaded") { return "Loaded" }
            }
        }
    }
}

function Show-LoadMenu {
    $deleteMode = $false

    while ($true) {
        $hadHeaderNotice = [bool]($global:Player.Message -or $global:Player.LastLoot)
        Show-Header -NoTrailingBlank
        if (-not $hadHeaderNotice) { Write-Host "" }
        Write-Host "##### " -ForegroundColor DarkGray -NoNewLine
		Write-Host "Load Game" -ForegroundColor Gray -NoNewLine
		Write-Host " #####" -ForegroundColor DarkGray
        Write-Host ""
        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"
        Write-Host -NoNewline "[" -ForegroundColor DarkGray
        Write-Host -NoNewline "P" -ForegroundColor DarkGray
        Write-Host -NoNewline "] " -ForegroundColor DarkGray
        Write-Host -NoNewline "Prune Saves" -ForegroundColor DarkGray
        Write-Host "   keep newest per pilot" -ForegroundColor DarkGray
        if ($deleteMode) {
            Write-Host -NoNewline "[" -ForegroundColor DarkGray
            Write-Host -NoNewline "A" -ForegroundColor DarkRed
            Write-Host -NoNewline "] " -ForegroundColor DarkGray
            Write-Host "Delete All Saves" -ForegroundColor DarkRed
        } else {
            Write-Host -NoNewline "[" -ForegroundColor DarkGray
            Write-Host -NoNewline "D" -ForegroundColor DarkRed
            Write-Host -NoNewline "] " -ForegroundColor DarkGray
            Write-Host "Delete Saves" -ForegroundColor DarkRed
        }
        Write-Host ""

        $saves = @(Get-SaveFiles)

        if ($saves.Count -eq 0) {
            Write-Host "No save files found." -ForegroundColor DarkGray
        } else {
            $saveRows = @($saves | ForEach-Object {
                $save = $_
                try {
                    $json = Get-Content $save.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $savedAt = [datetime]::Parse($json.SavedAt).ToString("MM/dd/yy hh:mm tt")
                    $ver     = if ($json.Version) { "v$($json.Version)" } else { "v?" }
                    $loc     = if ($json.Player.Location) { [string]$json.Player.Location } else { "Unknown" }
                    $sys     = if ($json.SystemName) { [string]$json.SystemName } else { "Sol" }
                    $where   = "$sys, $loc"
                } catch {
                    $savedAt = $save.LastWriteTime.ToString("MM/dd/yy hh:mm tt")
                    $ver     = "v?"
                    $where   = "Unknown"
                }

                [PSCustomObject]@{
                    File    = $save
                    Name    = $save.BaseName
                    SavedAt = $savedAt
                    Where   = $where
                    Version = $ver
                }
            })

            $nameWidth = [math]::Max(1, (($saveRows | ForEach-Object { $_.Name.Length }) | Measure-Object -Maximum).Maximum) + 1
            $whereWidth = [math]::Max(1, (($saveRows | ForEach-Object { $_.Where.Length }) | Measure-Object -Maximum).Maximum)

            $i = 1
            foreach ($row in $saveRows) {
                Write-Host -NoNewline (("[$i]").PadRight(5)) -ForegroundColor Cyan
                Write-Host -NoNewline ($row.Name.PadRight($nameWidth)) -ForegroundColor White
                Write-Host -NoNewline $row.SavedAt -ForegroundColor DarkGray
                Write-Host -NoNewline "  |  " -ForegroundColor DarkGray
                Write-Host -NoNewline ($row.Where.PadRight($whereWidth)) -ForegroundColor DarkGray
                Write-Host -NoNewline " | " -ForegroundColor DarkGray
                Write-Host $row.Version -ForegroundColor DarkGray
                $i++
            }
        }

        Write-Host ""
        if ($deleteMode) {
            Write-Host "Select a save file to delete, or Enter to cancel" -ForegroundColor Gray
        }
        $choice = (Read-Host ">").ToUpper().Trim()
        if ($deleteMode -and [string]::IsNullOrWhiteSpace($choice)) {
            $deleteMode = $false
            continue
        }
        if ($choice -eq "E" -or $choice -eq "") { return "Back" }
        if ($choice -eq "P") {
            Prune-Saves $saves
            $deleteMode = $false
            continue
        }
        if ($choice -eq "D") {
            if ($saves.Count -eq 0) {
                $global:Player.Message = "No save files to delete."
            } else {
                $deleteMode = $true
            }
            continue
        }
        if ($deleteMode -and $choice -eq "A") {
            Delete-AllSaves $saves
            $deleteMode = $false
            continue
        }

        if ($choice -match "^\d+$") {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $saves.Count) {
                if ($deleteMode) {
                    Delete-SaveFile $saves[$idx]
                    $deleteMode = $false
                    continue
                } else {
                    Load-Game $saves[$idx].FullName
                    return "Loaded"
                }
            }
        }

        if ($deleteMode) {
            $deleteMode = $false
            continue
        }
    }
}

function Show-OrbitMenu {
    if ($Player.HP -le 0) { Show-Death; return "Death" }
    $planetData = $CurrentSolarSystem[$Player.Location]
    if ($planetData.Inhabited -and -not $Player.Dialog) { Set-GreetingDialog -PlanetName $Player.Location -PlanetData $planetData }
    Show-Header
    $orbitHz = Get-EffectiveHazard $planetData
    $systemMeta = if ($CurrentSolarSystem.ContainsKey("_Metadata")) { $CurrentSolarSystem._Metadata } else { @{ Id = $Player.System; Color = "Green" } }
    $systemName = if ($systemMeta.Id) { $systemMeta.Id } else { $systemMeta.Name }
    $systemColor = if ($systemMeta.Color) { $systemMeta.Color } else { "Green" }
    Write-MenuKey "E" "Green" -Label $null
    Write-Host -NoNewline "View " -ForegroundColor DarkGray
    Write-Host -NoNewline $systemName -ForegroundColor $systemColor
    Write-Host " system" -ForegroundColor DarkGray
	Write-Host ""
	Write-Host -NoNewline "[" -ForegroundColor DarkGray
	Write-Host -NoNewline "1" -ForegroundColor (Get-HazardColor $orbitHz)
	Write-Host -NoNewline "] " -ForegroundColor DarkGray
	Write-Host -NoNewline "Frack " -ForegroundColor DarkCyan
	Write-Host $Player.Location -ForegroundColor ($planetData.PlanetColor)
	Write-MenuKey "2" "Gray" "Inventory"
    if ($planetData.Inhabited) { 
		Write-Host -NoNewline "[" -ForegroundColor DarkGray
		Write-Host -NoNewline "3" -ForegroundColor white
		Write-Host -NoNewline "] " -ForegroundColor DarkGray
		Write-Host -NoNewline "Hail " -ForegroundColor DarkCyan
		Write-Host $planetData.TraderName -ForegroundColor ($planetData.PlanetColor)
	}
	Write-Host ""
	if ($Player.XRFScanner) {
        $xrfCost = 75.0
        $xrfColor = if ($Player.Fuel -ge $xrfCost) { "DarkMagenta" } else { "DarkGray" }
        Write-MenuKey "F" $xrfColor -Label $null
        Write-Host -NoNewline "XRF8 Scan " -ForegroundColor DarkGray
        Write-Host -NoNewline $Player.Location -ForegroundColor ($planetData.PlanetColor)
        Write-Host " ($(Format-Fuel $xrfCost) FL)" -ForegroundColor DarkGray
    }
    Write-Host -NoNewline "[" -ForegroundColor DarkGray
    Write-Host -NoNewline "C" -ForegroundColor Yellow
    Write-Host -NoNewline "] " -ForegroundColor DarkGray
    Write-Host -NoNewline "View " -ForegroundColor DarkCyan
    Write-Host "Your Contracts" -ForegroundColor Yellow
    $choice = (Read-Host ">").ToUpper().Trim()
    switch ($choice) {
        "E" { return "Depart" }
        "1" { return "Prospect" }
		"2" { return "Inventory" }
        "3" { if ($planetData.Inhabited) { Set-TraderDialog -PlanetData $planetData -Key "TradeGreeting"; return "Trade" } }
		"F" { if ($Player.XRFScanner) { return "XRFScan" } }
        "C" { return "QuestLog" }
		"Q" { return "QuestLog" }
    }
    if ($planetData.Inhabited) {
        if ($choice -eq "") { Set-TraderDialog -PlanetData $planetData -Key "Greeting" }
        else { Set-TraderDialog -PlanetData $planetData -Key "Frustrated" }
    }
    return $null
}

#endregion

#region ##### DO IT #####
while ($true) {
    Start-NewGame
    $mainAction = Show-MainMenu
    if ($mainAction -eq "New") {
        Start-NewGame
    }
    while ($true) {
        $action = Show-OrbitMenu
        if ($action -eq "Death") { break }
        switch ($action) {
            "Depart"    { Show-SolarSystem }
            "Inventory" { Show-Inventory }
            "Prospect"  { Prospect }
            "Trade"     { Show-TraderMenu }
            "QuestLog"  { Show-QuestMenu }
            "XRFScan"   { Show-XRFScan }
        }
    }
}
#endregion

# CHANGELOG
# 0.0.0 - 02/15/2026
# 0.0.1 - 02/19/2026 - Added a better death screen. Added damage backgroundcolor flashes. Revised Buy/Sell/Inv: No longer returns upon every selection, can now select final item, items now list their rarity and effects.Replaced Get-HPColor with Get-PercentColor for dynamic scaling. 
# 0.0.2 - 02/20/2026 - Added $HazardMaster and re-worked the HazardReasons and Prospect damage logic. Added buying from/selling to headers. Changed resources from 100to1000 collective value, and re-balanced prospecting. Trader restock time halved to 5min. Re-balanced
# 0.0.3 - 06/27/2026 - Major update, lots not covered here... Added quest system. New resources and upgrades with hazard mitigation, hyperjumping, scanning planet composition, and more. Input/menus overhaul. Formatting changes/tweaks. Added Typhon-1B solar system with two new factions with more quests/upgrades.
# 0.0.4 - 07/04/2026 - Another big one: Added decimal fuel handling across travel, refueling, XRF scanning, and fracking, with shared fuel formatting. Reworked trader restocks to use quarter-hour refresh timing, dynamic stock generation, and improved restock presentation. Added the Settings Menu, moving save/load/status report access there and adding pilot rename plus fracking animation settings. Improved save/load UX with full save-path messaging, cleaner load-menu notices, safer individual save deletion, and delete-all confirmation. Added save compatibility defaults for new player fields introduced in v0.0.4. Overhauled the fracking screen with animated ASCII drill headers, cursor repaint animation, adjustable drill speed, animation-off mode, planet/type/HZ display, and tick-synced FRACKING color changes. Added animated main-menu drill accent with randomized animation speed and color pairs. Changed fracking ticks to scheduled one-second deadlines so prospecting stays aligned with the game clock. Improved fracking logs, resource/damage summaries, cargo-full handling, auto-heal display, and session time tracking. Added total Time Fracked tracking to the player and Status Report. Gated automatic shield-cell use while fracking behind the new Shield Cell Auto-Injector upgrade, awarded from the Mars questline. Reworked the main header with aligned stat/date spacing, dark gray separators, and a simplified clock-only right side while fracking. Added rarity foreground/background rendering support, including green-background Consumable names in menus and logs. Improved Inventory use-message placement so item-use feedback appears inline with the cargo header. Reworked XRF8 scan output to use relative composition bars, cleaner layout, decimal fuel formatting, and readable low-percentage values. Added planet type color lookup and expanded colored planet/type/HZ presentation where relevant. Expanded and redistributed Sol resource tables and added new planet descriptions. Rebalanced Typhon with new resources, hazards, inward-scaling resource yields, and expanded FFF/Bastion questlines. Added helper routines for item effect text, refuel pricing, travel fuel cost, prospect ASCII rendering, rarity text rendering, duration formatting, and console repaint behavior. Added pre-flight console resize handling for packaged executable display differences. Accessibility / formatting tweaks. Added new Typhon resources, hazards, and quests; overhauled the system. Upgraded the main menu to utilize repaint and include animated button options and the inverted ASCII drill animation (also in varying color).  Added player attributes to track stats. Moved save files into `%APPDATA%\spacefrack`, creating the directory on demand.

<#
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

   _____                       __________  ___   ________ __
  / ___/____  ____ _________  / ____/ __ \/   | / ____/ //_/
  \__ \/ __ \/ __ `/ ___/ _ \/ /_  / /_/ / /| |/ /   / ,<   
 ___/ / /_/ / /_/ / /__/  __/ __/ / _, _/ ___ / /___/ /| |  
/____/ .___/\__,_/\___/\___/_/   /_/ |_/_/  |_\____/_/ |_|  
    /_/
   _____                       ______                __
  / ___/____  ____ _________  / ____/________ ______/ /__
  \__ \/ __ \/ __ `/ ___/ _ \/ /_  / ___/ __ `/ ___/ //_/
 ___/ / /_/ / /_/ / /__/  __/ __/ / /  / /_/ / /__/ ,<
/____/ .___/\__,_/\___/\___/_/   /_/   \__,_/\___/_/|_|
    /_/


$ProspectDrillFrames = @(
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
#>
