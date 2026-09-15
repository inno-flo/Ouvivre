// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OuvivreKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "OuvivreKit", targets: ["OuvivreKit"])
    ],
    targets: [
        .target(name: "OuvivreKit")
    ]
)
