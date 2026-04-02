// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "PresencePeer",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "PresencePeer", targets: ["PresencePeer"])
  ],
  dependencies: [
    .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
  ],
  targets: [
    .executableTarget(
      name: "PresencePeer",
      dependencies: [
        .product(name: "Supabase", package: "supabase-swift")
      ]
    )
  ]
)
