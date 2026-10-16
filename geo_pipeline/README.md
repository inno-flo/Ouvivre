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

Le CSV inclut déjà `population`, `densite` et les coordonnées de la mairie
(`latitude_mairie`/`longitude_mairie`) et du centre géométrique
(`latitude_centre`/`longitude_centre`) par commune — aucun calcul géométrique
nécessaire, contrairement à `france_geo_scores.json`. Les coordonnées gardées
sont celles de la mairie (le centre seulement si elle manque) : Apple Plans
écrit le nom d'une localité sur son bourg, et l'infobulle de population des
cartes repère le clic sur ce nom. Seules les lignes `typecom == "COM"` sont gardées
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

## Score "mer" — distance en sauts au littoral (recompute_mer_score.py)

Remplace, dans `france_geo_scores.json`, le score "mer" d'origine (distance
continue min-max) par un score fondé sur le nombre de départements à
traverser pour atteindre un vrai littoral : 100 si le département est
lui-même côtier, puis 75/50/25/0 à mesure qu'on s'en éloigne (un saut =
un département voisin). Objectif : que "Mer et océan" à "déterminant"
(poids max) fasse remonter les départements réellement côtiers, et
"important" ceux à un saut du littoral — l'ancien score continu faisait
remonter des départements très intérieurs (Haute-Vienne, Loiret, Sarthe)
autour de 65-80/100 simplement parce que le minimum de la plage se
trouvait très à l'est (Alsace/Belfort).

Les départements côtiers sont une **liste statique** (`COASTAL_CODES` dans
le script), pas un calcul géométrique : une première version dérivait le
littoral par différence entre les polygones IGN et les polygones pays
voisins (Natural Earth), mais les tracés de frontière des deux jeux de
données ne coïncident pas assez finement — tous les départements
frontaliers (Bas-Rhin, Haut-Rhin, Moselle, Meurthe-et-Moselle, Meuse,
Ardennes, Doubs, Savoie, Haute-Garonne, Ariège, Hautes-Alpes, Territoire de
Belfort...) ressortaient "côtiers" à cause de résidus de décalage le long
de leur frontière terrestre, quel que soit le réglage de la marge
d'exclusion. La question "quels départements ont un littoral" étant une
géographie parfaitement établie, une liste statique est plus fiable qu'une
géométrie fragile entre deux sources hétérogènes.

L'adjacence entre départements (pour le calcul des sauts), en revanche,
reste géométrique (polygones IGN uniquement, internes à la France — pas de
confrontation à un autre jeu de données), et est vérifiée automatiquement
(voisins attendus de la Haute-Vienne).

### Run

```bash
.venv/bin/python recompute_mer_score.py   # relit/réécrit directement france_geo_scores.json
```

Ne nécessite aucun nouveau téléchargement (réutilise `data/raw/departements.json`,
déjà en cache depuis `build_france_geo_scores.py`).

## meteo_monthly.json (Inspecteur — section Météo)

Températures moyennes (`TM`, °C) et précipitations (`RR`, mm) mensuelles par
département, de janvier de N-5 (année complète) au mois courant de N,
depuis les données climatologiques mensuelles de Météo-France :
https://meteo.data.gouv.fr/datasets/6569b3d7d193b4daf2b43edc

Un fichier CSV.gz par département et par période (`previous-1950-2024`,
`latest-2025-2026`). Chaque département = moyenne des postes pondérée par la population (chaque
commune est rattachée au poste le plus proche ayant une mesure ce mois-là) ; le mois
courant est partiel (`partial: true`). Corse : fichier unique "20" réparti en
2A/2B via la commune INSEE du poste. Mayotte (976) n'est pas publiée.

```bash
.venv/bin/python build_meteo_data.py   # ~100 fichiers, écrit data/out/meteo_monthly.json
cp data/out/meteo_monthly.json ../OuvivreKit/Sources/OuvivreKit/Resources/
```

La température ressentie (`tr`) n'est pas publiée par Météo-France : elle est
calculée depuis TM, l'humidité (UMM) et le vent (FFM) moyens du département —
indice de chaleur ≥ 27 °C, refroidissement éolien ≤ 10 °C, sinon `tm`. Estimation
indicative sur moyennes mensuelles.

À relancer pour rafraîchir (la fenêtre glisse avec la date du jour).
