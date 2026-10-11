#!/usr/bin/env bash
# Rebuilds the battle map's snapshot of every contact on file: name, faction,
# role, tier, size, the core stats and a thumbnail, taken from the archive
# (index.html) through headless Chrome, the same way tools/chart-contacts.sh
# does for the star chart. Run it again whenever contacts are added to the
# archive's baked data, then commit battlemap.html. Sheets saved through the
# page's editor are picked up live and need no rebuild.
#
#   tools/battle-contacts.sh
set -e
cd "$(dirname "$0")/.."
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
TMP="$(mktemp -d)"
{
  echo '<script>try{localStorage.setItem("overseer.intro","1");}catch(e){} window.fetch=async function(){return new Response("[]",{status:200,headers:{"Content-Type":"application/json"}});};</script>'
  perl -0pe 's~  initAccounts\(\);\n~  initAccounts();\n  window.__snap = function () { var out = {}; DATA.forEach(function (d) { var st = d.stats || {}; out[d.name] = { faction: (FACTIONS[d.faction] || {}).name || d.faction, role: d.role || "", tier: d.tier || "", size: d.size, hp: st.hp, armor: st.armor, speed: st.speed, evade: st.evade, edef: st.edef, icon: iconOf(d.name) || stillOf(d.name) || null }; }); return out; };\n~' index.html
  echo "<script>window.addEventListener('load',function(){setTimeout(async function(){ var p=document.createElement('pre'); p.id='SNAP'; try { var snap=window.__snap(); /* portraits are shrunk to small square thumbnails so the page stays light */ for (var k in snap) { var src=snap[k].icon; if (!src || src.indexOf('data:')!==0) continue; snap[k].icon = await new Promise(function(res){ var im=new Image(); im.onload=function(){ var S=128, c=document.createElement('canvas'); c.width=S; c.height=S; var s=Math.max(S/im.width,S/im.height), w=im.width*s, h=im.height*s; c.getContext('2d').drawImage(im,(S-w)/2,(S-h)/2,w,h); res(c.toDataURL('image/webp',0.8)); }; im.onerror=function(){res(null);}; im.src=src; }); } p.textContent=JSON.stringify(snap); } catch(e) { p.textContent='ERR '+e.message; } document.body.appendChild(p); },1500);});</script>"
} > "$TMP/snap.html"
"$CHROME" --headless=new --disable-gpu --no-sandbox --window-size=1280,900 --virtual-time-budget=20000 --dump-dom "file:///$(cygpath -w "$TMP/snap.html" 2>/dev/null || echo "$TMP/snap.html")" 2>/dev/null > "$TMP/dom.html"
perl -0ne 'if (/<pre id="SNAP">(.*?)<\/pre>/s) { my $t = $1; $t =~ s/&gt;/>/g; $t =~ s/&lt;/</g; $t =~ s/&quot;/"/g; $t =~ s/&amp;/&/g; print $t; }' "$TMP/dom.html" > "$TMP/snap.json"
if ! grep -q '^{' "$TMP/snap.json"; then echo "snapshot failed: $(head -c 200 "$TMP/snap.json")"; exit 1; fi
echo "  var BATTLE_CONTACTS = $(cat "$TMP/snap.json");" > "$TMP/line.txt"
n=$(grep -n '^  var BATTLE_CONTACTS = ' battlemap.html | cut -d: -f1)
{ head -n $((n-1)) battlemap.html; cat "$TMP/line.txt"; tail -n +$((n+1)) battlemap.html; } > "$TMP/bm.html"
mv "$TMP/bm.html" battlemap.html
echo "snapshot of $(grep -o '"[^"]*":{"faction"' "$TMP/snap.json" | wc -l) contacts written into battlemap.html ($(wc -c < "$TMP/snap.json") bytes)"
rm -rf "$TMP"
