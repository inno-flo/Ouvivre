// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OuvivreKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "OuvivreKit", targets: ["OuvivreKit"])
    ],
    targets: [
        .target(name: "OuvivreKit", resources: [
            .copy("Resources/france_geo_scores.json"),
            .copy("Resources/france_regions_boundaries.json"),
            .copy("Resources/france_departements_boundaries.json"),
            .copy("Resources/communes_data.json"),
            .copy("Resources/culture_scores.json"),
            .copy("Resources/meteo_monthly.json")
        ])
    ]
)
