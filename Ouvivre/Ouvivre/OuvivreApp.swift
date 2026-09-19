//
//  OuvivreApp.swift
//  Ouvivre
//
//  Created by Florian Innocente on 15/09/2026.
//

import SwiftUI
import OuvivreKit

@main
struct OuvivreApp: App {
    @StateObject private var mapState = MapPanelState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button(mapState.isVisible ? "Masquer la carte" : "Afficher la carte") {
                    mapState.isVisible.toggle()
                }
            }
        }

        // Détail météo d'un département (double-clic sur la section Météo de
        // l'inspecteur) — la valeur de la scène est le code du département.
        WindowGroup("Météo", id: MeteoDetailView.windowID, for: String.self) { $code in
            if let code { MeteoDetailView(departementCode: code) }
        }
    }
}
