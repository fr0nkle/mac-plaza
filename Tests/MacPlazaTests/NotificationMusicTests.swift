import XCTest
import AppKit
@testable import MacPlaza

final class NotificationMusicTests: XCTestCase {
    private typealias State = AudioProcessActivity.ProcessState
    private let chime = State(pid:20,output:true,input:false,bundleID:"com.hnc.Discord")

    func testSystemNotificationsNeverSuppressOutputButMicrophonesStillDo() {
        for bundle in ["systemsoundserverd","com.apple.notificationcenterui"] {
            let notification=State(pid:20,output:true,input:false,bundleID:bundle)
            XCTAssertFalse(AudioProcessActivity.hasOtherActivity([notification],ownPID:10))
            var activity=SustainedAudioActivity()
            for time in [0.0,1,2,10,60] {
                XCTAssertEqual(activity.update(processes:[notification],ownPID:10,now:time),false)
            }
            XCTAssertEqual(activity.update(processes:[State(pid:20,output:false,input:true,bundleID:bundle)],ownPID:10,now:61),true)
        }
    }
    func testRepeatedAppChimesNeverAccumulateIntoAnInterruption() {
        var activity=SustainedAudioActivity(),quiet=AudioQuietPeriod()
        for time in [0.0,5,10,15] {
            for offset in [0.0,0.35,0.7,1.05,1.4] {
                let active=activity.update(processes:[chime],ownPID:10,now:time+offset)
                XCTAssertFalse(quiet.update(active:active,now:time+offset))
            }
            XCTAssertFalse(quiet.update(active:activity.update(processes:[],ownPID:10,now:time+1.75),now:time+1.75))
        }
    }
    func testSustainedPlaybackYieldsAfterTwoSecondsAndCallsYieldImmediately() {
        var activity=SustainedAudioActivity()
        XCTAssertEqual(activity.update(processes:[chime],ownPID:10,now:0),false)
        XCTAssertEqual(activity.update(processes:[chime],ownPID:10,now:1.99),false)
        XCTAssertEqual(activity.update(processes:[chime],ownPID:10,now:2),true)
        XCTAssertNil(activity.update(processes:nil,ownPID:10,now:3))
        XCTAssertEqual(activity.update(processes:[chime],ownPID:10,now:3.35),true)
        XCTAssertEqual(activity.update(processes:[State(pid:20,output:true,input:false)],ownPID:10,now:3.5),true,
                       "An unavailable identity property must not unmute a confirmed stream")
        XCTAssertEqual(activity.update(processes:[],ownPID:10,now:4),false)
        XCTAssertEqual(activity.update(processes:[State(pid:20,output:true,input:true,bundleID:"com.hnc.Discord")],ownPID:10,now:5),true)
        XCTAssertEqual(activity.update(processes:[chime],ownPID:10,now:5.35),true,"A call's output remains confirmed when its microphone stops")
    }
    func testUnknownSamplesDifferentProcessesAndReusedPIDsCannotConfirmChimes() {
        var activity=SustainedAudioActivity()
        XCTAssertEqual(activity.update(processes:[chime],ownPID:10,now:0),false)
        XCTAssertNil(activity.update(processes:nil,ownPID:10,now:1.5))
        XCTAssertEqual(activity.update(processes:[chime],ownPID:10,now:2.1),false)
        let next=State(pid:30,output:true,input:false,bundleID:"com.apple.Music")
        XCTAssertEqual(activity.update(processes:[next],ownPID:10,now:3.5),false)
        XCTAssertEqual(activity.update(processes:[State(pid:30,output:true,input:false,bundleID:"other.app")],ownPID:10,now:5),false)
        XCTAssertEqual(activity.update(processes:[State(pid:10,output:true,input:true)],ownPID:10,now:10),false)
    }
    @MainActor func testNotificationCenterOverlayDoesNotMuteMusic() {
        XCTAssertFalse(FullScreenAudioMonitor.shouldMute(frontmostPID:20,ownPID:10,coversDisplay:true,
                                                        frontmostBundleID:"com.apple.notificationcenterui"))
        XCTAssertTrue(FullScreenAudioMonitor.shouldMute(frontmostPID:20,ownPID:10,coversDisplay:true,
                                                       frontmostBundleID:"com.hnc.Discord"))
    }
    @MainActor func testChimeKeepsTheCurrentPlayerAndMusicPositionAdvancing() async throws {
        _=NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=PlazaModel(directory:root)
        defer {model.audio.update(enabled:false);try? FileManager.default.removeItem(at:root)}
        for _ in 0..<200 where !model.loaded {try await Task.sleep(for:.milliseconds(10))}
        model.wallpaperEnabled=true;model.windowVisible=false
        model.document.preferences.ambientSound=true;model.document.preferences.musicVolume=0
        model.updateAudio()
        let before=try XCTUnwrap(model.audio.backgroundPlayback.first).time
        var activity=SustainedAudioActivity(),quiet=AudioQuietPeriod()
        for time in [0.0,0.35,0.7,1.05,1.4] {
            model.otherAudioActive=quiet.update(active:activity.update(processes:[chime],ownPID:10,now:time),now:time)
            XCTAssertTrue(model.audio.isBackgroundPlaying)
            XCTAssertEqual(model.audio.backgroundPlayback.count,1,"Keep the existing player rather than releasing/recreating it")
        }
        try await Task.sleep(for:.milliseconds(120))
        XCTAssertGreaterThan(try XCTUnwrap(model.audio.backgroundPlayback.first).time,before+0.05)
        model.otherAudioActive=quiet.update(active:activity.update(processes:[chime],ownPID:10,now:2.1),now:2.1)
        XCTAssertTrue(model.audio.backgroundPlayback.isEmpty,"Real sustained playback still releases audio queues safely")
        await model.flush();try await model.storage.endSession()
    }
}
