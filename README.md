# Oùvivre

Application macOS (SwiftUI) d'aide au choix d'un lieu de vie : on règle des
critères (pays, tailles de commune, proximités géographiques, culture) et la
carte affiche les départements français correspondants, classés par
pertinence. Toutes les données sont embarquées (open data préparé hors ligne) ;
le seul appel réseau vérifie, au plus tous les 15 jours, si les jeux de données
sources ont été mis à jour sur data.gouv.fr.

## Organisation du dépôt

```
Ouvivre/          projet Xcode de l'app (cible macOS « Ouvivre », point d'entrée OuvivreApp.swift)
OuvivreKit/       package Swift contenant toute l'interface, les modèles et les données (voir son README)
geo_pipeline/     scripts Python qui génèrent les JSON de OuvivreKit/Sources/OuvivreKit/Resources
Design/AppIcon/   script de génération de l'icône de l'app
*.dc.html, support.js  maquettes HTML d'origine (export Claude Design), pour référence visuelle
```

## Compiler

Ouvrir `Ouvivre/Ouvivre.xcodeproj` dans Xcode et lancer la cible `Ouvivre`
(macOS). Le package seul se compile avec `swift build` depuis `OuvivreKit/`.

## Mettre à jour les données

Les JSON embarqués sont produits par `geo_pipeline/` (procédure dans
`geo_pipeline/README.md`) ; l'app ne lance jamais ce pipeline elle-même. La vue
Sources signale quand un jeu de données amont est plus récent que la version
embarquée.
