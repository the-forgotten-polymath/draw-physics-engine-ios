import Foundation

/// A true, checkable statement about what the child has actually done.
///
/// There is deliberately **no numeric score type in this package**, and no initialiser that
/// produces a statement without evidence. `00_README.md` §2.2 forbids skill scores; making
/// that structural rather than a policy means a future contributor cannot add one by
/// accident, only by deleting this comment and rewriting the type.
public struct CapabilityStatement: Equatable, Identifiable, Sendable {
    public let id: String
    /// What the child reads or hears. Always a fact: "You solved that level three
    /// different ways", never a judgement and never a rating.
    public let text: String
    public let evidence: Evidence

    public struct Evidence: Equatable, Sendable {
        /// What was counted, e.g. "distinctSolutions". Free-form because each game counts
        /// something different, and forcing a shared enum would push games into pretending
        /// they measure the same thing.
        public let kind: String
        public let observedCount: Int
        /// Below this the statement is not made. A single success is luck; a capability
        /// claim needs repetition.
        public let minimumRequired: Int

        public init(kind: String, observedCount: Int, minimumRequired: Int) {
            self.kind = kind
            self.observedCount = observedCount
            self.minimumRequired = minimumRequired
        }

        public var isSufficient: Bool { observedCount >= minimumRequired }
    }

    /// Fails rather than fudges. A statement with insufficient evidence is not a weaker
    /// statement, it is a false one.
    public init?(id: String, text: String, evidence: Evidence) {
        guard evidence.isSufficient else { return nil }
        self.id = id
        self.text = text
        self.evidence = evidence
    }
}
