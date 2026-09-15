# OuvivreKit — thème "classic"

Reproduction SwiftUI du thème "classic" d'Ouvivre (`../Ouvivre classic.dc.html`) :
interface éditoriale claire avec sidebar de navigation, 7 écrans (Pays,
Géographie, Météo, Affiner, Fiche ville, Comparateur, Mon espace). Données
entièrement mockées (mêmes valeurs que l'export dc), aucun appel réseau.

## Structure

```
Sources/OuvivreKit/
  Models/   ClassicData (données statiques), ClassicState (écran + curseurs,
            ObservableObject), ClassicDerived (valeurs calculées, miroir de renderVals())
  Theme/    couleurs, densité, ClassicTheme (accent configurable)
  Components/ SidebarNav, CriterionRow (slider à poignée), Card, boutons,
              MiniBar, PhotoPlaceholder, FlowLayout, AdaptiveTwoColumn
  Screens/  ClassicRootView (shell + sidebar/nav compacte), PaysView, GeoView,
            MeteoView, AffinerView, VilleView, CompareView, ProfilView
```

`ClassicRootView` est le point d'entrée unique : il possède `ClassicTheme` et
`ClassicState`, affiche la sidebar (≥720pt de large) ou une barre de nav
horizontale (< 720pt, iPhone), et bascule entre les 7 écrans.

## La target Xcode

La target App s'appelle **`Ouvivre`** (renommée depuis `OuvivreApp`) et vit
à côté de ce package, pas dedans :

```
Ouvivre/                    ← racine du dépôt
  OuvivreKit/                ← ce package (ne pas toucher)
  Ouvivre/                   ← dossier du projet Xcode
    Ouvivre.xcodeproj
    Ouvivre/                 ← sources de la target (ContentView.swift, OuvivreApp.swift, Assets.xcassets)
```

Elle dépend de `OuvivreKit` via **Add Package Dependencies… ▸ Add Local…**
(référence locale relative `../OuvivreKit`), et son `ContentView.swift`
instancie simplement :
```swift
import SwiftUI
import OuvivreKit

struct ContentView: View {
    var body: some View { ClassicRootView() }
}
```
Déploiement cible : iOS/iPadOS 16.0+, macOS 13.0+ (correspond au
`Package.swift`). Redimensionnez la fenêtre sur macOS : la sidebar bascule
en barre horizontale sous 720pt de large (comme sur iPhone).

### Polices (optionnel)

Le thème utilise **Archivo** (texte) et **IBM Plex Mono** (libellés/chiffres)
depuis Google Fonts. `CFont.sans`/`CFont.mono` retombent sur les polices
système si elles ne sont pas embarquées — ajoutez les `.ttf` à la target App
(pas au package) et déclarez-les dans `Info.plist` (`UIAppFonts`) pour une
fidélité complète.

## Vérifié jusqu'ici

- `swift build` réussit (macOS 13 / iOS 16).
- Pas encore testé dans une vraie target App/Simulateur — nécessite l'étape
  1-3 ci-dessus (besoin d'Xcode). Une fois la target créée, dites-le moi :
  je peux builder/lancer dans le Simulateur iOS pour vérifier visuellement.
