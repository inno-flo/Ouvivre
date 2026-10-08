//
//  OuvivreApp.swift
//  Oùvivre
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
            ClassicRootView()
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button(mapState.isVisible ? "Masquer l'inspecteur" : "Afficher l'inspecteur") {
                    withAnimation(.easeInOut(duration: 0.28)) { mapState.isVisible.toggle() }
                }
            }
        }

        // Vue d'un département favori (double-clic dans la sidebar) — la
        // valeur de la scène est le code du département.
        WindowGroup("Département", id: DepartementWindowView.windowID, for: String.self) { $code in
            if let code { DepartementWindowView(departementCode: code) }
        }

        // Détail météo d'un département (double-clic sur la section Météo de
        // l'inspecteur) — la valeur de la scène est le code du département.
        WindowGroup("Climat", id: MeteoDetailView.windowID, for: String.self) { $code in
            if let code { MeteoDetailView(departementCode: code) }
        }

        // Données culturelles d'un département (icône de la rubrique CULTURE
        // de l'inspecteur) — la valeur de la scène est le code du département.
        WindowGroup("Culture", id: CultureDetailView.windowID, for: String.self) { $code in
            if let code { CultureDetailView(departementCode: code) }
        }
    }
}
