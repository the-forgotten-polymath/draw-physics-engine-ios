import Foundation

/// `00_README.md` §4. A game may span bands, but must state how content and difficulty
/// differ per band — so the band is data every game reads, not a label in a store listing.
public enum AgeBand: String, Codable, CaseIterable, Sendable, Identifiable {
    case early
    case middle
    case upper

    public var id: String { rawValue }

    /// Child-facing name. Deliberately not an age range: a 7-year-old choosing "Starting
    /// out" is making a choice about difficulty, not being told they are behind.
    public var childFacingName: String {
        switch self {
        case .early: return "Starting Out"
        case .middle: return "Getting Good"
        case .upper: return "Tricky"
        }
    }

    /// Parent-facing only, behind the gate.
    public var ageRange: String {
        switch self {
        case .early: return "4–6"
        case .middle: return "7–9"
        case .upper: return "10–13"
        }
    }
}
