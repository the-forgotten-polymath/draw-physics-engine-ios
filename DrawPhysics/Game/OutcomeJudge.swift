import Foundation

/// Decides — once, during the original run — whether the goal was reached (§8.3).
///
/// The result of the ORIGINAL run is authoritative and is what gets stored. A replay
/// re-runs the same input and may, on a different device, diverge; when it does, the
/// stored verdict stands, because the child did solve it. `OutcomeJudge` therefore has no
/// API for revising a past verdict, which is the cheapest possible way to guarantee that
/// property: there is no code that could do it.
public struct OutcomeJudge {
    public let goal: GoalDefinition

    private var dwellCounter = 0
    private var gapCleared = false
    private(set) public var didReachGoal = false
    private(set) public var stepReached: Int?

    public init(goal: GoalDefinition) {
        self.goal = goal
    }

    /// Call exactly once per simulation step, never per rendered frame.
    public mutating func evaluate(world: FixedStepWorld, stepIndex: Int) {
        guard !didReachGoal else { return }

        switch goal {
        case let .ballInRegion(ballTag, region, dwellSteps):
            let inside = centre(of: ballTag, in: world).map { region.contains($0) } ?? false
            accumulate(inside: inside, needed: dwellSteps, stepIndex: stepIndex)

        case let .ballThroughGapThenRegion(ballTag, gap, region, dwellSteps):
            guard let centre = centre(of: ballTag, in: world) else { return }
            if !gapCleared, gap.contains(centre) { gapCleared = true }
            accumulate(inside: gapCleared && region.contains(centre),
                       needed: dwellSteps,
                       stepIndex: stepIndex)

        case let .allBallsInRegion(ballTags, region, dwellSteps):
            let all = ballTags.allSatisfy { tag in
                centre(of: tag, in: world).map { region.contains($0) } ?? false
            }
            accumulate(inside: all, needed: dwellSteps, stepIndex: stepIndex)
        }
    }

    private mutating func accumulate(inside: Bool, needed: Int, stepIndex: Int) {
        if inside {
            dwellCounter += 1
            if dwellCounter >= max(needed, 1) {
                didReachGoal = true
                stepReached = stepIndex
            }
        } else {
            // Reset rather than decay: a ball that grazes the cup twice has not been in it.
            dwellCounter = 0
        }
    }

    private func centre(of tag: String, in world: FixedStepWorld) -> Vec2? {
        guard let body = world.body(tagged: BodyTag(tag)) else { return nil }
        if case let .circle(center, _) = body.shapes.first?.kind {
            return body.toWorld(center)
        }
        return body.position
    }
}
