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
        Id = [string]$sys.Id
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
        ProspectFuel = "1 FL per successful prospect tick"
        Danger = "Target average HP damage per prospect tick before upgrades"
        Hazard = "Ceiling(Danger * 100 / (mean event damage * 0.75)), capped 1..100"
        HazardChance = "Floor(Effective HZ * 0.75) percent per tick, base values assume no upgrades"
        Damage = "[int][math]::Max(1, baseDamage * multiplier), baseDamage is 2..9"
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
section{margin:0 0 28px}.sectionHead{display:flex;gap:12px;align-items:end;justify-content:space-between;margin:0 0 10px}.headLeft{display:flex;align-items:center;gap:12px;flex-wrap:wrap}h2{font-size:18px;margin:0}.note{color:var(--muted);font-size:12px}.tabs{display:flex;gap:6px;flex-wrap:wrap}.tab{border:1px solid var(--line);background:var(--panel);color:var(--muted);padding:5px 9px;border-radius:6px;cursor:pointer;font-size:12px}.tab.on{background:var(--accent);border-color:var(--accent);color:var(--bg);font-weight:700}
.map{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px;overflow:hidden}.rail{position:relative;height:190px;min-width:100%}.axis{position:absolute;left:28px;right:28px;top:88px;height:2px;background:linear-gradient(90deg,var(--soft),var(--accent))}.planetMark{position:absolute;top:79px;width:18px;height:18px;transform:translateX(-9px);border-radius:50%;border:2px solid rgba(255,255,255,.6);box-shadow:0 0 14px currentColor}.planetLabel{position:absolute;width:96px;transform:translateX(-48px);text-align:center}.planetLabel.b0{top:106px}.planetLabel.a0{top:36px}.planetLabel.b1{top:142px}.planetLabel.a1{top:0}.leader{position:absolute;left:50%;width:1px;background:rgba(255,255,255,.18);transform:translateX(-.5px)}.b0 .leader{height:15px;top:-17px}.b1 .leader{height:51px;top:-53px}.a0 .leader{height:30px;bottom:-32px}.a1 .leader{height:66px;bottom:-68px}.pname{font-weight:700;font-size:12px;line-height:1.05;white-space:nowrap}.pmeta{font-size:11px;line-height:1.15;color:var(--muted)}.leg{position:absolute;top:112px;height:1px;background:rgba(255,255,255,.14)}.legText{position:absolute;top:119px;transform:translateX(-50%);font-size:10px;color:var(--muted);white-space:nowrap}.legText.tight{display:none}
.tableWrap{overflow:auto;border:1px solid var(--line);border-radius:8px;background:var(--panel)}table{width:100%;border-collapse:collapse;min-width:1280px}thead{display:table-header-group}th,td{padding:9px 10px;border-bottom:1px solid rgba(40,64,82,.72);vertical-align:top}th{background:#0d1821;color:var(--muted);font-size:11px;text-align:left;letter-spacing:.08em;text-transform:uppercase;cursor:pointer}td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}.planetCell{display:flex;align-items:center;gap:8px;font-weight:700}.miniDot{width:10px;height:10px;border-radius:50%;box-shadow:0 0 8px currentColor;flex:none}.tag{display:inline-block;border:1px solid var(--line);border-radius:5px;padding:2px 6px;color:var(--muted);font-size:11px}.tag.inh{border-color:rgba(106,183,255,.45);color:var(--blue)}.tag.trader{border-color:rgba(78,215,181,.45);color:var(--accent)}
.barStack{display:grid;gap:3px;min-width:300px}.res{display:grid;grid-template-columns:1fr 44px 150px;gap:6px;align-items:center;font-size:11px}.resName{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.barBg{height:8px;background:#253849;border-radius:99px;overflow:hidden}.bar{display:block;height:100%;border-radius:99px}.hazards{display:flex;flex-wrap:wrap;gap:4px;max-width:360px}.haz{border-radius:5px;padding:3px 6px;font-size:11px;color:#081018;font-weight:700}.stock{font-size:12px;color:var(--muted);max-width:320px}.summaryGrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:10px}.metric{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}.metric b{display:block;font-size:22px}.metric span{color:var(--muted);font-size:12px}
.traders{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:12px}.traderCard{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px}.traderCard h3{margin:0 0 6px;font-size:16px}.kv{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin:10px 0}.kv div{background:var(--panel2);border:1px solid rgba(40,64,82,.8);border-radius:6px;padding:8px}.kv b{display:block}.quest{border-top:1px solid var(--line);padding-top:8px;margin-top:8px}.questName{font-weight:700}.muted{color:var(--muted)}.small{font-size:12px}.good{color:var(--green)}.mid{color:var(--warn)}.poor,.underweight{color:var(--hot)}.deadly,.overweight{color:var(--bad)}
@media(max-width:760px){header{position:static}.wrap{padding:14px}.search{min-width:100%}.rail{min-width:860px}}
</style>
</head>
<body>
<header><h1>SpaceFRACK Guide</h1><div class="sub">Generated from live <code>Spacegame.ps1</code> data at __GENERATED_AT__. Travel cost is FL between planets, not from the star.</div></header>
<main class="wrap">
  <div class="toolbar" id="systemFilters"></div>
  <section><div class="sectionHead"><h2>System Travel Maps</h2><div class="note">Segment labels show AU gap and exact FL cost between adjacent planets.</div></div><div id="maps"></div></section>
  <section><div class="sectionHead"><div class="headLeft"><h2>Planet Table</h2><div class="tabs" id="tableTabs"></div></div><div class="note">Average DOT and CD/Tick kept from the old report, recalculated with current data.</div></div><div class="tableWrap"><table id="planetTable"></table></div></section>
  <section><div class="sectionHead"><h2>Traders And Quests</h2><div class="note">Trader economics, stock, and quest gates in one place.</div></div><div class="traders" id="traders"></div></section>
  <section><div class="sectionHead"><h2>Quick Extremes</h2><div class="note">Fast balance smell-test.</div></div><div class="summaryGrid" id="summary"></div></section>
</main>
<script id="payload" type="application/json">__PAYLOAD_JSON__</script>
<script>
const DATA = JSON.parse(document.getElementById('payload').textContent);
const state = { system: 'All', tableSystem: DATA.Systems[0]?.Id || 'All', sort: 'Distance', dir: 1, search: '' };
const colorMap = {Black:'#111',DarkBlue:'#264a99',DarkGreen:'#267a45',DarkCyan:'#2aa6a6',DarkRed:'#a83b34',DarkMagenta:'#8d4aa8',DarkYellow:'#b68b2e',Gray:'#9aa2aa',DarkGray:'#606873',Blue:'#4f8cff',Green:'#58c878',Cyan:'#5fd5e6',Red:'#ef5d5d',Magenta:'#dd72e8',Yellow:'#f0d35a',White:'#eef4ff'};
const rarityColors = {SuperCommon:'#94a3b8',Common:'#7dd3fc',Rare:'#facc15',SuperRare:'#c084fc',Consumable:'#79d879',Upgrade:'#6ab7ff'};
const pirate = new Set(['Stray projectile','EMP pulse','Orbital mine detonation','Hull breach','Gatling barrage','Missile volley','Torpedo strike']);
const allPlanets = DATA.Systems.flatMap(s => s.Planets.map((p,i,arr) => ({...p, SystemId:s.Id, SystemName:s.Name, Order:i, Prev:i?arr[i-1]:null, Next:i<arr.length-1?arr[i+1]:null})));
const money = n => Number(n||0).toLocaleString();
const fl = au => Math.ceil(Math.abs(au) / 0.1);
function psRound(n){ const f=Math.floor(n), d=n-f; if(d<.5)return f; if(d>.5)return f+1; return f % 2 === 0 ? f : f+1; }
function damageFor(mult){ let total=0; for(let base=2;base<=9;base++) total += Math.max(1, psRound(base*mult)); return total/8; }
function eventChance(p){ return Math.floor(p.Hazard * .75) / 100; }
function avgDamage(p){ const reasons = p.HazardReasons?.length ? p.HazardReasons : ['Hull stress']; return reasons.reduce((a,r)=>a+damageFor(DATA.HazardMaster[r] ?? 1),0) / reasons.length; }
function avgDot(p){ return eventChance(p) * avgDamage(p); }
function cdTick(p){ const entries = Object.entries(p.Resources || {}); return entries.reduce((a,[r,q])=>{ const master=DATA.ResourceMaster[r]||{}; if(master.Rarity==='Upgrade') return a; return a+(Number(q)/1000)*(master.Value ?? 0); },0); }
function hzClass(v){ return v>=10?'deadly':v>=3?'poor':v>=1.5?'mid':'good'; }
function planetColor(p){ return colorMap[p.PlanetColor] || '#e7edf2'; }
function resourceBars(p){ const entries=Object.entries(p.Resources||{}).sort((a,b)=>b[1]-a[1]); const total=entries.reduce((a,e)=>a+Number(e[1]),0)||1; const maxQty=Math.max(...entries.map(e=>Number(e[1])),1); const rw=Number(p.ResourceWeight||0); const pctClass=rw>1000?'overweight':rw<1000?'underweight':''; return `<div class="barStack">${entries.map(([r,q])=>{ const master=DATA.ResourceMaster[r]||{}; const pct=Number(q)/total*100; const barPct=Number(q)/maxQty*100; const color=rarityColors[master.Rarity]||'var(--accent)'; return `<div class="res"><span class="barBg"><span class="bar" style="width:${barPct}%;background:${color}"></span></span><span class="${pctClass}">${Math.round(pct)}%</span><span class="resName" title="${r}">${r} (${master.Value ?? '?'}, ${master.Weight ?? '?'})</span></div>`; }).join('')}</div>`; }
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
      seg+=`<span class="leg" style="left:${x1}px;width:${gap}px"></span><span class="legText ${gap<82?'tight':''}" style="left:${mid}px">${(b.Distance-a.Distance).toFixed(1)} AU / ${fl(b.Distance-a.Distance)} FL</span>`;
    }
    return `<div class="map" style="margin-bottom:12px"><b>${s.Name}</b><div class="rail" style="width:${railWidth}px"><div class="axis"></div>${seg}${s.Planets.map((p,i)=>`<span class="planetMark" style="left:${scale(p.Distance)}px;color:${planetColor(p)}"></span><div class="planetLabel ${slots[i]}" style="left:${scale(p.Distance)}px;color:${planetColor(p)}"><span class="leader"></span><div class="pname">${p.Name}</div><div class="pmeta">${p.Distance} AU<br>HZ ${p.Hazard}</div></div>`).join('')}</div></div>`;
  }).join('');
}
function filtered(){ return allPlanets.filter(p=>state.system==='All'||p.SystemId===state.system).filter(p=>!state.search || JSON.stringify(p).toLowerCase().includes(state.search)); }
function tableRows(){ return allPlanets.filter(p=>p.SystemId===state.tableSystem).filter(p=>!state.search || JSON.stringify(p).toLowerCase().includes(state.search)); }
function renderTableTabs(){ const el=document.getElementById('tableTabs'); el.innerHTML = DATA.Systems.map(s=>`<button class="tab ${state.tableSystem===s.Id?'on':''}" data-table-sys="${s.Id}">${s.Name}</button>`).join(''); el.querySelectorAll('button').forEach(b=>b.onclick=()=>{state.tableSystem=b.dataset.tableSys; renderTables();}); }
function renderTables(){ renderTableTabs(); const rows=tableRows().map(p=>({...p, AvgDOT:avgDot(p), AvgHit:avgDamage(p), CdTick:cdTick(p), Efficiency: cdTick(p)/Math.max(avgDot(p),.001), InCost:p.Prev?fl(p.Distance-p.Prev.Distance):0, OutCost:p.Next?fl(p.Next.Distance-p.Distance):0})); rows.sort((a,b)=>{ const av=a[state.sort], bv=b[state.sort]; return ((typeof av==='number'?av-bv:String(av).localeCompare(String(bv))) || a.Distance-b.Distance) * state.dir; }); const table=document.getElementById('planetTable'); const heads=[['Name','Planet'],['Type','Type'],['Distance','AU'],['InCost','Prev FL'],['OutCost','Next FL'],['Danger','Danger'],['Hazard','HZ'],['AvgHit','Avg Hit'],['AvgDOT','Avg DOT'],['CdTick','CD/Tick'],['Efficiency','CD:HP'],['Resources','Resources'],['Hazards','Hazards'],['Flags','Flags']]; table.innerHTML=`<thead><tr>${heads.map(([k,l])=>`<th class="${['Distance','InCost','OutCost','Danger','Hazard','AvgHit','AvgDOT','CdTick','Efficiency'].includes(k)?'num':''}" data-sort="${k}">${l}${state.sort===k?(state.dir>0?' ^':' v'):''}</th>`).join('')}</tr></thead><tbody>${rows.map(p=>{ const rw=Number(p.ResourceWeight||0); const rwClass=rw>1000?'overweight':rw<1000?'underweight':'muted'; return `<tr><td><div class="planetCell"><span class="miniDot" style="background:${planetColor(p)};color:${planetColor(p)}"></span>${p.Name}</div><div class="muted small">${p.Description||''}</div><div class="${rwClass} small">${rw}/1000</div></td><td>${p.Type}</td><td class="num">${p.Distance.toFixed(1)}</td><td class="num">${p.InCost||'Start'}</td><td class="num">${p.OutCost||'End'}</td><td class="num">${Number(p.Danger).toFixed(1)}</td><td class="num">${p.Hazard}</td><td class="num">${p.AvgHit.toFixed(1)}</td><td class="num ${avgDot(p)>=4?'deadly':avgDot(p)>=2?'poor':avgDot(p)>=1?'mid':'good'}">${p.AvgDOT.toFixed(2)}</td><td class="num">${p.CdTick.toFixed(1)}</td><td class="num ${p.Efficiency>=40?'good':p.Efficiency>=20?'mid':'poor'}">${p.Efficiency.toFixed(1)}</td><td>${resourceBars(p)}</td><td>${hazardTags(p)}</td><td>${p.Inhabited?'<span class="tag inh">Inhabited</span> ':''}${p.TraderName?'<span class="tag trader">Trader</span>':''}</td></tr>`}).join('')}</tbody>`; table.querySelectorAll('th[data-sort]').forEach(th=>th.onclick=()=>{const k=th.dataset.sort; state.dir=state.sort===k?-state.dir:1; state.sort=k; renderTables();}); summary(rows); traders(); }
function traders(){ const el=document.getElementById('traders'); const planets=filtered().filter(p=>p.TraderName); el.innerHTML=planets.map(p=>`<article class="traderCard"><h3>${p.TraderName}</h3><div class="muted">${p.Name}, ${p.SystemName}</div><div class="kv"><div><span class="muted small">Credits</span><b>${money(p.TotalTraderCredits)} CD</b></div><div><span class="muted small">Fuel price</span><b>x${p.FuelModifier}</b></div><div><span class="muted small">Repair price</span><b>x${p.RepairModifier}</b></div></div><div class="stock"><b>Stock</b>${Object.entries(p.TraderStock||{}).map(([i,q])=>`${i} (${q})`).join(', ')}</div>${(p.Quests||[]).map(q=>`<div class="quest"><div class="questName">${q.Name} <span class="muted">REP ${q.RepReq}</span></div><div class="small muted">Needs: ${(q.Requirements||[]).map(r=>`${r.Qty} ${r.Item}`).join(', ') || 'None'}</div><div class="small muted">Pays: ${money(q.RewardCD)} CD${q.RewardItems?.length ? ' + '+q.RewardItems.map(r=>`${r.Qty} ${r.Item}`).join(', ') : ''}</div></div>`).join('')}</article>`).join('') || '<div class="muted">No traders in current filter.</div>'; }
function summary(rows){ const el=document.getElementById('summary'); if(!rows.length){el.innerHTML='';return;} const by=(fn,dir=1)=>[...rows].sort((a,b)=>dir*(fn(b)-fn(a)))[0]; const rich=by(p=>p.CdTick), lethal=by(p=>p.AvgDOT), efficient=by(p=>p.Efficiency), long=by(p=>p.Distance); el.innerHTML=`<div class="metric"><span>Best CD/Tick</span><b>${rich.Name}</b><span>${rich.CdTick.toFixed(1)} CD/tick</span></div><div class="metric"><span>Highest Average DOT</span><b>${lethal.Name}</b><span>${lethal.AvgDOT.toFixed(2)} HP/tick</span></div><div class="metric"><span>Best CD:HP</span><b>${efficient.Name}</b><span>${efficient.Efficiency.toFixed(1)} CD per HP</span></div><div class="metric"><span>Outermost Route Endpoint</span><b>${long.Name}</b><span>${long.Distance.toFixed(1)} AU from star</span></div>`; }
function render(){ filters(); maps(); renderTables(); }
render();
</script>
</body>
</html>
'@

$html = $html.Replace('__GENERATED_AT__', $payload.GeneratedAt).Replace('__PAYLOAD_JSON__', $json)

Set-Content -LiteralPath $outPath -Value $html -Encoding UTF8
Write-Host "Wrote $outPath"
