import Foundation
import Observation

/// Same-device roles. No accounts, no network, no matchmaking — relatedness means the people
/// already in the child's life (`00_README.md` §3.1).
public enum PlayerRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case one
    case two

    public var id: String { rawValue }
    public var next: PlayerRole { self == .one ? .two : .one }

    /// Named by colour AND shape everywhere it is shown, never colour alone.
    public var displayName: String { self == .one ? "Blue" : "Orange" }
    public var symbolName: String { self == .one ? "circle.fill" : "triangle.fill" }
}

@MainActor
@Observable
public final class TurnManager {
    public private(set) var current: PlayerRole
    public private(set) var completedTurns: Int = 0
    public var isEnabled: Bool

    public init(startingWith role: PlayerRole = .one, isEnabled: Bool = false) {
        self.current = role
        self.isEnabled = isEnabled
    }

    /// Hand-off is explicit and announced, because a pre-reader needs to know whose turn it
    /// is without being told by the adult they are playing against.
    public func endTurn(announce: (String) -> Void) {
        guard isEnabled else { return }
        completedTurns += 1
        current = current.next
        announce("\(current.displayName)'s turn.")
    }

    public func reset(to role: PlayerRole = .one) {
        current = role
        completedTurns = 0
    }
}
