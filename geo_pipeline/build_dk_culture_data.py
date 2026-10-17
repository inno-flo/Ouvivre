"""
Builds dk_culture_scores.json: per-kommune 0-100 scores for Musées et Lieux
du patrimoine — the Danish counterpart of culture_scores.json, same
structure (keyed by kommune code instead of département code).

Le critère Festivals est masqué pour le Danemark : aucune base ouverte
nationale. Wikidata n'en recense que ~140, dont 90 localisables, surtout à
Copenhague (contre 7 245 pour la France) — trop partiel pour un score. À
réactiver si une source apparaît (piste : même requête Wikidata que les
musées, classe Q132241 « festival »).

Sources :
- Musées : Wikidata (CC0), éléments « musée » (Q33506 et sous-classes) au
  Danemark, avec coordonnées, hors musées fermés (P576 dissolution, P3999
  fermeture) — interrogé via le miroir QLever
  (https://qlever.dev/api/wikidata), le point SPARQL de Wikimedia limitant
  fortement les requêtes. Nom danois (anglais à défaut) et site officiel
  (P856) pour l'inspecteur.
- Lieux du patrimoine : Slots- og Kulturstyrelsen, registre FBB des
  bâtiments classés (« fredede bygninger »), service de téléchargement
  INSPIRE : https://www.kulturarv.dk/fbb/inspire/FrededeBygninger.gml.gz
  (données géographiques libres, sans condition). Une entité = un bâtiment,
  comme la table DST KFRED1 ; le total par région est comparé à KFRED1 à
  titre de contrôle. Le fichier INSPIRE ne porte pas les noms des
  bâtiments : la liste « names.patrimoine » reste vide.
  Coordonnées en EPSG:4936 (ETRS89 géocentrique) réduites à X, Y : la
  longitude vaut atan2(Y, X), la latitude se déduit de √(X² + Y²) sur
  l'ellipsoïde GRS80 en supposant une hauteur nulle (erreur < 50 m).

Rattachement à la kommune par point dans le contour
(dk_kommuner_boundaries.json ; lancer build_dk_kommuner.py d'abord), ou à
la kommune la plus proche à moins de 2 km pour un point sur la côte que le
contour généralisé au 1:1 M laisse en mer. Les points hors du Danemark
(Féroé, Groenland, que Wikidata rattache aussi au pays Danemark) sont
ignorés.

Méthode : décompte brut par kommune puis normalisation min-max sur les 98
kommuner (0 = minimum, 100 = maximum), comme build_culture_data.py.

Run: .venv/bin/python build_dk_culture_data.py
"""
import gzip
import json
import math
import re
from datetime import datetime, timezone
from pathlib import Path

import requests
from shapely.geometry import Point, shape
from shapely.prepared import prep

RAW = Path(__file__).parent / "data" / "raw" / "dk"
OUT = Path(__file__).parent / "data" / "out"
FBB_DIR = RAW / "fbb"
FBB_DIR.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

KOMMUNER_PATH = OUT / "dk_kommuner.json"
BOUNDARIES_PATH = OUT / "dk_kommuner_boundaries.json"

QLEVER = "https://qlever.dev/api/wikidata"
FBB_URL = "https://www.kulturarv.dk/fbb/inspire/FrededeBygninger.gml.gz"
FBB_PATH = FBB_DIR / "FrededeBygninger.gml.gz"
KFRED1 = "https://api.statbank.dk/v1/data/KFRED1/CSV"

# Distance maximale (degrés, ~2 km) pour rattacher un point côtier.
COAST_TOLERANCE = 0.02
# GRS80 (ETRS89).
A = 6_378_137.0
E2 = 0.006694380022900787

MUSEUMS_QUERY = """
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?m ?da ?en ?coord ?site WHERE {
  ?m wdt:P31/wdt:P279* wd:Q33506 .
  ?m wdt:P17 wd:Q35 .
  ?m wdt:P625 ?coord .
  FILTER NOT EXISTS { ?m wdt:P576 ?dissolved }
  FILTER NOT EXISTS { ?m wdt:P3999 ?closed }
  OPTIONAL { ?m rdfs:label ?da FILTER(LANG(?da) = "da") }
  OPTIONAL { ?m rdfs:label ?en FILTER(LANG(?en) = "en") }
  OPTIONAL { ?m wdt:P856 ?site }
}
"""


def min_max(values):
    lo, hi = min(values.values()), max(values.values())
    span = hi - lo
    return {k: (round((v - lo) / span * 100.0, 1) if span else 50.0) for k, v in values.items()}


def fetch_museums():
    print("Querying Wikidata (QLever) for museums ...")
    r = requests.post(QLEVER, data={"query": MUSEUMS_QUERY},
                      headers={"Accept": "application/sparql-results+json"}, timeout=180)
    r.raise_for_status()
    museums = {}
    for b in r.json()["results"]["bindings"]:
        qid = b["m"]["value"].rsplit("/", 1)[-1]
        name = (b.get("da") or b.get("en") or {}).get("value")
        match = re.match(r"point\(([-\d.]+) ([-\d.]+)\)", b["coord"]["value"], re.IGNORECASE)
        if not name or not match:
            continue
        entry = museums.setdefault(qid, {"name": name, "lon": float(match[1]), "lat": float(match[2]), "url": None})
        if "site" in b and not entry["url"]:
            entry["url"] = b["site"]["value"]
    return list(museums.values())


def ecef_xy_to_latlon(x, y):
    """Latitude, longitude (degrés) d'un point ETRS89 géocentrique dont seuls
    X et Y sont connus, en supposant une hauteur ellipsoïdale nulle."""
    lon = math.atan2(y, x)
    p = math.hypot(x, y)
    lat = math.acos(min(1.0, p / A))
    for _ in range(10):  # p = N(φ)·cos φ, N(φ) = a / √(1 − e² sin² φ)
        n = A / math.sqrt(1 - E2 * math.sin(lat) ** 2)
        lat = math.acos(min(1.0, p / n))
    return math.degrees(lat), math.degrees(lon)


def fetch_fbb():
    if not FBB_PATH.exists():
        print(f"Downloading {FBB_URL} ...")
        r = requests.get(FBB_URL, timeout=300)
        r.raise_for_status()
        FBB_PATH.write_bytes(r.content)
    with gzip.open(FBB_PATH, "rt", encoding="utf-8") as f:
        text = f.read()
    points = []
    for x, y in re.findall(r"<gml:pos[^>]*>([-\d.]+) ([-\d.]+)</gml:pos>", text):
        points.append(ecef_xy_to_latlon(float(x), float(y)))
    return points


def fetch_kfred1():
    params = {"lang": "da", "valuePresentation": "Code", "OMRÅDE": "*", "BYGTYP": "000",
              "OPFØRELSESÅR": "0000", "Tid": "(1)"}
    r = requests.get(KFRED1, params=params, timeout=60)
    r.raise_for_status()
    rows = [line.split(";") for line in r.content.decode("utf-8-sig").splitlines()[1:]]
    return rows[0][3], {code: int(value) for code, _, _, _, value in rows}


def main():
    kommuner = {k["code"]: k for k in json.loads(KOMMUNER_PATH.read_text(encoding="utf-8"))["kommuner"]}
    outlines = {b["code"]: shape(b["geometry"]) for b in json.loads(BOUNDARIES_PATH.read_text(encoding="utf-8"))}
    inside = {code: prep(geom) for code, geom in outlines.items()}

    def kommune_of(lat, lon):
        point = Point(lon, lat)
        for code, geom in inside.items():
            if geom.contains(point):
                return code
        code, distance = min(((c, g.distance(point)) for c, g in outlines.items()), key=lambda t: t[1])
        return code if distance <= COAST_TOLERANCE else None

    museums = fetch_museums()
    museum_names = {code: [] for code in kommuner}
    museum_urls = {code: {} for code in kommuner}
    outside = 0
    for m in museums:
        code = kommune_of(m["lat"], m["lon"])
        if code is None:
            outside += 1
            continue
        museum_names[code].append(m["name"])
        if m["url"]:
            museum_urls[code][m["name"]] = m["url"]
    print(f"Musées : {len(museums)} sur Wikidata, {len(museums) - outside} au Danemark ({outside} hors kommuner)")

    buildings = fetch_fbb()
    heritage = {code: 0 for code in kommuner}
    lost = 0
    for lat, lon in buildings:
        code = kommune_of(lat, lon)
        if code is None:
            lost += 1
        else:
            heritage[code] += 1
    print(f"Bâtiments classés : {len(buildings)} dans FBB, {lost} hors kommuner")
    assert lost <= len(buildings) * 0.01, "trop de bâtiments FBB hors kommuner : conversion de coordonnées ?"

    # Contrôle : total par région (découpage DST avant 2027) face à KFRED1.
    kfred_year, kfred = fetch_kfred1()
    by_region = {}
    for code, n in heritage.items():
        region = kommuner[code]["codeRegion"]
        by_region[region] = by_region.get(region, 0) + n
    east = kfred.get("084", 0) + kfred.get("085", 0)
    print(f"Contrôle KFRED1 {kfred_year} (bâtiments) : Danemark {kfred['000']} vs FBB {sum(heritage.values())} ; "
          f"Østdanmark {east} vs {by_region.get('1086')}, Syddanmark {kfred['083']} vs {by_region.get('1083')}, "
          f"Midtjylland {kfred['082']} vs {by_region.get('1082')}, Nordjylland {kfred['081']} vs {by_region.get('1081')}")

    museum_counts = {code: len(names) for code, names in museum_names.items()}
    museum_scores = min_max(museum_counts)
    heritage_scores = min_max(heritage)

    records = []
    for code in sorted(kommuner):
        records.append({
            "code": code,
            "nom": kommuner[code]["nom"],
            "scores": {"musees": museum_scores[code], "patrimoine": heritage_scores[code]},
            "counts": {"musees": museum_counts[code], "patrimoine": heritage[code]},
            "names": {"musees": sorted(museum_names[code], key=str.casefold), "patrimoine": []},
            "urls": {"musees": museum_urls[code]},
            "disciplines": {},
        })

    final = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": ("Wikidata (CC0, via QLever) pour les musées ; Slots- og Kulturstyrelsen, registre FBB "
                   "(INSPIRE FrededeBygninger) pour les bâtiments classés ; festivals masqués (pas de source)"),
        "kommuner": records,
    }
    out_path = OUT / "dk_culture_scores.json"
    out_path.write_text(json.dumps(final, ensure_ascii=False, indent=1), encoding="utf-8")
    top = sorted(records, key=lambda r: -r["counts"]["musees"])[:5]
    print("Plus de musées : " + ", ".join(f"{r['nom']} {r['counts']['musees']}" for r in top))
    top = sorted(records, key=lambda r: -r["counts"]["patrimoine"])[:5]
    print("Plus de bâtiments classés : " + ", ".join(f"{r['nom']} {r['counts']['patrimoine']}" for r in top))
    print(f"Wrote {len(records)} kommuner to {out_path}")


if __name__ == "__main__":
    main()
