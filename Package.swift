// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftyWizard",
    // Raised from iOS 16 / macOS 13 so the package can carry its own ActiveUI
    // wrapper, and raised to **15** to match where ActiveUI's other companion
    // packages sit — one story across the ecosystem rather than a wizard a
    // version behind everything it is drawn beside.
    //
    // `.macOS(.v15)` requires swift-tools-version 6.0, which also puts this
    // package in Swift 6 language mode. Done deliberately rather than opted out
    // of with `swiftLanguageModes: [.v5]`: the concurrency checking is the
    // point of the version, and a framework that ships to other people should
    // not be the last thing holding a consumer back.
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftyWizard",
            targets: ["SwiftyWizard"]
        ),
        .executable(
            name: "SwiftyWizardDemo",
            targets: ["SwiftyWizardDemo"]
        ),
        // The ActiveUI wrapper, beside the SwiftUI one. A separate *product* so
        // an app that wants the SwiftUI wizard does not link ActiveUI, and an
        // ActiveUI app does not link SwiftUI — one engine, two peers, neither
        // of them the real one.
        .library(
            name: "SwiftyWizardActiveUI",
            targets: ["SwiftyWizardActiveUI"]
        )
    ],
    dependencies: [
        .package(path: "/Users/bobby/AIResearch/ActiveUI/Code/ActiveUI")
    ],
    targets: [
        .target(name: "SwiftyWizard"),
        .target(
            name: "SwiftyWizardActiveUI",
            dependencies: [
                "SwiftyWizard",
                .product(name: "ActiveUI", package: "ActiveUI")
            ]
        ),
        .executableTarget(
            name: "SwiftyWizardDemo",
            dependencies: ["SwiftyWizard"],
            resources: [
                .process("Resources")
            ]
        ),
        // The wizard's rules — parsing, validation, navigation, templating —
        // were untestable while they lived inside a SwiftUI view. They are
        // `WizardEngine` now, so they can be.
        .testTarget(
            name: "SwiftyWizardTests",
            dependencies: ["SwiftyWizard"]
        ),
        .testTarget(
            name: "SwiftyWizardActiveUITests",
            dependencies: ["SwiftyWizardActiveUI"]
        )
    ]
)
