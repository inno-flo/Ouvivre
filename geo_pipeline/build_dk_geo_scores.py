"""
Builds dk_geo_scores.json: for every Danish kommune, a 0-100 score for the
Géographie criteria — the Danish counterpart of france_geo_scores.json.

Le critère « montagne » est supprimé pour le Danemark (point culminant
171 m) : la clé est absente des scores.

Critères :
- mer : nombre de kommuner à traverser pour atteindre le littoral, comme
  recompute_mer_score.py — 100 si la kommune est côtière, puis 75/50/25/0.
  Côtière = une partie de son contour (> 1 km) n'est partagée ni avec une
  autre kommune ni avec une commune allemande. Contrairement à la France
  (IGN contre Natural Earth), les deux côtés viennent du même jeu GISCO
  LAU 2024, dont les limites coïncident : le calcul géométrique est fiable.
  L'adjacence entre kommuner pour les sauts vient du même jeu.
- paysEtranger : distance (km) du contour de la kommune au pays étranger le
  plus proche (Natural Earth 1:50 M, ne_50m_admin_0_countries : Allemagne,
  Suède…), comme build_france_geo_scores.py ; min-max inversé.
- lacs : part de la surface de la kommune couverte de plans d'eau
  (OpenStreetMap, couche gis_osm_water_a, fclass water et reservoir), hors
  lagunes et bras de mer listés dans SEA_WATERS ; min-max.
- fleuves : distance (km) au grand cours d'eau le plus proche, comme la
  France (où seuls les cours d'eau d'importance 1 comptent) ; min-max
  inversé. Le Danemark n'a pas de fleuve : « grand cours d'eau » = rivière
  OpenStreetMap nommée (couche gis_osm_waterways, fclass river) dont les
  tronçons connexes totalisent au moins MAJOR_RIVER_MIN_KM (les homonymes
  éloignés, comme les diverses « Nørreå », sont séparés ; une
  vingtaine : Gudenå, Skjern Å, Storå, Omme Å, Karup Å, Suså, Odense Å…).
  Une densité de rivières avait été essayée d'abord : elle faisait sortir
  en tête de petites kommuner urbaines traversées par un seul ruisseau
  classé rivière (Rødovre, Lyngby-Taarbæk). La distance est plafonnée à
  RIVER_CAP_KM avant normalisation : sans cela, Bornholm (180 km de la
  Suså) écrase l'échelle et le nord du Sjælland, à 60-80 km de tout grand
  cours d'eau, garde encore 55-65/100.
- forets : part de forêt (« Skov ») dans la surface cadastrée de la kommune,
  Danmarks Statistik, table AREALDK2, dernière année ; min-max.

Pourquoi OSM pour les lacs : AREALDK2 laisse 154 km² de grands lacs hors
cadastre sans kommune (Mossø, lacs de Silkeborg…), ce qui sous-estimait le
Jutland.

Sources et licences :
- Eurostat GISCO LAU 2024 (© EuroGeographics) — data/raw/dk, téléchargé
  par build_dk_kommuner.py ;
- Natural Earth (domaine public) — data/raw/ne_countries.json, partagé
  avec le pipeline France ;
- OpenStreetMap via Geofabrik (© contributeurs OpenStreetMap, ODbL) :
  https://download.geofabrik.de/europe/denmark-latest-free.shp.zip
  (~810 Mo, une fois) ;
- Danmarks Statistik, AREALDK2 (api.statbank.dk).

Calculs en EPSG:3035 (Lambert azimutal équivalente, Europe) : surfaces et
distances justes à l'échelle du pays.

Run: .venv/bin/python build_dk_geo_scores.py   (nécessite pyshp)
"""
import csv
import io
import json
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import requests
import shapefile
from pyproj import Transformer
from shapely.geometry import shape
from shapely.ops import transform, unary_union
from shapely.prepared import prep
from shapely.strtree import STRtree

from normalize_and_export import min_max_normalize

RAW = Path(__file__).parent / "data" / "raw"
DK_RAW = RAW / "dk"
OUT = Path(__file__).parent / "data" / "out"
GEOFABRIK_DIR = DK_RAW / "geofabrik"
GEOFABRIK_DIR.mkdir(parents=True, exist_ok=True)

LAU_PATH = DK_RAW / "LAU_RG_01M_2024_4326.geojson"
KOMMUNER_PATH = OUT / "dk_kommuner.json"
COUNTRIES_PATH = RAW / "ne_countries.json"
COUNTRIES_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson"
GEOFABRIK_URL = "https://download.geofabrik.de/europe/denmark-latest-free.shp.zip"
GEOFABRIK_PATH = GEOFABRIK_DIR / "denmark-latest-free.shp.zip"
AREALDK2 = "https://api.statbank.dk/v1/data/AREALDK2/CSV"

# Marge (m) pour considérer deux contours GISCO comme communs.
SHARED_TOLERANCE = 100
# Longueur minimale (m) de contour non partagé pour qu'une kommune soit côtière.
COAST_MIN_LENGTH = 1_000
# Score « mer » par nombre de sauts jusqu'au littoral (recompute_mer_score.py).
HOP_SCORES = [100.0, 75.0, 50.0, 25.0]
# Plans d'eau OSM « water » qui sont des lagunes ou des bras de mer.
SEA_WATERS = {"Ringkøbing Fjord", "Nissum Bredning", "Thyborøn Kanal"}
LAKE_CLASSES = {"water", "reservoir"}
# Longueur totale (km) à partir de laquelle une rivière nommée est « grande ».
MAJOR_RIVER_MIN_KM = 40
# Plafond (km) de la distance au grand cours d'eau pour la normalisation.
RIVER_CAP_KM = 80
# Écart maximal (m) entre deux tronçons d'une même rivière.
RIVER_GAP = 3_000

TO_3035 = Transformer.from_crs("EPSG:4326", "EPSG:3035", always_xy=True).transform


def project(geom):
    return transform(TO_3035, geom)


def download(url, path, timeout):
    if path.exists():
        return
    print(f"Downloading {url} ...")
    with requests.get(url, stream=True, timeout=timeout) as r:
        r.raise_for_status()
        with path.open("wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 20):
                f.write(chunk)


def osm_layer(archive, base):
    return shapefile.Reader(shp=io.BytesIO(archive.read(base + ".shp")),
                            dbf=io.BytesIO(archive.read(base + ".dbf")),
                            shx=io.BytesIO(archive.read(base + ".shx")))


def forest_shares():
    params = {"lang": "da", "valuePresentation": "Code", "OMRÅDE": "*", "ARE1": "E",
              "ENHED": "8140", "Tid": "(1)"}
    r = requests.get(AREALDK2, params=params, timeout=60)
    r.raise_for_status()
    rows = list(csv.DictReader(io.StringIO(r.content.decode("utf-8-sig")), delimiter=";"))
    year = rows[0]["TID"]
    return year, {row["OMRÅDE"].zfill(4): float(row["INDHOLD"].replace(",", ".")) for row in rows}


def coastal_and_hops(kommuner, germany):
    """(longueur de côte en m, nombre de sauts au littoral) par kommune."""
    codes = sorted(kommuner)
    tree = STRtree([kommuner[c] for c in codes] + germany)
    everything = [kommuner[c] for c in codes] + germany
    coast_length, neighbours = {}, {}
    for i, code in enumerate(codes):
        geom = kommuner[code]
        near = [j for j in tree.query(geom.buffer(SHARED_TOLERANCE)) if j != i]
        shared = unary_union([everything[j].buffer(SHARED_TOLERANCE) for j in near]) if near else None
        coast = geom.boundary.difference(shared) if shared is not None else geom.boundary
        coast_length[code] = coast.length
        neighbours[code] = {codes[j] for j in near if j < len(codes)}

    hops = {c: 0 for c in codes if coast_length[c] > COAST_MIN_LENGTH}
    frontier = list(hops)
    while frontier:
        nxt = []
        for c in frontier:
            for n in neighbours[c]:
                if n not in hops:
                    hops[n] = hops[c] + 1
                    nxt.append(n)
        frontier = nxt
    return coast_length, hops


def coverage(kommuner, geoms, measure):
    """{code: somme de `measure` (surface ou longueur) de `geoms` dans la kommune}."""
    tree = STRtree(geoms)
    out = {}
    for code, kgeom in kommuner.items():
        inside = prep(kgeom)
        total = 0.0
        for j in tree.query(kgeom):
            g = geoms[j]
            total += measure(g) if inside.contains(g) else measure(g.intersection(kgeom))
        out[code] = total
    return out


def main():
    meta = {k["code"]: k for k in json.loads(KOMMUNER_PATH.read_text(encoding="utf-8"))["kommuner"]}

    print("Loading GISCO LAU ...")
    lau = json.loads(LAU_PATH.read_text(encoding="utf-8"))
    kommuner, germany = {}, []
    for feat in lau["features"]:
        props = feat["properties"]
        if props.get("CNTR_CODE") == "DK":
            code = props["GISCO_ID"].removeprefix("DK_").zfill(4)
            if code in meta:
                kommuner[code] = project(shape(feat["geometry"]))
        elif props.get("CNTR_CODE") == "DE":
            geom = shape(feat["geometry"])
            if geom.bounds[3] > 54.5:  # communes du Schleswig, le long de la frontière
                germany.append(project(geom))
    assert set(kommuner) == set(meta), "kommuner GISCO ≠ dk_kommuner.json"

    print("Mer : littoral et sauts ...")
    coast_length, hops = coastal_and_hops(kommuner, germany)
    inland = sorted(meta[c]["nom"] for c, h in hops.items() if h > 0)
    print(f"  {sum(1 for h in hops.values() if h == 0)} kommuner côtières ; sans littoral : {inland}")
    assert set(hops) == set(kommuner), f"kommuner sans chemin vers la côte : {set(kommuner) - set(hops)}"

    print("Pays étranger : distances ...")
    download(COUNTRIES_URL, COUNTRIES_PATH, 60)
    foreign = [project(shape(f["geometry"])) for f in json.loads(COUNTRIES_PATH.read_text())["features"]
               if f["properties"]["ADM0_A3"] != "DNK" and shape(f["geometry"]).intersects(shape(
                   {"type": "Polygon", "coordinates": [[[3, 52], [20, 52], [20, 60], [3, 60], [3, 52]]]}))]
    foreign_union = unary_union(foreign)
    abroad_km = {c: g.distance(foreign_union) / 1000 for c, g in kommuner.items()}

    download(GEOFABRIK_URL, GEOFABRIK_PATH, 1800)
    archive = zipfile.ZipFile(GEOFABRIK_PATH)

    print("Lacs : plans d'eau OSM ...")
    lakes = []
    for sr in osm_layer(archive, "gis_osm_water_a_free_1").iterShapeRecords():
        if sr.record["fclass"] in LAKE_CLASSES and sr.record["name"] not in SEA_WATERS:
            geom = project(shape(sr.shape.__geo_interface__))
            lakes.append(geom if geom.is_valid else geom.buffer(0))
    lake_area = coverage(kommuner, lakes, lambda g: g.area)

    print("Fleuves : grands cours d'eau OSM ...")
    segments = {}
    for sr in osm_layer(archive, "gis_osm_waterways_free_1").iterShapeRecords():
        if sr.record["fclass"] == "river" and sr.record["name"]:
            segments.setdefault(sr.record["name"], []).append(project(shape(sr.shape.__geo_interface__)))
    # Un même nom peut désigner plusieurs rivières : on regroupe les tronçons
    # connexes (à RIVER_GAP près) et on garde les groupes assez longs.
    major = {}
    for name, lines in segments.items():
        blobs = unary_union([line.buffer(RIVER_GAP) for line in lines])
        for blob in getattr(blobs, "geoms", [blobs]):
            part = [line for line in lines if blob.intersects(line)]
            if sum(line.length for line in part) >= MAJOR_RIVER_MIN_KM * 1000:
                key = name if name not in major else f"{name} ({len([k for k in major if k.startswith(name)]) + 1})"
                major[key] = unary_union(part)
    print(f"  {len(major)} grands cours d'eau : {sorted(major)}")
    nearest_river = {}
    for c, g in kommuner.items():
        name, dist = min(((n, g.distance(line)) for n, line in major.items()), key=lambda t: t[1])
        nearest_river[c] = (name.split(" (")[0], dist / 1000)  # sans le numéro d'homonyme

    forest_year, forest_pct = forest_shares()

    area_km2 = {c: g.area / 1e6 for c, g in kommuner.items()}
    measures = {
        c: {
            "merSauts": hops[c],
            "littoralKm": round(coast_length[c] / 1000, 1),
            "lacsPct": round(lake_area[c] / 1e6 / area_km2[c] * 100, 2),
            "fleuveProche": nearest_river[c][0],
            "foretsPct": forest_pct[c],
        }
        for c in kommuner
    }
    score_abroad = min_max_normalize(list(abroad_km.values()), invert=True)
    score_lakes = min_max_normalize([m["lacsPct"] for m in measures.values()], invert=False)
    river_km = {c: nearest_river[c][1] for c in kommuner}
    capped_river_km = {c: min(km, RIVER_CAP_KM) for c, km in river_km.items()}
    score_rivers = min_max_normalize(list(capped_river_km.values()), invert=True)
    score_forests = min_max_normalize([m["foretsPct"] for m in measures.values()], invert=False)

    records = []
    for code in sorted(kommuner):
        m = measures[code]
        records.append({
            "code": code,
            "nom": meta[code]["nom"],
            "codeRegion": meta[code]["codeRegion"],
            "nomRegion": meta[code]["nomRegion"],
            "scores": {
                "paysEtranger": score_abroad(abroad_km[code]),
                "mer": HOP_SCORES[m["merSauts"]] if m["merSauts"] < len(HOP_SCORES) else 0.0,
                "fleuves": score_rivers(capped_river_km[code]),
                "lacs": score_lakes(m["lacsPct"]),
                "forets": score_forests(m["foretsPct"]),
            },
            "distancesKm": {"paysEtranger": round(abroad_km[code], 1), "fleuves": round(river_km[code], 1)},
            "mesures": m,
        })

    final = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": (f"Eurostat GISCO LAU 2024 (mer, adjacence) + Natural Earth (pays étranger) + OpenStreetMap "
                   f"via Geofabrik, ODbL (lacs, rivières) + Danmarks Statistik AREALDK2 {forest_year} (forêts) ; "
                   "critère montagne supprimé"),
        "kommuner": records,
    }
    out_path = OUT / "dk_geo_scores.json"
    out_path.write_text(json.dumps(final, ensure_ascii=False, indent=1), encoding="utf-8")

    far = sorted(records, key=lambda r: -r["distancesKm"]["fleuves"])[:5]
    print("  plus loin d'un grand cours d'eau : " + ", ".join(
        f"{r['nom']} {r['distancesKm']['fleuves']} km ({r['mesures']['fleuveProche']})" for r in far))
    for key in ("lacsPct", "foretsPct"):
        top = sorted(records, key=lambda r: -r["mesures"][key])[:4]
        print(f"  max {key} : " + ", ".join(f"{r['nom']} {r['mesures'][key]}" for r in top))
    near = sorted(records, key=lambda r: r["distancesKm"]["paysEtranger"])[:5]
    print("  plus près de l'étranger : " + ", ".join(f"{r['nom']} {r['distancesKm']['paysEtranger']} km" for r in near))
    print(f"Wrote {len(records)} kommuner to {out_path}")


if __name__ == "__main__":
    main()
