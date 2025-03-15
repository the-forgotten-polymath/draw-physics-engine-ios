import Foundation
import SwiftData

@MainActor
final class SolutionStore {
    let container: ModelContainer
    let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    convenience init(inMemory: Bool = false) throws {
        let schema = Schema([SolutionRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.init(container: container)
    }

    func save(_ record: SolutionRecord) {
        context.insert(record)
        try? context.save()
    }

    func records(forLevel levelID: String) throws -> [SolutionRecord] {
        let fetchDescriptor = FetchDescriptor<SolutionRecord>(
            predicate: #Predicate { $0.levelID == levelID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(fetchDescriptor)
    }

    func distinctSolutionCount(forLevel levelID: String) throws -> Int {
        let allRecords = try records(forLevel: levelID)
        var distinctCount = 0
        var seenSignatures = Set<String>()

        for record in allRecords {
            // "counts records whose stroke count or whose rounded ink cost differs"
            let roundedInk = Int(round(record.inkUsed))
            let signature = "\(record.strokeCount)-\(roundedInk)"
            if !seenSignatures.contains(signature) {
                seenSignatures.insert(signature)
                distinctCount += 1
            }
        }
        return distinctCount
    }
}
