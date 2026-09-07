// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DisplayWizard", platforms: [.macOS(.v14)], products: [.executable(name: "DisplayWizard", targets: ["DisplayWizard"])], targets: [.executableTarget(name: "DisplayWizard", swiftSettings: [.swiftLanguageMode(.v5)]), .testTarget(name: "DisplayWizardTests", dependencies: ["DisplayWizard"])])
