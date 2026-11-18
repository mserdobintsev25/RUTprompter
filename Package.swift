// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RUTprompter",
    platforms: [.macOS(.v13)],
    targets: [
        // Чистая логика без AppKit: разбор скрипта, сопоставление речи,
        // темп, ETA, анализ дублей. Проверяется таргетом CoreChecks.
        .target(
            name: "PrompterCore",
            path: "Sources/PrompterCore"
        ),
        .executableTarget(
            name: "RUTprompter",
            dependencies: ["PrompterCore"],
            path: "Sources/RUTprompter"
        ),
        // `swift run CoreChecks` — самопроверка логики (XCTest в Command
        // Line Tools недоступен, поэтому простой исполняемый таргет).
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["PrompterCore"],
            path: "Sources/CoreChecks"
        )
    ]
)
