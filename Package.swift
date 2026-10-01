// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenClawMobile",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "OpenClawKit", targets: ["OpenClawKit"]),
    ],
    targets: [
        .target(name: "OpenClawKit", path: "OpenClawKit/Sources"),
        .testTarget(name: "OpenClawKitTests", dependencies: ["OpenClawKit"], path: "OpenClawKit/Tests"),
    ]
)
