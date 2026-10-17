"""
Builds dk_byer_data.json: population, superficie, densité, catégorie de
taille et coordonnées des ~1 600 byer danoises — l'équivalent danois de
communes_data.json.

Le « by » n'est pas une collectivité mais une agglomération statistique
définie par Danmarks Statistik (bâti continu, ≥ 200 habitants). Une by à
cheval sur plusieurs kommuner (« del af flere kommuner », et
Hovedstadsområdet, l'agglomération de Copenhague, découpée en 18 kommuner)
a une ligne par kommune : on garde ce découpage, chaque partie est rattachée
à sa kommune comme une commune à son département. Le reste de chaque
kommune (« Landdistrikter », zone rurale) n'a pas de point : il est exporté
à part, par kommune.

Sources :
- Danmarks Statistik, table BY3 (population au 1er janvier, superficie et
  densité par by et landdistrikt), dernière année — API
  https://api.statbank.dk/v1/, sans clé, réutilisation libre avec citation
  (« Danmarks Statistik, BY3 »).
- Coordonnées : GeoNames, extrait par pays
  https://download.geonames.org/export/dump/DK.zip (CC BY 4.0), lieux de
  classe P (PPL, PPLA2, PPLX…). DST ne publie pas de coordonnées.
- Contours des kommuner : data/out/dk_kommuner_boundaries.json (lancer
  build_dk_kommuner.py d'abord).

Rapprochement by ↔ GeoNames, par nom normalisé (casse, æ/ø/å ↔ ae/oe/aa,
ponctuation), sur le nom principal et les noms alternatifs GeoNames, dans
cet ordre :
1. lieux de la même kommune (code admin2 GeoNames = kommunekode, ou point
   dans le contour de la kommune) ;
2. pour une by partagée entre kommuner, lieux à moins de 10 km du contour ;
3. noms composés « A-B » (villes jumelles) : même recherche sur chaque
   partie ;
4. nom approché : sans les qualificatifs de quartier ou d'extension
   (« Ishøj Landsby », « Annisse Nord », « Gammel Kalvehave »…), on prend le
   village de base, dans la même kommune — à quelques centaines de mètres
   près.
Les abréviations courantes (Skt., Gl., Nr., Sdr., St., Ll.) sont développées
des deux côtés. ALIASES couvre les cas restants connus, dont les parties de
Hovedstadsområdet qui portent le nom de leur kommune sans ville de ce nom
(Rudersdal → Holte, Furesø → Hareskovby).
Homonymes départagés par type (PPLA2 d'abord, PPLX en dernier), puis
population GeoNames. Une partie de by dont le point GeoNames tombe hors de
sa kommune (la ville est centrée chez le voisin) est ramenée au point le
plus proche du contour de sa kommune. Ces positions ramenées et les noms
approchés sont marqués `approx: true`. Les byer non rapprochées gardent lat/lon à null et
sont listées en sortie.

Seuils de catégorie identiques à build_communes_data.py et
CommuneSizeCategory.category(forPopulation:).

Run: .venv/bin/python build_dk_byer_data.py
"""
import csv
import io
import json
import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import requests
from shapely.geometry import Point, shape
from shapely.ops import nearest_points
from shapely.prepared import prep

RAW = Path(__file__).parent / "data" / "raw" / "dk"
OUT = Path(__file__).parent / "data" / "out"
GEONAMES_DIR = RAW / "geonames"
GEONAMES_DIR.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

STATBANK = "https://api.statbank.dk/v1/data"
GEONAMES_URL = "https://download.geonames.org/export/dump/DK.zip"
GEONAMES_ZIP = GEONAMES_DIR / "DK.zip"
KOMMUNER_PATH = OUT / "dk_kommuner.json"
BOUNDARIES_PATH = OUT / "dk_kommuner_boundaries.json"

LANDDISTRIKT = "99999"
UDEN_FAST_BOPAEL = "99997"
# Distance maximale au contour pour une by partagée entre kommuner (degrés,
# ~10 km en latitude ; suffisant à la latitude du Danemark).
SHARED_TOWN_BUFFER = 0.09
# Abréviations développées dans les noms normalisés (DST et GeoNames).
ABBREVIATIONS = {"skt": "sankt", "sct": "sankt", "gl": "gammel", "nr": "noerre",
                 "sdr": "soender", "st": "store", "ll": "lille", "oe": "oester"}
# Qualificatifs retirés pour le rapprochement approché (en fin, puis en tête).
TRAILING_QUALIFIERS = {"nord", "syd", "oest", "vest", "landsby", "stationsby", "kirkeby",
                       "villaby", "skovby", "bakkeby", "sommerby", "by", "strand", "strandhuse",
                       "sydstrand", "nordstrand", "huse", "sydmark", "mark", "lyng", "fed",
                       "bakker", "plantage"}
LEADING_QUALIFIERS = {"gammel", "ny"}
# Noms DST → nom GeoNames, par kommune.
ALIASES = {
    ("0230", "Rudersdal"): "Holte",
    ("0190", "Furesø"): "Hareskovby",
    ("0306", "Nykøbing S"): "Nykøbing Sjælland",
}
# Ordre de préférence des types GeoNames (les autres viennent ensuite).
FEATURE_RANK = {"PPLC": 0, "PPLA": 0, "PPLA2": 1, "PPL": 2, "PPLL": 3, "PPLX": 4}


def category(population):
    if population < 2_000:
        return "village"
    if population < 20_000:
        return "petiteVille"
    if population < 100_000:
        return "villeMoyenne"
    return "grandeVille"


def normalize(name):
    s = name.casefold().replace("æ", "ae").replace("ø", "oe").replace("å", "aa")
    s = s.replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("é", "e")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return " ".join(ABBREVIATIONS.get(t, t) for t in s.split())


def approximate(name):
    """Nom sans qualificatifs (« ishoej landsby » → « ishoej »), ou None."""
    tokens = normalize(name).split()
    while len(tokens) > 1 and tokens[-1] in TRAILING_QUALIFIERS:
        tokens.pop()
    while len(tokens) > 1 and tokens[0] in LEADING_QUALIFIERS:
        tokens.pop(0)
    approx = " ".join(tokens)
    return approx if approx != normalize(name) else None


def download_by3():
    url = f"{STATBANK}/BY3/CSV"
    params = {"lang": "da", "valuePresentation": "CodeAndValue", "BYER": "*", "FOLKARTAET": "*", "Tid": "(1)"}
    print("Downloading BY3 ...")
    r = requests.get(url, params=params, timeout=300)
    r.raise_for_status()
    rows = {}
    period = None
    for row in csv.DictReader(io.StringIO(r.content.decode("utf-8-sig")), delimiter=";"):
        code, _, label = row["BYER"].partition(" ")
        measure = row["FOLKARTAET"].split(" ")[0]
        period = row["TID"].split(" ")[0]
        entry = rows.setdefault(code, {"label": label})
        if row["INDHOLD"].strip() != "..":  # « .. » : valeur non publiée
            entry[measure] = float(row["INDHOLD"].replace(",", "."))
    return rows, period


def load_geonames():
    if not GEONAMES_ZIP.exists():
        print(f"Downloading {GEONAMES_URL} ...")
        r = requests.get(GEONAMES_URL, timeout=120)
        r.raise_for_status()
        GEONAMES_ZIP.write_bytes(r.content)
    places = []
    with zipfile.ZipFile(GEONAMES_ZIP) as z, z.open("DK.txt") as f:
        for line in io.TextIOWrapper(f, encoding="utf-8"):
            c = line.rstrip("\n").split("\t")
            if c[6] != "P":
                continue
            names = {normalize(c[1]), normalize(c[2])}
            names |= {normalize(a) for a in c[3].split(",") if a}
            names.discard("")
            places.append({
                "names": names,
                "lat": float(c[4]),
                "lon": float(c[5]),
                "point": Point(float(c[5]), float(c[4])),
                "feature": c[7],
                "kommune": c[11].zfill(4) if c[11] else None,
                "population": int(c[14] or 0),
            })
    return places


def best(candidates):
    return min(candidates, key=lambda p: (FEATURE_RANK.get(p["feature"], 5), -p["population"]))


def main():
    kommuner = {k["code"]: k for k in json.loads(KOMMUNER_PATH.read_text(encoding="utf-8"))["kommuner"]}
    outlines = {b["code"]: shape(b["geometry"]) for b in json.loads(BOUNDARIES_PATH.read_text(encoding="utf-8"))}
    inside = {code: prep(geom) for code, geom in outlines.items()}
    near = {code: prep(geom.buffer(SHARED_TOWN_BUFFER)) for code, geom in outlines.items()}

    places = load_geonames()
    by_name = {}
    for p in places:
        for n in p["names"]:
            by_name.setdefault(n, []).append(p)

    def lookup(name, kommune, shared, normalized=False):
        candidates = by_name.get(name if normalized else normalize(name), [])
        local = [p for p in candidates if p["kommune"] == kommune or inside[kommune].contains(p["point"])]
        if local:
            return best(local), "kommune"
        if shared:
            nearby = [p for p in candidates if near[kommune].contains(p["point"])]
            if nearby:
                return best(nearby), "voisinage"
        return None, None

    rows, period = download_by3()

    byer, landdistrikter, unmatched = [], {}, []
    stats = {"kommune": 0, "voisinage": 0, "nom composé": 0, "nom approché": 0}
    empty = 0
    without_address = 0
    for code, row in rows.items():
        kommune = code[:3].zfill(4)
        bykode = code[3:]
        population = int(row.get("FOLKETAL", 0))
        if kommune not in kommuner:
            continue  # 0000 : agrégat Hovedstadsområdet (valeurs nulles)
        if bykode == UDEN_FAST_BOPAEL:
            without_address += population
            continue
        area = row.get("AREAL", 0.0)
        if bykode == LANDDISTRIKT:
            landdistrikter[kommune] = {
                "population": population,
                "superficieKm2": round(area, 1),
                "densite": round(population / area) if area else 0,
            }
            continue
        if population == 0:
            empty += 1
            continue  # partie d'agglomération sans habitant dans cette kommune

        label = row["label"].split(" ", 1)[1]
        shared = "(del af" in label
        name = re.sub(r"\s*\(del af[^)]*\)", "", label).strip()

        place, how = lookup(ALIASES.get((kommune, name), name), kommune, shared)
        if place is None and "-" in name:
            for part in name.split("-"):
                place, _ = lookup(part, kommune, shared)
                if place:
                    how = "nom composé"
                    break
        if place is None and approximate(name):
            place, _ = lookup(approximate(name), kommune, False, normalized=True)
            how = "nom approché"
        lat = lon = None
        approx = how == "nom approché"
        if place:
            stats[how] += 1
            point = place["point"]
            if not inside[kommune].contains(point):
                point = nearest_points(outlines[kommune], point)[0]
                approx = True
            lat, lon = round(point.y, 5), round(point.x, 5)
        else:
            unmatched.append((kommune, name, population))

        byer.append({
            "code": f"{kommune}-{bykode}",
            "name": name,
            "kommuneCode": kommune,
            "population": population,
            "superficieKm2": round(area, 2),
            "densite": round(row.get("BEFTAET", 0.0)),
            "category": category(population),
            "lat": lat,
            "lon": lon,
            **({"approx": True} if approx else {}),
        })

    byer.sort(key=lambda b: b["code"])

    # Contrôle : byer + landdistrikter + sans adresse = population BY3 des kommuner.
    total = sum(b["population"] for b in byer) + sum(l["population"] for l in landdistrikter.values()) + without_address
    expected = sum(int(r.get("FOLKETAL", 0)) for c, r in rows.items() if c[:3].zfill(4) in kommuner)
    assert total == expected, f"{total} ≠ {expected}"
    assert set(landdistrikter) == set(kommuner), "landdistrikt manquant"

    final = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": f"Danmarks Statistik — BY3 (1er janvier {period}), api.statbank.dk ; coordonnées GeoNames (CC BY 4.0)",
        "byer": byer,
        "landdistrikter": dict(sorted(landdistrikter.items())),
        "sansAdresseFixe": without_address,
    }
    out_path = OUT / "dk_byer_data.json"
    out_path.write_text(json.dumps(final, ensure_ascii=False), encoding="utf-8")

    located = sum(1 for b in byer if b["lat"] is not None)
    located_pop = sum(b["population"] for b in byer if b["lat"] is not None)
    print(f"BY3 {period} : {len(byer)} byer, {located} localisées ({stats}), "
          f"{located_pop / sum(b['population'] for b in byer):.1%} de la population urbaine")
    print(f"Positions approchées (nom approché ou ramenées dans la kommune) : {sum(1 for b in byer if b.get('approx'))}")
    print(f"Lignes BY3 sans habitant ignorées : {empty}")
    print(f"Non rapprochées ({len(unmatched)}) :")
    for kommune, name, population in sorted(unmatched, key=lambda u: -u[2]):
        print(f"  {kommune} {kommuner[kommune]['nom']:<18} {name} ({population})")
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
