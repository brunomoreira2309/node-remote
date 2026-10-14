// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "NodeRemote",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NodeRemote", targets: ["NodeRemote"])],
    targets: [
        .executableTarget(
            name: "NodeRemote",
            exclude: ["README.md"],
            resources: [.copy("registration.json"), .copy("AppAssets"), .copy("app-catalog.json"), .copy("samsung-apps.json")]
        )
    ]
)
