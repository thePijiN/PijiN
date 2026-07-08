#Requires -Version 5.1
<#
    DELVE
    A single-file PowerShell roguelike dungeon crawler.

    Descend twenty procedurally generated floors, fight monsters, gather loot,
    and try to reach the bottom alive. Death is permanent within a run, but
    every run earns Echoes -- a persistent currency spent at the Sanctuary to
    unlock new classes and permanent perks for future attempts.

    Run it with:
        powershell -ExecutionPolicy Bypass -File .\Delve.ps1

    Target: Windows PowerShell 5.1, best viewed in a terminal at least
    100 columns by 35 rows (Windows Terminal default works well).

#>

# ============================================================================
#  CONSTANTS
# ============================================================================

$Global:GameVersion   = "1.0.2"
$Global:MapWidth       = 70
$Global:MapHeight      = 20
$Global:MaxFloor       = 20
$Global:BossFloors     = @(5, 10, 15, 20)
$Global:AggroRadius    = 6
$Global:RogueTrapSense = 2

$Global:SaveDir  = Join-Path $env:APPDATA "Delve"
$Global:MetaPath = Join-Path $Global:SaveDir "delve_meta.json"
$Global:RunPath  = Join-Path $Global:SaveDir "delve_run.json"

$Global:MessageLog = @()
$Global:Map        = @{}
$Global:Rooms      = @()
$Global:Monsters   = @()
$Global:Player     = $null
$Global:Meta       = $null

# ============================================================================
#  DATA: CLASSES
# ============================================================================

$Global:ClassMaster = [ordered]@{
    "Warrior" = @{
        BaseMaxHP = 28; BaseAttack = 6; BaseDefense = 4; BaseCrit = 0.05; BaseDodge = 0.03
        StartWeapon = "Short Sword"; StartArmor = "Leather Armor"; StartTrinket = $null
        StartItems = @{ "Minor Health Potion" = 2 }
        AbilityName = "Cleave"; AbilityCooldown = 6
        AbilityDesc = "Strike every foe standing next to you for solid damage."
        UnlockCost = 0
        Blurb = "A hardened contract-frack veteran. Tough, dependable, unglamorous."
    }
    "Rogue" = @{
        BaseMaxHP = 22; BaseAttack = 7; BaseDefense = 2; BaseCrit = 0.15; BaseDodge = 0.10
        StartWeapon = "Rusty Dagger"; StartArmor = "Traveler's Cloak"; StartTrinket = $null
        StartItems = @{ "Minor Health Potion" = 1; "Scroll of Teleport" = 1 }
        AbilityName = "Dodge Roll"; AbilityCooldown = 7
        AbilityDesc = "Roll up to three tiles in your last movement direction and guarantee your next strike crits."
        UnlockCost = 250
        Blurb = "Fast, fragile, and allergic to a fair fight. Senses nearby traps."
    }
    "Mage" = @{
        BaseMaxHP = 20; BaseAttack = 5; BaseDefense = 2; BaseCrit = 0.08; BaseDodge = 0.05
        StartWeapon = "Quarter Staff"; StartArmor = "Apprentice Robe"; StartTrinket = $null
        StartItems = @{ "Minor Health Potion" = 1; "Scroll of Fireball" = 1 }
        AbilityName = "Arcane Bolt"; AbilityCooldown = 3
        AbilityDesc = "Hurl a bolt of force at a foe up to five tiles away."
        UnlockCost = 500
        Blurb = "Weak in melee, dangerous at range. Never learned to swing a sword."
    }
}

# ============================================================================
#  DATA: ITEMS
# ============================================================================

$Global:ItemMaster = [ordered]@{
    # --- Potions ---
    "Minor Health Potion"  = @{ Type="Potion"; Effect="Heal"; EffectValue=12; Value=8;  Rarity="Potion"; Symbol="!"; Color="Green"; Description="A weak but reliable restorative brew." }
    "Health Potion"        = @{ Type="Potion"; Effect="Heal"; EffectValue=25; Value=18; Rarity="Potion"; Symbol="!"; Color="Green"; Description="A proper healer's draught." }
    "Greater Health Potion"= @{ Type="Potion"; Effect="Heal"; EffectValue=50; Value=35; Rarity="Potion"; Symbol="!"; Color="DarkGreen"; Description="Thick, glowing, faintly unnerving. Heals deeply." }
    "Antidote"             = @{ Type="Potion"; Effect="CurePoison"; Value=6;  Rarity="Potion"; Symbol="!"; Color="Magenta";   Description="Neutralizes venom and creeping toxins." }
    "Potion of Strength"   = @{ Type="Potion"; Effect="BuffAtk"; EffectValue=1; Value=50; Rarity="PotentPotion"; Symbol="!"; Color="Red";     Description="Permanently hardens muscle and resolve. +1 Attack." }
    "Potion of Fortitude"  = @{ Type="Potion"; Effect="BuffDef"; EffectValue=1; Value=50; Rarity="PotentPotion"; Symbol="!"; Color="Cyan";    Description="Permanently thickens hide and nerve. +1 Defense." }
    "Potion of Vitality"   = @{ Type="Potion"; Effect="BuffMaxHP"; EffectValue=8; Value=55; Rarity="PotentPotion"; Symbol="!"; Color="Yellow"; Description="Permanently deepens your well of life. +8 Max HP." }

    # --- Scrolls ---
    "Scroll of Teleport"    = @{ Type="Scroll"; Effect="Teleport"; Value=15; Rarity="Scroll"; Symbol="?"; Color="Cyan";  Description="Folds space just enough to get you out of trouble." }
    "Scroll of Fireball"    = @{ Type="Scroll"; Effect="Fireball"; Value=25; Rarity="Scroll"; Symbol="?"; Color="Red";   Description="Engulfs nearby foes in sudden, ugly fire." }
    "Scroll of Warding"     = @{ Type="Scroll"; Effect="Warding"; EffectValue=5; Value=20; Rarity="Scroll"; Symbol="?"; Color="Yellow"; Description="Wraps you in a shimmer that turns aside blows. +5 Defense, 10 turns." }
    "Scroll of Revelation"  = @{ Type="Scroll"; Effect="Revelation"; Value=20; Rarity="Scroll"; Symbol="?"; Color="White"; Description="Lays the whole floor bare to your mind's eye." }

    # --- Weapons ---
    "Rusty Dagger"   = @{ Type="Weapon"; Value=10; Rarity="Common";   Symbol="/"; Color="Gray";   Description="Small, quick, and none too sharp."; AtkBonus=2 }
	"Hatchet"        = @{ Type="Weapon"; Value=15; Rarity="Common";   Symbol="/"; Color="Gray";   Description="Standard contractor-issue steel."; AtkBonus=2; CritBonus=0.07 }
	"Quarter Staff"  = @{ Type="Weapon"; Value=25; Rarity="Common";   Symbol="/"; Color="Cyan";   Description="Channels just enough force to matter."; AtkBonus=2; CritBonus=0.25 }
    "Short Sword"    = @{ Type="Weapon"; Value=20; Rarity="Common";   Symbol="/"; Color="Gray";   Description="Standard contractor-issue steel."; AtkBonus=3 }
	"Flanged mace"   = @{ Type="Weapon"; Value=30; Rarity="Uncommon"; Symbol="/"; Color="White";  Description="A sturdy steel flanged mace."; AtkBonus=4 }
    "War Axe"        = @{ Type="Weapon"; Value=45; Rarity="Uncommon"; Symbol="/"; Color="White";  Description="Heavy, brutal, satisfying."; AtkBonus=5 }
    "Longsword"      = @{ Type="Weapon"; Value=60; Rarity="Uncommon"; Symbol="/"; Color="White";  Description="Standard two-handed steel sword."; AtkBonus=6 }
	"Maul"           = @{ Type="Weapon"; Value=50; Rarity="Uncommon"; Symbol="/"; Color="White";  Description="Heavy and slow, but devastating."; AtkBonus=8; CritBonus=0.05; DodgeBonus=-0.33; DefBonus=-2}
    "Rapier"         = @{ Type="Weapon"; Value=55; Rarity="Rare";     Symbol="/"; Color="Yellow"; Description="Finds the gaps in armor."; AtkBonus=4; CritBonus=0.10 }
    "Estoc"          = @{ Type="Weapon"; Value=90; Rarity="Rare";     Symbol="/"; Color="DarkGray";Description="A dueling sword designed for stabbing."; AtkBonus=6; CritBonus=0.10 }
    "Warhammer"      = @{ Type="Weapon"; Value=100;Rarity="Rare";     Symbol="/"; Color="White";  Description="Capable of crushing or piercing foes."; AtkBonus=7; DodgeBonus=-0.05 }

    # --- Armor ---
    "Leather Armor"    = @{ Type="Armor"; Value=15; Rarity="Common";   Symbol="["; Color="DarkYellow"; Description="Broken in. Smells like the last owner."; DefBonus=2 }
    "Traveler's Cloak" = @{ Type="Armor"; Value=20; Rarity="Common";   Symbol="["; Color="DarkGray";   Description="Light enough to run in."; DefBonus=1; DodgeBonus=0.03 }
	"Brigandine"       = @{ Type="Armor"; Value=40; Rarity="Uncommon"; Symbol="["; Color="Gray";       Description="Like a guard's, but with no ensignia."; DefBonus=4 }
	"Chainmail"        = @{ Type="Armor"; Value=40; Rarity="Uncommon"; Symbol="["; Color="Gray";       Description="Heavy, loud, dependable."; DefBonus=5 }
    "Apprentice Robe"  = @{ Type="Armor"; Value=30; Rarity="Common";   Symbol="["; Color="Cyan";       Description="Warded cloth, more than it looks."; DefBonus=1; MaxHPBonus=5 }
    "Plate Armor"      = @{ Type="Armor"; Value=90; Rarity="Rare";     Symbol="["; Color="White";      Description="Nearly a small building. Very slow."; DefBonus=7; DodgeBonus=-0.10 }
    "Shadow Cloak"     = @{ Type="Armor"; Value=70; Rarity="Rare";     Symbol="["; Color="DarkGray";   Description="Seems to bend the eye away from you."; DefBonus=3; DodgeBonus=0.05 }

    # --- Trinkets ---
    "Lucky Coin"       = @{ Type="Trinket"; Value=35; Rarity="Uncommon"; Symbol="*"; Color="Yellow"; Description="Worn smooth by nervous thumbs."; CritBonus=0.05 }
    "Amulet of Vigor"  = @{ Type="Trinket"; Value=40; Rarity="Uncommon"; Symbol="*"; Color="Red";    Description="Fortifies constitution."; MaxHPBonus=8 }
    "Ring of Greed"    = @{ Type="Trinket"; Value=45; Rarity="Uncommon"; Symbol="*"; Color="Yellow"; Description="It wants you to be rich."; GoldBonusPct=0.10 }
    "Charm of Warding" = @{ Type="Trinket"; Value=35; Rarity="Uncommon"; Symbol="*"; Color="Cyan";   Description="Hums faintly when danger is near."; DefBonus=3 }
    "Emberheart"       = @{ Type="Trinket"; Value=45; Rarity="Uncommon"; Symbol="*"; Color="Red";    Description="A coal that never goes cold."; AtkBonus=1; OnHitBurnChance=0.25; OnHitBurnPower=4; OnHitBurnDuration=3 }

    # --- Special (not sold, meta-unlock only) ---
    "Phoenix Plume" = @{ Type="Special"; Value=0; Rarity="Artifact"; Symbol="*"; Color="Yellow"; Description="One more chance than you deserved."; Effect="PhoenixRevive" }
}

# Fill in default fields so every item has the same safe shape.
foreach ($__key in @($Global:ItemMaster.Keys)) {
    $__it = $Global:ItemMaster[$__key]
    foreach ($__f in @('AtkBonus','DefBonus','CritBonus','DodgeBonus','MaxHPBonus','GoldBonusPct','OnHitBurnChance','OnHitBurnPower','OnHitBurnDuration','EffectValue')) {
        if (-not $__it.ContainsKey($__f)) { $__it[$__f] = 0 }
    }
    if (-not $__it.ContainsKey('Effect')) { $__it['Effect'] = "" }
}

# ============================================================================
#  DATA: MONSTERS
# ============================================================================

$Global:MonsterMaster = [ordered]@{
    "Rat"             = @{ Symbol="r"; Color="DarkGray";   BaseHP=6;  BaseAtk=2;  BaseDef=0; XP=3;  GoldMin=1;  GoldMax=3;  MinFloor=1; MaxFloor=8 }
    "Cave Bat"        = @{ Symbol="b"; Color="Gray";       BaseHP=8;  BaseAtk=3;  BaseDef=0; XP=5;  GoldMin=1;  GoldMax=3;  MinFloor=1; MaxFloor=10; Erratic=$true }
    "Giant Spider"    = @{ Symbol="s"; Color="Green";      BaseHP=10; BaseAtk=3;  BaseDef=1; XP=6;  GoldMin=2;  GoldMax=5;  MinFloor=2; MaxFloor=12; SpecialType="Poison"; SpecialChance=0.25; SpecialPower=3; SpecialDuration=4 }
    "Goblin"          = @{ Symbol="g"; Color="DarkYellow"; BaseHP=12; BaseAtk=4;  BaseDef=1; XP=8;  GoldMin=3;  GoldMax=8;  MinFloor=2; MaxFloor=14 }
    "Skeleton"        = @{ Symbol="k"; Color="White";      BaseHP=14; BaseAtk=4;  BaseDef=3; XP=10; GoldMin=2;  GoldMax=6;  MinFloor=3; MaxFloor=16 }
    "Zombie"          = @{ Symbol="z"; Color="DarkGreen";  BaseHP=20; BaseAtk=5;  BaseDef=2; XP=14; GoldMin=4;  GoldMax=10; MinFloor=4; MaxFloor=18; Speed=0.5 }
    "Fire Imp"        = @{ Symbol="i"; Color="Red";        BaseHP=14; BaseAtk=6;  BaseDef=1; XP=16; GoldMin=5;  GoldMax=10; MinFloor=5; MaxFloor=20; SpecialType="Burn"; SpecialChance=0.30; SpecialPower=4; SpecialDuration=3 }
    "Orc Brute"       = @{ Symbol="o"; Color="Red";        BaseHP=24; BaseAtk=7;  BaseDef=3; XP=18; GoldMin=6;  GoldMax=14; MinFloor=5; MaxFloor=20 }
    "Wraith"          = @{ Symbol="w"; Color="Cyan";       BaseHP=16; BaseAtk=8;  BaseDef=2; XP=20; GoldMin=5;  GoldMax=12; MinFloor=6; MaxFloor=20; SpecialType="StatMod"; SpecialChance=0.30; SpecialDuration=4; SpecialDefMod=-3 }
    "Deep One"        = @{ Symbol="d"; Color="Blue";       BaseHP=26; BaseAtk=8;  BaseDef=4; XP=24; GoldMin=8;  GoldMax=15; MinFloor=7; MaxFloor=20 }
    "Stone Golem"     = @{ Symbol="G"; Color="Gray";       BaseHP=35; BaseAtk=9;  BaseDef=6; XP=28; GoldMin=8;  GoldMax=16; MinFloor=8; MaxFloor=20 }
    "Assassin"        = @{ Symbol=","; Color="DarkGray";   BaseHP=18; BaseAtk=10; BaseDef=2; XP=26; GoldMin=10; GoldMax=18; MinFloor=9; MaxFloor=20; SpecialType="Crit"; SpecialChance=0.25 }
}

$Global:BossMaster = @{
    5  = @{ Name="The Bloated Maw";            Symbol="M"; Color="Red";     BaseHP=70;  BaseAtk=9;  BaseDef=3;  XP=90;  GoldMin=50;  GoldMax=80;  SpecialType="Poison";  SpecialChance=0.20; SpecialPower=3; SpecialDuration=3 }
    10 = @{ Name="Karrgoth, Orc Warlord";      Symbol="O"; Color="DarkRed"; BaseHP=130; BaseAtk=15; BaseDef=6;  XP=200; GoldMin=90;  GoldMax=140 }
    15 = @{ Name="The Hollow Wraith King";     Symbol="W"; Color="Cyan";    BaseHP=190; BaseAtk=19; BaseDef=8;  XP=340; GoldMin=150; GoldMax=220; SpecialType="StatMod"; SpecialChance=0.30; SpecialDuration=4; SpecialDefMod=-3 }
    20 = @{ Name="Malphestus, the Deep Warden"; Symbol="D"; Color="Magenta"; BaseHP=280; BaseAtk=25; BaseDef=10; XP=650; GoldMin=300; GoldMax=450; SpecialType="Burn"; SpecialChance=0.25; SpecialPower=5; SpecialDuration=3; Enrage=$true }
}

# Fill in default fields for monsters and bosses.
foreach ($__key in @($Global:MonsterMaster.Keys)) {
    $__m = $Global:MonsterMaster[$__key]
    foreach ($__f in @('Erratic')) { if (-not $__m.ContainsKey($__f)) { $__m[$__f] = $false } }
    if (-not $__m.ContainsKey('Speed')) { $__m['Speed'] = 1.0 }
    foreach ($__f in @('SpecialChance','SpecialPower','SpecialDuration','SpecialDefMod','SpecialAtkMod')) {
        if (-not $__m.ContainsKey($__f)) { $__m[$__f] = 0 }
    }
    if (-not $__m.ContainsKey('SpecialType')) { $__m['SpecialType'] = "" }
}
foreach ($__key in @($Global:BossMaster.Keys)) {
    $__m = $Global:BossMaster[$__key]
    $__m['Erratic'] = $false
    $__m['Speed'] = 1.0
    foreach ($__f in @('SpecialChance','SpecialPower','SpecialDuration','SpecialDefMod','SpecialAtkMod')) {
        if (-not $__m.ContainsKey($__f)) { $__m[$__f] = 0 }
    }
    if (-not $__m.ContainsKey('SpecialType')) { $__m['SpecialType'] = "" }
    if (-not $__m.ContainsKey('Enrage')) { $__m['Enrage'] = $false }
}

# ============================================================================
#  DATA: SANCTUARY PERKS (meta-progression, spent between runs)
# ============================================================================

$Global:PerkMaster = [ordered]@{
    "UnlockRogue"    = @{ Name="Unlock Rogue Class";              Cost=250;  Type="ClassUnlock"; Target="Rogue";  Desc="Fast, crit-fueled, allergic to armor." }
    "UnlockMage"   = @{ Name="Unlock Mage Class";                 Cost=500;  Type="ClassUnlock"; Target="Mage"; Desc="Ranged bolts, thin skin." }
    "VigorTraining"  = @{ Name="Vigor Training";                  Cost=1000;  Type="StatPerk"; Desc="+10 starting Max HP, permanently, on every class." }
    "CombatTraining" = @{ Name="Combat Training";                 Cost=1000;  Type="StatPerk"; Desc="+2 starting Attack, permanently, on every class." }
    "IronSkin"       = @{ Name="Iron Skin";                       Cost=1000;  Type="StatPerk"; Desc="+2 starting Defense, permanently, on every class." }
    "DeepPockets"    = @{ Name="Deep Pockets";                    Cost=2000;  Type="StatPerk"; Desc="+75 starting Gold, permanently, on every class." }
    "PhoenixCharm"   = @{ Name="Phoenix Charm";                   Cost=5000; Type="ItemPerk"; Desc="Every run starts carrying a Phoenix Plume." }
}

# ============================================================================
#  UTILITY HELPERS
# ============================================================================

function Get-Clamp {
    param([double]$Value, [double]$Min, [double]$Max)
    if ($Value -lt $Min) { return $Min }
    if ($Value -gt $Max) { return $Max }
    return $Value
}

function ConvertTo-HashtableDeep {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-HashtableDeep $InputObject[$k] }
        return $h
    }
    if ($InputObject -is [PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
        return $h
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and (-not ($InputObject -is [string]))) {
        $list = @()
        foreach ($item in $InputObject) { $list += ,(ConvertTo-HashtableDeep $item) }
        return $list
    }
    return $InputObject
}

function Add-Message {
    param([string]$Text, [string]$Color = "Gray")
    $Global:MessageLog += ,@{ Text = $Text; Color = $Color }
    if ($Global:MessageLog.Count -gt 60) {
        $Global:MessageLog = $Global:MessageLog[($Global:MessageLog.Count - 60)..($Global:MessageLog.Count - 1)]
    }
}

function Wait-AnyKey {
    param([string]$Prompt = "Press any key to continue...")
    Write-Host ""
    Write-Host $Prompt -ForegroundColor DarkGray
    [void][System.Console]::ReadKey($true)
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        Write-Host "$Prompt (Y/N): " -ForegroundColor Yellow -NoNewline
        $k = [System.Console]::ReadKey($true)
        $ch = $k.KeyChar.ToString().ToUpper()
        Write-Host $ch
        if ($ch -eq 'Y') { return $true }
        if ($ch -eq 'N') { return $false }
    }
}

function Get-HPColor {
    param([double]$Current, [double]$Max)
    if ($Max -le 0) { return "DarkGray" }
    $pct = $Current / $Max
    if ($pct -gt 0.6) { return "Green" }
    if ($pct -gt 0.3) { return "Yellow" }
    return "Red"
}

function Write-Bar {
    param([double]$Current, [double]$Max, [int]$Width = 20, [string]$FullColor = "Green", [string]$EmptyColor = "DarkGray")
    if ($Max -le 0) { $Max = 1 }
    $pct = Get-Clamp -Value ($Current / $Max) -Min 0 -Max 1
    $filled = [int][math]::Round($pct * $Width)
    $empty = $Width - $filled
    Write-Host "[" -NoNewline -ForegroundColor DarkGray
    if ($filled -gt 0) { Write-Host ("#" * $filled) -NoNewline -ForegroundColor $FullColor }
    if ($empty -gt 0) { Write-Host ("-" * $empty) -NoNewline -ForegroundColor $EmptyColor }
    Write-Host "]" -NoNewline -ForegroundColor DarkGray
}

function Get-RarityColor {
    param([string]$Rarity)
    switch ($Rarity) {
        "Common"   { return "Gray" }
        "Uncommon" { return "Green" }
        "Rare"     { return "Cyan" }
        "Artifact" { return "DarkYellow" }
        "Potion"   { return "Magenta" }
        "PotentPotion" { return "DarkMagenta" }
        "Scroll"   { return "Yellow" }
        default    { return "White" }
    }
}

function Get-ClassUnlockCost {
    param([string]$ClassName)
    foreach ($pk in @($Global:PerkMaster.Keys)) {
        $pd = $Global:PerkMaster[$pk]
        if ($pd.Type -eq "ClassUnlock" -and $pd.Target -eq $ClassName) { return $pd.Cost }
    }
    if ($Global:ClassMaster.Contains($ClassName)) { return $Global:ClassMaster[$ClassName].UnlockCost }
    return 0
}

function Test-ClassUnlocked {
    param([string]$ClassName)
    if (-not $Global:ClassMaster.Contains($ClassName)) { return $false }
    $cDef = $Global:ClassMaster[$ClassName]
    if ($cDef.UnlockCost -eq 0) { return $true }
    if (-not $Global:Meta -or -not $Global:Meta.ContainsKey('Unlocked')) { return $false }
    foreach ($pk in @($Global:PerkMaster.Keys)) {
        $pd = $Global:PerkMaster[$pk]
        if ($pd.Type -eq "ClassUnlock" -and $pd.Target -eq $ClassName -and $Global:Meta.Unlocked[$pk]) { return $true }
    }
    return $false
}

function Get-StatusEffectLabel {
    param($Eff)
    switch ($Eff.Type) {
        "Poison" { return "Poisoned" }
        "Burn"   { return "Burning" }
        "Stun"   { return "Stunned" }
        "StatMod" {
            if ($Eff.DefMod -gt 0) { return "Warded" }
            if ($Eff.DefMod -lt 0) { return "Weakened" }
            if ($Eff.AtkMod -gt 0) { return "Empowered" }
            if ($Eff.AtkMod -lt 0) { return "Enfeebled" }
            return "Charmed"
        }
        default { return $Eff.Type }
    }
}

# ============================================================================
#  PERSISTENCE: META (persistent, cross-run progression)
# ============================================================================

function Get-SaveFolder {
    if (-not (Test-Path $Global:SaveDir)) {
        New-Item -ItemType Directory -Path $Global:SaveDir -Force | Out-Null
    }
    return $Global:SaveDir
}

function Get-DefaultMeta {
    $unlocked = @{}
    foreach ($k in @($Global:PerkMaster.Keys)) { $unlocked[$k] = $false }
    return @{
        Version    = "1"
        Echoes     = 0
        TotalEchoesEarned = 0
        Unlocked   = $unlocked
        PilotName  = "Wanderer"
        Stats = @{
            TotalRuns      = 0
            TotalDeaths    = 0
            TotalVictories = 0
            TotalAbandons  = 0
            BestFloor      = 0
            TotalKills     = 0
            TotalGoldEver  = 0
        }
    }
}

function Import-Meta {
    Get-SaveFolder | Out-Null
    if (-not (Test-Path $Global:MetaPath)) {
        $Global:Meta = Get-DefaultMeta
        return
    }
    try {
        $raw = Get-Content -Path $Global:MetaPath -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $loaded = ConvertTo-HashtableDeep $obj
        $default = Get-DefaultMeta
        foreach ($k in $default.Keys) {
            if (-not $loaded.ContainsKey($k)) { $loaded[$k] = $default[$k] }
        }
        foreach ($k in $default.Unlocked.Keys) {
            if (-not $loaded.Unlocked.ContainsKey($k)) { $loaded.Unlocked[$k] = $false }
        }
        foreach ($k in $default.Stats.Keys) {
            if (-not $loaded.Stats.ContainsKey($k)) { $loaded.Stats[$k] = $default.Stats[$k] }
        }
        $Global:Meta = $loaded
    } catch {
        $Global:Meta = Get-DefaultMeta
    }
}

function Export-Meta {
    Get-SaveFolder | Out-Null
    try {
        $Global:Meta | ConvertTo-Json -Depth 8 | Set-Content -Path $Global:MetaPath -ErrorAction Stop
    } catch {
        Add-Message "Warning: could not save progress to disk." "Red"
    }
}

# ============================================================================
#  PERSISTENCE: RUN (single in-progress run)
# ============================================================================

function Test-RunSaveExists {
    return (Test-Path $Global:RunPath)
}

function Export-Run {
    Get-SaveFolder | Out-Null
    try {
        $Global:Player | ConvertTo-Json -Depth 8 | Set-Content -Path $Global:RunPath -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Import-Run {
    if (-not (Test-Path $Global:RunPath)) { return $null }
    try {
        $raw = Get-Content -Path $Global:RunPath -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $p = ConvertTo-HashtableDeep $obj
        if (-not $p.ContainsKey('Inventory') -or $null -eq $p.Inventory) { $p.Inventory = @{} }
        if (-not $p.ContainsKey('Equipment') -or $null -eq $p.Equipment) { $p.Equipment = @{ Weapon=$null; Armor=$null; Trinket=$null } }
        $p.StatusEffects = @()
        $p.AbilityCooldown = 0
        if ($Global:ClassMaster.Contains($p.Class)) {
            $classDef = $Global:ClassMaster[$p.Class]
            $p.AbilityName = $classDef.AbilityName
            $p.AbilityMaxCooldown = $classDef.AbilityCooldown
        }
        if (-not $p.ContainsKey('LastMoveDX')) { $p.LastMoveDX = 0 }
        if (-not $p.ContainsKey('LastMoveDY')) { $p.LastMoveDY = 0 }
        $p.GuaranteedCrit = $false
        $p.Victorious = $false
        return $p
    } catch {
        return $null
    }
}

function Remove-RunSave {
    if (Test-Path $Global:RunPath) {
        Remove-Item -Path $Global:RunPath -Force -ErrorAction SilentlyContinue
    }
}


# ============================================================================
#  PLAYER FACTORY & DERIVED STATS
# ============================================================================

function New-Player {
    param([string]$Name, [string]$Class)

    $def = $Global:ClassMaster[$Class]
    $meta = $Global:Meta

    $bonusHP = 0; $bonusAtk = 0; $bonusDef = 0; $bonusGold = 0
    if ($meta.Unlocked["VigorTraining"])  { $bonusHP = 10 }
    if ($meta.Unlocked["CombatTraining"]) { $bonusAtk = 2 }
    if ($meta.Unlocked["IronSkin"])       { $bonusDef = 2 }
    if ($meta.Unlocked["DeepPockets"])    { $bonusGold = 75 }

    $player = @{
        Name = $Name
        Class = $Class
        Level = 1
        XP = 0
        XPToNext = 20
        Floor = 1
        Turn = 0
        Gold = 20 + $bonusGold
        X = 0
        Y = 0
        BaseMaxHP = $def.BaseMaxHP + $bonusHP
        BaseAttack = $def.BaseAttack + $bonusAtk
        BaseDefense = $def.BaseDefense + $bonusDef
        BaseCrit = $def.BaseCrit
        BaseDodge = $def.BaseDodge
        MaxHP = $def.BaseMaxHP + $bonusHP
        Attack = $def.BaseAttack + $bonusAtk
        Defense = $def.BaseDefense + $bonusDef
        Crit = $def.BaseCrit
        Dodge = $def.BaseDodge
        HP = $def.BaseMaxHP + $bonusHP
        Equipment = @{ Weapon = $def.StartWeapon; Armor = $def.StartArmor; Trinket = $def.StartTrinket }
        Inventory = @{}
        StatusEffects = @()
        AbilityCooldown = 0
        AbilityName = $def.AbilityName
        AbilityMaxCooldown = $def.AbilityCooldown
        KillCount = 0
        GoldCollected = 0
        DeepestFloor = 1
        Alive = $true
        Victorious = $false
        LastMoveDX = 0
        LastMoveDY = 0
        GuaranteedCrit = $false
    }

    foreach ($k in $def.StartItems.Keys) {
        Add-InventoryItem -PlayerRef $player -ItemName $k -Qty $def.StartItems[$k]
    }

    if ($meta.Unlocked["PhoenixCharm"]) {
        Add-InventoryItem -PlayerRef $player -ItemName "Phoenix Plume" -Qty 1
    }

    Update-DerivedStats -Actor $player
    $player.HP = $player.MaxHP
    return $player
}

function Update-DerivedStats {
    param($Actor)

    $atk = $Actor.BaseAttack
    $def = $Actor.BaseDefense
    $crit = $Actor.BaseCrit
    $dodge = $Actor.BaseDodge
    $maxhp = $Actor.BaseMaxHP

    if ($Actor.ContainsKey('Equipment') -and $null -ne $Actor.Equipment) {
        foreach ($slot in @('Weapon', 'Armor', 'Trinket')) {
            $itemName = $Actor.Equipment[$slot]
            if ($itemName -and $Global:ItemMaster.Contains($itemName)) {
                $item = $Global:ItemMaster[$itemName]
                $atk += $item.AtkBonus
                $def += $item.DefBonus
                $crit += $item.CritBonus
                $dodge += $item.DodgeBonus
                $maxhp += $item.MaxHPBonus
            }
        }
    }

    foreach ($eff in @($Actor.StatusEffects)) {
        if ($eff.Type -eq 'StatMod') {
            $atk += $eff.AtkMod
            $def += $eff.DefMod
            $dodge += $eff.DodgeMod
        }
    }

    $Actor.MaxHP = [math]::Max(1, [int][math]::Round($maxhp))
    $Actor.Attack = [math]::Max(0, [int][math]::Round($atk))
    $Actor.Defense = [math]::Max(0, [int][math]::Round($def))
    $Actor.Crit = Get-Clamp -Value $crit -Min 0.0 -Max 0.9
    $Actor.Dodge = Get-Clamp -Value $dodge -Min 0.0 -Max 0.75
    if ($Actor.HP -gt $Actor.MaxHP) { $Actor.HP = $Actor.MaxHP }
}

# ============================================================================
#  STATUS EFFECTS
# ============================================================================

function Add-StatusEffect {
    param($Actor, [string]$Type, [int]$Duration, [int]$Power = 0, [int]$AtkMod = 0, [int]$DefMod = 0, [double]$DodgeMod = 0.0)
    $Actor.StatusEffects += ,@{ Type = $Type; Duration = $Duration; Power = $Power; AtkMod = $AtkMod; DefMod = $DefMod; DodgeMod = $DodgeMod }
    Update-DerivedStats -Actor $Actor
}

function Invoke-StatusTick {
    param($Actor, [string]$Label)
    $survived = $true
    $verbTake = "takes"
    $verbBurn = "burns"
    if ($Label -eq "You") { $verbTake = "take"; $verbBurn = "burn" }
    foreach ($eff in @($Actor.StatusEffects)) {
        if ($eff.Type -eq 'Poison') {
            $Actor.HP -= $eff.Power
            Add-Message "$Label $verbTake $($eff.Power) poison damage." "Green"
        } elseif ($eff.Type -eq 'Burn') {
            $Actor.HP -= $eff.Power
            Add-Message "$Label $verbBurn for $($eff.Power) damage." "Red"
        }
        $eff.Duration -= 1
        if ($Actor.HP -le 0) { $survived = $false }
    }
    $Actor.StatusEffects = @($Actor.StatusEffects | Where-Object { $_.Duration -gt 0 })
    Update-DerivedStats -Actor $Actor
    return $survived
}

function Test-Stunned {
    param($Actor)
    foreach ($eff in @($Actor.StatusEffects)) {
        if ($eff.Type -eq 'Stun') { return $true }
    }
    return $false
}

# ============================================================================
#  INVENTORY / EQUIPMENT
# ============================================================================

function Add-InventoryItem {
    param($PlayerRef, [string]$ItemName, [int]$Qty = 1)
    if (-not $PlayerRef.Inventory.ContainsKey($ItemName)) {
        $PlayerRef.Inventory[$ItemName] = 0
    }
    $PlayerRef.Inventory[$ItemName] += $Qty
}

function Remove-InventoryItem {
    param($PlayerRef, [string]$ItemName, [int]$Qty = 1)
    if (-not $PlayerRef.Inventory.ContainsKey($ItemName)) { return $false }
    if ($PlayerRef.Inventory[$ItemName] -lt $Qty) { return $false }
    $PlayerRef.Inventory[$ItemName] -= $Qty
    if ($PlayerRef.Inventory[$ItemName] -le 0) { $PlayerRef.Inventory.Remove($ItemName) }
    return $true
}

function Get-ItemCount {
    param($PlayerRef, [string]$ItemName)
    if ($PlayerRef.Inventory.ContainsKey($ItemName)) { return $PlayerRef.Inventory[$ItemName] }
    return 0
}

function Set-EquipItem {
    param($PlayerRef, [string]$ItemName)
    $item = $Global:ItemMaster[$ItemName]
    if (-not $item) { return }
    $slot = $item.Type
    if ($slot -ne 'Weapon' -and $slot -ne 'Armor' -and $slot -ne 'Trinket') { return }
    if (-not (Remove-InventoryItem -PlayerRef $PlayerRef -ItemName $ItemName -Qty 1)) { return }

    $current = $PlayerRef.Equipment[$slot]
    if ($current) {
        Add-InventoryItem -PlayerRef $PlayerRef -ItemName $current -Qty 1
    }
    $PlayerRef.Equipment[$slot] = $ItemName
    Update-DerivedStats -Actor $PlayerRef
    Add-Message "You equip the $ItemName." "Cyan"
}

function Set-UnequipItem {
    param($PlayerRef, [string]$Slot)
    $current = $PlayerRef.Equipment[$Slot]
    if (-not $current) { return }
    Add-InventoryItem -PlayerRef $PlayerRef -ItemName $current -Qty 1
    $PlayerRef.Equipment[$Slot] = $null
    Update-DerivedStats -Actor $PlayerRef
    Add-Message "You unequip the $current." "DarkGray"
}


# ============================================================================
#  DUNGEON GENERATION
# ============================================================================

function Test-Walkable {
    param([int]$X, [int]$Y)
    if ($X -lt 0 -or $X -ge $Global:MapWidth -or $Y -lt 0 -or $Y -ge $Global:MapHeight) { return $false }
    $tile = $Global:Map["$X,$Y"]
    if (-not $tile) { return $false }
    return ($tile.Type -ne "Wall")
}

function Test-RoomOverlap {
    param($Rooms, [int]$X1, [int]$Y1, [int]$X2, [int]$Y2)
    foreach ($r in $Rooms) {
        if ($X1 -le ($r.X2 + 1) -and $X2 -ge ($r.X1 - 1) -and $Y1 -le ($r.Y2 + 1) -and $Y2 -ge ($r.Y1 - 1)) {
            return $true
        }
    }
    return $false
}

function Set-CorridorRow {
    param([int]$Y, [int]$XFrom, [int]$XTo)
    $lo = [math]::Min($XFrom, $XTo)
    $hi = [math]::Max($XFrom, $XTo)
    for ($x = $lo; $x -le $hi; $x++) {
        $key = "$x,$Y"
        if ($Global:Map[$key].Type -eq "Wall") { $Global:Map[$key].Type = "Floor" }
    }
}

function Set-CorridorCol {
    param([int]$X, [int]$YFrom, [int]$YTo)
    $lo = [math]::Min($YFrom, $YTo)
    $hi = [math]::Max($YFrom, $YTo)
    for ($y = $lo; $y -le $hi; $y++) {
        $key = "$X,$y"
        if ($Global:Map[$key].Type -eq "Wall") { $Global:Map[$key].Type = "Floor" }
    }
}

function New-Corridor {
    param([int]$X1, [int]$Y1, [int]$X2, [int]$Y2)
    if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
        Set-CorridorRow -Y $Y1 -XFrom $X1 -XTo $X2
        Set-CorridorCol -X $X2 -YFrom $Y1 -YTo $Y2
    } else {
        Set-CorridorCol -X $X1 -YFrom $Y1 -YTo $Y2
        Set-CorridorRow -Y $Y2 -XFrom $X1 -XTo $X2
    }
}

function Get-RandomFloorTileInRoom {
    param([int]$RoomIdx)
    $room = $Global:Rooms[$RoomIdx]
    for ($tries = 0; $tries -lt 30; $tries++) {
        $x = Get-Random -Minimum $room.X1 -Maximum ($room.X2 + 1)
        $y = Get-Random -Minimum $room.Y1 -Maximum ($room.Y2 + 1)
        $tile = $Global:Map["$x,$y"]
        if ($tile.Type -eq "Floor") { return @{ X = $x; Y = $y } }
    }
    return $null
}

function Test-TileOccupiedByMonster {
    param([int]$X, [int]$Y)
    foreach ($m in $Global:Monsters) {
        if ($m.Alive -and $m.X -eq $X -and $m.Y -eq $Y) { return $true }
    }
    return $false
}

function New-MonsterInstance {
    param($Def, [int]$FloorNum, [bool]$IsBoss, [string]$Name)

    $scale = 1.0 + (($FloorNum - 1) * 0.12)
    if ($IsBoss) {
        $hp = $Def.BaseHP
        $atk = $Def.BaseAtk
        $defense = $Def.BaseDef
    } else {
        $hp = [int][math]::Ceiling($Def.BaseHP * $scale)
        $atk = [int][math]::Ceiling($Def.BaseAtk * $scale)
        $defense = [int][math]::Ceiling($Def.BaseDef * $scale * 0.8)
    }

    $gold = Get-Random -Minimum $Def.GoldMin -Maximum ($Def.GoldMax + 1)

    return @{
        Name = $Name
        Symbol = $Def.Symbol
        Color = $Def.Color
        X = 0; Y = 0
        BaseMaxHP = $hp; BaseAttack = $atk; BaseDefense = $defense
        BaseCrit = 0.05; BaseDodge = 0.0
        MaxHP = $hp; Attack = $atk; Defense = $defense; Crit = 0.05; Dodge = 0.0
        HP = $hp
        Equipment = @{ Weapon = $null; Armor = $null; Trinket = $null }
        StatusEffects = @()
        XPReward = $Def.XP
        GoldReward = $gold
        SpecialType = $Def.SpecialType
        SpecialChance = $Def.SpecialChance
        SpecialPower = $Def.SpecialPower
        SpecialDuration = $Def.SpecialDuration
        SpecialDefMod = $Def.SpecialDefMod
        Erratic = $Def.Erratic
        Speed = $Def.Speed
        TurnAccumulator = 0.0
        IsBoss = $IsBoss
        Enrage = $Def.Enrage
        IsFinalBoss = ($FloorNum -eq $Global:MaxFloor -and $IsBoss)
        Alive = $true
        Aggro = $IsBoss
    }
}

function Add-DungeonFeatures {
    param([int]$FloorNum)

    $isBossFloor = $Global:BossFloors -contains $FloorNum
    $isShopFloor = (($FloorNum % 5) -eq 4) -and ($FloorNum -lt $Global:MaxFloor)

    $lastIdx = $Global:Rooms.Count - 1
    $stairsRoom = $Global:Rooms[$lastIdx]
    $Global:Map["$($stairsRoom.CenterX),$($stairsRoom.CenterY)"].Type = "Stairs"

    $midRooms = @()
    for ($i = 1; $i -lt $lastIdx; $i++) { $midRooms += , $i }
    if ($midRooms.Count -eq 0) { $midRooms = @($lastIdx) }

    if ($isBossFloor) {
        $bossDef = $Global:BossMaster[$FloorNum]
        $boss = New-MonsterInstance -Def $bossDef -FloorNum $FloorNum -IsBoss $true -Name $bossDef.Name
        $boss.X = $stairsRoom.CenterX
        $bossY = $stairsRoom.CenterY - 1
        if ($bossY -lt $stairsRoom.Y1) { $bossY = $stairsRoom.Y1 }
        $boss.Y = $bossY
        $Global:Monsters += , $boss
    }

    if ($isShopFloor -and $midRooms.Count -gt 0) {
        $shopRoomIdx = Get-Random -InputObject $midRooms
        $Global:Rooms[$shopRoomIdx].Type = "Shop"
        $Global:Map["$($Global:Rooms[$shopRoomIdx].CenterX),$($Global:Rooms[$shopRoomIdx].CenterY)"].Type = "Shop"
        $midRooms = @($midRooms | Where-Object { $_ -ne $shopRoomIdx })
    }

    if ((-not $isBossFloor) -and (-not $isShopFloor) -and $midRooms.Count -gt 0) {
        if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.45) {
            $shrineRoomIdx = Get-Random -InputObject $midRooms
            $Global:Rooms[$shrineRoomIdx].Type = "Shrine"
            $shrineKey = "$($Global:Rooms[$shrineRoomIdx].CenterX),$($Global:Rooms[$shrineRoomIdx].CenterY)"
            $Global:Map[$shrineKey].Type = "Shrine"
            $Global:Map[$shrineKey].Used = $false
            $midRooms = @($midRooms | Where-Object { $_ -ne $shrineRoomIdx })
        }
    }

    $chestRoomIdx = $lastIdx
    if ($midRooms.Count -gt 0) { $chestRoomIdx = Get-Random -InputObject $midRooms }
    $chestPos = Get-RandomFloorTileInRoom -RoomIdx $chestRoomIdx
    if ($chestPos) {
        $ck = "$($chestPos.X),$($chestPos.Y)"
        $Global:Map[$ck].Type = "Chest"
        $Global:Map[$ck].Opened = $false
    }

    if (-not $isBossFloor) {
        $count = 4 + [int][math]::Floor($FloorNum / 2) + (Get-Random -Minimum -1 -Maximum 3)
        $count = [int](Get-Clamp -Value $count -Min 3 -Max 16)
    } else {
        $count = 2 + [int][math]::Floor($FloorNum / 4)
        $count = [int](Get-Clamp -Value $count -Min 2 -Max 8)
    }

    $pool = @()
    foreach ($k in @($Global:MonsterMaster.Keys)) {
        $md = $Global:MonsterMaster[$k]
        if ($FloorNum -ge $md.MinFloor -and $FloorNum -le $md.MaxFloor) { $pool += , $k }
    }
    if ($pool.Count -eq 0) { $pool = @(@($Global:MonsterMaster.Keys)[0]) }

    $spawnRoomIndices = @()
    for ($i = 1; $i -le $lastIdx; $i++) { $spawnRoomIndices += , $i }
    if ($spawnRoomIndices.Count -eq 0) { $spawnRoomIndices = @(0) }

    for ($i = 0; $i -lt $count; $i++) {
        $rIdx = Get-Random -InputObject $spawnRoomIndices
        if ($Global:Rooms[$rIdx].Type -eq "Shop") { continue }
        $mName = Get-Random -InputObject $pool
        $mDef = $Global:MonsterMaster[$mName]
        $pos = Get-RandomFloorTileInRoom -RoomIdx $rIdx
        if (-not $pos) { continue }
        if (Test-TileOccupiedByMonster -X $pos.X -Y $pos.Y) { continue }
        $mon = New-MonsterInstance -Def $mDef -FloorNum $FloorNum -IsBoss $false -Name $mName
        $mon.X = $pos.X
        $mon.Y = $pos.Y
        $Global:Monsters += , $mon
    }

    $goldCount = Get-Random -Minimum 3 -Maximum 7
    for ($i = 0; $i -lt $goldCount; $i++) {
        $rIdx = Get-Random -InputObject $spawnRoomIndices
        $pos = Get-RandomFloorTileInRoom -RoomIdx $rIdx
        if (-not $pos) { continue }
        $tile = $Global:Map["$($pos.X),$($pos.Y)"]
        if ($tile.Type -ne "Floor") { continue }
        $amt = (Get-Random -Minimum 3 -Maximum 8) + ($FloorNum * 1.5)
        $tile.Type = "Gold"
        $tile.GoldAmt = $amt
    }

    $potionScrollPool = @()
    $equipPool = @()
    foreach ($k in @($Global:ItemMaster.Keys)) {
        $it = $Global:ItemMaster[$k]
        if ($it.Type -eq "Potion" -or $it.Type -eq "Scroll") { $potionScrollPool += , $k }
        if ($it.Type -eq "Weapon" -or $it.Type -eq "Armor" -or $it.Type -eq "Trinket") { $equipPool += , $k }
    }

    $itemCount = Get-Random -Minimum 2 -Maximum 5
    for ($i = 0; $i -lt $itemCount; $i++) {
        $rIdx = Get-Random -InputObject $spawnRoomIndices
        $pos = Get-RandomFloorTileInRoom -RoomIdx $rIdx
        if (-not $pos) { continue }
        $tile = $Global:Map["$($pos.X),$($pos.Y)"]
        if ($tile.Type -ne "Floor") { continue }
        $itemName = Get-Random -InputObject $potionScrollPool
        $tile.Type = "Item"
        $tile.ItemName = $itemName
    }

    if (((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.4) -and ($equipPool.Count -gt 0)) {
        $rIdx = Get-Random -InputObject $spawnRoomIndices
        $pos = Get-RandomFloorTileInRoom -RoomIdx $rIdx
        if ($pos) {
            $tile = $Global:Map["$($pos.X),$($pos.Y)"]
            if ($tile.Type -eq "Floor") {
                $itemName = Get-Random -InputObject $equipPool
                $tile.Type = "Item"
                $tile.ItemName = $itemName
            }
        }
    }

    $trapCount = 2 + [int][math]::Floor($FloorNum / 5)
    $trapCount = [int](Get-Clamp -Value $trapCount -Min 2 -Max 6)
    $trapTypes = @("Spike", "Gas", "Pitfall")
    for ($i = 0; $i -lt $trapCount; $i++) {
        $rIdx = Get-Random -InputObject $spawnRoomIndices
        $pos = Get-RandomFloorTileInRoom -RoomIdx $rIdx
        if (-not $pos) { continue }
        $tile = $Global:Map["$($pos.X),$($pos.Y)"]
        if ($tile.Type -ne "Floor") { continue }
        $tile.Type = "Trap"
        $tile.TrapType = Get-Random -InputObject $trapTypes
        $tile.Revealed = $false
        $tile.Detected = $false
        $tile.Triggered = $false
    }
}

function New-Dungeon {
    param([int]$FloorNum)

    $Global:Map = @{}
    for ($y = 0; $y -lt $Global:MapHeight; $y++) {
        for ($x = 0; $x -lt $Global:MapWidth; $x++) {
            $Global:Map["$x,$y"] = @{ Type = "Wall"; Discovered = $false }
        }
    }

    $Global:Rooms = @()
    $numRoomsTarget = Get-Random -Minimum 8 -Maximum 13
    $attempts = 0
    while ($Global:Rooms.Count -lt $numRoomsTarget -and $attempts -lt 300) {
        $attempts++
        $w = Get-Random -Minimum 5 -Maximum 12
        $h = Get-Random -Minimum 4 -Maximum 8
        $x1 = Get-Random -Minimum 1 -Maximum ($Global:MapWidth - $w - 1)
        $y1 = Get-Random -Minimum 1 -Maximum ($Global:MapHeight - $h - 1)
        $x2 = $x1 + $w - 1
        $y2 = $y1 + $h - 1
        if (-not (Test-RoomOverlap -Rooms $Global:Rooms -X1 $x1 -Y1 $y1 -X2 $x2 -Y2 $y2)) {
            $room = @{ X1 = $x1; Y1 = $y1; X2 = $x2; Y2 = $y2; CenterX = [int](($x1 + $x2) / 2); CenterY = [int](($y1 + $y2) / 2); Type = "Normal" }
            for ($yy = $y1; $yy -le $y2; $yy++) {
                for ($xx = $x1; $xx -le $x2; $xx++) {
                    $Global:Map["$xx,$yy"].Type = "Floor"
                }
            }
            $Global:Rooms += , $room
        }
    }

    if ($Global:Rooms.Count -eq 0) {
        $room = @{ X1 = 2; Y1 = 2; X2 = 10; Y2 = 8; CenterX = 6; CenterY = 5; Type = "Normal" }
        for ($yy = 2; $yy -le 8; $yy++) { for ($xx = 2; $xx -le 10; $xx++) { $Global:Map["$xx,$yy"].Type = "Floor" } }
        $Global:Rooms += , $room
    }

    for ($i = 1; $i -lt $Global:Rooms.Count; $i++) {
        New-Corridor -X1 $Global:Rooms[$i - 1].CenterX -Y1 $Global:Rooms[$i - 1].CenterY -X2 $Global:Rooms[$i].CenterX -Y2 $Global:Rooms[$i].CenterY
    }
    $extra = [int]([math]::Floor($Global:Rooms.Count / 4))
    for ($i = 0; $i -lt $extra; $i++) {
        $a = Get-Random -Minimum 0 -Maximum $Global:Rooms.Count
        $b = Get-Random -Minimum 0 -Maximum $Global:Rooms.Count
        if ($a -ne $b) {
            New-Corridor -X1 $Global:Rooms[$a].CenterX -Y1 $Global:Rooms[$a].CenterY -X2 $Global:Rooms[$b].CenterX -Y2 $Global:Rooms[$b].CenterY
        }
    }

    $Global:Rooms[0].Type = "Start"
    $lastIdx = $Global:Rooms.Count - 1
    $Global:Rooms[$lastIdx].Type = "Stairs"

    Add-DungeonFeatures -FloorNum $FloorNum

    return @{ X = $Global:Rooms[0].CenterX; Y = $Global:Rooms[0].CenterY }
}

function Update-Visibility {
    param([int]$PX, [int]$PY)

    $inRoom = $null
    foreach ($r in $Global:Rooms) {
        if ($PX -ge $r.X1 -and $PX -le $r.X2 -and $PY -ge $r.Y1 -and $PY -le $r.Y2) { $inRoom = $r; break }
    }

    if ($inRoom) {
        for ($y = $inRoom.Y1; $y -le $inRoom.Y2; $y++) {
            for ($x = $inRoom.X1; $x -le $inRoom.X2; $x++) {
                $Global:Map["$x,$y"].Discovered = $true
            }
        }
    }

    $radius = 1
    for ($dy = -$radius; $dy -le $radius; $dy++) {
        for ($dx = -$radius; $dx -le $radius; $dx++) {
            $x = $PX + $dx
            $y = $PY + $dy
            $key = "$x,$y"
            if ($Global:Map.ContainsKey($key)) { $Global:Map[$key].Discovered = $true }
        }
    }

    if ($Global:Player -and $Global:Player.Class -eq 'Rogue') {
        $tr = $Global:RogueTrapSense
        for ($dy = -$tr; $dy -le $tr; $dy++) {
            for ($dx = -$tr; $dx -le $tr; $dx++) {
                $x = $PX + $dx
                $y = $PY + $dy
                $key = "$x,$y"
                if ($Global:Map.ContainsKey($key) -and $Global:Map[$key].Type -eq "Trap") {
                    $Global:Map[$key].Discovered = $true
                    $Global:Map[$key].Detected = $true
                }
            }
        }
    }
}

function Start-NewFloor {
    param([int]$FloorNum)
    $Global:Monsters = @()
    $spawn = New-Dungeon -FloorNum $FloorNum
    $Global:Player.X = $spawn.X
    $Global:Player.Y = $spawn.Y
    $Global:Player.Floor = $FloorNum
    if ($FloorNum -gt $Global:Player.DeepestFloor) { $Global:Player.DeepestFloor = $FloorNum }
    Update-Visibility -PX $spawn.X -PY $spawn.Y
    Add-Message "You descend to floor $FloorNum." "White"
    if ($Global:BossFloors -contains $FloorNum) {
        Add-Message "Something huge stirs in the dark ahead." "Red"
    }
}


# ============================================================================
#  COMBAT
# ============================================================================

function Get-AttackResult {
    param([int]$Attack, [int]$Defense, [double]$CritChance = 0.05, [double]$DodgeChance = 0.0, [double]$CritMultiplier = 1.75, [bool]$ForceCrit = $false)
    if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $DodgeChance) {
        return @{ Hit = $false; Damage = 0; Crit = $false }
    }
    $variance = Get-Random -Minimum -2 -Maximum 4
    $raw = $Attack - [math]::Floor($Defense / 2) + $variance
    $dmg = [math]::Max(1, $raw)
    $isCrit = $ForceCrit -or ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $CritChance)
    if ($isCrit) { $dmg = [int][math]::Floor($dmg * $CritMultiplier) }
    return @{ Hit = $true; Damage = $dmg; Crit = $isCrit }
}

function Get-TrinketGoldBonus {
    $t = $Global:Player.Equipment.Trinket
    if ($t -and $Global:ItemMaster.Contains($t)) { return $Global:ItemMaster[$t].GoldBonusPct }
    return 0.0
}

function Grant-XP {
    param([int]$Amount)
    $Global:Player.XP += $Amount
    Add-Message "You gain $Amount XP." "Cyan"
    while ($Global:Player.XP -ge $Global:Player.XPToNext) {
        $Global:Player.XP -= $Global:Player.XPToNext
        $Global:Player.Level += 1
        $Global:Player.BaseMaxHP += 6
        $Global:Player.BaseAttack += 1
        if ($Global:Player.Level % 2 -eq 0) { $Global:Player.BaseDefense += 1 }
        $Global:Player.XPToNext = 20 + (($Global:Player.Level - 1) * 12)
        Update-DerivedStats -Actor $Global:Player
        $Global:Player.HP = $Global:Player.MaxHP
        Add-Message "You reach level $($Global:Player.Level)! Fully healed." "Yellow"
    }
}

function Invoke-MonsterDeath {
    param($Monster)
    $Monster.Alive = $false
    $Global:Player.KillCount += 1
    $bonus = Get-TrinketGoldBonus
    $goldGain = [int]([math]::Round($Monster.GoldReward * (1 + $bonus)))
    $Global:Player.Gold += $goldGain
    $Global:Player.GoldCollected += $goldGain
    Add-Message "You defeat the $($Monster.Name)! (+$goldGain gold)" "Yellow"
    Grant-XP -Amount $Monster.XPReward
    if ($Monster.IsFinalBoss) {
        Show-VictoryScreen
    } elseif ($Monster.IsBoss) {
        Add-Message "The way forward is clear." "Green"
    }
}

function Resolve-PlayerAttack {
    param($Monster)
    $forceCrit = $Global:Player.GuaranteedCrit
    $result = Get-AttackResult -Attack $Global:Player.Attack -Defense $Monster.Defense -CritChance $Global:Player.Crit -DodgeChance $Monster.Dodge -ForceCrit $forceCrit
    if ($forceCrit) { $Global:Player.GuaranteedCrit = $false }

    if (-not $result.Hit) {
        Add-Message "The $($Monster.Name) dodges your attack!" "DarkGray"
        return
    }
    $Monster.HP -= $result.Damage
    if ($result.Crit) {
        Add-Message "Critical hit! You deal $($result.Damage) damage to the $($Monster.Name)." "Yellow"
    } else {
        Add-Message "You hit the $($Monster.Name) for $($result.Damage) damage." "White"
    }

    $trinket = $Global:Player.Equipment.Trinket
    if ($trinket -and $Global:ItemMaster.Contains($trinket)) {
        $ti = $Global:ItemMaster[$trinket]
        if ($ti.OnHitBurnChance -gt 0 -and (Get-Random -Minimum 0.0 -Maximum 1.0) -lt $ti.OnHitBurnChance) {
            Add-StatusEffect -Actor $Monster -Type "Burn" -Duration $ti.OnHitBurnDuration -Power $ti.OnHitBurnPower
            Add-Message "The $($Monster.Name) catches fire!" "Red"
        }
    }

    if ($Monster.HP -le 0) {
        Invoke-MonsterDeath -Monster $Monster
    }
}

function Resolve-MonsterAttack {
    param($Monster)
    if ($Monster.IsFinalBoss -and (($Monster.HP / $Monster.MaxHP) -lt 0.3)) {
        $atk = [int][math]::Round($Monster.Attack * 1.5)
    } else {
        $atk = $Monster.Attack
    }
    $critChance = $Monster.Crit
    if ($Monster.SpecialType -eq 'Crit') { $critChance += $Monster.SpecialChance }

    $result = Get-AttackResult -Attack $atk -Defense $Global:Player.Defense -CritChance $critChance -DodgeChance $Global:Player.Dodge
    if (-not $result.Hit) {
        Add-Message "You dodge the $($Monster.Name)'s attack!" "DarkGray"
        return
    }
    $Global:Player.HP -= $result.Damage
    if ($result.Crit) {
        Add-Message "The $($Monster.Name) lands a brutal hit for $($result.Damage) damage!" "Red"
    } else {
        Add-Message "The $($Monster.Name) hits you for $($result.Damage) damage." "Red"
    }

    if ($Monster.SpecialType -eq 'Poison' -and ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $Monster.SpecialChance)) {
        Add-StatusEffect -Actor $Global:Player -Type "Poison" -Duration $Monster.SpecialDuration -Power $Monster.SpecialPower
        Add-Message "You've been poisoned!" "Green"
    } elseif ($Monster.SpecialType -eq 'Burn' -and ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $Monster.SpecialChance)) {
        Add-StatusEffect -Actor $Global:Player -Type "Burn" -Duration $Monster.SpecialDuration -Power $Monster.SpecialPower
        Add-Message "You are set ablaze!" "Red"
    } elseif ($Monster.SpecialType -eq 'StatMod' -and ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $Monster.SpecialChance)) {
        Add-StatusEffect -Actor $Global:Player -Type "StatMod" -Duration $Monster.SpecialDuration -DefMod $Monster.SpecialDefMod
        Add-Message "You feel your defenses weaken!" "Magenta"
    }

    Invoke-PlayerDeathCheck
}

function Invoke-PlayerDeathCheck {
    if ($Global:Player.HP -gt 0) { return }
    if ((Get-ItemCount -PlayerRef $Global:Player -ItemName "Phoenix Plume") -gt 0) {
        Remove-InventoryItem -PlayerRef $Global:Player -ItemName "Phoenix Plume" -Qty 1
        $Global:Player.HP = [int][math]::Ceiling($Global:Player.MaxHP * 0.5)
        $Global:Player.StatusEffects = @()
        Update-DerivedStats -Actor $Global:Player
        Add-Message "The Phoenix Plume flares -- you're pulled back from the brink!" "Yellow"
        return
    }
    $Global:Player.Alive = $false
}

# ============================================================================
#  MONSTER AI
# ============================================================================

function Get-MonsterStep {
    param([int]$MX, [int]$MY, [int]$PX, [int]$PY)
    $dx = $PX - $MX
    $dy = $PY - $MY
    $moves = @()
    if ([math]::Abs($dx) -ge [math]::Abs($dy)) {
        if ($dx -ne 0) { $moves += , @([math]::Sign($dx), 0) }
        if ($dy -ne 0) { $moves += , @(0, [math]::Sign($dy)) }
    } else {
        if ($dy -ne 0) { $moves += , @(0, [math]::Sign($dy)) }
        if ($dx -ne 0) { $moves += , @([math]::Sign($dx), 0) }
    }
    return $moves
}

function Invoke-MonsterTurns {
    foreach ($m in @($Global:Monsters)) {
        if (-not $Global:Player.Alive) { return }
        if (-not $m.Alive) { continue }

        $survived = Invoke-StatusTick -Actor $m -Label "The $($m.Name)"
        if (-not $survived) {
            Add-Message "The $($m.Name) succumbs." "Yellow"
            Invoke-MonsterDeath -Monster $m
            continue
        }
        if (-not $m.Alive) { continue }

        $m.TurnAccumulator += $m.Speed
        if ($m.TurnAccumulator -lt 1.0) { continue }
        $m.TurnAccumulator -= 1.0

        $dx = $Global:Player.X - $m.X
        $dy = $Global:Player.Y - $m.Y
        $dist = [math]::Max([math]::Abs($dx), [math]::Abs($dy))

        if ((-not $m.Aggro) -and ($dist -le $Global:AggroRadius)) { $m.Aggro = $true }

        if (-not $m.Aggro) {
            if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.3) {
                $dirs = @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))
                $pick = Get-Random -InputObject $dirs
                $nx = $m.X + $pick[0]
                $ny = $m.Y + $pick[1]
                if ((Test-Walkable -X $nx -Y $ny) -and (-not (Test-TileOccupiedByMonster -X $nx -Y $ny)) -and (-not ($nx -eq $Global:Player.X -and $ny -eq $Global:Player.Y))) {
                    $m.X = $nx
                    $m.Y = $ny
                }
            }
            continue
        }

        if (([math]::Abs($dx) + [math]::Abs($dy)) -eq 1) {
            Resolve-MonsterAttack -Monster $m
            continue
        }

        if ($m.Erratic -and ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.4)) {
            $dirs = @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))
            $pick = Get-Random -InputObject $dirs
            $nx = $m.X + $pick[0]
            $ny = $m.Y + $pick[1]
            if ((Test-Walkable -X $nx -Y $ny) -and (-not (Test-TileOccupiedByMonster -X $nx -Y $ny)) -and (-not ($nx -eq $Global:Player.X -and $ny -eq $Global:Player.Y))) {
                $m.X = $nx
                $m.Y = $ny
            }
            continue
        }

        $candidates = Get-MonsterStep -MX $m.X -MY $m.Y -PX $Global:Player.X -PY $Global:Player.Y
        foreach ($c in $candidates) {
            $nx = $m.X + $c[0]
            $ny = $m.Y + $c[1]
            if ($nx -eq $Global:Player.X -and $ny -eq $Global:Player.Y) { continue }
            if ((Test-Walkable -X $nx -Y $ny) -and (-not (Test-TileOccupiedByMonster -X $nx -Y $ny))) {
                $m.X = $nx
                $m.Y = $ny
                break
            }
        }
    }
    Invoke-PlayerDeathCheck
}


# ============================================================================
#  PLAYER ACTIONS
# ============================================================================

function Invoke-EndOfTurn {
    $Global:Player.Turn += 1
    if ($Global:Player.AbilityCooldown -gt 0) { $Global:Player.AbilityCooldown -= 1 }
    Invoke-StatusTick -Actor $Global:Player -Label "You" | Out-Null
    Invoke-PlayerDeathCheck
    if ($Global:Player.Alive -and $Global:Player.HP -gt 0) {
        Invoke-MonsterTurns
    }
    Invoke-PlayerDeathCheck
}

function Open-Chest {
    param($Tile)
    $gold = (Get-Random -Minimum 10 -Maximum 31) + ($Global:Player.Floor * 2)
    $bonus = Get-TrinketGoldBonus
    $gold = [int]([math]::Round($gold * (1 + $bonus)))
    $Global:Player.Gold += $gold
    $Global:Player.GoldCollected += $gold
    Add-Message "You open a chest and find $gold gold!" "Yellow"

    $rollEquip = (Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.4
    $pool = @()
    foreach ($k in @($Global:ItemMaster.Keys)) {
        $it = $Global:ItemMaster[$k]
        if ($rollEquip -and ($it.Type -eq "Weapon" -or $it.Type -eq "Armor" -or $it.Type -eq "Trinket")) { $pool += , $k }
        if ((-not $rollEquip) -and ($it.Type -eq "Potion" -or $it.Type -eq "Scroll")) { $pool += , $k }
    }
    if ($pool.Count -gt 0) {
        $itemName = Get-Random -InputObject $pool
        Add-InventoryItem -PlayerRef $Global:Player -ItemName $itemName -Qty 1
        Add-Message "The chest also held: $itemName." "Cyan"
    }
}

function Invoke-TrapTrigger {
    param($Tile)
    $Tile.Revealed = $true
    $Tile.Detected = $true
    $Tile.Triggered = $true
    switch ($Tile.TrapType) {
        "Spike" {
            $dmg = Get-Random -Minimum 4 -Maximum 12
            $Global:Player.HP -= $dmg
            Add-Message "A spike trap jabs you for $dmg damage!" "Red"
            break
        }
        "Gas" {
            Add-StatusEffect -Actor $Global:Player -Type "Poison" -Duration 6 -Power 2
            Add-Message "A cloud of noxious gas hisses out. You're poisoned!" "Green"
            break
        }
        "Pitfall" {
            $dmg = Get-Random -Minimum 3 -Maximum 10
            $Global:Player.HP -= $dmg
            Add-Message "The floor gives way! You tumble through the dark and land elsewhere, taking $dmg damage." "Red"
            if ($Global:Rooms.Count -gt 0) {
                $ridx = Get-Random -Minimum 0 -Maximum $Global:Rooms.Count
                $pos = Get-RandomFloorTileInRoom -RoomIdx $ridx
                if ($pos) {
                    $Global:Player.X = $pos.X
                    $Global:Player.Y = $pos.Y
                    Update-Visibility -PX $pos.X -PY $pos.Y
                }
            }
            break
        }
        default { }
    }
    Invoke-PlayerDeathCheck
}

function Visit-Shrine {
    param($Tile)
    $Tile.Used = $true
    $roll = Get-Random -Minimum 0.0 -Maximum 1.0
    if ($roll -lt 0.5) {
        $outcomes = @("HP", "Atk", "Def", "Heal", "Gold")
        $pick = Get-Random -InputObject $outcomes
        switch ($pick) {
            "HP"   { $Global:Player.BaseMaxHP += 5; Update-DerivedStats -Actor $Global:Player; Add-Message "The shrine blesses you: +5 Max HP." "Green"; break }
            "Atk"  { $Global:Player.BaseAttack += 1; Update-DerivedStats -Actor $Global:Player; Add-Message "The shrine blesses you: +1 Attack." "Green"; break }
            "Def"  { $Global:Player.BaseDefense += 1; Update-DerivedStats -Actor $Global:Player; Add-Message "The shrine blesses you: +1 Defense." "Green"; break }
            "Heal" { $Global:Player.HP = $Global:Player.MaxHP; Add-Message "The shrine blesses you: fully healed." "Green"; break }
            "Gold" { $Global:Player.Gold += 20; $Global:Player.GoldCollected += 20; Add-Message "The shrine blesses you: +20 gold." "Green"; break }
            default { }
        }
    } elseif ($roll -lt 0.8) {
        Add-Message "The shrine remains silent." "DarkGray"
    } else {
        $outcomes = @("HP", "Gold", "Weaken")
        $pick = Get-Random -InputObject $outcomes
        switch ($pick) {
            "HP"     { $Global:Player.BaseMaxHP = [math]::Max(10, $Global:Player.BaseMaxHP - 3); Update-DerivedStats -Actor $Global:Player; Add-Message "The shrine curses you: -3 Max HP." "Red"; break }
            "Gold"   { $loss = [math]::Min($Global:Player.Gold, 50); $Global:Player.Gold -= $loss; Add-Message "The shrine curses you: -$loss gold." "Red"; break }
            "Weaken" { Add-StatusEffect -Actor $Global:Player -Type "StatMod" -Duration 12 -DefMod -2; Add-Message "The shrine curses you: defenses weakened." "Red"; break }
            default { }
        }
    }
}

function Invoke-PlayerTileEntry {
    $tile = $Global:Map["$($Global:Player.X),$($Global:Player.Y)"]
    if (-not $tile) { return }

    switch ($tile.Type) {
        "Gold" {
            $bonus = Get-TrinketGoldBonus
            $amt = [int]([math]::Round($tile.GoldAmt * (1 + $bonus)))
            $Global:Player.Gold += $amt
            $Global:Player.GoldCollected += $amt
            Add-Message "You find $amt gold." "Yellow"
            $tile.Type = "Floor"
            break
        }
        "Item" {
            $itemName = $tile.ItemName
            Add-InventoryItem -PlayerRef $Global:Player -ItemName $itemName -Qty 1
            Add-Message "You pick up: $itemName." "Cyan"
            $tile.Type = "Floor"
            break
        }
        "Chest" {
            if (-not $tile.Opened) {
                Open-Chest -Tile $tile
                $tile.Opened = $true
            }
            break
        }
        "Trap" {
            $isTriggered = ($tile.ContainsKey('Triggered') -and $tile.Triggered)
            if (-not $isTriggered) {
                Invoke-TrapTrigger -Tile $tile
            } else {
                Add-Message "You carefully step around the trap." "DarkGray"
            }
            break
        }
        "Shrine" {
            if (-not $tile.Used) {
                Visit-Shrine -Tile $tile
            } else {
                Add-Message "The shrine is quiet now." "DarkGray"
            }
            break
        }
        "Shop" {
            Show-ShopMenu
            break
        }
        default { }
    }
}

function Move-Player {
    param([int]$DX, [int]$DY)

    if (Test-Stunned -Actor $Global:Player) {
        Add-Message "You're stunned and stumble in place!" "Magenta"
        Invoke-EndOfTurn
        return
    }

    $nx = $Global:Player.X + $DX
    $ny = $Global:Player.Y + $DY

    $targetMonster = $null
    foreach ($m in $Global:Monsters) {
        if ($m.Alive -and $m.X -eq $nx -and $m.Y -eq $ny) { $targetMonster = $m; break }
    }

    if ($targetMonster) {
        Resolve-PlayerAttack -Monster $targetMonster
        Invoke-EndOfTurn
        return
    }

    if (-not (Test-Walkable -X $nx -Y $ny)) {
        return
    }

    $Global:Player.X = $nx
    $Global:Player.Y = $ny
    $Global:Player.LastMoveDX = $DX
    $Global:Player.LastMoveDY = $DY
    Invoke-PlayerTileEntry

    Update-Visibility -PX $Global:Player.X -PY $Global:Player.Y
    Invoke-EndOfTurn
}

function Invoke-StairsInteract {
    $tile = $Global:Map["$($Global:Player.X),$($Global:Player.Y)"]
    if ($tile.Type -ne "Stairs") {
        Add-Message "There's nothing to do here." "DarkGray"
        return
    }
    if ($Global:BossFloors -contains $Global:Player.Floor) {
        $bossAlive = $false
        foreach ($m in $Global:Monsters) {
            if ($m.IsBoss -and $m.Alive) { $bossAlive = $true; break }
        }
        if ($bossAlive) {
            Add-Message "The stairway is sealed while the guardian lives." "Red"
            return
        }
    }
    if ($Global:Player.Floor -ge $Global:MaxFloor) {
        Add-Message "This is as deep as the dungeon goes." "DarkGray"
        return
    }
    Export-Run | Out-Null
    Start-NewFloor -FloorNum ($Global:Player.Floor + 1)
}

function Invoke-TileInteract {
    $tile = $Global:Map["$($Global:Player.X),$($Global:Player.Y)"]
    switch ($tile.Type) {
        "Stairs" {
            Invoke-StairsInteract
            break
        }
        "Shop" {
            Show-ShopMenu
            break
        }
        "Shrine" {
            if (-not $tile.Used) {
                Visit-Shrine -Tile $tile
                Invoke-EndOfTurn
            } else {
                Add-Message "The shrine is quiet now." "DarkGray"
            }
            break
        }
        default {
            Add-Message "There is nothing to interact with right now." "DarkGray"
            break
        }
    }
}

function Wait-Turn {
    $tile = $Global:Map["$($Global:Player.X),$($Global:Player.Y)"]
    if ($tile.Type -eq "Stairs") {
        Invoke-StairsInteract
        return
    }

    if (Test-Stunned -Actor $Global:Player) {
        Add-Message "You're stunned and can't act." "Magenta"
    } else {
        Add-Message "You wait a moment." "DarkGray"
    }
    Invoke-EndOfTurn
}

function Use-Ability {
    if (Test-Stunned -Actor $Global:Player) {
        Add-Message "You're too stunned to focus." "Magenta"
        return
    }
    if ($Global:Player.AbilityCooldown -gt 0) {
        Add-Message "$($Global:Player.AbilityName) isn't ready yet ($($Global:Player.AbilityCooldown) turns)." "DarkGray"
        return
    }

    $used = $false
    switch ($Global:Player.Class) {
        "Warrior" {
            $hit = $false
            foreach ($dir in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))) {
                $nx = $Global:Player.X + $dir[0]
                $ny = $Global:Player.Y + $dir[1]
                foreach ($m in $Global:Monsters) {
                    if ($m.Alive -and $m.X -eq $nx -and $m.Y -eq $ny) {
                        $dmg = $Global:Player.Attack + 2
                        $m.HP -= $dmg
                        Add-Message "Cleave strikes the $($m.Name) for $dmg damage!" "Yellow"
                        $hit = $true
                        if ($m.HP -le 0) { Invoke-MonsterDeath -Monster $m }
                    }
                }
            }
            if ($hit) { $used = $true } else { Add-Message "Cleave hits nothing but air." "DarkGray" }
            break
        }
        "Rogue" {
            $dx = 0
            $dy = 0
            if ($Global:Player.ContainsKey('LastMoveDX')) { $dx = [int]$Global:Player.LastMoveDX }
            if ($Global:Player.ContainsKey('LastMoveDY')) { $dy = [int]$Global:Player.LastMoveDY }

            if ($dx -eq 0 -and $dy -eq 0) {
                Add-Message "Move first, then roll." "DarkGray"
                break
            }

            $landing = $null
            for ($range = 1; $range -le 3; $range++) {
                $nx = $Global:Player.X + ($dx * $range)
                $ny = $Global:Player.Y + ($dy * $range)
                if (-not (Test-Walkable -X $nx -Y $ny)) { break }
                if (-not (Test-TileOccupiedByMonster -X $nx -Y $ny)) {
                    $landing = @{ X = $nx; Y = $ny; Range = $range }
                }
            }

            if ($landing) {
                $Global:Player.X = $landing.X
                $Global:Player.Y = $landing.Y
                Invoke-PlayerTileEntry
                Update-Visibility -PX $Global:Player.X -PY $Global:Player.Y
                $used = $true
                if ($Global:Player.Alive -and (-not $Global:Player.Victorious)) {
                    $Global:Player.GuaranteedCrit = $true
                    Add-Message "You roll and poise your weapon." "Cyan"
                }
            } else {
                Add-Message "There is no room to roll." "DarkGray"
            }
            break
        }
        "Mage" {
            $target = $null
            $bestDist = 999
            foreach ($dir in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))) {
                for ($r = 1; $r -le 5; $r++) {
                    $nx = $Global:Player.X + $dir[0] * $r
                    $ny = $Global:Player.Y + $dir[1] * $r
                    if (-not (Test-Walkable -X $nx -Y $ny)) { break }
                    foreach ($m in $Global:Monsters) {
                        if ($m.Alive -and $m.X -eq $nx -and $m.Y -eq $ny) {
                            if ($r -lt $bestDist) { $target = $m; $bestDist = $r }
                        }
                    }
                }
            }
            if ($target) {
                $dmg = [int][math]::Round(($Global:Player.Attack * 1.5) + 3)
                $target.HP -= $dmg
                Add-Message "Arcane Bolt sears the $($target.Name) for $dmg damage!" "Yellow"
                if ($target.HP -le 0) { Invoke-MonsterDeath -Monster $target }
                $used = $true
            } else {
                Add-Message "No target in range for Arcane Bolt." "DarkGray"
            }
            break
        }
        default { }
    }

    if ($used) {
        $Global:Player.AbilityCooldown = $Global:Player.AbilityMaxCooldown
        Invoke-EndOfTurn
    }
}

function Use-Item {
    param([string]$ItemName)
    $item = $Global:ItemMaster[$ItemName]
    if (-not $item) { return $false }
    if ($item.Type -ne "Potion" -and $item.Type -ne "Scroll") { return $false }

    $consumed = $true
    switch ($item.Effect) {
        "Heal" {
            $before = $Global:Player.HP
            $Global:Player.HP = [math]::Min($Global:Player.MaxHP, $Global:Player.HP + $item.EffectValue)
            $healed = $Global:Player.HP - $before
            Add-Message "You drink the $ItemName and recover $healed HP." "Green"
            break
        }
        "CurePoison" {
            $Global:Player.StatusEffects = @($Global:Player.StatusEffects | Where-Object { $_.Type -ne 'Poison' })
            Add-Message "You drink the $ItemName and feel better." "Green"
            break
        }
        "BuffAtk" {
            $Global:Player.BaseAttack += $item.EffectValue
            Update-DerivedStats -Actor $Global:Player
            Add-Message "You drink the $ItemName. Your muscles harden. +$($item.EffectValue) Attack." "Red"
            break
        }
        "BuffDef" {
            $Global:Player.BaseDefense += $item.EffectValue
            Update-DerivedStats -Actor $Global:Player
            Add-Message "You drink the $ItemName. Your hide thickens. +$($item.EffectValue) Defense." "Cyan"
            break
        }
        "BuffMaxHP" {
            $Global:Player.BaseMaxHP += $item.EffectValue
            Update-DerivedStats -Actor $Global:Player
            $Global:Player.HP = $Global:Player.MaxHP
            Add-Message "You drink the $ItemName. Your willpower's bolstered. +$($item.EffectValue) Max HP." "Yellow"
            break
        }
        "Teleport" {
            $pos = $null
            if ($Global:Rooms.Count -gt 0) {
                $ridx = Get-Random -Minimum 0 -Maximum $Global:Rooms.Count
                $pos = Get-RandomFloorTileInRoom -RoomIdx $ridx
            }
            if ($pos) {
                $Global:Player.X = $pos.X
                $Global:Player.Y = $pos.Y
                Update-Visibility -PX $pos.X -PY $pos.Y
                Add-Message "You read the $ItemName and vanish, reappearing elsewhere." "Cyan"
            } else {
                Add-Message "The scroll fizzles. Nothing happens." "DarkGray"
            }
            break
        }
        "Fireball" {
            $dmg = ($Global:Player.Attack * 2) + 5
            $hitAny = $false
            foreach ($m in $Global:Monsters) {
                if (-not $m.Alive) { continue }
                $ddx = [math]::Abs($m.X - $Global:Player.X)
                $ddy = [math]::Abs($m.Y - $Global:Player.Y)
                if ($ddx -le 2 -and $ddy -le 2) {
                    $m.HP -= $dmg
                    $hitAny = $true
                    if ($m.HP -le 0) { Invoke-MonsterDeath -Monster $m }
                }
            }
            if ($hitAny) {
                Add-Message "You read the $ItemName. Fire roars outward for $dmg damage!" "Red"
            } else {
                Add-Message "You read the $ItemName, but no one is close enough to burn." "DarkGray"
            }
            break
        }
        "Warding" {
            Add-StatusEffect -Actor $Global:Player -Type "StatMod" -Duration 10 -DefMod $item.EffectValue
            Add-Message "You read the $ItemName. A shimmer surrounds you. +$($item.EffectValue) Defense, 10 turns." "Yellow"
            break
        }
        "Revelation" {
            foreach ($k in @($Global:Map.Keys)) { $Global:Map[$k].Discovered = $true }
            Add-Message "You read the $ItemName. The floor's layout floods into your mind." "White"
            break
        }
        default {
            $consumed = $false
        }
    }

    if ($consumed) {
        Remove-InventoryItem -PlayerRef $Global:Player -ItemName $ItemName -Qty 1
    }
    return $consumed
}


# ============================================================================
#  RENDERING
# ============================================================================

function Read-MenuLine {
    return (Read-Host)
}

function Write-ColorRuns {
    param([array]$Cells)
    if ($Cells.Count -eq 0) { Write-Host ""; return }
    $curColor = $Cells[0].Color
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($Cells[0].Char)
    for ($i = 1; $i -lt $Cells.Count; $i++) {
        if ($Cells[$i].Color -eq $curColor) {
            [void]$sb.Append($Cells[$i].Char)
        } else {
            Write-Host $sb.ToString() -NoNewline -ForegroundColor $curColor
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append($Cells[$i].Char)
            $curColor = $Cells[$i].Color
        }
    }
    Write-Host $sb.ToString() -ForegroundColor $curColor
}

function Get-TileRenderCell {
    param([int]$X, [int]$Y)
    if ($X -eq $Global:Player.X -and $Y -eq $Global:Player.Y) {
        return @{ Char = "@"; Color = "White" }
    }
    $tile = $Global:Map["$X,$Y"]
    foreach ($m in $Global:Monsters) {
        if ($m.Alive -and $m.X -eq $X -and $m.Y -eq $Y -and $tile.Discovered) {
            return @{ Char = $m.Symbol; Color = $m.Color }
        }
    }
    if (-not $tile.Discovered) {
        return @{ Char = " "; Color = "Black" }
    }
    switch ($tile.Type) {
        "Wall"   { return @{ Char = "#"; Color = "DarkGray" } }
        "Floor"  { return @{ Char = "."; Color = "DarkGray" } }
        "Stairs" { return @{ Char = ">"; Color = "White" } }
        "Shop"   { return @{ Char = "M"; Color = "Yellow" } }
        "Shrine" { return @{ Char = "&"; Color = "Magenta" } }
        "Chest"  {
            if ($tile.Opened) { return @{ Char = "*"; Color = "DarkGray" } }
            return @{ Char = "*"; Color = "Yellow" }
        }
        "Gold"   { return @{ Char = '$'; Color = "Yellow" } }
        "Item"   {
            $it = $Global:ItemMaster[$tile.ItemName]
            if ($it) { return @{ Char = $it.Symbol; Color = $it.Color } }
            return @{ Char = "?"; Color = "White" }
        }
        "Trap"   {
            if ($tile.ContainsKey('Triggered') -and $tile.Triggered) {
                switch ($tile.TrapType) {
                    "Spike"   { return @{ Char = "^"; Color = "Red" } }
                    "Gas"     { return @{ Char = "^"; Color = "Green" } }
                    "Pitfall" { return @{ Char = "^"; Color = "Gray" } }
                    default   { return @{ Char = "^"; Color = "Red" } }
                }
            }
            if (($tile.ContainsKey('Detected') -and $tile.Detected) -or ($tile.ContainsKey('Revealed') -and $tile.Revealed)) {
                return @{ Char = "^"; Color = "DarkGray" }
            }
            return @{ Char = "."; Color = "DarkGray" }
        }
        default  { return @{ Char = "."; Color = "DarkGray" } }
    }
}

function Show-Header {
    $p = $Global:Player
    Write-Host ("=" * 100) -ForegroundColor DarkGray
    Write-Host "DELVE" -NoNewline -ForegroundColor White
    Write-Host "  " -NoNewline
    Write-Host "$($p.Name)" -NoNewline -ForegroundColor Cyan
    Write-Host " the $($p.Class)" -NoNewline -ForegroundColor Cyan
    Write-Host "   Lv $($p.Level)" -NoNewline -ForegroundColor Yellow
    Write-Host "   Floor $($p.Floor)/$($Global:MaxFloor)" -NoNewline -ForegroundColor White
    Write-Host "   Turn $($p.Turn)" -ForegroundColor DarkGray

    Write-Host "HP " -NoNewline -ForegroundColor Gray
    Write-Bar -Current $p.HP -Max $p.MaxHP -Width 20 -FullColor (Get-HPColor -Current $p.HP -Max $p.MaxHP)
    Write-Host (" {0}/{1}" -f [int]$p.HP, [int]$p.MaxHP) -NoNewline -ForegroundColor White
    Write-Host "   ATK $($p.Attack)" -NoNewline -ForegroundColor Red
    Write-Host "   DEF $($p.Defense)" -NoNewline -ForegroundColor Cyan
    Write-Host "   CRIT $([int]($p.Crit * 100))%" -NoNewline -ForegroundColor Yellow
    Write-Host "   DODGE $([int]($p.Dodge * 100))%" -ForegroundColor Green

    Write-Host "XP " -NoNewline -ForegroundColor Gray
    Write-Bar -Current $p.XP -Max $p.XPToNext -Width 20 -FullColor "Magenta"
    Write-Host (" {0}/{1}" -f $p.XP, $p.XPToNext) -NoNewline -ForegroundColor White
    Write-Host "   Gold $($p.Gold)" -NoNewline -ForegroundColor Yellow
    $abilStatus = "Ready"
    if ($p.AbilityCooldown -gt 0) { $abilStatus = "$($p.AbilityCooldown)t" }
    Write-Host "   $($p.AbilityName): $abilStatus" -ForegroundColor DarkCyan

    $statusText = @()
    foreach ($eff in $p.StatusEffects) {
        $lbl = Get-StatusEffectLabel -Eff $eff
        $statusText += "$lbl($($eff.Duration))"
    }
    if ($statusText.Count -gt 0) {
        Write-Host ("Status: " + ($statusText -join ", ")) -ForegroundColor Magenta
    } else {
        Write-Host ""
    }
    Write-Host ("=" * 100) -ForegroundColor DarkGray
}

function Show-MapView {
    for ($y = 0; $y -lt $Global:MapHeight; $y++) {
        $cells = @()
        for ($x = 0; $x -lt $Global:MapWidth; $x++) {
            $cells += (Get-TileRenderCell -X $x -Y $y)
        }
        Write-ColorRuns -Cells $cells
    }
}

function Show-MessageLog {
    Write-Host ("-" * 100) -ForegroundColor DarkGray
    $logCount = $Global:MessageLog.Count
    $showCount = [math]::Min(5, $logCount)
    if ($showCount -eq 0) {
        for ($i = 0; $i -lt 5; $i++) { Write-Host "" }
    } else {
        $startIdx = $logCount - $showCount
        for ($i = $startIdx; $i -lt $logCount; $i++) {
            $msg = $Global:MessageLog[$i]
            Write-Host $msg.Text -ForegroundColor $msg.Color
        }
        for ($i = $showCount; $i -lt 5; $i++) { Write-Host "" }
    }
}

function Show-Hints {
    Write-Host ("-" * 100) -ForegroundColor DarkGray
    Write-Host "[Arrows/WASD] Move/Attack  [Enter] Interact  [Space] Wait/Stairs  [Q] Ability  [I] Inventory  [C] Character  [Esc] Menu" -ForegroundColor DarkGray
}

function Render-Screen {
    Clear-Host
    Show-Header
    Show-MapView
    Show-MessageLog
    Show-Hints
}

# ============================================================================
#  MENUS: INVENTORY / CHARACTER
# ============================================================================

function Read-InventoryUseCount {
    param([string]$ItemName, [int]$MaxQty)
    if ($MaxQty -le 1) { return 1 }

    while ($true) {
        Write-Host "How many $ItemName to use? " -NoNewline -ForegroundColor DarkGray
        Write-Host "(1-$MaxQty, blank cancels): " -NoNewline -ForegroundColor Yellow
        $line = Read-MenuLine
        if ($line.Trim() -eq "") { return 0 }

        $count = 0
        if ([int]::TryParse($line, [ref]$count) -and $count -ge 1 -and $count -le $MaxQty) {
            return $count
        }
    }
}

function Read-InventoryActionConfirm {
    param([string]$Action, [string]$TargetText)

    Write-Host "Press " -NoNewline -ForegroundColor DarkGray
    Write-Host "Enter" -NoNewline -ForegroundColor DarkYellow
    Write-Host " to $Action $TargetText, " -NoNewline -ForegroundColor DarkGray
    Write-Host "any other key" -NoNewline -ForegroundColor Yellow
    Write-Host " to cancel..." -ForegroundColor DarkGray

    $k = [System.Console]::ReadKey($true)
    return ($k.Key -eq "Enter")
}

function Invoke-InventoryItemSelection {
    param([string]$ItemName, [int]$Qty)

    $item = $Global:ItemMaster[$ItemName]
    if (-not $item) { return }

    if ($item.Type -eq "Weapon" -or $item.Type -eq "Armor" -or $item.Type -eq "Trinket") {
        if (Read-InventoryActionConfirm -Action "equip" -TargetText $ItemName) {
            Set-EquipItem -PlayerRef $Global:Player -ItemName $ItemName
        }
        return
    }

    if ($item.Type -eq "Potion" -or $item.Type -eq "Scroll") {
        $useCount = Read-InventoryUseCount -ItemName $ItemName -MaxQty $Qty
        if ($useCount -le 0) { return }

        $targetText = $ItemName
        if ($useCount -gt 1) { $targetText = "$useCount x $ItemName" }

        if (-not (Read-InventoryActionConfirm -Action "use" -TargetText $targetText)) { return }

        for ($i = 0; $i -lt $useCount; $i++) {
            if ((Get-ItemCount -PlayerRef $Global:Player -ItemName $ItemName) -le 0) { break }
            $ok = Use-Item -ItemName $ItemName
            if ($ok) {
                if ($Global:Player.Victorious) { break }
                Invoke-EndOfTurn
                if ((-not $Global:Player.Alive) -or $Global:Player.Victorious) { break }
            }
        }
        return
    }

    Write-Host "There is nothing to do with $ItemName here." -ForegroundColor DarkGray
    [void][System.Console]::ReadKey($true)
}

function Show-InventoryMenu {
    $done = $false
    while (-not $done) {
        Clear-Host
        Write-Host ("=" * 100) -ForegroundColor DarkGray
        Write-Host "INVENTORY" -ForegroundColor White
        Write-Host ("=" * 100) -ForegroundColor DarkGray

        Write-Host ""
        Write-Host "Equipped:" -ForegroundColor Gray
        foreach ($slot in @('Weapon', 'Armor', 'Trinket')) {
            $itemName = $Global:Player.Equipment[$slot]
            if ($itemName) {
                $it = $Global:ItemMaster[$itemName]
                Write-Host ("  {0,-8}: " -f $slot) -NoNewline -ForegroundColor Gray
                Write-Host $itemName -ForegroundColor (Get-RarityColor -Rarity $it.Rarity)
            } else {
                Write-Host ("  {0,-8}: (none)" -f $slot) -ForegroundColor DarkGray
            }
        }

        Write-Host ""
        Write-Host "Carried:" -ForegroundColor Gray
        $listing = @()
        foreach ($k in @($Global:ItemMaster.Keys)) {
            $qty = Get-ItemCount -PlayerRef $Global:Player -ItemName $k
            if ($qty -gt 0) { $listing += , @{ Name = $k; Qty = $qty } }
        }

        if ($listing.Count -eq 0) {
            Write-Host "  (nothing)" -ForegroundColor DarkGray
        } else {
            for ($i = 0; $i -lt $listing.Count; $i++) {
                $it = $Global:ItemMaster[$listing[$i].Name]
                $num = $i + 1
                Write-Host ("  [{0,2}] " -f $num) -NoNewline -ForegroundColor White
                Write-Host ("{0,-22}" -f $listing[$i].Name) -NoNewline -ForegroundColor (Get-RarityColor -Rarity $it.Rarity)
                Write-Host (" x{0,-3}" -f $listing[$i].Qty) -NoNewline -ForegroundColor Gray
                Write-Host " $($it.Description)" -ForegroundColor DarkGray
            }
        }

        Write-Host ""
        Write-Host ("-" * 100) -ForegroundColor DarkGray
        Write-Host "Enter a number to select an item. [W/A/T] Unequip slot. [E] Back" -ForegroundColor DarkGray
        Write-Host "> " -NoNewline -ForegroundColor Yellow

        $line = Read-MenuLine
        $upper = $line.ToUpper()
        if ($upper -eq "" -or $upper -eq "E") { $done = $true; continue }
        if ($upper -eq "W") { Set-UnequipItem -PlayerRef $Global:Player -Slot "Weapon"; continue }
        if ($upper -eq "A") { Set-UnequipItem -PlayerRef $Global:Player -Slot "Armor"; continue }
        if ($upper -eq "T") { Set-UnequipItem -PlayerRef $Global:Player -Slot "Trinket"; continue }

        $idx = 0
        if ([int]::TryParse($line, [ref]$idx)) {
            $idx = $idx - 1
            if ($idx -ge 0 -and $idx -lt $listing.Count) {
                Invoke-InventoryItemSelection -ItemName $listing[$idx].Name -Qty $listing[$idx].Qty
                if ((-not $Global:Player.Alive) -or $Global:Player.Victorious) { return }
            }
        }
    }
}

function Show-CharacterSheet {
    Clear-Host
    $p = $Global:Player
    Write-Host ("=" * 100) -ForegroundColor DarkGray
    Write-Host "CHARACTER SHEET" -ForegroundColor White
    Write-Host ("=" * 100) -ForegroundColor DarkGray
    Write-Host "Name:    $($p.Name)" -ForegroundColor Gray
    Write-Host "Class:   $($p.Class)" -ForegroundColor Gray
    Write-Host "Level:   $($p.Level)  (XP $($p.XP)/$($p.XPToNext))" -ForegroundColor Gray
    Write-Host ""
    Write-Host "HP:      $([int]$p.HP)/$([int]$p.MaxHP)" -ForegroundColor Gray
    Write-Host "Attack:  $($p.Attack)" -ForegroundColor Gray
    Write-Host "Defense: $($p.Defense)" -ForegroundColor Gray
    Write-Host "Crit:    $([int]($p.Crit * 100))%" -ForegroundColor Gray
    Write-Host "Dodge:   $([int]($p.Dodge * 100))%" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Gold:    $($p.Gold)" -ForegroundColor Yellow
    Write-Host "Floor:   $($p.Floor) / $($Global:MaxFloor)  (deepest: $($p.DeepestFloor))" -ForegroundColor Gray
    Write-Host "Turn:    $($p.Turn)" -ForegroundColor Gray
    Write-Host "Kills:   $($p.KillCount)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Ability: $($p.AbilityName)" -ForegroundColor Cyan
    $classDesc = $Global:ClassMaster[$p.Class].AbilityDesc
    Write-Host "  $classDesc" -ForegroundColor DarkGray
    Wait-AnyKey
}

# ============================================================================
#  MENUS: SHOP / PAUSE / HELP
# ============================================================================

function Show-ShopMenu {
    $tile = $Global:Map["$($Global:Player.X),$($Global:Player.Y)"]
    if (-not $tile.ContainsKey('Stock')) {
        $pool = @()
        foreach ($k in @($Global:ItemMaster.Keys)) {
            $it = $Global:ItemMaster[$k]
            if ($it.Type -ne "Special") { $pool += , $k }
        }
        $stock = @()
        $stockCount = Get-Random -Minimum 6 -Maximum 10
        for ($i = 0; $i -lt $stockCount; $i++) {
            $stock += , (Get-Random -InputObject $pool)
        }
        $tile.Stock = $stock
    }

    $done = $false
    while (-not $done) {
        Clear-Host
        Write-Host ("=" * 100) -ForegroundColor DarkGray
        Write-Host "MERCHANT" -ForegroundColor White
        Write-Host "Your gold: $($Global:Player.Gold)" -ForegroundColor Yellow
        Write-Host ("=" * 100) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "For sale:" -ForegroundColor Gray

        $counts = @{}
        foreach ($s in $tile.Stock) {
            if (-not $counts.ContainsKey($s)) { $counts[$s] = 0 }
            $counts[$s] += 1
        }
        $stockList = @($counts.Keys)
        for ($i = 0; $i -lt $stockList.Count; $i++) {
            $name = $stockList[$i]
            $it = $Global:ItemMaster[$name]
            $num = $i + 1
            Write-Host ("  [{0,2}] " -f $num) -NoNewline -ForegroundColor White
            Write-Host ("{0,-22}" -f $name) -NoNewline -ForegroundColor (Get-RarityColor -Rarity $it.Rarity)
            Write-Host (" {0}g" -f $it.Value) -NoNewline -ForegroundColor Yellow
            Write-Host ("  (x{0} in stock)" -f $counts[$name]) -ForegroundColor DarkGray
        }
        if ($stockList.Count -eq 0) {
            Write-Host "  (sold out)" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "Your items (sell):" -ForegroundColor Gray
        $sellList = @()
        foreach ($k in @($Global:ItemMaster.Keys)) {
            $qty = Get-ItemCount -PlayerRef $Global:Player -ItemName $k
            if ($qty -gt 0 -and $Global:ItemMaster[$k].Value -gt 0) { $sellList += , @{ Name = $k; Qty = $qty } }
        }
        for ($i = 0; $i -lt $sellList.Count; $i++) {
            $name = $sellList[$i].Name
            $it = $Global:ItemMaster[$name]
            $sellPrice = [int][math]::Floor($it.Value * 0.5)
            $letter = [char](65 + $i)
            Write-Host ("  [{0}] " -f $letter) -NoNewline -ForegroundColor White
            Write-Host ("{0,-22}" -f $name) -NoNewline -ForegroundColor (Get-RarityColor -Rarity $it.Rarity)
            Write-Host (" {0}g each" -f $sellPrice) -NoNewline -ForegroundColor Yellow
            Write-Host ("  (you have x{0})" -f $sellList[$i].Qty) -ForegroundColor DarkGray
        }
        if ($sellList.Count -eq 0) {
            Write-Host "  (nothing to sell)" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("-" * 100) -ForegroundColor DarkGray
        Write-Host "Enter a number to buy, a letter to sell, or [E] to leave." -ForegroundColor DarkGray
        Write-Host "> " -NoNewline -ForegroundColor Yellow
        $line = Read-MenuLine
        $upper = $line.ToUpper()
        if ($upper -eq "" -or $upper -eq "E") { $done = $true; continue }

        $idx = 0
        if ([int]::TryParse($line, [ref]$idx)) {
            $bIdx = $idx - 1
            if ($bIdx -ge 0 -and $bIdx -lt $stockList.Count) {
                $name = $stockList[$bIdx]
                $it = $Global:ItemMaster[$name]
                if ($Global:Player.Gold -ge $it.Value) {
                    $Global:Player.Gold -= $it.Value
                    Add-InventoryItem -PlayerRef $Global:Player -ItemName $name -Qty 1
                    $stockArr = New-Object System.Collections.ArrayList
                    foreach ($s in $tile.Stock) { [void]$stockArr.Add($s) }
                    $removeIdx = $stockArr.IndexOf($name)
                    if ($removeIdx -ge 0) { $stockArr.RemoveAt($removeIdx) }
                    $tile.Stock = @($stockArr)
                    Write-Host "Purchased $name." -ForegroundColor Green
                } else {
                    Write-Host "Not enough gold." -ForegroundColor Red
                }
                Wait-AnyKey
            }
        } elseif ($line.Length -eq 1 -and [char]::IsLetter($line[0])) {
            $sIdx = [int]([char]::ToUpper($line[0])) - 65
            if ($sIdx -ge 0 -and $sIdx -lt $sellList.Count) {
                $name = $sellList[$sIdx].Name
                $it = $Global:ItemMaster[$name]
                $sellPrice = [int][math]::Floor($it.Value * 0.5)
                Remove-InventoryItem -PlayerRef $Global:Player -ItemName $name -Qty 1
                $Global:Player.Gold += $sellPrice
                Write-Host "Sold $name for $sellPrice gold." -ForegroundColor Green
                Wait-AnyKey
            }
        }
    }
}

function Show-HelpScreen {
    Clear-Host
    Write-Host ("=" * 100) -ForegroundColor DarkGray
    Write-Host "HOW TO PLAY" -ForegroundColor White
    Write-Host ("=" * 100) -ForegroundColor DarkGray
    $lines = @(
        "Move with the Arrow keys or WASD. Walking into a monster attacks it.",
        "Walking onto gold, items, and chests picks them up or opens them automatically.",
        "Shrines offer a risky blessing once per visit; shops let you buy and sell.",
        "",
        "[Enter]  Interact with stairs, merchants, and shrines",
        "[Space]  Wait one turn in place, or use stairs while standing on them",
        "[I]      Open your inventory (use potions/scrolls, equip gear)",
        "[Q]      Use your class ability",
        "[C]      View your character sheet",
        "[Esc]    Pause menu (save and quit, or abandon the run)",
        "",
        "Legend:",
        "  @ you        # wall         . floor        > stairs down",
        "  `$ gold       * chest        & shrine        M merchant",
        "  / weapon     [ armor        ! potion        ? scroll",
        "  ^ trap (once revealed)",
        "",
        "Death is permanent. Every run, win or lose, earns Echoes based on how",
        "deep you got, how much gold you found, and how many foes you slew.",
        "Spend Echoes at the Sanctuary between runs to unlock classes and perks."
    )
    foreach ($l in $lines) { Write-Host $l -ForegroundColor Gray }
    Wait-AnyKey
}

function Show-PauseMenu {
    $result = "Resume"
    $done = $false
    while (-not $done) {
        Clear-Host
        Write-Host ("=" * 100) -ForegroundColor DarkGray
        Write-Host "PAUSED" -ForegroundColor White
        Write-Host ("=" * 100) -ForegroundColor DarkGray
        Write-Host "[1] Resume" -ForegroundColor Yellow
        Write-Host "[2] Help" -ForegroundColor Yellow
        Write-Host "[3] Save and Quit to Main Menu" -ForegroundColor Yellow
        Write-Host "[4] Abandon Run (bank Echoes, remove save)" -ForegroundColor Red
        Write-Host "> " -NoNewline -ForegroundColor Yellow
        $line = Read-MenuLine
        switch ($line) {
            "1" { $done = $true; break }
            "2" { Show-HelpScreen; break }
            "3" {
                Export-Run | Out-Null
                $result = "QuitToMenu"
                $done = $true
                break
            }
            "4" {
                if (Read-YesNo "Abandon this run, bank earned Echoes, and remove the save") {
                    $result = "Abandoned"
                    $done = $true
                }
                break
            }
            default { }
        }
    }
    return $result
}


# ============================================================================
#  DEATH / VICTORY
# ============================================================================

function Get-EchoesEarned {
    param([bool]$Victory)
    $p = $Global:Player
    $echoes = ($p.DeepestFloor * 8) + $p.KillCount + [int]([math]::Floor($p.GoldCollected / 10))
    if ($Victory) { $echoes += 200 }
    return [int]$echoes
}

function Add-RunRewards {
    param([string]$Outcome)

    $victory = ($Outcome -eq "Victory")
    $echoes = Get-EchoesEarned -Victory $victory
    $Global:Meta.Echoes += $echoes
    $Global:Meta.TotalEchoesEarned += $echoes
    $Global:Meta.Stats.TotalRuns += 1
    switch ($Outcome) {
        "Death" { $Global:Meta.Stats.TotalDeaths += 1; break }
        "Victory" { $Global:Meta.Stats.TotalVictories += 1; break }
        "Abandoned" {
            if (-not $Global:Meta.Stats.ContainsKey('TotalAbandons')) { $Global:Meta.Stats.TotalAbandons = 0 }
            $Global:Meta.Stats.TotalAbandons += 1
            break
        }
        default { }
    }
    if ($Global:Player.DeepestFloor -gt $Global:Meta.Stats.BestFloor) {
        $Global:Meta.Stats.BestFloor = $Global:Player.DeepestFloor
    }
    $Global:Meta.Stats.TotalKills += $Global:Player.KillCount
    $Global:Meta.Stats.TotalGoldEver += $Global:Player.GoldCollected
    Export-Meta
    Remove-RunSave
    return $echoes
}

function Show-DeathScreen {
    $echoes = Add-RunRewards -Outcome "Death"

    Clear-Host
    Write-Host ("=" * 100) -ForegroundColor DarkRed
    Write-Host "YOU HAVE FALLEN" -ForegroundColor Red
    Write-Host ("=" * 100) -ForegroundColor DarkRed
    Write-Host ""
    Write-Host "$($Global:Player.Name) the $($Global:Player.Class), Level $($Global:Player.Level)" -ForegroundColor Gray
    Write-Host "Reached floor $($Global:Player.DeepestFloor) of $($Global:MaxFloor)" -ForegroundColor Gray
    Write-Host "Turns survived: $($Global:Player.Turn)" -ForegroundColor Gray
    Write-Host "Monsters slain: $($Global:Player.KillCount)" -ForegroundColor Gray
    Write-Host "Gold collected: $($Global:Player.GoldCollected)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Echoes earned: $echoes" -ForegroundColor Yellow
    Write-Host "Total Echoes available: $($Global:Meta.Echoes)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host ("-" * 100) -ForegroundColor DarkGray
    if ($Global:MessageLog.Count -gt 0) {
        Write-Host "Final moments:" -ForegroundColor DarkGray
        $logCount = $Global:MessageLog.Count
        $showCount = [math]::Min(4, $logCount)
        $startIdx = $logCount - $showCount
        for ($i = $startIdx; $i -lt $logCount; $i++) {
            $msg = $Global:MessageLog[$i]
            Write-Host "  $($msg.Text)" -ForegroundColor $msg.Color
        }
    }
    Wait-AnyKey "Press any key to return to the Sanctuary..."
}

function Show-AbandonScreen {
    $echoes = Add-RunRewards -Outcome "Abandoned"

    Clear-Host
    Write-Host ("=" * 100) -ForegroundColor DarkYellow
    Write-Host "RUN ABANDONED" -ForegroundColor Yellow
    Write-Host ("=" * 100) -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "$($Global:Player.Name) the $($Global:Player.Class), Level $($Global:Player.Level)" -ForegroundColor Gray
    Write-Host "Reached floor $($Global:Player.DeepestFloor) of $($Global:MaxFloor)" -ForegroundColor Gray
    Write-Host "Turns survived: $($Global:Player.Turn)" -ForegroundColor Gray
    Write-Host "Monsters slain: $($Global:Player.KillCount)" -ForegroundColor Gray
    Write-Host "Gold collected: $($Global:Player.GoldCollected)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Echoes banked: $echoes" -ForegroundColor Yellow
    Write-Host "Total Echoes available: $($Global:Meta.Echoes)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "The Delve keeps its secrets. Your earned Echoes remain." -ForegroundColor DarkGray
    Wait-AnyKey "Press any key to return to the Sanctuary..."
}

function Show-VictoryScreen {
    $echoes = Add-RunRewards -Outcome "Victory"

    Clear-Host
    Write-Host ("=" * 100) -ForegroundColor Yellow
    Write-Host "VICTORY" -ForegroundColor Yellow
    Write-Host ("=" * 100) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "$($Global:Player.Name) the $($Global:Player.Class) has slain Malphestus and cleared the Delve." -ForegroundColor White
    Write-Host "Level $($Global:Player.Level), $($Global:Player.Turn) turns, $($Global:Player.KillCount) kills, $($Global:Player.GoldCollected) gold gathered." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Echoes earned: $echoes" -ForegroundColor Yellow
    Write-Host "Total Echoes available: $($Global:Meta.Echoes)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Nothing stops you from descending again -- a new Delve always waits." -ForegroundColor DarkGray
    Wait-AnyKey "Press any key to return to the Sanctuary..."
    $Global:Player.Victorious = $true
}

# ============================================================================
#  TITLE / MAIN MENU / SANCTUARY / RECORDS
# ============================================================================

function Get-TitleArtLines {
    $letterD = @("##### ", "#    #", "#    #", "#    #", "#    #", "##### ")
    $letterE = @("######", "#     ", "##### ", "#     ", "#     ", "######")
    $letterL = @("#     ", "#     ", "#     ", "#     ", "#     ", "######")
    $letterV = @("#    #", "#    #", "#    #", "#    #", " #  # ", "  ##  ")
    $letters = @($letterD, $letterE, $letterL, $letterV, $letterE)
    $lines = @()
    for ($row = 0; $row -lt 6; $row++) {
        $parts = @()
        foreach ($ltr in $letters) { $parts += $ltr[$row] }
        $lines += ($parts -join " ")
    }
    return $lines
}

function Show-TitleScreen {
    Clear-Host
    $lines = Get-TitleArtLines
    Write-Host ""
    foreach ($l in $lines) {
        Write-Host ("     " + $l) -ForegroundColor DarkGray
    }
    Write-Host "                                 v" -ForegroundColor DarkGray -NoNewLine
    Write-Host "$($Global:GameVersion)" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "A Roguelike Dungeon Crawl for Windows Terminal" -ForegroundColor Gray
    Write-Host ""
    Wait-AnyKey "Press any key to begin..."
}

function Show-ClassSelect {
    $classNames = @($Global:ClassMaster.Keys)
    while ($true) {
        Clear-Host
        Write-Host ("=" * 70) -ForegroundColor DarkGray
        Write-Host "  CHOOSE YOUR CLASS" -ForegroundColor White
        Write-Host ("=" * 70) -ForegroundColor DarkGray
        for ($i = 0; $i -lt $classNames.Count; $i++) {
            $cName = $classNames[$i]
            $cDef = $Global:ClassMaster[$cName]
            $unlocked = Test-ClassUnlocked -ClassName $cName
            $num = $i + 1
            if ($unlocked) {
                Write-Host "  [$num] $cName" -ForegroundColor Yellow
                Write-Host "      $($cDef.Blurb)" -ForegroundColor Gray
                Write-Host "      HP $($cDef.BaseMaxHP)  ATK $($cDef.BaseAttack)  DEF $($cDef.BaseDefense)  Ability: $($cDef.AbilityName)" -ForegroundColor DarkGray
            } else {
                $cost = Get-ClassUnlockCost -ClassName $cName
                Write-Host "  [$num] $cName -- LOCKED (unlock at the Sanctuary, costs $cost Echoes)" -ForegroundColor DarkGray
            }
            Write-Host ""
        }
        Write-Host "  [E] Back" -ForegroundColor DarkGray
        Write-Host "> " -NoNewline -ForegroundColor Yellow
        $line = Read-MenuLine
        if ($line.ToUpper() -eq "E" -or $line -eq "") { return $null }
        $idx = 0
        if ([int]::TryParse($line, [ref]$idx)) {
            $idx = $idx - 1
            if ($idx -ge 0 -and $idx -lt $classNames.Count) {
                $cName = $classNames[$idx]
                if (Test-ClassUnlocked -ClassName $cName) { return $cName }
            }
        }
    }
}

function Start-NewRun {
    if (Test-RunSaveExists) {
        Clear-Host
        Write-Host ("=" * 70) -ForegroundColor DarkGray
        Write-Host "  EXISTING SAVE FOUND" -ForegroundColor Yellow
        Write-Host ("=" * 70) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Starting a new run will remove the saved run." -ForegroundColor Gray
        Write-Host ""
        if (-not (Read-YesNo "Start a new run and delete the saved run")) { return }
    }

    $className = Show-ClassSelect
    if (-not $className) { return }

    Clear-Host
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host "  NAME YOUR AVATAR" -ForegroundColor White
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host "Enter a name (leave blank for '$($Global:Meta.PilotName)'): " -NoNewline -ForegroundColor Yellow
    $name = Read-MenuLine
    if ($name.Trim() -eq "") {
        $name = $Global:Meta.PilotName
    } else {
        $Global:Meta.PilotName = $name.Trim()
        Export-Meta
    }

    $Global:MessageLog = @()
    $Global:Player = New-Player -Name $name -Class $className
    Remove-RunSave
    Start-NewFloor -FloorNum 1
    Add-Message "Welcome to the Delve, $name." "White"
    Start-GameLoop
}

function Resume-Run {
    $loaded = Import-Run
    if (-not $loaded) {
        Write-Host "No valid save found." -ForegroundColor Red
        Wait-AnyKey
        return
    }
    $Global:Player = $loaded
    $Global:MessageLog = @()
    Start-NewFloor -FloorNum $Global:Player.Floor
    Add-Message "You return to the Delve, floor $($Global:Player.Floor)." "White"
    Start-GameLoop
}

function Show-Sanctuary {
    $done = $false
    while (-not $done) {
        Clear-Host
        Write-Host ("=" * 70) -ForegroundColor DarkGray
        Write-Host "  THE SANCTUARY" -ForegroundColor White
        Write-Host "  Echoes available: $($Global:Meta.Echoes)" -ForegroundColor Yellow
        Write-Host ("=" * 70) -ForegroundColor DarkGray
        Write-Host ""
        $keys = @($Global:PerkMaster.Keys)
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $pk = $keys[$i]
            $pd = $Global:PerkMaster[$pk]
            $num = $i + 1
            if ($Global:Meta.Unlocked[$pk]) {
                Write-Host ("  [{0,2}] {1,-28} OWNED" -f $num, $pd.Name) -ForegroundColor DarkGray
            } else {
                Write-Host ("  [{0,2}] {1,-28} {2,4} Echoes" -f $num, $pd.Name, $pd.Cost) -ForegroundColor Yellow
            }
            Write-Host "       $($pd.Desc)" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "  [E] Back" -ForegroundColor DarkGray
        Write-Host "> " -NoNewline -ForegroundColor Yellow
        $line = Read-MenuLine
        if ($line.ToUpper() -eq "E" -or $line -eq "") { $done = $true; continue }
        $idx = 0
        if ([int]::TryParse($line, [ref]$idx)) {
            $idx = $idx - 1
            if ($idx -ge 0 -and $idx -lt $keys.Count) {
                $pk = $keys[$idx]
                $pd = $Global:PerkMaster[$pk]
                if ($Global:Meta.Unlocked[$pk]) {
                    Write-Host "You already own this." -ForegroundColor DarkGray
                    Wait-AnyKey
                } elseif ($Global:Meta.Echoes -ge $pd.Cost) {
                    if (Read-YesNo "Spend $($pd.Cost) Echoes on '$($pd.Name)'") {
                        $Global:Meta.Echoes -= $pd.Cost
                        $Global:Meta.Unlocked[$pk] = $true
                        Export-Meta
                        Write-Host "Unlocked: $($pd.Name)!" -ForegroundColor Green
                        Wait-AnyKey
                    }
                } else {
                    Write-Host "Not enough Echoes." -ForegroundColor Red
                    Wait-AnyKey
                }
            }
        }
    }
}

function Show-Records {
    Clear-Host
    $s = $Global:Meta.Stats
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host "  RECORDS" -ForegroundColor White
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host "  Total runs:       $($s.TotalRuns)" -ForegroundColor Gray
    Write-Host "  Victories:        $($s.TotalVictories)" -ForegroundColor Gray
    Write-Host "  Deaths:           $($s.TotalDeaths)" -ForegroundColor Gray
    Write-Host "  Abandoned:        $($s.TotalAbandons)" -ForegroundColor Gray
    Write-Host "  Best floor:       $($s.BestFloor) / $($Global:MaxFloor)" -ForegroundColor Gray
    Write-Host "  Total kills:      $($s.TotalKills)" -ForegroundColor Gray
    Write-Host "  Total gold ever:  $($s.TotalGoldEver)" -ForegroundColor Gray
    Write-Host "  Lifetime Echoes:  $($Global:Meta.TotalEchoesEarned)" -ForegroundColor Gray
    Write-Host "  Echoes available: $($Global:Meta.Echoes)" -ForegroundColor Yellow
    Wait-AnyKey
}

function Show-MainMenu {
    $done = $false
    while (-not $done) {
        Clear-Host
        Write-Host ("=" * 70) -ForegroundColor DarkGray
        Write-Host "  DELVE - MAIN MENU" -ForegroundColor White
        Write-Host ("=" * 70) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [1] New Run" -ForegroundColor Yellow
        if (Test-RunSaveExists) {
            Write-Host "  [2] Continue Run" -ForegroundColor Yellow
        } else {
            Write-Host "  [2] Continue Run (none saved)" -ForegroundColor DarkGray
        }
        Write-Host "  [3] Sanctuary (Echoes: $($Global:Meta.Echoes))" -ForegroundColor Yellow
        Write-Host "  [4] Records" -ForegroundColor Yellow
        Write-Host "  [5] Help" -ForegroundColor Yellow
        Write-Host "  [6] Quit" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "> " -NoNewline -ForegroundColor Yellow
        $line = Read-MenuLine
        switch ($line) {
            "1" { Start-NewRun; break }
            "2" {
                if (Test-RunSaveExists) { Resume-Run }
                break
            }
            "3" { Show-Sanctuary; break }
            "4" { Show-Records; break }
            "5" { Show-HelpScreen; break }
            "6" { $done = $true; break }
            default { }
        }
    }
}

# ============================================================================
#  MAIN GAME LOOP
# ============================================================================

function Start-GameLoop {
    while ($true) {
        Render-Screen
        $key = [System.Console]::ReadKey($true)

        switch ($key.Key) {
            "UpArrow"    { Move-Player -DX 0 -DY -1; break }
            "DownArrow"  { Move-Player -DX 0 -DY 1; break }
            "LeftArrow"  { Move-Player -DX -1 -DY 0; break }
            "RightArrow" { Move-Player -DX 1 -DY 0; break }
            "W" { Move-Player -DX 0 -DY -1; break }
            "S" { Move-Player -DX 0 -DY 1; break }
            "A" { Move-Player -DX -1 -DY 0; break }
            "D" { Move-Player -DX 1 -DY 0; break }
            "Enter" { Invoke-TileInteract; break }
            "Spacebar" { Wait-Turn; break }
            "I" { Show-InventoryMenu; break }
            "Q" { Use-Ability; break }
            "C" { Show-CharacterSheet; break }
            "Escape" {
                $res = Show-PauseMenu
                if ($res -eq "Abandoned") {
                    Show-AbandonScreen
                    $Global:Player = $null
                } elseif ($res -eq "QuitToMenu") {
                    $Global:Player = $null
                }
                break
            }
            default { }
        }

        if (-not $Global:Player) { return }
        if ($Global:Player.Victorious) { $Global:Player = $null; return }
        if (-not $Global:Player.Alive) {
            Show-DeathScreen
            $Global:Player = $null
            return
        }
    }
}

# ============================================================================
#  PRE-FLIGHT: CONSOLE SIZING
# ============================================================================
# DELVE's full screen (header + 20-row map + message log + hint line) is
# 34 lines tall and up to 100 columns wide. Many default console profiles
# are shorter than that, which causes Clear-Host to visually "stack" old
# frames instead of cleanly redrawing -- the window's viewport scrolls
# down a little further each turn because the content doesn't fit, even
# though each frame really is being drawn fresh into a cleared buffer.
# This grows the window/buffer to fit, once, at startup. It only ever
# grows (never shrinks) and only if the current size is already too
# small, and every step is wrapped in try/catch: plenty of hosts (many
# Windows Terminal profiles, VS Code's integrated terminal, the ISE)
# don't support resizing at all or throw when asked, and this fails
# silently in those cases -- the game still runs, just may need manual
# resizing or scrolling in those specific hosts.

$Global:DelveLayoutWidth = 102
$Global:DelveLayoutHeight = 40

function Resize-DelveConsole {
    try {
        $rawUi = $Host.UI.RawUI
        if (-not $rawUi) { return }

        $targetWidth = $Global:DelveLayoutWidth
        $targetHeight = $Global:DelveLayoutHeight

        $maxSize = $rawUi.MaxPhysicalWindowSize
        if ($maxSize.Width -gt 0) { $targetWidth = [Math]::Min($targetWidth, $maxSize.Width) }
        if ($maxSize.Height -gt 0) { $targetHeight = [Math]::Min($targetHeight, $maxSize.Height) }
        if ($targetWidth -le 0 -or $targetHeight -le 0) { return }

        # Buffer must be at least as large as the window before the window
        # can grow, so grow the buffer first.
        $bufferSize = $rawUi.BufferSize
        $newBufferWidth = [Math]::Max($bufferSize.Width, $targetWidth)
        $newBufferHeight = [Math]::Max($bufferSize.Height, $targetHeight)
        if ($newBufferWidth -ne $bufferSize.Width -or $newBufferHeight -ne $bufferSize.Height) {
            $bufferSize.Width = $newBufferWidth
            $bufferSize.Height = $newBufferHeight
            $rawUi.BufferSize = $bufferSize
        }

        $windowSize = $rawUi.WindowSize
        $newWindowWidth = [Math]::Max($windowSize.Width, $targetWidth)
        $newWindowHeight = [Math]::Max($windowSize.Height, $targetHeight)
        if ($newWindowWidth -ne $windowSize.Width -or $newWindowHeight -ne $windowSize.Height) {
            $windowSize.Width = $newWindowWidth
            $windowSize.Height = $newWindowHeight
            $rawUi.WindowSize = $windowSize
        }
    } catch {
        # Resizing isn't supported here -- carry on at whatever size is available.
    }
}

# ============================================================================
#  ENTRY POINT
# ============================================================================

$__origCursorVisible = $true
try {
    $__origCursorVisible = [System.Console]::CursorVisible
} catch { }

try {
    Resize-DelveConsole
    try { $Host.UI.RawUI.WindowTitle = "DELVE" } catch { }
    try { [System.Console]::CursorVisible = $false } catch { }

    Import-Meta
    Show-TitleScreen
    Show-MainMenu

    Clear-Host
    Write-Host "Thanks for playing DELVE. Until next descent." -ForegroundColor Cyan
    Write-Host ""
} finally {
    try { [System.Console]::CursorVisible = $__origCursorVisible } catch { }
}


# CHANGELOG
# 1.0.0 - 07/04/26
# 1.0.1 - 07/05/26 - Bugfixes, balance and formatting changes. 
# 1.0.2 - 07/07/26 - Locked class costs follow Sanctuary data; New Run confirms before replacing a save; Abandon Run banks earned Echoes without death credit. Reworked/added new items, added new rarities. Locked class costs follow Sanctuary data; New Run confirms before replacing a save; Abandon Run banks earned Echoes without death credit; inventory item use now confirms inline; Space uses stairs when standing on them; Enter reuses stairs, merchants, and shrines.
