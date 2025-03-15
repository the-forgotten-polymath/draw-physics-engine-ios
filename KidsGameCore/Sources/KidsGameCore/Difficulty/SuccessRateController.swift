import Foundation

/// Continuous difficulty. Not a level number, so adjustment is invisible and never feels
/// like demotion (`00_README.md` §3.2).
public struct DifficultyParameter: Codable, Equatable, Sendable {
    public private(set) var value: Double
    /// Set by the child, not the controller. Always visible, and the honest admission that
    /// the controller will sometimes be wrong.
    public private(set) var childOffset: Double

    public init(value: Double = 0.35, childOffset: Double = 0) {
        self.value = value.clamped(to: 0...1)
        self.childOffset = childOffset.clamped(to: -0.25...0.25)
    }

    public var effective: Double { (value + childOffset).clamped(to: 0...1) }

    public mutating func setControllerValue(_ newValue: Double) {
        value = newValue.clamped(to: 0...1)
    }

    public mutating func makeHarder() { childOffset = (childOffset + 0.08).clamped(to: -0.25...0.25) }
    public mutating func makeEasier() { childOffset = (childOffset - 0.08).clamped(to: -0.25...0.25) }
}

/// The flow-channel controller shared by all twenty games (`01_EchoPath.md` §9.1).
public struct SuccessRateController: Sendable {
    public let targetLow = 0.75
    public let targetHigh = 0.85

    /// Asymmetric gains. Raising difficulty after success feels like recognition; dropping
    /// it after failure feels like being condescended to — so we rise readily and retreat
    /// gently.
    private let upGain = 0.060
    private let downGain = 0.025

    /// Never react to a handful of attempts. Small samples are noise, and a controller that
    /// twitches produces difficulty that feels random.
    private let minimumAttempts = 6
    private let windowSize = 12

    /// The rate must sit outside the band for two consecutive evaluations before we move.
    /// This is what prevents the oscillation a naive proportional controller produces.
    private let consecutiveDeviationsRequired = 2

    public init() {}

    public func next(difficulty d: Double,
                     window: [Bool],
                     consecutiveDeviations: Int) -> (difficulty: Double, deviations: Int) {
        guard window.count >= minimumAttempts else { return (d, 0) }

        let recent = window.suffix(windowSize)
        let rate = Double(recent.filter { $0 }.count) / Double(recent.count)

        if rate > targetHigh {
            let n = consecutiveDeviations + 1
            guard n >= consecutiveDeviationsRequired else { return (d, n) }
            // Scale the step by how far outside the band we are, so a child who is far
            // ahead catches up quickly instead of climbing one notch at a time.
            let excess = (rate - targetHigh) / (1.0 - targetHigh)
            return ((d + upGain * (0.5 + excess)).clamped(to: 0...1), 0)
        }

        if rate < targetLow {
            let n = consecutiveDeviations + 1
            guard n >= consecutiveDeviationsRequired else { return (d, n) }
            let deficit = (targetLow - rate) / targetLow
            return ((d - downGain * (0.5 + deficit)).clamped(to: 0...1), 0)
        }

        return (d, 0)      // inside the band — deliberately do nothing
    }
}

/// A synthetic child, for testing the controller. Real children are not available in CI,
/// and "it felt about right" is not a convergence proof.
public struct PlayerModel: Sendable {
    public var ability: Double
    public var sharpness: Double

    public init(ability: Double, sharpness: Double = 8) {
        self.ability = ability
        self.sharpness = sharpness
    }

    public func succeeds(atDifficulty d: Double, random: Double) -> Bool {
        let p = 1 / (1 + exp(-sharpness * (ability - d)))
        return random < p
    }
}

extension Double {
    public func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Deterministic PRNG (`00_README.md` §7, Seeding). `SystemRandomNumberGenerator` cannot be
/// seeded, so a "reproduce this puzzle" feature is impossible with it.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
