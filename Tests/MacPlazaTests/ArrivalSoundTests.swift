import XCTest
import AVFoundation
import PlazaCore
@testable import MacPlaza

final class ArrivalSoundTests:XCTestCase {
    @MainActor func testBundledEffectsAreShortStereoOneShotsWithCleanBoundaries() throws {
        for cue in PlazaArrival.Cue.allCases {
            let url=try XCTUnwrap(PlazaAudio.arrivalEffectURL(for:cue))
            let file=try AVAudioFile(forReading:url)
            XCTAssertEqual(file.processingFormat.channelCount,2)
            let duration=Double(file.length)/file.processingFormat.sampleRate
            XCTAssertTrue((0.25...3).contains(duration))
            XCTAssertLessThan(cue.time+duration,PlazaArrival.pullback,"The original musical cue finishes before the camera pulls back")
            let buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)))
            try file.read(into:buffer)
            let channels=try XCTUnwrap(buffer.floatChannelData)
            for c in 0..<2 {
                let samples=UnsafeBufferPointer(start:channels[c],count:Int(buffer.frameLength))
                XCTAssertLessThan(abs(samples.first ?? 1),0.001)
                XCTAssertLessThan(abs(samples.last ?? 1),0.001)
                XCTAssertLessThan(samples.map {abs($0)}.max() ?? 1,0.8)
                XCTAssertGreaterThan(samples.map {abs($0)}.max() ?? 0,0.3)
            }
        }
    }

    @MainActor func testEffectsLayerOverMusicAndMuteOrPreviewStopsThem() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("Silent.wav")
        var silent=PlazaAudio.loop();silent.replaceSubrange(44..<silent.count,with:Data(repeating:0,count:silent.count-44))
        try silent.write(to:url)
        let audio=PlazaAudio()
        defer {audio.update(enabled:false,allowPreview:false);try? FileManager.default.removeItem(at:root)}
        audio.update(enabled:true,volume:0,customURL:url)
        audio.playArrivalEffect(.drop,volume:0.0000001)
        audio.playArrivalEffect(.wave,volume:0.0000001)
        XCTAssertEqual(audio.effectPlayback.map(\.cue),[.drop,.wave])
        XCTAssertTrue(audio.effectPlayback.allSatisfy(\.playing))
        XCTAssertTrue(audio.isBackgroundPlaying,"Arrival effects must not interrupt the selected soundtrack")
        audio.update(enabled:false)
        XCTAssertTrue(audio.effectPlayback.isEmpty)
        audio.playArrivalEffect(.drop,volume:0.12)
        XCTAssertTrue(audio.effectPlayback.isEmpty,"Mute prevents later cues from starting")
        audio.update(enabled:true,volume:0,customURL:url)
        audio.playArrivalEffect(.wave,volume:0)
        XCTAssertTrue(audio.effectPlayback.isEmpty,"A zero volume also silences arrival cues")
        audio.playArrivalEffect(.wave,volume:0.0000001)
        try audio.preview(url,track:.plaza,volume:0)
        XCTAssertTrue(audio.effectPlayback.isEmpty)
        audio.playArrivalEffect(.drop,volume:0.0000001)
        XCTAssertTrue(audio.effectPlayback.isEmpty,"Music audition owns audio until it ends")
    }

    @MainActor func testCuesWaitForRendererFireOnceAndDoNotAdvanceDuringPause() async throws {
        let scene=PlazaScene(size:CGSize(width:1200,height:720)),avatar=Avatar(name:"Sound",outfit:0)
        scene.configure(avatars:[avatar],population:20)
        let owner=UUID();scene.attachFFL(owner:owner,frame:{_ in},configure:{_ in})
        defer {scene.detachFFL(owner:owner)}
        var cues:[PlazaArrival.Cue]=[],stops=0
        scene.onArrivalCue={cues.append($0)};scene.onArrivalStopped={stops+=1}
        scene.beginArrival(for:avatar.id,animated:true);scene.setMoving(true)
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertTrue(cues.isEmpty)
        scene.rendererDidBecomeReady()
        for _ in 0..<250 where cues.isEmpty {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(cues,[.drop])
        scene.setMoving(false)
        let paused=cues
        try await Task.sleep(for:.milliseconds(400))
        XCTAssertEqual(cues,paused)
        scene.setMoving(true)
        for _ in 0..<150 where cues.count<2 {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(cues,[.drop,.wave])
        try await Task.sleep(for:.milliseconds(200))
        XCTAssertEqual(cues,[.drop,.wave],"An idle wave must not retrigger the greeting chime")
        scene.finishArrival()
        XCTAssertGreaterThanOrEqual(stops,2,"Pausing and skipping stop any in-flight one-shots")
        scene.beginArrival(for:avatar.id,animated:false)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(cues,[.drop,.wave],"Reduce Motion skips the choreography and its timed sounds")
    }
}
