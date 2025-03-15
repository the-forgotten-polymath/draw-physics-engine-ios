import Foundation

public struct CapabilityStatement: Equatable, Sendable {
    public let text: String
}

public final class DrawPhysicsProgress {
    private let store: SolutionStore
    
    init(store: SolutionStore) {
        self.store = store
    }
    
    @MainActor
    func statements(for level: LevelDefinition) throws -> [CapabilityStatement] {
        var results: [CapabilityStatement] = []
        
        // "You solved that level N different ways."
        let distinctCount = try store.distinctSolutionCount(forLevel: level.id)
        if distinctCount >= 2 {
            results.append(CapabilityStatement(text: "You solved that level \(distinctCount) different ways."))
        }
        
        return results
    }
}
