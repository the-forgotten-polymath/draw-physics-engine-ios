import Foundation
import SwiftUI
import Observation

/// A real gate, not a tappable "are you a grown-up?" button (`00_README.md` §5.4).
///
/// The design constraints are narrower than they look. It must be hard for a 6-year-old and
/// trivial for an adult, so it cannot be a reading task (some adults read poorly, some
/// children read well) and it cannot be a memory task. Two-digit multiplication sits in the
/// gap: mechanical for an adult, out of reach for the age range this app serves.
///
/// It must also not be brute-forceable by tapping, hence the cooldown.
@MainActor
@Observable
public final class ParentGate {

    public struct Challenge: Equatable, Sendable {
        public let left: Int
        public let right: Int
        public let options: [Int]
        public var answer: Int { left * right }
        public var spokenPrompt: String { "Grown-ups only. What is \(left) times \(right)?" }
    }

    public private(set) var challenge: Challenge
    public private(set) var failedAttempts = 0
    public private(set) var lockedUntil: Date?
    public private(set) var isUnlocked = false

    /// Three wrong answers buys a minute of nothing happening. Long enough to end a child's
    /// interest, short enough not to punish an adult who mis-tapped.
    private let attemptsBeforeLockout = 3
    private let lockoutSeconds: TimeInterval = 60

    private var generator: RandomNumberGenerator

    public init(seed: UInt64? = nil) {
        var rng: RandomNumberGenerator = seed.map { SplitMix64(seed: $0) } ?? SystemRandomNumberGenerator()
        self.challenge = Self.makeChallenge(using: &rng)
        self.generator = rng
    }

    public var isLockedOut: Bool {
        guard let lockedUntil else { return false }
        return Date() < lockedUntil
    }

    public var lockoutRemaining: TimeInterval {
        guard let lockedUntil else { return 0 }
        return max(0, lockedUntil.timeIntervalSinceNow)
    }

    @discardableResult
    public func submit(_ value: Int) -> Bool {
        guard !isLockedOut else { return false }
        if value == challenge.answer {
            isUnlocked = true
            failedAttempts = 0
            return true
        }
        failedAttempts += 1
        if failedAttempts >= attemptsBeforeLockout {
            lockedUntil = Date().addingTimeInterval(lockoutSeconds)
            failedAttempts = 0
        }
        challenge = Self.makeChallenge(using: &generator)
        return false
    }

    /// Unlock does not persist. Every visit to a gated screen is gated again, because a
    /// remembered unlock is a gate a child walks through later.
    public func relock() {
        isUnlocked = false
        challenge = Self.makeChallenge(using: &generator)
    }

    private static func makeChallenge(using rng: inout RandomNumberGenerator) -> Challenge {
        let left = Int.random(in: 12...19, using: &rng)
        let right = Int.random(in: 12...19, using: &rng)
        let answer = left * right
        // Distractors are close to the answer so guessing is not rewarded, and are unique so
        // there is never more than one correct button.
        var options = Set([answer])
        while options.count < 4 {
            let delta = Int.random(in: -30...30, using: &rng)
            let candidate = answer + delta
            if candidate > 0, candidate != answer { options.insert(candidate) }
        }
        return Challenge(left: left, right: right, options: options.shuffled(using: &rng))
    }
}

public struct ParentGateView: View {
    @State private var gate = ParentGate()
    @State private var shakeCount = 0
    private let onUnlocked: () -> Void
    private let onCancel: () -> Void

    public init(onUnlocked: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onUnlocked = onUnlocked
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 44))
                .accessibilityHidden(true)

            Text("Grown-ups only")
                .font(.title2.bold())

            Text("What is \(gate.challenge.left) × \(gate.challenge.right)?")
                .font(.title3)
                .accessibilityLabel("What is \(gate.challenge.left) times \(gate.challenge.right)?")

            if gate.isLockedOut {
                Text("Try again in \(Int(gate.lockoutRemaining.rounded())) seconds.")
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(gate.challenge.options, id: \.self) { option in
                        Button {
                            if gate.submit(option) {
                                onUnlocked()
                            } else {
                                shakeCount += 1
                            }
                        } label: {
                            Text("\(option)")
                                .font(.title3.monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .modifier(ShakeEffect(animatableData: CGFloat(shakeCount)))
            }

            Button("Not now", action: onCancel)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 8 * sin(animatableData * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
