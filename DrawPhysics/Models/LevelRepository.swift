import Foundation

/// Loads authored levels from `Resources/Levels/*.json`.
///
/// Loudly, on purpose. A missing or malformed level file is a build/packaging mistake, and
/// silently falling back to a built-in level would hide it until a child hit an empty
/// level list. `LevelIntegrityTests` runs this same loader, so the mistake surfaces in CI.
public struct LevelRepository {

    public enum LoadError: Error, CustomStringConvertible {
        case levelsDirectoryMissing(bundle: String)
        case noLevelFiles(directory: String)
        case decodeFailed(file: String, underlying: String)
        case duplicateIdentifier(String)

        public var description: String {
            switch self {
            case let .levelsDirectoryMissing(bundle):
                return """
                Levels/ was not found in \(bundle). Add Resources/Levels to the target's \
                "Copy Bundle Resources" phase as a FOLDER REFERENCE (blue folder), not a group.
                """
            case let .noLevelFiles(directory):
                return "No .json level files in \(directory)."
            case let .decodeFailed(file, underlying):
                return "Level \(file) failed to decode: \(underlying)"
            case let .duplicateIdentifier(id):
                return "Two levels share the id \(id). Level ids are used as persistence keys."
            }
        }
    }

    public let bundle: Bundle
    public let subdirectory: String

    public init(bundle: Bundle = .main, subdirectory: String = "Levels") {
        self.bundle = bundle
        self.subdirectory = subdirectory
    }

    public func loadAll() throws -> [LevelDefinition] {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory),
              !urls.isEmpty else {
            guard bundle.url(forResource: subdirectory, withExtension: nil) != nil else {
                throw LoadError.levelsDirectoryMissing(bundle: bundle.bundlePath)
            }
            throw LoadError.noLevelFiles(directory: subdirectory)
        }

        let decoder = JSONDecoder()
        var levels: [LevelDefinition] = []
        // Sorted by filename so level order is stable across filesystems. Directory
        // enumeration order is not guaranteed and a shuffling level list looks broken.
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data = try Data(contentsOf: url)
            do {
                levels.append(try decoder.decode(LevelDefinition.self, from: data))
            } catch {
                throw LoadError.decodeFailed(file: url.lastPathComponent,
                                             underlying: String(describing: error))
            }
        }

        var seen = Set<String>()
        for level in levels {
            guard seen.insert(level.id).inserted else {
                throw LoadError.duplicateIdentifier(level.id)
            }
        }
        return levels
    }

    public static func decode(from data: Data) throws -> LevelDefinition {
        try JSONDecoder().decode(LevelDefinition.self, from: data)
    }
}
