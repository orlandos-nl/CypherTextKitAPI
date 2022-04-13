// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "API",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "API", targets: ["API"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
        .package(url: "https://github.com/joannis/IkigaJSON.git", from: "2.0.0"),
        .package(url: "https://github.com/OpenKitten/MongoKitten.git", .branch("master/6.0")),
        .package(url: "https://github.com/vapor/apns.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "API",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "MongoKitten", package: "MongoKitten"),
                .product(name: "Meow", package: "MongoKitten"),
                .product(name: "APNS", package: "apns"),
                .product(name: "IkigaJSON", package: "IkigaJSON"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-disable-availability-checking",
                ])
            ]
        ),
        .testTarget(
            name: "APITests",
            dependencies: ["API"]),
    ]
)
