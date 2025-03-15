import Foundation

/// Ink accounting (§8.4). The budget is the mechanism that makes the game a
/// divergent-thinking game rather than a "draw a funnel" game.
public struct InkMeter: Sendable {

    /// Ink units charged per unit of enclosed area for a CLOSED shape.
    ///
    /// Arc length alone is not enough: a circle enclosing the whole scene has a short
    /// outline relative to what it achieves, so a child can cheaply funnel the ball
    /// into the cup on every level and never think again. Charging for enclosed area
    /// makes the big blob expensive while leaving a small, deliberate block affordable.
    /// Calibration evidence is in `ENGINEERING.md`.
    public let areaCharge: Double

    /// Strokes shorter than this are ignored entirely — no ink, no body. Accidental
    /// taps and finger jitter otherwise create tiny unstable bodies.
    public let minimumStrokeLength: Double

    public init(areaCharge: Double = 0.06, minimumStrokeLength: Double = 18.0) {
        self.areaCharge = areaCharge
        self.minimumStrokeLength = minimumStrokeLength
    }

    public func cost(perimeterOrLength: Double, enclosedArea: Double, isClosed: Bool) -> Double {
        isClosed ? perimeterOrLength + enclosedArea * areaCharge : perimeterOrLength
    }

    public func cost(of shape: DrawnShape) -> Double {
        cost(perimeterOrLength: shape.inkLength,
             enclosedArea: shape.enclosedArea,
             isClosed: shape.isClosed)
    }

    public func cost(of stroke: StrokeSimplifier.ProcessedStroke) -> Double {
        cost(perimeterOrLength: stroke.inkLength,
             enclosedArea: stroke.enclosedArea,
             isClosed: stroke.isClosed)
    }

    public func isLongEnough(_ stroke: StrokeSimplifier.ProcessedStroke) -> Bool {
        stroke.inkLength >= minimumStrokeLength
    }
}

/// A spend ledger with exact refunds. Undo is unlimited and free, because that is
/// what makes experimenting safe (§5.1) — so the refund has to be exact, not
/// approximate, or repeated undo slowly leaks budget and the level becomes unsolvable.
public struct InkBudget: Equatable, Sendable {
    public let total: Double
    public private(set) var charges: [Double]

    public init(total: Double) {
        self.total = total
        self.charges = []
    }

    public var spent: Double { charges.reduce(0, +) }
    public var remaining: Double { total - spent }
    public var fractionUsed: Double { total > 0 ? (spent / total).clamped(to: 0...1) : 1 }

    public func canAfford(_ amount: Double) -> Bool {
        // Tolerance of one ink unit so a stroke that lands exactly on the budget is
        // allowed rather than rejected by a floating-point hair.
        amount <= remaining + 1e-6
    }

    @discardableResult
    public mutating func charge(_ amount: Double) -> Bool {
        guard canAfford(amount) else { return false }
        charges.append(amount)
        return true
    }

    /// Refund the most recent charge, returning the exact amount refunded.
    @discardableResult
    public mutating func refundLast() -> Double? {
        guard let last = charges.popLast() else { return nil }
        return last
    }

    public mutating func reset() {
        charges.removeAll()
    }
}
