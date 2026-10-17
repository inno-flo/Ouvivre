"""
Builds the Danish equivalent of the département layer: the 98 kommuner and
the 4 regioner of 1 January 2027, with population, area, density and
simplified outlines.

Danemark ↔ France : kommune ≈ département (98 / 101), region ≈ région.
Le découpage régional retenu est celui du 1er janvier 2027 (réforme de la
santé de 2024) : Region Hovedstaden et Region Sjælland fusionnent en Region
Østdanmark (code 1086, registres DST) ; Nordjylland, Midtjylland et
Syddanmark ne changent pas. Les kommuner ne changent pas. Les sources
publient encore 5 régions : le rattachement kommune → région 2027 est
dérivé de l'ancien découpage par la table REGIONS_2027 ci-dessous.

Sources :
- Population : Danmarks Statistik, table FOLK1A (population au 1er jour du
  trimestre, par kommune et région), dernier trimestre publié, API
  https://api.statbank.dk/v1/ (sans clé, CC BY 4.0 — citer « Danmarks
  Statistik, FOLK1A »).
- Superficie (km²) : Danmarks Statistik, table ARE207, dernière année.
- Contours : Eurostat GISCO, LAU 2024 1:1 M, EPSG:4326 (© EuroGeographics
  pour les limites administratives) :
  https://gisco-services.ec.europa.eu/distribution/v2/lau/geojson/LAU_RG_01M_2024_4326.geojson
  (~150 Mo, toute l'Europe ; seules les entités CNTR_CODE == "DK" sont
  gardées). Les régions sont la fusion des polygones de leurs kommuner.

Codes : kommunekode à 4 chiffres (« 0101 » København), comme DAGI et l'API
climat DMI (municipalityId) ; regionskode à 4 chiffres (1081 Nordjylland …
1086 Østdanmark). DST, lui, écrit 101 et 081.

Christiansø (Ertholmene, ~90 hab.) n'appartient à aucune kommune : présent
dans GISCO (411) et compté dans « Hele landet » par DST, il est écarté des
kommuner et signalé à part.

Sorties (data/out/) :
- dk_kommuner.json : régions et kommuner (code, nom, région, population,
  superficie, densité) ;
- dk_kommuner_boundaries.json, dk_regions_boundaries.json : même format que
  france_departements_boundaries.json (code, nom, centroïde lat/lon, span en
  degrés pour la caméra, géométrie GeoJSON).

Run: .venv/bin/python build_dk_kommuner.py
"""
import csv
import io
import json
from datetime import datetime, timezone
from pathlib import Path

import requests
from shapely.geometry import mapping, shape
from shapely.ops import unary_union

RAW = Path(__file__).parent / "data" / "raw" / "dk"
OUT = Path(__file__).parent / "data" / "out"
RAW.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

STATBANK = "https://api.statbank.dk/v1/data"
LAU_URL = "https://gisco-services.ec.europa.eu/distribution/v2/lau/geojson/LAU_RG_01M_2024_4326.geojson"
LAU_PATH = RAW / "LAU_RG_01M_2024_4326.geojson"

CHRISTIANSO = "0411"

# Ancien code DST (avant 2027) → région du 1er janvier 2027.
REGIONS_2027 = {
    "081": ("1081", "Region Nordjylland"),
    "082": ("1082", "Region Midtjylland"),
    "083": ("1083", "Region Syddanmark"),
    "084": ("1086", "Region Østdanmark"),
    "085": ("1086", "Region Østdanmark"),
}
# Nombre de kommuner attendu par ancienne région (contrôle du rattachement).
EXPECTED_KOMMUNER = {"081": 11, "082": 19, "083": 22, "084": 29, "085": 17}

# Décimales gardées dans les géométries (~1 m).
COORD_DECIMALS = 5
# Marge appliquée à l'emprise pour le zoom caméra (France : ~1,4).
SPAN_MARGIN = 1.4


def statbank_csv(table):
    """Dernière période de `table`, toutes zones, codes et libellés."""
    url = f"{STATBANK}/{table}/CSV"
    params = {"lang": "da", "valuePresentation": "CodeAndValue", "OMRÅDE": "*", "Tid": "(1)"}
    print(f"Downloading {table} ...")
    r = requests.get(url, params=params, timeout=120)
    r.raise_for_status()
    rows = []
    for row in csv.DictReader(io.StringIO(r.content.decode("utf-8-sig")), delimiter=";"):
        code, _, name = row["OMRÅDE"].partition(" ")
        period = row["TID"].split(" ")[0]
        value = float(row["INDHOLD"].replace(",", "."))
        rows.append((code, name, period, value))
    return rows


def download_lau():
    if LAU_PATH.exists():
        return
    print(f"Downloading {LAU_URL} ...")
    r = requests.get(LAU_URL, timeout=600)
    r.raise_for_status()
    LAU_PATH.write_bytes(r.content)
    print(f"Saved {len(r.content)} bytes to {LAU_PATH}")


def rounded(coords):
    if isinstance(coords[0], (int, float)):
        return [round(coords[0], COORD_DECIMALS), round(coords[1], COORD_DECIMALS)]
    return [rounded(c) for c in coords]


def boundary_entry(code, nom, geom):
    min_lon, min_lat, max_lon, max_lat = geom.bounds
    centroid = geom.centroid
    geojson = mapping(geom)
    return {
        "code": code,
        "nom": nom,
        "lat": round(centroid.y, 6),
        "lon": round(centroid.x, 6),
        "span": round(SPAN_MARGIN * max(max_lat - min_lat, max_lon - min_lon), 4),
        "geometry": {"type": geojson["type"], "coordinates": rounded(geojson["coordinates"])},
    }


def main():
    download_lau()

    # Population : l'ordre de FOLK1A est hiérarchique — chaque ligne région
    # (08x) est suivie de ses kommuner. On en tire le rattachement.
    population, names, old_region = {}, {}, {}
    total_population = None
    current_region = None
    pop_rows = statbank_csv("FOLK1A")
    pop_period = pop_rows[0][2]
    for code, name, _, value in pop_rows:
        if code == "000":
            total_population = int(value)
        elif code in REGIONS_2027:
            current_region = code
        else:
            kode = code.zfill(4)
            population[kode] = int(value)
            names[kode] = name
            old_region[kode] = current_region

    area_rows = statbank_csv("ARE207")
    area_period = area_rows[0][2]
    area = {code.zfill(4): value for code, _, _, value in area_rows if code != "000" and code not in REGIONS_2027}

    with LAU_PATH.open(encoding="utf-8") as f:
        lau = json.load(f)
    geometries = {
        feat["properties"]["GISCO_ID"].removeprefix("DK_").zfill(4): shape(feat["geometry"])
        for feat in lau["features"]
        if feat["properties"].get("CNTR_CODE") == "DK"
    }

    christianso_population = population.pop(CHRISTIANSO, None)
    names.pop(CHRISTIANSO, None)
    old_region.pop(CHRISTIANSO, None)
    area.pop(CHRISTIANSO, None)
    geometries.pop(CHRISTIANSO, None)

    # Contrôles : mêmes 98 kommuner dans les trois sources, rattachement complet.
    codes = sorted(population)
    assert len(codes) == 98, f"{len(codes)} kommuner dans FOLK1A"
    assert set(codes) == set(area), f"ARE207 diffère : {set(codes) ^ set(area)}"
    assert set(codes) == set(geometries), f"GISCO diffère : {set(codes) ^ set(geometries)}"
    counts = {r: sum(1 for k in codes if old_region[k] == r) for r in REGIONS_2027}
    assert counts == EXPECTED_KOMMUNER, f"rattachement inattendu : {counts}"
    accounted = sum(population.values()) + (christianso_population or 0)
    assert accounted == total_population, f"somme {accounted} ≠ Hele landet {total_population}"

    kommuner = []
    for kode in codes:
        region_code, region_name = REGIONS_2027[old_region[kode]]
        kommuner.append({
            "code": kode,
            "nom": names[kode],
            "codeRegion": region_code,
            "nomRegion": region_name,
            "population": population[kode],
            "superficieKm2": round(area[kode], 1),
            "densite": round(population[kode] / area[kode]),
        })

    regions = []
    region_boundaries = []
    for region_code, region_name in sorted(set(REGIONS_2027.values())):
        members = [k for k in kommuner if k["codeRegion"] == region_code]
        pop = sum(k["population"] for k in members)
        surface = sum(area[k["code"]] for k in members)
        regions.append({
            "code": region_code,
            "nom": region_name,
            "nombreKommuner": len(members),
            "population": pop,
            "superficieKm2": round(surface, 1),
            "densite": round(pop / surface),
        })
        merged = unary_union([geometries[k["code"]] for k in members])
        region_boundaries.append(boundary_entry(region_code, region_name, merged))

    kommune_boundaries = [boundary_entry(k["code"], k["nom"], geometries[k["code"]]) for k in kommuner]

    generated_at = datetime.now(timezone.utc).isoformat()
    source = (
        f"Danmarks Statistik — FOLK1A ({pop_period}) et ARE207 ({area_period}), api.statbank.dk ; "
        "Eurostat GISCO LAU 2024 (© EuroGeographics) ; régions au découpage du 1er janvier 2027"
    )
    data = {
        "generatedAt": generated_at,
        "source": source,
        "periodePopulation": pop_period,
        "regions": regions,
        "kommuner": kommuner,
        "horsKommune": [{"code": CHRISTIANSO, "nom": "Christiansø", "population": christianso_population}],
    }
    (OUT / "dk_kommuner.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / "dk_kommuner_boundaries.json").write_text(json.dumps(kommune_boundaries, ensure_ascii=False), encoding="utf-8")
    (OUT / "dk_regions_boundaries.json").write_text(json.dumps(region_boundaries, ensure_ascii=False), encoding="utf-8")

    print(f"Population {pop_period} : {total_population} (dont Christiansø {christianso_population})")
    for r in regions:
        print(f"  {r['code']} {r['nom']} : {r['nombreKommuner']} kommuner, {r['population']} hab., {r['superficieKm2']} km²")
    print(f"Wrote {len(kommuner)} kommuner, {len(regions)} regions to {OUT}")


if __name__ == "__main__":
    main()
