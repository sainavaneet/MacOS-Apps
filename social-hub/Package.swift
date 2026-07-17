// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SocialHub",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SocialHub",
            path: "Sources/App",
            exclude: ["Info.plist"],
            resources: [.process("Assets.xcassets")],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CoreLocation"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/App/Info.plist",
                ]),
            ]
        )
    ]
)
