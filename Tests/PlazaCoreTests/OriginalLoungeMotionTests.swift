import XCTest
@testable import PlazaCore

final class OriginalLoungeMotionTests: XCTestCase {
    func testCollisionMemoryDampingAndImmovableActors() {
        var collision = OriginalLoungeCollision()
        collision.previous = .init(6,-3)
        let (push,opposed) = collision.contact(.init(-4,4),direction:.init(1,0),neighborDelta:.init(10,0))
        XCTAssertEqual(push,.init(0,0))
        XCTAssertTrue(opposed,"Opposition is evaluated before the anti-oscillation filter")
        collision.impulse = .init(2,-1)
        XCTAssertEqual(collision.integrate(.init(5,6),opposed:true,forward:.init(0,1),blocked:true),.init(0,0))
        XCTAssertEqual(collision.impulse.x,2*0.92,accuracy:1e-6)
        XCTAssertEqual(collision.speedScale,1)
    }
    func testWalkingRampsAndSlowsAtDestinationWithoutStrideDrivenSpeed() {
        var motion = OriginalLoungeMotion()
        for _ in 0..<600 { motion.walk(toward:.init(0,200),forward:.init(0,1)) }
        XCTAssertEqual(motion.speed,0.25,accuracy:1e-5)
        XCTAssertEqual(motion.ramp,1)
        for _ in 0..<600 { motion.walk(toward:.init(0,10),forward:.init(0,1)) }
        XCTAssertEqual(motion.speed,0.17,accuracy:1e-5)
        XCTAssertEqual(OriginalLounge.walkStopRadius(frame:6,length:40),2)
        XCTAssertEqual(OriginalLounge.walkStopRadius(frame:16,length:40),6)
    }
    func testGroupSlotsScanCyclicallyAndConsumeOneDrawEvenWhenEmpty() {
        var a = OriginalLoungeRandom(seed:12), b = a
        XCTAssertNil(OriginalLounge.groupNeighbor(slots:[],random:&a))
        _ = b.below(6); XCTAssertEqual(a,b)
        for mask: UInt32 in [0x1c,0xe,7,0x23,0x31,0x38] {
            let slots: [Int?] = (0..<6).map { $0 }
            for seed: UInt32 in 0..<100 {
                var random = OriginalLoungeRandom(seed:seed)
                let selected = OriginalLounge.groupNeighbor(slots:slots,mask:mask,random:&random)!
                XCTAssertNotEqual(mask & (1<<selected),0)
            }
        }
        XCTAssertEqual(OriginalLounge.groupDirectionMask(.init(0,1)),0x1c)
        XCTAssertEqual(OriginalLounge.groupDirectionMask(.init(1,0)),0xe)
    }
    func testMotionAndGroupsAgainstOriginalInstructions() throws {
        guard let path = ProcessInfo.processInfo.environment["PLAZA_ORIGINAL_LOGIC_QA"] else { throw XCTSkip("Set PLAZA_ORIGINAL_LOGIC_QA to local instruction fixtures") }
        struct Vectors: Decodable {
            let walks, contacts, collisionIntegration, groupSlots, groupGates, groupTurns, groupDirections, walkStops, groupFacing: [[Double]]
        }
        let vectors = try JSONDecoder().decode(Vectors.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
        XCTAssertEqual(vectors.walks.count,567);XCTAssertEqual(vectors.contacts.count,100)
        XCTAssertEqual(vectors.collisionIntegration.count,128);XCTAssertEqual(vectors.groupSlots.count,1800)
        XCTAssertEqual(vectors.groupGates.count,1600);XCTAssertEqual(vectors.groupTurns.count,1200)
        XCTAssertEqual(vectors.groupDirections.count,721);XCTAssertEqual(vectors.walkStops.count,132);XCTAssertEqual(vectors.groupFacing.count,420)
        for row in vectors.groupDirections {
            XCTAssertEqual(OriginalLounge.groupDirectionMask(.init(Float(row[0]),Float(row[1]))),UInt32(row[2]))
        }
        for row in vectors.walkStops {
            XCTAssertEqual(OriginalLounge.walkStopRadius(frame:row[2] == 2 ? Float(row[1]):0,length:Float(row[0])),Float(row[3]),accuracy:1e-6)
        }
        for row in vectors.groupFacing {
            var input=OriginalLounge.PartnerInput(position:.init(5,7),forward:.init(0,1),animation:Int(row[0]))
            input.hasWatchTarget=row[1] != 0;input.hasPartner=row[2] != 0;input.restrictions=UInt32(row[3]);input.socialTicks=Int(row[4])
            XCTAssertEqual(OriginalLounge.acceptsGroupFacing(input,at:.init(Float(row[5]),Float(row[6]))),row[7] != 0)
        }
        for row in vectors.walks {
            let v = row.map(Float.init)
            var motion = OriginalLoungeMotion();motion.direction = .init(v[2],v[3]);motion.ramp=v[10];motion.speed=v[11]
            motion.walk(toward:.init(v[0],v[1]),forward:.init(v[4],v[5]),height:v[6],urgency:v[7],special:v[8] != 0,turnFactor:v[9])
            for (actual,expected) in zip([motion.speed,motion.direction.x,motion.direction.z,motion.ramp],v[12..<16]) {
                XCTAssertEqual(actual,expected,accuracy:2e-6,"Source walking input: \(row)")
            }
        }
        for row in vectors.contacts {
            let v = row.map(Float.init)
            var collision = OriginalLoungeCollision();collision.previous = .init(v[2],v[3]);collision.impulse = .init(v[10],v[11])
            let (push,opposed) = collision.contact(.init(v[0],v[1]),direction:.init(v[8],v[9]),neighborDelta:.init(v[4],v[5]),relativeMovement:.init(v[6],v[7]),neighborMovable:false)
            for (actual,expected) in zip([push.x,push.z,collision.impulse.x,collision.impulse.z],v[12..<16]) {
                XCTAssertEqual(actual,expected,accuracy:2e-6,"Source collision input: \(row)")
            }
            XCTAssertEqual(opposed,v[16] != 0)
            if v.count>=19 {
                XCTAssertEqual(collision.reactionDelta?.x ?? .nan,v[17],accuracy:2e-6)
                XCTAssertEqual(collision.reactionDelta?.z ?? .nan,v[18],accuracy:2e-6)
            }
        }
        for row in vectors.collisionIntegration {
            let v = row.map(Float.init)
            var collision = OriginalLoungeCollision();collision.impulse = .init(v[2],v[3]);collision.previous = .init(v[4],-v[4]);collision.speedScale=v[8];collision.gait=v[9]
            let push = collision.integrate(.init(v[0],v[1]),opposed:v[5] != 0,forward:.init(v[10],v[11]),stature:v[12],urgency:v[7],special:v[6] != 0)
            for (actual,expected) in zip([5+push.x,7+push.z,collision.impulse.x,collision.impulse.z,collision.gait,collision.speedScale,collision.previous.x,collision.previous.z],v[13..<21]) {
                XCTAssertEqual(actual,expected,accuracy:1e-6,"Source integration input: \(row)")
            }
        }
        for row in vectors.groupSlots {
            var random = OriginalLoungeRandom(seed:UInt32(row[0]))
            let slots: [Int?] = (0..<6).map { Int(row[2]) & (1<<$0) != 0 ? $0+1:nil }
            XCTAssertEqual(OriginalLounge.groupNeighbor(slots:slots,mask:UInt32(row[1]),random:&random) ?? 0,Int(row[3]))
            XCTAssertEqual(random.words,row[4..<8].map(UInt32.init))
        }
        for row in vectors.groupGates {
            var random = OriginalLoungeRandom(seed:UInt32(row[0]))
            XCTAssertEqual(OriginalLounge.automaticDanceGate(population:Int(row[1]),random:&random),row[2] != 0)
            XCTAssertEqual(random.words,row[3..<7].map(UInt32.init))
        }
        for row in vectors.groupTurns {
            var random = OriginalLoungeRandom(seed:UInt32(row[0]))
            XCTAssertEqual(OriginalLounge.groupTurn(forward:.init(Float(row[1]),Float(row[2])),random:&random),Float(row[3]),accuracy:1e-5)
            XCTAssertEqual(random.words,row[4..<8].map(UInt32.init))
        }
    }
}
