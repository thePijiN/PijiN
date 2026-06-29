```text
   _____                       __________  ___   ________ __
  / ___/____  ____ _________  / ____/ __ \/   | / ____/ //_/
  \__ \/ __ \/ __ `/ ___/ _ \/ /_  / /_/ / /| |/ /   / ,<
 ___/ / /_/ / /_/ / /__/  __/ __/ / _, _/ ___ / /___/ /| |
/____/ .___/\__,_/\___/\___/_/   /_/ |_/_/  |_\____/_/ |_|
    /_/
```

# SpaceFRACK

A terminal space-prospecting game about squeezing value out of hostile planets,
selling what survives the trip, and not dying in the process.

## The Three Big Numbers

Managing these three values is the key to not dying or getting stranded:

- `HP` = Health. When this hits zero, that's it.
- `FL` = Fuel. Travel, scanning, and survival all get awkward when this runs dry.
- `WT` = Weight. Your cargo has limits. Heavy pockets can end a good run fast.

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

## The Loop

1. Frack planets to acquire materials.
2. Sell resources to trader outposts.
3. Buy consumables and upgrades.
4. Complete contracts for better rewards.
5. Explore the Sol system and beyond.

## Getting Started

Run the game with PowerShell:

```powershell
.\Spacegame.ps1
```

You begin in Sol with a small ship, limited resources, and no reputation. 
Manage your `HP`, `FL`, `WT`, and `CD`, and move strategically.

The "Cryo-Sleep Chamber" upgradecan be attained via an early Mars quest...
 **ahem**gotovenus**ahem** 
 ... which can be used to fast-forward. Enabling the game to be actively
 played, no more idling, if you can manage the risks, and get lucky.

Go forth and frack.
