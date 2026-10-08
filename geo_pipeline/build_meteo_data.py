"""
Builds meteo_monthly.json: températures et précipitations mensuelles par
département sur les 5 dernières années glissantes — alimente la section
"Météo" de l'inspecteur.

Source : Météo-France, "Données climatologiques de base — mensuelles"
(meteo.data.gouv.fr / data.gouv.fr, dataset 6569b3d7d193b4daf2b43edc), un
fichier CSV.gz par département et par période :
  - MENSQ_<dep>_previous-1950-2024.csv.gz  (annuel/mensuel, jusqu'à 2024)
  - MENSQ_<dep>_latest-2025-2026.csv.gz    (mis à jour quotidiennement)
Description des paramètres :
https://www.data.gouv.fr/api/1/datasets/r/766dbe58-0c5a-428b-b76e-a24b3cd250e1

Paramètres retenus (une ligne = un poste × un mois, colonne AAAAMM) :
  - TM : moyenne mensuelle des températures quotidiennes (°C)
  - TX : moyenne mensuelle des températures maximales quotidiennes (°C)
  - TXAB / TXDAT : maximum absolu du mois (°C) et jour où il a été relevé
  - TNAB : minimum absolu du mois (°C) — « record de froid », min. des postes
  - UMM : humidité relative moyenne mensuelle (%)
  - FFM : vitesse moyenne mensuelle du vent à 10 m (m/s)
  - RR : cumul mensuel des précipitations (mm)
  - NBRR : nombre de jours renseignés pour RR (sert à repérer un mois en cours)

Méthode : moyenne des postes du département pour chaque mois, pondérée par
la population (TM, TX et RR). Chaque commune (communes_data.json, avec
coordonnées et population) est rattachée au poste le plus proche parmi ceux
qui ont une mesure ce mois-là ; chaque poste pèse la population des communes
qui lui sont rattachées. Cela évite que des postes d'altitude, nombreux mais
peu habités, tirent la valeur d'un département de montagne vers le bas
(effet de +0,3 °C en plaine à +3,6 °C en Savoie sur la moyenne annuelle).
Repli sur la moyenne simple si le département n'a aucune commune localisée.
Les records absolus (TXAB, TNAB), eux, restent le maximum / minimum des postes,
et l'humidité / le vent (pour la température ressentie) la moyenne simple. La
composition du réseau de postes varie d'une année à l'autre — c'est un ordre
de grandeur départemental, pas une série homogénéisée.

Température ressentie (`tr`) : non publiée par Météo-France, calculée ici à
partir des moyennes départementales du mois (voir `feels_like`) — indice de
chaleur (Rothfusz, NOAA) quand il fait chaud, refroidissement éolien
(formule canadienne) quand il fait froid, sinon la température moyenne.
Appliquer ces formules à des moyennes mensuelles lisse les extrêmes : c'est une
estimation indicative, pas une mesure.

Fenêtre : de janvier de l'année N-5 (année complète) au mois courant de
l'année N (69 mois en septembre 2026). Le mois courant est partiel : marqué `partial` dans le JSON.

Corse : Météo-France publie un seul fichier "20" pour 2A et 2B ; chaque poste
est rattaché à 2A ou 2B via la commune INSEE de même numéro (communes_data.json),
départagée par proximité quand le numéro existe dans les deux départements.

Run: .venv/bin/python build_meteo_data.py
"""
import csv
import gzip
import io
import json
import math
from datetime import date, datetime, timezone
from pathlib import Path

import requests

BASE = "https://meteofrance.s3.sbg.io.cloud.ovh.net/data/synchro_ftp/BASE/MENS"
OUT = Path(__file__).parent / "data" / "out"
RAW = Path(__file__).parent / "data" / "raw" / "meteo"
OUT.mkdir(parents=True, exist_ok=True)
RAW.mkdir(parents=True, exist_ok=True)

RES = Path(__file__).parent.parent / "OuvivreKit" / "Sources" / "OuvivreKit" / "Resources"
FRANCE_GEO_SCORES = RES / "france_geo_scores.json"
COMMUNES = RES / "communes_data.json"

YEARS_BACK = 5


def window(today):
    """Liste AAAAMM de janvier N-5 au mois courant de N (inclus) — l'année de
    départ est prise en entier."""
    y, m = today.year - YEARS_BACK, 1
    months = []
    while (y, m) <= (today.year, today.month):
        months.append(f"{y}{m:02d}")
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return months


def fetch_rows(file_dep, name):
    """Lignes CSV d'un fichier département/période (téléchargé une fois, mis
    en cache dans data/raw/meteo — sauf la période récente, retéléchargée à
    chaque run car mise à jour quotidiennement)."""
    path = RAW / name
    if not path.exists() or "latest" in name:
        r = requests.get(f"{BASE}/{name}", timeout=120)
        if r.status_code == 404:
            return None
        r.raise_for_status()
        path.write_bytes(r.content)
    with gzip.open(path, "rt", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter=";"))


def load_departements():
    data = json.loads(FRANCE_GEO_SCORES.read_text())
    return {d["codeInsee"]: d["nom"] for d in data["departements"]}


def corsica_resolver():
    communes = json.loads(COMMUNES.read_text())["communes"]
    by_code = {c["insee"]: c for c in communes if c["departementCode"] in ("2A", "2B")}

    def resolve(row):
        num = row["NUM_POSTE"][2:5]
        cands = [by_code[k] for k in (f"2A{num}", f"2B{num}") if k in by_code]
        if not cands:
            return None
        lat, lon = float(row["LAT"]), float(row["LON"])
        best = min(cands, key=lambda c: math.hypot(c["lat"] - lat, c["lon"] - lon))
        return best["departementCode"]

    return resolve


def feels_like(t, rh, wind_ms):
    """Température ressentie (°C) depuis la température moyenne `t`, l'humidité
    relative `rh` (%) et le vent moyen `wind_ms` (m/s) — `None` si `t` manque.
    Chaud (≥ 27 °C, humidité ≥ 40 %) : indice de chaleur de Rothfusz (NOAA).
    Froid (≤ 10 °C, vent ≥ 1,3 m/s ≈ 4,8 km/h) : refroidissement éolien
    canadien. Sinon : `t`. Une donnée d'entrée absente ramène à `t`."""
    if t is None:
        return None
    if t >= 27 and rh is not None and rh >= 40:
        f = t * 9 / 5 + 32
        hi = (-42.379 + 2.04901523 * f + 10.14333127 * rh - 0.22475541 * f * rh
              - 0.00683783 * f * f - 0.05481717 * rh * rh + 0.00122874 * f * f * rh
              + 0.00085282 * f * rh * rh - 0.00000199 * f * f * rh * rh)
        return round((hi - 32) * 5 / 9, 1)
    if t <= 10 and wind_ms is not None and wind_ms * 3.6 >= 4.8:
        v = (wind_ms * 3.6) ** 0.16
        return round(13.12 + 0.6215 * t - 11.37 * v + 0.3965 * t * v, 1)
    return t


def mean(values):
    return round(sum(values) / len(values), 1) if values else None


def communes_by_departement():
    """{code département: [(lat, lon, population)]} — communes localisées et
    habitées seulement (les autres ne peuvent pas être rattachées à un poste)."""
    out = {}
    for c in json.loads(COMMUNES.read_text())["communes"]:
        if c.get("lat") is not None and c.get("lon") is not None and c.get("population"):
            out.setdefault(c["departementCode"], []).append((c["lat"], c["lon"], c["population"]))
    return out


def rank_stations(communes, coords):
    """Pour chaque commune, [(population, postes triés du plus proche au plus
    éloigné)] — calculé une fois par département, réutilisé pour chaque mois."""
    ranked = []
    for lat, lon, pop in communes:
        k = math.cos(math.radians(lat))
        order = sorted(coords, key=lambda n: (coords[n][0] - lat) ** 2 + ((coords[n][1] - lon) * k) ** 2)
        ranked.append((pop, order))
    return ranked


def weighted_mean(values, ranked):
    """Moyenne des `values` ({poste: valeur}) pondérée par la population des
    communes rattachées à chaque poste disponible ; moyenne simple en repli."""
    if not values:
        return None
    weights = {}
    for pop, order in ranked:
        for n in order:
            if n in values:
                weights[n] = weights.get(n, 0) + pop
                break
    total = sum(weights.values())
    if total == 0:
        return mean(list(values.values()))
    return round(sum(values[n] * w for n, w in weights.items()) / total, 1)


def build_departement(code, months, wanted, resolve_corsica, communes):
    """{AAAAMM: {tm, tx, tr, xa, xn, xd, na, rr, partial}} pour un département (ou 2A/2B)."""
    file_dep = "20" if code in ("2A", "2B") else code
    years = {m[:4] for m in months}
    names = []
    if any(int(y) <= 2024 for y in years):
        names.append(f"MENSQ_{file_dep}_previous-1950-2024.csv.gz")
    names.append(f"MENSQ_{file_dep}_latest-2025-2026.csv.gz")

    tm, tx, rr = {}, {}, {}  # AAAAMM -> {poste: valeur}, pondérés par la population
    um, ff, nbrr = {}, {}, {}
    coords = {}  # poste -> (lat, lon)
    record = {}  # AAAAMM -> (TXAB, nom du poste, jour) du poste le plus chaud
    cold = {}  # AAAAMM -> TNAB le plus bas des postes (record de froid)
    for name in names:
        rows = fetch_rows(file_dep, name)
        if rows is None:
            return None
        for row in rows:
            m = row["AAAAMM"]
            if m not in wanted:
                continue
            if file_dep == "20" and resolve_corsica(row) != code:
                continue
            num = row["NUM_POSTE"]
            coords[num] = (float(row["LAT"]), float(row["LON"]))
            if row["TM"]:
                tm.setdefault(m, {})[num] = float(row["TM"])
            if row["TX"]:
                tx.setdefault(m, {})[num] = float(row["TX"])
            if row["TXAB"] and (m not in record or float(row["TXAB"]) > record[m][0]):
                record[m] = (float(row["TXAB"]), row["NOM_USUEL"], int(row["TXDAT"]) if row["TXDAT"] else None)
            if row["TNAB"] and (m not in cold or float(row["TNAB"]) < cold[m]):
                cold[m] = float(row["TNAB"])
            if row["UMM"]:
                um.setdefault(m, []).append(float(row["UMM"]))
            if row["FFM"]:
                ff.setdefault(m, []).append(float(row["FFM"]))
            if row["RR"]:
                rr.setdefault(m, {})[num] = float(row["RR"])
                if row["NBRR"]:
                    nbrr.setdefault(m, []).append(int(row["NBRR"]))

    ranked = rank_stations(communes, coords)
    result = {}
    for m in months:
        if m not in tm and m not in rr:
            continue
        t = weighted_mean(tm.get(m, {}), ranked)
        entry = {
            "tm": t,
            "tx": weighted_mean(tx.get(m, {}), ranked),
            "tr": feels_like(t, mean(um.get(m, [])), mean(ff.get(m, []))),
            "rr": weighted_mean(rr.get(m, {}), ranked),
        }
        if m in record:
            entry["xa"], entry["xn"], entry["xd"] = record[m]
        if m in cold:
            entry["na"] = cold[m]
        if m == months[-1]:
            entry["partial"] = True
        result[m] = entry
    return result


def main():
    today = date.today()
    months = window(today)
    wanted = set(months)
    departements = load_departements()
    resolve_corsica = corsica_resolver()
    communes = communes_by_departement()

    out = {}
    missing = []
    for code, nom in sorted(departements.items()):
        series = build_departement(code, months, wanted, resolve_corsica, communes.get(code, []))
        if not series:
            missing.append(code)
            continue
        out[code] = series
        print(f"{code} {nom}: {len(series)} mois")

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": "Météo-France — données climatologiques de base mensuelles (dataset data.gouv.fr 6569b3d7d193b4daf2b43edc)",
        "from": months[0],
        "to": months[-1],
        "departements": out,
    }
    (OUT / "meteo_monthly.json").write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    print(f"Écrit {len(out)} départements ; sans données : {missing}")


if __name__ == "__main__":
    main()
