// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "openssl_ios",
    products: [
        .library(name: "openssl_ios", targets: ["libssl", "libcrypto"]),
    ],
    targets: [
        .binaryTarget(name: "libssl", path: ".build/libssl.xcframework"),
        .binaryTarget(name: "libcrypto", path: ".build/libcrypto.xcframework"),
    ]
)
