"""
Builds communes_data.json: population, densité, catégorie de taille, et
coordonnées pour ~35 000 communes françaises réelles — remplace le petit
échantillon de 46 communes de CommuneSizeData.swift.

Source (Etalab / data.gouv.fr, mirroré par villedereve.fr) :
"Liste des communes de France : code INSEE, codes postaux, EPCI,
population, superficie - 62 indicateurs"
https://www.data.gouv.fr/datasets/liste-des-communes-de-france-code-insee-codes-postaux-epci-population-superficie-62-indicateurs
Dataset id (data.gouv.fr API) : 6745d9ae4524d845d2138193
Ressource utilisée (CSV 2026) :
https://static.data.gouv.fr/resources/communes-et-villes-de-france-en-csv-excel-json-parquet-et-feather/20260617-155950/communes-france-2026.csv

Seuils de catégorisation (identiques à CommuneSizeCategory.category(forPopulation:)
côté Swift) :
- Village : population < 2 000 hab.
- Petite ville : 2 000 à 20 000 hab.
- Ville moyenne : 20 000 à 100 000 hab.
- Grande ville : > 100 000 hab.

Run: .venv/bin/python build_communes_data.py
"""
import csv
import json
from datetime import datetime, timezone
from pathlib import Path

import requests

RAW = Path(__file__).parent / "data" / "raw"
OUT = Path(__file__).parent / "data" / "out"
RAW.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

CSV_URL = "https://static.data.gouv.fr/resources/communes-et-villes-de-france-en-csv-excel-json-parquet-et-feather/20260617-155950/communes-france-2026.csv"
CSV_PATH = RAW / "communes-france-2026.csv"


def category(population):
    if population < 2_000:
        return "village"
    if population < 20_000:
        return "petiteVille"
    if population < 100_000:
        return "villeMoyenne"
    return "grandeVille"


def download():
    if CSV_PATH.exists():
        return
    print(f"Downloading {CSV_URL} ...")
    r = requests.get(CSV_URL, timeout=120)
    r.raise_for_status()
    CSV_PATH.write_bytes(r.content)
    print(f"Saved {len(r.content)} bytes to {CSV_PATH}")


def to_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    download()

    entries = []
    skipped = 0
    with CSV_PATH.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("typecom") != "COM":
                # Exclut les arrondissements municipaux (Paris/Lyon/Marseille) et
                # autres types (COMD, COMA...) pour éviter les doublons de population.
                continue
            insee = row.get("code_insee", "").strip()
            pop_raw = row.get("population", "").strip()
            if not insee or not pop_raw:
                skipped += 1
                continue
            try:
                population = int(float(pop_raw))
            except ValueError:
                skipped += 1
                continue
            densite_raw = to_float(row.get("densite"))
            densite = int(round(densite_raw)) if densite_raw is not None else 0
            lat = to_float(row.get("latitude_centre")) or to_float(row.get("latitude_mairie"))
            lon = to_float(row.get("longitude_centre")) or to_float(row.get("longitude_mairie"))
            entries.append({
                "insee": insee,
                "name": row.get("nom_standard", "").strip(),
                "departementCode": row.get("dep_code", "").strip(),
                "population": population,
                "densite": densite,
                "category": category(population),
                "lat": lat,
                "lon": lon,
            })

    entries.sort(key=lambda e: e["insee"])

    final = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": "data.gouv.fr — Liste des communes de France (Etalab), CSV 2026: " + CSV_URL,
        "communes": entries,
    }
    out_path = OUT / "communes_data.json"
    out_path.write_text(json.dumps(final, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {len(entries)} communes ({skipped} skipped) to {out_path}")


if __name__ == "__main__":
    main()
