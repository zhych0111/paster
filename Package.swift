// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paster",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Paster", targets: ["Paster"]),
        .executable(name: "PasterSelfTests", targets: ["PasterSelfTests"])
    ],
    targets: [
        .target(name: "PasterCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Paster", dependencies: ["PasterCore"], linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("Carbon"),
            .linkedFramework("ApplicationServices")
        ]),
        .executableTarget(name: "PasterSelfTests", dependencies: ["PasterCore"])
    ],
    swiftLanguageModes: [.v5]
)
