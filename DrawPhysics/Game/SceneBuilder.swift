import Foundation

/// Turns a level definition into a world. Deterministic and order-stable: fixtures are
/// added in authored order, then movables, then the child's strokes as they are committed.
/// Body order is part of the reproducibility contract, so this function must never
/// reorder anything.
public struct SceneBuilder {

    public struct Built {
        public let world: FixedStepWorld
        public let ballBodies: [String: RigidBody]
    }

    public static let boundaryThickness = 60.0

    public static func build(level: LevelDefinition) -> Built {
        let world = FixedStepWorld()
        let size = level.sceneSize

        // Boundaries. The ceiling is deliberately absent: a ball launched out of the top
        // simply leaves, which reads as an honest miss rather than a trick bounce.
        addStaticBox(world, tag: .floor,
                     center: Vec2(size.width / 2, -boundaryThickness / 2),
                     size: Size(width: size.width * 3, height: boundaryThickness),
                     friction: 0.7)
        addStaticBox(world, tag: .wall,
                     center: Vec2(-boundaryThickness / 2, size.height / 2),
                     size: Size(width: boundaryThickness, height: size.height * 2),
                     friction: 0.4)
        addStaticBox(world, tag: .wall,
                     center: Vec2(size.width + boundaryThickness / 2, size.height / 2),
                     size: Size(width: boundaryThickness, height: size.height * 2),
                     friction: 0.4)

        for (index, fixture) in level.fixtures.enumerated() {
            addFixture(fixture, index: index, to: world)
        }

        var balls: [String: RigidBody] = [:]
        for movable in level.movables {
            let body = addMovable(movable, to: world)
            if case .ball = movable.kind { balls[movable.tag] = body }
        }

        return Built(world: world, ballBodies: balls)
    }

    // MARK: - Fixtures

    private static func addFixture(_ fixture: FixtureDefinition, index: Int, to world: FixedStepWorld) {
        switch fixture.kind {
        case let .box(center, size, rotation):
            world.add { id in
                let body = RigidBody(id: id,
                                     tag: BodyTag("fixture.\(index)"),
                                     shapes: [.polygon(boxVertices(size))],
                                     motion: .static,
                                     position: center,
                                     rotation: rotation,
                                     restitution: fixture.restitution,
                                     friction: fixture.friction)
                return body
            }

        case let .polygon(points):
            // An authored polygon may be concave, exactly like a drawn one, so it goes
            // through the same decomposition path rather than a second code route.
            let centred = Polygon.centroid(points)
            let local = points.map { $0 - centred }
            let pieces = ConvexDecomposer().decompose(local)
            guard !pieces.isEmpty else { return }
            world.add { id in
                RigidBody(id: id,
                          tag: BodyTag("fixture.\(index)"),
                          shapes: pieces.map { Shape.polygon($0) },
                          motion: .static,
                          position: centred,
                          restitution: fixture.restitution,
                          friction: fixture.friction)
            }

        case let .cup(center, width, height, wallThickness):
            let half = width / 2
            addStaticBox(world, tag: BodyTag("cup.base.\(index)"),
                         center: Vec2(center.x, center.y - height / 2 + wallThickness / 2),
                         size: Size(width: width, height: wallThickness),
                         friction: fixture.friction, restitution: fixture.restitution)
            addStaticBox(world, tag: BodyTag("cup.left.\(index)"),
                         center: Vec2(center.x - half + wallThickness / 2, center.y),
                         size: Size(width: wallThickness, height: height),
                         friction: fixture.friction, restitution: fixture.restitution)
            addStaticBox(world, tag: BodyTag("cup.right.\(index)"),
                         center: Vec2(center.x + half - wallThickness / 2, center.y),
                         size: Size(width: wallThickness, height: height),
                         friction: fixture.friction, restitution: fixture.restitution)

        case let .movingPlatform(center, size, travel, periodSteps):
            let path = KinematicPath(origin: center, travel: travel, periodSteps: periodSteps)
            world.add { id in
                let body = RigidBody(id: id,
                                     tag: BodyTag("platform.\(index)"),
                                     shapes: [.polygon(boxVertices(size))],
                                     motion: .kinematic,
                                     position: path.position(atStep: 0),
                                     restitution: fixture.restitution,
                                     friction: fixture.friction)
                body.kinematicPath = path
                return body
            }

        case let .seesaw(pivot, length, thickness, density):
            let plank = world.add { id in
                RigidBody(id: id,
                          tag: BodyTag("seesaw.\(index)"),
                          shapes: [.polygon(boxVertices(Size(width: length, height: thickness)))],
                          motion: .dynamic,
                          position: pivot,
                          density: density,
                          restitution: fixture.restitution,
                          friction: fixture.friction,
                          linearDamping: 0.4,
                          angularDamping: 0.6)
            }
            // The pin needs something immovable to pin against, and that anchor must have NO
            // collider. Giving it a visible post shape puts a static box inside the plank, the
            // contact solver spends every step pushing the two apart, and the plank walks off
            // its own pivot. The post a child sees is drawn by the renderer, not simulated.
            let anchor = world.add { id in
                RigidBody(id: id,
                          tag: BodyTag("seesaw.anchor.\(index)"),
                          shapes: [],
                          motion: .static,
                          position: pivot)
            }
            world.addJoint(a: anchor, b: plank, worldAnchor: pivot)
        }
    }

    private static func addStaticBox(_ world: FixedStepWorld,
                                     tag: BodyTag,
                                     center: Vec2,
                                     size: Size,
                                     friction: Double = 0.6,
                                     restitution: Double = 0.1) {
        world.add { id in
            RigidBody(id: id,
                      tag: tag,
                      shapes: [.polygon(boxVertices(size))],
                      motion: .static,
                      position: center,
                      restitution: restitution,
                      friction: friction)
        }
    }

    // MARK: - Movables

    private static func addMovable(_ movable: MovableDefinition, to world: FixedStepWorld) -> RigidBody {
        switch movable.kind {
        case let .ball(center, radius):
            return world.add { id in
                RigidBody(id: id,
                          tag: BodyTag(movable.tag),
                          shapes: [.circle(radius: radius)],
                          motion: .dynamic,
                          position: center,
                          density: movable.density,
                          restitution: movable.restitution,
                          friction: movable.friction,
                          linearDamping: 0.05,
                          angularDamping: 0.05)
            }

        case let .crate(center, size, rotation):
            return world.add { id in
                RigidBody(id: id,
                          tag: BodyTag(movable.tag),
                          shapes: [.polygon(boxVertices(size))],
                          motion: .dynamic,
                          position: center,
                          rotation: rotation,
                          density: movable.density,
                          restitution: movable.restitution,
                          friction: movable.friction)
            }
        }
    }

    // MARK: - Drawn shapes

    /// A committed stroke becomes ONE static body carrying every convex piece.
    ///
    /// This is the refinement of §8.2's "each piece is a body": narrowphase cost tracks
    /// the number of *pairs* tested, and because static bodies never collide with each
    /// other, collapsing a stroke's pieces into a single static body removes every
    /// intra-stroke pair and every broadphase entry but one.
    @discardableResult
    public static func addDrawnShape(_ shape: DrawnShape, to world: FixedStepWorld) -> RigidBody? {
        guard !shape.convexPieces.isEmpty else { return nil }
        let anchor = Polygon.centroid(shape.simplifiedPoints)
        let localPieces = shape.convexPieces.map { piece in piece.map { $0 - anchor } }
        return world.add { id in
            RigidBody(id: id,
                      tag: BodyTag("drawn.\(shape.id)"),
                      shapes: localPieces.map { Shape.polygon($0) },
                      motion: .static,
                      position: anchor,
                      // Drawn ink is deliberately grippy and dead: a child expects the
                      // line they drew to hold the ball, not flick it away.
                      restitution: 0.05,
                      friction: 0.7)
        }
    }

    public static func boxVertices(_ size: Size) -> [Vec2] {
        let hw = size.width / 2, hh = size.height / 2
        return [Vec2(-hw, -hh), Vec2(hw, -hh), Vec2(hw, hh), Vec2(-hw, hh)]
    }
}
