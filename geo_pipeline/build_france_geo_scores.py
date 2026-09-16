"""
Builds france_geo_scores.json: for every French département, a 0-100
proximity score for each of the 6 Géographie criteria, derived from real
IGN (data.geopf.fr BD TOPO V3 WFS) and Natural Earth geometry.

Method: for each département, geodesic-accurate distance (km) to the
nearest feature of each criterion, computed in a local azimuthal-equidistant
projection centered on that département (works uniformly for metropolitan
and overseas départements). Distances are then min-max normalized across
all départements per criterion (0 = farthest, 100 = nearest).

Run: .venv/bin/python build_france_geo_scores.py
"""
import json
import time
from pathlib import Path

import requests
from pyproj import Transformer, Geod
from shapely.geometry import shape
from shapely.ops import transform as shp_transform, unary_union
from shapely.strtree import STRtree

GEOD = Geod(ellps="WGS84")

WFS = "https://data.geopf.fr/wfs/ows"
RAW = Path(__file__).parent / "data" / "raw"
OUT = Path(__file__).parent / "data" / "out"
RAW.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

SESSION = requests.Session()


def wfs_get(typenames, count=2000, bbox=None, cache_name=None):
    if cache_name:
        cache_file = RAW / cache_name
        if cache_file.exists():
            return json.loads(cache_file.read_text())
    params = {
        "SERVICE": "WFS", "VERSION": "2.0.0", "REQUEST": "GetFeature",
        "TYPENAMES": typenames, "OUTPUTFORMAT": "application/json", "COUNT": count,
    }
    if bbox:
        params["BBOX"] = f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]},urn:ogc:def:crs:OGC::CRS84"
    r = SESSION.get(WFS, params=params, timeout=60)
    r.raise_for_status()
    data = r.json()
    if cache_name:
        (RAW / cache_name).write_text(json.dumps(data))
    return data


def fetch_departements():
    data = wfs_get("BDTOPO_V3:departement", count=200, cache_name="departements.json")
    return data["features"]


def fetch_regions():
    data = wfs_get("BDTOPO_V3:region", count=50, cache_name="regions.json")
    return {f["properties"]["code_insee"]: f["properties"]["nom_officiel"] for f in data["features"]}


def fetch_countries():
    cache_file = RAW / "ne_countries.json"
    if not cache_file.exists():
        url = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson"
        r = SESSION.get(url, timeout=60)
        r.raise_for_status()
        cache_file.write_text(r.text)
    return json.loads(cache_file.read_text())["features"]


DISTANCE_LAYERS = {
    "mer": ("BDTOPO_V3:limite_terre_mer", None),
}

# lacs/forêts are common enough that "distance to the nearest one" is ~0 km
# for almost every département (verified on the first full run: min==max==
# 0.0 across all 101) — no discriminative signal. These instead use coverage
# within the département: total water/forest area as a % of département area.
# fleuves is handled separately below (distance to a *major* river only —
# see the comment at its computation for why).
COVERAGE_LAYERS = {
    "lacs": (("BDTOPO_V3:plan_d_eau",), "area"),
    "forets": (("BDTOPO_V3:foret_publique", "BDTOPO_V3:parc_ou_reserve"), "area"),
}

# BD TOPO's "ligne_orographique" turned out to be embankments/quarries, not
# mountain relief (verified: it returned Talus/Levée near Paris, no Crête
# anywhere) — and "detail_orographique" summit points aren't filterable by
# elevation (a Paris hill and a Mont Blanc peak can share the same
# "importance" rank). So "montagne" instead uses IGN's real elevation API
# (RGE ALTI) sampled on a grid restricted to France's known massifs —
# established geography, not fabricated — keeping the query volume sane.
ELEVATION_API = "https://data.geopf.fr/altimetrie/1.0/calcul/alti/rest/elevation.json"
MOUNTAIN_ELEVATION_THRESHOLD_M = 1000

MASSIF_BBOXES_DEG = {
    "alpes": (5.5, 44.0, 7.8, 46.5, 0.05),
    "pyrenees": (-1.8, 42.3, 3.0, 43.2, 0.05),
    "massif_central": (2.0, 44.0, 4.5, 46.0, 0.05),
    "jura": (5.5, 46.0, 7.0, 47.5, 0.05),
    "vosges": (6.5, 47.7, 7.5, 48.5, 0.05),
    "corse": (8.5, 41.3, 9.6, 43.1, 0.05),
    "guadeloupe": (-61.85, 15.8, -61.0, 16.55, 0.02),
    "martinique": (-61.25, 14.35, -60.8, 14.9, 0.02),
    "guyane": (-54.65, 2.1, -51.6, 5.8, 0.1),
    "reunion": (55.15, -21.4, 55.9, -20.85, 0.02),
    "mayotte": (45.0, -13.05, 45.35, -12.6, 0.02),
}


def elevation_batch(points):
    """points: list of (lon, lat). Returns list of elevations (meters)."""
    out = []
    for i in range(0, len(points), 100):
        chunk = points[i:i + 100]
        lon = "|".join(str(p[0]) for p in chunk)
        lat = "|".join(str(p[1]) for p in chunk)
        r = SESSION.get(ELEVATION_API, params={
            "lon": lon, "lat": lat, "resource": "ign_rge_alti_wld", "zonly": "true",
        }, timeout=30)
        r.raise_for_status()
        out.extend(r.json()["elevations"])
    return out


def build_mountain_points():
    cache_file = RAW / "mountain_points_1000m.json"
    if cache_file.exists():
        return json.loads(cache_file.read_text())

    print("Building mountain point cloud (IGN elevation grid over known massifs)…")
    mountain_points = []
    for name, (lon0, lat0, lon1, lat1, step) in MASSIF_BBOXES_DEG.items():
        grid = []
        lon = lon0
        while lon <= lon1:
            lat = lat0
            while lat <= lat1:
                grid.append((lon, lat))
                lat += step
            lon += step
        elevations = elevation_batch(grid)
        kept = [(p[0], p[1]) for p, e in zip(grid, elevations) if e is not None and e >= MOUNTAIN_ELEVATION_THRESHOLD_M]
        print(f"  {name}: {len(kept)}/{len(grid)} grid points >= {MOUNTAIN_ELEVATION_THRESHOLD_M}m")
        mountain_points.extend(kept)

    cache_file.write_text(json.dumps(mountain_points))
    return mountain_points

WGS84_CRS = "EPSG:4326"


def local_aeqd(lon, lat):
    return f"+proj=aeqd +lat_0={lat} +lon_0={lon} +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs"


def to_local(geom, lon, lat):
    transformer = Transformer.from_crs(WGS84_CRS, local_aeqd(lon, lat), always_xy=True)
    return shp_transform(transformer.transform, geom)


def expanding_bbox_fetch(typenames_list, center_lon, center_lat, base_deg=0.3, max_deg=20.0, count=2000, predicate=None):
    """Fetch features from one or more WFS layers, growing the bbox around
    (center_lon, center_lat) until at least one feature is found — or, if
    `predicate` is given, until at least one *matching* feature is found
    (e.g. only importance=1 "major" rivers, which aren't in every bbox the
    way any cours d'eau is)."""
    deg = base_deg
    while deg <= max_deg:
        bbox = (center_lon - deg, center_lat - deg, center_lon + deg, center_lat + deg)
        feats = []
        for tn in typenames_list:
            if tn is None:
                continue
            data = wfs_get(tn, count=count, bbox=bbox)
            feats.extend(data.get("features", []))
        matching = feats if predicate is None else [f for f in feats if predicate(f)]
        if matching:
            return matching, deg
        deg *= 2.5
    return [], deg


def wfs_get_all(typenames, bbox, page_size=2000, max_total=10000):
    """Paginated WFS fetch of every feature intersecting bbox (up to max_total)."""
    feats = []
    start = 0
    while start < max_total:
        params = {
            "SERVICE": "WFS", "VERSION": "2.0.0", "REQUEST": "GetFeature",
            "TYPENAMES": typenames, "OUTPUTFORMAT": "application/json",
            "COUNT": page_size, "STARTINDEX": start,
            "BBOX": f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]},urn:ogc:def:crs:OGC::CRS84",
        }
        r = SESSION.get(WFS, params=params, timeout=60)
        r.raise_for_status()
        data = r.json()
        page = data.get("features", [])
        feats.extend(page)
        if len(page) < page_size:
            break
        start += page_size
    return feats


def coverage_within_department(dept_local, dept_geom_wgs84, typenames_list, lon, lat, kind):
    """Area (km², kind='area') or length (km, kind='length') of features
    clipped to the département polygon — used for criteria (lacs, forêts)
    that are so common a "nearest distance" is ~0 almost everywhere in
    France and carries no signal. Geometries are unioned before measuring
    so that overlapping features (e.g. a parc naturel régional overlapping a
    forêt domaniale) aren't double-counted — otherwise forest coverage can
    exceed 100% of the département's own area, which is impossible."""
    bbox = dept_geom_wgs84.bounds
    clipped_geoms = []
    for tn in typenames_list:
        if tn is None:
            continue
        feats = wfs_get_all(tn, bbox)
        for f in feats:
            try:
                g = shape(f["geometry"])
                if g.is_empty:
                    continue
            except Exception:
                continue
            g_local = to_local(g, lon, lat)
            clipped = g_local.intersection(dept_local)
            if not clipped.is_empty:
                clipped_geoms.append(clipped)
    if not clipped_geoms:
        return 0.0
    merged = unary_union(clipped_geoms)
    if kind == "area":
        return merged.area / 1_000_000.0
    return merged.length / 1000.0


def _river_importance(feature):
    try:
        return int(feature["properties"].get("importance"))
    except (TypeError, ValueError):
        return 5


def min_distance_km(dept_geom_local, features, lon, lat):
    if not features:
        return None
    geoms = []
    for f in features:
        try:
            g = shape(f["geometry"])
            if g.is_empty:
                continue
            geoms.append(to_local(g, lon, lat))
        except Exception:
            continue
    if not geoms:
        return None
    tree = STRtree(geoms)
    idx = tree.nearest(dept_geom_local)
    nearest = geoms[idx]
    return dept_geom_local.distance(nearest) / 1000.0


def main():
    print("Fetching départements…")
    dept_features = fetch_departements()
    print(f"  {len(dept_features)} départements")

    print("Fetching régions…")
    region_names = fetch_regions()

    print("Fetching countries (Natural Earth)…")
    country_features = fetch_countries()
    country_geoms_wgs84 = []
    for f in country_features:
        if f["properties"].get("NAME") == "France":
            continue
        try:
            g = shape(f["geometry"])
            if not g.is_empty:
                country_geoms_wgs84.append(g)
        except Exception:
            continue
    print(f"  {len(country_geoms_wgs84)} neighboring-country geometries loaded")

    mountain_points = build_mountain_points()
    print(f"Mountain point cloud: {len(mountain_points)} points >= {MOUNTAIN_ELEVATION_THRESHOLD_M}m")
    from shapely.geometry import MultiPoint

    results = []
    n = len(dept_features)
    for i, f in enumerate(dept_features):
        props = f["properties"]
        code_insee = props["code_insee"]
        nom = props["nom_officiel"]
        code_region = props["code_insee_de_la_region"]
        dept_geom_wgs84 = shape(f["geometry"])
        centroid = dept_geom_wgs84.centroid
        lon, lat = centroid.x, centroid.y
        dept_local = to_local(dept_geom_wgs84, lon, lat)

        print(f"[{i+1}/{n}] {nom} ({code_insee})")

        distances = {}

        # pays étranger: nearest neighboring country (small dataset, no bbox windowing needed)
        country_local = [to_local(g, lon, lat) for g in country_geoms_wgs84]
        tree = STRtree(country_local)
        idx = tree.nearest(dept_local)
        distances["paysEtranger"] = dept_local.distance(country_local[idx]) / 1000.0
        print(f"    paysEtranger: {distances['paysEtranger']:.1f} km")

        # montagne: nearest point in the precomputed high-elevation cloud
        if mountain_points:
            from shapely.geometry import Point as ShpPoint
            mp_local = [to_local(ShpPoint(p[0], p[1]), lon, lat) for p in mountain_points]
            mtree = STRtree(mp_local)
            midx = mtree.nearest(dept_local)
            distances["montagne"] = dept_local.distance(mp_local[midx]) / 1000.0
        else:
            distances["montagne"] = None
        print(f"    montagne: {distances['montagne']:.1f} km" if distances["montagne"] is not None else "    montagne: NONE")

        for key, (tn1, tn2) in DISTANCE_LAYERS.items():
            feats, used_deg = expanding_bbox_fetch([tn1, tn2], lon, lat)
            d = min_distance_km(dept_local, feats, lon, lat)
            distances[key] = d
            print(f"    {key}: {d:.1f} km (bbox ±{used_deg:.2f}°, {len(feats)} feats)" if d is not None else f"    {key}: NONE")

        # fleuves: distance to the nearest *major* river (importance=1 —
        # le Rhône, la Saône, la Loire…), not "any cours d'eau" (saturates at
        # 0 km almost everywhere, see COVERAGE_LAYERS comment) and not
        # importance-weighted length (favors long rural départements over
        # ones like Rhône with a short but real river through their main
        # city) — this direclty answers "is there a real river nearby".
        # count=8000: importance=1 rivers are a small fraction of all cours
        # d'eau in a wide bbox — the default 2000-row cap could fill up with
        # minor streams before reaching one (verified: Corsica found none up
        # to the 20° max at count=2000, but found "le Rhône" at count=8000).
        feats, used_deg = expanding_bbox_fetch(
            ["BDTOPO_V3:cours_d_eau"], lon, lat,
            predicate=lambda f: _river_importance(f) <= 1, count=8000
        )
        distances["fleuves"] = min_distance_km(dept_local, feats, lon, lat)
        print(f"    fleuves: {distances['fleuves']:.1f} km (bbox ±{used_deg:.2f}°, {len(feats)} major rivers)" if distances["fleuves"] is not None else "    fleuves: NONE")

        area_geod_m2, _ = GEOD.geometry_area_perimeter(dept_geom_wgs84)
        dept_area_km2 = abs(area_geod_m2) / 1_000_000.0

        coverage = {}
        for key, (typenames, kind) in COVERAGE_LAYERS.items():
            raw = coverage_within_department(dept_local, dept_geom_wgs84, typenames, lon, lat, kind)
            density = raw / dept_area_km2  # fraction of département area covered
            coverage[key] = density
            print(f"    {key}: {raw:.1f} km² total ({density:.4f} density)")

        results.append({
            "code_insee": code_insee,
            "nom": nom,
            "code_region": code_region,
            "nom_region": region_names.get(code_region, code_region),
            "area_km2": dept_area_km2,
            "distances_km": distances,
            "coverage_density": coverage,
        })

        if i % 10 == 0:
            (OUT / "raw_distances_partial.json").write_text(json.dumps(results, ensure_ascii=False, indent=1))

    (OUT / "raw_distances.json").write_text(json.dumps(results, ensure_ascii=False, indent=1))
    print("Raw distances written to data/out/raw_distances.json")


if __name__ == "__main__":
    main()
