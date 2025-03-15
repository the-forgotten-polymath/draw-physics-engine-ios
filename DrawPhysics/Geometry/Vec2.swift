import Foundation

/// A 2D vector in scene units (1 unit == 1 point of the 750x1000 design space).
///
/// `Double` throughout, deliberately. `CGFloat` is `Double` on 64-bit, but naming
/// the type removes any chance of a 32-bit narrowing sneaking into the simulation,
/// which is where reproducibility dies first.
public struct Vec2: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x + r.x, l.y + r.y) }
    public static func - (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x - r.x, l.y - r.y) }
    public static func * (l: Vec2, s: Double) -> Vec2 { Vec2(l.x * s, l.y * s) }
    public static func * (s: Double, r: Vec2) -> Vec2 { Vec2(r.x * s, r.y * s) }
    public static func / (l: Vec2, s: Double) -> Vec2 { Vec2(l.x / s, l.y / s) }
    public static prefix func - (v: Vec2) -> Vec2 { Vec2(-v.x, -v.y) }

    public static func += (l: inout Vec2, r: Vec2) { l = l + r }
    public static func -= (l: inout Vec2, r: Vec2) { l = l - r }
    public static func *= (l: inout Vec2, s: Double) { l = l * s }

    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }

    /// z-component of the 3D cross product. Sign gives orientation, magnitude gives
    /// twice the triangle area — both used constantly by the geometry pipeline.
    public func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }

    public var lengthSquared: Double { x * x + y * y }
    public var length: Double { (x * x + y * y).squareRoot() }

    public func normalized() -> Vec2 {
        let l = length
        guard l > 1e-12 else { return .zero }
        return Vec2(x / l, y / l)
    }

    /// Left-hand perpendicular. For a counter-clockwise polygon edge `b - a`, the
    /// OUTWARD normal is `(b - a).perpendicularCW`, which is the one collision code wants.
    public var perpendicularCCW: Vec2 { Vec2(-y, x) }
    public var perpendicularCW: Vec2 { Vec2(y, -x) }

    public func rotated(by radians: Double) -> Vec2 {
        let c = cos(radians), s = sin(radians)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    public func distance(to o: Vec2) -> Double { (self - o).length }

    public func isApproximatelyEqual(to o: Vec2, tolerance: Double = 1e-9) -> Bool {
        abs(x - o.x) <= tolerance && abs(y - o.y) <= tolerance
    }
}

/// Axis-aligned size, kept free of CoreGraphics so the whole simulation core is
/// testable on any platform without a window server.
public struct Size: Equatable, Codable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct Rect: Equatable, Codable, Sendable {
    public var origin: Vec2
    public var size: Size

    public init(origin: Vec2, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Vec2(x, y), size: Size(width: width, height: height))
    }

    public var minX: Double { min(origin.x, origin.x + size.width) }
    public var maxX: Double { max(origin.x, origin.x + size.width) }
    public var minY: Double { min(origin.y, origin.y + size.height) }
    public var maxY: Double { max(origin.y, origin.y + size.height) }
    public var center: Vec2 { Vec2((minX + maxX) / 2, (minY + maxY) / 2) }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    public func intersects(_ o: Rect) -> Bool {
        minX <= o.maxX && maxX >= o.minX && minY <= o.maxY && maxY >= o.minY
    }
}

// `Double.clamped(to:)` lives in KidsGameCore. Defining it here as well makes every call
// site ambiguous the moment a file imports both modules.
