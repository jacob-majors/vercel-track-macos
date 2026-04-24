// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeplogNative",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "DeplogNative", targets: ["DeplogNative"])
    ],
    targets: [
        .executableTarget(
            name: "DeplogNative",
            path: "Sources/DeplogNative"
        )
    ]
)
