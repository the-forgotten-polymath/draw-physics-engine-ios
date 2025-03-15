import Foundation
import KidsGameCore

/// Maps the shared controller's single 0...1 parameter onto this game's axes.
///
/// Ink budget is the primary axis, because it is the axis that creates thinking (§5.4).
/// The others move in coarse steps and only between levels, never mid-attempt: changing
/// the rules under a child who is halfway through an idea reads as the game breaking.
public struct DrawPhysicsDifficulty: Equatable, Sendable {

    public let band: AgeBand
    public let parameter: Double

    public init(band: AgeBand, parameter: Double) {
        self.band = band
        self.parameter = parameter.clamped(to: 0...1)
    }

    /// Per-band ink range (§6). Generous end first.
    private var inkRange: ClosedRange<Double> {
        switch band {
        case .early: return 1600...2600
        case .middle: return 900...1500
        case .upper: return 550...950
        }
    }

    /// The authored budget is the level designer's intent; this scales it within the
    /// band's range rather than replacing it, so a deliberately tight level stays tight.
    public func inkBudget(authored: Double) -> Double {
        let range = inkRange
        let scaled = range.upperBound - (range.upperBound - range.lowerBound) * parameter
        // Never hand a child less than the level's own reference solution needs; the
        // build gate proves the authored budget is sufficient, nothing proves a
        // controller-shrunk one is.
        return max(min(authored, scaled), authored * 0.75)
    }

    public var strokeLimit: Int? {
        switch band {
        case .early: return nil
        case .middle: return parameter > 0.7 ? 3 : nil
        case .upper: return parameter > 0.5 ? 2 : 3
        }
    }

    public var allowsDrawWhileRunning: Bool {
        band == .upper
    }

    /// Ink-stroke thickness, child-adjustable on top of this (§6 accessibility).
    public var suggestedStrokeThickness: Double {
        switch band {
        case .early: return 14
        case .middle: return 11
        case .upper: return 9
        }
    }
}
