// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Legado",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Legado",
            targets: ["Legado"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Legado",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "SwiftyJSON", package: "SwiftyJSON"),
            ],
            path: "Sources")
    ]
)
