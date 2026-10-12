import XCTest
@testable import PlazaCore

final class OriginalLoungeSpatialTests: XCTestCase {
    func testPartnerChecksUseStrictDistanceMutualFacingAndSourceEligibility() {
        var a = OriginalLounge.PartnerInput(position: .init(0,0), forward: .init(0,1), animation: 10)
        var b = OriginalLounge.PartnerInput(position: .init(0,17), forward: .init(0,-1), animation: 25)
        XCTAssertTrue(OriginalLounge.acceptsPartner(a, at: b.position))
        XCTAssertTrue(OriginalLounge.acceptsPartner(b, at: a.position))
        b.forward = .init(0,1)
        XCTAssertFalse(OriginalLounge.acceptsPartner(b, at: a.position))
        XCTAssertFalse(OriginalLounge.acceptsPartner(a, at: .init(0,18)))
        XCTAssertFalse(OriginalLounge.acceptsPartner(a, at: .init(0,0)))
        a.socialTicks = -1
        XCTAssertFalse(OriginalLounge.acceptsPartner(a, at: b.position))
        a.socialTicks = 0; a.hasWatchTarget = true
        XCTAssertFalse(OriginalLounge.acceptsPartner(a, at: b.position))
    }
    func testDanceCorrectionHasOriginalPhasePulseSpacingAndOppositeTangents() throws {
        let position = OriginalLounge.GroundPoint(0,0), partner = OriginalLounge.GroundPoint(0,20)
        let start = try XCTUnwrap(OriginalLounge.dancePosition(action:11,position:position,partner:partner,mainFrame:0,length:40))
        XCTAssertEqual(start.position,position); XCTAssertEqual(start.headingGain,0)
        let peak = try XCTUnwrap(OriginalLounge.dancePosition(action:11,position:position,partner:partner,mainFrame:30,length:40))
        XCTAssertEqual(peak.position.z,sqrt(11)*0.01,accuracy:1e-6)
        XCTAssertEqual(peak.headingGain,0.1)
        let reverse = try XCTUnwrap(OriginalLounge.dancePosition(action:12,position:position,partner:partner,mainFrame:30,length:40))
        XCTAssertEqual(peak.tangent.x,-reverse.tangent.x)
        let tight = try XCTUnwrap(OriginalLounge.dancePosition(action:13,position:position,partner:.init(0,9),mainFrame:30,length:40))
        XCTAssertLessThan(tight.position.z,0,"Actions 13/14 keep eleven source units between partners")
        XCTAssertEqual(OriginalLounge.pairedRate(frame:6,partnerFrame:0,length:40),1)
        XCTAssertEqual(OriginalLounge.pairedRate(frame:7,partnerFrame:0,length:40),0.7)
        XCTAssertEqual(OriginalLounge.pairedRate(frame:20,partnerFrame:0,length:40),1)
        XCTAssertEqual(OriginalLounge.pairedRate(frame:1,partnerFrame:30,length:40),0.7)
    }
    func testNavigationIsDeterministicBoundedAndSpecialRolesUseOriginalEllipse() throws {
        for seed in 0..<100 {
            var a = OriginalLoungeRandom(seed:UInt32(seed)), b = a
            let point = try XCTUnwrap(OriginalLounge.destination(from:.init(0,0),role:1,halfWidth:432,halfDepth:288,obstacles:[],random:&a))
            XCTAssertLessThanOrEqual(pow(point.x/150,2)+pow((point.z-20)/130,2),1.000001)
            XCTAssertEqual(point,OriginalLounge.destination(from:.init(0,0),role:1,halfWidth:432,halfDepth:288,obstacles:[],random:&b))
            XCTAssertEqual(a,b)
        }
        var random = OriginalLoungeRandom(seed:1234)
        let dense = (0..<11).map { i in OriginalLounge.NavigationObstacle(center:.init(Float(i),Float(i)),radius:10000) }
        let result = OriginalLounge.destination(from:.init(100,100),role:0,halfWidth:432,halfDepth:288,obstacles:dense,random:&random)
        XCTAssertTrue(result == nil || (result!.x.isFinite && result!.z.isFinite))
    }
    func testOverlapUsesExtremaRatherThanAddingEveryNeighbor() {
        let one = OriginalLounge.NavigationObstacle(center:.init(10,0),radius:8)
        let a = OriginalLounge.separation(position:.init(0,0),radius:8,neighbors:[one])
        let b = OriginalLounge.separation(position:.init(0,0),radius:8,neighbors:[one,one,one])
        XCTAssertEqual(a,b); XCTAssertEqual(a.x,-6,accuracy:1e-6)
        let balanced = OriginalLounge.separation(position:.init(0,0),radius:8,neighbors:[one,.init(center:.init(-10,0),radius:8)])
        XCTAssertEqual(balanced,.init(0,0))
        XCTAssertEqual(OriginalLounge.separation(position:.init(0,0),radius:8,neighbors:[.init(center:.init(0,0),radius:8)]),.init(0,16))
    }
    func testSpatialPortAgainstOriginalInstructions() throws {
        guard let path = ProcessInfo.processInfo.environment["PLAZA_ORIGINAL_LOGIC_QA"] else {
            throw XCTSkip("Set PLAZA_ORIGINAL_LOGIC_QA to local instruction fixtures")
        }
        struct Vectors: Decodable {
            let partnerEligibility: [[Double]]
            let socialStarts: [[Double]]
            let destinations: [[Double]]
            let dancePositions: [[Double]]
            let danceStarts: [[Double]]
            let danceEligibility: [[Double]]
        }
        let vectors = try JSONDecoder().decode(Vectors.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
        XCTAssertEqual(vectors.partnerEligibility.count,1584)
        XCTAssertEqual(vectors.socialStarts.count,1000)
        XCTAssertEqual(vectors.destinations.count,400)
        XCTAssertEqual(vectors.dancePositions.count,4000)
        XCTAssertEqual(vectors.danceStarts.count,1000)
        XCTAssertEqual(vectors.danceEligibility.count,1050)
        for row in vectors.partnerEligibility {
            var input = OriginalLounge.PartnerInput(position:.init(Float(row[5]),Float(row[6])),forward:.init(Float(row[7]),Float(row[8])),animation:Int(row[0]))
            input.hasWatchTarget=row[1] != 0;input.hasPartner=row[2] != 0
            input.restrictions=UInt32(row[3]);input.socialTicks=Int(row[4])
            XCTAssertEqual(OriginalLounge.acceptsPartner(input,at:.init(Float(row[9]),Float(row[10]))),row[11] != 0,"Original partner inputs: \(row)")
        }
        for row in vectors.socialStarts {
            var random = OriginalLoungeRandom(seed:UInt32(row[0]))
            let start = OriginalLounge.startSocial(bowFrames:12,random:&random)
            XCTAssertEqual([start.firstAction,start.secondAction,start.durationTicks,start.firstLeader ? 1:0],row[1..<5].map(Int.init))
            XCTAssertEqual(random.words,row[5..<9].map(UInt32.init))
        }
        for row in vectors.danceStarts {
            var random = OriginalLoungeRandom(seed:UInt32(row[0]))
            let start = OriginalLounge.startDance(random:&random)
            XCTAssertEqual([start.firstAction,start.secondAction,start.durationTicks,start.firstLeader ? 1:0],row[1..<5].map(Int.init))
            XCTAssertEqual(random.words,row[5..<9].map(UInt32.init))
        }
        for row in vectors.danceEligibility {
            var a = OriginalLounge.PartnerInput(position:.init(5,7),forward:.init(Float(row[0]),Float(row[1])),animation:Int(row[6]))
            var b = OriginalLounge.PartnerInput(position:.init(5+Float(row[4]),7+Float(row[5])),forward:.init(Float(row[2]),Float(row[3])),animation:Int(row[6]))
            a.hasWatchTarget=row[7] != 0;a.restrictions=UInt32(row[8]);a.socialTicks=Int(row[9])
            b.hasWatchTarget=a.hasWatchTarget;b.restrictions=a.restrictions;b.socialTicks=a.socialTicks
            XCTAssertEqual(OriginalLounge.acceptsDance(a,b),row[10] != 0,"Original dance eligibility: \(row)")
        }
        for row in vectors.destinations {
            var random = OriginalLoungeRandom(seed:UInt32(row[0]))
            let obstacles: [OriginalLounge.NavigationObstacle] = row[1] == 0 ? []:[.init(center:.init(30,40),radius:35),.init(center:.init(-50,-60),radius:50)]
            let point = try XCTUnwrap(OriginalLounge.destination(from:.init(5,7),role:0,halfWidth:432,halfDepth:288,obstacles:obstacles,random:&random))
            XCTAssertEqual(point,.init(Float(row[2]),Float(row[3])),"Original destination seed \(row[0]), obstacles \(row[1])")
            XCTAssertEqual(random.words,row[4..<8].map(UInt32.init))
        }
        for row in vectors.dancePositions {
            let frame:Float = row[4] == 2 ? Float(row[1]):0, other:Float = row[5] == 2 ? Float(row[2]):0
            XCTAssertEqual(OriginalLounge.pairedRate(frame:frame,partnerFrame:other,length:Float(row[3])),Float(row[12]),"Original paired phase: \(row)")
            if let dance = OriginalLounge.dancePosition(action:Int(row[0]),position:.init(Float(row[6]),Float(row[7])),partner:.init(Float(row[8]),Float(row[9])),mainFrame:frame,length:Float(row[3])) {
                XCTAssertEqual(dance.position.x,Float(row[10]),accuracy:2e-6,"Original root x: \(row)")
                XCTAssertEqual(dance.position.z,Float(row[11]),accuracy:2e-6,"Original root z: \(row)")
                XCTAssertEqual(dance.tangent.x,Float(row[13]),accuracy:1e-6)
                XCTAssertEqual(dance.tangent.z,Float(row[14]),accuracy:1e-6)
                XCTAssertEqual(dance.headingGain,Float(row[15]),accuracy:1e-6)
                XCTAssertEqual(row[16],1)
            }
        }
    }
}
