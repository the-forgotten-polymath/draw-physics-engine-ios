import Foundation
import SwiftUI

/// Fine-motor accommodations (`00_README.md` §6). Not a mode — always-on settings, because a
/// child who needs a bigger target needs it in every game.
public struct MotorAccommodations: Codable, Equatable, Sendable {
    /// Minimum tappable edge. 44pt is Apple's floor for adults; children with motor
    /// differences need more, and nothing in this game is dense enough to suffer from it.
    public var minimumTargetSize: Double
    /// Extra ink thickness, so a shaky line still reads as a line.
    public var strokeThicknessBoost: Double
    /// Dwell-to-select for children who cannot tap reliably.
    public var isDwellSelectEnabled: Bool
    public var dwellSeconds: Double
    /// Ignores contact shorter than this, which is what an unintended brush looks like.
    public var touchDebounceSeconds: Double

    public init(minimumTargetSize: Double = 56,
                strokeThicknessBoost: Double = 0,
                isDwellSelectEnabled: Bool = false,
                dwellSeconds: Double = 1.2,
                touchDebounceSeconds: Double = 0) {
        self.minimumTargetSize = minimumTargetSize
        self.strokeThicknessBoost = strokeThicknessBoost
        self.isDwellSelectEnabled = isDwellSelectEnabled
        self.dwellSeconds = dwellSeconds
        self.touchDebounceSeconds = touchDebounceSeconds
    }

    public static let standard = MotorAccommodations()
}

/// Palette where every entry carries a shape as well as a hue, so nothing in any game is
/// communicated by colour alone.
public struct ColourSafeToken: Identifiable, Sendable {
    public let id: String
    public let colour: Color
    public let symbolName: String

    public init(id: String, colour: Color, symbolName: String) {
        self.id = id
        self.colour = colour
        self.symbolName = symbolName
    }
}

public enum ColourSafePalette {
    /// Okabe-Ito derived hues, chosen because they stay distinguishable under the common
    /// forms of colour vision deficiency.
    public static let ink = ColourSafeToken(id: "ink", colour: Color(red: 0.00, green: 0.45, blue: 0.70),
                                            symbolName: "scribble")
    public static let ball = ColourSafeToken(id: "ball", colour: Color(red: 0.90, green: 0.62, blue: 0.00),
                                             symbolName: "circle.fill")
    public static let goal = ColourSafeToken(id: "goal", colour: Color(red: 0.00, green: 0.62, blue: 0.45),
                                             symbolName: "flag.fill")
    public static let fixture = ColourSafeToken(id: "fixture", colour: Color(red: 0.35, green: 0.35, blue: 0.38),
                                                symbolName: "square.fill")
    public static let all = [ink, ball, goal, fixture]
}
