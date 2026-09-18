"""
Recomputes the "mer" (mer et océan) score using hop-distance-to-coast
instead of the old continuous min-max distance gradient.

Why: the old "mer" score was distance-to-coastline min-max normalized
across all 101 départements. Because the true minimum of that range sits
way out in Alsace/Belfort, landlocked-but-central départements (e.g.
Haute-Vienne, Loiret, Sarthe) still scored 65-80/100 — nowhere near a real
coast. The user wants slider semantics instead: "déterminant" (max) should
surface départements that actually touch the sea; the next tier down
("important") should surface départements exactly one hop away (adjacent
to a coastal département, but not themselves coastal).

Method:
1. Coastal départements: a STATIC, hand-verified list (see COASTAL_CODES
   below), not a geometric computation. An earlier version tried deriving
   "touches the sea" from IGN département polygons minus a buffered union
   of neighboring-country polygons (Natural Earth) — but the two datasets'
   border tracings don't coincide closely enough: land-border départements
   (Bas-Rhin, Haut-Rhin, Moselle, Meurthe-et-Moselle, Meuse, Ardennes,
   Doubs, Savoie, Haute-Garonne, Ariège, Hautes-Alpes, Territoire de
   Belfort...) all came out as false-positive "coastal" from leftover
   mismatch slivers along their real (land) international borders, no
   matter how the exclusion buffer was tuned. Which départements have a
   real coastline is unambiguous, well-established geography — a static
   list is simply more reliable here than fragile cross-dataset geometry.
2. Load département polygons from data/raw/departements.json (same cached
   IGN BD TOPO file build_france_geo_scores.py already uses — code_insee /
   nom_officiel properties) to build a département ADJACENCY graph (polygon
   touch/intersect, buffered to close floating-point gaps) — this part
   stays geometric since it's purely internal to France's départements
   (no cross-dataset border mismatch involved), and is sanity-checked below
   (Haute-Vienne's expected neighbors).
3. Multi-source BFS from all coastal départements over that graph =>
   hop-distance per département (0 = coastal).
4. Map hop-distance to a 0-100 score: score = max(0, 100 - hop * 25)
   (0->100, 1->75, 2->50, 3->25, 4+->0). Simple, monotonic, hop-0 = 100.
5. Patch OuvivreKit/Sources/OuvivreKit/Resources/france_geo_scores.json,
   replacing only the "mer" value in each département's "scores", keeping
   every other criterion untouched, and refreshing "generatedAt".

Run: .venv/bin/python recompute_mer_score.py
"""
import json
from pathlib import Path

from shapely.geometry import shape
from shapely.strtree import STRtree

RAW = Path(__file__).parent / "data" / "raw"
OUT = Path(__file__).parent / "data" / "out"
OUT.mkdir(parents=True, exist_ok=True)

RESOURCES = Path(__file__).parent.parent / "OuvivreKit" / "Sources" / "OuvivreKit" / "Resources"
GEO_SCORES_PATH = RESOURCES / "france_geo_scores.json"

# Départements ayant un vrai littoral (Manche/mer du Nord, Atlantique,
# Méditerranée, Corse, DROM) — géographie établie, liste statique plutôt
# que dérivée par géométrie (voir docstring du module).
COASTAL_CODES = {
    # Manche / mer du Nord
    "59", "62", "80", "76", "14", "50",
    # Bretagne
    "35", "22", "29", "56",
    # Atlantique
    "44", "85", "17", "33", "40", "64",
    # Méditerranée
    "66", "11", "34", "30", "13", "83", "06",
    # Corse
    "2A", "2B",
    # DROM
    "971", "972", "973", "974", "976",
}

ADJACENCY_BUFFER_DEG = 0.001   # close floating-point gaps between polygons

# The raw IGN BD TOPO département polygons are extremely high-resolution
# (departements.json is ~127 MB for 101 features) — simplified for the
# adjacency graph, where touch/intersect tests tolerate the ~100 m error
# fine (ADJACENCY_BUFFER_DEG already covers gaps of that size).
SIMPLIFY_TOLERANCE_DEG = 0.001

HOP_STEP = 25  # score = max(0, 100 - hop * HOP_STEP)


def load_departements():
    data = json.loads((RAW / "departements.json").read_text())
    depts = []
    for f in data["features"]:
        props = f["properties"]
        geom = shape(f["geometry"])
        if not geom.is_valid:
            geom = geom.buffer(0)
        depts.append({
            "code_insee": props["code_insee"],
            "nom": props["nom_officiel"],
            "geom": geom,
        })
    return depts


def build_adjacency(depts):
    codes = [d["code_insee"] for d in depts]
    simplified = []
    for d in depts:
        g = d["geom"].simplify(SIMPLIFY_TOLERANCE_DEG, preserve_topology=True)
        if not g.is_valid:
            g = g.buffer(0)
        simplified.append(g)
    buffered_geoms = [g.buffer(ADJACENCY_BUFFER_DEG) for g in simplified]
    tree = STRtree(buffered_geoms)
    adjacency = {c: set() for c in codes}
    for i, geom in enumerate(buffered_geoms):
        a = codes[i]
        for j in tree.query(geom):
            j = int(j)
            if j == i:
                continue
            if geom.intersects(buffered_geoms[j]):
                b = codes[j]
                adjacency[a].add(b)
                adjacency[b].add(a)
    return adjacency


def bfs_hop_distance(codes, coastal, adjacency):
    from collections import deque
    dist = {c: None for c in codes}
    q = deque()
    for c in codes:
        if coastal[c]:
            dist[c] = 0
            q.append(c)
    while q:
        cur = q.popleft()
        for nxt in adjacency[cur]:
            if dist[nxt] is None:
                dist[nxt] = dist[cur] + 1
                q.append(nxt)
    # any département with no path to a coastal one (shouldn't happen in
    # a connected mainland+Corse+DROM graph, since all DROM are coastal
    # themselves at hop 0) gets max distance treatment
    max_known = max((v for v in dist.values() if v is not None), default=0)
    for c in codes:
        if dist[c] is None:
            dist[c] = max_known + 1
    return dist


def hop_to_score(hop):
    return max(0, 100 - hop * HOP_STEP)


def main():
    depts = load_departements()
    print(f"{len(depts)} départements loaded")
    codes = [d["code_insee"] for d in depts]
    names = {d["code_insee"]: d["nom"] for d in depts}

    unknown = COASTAL_CODES - set(codes)
    if unknown:
        raise SystemExit(f"COASTAL_CODES contains codes not found among loaded départements: {unknown}")
    coastal = {c: c in COASTAL_CODES for c in codes}

    coastal_codes = sorted([c for c in codes if coastal[c]], key=lambda c: names[c])
    print(f"\nCoastal départements ({len(coastal_codes)}):")
    for c in coastal_codes:
        print(f"  {c} {names[c]}")

    # Sanity checks
    must_be_coastal = {
        "2A": "Corse-du-Sud", "2B": "Haute-Corse",
        "971": "Guadeloupe", "972": "Martinique", "973": "Guyane",
        "974": "La Réunion", "976": "Mayotte",
    }
    for code, name in must_be_coastal.items():
        status = "OK" if coastal.get(code) else "FAIL"
        print(f"Sanity check {code} {name}: coastal={coastal.get(code)} [{status}]")
        if not coastal.get(code):
            raise SystemExit(f"Sanity check failed: {code} {name} must be coastal")

    for suspicious in ("87", "45", "72"):  # Haute-Vienne, Loiret, Sarthe
        if coastal.get(suspicious):
            raise SystemExit(f"Sanity check failed: {suspicious} {names.get(suspicious)} should NOT be coastal")

    print("\nBuilding adjacency graph…")
    adjacency = build_adjacency(depts)

    # verify a known adjacency: Haute-Vienne (87) <-> Charente(16), Dordogne(24), Corrèze(19), Creuse(23), Vienne(86)
    expected_hv_neighbors = {"16", "24", "19", "23", "86"}
    found = adjacency.get("87", set())
    missing = expected_hv_neighbors - found
    if missing:
        print(f"WARNING: Haute-Vienne adjacency missing expected neighbors: {missing} (found: {found})")
    else:
        print(f"Adjacency sanity check OK: Haute-Vienne neighbors include {expected_hv_neighbors}")

    print("\nRunning multi-source BFS from coastal départements…")
    hop_dist = bfs_hop_distance(codes, coastal, adjacency)

    dist_counts = {}
    for c in codes:
        dist_counts[hop_dist[c]] = dist_counts.get(hop_dist[c], 0) + 1
    print("\nHop-distance distribution:")
    for hop in sorted(dist_counts):
        print(f"  hop {hop}: {dist_counts[hop]} départements (score {hop_to_score(hop)})")

    for code in ("87", "45", "72"):
        print(f"  Flagged: {names[code]} ({code}) -> hop {hop_dist[code]}, score {hop_to_score(hop_dist[code])}")

    # ---- patch france_geo_scores.json ----
    print(f"\nLoading {GEO_SCORES_PATH}…")
    existing = json.loads(GEO_SCORES_PATH.read_text())

    old_scores = {}
    for rec in existing["departements"]:
        code = rec["codeInsee"]
        old_scores[code] = rec["scores"].get("mer")
        new_score = float(hop_to_score(hop_dist[code]))
        rec["scores"]["mer"] = new_score

    existing["generatedAt"] = "2026-09-18"
    existing["source"] = existing.get("source", "") + " + hop-distance-to-coast recompute (recompute_mer_score.py)"

    GEO_SCORES_PATH.write_text(json.dumps(existing, ensure_ascii=False, indent=1))
    print(f"Wrote updated {GEO_SCORES_PATH}")

    # ---- before/after sample table ----
    sample_codes = coastal_codes[:3] + ["87", "45", "72"]
    # add a couple 1-hop départements for the table
    one_hop = sorted([c for c in codes if hop_dist[c] == 1], key=lambda c: names[c])[:2]
    sample_codes += one_hop
    if "15" in names:  # Cantal
        sample_codes.append("15")

    print("\nBefore/after 'mer' score table:")
    print(f"{'code':<6}{'nom':<20}{'hop':<5}{'old_mer':<10}{'new_mer':<10}")
    seen = set()
    for code in sample_codes:
        if code in seen:
            continue
        seen.add(code)
        print(f"{code:<6}{names.get(code, code):<20}{hop_dist.get(code, '?'):<5}{old_scores.get(code):<10}{hop_to_score(hop_dist[code]):<10}")


if __name__ == "__main__":
    main()
