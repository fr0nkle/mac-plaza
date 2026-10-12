import XCTest
@testable import PlazaCore

final class UpgradeTests: XCTestCase {
    func testVersionOneMigrationKeepsCharacterAndJournalIdentity() throws {
        var doc=PlazaDocument(); doc.avatars[0].name="Old friend"; doc.notes=[LocalNote(authorID:doc.avatars[0].id,author:"Old friend",appID:nil,text:"Keep me")]
        var old=try JSONSerialization.jsonObject(with:JSONEncoder().encode(doc)) as! [String:Any]
        old["version"]=1
        old["avatars"]=(old["avatars"] as! [[String:Any]]).map { a in var a=a; a.removeValue(forKey:"features"); return a }
        let upgraded=try DocumentStorage.decode(JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(upgraded.version,2); XCTAssertEqual(upgraded.avatars[0].id,doc.avatars[0].id); XCTAssertEqual(upgraded.notes,doc.notes); XCTAssertEqual(upgraded.avatars[0].features,MiiFeatures())
    }
    func testKnownPublicMiiFixtureAndChecksum() throws {
        // Public example from PretendoNetwork/mii-js README; field layout cross-check.
        let encoded="AwEAMLrDTIqIpLZhlH8Ps6TA4eK42QAAAFAOMHPgSQBtAG8AcgBhAHPgDzAAAGsrAgA5AQJoRBgmNEYUgRIWaA0AACmGAUhQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAG7s"
        let data=try XCTUnwrap(Data(base64Encoded:encoded)); XCTAssertEqual(data.count,96)
        let a=try MiiFile.decode(data)
        XCTAssertEqual(a.hair,57); XCTAssertEqual(a.skin,0); XCTAssertEqual(a.face,1); XCTAssertEqual(a.features.eyeColor,0)
        XCTAssertEqual(try MiiFile.encode(a).count,96)
        var broken=data; broken[50]^=1; XCTAssertThrowsError(try MiiFile.decode(broken))
        XCTAssertThrowsError(try MiiFile.decode(data.prefix(95)))
    }
    func testMiiFeatureExtremesRoundTripWithinQuantization() throws {
        var a=Avatar(name:"Plaza"); a.hair=131; a.eyes=59; a.brows=23; a.nose=17; a.mouth=35; a.face=11; a.outfit=11
        a.glasses=true; a.beard=true; a.features.glassesType=8; a.features.mustache=5; a.features.beardType=5; a.features.mole=true
        a.features.eyeRotation=1; a.features.browY=0; a.features.mouthStretch=1; a.features.moleX=0; a.features.moleY=1
        a.features.birthMonth=12; a.features.birthDay=31; a.features.creator="Maker"; a.features.flipHair=true
        let data=try MiiFile.encode(a),b=try MiiFile.decode(data)
        XCTAssertEqual(b.hair,a.hair); XCTAssertEqual(b.eyes,a.eyes); XCTAssertEqual(b.mouth,a.mouth); XCTAssertEqual(b.features.browY,0); XCTAssertEqual(b.features.moleY,1); XCTAssertEqual(b.features.mustache,5)
        XCTAssertEqual(b.features.creator,"Maker"); XCTAssertEqual(b.height,a.height,accuracy:1.0/127)
        XCTAssertEqual(try MiiFile.encode(b).dropFirst(24).dropLast(2),data.dropFirst(24).dropLast(2))
        a.name=String(repeating:"😀",count:6); XCTAssertThrowsError(try MiiFile.encode(a))
        a.name="Plaza"; a.features.moleX = .nan; XCTAssertThrowsError(try MiiFile.encode(a))
        XCTAssertEqual(MiiFile.crc("123456789".utf8),0x31C3)
    }
    func testCrowdIsDeterministicStaysBoundedAndAvoidsControls() {
        var a=CrowdSimulation(population:80,localCount:3),b=a
        let islands=[CrowdPoint(0.15,0.18),CrowdPoint(0.38,0.1),CrowdPoint(0.62,0.1),CrowdPoint(0.85,0.18),CrowdPoint(0.89,0.52),CrowdPoint(0.72,0.78),CrowdPoint(0.28,0.78),CrowdPoint(0.11,0.52)]
        a.islands=islands; b.islands=islands
        var states=Set<Int>()
        for _ in 0..<1800 { a.step(1.0/30); b.step(1.0/30)
            for w in a.walkers { states.insert(w.state); XCTAssertTrue((0.05...0.95).contains(w.position.x)); XCTAssertTrue((0.20...0.95).contains(w.position.y)); XCTAssertTrue(w.angle.isFinite)
                XCTAssertFalse(islands.contains { abs(w.position.x-$0.x)<0.075 && w.position.y > $0.y-0.08 && w.position.y < $0.y+0.23 })
            }
        }
        XCTAssertEqual(a.walkers,b.walkers); XCTAssertEqual(states,Set(0...5))
    }
    func testDraftRepliesAndIconsPersistWithPortableExport() throws {
        var doc=PlazaDocument(); var draft=NoteDraft(); draft.text="Unfinished"; doc.draft=draft
        var n=LocalNote(authorID:doc.primaryAvatar.id,author:"You",appID:nil,text:"A note"); n.replies=[LocalReply(authorID:doc.primaryAvatar.id,author:"You",text:"A reply")]; n.read=true; doc.notes=[n]
        var app=AppIsland(label:"App",bundleID:"test",path:"/Applications/App.app"); app.customIcon=Data([1,2,3]); doc.apps=[app]
        let copy=try DocumentStorage.decode(JSONEncoder().encode(doc.portable()))
        XCTAssertEqual(copy.draft,draft); XCTAssertEqual(copy.notes,doc.notes); XCTAssertEqual(copy.apps[0].customIcon,app.customIcon); XCTAssertNil(copy.apps[0].path)
        doc.notes[0].replies=Array(repeating:n.replies![0],count:51); XCTAssertThrowsError(try doc.validated())
    }
    func testInterruptedSessionIsDetectedAndCleanQuitClearsIt() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:dir) }
        let s=DocumentStorage(url:dir.appendingPathComponent("plaza.json"))
        let first=try await s.beginSession(), second=try await s.beginSession(); XCTAssertFalse(first); XCTAssertTrue(second)
        try await s.endSession(); let third=try await s.beginSession(); XCTAssertFalse(third)
    }
}

extension UpgradeTests {
    func testSocialPairsAreReciprocalAndWalkingNeverTeleports() {
        var crowd=CrowdSimulation(population:60,localCount:3)
        crowd.islands=[CrowdPoint(0.15,0.18),CrowdPoint(0.38,0.1),CrowdPoint(0.62,0.1),CrowdPoint(0.85,0.18),CrowdPoint(0.89,0.52),CrowdPoint(0.72,0.78),CrowdPoint(0.28,0.78),CrowdPoint(0.11,0.52)]
        crowd.step(0.001)
        var pairedFrames=0,alignedPairs=0,acceleratingFrames=0
        for _ in 0..<3600 {
            let before=crowd.walkers;crowd.step(1.0/30)
            for (i,w) in crowd.walkers.enumerated() {
                XCTAssertLessThan(hypot(w.position.x-before[i].position.x,w.position.y-before[i].position.y),0.004)
                XCTAssertTrue((0...1).contains(w.motion));XCTAssertGreaterThanOrEqual(w.speed,0)
                if w.speed>0 && w.speed<0.018 {acceleratingFrames+=1}
                if let j=w.partner {
                    XCTAssertEqual(crowd.walkers[j].partner,i);pairedFrames+=1
                    if w.conversation<1.5 {
                        let p=crowd.walkers[j].position,desired=atan2(p.x-w.position.x,p.y-w.position.y)
                        if cos(desired-w.angle)>0.9 {alignedPairs+=1}
                    }
                }
            }
        }
        XCTAssertGreaterThan(pairedFrames,100);XCTAssertGreaterThan(alignedPairs,50);XCTAssertGreaterThan(acceleratingFrames,100)
    }
}

extension UpgradeTests {
    func testLaunchReactionIsBoundedAndExpires() {
        var crowd=CrowdSimulation(population:60,localCount:3)
        let positions=crowd.walkers.map(\.position)
        crowd.cheer(near:positions[0])
        XCTAssertTrue((1...6).contains(crowd.walkers.filter {$0.cue>0}.count))
        XCTAssertEqual(crowd.walkers.map(\.position),positions)
        for _ in 0..<100 {crowd.step(1.0/30)}
        XCTAssertTrue(crowd.walkers.allSatisfy {$0.cue==0})
    }
}
