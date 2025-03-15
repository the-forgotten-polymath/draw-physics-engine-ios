import Foundation

/// The whole stroke pipeline behind one call, so the game layer never has to know the
/// stage order and the tests can exercise it end to end.
public struct StrokePipeline: Sendable {
    public let simplifier: StrokeSimplifier
    public let decomposer: ConvexDecomposer
    public let inkMeter: InkMeter

    public init(simplifier: StrokeSimplifier = StrokeSimplifier(),
                decomposer: ConvexDecomposer = ConvexDecomposer(),
                inkMeter: InkMeter = InkMeter()) {
        self.simplifier = simplifier
        self.decomposer = decomposer
        self.inkMeter = inkMeter
    }

    public enum Rejection: Equatable, Sendable {
        case tooShort
        case degenerate
        case overBudget(cost: Double, remaining: Double)
        case strokeLimitReached
    }

    public enum Outcome: Equatable, Sendable {
        case accepted(DrawnShape, cost: Double)
        case rejected(Rejection)
    }

    /// `id` is supplied by the caller (a monotonically increasing counter) rather than
    /// generated here, so the same stroke sequence always produces the same ids —
    /// which replay depends on.
    public func makeShape(id: Int,
                          rawPoints: [Vec2],
                          source: StrokeSource,
                          budget: InkBudget) -> Outcome {
        guard let processed = simplifier.process(rawPoints: rawPoints) else {
            return .rejected(.degenerate)
        }
        guard inkMeter.isLongEnough(processed) else {
            return .rejected(.tooShort)
        }

        let pieces: [[Vec2]]
        if processed.isClosed {
            pieces = decomposer.decompose(processed.simplifiedPoints)
        } else {
            pieces = StrokeSimplifier.chainPieces(processed.simplifiedPoints,
                                                  thickness: simplifier.configuration.chainThickness)
        }
        guard !pieces.isEmpty else { return .rejected(.degenerate) }

        let cost = inkMeter.cost(of: processed)
        guard budget.canAfford(cost) else {
            return .rejected(.overBudget(cost: cost, remaining: budget.remaining))
        }

        let shape = DrawnShape(id: id,
                               rawPoints: rawPoints,
                               simplifiedPoints: processed.simplifiedPoints,
                               convexPieces: pieces,
                               isClosed: processed.isClosed,
                               inkLength: processed.inkLength,
                               enclosedArea: processed.enclosedArea,
                               thickness: simplifier.configuration.chainThickness,
                               source: source)
        return .accepted(shape, cost: cost)
    }
}
