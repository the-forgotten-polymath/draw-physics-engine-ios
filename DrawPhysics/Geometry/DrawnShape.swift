import Foundation

/// Where a shape came from. The library case exists so children who cannot draw
/// freehand reach the same simulation through taps (§6, acceptance criterion 15).
public enum StrokeSource: Codable, Equatable, Sendable {
    case freehand
    case library(String)
}

/// A stroke after the full pipeline: what the child sees (`simplifiedPoints`) and
/// what the simulation receives (`convexPieces`). Keeping both is what lets the
/// rendered ink match the physics without the physics driving the visuals.
public struct DrawnShape: Codable, Equatable, Sendable {
    public var id: Int
    public var rawPoints: [Vec2]
    public var simplifiedPoints: [Vec2]
    /// Each piece is convex and counter-clockwise. All pieces belong to ONE static
    /// body — see `ENGINEERING.md`: fewer bodies beats fewer pieces.
    public var convexPieces: [[Vec2]]
    /// Closed strokes become a filled solid, open strokes a thin chain. A child
    /// notices this distinction immediately, so it is a product decision, not a detail.
    public var isClosed: Bool
    public var inkLength: Double
    public var enclosedArea: Double
    public var thickness: Double
    public var source: StrokeSource

    public init(id: Int,
                rawPoints: [Vec2],
                simplifiedPoints: [Vec2],
                convexPieces: [[Vec2]],
                isClosed: Bool,
                inkLength: Double,
                enclosedArea: Double,
                thickness: Double,
                source: StrokeSource) {
        self.id = id
        self.rawPoints = rawPoints
        self.simplifiedPoints = simplifiedPoints
        self.convexPieces = convexPieces
        self.isClosed = isClosed
        self.inkLength = inkLength
        self.enclosedArea = enclosedArea
        self.thickness = thickness
        self.source = source
    }
}

/// The stroke as recorded for replay: the INPUT, plus the simulation step it was
/// committed on. Recording input rather than resulting motion is what makes a
/// replay possible at all (§8.3).
public struct RecordedStroke: Codable, Equatable, Sendable {
    public var points: [Vec2]
    public var committedAtStep: Int
    public var source: StrokeSource

    public init(points: [Vec2], committedAtStep: Int, source: StrokeSource = .freehand) {
        self.points = points
        self.committedAtStep = committedAtStep
        self.source = source
    }
}

/// The persisted artefact. Versioned because a stroke format change must not
/// silently reinterpret solutions a child already made.
public struct SolutionPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var levelID: String
    public var strokes: [RecordedStroke]
    /// Number of fixed steps the original run needed to reach the goal. Replay uses
    /// it as an upper bound so a diverging replay stops instead of running forever.
    public var stepsToGoal: Int

    public init(levelID: String, strokes: [RecordedStroke], stepsToGoal: Int) {
        self.version = Self.currentVersion
        self.levelID = levelID
        self.strokes = strokes
        self.stepsToGoal = stepsToGoal
    }
}
