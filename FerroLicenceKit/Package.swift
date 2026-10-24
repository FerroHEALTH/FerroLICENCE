// swift-tools-version: 6.4
//
// FerroLicenceKit: everything FerroLICENCE does, without a window.
//
// LicenceCore is the licence format and the nine checks FerroEHR runs, tied to
// FerroEHR's checker by the vectors in Tests/LicenceCoreTests/Vectors. Register
// is the register in memory, Signing drives GnuPG and the YubiKey, GitHubKit
// talks to the repository through the FerroLICENCE GitHub App. register-check
// is the command the Register check workflow runs on every pull request.

import PackageDescription

// Swift 6 language mode with the approachable-concurrency defaults the app
// target uses too: async functions run on their caller's actor unless marked
// `@concurrent`, and conformances take their type's isolation.
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "FerroLicenceKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "LicenceCore", targets: ["LicenceCore"]),
        .library(name: "Register", targets: ["Register"]),
        .library(name: "Signing", targets: ["Signing"]),
        .library(name: "GitHubKit", targets: ["GitHubKit"]),
        .executable(name: "register-check", targets: ["register-check"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.2")
    ],
    targets: [
        .target(name: "LicenceCore", resources: [.process("Localizable.xcstrings")], swiftSettings: strict),
        .target(name: "Register", dependencies: ["LicenceCore"], resources: [.process("Localizable.xcstrings")], swiftSettings: strict),
        .target(
            name: "Signing", dependencies: ["LicenceCore", "Register", .product(name: "Subprocess", package: "swift-subprocess")],
            resources: [.process("Localizable.xcstrings")], swiftSettings: strict),
        .target(name: "GitHubKit", dependencies: ["Register"], resources: [.process("Localizable.xcstrings")], swiftSettings: strict),
        .executableTarget(name: "register-check", dependencies: ["LicenceCore", "Register"], swiftSettings: strict),
        .testTarget(name: "LicenceCoreTests", dependencies: ["LicenceCore"], resources: [.copy("Vectors")], swiftSettings: strict),
        .testTarget(name: "RegisterTests", dependencies: ["Register", "LicenceCore"], swiftSettings: strict),
        .testTarget(name: "SigningTests", dependencies: ["Signing", "Register", "LicenceCore"], swiftSettings: strict),
        .testTarget(name: "GitHubKitTests", dependencies: ["GitHubKit", "Register"], swiftSettings: strict),
    ]
)
