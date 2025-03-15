import Foundation
import SwiftData

@Model final class SolutionRecord {
    @Attribute(.unique) var id: UUID
    var levelID: String
    /// JSON-encoded `SolutionPayload`. Stored as Data rather than a relationship because a
    /// stroke list is opaque to queries and a versioned blob survives format changes.
    var payload: Data
    /// The authoritative verdict from the ORIGINAL run. `private(set)`-equivalent by
    /// convention plus the test in §18.14; SwiftData cannot express `let`.
    var didReachGoal: Bool
    var inkUsed: Double
    var strokeCount: Int
    var stepsToGoal: Int
    var createdAt: Date

    init(payload: SolutionPayload, outcome: SolutionOutcome) throws {
        self.id = UUID()
        self.levelID = payload.levelID
        let encoder = JSONEncoder()
        self.payload = try encoder.encode(payload)
        self.didReachGoal = outcome.didReachGoal
        self.inkUsed = outcome.inkUsed
        self.strokeCount = outcome.strokeCount
        self.stepsToGoal = outcome.stepsToGoal ?? 0
        self.createdAt = Date()
    }

    func decodedPayload() throws -> SolutionPayload {
        let decoder = JSONDecoder()
        return try decoder.decode(SolutionPayload.self, from: self.payload)
    }
}
