# Ouvivre — notes de projet

## Compilation en ligne de commande

`xcode-select` pointe sur les Command Line Tools, sans SDK macOS 27 : passer par
Xcode-beta.

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Ouvivre/Ouvivre.xcodeproj -scheme Ouvivre -destination 'platform=macOS' build
```

## Infobulle de population au clic sur une localité — désactivée

**Objectif.** Un clic sur le nom d'une localité dessiné par MapKit affiche une
infobulle (nom, population, catégorie de taille). Cela concerne la carte
principale (`SelecteurView`) et la carte de département (`DepartementMapCard`).

**État (17/10/2026).** La fonction est désactivée. Le code est conservé en
commentaire et repérable par le marqueur
« Infobulle de population au clic sur une localité — désactivée, voir CLAUDE.md ».

### Où est le code

- `OuvivreKit/Sources/OuvivreKit/Models/CommuneLookup.swift` : tout le fichier
  est en commentaire de bloc. Il contient :
  - `CommuneInfo` ;
  - `CommuneLookup`, qui décode `communes_data.json` à la première demande et
    propose :
    - `preload()` ;
    - `communes(latitudes:longitudes:)` ;
    - `commune(near:halfWidth:halfHeight:)`, qui choisit parmi les communes dont
      le centre tombe dans une ellipse autour du clic, au score
      population^0,3 / (distance² + 0,03).
- `OuvivreKit/Sources/OuvivreKit/Components/CommuneInfoCard.swift` : tout le
  fichier est en commentaire de bloc. Il contient :
  - `CommuneTooltip`, qui convertit le clic et une ellipse de 45 × 14 pt en
    degrés via `MapProxy` ;
  - `CommuneInfoCard`, la vue de l'infobulle ;
  - `MapCameraTracker`, un `@Observable` qui suit la région en continu ;
  - `CommuneTooltipOverlay`, la surimpression SwiftUI ;
  - `CommuneHitZonesOverlay`, l'outil de mise au point (zones de clic en violet
    à 50 % et point sur le centre de chaque commune, activé par `isEnabled`).
- `DepartementMapCard.swift` et `SelecteurView.swift` : lignes commentées. Ce
  sont les états `communeTooltip` et `tooltipCamera`, l'affectation dans le
  geste de clic, les deux `.overlay`, `onMapCameraChange(frequency: .continuous)`
  et le `.task` de préchargement.

**Réactiver.** Retirer les lignes `/*` et `*/` des deux fichiers dédiés, puis
décommenter les lignes marquées dans les deux cartes.

### Données (restées actives)

`communes_data.json` a été régénéré avec les coordonnées de la **mairie**.
`geo_pipeline/build_communes_data.py` prend la mairie, puis le centre
géométrique si elle manque (5 communes). Côté app, seule l'infobulle utilisait
`lat`/`lon` ; `build_meteo_data.py` les relira lors d'une prochaine
régénération de la météo.

### Ce qui a été essayé

1. **Sélection native MapKit.** `Map(selection:)` avec `MapFeature` est
   impossible sur macOS, car `MapFeature` n'y est pas `Hashable`. Avec
   `MapSelection<String>`, le code compile (paquet passé à macOS 15), mais
   aucun clic sur un nom de localité ne déclenche la sélection sur macOS.
   Abandonné ; le paquet est revenu à macOS 14.
2. **Rapprochement maison.** Le clic est converti en coordonnée, puis
   rapproché d'une commune dont le centre est proche, dans une ellipse en
   points écran autour du clic. Trois règles de choix ont été essayées :
   - la commune la plus peuplée, avec un seuil de population selon le zoom :
     comportement aléatoire ;
   - un score population / distance² : les grandes communes voisines
     l'emportaient ;
   - un score population^0,3 / (distance² + 0,03), où la proximité domine :
     c'est la version conservée.
3. **Infobulle en `Annotation` MapKit.** MapKit la masquait quand elle
   chevauchait ses propres étiquettes. Elle a été remplacée par une
   surimpression SwiftUI placée via `proxy.convert`, qui suit la caméra.
4. **Diagnostic.** Les zones violettes ont montré que les noms MapKit sont
   souvent loin des centres de commune. Le centre géométrique
   (`latitude_centre`) est à 0,75 km de la mairie en médiane (1,7 km pour
   90 % des communes). Le passage aux coordonnées de mairie a nettement
   amélioré les résultats, mais **reste insuffisant**. Les mairies tombent
   souvent hors de l'ellipse, surtout quand on zoome : l'ellipse a une taille
   fixe en points alors que l'écart se mesure en kilomètres. MapKit n'expose
   pas la position de ses étiquettes.

### Pistes non explorées

- Dessiner nos propres noms de communes, cliquables, dont la position est
  connue exactement, au lieu de deviner celle des étiquettes MapKit.
- Une zone de clic exprimée en distance (km) plutôt qu'en points, au-delà d'un
  certain niveau de zoom.
- Une infobulle de la commune sous le clic, à partir des contours communaux
  (ex. ADMIN EXPRESS de l'IGN), sans dépendre des étiquettes.
