// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "carttool",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0"),
        .package(url: "https://github.com/xcodeswift/xcproj.git", .upToNextMajor(from: "4.3.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "carttool",
            dependencies: ["CartToolCore"]),
	.target(name: "CartToolCore",
        dependencies: ["Utility", "xcproj"]),
	.testTarget(
	    name: "CartToolTests",
	    dependencies: ["CartToolCore"]
	)	
    ]
)

