import Foundation

/// The verdict from the ORIGINAL run, and the reason acceptance criterion 7 holds.
///
/// Every property is `let`. There is no initialiser that takes an existing outcome and
/// changes it, and no mutating method. A replay physically cannot un-solve a level because
/// no code exists that could write to this type after it is made — which is a stronger
/// guarantee than a comment asking future contributors not to.
public struct SolutionOutcome: Codable, Equatable, Sendable {
    public let didReachGoal: Bool
    public let stepsToGoal: Int?
    public let inkUsed: Double
    public let strokeCount: Int
    public let judgedAt: Date

    public init(didReachGoal: Bool,
                stepsToGoal: Int?,
                inkUsed: Double,
                strokeCount: Int,
                judgedAt: Date = Date()) {
        self.didReachGoal = didReachGoal
        self.stepsToGoal = stepsToGoal
        self.inkUsed = inkUsed
        self.strokeCount = strokeCount
        self.judgedAt = judgedAt
    }

    public init(simulated: SolutionSimulator.Result, judgedAt: Date = Date()) {
        self.init(didReachGoal: simulated.didReachGoal,
                  stepsToGoal: simulated.stepsToGoal,
                  inkUsed: simulated.inkUsed,
                  strokeCount: simulated.acceptedStrokes,
                  judgedAt: judgedAt)
    }
}

/// What a replay is allowed to report: that it looked different. Not that the child failed.
///
/// Cross-device bit-reproducibility is not available on any float physics stack, so the
/// design makes divergence a display note rather than a correctness problem. The replay is
/// presented as "here's how they did it", and if the ball behaves slightly differently the
/// solution is still solved.
public struct ReplayComparison: Sendable {
    public let stored: SolutionOutcome
    public let replayReachedGoal: Bool
    public let replayStepsToGoal: Int?

    public init(stored: SolutionOutcome, replay: SolutionSimulator.Result) {
        self.stored = stored
        self.replayReachedGoal = replay.didReachGoal
        self.replayStepsToGoal = replay.stepsToGoal
    }

    public var diverged: Bool { stored.didReachGoal != replayReachedGoal }

    /// Shown under a replay only when it happens. Deliberately not framed as an error, and
    /// deliberately not shown to the child as "this device is wrong".
    public var childFacingNote: String? {
        diverged ? "The ball went a bit differently this time." : nil
    }
}
