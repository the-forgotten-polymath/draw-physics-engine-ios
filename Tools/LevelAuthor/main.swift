import Foundation

/// Authoring tool. Four jobs:
///
/// - `generate <dir>`   write the authored levels to JSON.
/// - `verify <dir>`     decode the JSON and simulate every reference solution.
/// - `search <levelID>` brute-force candidate strokes and report which solve the level,
///                      printing the winner as JSON ready to paste in.
/// - `probe <levelID> x0 y0 x1 y1 ...` dump one run's trajectory.
///
/// `search` and `probe` exist because hand-guessing coordinates for a reference solution
/// does not work — you find out whether a ramp works by running it. This is the same
/// simulator the build gate and the replay use, so a stroke found here is a stroke that
/// passes CI.

let simulator = SolutionSimulator()

func write(_ levels: [LevelDefinition], to directory: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let url = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for level in levels {
        let data = try encoder.encode(level)
        try data.write(to: url.appendingPathComponent("\(level.id).json"))
        print("wrote \(level.id).json  (\(data.count) bytes)")
    }
}

func verify(directory: String) throws -> Bool {
    let url = URL(fileURLWithPath: directory, isDirectory: true)
    let files = try FileManager.default.contentsOfDirectory(atPath: directory)
        .filter { $0.hasSuffix(".json") }
        .sorted()
    guard !files.isEmpty else {
        print("no level json in \(directory)")
        return false
    }
    var allPassed = true
    for file in files {
        let data = try Data(contentsOf: url.appendingPathComponent(file))
        let level = try LevelRepository.decode(from: data)
        if level.referenceSolutions.isEmpty {
            print("FAIL \(level.id): no reference solution")
            allPassed = false
            continue
        }
        for reference in level.referenceSolutions {
            let result = simulator.run(level: level, strokes: reference.strokes)
            let inkOK = result.inkUsed <= level.inkBudget
            let ok = result.didReachGoal && inkOK && result.rejections.isEmpty
            allPassed = allPassed && ok
            let status = ok ? "PASS" : "FAIL"
            print("""
            \(status) \(level.id)/\(reference.id)  goal=\(result.didReachGoal) \
            steps=\(result.stepsToGoal.map(String.init) ?? "-")/\(level.maximumSteps) \
            ink=\(String(format: "%.0f", result.inkUsed))/\(String(format: "%.0f", level.inkBudget)) \
            strokes=\(result.acceptedStrokes) rejections=\(result.rejections)
            """)
        }
    }
    return allPassed
}

/// Straight two-point strokes, which is what a child's first ramp actually is.
func candidateRamps() -> [[Vec2]] {
    var result: [[Vec2]] = []
    for startX in stride(from: 70.0, through: 210.0, by: 70) {
        for startY in stride(from: 420.0, through: 820.0, by: 100) {
            for endX in stride(from: 300.0, through: 700.0, by: 50) {
                for endY in stride(from: 110.0, through: 560.0, by: 50) {
                    guard endX > startX + 80, startY > endY + 40 else { continue }
                    result.append([Vec2(startX, startY), Vec2(endX, endY)])
                }
            }
        }
    }
    return result
}

/// Short catcher strokes on the right-hand side, for two-stroke solutions.
func candidateCatchers() -> [[Vec2]] {
    var result: [[Vec2]] = []
    for startX in stride(from: 280.0, through: 560.0, by: 70) {
        for startY in stride(from: 180.0, through: 520.0, by: 70) {
            for endX in stride(from: startX + 90, through: 720.0, by: 70) {
                for endY in stride(from: 110.0, through: startY, by: 70) {
                    result.append([Vec2(startX, startY), Vec2(endX, endY)])
                }
            }
        }
    }
    return result
}

struct Win {
    let strokes: [RecordedStroke]
    let steps: Int
    let ink: Double
}

func report(_ wins: [Win], levelID: String) {
    guard !wins.isEmpty else {
        print("\(levelID): no candidate solved it — the level needs redesigning, not a better search")
        return
    }
    // Prefer the cheapest solution, then the quickest. A reference solution that only just
    // makes it is exactly the one that breaks when a constant changes.
    let ranked = wins.sorted { $0.ink == $1.ink ? $0.steps < $1.steps : $0.ink < $1.ink }
    print("\(levelID): \(wins.count) solving candidates. Best five:")
    for win in ranked.prefix(5) {
        let described = win.strokes.map { stroke in
            stroke.points.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: "->")
        }.joined(separator: " | ")
        print("  ink=\(String(format: "%.0f", win.ink)) steps=\(win.steps)  \(described)")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let best = ranked.first,
       let data = try? encoder.encode(ReferenceSolution(
           id: "\(levelID)-ref-1",
           note: "Found by LevelAuthor search, verified by simulation.",
           strokes: best.strokes)),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

func solves(_ level: LevelDefinition, _ strokes: [RecordedStroke]) -> (Bool, Int, Double) {
    let result = simulator.run(level: level, strokes: strokes)
    let ok = result.didReachGoal && result.rejections.isEmpty && result.inkUsed <= level.inkBudget
    return (ok, result.stepsToGoal ?? result.stepsSimulated, result.inkUsed)
}

/// A reference solution must survive being drawn slightly differently.
///
/// Without this the search happily returns knife-edge flukes — a ball that clips a corner
/// at exactly the right angle. Those pass CI on the day they are found and fail the first
/// time a constant moves, which is the worst possible failure for a build gate. Requiring
/// every jittered variant to also solve means the reference solution reflects a real idea,
/// not a coincidence.
func isRobust(_ level: LevelDefinition, _ strokes: [RecordedStroke], jitter: Double = 6) -> Bool {
    let offsets = [Vec2(jitter, 0), Vec2(-jitter, 0), Vec2(0, jitter), Vec2(0, -jitter)]
    for offset in offsets {
        let moved = strokes.map { stroke in
            RecordedStroke(points: stroke.points.map { $0 + offset },
                           committedAtStep: stroke.committedAtStep,
                           source: stroke.source)
        }
        guard solves(level, moved).0 else { return false }
    }
    return true
}

func search(levelID: String, in levels: [LevelDefinition], maxWins: Int = 40) {
    guard let level = levels.first(where: { $0.id == levelID }) else {
        print("unknown level \(levelID)")
        return
    }

    // A level solvable with no strokes is not a level. Check first, loudly.
    if solves(level, []).0 {
        print("\(levelID): SOLVABLE WITH NO STROKES — redesign the level")
        return
    }

    var wins: [Win] = []
    let ramps = candidateRamps()
    print("single-stroke search over \(ramps.count) candidates...")
    for points in ramps {
        let strokes = [RecordedStroke(points: points, committedAtStep: 0)]
        let (ok, steps, ink) = solves(level, strokes)
        if ok, isRobust(level, strokes) {
            wins.append(Win(strokes: strokes, steps: steps, ink: ink))
            if wins.count >= maxWins { break }
        }
    }

    if wins.isEmpty {
        let catchers = candidateCatchers()
        let feeders = ramps.enumerated().filter { $0.offset % 5 == 0 }.map { $0.element }
        print("two-stroke search over \(feeders.count) x \(catchers.count) candidates...")
        outer: for feeder in feeders {
            for catcher in catchers {
                let strokes = [RecordedStroke(points: feeder, committedAtStep: 0),
                               RecordedStroke(points: catcher, committedAtStep: 0)]
                let (ok, steps, ink) = solves(level, strokes)
                if ok, isRobust(level, strokes) {
                    wins.append(Win(strokes: strokes, steps: steps, ink: ink))
                    if wins.count >= maxWins { break outer }
                }
            }
        }
    }
    report(wins, levelID: levelID)
}

/// Dumps a single run's trajectory. This is the tool you actually reach for when a level
/// will not solve: it answers "is the ball even hitting the thing I drew" in one line.
func probe(levelID: String, points: [Vec2], in levels: [LevelDefinition]) {
    guard let level = levels.first(where: { $0.id == levelID }) else {
        print("unknown level \(levelID)")
        return
    }
    let strokes = points.isEmpty ? [] : [RecordedStroke(points: points, committedAtStep: 0)]
    let result = simulator.run(level: level, strokes: strokes, captureEveryNthStep: 30)
    print("goal=\(result.didReachGoal) steps=\(result.stepsSimulated) ink=\(String(format: "%.0f", result.inkUsed)) rejections=\(result.rejections) accepted=\(result.acceptedStrokes)")
    for frame in result.frames {
        let ball = frame.bodies.first { $0.tag == "ball" }
        let ballText = ball.map { "(\(Int($0.position.x)),\(Int($0.position.y)))" } ?? "missing"
        print("  step \(frame.stepIndex): ball \(ballText)  bodies=\(frame.bodies.count)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print("usage: LevelAuthor generate <dir> | verify <dir> | search <levelID> | probe <levelID> x0 y0 ...")
    exit(2)
}

switch command {
case "generate":
    try write(AuthoredLevels.all, to: arguments.count > 1 ? arguments[1] : "Sources/DrawPhysicsCore/Levels")

case "verify":
    let passed = try verify(directory: arguments.count > 1 ? arguments[1] : "Sources/DrawPhysicsCore/Levels")
    print(passed ? "all reference solutions pass" : "FAILURES PRESENT")
    exit(passed ? 0 : 1)

case "search":
    guard arguments.count > 1 else { print("search needs a level id"); exit(2) }
    search(levelID: arguments[1], in: AuthoredLevels.all)

case "bench":
    // Numbers for ENGINEERING.md. Measured, not estimated.
    let decomposer = ConvexDecomposer()
    let shapes: [(String, [Vec2])] = [
        ("circle-blob", (0..<220).map { i in
            let a = 2 * Double.pi * Double(i) / 220
            return Vec2(300 + cos(a) * 90, 400 + sin(a) * 90)
        }),
        ("scoop", (0..<180).map { i in
            let a = Double.pi * Double(i) / 179
            let r = 110.0
            return Vec2(300 + cos(.pi + a) * r, 400 + sin(.pi + a) * r * 0.7)
        } + [Vec2(300 - 90, 430), Vec2(300 + 90, 430)]),
        ("star", (0..<10).map { i in
            let a = Double(i) * Double.pi / 5 - Double.pi / 2
            let r = i.isMultiple(of: 2) ? 110.0 : 46.0
            return Vec2(300 + cos(a) * r, 400 + sin(a) * r)
        }),
        ("comb", { () -> [Vec2] in
            var pts: [Vec2] = [Vec2(100, 300), Vec2(340, 300), Vec2(340, 330)]
            var x = 340.0
            while x > 100 {
                pts.append(contentsOf: [Vec2(x, 330), Vec2(x, 400), Vec2(x - 20, 400), Vec2(x - 20, 330)])
                x -= 40
            }
            pts.append(Vec2(100, 330))
            return pts
        }())
    ]
    print("shape           rawPts  simplified  triangles  merged  reduction")
    for (name, raw) in shapes {
        guard let processed = StrokeSimplifier().process(rawPoints: raw) else {
            print("\(name): rejected"); continue
        }
        let canonical = Polygon.ensureCounterClockwise(processed.simplifiedPoints)
        let triangles = ConvexDecomposer.earClip(canonical).count
        let merged = decomposer.decompose(processed.simplifiedPoints).count
        let reduction = merged > 0 ? Double(triangles) / Double(merged) : 0
        print(String(format: "%-15@ %6d  %10d  %9d  %6d  %.2fx",
                     name as NSString, raw.count, processed.simplifiedPoints.count,
                     triangles, merged, reduction))
    }

    // Step cost with a realistic worst case: a level plus several committed strokes.
    let benchLevel = AuthoredLevels.throughTheGap
    let built = SceneBuilder.build(level: benchLevel)
    let benchPipeline = StrokePipeline()
    var benchBudget = InkBudget(total: 100_000)
    // Worst case a child can actually reach: the ink budget spent entirely on wiggly open
    // chains and closed blobs, which is the maximum shape count the narrowphase ever sees.
    var benchID = 0
    for row in 0..<6 {
        let y = 760.0 - Double(row) * 55
        let wiggle = (0..<160).map { i in
            Vec2(70 + Double(i) * 3.8, y + sin(Double(i) / 6) * 26)
        }
        if case let .accepted(shape, cost) = benchPipeline.makeShape(id: benchID, rawPoints: wiggle,
                                                                    source: .freehand, budget: benchBudget) {
            benchBudget.charge(cost)
            SceneBuilder.addDrawnShape(shape, to: built.world)
            benchID += 1
        }
    }
    for column in 0..<6 {
        let centre = Vec2(120 + Double(column) * 100, 300)
        let blob = (0..<140).map { i -> Vec2 in
            let a = 2 * Double.pi * Double(i) / 140
            return centre + Vec2(cos(a) * 44, sin(a) * (34 + sin(a * 3) * 12))
        }
        if case let .accepted(shape, cost) = benchPipeline.makeShape(id: benchID, rawPoints: blob,
                                                                    source: .freehand, budget: benchBudget) {
            benchBudget.charge(cost)
            SceneBuilder.addDrawnShape(shape, to: built.world)
            benchID += 1
        }
    }
    print("committed \(benchID) drawn shapes")
    let totalShapes = built.world.bodies.reduce(0) { $0 + $1.shapes.count }
    let benchStart = Date()
    let benchSteps = 12_000
    for _ in 0..<benchSteps { built.world.stepOnce() }
    let elapsed = Date().timeIntervalSince(benchStart)
    print(String(format: "bodies=%d shapes=%d  %d steps in %.3fs  =>  %.0f steps/s, %.4f ms/step",
                 built.world.bodies.count, totalShapes, benchSteps, elapsed,
                 Double(benchSteps) / elapsed, elapsed / Double(benchSteps) * 1000))
    print(String(format: "budget at 120Hz is 8.333 ms/frame; simulation uses %.2f%% of it",
                 (elapsed / Double(benchSteps) * 1000) / 8.333 * 100))

case "check":
    guard arguments.count > 1, let level = AuthoredLevels.all.first(where: { $0.id == arguments[1] }) else {
        print("check needs a known level id")
        exit(2)
    }
    let numbers = arguments.dropFirst(2).compactMap(Double.init)
    var checkPoints: [Vec2] = []
    var cursor = 0
    while cursor + 1 < numbers.count {
        checkPoints.append(Vec2(numbers[cursor], numbers[cursor + 1]))
        cursor += 2
    }
    let checkStrokes = [RecordedStroke(points: checkPoints, committedAtStep: 0)]
    let (ok, steps, ink) = solves(level, checkStrokes)
    let robust = ok && isRobust(level, checkStrokes)
    print("\(level.id): solves=\(ok) robust=\(robust) steps=\(steps) ink=\(String(format: "%.0f", ink))/\(String(format: "%.0f", level.inkBudget))")

case "probe":
    guard arguments.count > 1 else { print("probe needs a level id"); exit(2) }
    let numbers = arguments.dropFirst(2).compactMap(Double.init)
    var points: [Vec2] = []
    var index = 0
    while index + 1 < numbers.count {
        points.append(Vec2(numbers[index], numbers[index + 1]))
        index += 2
    }
    probe(levelID: arguments[1], points: points, in: AuthoredLevels.all)

default:
    print("unknown command \(command)")
    exit(2)
}
