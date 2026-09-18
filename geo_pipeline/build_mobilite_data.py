"""
Builds mobilite_scores.json: per-département 0-100 scores for Pistes
cyclables et Gares — feeds the "Mobilité" block of BigMacView.

Sources (data.gouv.fr) :
- Pistes cyclables : Linéaire d'aménagements cyclables (résolution
  département), Ministère de la Transition écologique / SDES —
  https://www.data.gouv.fr/datasets/lineaire-damenagements-cyclables
  Somme du linéaire (km) tous types d'aménagement confondus (pistes,
  bandes, voies vertes, double-sens, aménagements mixtes, voies bus
  partagées, autre), pour la mesure la plus récente (2025-01-01).
- Gares : Liste des gares du réseau ferré national, SNCF Réseau —
  https://www.data.gouv.fr/datasets/liste-des-gares
  Filtré sur VOYAGEURS == "O" (gares voyageurs uniquement, exclut le fret).
  Le CSV ne porte qu'un nom de département (pas de code INSEE) : rattaché
  par normalisation du libellé (accents/tirets/apostrophes retirés,
  majuscules) contre `nom` dans france_geo_scores.json.

Méthode : décompte/somme brut par département pour chacun des 2 critères,
puis normalisation min-max sur les 101 départements (0 = minimum,
100 = maximum) — même convention que build_culture_data.py.

Run: .venv/bin/python build_mobilite_data.py
"""
import csv
import json
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

import requests

RAW = Path(__file__).parent / "data" / "raw"
OUT = Path(__file__).parent / "data" / "out"
RAW.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

GARES_URL = "https://www.data.gouv.fr/api/1/datasets/r/d22ba593-90a4-4725-977c-095d1f654d28"
CYCLABLES_URL = "https://static.data.gouv.fr/resources/lineaire-damenagements-cyclables/20260203-174349/lineaire-d-amenagements-cyclables-departement.csv"

GARES_PATH = RAW / "gares.csv"
CYCLABLES_PATH = RAW / "cyclables_dept.csv"

FRANCE_GEO_SCORES = Path(__file__).parent.parent / "OuvivreKit" / "Sources" / "OuvivreKit" / "Resources" / "france_geo_scores.json"


def download(url, path):
    if path.exists():
        return
    print(f"Downloading {url} ...")
    r = requests.get(url, timeout=120)
    r.raise_for_status()
    path.write_bytes(r.content)
    print(f"Saved {len(r.content)} bytes to {path}")


def load_departements():
    """Canonical list of 101 départements (code, nom) from the existing
    france_geo_scores.json — keeps this pipeline consistent with it."""
    data = json.loads(FRANCE_GEO_SCORES.read_text())
    return {d["codeInsee"]: d["nom"] for d in data["departements"]}


def normalize_label(s):
    """Uppercase, accent-stripped, punctuation-flattened label for matching
    the gares CSV's free-text DEPARTEMEN column against `nom`."""
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = s.upper().replace("'", " ").replace("-", " ")
    return " ".join(s.split())


def count_gares(dept_names):
    """Nombre de gares voyageurs (VOYAGEURS == 'O') par département,
    rattachées par libellé de département normalisé."""
    label_to_code = {normalize_label(nom): code for code, nom in dept_names.items()}
    counts = {c: 0 for c in dept_names}
    names = {c: [] for c in dept_names}
    unmatched = set()
    with GARES_PATH.open(encoding="utf-8-sig") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            if row.get("VOYAGEURS", "").strip() != "O":
                continue
            label = normalize_label(row.get("DEPARTEMEN", "").strip())
            code = label_to_code.get(label)
            if code is None:
                unmatched.add(label)
                continue
            counts[code] += 1
            name = row.get("LIBELLE", "").strip()
            if name:
                names[code].append(name)
    if unmatched:
        print("Unmatched DEPARTEMEN labels (gares):", sorted(unmatched))
    return counts, names


def sum_cyclables(dept_names):
    """Linéaire total d'aménagements cyclables (km, tous types confondus)
    par département, pour la mesure la plus récente disponible."""
    with CYCLABLES_PATH.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    latest_date = max(row["date_mesure"] for row in rows)
    totals = {c: 0.0 for c in dept_names}
    for row in rows:
        if row["date_mesure"] != latest_date:
            continue
        code = row["geocode_departement"].strip()
        if code in totals:
            totals[code] += float(row["valeur"] or 0.0)
    return totals, latest_date


def min_max_normalize(counts):
    vals = list(counts.values())
    lo, hi = min(vals), max(vals)
    span = hi - lo

    def score(code):
        if span == 0:
            return 50.0
        return round((counts[code] - lo) / span * 100.0, 1)
    return score


def main():
    download(GARES_URL, GARES_PATH)
    download(CYCLABLES_URL, CYCLABLES_PATH)

    dept_names = load_departements()

    gares_counts, gares_names = count_gares(dept_names)
    cyclables_km, cyclables_date = sum_cyclables(dept_names)

    gares_score = min_max_normalize(gares_counts)
    cyclables_score = min_max_normalize(cyclables_km)

    out_records = []
    for code in sorted(dept_names):
        out_records.append({
            "codeInsee": code,
            "nom": dept_names[code],
            "scores": {
                "pistesCyclables": cyclables_score(code),
                "gares": gares_score(code),
            },
            "counts": {
                "pistesCyclablesKm": round(cyclables_km[code], 1),
                "gares": gares_counts[code],
            },
            "names": {
                "gares": sorted(gares_names[code]),
            },
        })

    final = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": (
            f"data.gouv.fr — Linéaire d'aménagements cyclables (département, mesure {cyclables_date[:10]}): "
            + CYCLABLES_URL + " | "
            "Liste des gares du réseau ferré national (SNCF Réseau, filtré VOYAGEURS=O): " + GARES_URL
        ),
        "departements": out_records,
    }
    out_path = OUT / "mobilite_scores.json"
    out_path.write_text(json.dumps(final, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"Wrote {len(out_records)} départements to {out_path}")
    print("Totals — pistes cyclables (km):", round(sum(cyclables_km.values()), 1), "gares:", sum(gares_counts.values()))


if __name__ == "__main__":
    main()
