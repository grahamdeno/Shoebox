// swift-tools-version: 6.2
import PackageDescription

// ShoeboxCore holds the rules that must be right and must be testable without a phone:
// the value types, the old-backup importer, and later the return planner's plain rules.
// Foundation and CryptoKit only. No UI, no SwiftData.
let package = Package(
    name: "ShoeboxCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "ShoeboxCore", targets: ["ShoeboxCore"])],
    targets: [
        .target(name: "ShoeboxCore"),
        .testTarget(name: "ShoeboxCoreTests", dependencies: ["ShoeboxCore"], resources: [.copy("Fixtures")]),
    ]
)
