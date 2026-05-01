// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftyWizard",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftyWizard",
            targets: ["SwiftyWizard"]
        ),
        .executable(
            name: "SwiftyWizardDemo",
            targets: ["SwiftyWizardDemo"]
        )
    ],
    targets: [
        .target(name: "SwiftyWizard"),
        .executableTarget(
            name: "SwiftyWizardDemo",
            dependencies: ["SwiftyWizard"]
        )
    ]
)
