import XCTest
@testable import PlazaCore

final class NaturalGatheringTests:XCTestCase {
    private let icons:[CrowdPoint] = [
        .init(0.22,0.18),.init(0.40,0.105),.init(0.60,0.105),.init(0.78,0.18),
        .init(0.84,0.55),.init(0.625,0.67),.init(0.38,0.65),.init(0.165,0.55),
        .init(0.945,0.33),.init(0.055,0.33)
    ]
    private func crowd(original:Bool,seed:UInt64)->CrowdSimulation {
        var crowd=CrowdSimulation(population:0,localCount:0,seed:seed)
        crowd.worldWidth=48;crowd.worldAspect=0.9
        crowd.groupsBelowIslands=true;crowd.minimumSpacing=0.016
        crowd.islandHalfWidth=0.05;crowd.islandTopClearance=0.075;crowd.islandBottomClearance=0.14
        if original {
            let names=Set(OriginalLounge.animations.map(\.name)).sorted()
            crowd.enableOriginalControllers(OriginalLoungeCatalog(clips:names.map {.init(name:$0,frames:40,loop:$0.hasSuffix("_l"))})!)
        }
        let ids=(0..<60).map {UUID(uuidString:String(format:"57415241-0000-4000-8000-%012llx",UInt64($0)))!}
        crowd.reconcileRoster(ids,localCount:4);crowd.islands=icons
        return crowd
    }
    private func group(_ p:CrowdPoint)->Int? {
        icons.indices.filter {
            abs(p.x-icons[$0].x)<0.105 && p.y>icons[$0].y+0.115 && p.y<min(0.95,icons[$0].y+0.275)
        }.min {abs(p.x-icons[$0].x)<abs(p.x-icons[$1].x)}
    }
    func testSixtyMiisFormLooseGroupsWithAMinorityWalkingBetweenThem() {
        for original in [false,true] {
            var crowd=crowd(original:original,seed:42)
            let initial=crowd.walkers.map(\.position)
            var counts=Array(repeating:0,count:icons.count)
            for p in initial {if let g=group(p) {counts[g]+=1}}
            print("Natural crowd \(original ? "original":"fallback"): initial groups \(counts)")
            XCTAssertGreaterThanOrEqual(counts.reduce(0,+),46)
            XCTAssertLessThanOrEqual(counts.reduce(0,+),56,"Keep a few Miis on the connecting paths")
            XCTAssertTrue(counts.allSatisfy {$0>=3},"Every icon should have a gathering at 60 Miis")
            for g in icons.indices {
                let positions=initial.filter {group($0)==g}
                XCTAssertGreaterThan((positions.map(\.x).max() ?? 0)-(positions.map(\.x).min() ?? 0),0.015)
                XCTAssertGreaterThan((positions.map(\.y).max() ?? 0)-(positions.map(\.y).min() ?? 0),0.01)
            }
            var travel=Array(repeating:0.0,count:60),movingSamples=0,gatheredSamples=0
            for frame in 0..<3600 {
                let before=crowd.walkers;crowd.step(1.0/30)
                XCTAssertEqual(crowd.walkers.count,60)
                for i in 0..<60 {
                    let p=crowd.walkers[i].position,old=before[i].position
                    let step=hypot(p.x-old.x,p.y-old.y)
                    XCTAssertLessThan(step,0.006,"Gathering must remain continuous")
                    travel[i]+=step
                    if frame%30==0 {
                        if crowd.walkers[i].speed>0.005 {movingSamples+=1}
                        if group(p) != nil {gatheredSamples+=1}
                    }
                }
            }
            print("Natural crowd: moving samples \(movingSamples), gathered samples \(gatheredSamples), travelers \(travel.filter {$0>0.1}.count)")
            XCTAssertGreaterThan(travel.filter {$0>0.1}.count,3,"Travelers must actually move between gatherings")
            XCTAssertGreaterThan(gatheredSamples,3600,"Most of the crowd should stay near icons over time")
            XCTAssertGreaterThan(movingSamples,100)
            XCTAssertLessThan(movingSamples,3600,"The whole crowd should not march at once")
        }
    }
    func testGatheringRolesAndDestinationsStayWithIdentitiesOnRefresh() {
        for original in [false,true] {
            var crowd=crowd(original:original,seed:7)
            for _ in 0..<900 {crowd.step(1.0/30)}
            let before=crowd.walkers
            let reversed=(0..<60).reversed().map {UUID(uuidString:String(format:"57415241-0000-4000-8000-%012llx",UInt64($0)))!}
            crowd.reconcileRoster(reversed,localCount:4)
            XCTAssertEqual(crowd.walkers.map(\.position),before.reversed().map(\.position))
            XCTAssertEqual(crowd.walkers.map(\.target),before.reversed().map(\.target))
            crowd.setGatheringIslands([0:2])
            XCTAssertEqual(crowd.walkers.map(\.position),before.reversed().map(\.position),"An explicit affinity changes the route, never the current position")
            let target=crowd.walkers[0].target
            XCTAssertLessThan(abs(target.x-icons[2].x),0.105)
            XCTAssertGreaterThan(target.y,icons[2].y+0.10)
        }
    }
}
