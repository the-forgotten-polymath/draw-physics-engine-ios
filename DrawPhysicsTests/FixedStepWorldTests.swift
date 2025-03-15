import XCTest
import KidsGameCore
@testable import DrawPhysics

final class FixedStepWorldTests: XCTestCase {

    private let simulator = SolutionSimulator()

    /// A minimal level built in code rather than loaded, so these tests exercise the
    /// simulation and nothing else.
    private func testLevel(inkBudget: Double = 3000) -> LevelDefinition {
        LevelDefinition(
            id: "unit-fixed-step",
            title: "Unit",
            band: .middle,
            inkBudget: inkBudget,
            spokenHint: "unit test",
            fixtures: [
                FixtureDefinition(kind: .cup(center: Vec2(600, 130), width: 200,
                                             height: 150, wallThickness: 18),
                                  friction: 0.8, restitution: 0.05)
            ],
            movables: [
                MovableDefinition(tag: "ball", kind: .ball(center: Vec2(140, 880), radius: 26))
            ],
            goal: .ballInRegion(ballTag: "ball",
                                region: Rect(x: 510, y: 60, width: 180, height: 110),
                                dwellSteps: 30)
        )
    }

    private var workingRamp: [RecordedStroke] {
        [RecordedStroke(points: [Vec2(110, 700), Vec2(560, 250)], committedAtStep: 0)]
    }

    // MARK: - Named invariants (§9)

    func testSameInputSameOutcomeAcrossRunsOnDevice() {
        let level = testLevel()
        var results: [(Bool, Int?, Vec2)] = []
        for _ in 0..<8 {
            let result = simulator.run(level: level, strokes: workingRamp, captureEveryNthStep: 60)
            let lastBall = result.frames.last?.bodies.first { $0.tag == "ball" }
            results.append((result.didReachGoal, result.stepsToGoal, lastBall?.position ?? .zero))
        }
        for run in results.dropFirst() {
            XCTAssertEqual(run.0, results[0].0)
            XCTAssertEqual(run.1, results[0].1)
            // Bit-identical, not merely close. Same machine, same input, same order of
            // operations: any difference at all would mean an unordered collection or
            // wall-clock time had leaked into the step.
            XCTAssertEqual(run.2.x, results[0].2.x)
            XCTAssertEqual(run.2.y, results[0].2.y)
        }
        XCTAssertTrue(results[0].0, "the fixture ramp is supposed to solve the fixture level")
    }

    func testForcedFrameRateChangeDoesNotAlterOutcome() {
        // The step function never sees the frame delta — `advance` only decides HOW MANY
        // steps to run. So 60Hz, 120Hz, and a deliberately jittering frame rate must all
        // produce identical state at the same step index. Without a fixed timestep this is
        // exactly what breaks, and a replay of a successful solution starts failing under
        // load.
        let targetStep = 600
        func stateAtTargetStep(deltas: [TimeInterval]) -> Vec2 {
            let built = SceneBuilder.build(level: testLevel())
            let pipeline = StrokePipeline()
            var budget = InkBudget(total: 3000)
            if case let .accepted(shape, cost) = pipeline.makeShape(id: 0,
                                                                   rawPoints: workingRamp[0].points,
                                                                   source: .freehand,
                                                                   budget: budget) {
                budget.charge(cost)
                SceneBuilder.addDrawnShape(shape, to: built.world)
            }
            var captured = Vec2.zero
            var deltaIndex = 0
            while built.world.stepIndex < targetStep {
                built.world.advance(by: deltas[deltaIndex % deltas.count]) { step in
                    if step == targetStep, let ball = built.world.body(tagged: BodyTag("ball")) {
                        captured = ball.position
                    }
                }
                deltaIndex += 1
            }
            return captured
        }

        let at120 = stateAtTargetStep(deltas: [1.0 / 120.0])
        let at60 = stateAtTargetStep(deltas: [1.0 / 60.0])
        let at30 = stateAtTargetStep(deltas: [1.0 / 30.0])
        let jittery = stateAtTargetStep(deltas: [1.0 / 58.0, 1.0 / 121.0, 1.0 / 41.0, 0.2])

        XCTAssertEqual(at60.x, at120.x)
        XCTAssertEqual(at60.y, at120.y)
        XCTAssertEqual(at30.x, at120.x)
        XCTAssertEqual(at30.y, at120.y)
        XCTAssertEqual(jittery.x, at120.x)
        XCTAssertEqual(jittery.y, at120.y)
    }

    func testStoredOutcomeIsNeverMutatedByReplay() {
        let level = testLevel()
        let original = simulator.run(level: level, strokes: workingRamp)
        XCTAssertTrue(original.didReachGoal)
        let stored = SolutionOutcome(simulated: original)

        // Force the replay to diverge the way another device's floating point might, only
        // harder, so the assertion is unambiguous.
        var divergentLevel = level
        divergentLevel.movables = [
            MovableDefinition(tag: "ball", kind: .ball(center: Vec2(120, 880), radius: 26))
        ]
        let replay = simulator.run(level: divergentLevel, strokes: workingRamp)
        let comparison = ReplayComparison(stored: stored, replay: replay)

        XCTAssertTrue(comparison.stored.didReachGoal,
                      "a divergent replay must never un-solve a level")
        XCTAssertEqual(comparison.stored.stepsToGoal, original.stepsToGoal)
        XCTAssertEqual(comparison.stored.inkUsed, original.inkUsed)
        if comparison.diverged {
            XCTAssertNotNil(comparison.childFacingNote)
        }
    }

    // MARK: - Stability

    func testRestingBallNeitherJittersNorSinks() {
        // Jitter and sink are the two failure modes that make a physics game feel broken, and
        // both come from the solver rather than from the geometry.
        let level = LevelDefinition(id: "unit-rest", title: "Rest", band: .early,
                                    inkBudget: 1000, spokenHint: "",
                                    fixtures: [],
                                    movables: [MovableDefinition(tag: "ball",
                                                                 kind: .ball(center: Vec2(300, 200),
                                                                             radius: 30))],
                                    goal: .ballInRegion(ballTag: "ball",
                                                        region: Rect(x: -9999, y: -9999,
                                                                     width: 1, height: 1),
                                                        dwellSteps: 30),
                                    maximumSteps: 1200)
        let result = simulator.run(level: level, strokes: [], captureEveryNthStep: 30)
        let settled = result.frames.suffix(12).compactMap { frame in
            frame.bodies.first { $0.tag == "ball" }?.position.y
        }
        XCTAssertFalse(settled.isEmpty)
        for y in settled {
            XCTAssertEqual(y, 30, accuracy: 1.0, "ball sank into or floated above the floor")
        }
        let spread = (settled.max() ?? 0) - (settled.min() ?? 0)
        XCTAssertLessThan(spread, 0.05, "resting ball is jittering by \(spread)")
    }

    func testFastBallDoesNotTunnelThroughAThinDrawnBarrier() {
        // The speed clamp plus the 120Hz step exists for this. A ball that passes through the
        // line a child drew is the single most trust-destroying bug the game could have.
        let world = FixedStepWorld()
        SceneBuilder.addDrawnShape(
            DrawnShape(id: 0,
                       rawPoints: [Vec2(0, 300), Vec2(750, 300)],
                       simplifiedPoints: [Vec2(0, 300), Vec2(750, 300)],
                       convexPieces: StrokeSimplifier.chainPieces([Vec2(0, 300), Vec2(750, 300)],
                                                                  thickness: 11),
                       isClosed: false,
                       inkLength: 750,
                       enclosedArea: 0,
                       thickness: 11,
                       source: .freehand),
            to: world)
        let ball = world.add { id in
            RigidBody(id: id, tag: BodyTag("ball"),
                      shapes: [.circle(radius: 22)],
                      motion: .dynamic, position: Vec2(375, 900))
        }
        ball.velocity = Vec2(0, -FixedStepWorld.maximumSpeed)
        for _ in 0..<600 { world.stepOnce() }
        XCTAssertGreaterThan(ball.position.y, 300,
                             "ball tunnelled through the barrier to y=\(ball.position.y)")
    }

    func testStallDoesNotSpiralTheSimulation() {
        // A push notification or an app switch hands us a huge delta. Without the clamp we
        // run hundreds of steps to catch up, that takes longer than a frame, the next delta
        // is bigger, and the app appears to hang.
        let world = FixedStepWorld()
        let steps = world.advance(by: 12.0)
        XCTAssertLessThanOrEqual(steps, 30, "a 12 second stall must not run 1440 steps")
    }

    func testSeesawTipsUnderLoad() {
        // Proves the revolute joint actually constrains: the plank must rotate about its
        // pivot rather than fall, and it must respond to a ball landing off-centre.
        let level = LevelDefinition(
            id: "unit-seesaw", title: "Seesaw", band: .middle, inkBudget: 1000, spokenHint: "",
            fixtures: [FixtureDefinition(kind: .seesaw(pivot: Vec2(375, 300), length: 340,
                                                       thickness: 22, density: 0.7))],
            movables: [MovableDefinition(tag: "ball", kind: .ball(center: Vec2(260, 600), radius: 24))],
            goal: .ballInRegion(ballTag: "ball",
                                region: Rect(x: -9999, y: -9999, width: 1, height: 1),
                                dwellSteps: 30),
            maximumSteps: 600)
        let built = SceneBuilder.build(level: level)
        guard let plank = built.world.bodies.first(where: { $0.tag.raw.hasPrefix("seesaw.0") }) else {
            return XCTFail("no plank")
        }
        for _ in 0..<600 { built.world.stepOnce() }
        XCTAssertEqual(plank.position.x, 375, accuracy: 3.0, "the pin let the plank drift")
        XCTAssertEqual(plank.position.y, 300, accuracy: 3.0, "the pin let the plank fall")
        XCTAssertGreaterThan(abs(plank.rotation), 0.05, "the plank never tipped")
    }
}
