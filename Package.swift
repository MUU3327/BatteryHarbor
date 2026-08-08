// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BatteryHarbor",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BatteryHarbor", targets: ["BatteryHarbor"])
    ],
    targets: [
        .executableTarget(
            name: "BatteryHarbor",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "BatteryHarborTests",
            dependencies: ["BatteryHarbor"]
        )
    ]
)
