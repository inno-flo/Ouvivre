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
    }
}
