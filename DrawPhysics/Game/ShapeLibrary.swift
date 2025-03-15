import Foundation

struct LibraryShape: Identifiable {
    let id: String
    let symbolName: String
    let spokenName: String
    let points: (Vec2, Double) -> [Vec2]
    
    func points(at centre: Vec2, scale: Double) -> [Vec2] {
        return points(centre, scale)
    }
}

final class ShapeLibrary {
    static let shapes: [LibraryShape] = [
        LibraryShape(
            id: "ramp-left",
            symbolName: "play.fill",
            spokenName: "Left Ramp",
            points: { centre, scale in
                [
                    Vec2(centre.x - 50 * scale, centre.y - 50 * scale),
                    Vec2(centre.x + 50 * scale, centre.y + 50 * scale),
                    Vec2(centre.x + 50 * scale, centre.y - 50 * scale),
                    Vec2(centre.x - 50 * scale, centre.y - 50 * scale)
                ]
            }
        ),
        LibraryShape(
            id: "ramp-right",
            symbolName: "play.fill", // rotated in UI
            spokenName: "Right Ramp",
            points: { centre, scale in
                [
                    Vec2(centre.x - 50 * scale, centre.y - 50 * scale),
                    Vec2(centre.x - 50 * scale, centre.y + 50 * scale),
                    Vec2(centre.x + 50 * scale, centre.y - 50 * scale),
                    Vec2(centre.x - 50 * scale, centre.y - 50 * scale)
                ]
            }
        ),
        LibraryShape(
            id: "block",
            symbolName: "square.fill",
            spokenName: "Block",
            points: { centre, scale in
                [
                    Vec2(centre.x - 50 * scale, centre.y - 50 * scale),
                    Vec2(centre.x - 50 * scale, centre.y + 50 * scale),
                    Vec2(centre.x + 50 * scale, centre.y + 50 * scale),
                    Vec2(centre.x + 50 * scale, centre.y - 50 * scale),
                    Vec2(centre.x - 50 * scale, centre.y - 50 * scale)
                ]
            }
        ),
        LibraryShape(
            id: "bowl",
            symbolName: "tray.fill",
            spokenName: "Bowl",
            points: { centre, scale in
                // A U-shape
                [
                    Vec2(centre.x - 50 * scale, centre.y + 50 * scale),
                    Vec2(centre.x - 50 * scale, centre.y - 50 * scale),
                    Vec2(centre.x + 50 * scale, centre.y - 50 * scale),
                    Vec2(centre.x + 50 * scale, centre.y + 50 * scale)
                ]
            }
        ),
        LibraryShape(
            id: "post",
            symbolName: "rectangle.portrait.fill",
            spokenName: "Post",
            points: { centre, scale in
                [
                    Vec2(centre.x - 20 * scale, centre.y - 100 * scale),
                    Vec2(centre.x - 20 * scale, centre.y + 100 * scale),
                    Vec2(centre.x + 20 * scale, centre.y + 100 * scale),
                    Vec2(centre.x + 20 * scale, centre.y - 100 * scale),
                    Vec2(centre.x - 20 * scale, centre.y - 100 * scale)
                ]
            }
        )
    ]
}
