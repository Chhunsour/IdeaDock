// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IdeaDock",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "IdeaDock", targets: ["IdeaDock"])],
    targets: [.executableTarget(name: "IdeaDock", resources: [.copy("Resources/PrivacyInfo.xcprivacy")])],
    swiftLanguageModes: [.v5]
)
