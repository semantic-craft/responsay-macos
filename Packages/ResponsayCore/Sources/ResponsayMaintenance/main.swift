import Foundation
import ResponsayCore

struct MigrationSmokeReport: Codable {
    let sourceDirectory: String
    let workDirectory: String
    let capturesExists: Bool
    let capturesCount: Int
    let reviewCount: Int
    let schemaVersion: Int
    let sourceCapturesStillExists: Bool
    let databaseExists: Bool
}

@main
struct ResponsayMaintenance {
    static func main() throws {
        let command = CommandLine.arguments.dropFirst().first
        guard command == "review-migration-smoke" else {
            throw UsageError("Usage: ResponsayMaintenance review-migration-smoke [--source DIR] [--work-dir DIR]")
        }

        let options = try parseOptions(Array(CommandLine.arguments.dropFirst().dropFirst()))
        let sourceDirectory = options.sourceDirectory ?? defaultAppSupportDirectory()
        let workDirectory = options.workDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("responsay-review-migration-\(UUID().uuidString)", isDirectory: true)

        let report = try runReviewMigrationSmoke(
            sourceDirectory: sourceDirectory,
            workDirectory: workDirectory)
        let data = try JSONEncoder.pretty.encode(report)
        guard let json = String(data: data, encoding: .utf8) else {
            throw UsageError("Unable to encode smoke report.")
        }
        print(json)
    }

    private static func runReviewMigrationSmoke(
        sourceDirectory: URL,
        workDirectory: URL
    ) throws -> MigrationSmokeReport {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let sourceCapturesURL = sourceDirectory.appendingPathComponent("captures.json")
        let copiedCapturesURL = workDirectory.appendingPathComponent("captures.json")
        let capturesExists = fileManager.fileExists(atPath: sourceCapturesURL.path)
        var capturesCount = 0

        if capturesExists {
            if fileManager.fileExists(atPath: copiedCapturesURL.path) {
                try fileManager.removeItem(at: copiedCapturesURL)
            }
            try fileManager.copyItem(at: sourceCapturesURL, to: copiedCapturesURL)
            let data = try Data(contentsOf: copiedCapturesURL)
            capturesCount = try JSONDecoder().decode([CaptureItem].self, from: data).count
        }

        let databaseURL = workDirectory.appendingPathComponent("review.sqlite")
        let store = try SQLiteReviewStore(
            databaseURL: databaseURL,
            importCapturesFrom: capturesExists ? copiedCapturesURL : nil)
        let reviewCount = try store.count()
        let schemaVersion = try store.schemaVersion()

        return MigrationSmokeReport(
            sourceDirectory: sourceDirectory.path,
            workDirectory: workDirectory.path,
            capturesExists: capturesExists,
            capturesCount: capturesCount,
            reviewCount: reviewCount,
            schemaVersion: schemaVersion,
            sourceCapturesStillExists: fileManager.fileExists(atPath: sourceCapturesURL.path),
            databaseExists: fileManager.fileExists(atPath: databaseURL.path))
    }

    private static func parseOptions(_ args: [String]) throws -> Options {
        var sourceDirectory: URL?
        var workDirectory: URL?
        var index = 0
        while index < args.count {
            let arg = args[index]
            func next() throws -> String {
                index += 1
                guard index < args.count else { throw UsageError("\(arg) requires a value.") }
                return args[index]
            }

            switch arg {
            case "--source":
                sourceDirectory = URL(fileURLWithPath: try next(), isDirectory: true)
            case "--work-dir":
                workDirectory = URL(fileURLWithPath: try next(), isDirectory: true)
            default:
                throw UsageError("Unknown argument: \(arg)")
            }
            index += 1
        }
        return Options(sourceDirectory: sourceDirectory, workDirectory: workDirectory)
    }

    private static func defaultAppSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppBrand.appSupportDirectoryName, isDirectory: true)
    }
}

private struct Options {
    let sourceDirectory: URL?
    let workDirectory: URL?
}

private struct UsageError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
