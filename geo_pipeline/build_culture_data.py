"""
Builds culture_scores.json: per-département 0-100 scores for Musées, Lieux
du patrimoine et Festivals — feeds the "Culture" block of BigMacView.

Sources (culture.data.gouv.fr / ministère de la Culture, via data.gouv.fr) :
- Musées : Base des lieux et équipements culturels (Basilic)
  https://culture.data.gouv.fr/datasets/61777ddaa9101d073e5506cd
  filtré sur Type équipement ou lieu == "Musée" (1843 lignes sur ~86k)
- Lieux du patrimoine : Immeubles protégés au titre des Monuments
  Historiques (base Mérimée) — une ligne par monument
  https://www.data.gouv.fr/datasets/immeubles-proteges-au-titre-des-monuments-historiques
  (les sites patrimoniaux remarquables (SPR) — zones protégées par commune,
  https://culture.data.gouv.fr/datasets/628da9ff836d8bf454c7fd48 — restent
  listés à part dans "names.spr" pour l'inspecteur, mais ne servent plus au
  score : Paris n'a que 2 SPR pour près de 1 900 monuments historiques.)
- Festivals : Liste des festivals en France
  https://culture.data.gouv.fr/datasets/62cf95993d99f22480f49334

Méthode : décompte brut par département pour chacune des 3 catégories, puis
normalisation min-max sur les 101 départements (0 = minimum, 100 = maximum) —
même convention que normalize_and_export.py pour france_geo_scores.json.

Run: .venv/bin/python build_culture_data.py
"""
import csv
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import requests

RAW = Path(__file__).parent / "data" / "raw"
OUT = Path(__file__).parent / "data" / "out"
RAW.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

MUSEES_URL = "https://static.data.gouv.fr/resources/base-des-lieux-et-equipements-culturels-basilic/20260218-084338/base-des-lieux-et-des-equipements-culturels.csv"
PATRIMOINE_URL = "https://ministere-culture.s3.sbg.io.cloud.ovh.net/SPR/liste_sites_patrimoniaux_remarquables.csv"
MONUMENTS_URL = "https://ministere-culture.s3.sbg.io.cloud.ovh.net/POP/merimee.csv"
FESTIVALS_URL = "https://static.data.gouv.fr/resources/liste-des-festivals-en-france/20250827-132958/festivals-global-festivals-pl.csv"

MUSEES_PATH = RAW / "musees.csv"
PATRIMOINE_PATH = RAW / "patrimoine.csv"
MONUMENTS_PATH = RAW / "merimee.csv"
FESTIVALS_PATH = RAW / "festivals.csv"

FRANCE_GEO_SCORES = Path(__file__).parent.parent / "OuvivreKit" / "Sources" / "OuvivreKit" / "Resources" / "france_geo_scores.json"


def download(url, path):
    if path.exists():
        return
    print(f"Downloading {url} ...")
    r = requests.get(url, timeout=120)
    r.raise_for_status()
    path.write_bytes(r.content)
    print(f"Saved {len(r.content)} bytes to {path}")


def dept_code_from_insee(insee):
    if not insee:
        return None
    if insee.startswith("97") or insee.startswith("98"):
        return insee[:3]
    return insee[:2]


def load_departements():
    """Canonical list of 101 départements (code, nom) from the existing
    france_geo_scores.json — keeps this pipeline consistent with it."""
    data = json.loads(FRANCE_GEO_SCORES.read_text())
    return {d["codeInsee"]: d["nom"] for d in data["departements"]}


def count_musees(dept_codes):
    counts = {c: 0 for c in dept_codes}
    names = {c: [] for c in dept_codes}
    with MUSEES_PATH.open(encoding="utf-8-sig") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            if row.get("Type équipement ou lieu", "").strip() != "Musée":
                continue
            code = dept_code_from_insee(row.get("code_insee", "").strip())
            if code in counts:
                counts[code] += 1
                name = row.get("Nom", "").strip()
                if name:
                    names[code].append(name)
    return counts, names


def count_monuments(dept_codes):
    """Monuments historiques (base Mérimée) : un monument = une ligne. Nom
    affiché "Titre — Commune" pour distinguer les nombreuses "Église" d'un
    même département."""
    counts = {c: 0 for c in dept_codes}
    names = {c: [] for c in dept_codes}
    csv.field_size_limit(10**9)
    with MONUMENTS_PATH.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f, delimiter="|")
        for row in reader:
            code = row.get("Departement_format_numerique", "").strip()
            if code in counts:
                counts[code] += 1
                titre = row.get("Titre_editorial_de_la_notice", "").strip()
                commune = row.get("Commune_forme_index", "").strip()
                if titre:
                    names[code].append(f"{titre} — {commune}" if commune else titre)
    return counts, names


def count_spr(dept_codes):
    counts = {c: 0 for c in dept_codes}
    # Le SPR (site patrimonial remarquable) est répertorié par commune, sans
    # nom propre — "commune" est donc le nom affiché pour chaque entrée.
    names = {c: [] for c in dept_codes}
    with PATRIMOINE_PATH.open(encoding="utf-8-sig") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            code = row.get("code_departement", "").strip()
            if code in counts:
                try:
                    counts[code] += int(row.get("nombre_de_spr", "1") or "1")
                except ValueError:
                    counts[code] += 1
                commune = row.get("commune", "").strip()
                if commune:
                    names[code].append(commune)
    return counts, names


def normalize_url(raw):
    """Site internet du festival -> URL https exploitable, ou None. Le champ
    est saisi librement (souvent sans schéma, "www.exemple.fr")."""
    raw = (raw or "").strip()
    if not raw or " " in raw or "." not in raw:
        return None
    if not re.match(r"^https?://", raw, re.IGNORECASE):
        raw = "https://" + raw
    return raw


def count_festivals(dept_codes):
    counts = {c: 0 for c in dept_codes}
    names = {c: [] for c in dept_codes}
    urls = {c: {} for c in dept_codes}
    disciplines = {c: {} for c in dept_codes}
    with FESTIVALS_PATH.open(encoding="utf-8-sig") as f:
        reader = csv.DictReader(f, delimiter=";")
        # Le fichier source a un double BOM : utf-8-sig n'en retire qu'un, la
        # 1re colonne s'appelle donc "\ufeffNom du festival".
        reader.fieldnames = [n.lstrip("\ufeff") for n in reader.fieldnames]
        for row in reader:
            insee = row.get("Code Insee commune", "").strip()
            # Codes à 4 chiffres : le zéro initial des départements 01-09 a
            # été perdu dans le CSV (ex. "1053" pour l'Ain).
            if len(insee) == 4 and insee.isdigit():
                insee = insee.zfill(5)
            code = dept_code_from_insee(insee)
            if code in counts:
                counts[code] += 1
                name = row.get("Nom du festival", "").strip()
                if name:
                    names[code].append(name)
                    url = normalize_url(row.get("Site internet du festival"))
                    if url:
                        urls[code][name] = url
                    discipline = row.get("Discipline dominante", "").strip()
                    if discipline:
                        disciplines[code][name] = discipline
    return counts, names, urls, disciplines


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
    download(MUSEES_URL, MUSEES_PATH)
    download(PATRIMOINE_URL, PATRIMOINE_PATH)
    download(MONUMENTS_URL, MONUMENTS_PATH)
    download(FESTIVALS_URL, FESTIVALS_PATH)

    dept_names = load_departements()
    dept_codes = list(dept_names.keys())

    musees_counts, musees_names = count_musees(dept_codes)
    patrimoine_counts, patrimoine_names = count_monuments(dept_codes)
    spr_counts, spr_names = count_spr(dept_codes)
    festivals_counts, festivals_names, festivals_urls, festivals_disciplines = count_festivals(dept_codes)

    musees_score = min_max_normalize(musees_counts)
    patrimoine_score = min_max_normalize(patrimoine_counts)
    festivals_score = min_max_normalize(festivals_counts)

    out_records = []
    for code in sorted(dept_codes):
        out_records.append({
            "codeInsee": code,
            "nom": dept_names[code],
            "scores": {
                "musees": musees_score(code),
                "patrimoine": patrimoine_score(code),
                "festivals": festivals_score(code),
            },
            "counts": {
                "musees": musees_counts[code],
                "patrimoine": patrimoine_counts[code],
                "festivals": festivals_counts[code],
                "spr": spr_counts[code],
            },
            "names": {
                "musees": sorted(musees_names[code]),
                "patrimoine": sorted(patrimoine_names[code]),
                "festivals": sorted(festivals_names[code]),
                "spr": sorted(set(spr_names[code])),
            },
            # Seuls les festivals ont une URL dans les données sources ; les
            # musées (Basilic) et les SPR n'ont pas de colonne site internet.
            "urls": {"festivals": festivals_urls[code]},
            # Discipline dominante : seule catégorie thématique présente dans
            # les données (les musées Basilic n'en ont pas de variable).
            "disciplines": {"festivals": festivals_disciplines[code]},
        })

    final = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": (
            "culture.data.gouv.fr — Base des lieux et équipements culturels "
            "(Basilic, filtré Musée): " + MUSEES_URL + " | "
            "Immeubles protégés au titre des Monuments Historiques (Mérimée): " + MONUMENTS_URL + " | "
            "Liste des sites patrimoniaux remarquables (SPR, affichage): " + PATRIMOINE_URL + " | "
            "Liste des festivals en France: " + FESTIVALS_URL
        ),
        "departements": out_records,
    }
    out_path = OUT / "culture_scores.json"
    out_path.write_text(json.dumps(final, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"Wrote {len(out_records)} départements to {out_path}")
    print("Totals — musées:", sum(musees_counts.values()), "patrimoine:", sum(patrimoine_counts.values()), "festivals:", sum(festivals_counts.values()))


if __name__ == "__main__":
    main()
