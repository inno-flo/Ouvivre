"""
Reads data/out/raw_distances.json (raw km distances + coverage densities per
département) and writes france_geo_scores.json: for each département, a
0-100 score per criterion, min-max normalized across all 101 départements.

- paysEtranger, montagne, mer: distance-based (nearer = higher score).
- lacs, fleuves, forets: coverage-density-based (denser = higher score).

Run: .venv/bin/python normalize_and_export.py
"""
import json
from pathlib import Path

OUT = Path(__file__).parent / "data" / "out"

DISTANCE_KEYS = ["paysEtranger", "montagne", "mer"]
COVERAGE_KEYS = ["lacs", "fleuves", "forets"]


def min_max_normalize(values, invert):
    vals = [v for v in values if v is not None]
    lo, hi = min(vals), max(vals)
    span = hi - lo

    def score(v):
        if v is None or span == 0:
            return 50.0
        pct = (v - lo) / span
        if invert:
            pct = 1.0 - pct
        return round(pct * 100.0, 1)
    return score


def main():
    records = json.loads((OUT / "raw_distances.json").read_text())

    scorers = {}
    for k in DISTANCE_KEYS:
        scorers[k] = min_max_normalize([r["distances_km"][k] for r in records], invert=True)
    for k in COVERAGE_KEYS:
        scorers[k] = min_max_normalize([r["coverage_density"][k] for r in records], invert=False)

    out_records = []
    for r in records:
        scores = {}
        for k in DISTANCE_KEYS:
            scores[k] = scorers[k](r["distances_km"][k])
        for k in COVERAGE_KEYS:
            scores[k] = scorers[k](r["coverage_density"][k])
        out_records.append({
            "codeInsee": r["code_insee"],
            "nom": r["nom"],
            "codeRegion": r["code_region"],
            "nomRegion": r["nom_region"],
            "scores": scores,
        })

    out_records.sort(key=lambda r: r["codeInsee"])
    final = {
        "generatedAt": "2026-09-15",
        "source": "IGN BD TOPO V3 (data.geopf.fr) + IGN RGE ALTI elevation API + Natural Earth admin boundaries",
        "departements": out_records,
    }
    out_path = OUT / "france_geo_scores.json"
    out_path.write_text(json.dumps(final, ensure_ascii=False, indent=1))
    print(f"Wrote {len(out_records)} départements to {out_path}")


if __name__ == "__main__":
    main()
