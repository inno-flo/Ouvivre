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
  - RR : cumul mensuel des précipitations (mm)
  - NBRR : nombre de jours renseignés pour RR (sert à repérer un mois en cours)

Méthode : moyenne simple des valeurs de tous les postes du département pour
chaque mois (postes sans valeur ignorés). La composition du réseau de postes
(et leur altitude) varie d'un département et d'un mois à l'autre — c'est un
ordre de grandeur départemental, pas une série homogénéisée.

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


def mean(values):
    return round(sum(values) / len(values), 1) if values else None


def build_departement(code, months, wanted, resolve_corsica):
    """{AAAAMM: {tm, rr, partial}} pour un département (ou 2A/2B)."""
    file_dep = "20" if code in ("2A", "2B") else code
    years = {m[:4] for m in months}
    names = []
    if any(int(y) <= 2024 for y in years):
        names.append(f"MENSQ_{file_dep}_previous-1950-2024.csv.gz")
    names.append(f"MENSQ_{file_dep}_latest-2025-2026.csv.gz")

    tm, tx, rr, nbrr = {}, {}, {}, {}
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
            if row["TM"]:
                tm.setdefault(m, []).append(float(row["TM"]))
            if row["TX"]:
                tx.setdefault(m, []).append(float(row["TX"]))
            if row["RR"]:
                rr.setdefault(m, []).append(float(row["RR"]))
                if row["NBRR"]:
                    nbrr.setdefault(m, []).append(int(row["NBRR"]))

    result = {}
    for m in months:
        if m not in tm and m not in rr:
            continue
        entry = {"tm": mean(tm.get(m, [])), "tx": mean(tx.get(m, [])), "rr": mean(rr.get(m, []))}
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

    out = {}
    missing = []
    for code, nom in sorted(departements.items()):
        series = build_departement(code, months, wanted, resolve_corsica)
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
