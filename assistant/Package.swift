// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Assistant",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Assistant",
            path: "Sources/App",
            exclude: ["Info.plist"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("CoreAudio"),
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
