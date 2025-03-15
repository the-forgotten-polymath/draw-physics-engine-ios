import Foundation

/// Hand-designed levels. This is the authoring source; `swift run LevelAuthor generate`
/// emits the JSON that ships in `Resources/Levels`, and `verify` proves each level's
/// reference solution reaches its goal inside its own ink budget (§8.5).
///
/// Scene space is 750 x 1000, y-up, origin bottom-left — the same space strokes are
/// recorded in, so a reference solution is literally a recording of someone playing.
enum AuthoredLevels {

    static let sceneSize = Size(width: 750, height: 1000)

    static var all: [LevelDefinition] {
        [rollItIn, overTheBump, throughTheGap, theSeesaw, twoStrokes, movingShelf]
    }

    // MARK: - Early band

    /// The first level a child ever sees. Nothing in the scene but a ball and a cup, so
    /// the only question is "how do I get it there", which is the question the whole game
    /// is about. Generous ink, no stroke limit.
    static let rollItIn = LevelDefinition(
        id: "early-01-roll-it-in",
        title: "Roll It In",
        band: .early,
        sceneSize: sceneSize,
        inkBudget: 2200,
        maxStrokes: nil,
        drawWhileRunning: false,
        spokenHint: "Draw something to get the ball into the cup.",
        fixtures: [
            FixtureDefinition(kind: .cup(center: Vec2(600, 130),
                                         width: 200, height: 150,
                                         wallThickness: 18),
                              friction: 0.8, restitution: 0.05)
        ],
        movables: [
            MovableDefinition(tag: "ball",
                              kind: .ball(center: Vec2(140, 880), radius: 26),
                              density: 1.0, friction: 0.5, restitution: 0.15)
        ],
        goal: .ballInRegion(ballTag: "ball",
                            region: Rect(x: 510, y: 60, width: 180, height: 110),
                            dwellSteps: 30),
        referenceSolutions: [
            ReferenceSolution(id: "early-01-ref-long-ramp",
                              note: "One long ramp from the left wall to just above the cup.",
                              strokes: [ramp(Vec2(110, 700), Vec2(560, 250))]),
            ReferenceSolution(id: "early-01-ref-shallow-ramp",
                              note: "A shallower, shorter ramp. Different idea, same outcome — which is the point of the game.",
                              strokes: [ramp(Vec2(90, 660), Vec2(520, 300))])
        ]
    )

    /// Same idea with one obstacle, so the obvious single ramp no longer reaches. Still
    /// generous ink: at this band the interesting part is discovering that a second stroke
    /// is allowed at all.
    static let overTheBump = LevelDefinition(
        id: "early-02-over-the-bump",
        title: "Over the Bump",
        band: .early,
        sceneSize: sceneSize,
        inkBudget: 2200,
        maxStrokes: nil,
        drawWhileRunning: false,
        spokenHint: "The block is in the way. Draw a path over it.",
        fixtures: [
            FixtureDefinition(kind: .box(center: Vec2(400, 110),
                                         size: Size(width: 140, height: 220),
                                         rotation: 0),
                              friction: 0.6, restitution: 0.05),
            FixtureDefinition(kind: .cup(center: Vec2(620, 130),
                                         width: 200, height: 150,
                                         wallThickness: 18),
                              friction: 0.8, restitution: 0.05)
        ],
        movables: [
            MovableDefinition(tag: "ball",
                              kind: .ball(center: Vec2(120, 880), radius: 26),
                              density: 1.0, friction: 0.5, restitution: 0.15)
        ],
        goal: .ballInRegion(ballTag: "ball",
                            region: Rect(x: 530, y: 60, width: 180, height: 110),
                            dwellSteps: 30),
        referenceSolutions: [
            ReferenceSolution(id: "early-02-ref-over-ramp",
                              note: "A long ramp starting above the block, so the ball flies over it.",
                              strokes: [ramp(Vec2(80, 700), Vec2(500, 260))]),
            ReferenceSolution(id: "early-02-ref-short-launch",
                              note: "A short high deflector: much less ink, relies on the drop instead of the ramp.",
                              strokes: [ramp(Vec2(70, 820), Vec2(350, 560))])
        ]
    )

    // MARK: - Middle band

    /// Two-stage goal: the ball has to pass through a gap before the cup counts. This is
    /// the level where "draw a big funnel" stops working, because the funnel cannot get
    /// the ball through the gap.
    static let throughTheGap = LevelDefinition(
        id: "middle-01-through-the-gap",
        title: "Through the Gap",
        band: .middle,
        sceneSize: sceneSize,
        inkBudget: 1200,
        maxStrokes: 3,
        drawWhileRunning: false,
        spokenHint: "Send the ball through the gap first, then into the cup.",
        fixtures: [
            FixtureDefinition(kind: .box(center: Vec2(160, 520),
                                         size: Size(width: 320, height: 30),
                                         rotation: 0),
                              friction: 0.5, restitution: 0.05),
            FixtureDefinition(kind: .box(center: Vec2(610, 520),
                                         size: Size(width: 280, height: 30),
                                         rotation: 0),
                              friction: 0.5, restitution: 0.05),
            FixtureDefinition(kind: .cup(center: Vec2(400, 120),
                                         width: 190, height: 140,
                                         wallThickness: 18),
                              friction: 0.8, restitution: 0.05)
        ],
        movables: [
            MovableDefinition(tag: "ball",
                              kind: .ball(center: Vec2(130, 900), radius: 24),
                              density: 1.0, friction: 0.5, restitution: 0.15)
        ],
        goal: .ballThroughGapThenRegion(ballTag: "ball",
                                        gap: Rect(x: 325, y: 480, width: 140, height: 80),
                                        region: Rect(x: 315, y: 55, width: 170, height: 100),
                                        dwellSteps: 30),
        referenceSolutions: [
            ReferenceSolution(id: "middle-01-ref-feed-the-gap",
                              note: "A ramp that ends exactly at the near edge of the gap, so the ball drops through it.",
                              strokes: [ramp(Vec2(70, 620), Vec2(350, 560))])
        ]
    )

    /// A see-saw the child can load. Introduces the idea that a drawn shape can act on
    /// something that then acts on the ball — the first genuinely indirect solution.
    static let theSeesaw = LevelDefinition(
        id: "middle-02-the-seesaw",
        title: "The See-Saw",
        band: .middle,
        sceneSize: sceneSize,
        inkBudget: 1200,
        maxStrokes: 3,
        drawWhileRunning: false,
        spokenHint: "The plank tips. Use it.",
        fixtures: [
            FixtureDefinition(kind: .seesaw(pivot: Vec2(330, 300),
                                            length: 340, thickness: 22,
                                            density: 0.7),
                              friction: 0.7, restitution: 0.05),
            FixtureDefinition(kind: .cup(center: Vec2(640, 120),
                                         width: 190, height: 140,
                                         wallThickness: 18),
                              friction: 0.8, restitution: 0.05)
        ],
        movables: [
            MovableDefinition(tag: "ball",
                              kind: .ball(center: Vec2(150, 890), radius: 24),
                              density: 1.0, friction: 0.5, restitution: 0.15)
        ],
        goal: .ballInRegion(ballTag: "ball",
                            region: Rect(x: 555, y: 55, width: 170, height: 100),
                            dwellSteps: 30),
        referenceSolutions: [
            ReferenceSolution(id: "middle-02-ref-load-the-plank",
                              note: "Feed the ball onto the plank's left side and let the tip throw it right.",
                              strokes: [ramp(Vec2(90, 700), Vec2(300, 480))]),
            ReferenceSolution(id: "middle-02-ref-flatter-feed",
                              note: "A flatter feed that lands nearer the pivot. Slower tip, same result.",
                              strokes: [ramp(Vec2(100, 720), Vec2(320, 460))])
        ]
    )

    // MARK: - Upper band

    /// Tight ink and two strokes. The blob strategy is arithmetically impossible here, and
    /// so is a long sweeping ramp — the child has to find the short intervention.
    static let twoStrokes = LevelDefinition(
        id: "upper-01-two-strokes",
        title: "Two Strokes",
        band: .upper,
        sceneSize: sceneSize,
        inkBudget: 700,
        maxStrokes: 2,
        drawWhileRunning: false,
        spokenHint: "Two strokes only. Make them count.",
        fixtures: [
            // A tall wall the ball must be sent OVER. Deliberately taller than any ramp
            // the ink budget can reach from the floor, so the answer has to happen high up.
            FixtureDefinition(kind: .box(center: Vec2(470, 215),
                                         size: Size(width: 28, height: 430),
                                         rotation: 0),
                              friction: 0.5, restitution: 0.05),
            FixtureDefinition(kind: .cup(center: Vec2(620, 120),
                                         width: 180, height: 140,
                                         wallThickness: 16),
                              friction: 0.8, restitution: 0.05)
        ],
        movables: [
            MovableDefinition(tag: "ball",
                              kind: .ball(center: Vec2(150, 900), radius: 22),
                              density: 1.0, friction: 0.5, restitution: 0.15)
        ],
        goal: .ballInRegion(ballTag: "ball",
                            region: Rect(x: 540, y: 55, width: 160, height: 100),
                            dwellSteps: 30),
        referenceSolutions: [
            ReferenceSolution(id: "upper-01-ref-over-the-wall",
                              note: "One stroke, 335 of 700 ink: a launch ramp that clears the wall.",
                              strokes: [ramp(Vec2(70, 620), Vec2(400, 560))]),
            ReferenceSolution(id: "upper-01-ref-lower-launch",
                              note: "The same idea started lower. Proves the answer is the angle, not the height.",
                              strokes: [ramp(Vec2(70, 520), Vec2(400, 460))])
        ]
    )

    /// Draw-while-running is enabled, so timing becomes part of the answer. The platform's
    /// motion is a function of the step index, so a solution that depends on catching it at
    /// the right moment replays exactly.
    static let movingShelf = LevelDefinition(
        id: "upper-02-moving-shelf",
        title: "Moving Shelf",
        band: .upper,
        sceneSize: sceneSize,
        inkBudget: 800,
        maxStrokes: 3,
        drawWhileRunning: true,
        spokenHint: "The shelf keeps moving. You can draw while it runs.",
        fixtures: [
            FixtureDefinition(kind: .movingPlatform(center: Vec2(250, 480),
                                                    size: Size(width: 220, height: 26),
                                                    travel: Vec2(280, 0),
                                                    periodSteps: 480),
                              friction: 0.6, restitution: 0.05),
            FixtureDefinition(kind: .cup(center: Vec2(600, 120),
                                         width: 190, height: 140,
                                         wallThickness: 18),
                              friction: 0.8, restitution: 0.05)
        ],
        movables: [
            MovableDefinition(tag: "ball",
                              kind: .ball(center: Vec2(180, 900), radius: 22),
                              density: 1.0, friction: 0.5, restitution: 0.15)
        ],
        goal: .ballInRegion(ballTag: "ball",
                            region: Rect(x: 520, y: 55, width: 170, height: 100),
                            dwellSteps: 30),
        referenceSolutions: [
            ReferenceSolution(id: "upper-02-ref-timed-drop",
                              note: "A ramp that drops the ball onto the shelf as it travels right.",
                              strokes: [ramp(Vec2(100, 780), Vec2(340, 560))]),
            ReferenceSolution(id: "upper-02-ref-lower-feed",
                              note: "A lower feed that meets the shelf later in its cycle.",
                              strokes: [ramp(Vec2(90, 740), Vec2(320, 520))])
        ]
    )

    // MARK: - Helpers

    /// A straight two-point stroke committed before the simulation starts. Reference
    /// solutions are deliberately the simplest possible input: if a level needs a curve to
    /// be solvable at all, its difficulty is coming from drawing skill rather than from
    /// thinking, which is the wrong axis for this game.
    static func ramp(_ from: Vec2, _ to: Vec2, committedAtStep: Int = 0) -> RecordedStroke {
        RecordedStroke(points: [from, to], committedAtStep: committedAtStep)
    }
}
