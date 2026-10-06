// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrackIt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TrackIt",
            path: "Sources/TrackIt",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
