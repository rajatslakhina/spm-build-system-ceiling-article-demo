// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModuleGraphRules",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ModuleGraphRules", targets: ["ModuleGraphRules"])
    ],
    targets: [
        .target(name: "ModuleGraphRules"),
        .testTarget(name: "ModuleGraphRulesTests", dependencies: ["ModuleGraphRules"])
    ]
)
