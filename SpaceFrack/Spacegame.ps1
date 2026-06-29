Clear-Host
$SpacegameVersion = "0.0.3"
# region ##### GAME INITIALIZER #####
function Start-NewGame {
    # Set the global start time for the survival clock
    $global:GameStartTime = Get-Date

##### PLAYER #####
    $global:Player = @{
        Credits    = 350
        HP         = 100
		MaxHP	   = 100
        Fuel       = 100
        MaxFuel    = 100
		MaxWeight  = 100
		System	   = $null
        SaveName   = $null
        CreditsAcquired = 0
        TimesSlept = 0
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
		Known      = [System.Collections.Generic.List[string]]@( "Sol", "Typhon-1B", "Mars")
    }

    $global:Inventory = @{
        "Fuel Cell (Small)"   = 1
        "Shield Cell (Small)" = 1
		#"Gas Giant Surveyor"= 1
		#"Ice Giant Surveyor"= 1
		#"Terrain Hardening Kit"= 1
		#"Asteroid Surveyer"   = 1
		#"Dwarf-Class Surveyor"= 1
		#"Rad-Shielding Exosuit"= 1
		#"XRF8 Scanner"= 1
		"Cryo-Sleep Chamber"= 1
		#"HyperDrive Module"     = 1
		#"HeavyObject" = 1
    }

    # Initialize/Reset the Trader State (Prevents persistence after death)
    $global:TraderState = @{}
	$global:QuestState  = @{}
	
	##### Values for Resources #####
	$global:ResourceMaster = @{
        # --- Resources ---
		# Debug 
		"HeavyObject"      = @{ Value = 1000;Weight = 999; Rarity = "SuperRare"; Description = "Shit's heavy."; Consumable = $false }
        # Metals
		"Iron"             = @{ Value = 5;   Weight = 1; Rarity = "SuperCommon"; Description = "Raw Iron ore."; Consumable = $false }
		"ScrapMetal"       = @{ Value = 20;  Weight = 2; Rarity = "Common";      Description = "Salvaged hull plating."; Consumable = $false }
		"Copper"           = @{ Value = 30;  Weight = 1; Rarity = "Common";      Description = "Raw Copper ore."; Consumable = $false }
		"Nickel"           = @{ Value = 40;  Weight = 1; Rarity = "Common"; 	 Description = "Raw Nickel ore."; Consumable = $false }
		"Silver"           = @{ Value = 100; Weight = 1; Rarity = "Rare"; 	 	 Description = "Raw Silver ore. (Shiny!)"; Consumable = $false }
		"Gold"			   = @{ Value = 250; Weight = 1; Rarity = "Rare"; 	     Description = "Raw Gold ore. (We're rich!)"; Consumable = $false }
		"Uranium"          = @{ Value = 150; Weight = 1; Rarity = "SuperRare";   Description = "Raw Uranium ore. (Spicy!)"; Consumable = $false }
		"Mythril"          = @{ Value = 200; Weight = 1.5; Rarity = "SuperRare"; Description = "Raw Mithril ore. (Sturdy!)"; Consumable = $false }
		# Minerals 
        "Silicates"        = @{ Value = 5;   Weight = .5; Rarity = "SuperCommon"; Description = "Raw silicate minerals."; Consumable = $false }
        "Sulfur"           = @{ Value = 20;  Weight = .5; Rarity = "Common";      Description = "Crystalline sulfur."; Consumable = $false }
        "SulfuricAcid"     = @{ Value = 30;  Weight = 1; Rarity = "Common";       Description = "Corrosive chemical drums."; Consumable = $false }
		# Gases
		"Nitrogen"         = @{ Value = 12;  Weight = 1; Rarity = "Common"; Description = "Compressed nitrogen canisters."; Consumable = $false }
        "Hydrogen"         = @{ Value = 14;  Weight = 1; Rarity = "Common"; Description = "Hydrogen gas cylinders."; Consumable = $false }
		"Helium"           = @{ Value = 75;  Weight = 1; Rarity = "Rare";   Description = "Helium gas cylinders."; Consumable = $false }
		# Biological materials
        "Water"            = @{ Value = 5;  Weight = 1; Rarity = "SuperCommon"; Description = "Frozen H2O blocks."; Consumable = $false }
        "Biomass"          = @{ Value = 35;  Weight = 1; Rarity = "Rare";       Description = "Organic matter samples."; Consumable = $false }
		# Rarities / Artifiacts
		"MetallicHydrogen" = @{ Value = 250; Weight = 2.5; Rarity = "SuperRare"; Description = "Highly pressurized fuel precursor."; Consumable = $false }
		"Fossils"		   = @{ Value = 300; Weight = 1.5; Rarity = "SuperRare"; Description = "Unknown fossilzed alien lifeform."; Consumable = $false }
		"Tantalum Hafnium Carbide" = @{ Value = 500; Weight = 1; Rarity = "SuperRare"; Description = "As heat-resistant as it gets."; Consumable = $false }

        # --- Consumables ---
        "Fuel Cell (Small)" 	= @{ Value = 35;  Weight = .5; Rarity = "Consumable";  Consumable = $true; Effect = "Fuel"; EffectValue = 50 ; Description = "A small fuel cell.";  UseMessage = "+50 Fuel" }
		"Fuel Cell (Medium)"	= @{ Value = 70;  Weight = 1; Rarity = "Consumable";  Consumable = $true; Effect = "Fuel"; EffectValue = 100 ; Description = "A medium fuel cell.";  UseMessage = "+100 Fuel" }
		"Fuel Cell (Large)"		= @{ Value = 140; Weight = 2; Rarity = "Consumable";  Consumable = $true; Effect = "Fuel"; EffectValue = 200 ; Description = "A large fuel cell.";  UseMessage = "+200 Fuel" }
		"Bastion Fuel Cell"		= @{ Value = 300; Weight = 2; Rarity = "Consumable";  Consumable = $true; Effect = "Fuel"; EffectValue = 500 ; Description = "A Republic Armada fuel cell.";  UseMessage = "+500 Fuel" }
        "Shield Cell (Small)"   = @{ Value = 75;  Weight = .5; Rarity = "Consumable";  Consumable = $true; Effect = "HP"; EffectValue = 50 ; Description = "A small shield recharge cell."; UseMessage = "+50 HP" }
		"Shield Cell (Medium)"  = @{ Value = 150; Weight = 1; Rarity = "Consumable";  Consumable = $true; Effect = "HP"; EffectValue = 100 ; Description = "A medium shield recharge cell."; UseMessage = "+100 HP" }
        "Shield Cell (Large)"   = @{ Value = 275; Weight = 2; Rarity = "Consumable";  Consumable = $true; Effect = "HP"; EffectValue = 200 ; Description = "A large shield recharge cell."; UseMessage = "+200 HP" }
		"Bastion Shield Cell"   = @{ Value = 500; Weight = 2; Rarity = "Consumable";  Consumable = $true; Effect = "HP"; EffectValue = 500 ; Description = "A Republic Armada shield recharge cell."; UseMessage = "+500 HP" }

        # --- Upgrades ---
		# Stat Boosters
        "Cargo Baffles"    				= @{ Value = 750;  Weight = 0; Rarity = "Upgrade";     Description = "Optimized storage racks.";   Consumable = $true; Effect = "MaxWeight"; EffectValue = 50 }
		"Premium Cargo Baffles" 		= @{ Value = 1500; Weight = 0; Rarity = "Upgrade";     Description = "Superbly optimized storage racks."; Consumable = $true; Effect = "MaxWeight"; EffectValue = 100 }
		"Auxiliary Fuel Tank"  			= @{ Value = 500;  Weight = 0; Rarity = "Upgrade";     Description = "Additional fuel capacity.";  Consumable = $true; Effect = "MaxFuel"; EffectValue = 50 }
		"Deluxe Auxiliary Fuel Tank"  	= @{ Value = 1000; Weight = 0; Rarity = "Upgrade";     Description = "Additional fuel capacity.";  Consumable = $true; Effect = "MaxFuel"; EffectValue = 100 }
		"U.C.E. Shield Generator MK I"  = @{ Value = 1000; Weight = 0; Rarity = "Upgrade";    Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 25 }
		"U.C.E. Shield Generator MK II" = @{ Value = 2000; Weight = 0; Rarity = "Upgrade";    Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 50 }
		"U.C.E. Shield Generator MK III"= @{ Value = 3000; Weight = 0; Rarity = "Upgrade";    Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 75 }
		"FFF Shield Generator"    = @{ Value = 4000; Weight = 0; Rarity = "Upgrade";    Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 100 }
		"Bastion Shield Generator"= @{ Value = 8000; Weight = 0; Rarity = "Upgrade";  Description = "Increased shield capacity."; Consumable = $true; Effect = "MaxHP"; EffectValue = 200 }
		# Hazard-Reduction Gadgets
		"Gas Giant Surveyor"  	= @{ Value = 3000; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Gas Giants.";          Consumable = $true; Effect = "frackGas";       EffectValue = 1; HazardReduction = @{ "Gas Giant"    = 0.50 } }
		"Ice Giant Surveyor"  	= @{ Value = 4000; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Ice Giants.";          Consumable = $true; Effect = "frackIce";       EffectValue = 1; HazardReduction = @{ "Ice Giant"    = 0.50 } }
		"Terrain Hardening Kit" = @{ Value = 2500; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Terrestrial planets."; Consumable = $true; Effect = "frackTerr";      EffectValue = 1; HazardReduction = @{ "Terrestrial"  = 0.40 } }
		"Asteroid Surveyer"     = @{ Value = 2000; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Asteroid bodies.";     Consumable = $true; Effect = "frackAst";       EffectValue = 1; HazardReduction = @{ "Asteroid"     = 0.50 } }
		"Dwarf-Class Surveyor"  = @{ Value = 1500; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards on Dwarf-class planets."; Consumable = $true; Effect = "frackDwarf";     EffectValue = 1; HazardReduction = @{ "Dwarf"        = 0.30 } }
		"Rad-Shielding Exosuit" = @{ Value = 6000; Weight = 1; Rarity = "Upgrade"; Description = "Reduces hazards by 25% on HZ80+ planets.";Consumable = $true; Effect = "RadiationSuit";  EffectValue = 1; HazardThreshold = 80; HazardReduction = @{ "_threshold" = 0.25 } }
		# Abilities
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
		"Diamond Rain Ballistic Impact"= 14
		"Gamma ray exposure"		 = 18
		"Critical gamma ray exposure"= 30
		"Singularity"				 = 1000

		# Pirate Events
		"Stray projectile"           = 1.0
		"EMP pulse"                  = 2.0
		"Orbital mine detonation"    = 3.0
		"Hull breach"                = 5.0
		"Gatling barrage"            = 10.0
		"Missile volley"             = 15.0
		"Torpedo strike"             = 20.0
		
		# Volcanic Fissure Venting, Crusader drone flyby, Plasma blaster shot
	}

    # Define rarity order for sorting logic
    $global:RarityOrder = @{
        "SuperCommon" = 1
        "Common"      = 2
        "Rare"        = 3
        "SuperRare"   = 4
        "Consumable"  = 5
        "Upgrade"     = 6
    }

	$global:SolSystem = @{
		_Metadata = @{ Id = "Sol"; Name = "The Sol System"; Color = "Green" }
		Mercury  = @{
			Distance = 0; Inhabited = $false; Type = "Terrestrial"; Danger = 8.3; PlanetColor = "DarkYellow"
			Description = "Mostly magma."
			Resources = @{ "Iron" = 99; "Copper" = 40; "Nickel" = 180; "Silver" = 70; "Gold" = 150; "Silicates" = 50; "Sulfur" = 140 ; "SulfuricAcid" = 60; "Nitrogen" = 90 ; "Hydrogen" = 60; "Helium" = 50; "MetallicHydrogen" = 10; "U.C.E. Shield Generator MK III" = 1}
			HazardReasons = @("Micro-vibrations", "Thermal shock cycling", "Solar flare radiation", "Magma spray", "Tectonic plate collapse", "Coronal particle surge")
		}
		Venus    = @{
			Distance = 2; Inhabited = $false; Type = "Terrestrial"; Danger = 4.2; PlanetColor = "Yellow"
			Description = "Very bright."
			Resources = @{ "Copper" = 269; "Nickel" = 100; "Silver" = 130; "Gold" = 69; "Sulfur" = 160; "SulfuricAcid" = 120; "Nitrogen" = 70 ; "Hydrogen" = 60; "Helium" = 20; "MetallicHydrogen" = 1; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Static discharge", "Atmospheric turbulence", "Acid rain corrosion", "Sulfuric acid deluge", "Runaway greenhouse pressure", "Tectonic plate collapse")
		}
		Earth    = @{
			Distance = 6.5; Inhabited = $true; Type = "Terrestrial"; Danger = 1.2; PlanetColor = "DarkGreen"
			Description = 'Home of the United Countries of Earth'
			Resources = @{ "Iron" = 161; "ScrapMetal" = 195; "Copper" = 150; "Silver" = 25; "Gold" = 10; "Uranium" = 5; "Water" = 345; "Biomass" = 100; "Fossils" = 3 ; "Nitrogen" = 0; "Hydrogen" = 0; "Helium" = 5; "U.C.E. Shield Generator MK I" = 1 }
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "Atmospheric turbulence", "Tectonic shift")
			TraderName = "U.C.E.O.C.S."; TotalTraderCredits = 5000; FuelModifier = 1.8; RepairModifier = 2
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
				"Fuel Cell (Small)" = 5
				"Shield Cell (Small)" = 5
				"Fuel Cell (medium)" = 2
				"Shield Cell (medium)" = 2
				"Auxiliary Fuel Tank" = 1
				"U.C.E. Shield Generator MK I" = 1
				"U.C.E. Shield Generator MK II" = 1
			}
			Quests = @(
				@{
					Id = "earth_1"; Name = "Precious Metals Procurement"; RepReq = 0
					Desc = "You've got pay for a permit upfront if you want to take on *our* contracts."
					Requirements = @(@{ Item = "Gold"; Qty = 1 }; @{ Item = "Silver"; Qty = 10 })
					RewardCD = 500; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK I"; Qty = 1 })
				}
				@{
					Id = "earth_2"; Name = "Strategic Reserve Expansion"; RepReq = 1
					Desc = "Industrial reserves are below threshold. Deliver refined construction metals."
					Requirements = @(
						@{ Item = "Iron"; Qty = 30 }
						@{ Item = "Copper"; Qty = 25 }
						@{ Item = "Silver"; Qty = 10 }
					)
					RewardCD = 500; RewardItems = @(@{ Item = "Cargo Baffles"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK I"; Qty = 1 })
				}
				@{
					Id = "earth_3"; Name = "A Silicate Matter"; RepReq = 2
					Desc = "Quarterly margin projections are in and you wouldn't believe what they're paying for this dirt currently!"
					Requirements = @(@{ Item = "Silicates"; Qty = 150 })
					RewardCD = 2500; RewardItems = @(@{ Item = "Auxiliary Fuel Tank"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK II"; Qty = 1 })
				}
				@{
					Id = "earth_4"; Name = "Special Materials Contract"; RepReq = 3
					Desc = "Deliver fissile material and sulfur compounds. The department will not elaborate"
					Requirements = @(@{ Item = "Uranium"; Qty = 5 }; @{ Item = "Sulfur"; Qty = 20 })
					RewardCD = 2500; RewardItems = @(@{ Item = "Ice Giant Surveyor"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK II"; Qty = 1 })
				}
				@{
					Id = "earth_5"; Name = "A Noble Endeavor"; RepReq = 3
					Desc = "Helium procurement operations have been experiencing steady reduction in productivity."
					Requirements = @(
						@{ Item = "Helium"; Qty = 50 }
					)
					RewardCD = 500; RewardItems = @(@{ Item = "Cargo Baffles"; Qty = 1 };@{ Item = "U.C.E. Shield Generator MK III"; Qty = 1 })
				}
				@{
					Id = "earth_6"; Name = "Project Horizon"; RepReq = 4
					Desc = "Twenty-five units of metallic hydrogen. Questions regarding use are not authorized."
					Requirements = @(@{ Item = "MetallicHydrogen"; Qty = 25 })
					RewardCD = 0; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK II"; Qty = 1 };@{ Item = "Terrain Hardening Kit"; Qty = 1 })
				}
				@{
					Id = "earth_7"; Name = "Gaseous Venture"; RepReq = 5
					Desc = "Gas prices are up. Pay a visit to our local giants and cut us in."
					Requirements = @(
						@{ Item = "Hydrogen"; Qty = 150 }
						@{ Item = "Helium"; Qty = 100 }
						@{ Item = "Nitrogen"; Qty = 50 }
					)
					RewardCD = 500; RewardItems = @(@{ Item = "Premium Cargo Baffles"; Qty = 1 };@{ Item = "U.C.E. Shield Generator MK III"})
				}
			)
		}
		Mars     = @{
			Distance = 11; Inhabited = $true; Type = "Terrestrial"; Danger = 1.0; PlanetColor = "DarkRed"
			Description = "The frontier."
			Resources = @{ "Iron" = 489; "ScrapMetal" = 100; ; "Copper" = 10; "Silver" = 50; "Silicates" = 265; "Water" = 50 ; "Biomass" = 25; "Nitrogen" = 4; "Hydrogen" = 5; "Helium" = 1 ; "U.C.E. Shield Generator MK I" = 1}
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "Dust storm abrasion", "Tectonic shift")
			TraderName = "Martian Colony"; TotalTraderCredits = 3000; FuelModifier = 1.5; RepairModifier = 1.5
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
				"Fuel Cell (Small)" = 8
				"Shield Cell (Small)" = 5
				"Cargo Baffles" = 1
				"Auxiliary Fuel Tank" = 1
			}
			Quests = @(
				@{
					Id = "mars_1"; Name = "Dust and Rust"; RepReq = 0
					Desc = "Need raw iron ore for colony expansion. Won't pay much, but it's honest work."
					Requirements = @(@{ Item = "Iron"; Qty = 50 })
					RewardCD = 0; RewardItems = @(@{ Item = "Shield Cell (Small)"; Qty = 2 } ; @{ Item = "Fuel Cell (Medium)"; Qty = 2 })
				}
				@{
					Id = "mars_2"; Name = "Spectral Calibration"; RepReq = 1
					Desc = "Venusian chemical samples could tune our orbital scanner. Bring back a little poison."
					Requirements = @(@{ Item = "Nitrogen"; Qty = 5 }; @{ Item = "SulfuricAcid"; Qty = 5 })
					RewardCD = 0; RewardItems = @(@{ Item = "XRF8 Scanner"; Qty = 1 })
				}
				@{
					Id = "mars_3"; Name = "Patchwork Fleet"; RepReq = 1
					Desc = "Every hull in port's held together with hope and recycled metal."
					Requirements = @(
						@{ Item = "ScrapMetal"; Qty = 20 }
						@{ Item = "Iron"; Qty = 25 }
						@{ Item = "Copper"; Qty = 20 }
					)
					RewardCD = 500; RewardItems = @(@{ Item = "Shield Cell (Medium)"; Qty = 3 })
				}
				@{
					Id = "mars_4"; Name = "Biological Census"; RepReq = 2
					Desc = "Organic samples are high-priority. Living ecosystems are rare."
					Requirements = @(@{ Item = "Biomass"; Qty = 40 })
					RewardCD = 1000; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK III"; Qty = 1 })
				}
				@{
					Id = "mars_5"; Name = "Atmospheric Processor"; RepReq = 3
					Desc = "Scrubbers need sulfur catalysts and nitrogen reserves before winter."
					Requirements = @(@{ Item = "Sulfur"; Qty = 30 }; @{ Item = "Nitrogen"; Qty = 30 })
					RewardCD = 0; RewardItems = @(@{ Item = "Gas Giant Surveyor"; Qty = 1 } ; @{ Item = "Shield Cell (Medium)"; Qty = 2 })
				}
				@{
					Id = "mars_6"; Name = "Hydrological Acquisition"; RepReq = 5
					Desc = "Dust storm took the condenser offline. We're short on water."
					Requirements = @(@{ Item = "Water"; Qty = 150 })
					RewardCD = 750; RewardItems = @(@{ Item = "Premium Cargo Baffles"; Qty = 1 })
				}
				@{
					Id = "mars_7"; Name = "Belt Hardening Trial"; RepReq = 5
					Desc = "Ceres keeps chewing up survey hulls. Bring asteroid samples and we'll reinforce yours."
					Requirements = @(
						@{ Item = "Silicates"; Qty = 80 }
						@{ Item = "Nickel"; Qty = 40 }
						@{ Item = "Water"; Qty = 50 }
					)
					RewardCD = 1000; RewardItems = @(@{ Item = "Asteroid Surveyer"; Qty = 1 }; @{ Item = "U.C.E. Shield Generator MK II"; Qty = 1 })
				}
				@{
					Id = "mars_8"; Name = "Colony Stockpile"; RepReq = 6
					Desc = "Bring metal, water, and organics before the next storm."
					Requirements = @(
						@{ Item = "Iron"; Qty = 120 }
						@{ Item = "Water"; Qty = 80 }
						@{ Item = "Biomass"; Qty = 25 }
					)
					RewardCD = 1500; RewardItems = @(@{ Item = "Fuel Cell (Large)"; Qty = 2 }; @{ Item = "Shield Cell (Large)"; Qty = 2 }; @{ Item = "Deluxe Auxiliary Fuel Tank"; Qty = 1 })
				}
			)
		}
		Ceres    = @{
			Distance = 15; Inhabited = $false; Type = "Asteroid"; Danger = 2.6; PlanetColor = "Gray"
			Description = "A big rock."
			Resources = @{ "Iron" = 170; "Nickel" = 125; "Silver" = 80; "Gold" = 75; "Silicates" = 350; "Water" = 199 ; "U.C.E. Shield Generator MK I" = 1}
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "Micrometeor swarm", "Meteoroid bombardment", "Debris field collision", "Ring shard impact")
		}
		Jupiter  = @{
			Distance = 20; Inhabited = $false; Type = "Gas Giant"; Danger = 22.0; PlanetColor = "Red"
			Description = "Vast and hostile."
			Resources = @{ "Nitrogen" = 175; "Hydrogen" = 299; "Helium" = 150; "Silver" = 30; "Gold" = 10; "Uranium" = 10; "Sulfur" = 100 ; "SulfuricAcid" = 100; "MetallicHydrogen" = 125 ; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Gravity well shear", "Deep pressure crush", "Lightning discharge", "Extreme Lightning discharge", "Super-cyclone vortex", "Magnetosphere flux storm", "Gamma ray exposure")
		}
		Saturn   = @{
			Distance = 25; Inhabited = $false; Type = "Gas Giant"; Danger = 23.0; PlanetColor = "Yellow"
			Description = "The ringed behemoth."
			Resources = @{ "Nitrogen" = 150; "Hydrogen" = 359; "Helium" = 110; "Silver" = 20; "Gold" = 20; "Uranium" = 20; "Water" = 150; "MetallicHydrogen" = 115 ; "ScrapMetal" = 55 ; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Ring shard impact", "Deep pressure crush", "Lightning discharge", "Extreme Lightning discharge", "Super-cyclone vortex", "Magnetosphere flux storm", "Gamma ray exposure")
		}
		Uranus   = @{
			Distance = 30; Inhabited = $false; Type = "Ice Giant"; Danger = 14.0; PlanetColor = "DarkCyan"
			Description = "The tilted giant."
			Resources = @{ "Uranium" = 120; "Nitrogen" = 174; ; "Helium" = 115; "Hydrogen" = 190; "Silver" = 40; "Gold" = 10; "Water" = 250; "MetallicHydrogen" = 100 ; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Extreme cold stress", "Methane pressure spike", "Cryovolcanic ejecta", "Cryo-geyser eruption", "Lightning discharge", "Ring shard impact", "Diamond Rain Ballistic Impact")
		}
		Neptune  = @{
			Distance = 35.0; Inhabited = $false; Type = "Ice Giant"; Danger = 16.0; PlanetColor = "Blue"
			Description = "Deep blue."
			Resources = @{ "SulfuricAcid" = 150; "Nitrogen" = 150; ; "Helium" = 149; "Hydrogen" = 220; "Silver" = 30; "Gold" = 30; "Uranium" = 30; "Water" = 125; "MetallicHydrogen" = 115 ; "U.C.E. Shield Generator MK II" = 1}
			HazardReasons = @("Extreme cold stress", "Deep pressure crush", "Supersonic wind shear", "Lightning discharge", "Super-cyclone vortex", "Diamond Rain Ballistic Impact")
		}
		Pluto    = @{
			Distance = 39.0; Inhabited = $true; Type = "Dwarf"; Danger = 4.5; PlanetColor = "Gray"
			Description = "An abandoned automated mining outpost."
			Resources = @{ "Water" = 50; "Silicates" = 190 ; "ScrapMetal" = 200 ; "Iron" = 190; "Copper" = 145; "Nickel" = 75; "Silver" = 44; "Gold" = 60; "Uranium" = 15 ; "Biomass" = 10 ; "Helium" = 10 ; "Fossils" = 10 ; "U.C.E. Shield Generator MK I" = 1}
			HazardReasons = @("Hull stress", "Extreme cold stress", "Cryovolcanic ejecta", "Cryo-geyser eruption", "Ion cannon blast")
			TraderName = "A.M.O.8 `"Theta`""; TotalTraderCredits = 3000; FuelModifier = 2.0; RepairModifier = 1.0
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
				"Fuel Cell (Medium)" = 5
				"Fuel Cell (Large)" = 2
				"Shield Cell (Medium)" = 5
				"Shield Cell (Large)" = 2
				"Cargo Baffles" = 1
				"U.C.E. Shield Generator MK III" = 1
			}
			Quests = @(
				@{
					Id = "pluto_1"; Name = "Feed the Beast"; RepReq = 0
					Desc = "Auxilary fuel reserves are low. Replenishment required."
					Requirements = @(@{ Item = "MetallicHydrogen"; Qty = 50 })
					RewardCD = 2000; RewardItems = @(@{ Item = "U.C.E. Shield Generator MK I"; Qty = 1 })
				}
				@{
					Id = "pluto_2"; Name = "Crionics"; RepReq = 1
					Desc = "Cryogenic biocomputer datafarms require nitrogen coolant and fuel precursors."
					Requirements = @(
						@{ Item = "MetallicHydrogen"; Qty = 30 }
						@{ Item = "Nitrogen"; Qty = 30 }
					)
					RewardCD = 0; RewardItems = @(@{ Item = "Cryo-Sleep Chamber"; Qty = 1 })
				}
				@{
					Id = "pluto_3"; Name = "Structural Maintenance"; RepReq = 1
					Desc = "Exterior impact shielding below operational threshold. Deliver replacement materials"
					Requirements = @(@{ Item = "Iron"; Qty = 80 }; @{ Item = "Nickel"; Qty = 20 } )
					RewardCD = 3000; RewardItems = @()
				}
				@{
					Id = "pluto_4"; Name = "Carbon Pangs"; RepReq = 1
					Desc = "Organic material reserves are low. Replenishment required."
					Requirements = @(@{ Item = "Biomass"; Qty = 200 })
					RewardCD = 2000; RewardItems = @(@{ Item = "Dwarf-Class Surveyor"; Qty = 1 })
				}
				@{
					Id = "pluto_5"; Name = "Debris Mitigation"; RepReq = 2
					Desc = "Asteroid interception grid operating below acceptable efficiency. Reinforcement required."
					Requirements = @(@{ Item = "ScrapMetal"; Qty = 40 }; @{ Item = "Silver"; Qty = 20 })
					RewardCD = 1000; RewardItems = @(@{ Item = "Asteroid Surveyer"; Qty = 1 })
				}
				@{
					Id = "pluto_6"; Name = "Samples"; RepReq = 3
					Desc = "Diverse samples requested for chemical synthesis."
					Requirements = @(
						@{ Item = "ScrapMetal"; Qty = 10 }
						@{ Item = "Iron"; Qty = 50 }
						@{ Item = "Copper"; Qty = 20 }
						@{ Item = "Nickel"; Qty = 15 }
						@{ Item = "Silver"; Qty = 10 }
						@{ Item = "Gold"; Qty = 5 }
						
						@{ Item = "Hydrogen"; Qty = 30 }
						@{ Item = "Nitrogen"; Qty = 10 }
						@{ Item = "Helium"; Qty = 10 }
						
						@{ Item = "Water"; Qty = 20 }
						@{ Item = "Biomass"; Qty = 5 }
						
						@{ Item = "Silicates"; Qty = 30 }
						@{ Item = "Sulfur"; Qty = 10 }
						@{ Item = "SulfuricAcid"; Qty = 10 }
						
						@{ Item = "MetallicHydrogen"; Qty = 10 }
						@{ Item = "Fossils"; Qty = 1 }
					)
					RewardCD = 2000; RewardItems = @(@{ Item = "HyperDrive Module"; Qty = 1 })
				}
			)
		}
		Haumea   = @{
			Distance = 41.6; Inhabited = $false; Type = "Dwarf"; Danger = 4.5; PlanetColor = "Gray"
			Description = "Hi'iaka & Namaka"
			Resources = @{ "Silicates" = 250 ; "ScrapMetal" = 50 ; "Iron" = 287; "Copper" = 225; "Nickel" = 125; "Silver" = 50; "Gold" = 5; "Uranium" = 5; "Auxiliary Fuel Tank" = 1; "U.C.E. Shield Generator MK I" = 1; "Deluxe Auxiliary Fuel Tank" = 1 }
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "Micrometeor swarm", "Ion cannon blast")
		}
		Makemake = @{
			Distance = 44.0; Inhabited = $false; Type = "Dwarf"; Danger = 6.8; PlanetColor = "Gray"
			Description = "Red and cold."
			Resources = @{ "Silicates" = 250 ; "ScrapMetal" = 25 ; "Iron" = 298; "Copper" = 205; "Nickel" = 100; "Silver" = 45; "Gold" = 60; "Uranium" = 15; "U.C.E. Shield Generator MK I" = 1; "U.C.E. Shield Generator MK II" = 1 } # "Fuel Cell (Small)" = 00; "Fuel Cell (Medium)" = 00; "Fuel Cell (Large)" = 00; "Shield Cell (Small)" = 00; "Shield Cell (Medium)" = 00; "Shield Cell (Large)" = 00
			HazardReasons = @("Hull stress", "Static discharge", "Extreme cold stress", "Cryovolcanic ejecta", "Ion cannon blast")
		}
		Eris     = @{
			Distance = 49.0; Inhabited = $false; Type = "Dwarf"; Danger = 7.6; PlanetColor = "Gray"
			Description = "Far-out..."
			Resources = @{ "Silicates" = 250 ; "Iron" = 198; "ScrapMetal" = 50; "Copper" = 200; "Nickel" = 125; "Silver" = 100; "Gold" = 50; "Uranium" = 5 ; "Biomass" = 19; "Fossils" = 1; "U.C.E. Shield Generator MK I" = 1; "Cargo Baffles" = 1 }
			HazardReasons = @("Hull stress", "Micro-vibrations", "Solar flare radiation", "Ion cannon blast", "Asteroid impact")
		}
	}

	$global:SolSystem2 = @{
		_Metadata = @{ Id = "Typhon-1B"; Name = "Typhon-1B"; Color = "Blue" }
		Pyre     = @{
			Distance = 0; Inhabited = $false; Type = "Terrestrial"; Danger = 25.0; PlanetColor = "DarkRed"
			Description = "A molten hellhole with abundant resources."
			Resources = @{ "Iron" = 115; "Copper" = 115; "Nickel" = 195; "Gold" = 115; "Uranium" = 95; "Mythril" = 45; "Tantalum Hafnium Carbide" = 90 ; "Nitrogen" = 25; "Hydrogen" = 25; "Helium" = 150; "Bastion Fuel Cell" = 10; "Bastion Shield Cell" =  10; "Bastion Shield Generator" = 5  ; "Terrain Hardening Kit" = 5} # ; "Nitrogen" = 0; "Hydrogen" = 0; "Helium" = 0
			HazardReasons = @("Hull stress", "Micro-vibrations", "Atmospheric turbulence", "Gravity well shear", "Tectonic shift", "Solar flare radiation", "Magma spray", "Tectonic plate collapse", "Fission Event", "Gamma ray exposure", "Critical gamma ray exposure")
		}
		Bastion  = @{
			Distance = 5.0; Inhabited = $true; Type = "Terrestrial"; Danger = 8.0; PlanetColor = "DarkCyan"
			Description = "Capital of the fractured Republic."
			Resources = @{ "Iron" = 208; "Copper" = 190; "Silver" = 156; "Gold" = 63; "Mythril" = 21; "Water" = 156; "Biomass" = 125; "Tantalum Hafnium Carbide" = 60 ; "Bastion Fuel Cell" = 10; "Bastion Shield Cell" = 10  ; "Terrain Hardening Kit" = 1}
			HazardReasons = @("Hull stress", "Micro-vibrations", "Stray projectile", "Static discharge", "Atmospheric turbulence", "EMP pulse", "Orbital mine detonation", "Hull breach", "Gatling barrage", "Missile volley", "Torpedo strike")
			TraderName = "Bastion Republic"; TotalTraderCredits = 9001; FuelModifier = 3.0; RepairModifier = 2.5
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
				"Fuel Cell (Large)" = 10
				"Shield Cell (Large)" = 10
				"Premium Cargo Baffles" = 1
				"Deluxe Auxiliary Fuel Tank" = 1
				"Bastion Shield Generator" = 1
			}
			Quests = @(
				@{
					Id = "rep_1"; Name = "Strategic Alloy Procurement"; RepReq = 0
					Desc = "Production quotas have not been met. Deliver Mythril for armor fabrication."
					Requirements = @(@{ Item = "Mythril"; Qty = 20 })
					RewardCD = 3000; RewardItems = @()
				}
				@{
					Id = "rep_2"; Name = "Project Bulwark"; RepReq = 1
					Desc = "Experimental survey equipment requires field deployment on hostile terrestrial worlds."
					Requirements = @(
						@{ Item = "Tantalum Hafnium Carbide"; Qty = 10 }
						@{ Item = "Gold"; Qty = 25 }
						@{ Item = "Copper"; Qty = 75 }
					)
					RewardCD = 2000; RewardItems = @(@{ Item = "Terrain Hardening Kit"; Qty = 1 })
				}
				@{
					Id = "rep_3"; Name = "Weapons Division Allocation"; RepReq = 2
					Desc = "Fissile reserves remain critically below operational requirements."
					Requirements = @(@{ Item = "Uranium"; Qty = 25 }; @{ Item = "Mythril"; Qty = 30 })
					RewardCD = 5000; RewardItems = @(@{ Item = "FFF Shield Generator"; Qty = 1 }; @{ Item = "Shield Cell (Large)"; Qty = 3 })
				}
				@{
					Id = "rep_4"; Name = "Operation Sunforge"; RepReq = 3
					Desc = "Command has authorized civilian acquisition of strategic fuel precursors. No questions."
					Requirements = @(@{ Item = "MetallicHydrogen"; Qty = 50 }; @{ Item = "Tantalum Hafnium Carbide"; Qty = 20 })
					RewardCD = 9000; RewardItems = @(@{ Item = "Rad-Shielding Exosuit"; Qty = 1 })
				}
				@{
					Id = "rep_5"; Name = "Thermal Research"; RepReq = 4
					Desc = "Engineering requires ultra-high-temperature ceramics and liquid superconductors."
					Requirements = @(@{ Item = "Tantalum Hafnium Carbide"; Qty = 15 }; @{ Item = "MetallicHydrogen"; Qty = 30 })
					RewardCD = 5000
					RewardItems = @(
						@{ Item = "Bastion Shield Generator"; Qty = 1 }
						@{ Item = "Shield Cell (Large)"; Qty = 4 }
						@{ Item = "Fuel Cell (Large)"; Qty = 4 }
					)
				}
			)
		}
		Shrapnel = @{
			Distance = 27.5; Inhabited = $false; Type = "Asteroid"; Danger = 10.0; PlanetColor = "Gray"
			Description = "A shattered asteroid belt littered with remnants of war."
			Resources = @{ "Silicates" = 50; "Iron" = 175; "ScrapMetal" = 209; "Copper" = 145; "Nickel" = 145; "Silver" = 100; "Gold" = 65; "Mythril" = 100 ; "Bastion Fuel Cell" = 5; "Bastion Shield Cell" = 5  ; "Asteroid Surveyor" = 1}
			HazardReasons = @("Hull stress", "Micro-vibrations", "Stray projectile", "EMP pulse", "Orbital mine detonation", "Hull breach", "Gatling barrage", "Missile volley", "Ring shard impact", "Torpedo strike", "Asteroid impact")
		}
		Hyperion = @{
			Distance = 35.5; Inhabited = $false; Type = "Gas Giant"; Danger = 24.0; PlanetColor = "DarkYellow"
			Description = "Massive storms hide priceless fuel reserves."
			Resources = @{ "Mythril" = 15; "Nitrogen" = 198; "Hydrogen" = 250; "Helium" = 252; "MetallicHydrogen" = 282 ; "Bastion Fuel Cell" = 1; "Bastion Shield Cell" = 1  ; "Gas Giant Surveyor" = 1} 
			HazardReasons = @("Atmospheric turbulence", "Gravity well shear", "Lightning discharge", "Extreme Lightning discharge", "Super-cyclone vortex", "Gamma ray exposure", "Critical gamma ray exposure")
		}
		Cocytus  = @{
			Distance = 53.0; Inhabited = $false; Type = "Ice Giant"; Danger = 12.0; PlanetColor = "Cyan"
			Description = "Frozen oceans beneath violent clouds."
			Resources = @{ "Mythril" = 10; "Uranium" = 99; "Nitrogen" = 300; "Hydrogen" = 175; "Helium" = 175; "Water" = 40; "MetallicHydrogen" = 190 ; "Bastion Fuel Cell" = 5; "Bastion Shield Cell" = 5 ; "Ice Giant Surveyor" = 1}
			HazardReasons = @("Stray projectile", "EMP pulse", "Extreme cold stress", "Methane pressure spike", "Cryo-geyser eruption", "Lightning discharge", "Ring shard impact", "Diamond Rain Ballistic Impact")
		}
		Flotsam  = @{
			Distance = 69.0; Inhabited = $true; Type = "Dwarf"; Danger = 3.0; PlanetColor = "White"
			Description = "A Free Frontier Fighters rebel outpost."
			Resources = @{ "Iron" = 203; "ScrapMetal" = 208; "Copper" = 100; "Silver" = 34; "Mythril" = 10; "Water" = 207 ; "Biomass" = 85 ; "Nitrogen" = 50; "Hydrogen" = 50; "Helium" = 40; "Bastion Fuel Cell" = 5; "Bastion Shield Cell" = 5 ; "FFF Shield Generator" = 3 }
			HazardReasons = @("Hull stress", "Micro-vibrations", "Static discharge", "EMP pulse", "Extreme cold stress", "Cryo-geyser eruption")
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
				"Fuel Cell (Medium)" = 5
				"Fuel Cell (Large)" = 4
				"Shield Cell (Medium)" = 5
				"Shield Cell (Large)" = 3
				"Cargo Baffles" = 1
				"Auxiliary Fuel Tank" = 1
				"Deluxe Auxiliary Fuel Tank" = 1
				"FFF Shield Generator" = 1
			}
			Quests = @(
				@{
					Id = "rebel_1"; Name = "Keeping Us Flying"; RepReq = 0
					Desc = "Every plate we weld onto a freighter is one saved grunt."
					Requirements = @(@{ Item = "ScrapMetal"; Qty = 50 }; @{ Item = "Iron"; Qty = 50 })
					RewardCD = 1500; RewardItems = @()
				}
				@{
					Id = "rebel_2"; Name = "Hard-Shell Survival"; RepReq = 1
					Desc = "Republic patrol routes cut through hot zones. Help us harden suits for radiation work."
					Requirements = @(@{ Item = "Water"; Qty = 100 }; @{ Item = "Nitrogen"; Qty = 100 })
					RewardCD = 0; RewardItems = @(@{ Item = "Rad-Shielding Exosuit"; Qty = 1 })
				}
				@{
					Id = "rebel_3"; Name = "Long Haul Logistics"; RepReq = 1
					Desc = "Our supply lines stretch farther every month. More range means more survivors."
					Requirements = @(@{ Item = "MetallicHydrogen"; Qty = 20 }; @{ Item = "Hydrogen"; Qty = 80 })
					RewardCD = 2000; RewardItems = @(@{ Item = "Auxiliary Fuel Tank"; Qty = 2 })
				}
				@{
					Id = "rebel_4"; Name = "Edge of the Frontier"; RepReq = 2
					Desc = "Help us improve our survey equipment for dwarf-class extraction operations."
					Requirements = @(
						@{ Item = "Mythril"; Qty = 20 }
						@{ Item = "Gold"; Qty = 20 }
						@{ Item = "Nickel"; Qty = 40 }
					)
					RewardCD = 3000; RewardItems = @(
						@{ Item = "Shield Cell (Large)"; Qty = 4 }
						@{ Item = "Fuel Cell (Large)"; Qty = 4 } 
						@{ Item = "Dwarf-Class Surveyor"; Qty = 1 }
					)
				}
				@{
					Id = "rebel_5"; Name = "Break the Blockade"; RepReq = 3
					Desc = "We need more Metallic Hydrogen to power Hyperion orbital relays."
					Requirements = @(@{ Item = "MetallicHydrogen"; Qty = 50 })
					RewardCD = 2500; RewardItems = @(
						@{ Item = "Cargo Baffles"; Qty = 2 }
						@{ Item = "Gas Giant Surveyor"; Qty = 1 }
					)
				}
				@{
					Id = "rebel_5"; Name = "Break the Blockade"; RepReq = 3
					Desc = "Jammers on Cocytus could use some more juice."
					Requirements = @(
						@{ Item = "Helium"; Qty = 50 }
						@{ Item = "Nitrogen"; Qty = 100 }
						@{ Item = "Hydrogen"; Qty = 100 }
						@{ Item = "MetallicHydrogen"; Qty = 25 }
					)
					RewardCD = 2500; RewardItems = @(
						@{ Item = "Cargo Baffles"; Qty = 2 }
						@{ Item = "Ice Giant Surveyor"; Qty = 1 }
					)
				}
			)
		}
	}

	## >> Solar Systems << ##
	$global:AllSystems = @(
        @{ Id = $global:SolSystem._Metadata.Id;    Name = $global:SolSystem._Metadata.Name;  Data = $global:SolSystem  }
        @{ Id = $global:SolSystem2._Metadata.Id;   Name = $global:SolSystem2._Metadata.Name; Data = $global:SolSystem2 }
    )

	$global:CurrentSolarSystem = $global:SolSystem
    if ($CurrentSolarSystem.ContainsKey("_Metadata")) {
        $global:Player.System = $CurrentSolarSystem._Metadata.Name
    }
}

function Initialize-Trader($planetName) {
    $planet = $CurrentSolarSystem[$planetName]
    if (-not $planet.Inhabited) { return }
    if ($null -eq $global:TraderState) { $global:TraderState = @{} }

    $now         = Get-Date
	$boundaryMin = $now.Minute # Debug - Restock every minute
    #$boundaryMin = [math]::Floor($now.Minute / 10) * 10
    $boundary    = [datetime]($now.ToString("yyyy-MM-dd HH:") + $boundaryMin.ToString("00") + ":00")

    if (-not $global:TraderState.ContainsKey($planetName)) {
        $global:TraderState[$planetName] = @{
            Stock     = $planet.TraderStock.Clone()
            Credits   = $planet.TotalTraderCredits
            LastTrade = $boundary
            Rep       = 0
        }
    }
    else {
        $lastTrade = [datetime]$global:TraderState[$planetName].LastTrade
        if ($lastTrade -lt $boundary) {
            $global:TraderState[$planetName].Stock     = $planet.TraderStock.Clone()
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

function Get-SurvivedTime {
    if (-not $global:GameStartTime) { return "0s" }
    $span = (Get-Date) - $global:GameStartTime
    $h = [math]::Floor($span.TotalHours)
    $m = $span.Minutes
    $s = $span.Seconds
    if ($h -gt 0) { return "{0}h {1}m {2}s" -f $h, $m, $s }
    if ($m -gt 0) { return "{0}m {1}s" -f $m, $s }
    return "{0}s" -f $s
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

<# Legacy mf
function Get-HPColor {
    param([int]$Value, [int]$UpBand=66, [int]$MidBand=33, [int]$LowBand=9, [string]$UpBandColor="Green", [string]$MidBandColor="Yellow", [string]$LowBandColor="Red", [string]$EmptyBandColor="DarkRed", [string]$zeroColor="DarkRed")
    if     ($Value -ge $UpBand)  { $UpBandColor }
    elseif ($Value -ge $MidBand) { $MidBandColor }
    elseif ($Value -ge $LowBand) { $LowBandColor }
    elseif ($Value -eq 0)        { $zeroColor }
    else                         { $EmptyBandColor }
}#>

function Get-HazardColor($Value) {
    if ($Value -ge 85) { "DarkRed" }
    elseif ($Value -ge 66) { "Red" }
    elseif ($Value -ge 33) { "Yellow" }
    elseif ($Value -eq 1 ) { "DarkCyan" }
    else { "Green" }
}

function Get-RarityColor($rarity) {
    switch ($rarity) {
        "SuperCommon" { "DarkGray" }
        "Common"      { "Gray" }
        "Rare"        { "Cyan" }
        "SuperRare"   { "Magenta" }
        "Consumable"  { "Green" }
        "Upgrade"     { "DarkGreen" }
    }
}

function Flash-DamageBackground {
    param(
        [System.ConsoleColor]$FlashColor,
        [scriptblock]$RedrawAction
    )
    # Store current color
    $originalColor = $host.UI.RawUI.BackgroundColor
    
    # Trigger flash
    $host.UI.RawUI.BackgroundColor = $FlashColor
    Clear-Host
    
    # Execute the redraw so the screen isn't empty during the flash
    if ($RedrawAction) { &$RedrawAction }
    
    Start-Sleep -Milliseconds 100
    
    # Revert to original color
    $host.UI.RawUI.BackgroundColor = $originalColor
    Clear-Host

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

function Get-SaveFiles {
    @(Get-ChildItem -Path $env:APPDATA -Filter "spacegame_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
}

function Get-SaveFileInfo {
    param($SaveFile)

    $saveName = "legacy"
    $savedAt = $SaveFile.LastWriteTime

    try {
        $json = Get-Content $SaveFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.SavedAt) { $savedAt = [datetime]::Parse($json.SavedAt) }
        if ($json.Player.SaveName) {
            $saveName = [string]$json.Player.SaveName
        } elseif ($SaveFile.BaseName -match '^spacegame_(.+)_\d{6}-\d{6}$') {
            $saveName = $matches[1]
        }
    } catch {
        if ($SaveFile.BaseName -match '^spacegame_(.+)_\d{6}-\d{6}$') {
            $saveName = $matches[1]
        }
    }

    [PSCustomObject]@{
        File     = $SaveFile
        SaveName = $saveName
        SavedAt  = $savedAt
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

function Save-Game {
    if (-not $global:Player.ContainsKey("SaveName") -or [string]::IsNullOrWhiteSpace($global:Player.SaveName)) {
        $global:Player.SaveName = Read-SaveName
    }

    $timestamp = (Get-Date).ToString("ddMMyy-HHmmss")
    $saveFileName = "spacegame_$($global:Player.SaveName)_$timestamp.txt"
    $savePath  = Join-Path $env:APPDATA $saveFileName
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
    $global:Player.Message = "Saved: $saveFileName"
}

function Load-Game($path) {
    $data = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { ConvertTo-Hashtable $_ }

    $global:CurrentSolarSystem = switch ($data.SystemName) {
        "Typhon-1B"       { $global:SolSystem2 }
        "The Sol System"  { $global:SolSystem  }
        "Sol"             { $global:SolSystem  }
        default           { $global:SolSystem  }
    }

    $global:GameStartTime = [datetime]::Parse($data.GameStartTime)

    $global:Player           = $data.Player
    if (-not $global:Player.ContainsKey("SaveName")) { $global:Player.SaveName = $null }
    if (-not $global:Player.ContainsKey("CreditsAcquired")) { $global:Player.CreditsAcquired = 0 }
    if (-not $global:Player.ContainsKey("TimesSlept")) { $global:Player.TimesSlept = 0 }
    $global:Player.Known     = [System.Collections.Generic.List[string]]@($data.Player.Known)
    $global:Player.System    = $global:CurrentSolarSystem._Metadata.Name

    $global:Inventory   = $data.Inventory
    $global:TraderState = $data.TraderState
    $global:QuestState  = $data.QuestState

    # Rehydrate LastTrade datetimes â€” always stored as ISO string now
    foreach ($planet in @($global:TraderState.Keys)) {
        $ts = $global:TraderState[$planet]
        if ($ts.ContainsKey("LastTrade") -and $ts.LastTrade -ne $null) {
            $lt = $ts.LastTrade
            if ($lt -is [string]) {
                $ts.LastTrade = [datetime]::Parse($lt)
            } elseif ($lt -is [hashtable] -and $lt.ContainsKey("DateTime")) {
                $ts.LastTrade = [datetime]::Parse($lt.DateTime.ToString())
            } else {
                $ts.LastTrade = [datetime]$lt
            }
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

        $neededHP = 1 - [int]$Player.HP
        $selected = @($hpConsumables | Where-Object { $_.EffectValue -ge $neededHP } | Select-Object -First 1)
        if ($selected.Count -eq 0) {
            $selected = @($hpConsumables | Sort-Object EffectValue, Value, Name -Descending | Select-Object -First 1)
        }
        $selected = $selected[0]

        $Player.HP = [Math]::Min($Player.MaxHP, $Player.HP + $selected.EffectValue)
        if ($Inventory[$selected.Name] -le 1) { $Inventory.Remove($selected.Name) }
        else { $Inventory[$selected.Name]-- }

        $SessionLog.Insert(0, @{
            Style      = "AutoHP"
            HealAmount = $selected.EffectValue
            ItemName   = $selected.Name
        })
    }

    return $true
}

function Invoke-ProspectTick {
    param($PlanetData, [System.Collections.Generic.List[PSObject]]$SessionLog)

    if ($Player.Fuel -le 0) { return @{ Status = "Empty"; Damage = 0; AutoHealed = $false } }

    if ((Get-CurrentWeight) -ge $Player.MaxWeight) {
        $Player.Message = "Cargo hull is full!"
        return @{ Status = "Full"; Damage = 0; AutoHealed = $false }
    }

    # --- Balanced Hazard Logic ---
    $finalDmg = 0
    $autoHealed = $false
    $effectiveHazard = Get-EffectiveHazard $PlanetData
    if ((Get-Random -Min 1 -Max 101) -le (Get-HazardEventChance $effectiveHazard)) {
        $reason = if ($PlanetData.HazardReasons) { $PlanetData.HazardReasons | Get-Random } else { "Hull stress" }
        $multiplier = Get-HazardDamageMultiplier $reason

        $baseDmg = Get-Random -Min 2 -Max 10
        $finalDmg = [int][math]::Max(1, ($baseDmg * $multiplier))

        $Player.HP -= $finalDmg
        $SessionLog.Insert(0, @{ Text = "-$finalDmg HP - $reason"; Color = "Red" })
    }

    if ($Player.HP -le 0) {
        $autoHealed = Invoke-AutoAdministerHPConsumable -SessionLog $SessionLog
        if (-not $autoHealed) {
            return @{ Status = "Death"; Damage = $finalDmg; AutoHealed = $false }
        }
    }
    if ($finalDmg -gt 0) { return @{ Status = "Continue"; Damage = $finalDmg; AutoHealed = $autoHealed } }

    # Roll 1-1000 for high-resolution rarity
    $roll = Get-Random -Minimum 1 -Maximum 1001
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
            Text  = "+1 $resName"
            Color = (Get-RarityColor $ResourceMaster[$resName].Rarity)
        })
        $Player.Fuel = [math]::Max(0, $Player.Fuel - 1)
    }

    return @{ Status = "Continue"; Damage = 0; AutoHealed = $autoHealed }
}

function Prospect {
    $planetData = $CurrentSolarSystem[$Player.Location]
    $startTime = Get-Date
    $lastYieldTime = Get-Date
    $sessionLog = New-Object System.Collections.Generic.List[PSObject]
    $targetScreenLines = 28
    $cryoSkipAvailable = [bool]$Player.CryoSkip
    $prospectComplete = $false
    $waitingToWake = $false

    $DrawUI = {
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
        $fixedLines = 1 + $headerExtraLines + 3 + 1 + $footerLines
        $maxVisibleLines = [math]::Max(1, $targetScreenLines - $fixedLines)

        Show-Header -Prospecting
        $elapsed = (Get-Date) - $startTime
        $cycleColor = if ($elapsed.Seconds % 2 -eq 0) { "Yellow" } else { "DarkYellow" }
        $planetNameColor = if ($planetData.PlanetColor) { $planetData.PlanetColor } else { "White" }

        Write-Host -NoNewline "   =>>> " -ForegroundColor $cycleColor
        Write-Host -NoNewline "FRACKING " -ForegroundColor DarkGray
        Write-Host -NoNewline $Player.Location.ToUpper() -ForegroundColor $planetNameColor
        Write-Host " <<<= " -ForegroundColor $cycleColor

        $effHz = Get-EffectiveHazard $planetData
        $baseHz = Get-BaseHazard $planetData
        Write-Host -NoNewline "   Hazard Lvl: "
        Write-Host -NoNewline $effHz -ForegroundColor (Get-HazardColor $effHz)
        if ($effHz -lt $baseHz) { Write-Host " (base $baseHz)" -ForegroundColor DarkGray } else { Write-Host "" }
        Write-Host ""

        for ($i = 0; $i -lt $maxVisibleLines; $i++) {
            if ($i -lt $sessionLog.Count) { 
                $entry = $sessionLog[$i]
                if ($entry.Style -eq "AutoHP") {
                    Write-Host -NoNewline "   "
                    Write-Host -NoNewline "+$($entry.HealAmount) HP - " -ForegroundColor Green
                    Write-Host "$($entry.ItemName) auto-administered." -ForegroundColor Black -BackgroundColor Green
                } else {
                    Write-Host "   $($entry.Text)" -ForegroundColor $entry.Color
                }
            } 
            else { Write-Host "" }
        }

        if ($sessionLog.Count -gt $maxVisibleLines) {
            $hiddenCount = $sessionLog.Count - $maxVisibleLines
            Write-Host "   ($hiddenCount more...)" -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }
        Write-Host -NoNewLine "   Fracking for: "
        Write-Host "$($elapsed.ToString('mm\:ss'))" -ForegroundColor Cyan
        if ($waitingToWake) {
            Write-Host -NoNewline "   Press "
            Write-Host -NoNewline "[ANY KEY]" -ForegroundColor DarkCyan
            Write-Host " to wake up..."
        } elseif ($showControls) {
			if ($cryoSkipAvailable) {
                Write-Host -NoNewline "   Press "
                Write-Host -NoNewline "[C]" -ForegroundColor DarkCyan
                Write-Host -NoNewline " to Cryo-Skip... "
                Write-Host "[!!!]" -ForegroundColor Red
            }
            Write-Host -NoNewline "   Press "
            $stopKeyLabel = if ($cryoSkipAvailable) { "[ANY OTHER KEY]" } else { "[ANY KEY]" }
            Write-Host -NoNewline $stopKeyLabel -ForegroundColor DarkCyan
            Write-Host " to stop fracking..."
        }
    }

    while ($true) {
        &$DrawUI

        # Resource + Hazard Tick (Every second)
        if (((Get-Date) - $lastYieldTime).TotalSeconds -ge 1) {
            $lastYieldTime = Get-Date

            $tick = Invoke-ProspectTick -PlanetData $planetData -SessionLog $sessionLog

            if ($tick.AutoHealed) {
                Flash-DamageBackground -FlashColor "Green" -RedrawAction $DrawUI
            } elseif ($tick.Damage -ge 10) {
                Flash-DamageBackground -FlashColor "DarkRed" -RedrawAction $DrawUI
            }

            if ($tick.Status -ne "Continue") { break }
        }

        $exitLoop = $false
        $cryoSkip = $false
        for ($j = 0; $j -lt 10; $j++) {
            Start-Sleep -Milliseconds 100
            if ([Console]::KeyAvailable) {
                $keyInfo = [Console]::ReadKey($true)
                if ($cryoSkipAvailable -and $keyInfo.Key -eq [System.ConsoleKey]::C) { $cryoSkip = $true }
                else { $exitLoop = $true }
                break
            }
        }

        if ($cryoSkip) {
            if (-not $Player.ContainsKey("TimesSlept")) { $Player.TimesSlept = 0 }
            $Player.TimesSlept++
            Flash-DamageBackground -FlashColor "Cyan" -RedrawAction $DrawUI

            # Cryo-Skip: resolve all remaining ticks instantly until a natural end condition
            $finalStatus = "Continue"
            while ($true) {
                $tick = Invoke-ProspectTick -PlanetData $planetData -SessionLog $sessionLog
                $finalStatus = $tick.Status
                if ($tick.Status -ne "Continue") { break }
            }
            $prospectComplete = $true
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

        if ($exitLoop) { break }
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
        "Fuel"      { $Player.Fuel = [Math]::Min($Player.MaxFuel, $Player.Fuel + $itemMaster.EffectValue) }
        "MaxFuel"   { $Player.MaxFuel += $itemMaster.EffectValue; $Player.Fuel += $itemMaster.EffectValue }
        "HP"        { $Player.HP   = [Math]::Min($player.MaxHP, $Player.HP   + $itemMaster.EffectValue) }
		"MaxHP"        { $Player.MaxHP += $itemMaster.EffectValue; $Player.HP += $itemMaster.EffectValue }
        "MaxWeight"  { $Player.MaxWeight += $itemMaster.EffectValue }
        "frackGas"       { Add-PlayerUpgradeStack "frackGas" $itemMaster.EffectValue }
        "frackIce"       { Add-PlayerUpgradeStack "frackIce" $itemMaster.EffectValue }
        "frackTerr"      { Add-PlayerUpgradeStack "frackTerr" $itemMaster.EffectValue }
        "frackAst"       { Add-PlayerUpgradeStack "frackAst" $itemMaster.EffectValue }
        "frackDwarf"     { Add-PlayerUpgradeStack "frackDwarf" $itemMaster.EffectValue }
        "RadiationSuit"   { $Player.RadiationSuit   = $true }
        "XRFScanner"      { $Player.XRFScanner      = $true }
        "CryoSkip"        { $Player.CryoSkip        = $true }
        "Hyperdrive"      { $Player.Hyperdrive       = $true }
    }

    if ($Inventory[$ItemName] -le 1) { $Inventory.Remove($ItemName) }
    else { $Inventory[$ItemName]-- }
    $Player.Message = "Used $ItemName."
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
        Write-Host $Player.LastLoot.Name -ForegroundColor (Get-RarityColor $Player.LastLoot.Rarity)
        $Player.LastLoot = $null
        return $true
    }

    return $false
}

function Write-TraderWealth {
    param([int]$Credits)

    Write-Host -NoNewline "Trader wealth: " -ForegroundColor DarkGray
    Write-Host -NoNewline $Credits -ForegroundColor Yellow
    Write-Host " CD" -ForegroundColor DarkYellow
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
    param([switch]$Prospecting, [switch]$SuppressNotice, [switch]$NoTrailingBlank)
    Clear-Host
    $planetData = $CurrentSolarSystem[$Player.Location]
    $weight = Get-CurrentWeight
    
    # Credits
    Write-Host -BackgroundColor Black -NoNewline "CD="
    Write-Host -NoNewline $Player.Credits -ForegroundColor Yellow
    
    # HP (High = Good)
    Write-Host -BackgroundColor Black -NoNewline " | HP="
    $hpCol = Get-PercentColor -Current $Player.HP -Max $player.MaxHP
    Write-Host -BackgroundColor Black -NoNewline "$($Player.HP)" -ForegroundColor $hpCol
	Write-Host -BackgroundColor Black -NoNewline "/$($Player.MaxHP)"
    
    # Fuel (High = Good)
    #$fuelPercent = [int](($Player.Fuel / $Player.MaxFuel) * 100)
    Write-Host -BackgroundColor Black -NoNewline " | FL="
    $fuelCol = Get-PercentColor -Current $Player.Fuel -Max $Player.MaxFuel
    #Write-Host -NoNewline "$($fuelPercent)%" -ForegroundColor $fuelCol
    Write-Host -BackgroundColor Black -NoNewline " $($Player.Fuel)" -ForegroundColor $fuelCol
	Write-Host -BackgroundColor Black -NoNewline "/$($Player.MaxFuel)"
    
    # Weight (High = Bad/Inverted)
    Write-Host -BackgroundColor Black -NoNewline " | WT="
    $wtCol = Get-PercentColor -Current $weight -Max $Player.MaxWeight -Inverted
    Write-Host -BackgroundColor Black -NoNewline "$weight" -ForegroundColor $wtCol
    Write-Host -BackgroundColor Black -NoNewline "/$($Player.MaxWeight)" 
    
    # Orbit/System Info
    $label = if ($Prospecting) { "Fracking: " } else { "Orbiting: " }
    Write-Host -BackgroundColor Black -NoNewline " | $label" 
    Write-Host -BackgroundColor Black -NoNewline $Player.Location -ForegroundColor ($planetData.PlanetColor)
	$headerHz = Get-EffectiveHazard $planetData
	Write-Host -BackgroundColor Black -NoNewLine ", HZ="
	Write-Host -BackgroundColor Black -NoNewLine "$headerHz" -ForegroundColor (Get-HazardColor $headerHz)
    Write-Host -BackgroundColor Black " | $(Get-Clock)"

    if (-not $SuppressNotice) {
        Write-PlayerNotice | Out-Null
    }

    if ($Player.Dialog) {
        Write-Host ""
        $PlanetColor = if ($planetData.Inhabited -and $planetData.ContainsKey("PlanetColor")) { $planetData.PlanetColor } else { "Gray" }
        Write-Host -NoNewline "> Incoming transmission from "
        Write-Host -NoNewline "$($planetData.TraderName)" -ForegroundColor $PlanetColor
        Write-Host ":"
        Write-Host -NoNewline "   `"" 
        Write-Host -NoNewline $Player.Dialog -ForegroundColor $PlanetColor
        Write-Host "`""
        $Player.Dialog = $null
    }
    if (-not $NoTrailingBlank) { Write-Host "" }
}

function Show-XRFScan {
    $scanCost = 100
    $planetData = $CurrentSolarSystem[$Player.Location]

    if ($Player.Fuel -lt $scanCost) {
        $Player.Message = "Insufficient fuel for XRF8 scan ($scanCost FL required)."
        return
    }

    $Player.Fuel -= $scanCost

    # Build noisy readings: multiply each resource weight by a random factor 0.72-1.28
    $noisyResources = @{}
    foreach ($kvp in $planetData.Resources.GetEnumerator()) {
        $factor = (Get-Random -Minimum 72 -Maximum 129) / 100.0
        $noisyResources[$kvp.Key] = [math]::Max(1, [int]($kvp.Value * $factor))
    }
    $noisyTotal = ($noisyResources.Values | Measure-Object -Sum).Sum

    # Sort by noisy weight descending (order itself has noise)
    $sorted = $noisyResources.GetEnumerator() | Sort-Object Value -Descending

    $planetColor = $planetData.PlanetColor

    while ($true) {
        Show-Header
        Write-Host -NoNewline "##### XRF8 SCAN - " -ForegroundColor Cyan
        Write-Host -NoNewline $Player.Location.ToUpper() -ForegroundColor $planetColor
        Write-Host " #####" -ForegroundColor Cyan
        Write-Host "   Spectral analysis complete. Readings are approximate." -ForegroundColor DarkGray
        Write-Host "   Fuel consumed: $scanCost FL" -ForegroundColor DarkGray
        Write-Host ""

        Write-Host -NoNewline ("   Resource").PadRight(24) -ForegroundColor DarkGray
        Write-Host -NoNewline "  Composition" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "   $("-" * 44)" -ForegroundColor DarkGray

        foreach ($kvp in $sorted) {
            $pct = [math]::Round($kvp.Value / $noisyTotal * 100)
            if ($pct -lt 1) { $pct = 1 }
            $barLen = [math]::Max(1, [math]::Round($pct / 5))
            $bar = ("#" * $barLen).PadRight(20)
            $rarColor = Get-RarityColor $ResourceMaster[$kvp.Key].Rarity
            Write-Host -NoNewline "   "
            Write-Host -NoNewline $kvp.Key.PadRight(24) -ForegroundColor $rarColor
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
        @{ Flag = "XRFScanner";    Name = "XRF8 Scanner";                 Effect = "Reveals approximate resource composition from orbit (100 FL)." }
        @{ Flag = "CryoSkip";      Name = "Cryo-Sleep Chamber";           Effect = "Cryo-sleep chamber operates in 1 year increments only. Sleep smart." }
        @{ Flag = "Hyperdrive";    Name = "HyperDrive Module";            Effect = "Enables interstellar travel." }
        @{ Flag = "frackGas";       Name = "Gas Giant Surveyor";  Effect = "50% hazard reduction per stack on Gas Giants." }
        @{ Flag = "frackIce";       Name = "Ice Giant Surveyor";  Effect = "60% hazard reduction per stack on Ice Giants." }
        @{ Flag = "frackTerr";      Name = "Terrain Hardening Kit";        Effect = "40% hazard reduction per stack on Terrestrial planets." }
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
        Write-Host -NoNewline ("   Session Time").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host (Get-SurvivedTime) -ForegroundColor Yellow
        Write-Host -NoNewline ("   Credits Acquired").PadRight($labelW) -ForegroundColor DarkGray
        Write-Host -NoNewline $Player.CreditsAcquired -ForegroundColor Yellow
        Write-Host " CD" -ForegroundColor DarkYellow
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

function Show-Inventory {
    while ($true) {
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
            "Rare"        = 5
            "SuperRare"   = 6
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
		Write-Host " #####" -ForegroundColor DarkGray
        $noticeShown = Write-PlayerNotice
        if ($noticeShown) { Write-Host "" }
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
            Write-Host -NoNewline ($item.Name.PadRight($maxNameLength + 1)) -ForegroundColor (Get-RarityColor $item.Master.Rarity)

            $desc = $item.Master.Description
            Write-Host -NoNewline "| "
            Write-Host -NoNewline ($weightString.PadLeft(6)) -ForegroundColor (Get-PercentColor -Current $itemWeight -Max $Player.MaxWeight -Inverted)
            Write-Host -NoNewline "| "

            if ($item.Master.Effect) {
                $effectText = if ($item.Master.UseMessage) { $item.Master.UseMessage } else { "+$($item.Master.EffectValue) $($item.Master.Effect)" }
                Write-Host -NoNewline "{Consumable: "
                Write-Host -NoNewline $effectText -ForegroundColor (Get-RarityColor $item.Master.Rarity)
                Write-Host -NoNewline "} "
            }
            else {
                Write-Host -NoNewline "["
                Write-Host -NoNewline $item.Master.Rarity -ForegroundColor (Get-RarityColor $item.Master.Rarity)
                Write-Host -NoNewline "] "
            }
            #Write-Host -NoNewline "| "
            Write-Host ($desc.PadRight($maxDescLength + 1)) -ForegroundColor DarkGray

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
                    Use-Item $selected
                }
                else {
                    $Player.Message = "$selected is not consumable."
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
        $fuelPrice   = [math]::Ceiling(($missingFuel * 0.5) * $planetData.FuelModifier)
        $missingHP   = $Player.MaxHP - $Player.HP
        $repairPrice = [math]::Ceiling(($missingHP * 1.0) * $planetData.RepairModifier)
        $fuelColor   = if ($Player.Credits -ge $fuelPrice)   { "Green" } else { "Red" }
        $repairColor = if ($Player.Credits -ge $repairPrice) { "Green" } else { "Red" }

        Write-MenuKey "E" "DarkGray" "Back" "DarkGray"
		Write-Host ""
        Write-MenuKey "1" "Gray" -Label $null
        Write-Host -NoNewline "Repair   " -ForegroundColor Cyan
        Write-Host -NoNewline "$repairPrice CD" -ForegroundColor $repairColor
        Write-Host ""
        Write-MenuKey "2" "Gray" -Label $null
        Write-Host -NoNewline "Refuel   " -ForegroundColor Cyan
        Write-Host "$fuelPrice CD" -ForegroundColor $fuelColor
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
                } else { Set-TraderDialog -PlanetData $planetData -Key "InsufficientFunds" }
            }
        }
        $refuelAction = {
            $currentMissingFuel = $Player.MaxFuel - $Player.Fuel
            $currentFuelPrice = [math]::Ceiling(($currentMissingFuel * 0.5) * $planetData.FuelModifier)
            if ($Player.Fuel -ge $Player.MaxFuel) { Set-TraderDialog -PlanetData $planetData -Key "Frustrated" }
            else {
                if ($Player.Credits -ge $currentFuelPrice) {
                    $Player.Credits -= $currentFuelPrice; $trader.Credits += $currentFuelPrice
                    $Player.Fuel = $Player.MaxFuel; Set-TraderDialog -PlanetData $planetData -Key "Refuel"
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
    while ($true) {
        # Explicitly wrap in @() to fix "single item selection" bug
        $sortedStock = @($trader.Stock.Keys | ForEach-Object {
            $m = $ResourceMaster[$_]
            [PSCustomObject]@{ Name = $_; RarityOrder = $global:RarityOrder[$m.Rarity]; Master = $m }
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

        $i = 1
        foreach ($item in $sortedStock) {
            $qtyString = "x" + $trader.Stock[$item.Name]
            $priceColor = if ($Player.Credits -ge $item.Master.Value) { "Green" } else { "Red" }

            # Dynamic Description with Effects
            $desc = $item.Master.Description
            if ($item.Master.Effect) {
                $desc = "$desc ($($item.Master.Rarity) - +$($item.Master.EffectValue) $($item.Master.Effect))"
            } else {
                $desc = "$desc ($($item.Master.Rarity))"
            }

            Write-Host -NoNewline "[$i] " -ForegroundColor Cyan
            Write-Host -NoNewline ("{0,5}" -f $item.Master.Value + " CD") -ForegroundColor $priceColor
            Write-Host -NoNewline " | "
            Write-Host -NoNewline ($qtyString.PadRight($maxQtyLength + 2)) -ForegroundColor Cyan
            Write-Host -NoNewline ($item.Name.PadRight(15)) -ForegroundColor (Get-RarityColor $item.Master.Rarity)
            $desc = $item.Master.Description
            if ($item.Master.Effect) { Write-Host -NoNewline " | $desc"; Write-Host -NoNewline " (";Write-Host -NoNewline "$($item.Master.Rarity)" -ForegroundColor (Get-RarityColor $item.Master.Rarity); Write-Host ": +$($item.Master.EffectValue) $($item.Master.Effect))" }
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
                    Write-Host -NoNewline "$selectedName" -ForegroundColor (Get-RarityColor $m.Rarity)
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
                $desc = "$desc ($($item.Master.Rarity) - +$($item.Master.EffectValue) $($item.Master.Effect))"
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
            Write-Host -NoNewline $item.Name -ForegroundColor (Get-RarityColor $item.Master.Rarity)
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
            if ($item.Master.Effect) { Write-Host -NoNewline " | $desc"; Write-Host -NoNewline " (";Write-Host -NoNewline "$($item.Master.Rarity)" -ForegroundColor (Get-RarityColor $item.Master.Rarity); Write-Host ": +$($item.Master.EffectValue) $($item.Master.Effect))" }
			else { Write-Host -NoNewline " | $desc"; Write-Host -NoNewline "(";Write-Host -NoNewline "$($item.Master.Rarity)" -ForegroundColor (Get-RarityColor $item.Master.Rarity);Write-Host ")"}
            $i++
        }

        if ($sortedInv.Count -le 16) {
            $hasQuestSurplusItems = $false
            $hasQuestSafeSellItems = $false
            foreach ($item in $sortedInv) {
                if ($item.Master.Rarity -eq "Consumable" -or $item.Master.Rarity -eq "Upgrade") { continue }

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
                if ($item.Master.Rarity -eq "Consumable" -or $item.Master.Rarity -eq "Upgrade") { continue }

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
                    Write-Host -NoNewline "$selectedName" -ForegroundColor (Get-RarityColor $m.Rarity)
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
            Write-Host -NoNewline $req.Item.PadRight(28) -ForegroundColor (Get-RarityColor $ResourceMaster[$req.Item].Rarity)
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
            Write-Host -NoNewline $ri_obj.Item -ForegroundColor (Get-RarityColor $ResourceMaster[$ri_obj.Item].Rarity)
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

                # Completed trader quests go to the log section below” skip here
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
                    Write-Host -NoNewline $req.Item -ForegroundColor (Get-RarityColor $ResourceMaster[$req.Item].Rarity)
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
Write-Host "      -# =---.==@###########==.  +.--.=.##+####      " -ForegroundColor DarkRed -NoNewline;Write-Host "     >=>    >=>    >=>    >=>   >=>     >=>  " -ForegroundColor Red
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
    $Player.Location = $nearest; $Player.Fuel = [math]::Min($Player.MaxFuel, 10); $Player.HP = 50   
    $Player.Dialog = "You were towed to orbit by a Scrapper Union vessel. Don't make them come out again."
    return $true
}

function Show-SolarSystem {
    while ($true) {
        Show-Header
        if ($Player.System) { Write-Host "--- $($Player.System) ---" -ForegroundColor Green }
        Write-Host -NoNewline "[" -ForegroundColor DarkGray
        Write-Host -NoNewline "E" -ForegroundColor Green
        Write-Host -NoNewline "]  Return to " -ForegroundColor DarkGray
		Write-Host -NoNewline "$($Player.Location)" -ForegroundColor ($CurrentSolarSystem[$Player.Location].PlanetColor)
		Write-Host " orbit" -ForegroundColor DarkGray
        
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
			$fuelCost = [math]::Ceiling($distanceAU / 0.1)
            $distanceText = if ($distanceAU -ge 100) { "{0:000.0}" -f $distanceAU } else { "{0:00.00}" -f $distanceAU }
            $fuelText = ("$fuelCost FL").PadRight(6)
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
            
            # Hazard Rating (effective â€” reflects player upgrades)
            $effHzMap = Get-EffectiveHazard $data
            Write-Host -NoNewline "("
            Write-Host -NoNewline "$effHzMap HZ" -ForegroundColor (Get-HazardColor $effHzMap)
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
			$typeCol = switch($data.Type){ "Terrestrial"{"DarkYellow"};"Gas Giant"{"Yellow"};"Ice Giant"{"Cyan"};"Asteroid"{"DarkGray"};"Dwarf"{"DarkGray"};default{"Magenta"} }
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

        Write-Host ""
        Write-MenuKey "C" "Yellow" "Contracts"
        Write-Host ""
        Write-MenuKey "S" "DarkGray" "Save Game"
        Write-MenuKey "L" "DarkGray" "Load Game"

        $choice = (Read-Host ">").ToUpper().Trim()
        if ($choice -eq "E" -or $choice -eq "") { return }
        if ($choice -eq "H" -and $Player.Hyperdrive) { Show-GalaxyMenu; return }
        if ($choice -eq "C") { Show-QuestMenu; continue }
		if ($choice -eq "Q") { Show-QuestMenu; continue }
        if ($choice -eq "S") { Save-Game; continue }
        if ($choice -eq "L") { Show-LoadMenu; continue }
        if ($distressIndex -ne -1 -and $choice -eq [string]$distressIndex) {
            if (Show-DistressSignal) { return }
            continue
        }
        if ($choice -match "^\d+$") {
            $index = [int]$choice
            if ($index -ge 1 -and $index -lt ($planetList.Count + 1)) {
				$selected = $planetList[$index - 1]
                if ($selected.Name -eq $Player.Location) { return }
					$fuelCost = [math]::Ceiling($selected.DistFromPlayer / 0.1)
                if ($fuelCost -le $Player.Fuel) {
                    $Player.Fuel -= $fuelCost; $Player.Location = $selected.Name
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

        $jumpCost = [math]::Floor($Player.Fuel * 0.5)
        Write-Host ""
        Write-Host -NoNewline "   Jump Cost: "
        $costColor = if ($Player.Fuel -ge 50) { "Yellow" } else { "DarkRed" }
        Write-Host "$jumpCost FL (50% current fuel)" -ForegroundColor $costColor
        if ($Player.Fuel -lt 50) { Write-Host "   !! Insufficient fuel for jump (min 50 FL required)" -ForegroundColor DarkRed }
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

                if ($Player.Fuel -lt 50) {
                    $Player.Message = "Not enough fuel for a hyperjump. Need at least 50 FL."
                    continue
                }

                $jumpCost = [math]::Floor($Player.Fuel * 0.5)
                $Player.Fuel -= $jumpCost

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
    $asciiLogoColors = @("DarkCyan", "DarkGray", "Gray", "DarkYellow", "DarkMagenta", "DarkBlue")
    $asciiTextColors = @("DarkCyan", "Cyan", "White", "Gray", "Yellow", "Green", "Magenta")

    while ($true) {
        Clear-Host
        $saves = @(Get-SaveFiles)
        $logoColor = $asciiLogoColors | Get-Random
        $textColor = $asciiTextColors | Get-Random
        $textStart = 6
        $menuStart = 14

        for ($i = 0; $i -lt $asciiLogo.Count; $i++) {
            Write-Host -NoNewline $asciiLogo[$i] -ForegroundColor $logoColor
            $textIndex = $i - $textStart
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
            } elseif ($i -eq $menuStart) {
                Write-Host -NoNewline "                        "
                Write-Host -NoNewline "[" -ForegroundColor DarkGray
                Write-Host -NoNewline "N" -ForegroundColor Cyan
                Write-Host -NoNewline "] " -ForegroundColor DarkGray
                Write-Host -NoNewline "New game" -ForegroundColor DarkCyan
            } elseif ($i -eq ($menuStart + 1) -and $saves.Count -gt 0) {
                Write-Host -NoNewline "                        "
                Write-Host -NoNewline "[" -ForegroundColor DarkGray
                Write-Host -NoNewline "L" -ForegroundColor Green
                Write-Host -NoNewline "] " -ForegroundColor DarkGray
                Write-Host -NoNewline "Load game" -ForegroundColor DarkCyan
            }
            Write-Host ""
        }
        $choice = (Read-Host ">").ToUpper().Trim()
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
    while ($true) {
        Show-Header
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
        Write-Host -NoNewline "[" -ForegroundColor DarkGray
        Write-Host -NoNewline "D" -ForegroundColor DarkRed
        Write-Host -NoNewline "] " -ForegroundColor DarkGray
        Write-Host -NoNewline "Delete Saves" -ForegroundColor DarkRed
        Write-Host "  remove all save files" -ForegroundColor DarkGray
        Write-Host ""

        $saves = @(Get-SaveFiles)

        if ($saves.Count -eq 0) {
            Write-Host "No save files found." -ForegroundColor DarkGray
        } else {
            $i = 1
            foreach ($save in $saves) {
                $meta = $null
                try {
                    $json = Get-Content $save.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $savedAt = [datetime]::Parse($json.SavedAt).ToString("MM/dd/yy hh:mm tt")
                    $ver     = $json.Version
                    $loc     = $json.Player.Location
                    $sys     = $json.SystemName
                    $meta    = "v$ver  |  $savedAt  |  $sys, $loc"
                } catch { $meta = $save.BaseName }

                Write-Host -NoNewline (("[$i]").PadRight(5)) -ForegroundColor Cyan
                Write-Host -NoNewline ($save.BaseName + "  ") -ForegroundColor White
                Write-Host $meta -ForegroundColor DarkGray
                $i++
            }
        }

        Write-Host ""
        $choice = (Read-Host ">").ToUpper().Trim()
        if ($choice -eq "E" -or $choice -eq "") { return "Back" }
        if ($choice -eq "P") {
            Prune-Saves $saves
            continue
        }
        if ($choice -eq "D") {
            Delete-AllSaves $saves
            continue
        }

        if ($choice -match "^\d+$") {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $saves.Count) {
                Load-Game $saves[$idx].FullName
                return "Loaded"
            }
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
        $xrfColor = if ($Player.Fuel -ge 50) { "DarkCyan" } else { "DarkGray" }
        Write-MenuKey "F" $xrfColor -Label $null
        Write-Host -NoNewline "XRF8 Scan " -ForegroundColor DarkGray
        Write-Host -NoNewline $Player.Location -ForegroundColor ($planetData.PlanetColor)
        Write-Host " (50 FL)" -ForegroundColor DarkGray
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
# 0.1.0 - 06/27/2026 - Major update, lots not covered here... Added quest system. New resources and upgrades with hazard mitigation, hyperjumping, scanning planet composition, and more. Input/menus overhaul. Formatting changes/tweaks. Added Typhon-1B solar system with two new factions with more quests/upgrades.

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
#>

# Lots of balancing to do... 
