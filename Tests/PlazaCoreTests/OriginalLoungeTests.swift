import XCTest
@testable import PlazaCore

final class OriginalLoungeTests: XCTestCase {
    func testOriginalSeedAndRandomTrace() {
        var random = OriginalLoungeRandom(seed: 1234)
        XCTAssertEqual(random.words, [3159640283, 4062961311, 3954462607, 3112783424])
        XCTAssertEqual((0..<4).map { _ in random.next() }, [2810567482, 200685171, 1115146421, 2977920501])
    }

    func testEveryOriginalActionMask() {
        for mask in 0..<4096 {
            var bytes: [UInt8] = []
            for index in 0..<12 {
                let expected = UInt8(index < 9 ? index + 49 : index + 56)
                bytes.append(mask & (1 << index) == 0 ? 32 : expected)
            }
            XCTAssertEqual(OriginalLounge.actionMask(bytes), UInt16(mask))
        }
        XCTAssertEqual(OriginalLounge.actionMask(Array("123\0".utf8) + Array("56789ABC".utf8)), 7)
        XCTAssertEqual(OriginalLounge.actionMask(Array("ABC123456789".utf8)), 0)
    }

    func testOriginalInterruptsRespectSeatedExitAndBlendLimits() throws {
        let standing = try XCTUnwrap(OriginalLounge.transition(from: 110, to: 3, previousHasExit: true, nextHasEntrance: false, blendOverride: 60))
        XCTAssertEqual(standing.stage, .main)
        XCTAssertEqual(standing.blendFrames, 10)
        XCTAssertTrue(standing.interrupts)
        let seated = try XCTUnwrap(OriginalLounge.transition(from: 34, to: 3, previousHasExit: true, nextHasEntrance: false))
        XCTAssertEqual(seated.stage, .exit)
        let limited = try XCTUnwrap(OriginalLounge.transition(from: 46, to: 110, previousHasExit: true, nextHasEntrance: true))
        XCTAssertEqual(limited.blendFrames, 10)
        let minimum = try XCTUnwrap(OriginalLounge.transition(from: 112, to: 111, previousHasExit: false, nextHasEntrance: false))
        XCTAssertEqual(minimum.blendFrames, 40)
        XCTAssertNil(OriginalLounge.transition(from: -1, to: 3, previousHasExit: false, nextHasEntrance: false))
    }

    func testOriginalBoundaryAndQueueGuards() {
        XCTAssertFalse(OriginalLounge.crossesBoundary(frame: 30, frameOffset: 1, step: 1, length: 40))
        XCTAssertTrue(OriginalLounge.crossesBoundary(frame: 39, frameOffset: 1, step: 1, length: 40))
        XCTAssertFalse(OriginalLounge.mayChangeAnimation(current: 0, requested: 3, stage: .entrance,
            blendWeight: 1, flags: 0, frame: 0, frameOffset: 0, step: 1, length: 40))
        XCTAssertFalse(OriginalLounge.mayChangeAnimation(current: 0, requested: 3, stage: .main,
            blendWeight: 1, queuedA: 110, flags: 0, frame: 0, frameOffset: 0, step: 1, length: 40))
        XCTAssertTrue(OriginalLounge.mayChangeAnimation(current: 0, requested: 3, stage: .main,
            blendWeight: 1, flags: 4, frame: 39, frameOffset: 1, step: 1, length: 40))
    }

    func testOriginalDescriptorAndHoldingRules() {
        XCTAssertEqual(OriginalLounge.animations.count, 128)
        XCTAssertEqual(OriginalLounge.animations[3].name, "Walk00_l")
        XCTAssertEqual(OriginalLounge.animations[112].name, "Talk00_l")
        var seated = OriginalLoungeRandom(seed: 1234)
        var reference = seated
        _ = reference.next() // Ordinary draw precedes the seated replacement.
        let expected = Int((UInt64(reference.next()) * 1200) >> 32) + 1200
        XCTAssertEqual(OriginalLounge.holdTicks(animation: 34, random: &seated), expected)
        XCTAssertEqual(seated, reference)
        var last = 10
        for _ in 0..<1000 {
            let next = OriginalLounge.standingIdle(after: last, random: &seated)
            XCTAssertTrue((10...25).contains(next))
            XCTAssertNotEqual(next, last)
            last = next
        }
    }

    /// Fixtures are obtained by executing the isolated original instructions,
    /// not by calling the Swift implementation or duplicating its formulas.
    func testParityWithOriginalPowerPCInstructions() throws {
        guard let path = ProcessInfo.processInfo.environment["PLAZA_ORIGINAL_LOGIC_QA"] else {
            throw XCTSkip("Set PLAZA_ORIGINAL_LOGIC_QA to recover-lounge.py's local fixture JSON")
        }
        struct RandomTrace: Decodable { let seed: UInt32; let words: [UInt32]; let values: [UInt32] }
        struct Vectors: Decodable {
            let version: Int; let sha256: String; let random: [RandomTrace]
            let masks: [UInt16]; let restrictions: [[Int64]]; let transitions: [[Double]]
            let idleSelections: [[Int64]]; let socialSelections: [[Int64]]; let socialTimings: [[Double]]
            let headings: [[Double]]
        }
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(vectors.version, 1)
        XCTAssertEqual(vectors.sha256, "b67deb8fb36889fd5451b89a5b1ce06b31abe341960c3bf1df84e9df4bbe1474")
        XCTAssertEqual(vectors.transitions.count, 65536)
        XCTAssertEqual(vectors.restrictions.count, 7168)
        XCTAssertEqual(vectors.headings.count, 1701)
        for row in vectors.headings {
            var heading = OriginalLoungeHeading(angle: Float(row[0]), lean: Float(row[4]), accumulatedDegrees: Float(row[5]))
            heading.step(toward: Float(row[1]), gain: Float(row[2]), limit: Float(row[3]))
            XCTAssertEqual([heading.angle, heading.delta, heading.lean, heading.accumulatedDegrees], row[6..<10].map(Float.init), "Original heading inputs: \(row)")
        }
        for trace in vectors.random {
            var random = OriginalLoungeRandom(seed: trace.seed)
            XCTAssertEqual(random.words, trace.words)
            XCTAssertEqual(trace.values.map { _ in random.next() }, trace.values)
        }
        XCTAssertEqual(vectors.masks, Array(0..<4096).map(UInt16.init))
        for row in vectors.restrictions {
            var input = OriginalLounge.RestrictionInput()
            input.forcedAnimation = Int32(row[0]); input.flag288 = row[1] != 0; input.flag289 = row[2] != 0
            input.movementState = Int32(row[3]); input.has3b4 = row[4] != 0; input.has3a0 = row[5] != 0
            input.animationFlags = UInt32(row[6]); input.animationID = Int32(row[7]); input.category = Int32(row[8])
            XCTAssertEqual(OriginalLounge.restrictions(input), UInt32(row[9]), "Original flag inputs: \(row)")
        }
        XCTAssertEqual(vectors.idleSelections.count, 2400)
        for row in vectors.idleSelections {
            var random = OriginalLoungeRandom(seed: UInt32(row[0]))
            var input = OriginalLounge.IdleContext()
            input.current = Int(row[1]); input.idleTicks = Int(row[2]); input.groupDensity = Int(row[3])
            input.preventsLyingDown = row[4] != 0; input.groupActivity = row[5] == 128 ? nil : Int(row[5])
            input.disablesGroupActivities = row[6] != 0
            let selected = OriginalLounge.selectIdle(input, random: &random)
            XCTAssertEqual([selected.baseline, selected.intermediate, selected.intermediateTicks, selected.followup], row[7..<11].map(Int.init), "Original idle inputs: \(row)")
            XCTAssertEqual(random.words, row[11..<15].map(UInt32.init), "Original idle draw order: \(row)")
        }
        XCTAssertEqual(vectors.socialSelections.count, 12000)
        for row in vectors.socialSelections {
            var random = OriginalLoungeRandom(seed: UInt32(row[0]))
            XCTAssertEqual(OriginalLounge.nextSocialAction(after: Int(row[1]), random: &random) ?? 25, Int(row[2]), "Original social inputs: \(row)")
            XCTAssertEqual(random.words, row[3..<7].map(UInt32.init), "Original social draw order: \(row)")
        }
        let names = Set(OriginalLounge.animations.map(\.name))
        let catalog = try XCTUnwrap(OriginalLoungeCatalog(clips: names.sorted().map {
            .init(name: $0, frames: $0.hasSuffix("_l") ? 40 : 12, loop: $0.hasSuffix("_l"))
        }))
        XCTAssertEqual(vectors.socialTimings.count, 1000)
        for row in vectors.socialTimings {
            var random = OriginalLoungeRandom(seed: UInt32(row[0]))
            let transition = try XCTUnwrap(OriginalLounge.socialTransition(action: Int(row[1]), catalog: catalog, random: &random))
            XCTAssertEqual(transition.partnerAction, Int(row[2]), "Original social timer inputs: \(row)")
            XCTAssertEqual(transition.durationTicks, Int(row[3]), "Original social timer inputs: \(row)")
            XCTAssertEqual(transition.rate, Float(row[4]), "Original social rate inputs: \(row)")
            XCTAssertEqual(random.words, row[5..<9].map(UInt32.init), "Original social timing draw order: \(row)")
        }
        for row in vectors.transitions {
            let plan = try XCTUnwrap(OriginalLounge.transition(from: Int(row[0]), to: Int(row[1]),
                previousHasExit: row[2] != 0, nextHasEntrance: row[3] != 0, blendOverride: Float(row[4])))
            XCTAssertEqual(plan.stage.rawValue, Int(row[5]), "Original transition inputs: \(row)")
            XCTAssertEqual(plan.blendFrames, Float(row[6]), "Original transition inputs: \(row)")
        }
    }
}
