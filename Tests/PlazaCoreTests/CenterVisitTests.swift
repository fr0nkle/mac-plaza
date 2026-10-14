import XCTest
@testable import PlazaCore

final class CenterVisitTests:XCTestCase {
    private let ids=(0..<60).map {UUID(uuidString:String(format:"57415241-0000-4000-8000-%012llx",UInt64($0)))!}
    private let icons:[CrowdPoint]=[.init(0.22,0.18),.init(0.40,0.105),.init(0.60,0.105),.init(0.78,0.18),
        .init(0.84,0.55),.init(0.625,0.67),.init(0.38,0.65),.init(0.165,0.55)]
    private var catalog:OriginalLoungeCatalog {
        var names=Set(OriginalLounge.animations.map(\.name))
        let root=String(OriginalLounge.animations[110].name.dropLast(2))
        names.insert(root+"_o");names.insert(root+"_oe")
        return OriginalLoungeCatalog(clips:names.sorted().map {.init(name:$0,frames:40,loop:$0.hasSuffix("_l"))})!
    }
    private func crowd(original:Bool)->CrowdSimulation {
        var c=CrowdSimulation(population:0,localCount:0,seed:42)
        c.worldWidth=48;c.worldAspect=0.9;c.groupsBelowIslands=true;c.minimumSpacing=0.016;c.nominalSpeed=0.011
        c.islandHalfWidth=0.05;c.islandTopClearance=0.075;c.islandBottomClearance=0.14
        if original {
            c.enableOriginalControllers(catalog)
        }
        c.reconcileRoster(ids,localCount:4);c.setPrimaryAvatar(ids[3]);c.islands=icons
        return c
    }
    func testGuestCompletesHelloThenChatThenGoodbyeBeforeWalkingHome() throws {
        for original in [false,true] {
            var c=crowd(original:original)
            for _ in 0..<4500 where c.centerGuestID == nil {c.step(1.0/30)}
            let id=try XCTUnwrap(c.centerGuestID),guest=try XCTUnwrap(ids.firstIndex(of:id))
            let clips=catalog.clips
            var phases:[String]=[],helloClips=Set<String>(),goodbyeClips=Set<String>()
            var replyHelloClips=Set<String>(),replyGoodbyeClips=Set<String>()
            var guestStarts:[String:Double]=[:],replyStarts:[String:Double]=[:]
            var replyHelloTime=0.0,replyGoodbyeTime=0.0
            var helloTime=0.0,goodbyeTime=0.0,otherMovement=0.0
            for frame in 0..<12000 {
                let before=c.walkers;c.step(1.0/30)
                XCTAssertEqual(c.walkers.count,60)
                for i in c.walkers.indices where i != guest && i != 3 {
                    otherMovement+=hypot(c.walkers[i].position.x-before[i].position.x,c.walkers[i].position.y-before[i].position.y)
                }
                let wave=c.centerGuestGreeting || c.centerGuestFarewell
                let phase=c.centerGuestGreeting ? "hello":c.centerGuestFarewell ? "goodbye":c.centerGuestReturning ? "return":c.walkers[guest].partner==3 ? "chat":nil
                if let phase,phases.last != phase {phases.append(phase)}
                if wave {
                    let wavePhase=c.centerGuestGreeting ? "hello":"goodbye"
                    if guestStarts[wavePhase] == nil {guestStarts[wavePhase]=Double(frame)/30}
                    XCTAssertNil(c.walkers[guest].partner)
                    XCTAssertEqual(c.walkers[guest].activity,.wave)
                    XCTAssertTrue(c.walkers[guest].path.isEmpty)
                    XCTAssertLessThan(hypot(c.walkers[guest].position.x-before[guest].position.x,c.walkers[guest].position.y-before[guest].position.y),0.006)
                    if c.centerGuestGreeting {helloTime+=1.0/30} else {goodbyeTime+=1.0/30}
                    if let sample=c.originalSample(guest) {
                        let name=clips[sample.clip].name
                        if c.centerGuestGreeting {helloClips.insert(name)} else {goodbyeClips.insert(name)}
                    }
                    XCTAssertNil(c.walkers[3].partner)
                    XCTAssertTrue(c.walkers[3].path.isEmpty)
                    if c.walkers[3].activity == .wave {
                        if replyStarts[wavePhase] == nil {replyStarts[wavePhase]=Double(frame)/30}
                        if c.centerGuestGreeting {replyHelloTime+=1.0/30} else {replyGoodbyeTime+=1.0/30}
                        if let sample=c.originalSample(3) {
                            if c.centerGuestGreeting {replyHelloClips.insert(clips[sample.clip].name)}
                            else {replyGoodbyeClips.insert(clips[sample.clip].name)}
                        }
                    }
                    XCTAssertLessThan(hypot(c.walkers[3].position.x-before[3].position.x,c.walkers[3].position.y-before[3].position.y),0.006)
                    // A paused wallpaper must not consume either greeting.
                    let frozen=c.walkers,clock=c.animationClock,sample=c.originalSample(guest),reply=c.originalSample(3)
                    c.step(0)
                    XCTAssertEqual(c.walkers,frozen);XCTAssertEqual(c.animationClock,clock)
                    XCTAssertEqual(c.originalSample(guest),sample)
                    XCTAssertEqual(c.originalSample(3),reply)
                }
                if c.centerGuestID == nil {break}
            }
            XCTAssertNil(c.centerGuestID)
            XCTAssertEqual(phases,["hello","chat","goodbye","return"])
            XCTAssertGreaterThan(helloTime,2);XCTAssertGreaterThan(goodbyeTime,2)
            XCTAssertGreaterThan(replyHelloTime,2);XCTAssertGreaterThan(replyGoodbyeTime,2)
            for phase in ["hello","goodbye"] {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(replyStarts[phase])-XCTUnwrap(guestStarts[phase]),0.2,"The main Mii should answer the visitor's wave")
            }
            XCTAssertGreaterThan(otherMovement,0.5,"The rest of the plaza keeps moving during the visit")
            if original {
                for clip in ["Handwaving00_o","Handwaving00_l","Handwaving00_oe"] {
                    XCTAssertTrue(helloClips.contains(clip),"Hello should include \(clip)")
                    XCTAssertTrue(goodbyeClips.contains(clip),"Goodbye should include \(clip)")
                    XCTAssertTrue(replyHelloClips.contains(clip),"The main Mii's hello should include \(clip)")
                    XCTAssertTrue(replyGoodbyeClips.contains(clip),"The main Mii's goodbye should include \(clip)")
                }
            }
        }
    }
    func testReturnedWavesFollowIdentitiesAndClearWhenAVisitIsCancelled() throws {
        for original in [false,true] {
            var c=crowd(original:original)
            for _ in 0..<6000 {
                c.step(1.0/30)
                if c.centerGuestGreeting && c.walkers[3].activity == .wave {break}
            }
            XCTAssertTrue(c.centerGuestGreeting);XCTAssertEqual(c.walkers[3].activity,.wave)
            let guest=try XCTUnwrap(c.centerGuestID),before=c.walkers,pose=c.originalSample(3)
            c.reconcileRoster(Array(ids.reversed()),localCount:4)
            let host=56
            XCTAssertEqual(c.walkers.map(\.position),before.reversed().map(\.position))
            XCTAssertEqual(c.walkers[host].activity,.wave);XCTAssertEqual(c.originalSample(host),pose)
            c.step(1.0/30)
            XCTAssertEqual(c.walkers[host].activity,.wave)
            var changedMain=c
            changedMain.setPrimaryAvatar(guest);changedMain.step(1.0/30)
            XCTAssertNil(changedMain.centerGuestID)
            XCTAssertEqual(changedMain.walkers[host].greeting,0)
            XCTAssertNotEqual(changedMain.walkers[host].activity,.wave)
            var removedGuest=c
            removedGuest.reconcileRoster(Array(ids.reversed()).map {$0==guest ? UUID():$0},localCount:4)
            XCTAssertNil(removedGuest.centerGuestID)
            XCTAssertEqual(removedGuest.walkers[host].greeting,0)
            XCTAssertNotEqual(removedGuest.walkers[host].activity,.wave)
            c.islands=[];c.step(1.0/30)
            XCTAssertNil(c.centerGuestID);XCTAssertEqual(c.walkers[host].greeting,0)
            XCTAssertNotEqual(c.walkers[host].activity,.wave)
            XCTAssertEqual(c.walkers.count,60)
        }
    }
    private func groupNear(_ p:CrowdPoint)->Int {
        icons.indices.min {a,b in
            func gap(_ i:Int)->Double {hypot(p.x-icons[i].x,p.y-(icons[i].y+0.175))}
            return gap(a)<gap(b)
        }!
    }
    func testExistingGuestsChatCentrallyThenReturnToTheirOwnGroups() {
        for original in [false,true] {
            var c=crowd(original:original),guests=Set<UUID>(),talkers=Set<UUID>()
            var active:UUID?,home=0,returns=0,chatSamples=0,start=0.0
            for frame in 0..<27000 {
                let before=c.walkers,previousGuest=c.centerGuestID,returning=c.centerGuestReturning
                c.step(1.0/30)
                XCTAssertEqual(c.walkers.count,60)
                for i in 0..<60 {
                    XCTAssertLessThan(hypot(c.walkers[i].position.x-before[i].position.x,c.walkers[i].position.y-before[i].position.y),0.006)
                    if let j=c.walkers[i].partner {XCTAssertEqual(c.walkers[j].partner,i)}
                }
                if let guest=c.centerGuestID,guest != previousGuest {
                    XCTAssertTrue(ids.contains(guest));XCTAssertNotEqual(guest,ids[3])
                    active=guest;guests.insert(guest);home=groupNear(before[ids.firstIndex(of:guest)!].position);start=Double(frame)/30
                }
                if c.centerGuestReturning && !returning,let active {
                    let w=before[ids.firstIndex(of:active)!],main=before[3]
                    print("Center departure \(original): after \(Double(frame)/30-start)s, state \(w.state), activity \(w.activity), gap \(hypot(w.position.x-main.position.x,w.position.y-main.position.y)), goal gap \(hypot(w.position.x-w.target.x,w.position.y-w.target.y))")
                }
                if let active,let guest=ids.firstIndex(of:active),c.walkers[guest].partner==3 {
                    chatSamples+=1;talkers.insert(active)
                    XCTAssertLessThan(hypot(c.walkers[guest].position.x-0.5,c.walkers[guest].position.y-0.55),0.16)
                }
                if previousGuest != nil,c.centerGuestID == nil,let id=active {
                    let guest=ids.firstIndex(of:id)!
                    XCTAssertEqual(groupNear(c.walkers[guest].position),home,"Guests should return to the group they came from")
                    returns+=1;active=nil
                }
            }
            // A guest may still be walking home at the observation cutoff.
            // Let that same visit finish; do not count a pending return as lost.
            if let id=c.centerGuestID {
                for _ in 0..<5400 where c.centerGuestID != nil {
                    let before=c.walkers;c.step(1.0/30)
                    XCTAssertEqual(c.walkers.count,60)
                    for i in 0..<60 {XCTAssertLessThan(hypot(c.walkers[i].position.x-before[i].position.x,c.walkers[i].position.y-before[i].position.y),0.006)}
                }
                XCTAssertNil(c.centerGuestID,"The final guest must finish its return trip")
                if c.centerGuestID == nil {
                    XCTAssertEqual(groupNear(c.walkers[ids.firstIndex(of:id)!].position),home)
                    returns+=1
                }
            }
            print("Center guests \(original ? "original":"fallback"): \(guests.count) identities, \(talkers.count) talkers, \(c.completedCenterChats) chats, \(returns) returns")
            XCTAssertGreaterThanOrEqual(guests.count,2)
            XCTAssertGreaterThanOrEqual(talkers.count,2)
            XCTAssertGreaterThanOrEqual(talkers.count,guests.count-1,"Guests should reach the conversation, allowing only the final visit still in progress")
            XCTAssertGreaterThanOrEqual(c.completedCenterChats,2)
            XCTAssertGreaterThanOrEqual(returns,2)
            XCTAssertGreaterThan(chatSamples,60)
            XCTAssertLessThan(guests.count,15,"Visits should remain occasional, not a crowd migration")
        }
    }
    func testAnActiveVisitSurvivesRosterReorderingAndPauseWithoutMovingActors() {
        for original in [false,true] {
            var c=crowd(original:original)
            for _ in 0..<3600 where c.centerGuestID == nil {c.step(1.0/30)}
            let guest=c.centerGuestID
            XCTAssertNotNil(guest)
            let before=c.walkers,clock=c.animationClock
            c.step(0)
            XCTAssertEqual(c.walkers,before);XCTAssertEqual(c.animationClock,clock)
            c.reconcileRoster(Array(ids.reversed()),localCount:4)
            XCTAssertEqual(c.centerGuestID,guest)
            XCTAssertEqual(c.walkers.map(\.position),before.reversed().map(\.position))
            XCTAssertEqual(c.walkers.map(\.target),before.reversed().map(\.target))
            var newHost=c
            newHost.setPrimaryAvatar(guest)
            XCTAssertEqual(newHost.walkers.map(\.position),c.walkers.map(\.position))
            newHost.step(1.0/30)
            XCTAssertNil(newHost.centerGuestID,"A guest chosen as the main Mii should settle centrally rather than remain a returning guest")
            let revised=Array(ids.reversed()).map {$0==guest ? UUID():$0}
            let positions=c.walkers.map(\.position)
            c.reconcileRoster(revised,localCount:4)
            XCTAssertNil(c.centerGuestID)
            XCTAssertEqual(c.walkers.count,60);XCTAssertEqual(c.walkers.map(\.position),positions)
        }
    }
}
