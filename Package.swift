// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpokeServer",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "SpokeServer", targets: ["SpokeServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
        .package(url: "https://github.com/OpenKitten/MongoKitten.git", .branch("master/6.0"))
    ],
    targets: [
        .target(
            name: "SpokeServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "MongoKitten", package: "MongoKitten"),
                .product(name: "Meow", package: "MongoKitten")
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-disable-availability-checking",
                ])
            ]
        ),
        .testTarget(
            name: "SpokeServerTests",
            dependencies: ["SpokeServer"]),
    ]
)
