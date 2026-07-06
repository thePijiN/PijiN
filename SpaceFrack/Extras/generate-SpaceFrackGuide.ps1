$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$gamePath = Join-Path $root "Spacegame.ps1"
$outPath = Join-Path $root "SpaceFrackGuide.html"

$gameSource = Get-Content -LiteralPath $gamePath -Raw
$version = if ($gameSource -match '\$SpacegameVersion\s*=\s*"([^"]+)"') { $Matches[1] } else { $null }
$defsOnly = [regex]::Replace($gameSource, '(?s)#region ##### DO IT #####.*$', '')
. ([scriptblock]::Create($defsOnly))
Start-NewGame

function Convert-Map($map) {
    $obj = [ordered]@{}
    foreach ($key in ($map.Keys | Sort-Object)) {
        $value = $map[$key]
        if ($value -is [System.Collections.IDictionary]) {
            $obj[$key] = Convert-Map $value
        } elseif ($value -is [System.Array]) {
            $obj[$key] = @($value | ForEach-Object {
                if ($_ -is [System.Collections.IDictionary]) { Convert-Map $_ } else { $_ }
            })
        } else {
            $obj[$key] = $value
        }
    }
    return $obj
}

$systems = @()
foreach ($sys in $global:AllSystems) {
    $planets = @()
    foreach ($planetName in ($sys.Data.Keys | Where-Object { $_ -ne "_Metadata" } | Sort-Object { [double]$sys.Data[$_].Distance })) {
        $p = $sys.Data[$planetName]
        $resourceWeight = ($p.Resources.GetEnumerator() | Measure-Object -Property Value -Sum).Sum
        $planets += [ordered]@{
            Name = $planetName
            Distance = [double]$p.Distance
            Inhabited = [bool]$p.Inhabited
            Type = [string]$p.Type
            Danger = [double](Get-PlanetDanger $p)
            Hazard = [int](Get-BaseHazard $p)
            PlanetColor = [string]$p.PlanetColor
            Description = [string]$p.Description
            ResourceWeight = [int]$resourceWeight
            Resources = Convert-Map $p.Resources
            HazardReasons = @($p.HazardReasons)
            TraderName = if ($p.TraderName) { [string]$p.TraderName } else { $null }
            TotalTraderCredits = if ($p.TotalTraderCredits) { [int]$p.TotalTraderCredits } else { $null }
            FuelModifier = if ($p.FuelModifier) { [double]$p.FuelModifier } else { $null }
            RepairModifier = if ($p.RepairModifier) { [double]$p.RepairModifier } else { $null }
            TraderStock = if ($p.TraderStock) { Convert-Map $p.TraderStock } else { $null }
            Quests = if ($p.Quests) { @($p.Quests | ForEach-Object { Convert-Map $_ }) } else { @() }
        }
    }
    $systems += [ordered]@{
        Id = [string]$sys.Name
        Name = [string]$sys.Name
        Planets = $planets
    }
}

$payload = [ordered]@{
    GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Version = $version
    ResourceMaster = Convert-Map $global:ResourceMaster
    HazardMaster = Convert-Map $global:HazardMaster
    Systems = $systems
    Formulas = [ordered]@{
        Travel = "Ceiling(abs(distanceA - distanceB) / 0.1)"
        ProspectFuel = "0.5 FL per prospect tick"
        Danger = "Target average HP damage per prospect tick before upgrades"
        Hazard = "Ceiling(Danger * 100 / (mean event damage * 0.75)), capped 1..100"
        HazardChance = "Floor(Effective HZ * 0.75) percent per tick, base values assume no upgrades"
        Damage = "[int][math]::Max(1, baseDamage * multiplier), baseDamage is 2..9"
        SellValue = "floor(ResourceMaster.Value * 0.69), matching trader sell value"
        SellTick = "Weighted average sell value * (1 - HazardChance), because hazard ticks do not yield resources"
        Service = "Nearest trader in the same system, tie-broken by lower fuel+repair modifiers; shown with one-way FL"
        EffectiveHazard = "Base HZ multiplied by (1 - matching frack reduction)^stacks, then radiation suit reduction when enabled and base HZ meets the threshold"
        HpTick = "Average event hit * HazardChance after active upgrade assumptions"
        CostTick = "(0.5 FL * 3 CD * service fuel modifier) + (HP/Tick * service repair modifier)"
        NetTick = "Adjusted SellTick - adjusted CostTick under the active upgrade assumptions"
        BaseNet = "Unupgraded NetTick, kept as a comparison column"
        ServiceTravel = "Service travel is shown for context but not amortized into NetTick"
    }
}

$json = $payload | ConvertTo-Json -Depth 80 -Compress
$html = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SpaceFRACK Guide</title>
<style>
:root{--bg:#081018;--panel:#111b24;--panel2:#172532;--ink:#e7edf2;--muted:#93a4b3;--soft:#5e7283;--line:#284052;--accent:#4ed7b5;--warn:#f2c84b;--hot:#f47a55;--bad:#ef4f69;--blue:#6ab7ff;--violet:#b696ff;--green:#79d879}
*{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);font-family:Inter,Segoe UI,Arial,sans-serif;font-size:14px;line-height:1.35}
header{position:sticky;top:0;z-index:5;background:rgba(8,16,24,.96);border-bottom:1px solid var(--line);padding:16px 22px}
h1{margin:0;font-size:24px;letter-spacing:.02em} .sub{margin-top:4px;color:var(--muted);font-size:13px}.wrap{padding:22px;max-width:1800px;margin:auto}
.toolbar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:18px}.chip{border:1px solid var(--line);background:var(--panel);color:var(--muted);padding:7px 10px;border-radius:6px;cursor:pointer}.chip.on{color:var(--bg);background:var(--accent);border-color:var(--accent);font-weight:700}.spacer{flex:1}.search{background:var(--panel);border:1px solid var(--line);color:var(--ink);border-radius:6px;padding:8px 10px;min-width:260px}
section{margin:0 0 28px}.sectionHead{display:flex;gap:12px;align-items:end;justify-content:space-between;margin:0 0 10px}.headLeft{display:flex;align-items:center;gap:12px;flex-wrap:wrap}h2{font-size:18px;margin:0}.note{color:var(--muted);font-size:12px}.tabs{display:flex;gap:6px;flex-wrap:wrap}.tab{border:1px solid var(--line);background:var(--panel);color:var(--muted);padding:5px 9px;border-radius:6px;cursor:pointer;font-size:12px}.tab.on{background:var(--accent);border-color:var(--accent);color:var(--bg);font-weight:700}.traderFilters{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.traderToggle{display:inline-flex;gap:5px;align-items:center;border:1px solid var(--line);background:var(--panel);border-radius:6px;padding:5px 8px;font-size:12px;font-weight:700}.traderToggle input{accent-color:var(--accent)}
.map{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px;overflow:hidden}.rail{position:relative;height:190px;min-width:100%}.axis{position:absolute;left:28px;right:28px;top:88px;height:2px;background:linear-gradient(90deg,var(--soft),var(--accent))}.planetMark{position:absolute;top:79px;width:18px;height:18px;transform:translateX(-9px);border-radius:50%;border:2px solid rgba(255,255,255,.6);box-shadow:0 0 14px currentColor}.planetLabel{position:absolute;width:96px;transform:translateX(-48px);text-align:center}.planetLabel.b0{top:106px}.planetLabel.a0{top:36px}.planetLabel.b1{top:142px}.planetLabel.a1{top:0}.leader{position:absolute;left:50%;width:1px;background:rgba(255,255,255,.18);transform:translateX(-.5px)}.b0 .leader{height:15px;top:-17px}.b1 .leader{height:51px;top:-53px}.a0 .leader{height:30px;bottom:-32px}.a1 .leader{height:66px;bottom:-68px}.pname{font-weight:700;font-size:12px;line-height:1.05;white-space:nowrap}.pmeta{font-size:11px;line-height:1.15;color:var(--muted)}.leg{position:absolute;top:112px;height:1px;background:rgba(255,255,255,.14)}.legText{position:absolute;top:119px;transform:translateX(-50%);font-size:10px;color:var(--muted);white-space:nowrap}.legText.tight{display:none}
.upgradeGrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px}.upgradeCard{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}.upgradeCard b{display:block;font-size:14px}.upgradeCard span{color:var(--muted);font-size:12px}.controlRow{display:grid;grid-template-columns:1fr 72px 92px;gap:8px;align-items:end}.field{display:grid;gap:3px}.field label{color:var(--muted);font-size:11px}.numInput{width:100%;background:var(--panel2);border:1px solid var(--line);border-radius:6px;color:var(--ink);padding:6px 7px;font:inherit}.presetRow{display:flex;gap:6px;flex-wrap:wrap;margin-top:10px}.checkRow{display:flex;gap:8px;align-items:center;margin-bottom:8px;color:var(--ink);font-weight:700}.checkRow input{accent-color:var(--accent)}
.tableWrap{overflow:auto;border:1px solid var(--line);border-radius:8px;background:var(--panel)}table{width:100%;border-collapse:collapse;min-width:1680px}thead{display:table-header-group}th,td{padding:9px 10px;border-bottom:1px solid rgba(40,64,82,.72);vertical-align:top}th{background:#0d1821;color:var(--muted);font-size:11px;text-align:left;letter-spacing:.08em;text-transform:uppercase;cursor:pointer}td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}.planetCell{display:flex;align-items:center;gap:8px;font-weight:700}.miniDot{width:10px;height:10px;border-radius:50%;box-shadow:0 0 8px currentColor;flex:none}.tag{display:inline-block;border:1px solid var(--line);border-radius:5px;padding:2px 6px;color:var(--muted);font-size:11px}.tag.inh{border-color:rgba(106,183,255,.45);color:var(--blue)}.tag.trader{border-color:rgba(78,215,181,.45);color:var(--accent)}
.barStack{display:grid;gap:3px;min-width:300px}.res{display:grid;grid-template-columns:1fr 44px 150px;gap:6px;align-items:center;font-size:11px}.resName{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.barBg{height:8px;background:#253849;border-radius:99px;overflow:hidden}.bar{display:block;height:100%;border-radius:99px}.hazards{display:flex;flex-wrap:wrap;gap:4px;max-width:360px}.haz{border-radius:5px;padding:3px 6px;font-size:11px;color:#081018;font-weight:700}.stock{font-size:12px;color:var(--muted);max-width:360px}.stock b{display:block;margin-bottom:4px}.stockItem{display:block;margin:2px 0}.summaryGrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:10px}.metric{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}.metric b{display:block;font-size:22px}.metric span{color:var(--muted);font-size:12px}
.traders{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:12px}.traderCard{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px}.traderCard h3{margin:0 0 6px;font-size:16px}.kv{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin:10px 0}.kv div{background:var(--panel2);border:1px solid rgba(40,64,82,.8);border-radius:6px;padding:8px}.kv b{display:block}.quest{border-top:1px solid var(--line);padding-top:10px;margin-top:10px}.questTop{display:flex;justify-content:space-between;gap:10px;align-items:baseline}.questName{font-weight:700}.rep{font-size:11px;color:var(--bg);background:var(--accent);border-radius:4px;padding:2px 6px;font-weight:800;white-space:nowrap}.qrow{display:grid;grid-template-columns:54px 1fr;gap:8px;margin-top:5px}.qrow b{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.06em}.itemRef{font-weight:700}.muted{color:var(--muted)}.small{font-size:12px}.good{color:var(--green)}.mid{color:var(--warn)}.poor{color:var(--hot)}.deadly{color:var(--bad)}
@media(max-width:760px){header{position:static}.wrap{padding:14px}.search{min-width:100%}.rail{min-width:860px}}
</style>
</head>
<body>
<header><h1>SpaceFRACK Guide</h1><div class="sub">Generated from live <code>Spacegame.ps1</code> data at __GENERATED_AT__. Travel cost is FL between planets, not from the star.</div></header>
<main class="wrap">
  <div class="toolbar" id="systemFilters"></div>
  <section><div class="sectionHead"><h2>System Travel Maps</h2><div class="note">Segment labels show AU gap and exact FL cost between adjacent planets.</div></div><div id="maps"></div></section>
  <section><div class="sectionHead"><h2>Upgrade Assumptions</h2><div class="note">Live frack stacks and reduction values used by the planet table.</div></div><div class="upgradeGrid" id="upgradeControls"></div></section>
  <section><div class="sectionHead"><div class="headLeft"><h2>Planet Table</h2><div class="tabs" id="tableTabs"></div></div><div class="note">Expected fracking value, damage, and service-adjusted profitability per tick.</div></div><div class="tableWrap"><table id="planetTable"></table></div></section>
  <section><div class="sectionHead"><div class="headLeft"><h2>Traders And Quests</h2><div class="traderFilters" id="traderFilters"></div></div><div class="note">Trader economics, stock, and quest gates in one place.</div></div><div class="traders" id="traders"></div></section>
  <section><div class="sectionHead"><h2>Quick Extremes</h2><div class="note">Fast balance smell-test.</div></div><div class="summaryGrid" id="summary"></div></section>
  <section><div class="sectionHead"><h2>Balance Metrics</h2><div class="note">Definitions used by the planet table.</div></div><div class="summaryGrid" id="formulaSummary"></div></section>
</main>
<script id="payload" type="application/json">__PAYLOAD_JSON__</script>
<script>
const DATA = JSON.parse(document.getElementById('payload').textContent);
const state = { system: 'All', tableSystem: DATA.Systems[0]?.Id || 'All', sort: 'Distance', dir: 1, search: '' };
const colorMap = {Black:'#111',DarkBlue:'#264a99',DarkGreen:'#267a45',DarkCyan:'#2aa6a6',DarkRed:'#a83b34',DarkMagenta:'#8d4aa8',DarkYellow:'#b68b2e',Gray:'#9aa2aa',DarkGray:'#606873',Blue:'#4f8cff',Green:'#58c878',Cyan:'#5fd5e6',Red:'#ef5d5d',Magenta:'#dd72e8',Yellow:'#f0d35a',White:'#eef4ff'};
const rarityColors = {SuperCommon:'#94a3b8',Common:'#cbd5e1',Uncommon:'#22d3ee',Rare:'#67e8f9',SuperRare:'#c084fc',UltraRare:'#d6a721',Artifact:'#d6a721',Oddity:'#f8fafc',Consumable:'#79d879',Upgrade:'#6abf69'};
const pirate = new Set(['Stray projectile','EMP pulse','Orbital mine detonation','Hull breach','Gatling barrage','Missile volley','Torpedo strike']);
const allPlanets = DATA.Systems.flatMap(s => s.Planets.map((p,i,arr) => ({...p, SystemId:s.Id, SystemName:s.Name, Order:i, Prev:i?arr[i-1]:null, Next:i<arr.length-1?arr[i+1]:null})));
const allTraders = allPlanets.filter(p=>p.TraderName);
const upgradeTypes = [
  {key:'frackTerr', label:'frackTerr', type:'Terrestrial', item:'Terrain Hardening Kit', fallback:20},
  {key:'frackAst', label:'frackAst', type:'Asteroid', item:'Asteroid Surveyer', fallback:50},
  {key:'frackGas', label:'frackGas', type:'Gas Giant', item:'Gas Giant Surveyor', fallback:50},
  {key:'frackIce', label:'frackIce', type:'Ice Giant', item:'Ice Giant Surveyor', fallback:50},
  {key:'frackDwarf', label:'frackDwarf', type:'Dwarf', item:'Dwarf-Class Surveyor', fallback:30}
];
state.traders = {};
allTraders.forEach(p => { state.traders[traderKey(p)] = true; });
state.upgrades = {};
upgradeTypes.forEach(t => { const item=DATA.ResourceMaster[t.item]||{}; const reduction=Number(item.HazardReduction?.[t.type] ?? (t.fallback/100)) * 100; state.upgrades[t.key] = { stacks:0, reduction:reduction }; });
const radItem = DATA.ResourceMaster['Rad-Shielding Exosuit'] || {};
state.radiation = { enabled:false, threshold:Number(radItem.HazardThreshold ?? 80), reduction:Number(radItem.HazardReduction?._threshold ?? .25) * 100 };
const money = n => Number(n||0).toLocaleString();
const fl = au => Math.ceil(Math.abs(au) / 0.1);
const flText = au => fl(au).toFixed(1);
const htmlEscapes = {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'};
function esc(v){ return String(v ?? '').replace(/[&<>"']/g, ch => htmlEscapes[ch]); }
function rarityColor(item){ const master=DATA.ResourceMaster[item]||{}; return rarityColors[master.Rarity] || 'var(--ink)'; }
function itemRef(item, qty){ const prefix=qty===undefined || qty===null ? '' : `${money(qty)} `; return `<span class="itemRef" style="color:${rarityColor(item)}">${prefix}${esc(item)}</span>`; }
function stockRuleSummary(rule){ if(rule===undefined || rule===null) return ''; if(typeof rule !== 'object') return money(rule); const chance=Number(rule.Chance ?? 100); const min=Number(rule.MinQty ?? 1); const max=Number(rule.MaxQty ?? min); const doubleChance=Number(rule.DoubleChance ?? 0); if(min===1 && max===1 && doubleChance>0) return `${money(chance)}%, x1, +${money(doubleChance)}% x2`; const expected=(chance/100)*((min+max)/2+(doubleChance/100)); const avgText=expected>0 && expected<1 ? expected.toFixed(2) : expected.toFixed(1); const parts=[`avg ${avgText}`, `${money(min)}-${money(max)}`]; if(chance!==100) parts.push(`${money(chance)}%`); if(doubleChance>0) parts.push(`+${money(doubleChance)}%`); return parts.join(', '); }
function questNeeds(q){ const reqs=q.Requirements||[]; return reqs.length ? reqs.map(r=>itemRef(r.Item, r.Qty)).join(', ') : '<span class="muted">None</span>'; }
function questPays(q){ const parts=[]; const known=Array.isArray(q.RewardKnown)?q.RewardKnown:(q.RewardKnown?[q.RewardKnown]:[]); if(Number(q.RewardCD||0)>0) parts.push(`<span class="good">${money(q.RewardCD)} CD</span>`); if(q.RewardItems?.length) parts.push(...q.RewardItems.map(r=>itemRef(r.Item, r.Qty))); if(known.length) parts.push(...known.map(k=>`<span class="muted">Unlock: ${esc(k)}</span>`)); return parts.join(', ') || '<span class="muted">None</span>'; }
function psRound(n){ const f=Math.floor(n), d=n-f; if(d<.5)return f; if(d>.5)return f+1; return f % 2 === 0 ? f : f+1; }
function damageFor(mult){ let total=0; for(let base=2;base<=9;base++) total += Math.max(1, psRound(base*mult)); return total/8; }
function clamp(n,min,max){ const v=Number(n); return Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : min; }
function eventChanceForHz(hz){ return Math.min(100, Math.max(0, Math.floor(Number(hz||0) * .75))) / 100; }
function eventChance(p){ return eventChanceForHz(p.Hazard); }
function yieldChanceForHz(hz){ return Math.max(0, 1 - eventChanceForHz(hz)); }
function effectiveHazard(p){ let hz=Number(p.Hazard||0); const model=upgradeTypes.find(t=>t.type===p.Type); if(model){ const cfg=state.upgrades[model.key]||{}; const stacks=Math.max(0, Math.floor(Number(cfg.stacks||0))); const reduction=clamp(cfg.reduction,0,100)/100; for(let i=0;i<stacks;i++) hz *= (1-reduction); } if(state.radiation.enabled && Number(p.Hazard||0) >= clamp(state.radiation.threshold,0,100)){ hz *= (1 - clamp(state.radiation.reduction,0,100)/100); } return Math.floor(Math.max(0,hz)); }
function avgDamage(p){ const reasons = p.HazardReasons?.length ? p.HazardReasons : ['Hull stress']; return reasons.reduce((a,r)=>a+damageFor(DATA.HazardMaster[r] ?? 1),0) / reasons.length; }
function avgDotForHz(p,hz){ return eventChanceForHz(hz) * avgDamage(p); }
function avgDot(p){ return avgDotForHz(p, p.Hazard); }
function sellResourceValue(p){ const entries = Object.entries(p.Resources || {}); const total=entries.reduce((a,[,q])=>a+Number(q),0)||1; return entries.reduce((a,[r,q])=>{ const master=DATA.ResourceMaster[r]||{}; const sell=Math.floor(Number(master.Value||0)*.69); return a+(Number(q)/total)*sell; },0); }
function grossSellTickForHz(p,hz){ return sellResourceValue(p) * yieldChanceForHz(hz); }
function servicePlanet(p){ const traders=allTraders.filter(t=>t.SystemId===p.SystemId); if(!traders.length) return null; return [...traders].sort((a,b)=>(Math.abs(a.Distance-p.Distance)-Math.abs(b.Distance-p.Distance)) || ((Number(a.FuelModifier||1)+Number(a.RepairModifier||1))-(Number(b.FuelModifier||1)+Number(b.RepairModifier||1))) || a.Distance-b.Distance)[0]; }
function serviceName(p){ const svc=servicePlanet(p); if(!svc) return 'Base'; const svcFl=fl(svc.Distance-p.Distance); return svcFl>0 ? `${svc.Name} (${svcFl.toFixed(1)} FL)` : svc.Name; }
function fuelCostTick(p){ const svc=servicePlanet(p); return .5 * 3 * (svc ? Number(svc.FuelModifier||1) : 1); }
function repairCostTickForHz(p,hz){ const svc=servicePlanet(p); return avgDotForHz(p,hz) * (svc ? Number(svc.RepairModifier||1) : 1); }
function costTickForHz(p,hz){ return fuelCostTick(p) + repairCostTickForHz(p,hz); }
function netTickForHz(p,hz){ return grossSellTickForHz(p,hz) - costTickForHz(p,hz); }
function cdTick(p){ return grossSellTickForHz(p, p.Hazard); }
function netClass(v){ return v>=10?'good':v>=0?'mid':'poor'; }
function hzClass(v){ return v>=10?'deadly':v>=3?'poor':v>=1.5?'mid':'good'; }
function planetColor(p){ return colorMap[p.PlanetColor] || '#e7edf2'; }
function traderKey(p){ return `${p.SystemName}::${p.Name}::${p.TraderName}`; }
function resourceBars(p){ const entries=Object.entries(p.Resources||{}).sort((a,b)=>b[1]-a[1]); const total=entries.reduce((a,e)=>a+Number(e[1]),0)||1; const maxQty=Math.max(...entries.map(e=>Number(e[1])),1); return `<div class="barStack">${entries.map(([r,q])=>{ const master=DATA.ResourceMaster[r]||{}; const pct=Number(q)/total*100; const barPct=Number(q)/maxQty*100; const color=rarityColors[master.Rarity]||'var(--accent)'; return `<div class="res"><span class="barBg"><span class="bar" style="width:${barPct}%;background:${color}"></span></span><span class="muted">${Math.round(pct)}%</span><span class="resName" title="${esc(r)}" style="color:${color}">${esc(r)} (${master.Value ?? '?'}, ${master.Weight ?? '?'})</span></div>`; }).join('')}</div>`; }
function hazardTags(p){ return `<div class="hazards">${(p.HazardReasons||[]).map(h=>{const m=DATA.HazardMaster[h]??1; const bg=m>=10?'#ef4f69':m>=3?'#f47a55':m>=1.5?'#f2c84b':'#79d879'; return `<span class="haz" title="${h}: x${m}${pirate.has(h)?' pirate event':''}" style="background:${bg}">${h} x${m}</span>`}).join('')}</div>`; }
function filters(){ const el=document.getElementById('systemFilters'); el.innerHTML = `<button class="chip ${state.system==='All'?'on':''}" data-sys="All">All Systems</button>` + DATA.Systems.map(s=>`<button class="chip ${state.system===s.Id?'on':''}" data-sys="${s.Id}">${s.Name}</button>`).join('') + `<span class="spacer"></span><input class="search" placeholder="Search planet, resource, hazard, trader..." value="${state.search}">`; el.querySelectorAll('button').forEach(b=>b.onclick=()=>{state.system=b.dataset.sys; render();}); el.querySelector('input').oninput=e=>{state.search=e.target.value.toLowerCase(); renderTables();}; }
function labelSlots(planets, scale){
  const last = { b0:-999, a0:-999, b1:-999, a1:-999 };
  return planets.map((p, index) => {
    const x = scale(p.Distance);
    const preferred = (index % 2 === 0) ? ['b0','b1','a0','a1'] : ['a0','a1','b0','b1'];
    let slot = preferred[0];
    for (const candidate of preferred) {
      if (x - last[candidate] >= 94) { slot = candidate; break; }
    }
    last[slot] = x;
    return slot;
  });
}
function maps(){
  const holder=document.getElementById('maps');
  const available = Math.max(860, holder.clientWidth - 34);
  holder.innerHTML = DATA.Systems.filter(s=>state.system==='All'||state.system===s.Id).map(s=>{
    const max=Math.max(...s.Planets.map(p=>p.Distance));
    const min=Math.min(...s.Planets.map(p=>p.Distance));
    const span=max-min || 1;
    const railWidth=available;
    const scale=d=>28+((d-min)/span)*(railWidth-56);
    const slots=labelSlots(s.Planets, scale);
    let seg='';
    for(let i=1;i<s.Planets.length;i++){
      const a=s.Planets[i-1], b=s.Planets[i], x1=scale(a.Distance), x2=scale(b.Distance), mid=(x1+x2)/2, gap=x2-x1;
      seg+=`<span class="leg" style="left:${x1}px;width:${gap}px"></span><span class="legText ${gap<82?'tight':''}" style="left:${mid}px">${(b.Distance-a.Distance).toFixed(1)} AU / ${flText(b.Distance-a.Distance)} FL</span>`;
    }
    return `<div class="map" style="margin-bottom:12px"><b>${s.Name}</b><div class="rail" style="width:${railWidth}px"><div class="axis"></div>${seg}${s.Planets.map((p,i)=>`<span class="planetMark" style="left:${scale(p.Distance)}px;color:${planetColor(p)}"></span><div class="planetLabel ${slots[i]}" style="left:${scale(p.Distance)}px;color:${planetColor(p)}"><span class="leader"></span><div class="pname">${p.Name}</div><div class="pmeta">${p.Distance} AU<br>HZ ${p.Hazard}</div></div>`).join('')}</div></div>`;
  }).join('');
}
function filtered(){ return allPlanets.filter(p=>state.system==='All'||p.SystemId===state.system).filter(p=>!state.search || JSON.stringify(p).toLowerCase().includes(state.search)); }
function tableRows(){ return allPlanets.filter(p=>p.SystemId===state.tableSystem).filter(p=>!state.search || JSON.stringify(p).toLowerCase().includes(state.search)); }
function renderTableTabs(){ const el=document.getElementById('tableTabs'); el.innerHTML = DATA.Systems.map(s=>`<button class="tab ${state.tableSystem===s.Id?'on':''}" data-table-sys="${s.Id}">${s.Name}</button>`).join(''); el.querySelectorAll('button').forEach(b=>b.onclick=()=>{state.tableSystem=b.dataset.tableSys; renderTables();}); }
function refreshBalanceViews(){ renderTables(); formulas(); }
function setStackPreset(stacks, resetRad){ upgradeTypes.forEach(t=>{ state.upgrades[t.key].stacks = stacks; }); if(resetRad){ state.radiation.enabled = false; } upgradeControls(); refreshBalanceViews(); }
function upgradeControls(){ const el=document.getElementById('upgradeControls'); const cards=upgradeTypes.map(t=>{ const cfg=state.upgrades[t.key]; return `<div class="upgradeCard"><div class="controlRow"><div><b>${esc(t.label)}</b><span>${esc(t.type)}<br>${esc(t.item)}</span></div><div class="field"><label>Stacks</label><input class="numInput" type="number" min="0" max="20" step="1" value="${cfg.stacks}" data-stack="${esc(t.key)}"></div><div class="field"><label>Reduction %</label><input class="numInput" type="number" min="0" max="100" step="1" value="${Number(cfg.reduction).toFixed(0)}" data-reduction="${esc(t.key)}"></div></div></div>`; }); el.innerHTML=`<div class="upgradeCard"><b>Presets</b><span>Set stack counts. Reduction values stay editable.</span><div class="presetRow"><button class="chip" data-preset="base">Base</button><button class="chip" data-preset="1">1x All</button><button class="chip" data-preset="2">2x All</button><button class="chip" data-preset="3">3x All</button></div></div>${cards.join('')}<div class="upgradeCard"><label class="checkRow"><input type="checkbox" data-rad-enabled ${state.radiation.enabled?'checked':''}>RadiationSuit</label><div class="controlRow"><div><b>Rad-Shielding</b><span>Applies after frack stacks when base HZ meets threshold.</span></div><div class="field"><label>HZ Min</label><input class="numInput" type="number" min="0" max="100" step="1" value="${state.radiation.threshold}" data-rad-threshold></div><div class="field"><label>Reduction %</label><input class="numInput" type="number" min="0" max="100" step="1" value="${Number(state.radiation.reduction).toFixed(0)}" data-rad-reduction></div></div></div>`; el.querySelectorAll('[data-preset]').forEach(btn=>btn.onclick=()=>{ const preset=btn.dataset.preset; if(preset==='base'){ setStackPreset(0, true); } else { setStackPreset(Number(preset), false); } }); el.querySelectorAll('[data-stack]').forEach(input=>input.oninput=()=>{ state.upgrades[input.dataset.stack].stacks = clamp(input.value,0,20); refreshBalanceViews(); }); el.querySelectorAll('[data-reduction]').forEach(input=>input.oninput=()=>{ state.upgrades[input.dataset.reduction].reduction = clamp(input.value,0,100); refreshBalanceViews(); }); const radEnabled=el.querySelector('[data-rad-enabled]'); radEnabled.onchange=()=>{ state.radiation.enabled = radEnabled.checked; refreshBalanceViews(); }; const radThreshold=el.querySelector('[data-rad-threshold]'); radThreshold.oninput=()=>{ state.radiation.threshold = clamp(radThreshold.value,0,100); refreshBalanceViews(); }; const radReduction=el.querySelector('[data-rad-reduction]'); radReduction.oninput=()=>{ state.radiation.reduction = clamp(radReduction.value,0,100); refreshBalanceViews(); }; }
function renderTables(){ renderTableTabs(); const rows=tableRows().map(p=>{ const effHz=effectiveHazard(p); return {...p, EffectiveHazard:effHz, AvgDOT:avgDotForHz(p,effHz), BaseAvgDOT:avgDot(p), AvgHit:avgDamage(p), SellTick:grossSellTickForHz(p,effHz), CostTick:costTickForHz(p,effHz), NetTick:netTickForHz(p,effHz), BaseNetTick:netTickForHz(p,p.Hazard), Service:serviceName(p), InCost:p.Prev?fl(p.Distance-p.Prev.Distance):0, OutCost:p.Next?fl(p.Next.Distance-p.Distance):0}; }); rows.sort((a,b)=>{ const av=a[state.sort], bv=b[state.sort]; return ((typeof av==='number'?av-bv:String(av).localeCompare(String(bv))) || a.Distance-b.Distance) * state.dir; }); const table=document.getElementById('planetTable'); const heads=[['Name','Planet'],['Type','Type'],['Distance','AU'],['InCost','Prev FL'],['OutCost','Next FL'],['Hazard','Base HZ'],['EffectiveHazard','Eff HZ'],['AvgHit','Avg Hit'],['AvgDOT','HP/Tick'],['SellTick','Sell/Tick'],['CostTick','Cost/Tick'],['NetTick','Net/Tick'],['BaseNetTick','Base Net'],['Service','Svc'],['Resources','Resources'],['Hazards','Hazards'],['Flags','Flags']]; const numericHeads=['Distance','InCost','OutCost','Hazard','EffectiveHazard','AvgHit','AvgDOT','SellTick','CostTick','NetTick','BaseNetTick']; table.innerHTML=`<thead><tr>${heads.map(([k,l])=>`<th class="${numericHeads.includes(k)?'num':''}" data-sort="${k}">${l}${state.sort===k?(state.dir>0?' ^':' v'):''}</th>`).join('')}</tr></thead><tbody>${rows.map(p=>{ const rw=Number(p.ResourceWeight||0); return `<tr><td><div class="planetCell"><span class="miniDot" style="background:${planetColor(p)};color:${planetColor(p)}"></span>${esc(p.Name)}</div><div class="muted small">${esc(p.Description||'')}</div><div class="muted small">Resource weight: ${money(rw)}</div></td><td>${esc(p.Type)}</td><td class="num">${p.Distance.toFixed(1)}</td><td class="num">${p.InCost?p.InCost.toFixed(1):'Start'}</td><td class="num">${p.OutCost?p.OutCost.toFixed(1):'End'}</td><td class="num">${p.Hazard}</td><td class="num">${p.EffectiveHazard}</td><td class="num">${p.AvgHit.toFixed(1)}</td><td class="num ${hzClass(p.AvgDOT)}">${p.AvgDOT.toFixed(2)}</td><td class="num">${p.SellTick.toFixed(1)}</td><td class="num">${p.CostTick.toFixed(1)}</td><td class="num ${netClass(p.NetTick)}">${p.NetTick.toFixed(1)}</td><td class="num ${netClass(p.BaseNetTick)}">${p.BaseNetTick.toFixed(1)}</td><td>${esc(p.Service)}</td><td>${resourceBars(p)}</td><td>${hazardTags(p)}</td><td>${p.Inhabited?'<span class="tag inh">Inhabited</span> ':''}${p.TraderName?'<span class="tag trader">Trader</span>':''}</td></tr>`}).join('')}</tbody>`; table.querySelectorAll('th[data-sort]').forEach(th=>th.onclick=()=>{const k=th.dataset.sort; state.dir=state.sort===k?-state.dir:1; state.sort=k; renderTables();}); summary(rows); traders(); }
function traderFilters(){ const el=document.getElementById('traderFilters'); el.innerHTML=allTraders.map(p=>{ const key=traderKey(p), color=planetColor(p); return `<label class="traderToggle" style="color:${color}"><input type="checkbox" data-trader="${esc(key)}" ${state.traders[key]?'checked':''}>${esc(p.TraderName)}</label>`; }).join(''); el.querySelectorAll('input').forEach(box=>box.onchange=()=>{ state.traders[box.dataset.trader]=box.checked; traders(); }); }
function traders(){ traderFilters(); const el=document.getElementById('traders'); const planets=filtered().filter(p=>p.TraderName && state.traders[traderKey(p)]); el.innerHTML=planets.map(p=>{ const color=planetColor(p); return `<article class="traderCard"><h3 style="color:${color}">${esc(p.TraderName)}</h3><div class="muted">${esc(p.Name)}, ${esc(p.SystemName)}</div><div class="kv"><div><span class="muted small">Credits</span><b>${money(p.TotalTraderCredits)} CD</b></div><div><span class="muted small">Fuel price</span><b>x${p.FuelModifier}</b></div><div><span class="muted small">Repair price</span><b>x${p.RepairModifier}</b></div></div><div class="stock"><b>Stock</b>${Object.entries(p.TraderStock||{}).map(([i,q])=>`<div class="stockItem">${itemRef(i)} <span class="muted">(${stockRuleSummary(q)})</span></div>`).join('') || '<span class="muted">None</span>'}</div>${(p.Quests||[]).map(q=>`<div class="quest"><div class="questTop"><div class="questName">${esc(q.Name)}</div><span class="rep">REP ${q.RepReq ?? 0}</span></div><div class="qrow"><b>Needs</b><span>${questNeeds(q)}</span></div><div class="qrow"><b>Pays</b><span>${questPays(q)}</span></div></div>`).join('')}</article>`; }).join('') || '<div class="muted">No traders selected in current filter.</div>'; }
function summary(rows){ const el=document.getElementById('summary'); if(!rows.length){el.innerHTML='';return;} const maxBy=fn=>[...rows].sort((a,b)=>fn(b)-fn(a))[0]; const minBy=fn=>[...rows].sort((a,b)=>fn(a)-fn(b))[0]; const bestNet=maxBy(p=>p.NetTick), worstNet=minBy(p=>p.NetTick), bestBase=maxBy(p=>p.BaseNetTick), improved=maxBy(p=>p.NetTick-p.BaseNetTick); el.innerHTML=`<div class="metric"><span>Best Adjusted Net</span><b>${bestNet.Name}</b><span>${bestNet.NetTick.toFixed(1)} CD/tick via ${esc(bestNet.Service)}</span></div><div class="metric"><span>Worst Adjusted Net</span><b>${worstNet.Name}</b><span>${worstNet.NetTick.toFixed(1)} CD/tick via ${esc(worstNet.Service)}</span></div><div class="metric"><span>Best Base Net</span><b>${bestBase.Name}</b><span>${bestBase.BaseNetTick.toFixed(1)} CD/tick</span></div><div class="metric"><span>Biggest Upgrade Swing</span><b>${improved.Name}</b><span>+${(improved.NetTick-improved.BaseNetTick).toFixed(1)} CD/tick</span></div>`; }
function formulaLabel(key){ return key.replace(/([a-z])([A-Z])/g, '$1 $2'); }
function formulas(){ const el=document.getElementById('formulaSummary'); const keys=['EffectiveHazard','HpTick','SellValue','SellTick','CostTick','NetTick','BaseNet','Service','ServiceTravel']; el.innerHTML=keys.map(k=>`<div class="metric"><span>${esc(k)}</span><b>${esc(formulaLabel(k))}</b><span>${esc(DATA.Formulas[k]||'')}</span></div>`).join(''); }
function render(){ filters(); maps(); upgradeControls(); renderTables(); formulas(); }
render();
</script>
</body>
</html>
'@

$html = $html.Replace('__GENERATED_AT__', $payload.GeneratedAt).Replace('__PAYLOAD_JSON__', $json)

Set-Content -LiteralPath $outPath -Value $html -Encoding UTF8
Write-Host "Wrote $outPath"
