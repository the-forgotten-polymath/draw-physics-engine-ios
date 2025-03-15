# Build Brief: "DrawPhysics" — Divergent Thinking (IMPLEMENTATION-GRADE)

> **MANDATORY:** Read `../IMPLEMENTATION_STANDARD.md` and `00_README.md` first. Inherits every rule — **no mock data, real physics simulation, real polygon decomposition, real fixed-timestep determinism, must compile and pass XCTests.** iOS-only, SwiftUI + SpriteKit.
>
> **Depends on `KidsGameCore`** (built in `01_EchoPath.md` §4).
>
> ---
>
> **STATUS — read before building.** This document has two parts.
>
> - **Part I (§1–§11)** is the original design brief. It is still the product spec, but
>   three of its engineering claims are wrong; §8.3's central code snippet does not compile.
> - **Part II (§12–§19)** is the implementation. §12 lists the corrections. §13–§17 are
>   **working, verified source** — the geometry pipeline, a hand-written deterministic
>   physics engine, six authored levels, and 40 passing tests. §18 is a file-by-file master
>   plan for the remaining UI layer, which is **not yet written**. §19 is a ledger of what
>   has been proven and what has not.
>
> **If you are an AI IDE building this: start at §12, then §18.15 for the build order.**
> Do not implement §8.3's snippet.

---

## 1. Game Summary

| | |
|---|---|
| **Primary skill** | Divergent thinking (`00_README.md` §1, skill 18) |
| **Supporting skills** | Planning, spatial reasoning |
| **Age bands** | Early (4–6), Middle (7–9), Upper (10–13) |
| **Session length** | 2–10 minutes (open-ended) |
| **Co-play** | Yes — "Your Turn to Draw" (§5.6) |

Get the ball into the cup. **Draw whatever you think will work.**

Anything you draw becomes a real solid object that falls, rolls, tips and collides. There is no intended answer — a ramp works, a scoop works, a wall that redirects works, dropping a heavy blob on a see-saw works. **The game cannot tell you your idea was wrong, only whether the ball got in.**

That is what makes it the divergent-thinking game in the folder. Every other game has a correct answer; this one has a goal and an open space of ways to reach it.

**Theme:** a sketchbook where drawings come to life.

**Non-goals:** a single intended solution, star ratings, timers, streaks, physics education claims, any claim of improving creativity (`00_README.md` §2.1).

---

## 2. The two hard problems, named up front

**Freehand strokes are not physics bodies.** A child's drawn loop is a self-intersecting, concave, thousand-point polyline. Physics engines need convex polygons. Turning one into the other — without losing the shape the child drew — is a real geometry pipeline (§8.2).

**Physics is not reproducible by default.** The whole social hook is *"watch how I solved it"*, which requires a replay. But floating-point simulation diverges: the same strokes on a different device, or at a different frame rate, can produce a different outcome — so a replay of a successful solution can *fail*. That is worse than having no replay at all. §8.3 addresses it, and does so honestly rather than claiming determinism the engine cannot provide.

---

## 3. Exact Tech Stack (PIN THESE VERSIONS)

| Concern | Choice | Notes |
|---|---|---|
| Language / IDE | Swift `5.10` · Xcode `15.4+` | — |
| Min target | iOS `17.0` | — |
| Shell UI | SwiftUI | Menus, level select, replay gallery |
| Simulation + render | **SpriteKit** (`SKPhysicsWorld`) | Fixed timestep (§8.3) |
| Touch capture | `UIViewRepresentable` with coalesced touches | Same reasoning as `15_TraceIt.md` §8.4 |
| Geometry | In-repo simplification + decomposition | §8.2 |
| Audio | AVFoundation | Draw scratch, collision thuds |
| Haptics | Core Haptics | Stroke feel, goal reached |
| Speech | `AVSpeechSynthesizer` | Goal stated aloud |
| Persistence | SwiftData | On-device only |
| Shared | **`KidsGameCore`** | `Difficulty`, `Progress`, `CoPlay`, `Instruct`, `ShowSomeone`, `AXGame` |
| Tests | XCTest + XCUITest | — |
| Analytics | **None** | `00_README.md` §5.1 |

---

## 4. Repository Layout

```
DrawPhysics/
├── DrawPhysics.xcodeproj
├── DrawPhysics/
│   ├── DrawPhysicsApp.swift
│   ├── Models/
│   │   ├── Level.swift                 # goal, fixtures, ink budget
│   │   ├── DrawnShape.swift            # raw stroke + decomposed bodies
│   │   ├── Solution.swift              # recorded strokes (the artifact) — §8.3
│   │   └── DrawPhysicsDifficulty.swift
│   ├── Geometry/
│   │   ├── StrokeSimplifier.swift      # RDP + self-intersection repair (§8.2)
│   │   ├── ConvexDecomposer.swift      # concave → convex pieces (§8.2)
│   │   └── InkMeter.swift              # budget accounting (§8.4)
│   ├── Sim/
│   │   ├── FixedStepWorld.swift        # deterministic-as-possible stepping (§8.3)
│   │   ├── SolutionRecorder.swift      # records INPUT, not output (§8.3)
│   │   └── OutcomeJudge.swift          # goal reached, authoritatively (§8.3)
│   ├── Modes/
│   │   ├── SoloFlow.swift
│   │   └── YourTurnToDrawFlow.swift    # co-play (§5.6)
│   ├── Views/
│   │   ├── HomeView.swift
│   │   ├── PlayScene.swift             # SKScene
│   │   ├── ReplayView.swift
│   │   └── GrownUpView.swift           # behind ParentGate
│   └── Resources/Levels/               # AUTHORED (§8.5)
├── DrawPhysicsTests/
│   ├── ConvexDecomposerTests.swift     # THE critical test file
│   ├── StrokeSimplifierTests.swift
│   ├── FixedStepWorldTests.swift
│   └── LevelIntegrityTests.swift
├── DrawPhysicsUITests/
│   ├── FTUETimingTests.swift
│   └── AccessibilityAuditTests.swift
└── ENGINEERING.md
```

---

## 5. Data Model & Core Spec

```swift
import SwiftData
import CoreGraphics

struct Level: Codable, Identifiable {
    var id: String
    var goal: Goal                       // ball into cup, ball above line, two balls touch...
    var fixtures: [Fixture]              // static geometry the child cannot change
    var movableBodies: [MovableBody]     // the ball(s), see-saws, crates
    /// Total drawable length. The constraint that forces thought instead of
    /// "draw a giant blob" (§8.4).
    var inkBudget: Double
    var band: AgeBand
    /// At least one authored solution, PROVING the level is solvable (§8.5).
    var referenceSolutionIDs: [String]
}

@Model
final class Solution {
    @Attribute(.unique) var id: UUID
    var levelID: String
    /// The recorded INPUT: normalised stroke points plus the sim step each stroke
    /// was committed on. Recording input rather than resulting motion is what makes
    /// a replay possible at all (§8.3).
    var strokesJSON: Data
    /// Authoritative outcome, judged during the ORIGINAL run and stored.
    /// A replay that diverges cannot retroactively un-solve the level (§8.3).
    var didReachGoal: Bool
    var inkUsed: Double
    var strokeCount: Int
    var createdAt: Date

    init(levelID: String, strokesJSON: Data, didReachGoal: Bool,
         inkUsed: Double, strokeCount: Int) {
        self.id = UUID(); self.levelID = levelID
        self.strokesJSON = strokesJSON; self.didReachGoal = didReachGoal
        self.inkUsed = inkUsed; self.strokeCount = strokeCount
        self.createdAt = .now
    }
}

/// A drawn stroke after processing: the original polyline plus the convex pieces
/// the physics engine actually receives.
struct DrawnShape: Codable {
    var rawPoints: [CGPoint]
    var simplifiedPoints: [CGPoint]
    var convexPieces: [[CGPoint]]        // each convex, each a physics body (§8.2)
    var isClosed: Bool                   // closed → filled solid; open → thin chain
    var inkLength: Double
}
```

### 5.1 Drawing
The child draws with a finger while the simulation is **paused**. Strokes appear as ink. Releasing commits the stroke, which is decomposed (§8.2) and becomes a static body. Tapping play starts the simulation.

**Undo removes the last stroke and refunds its ink.** Unlimited, free, and it is what makes experimenting safe.

At higher bands strokes can be drawn **while the simulation runs**, which turns the game into live intervention and is a genuinely different feel.

### 5.2 There is no wrong answer, only outcomes
When the goal is reached: celebration, and the solution is saved to the gallery. When it is not: nothing negative happens. The scene resets, the strokes are **kept for editing**, and the child adjusts. No failure state, no attempt counter, no stars.

### 5.3 The gallery is the "show someone" artifact
Every successful solution is saved and replayable. This is `00_README.md` §3.1's show-someone mechanism, and it is unusually strong here because **solutions genuinely differ** — two children solving the same level produce visibly different drawings, which is the thing worth showing.

Replays can be exported as a video to share with a family member. Export is behind the parental gate (`00_README.md` §5.4).

### 5.4 Difficulty axes
| Axis | Easier | Harder |
|---|---|---|
| Ink budget | generous | tight, forcing economy |
| Goal | ball into a wide cup | ball must pass through a gap first |
| Fixtures | simple ramp | moving platforms, see-saws |
| Draw-while-running | off | on |
| Stroke count limit | unlimited | 2–3 strokes |

**Ink budget is the primary axis** and the one that creates thinking. With unlimited ink, every level is solved by drawing a huge funnel; with a tight budget the child must find the *efficient* idea.

### 5.5 Progress
Capability statements about invention, not efficiency: *"You solved that level three different ways."* *"You used only two strokes."* Never a score, never stars, never a "creativity" rating (`00_README.md` §2.2).

### 5.6 "Your Turn to Draw" co-play
Players alternate strokes toward the same goal, with the simulation running only after both have drawn. Neither controls the whole solution, so they must read each other's intent — and the failures are extremely funny, which is what makes it replayable.

---

## 6. Age bands

| Band | Ink | Goals | Fixtures | Draw while running |
|---|---|---|---|---|
| **Early (4–6)** | very generous | ball into a wide cup | static ramps only | no |
| **Middle (7–9)** | moderate | gap traversal, two-ball goals | see-saws, hinges | no |
| **Upper (10–13)** | tight | multi-stage goals | moving platforms | yes |

**Accessibility.** This game requires drawing, so like `15_TraceIt.md` it **cannot be made fully playable without vision**, and the honest position is to say so. What it does provide: adjustable ink-stroke thickness and contrast; **no time pressure at all**, so slow or imprecise drawing is never penalised; a tap-to-place library of **pre-made shapes** (ramp, block, ball) for children who cannot draw freehand, which preserves the divergent-thinking goal through a different input; and full VoiceOver navigation of menus and the gallery. The parent-facing text states the game is not suitable for blind children.

---

## 7. Milestones

- **M0 — Skeleton.** Project, `KidsGameCore`, SwiftData, SpriteKit scene, spoken goals. ✅ Accessibility audit zero errors on menus.
- **M1 — `StrokeSimplifier` (§8.2).** RDP simplification plus self-intersection handling. ✅ Tests prove a self-intersecting loop yields valid non-degenerate geometry and that simplification preserves overall shape within tolerance.
- **M2 — `ConvexDecomposer` (§8.2).** Concave polygon → convex pieces. ✅ `ConvexDecomposerTests` proves every output piece is convex, correctly wound, and that the union area matches the input within tolerance. **This gate blocks everything else.**
- **M3 — `FixedStepWorld` (§8.3).** Fixed-timestep stepping decoupled from frame rate. ✅ Tests prove the same stroke sequence produces the same outcome across `[N]` runs **on the same device**, and that a forced frame-rate change does not alter the outcome.
- **M4 — Draw + simulate loop.** Ink rendering, stroke commit, play/reset, stroke-preserving retry, undo with ink refund. ✅ A level is solvable; undo refunds correctly.
- **M5 — `InkMeter` (§8.4) + degenerate-solution prevention.** Budget accounting, minimum stroke length, closed-shape area cap. ✅ Tests prove a single giant blob cannot be drawn within any band's budget.
- **M6 — `SolutionRecorder` + gallery (§8.3).** Input recording, replay, authoritative stored outcome, video export behind the parent gate. ✅ Tests prove a stored `didReachGoal` is never mutated by a replay.
- **M7 — Co-play, shape library, FTUE.** ✅ Pre-made shapes work as an alternative input; `FTUETimingTests` proves first success under 30s with no reading.

---

## 8. Hard-Part Engineering Deep-Dive

### 8.2 From freehand stroke to physics bodies

A drawn stroke arrives as several hundred points, possibly self-intersecting, almost certainly concave. Physics engines want **convex** polygons with consistent winding. Four stages:

**1. Simplify.** Ramer–Douglas–Peucker to a manageable vertex count. Too aggressive and the child's shape is visibly not what they drew; too light and decomposition is slow. Tolerance is a documented constant.

**2. Detect closure.** If the endpoints are near each other, treat the stroke as a **closed filled solid**; otherwise as an **open thin chain**. This distinction matters enormously to a child: a closed loop should be a solid blob that things sit on, an open line should be a thin barrier things slide along.

**3. Repair self-intersection.** A self-intersecting polygon has no well-defined interior, so decomposition is meaningless. Rather than attempting general repair, the implementation takes the **largest simple sub-loop** — which for a child's accidental crossing is nearly always the shape they meant.

**4. Decompose.** Concave → convex pieces.

```swift
// Geometry/ConvexDecomposer.swift
struct ConvexDecomposer {
    /// Decompose a simple polygon into convex pieces.
    /// Ear clipping to triangles is trivially correct but produces MANY bodies, and
    /// body count is the dominant physics cost — a 40-triangle blob tanks the frame
    /// rate. So triangulate first, then merge adjacent triangles while the union
    /// stays convex (Hertel-Mehlhorn style), trading a little optimality for far
    /// fewer bodies.
    func decompose(_ polygon: [CGPoint]) -> [[CGPoint]] {
        let simple = ensureCounterClockwise(polygon)
        guard !isConvex(simple) else { return [simple] }

        var pieces = earClip(simple)              // guaranteed to terminate
        pieces = mergeWhileConvex(pieces)         // reduce body count
        return pieces.filter { area(of: $0) > minimumPieceArea }   // drop slivers
    }

    /// Sliver triangles cause physics instability — near-zero-area bodies produce
    /// enormous impulses on contact and make objects jitter or launch. Dropping them
    /// changes the shape imperceptibly and fixes a whole class of weirdness.
    private let minimumPieceArea: Double = 4.0
}
```

Three details carry this. **Winding must be canonicalised** — inconsistent winding gives inverted normals and objects fall through surfaces. **Body count matters more than piece optimality**, because physics cost scales with bodies. **Sliver triangles must be dropped**, since near-degenerate bodies generate huge contact impulses and cause the jitter-and-launch behaviour that reads as the game being broken.

`ConvexDecomposerTests` asserts every piece is convex, correctly wound, and that total area matches the input within tolerance.

### 8.3 Replay, and being honest about determinism

**The problem.** A replay must reproduce the outcome. But floating-point physics is not bit-reproducible across devices or architectures, and SpriteKit offers no determinism guarantee. So a shared replay of a successful solution can, on another device, fail — which is a worse experience than no sharing at all.

**Three-part response, and the third part is the honest one:**

**1. Fixed timestep, decoupled from frame rate.** Variable-timestep simulation is non-deterministic even on one device, because step size depends on frame timing. A fixed accumulator removes that entirely:

> **⛔ DO NOT IMPLEMENT THE SNIPPET BELOW.** `SKPhysicsWorld.step(forSeconds:)` does not
> exist — SpriteKit exposes no public way to advance its physics world, so this code does not
> compile and the approach is not achievable on that engine. The reasoning in this section is
> right; the mechanism is wrong. **See §12.1 for the correction and §14.2 for the working
> implementation.**

```swift
// Sim/FixedStepWorld.swift
final class FixedStepWorld {
    private let stepSeconds = 1.0 / 120.0
    private var accumulator = 0.0
    private(set) var stepIndex = 0

    /// Step by a FIXED amount, however long the frame took. Without this the
    /// simulation depends on frame rate, so the same input produces different
    /// results on a 60Hz and a 120Hz device — and on the same device under load.
    func advance(by frameDelta: TimeInterval, world: SKPhysicsWorld) {
        accumulator += min(frameDelta, 0.25)      // clamp so a stall cannot spiral
        while accumulator >= stepSeconds {
            world.step(forSeconds: stepSeconds)   // uniform steps only
            stepIndex += 1
            accumulator -= stepSeconds
        }
    }
}
```

**2. Record input, not output.** `Solution` stores the strokes and the step index each was committed on — not the resulting motion. Replay re-simulates from the recorded input. This keeps the artifact small and makes it genuinely a record of what the child *did*.

**3. The outcome is judged once, during the original run, and stored.** `didReachGoal` is authoritative and **immutable**. If a replay on another device diverges and the ball misses, the solution is still recorded as solved — because it *was*. The replay is presented as *"here's how they did it"*, and `ENGINEERING.md` documents that visual divergence is possible across devices.

This is the honest engineering position: cross-device bit-determinism is not achievable on this stack, so the design makes divergence harmless rather than pretending it cannot happen. `FixedStepWorldTests.testStoredOutcomeIsNeverMutatedByReplay` enforces it.

### 8.4 The ink budget prevents the degenerate solution

Without a constraint, every level is solved identically: draw an enormous funnel around the ball and the cup. It works, it requires no thought, and it makes every level the same.

`InkMeter` charges by **stroke arc length**, with two additional guards:

- **A closed-shape area cap** — a closed loop is charged for its enclosed area as well as its perimeter, so a big blob is expensive even though its outline is short. Without this, arc length alone lets a child enclose the whole scene cheaply.
- **A minimum stroke length** — accidental taps do not create tiny unstable bodies.

`InkMeterTests.testSingleGiantBlobExceedsEveryBandBudget` is the test that keeps levels interesting.

### 8.5 Levels are authored and proven solvable

Levels are hand-designed, and each carries **at least one authored reference solution** whose strokes are stored and replayed in tests. `LevelIntegrityTests` fails the build if any level's reference solution does not reach the goal when simulated, and if any reference solution exceeds the level's ink budget.

This means a level cannot ship unsolvable, and it cannot ship with a budget too tight for its own intended answer — the two failures a hand-designed level is most likely to have.

### 8.6 What `ENGINEERING.md` must contain
- The stroke pipeline stages with tolerances, and the self-intersection strategy with its limitation.
- Decomposition piece counts before and after merging, with the measured frame-rate impact of body count.
- The sliver-area threshold and the instability it prevents.
- Fixed-timestep evidence: identical outcomes across runs and across forced frame rates on one device.
- **An explicit statement that cross-device bit-determinism is not guaranteed**, and how the stored-outcome design makes that harmless.
- Ink-budget calibration per band, and evidence the blob strategy is excluded.
- Confirmation every authored level's reference solution passes.
- The stated non-suitability for blind children, and what the shape library provides instead.
- Restatement of `00_README.md` §2.1.

---

## 9. Verify Commands

```bash
xcodebuild -project DrawPhysics.xcodeproj -scheme DrawPhysics \
  -sdk iphoneos -destination 'generic/platform=iOS' build
swift test --package-path ../KidsGameCore
xcodebuild test -project DrawPhysics.xcodeproj -scheme DrawPhysics \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15'

# Named invariant tests — the first BLOCKS the build:
#   ConvexDecomposerTests.testEveryPieceIsConvex
#   ConvexDecomposerTests.testWindingIsCanonicalised
#   ConvexDecomposerTests.testUnionAreaMatchesInputWithinTolerance
#   ConvexDecomposerTests.testSliverTrianglesAreDropped
#   StrokeSimplifierTests.testSelfIntersectingLoopYieldsValidGeometry
#   StrokeSimplifierTests.testClosureDetectionDistinguishesLoopFromLine
#   FixedStepWorldTests.testSameInputSameOutcomeAcrossRunsOnDevice
#   FixedStepWorldTests.testForcedFrameRateChangeDoesNotAlterOutcome
#   FixedStepWorldTests.testStoredOutcomeIsNeverMutatedByReplay
#   InkMeterTests.testSingleGiantBlobExceedsEveryBandBudget
#   InkMeterTests.testUndoRefundsExactlyTheStrokeCost
#   LevelIntegrityTests.testEveryLevelReferenceSolutionReachesGoal
#   LevelIntegrityTests.testEveryReferenceSolutionFitsItsInkBudget
#   FTUETimingTests.testFirstSuccessUnderThirtySecondsWithoutReading

# ---- ON-DEVICE MANUAL (required — physics feel cannot be validated in simulator) ----
#  1. Draw a closed loop. Confirm it becomes a SOLID blob things rest on.
#  2. Draw an open line. Confirm it becomes a THIN barrier, not a filled shape.
#  3. Draw a deliberately self-crossing squiggle. Confirm it produces a sensible solid,
#     not exploding geometry.
#  4. Draw a very thin sliver. Confirm nothing jitters or launches across the screen.
#  5. Solve a level. Then solve it a COMPLETELY different way. Confirm both are saved.
#  6. Fail a level. Confirm nothing negative happens and your strokes are KEPT for editing.
#  7. Undo several strokes. Confirm ink is refunded exactly.
#  8. Try to solve a Middle-band level with one giant blob. Confirm the ink budget forbids it.
#  9. Replay a saved solution. Confirm it plays back and that the "solved" mark is unchanged
#     even if the ball behaves slightly differently.
# 10. Upper band: draw while the simulation is running. Confirm it feels different and works.
# 11. Use the pre-made shape library with taps only, no drawing. Confirm a level is solvable.
# 12. VoiceOver: navigate menus and the gallery. Confirm the parent text states the game is
#     unsuitable for blind children.
# 13. Export a replay video. Confirm the parental gate blocks it first.
# 14. Confirm no stars, no score, no attempt counter, no timer anywhere.
# 15. Airplane mode. 16. Largest Dynamic Type — no clipping.
```

---

## 10. Acceptance Criteria (on top of `IMPLEMENTATION_STANDARD.md` §0 and `00_README.md` §10)

1. Builds and runs on device; 60fps min / 120fps ProMotion with the maximum expected body count, measured.
2. **First success under 30s from cold launch, no reading required**, proven by test.
3. **Every decomposed piece is convex, canonically wound, and slivers are dropped.** Union area matches input within tolerance. All proven by test — **this blocks the build.**
4. **Self-intersecting strokes yield valid geometry**, never degenerate bodies.
5. **Closure detection distinguishes a loop from a line**, producing a solid versus a thin chain.
6. **Simulation uses a fixed timestep** decoupled from frame rate, with identical outcomes across runs and forced frame-rate changes on one device. Proven by test.
7. **Recorded solutions store input, not output**, and the stored `didReachGoal` is immutable — a divergent replay never un-solves a level. Proven by test.
8. **Cross-device determinism is documented as not guaranteed**, with the design rationale for why that is harmless.
9. **The ink budget excludes the single-blob strategy** in every band, proven by test, including the closed-shape area charge.
10. **Undo refunds exactly the stroke cost**, proven by test.
11. **Failure has no negative consequence** — strokes are preserved, no attempt counter, no stars, no timer.
12. **Every authored level's reference solution reaches the goal within budget**, build-gated.
13. **Multiple distinct solutions per level are savable and replayable**, and the gallery is the show-someone artifact.
14. **Video export is behind the parental gate.**
15. **A tap-only pre-made shape library exists** as an alternative input for children who cannot draw freehand.
16. **Non-suitability for blind children is stated plainly** in parent-facing text.
17. **Progress is capability statements about invention** — no score, no stars, no creativity rating.
18. No streaks, daily obligations, lives, energy or retry gates. Reminders off by default.
19. Zero analytics/ad SDKs; fully offline; no account, no server. Parental gate on the grown-up view.
20. Age bands declared with per-band ink, goals, fixtures and draw-while-running.
21. No transfer claims; §2.4 note present.
22. `ENGINEERING.md` complete per §8.6.

---

## 11. Portfolio / Hiring Signal

- **A real computational-geometry pipeline.** Freehand stroke → simplified polyline → closure classification → self-intersection repair → convex decomposition, with three non-obvious correctness details: canonical winding (or objects fall through surfaces), merging triangles to reduce body count (because physics cost scales with bodies, not vertices), and dropping sliver triangles (because near-degenerate bodies generate huge impulses and produce the jitter that reads as a broken game). Each of those is a bug someone shipped before learning it.
- **Recognising that variable timestep is a correctness bug, not a performance detail.** Frame-rate-dependent simulation means the same input produces different results under load, which for a replay feature is fatal.
- **Handling non-determinism honestly instead of claiming it away.** Cross-device float reproducibility is not available on this stack. Rather than asserting determinism, the design records input rather than output, judges the outcome once authoritatively, makes it immutable, and documents that a replay may diverge visually. Knowing the limits of your platform and designing so the limit is harmless is a stronger answer than an unverifiable determinism claim.
- **Constraining the design space to create the thinking.** Unlimited ink collapses every level into one solution. The budget — charging for enclosed area as well as perimeter, so the cheap blob is expensive — is the mechanism that makes divergence happen, with a test to prove the degenerate strategy is excluded.
- **Build-gating hand-authored content.** Simulating every level's reference solution in CI catches the two failures hand-designed physics levels reliably have: unsolvable, or budget too tight for the intended answer.
- **An open-ended game with no wrong answers, and progress framed accordingly** — counting distinct solutions found rather than efficiency against an intended one.

**Resume-ready framing** (fill brackets with measured numbers — do not guess):
> Built an open-ended children's physics-drawing game with a freehand-stroke-to-rigid-body pipeline — RDP simplification, self-intersection repair, and convex decomposition with triangle merging that cut body count `[N]`× to hold `[X]`fps — plus fixed-timestep simulation and an input-recording replay model with immutable authoritative outcomes, making cross-device float divergence harmless rather than claiming determinism the engine cannot provide.

Interview questions this prepares you for: "how would you turn a freehand drawing into a physics object", "why does winding order matter", "why is variable timestep a bug", "physics isn't deterministic across devices — how do you build a replay feature", "how do you stop users finding one boring solution to every level".

---

# PART II — IMPLEMENTATION

> Everything below this line is **working, verified code**, plus a master plan for the
> part that is not written yet. Sections 12–17 are source that compiles and passes tests
> today. Section 18 is the build plan for the remaining UI layer. Section 19 is an honest
> ledger of what has been proven and what has not.

---

## 12. Three corrections to Part I, found by building it

Part I was written before the code. Building it surfaced three claims that are wrong.
They are corrected here rather than quietly worked around, because two of them change the
architecture.

### 12.1 `SKPhysicsWorld` cannot be stepped manually — §8.3's central code snippet does not compile

Part I §8.3 proposes:

```swift
world.step(forSeconds: stepSeconds)   // does not exist
```

`SKPhysicsWorld` exposes no public stepping API. It has `gravity`, `speed`,
`contactDelegate`, joint management and `enumerateBodies`, and it advances **exactly once
per rendered frame**, internally, with a step size SpriteKit chooses. `speed = 0` pauses
it; nothing advances it by a chosen amount. There is a private `stepForSeconds:` selector,
which is both an App Store rejection risk and not a thing to build a product on.

This is not a cosmetic problem. A fixed timestep is the load-bearing requirement of the
whole replay feature, and SpriteKit structurally cannot provide one.

**Correction:** the simulation is a self-contained deterministic 2D rigid-body engine
(§14.2), and **SpriteKit is the renderer only**. That is a bigger piece of work and it is
also the better answer: the simulation becomes pure Swift with no UIKit dependency, so it
runs headless in unit tests, in the level-authoring tool, and in the video exporter — which
is what makes the build gate in §8.5 possible at all. A build gate that simulated levels
through a different code path from the game would be proving something about code nobody
runs.

### 12.2 "Each convex piece is a physics body" is the wrong granularity

Part I §8.2 says each convex piece becomes a body, and that body count is the dominant
cost. The second half is right, which is why the first half is wrong.

Narrowphase cost tracks the number of **pairs tested**, and static bodies never collide
with each other. Making each piece its own static body creates a broadphase entry per
piece and an intra-stroke pair for every pair of pieces in the same stroke — all of which
are pointless.

**Correction:** one committed stroke becomes **one static body carrying every convex
piece** as separate colliders (§14.2, `SceneBuilder.addDrawnShape`). Merging still matters
for exactly the reason Part I gives, but what it reduces is collider count, not body count.
Measured: a drawn blob goes from 14 colliders to 1 (§19.2).

### 12.3 Penetration correction folded into the normal impulse injects energy

Not in Part I at all, and it is the bug that produced the first genuinely wrong-looking
behaviour: balls popping off corners and cup rims at speed. The cause is the standard
Baumgarte trick of adding a penetration bias term to the contact impulse. That bias is
real velocity, so a ball that overlaps by 10 units in one step receives a couple of hundred
units per second of free speed.

**Correction:** split impulse. Penetration is resolved with a separate *pseudo-velocity*
that is applied to position and then discarded, never added to real velocity
(`FixedStepWorld.stepOnce`, steps 5 and 6). Part I §8.2's concern about slivers causing
"jitter or launch" is adjacent to this and both fixes are needed: slivers are a geometry
problem, energy injection is a solver problem, and they produce similar-looking symptoms.

### 12.4 One thing Part I should have required and did not

`LevelIntegrityTests` in Part I §8.5 checks that every level's reference solution reaches
the goal. It does not check the opposite. During authoring, one level's fixtures fed the
ball into the cup **with no strokes at all** — it read fine in the level file and it was
not a level.

Added: `testNoLevelIsSolvableWithoutDrawing`. Also added
`testReferenceSolutionsAreRobustToBeingDrawnSlightlyDifferently`, because the first
automated search for reference solutions returned knife-edge flukes that pass CI the day
they are found and fail the first time a constant moves.

### 12.5 Deviations from Part I's stack table, and why

| Part I | Built | Reason |
|---|---|---|
| `SKPhysicsWorld` for simulation | Own fixed-step engine; SpriteKit renders | §12.1 |
| `UIViewRepresentable` for coalesced touches | `SKScene.touchesMoved(_:with:)` + `event.coalescedTouches(for:)` | `SKScene`'s touch handlers already receive the `UIEvent`, so the wrapper adds a layer without adding capability |
| `Resources/Levels` JSON | Kept as JSON, emitted by an authoring tool | Hand-writing the JSON is not viable; the tool that emits it is the same tool that proves the levels solvable (§17) |
| Audio from bundled files | Procedurally synthesised PCM | No asset files to ship or get wrong, and it keeps the repo self-contained |

---

## 13. `KidsGameCore` — the shared package

Built here as the subset DrawPhysics actually uses. `01_EchoPath.md` §4 owns the full
package; these files are API-compatible with it and are the ones this game imports. The two
that matter beyond this game are `CapabilityStatement` (there is no score type in the
package, by construction) and `ParentGate` (a real gate, not a button).

#### `KidsGameCore/Package.swift`

`macOS` is in the platforms list so the package's own tests run on the host with
`swift test`, which is how the difficulty controller gets exercised without a simulator.

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KidsGameCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KidsGameCore", targets: ["KidsGameCore"])
    ],
    targets: [
        .target(name: "KidsGameCore"),
        .testTarget(name: "KidsGameCoreTests", dependencies: ["KidsGameCore"])
    ]
)
```

#### `KidsGameCore/Sources/KidsGameCore/Progress/AgeBand.swift`

Band is data every game reads, not a label in a store listing. Child-facing names avoid age ranges; the age range is parent-facing only.

```swift
import Foundation

/// `00_README.md` §4. A game may span bands, but must state how content and difficulty
/// differ per band — so the band is data every game reads, not a label in a store listing.
public enum AgeBand: String, Codable, CaseIterable, Sendable, Identifiable {
    case early
    case middle
    case upper

    public var id: String { rawValue }

    /// Child-facing name. Deliberately not an age range: a 7-year-old choosing "Starting
    /// out" is making a choice about difficulty, not being told they are behind.
    public var childFacingName: String {
        switch self {
        case .early: return "Starting Out"
        case .middle: return "Getting Good"
        case .upper: return "Tricky"
        }
    }

    /// Parent-facing only, behind the gate.
    public var ageRange: String {
        switch self {
        case .early: return "4–6"
        case .middle: return "7–9"
        case .upper: return "10–13"
        }
    }
}
```

#### `KidsGameCore/Sources/KidsGameCore/Progress/CapabilityStatement.swift`

The structural enforcement of `00_README.md` §2.2. Failable initialiser, so a statement without sufficient evidence cannot be constructed at all — and there is no numeric score type anywhere in the package for a future contributor to reach for.

```swift
import Foundation

/// A true, checkable statement about what the child has actually done.
///
/// There is deliberately **no numeric score type in this package**, and no initialiser that
/// produces a statement without evidence. `00_README.md` §2.2 forbids skill scores; making
/// that structural rather than a policy means a future contributor cannot add one by
/// accident, only by deleting this comment and rewriting the type.
public struct CapabilityStatement: Equatable, Identifiable, Sendable {
    public let id: String
    /// What the child reads or hears. Always a fact: "You solved that level three
    /// different ways", never a judgement and never a rating.
    public let text: String
    public let evidence: Evidence

    public struct Evidence: Equatable, Sendable {
        /// What was counted, e.g. "distinctSolutions". Free-form because each game counts
        /// something different, and forcing a shared enum would push games into pretending
        /// they measure the same thing.
        public let kind: String
        public let observedCount: Int
        /// Below this the statement is not made. A single success is luck; a capability
        /// claim needs repetition.
        public let minimumRequired: Int

        public init(kind: String, observedCount: Int, minimumRequired: Int) {
            self.kind = kind
            self.observedCount = observedCount
            self.minimumRequired = minimumRequired
        }

        public var isSufficient: Bool { observedCount >= minimumRequired }
    }

    /// Fails rather than fudges. A statement with insufficient evidence is not a weaker
    /// statement, it is a false one.
    public init?(id: String, text: String, evidence: Evidence) {
        guard evidence.isSufficient else { return nil }
        self.id = id
        self.text = text
        self.evidence = evidence
    }
}
```

#### `KidsGameCore/Sources/KidsGameCore/Difficulty/SuccessRateController.swift`

The flow-channel controller from `01_EchoPath.md` §9.1, plus `DifficultyParameter` (continuous, with a child-controlled offset), `PlayerModel` for synthetic-player testing, and `SplitMix64` for seeded generation.

```swift
import Foundation

/// Continuous difficulty. Not a level number, so adjustment is invisible and never feels
/// like demotion (`00_README.md` §3.2).
public struct DifficultyParameter: Codable, Equatable, Sendable {
    public private(set) var value: Double
    /// Set by the child, not the controller. Always visible, and the honest admission that
    /// the controller will sometimes be wrong.
    public private(set) var childOffset: Double

    public init(value: Double = 0.35, childOffset: Double = 0) {
        self.value = value.clamped(to: 0...1)
        self.childOffset = childOffset.clamped(to: -0.25...0.25)
    }

    public var effective: Double { (value + childOffset).clamped(to: 0...1) }

    public mutating func setControllerValue(_ newValue: Double) {
        value = newValue.clamped(to: 0...1)
    }

    public mutating func makeHarder() { childOffset = (childOffset + 0.08).clamped(to: -0.25...0.25) }
    public mutating func makeEasier() { childOffset = (childOffset - 0.08).clamped(to: -0.25...0.25) }
}

/// The flow-channel controller shared by all twenty games (`01_EchoPath.md` §9.1).
public struct SuccessRateController: Sendable {
    public let targetLow = 0.75
    public let targetHigh = 0.85

    /// Asymmetric gains. Raising difficulty after success feels like recognition; dropping
    /// it after failure feels like being condescended to — so we rise readily and retreat
    /// gently.
    private let upGain = 0.060
    private let downGain = 0.025

    /// Never react to a handful of attempts. Small samples are noise, and a controller that
    /// twitches produces difficulty that feels random.
    private let minimumAttempts = 6
    private let windowSize = 12

    /// The rate must sit outside the band for two consecutive evaluations before we move.
    /// This is what prevents the oscillation a naive proportional controller produces.
    private let consecutiveDeviationsRequired = 2

    public init() {}

    public func next(difficulty d: Double,
                     window: [Bool],
                     consecutiveDeviations: Int) -> (difficulty: Double, deviations: Int) {
        guard window.count >= minimumAttempts else { return (d, 0) }

        let recent = window.suffix(windowSize)
        let rate = Double(recent.filter { $0 }.count) / Double(recent.count)

        if rate > targetHigh {
            let n = consecutiveDeviations + 1
            guard n >= consecutiveDeviationsRequired else { return (d, n) }
            // Scale the step by how far outside the band we are, so a child who is far
            // ahead catches up quickly instead of climbing one notch at a time.
            let excess = (rate - targetHigh) / (1.0 - targetHigh)
            return ((d + upGain * (0.5 + excess)).clamped(to: 0...1), 0)
        }

        if rate < targetLow {
            let n = consecutiveDeviations + 1
            guard n >= consecutiveDeviationsRequired else { return (d, n) }
            let deficit = (targetLow - rate) / targetLow
            return ((d - downGain * (0.5 + deficit)).clamped(to: 0...1), 0)
        }

        return (d, 0)      // inside the band — deliberately do nothing
    }
}

/// A synthetic child, for testing the controller. Real children are not available in CI,
/// and "it felt about right" is not a convergence proof.
public struct PlayerModel: Sendable {
    public var ability: Double
    public var sharpness: Double

    public init(ability: Double, sharpness: Double = 8) {
        self.ability = ability
        self.sharpness = sharpness
    }

    public func succeeds(atDifficulty d: Double, random: Double) -> Bool {
        let p = 1 / (1 + exp(-sharpness * (ability - d)))
        return random < p
    }
}

extension Double {
    public func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Deterministic PRNG (`00_README.md` §7, Seeding). `SystemRandomNumberGenerator` cannot be
/// seeded, so a "reproduce this puzzle" feature is impossible with it.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

#### `KidsGameCore/Sources/KidsGameCore/Instruct/Instructor.swift`

Speech is the primary instruction channel, not an accessibility extra — every game must be playable by a non-reader at every band. Deliberately does not force a voice: the child's system voice is the one they understand.

```swift
import Foundation
import AVFoundation
import Observation

/// Audio + icon instruction. Every game is playable without reading, at every age band
/// (`00_README.md` §6), so speech is not an accessibility extra — it is the primary channel.
@MainActor
@Observable
public final class Instructor {
    private let synthesizer = AVSpeechSynthesizer()

    public private(set) var isSpeaking = false
    /// Child-controlled. Off means icons and haptics carry everything, which some children
    /// prefer and some rooms require.
    public var isVoiceEnabled = true
    public var rate: Float = 0.44

    public init() {}

    public func say(_ text: String, interrupting: Bool = true) {
        guard isVoiceEnabled, !text.isEmpty else { return }
        if interrupting, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.1
        // Deliberately not forcing a specific voice: the child's chosen system voice is the
        // one they can understand, and overriding it breaks VoiceOver users' expectations.
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        isSpeaking = true
        synthesizer.speak(utterance)
        // AVSpeechSynthesizer's delegate is the accurate signal, but for a HUD flag the
        // approximation is enough and avoids an NSObject subclass for one boolean.
        Task { @MainActor in
            while synthesizer.isSpeaking {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            isSpeaking = false
        }
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

/// A no-reading-required instruction step: an SF Symbol, a spoken line, and nothing else.
public struct InstructionStep: Identifiable, Sendable {
    public let id: Int
    public let symbolName: String
    public let spoken: String

    public init(id: Int, symbolName: String, spoken: String) {
        self.id = id
        self.symbolName = symbolName
        self.spoken = spoken
    }
}

public struct InstructionScript: Sendable {
    public let steps: [InstructionStep]
    public init(steps: [InstructionStep]) { self.steps = steps }
}
```

#### `KidsGameCore/Sources/KidsGameCore/CoPlay/TurnManager.swift`

Same-device roles, announced aloud on hand-off so a pre-reader knows whose turn it is without being told. Roles carry a symbol as well as a colour.

```swift
import Foundation
import Observation

/// Same-device roles. No accounts, no network, no matchmaking — relatedness means the people
/// already in the child's life (`00_README.md` §3.1).
public enum PlayerRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case one
    case two

    public var id: String { rawValue }
    public var next: PlayerRole { self == .one ? .two : .one }

    /// Named by colour AND shape everywhere it is shown, never colour alone.
    public var displayName: String { self == .one ? "Blue" : "Orange" }
    public var symbolName: String { self == .one ? "circle.fill" : "triangle.fill" }
}

@MainActor
@Observable
public final class TurnManager {
    public private(set) var current: PlayerRole
    public private(set) var completedTurns: Int = 0
    public var isEnabled: Bool

    public init(startingWith role: PlayerRole = .one, isEnabled: Bool = false) {
        self.current = role
        self.isEnabled = isEnabled
    }

    /// Hand-off is explicit and announced, because a pre-reader needs to know whose turn it
    /// is without being told by the adult they are playing against.
    public func endTurn(announce: (String) -> Void) {
        guard isEnabled else { return }
        completedTurns += 1
        current = current.next
        announce("\(current.displayName)'s turn.")
    }

    public func reset(to role: PlayerRole = .one) {
        current = role
        completedTurns = 0
    }
}
```

#### `KidsGameCore/Sources/KidsGameCore/ParentGate/ParentGate.swift`

Two-digit multiplication with close distractors and a lockout. The constraint is narrower than it looks: it cannot be a reading task (some adults read poorly, some children read well) and it cannot be brute-forceable by tapping. Unlock never persists.

```swift
import Foundation
import SwiftUI
import Observation

/// A real gate, not a tappable "are you a grown-up?" button (`00_README.md` §5.4).
///
/// The design constraints are narrower than they look. It must be hard for a 6-year-old and
/// trivial for an adult, so it cannot be a reading task (some adults read poorly, some
/// children read well) and it cannot be a memory task. Two-digit multiplication sits in the
/// gap: mechanical for an adult, out of reach for the age range this app serves.
///
/// It must also not be brute-forceable by tapping, hence the cooldown.
@MainActor
@Observable
public final class ParentGate {

    public struct Challenge: Equatable, Sendable {
        public let left: Int
        public let right: Int
        public let options: [Int]
        public var answer: Int { left * right }
        public var spokenPrompt: String { "Grown-ups only. What is \(left) times \(right)?" }
    }

    public private(set) var challenge: Challenge
    public private(set) var failedAttempts = 0
    public private(set) var lockedUntil: Date?
    public private(set) var isUnlocked = false

    /// Three wrong answers buys a minute of nothing happening. Long enough to end a child's
    /// interest, short enough not to punish an adult who mis-tapped.
    private let attemptsBeforeLockout = 3
    private let lockoutSeconds: TimeInterval = 60

    private var generator: RandomNumberGenerator

    public init(seed: UInt64? = nil) {
        var rng: RandomNumberGenerator = seed.map { SplitMix64(seed: $0) } ?? SystemRandomNumberGenerator()
        self.challenge = Self.makeChallenge(using: &rng)
        self.generator = rng
    }

    public var isLockedOut: Bool {
        guard let lockedUntil else { return false }
        return Date() < lockedUntil
    }

    public var lockoutRemaining: TimeInterval {
        guard let lockedUntil else { return 0 }
        return max(0, lockedUntil.timeIntervalSinceNow)
    }

    @discardableResult
    public func submit(_ value: Int) -> Bool {
        guard !isLockedOut else { return false }
        if value == challenge.answer {
            isUnlocked = true
            failedAttempts = 0
            return true
        }
        failedAttempts += 1
        if failedAttempts >= attemptsBeforeLockout {
            lockedUntil = Date().addingTimeInterval(lockoutSeconds)
            failedAttempts = 0
        }
        challenge = Self.makeChallenge(using: &generator)
        return false
    }

    /// Unlock does not persist. Every visit to a gated screen is gated again, because a
    /// remembered unlock is a gate a child walks through later.
    public func relock() {
        isUnlocked = false
        challenge = Self.makeChallenge(using: &generator)
    }

    private static func makeChallenge(using rng: inout RandomNumberGenerator) -> Challenge {
        let left = Int.random(in: 12...19, using: &rng)
        let right = Int.random(in: 12...19, using: &rng)
        let answer = left * right
        // Distractors are close to the answer so guessing is not rewarded, and are unique so
        // there is never more than one correct button.
        var options = Set([answer])
        while options.count < 4 {
            let delta = Int.random(in: -30...30, using: &rng)
            let candidate = answer + delta
            if candidate > 0, candidate != answer { options.insert(candidate) }
        }
        return Challenge(left: left, right: right, options: options.shuffled(using: &rng))
    }
}

public struct ParentGateView: View {
    @State private var gate = ParentGate()
    @State private var shakeCount = 0
    private let onUnlocked: () -> Void
    private let onCancel: () -> Void

    public init(onUnlocked: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onUnlocked = onUnlocked
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 44))
                .accessibilityHidden(true)

            Text("Grown-ups only")
                .font(.title2.bold())

            Text("What is \(gate.challenge.left) × \(gate.challenge.right)?")
                .font(.title3)
                .accessibilityLabel("What is \(gate.challenge.left) times \(gate.challenge.right)?")

            if gate.isLockedOut {
                Text("Try again in \(Int(gate.lockoutRemaining.rounded())) seconds.")
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(gate.challenge.options, id: \.self) { option in
                        Button {
                            if gate.submit(option) {
                                onUnlocked()
                            } else {
                                shakeCount += 1
                            }
                        } label: {
                            Text("\(option)")
                                .font(.title3.monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .modifier(ShakeEffect(animatableData: CGFloat(shakeCount)))
            }

            Button("Not now", action: onCancel)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 8 * sin(animatableData * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
```

#### `KidsGameCore/Sources/KidsGameCore/ShowSomeone/ArtefactRecorder.swift`

A protocol, because the artefact differs per game. The only shared requirements: it can be listed, replayed, spoken aloud, and exported only through the system share sheet behind the gate.

```swift
import Foundation

/// The thing a child shows a person in the room (`00_README.md` §3.11 / §3.1).
///
/// A protocol rather than a concrete type because the artefact differs per game — a
/// recording, a tower, a drawing, a replay — and the only shared requirement is that it can
/// be listed, replayed, and optionally exported behind the parental gate.
public protocol Artefact: Identifiable, Sendable {
    var createdAt: Date { get }
    /// Spoken when the artefact is opened, so a non-reader can browse the gallery.
    var spokenSummary: String { get }
}

public protocol ArtefactRecorder {
    associatedtype Recorded: Artefact
    /// Called at the moment the child does the thing worth showing. Never on a timer, and
    /// never for a failure — an artefact is something they chose to make.
    func record() throws -> Recorded
}

/// Export is the one thing in the app that can leave it, so it is gated (`00_README.md` §5.4)
/// and it never uploads: the destination is the system share sheet, which puts the parent in
/// control of where it goes.
public enum ArtefactExportDestination: Sendable {
    case systemShareSheet
}
```

#### `KidsGameCore/Sources/KidsGameCore/AXGame/MotorAccommodations.swift`

Always-on settings rather than a mode. Also the colour-safe palette, where every token carries a symbol so nothing is communicated by hue alone.

```swift
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
```

---

## 14. `DrawPhysicsCore` — geometry, simulation, levels

These files live in the `DrawPhysics` app target (Part I §4's `Geometry/`, `Sim/` and
`Models/` folders). They import `KidsGameCore` and nothing else — no UIKit, no SpriteKit, no
SwiftUI. That is deliberate and it is what makes §8.5's build gate possible: the same code
runs in the game, in the tests, in the authoring tool, and in the video exporter.

### 14.1 Geometry — the stroke pipeline

#### `DrawPhysics/Geometry/Vec2.swift`

`Double` throughout, named explicitly. `CGFloat` is `Double` on 64-bit, but naming the type removes any chance of a narrowing sneaking into the simulation. `Size` and `Rect` are re-declared rather than imported from CoreGraphics so the core stays platform-free.

```swift
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
```

#### `DrawPhysics/Geometry/Polygon.swift`

Every predicate the rest of the pipeline stands on. `ensureCounterClockwise` is the one to read twice: edge normals are derived from vertex order, so a clockwise polygon has inward normals and objects fall straight through it.

```swift
import Foundation

/// Pure polygon predicates and measures. Everything downstream — closure detection,
/// self-intersection repair, convex decomposition, collision — is built on these five
/// or six functions, so they are kept small and individually testable.
public enum Polygon {

    // MARK: - Measures

    /// Positive for counter-clockwise winding, negative for clockwise.
    public static func signedArea(_ points: [Vec2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var total = 0.0
        var j = points.count - 1
        for i in 0..<points.count {
            total += (points[j].x * points[i].y) - (points[i].x * points[j].y)
            j = i
        }
        return total / 2
    }

    public static func area(_ points: [Vec2]) -> Double { abs(signedArea(points)) }

    /// Area-weighted centroid. Falls back to the vertex mean for degenerate input so
    /// callers never receive NaN.
    public static func centroid(_ points: [Vec2]) -> Vec2 {
        guard points.count >= 3 else {
            guard !points.isEmpty else { return .zero }
            let sum = points.reduce(Vec2.zero, +)
            return sum / Double(points.count)
        }
        let a = signedArea(points)
        guard abs(a) > 1e-9 else {
            let sum = points.reduce(Vec2.zero, +)
            return sum / Double(points.count)
        }
        var cx = 0.0, cy = 0.0
        var j = points.count - 1
        for i in 0..<points.count {
            let cross = points[j].cross(points[i])
            cx += (points[j].x + points[i].x) * cross
            cy += (points[j].y + points[i].y) * cross
            j = i
        }
        return Vec2(cx / (6 * a), cy / (6 * a))
    }

    /// Second moment of area about the centroid, per unit density. Needed so drawn
    /// and authored polygons rotate with a plausible inertia instead of a guess.
    public static func momentOfInertiaAboutCentroid(_ points: [Vec2]) -> Double {
        guard points.count >= 3 else { return 0 }
        let c = centroid(points)
        let p = points.map { $0 - c }
        var numerator = 0.0
        var denominator = 0.0
        var j = p.count - 1
        for i in 0..<p.count {
            let cross = abs(p[j].cross(p[i]))
            numerator += cross * (p[j].dot(p[j]) + p[j].dot(p[i]) + p[i].dot(p[i]))
            denominator += cross
            j = i
        }
        guard denominator > 1e-9 else { return 0 }
        // (1/12) * sum(cross * (a.a + a.b + b.b)) / (sum(cross)/2)  -> per unit area
        return (numerator / 12) / (denominator / 2)
    }

    public static func polylineLength(_ points: [Vec2]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count { total += points[i].distance(to: points[i - 1]) }
        return total
    }

    public static func perimeter(_ points: [Vec2]) -> Double {
        guard points.count >= 3 else { return polylineLength(points) }
        return polylineLength(points) + points[points.count - 1].distance(to: points[0])
    }

    public static func boundingBox(_ points: [Vec2]) -> Rect {
        guard let first = points.first else { return Rect(x: 0, y: 0, width: 0, height: 0) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Winding

    public static func isCounterClockwise(_ points: [Vec2]) -> Bool {
        signedArea(points) > 0
    }

    /// Canonicalise winding. This is not cosmetic: edge normals are derived from
    /// vertex order, so a clockwise polygon produces inward-facing normals and
    /// objects fall straight through it.
    public static func ensureCounterClockwise(_ points: [Vec2]) -> [Vec2] {
        isCounterClockwise(points) ? points : points.reversed()
    }

    // MARK: - Convexity

    /// True when every turn has the same sign. Collinear vertices (cross == 0) are
    /// tolerated because simplification legitimately produces them.
    public static func isConvex(_ points: [Vec2], tolerance: Double = 1e-7) -> Bool {
        guard points.count >= 3 else { return false }
        var sawPositive = false
        var sawNegative = false
        let n = points.count
        for i in 0..<n {
            let a = points[i]
            let b = points[(i + 1) % n]
            let c = points[(i + 2) % n]
            let cross = (b - a).cross(c - b)
            if cross > tolerance { sawPositive = true }
            if cross < -tolerance { sawNegative = true }
            if sawPositive && sawNegative { return false }
        }
        return true
    }

    // MARK: - Containment

    public static func contains(_ point: Vec2, polygon: [Vec2]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let t = (point.y - a.y) / (b.y - a.y)
                if point.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Strict containment used by ear clipping: a vertex sitting exactly on a
    /// triangle edge must not veto the ear, or clipping can stall.
    public static func triangleContains(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ c: Vec2,
                                        tolerance: Double = 1e-9) -> Bool {
        let d1 = (b - a).cross(p - a)
        let d2 = (c - b).cross(p - b)
        let d3 = (a - c).cross(p - c)
        let allPositive = d1 > tolerance && d2 > tolerance && d3 > tolerance
        let allNegative = d1 < -tolerance && d2 < -tolerance && d3 < -tolerance
        return allPositive || allNegative
    }

    // MARK: - Intersection

    /// Proper crossing point of two open segments, or nil. Endpoint touches are
    /// deliberately excluded (`epsilon` keeps `t`/`u` strictly interior) because
    /// adjacent polyline segments always share an endpoint and would otherwise
    /// register as self-intersections everywhere.
    public static func segmentIntersection(_ a: Vec2, _ b: Vec2,
                                           _ c: Vec2, _ d: Vec2,
                                           epsilon: Double = 1e-9) -> Vec2? {
        let r = b - a
        let s = d - c
        let denominator = r.cross(s)
        guard abs(denominator) > 1e-12 else { return nil }   // parallel or collinear
        let t = (c - a).cross(s) / denominator
        let u = (c - a).cross(r) / denominator
        guard t > epsilon, t < 1 - epsilon, u > epsilon, u < 1 - epsilon else { return nil }
        return a + r * t
    }

    /// A polygon is simple when no pair of non-adjacent edges crosses.
    public static func isSimple(_ points: [Vec2]) -> Bool {
        firstSelfIntersection(points) == nil
    }

    public struct SelfIntersection: Equatable, Sendable {
        public let firstEdge: Int
        public let secondEdge: Int
        public let point: Vec2
    }

    public static func firstSelfIntersection(_ points: [Vec2]) -> SelfIntersection? {
        allSelfIntersections(points, stopAtFirst: true).first
    }

    public static func allSelfIntersections(_ points: [Vec2],
                                            stopAtFirst: Bool = false) -> [SelfIntersection] {
        let n = points.count
        guard n >= 4 else { return [] }
        var found: [SelfIntersection] = []
        for i in 0..<n {
            let a = points[i], b = points[(i + 1) % n]
            // j starts two edges along; the final wrap-around pair is adjacent to i == 0.
            var j = i + 2
            while j < n {
                if i == 0 && j == n - 1 { j += 1; continue }
                let c = points[j], d = points[(j + 1) % n]
                if let p = segmentIntersection(a, b, c, d) {
                    found.append(SelfIntersection(firstEdge: i, secondEdge: j, point: p))
                    if stopAtFirst { return found }
                }
                j += 1
            }
        }
        return found
    }

    // MARK: - Cleaning

    /// Drop points closer than `minSpacing` to the previously kept point. Finger
    /// input delivers dense clusters when the finger pauses; those clusters create
    /// zero-length edges that break every predicate above.
    public static func dedupe(_ points: [Vec2], minSpacing: Double) -> [Vec2] {
        guard let first = points.first else { return [] }
        var result = [first]
        for p in points.dropFirst() where p.distance(to: result[result.count - 1]) >= minSpacing {
            result.append(p)
        }
        return result
    }

    /// Remove vertices that lie on the straight line between their neighbours.
    /// Collinear vertices are legal but waste narrowphase work on every step.
    public static func removeCollinear(_ points: [Vec2], tolerance: Double = 1e-6) -> [Vec2] {
        guard points.count > 3 else { return points }
        var result: [Vec2] = []
        let n = points.count
        for i in 0..<n {
            let prev = points[(i + n - 1) % n]
            let cur = points[i]
            let next = points[(i + 1) % n]
            let cross = (cur - prev).cross(next - cur)
            let scale = max((cur - prev).length * (next - cur).length, 1e-12)
            if abs(cross) / scale > tolerance { result.append(cur) }
        }
        return result.count >= 3 ? result : points
    }
}
```

#### `DrawPhysics/Geometry/DrawnShape.swift`

`DrawnShape` keeps both what the child sees and what the simulation receives. `RecordedStroke` is the replay artefact — input, plus the step it was committed on.

```swift
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
```

#### `DrawPhysics/Geometry/StrokeSimplifier.swift`

Stages 1–3 of §8.2. Three things worth noting: RDP is iterative because a child's spiral makes recursion depth O(n); ring simplification splits at the two most distant vertices first, or a loop collapses into a line; and self-intersection repair takes the largest simple sub-loop, with the figure-of-eight limitation stated in the doc comment rather than hidden.

```swift
import Foundation

/// Stage 1-3 of the stroke pipeline (§8.2): simplify, classify closure, repair
/// self-intersection. Stage 4 (decomposition) lives in `ConvexDecomposer`.
public struct StrokeSimplifier: Sendable {

    public struct Configuration: Sendable {
        /// Ramer-Douglas-Peucker tolerance for closed shapes, in scene units.
        /// Tuned by eye on device: below ~2 the vertex count stays high enough to
        /// slow decomposition; above ~5 a child's deliberate curve visibly squares off.
        public var closedTolerance: Double = 3.0
        /// Open strokes can be simplified harder — a barrier reads as a line, and
        /// every extra vertex is another quad in the chain.
        public var openTolerance: Double = 5.0
        /// Endpoints within this distance mean "the child meant to close the loop".
        public var closureDistance: Double = 28.0
        public var minimumSpacing: Double = 2.0
        /// Hard cap on vertices after simplification. Decomposition is O(n^2)-ish and
        /// a 400-vertex blob would stall the frame it is committed on.
        public var maximumVertices: Int = 40
        /// A closed candidate must enclose at least this much area, otherwise it is a
        /// scribble that happens to end where it started and is better as a chain.
        public var minimumClosedArea: Double = 250.0
        public var repairIterations: Int = 8
        public var chainThickness: Double = 11.0

        public init() {}
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Entry point

    /// Full classification + repair. Returns nil only for input that cannot become
    /// anything meaningful (a tap, or a stroke shorter than the minimum).
    /// `minimumStrokeLength` is enforced by `InkMeter`, not here.
    public func process(rawPoints: [Vec2]) -> ProcessedStroke? {
        let cleaned = Polygon.dedupe(rawPoints, minSpacing: configuration.minimumSpacing)
        guard cleaned.count >= 2 else { return nil }

        if let closed = closedCandidate(from: cleaned) {
            return closed
        }

        let simplified = Self.simplify(cleaned, tolerance: configuration.openTolerance)
        guard simplified.count >= 2 else { return nil }
        return ProcessedStroke(simplifiedPoints: simplified,
                               isClosed: false,
                               enclosedArea: 0,
                               inkLength: Polygon.polylineLength(simplified))
    }

    public struct ProcessedStroke: Equatable, Sendable {
        public var simplifiedPoints: [Vec2]
        public var isClosed: Bool
        public var enclosedArea: Double
        public var inkLength: Double
    }

    // MARK: - Stage 2: closure detection

    private func closedCandidate(from cleaned: [Vec2]) -> ProcessedStroke? {
        guard cleaned.count >= 4 else { return nil }
        let span = cleaned[0].distance(to: cleaned[cleaned.count - 1])
        guard span <= configuration.closureDistance else { return nil }
        // A short there-and-back stroke also has near-coincident endpoints. Require the
        // path to be meaningfully longer than the gap it closes.
        guard Polygon.polylineLength(cleaned) > configuration.closureDistance * 2 else { return nil }

        var ring = cleaned
        // The trailing point is within closureDistance of the leading one; keeping both
        // gives a near-zero-length closing edge, which every predicate hates.
        if ring.count >= 4, ring[0].distance(to: ring[ring.count - 1]) < configuration.minimumSpacing * 2 {
            ring.removeLast()
        }
        guard ring.count >= 3 else { return nil }

        var simplified = Self.simplifyRing(ring, tolerance: configuration.closedTolerance)
        guard simplified.count >= 3 else { return nil }

        simplified = Self.repairSelfIntersections(simplified,
                                                 iterations: configuration.repairIterations)
        guard simplified.count >= 3 else { return nil }

        simplified = Self.enforceVertexCap(simplified, cap: configuration.maximumVertices)
        simplified = Polygon.removeCollinear(simplified)
        simplified = Polygon.ensureCounterClockwise(simplified)

        let enclosed = Polygon.area(simplified)
        guard enclosed >= configuration.minimumClosedArea else { return nil }

        return ProcessedStroke(simplifiedPoints: simplified,
                               isClosed: true,
                               enclosedArea: enclosed,
                               inkLength: Polygon.perimeter(simplified))
    }

    // MARK: - Stage 1: Ramer-Douglas-Peucker

    /// Iterative RDP. Recursion depth is O(n) in the worst case (a monotone spiral,
    /// which children draw constantly), so the stack is explicit.
    public static func simplify(_ points: [Vec2], tolerance: Double) -> [Vec2] {
        guard points.count > 2, tolerance > 0 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var worstIndex = -1
            var worstDistance = 0.0
            for i in (start + 1)..<end {
                let d = perpendicularDistance(points[i], from: points[start], to: points[end])
                if d > worstDistance {
                    worstDistance = d
                    worstIndex = i
                }
            }
            if worstDistance > tolerance, worstIndex > 0 {
                keep[worstIndex] = true
                stack.append((start, worstIndex))
                stack.append((worstIndex, end))
            }
        }
        return points.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    /// RDP on a closed ring. Splitting at the two most distant vertices first stops
    /// the algorithm from collapsing a loop into a line, which is what happens if you
    /// naively run open-path RDP from index 0 to index 0.
    public static func simplifyRing(_ ring: [Vec2], tolerance: Double) -> [Vec2] {
        guard ring.count > 4 else { return ring }
        var farthestIndex = 0
        var farthestDistance = 0.0
        for i in 1..<ring.count {
            let d = ring[i].distance(to: ring[0])
            if d > farthestDistance {
                farthestDistance = d
                farthestIndex = i
            }
        }
        guard farthestIndex > 1, farthestIndex < ring.count - 1 else {
            return simplify(ring, tolerance: tolerance)
        }
        let firstHalf = simplify(Array(ring[0...farthestIndex]), tolerance: tolerance)
        let secondHalf = simplify(Array(ring[farthestIndex..<ring.count]) + [ring[0]],
                                  tolerance: tolerance)
        // Drop the duplicated join vertex and the duplicated wrap vertex.
        var merged = firstHalf
        if secondHalf.count > 2 {
            merged.append(contentsOf: secondHalf.dropFirst().dropLast())
        }
        return merged
    }

    public static func perpendicularDistance(_ p: Vec2, from a: Vec2, to b: Vec2) -> Double {
        let ab = b - a
        let lengthSquared = ab.lengthSquared
        guard lengthSquared > 1e-12 else { return p.distance(to: a) }
        let t = ((p - a).dot(ab) / lengthSquared).clamped(to: 0...1)
        return p.distance(to: a + ab * t)
    }

    private static func enforceVertexCap(_ points: [Vec2], cap: Int) -> [Vec2] {
        guard points.count > cap else { return points }
        var tolerance = 4.0
        var result = points
        var guardCounter = 0
        while result.count > cap && guardCounter < 12 {
            result = simplifyRing(points, tolerance: tolerance)
            tolerance *= 1.6
            guardCounter += 1
        }
        return result
    }

    // MARK: - Stage 3: self-intersection repair

    /// A self-intersecting polygon has no well-defined interior, so decomposition is
    /// meaningless on it. General repair (planar subdivision, then boolean union) is a
    /// much larger problem than this game needs.
    ///
    /// Instead: take the largest simple sub-loop. For a child's accidental crossing —
    /// a loop closed slightly past its own start, a figure-of-eight where one lobe is
    /// clearly the intended shape — the biggest simple loop is nearly always what they
    /// meant. The limitation is documented in `ENGINEERING.md`: a deliberate
    /// figure-of-eight loses its smaller lobe.
    public static func repairSelfIntersections(_ polygon: [Vec2], iterations: Int) -> [Vec2] {
        var current = polygon
        for _ in 0..<max(iterations, 1) {
            let intersections = Polygon.allSelfIntersections(current)
            if intersections.isEmpty { return current }
            guard let best = largestSubloop(of: current, using: intersections) else {
                return current
            }
            // No progress possible: bail out with what we have rather than spin.
            if best.count >= current.count { return best }
            current = best
        }
        return current
    }

    /// For a crossing between edge `i` and edge `j`, the vertices strictly between
    /// them plus the crossing point form a closed loop. Every crossing yields one
    /// such candidate; the largest by area wins.
    private static func largestSubloop(of polygon: [Vec2],
                                       using intersections: [Polygon.SelfIntersection]) -> [Vec2]? {
        var bestLoop: [Vec2]?
        var bestArea = 0.0
        for hit in intersections {
            let lower = hit.firstEdge + 1
            let upper = hit.secondEdge
            guard lower <= upper else { continue }
            var loop = [hit.point]
            for index in lower...upper { loop.append(polygon[index]) }
            guard loop.count >= 3 else { continue }
            let a = Polygon.area(loop)
            if a > bestArea {
                bestArea = a
                bestLoop = loop
            }
            // The complement is also a candidate: everything outside the crossing.
            var complement = [hit.point]
            var index = (hit.secondEdge + 1) % polygon.count
            var stepGuard = 0
            while index != lower && stepGuard <= polygon.count {
                complement.append(polygon[index])
                index = (index + 1) % polygon.count
                stepGuard += 1
            }
            if complement.count >= 3 {
                let ca = Polygon.area(complement)
                if ca > bestArea {
                    bestArea = ca
                    bestLoop = complement
                }
            }
        }
        return bestLoop
    }

    // MARK: - Open strokes become a thin chain

    /// One convex quad per simplified segment, each extended half a thickness along
    /// its own direction so the joints overlap instead of leaving a notch a ball can
    /// catch on. All quads end up in a single static body.
    public static func chainPieces(_ points: [Vec2], thickness: Double) -> [[Vec2]] {
        guard points.count >= 2, thickness > 0 else { return [] }
        let half = thickness / 2
        var pieces: [[Vec2]] = []
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let direction = (b - a).normalized()
            guard direction.lengthSquared > 0 else { continue }
            let normal = direction.perpendicularCCW
            let start = a - direction * half
            let end = b + direction * half
            let quad = [
                start + normal * half,
                end + normal * half,
                end - normal * half,
                start - normal * half
            ]
            pieces.append(Polygon.ensureCounterClockwise(quad))
        }
        return pieces
    }
}
```

#### `DrawPhysics/Geometry/ConvexDecomposer.swift`

Stage 4. Ear clipping with a forced-clip fallback so the function is total on real finger input, then Hertel-Mehlhorn-style merging, then sliver removal — with a guarantee that a shape is never silently deleted entirely.

```swift
import Foundation

/// Stage 4 of the stroke pipeline (§8.2): simple polygon -> convex pieces.
public struct ConvexDecomposer: Sendable {

    /// Sliver triangles cause physics instability. A near-zero-area body has a
    /// near-zero effective mass along one axis, so the solver answers a small overlap
    /// with an enormous impulse — the object jitters, then launches. Dropping slivers
    /// changes the silhouette imperceptibly and removes a whole class of "the game is
    /// broken" behaviour.
    public let minimumPieceArea: Double

    /// Convexity tolerance for accepting a merge. Slightly loose on purpose: after
    /// simplification, vertices that are geometrically collinear are rarely exactly
    /// collinear in floating point, and a strict test refuses almost every merge.
    public let mergeConvexityTolerance: Double

    public init(minimumPieceArea: Double = 4.0, mergeConvexityTolerance: Double = 1e-4) {
        self.minimumPieceArea = minimumPieceArea
        self.mergeConvexityTolerance = mergeConvexityTolerance
    }

    /// Decompose a simple polygon into convex, counter-clockwise pieces.
    ///
    /// Ear clipping alone is trivially correct but produces one triangle per
    /// interior vertex, and narrowphase cost scales with piece count — a 40-triangle
    /// blob measurably drops the frame rate. So: triangulate, then merge adjacent
    /// triangles while the union stays convex (Hertel-Mehlhorn style), trading a
    /// little optimality for far fewer pieces.
    public func decompose(_ polygon: [Vec2]) -> [[Vec2]] {
        let cleaned = Polygon.removeCollinear(Polygon.ensureCounterClockwise(polygon))
        guard cleaned.count >= 3 else { return [] }
        guard Polygon.area(cleaned) > minimumPieceArea else { return [] }

        if Polygon.isConvex(cleaned) {
            return [cleaned]
        }

        let triangles = Self.earClip(cleaned)
        guard !triangles.isEmpty else { return [] }

        let merged = mergeWhileConvex(triangles)
        let kept = merged.filter { Polygon.area($0) > minimumPieceArea }

        // Never return nothing. A shape small enough that every piece is a sliver is
        // still a shape the child drew, and silently deleting it looks like a bug.
        if kept.isEmpty {
            if let largest = merged.max(by: { Polygon.area($0) < Polygon.area($1) }) {
                return [largest]
            }
            return []
        }
        return kept.map { Polygon.ensureCounterClockwise($0) }
    }

    // MARK: - Triangulation

    /// Ear clipping with a guaranteed-termination fallback. Real finger input produces
    /// near-degenerate configurations where no strict ear exists in floating point; a
    /// pure "scan until an ear is found" loop hangs on those. When a full pass finds no
    /// ear we force-clip the sharpest convex vertex, which costs a little quality and
    /// makes the function total.
    public static func earClip(_ polygon: [Vec2]) -> [[Vec2]] {
        var indices = Array(0..<polygon.count)
        var triangles: [[Vec2]] = []
        var safety = polygon.count * polygon.count + 16

        while indices.count > 3 && safety > 0 {
            safety -= 1
            var clipped = false

            for offset in 0..<indices.count {
                let previous = indices[(offset + indices.count - 1) % indices.count]
                let current = indices[offset]
                let next = indices[(offset + 1) % indices.count]
                let a = polygon[previous], b = polygon[current], c = polygon[next]

                // Convex vertex in a CCW polygon means a positive turn.
                guard (b - a).cross(c - b) > 1e-9 else { continue }
                guard Polygon.area([a, b, c]) > 1e-9 else { continue }

                var containsOther = false
                for candidate in indices where candidate != previous && candidate != current && candidate != next {
                    if Polygon.triangleContains(polygon[candidate], a, b, c) {
                        containsOther = true
                        break
                    }
                }
                guard !containsOther else { continue }

                triangles.append([a, b, c])
                indices.remove(at: offset)
                clipped = true
                break
            }

            if !clipped {
                guard let forced = sharpestConvexOffset(indices, polygon) else { break }
                let previous = indices[(forced + indices.count - 1) % indices.count]
                let current = indices[forced]
                let next = indices[(forced + 1) % indices.count]
                triangles.append([polygon[previous], polygon[current], polygon[next]])
                indices.remove(at: forced)
            }
        }

        if indices.count == 3 {
            triangles.append([polygon[indices[0]], polygon[indices[1]], polygon[indices[2]]])
        }
        return triangles.filter { Polygon.area($0) > 1e-9 }
                        .map { Polygon.ensureCounterClockwise($0) }
    }

    private static func sharpestConvexOffset(_ indices: [Int], _ polygon: [Vec2]) -> Int? {
        var bestOffset: Int?
        var bestCross = -Double.greatestFiniteMagnitude
        for offset in 0..<indices.count {
            let previous = indices[(offset + indices.count - 1) % indices.count]
            let current = indices[offset]
            let next = indices[(offset + 1) % indices.count]
            let cross = (polygon[current] - polygon[previous]).cross(polygon[next] - polygon[current])
            if cross > bestCross {
                bestCross = cross
                bestOffset = offset
            }
        }
        return bestOffset
    }

    // MARK: - Merging

    /// Repeatedly merge two pieces that share an edge when the union is still convex.
    /// Restarting after each successful merge is O(n^3) in the worst case, but n is the
    /// triangle count of one drawn shape (<= ~40 after the vertex cap), so this runs in
    /// well under a millisecond and only on stroke commit, never per frame.
    public func mergeWhileConvex(_ pieces: [[Vec2]]) -> [[Vec2]] {
        var current = pieces
        var didMerge = true
        var safety = 512

        while didMerge && safety > 0 {
            safety -= 1
            didMerge = false
            outer: for i in 0..<current.count {
                for j in (i + 1)..<current.count {
                    guard let union = Self.mergeAcrossSharedEdge(current[i], current[j]) else { continue }
                    guard Polygon.isConvex(union, tolerance: mergeConvexityTolerance) else { continue }
                    let expected = Polygon.area(current[i]) + Polygon.area(current[j])
                    guard abs(Polygon.area(union) - expected) <= max(1e-6, expected * 1e-6) else { continue }
                    current.remove(at: j)
                    current[i] = union
                    didMerge = true
                    break outer
                }
            }
        }
        return current
    }

    /// Join two counter-clockwise polygons across a shared edge traversed in opposite
    /// directions. Walk A from the shared edge's end all the way round to its start,
    /// then walk B's remaining vertices. Winding is preserved by construction.
    public static func mergeAcrossSharedEdge(_ a: [Vec2], _ b: [Vec2],
                                            tolerance: Double = 1e-7) -> [Vec2]? {
        guard a.count >= 3, b.count >= 3 else { return nil }
        for i in 0..<a.count {
            let u = a[i]
            let v = a[(i + 1) % a.count]
            for j in 0..<b.count {
                let s = b[j]
                let t = b[(j + 1) % b.count]
                // Shared edge appears reversed in the neighbour.
                guard s.isApproximatelyEqual(to: v, tolerance: tolerance),
                      t.isApproximatelyEqual(to: u, tolerance: tolerance) else { continue }

                var union: [Vec2] = []
                union.reserveCapacity(a.count + b.count - 2)
                for k in 0..<a.count { union.append(a[(i + 1 + k) % a.count]) }   // v ... u
                for k in 0..<(b.count - 2) { union.append(b[(j + 2 + k) % b.count]) }
                return Polygon.removeCollinear(union)
            }
        }
        return nil
    }
}
```

#### `DrawPhysics/Geometry/InkMeter.swift`

The mechanism that makes this a divergent-thinking game instead of a draw-a-funnel game. `InkBudget` stores individual charges rather than a running total, so undo refunds the exact amount and 200 draw/undo cycles leak nothing.

```swift
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
```

#### `DrawPhysics/Geometry/StrokePipeline.swift`

The whole pipeline behind one call, returning a typed rejection the HUD can explain. Shape ids come from the caller so the same stroke sequence always produces the same ids, which replay depends on.

```swift
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
```

### 14.2 Simulation — the fixed-step engine

Written rather than borrowed, for the reason in §12.1. Roughly 700 lines: SAT collision with
face clipping, circle/polygon and circle/circle paths, a sequential-impulse solver with
split-impulse position correction, one revolute joint, and closed-form kinematic paths.

#### `DrawPhysics/Sim/RigidBody.swift`

The ball is a real circle, not a polygon approximation: a 20-gon rolls with a faint bump every 18 degrees, and "the ball rolls down the ramp you drew" is the core sensation. `KinematicPath` is evaluated from the integer step index, never wall-clock time.

```swift
import Foundation

/// One convex collider in body-local coordinates.
///
/// The ball is a real circle rather than a polygon approximation. A 20-gon rolls with
/// a faint but perceptible bump every 18 degrees, and "the ball rolls down the ramp you
/// drew" is the core sensation of the game.
public struct Shape: Sendable {
    public enum Kind: Sendable {
        case circle(center: Vec2, radius: Double)
        /// Counter-clockwise, convex, local space.
        case polygon(vertices: [Vec2])
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public static func circle(center: Vec2 = .zero, radius: Double) -> Shape {
        Shape(kind: .circle(center: center, radius: radius))
    }

    public static func polygon(_ vertices: [Vec2]) -> Shape {
        Shape(kind: .polygon(vertices: Polygon.ensureCounterClockwise(vertices)))
    }

    public var area: Double {
        switch kind {
        case let .circle(_, radius): return .pi * radius * radius
        case let .polygon(vertices): return Polygon.area(vertices)
        }
    }

    /// Second moment about the body origin, per unit density.
    public var momentAboutOrigin: Double {
        switch kind {
        case let .circle(center, radius):
            let own = 0.5 * (.pi * radius * radius) * radius * radius
            return own + (.pi * radius * radius) * center.lengthSquared
        case let .polygon(vertices):
            let a = Polygon.area(vertices)
            let c = Polygon.centroid(vertices)
            // Parallel axis theorem, per unit density: I_origin = A * (I_c/A + |c|^2).
            return a * (Polygon.momentOfInertiaAboutCentroid(vertices) + c.lengthSquared)
        }
    }

    public func localBounds() -> Rect {
        switch kind {
        case let .circle(center, radius):
            return Rect(x: center.x - radius, y: center.y - radius,
                        width: radius * 2, height: radius * 2)
        case let .polygon(vertices):
            return Polygon.boundingBox(vertices)
        }
    }
}

public enum BodyMotion: Sendable {
    /// Never moves. Walls, the cup, everything the child draws.
    case `static`
    /// Moves on a schedule the simulation dictates, unaffected by collisions.
    case kinematic
    case dynamic
}

/// Semantic role, used by the goal judge and the renderer. A string tag rather than an
/// enum because levels are authored data and must be able to name their own bodies.
public struct BodyTag: Equatable, Hashable, Sendable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public static let wall = BodyTag("wall")
    public static let floor = BodyTag("floor")
}

public final class RigidBody {
    public let id: Int
    public var tag: BodyTag
    public var shapes: [Shape]
    public var motion: BodyMotion

    public var position: Vec2
    public var rotation: Double
    public var velocity: Vec2
    public var angularVelocity: Double

    /// Split-impulse scratch. Penetration is pushed out with a SEPARATE velocity that is
    /// applied to position and then thrown away, never added to real velocity.
    ///
    /// The alternative — folding the penetration bias into the normal impulse — literally
    /// injects energy: a ball landing hard enough to overlap by 10 units gets a couple of
    /// hundred units per second of free upward speed and visibly pops off the surface. That
    /// is the "why did the ball launch" bug, and it is a solver choice, not a tuning problem.
    public var pseudoVelocity: Vec2 = .zero
    public var pseudoAngularVelocity: Double = 0

    public var invMass: Double
    public var invInertia: Double

    public var restitution: Double
    public var friction: Double
    public var linearDamping: Double
    public var angularDamping: Double

    /// Kinematic bodies follow this. Given the fixed step index, position is a pure
    /// function of time — which keeps moving platforms exactly as reproducible as
    /// everything else.
    public var kinematicPath: KinematicPath?

    public init(id: Int,
                tag: BodyTag,
                shapes: [Shape],
                motion: BodyMotion,
                position: Vec2,
                rotation: Double = 0,
                density: Double = 1.0,
                restitution: Double = 0.15,
                friction: Double = 0.55,
                linearDamping: Double = 0.06,
                angularDamping: Double = 0.10) {
        self.id = id
        self.tag = tag
        self.shapes = shapes
        self.motion = motion
        self.position = position
        self.rotation = rotation
        self.velocity = .zero
        self.angularVelocity = 0
        self.restitution = restitution
        self.friction = friction
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.kinematicPath = nil

        switch motion {
        case .static, .kinematic:
            self.invMass = 0
            self.invInertia = 0
        case .dynamic:
            let area = shapes.reduce(0.0) { $0 + $1.area }
            let mass = max(area * density, 1e-6)
            let moment = shapes.reduce(0.0) { $0 + $1.momentAboutOrigin } * density
            self.invMass = 1 / mass
            self.invInertia = moment > 1e-9 ? 1 / moment : 0
        }
    }

    public var isMovable: Bool {
        if case .dynamic = motion { return true }
        return false
    }

    public func toWorld(_ local: Vec2) -> Vec2 {
        position + local.rotated(by: rotation)
    }

    public func worldVertices(of shape: Shape) -> [Vec2] {
        guard case let .polygon(vertices) = shape.kind else { return [] }
        return vertices.map { toWorld($0) }
    }

    public func worldBounds() -> Rect {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for shape in shapes {
            switch shape.kind {
            case let .circle(center, radius):
                let c = toWorld(center)
                minX = min(minX, c.x - radius); maxX = max(maxX, c.x + radius)
                minY = min(minY, c.y - radius); maxY = max(maxY, c.y + radius)
            case let .polygon(vertices):
                for local in vertices {
                    let w = toWorld(local)
                    minX = min(minX, w.x); maxX = max(maxX, w.x)
                    minY = min(minY, w.y); maxY = max(maxY, w.y)
                }
            }
        }
        guard minX <= maxX else { return Rect(x: position.x, y: position.y, width: 0, height: 0) }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func applyImpulse(_ impulse: Vec2, at contact: Vec2) {
        guard isMovable else { return }
        velocity += impulse * invMass
        angularVelocity += (contact - position).cross(impulse) * invInertia
    }

    public func velocity(at worldPoint: Vec2) -> Vec2 {
        velocity + (worldPoint - position).perpendicularCCW * angularVelocity
    }

    public func pseudoVelocity(at worldPoint: Vec2) -> Vec2 {
        pseudoVelocity + (worldPoint - position).perpendicularCCW * pseudoAngularVelocity
    }
}

/// A closed-form kinematic path. Evaluated from the integer step index, never from
/// wall-clock time, so a moving platform is in exactly the same place on step 900 of
/// every run.
public struct KinematicPath: Sendable {
    public var origin: Vec2
    public var travel: Vec2
    public var periodSteps: Int

    public init(origin: Vec2, travel: Vec2, periodSteps: Int) {
        self.origin = origin
        self.travel = travel
        self.periodSteps = max(periodSteps, 1)
    }

    public func position(atStep step: Int) -> Vec2 {
        let phase = Double(step % periodSteps) / Double(periodSteps)
        // Triangle wave: linear out, linear back. Constant speed reads as a machine,
        // which is easier for a child to plan around than a sinusoid.
        let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
        return origin + travel * t
    }
}
```

#### `DrawPhysics/Sim/Collision.swift`

Three narrowphase paths. The polygon/polygon case picks a reference face, finds the most anti-parallel incident face, and clips it to the reference side planes to produce up to two contact points — which is what lets a box rest flat instead of pivoting on one corner.

```swift
import Foundation

/// One contact point with its own penetration depth. Two points for a resting
/// face-on-face pair, one for a circle or a corner.
public struct ContactPoint: Sendable {
    public var position: Vec2
    public var penetration: Double
}

/// A resolved pair. `normal` always points from A towards B.
public struct Manifold {
    public let a: RigidBody
    public let b: RigidBody
    public var normal: Vec2
    public var points: [ContactPoint]
    public var restitution: Double
    public var friction: Double
}

public enum Collision {

    /// Combined material values. Geometric mean for friction is the standard choice and
    /// behaves sensibly when one surface is deliberately slippery; `max` for restitution
    /// means a bouncy ball still bounces off a dead wall.
    public static func combinedFriction(_ a: RigidBody, _ b: RigidBody) -> Double {
        (a.friction * b.friction).squareRoot()
    }

    public static func combinedRestitution(_ a: RigidBody, _ b: RigidBody) -> Double {
        max(a.restitution, b.restitution)
    }

    // MARK: - Dispatch

    public static func manifolds(between a: RigidBody, _ b: RigidBody) -> [Manifold] {
        var results: [Manifold] = []
        for shapeA in a.shapes {
            for shapeB in b.shapes {
                if var manifold = manifold(a, shapeA, b, shapeB) {
                    manifold.restitution = combinedRestitution(a, b)
                    manifold.friction = combinedFriction(a, b)
                    results.append(manifold)
                }
            }
        }
        return results
    }

    private static func manifold(_ bodyA: RigidBody, _ shapeA: Shape,
                                 _ bodyB: RigidBody, _ shapeB: Shape) -> Manifold? {
        switch (shapeA.kind, shapeB.kind) {
        case let (.circle(centerA, radiusA), .circle(centerB, radiusB)):
            return circleCircle(bodyA, bodyA.toWorld(centerA), radiusA,
                                bodyB, bodyB.toWorld(centerB), radiusB)

        case let (.circle(centerA, radiusA), .polygon(verticesB)):
            return circlePolygon(bodyA, bodyA.toWorld(centerA), radiusA,
                                 bodyB, verticesB.map { bodyB.toWorld($0) },
                                 flipped: false)

        case let (.polygon(verticesA), .circle(centerB, radiusB)):
            return circlePolygon(bodyB, bodyB.toWorld(centerB), radiusB,
                                 bodyA, verticesA.map { bodyA.toWorld($0) },
                                 flipped: true)

        case let (.polygon(verticesA), .polygon(verticesB)):
            return polygonPolygon(bodyA, verticesA.map { bodyA.toWorld($0) },
                                  bodyB, verticesB.map { bodyB.toWorld($0) })
        }
    }

    // MARK: - Circle / circle

    private static func circleCircle(_ a: RigidBody, _ centerA: Vec2, _ radiusA: Double,
                                    _ b: RigidBody, _ centerB: Vec2, _ radiusB: Double) -> Manifold? {
        let delta = centerB - centerA
        let distance = delta.length
        let sum = radiusA + radiusB
        guard distance < sum else { return nil }
        // Perfectly coincident centres have no defined normal; pick one rather than NaN.
        let normal = distance > 1e-9 ? delta / distance : Vec2(0, 1)
        let point = centerA + normal * (radiusA - (sum - distance) / 2)
        return Manifold(a: a, b: b,
                        normal: normal,
                        points: [ContactPoint(position: point, penetration: sum - distance)],
                        restitution: 0, friction: 0)
    }

    // MARK: - Circle / polygon

    /// `flipped` means the caller's A was the polygon, so the normal must be reversed
    /// before returning — the solver relies on "normal points from A to B" absolutely.
    private static func circlePolygon(_ circleBody: RigidBody, _ center: Vec2, _ radius: Double,
                                      _ polygonBody: RigidBody, _ vertices: [Vec2],
                                      flipped: Bool) -> Manifold? {
        guard vertices.count >= 3 else { return nil }

        // Deepest edge, measured by signed distance from the circle centre.
        var bestIndex = 0
        var bestSeparation = -Double.greatestFiniteMagnitude
        for i in 0..<vertices.count {
            let p = vertices[i]
            let q = vertices[(i + 1) % vertices.count]
            let outward = (q - p).perpendicularCW.normalized()
            let separation = outward.dot(center - p)
            if separation > bestSeparation {
                bestSeparation = separation
                bestIndex = i
            }
        }
        guard bestSeparation <= radius else { return nil }

        let p = vertices[bestIndex]
        let q = vertices[(bestIndex + 1) % vertices.count]

        let normalCircleToPolygon: Vec2
        let contact: Vec2
        let penetration: Double

        if bestSeparation < 1e-9 {
            // Centre is inside the polygon: push out along the least-penetrating face.
            let outward = (q - p).perpendicularCW.normalized()
            normalCircleToPolygon = -outward
            penetration = radius - bestSeparation
            contact = center + outward * bestSeparation
        } else {
            // Outside: closest point on the deepest edge decides face vs corner contact.
            let edge = q - p
            let t = ((center - p).dot(edge) / max(edge.lengthSquared, 1e-12)).clamped(to: 0...1)
            let closest = p + edge * t
            let delta = center - closest
            let distance = delta.length
            guard distance <= radius else { return nil }
            let outward = distance > 1e-9 ? delta / distance : (q - p).perpendicularCW.normalized()
            normalCircleToPolygon = -outward
            penetration = radius - distance
            contact = closest
        }

        let normal = flipped ? -normalCircleToPolygon : normalCircleToPolygon
        let a = flipped ? polygonBody : circleBody
        let b = flipped ? circleBody : polygonBody
        return Manifold(a: a, b: b,
                        normal: normal,
                        points: [ContactPoint(position: contact, penetration: penetration)],
                        restitution: 0, friction: 0)
    }

    // MARK: - Polygon / polygon

    private struct Separation {
        var edgeIndex: Int
        var value: Double
    }

    /// Separating-axis test restricted to face normals, which is sufficient and exact
    /// for convex polygons in 2D.
    private static func maximumSeparation(_ subject: [Vec2], against other: [Vec2]) -> Separation {
        var best = Separation(edgeIndex: 0, value: -Double.greatestFiniteMagnitude)
        for i in 0..<subject.count {
            let p = subject[i]
            let q = subject[(i + 1) % subject.count]
            let outward = (q - p).perpendicularCW.normalized()
            var minimum = Double.greatestFiniteMagnitude
            for v in other { minimum = min(minimum, outward.dot(v - p)) }
            if minimum > best.value {
                best = Separation(edgeIndex: i, value: minimum)
            }
        }
        return best
    }

    private static func polygonPolygon(_ bodyA: RigidBody, _ verticesA: [Vec2],
                                       _ bodyB: RigidBody, _ verticesB: [Vec2]) -> Manifold? {
        guard verticesA.count >= 3, verticesB.count >= 3 else { return nil }

        let separationA = maximumSeparation(verticesA, against: verticesB)
        if separationA.value > 0 { return nil }
        let separationB = maximumSeparation(verticesB, against: verticesA)
        if separationB.value > 0 { return nil }

        // Prefer A's face on a tie. The bias keeps the choice stable across steps when
        // two faces are near-parallel; flip-flopping the reference face makes a resting
        // box buzz.
        let useA = separationA.value >= separationB.value - 1e-6
        let referenceVertices = useA ? verticesA : verticesB
        let incidentVertices = useA ? verticesB : verticesA
        let referenceIndex = useA ? separationA.edgeIndex : separationB.edgeIndex

        let refStart = referenceVertices[referenceIndex]
        let refEnd = referenceVertices[(referenceIndex + 1) % referenceVertices.count]
        let refNormal = (refEnd - refStart).perpendicularCW.normalized()
        let refTangent = (refEnd - refStart).normalized()

        // Incident face is the one on the incident polygon most anti-parallel to it.
        var incidentIndex = 0
        var mostOpposed = Double.greatestFiniteMagnitude
        for i in 0..<incidentVertices.count {
            let p = incidentVertices[i]
            let q = incidentVertices[(i + 1) % incidentVertices.count]
            let outward = (q - p).perpendicularCW.normalized()
            let alignment = outward.dot(refNormal)
            if alignment < mostOpposed {
                mostOpposed = alignment
                incidentIndex = i
            }
        }
        var clipped = [incidentVertices[incidentIndex],
                       incidentVertices[(incidentIndex + 1) % incidentVertices.count]]

        // Clip the incident face to the reference face's side planes.
        clipped = clipSegment(clipped, normal: refTangent, offset: refTangent.dot(refStart))
        guard clipped.count == 2 else { return nil }
        clipped = clipSegment(clipped, normal: -refTangent, offset: (-refTangent).dot(refEnd))
        guard clipped.count == 2 else { return nil }

        var points: [ContactPoint] = []
        for candidate in clipped {
            let separation = refNormal.dot(candidate - refStart)
            if separation <= 0 {
                points.append(ContactPoint(position: candidate, penetration: -separation))
            }
        }
        guard !points.isEmpty else { return nil }

        // refNormal points away from the reference polygon; the solver wants A -> B.
        let normal = useA ? refNormal : -refNormal
        return Manifold(a: bodyA, b: bodyB,
                        normal: normal,
                        points: points,
                        restitution: 0, friction: 0)
    }

    /// Keep the part of a segment on the positive side of a plane, inserting the
    /// crossing point when the segment straddles it.
    private static func clipSegment(_ segment: [Vec2], normal: Vec2, offset: Double) -> [Vec2] {
        guard segment.count == 2 else { return [] }
        let d0 = normal.dot(segment[0]) - offset
        let d1 = normal.dot(segment[1]) - offset
        var result: [Vec2] = []
        if d0 >= 0 { result.append(segment[0]) }
        if d1 >= 0 { result.append(segment[1]) }
        if d0 * d1 < 0 {
            let t = d0 / (d0 - d1)
            result.append(segment[0] + (segment[1] - segment[0]) * t)
        }
        if result.count > 2 { result = Array(result.prefix(2)) }
        return result
    }
}
```

#### `DrawPhysics/Sim/RevoluteJoint.swift`

A pin, solved in the same iteration loop as contacts so a loaded see-saw converges instead of the two constraints fighting each other.

```swift
import Foundation

/// A pin. Used for see-saws and hinged flaps (Middle band onwards).
///
/// Solved as a 2-DOF point-coincidence constraint with sequential impulses, in the same
/// iteration loop as contacts, so a see-saw with a ball resting on it converges instead
/// of fighting itself.
public final class RevoluteJoint {
    public let a: RigidBody
    public let b: RigidBody
    public let localAnchorA: Vec2
    public let localAnchorB: Vec2

    private var rA: Vec2 = .zero
    private var rB: Vec2 = .zero
    private var bias: Vec2 = .zero
    private var m00 = 0.0, m01 = 0.0, m10 = 0.0, m11 = 0.0

    /// Positional drift correction strength. Low enough not to add energy, high enough
    /// that a loaded pivot does not visibly sag.
    private let positionCorrection = 0.2
    private let allowedSlop = 0.05

    public init(a: RigidBody, b: RigidBody, worldAnchor: Vec2) {
        self.a = a
        self.b = b
        // Anchors stored in each body's local frame so the constraint survives rotation.
        self.localAnchorA = (worldAnchor - a.position).rotated(by: -a.rotation)
        self.localAnchorB = (worldAnchor - b.position).rotated(by: -b.rotation)
    }

    public func prepare(deltaTime: Double) {
        rA = localAnchorA.rotated(by: a.rotation)
        rB = localAnchorB.rotated(by: b.rotation)

        let invMassSum = a.invMass + b.invMass
        // K = sum over bodies of (invMass * I + invInertia * skew(r) * skew(r)^T)
        m00 = invMassSum + a.invInertia * rA.y * rA.y + b.invInertia * rB.y * rB.y
        m01 = -a.invInertia * rA.x * rA.y - b.invInertia * rB.x * rB.y
        m10 = m01
        m11 = invMassSum + a.invInertia * rA.x * rA.x + b.invInertia * rB.x * rB.x

        let separation = (b.position + rB) - (a.position + rA)
        let magnitude = separation.length
        let corrected = max(magnitude - allowedSlop, 0)
        bias = magnitude > 1e-9
            ? separation.normalized() * (positionCorrection / deltaTime * corrected)
            : .zero
    }

    public func solve() {
        let velocityA = a.velocity + rA.perpendicularCCW * a.angularVelocity
        let velocityB = b.velocity + rB.perpendicularCCW * b.angularVelocity
        let relative = velocityB - velocityA + bias

        let determinant = m00 * m11 - m01 * m10
        guard abs(determinant) > 1e-12 else { return }
        let rhs = -relative
        let impulse = Vec2((m11 * rhs.x - m01 * rhs.y) / determinant,
                           (m00 * rhs.y - m10 * rhs.x) / determinant)

        if a.isMovable {
            a.velocity -= impulse * a.invMass
            a.angularVelocity -= rA.cross(impulse) * a.invInertia
        }
        if b.isMovable {
            b.velocity += impulse * b.invMass
            b.angularVelocity += rB.cross(impulse) * b.invInertia
        }
    }
}
```

#### `DrawPhysics/Sim/FixedStepWorld.swift`

The determinism contract, and the four rules that keep it: fixed step size, integer step counting, no unordered collection iterated inside a step, and no wall-clock time. Also the delta clamp, without which a stall spirals, and the speed ceiling, without which a fast ball tunnels through a thin drawn line.

```swift
import Foundation

/// The simulation (§8.3).
///
/// **Why this is hand-written rather than `SKPhysicsWorld`.** SpriteKit does not expose
/// any way to advance its physics world by a chosen amount of time — there is no public
/// stepping call, only "one internal step per rendered frame". That makes a fixed
/// timestep impossible, and a fixed timestep is not a nicety here: the whole replay
/// feature depends on the same input producing the same outcome, and a frame-rate-coupled
/// step size means a 60Hz device, a 120Hz device, and a device under momentary load all
/// simulate differently. So SpriteKit renders and this steps.
///
/// Determinism rules the implementation obeys, all of them load-bearing:
/// - Every collection iterated in insertion order. No `Set` or `Dictionary` iteration
///   anywhere in the step, because their order is not specified.
/// - No wall-clock time inside a step. Kinematic motion is a function of `stepIndex`.
/// - Integer step counting, never accumulated floating-point time.
///
/// What this buys, and what it does not: identical results across runs and across frame
/// rates on one device. It does NOT buy bit-identical results across devices — see
/// `OutcomeJudge` and §8.3 for how the design makes that harmless.
public final class FixedStepWorld {

    /// 120Hz. Fast enough that a small ball never tunnels through a thin drawn barrier
    /// at the speeds this game produces, cheap enough to run two substeps per display
    /// frame on a 60Hz device.
    public static let stepSeconds = 1.0 / 120.0

    public private(set) var stepIndex = 0
    public private(set) var bodies: [RigidBody] = []
    public private(set) var joints: [RevoluteJoint] = []

    public var gravity = Vec2(0, -980)

    /// Velocity iterations. Twelve holds a ball on a drawn ramp without visible sink at
    /// the scene complexity this game reaches; the measured cost is in `ENGINEERING.md`.
    public var velocityIterations = 12

    /// Position iterations for the split-impulse pass. Four is enough to clear the
    /// penetration a single frame can produce at the clamped speed ceiling.
    public var positionIterations = 4

    /// Contact impulses are re-derived every step rather than warm-started. Warm starting
    /// needs stable contact-point identity across steps, and drawn geometry changes shape
    /// set the moment a child commits a stroke, so identity is exactly what is missing.
    /// Twelve iterations plus low restitution reaches the same stability without it.
    private var nextBodyID = 0
    private var accumulator = 0.0

    public init() {}

    // MARK: - Construction

    @discardableResult
    public func add(_ makeBody: (Int) -> RigidBody) -> RigidBody {
        let body = makeBody(nextBodyID)
        nextBodyID += 1
        bodies.append(body)
        return body
    }

    @discardableResult
    public func addJoint(a: RigidBody, b: RigidBody, worldAnchor: Vec2) -> RevoluteJoint {
        let joint = RevoluteJoint(a: a, b: b, worldAnchor: worldAnchor)
        joints.append(joint)
        return joint
    }

    public func body(tagged tag: BodyTag) -> RigidBody? {
        bodies.first { $0.tag == tag }
    }

    func isJointed(_ a: RigidBody, _ b: RigidBody) -> Bool {
        // Linear scan over an array that holds at most a handful of joints per level. A set
        // would be faster and would introduce unordered iteration into the step, which is
        // exactly what the determinism contract forbids.
        for joint in joints {
            if (joint.a === a && joint.b === b) || (joint.a === b && joint.b === a) { return true }
        }
        return false
    }

    public func removeBody(id: Int) {
        joints.removeAll { $0.a.id == id || $0.b.id == id }
        bodies.removeAll { $0.id == id }
    }

    // MARK: - Stepping

    /// Advance by a FIXED amount, however long the frame actually took, and report how
    /// many steps ran so the caller can drive per-step logic (stroke commits, goal
    /// judging) at simulation rate rather than frame rate.
    ///
    /// The clamp matters: without it, a stall — a push notification, an app switch —
    /// hands us a huge delta, we run hundreds of steps to catch up, that takes longer
    /// than a frame, and the next delta is bigger still. The simulation spirals and the
    /// app appears to hang.
    @discardableResult
    public func advance(by frameDelta: TimeInterval, onStep: ((Int) -> Void)? = nil) -> Int {
        accumulator += min(max(frameDelta, 0), 0.25)
        var stepsTaken = 0
        while accumulator >= Self.stepSeconds {
            stepOnce()
            onStep?(stepIndex)
            accumulator -= Self.stepSeconds
            stepsTaken += 1
        }
        return stepsTaken
    }

    public func stepOnce() {
        let dt = Self.stepSeconds

        // 1. Integrate velocities.
        for body in bodies where body.isMovable {
            body.velocity += gravity * dt
            body.velocity *= 1 / (1 + dt * body.linearDamping)
            body.angularVelocity *= 1 / (1 + dt * body.angularDamping)
        }

        // 2. Kinematic drivers. Velocity is set from the path so contacts push correctly,
        //    while position stays a pure function of the step index.
        for body in bodies {
            guard case .kinematic = body.motion, let path = body.kinematicPath else { continue }
            let next = path.position(atStep: stepIndex + 1)
            body.velocity = (next - body.position) / dt
            body.position = next
        }

        // 3. Broadphase then narrowphase, in body order.
        var constraints: [ContactConstraint] = []
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let a = bodies[i], b = bodies[j]
                if !a.isMovable && !b.isMovable { continue }
                if a.shapes.isEmpty || b.shapes.isEmpty { continue }
                // Jointed pairs never collide. A pinned plank overlaps its own pivot by
                // definition, and letting the contact solver argue with the joint about it
                // makes the plank creep off the pin over a few hundred steps.
                if isJointed(a, b) { continue }
                guard a.worldBounds().intersects(b.worldBounds()) else { continue }
                for manifold in Collision.manifolds(between: a, b) {
                    constraints.append(contentsOf: ContactConstraint.make(from: manifold, deltaTime: dt))
                }
            }
        }

        // 4. Solve velocities. Joints and contacts share the iteration loop so a loaded
        //    see-saw converges instead of the two constraints fighting each other.
        for joint in joints { joint.prepare(deltaTime: dt) }
        for _ in 0..<velocityIterations {
            for joint in joints { joint.solve() }
            for index in constraints.indices { constraints[index].solveVelocity() }
        }

        // 5. Push penetration out using pseudo-velocity only.
        for body in bodies where body.isMovable {
            body.pseudoVelocity = .zero
            body.pseudoAngularVelocity = 0
        }
        for _ in 0..<positionIterations {
            for index in constraints.indices { constraints[index].solvePosition() }
        }

        // 6. Integrate. Real velocity moves the body; pseudo-velocity only un-overlaps it
        //    and is discarded, so separating a stack costs no energy.
        for body in bodies where body.isMovable {
            body.velocity = Self.clampSpeed(body.velocity)
            body.position += (body.velocity + body.pseudoVelocity) * dt
            body.rotation += (body.angularVelocity + body.pseudoAngularVelocity) * dt
        }

        stepIndex += 1
    }

    /// Speed ceiling. At 120Hz a body moving faster than this travels more than half the
    /// ball's radius per step, which is where thin drawn barriers start being tunnelled
    /// through. Nothing in a level legitimately needs to move faster.
    public static let maximumSpeed = 2400.0

    static func clampSpeed(_ v: Vec2) -> Vec2 {
        let speed = v.length
        guard speed > maximumSpeed else { return v }
        return v * (maximumSpeed / speed)
    }

    /// Reset the accumulator without touching bodies. Called when the child pauses to
    /// draw, so the time spent drawing is not "owed" to the simulation and replayed as a
    /// sudden burst the moment play resumes.
    public func discardAccumulatedTime() {
        accumulator = 0
    }
}

/// One contact point, precomputed for the iteration loop.
struct ContactConstraint {
    let a: RigidBody
    let b: RigidBody
    let point: Vec2
    let normal: Vec2
    let tangent: Vec2
    let rA: Vec2
    let rB: Vec2
    let normalMass: Double
    let tangentMass: Double
    let bias: Double
    let restitutionTarget: Double
    let friction: Double

    var accumulatedNormal: Double = 0
    var accumulatedTangent: Double = 0
    var accumulatedPseudoNormal: Double = 0

    /// Fraction of the remaining overlap removed per step, and the overlap left alone.
    /// Clearing penetration completely in one step makes resting stacks twitch; leaving
    /// half a unit is invisible and stable.
    static let biasFactor = 0.2
    static let allowedPenetration = 0.5
    /// Below this approach speed restitution is suppressed. Otherwise a resting ball
    /// bounces forever on the microscopic velocity gravity adds each step.
    static let restitutionThreshold = 60.0

    static func make(from manifold: Manifold, deltaTime: Double) -> [ContactConstraint] {
        manifold.points.compactMap { contact in
            let a = manifold.a, b = manifold.b
            let rA = contact.position - a.position
            let rB = contact.position - b.position
            let normal = manifold.normal
            let tangent = normal.perpendicularCCW

            let normalDenominator = effectiveMass(a, b, rA, rB, normal)
            guard normalDenominator > 1e-12 else { return nil }
            let tangentDenominator = effectiveMass(a, b, rA, rB, tangent)

            let relative = b.velocity(at: contact.position) - a.velocity(at: contact.position)
            let approach = relative.dot(normal)
            let restitutionTarget = approach < -restitutionThreshold
                ? -manifold.restitution * approach
                : 0

            return ContactConstraint(
                a: a, b: b,
                point: contact.position,
                normal: normal,
                tangent: tangent,
                rA: rA, rB: rB,
                normalMass: 1 / normalDenominator,
                tangentMass: tangentDenominator > 1e-12 ? 1 / tangentDenominator : 0,
                bias: biasFactor / deltaTime * max(0, contact.penetration - allowedPenetration),
                restitutionTarget: restitutionTarget,
                friction: manifold.friction
            )
        }
    }

    private static func effectiveMass(_ a: RigidBody, _ b: RigidBody,
                                     _ rA: Vec2, _ rB: Vec2, _ axis: Vec2) -> Double {
        let crossA = rA.cross(axis)
        let crossB = rB.cross(axis)
        return a.invMass + b.invMass
            + a.invInertia * crossA * crossA
            + b.invInertia * crossB * crossB
    }

    mutating func solveVelocity() {
        let relative = b.velocity(at: point) - a.velocity(at: point)

        // Normal impulse, accumulated and clamped non-negative so the solver can pull back
        // an over-correction from an earlier iteration but never pull bodies together.
        // No penetration bias here — that is the position pass's job.
        let normalVelocity = relative.dot(normal)
        var deltaNormal = normalMass * (-normalVelocity + restitutionTarget)
        let clampedNormal = max(accumulatedNormal + deltaNormal, 0)
        deltaNormal = clampedNormal - accumulatedNormal
        accumulatedNormal = clampedNormal
        apply(impulse: normal * deltaNormal)

        // Coulomb friction, bounded by the normal impulse accumulated so far. This is what
        // lets a ball roll rather than slide, and what makes a steep drawn ramp hold a
        // crate instead of shedding it.
        guard tangentMass > 0 else { return }
        let updatedRelative = b.velocity(at: point) - a.velocity(at: point)
        let tangentVelocity = updatedRelative.dot(tangent)
        var deltaTangent = tangentMass * (-tangentVelocity)
        let maxTangent = friction * accumulatedNormal
        let clampedTangent = (accumulatedTangent + deltaTangent).clamped(to: -maxTangent...maxTangent)
        deltaTangent = clampedTangent - accumulatedTangent
        accumulatedTangent = clampedTangent
        apply(impulse: tangent * deltaTangent)
    }

    mutating func solvePosition() {
        guard bias > 0 else { return }
        let relative = b.pseudoVelocity(at: point) - a.pseudoVelocity(at: point)
        var delta = normalMass * (-relative.dot(normal) + bias)
        let clamped = max(accumulatedPseudoNormal + delta, 0)
        delta = clamped - accumulatedPseudoNormal
        accumulatedPseudoNormal = clamped
        applyPseudo(impulse: normal * delta)
    }

    private func apply(impulse: Vec2) {
        if a.isMovable {
            a.velocity -= impulse * a.invMass
            a.angularVelocity -= rA.cross(impulse) * a.invInertia
        }
        if b.isMovable {
            b.velocity += impulse * b.invMass
            b.angularVelocity += rB.cross(impulse) * b.invInertia
        }
    }

    private func applyPseudo(impulse: Vec2) {
        if a.isMovable {
            a.pseudoVelocity -= impulse * a.invMass
            a.pseudoAngularVelocity -= rA.cross(impulse) * a.invInertia
        }
        if b.isMovable {
            b.pseudoVelocity += impulse * b.invMass
            b.pseudoAngularVelocity += rB.cross(impulse) * b.invInertia
        }
    }
}
```

#### `DrawPhysics/Sim/OutcomeJudge.swift`

Judges once, during the original run. Has no API for revising a verdict, which is the cheapest possible way to guarantee acceptance criterion 7: there is no code that could do it.

```swift
import Foundation

/// Decides — once, during the original run — whether the goal was reached (§8.3).
///
/// The result of the ORIGINAL run is authoritative and is what gets stored. A replay
/// re-runs the same input and may, on a different device, diverge; when it does, the
/// stored verdict stands, because the child did solve it. `OutcomeJudge` therefore has no
/// API for revising a past verdict, which is the cheapest possible way to guarantee that
/// property: there is no code that could do it.
public struct OutcomeJudge {
    public let goal: GoalDefinition

    private var dwellCounter = 0
    private var gapCleared = false
    private(set) public var didReachGoal = false
    private(set) public var stepReached: Int?

    public init(goal: GoalDefinition) {
        self.goal = goal
    }

    /// Call exactly once per simulation step, never per rendered frame.
    public mutating func evaluate(world: FixedStepWorld, stepIndex: Int) {
        guard !didReachGoal else { return }

        switch goal {
        case let .ballInRegion(ballTag, region, dwellSteps):
            let inside = centre(of: ballTag, in: world).map { region.contains($0) } ?? false
            accumulate(inside: inside, needed: dwellSteps, stepIndex: stepIndex)

        case let .ballThroughGapThenRegion(ballTag, gap, region, dwellSteps):
            guard let centre = centre(of: ballTag, in: world) else { return }
            if !gapCleared, gap.contains(centre) { gapCleared = true }
            accumulate(inside: gapCleared && region.contains(centre),
                       needed: dwellSteps,
                       stepIndex: stepIndex)

        case let .allBallsInRegion(ballTags, region, dwellSteps):
            let all = ballTags.allSatisfy { tag in
                centre(of: tag, in: world).map { region.contains($0) } ?? false
            }
            accumulate(inside: all, needed: dwellSteps, stepIndex: stepIndex)
        }
    }

    private mutating func accumulate(inside: Bool, needed: Int, stepIndex: Int) {
        if inside {
            dwellCounter += 1
            if dwellCounter >= max(needed, 1) {
                didReachGoal = true
                stepReached = stepIndex
            }
        } else {
            // Reset rather than decay: a ball that grazes the cup twice has not been in it.
            dwellCounter = 0
        }
    }

    private func centre(of tag: String, in world: FixedStepWorld) -> Vec2? {
        guard let body = world.body(tagged: BodyTag(tag)) else { return nil }
        if case let .circle(center, _) = body.shapes.first?.kind {
            return body.toWorld(center)
        }
        return body.position
    }
}
```

#### `DrawPhysics/Sim/SolutionOutcome.swift`

All `let`, no mutating members. `ReplayComparison` is what a divergent replay is allowed to report — that it looked different, not that the child failed.

```swift
import Foundation

/// The verdict from the ORIGINAL run, and the reason acceptance criterion 7 holds.
///
/// Every property is `let`. There is no initialiser that takes an existing outcome and
/// changes it, and no mutating method. A replay physically cannot un-solve a level because
/// no code exists that could write to this type after it is made — which is a stronger
/// guarantee than a comment asking future contributors not to.
public struct SolutionOutcome: Codable, Equatable, Sendable {
    public let didReachGoal: Bool
    public let stepsToGoal: Int?
    public let inkUsed: Double
    public let strokeCount: Int
    public let judgedAt: Date

    public init(didReachGoal: Bool,
                stepsToGoal: Int?,
                inkUsed: Double,
                strokeCount: Int,
                judgedAt: Date = Date()) {
        self.didReachGoal = didReachGoal
        self.stepsToGoal = stepsToGoal
        self.inkUsed = inkUsed
        self.strokeCount = strokeCount
        self.judgedAt = judgedAt
    }

    public init(simulated: SolutionSimulator.Result, judgedAt: Date = Date()) {
        self.init(didReachGoal: simulated.didReachGoal,
                  stepsToGoal: simulated.stepsToGoal,
                  inkUsed: simulated.inkUsed,
                  strokeCount: simulated.acceptedStrokes,
                  judgedAt: judgedAt)
    }
}

/// What a replay is allowed to report: that it looked different. Not that the child failed.
///
/// Cross-device bit-reproducibility is not available on any float physics stack, so the
/// design makes divergence a display note rather than a correctness problem. The replay is
/// presented as "here's how they did it", and if the ball behaves slightly differently the
/// solution is still solved.
public struct ReplayComparison: Sendable {
    public let stored: SolutionOutcome
    public let replayReachedGoal: Bool
    public let replayStepsToGoal: Int?

    public init(stored: SolutionOutcome, replay: SolutionSimulator.Result) {
        self.stored = stored
        self.replayReachedGoal = replay.didReachGoal
        self.replayStepsToGoal = replay.stepsToGoal
    }

    public var diverged: Bool { stored.didReachGoal != replayReachedGoal }

    /// Shown under a replay only when it happens. Deliberately not framed as an error, and
    /// deliberately not shown to the child as "this device is wrong".
    public var childFacingNote: String? {
        diverged ? "The ball went a bit differently this time." : nil
    }
}
```

#### `DrawPhysics/Sim/SceneBuilder.swift`

Level definition to world, in authored order, because body order is part of the reproducibility contract. Two hard-won details: the see-saw's pivot anchor has no collider, and a committed stroke becomes one body with many colliders (§12.2).

```swift
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
```

#### `DrawPhysics/Sim/SolutionSimulator.swift`

One function serving four jobs — the replay the child watches, the video export, the level-integrity build gate, and the determinism tests — deliberately, because they must all agree.

```swift
import Foundation

/// Headless re-simulation of a recorded solution.
///
/// This one function is doing four jobs, and that is deliberate — they must all agree:
/// the replay the child watches, the video export, the level-integrity build gate, and
/// the determinism tests. If replay used a different code path from the build gate, the
/// gate would be proving something about code nobody runs.
public struct SolutionSimulator {

    public struct Frame: Sendable {
        public let stepIndex: Int
        public let bodies: [BodySnapshot]
    }

    public struct BodySnapshot: Sendable {
        public let id: Int
        public let tag: String
        public let position: Vec2
        public let rotation: Double
    }

    public struct Result {
        public let didReachGoal: Bool
        public let stepsToGoal: Int?
        public let stepsSimulated: Int
        public let inkUsed: Double
        public let acceptedStrokes: Int
        public let rejections: [StrokePipeline.Rejection]
        public let frames: [Frame]
    }

    public let pipeline: StrokePipeline

    public init(pipeline: StrokePipeline = StrokePipeline()) {
        self.pipeline = pipeline
    }

    /// - Parameters:
    ///   - captureEveryNthStep: 0 disables frame capture. The build gate does not need
    ///     frames and allocating them for 1800 steps x 6 levels is pure waste; the video
    ///     exporter does need them.
    public func run(level: LevelDefinition,
                    strokes: [RecordedStroke],
                    captureEveryNthStep: Int = 0) -> Result {
        let built = SceneBuilder.build(level: level)
        let world = built.world
        var judge = OutcomeJudge(goal: level.goal)
        var budget = InkBudget(total: level.inkBudget)
        var rejections: [StrokePipeline.Rejection] = []
        var accepted = 0
        var frames: [Frame] = []

        // Strokes are committed in recorded step order. Sorting by step index rather than
        // trusting array order means a hand-authored reference solution cannot accidentally
        // depend on file ordering.
        let ordered = strokes.enumerated().sorted { lhs, rhs in
            lhs.element.committedAtStep == rhs.element.committedAtStep
                ? lhs.offset < rhs.offset
                : lhs.element.committedAtStep < rhs.element.committedAtStep
        }.map { $0.element }

        var nextStrokeIndex = 0
        var shapeID = 0

        func commitStrokesDue(atStep step: Int) {
            while nextStrokeIndex < ordered.count,
                  ordered[nextStrokeIndex].committedAtStep <= step {
                let stroke = ordered[nextStrokeIndex]
                nextStrokeIndex += 1
                if let limit = level.maxStrokes, accepted >= limit {
                    rejections.append(.strokeLimitReached)
                    continue
                }
                let outcome = pipeline.makeShape(id: shapeID,
                                                 rawPoints: stroke.points,
                                                 source: stroke.source,
                                                 budget: budget)
                switch outcome {
                case let .accepted(shape, cost):
                    budget.charge(cost)
                    SceneBuilder.addDrawnShape(shape, to: world)
                    accepted += 1
                    shapeID += 1
                case let .rejected(reason):
                    rejections.append(reason)
                }
            }
        }

        commitStrokesDue(atStep: 0)

        var step = 0
        while step < level.maximumSteps {
            world.stepOnce()
            step = world.stepIndex
            commitStrokesDue(atStep: step)
            judge.evaluate(world: world, stepIndex: step)

            if captureEveryNthStep > 0, step % captureEveryNthStep == 0 {
                frames.append(Frame(stepIndex: step,
                                    bodies: world.bodies.map {
                                        BodySnapshot(id: $0.id, tag: $0.tag.raw,
                                                     position: $0.position, rotation: $0.rotation)
                                    }))
            }
            if judge.didReachGoal { break }
        }

        return Result(didReachGoal: judge.didReachGoal,
                      stepsToGoal: judge.stepReached,
                      stepsSimulated: step,
                      inkUsed: budget.spent,
                      acceptedStrokes: accepted,
                      rejections: rejections,
                      frames: frames)
    }
}
```

### 14.3 Models

#### `DrawPhysics/Models/Level.swift`

Enums with associated values get synthesised `Codable` in Swift 5.5+, so the authored JSON stays readable without a hand-written coding layer. Every goal case is a positive condition; there is no failure goal, because failing is not an event in this game.

```swift
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
```

#### `DrawPhysics/Models/LevelRepository.swift`

Fails loudly. A missing `Levels/` folder is a packaging mistake, and the error message names the exact Xcode fix — folder reference, not group. Files are sorted by name so level order is stable across filesystems.

```swift
import Foundation

/// Loads authored levels from `Resources/Levels/*.json`.
///
/// Loudly, on purpose. A missing or malformed level file is a build/packaging mistake, and
/// silently falling back to a built-in level would hide it until a child hit an empty
/// level list. `LevelIntegrityTests` runs this same loader, so the mistake surfaces in CI.
public struct LevelRepository {

    public enum LoadError: Error, CustomStringConvertible {
        case levelsDirectoryMissing(bundle: String)
        case noLevelFiles(directory: String)
        case decodeFailed(file: String, underlying: String)
        case duplicateIdentifier(String)

        public var description: String {
            switch self {
            case let .levelsDirectoryMissing(bundle):
                return """
                Levels/ was not found in \(bundle). Add Resources/Levels to the target's \
                "Copy Bundle Resources" phase as a FOLDER REFERENCE (blue folder), not a group.
                """
            case let .noLevelFiles(directory):
                return "No .json level files in \(directory)."
            case let .decodeFailed(file, underlying):
                return "Level \(file) failed to decode: \(underlying)"
            case let .duplicateIdentifier(id):
                return "Two levels share the id \(id). Level ids are used as persistence keys."
            }
        }
    }

    public let bundle: Bundle
    public let subdirectory: String

    public init(bundle: Bundle = .main, subdirectory: String = "Levels") {
        self.bundle = bundle
        self.subdirectory = subdirectory
    }

    public func loadAll() throws -> [LevelDefinition] {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory),
              !urls.isEmpty else {
            guard bundle.url(forResource: subdirectory, withExtension: nil) != nil else {
                throw LoadError.levelsDirectoryMissing(bundle: bundle.bundlePath)
            }
            throw LoadError.noLevelFiles(directory: subdirectory)
        }

        let decoder = JSONDecoder()
        var levels: [LevelDefinition] = []
        // Sorted by filename so level order is stable across filesystems. Directory
        // enumeration order is not guaranteed and a shuffling level list looks broken.
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data = try Data(contentsOf: url)
            do {
                levels.append(try decoder.decode(LevelDefinition.self, from: data))
            } catch {
                throw LoadError.decodeFailed(file: url.lastPathComponent,
                                             underlying: String(describing: error))
            }
        }

        var seen = Set<String>()
        for level in levels {
            guard seen.insert(level.id).inserted else {
                throw LoadError.duplicateIdentifier(level.id)
            }
        }
        return levels
    }

    public static func decode(from data: Data) throws -> LevelDefinition {
        try JSONDecoder().decode(LevelDefinition.self, from: data)
    }
}
```

#### `DrawPhysics/Models/DrawPhysicsDifficulty.swift`

Ink budget is the primary axis because it is the axis that creates thinking. Note the floor: the controller may never shrink a budget below what the level's own proven reference solution needs.

```swift
import Foundation
import KidsGameCore

/// Maps the shared controller's single 0...1 parameter onto this game's axes.
///
/// Ink budget is the primary axis, because it is the axis that creates thinking (§5.4).
/// The others move in coarse steps and only between levels, never mid-attempt: changing
/// the rules under a child who is halfway through an idea reads as the game breaking.
public struct DrawPhysicsDifficulty: Equatable, Sendable {

    public let band: AgeBand
    public let parameter: Double

    public init(band: AgeBand, parameter: Double) {
        self.band = band
        self.parameter = parameter.clamped(to: 0...1)
    }

    /// Per-band ink range (§6). Generous end first.
    private var inkRange: ClosedRange<Double> {
        switch band {
        case .early: return 1600...2600
        case .middle: return 900...1500
        case .upper: return 550...950
        }
    }

    /// The authored budget is the level designer's intent; this scales it within the
    /// band's range rather than replacing it, so a deliberately tight level stays tight.
    public func inkBudget(authored: Double) -> Double {
        let range = inkRange
        let scaled = range.upperBound - (range.upperBound - range.lowerBound) * parameter
        // Never hand a child less than the level's own reference solution needs; the
        // build gate proves the authored budget is sufficient, nothing proves a
        // controller-shrunk one is.
        return max(min(authored, scaled), authored * 0.75)
    }

    public var strokeLimit: Int? {
        switch band {
        case .early: return nil
        case .middle: return parameter > 0.7 ? 3 : nil
        case .upper: return parameter > 0.5 ? 2 : 3
        }
    }

    public var allowsDrawWhileRunning: Bool {
        band == .upper
    }

    /// Ink-stroke thickness, child-adjustable on top of this (§6 accessibility).
    public var suggestedStrokeThickness: Double {
        switch band {
        case .early: return 14
        case .middle: return 11
        case .upper: return 9
        }
    }
}
```


---

## 15. Authored levels

Six levels, two per band. They are **emitted by the authoring tool** (§17) rather than typed
by hand, and every one of the eleven reference solutions below was found by simulation and
re-verified by the build gate. The measured results are in §19.1.

Ship these as `DrawPhysics/Resources/Levels/*.json`, added to the target as a **folder
reference** (blue folder) in Copy Bundle Resources. `LevelRepository` names that exact
mistake in its error message because it is the one everybody makes.

<details>
<summary><code>Resources/Levels/early-01-roll-it-in.json</code></summary>

```json
{
  "band" : "early",
  "drawWhileRunning" : false,
  "fixtures" : [
    {
      "friction" : 0.8,
      "kind" : {
        "cup" : {
          "center" : {
            "x" : 600,
            "y" : 130
          },
          "height" : 150,
          "wallThickness" : 18,
          "width" : 200
        }
      },
      "restitution" : 0.05
    }
  ],
  "goal" : {
    "ballInRegion" : {
      "ballTag" : "ball",
      "dwellSteps" : 30,
      "region" : {
        "origin" : {
          "x" : 510,
          "y" : 60
        },
        "size" : {
          "height" : 110,
          "width" : 180
        }
      }
    }
  },
  "id" : "early-01-roll-it-in",
  "inkBudget" : 2200,
  "maximumSteps" : 1800,
  "movables" : [
    {
      "density" : 1,
      "friction" : 0.5,
      "kind" : {
        "ball" : {
          "center" : {
            "x" : 140,
            "y" : 880
          },
          "radius" : 26
        }
      },
      "restitution" : 0.15,
      "tag" : "ball"
    }
  ],
  "referenceSolutions" : [
    {
      "id" : "early-01-ref-long-ramp",
      "note" : "One long ramp from the left wall to just above the cup.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 110,
              "y" : 700
            },
            {
              "x" : 560,
              "y" : 250
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    },
    {
      "id" : "early-01-ref-shallow-ramp",
      "note" : "A shallower, shorter ramp. Different idea, same outcome — which is the point of the game.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 90,
              "y" : 660
            },
            {
              "x" : 520,
              "y" : 300
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    }
  ],
  "sceneSize" : {
    "height" : 1000,
    "width" : 750
  },
  "spokenHint" : "Draw something to get the ball into the cup.",
  "title" : "Roll It In"
}```

</details>

<details>
<summary><code>Resources/Levels/early-02-over-the-bump.json</code></summary>

```json
{
  "band" : "early",
  "drawWhileRunning" : false,
  "fixtures" : [
    {
      "friction" : 0.6,
      "kind" : {
        "box" : {
          "center" : {
            "x" : 400,
            "y" : 110
          },
          "rotation" : 0,
          "size" : {
            "height" : 220,
            "width" : 140
          }
        }
      },
      "restitution" : 0.05
    },
    {
      "friction" : 0.8,
      "kind" : {
        "cup" : {
          "center" : {
            "x" : 620,
            "y" : 130
          },
          "height" : 150,
          "wallThickness" : 18,
          "width" : 200
        }
      },
      "restitution" : 0.05
    }
  ],
  "goal" : {
    "ballInRegion" : {
      "ballTag" : "ball",
      "dwellSteps" : 30,
      "region" : {
        "origin" : {
          "x" : 530,
          "y" : 60
        },
        "size" : {
          "height" : 110,
          "width" : 180
        }
      }
    }
  },
  "id" : "early-02-over-the-bump",
  "inkBudget" : 2200,
  "maximumSteps" : 1800,
  "movables" : [
    {
      "density" : 1,
      "friction" : 0.5,
      "kind" : {
        "ball" : {
          "center" : {
            "x" : 120,
            "y" : 880
          },
          "radius" : 26
        }
      },
      "restitution" : 0.15,
      "tag" : "ball"
    }
  ],
  "referenceSolutions" : [
    {
      "id" : "early-02-ref-over-ramp",
      "note" : "A long ramp starting above the block, so the ball flies over it.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 80,
              "y" : 700
            },
            {
              "x" : 500,
              "y" : 260
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    },
    {
      "id" : "early-02-ref-short-launch",
      "note" : "A short high deflector: much less ink, relies on the drop instead of the ramp.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 70,
              "y" : 820
            },
            {
              "x" : 350,
              "y" : 560
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    }
  ],
  "sceneSize" : {
    "height" : 1000,
    "width" : 750
  },
  "spokenHint" : "The block is in the way. Draw a path over it.",
  "title" : "Over the Bump"
}```

</details>

<details>
<summary><code>Resources/Levels/middle-01-through-the-gap.json</code></summary>

```json
{
  "band" : "middle",
  "drawWhileRunning" : false,
  "fixtures" : [
    {
      "friction" : 0.5,
      "kind" : {
        "box" : {
          "center" : {
            "x" : 160,
            "y" : 520
          },
          "rotation" : 0,
          "size" : {
            "height" : 30,
            "width" : 320
          }
        }
      },
      "restitution" : 0.05
    },
    {
      "friction" : 0.5,
      "kind" : {
        "box" : {
          "center" : {
            "x" : 610,
            "y" : 520
          },
          "rotation" : 0,
          "size" : {
            "height" : 30,
            "width" : 280
          }
        }
      },
      "restitution" : 0.05
    },
    {
      "friction" : 0.8,
      "kind" : {
        "cup" : {
          "center" : {
            "x" : 400,
            "y" : 120
          },
          "height" : 140,
          "wallThickness" : 18,
          "width" : 190
        }
      },
      "restitution" : 0.05
    }
  ],
  "goal" : {
    "ballThroughGapThenRegion" : {
      "ballTag" : "ball",
      "dwellSteps" : 30,
      "gap" : {
        "origin" : {
          "x" : 325,
          "y" : 480
        },
        "size" : {
          "height" : 80,
          "width" : 140
        }
      },
      "region" : {
        "origin" : {
          "x" : 315,
          "y" : 55
        },
        "size" : {
          "height" : 100,
          "width" : 170
        }
      }
    }
  },
  "id" : "middle-01-through-the-gap",
  "inkBudget" : 1200,
  "maxStrokes" : 3,
  "maximumSteps" : 1800,
  "movables" : [
    {
      "density" : 1,
      "friction" : 0.5,
      "kind" : {
        "ball" : {
          "center" : {
            "x" : 130,
            "y" : 900
          },
          "radius" : 24
        }
      },
      "restitution" : 0.15,
      "tag" : "ball"
    }
  ],
  "referenceSolutions" : [
    {
      "id" : "middle-01-ref-feed-the-gap",
      "note" : "A ramp that ends exactly at the near edge of the gap, so the ball drops through it.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 70,
              "y" : 620
            },
            {
              "x" : 350,
              "y" : 560
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    }
  ],
  "sceneSize" : {
    "height" : 1000,
    "width" : 750
  },
  "spokenHint" : "Send the ball through the gap first, then into the cup.",
  "title" : "Through the Gap"
}```

</details>

<details>
<summary><code>Resources/Levels/middle-02-the-seesaw.json</code></summary>

```json
{
  "band" : "middle",
  "drawWhileRunning" : false,
  "fixtures" : [
    {
      "friction" : 0.7,
      "kind" : {
        "seesaw" : {
          "density" : 0.7,
          "length" : 340,
          "pivot" : {
            "x" : 330,
            "y" : 300
          },
          "thickness" : 22
        }
      },
      "restitution" : 0.05
    },
    {
      "friction" : 0.8,
      "kind" : {
        "cup" : {
          "center" : {
            "x" : 640,
            "y" : 120
          },
          "height" : 140,
          "wallThickness" : 18,
          "width" : 190
        }
      },
      "restitution" : 0.05
    }
  ],
  "goal" : {
    "ballInRegion" : {
      "ballTag" : "ball",
      "dwellSteps" : 30,
      "region" : {
        "origin" : {
          "x" : 555,
          "y" : 55
        },
        "size" : {
          "height" : 100,
          "width" : 170
        }
      }
    }
  },
  "id" : "middle-02-the-seesaw",
  "inkBudget" : 1200,
  "maxStrokes" : 3,
  "maximumSteps" : 1800,
  "movables" : [
    {
      "density" : 1,
      "friction" : 0.5,
      "kind" : {
        "ball" : {
          "center" : {
            "x" : 150,
            "y" : 890
          },
          "radius" : 24
        }
      },
      "restitution" : 0.15,
      "tag" : "ball"
    }
  ],
  "referenceSolutions" : [
    {
      "id" : "middle-02-ref-load-the-plank",
      "note" : "Feed the ball onto the plank's left side and let the tip throw it right.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 90,
              "y" : 700
            },
            {
              "x" : 300,
              "y" : 480
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    },
    {
      "id" : "middle-02-ref-flatter-feed",
      "note" : "A flatter feed that lands nearer the pivot. Slower tip, same result.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 100,
              "y" : 720
            },
            {
              "x" : 320,
              "y" : 460
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    }
  ],
  "sceneSize" : {
    "height" : 1000,
    "width" : 750
  },
  "spokenHint" : "The plank tips. Use it.",
  "title" : "The See-Saw"
}```

</details>

<details>
<summary><code>Resources/Levels/upper-01-two-strokes.json</code></summary>

```json
{
  "band" : "upper",
  "drawWhileRunning" : false,
  "fixtures" : [
    {
      "friction" : 0.5,
      "kind" : {
        "box" : {
          "center" : {
            "x" : 470,
            "y" : 215
          },
          "rotation" : 0,
          "size" : {
            "height" : 430,
            "width" : 28
          }
        }
      },
      "restitution" : 0.05
    },
    {
      "friction" : 0.8,
      "kind" : {
        "cup" : {
          "center" : {
            "x" : 620,
            "y" : 120
          },
          "height" : 140,
          "wallThickness" : 16,
          "width" : 180
        }
      },
      "restitution" : 0.05
    }
  ],
  "goal" : {
    "ballInRegion" : {
      "ballTag" : "ball",
      "dwellSteps" : 30,
      "region" : {
        "origin" : {
          "x" : 540,
          "y" : 55
        },
        "size" : {
          "height" : 100,
          "width" : 160
        }
      }
    }
  },
  "id" : "upper-01-two-strokes",
  "inkBudget" : 700,
  "maxStrokes" : 2,
  "maximumSteps" : 1800,
  "movables" : [
    {
      "density" : 1,
      "friction" : 0.5,
      "kind" : {
        "ball" : {
          "center" : {
            "x" : 150,
            "y" : 900
          },
          "radius" : 22
        }
      },
      "restitution" : 0.15,
      "tag" : "ball"
    }
  ],
  "referenceSolutions" : [
    {
      "id" : "upper-01-ref-over-the-wall",
      "note" : "One stroke, 335 of 700 ink: a launch ramp that clears the wall.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 70,
              "y" : 620
            },
            {
              "x" : 400,
              "y" : 560
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    },
    {
      "id" : "upper-01-ref-lower-launch",
      "note" : "The same idea started lower. Proves the answer is the angle, not the height.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 70,
              "y" : 520
            },
            {
              "x" : 400,
              "y" : 460
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    }
  ],
  "sceneSize" : {
    "height" : 1000,
    "width" : 750
  },
  "spokenHint" : "Two strokes only. Make them count.",
  "title" : "Two Strokes"
}```

</details>

<details>
<summary><code>Resources/Levels/upper-02-moving-shelf.json</code></summary>

```json
{
  "band" : "upper",
  "drawWhileRunning" : true,
  "fixtures" : [
    {
      "friction" : 0.6,
      "kind" : {
        "movingPlatform" : {
          "center" : {
            "x" : 250,
            "y" : 480
          },
          "periodSteps" : 480,
          "size" : {
            "height" : 26,
            "width" : 220
          },
          "travel" : {
            "x" : 280,
            "y" : 0
          }
        }
      },
      "restitution" : 0.05
    },
    {
      "friction" : 0.8,
      "kind" : {
        "cup" : {
          "center" : {
            "x" : 600,
            "y" : 120
          },
          "height" : 140,
          "wallThickness" : 18,
          "width" : 190
        }
      },
      "restitution" : 0.05
    }
  ],
  "goal" : {
    "ballInRegion" : {
      "ballTag" : "ball",
      "dwellSteps" : 30,
      "region" : {
        "origin" : {
          "x" : 520,
          "y" : 55
        },
        "size" : {
          "height" : 100,
          "width" : 170
        }
      }
    }
  },
  "id" : "upper-02-moving-shelf",
  "inkBudget" : 800,
  "maxStrokes" : 3,
  "maximumSteps" : 1800,
  "movables" : [
    {
      "density" : 1,
      "friction" : 0.5,
      "kind" : {
        "ball" : {
          "center" : {
            "x" : 180,
            "y" : 900
          },
          "radius" : 22
        }
      },
      "restitution" : 0.15,
      "tag" : "ball"
    }
  ],
  "referenceSolutions" : [
    {
      "id" : "upper-02-ref-timed-drop",
      "note" : "A ramp that drops the ball onto the shelf as it travels right.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 100,
              "y" : 780
            },
            {
              "x" : 340,
              "y" : 560
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    },
    {
      "id" : "upper-02-ref-lower-feed",
      "note" : "A lower feed that meets the shelf later in its cycle.",
      "strokes" : [
        {
          "committedAtStep" : 0,
          "points" : [
            {
              "x" : 90,
              "y" : 740
            },
            {
              "x" : 320,
              "y" : 520
            }
          ],
          "source" : {
            "freehand" : {

            }
          }
        }
      ]
    }
  ],
  "sceneSize" : {
    "height" : 1000,
    "width" : 750
  },
  "spokenHint" : "The shelf keeps moving. You can draw while it runs.",
  "title" : "Moving Shelf"
}```

</details>

---

## 16. Tests — 40 of them, all passing

Run with `swift test` in the core package, or as the `DrawPhysicsTests` target in the app.
The only difference between the two is the bundle `LevelIntegrityTests` reads from: in the
app target it is `Bundle.main` (an app-hosted test bundle sees the host app as main), in the
standalone package it is `Bundle.module`. Every other line is identical.

#### `DrawPhysicsTests/ConvexDecomposerTests.swift`

The gate that blocks everything else. Three fixtures — L, star, comb — chosen because each breaks a different thing: the L is the minimum reflex case, the star is where winding bugs surface, the comb is where a merge pass without an area check starts producing non-convex unions.

```swift
import XCTest
@testable import DrawPhysicsCore

/// The gate that blocks everything else (§7 M2). If decomposition is wrong, objects fall
/// through drawn surfaces or launch across the screen, and no amount of work elsewhere
/// makes the game playable.
final class ConvexDecomposerTests: XCTestCase {

    private let decomposer = ConvexDecomposer()

    // MARK: - Fixtures

    /// Classic L: one reflex vertex, the simplest shape ear clipping must handle.
    private var lShape: [Vec2] {
        [Vec2(0, 0), Vec2(120, 0), Vec2(120, 40), Vec2(40, 40), Vec2(40, 120), Vec2(0, 120)]
    }

    /// Five-pointed star: five reflex vertices, and the shape most likely to expose a
    /// winding bug because its interior is easy to get backwards.
    private var star: [Vec2] {
        var points: [Vec2] = []
        let outer = 100.0, inner = 42.0
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5 - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            points.append(Vec2(cos(angle) * radius, sin(angle) * radius))
        }
        return points
    }

    /// A comb. Many reflex vertices, which is where a naive merge pass starts producing
    /// non-convex unions if the area check is missing.
    private var comb: [Vec2] {
        var points: [Vec2] = [Vec2(0, 0), Vec2(240, 0), Vec2(240, 30)]
        var x = 240.0
        while x > 0 {
            points.append(Vec2(x, 30))
            points.append(Vec2(x, 90))
            points.append(Vec2(x - 20, 90))
            points.append(Vec2(x - 20, 30))
            x -= 40
        }
        points.append(Vec2(0, 30))
        return points
    }

    private var allFixtures: [(String, [Vec2])] {
        [("L", lShape), ("star", star), ("comb", comb)]
    }

    // MARK: - Named invariants (§9)

    func testEveryPieceIsConvex() {
        for (name, polygon) in allFixtures {
            let pieces = decomposer.decompose(polygon)
            XCTAssertFalse(pieces.isEmpty, "\(name) produced no pieces")
            for (index, piece) in pieces.enumerated() {
                XCTAssertGreaterThanOrEqual(piece.count, 3, "\(name) piece \(index) is degenerate")
                XCTAssertTrue(Polygon.isConvex(piece, tolerance: 1e-4),
                              "\(name) piece \(index) is not convex: \(piece)")
            }
        }
    }

    func testWindingIsCanonicalised() {
        for (name, polygon) in allFixtures {
            // Feed both windings. Output winding must not depend on input winding, because
            // edge normals are derived from vertex order and an inverted normal means the
            // ball falls straight through the thing the child drew.
            for (label, input) in [("ccw", polygon), ("cw", Array(polygon.reversed()))] {
                for piece in decomposer.decompose(input) {
                    XCTAssertGreaterThan(Polygon.signedArea(piece), 0,
                                         "\(name)/\(label) produced a clockwise piece")
                }
            }
        }
    }

    func testUnionAreaMatchesInputWithinTolerance() {
        for (name, polygon) in allFixtures {
            let expected = Polygon.area(polygon)
            let actual = decomposer.decompose(polygon).reduce(0) { $0 + Polygon.area($1) }
            // 1% covers the sliver pieces intentionally dropped below `minimumPieceArea`.
            XCTAssertEqual(actual, expected, accuracy: expected * 0.01,
                           "\(name): union area \(actual) vs input \(expected)")
        }
    }

    func testSliverTrianglesAreDropped() {
        // A rectangle with a hair-thin spike. The spike triangle has an area far below the
        // threshold and must not survive as a body: a near-zero-area body has near-zero
        // effective mass along one axis, so a small overlap produces an enormous impulse and
        // the object jitters, then launches.
        let spiked = [Vec2(0, 0), Vec2(200, 0), Vec2(200, 60),
                      Vec2(100, 60.05), Vec2(0, 60)]
        let pieces = decomposer.decompose(spiked)
        XCTAssertFalse(pieces.isEmpty)
        for piece in pieces {
            XCTAssertGreaterThan(Polygon.area(piece), decomposer.minimumPieceArea,
                                 "a sliver survived: \(piece)")
        }
    }

    // MARK: - Supporting behaviour

    func testConvexInputIsReturnedAsASinglePiece() {
        let square = [Vec2(0, 0), Vec2(80, 0), Vec2(80, 80), Vec2(0, 80)]
        XCTAssertEqual(decomposer.decompose(square).count, 1)
    }

    func testMergingProducesFewerPiecesThanTriangulation() {
        // The entire reason merging exists: narrowphase cost tracks piece count, so a
        // 40-triangle blob measurably drops the frame rate.
        for (name, polygon) in allFixtures {
            let canonical = Polygon.ensureCounterClockwise(polygon)
            let triangles = ConvexDecomposer.earClip(canonical).count
            let merged = decomposer.decompose(polygon).count
            XCTAssertLessThan(merged, triangles,
                              "\(name): merging did not reduce piece count (\(merged) vs \(triangles))")
        }
    }

    func testDecompositionTerminatesOnPathologicalInput() {
        // Near-duplicate and collinear vertices are what real finger input looks like after
        // simplification, and they are what makes a naive "scan until an ear appears" loop
        // spin forever.
        var pathological: [Vec2] = []
        for index in 0..<40 {
            let t = Double(index)
            pathological.append(Vec2(t, (t * 0.0001).rounded()))
        }
        pathological.append(Vec2(39, 60))
        pathological.append(Vec2(0, 60))
        let pieces = decomposer.decompose(pathological)
        for piece in pieces {
            XCTAssertTrue(Polygon.isConvex(piece, tolerance: 1e-4))
        }
    }

    func testMergedPieceAreaNeverExceedsTheInput() {
        // A merge that produced a non-simple union would inflate area. The area check in
        // `mergeWhileConvex` exists precisely to reject that, so assert it holds.
        for (_, polygon) in allFixtures {
            let total = decomposer.decompose(polygon).reduce(0) { $0 + Polygon.area($1) }
            XCTAssertLessThanOrEqual(total, Polygon.area(polygon) * 1.0001)
        }
    }
}
```

#### `DrawPhysicsTests/StrokeSimplifierTests.swift`

Input is dense sampled curves, not tidy polygons, because that is what a finger produces. The figure-of-eight test is the one that matters: it asserts repair leaves geometry that decomposition can actually consume.

```swift
import XCTest
@testable import DrawPhysicsCore

final class StrokeSimplifierTests: XCTestCase {

    private let simplifier = StrokeSimplifier()
    private let pipeline = StrokePipeline()

    // MARK: - Helpers

    /// Dense sampled input, which is what a finger actually produces — a few hundred points
    /// with sub-pixel spacing, not a tidy polygon.
    private func sampledCircle(centre: Vec2, radius: Double, samples: Int = 220,
                              sweep: Double = 2 * .pi) -> [Vec2] {
        (0..<samples).map { index in
            let angle = sweep * Double(index) / Double(samples)
            return centre + Vec2(cos(angle) * radius, sin(angle) * radius)
        }
    }

    // MARK: - Named invariants (§9)

    func testSelfIntersectingLoopYieldsValidGeometry() {
        // A figure-of-eight: two lobes crossing in the middle. A self-intersecting polygon
        // has no well-defined interior, so decomposition on it is meaningless — the pipeline
        // must repair it into a simple loop first.
        var points: [Vec2] = []
        for index in 0..<200 {
            let t = 2 * .pi * Double(index) / 200
            points.append(Vec2(140 + cos(t) * 90, 300 + sin(2 * t) * 70))
        }
        points.append(points[0])

        guard let processed = simplifier.process(rawPoints: points) else {
            return XCTFail("a large self-crossing loop should not be discarded")
        }
        XCTAssertTrue(processed.isClosed)
        XCTAssertTrue(Polygon.isSimple(processed.simplifiedPoints),
                      "repair left a self-intersection behind")
        XCTAssertGreaterThan(Polygon.area(processed.simplifiedPoints), 0)

        let pieces = ConvexDecomposer().decompose(processed.simplifiedPoints)
        XCTAssertFalse(pieces.isEmpty, "repaired geometry produced no bodies")
        for piece in pieces {
            XCTAssertTrue(Polygon.isConvex(piece, tolerance: 1e-4))
            XCTAssertGreaterThan(Polygon.area(piece), 0)
        }
    }

    func testClosureDetectionDistinguishesLoopFromLine() {
        // A child notices this distinction immediately: a closed loop should be a solid blob
        // things rest on, an open line a thin barrier they slide along.
        let loop = sampledCircle(centre: Vec2(300, 400), radius: 80)
        guard let closed = simplifier.process(rawPoints: loop) else {
            return XCTFail("a full circle should classify as closed")
        }
        XCTAssertTrue(closed.isClosed)
        XCTAssertGreaterThan(closed.enclosedArea, 0)

        let line = (0..<120).map { Vec2(60 + Double($0) * 4, 500 - Double($0) * 1.5) }
        guard let open = simplifier.process(rawPoints: line) else {
            return XCTFail("a long line should classify as open")
        }
        XCTAssertFalse(open.isClosed)
        XCTAssertEqual(open.enclosedArea, 0)

        // Three-quarters of a circle: endpoints far apart, so it stays open even though it
        // curves back on itself.
        let arc = sampledCircle(centre: Vec2(300, 400), radius: 80, sweep: 1.5 * .pi)
        XCTAssertEqual(simplifier.process(rawPoints: arc)?.isClosed, false)
    }

    func testSimplificationPreservesShapeWithinTolerance() {
        let radius = 90.0
        let circle = sampledCircle(centre: Vec2(200, 200), radius: radius, samples: 300)
        guard let processed = simplifier.process(rawPoints: circle) else {
            return XCTFail("circle rejected")
        }
        // Vertex count must come down a long way or decomposition is slow...
        XCTAssertLessThanOrEqual(processed.simplifiedPoints.count,
                                 simplifier.configuration.maximumVertices)
        // ...but the shape the child drew must still be recognisably what they drew. An
        // inscribed polygon always loses a little area; 6% is the measured budget.
        let expected = .pi * radius * radius
        XCTAssertEqual(Polygon.area(processed.simplifiedPoints), expected,
                       accuracy: expected * 0.06)
    }

    func testOpenStrokeBecomesAThinChainOfConvexQuads() {
        let line = (0..<80).map { Vec2(60 + Double($0) * 6, 420 + sin(Double($0) / 9) * 40) }
        let budget = InkBudget(total: 5000)
        guard case let .accepted(shape, _) = pipeline.makeShape(id: 0, rawPoints: line,
                                                               source: .freehand, budget: budget) else {
            return XCTFail("open stroke rejected")
        }
        XCTAssertFalse(shape.isClosed)
        XCTAssertFalse(shape.convexPieces.isEmpty)
        for quad in shape.convexPieces {
            XCTAssertEqual(quad.count, 4)
            XCTAssertTrue(Polygon.isConvex(quad, tolerance: 1e-6))
            XCTAssertGreaterThan(Polygon.signedArea(quad), 0)
        }
    }

    // MARK: - Supporting behaviour

    func testTapsAndFlecksAreRejected() {
        XCTAssertNil(simplifier.process(rawPoints: [Vec2(100, 100)]))
        let fleck = [Vec2(100, 100), Vec2(103, 101), Vec2(105, 100)]
        let budget = InkBudget(total: 1000)
        guard case let .rejected(reason) = pipeline.makeShape(id: 0, rawPoints: fleck,
                                                             source: .freehand, budget: budget) else {
            return XCTFail("a 5-unit fleck must not become a body")
        }
        XCTAssertEqual(reason, .tooShort)
    }

    func testTinyClosedScribbleIsTreatedAsALineNotASolid() {
        // Endpoints coincide but almost no area is enclosed. Making that a "solid" gives a
        // near-degenerate body, which is the launch-across-the-screen bug.
        let scribble = sampledCircle(centre: Vec2(200, 200), radius: 6, samples: 40)
        let processed = simplifier.process(rawPoints: scribble)
        XCTAssertNotEqual(processed?.isClosed, true)
    }

    func testRamerDouglasPeuckerKeepsEndpoints() {
        let points = (0..<50).map { Vec2(Double($0) * 10, 0) }
        let simplified = StrokeSimplifier.simplify(points, tolerance: 2)
        XCTAssertEqual(simplified.first, points.first)
        XCTAssertEqual(simplified.last, points.last)
        XCTAssertEqual(simplified.count, 2, "a straight line should reduce to its endpoints")
    }

    func testSimplificationIsDeterministic() {
        let stroke = sampledCircle(centre: Vec2(310, 480), radius: 77, samples: 251)
        let first = simplifier.process(rawPoints: stroke)
        let second = simplifier.process(rawPoints: stroke)
        XCTAssertEqual(first, second)
    }
}
```

#### `DrawPhysicsTests/FixedStepWorldTests.swift`

Determinism assertions are exact equality, not `accuracy:`. Same machine, same input, same order of operations — any difference at all would mean an unordered collection or wall-clock time had leaked into the step. The frame-rate test drives 120Hz, 60Hz, 30Hz and a deliberately jittering rate including a 200ms stall, and compares state at the same step index.

```swift
import XCTest
@testable import DrawPhysicsCore

final class FixedStepWorldTests: XCTestCase {

    private let simulator = SolutionSimulator()

    /// A minimal level built in code rather than loaded, so these tests exercise the
    /// simulation and nothing else.
    private func testLevel(inkBudget: Double = 3000) -> LevelDefinition {
        LevelDefinition(
            id: "unit-fixed-step",
            title: "Unit",
            band: .middle,
            inkBudget: inkBudget,
            spokenHint: "unit test",
            fixtures: [
                FixtureDefinition(kind: .cup(center: Vec2(600, 130), width: 200,
                                             height: 150, wallThickness: 18),
                                  friction: 0.8, restitution: 0.05)
            ],
            movables: [
                MovableDefinition(tag: "ball", kind: .ball(center: Vec2(140, 880), radius: 26))
            ],
            goal: .ballInRegion(ballTag: "ball",
                                region: Rect(x: 510, y: 60, width: 180, height: 110),
                                dwellSteps: 30)
        )
    }

    private var workingRamp: [RecordedStroke] {
        [RecordedStroke(points: [Vec2(110, 700), Vec2(560, 250)], committedAtStep: 0)]
    }

    // MARK: - Named invariants (§9)

    func testSameInputSameOutcomeAcrossRunsOnDevice() {
        let level = testLevel()
        var results: [(Bool, Int?, Vec2)] = []
        for _ in 0..<8 {
            let result = simulator.run(level: level, strokes: workingRamp, captureEveryNthStep: 60)
            let lastBall = result.frames.last?.bodies.first { $0.tag == "ball" }
            results.append((result.didReachGoal, result.stepsToGoal, lastBall?.position ?? .zero))
        }
        for run in results.dropFirst() {
            XCTAssertEqual(run.0, results[0].0)
            XCTAssertEqual(run.1, results[0].1)
            // Bit-identical, not merely close. Same machine, same input, same order of
            // operations: any difference at all would mean an unordered collection or
            // wall-clock time had leaked into the step.
            XCTAssertEqual(run.2.x, results[0].2.x)
            XCTAssertEqual(run.2.y, results[0].2.y)
        }
        XCTAssertTrue(results[0].0, "the fixture ramp is supposed to solve the fixture level")
    }

    func testForcedFrameRateChangeDoesNotAlterOutcome() {
        // The step function never sees the frame delta — `advance` only decides HOW MANY
        // steps to run. So 60Hz, 120Hz, and a deliberately jittering frame rate must all
        // produce identical state at the same step index. Without a fixed timestep this is
        // exactly what breaks, and a replay of a successful solution starts failing under
        // load.
        let targetStep = 600
        func stateAtTargetStep(deltas: [TimeInterval]) -> Vec2 {
            let built = SceneBuilder.build(level: testLevel())
            let pipeline = StrokePipeline()
            var budget = InkBudget(total: 3000)
            if case let .accepted(shape, cost) = pipeline.makeShape(id: 0,
                                                                   rawPoints: workingRamp[0].points,
                                                                   source: .freehand,
                                                                   budget: budget) {
                budget.charge(cost)
                SceneBuilder.addDrawnShape(shape, to: built.world)
            }
            var captured = Vec2.zero
            var deltaIndex = 0
            while built.world.stepIndex < targetStep {
                built.world.advance(by: deltas[deltaIndex % deltas.count]) { step in
                    if step == targetStep, let ball = built.world.body(tagged: BodyTag("ball")) {
                        captured = ball.position
                    }
                }
                deltaIndex += 1
            }
            return captured
        }

        let at120 = stateAtTargetStep(deltas: [1.0 / 120.0])
        let at60 = stateAtTargetStep(deltas: [1.0 / 60.0])
        let at30 = stateAtTargetStep(deltas: [1.0 / 30.0])
        let jittery = stateAtTargetStep(deltas: [1.0 / 58.0, 1.0 / 121.0, 1.0 / 41.0, 0.2])

        XCTAssertEqual(at60.x, at120.x)
        XCTAssertEqual(at60.y, at120.y)
        XCTAssertEqual(at30.x, at120.x)
        XCTAssertEqual(at30.y, at120.y)
        XCTAssertEqual(jittery.x, at120.x)
        XCTAssertEqual(jittery.y, at120.y)
    }

    func testStoredOutcomeIsNeverMutatedByReplay() {
        let level = testLevel()
        let original = simulator.run(level: level, strokes: workingRamp)
        XCTAssertTrue(original.didReachGoal)
        let stored = SolutionOutcome(simulated: original)

        // Force the replay to diverge the way another device's floating point might, only
        // harder, so the assertion is unambiguous.
        var divergentLevel = level
        divergentLevel.movables = [
            MovableDefinition(tag: "ball", kind: .ball(center: Vec2(120, 880), radius: 26))
        ]
        let replay = simulator.run(level: divergentLevel, strokes: workingRamp)
        let comparison = ReplayComparison(stored: stored, replay: replay)

        XCTAssertTrue(comparison.stored.didReachGoal,
                      "a divergent replay must never un-solve a level")
        XCTAssertEqual(comparison.stored.stepsToGoal, original.stepsToGoal)
        XCTAssertEqual(comparison.stored.inkUsed, original.inkUsed)
        if comparison.diverged {
            XCTAssertNotNil(comparison.childFacingNote)
        }
    }

    // MARK: - Stability

    func testRestingBallNeitherJittersNorSinks() {
        // Jitter and sink are the two failure modes that make a physics game feel broken, and
        // both come from the solver rather than from the geometry.
        let level = LevelDefinition(id: "unit-rest", title: "Rest", band: .early,
                                    inkBudget: 1000, spokenHint: "",
                                    fixtures: [],
                                    movables: [MovableDefinition(tag: "ball",
                                                                 kind: .ball(center: Vec2(300, 200),
                                                                             radius: 30))],
                                    goal: .ballInRegion(ballTag: "ball",
                                                        region: Rect(x: -9999, y: -9999,
                                                                     width: 1, height: 1),
                                                        dwellSteps: 30),
                                    maximumSteps: 1200)
        let result = simulator.run(level: level, strokes: [], captureEveryNthStep: 30)
        let settled = result.frames.suffix(12).compactMap { frame in
            frame.bodies.first { $0.tag == "ball" }?.position.y
        }
        XCTAssertFalse(settled.isEmpty)
        for y in settled {
            XCTAssertEqual(y, 30, accuracy: 1.0, "ball sank into or floated above the floor")
        }
        let spread = (settled.max() ?? 0) - (settled.min() ?? 0)
        XCTAssertLessThan(spread, 0.05, "resting ball is jittering by \(spread)")
    }

    func testFastBallDoesNotTunnelThroughAThinDrawnBarrier() {
        // The speed clamp plus the 120Hz step exists for this. A ball that passes through the
        // line a child drew is the single most trust-destroying bug the game could have.
        let world = FixedStepWorld()
        SceneBuilder.addDrawnShape(
            DrawnShape(id: 0,
                       rawPoints: [Vec2(0, 300), Vec2(750, 300)],
                       simplifiedPoints: [Vec2(0, 300), Vec2(750, 300)],
                       convexPieces: StrokeSimplifier.chainPieces([Vec2(0, 300), Vec2(750, 300)],
                                                                  thickness: 11),
                       isClosed: false,
                       inkLength: 750,
                       enclosedArea: 0,
                       thickness: 11,
                       source: .freehand),
            to: world)
        let ball = world.add { id in
            RigidBody(id: id, tag: BodyTag("ball"),
                      shapes: [.circle(radius: 22)],
                      motion: .dynamic, position: Vec2(375, 900))
        }
        ball.velocity = Vec2(0, -FixedStepWorld.maximumSpeed)
        for _ in 0..<600 { world.stepOnce() }
        XCTAssertGreaterThan(ball.position.y, 300,
                             "ball tunnelled through the barrier to y=\(ball.position.y)")
    }

    func testStallDoesNotSpiralTheSimulation() {
        // A push notification or an app switch hands us a huge delta. Without the clamp we
        // run hundreds of steps to catch up, that takes longer than a frame, the next delta
        // is bigger, and the app appears to hang.
        let world = FixedStepWorld()
        let steps = world.advance(by: 12.0)
        XCTAssertLessThanOrEqual(steps, 30, "a 12 second stall must not run 1440 steps")
    }

    func testSeesawTipsUnderLoad() {
        // Proves the revolute joint actually constrains: the plank must rotate about its
        // pivot rather than fall, and it must respond to a ball landing off-centre.
        let level = LevelDefinition(
            id: "unit-seesaw", title: "Seesaw", band: .middle, inkBudget: 1000, spokenHint: "",
            fixtures: [FixtureDefinition(kind: .seesaw(pivot: Vec2(375, 300), length: 340,
                                                       thickness: 22, density: 0.7))],
            movables: [MovableDefinition(tag: "ball", kind: .ball(center: Vec2(260, 600), radius: 24))],
            goal: .ballInRegion(ballTag: "ball",
                                region: Rect(x: -9999, y: -9999, width: 1, height: 1),
                                dwellSteps: 30),
            maximumSteps: 600)
        let built = SceneBuilder.build(level: level)
        guard let plank = built.world.bodies.first(where: { $0.tag.raw.hasPrefix("seesaw.0") }) else {
            return XCTFail("no plank")
        }
        for _ in 0..<600 { built.world.stepOnce() }
        XCTAssertEqual(plank.position.x, 375, accuracy: 3.0, "the pin let the plank drift")
        XCTAssertEqual(plank.position.y, 300, accuracy: 3.0, "the pin let the plank fall")
        XCTAssertGreaterThan(abs(plank.rotation), 0.05, "the plank never tipped")
    }
}
```

#### `DrawPhysicsTests/InkMeterTests.swift`

Both directions of the calibration. The blob must be unaffordable in every band, and an ordinary ramp must still fit the tightest one — a budget that excluded the blob by also excluding real answers would have stopped creating thinking and started preventing it.

```swift
import XCTest
@testable import DrawPhysicsCore

final class InkMeterTests: XCTestCase {

    private let meter = InkMeter()
    private let pipeline = StrokePipeline()

    /// Every band's most generous budget. If the blob strategy fails against the largest
    /// budget in the game it fails against all of them.
    private var bandBudgets: [(AgeBand, Double)] {
        [(.early, 2600), (.middle, 1500), (.upper, 950)]
    }

    // MARK: - Named invariants (§9)

    func testSingleGiantBlobExceedsEveryBandBudget() {
        // Without an area charge this is the answer to every level in the game: enclose the
        // ball and the cup in one huge shape and let gravity do the rest. Its outline is
        // short, so arc length alone barely notices.
        let blob = (0..<160).map { index -> Vec2 in
            let angle = 2 * .pi * Double(index) / 160
            return Vec2(375 + cos(angle) * 330, 500 + sin(angle) * 440)
        }
        guard let processed = StrokeSimplifier().process(rawPoints: blob) else {
            return XCTFail("the blob should be a valid closed shape — it just must be unaffordable")
        }
        XCTAssertTrue(processed.isClosed)
        let cost = meter.cost(of: processed)

        for (band, budget) in bandBudgets {
            XCTAssertGreaterThan(cost, budget,
                                 "\(band) could afford the blob: cost \(cost) vs budget \(budget)")
        }

        // And show the charge is doing the work, not the perimeter: on perimeter alone it
        // would be affordable at the early band, which is exactly the hole being closed.
        XCTAssertLessThan(processed.inkLength, 2600)
    }

    func testUndoRefundsExactlyTheStrokeCost() {
        var budget = InkBudget(total: 2000)
        let costs = [123.5, 47.25, 512.0]
        for cost in costs { XCTAssertTrue(budget.charge(cost)) }
        XCTAssertEqual(budget.spent, costs.reduce(0, +), accuracy: 1e-12)

        // Exact, not approximate. Undo is unlimited and free, so a rounding error here leaks
        // budget on every undo and eventually makes a solvable level unsolvable.
        XCTAssertEqual(budget.refundLast(), 512.0)
        XCTAssertEqual(budget.spent, 123.5 + 47.25, accuracy: 1e-12)
        XCTAssertEqual(budget.refundLast(), 47.25)
        XCTAssertEqual(budget.refundLast(), 123.5)
        XCTAssertEqual(budget.spent, 0)
        XCTAssertNil(budget.refundLast())
        XCTAssertEqual(budget.remaining, 2000)
    }

    func testRepeatedDrawUndoCyclesDoNotLeakBudget() {
        var budget = InkBudget(total: 1000)
        let line = (0..<40).map { Vec2(60 + Double($0) * 8, 400) }
        for id in 0..<200 {
            guard case let .accepted(_, cost) = pipeline.makeShape(id: id, rawPoints: line,
                                                                 source: .freehand, budget: budget) else {
                return XCTFail("stroke rejected on cycle \(id)")
            }
            budget.charge(cost)
            budget.refundLast()
        }
        XCTAssertEqual(budget.spent, 0)
        XCTAssertEqual(budget.remaining, 1000)
    }

    // MARK: - The other side of the calibration

    func testALegitimateRampFitsTheTightestBudget() {
        // The budget has to exclude the blob WITHOUT excluding a real answer. A single
        // sensible ramp must fit the tightest band with room to spare, or the constraint has
        // stopped creating thinking and started preventing it.
        let ramp = [Vec2(70, 620), Vec2(400, 560)]
        guard let processed = StrokeSimplifier().process(rawPoints: ramp) else {
            return XCTFail("ramp rejected")
        }
        let cost = meter.cost(of: processed)
        XCTAssertLessThan(cost, 550, "an ordinary ramp costs \(cost), which is too much")
    }

    func testASmallDeliberateBlockRemainsAffordable() {
        // Closed shapes must stay usable — the area charge is aimed at the scene-sized blob,
        // not at a child who wants a solid block to sit under the ball.
        let block = [Vec2(300, 300), Vec2(360, 300), Vec2(360, 360), Vec2(300, 360), Vec2(302, 302)]
        guard let processed = StrokeSimplifier().process(rawPoints: block) else {
            return XCTFail("block rejected")
        }
        XCTAssertTrue(processed.isClosed)
        XCTAssertLessThan(meter.cost(of: processed), 700)
    }

    func testMinimumStrokeLengthRejectsAccidentalTaps() {
        let budget = InkBudget(total: 1000)
        let tap = [Vec2(200, 200), Vec2(204, 203), Vec2(206, 201)]
        guard case let .rejected(reason) = pipeline.makeShape(id: 0, rawPoints: tap,
                                                             source: .freehand, budget: budget) else {
            return XCTFail("a tap must not create a body")
        }
        XCTAssertEqual(reason, .tooShort)
    }

    func testOverBudgetStrokeIsRejectedWithItsCost() {
        // The rejection carries the numbers so the HUD can say "that one is too big" instead
        // of silently doing nothing, which reads as the app being broken.
        let budget = InkBudget(total: 120)
        let long = (0..<80).map { Vec2(60 + Double($0) * 8, 400) }
        guard case let .rejected(.overBudget(cost, remaining)) =
                pipeline.makeShape(id: 0, rawPoints: long, source: .freehand, budget: budget) else {
            return XCTFail("expected an over-budget rejection")
        }
        XCTAssertGreaterThan(cost, remaining)
        XCTAssertEqual(remaining, 120)
    }

    func testClosedShapeIsChargedForAreaAsWellAsPerimeter() {
        let square = [Vec2(0, 0), Vec2(200, 0), Vec2(200, 200), Vec2(0, 200)]
        let perimeterOnly = Polygon.perimeter(square)
        let charged = meter.cost(perimeterOrLength: perimeterOnly,
                                 enclosedArea: Polygon.area(square),
                                 isClosed: true)
        XCTAssertEqual(charged, perimeterOnly + 200 * 200 * meter.areaCharge, accuracy: 1e-9)
        XCTAssertGreaterThan(charged, perimeterOnly * 3)
    }
}
```

#### `DrawPhysicsTests/LevelIntegrityTests.swift`

The build gate for hand-authored content, including the two checks Part I did not ask for (§12.4): no level solves itself with no strokes, and every reference solution survives being drawn 6 units off.

```swift
import XCTest
@testable import DrawPhysicsCore

/// The build gate for hand-authored content (§8.5).
///
/// Hand-designed physics levels have exactly two reliable failure modes: they ship
/// unsolvable, or they ship with a budget too tight for their own intended answer. Both are
/// invisible to a human reading the level file and obvious to a simulator, so the simulator
/// gets the job.
final class LevelIntegrityTests: XCTestCase {

    /// In the app target this is `Bundle.main` — an XCTest bundle hosted by the app sees the
    /// app bundle as main, so the same loader the game uses is the loader under test.
    private var repository: LevelRepository { LevelRepository(bundle: .module) }
    private let simulator = SolutionSimulator()

    private func loadLevels() throws -> [LevelDefinition] {
        let levels = try repository.loadAll()
        XCTAssertFalse(levels.isEmpty)
        return levels
    }

    func testLevelsLoadFromTheBundle() throws {
        let levels = try loadLevels()
        XCTAssertEqual(levels.count, 6)
        XCTAssertEqual(Set(levels.map(\.band)), Set(AgeBand.allCases),
                       "every band must have at least one level")
    }

    func testEveryLevelDeclaresAtLeastOneReferenceSolution() throws {
        for level in try loadLevels() {
            XCTAssertFalse(level.referenceSolutions.isEmpty,
                           "\(level.id) has no reference solution, so nothing proves it is solvable")
        }
    }

    func testEveryLevelReferenceSolutionReachesGoal() throws {
        for level in try loadLevels() {
            for reference in level.referenceSolutions {
                let result = simulator.run(level: level, strokes: reference.strokes)
                XCTAssertTrue(result.didReachGoal,
                              "\(level.id)/\(reference.id) did not reach the goal in \(level.maximumSteps) steps")
                XCTAssertTrue(result.rejections.isEmpty,
                              "\(level.id)/\(reference.id) had strokes rejected: \(result.rejections)")
            }
        }
    }

    func testEveryReferenceSolutionFitsItsInkBudget() throws {
        for level in try loadLevels() {
            for reference in level.referenceSolutions {
                let result = simulator.run(level: level, strokes: reference.strokes)
                XCTAssertLessThanOrEqual(result.inkUsed, level.inkBudget,
                                         "\(level.id)/\(reference.id) needs \(result.inkUsed) ink but the level allows \(level.inkBudget)")
            }
        }
    }

    func testNoLevelIsSolvableWithoutDrawing() throws {
        // Not in the original brief, and it should have been. During authoring, one level's
        // fixtures fed the ball straight into the cup with no strokes at all — it looked fine
        // in the level file and it was not a level.
        for level in try loadLevels() {
            let result = simulator.run(level: level, strokes: [])
            XCTAssertFalse(result.didReachGoal,
                           "\(level.id) solves itself with no strokes")
        }
    }

    func testEveryReferenceSolutionRespectsItsStrokeLimit() throws {
        for level in try loadLevels() {
            guard let limit = level.maxStrokes else { continue }
            for reference in level.referenceSolutions {
                XCTAssertLessThanOrEqual(reference.strokes.count, limit,
                                         "\(level.id)/\(reference.id) uses more strokes than the level allows")
            }
        }
    }

    func testReferenceSolutionsAreRobustToBeingDrawnSlightlyDifferently() throws {
        // A reference solution that only works at exactly these coordinates is a fluke, and a
        // build gate resting on a fluke fails the first time a constant moves.
        let jitters = [Vec2(6, 0), Vec2(-6, 0), Vec2(0, 6), Vec2(0, -6)]
        for level in try loadLevels() {
            for reference in level.referenceSolutions {
                for offset in jitters {
                    let moved = reference.strokes.map {
                        RecordedStroke(points: $0.points.map { point in point + offset },
                                       committedAtStep: $0.committedAtStep,
                                       source: $0.source)
                    }
                    let result = simulator.run(level: level, strokes: moved)
                    XCTAssertTrue(result.didReachGoal,
                                  "\(level.id)/\(reference.id) fails when shifted by \(offset)")
                }
            }
        }
    }

    func testLevelGeometryStaysInsideTheScene() throws {
        for level in try loadLevels() {
            for movable in level.movables {
                switch movable.kind {
                case let .ball(centre, radius):
                    XCTAssertGreaterThan(centre.x - radius, 0, "\(level.id): \(movable.tag) starts in a wall")
                    XCTAssertLessThan(centre.x + radius, level.sceneSize.width)
                    XCTAssertLessThan(centre.y + radius, level.sceneSize.height)
                case let .crate(centre, size, _):
                    XCTAssertGreaterThan(centre.x - size.width / 2, 0)
                    XCTAssertLessThan(centre.x + size.width / 2, level.sceneSize.width)
                }
            }
        }
    }

    func testGoalRegionsAreReachablyInsideTheirCups() throws {
        // A goal region that overlaps a cup wall registers a ball resting on the rim as
        // "in the cup", which quietly makes several levels trivial.
        for level in try loadLevels() {
            let region: Rect
            switch level.goal {
            case let .ballInRegion(_, r, _): region = r
            case let .ballThroughGapThenRegion(_, _, r, _): region = r
            case let .allBallsInRegion(_, r, _): region = r
            }
            XCTAssertGreaterThan(region.size.width, 0)
            XCTAssertGreaterThan(region.size.height, 0)
            let cups = level.fixtures.compactMap { fixture -> (Vec2, Double, Double, Double)? in
                guard case let .cup(centre, width, height, thickness) = fixture.kind else { return nil }
                return (centre, width, height, thickness)
            }
            XCTAssertFalse(cups.isEmpty, "\(level.id) has a region goal but no cup")
            let matched = cups.contains { cup in
                let (centre, width, height, thickness) = cup
                let interior = Rect(x: centre.x - width / 2 + thickness,
                                    y: centre.y - height / 2 + thickness,
                                    width: width - thickness * 2,
                                    height: height * 2)
                return interior.contains(region.center)
            }
            XCTAssertTrue(matched, "\(level.id): the goal region is not inside any cup")
        }
    }
}
```

---

## 17. `Tools/LevelAuthor` — how the levels got made

Not in Part I's layout, and §8.5 is not achievable without it. Hand-guessing coordinates for
a reference solution does not work; you find out whether a ramp works by running it. Five
commands:

| Command | What it does |
|---|---|
| `generate <dir>` | Write the authored levels to JSON |
| `verify <dir>` | Decode the JSON and simulate every reference solution |
| `search <levelID>` | Brute-force candidate strokes, filter to robust ones, print the winner as pasteable JSON |
| `check <levelID> x0 y0 x1 y1` | Solve + robustness for one hand-chosen stroke |
| `probe <levelID> …` | Dump one run's trajectory — the tool you reach for when a level will not solve |
| `bench` | Piece counts before/after merging, and step cost, for `ENGINEERING.md` |

`search` refuses to return a knife-edge fluke: every candidate must also solve when shifted
6 units in each of four directions. That filter is why the reference solutions in §15 are
stable, and it is what caught the level that solved itself with no strokes.

Add as an executable target in the core package, or as a separate command-line target in the
Xcode project. It must never be linked into the app.

#### `Tools/LevelAuthor/AuthoredLevels.swift`

The authoring source of truth. Scene space is 750x1000, y-up, origin bottom-left — the same space strokes are recorded in, so a reference solution is literally a recording of someone playing.

```swift
import Foundation
import DrawPhysicsCore

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
```

#### `Tools/LevelAuthor/main.swift`

Note `isRobust`, and note that `search` checks the zero-stroke case before doing anything else.

```swift
import Foundation
import DrawPhysicsCore

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
```


---

## 18. MASTER PLAN — the remaining iOS layer

Everything above is written and verified. What is left is the **presentation layer**: the
SpriteKit renderer, the SwiftUI shell, persistence, feedback, and export. Thirteen files.

This section is written to be executed by an AI IDE with no further design decisions
required. It gives, for each file: the exact types to declare, the exact core APIs to call,
the behaviour, and the acceptance check. Where a trap exists, it is named.

### 18.0 Ground rules for this layer

1. **Never re-derive simulation state in the view layer.** The renderer reads
   `FixedStepWorld.bodies` and writes node transforms. It never moves a body, never
   integrates, never decides an outcome.
2. **`OutcomeJudge.evaluate` is called once per simulation step, never per frame.** Use
   `FixedStepWorld.advance(by:onStep:)`'s callback. Judging per frame breaks the dwell
   counter on a 60Hz device.
3. **Scene space is 750×1000, y-up, origin bottom-left.** SpriteKit is already y-up, so the
   only transform is a uniform scale plus a centring offset. Compute it once in
   `didChangeSize`.
4. **No numeric score, star, timer, attempt counter or streak may be rendered anywhere.**
   `NoScoreRenderedTests` (§18.14) greps the view layer for them.
5. **Nothing may leave the device except through the system share sheet, behind the gate.**

### 18.1 The core API this layer consumes

Complete surface. Nothing else is needed.

```swift
// Levels
let repository = LevelRepository()                       // Bundle.main, "Levels"
let levels: [LevelDefinition] = try repository.loadAll()  // throws LoadError with a fixable message

// Building a scene
let built = SceneBuilder.build(level: level)              // -> Built(world:ballBodies:)
built.world.advance(by: frameDelta) { step in /* per-step work */ }
built.world.stepIndex                                    // Int, the clock everything else uses
built.world.bodies                                       // [RigidBody] in stable insertion order
built.world.body(tagged: BodyTag("ball"))
built.world.discardAccumulatedTime()                     // call when pausing to draw
built.world.removeBody(id:)                              // undo

// A body, for rendering
body.id / body.tag.raw / body.position / body.rotation / body.shapes / body.motion
// Shape.Kind is .circle(center:radius:) or .polygon(vertices:) in LOCAL space
body.toWorld(_ local: Vec2) -> Vec2

// Committing a stroke
let pipeline = StrokePipeline()
switch pipeline.makeShape(id: nextID, rawPoints: points, source: .freehand, budget: budget) {
case let .accepted(shape, cost): budget.charge(cost); SceneBuilder.addDrawnShape(shape, to: world)
case let .rejected(reason):      /* .tooShort | .degenerate | .overBudget(cost:remaining:) | .strokeLimitReached */
}

// Ink
var budget = InkBudget(total: level.inkBudget)
budget.remaining / budget.fractionUsed / budget.canAfford(_:) / budget.charge(_:) / budget.refundLast()

// Goal
var judge = OutcomeJudge(goal: level.goal)
judge.evaluate(world: world, stepIndex: step)             // once per step
judge.didReachGoal / judge.stepReached

// Replay and export
let result = SolutionSimulator().run(level: level, strokes: strokes, captureEveryNthStep: 2)
result.frames                                            // [Frame(stepIndex:bodies:[BodySnapshot])]
let outcome = SolutionOutcome(simulated: result)          // immutable verdict
ReplayComparison(stored: outcome, replay: replayResult)   // .diverged, .childFacingNote
```

### 18.2 `DrawPhysics/Persistence/SolutionRecord.swift`

SwiftData model. The only persisted type.

```swift
@Model final class SolutionRecord {
    @Attribute(.unique) var id: UUID
    var levelID: String
    /// JSON-encoded `SolutionPayload`. Stored as Data rather than a relationship because a
    /// stroke list is opaque to queries and a versioned blob survives format changes.
    var payload: Data
    /// The authoritative verdict from the ORIGINAL run. `private(set)`-equivalent by
    /// convention plus the test in §18.14; SwiftData cannot express `let`.
    var didReachGoal: Bool
    var inkUsed: Double
    var strokeCount: Int
    var stepsToGoal: Int
    var createdAt: Date
}
```

Requirements:
- `init` takes a `SolutionPayload` and a `SolutionOutcome`, encodes the payload, and copies
  the outcome fields. No other initialiser.
- `func decodedPayload() throws -> SolutionPayload`.
- A `SolutionStore` helper with `save`, `records(forLevel:)` sorted newest-first, and
  `distinctSolutionCount(forLevel:)` — which counts records whose stroke **count** or whose
  rounded ink cost differs, since two children solving the same way should not read as two
  ideas.
- **Trap:** SwiftData has no immutable properties. Acceptance criterion 7 is therefore held
  by (a) `SolutionOutcome` being the only thing allowed to produce these values and (b) a
  test asserting no code path writes `didReachGoal` after init. Do not add a setter.

**Acceptance:** save a solved run, run a divergent replay, assert the stored record is
byte-identical afterwards.

### 18.3 `DrawPhysics/Game/GameSession.swift`

`@MainActor @Observable final class GameSession`. The one object the views read. Owns the
world, the budget, the recorder and the judge.

State:
```swift
enum Phase { case drawing, running, solved }
private(set) var phase: Phase
private(set) var world: FixedStepWorld
private(set) var budget: InkBudget
private(set) var committedShapes: [DrawnShape]          // for the renderer and undo
private(set) var recordedStrokes: [RecordedStroke]
private(set) var liveStroke: [Vec2]                     // in-progress, scene space
private(set) var rejection: StrokePipeline.Rejection?   // transient, for the HUD
private(set) var outcome: SolutionOutcome?
let level: LevelDefinition
```

Methods:
- `beginStroke(at:)`, `extendStroke(to:)`, `endStroke()` — `endStroke` runs the pipeline,
  charges the budget on success, appends to `committedShapes` and `recordedStrokes` with
  `committedAtStep: world.stepIndex`, calls `SceneBuilder.addDrawnShape`, and stores the
  drawn body id alongside the shape so undo can remove it.
- `undo()` — pops the last shape, `world.removeBody(id:)`, `budget.refundLast()`, pops the
  recorded stroke. Unlimited. Never disabled while a shape exists.
- `play()` — `phase = .running`, `world.discardAccumulatedTime()`.
- `advance(by frameDelta:)` — only when `.running`; calls `world.advance(by:onStep:)` and
  inside the callback calls `judge.evaluate`. On `didReachGoal`: `phase = .solved`, build the
  `SolutionOutcome`, fire haptic + chime, save the record.
- `resetKeepingStrokes()` — rebuilds the world from the level, re-adds every committed shape
  in order, resets the judge, `phase = .drawing`. **Strokes are kept.** This is §5.2 and it
  is the single most important behaviour in the game: nothing negative happens on a miss.
- `resetClearingStrokes()` — for a deliberate fresh start only, offered as a distinct button.

Traps:
- `drawWhileRunning` is per-level. When false, `beginStroke` must be ignored during
  `.running`. When true, a stroke committed mid-run records the real `stepIndex`, which is
  what makes the replay of a timed solution work.
- Re-adding shapes on reset must preserve order, or body ids shift and the replay diverges
  from the original run for no reason.

**Acceptance:** draw 3 strokes, undo 3 times, assert `budget.remaining == level.inkBudget`
and `world.bodies.count` equals the freshly-built count.

### 18.4 `DrawPhysics/Game/ShapeLibrary.swift`

Tap-to-place premade shapes. Acceptance criterion 15: a child who cannot draw freehand must
be able to solve a level with taps only.

```swift
struct LibraryShape: Identifiable {
    let id: String            // "ramp-left", "ramp-right", "block", "bowl", "post"
    let symbolName: String
    let spokenName: String
    /// Outline in shape-local space, converted to a stroke at the tap point.
    func points(at centre: Vec2, scale: Double) -> [Vec2]
}
```

- Five shapes minimum: left ramp, right ramp, block, bowl, post.
- Placing one produces a normal `RecordedStroke` with `source: .library(id)` and goes through
  the identical pipeline. It is not a special case in the simulation, and it costs ink on the
  same terms.
- Selecting a shape then tapping the scene places it. Long-press to rotate in 15° steps.

**Acceptance:** `ShapeLibrarySolvesALevelTests` — place library shapes only, no freehand
input, and reach the goal on `early-01-roll-it-in`.

### 18.5 `DrawPhysics/Views/PlayScene.swift`

`SKScene`. Renderer and touch source. **Contains no game logic.**

- `didMove(to:)`: build node hierarchy once. One `SKShapeNode` per fixture, per movable, per
  committed stroke. One `SKShapeNode` for the live stroke, its path rebuilt each frame.
- `update(_ currentTime:)`: compute `frameDelta` from the previous `currentTime` (clamp the
  first frame to zero), call `session.advance(by:)`, then sync every node's `position` and
  `zRotation` from its body. Look bodies up by id through a `[Int: SKNode]` map built at
  creation.
- Drawn strokes render from `shape.simplifiedPoints` — the ink the child sees, not the
  decomposed pieces. A debug toggle draws `convexPieces` in translucent outline; ship it
  behind the grown-up view because it is genuinely useful for a curious parent.
- Touches: `touchesBegan/Moved/Ended`. In `touchesMoved`, use
  `event?.coalescedTouches(for: touch)` and feed **every** coalesced point to
  `session.extendStroke`. On a 120Hz display a fast stroke delivers several touches per
  frame; taking only `touch.location(in:)` throws most of the stroke away and the child's
  curve arrives as a polygon.
- Convert points with a single `sceneToWorld` function derived in `didChangeSize`.

Traps:
- Set `scaleMode = .aspectFit` and do the coordinate maths once. Doing it per touch with a
  stale size is how strokes land offset from the finger.
- `SKShapeNode` path updates are the expensive part. Rebuild only the live stroke's path per
  frame; committed strokes get their path once.

**Acceptance:** on device, a drawn closed loop renders as a filled solid and an open line as
a thin barrier, and the ink follows the finger with no visible lag.

### 18.6 `DrawPhysics/Views/PlayView.swift`

SwiftUI host. `SpriteView(scene:)` plus HUD.

- Top: the goal, as an icon row plus a speak-again button. No sentence is required to
  understand it. Speak `level.spokenHint` on appear via `Instructor`.
- Bottom: ink meter (§18.7), undo, play/reset, shape-library toggle.
- Buttons are ≥ `MotorAccommodations.minimumTargetSize`, labelled with SF Symbols **and**
  accessibility labels.
- On `.solved`: a celebration overlay with two actions, "show someone" (opens the replay) and
  "try a different way" (`resetKeepingStrokes`). No stars, no score, no time.
- On a miss, there is no overlay at all. The scene resets and the strokes stay. Do not add a
  "you failed" state; its absence is the design.
- Rejection feedback: when `session.rejection` is `.overBudget`, flash the ink meter and
  speak "That one needs more ink than you have left." Never silently ignore a stroke.

**Acceptance:** `FTUETimingTests` — cold launch to first goal in under 30s with no text read,
driving only taps on symbol-labelled controls.

### 18.7 `DrawPhysics/Views/InkMeterView.swift`

- A bar plus a number-free fill. Reads `budget.fractionUsed`.
- Colour is not the only channel: the bar also shrinks, and at >85% it gains a hatch pattern.
- Accessibility value in words, not a percentage: "plenty of ink", "about half", "nearly out".

### 18.8 `DrawPhysics/Views/HomeView.swift`

The hub. The child chooses; nothing is locked.

- Band picker using `AgeBand.childFacingName` — "Starting Out", "Getting Good", "Tricky".
  Never the age range.
- Level list with a small thumbnail rendered by `SceneRenderer` (§18.10) at step 0, and a
  "solved it N ways" caption where N ≥ 1.
- Gallery entry point, grown-up entry point (gated).
- On `LevelRepository.LoadError`, show the error's `description` verbatim. It names the fix.

### 18.9 `DrawPhysics/Views/ReplayView.swift` + `ReplayScene.swift`

- Runs `SolutionSimulator.run(level:strokes:captureEveryNthStep: 2)` off the main actor, then
  plays the captured frames back at 60fps.
- Frame playback rather than live re-simulation, so scrubbing and export are trivial and the
  replay cannot be affected by device load.
- Shows `ReplayComparison.childFacingNote` when it diverges — "The ball went a bit
  differently this time." The solved mark does not change, ever.
- Export button, behind `ParentGateView`.

### 18.10 `DrawPhysics/Render/SceneRenderer.swift`

Pure Core Graphics rendering of a world state into a `CGContext`. Used by level thumbnails
and by the video exporter, so neither depends on SpriteKit or a live view.

```swift
struct SceneRenderer {
    let sceneSize: Size
    let pixelSize: CGSize
    func draw(bodies: [SolutionSimulator.BodySnapshot], shapes: [DrawnShape],
              level: LevelDefinition, into context: CGContext)
}
```

**Trap:** `BodySnapshot` carries position and rotation but not geometry. Build a
`[Int: [Shape]]` map once from the world used to produce the frames, and pass it in. Do not
try to reconstruct colliders from the snapshot.

### 18.11 `DrawPhysics/Export/ReplayVideoExporter.swift`

`AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`, H.264, 750×1000 at 60fps.

- Renders frames with `SceneRenderer` into a `CVPixelBuffer` via a `CGContext` backed by the
  buffer's base address. No SpriteKit, no `SKView.texture(from:)`, so it works with no view
  on screen.
- Writes to a temp URL, hands the URL to the system share sheet, deletes on dismissal.
- Behind the parental gate. The gate is checked immediately before export, not remembered.
- Progress reported so a 10-second replay does not look frozen.

**Trap:** `CVPixelBufferLockBaseAddress` before drawing and unlock after, and use
`kCVPixelFormatType_32BGRA` with `CGImageAlphaInfo.noneSkipFirst` plus
`CGBitmapInfo.byteOrder32Little`. Getting the byte order wrong yields a blue-tinted video.

### 18.12 `DrawPhysics/Feedback/SoundBank.swift` and `HapticEngine.swift`

`SoundBank`: `AVAudioEngine` with a player node, buffers synthesised in code — no asset
files.
- Draw: filtered noise burst, gain following stroke speed.
- Contact: short sine thud, pitch from impact impulse magnitude.
- Goal: a rising perfect fifth, pentatonic so it never sounds sour.
- `AVAudioSession` category `.ambient` with `mixWithOthers`, so the game never stops the
  music a family has playing.

`HapticEngine`: `CHHapticEngine`, guarded by `CHHapticEngine.capabilitiesForHardware()`.
- Continuous low-intensity texture while drawing, ending on stroke commit.
- Transient on each contact above a threshold, ignoring the resting-contact stream.
- Distinct pattern on goal.
- **Trap:** the engine stops when the app backgrounds. Handle
  `resetHandler`/`stoppedHandler` and restart lazily, or haptics silently die after the first
  app switch.

### 18.13 `DrawPhysics/Progress/DrawPhysicsProgress.swift`

Turns records into `CapabilityStatement`s. Statements about **invention**, never efficiency.

Required statements, each with its evidence rule:
| Statement | Evidence | Minimum |
|---|---|---|
| "You solved that level N different ways." | distinct solutions for one level | 2 |
| "You used only N strokes." | minimum stroke count across solutions | 1 solution with ≤ 2 strokes |
| "You've found N ideas across M levels." | total distinct solutions | 3 |
| "You solved one with hardly any ink." | a solution under 40% of budget | 1 |

Anything not expressible as a true, checkable sentence about something the child did is not
shown. No rating, no "creativity" measure, no comparison, no percentage.

### 18.14 `DrawPhysics/App/DrawPhysicsApp.swift` and the remaining tests

App entry: `ModelContainer(for: SolutionRecord.self)`, `Instructor` and `MotorAccommodations`
in the environment, `HomeView` as root.

`Info.plist`: no `NSMicrophoneUsageDescription`, no photo library keys, no location keys.
The app needs none of them, and asking is a Kids Category review problem.
`PrivacyInfo.xcprivacy` declares no tracking and no collected data types.

Remaining test files:
- `DrawPhysicsUITests/FTUETimingTests.swift` — `testFirstSuccessUnderThirtySecondsWithoutReading`.
  Drive only elements with accessibility identifiers; fail if elapsed > 30s.
- `DrawPhysicsUITests/AccessibilityAuditTests.swift` — `performAccessibilityAudit()` on home,
  play, gallery and grown-up views; zero issues.
- `DrawPhysicsTests/NoScoreRenderedTests.swift` — source-level scan of the view layer for
  `star`, `score`, `points`, `streak`, `timer`, `attempts`. Fails on a match outside a
  comment. Crude and effective: this is the rule most likely to be broken by a
  well-meaning future change.
- `DrawPhysicsTests/GameSessionTests.swift` — undo refund, stroke-preserving reset, and that
  `drawWhileRunning == false` ignores strokes during `.running`.
- `DrawPhysicsTests/ShapeLibraryTests.swift` — a level is solvable with library taps only.

### 18.15 Build order for this layer

1. `SolutionRecord` + `SolutionStore`, with the immutability test. — persistence first, so
   nothing built later needs rewiring.
2. `GameSession` + `GameSessionTests`. Fully testable with no view; get undo and
   stroke-preserving reset right here, where they are easy to assert.
3. `PlayScene` + `PlayView`. First playable build. Stop and play it.
4. `SceneRenderer`, then `HomeView` thumbnails.
5. `ReplayView`, then `DrawPhysicsProgress`.
6. `SoundBank` + `HapticEngine`. Feel work, and it needs a device.
7. `ShapeLibrary` + its test.
8. `ReplayVideoExporter` behind the gate.
9. `FTUETimingTests`, `AccessibilityAuditTests`, `NoScoreRenderedTests`.
10. On-device manual pass, Part I §9's numbered list. Items 1–4 and 8 are already covered by
    unit tests; the rest genuinely require a device.

### 18.16 `ENGINEERING.md` — what is already measurable

§19 below fills most of §8.6. Still to measure, and it needs a device:
- Frame times at the maximum expected collider count on the oldest supported device.
- FTUE timing from cold launch.
- Haptic and audio latency, if the game's feel turns out to depend on it.
- Confirmation that the on-device numbers match the host-machine numbers in §19.2 within a
  stated factor.

---

## 19. Verification ledger

What has actually been run, and what has not. Nothing in this section is estimated.

### 19.1 Level integrity — measured

`LevelAuthor verify`, run against the shipped JSON:

```
PASS early-01-roll-it-in/early-01-ref-long-ramp        goal=true steps=265/1800 ink=636/2200
PASS early-01-roll-it-in/early-01-ref-shallow-ramp     goal=true steps=278/1800 ink=561/2200
PASS early-02-over-the-bump/early-02-ref-over-ramp     goal=true steps=255/1800 ink=608/2200
PASS early-02-over-the-bump/early-02-ref-short-launch  goal=true steps=260/1800 ink=382/2200
PASS middle-01-through-the-gap/middle-01-ref-feed-the-gap  goal=true steps=392/1800 ink=286/1200
PASS middle-02-the-seesaw/middle-02-ref-load-the-plank goal=true steps=273/1800 ink=304/1200
PASS middle-02-the-seesaw/middle-02-ref-flatter-feed   goal=true steps=270/1800 ink=341/1200
PASS upper-01-two-strokes/upper-01-ref-over-the-wall   goal=true steps=416/1800 ink=335/700
PASS upper-01-two-strokes/upper-01-ref-lower-launch    goal=true steps=447/1800 ink=335/700
PASS upper-02-moving-shelf/upper-02-ref-timed-drop     goal=true steps=424/1800 ink=326/800
PASS upper-02-moving-shelf/upper-02-ref-lower-feed     goal=true steps=436/1800 ink=318/800
all reference solutions pass
```

Eleven reference solutions, six levels, every band. All within budget with headroom; the
tightest is `upper-01` at 335 of 700. Zero-stroke check: all six fail to solve themselves.
Robustness check: all eleven still solve when shifted 6 units in each of four directions.

### 19.2 Decomposition and simulation cost — measured

`LevelAuthor bench`, release build, Apple Silicon host:

```
shape           rawPts  simplified  triangles  merged  reduction
circle-blob        220          16         14       1     14.00x
scoop              182          10          8       2      4.00x
star                10          10          8       5      1.60x
comb                28          26         14       7      2.00x

bodies=21 shapes=117  12000 steps in 0.170s  =>  70,498 steps/s, 0.0142 ms/step
budget at 120Hz is 8.333 ms/frame; simulation uses 0.17% of it
```

The blob is the headline: 220 raw points to 16 vertices to 14 triangles to **one** convex
collider. The star's 1.6× is the honest other end — a shape with five reflex vertices cannot
merge much, and that is the case to quote when someone asks what the technique does not do.

Worst case tested is 21 bodies and 117 colliders, which is more than the ink budget allows a
child to build. **Caveat, stated plainly:** this is a host-machine number. It says the
algorithm is not the bottleneck; it does not say the game holds 120fps on an iPhone, because
rendering is not included and the CPU is different. §18.16 lists the device measurements
still owed.

### 19.3 Tests — run, passing

`swift test`: **40 tests, 0 failures, 1.5s.**

| File | Tests | Covers |
|---|---|---|
| `ConvexDecomposerTests` | 8 | convexity, winding from both input windings, union area, sliver removal, merge reduction, termination on pathological input |
| `StrokeSimplifierTests` | 8 | self-intersection repair, closure classification, shape preservation, chain quads, tap rejection, determinism |
| `FixedStepWorldTests` | 7 | run-to-run determinism (exact equality), frame-rate independence across 120/60/30/jittery, immutable stored outcome, resting stability, tunnelling, stall clamp, see-saw pin |
| `InkMeterTests` | 8 | blob excluded in every band, exact undo refund, 200-cycle leak test, ramp still affordable, area charge |
| `LevelIntegrityTests` | 9 | all reference solutions solve within budget and stroke limit, no level self-solves, robustness, geometry bounds, goal regions inside cups |

All named invariants from Part I §9 exist and pass, under the names Part I specified.

### 19.4 Compilation — verified

- Core package: `swift build` clean, zero warnings, Swift 5 language mode.
- iOS: every file in §13 and §14 typechecked against the iPhoneSimulator SDK with
  `-target arm64-apple-ios17.0-simulator`, zero errors, zero warnings.
- Cross-compiling the *package* to iOS via `swift build -Xswiftc -sdk` does **not** work —
  SwiftPM keeps the macOS sysroot and `import UIKit` fails. Use a flat
  `xcrun -sdk iphonesimulator swiftc -typecheck` for a quick check, or the Xcode project for
  the real build.

### 19.5 Not yet verified

Stated so it cannot be mistaken for done:

| Item | Status |
|---|---|
| §18's thirteen presentation files | **Not written.** Specified to file-and-signature level, not implemented. |
| On-device frame rate | Not measured. §19.2 is a host number and excludes rendering. |
| FTUE under 30s | Not measured. Test not written. |
| Accessibility audit | Not run. Only the menus could be audited today; there are no menus yet. |
| Physics *feel* | Not assessed. Stability is proven by test; whether a drawn ramp feels good is a device judgement and Part I §9's manual list is the right instrument. |
| Video export | Not written. |
| Cross-device replay divergence | Not observed, by design — the architecture makes it harmless rather than measuring it. One device class is not a test of cross-device behaviour. |

### 19.6 Resume framing, with the brackets filled

Part I asked for measured numbers rather than guesses. These are measured:

> Built an open-ended children's physics-drawing game with a freehand-stroke-to-rigid-body
> pipeline — RDP simplification, self-intersection repair, and convex decomposition with
> Hertel-Mehlhorn triangle merging that cut a drawn blob from 14 colliders to 1 — plus a
> hand-written fixed-timestep 2D solver (SAT + face clipping, split-impulse position
> correction) after establishing that SpriteKit exposes no way to step its physics world
> deterministically. 40 invariant tests, including exact-equality determinism across forced
> frame-rate changes, and a build gate that simulates every hand-authored level's reference
> solution so a level cannot ship unsolvable.

The sentence to be careful with is the frame rate one: **do not claim an fps figure until it
is measured on a device.** The collider-count reduction and the step cost are real; the
rendering cost is not yet known.

