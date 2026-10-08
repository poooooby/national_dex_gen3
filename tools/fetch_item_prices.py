"""
Fetch each evolution item's price table from Bulbapedia (its MediaWiki API, with
a descriptive user agent as its policy asks) into tools/item_prices.json.

The shop price tools/build_items.py gives each item is derived from this: twice
the sell price of the earliest game that lists one (a shop buys at half what it
sells for), or the classic stone price of 2100 when the wiki has none. The
table text is CC BY-NC-SA, so CREDITS.md credits Bulbapedia; only numbers are
kept here.

Usage:
    python tools/fetch_item_prices.py
"""
import json, re, sys, time, urllib.request, urllib.parse
from pathlib import Path
UA = "national_dex_gen3-research/1.0 (https://github.com/poooooby/national_dex_gen3)"
titles = {
 "dawn-stone":"Dawn Stone","dubious-disc":"Dubious Disc","dusk-stone":"Dusk Stone","electirizer":"Electirizer",
 "ice-stone":"Ice Stone","magmarizer":"Magmarizer","protector":"Protector","reaper-cloth":"Reaper Cloth",
 "sachet":"Sachet","shiny-stone":"Shiny Stone","sweet-apple":"Sweet Apple","tart-apple":"Tart Apple",
 "whipped-dream":"Whipped Dream","auspicious-armor":"Auspicious Armor","black-augurite":"Black Augurite",
 "malicious-armor":"Malicious Armor","metal-alloy":"Metal Alloy","peat-block":"Peat Block","syrupy-apple":"Syrupy Apple"}
out = {}
for slug, title in titles.items():
    url = "https://bulbapedia.bulbagarden.net/w/api.php?" + urllib.parse.urlencode(
        {"action":"query","prop":"revisions","rvprop":"content","rvslots":"main","titles":title,"format":"json","formatversion":"2","redirects":"1"})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        d = json.load(urllib.request.urlopen(req, timeout=30))
        text = d["query"]["pages"][0]["revisions"][0]["slots"]["main"]["content"]
    except Exception as e:
        out[slug] = {"error": str(e)}; continue
    # the price rows: |{{gameabbrev..}} ... |buy|sell}}
    rows = re.findall(r"Price\|([^\n]*?)\|(N/A|\{\{PDollar\}\}[\d,]+)\|(N/A|\{\{PDollar\}\}[\d,]+)\}\}", text)
    parsed = []
    for games, buy, sell in rows:
        g = re.findall(r"\{\{gameabbrev\d?\|([A-Za-z0-9]+)\}\}", games)
        num = lambda v: None if v == "N/A" else int(re.sub(r"\D", "", v))
        parsed.append({"games": g, "buy": num(buy), "sell": num(sell)})
    out[slug] = {"title": title, "prices": parsed}
    time.sleep(1.0)   # be polite to the wiki
dest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / "item_prices.json"
dest.write_text(json.dumps(out, indent=1) + chr(10), encoding="utf-8")
for slug, v in out.items():
    print(slug, v.get("error") or [(",".join(p["games"]), p["buy"], p["sell"]) for p in v["prices"]])
