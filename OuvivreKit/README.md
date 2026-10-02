# OuvivreKit

Package Swift (macOS 14+) qui contient toute l'application Oùvivre : la cible
App `Ouvivre` (dans `../Ouvivre/`) n'en est qu'une coquille qui affiche
`ClassicRootView` et déclare les fenêtres de détail.

## API publique

- `ClassicRootView` — fenêtre principale (sidebar + écran + inspecteur).
- `MeteoDetailView`, `CultureDetailView` — fenêtres de détail d'un
  département (`windowID` + code du département comme valeur de scène).
- `MapPanelState.shared.isVisible` — visibilité de l'inspecteur, pilotée aussi
  par le menu Présentation de l'app.

Tout le reste est interne au package.

## Structure

```
Sources/OuvivreKit/
  Models/      ClassicState (état de l'app, favoris, classement des départements),
               ClassicData (libellés, pays), MapPanelState (carte + inspecteur),
               données embarquées : FranceGeoData (proximités), CultureScores,
               CommuneSizeData, MeteoMensuelle, DepartementBoundaries,
               DatasetFreshness (vérification de fraîcheur sur data.gouv.fr)
  Theme/       ClassicTheme (palette, métriques), CFont, DetailColors (clair/sombre)
  Components/  SidebarNav, InspectorPanelView, CriterionRow (réglette), SelecteurBlocks,
               DepartementMapCard, DepartementDetailHeader, FlowLayout, MapPlanType…
  Screens/     ClassicRootView, SelecteurView (carte plein cadre + réglages),
               FavorisView (comparatif), DepartementView, MeteoDetailView,
               CultureDetailView, SourcesView
  Resources/   JSON générés par ../geo_pipeline
```

Écrans de la sidebar : **Sélecteur** (carte + colonne de réglages, inspecteur
au clic sur un département), **Favoris** (tableau comparatif + vue de chaque
département favori) et **Sources** (références open data et fraîcheur).
