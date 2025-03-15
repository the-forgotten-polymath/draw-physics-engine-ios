import Foundation

/// Headless re-simulation of a recorded solution.
///
/// This one function is doing four jobs, and that is deliberate — they must all agree:
/// the replay the child watches, the video export, the level-integrity build gate, and
/// the determinism tests. If replay used a different code path from the build gate, the
/// gate would be proving something about code nobody runs.
public struct SolutionSimulator {

    public struct Frame: Sendable {
        public let stepIndex: Int
        public let bodies: [BodySnapshot]
    }

    public struct BodySnapshot: Sendable {
        public let id: Int
        public let tag: String
        public let position: Vec2
        public let rotation: Double
    }

    public struct Result {
        public let didReachGoal: Bool
        public let stepsToGoal: Int?
        public let stepsSimulated: Int
        public let inkUsed: Double
        public let acceptedStrokes: Int
        public let rejections: [StrokePipeline.Rejection]
        public let frames: [Frame]
        public let shapes: [DrawnShape]
    }

    public let pipeline: StrokePipeline

    public init(pipeline: StrokePipeline = StrokePipeline()) {
        self.pipeline = pipeline
    }

    /// - Parameters:
    ///   - captureEveryNthStep: 0 disables frame capture. The build gate does not need
    ///     frames and allocating them for 1800 steps x 6 levels is pure waste; the video
    ///     exporter does need them.
    public func run(level: LevelDefinition,
                    strokes: [RecordedStroke],
                    captureEveryNthStep: Int = 0) -> Result {
        let built = SceneBuilder.build(level: level)
        let world = built.world
        var judge = OutcomeJudge(goal: level.goal)
        var budget = InkBudget(total: level.inkBudget)
        var rejections: [StrokePipeline.Rejection] = []
        var accepted = 0
        var acceptedShapes: [DrawnShape] = []
        var frames: [Frame] = []

        // Strokes are committed in recorded step order. Sorting by step index rather than
        // trusting array order means a hand-authored reference solution cannot accidentally
        // depend on file ordering.
        let ordered = strokes.enumerated().sorted { lhs, rhs in
            lhs.element.committedAtStep == rhs.element.committedAtStep
                ? lhs.offset < rhs.offset
                : lhs.element.committedAtStep < rhs.element.committedAtStep
        }.map { $0.element }

        var nextStrokeIndex = 0
        var shapeID = 0

        func commitStrokesDue(atStep step: Int) {
            while nextStrokeIndex < ordered.count,
                  ordered[nextStrokeIndex].committedAtStep <= step {
                let stroke = ordered[nextStrokeIndex]
                nextStrokeIndex += 1
                if let limit = level.maxStrokes, accepted >= limit {
                    rejections.append(.strokeLimitReached)
                    continue
                }
                let outcome = pipeline.makeShape(id: shapeID,
                                                 rawPoints: stroke.points,
                                                 source: stroke.source,
                                                 budget: budget)
                switch outcome {
                case let .accepted(shape, cost):
                    budget.charge(cost)
                    SceneBuilder.addDrawnShape(shape, to: world)
                    acceptedShapes.append(shape)
                    accepted += 1
                    shapeID += 1
                case let .rejected(reason):
                    rejections.append(reason)
                }
            }
        }

        commitStrokesDue(atStep: 0)

        var step = 0
        while step < level.maximumSteps {
            world.stepOnce()
            step = world.stepIndex
            commitStrokesDue(atStep: step)
            judge.evaluate(world: world, stepIndex: step)

            if captureEveryNthStep > 0, step % captureEveryNthStep == 0 {
                frames.append(Frame(stepIndex: step,
                                    bodies: world.bodies.map {
                                        BodySnapshot(id: $0.id, tag: $0.tag.raw,
                                                     position: $0.position, rotation: $0.rotation)
                                    }))
            }
            if judge.didReachGoal { break }
        }

        return Result(didReachGoal: judge.didReachGoal,
                      stepsToGoal: judge.stepReached,
                      stepsSimulated: step,
                      inkUsed: budget.spent,
                      acceptedStrokes: accepted,
                      rejections: rejections,
                      frames: frames,
                      shapes: acceptedShapes)
    }
}
