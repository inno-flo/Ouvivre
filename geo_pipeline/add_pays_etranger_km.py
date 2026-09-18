"""
Adds the raw "paysEtranger" distance (km, to the nearest foreign country —
land or sea) alongside the existing min-max normalized score, so the app
can apply a real-world km threshold instead of the compressed 0-100 score.

Why: min-max normalizing "paysEtranger" across all 101 départements (some
DROM thousands of km from any border) compresses mainland distances into a
narrow high band. A département a few km from a maritime border (e.g.
Manche, 22 km from Jersey across the Channel) scores nearly as high as one
that only just fails to touch a land border, and a hard filter on that
score alone can't distinguish "actually close" from "technically touches".
A straight km cutoff (see `FranceGeoData.maxPaysEtrangerKm`) treats a short
Channel/Mediterranean crossing the same as a short land border, correctly
reflecting the source distance computation itself (build_france_geo_scores
picks the nearest neighboring country regardless of land or sea).

Source: geo_pipeline/data/out/raw_distances.json (already computed by
build_france_geo_scores.py, see its `distances_km["paysEtranger"]`) — no
geometry recomputation needed here, just merging that raw value into the
shipped JSON as an extra field per département.

Run: .venv/bin/python add_pays_etranger_km.py
"""
import json
from pathlib import Path

OUT = Path(__file__).parent / "data" / "out"
RAW_DISTANCES_PATH = OUT / "raw_distances.json"

RESOURCES = Path(__file__).parent.parent / "OuvivreKit" / "Sources" / "OuvivreKit" / "Resources"
GEO_SCORES_PATH = RESOURCES / "france_geo_scores.json"


def main():
    raw = json.loads(RAW_DISTANCES_PATH.read_text())
    km_by_code = {r["code_insee"]: r["distances_km"]["paysEtranger"] for r in raw}

    existing = json.loads(GEO_SCORES_PATH.read_text())
    missing = []
    for rec in existing["departements"]:
        code = rec["codeInsee"]
        km = km_by_code.get(code)
        if km is None:
            missing.append(code)
            continue
        rec.setdefault("distancesKm", {})["paysEtranger"] = round(float(km), 1)

    if missing:
        raise SystemExit(f"No raw distance found for: {missing}")

    existing["generatedAt"] = "2026-09-18"
    existing["source"] = existing.get("source", "") + " + raw paysEtranger km (add_pays_etranger_km.py)"

    GEO_SCORES_PATH.write_text(json.dumps(existing, ensure_ascii=False, indent=1))
    print(f"Wrote updated {GEO_SCORES_PATH} ({len(km_by_code)} départements patched)")


if __name__ == "__main__":
    main()
