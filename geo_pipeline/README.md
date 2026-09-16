# geo_pipeline

Builds `OuvivreKit/Sources/OuvivreKit/Resources/france_geo_scores.json` — real, per-département (101, incl. overseas) proximity scores for the 6 Géographie criteria, from IGN and Natural Earth open geometry. Not run by the app; a one-time (or periodically re-run) offline build.

## Sources

- Département/région boundaries: IGN BD TOPO V3, WFS `data.geopf.fr` (`BDTOPO_V3:departement`, `BDTOPO_V3:region`)
- Mer: IGN BD TOPO V3 `limite_terre_mer` (coastline)
- Montagne: IGN elevation API (RGE ALTI) sampled on a grid restricted to France's known massifs (Alpes, Pyrénées, Massif central, Jura, Vosges, Corse + DOM), threshold 1000 m — `ligne_orographique`/`detail_orographique` were tried first and rejected (embankments, or unfilterable by elevation)
- Lacs / forêts publiques: IGN BD TOPO V3 `plan_d_eau` / `foret_publique` + `parc_ou_reserve`, area coverage within each département (not distance — see below)
- Fleuves et rivières: IGN BD TOPO V3 `cours_d_eau`, length density within each département
- Pays étranger: Natural Earth `ne_50m_admin_0_countries` (neighboring country polygons)

`mer`, `montagne`, `paysEtranger` are distance-to-nearest-feature (min-max normalized, inverted). `lacs`, `fleuves`, `forets` are coverage density within the département instead — a first pass using "distance to nearest occurrence" gave 0.0 km for effectively every département (these features are too common at département scale to discriminate).

## Run

```bash
python3 -m venv .venv && .venv/bin/pip install shapely pyproj requests
.venv/bin/python build_france_geo_scores.py   # ~20 min, writes data/out/raw_distances.json
.venv/bin/python normalize_and_export.py       # writes data/out/france_geo_scores.json
cp data/out/france_geo_scores.json ../OuvivreKit/Sources/OuvivreKit/Resources/
```

`data/raw/` and `data/out/` are gitignored (raw IGN geometry alone is ~200 MB) — only the final `france_geo_scores.json` copied into OuvivreKit is committed.
