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

## communes_data.json (Big Mac — bloc Régions)

Builds `OuvivreKit/Sources/OuvivreKit/Resources/communes_data.json` — ~34 900 communes
françaises réelles (INSEE, nom, département, population, densité, catégorie de
taille, coordonnées) — remplace l'échantillon de 46 communes de
`CommuneSizeData.swift`.

### Source

data.gouv.fr dataset id `6745d9ae4524d845d2138193` — "Liste des communes de
France : code INSEE, codes postaux, EPCI, population, superficie - 62
indicateurs" :
https://www.data.gouv.fr/datasets/liste-des-communes-de-france-code-insee-codes-postaux-epci-population-superficie-62-indicateurs

Ressource utilisée (CSV 2026, ~35k lignes) :
https://static.data.gouv.fr/resources/communes-et-villes-de-france-en-csv-excel-json-parquet-et-feather/20260617-155950/communes-france-2026.csv

Le CSV inclut déjà `population`, `densite` et `latitude_centre`/`longitude_centre`
par commune — aucun calcul géométrique nécessaire, contrairement à
`france_geo_scores.json`. Seules les lignes `typecom == "COM"` sont gardées
(exclut les arrondissements municipaux de Paris/Lyon/Marseille pour éviter
les doublons de population).

### Run

```bash
python3 -m venv .venv && .venv/bin/pip install requests
.venv/bin/python build_communes_data.py   # télécharge le CSV (~20 Mo), écrit data/out/communes_data.json
cp data/out/communes_data.json ../OuvivreKit/Sources/OuvivreKit/Resources/
```

Pour une nouvelle édition annuelle, mettre à jour `CSV_URL` dans
`build_communes_data.py` avec la ressource la plus récente listée par
`GET https://www.data.gouv.fr/api/1/datasets/6745d9ae4524d845d2138193/`.

## culture_scores.json (Big Mac — bloc Culture)

Builds `OuvivreKit/Sources/OuvivreKit/Resources/culture_scores.json` — pour
chaque département, un score 0-100 (min-max normalisé) pour Musées, Lieux du
patrimoine et Festivals, dans le même format que `france_geo_scores.json`.

### Sources (culture.data.gouv.fr, hébergées par data.gouv.fr/Etalab)

- Musées : dataset id `61777ddaa9101d073e5506cd` (Base des lieux et
  équipements culturels, dite "Basilic") — filtré sur
  `Type équipement ou lieu == "Musée"` (1 843 lignes sur ~86k) :
  https://culture.data.gouv.fr/datasets/61777ddaa9101d073e5506cd
- Lieux du patrimoine : dataset id `628da9ff836d8bf454c7fd48` (Liste des
  sites patrimoniaux remarquables, SPR — comptage par `nombre_de_spr`) :
  https://culture.data.gouv.fr/datasets/628da9ff836d8bf454c7fd48
- Festivals : dataset id `62cf95993d99f22480f49334` (Liste des festivals en
  France) : https://culture.data.gouv.fr/datasets/62cf95993d99f22480f49334

Chaque ligne est rattachée à un département via son code INSEE commune (les
2 premiers chiffres, 3 pour les DOM `97x`/`98x`), puis les décomptes bruts
par département sont normalisés min-max sur les 101 départements — même
convention que `normalize_and_export.py`.

### Run

```bash
python3 -m venv .venv && .venv/bin/pip install requests
.venv/bin/python build_culture_data.py   # télécharge les 3 CSV, écrit data/out/culture_scores.json
cp data/out/culture_scores.json ../OuvivreKit/Sources/OuvivreKit/Resources/
```

Totaux vérifiés au dernier run : 1 838 musées, 1 131 SPR, 7 245 festivals
répartis sur 101 départements (aucune ligne perdue vs. les CSV sources).
