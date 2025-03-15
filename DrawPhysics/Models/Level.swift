import Foundation
import KidsGameCore

/// Static geometry the child cannot change.
public struct FixtureDefinition: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case box(center: Vec2, size: Size, rotation: Double)
        case polygon(points: [Vec2])
        /// Three boxes: floor plus two walls. Authored as one thing because "a cup" is
        /// what the level designer is actually placing.
        case cup(center: Vec2, width: Double, height: Double, wallThickness: Double)
        /// Kinematic. `periodSteps` is in simulation steps, not seconds, so the motion is
        /// reproducible by construction.
        case movingPlatform(center: Vec2, size: Size, travel: Vec2, periodSteps: Int)
        /// A dynamic plank pinned at its centre.
        case seesaw(pivot: Vec2, length: Double, thickness: Double, density: Double)
    }

    public var kind: Kind
    public var friction: Double
    public var restitution: Double

    public init(kind: Kind, friction: Double = 0.6, restitution: Double = 0.1) {
        self.kind = kind
        self.friction = friction
        self.restitution = restitution
    }
}

/// Bodies that move. The ball is always one of these.
public struct MovableDefinition: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case ball(center: Vec2, radius: Double)
        case crate(center: Vec2, size: Size, rotation: Double)
    }

    public var tag: String
    public var kind: Kind
    public var density: Double
    public var friction: Double
    public var restitution: Double

    public init(tag: String,
                kind: Kind,
                density: Double = 1.0,
                friction: Double = 0.5,
                restitution: Double = 0.18) {
        self.tag = tag
        self.kind = kind
        self.density = density
        self.friction = friction
        self.restitution = restitution
    }
}

/// What counts as done. Every case is a positive condition — there is deliberately no
/// failure goal, because failing is not an event in this game (§5.2).
public enum GoalDefinition: Codable, Equatable, Sendable {
    /// `dwellSteps` stops a ball that clips through the cup on its way past from
    /// registering as solved.
    case ballInRegion(ballTag: String, region: Rect, dwellSteps: Int)
    case ballThroughGapThenRegion(ballTag: String, gap: Rect, region: Rect, dwellSteps: Int)
    case allBallsInRegion(ballTags: [String], region: Rect, dwellSteps: Int)

    public var spokenDescription: String {
        switch self {
        case .ballInRegion:
            return "Get the ball into the cup."
        case .ballThroughGapThenRegion:
            return "Send the ball through the gap, then into the cup."
        case .allBallsInRegion:
            return "Get both balls into the cup."
        }
    }
}

/// An authored solution, stored with the level and simulated in CI. Its existence is
/// what proves the level is solvable at all, and that its ink budget is not tighter than
/// its own intended answer (§8.5).
public struct ReferenceSolution: Codable, Equatable, Sendable {
    public var id: String
    public var note: String
    public var strokes: [RecordedStroke]

    public init(id: String, note: String, strokes: [RecordedStroke]) {
        self.id = id
        self.note = note
        self.strokes = strokes
    }
}

public struct LevelDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var band: AgeBand
    public var sceneSize: Size
    /// Total drawable ink. The constraint that forces thought instead of "draw a giant
    /// blob" (§8.4).
    public var inkBudget: Double
    /// nil means unlimited. A limit is a difficulty axis, never a punishment — running out
    /// of strokes still allows undo.
    public var maxStrokes: Int?
    public var drawWhileRunning: Bool
    public var spokenHint: String
    public var fixtures: [FixtureDefinition]
    public var movables: [MovableDefinition]
    public var goal: GoalDefinition
    public var referenceSolutions: [ReferenceSolution]
    /// Simulation steps before a run is considered settled. At 120Hz, 1800 is 15 seconds.
    public var maximumSteps: Int

    public init(id: String,
                title: String,
                band: AgeBand,
                sceneSize: Size = Size(width: 750, height: 1000),
                inkBudget: Double,
                maxStrokes: Int? = nil,
                drawWhileRunning: Bool = false,
                spokenHint: String,
                fixtures: [FixtureDefinition],
                movables: [MovableDefinition],
                goal: GoalDefinition,
                referenceSolutions: [ReferenceSolution] = [],
                maximumSteps: Int = 1800) {
        self.id = id
        self.title = title
        self.band = band
        self.sceneSize = sceneSize
        self.inkBudget = inkBudget
        self.maxStrokes = maxStrokes
        self.drawWhileRunning = drawWhileRunning
        self.spokenHint = spokenHint
        self.fixtures = fixtures
        self.movables = movables
        self.goal = goal
        self.referenceSolutions = referenceSolutions
        self.maximumSteps = maximumSteps
    }
}
