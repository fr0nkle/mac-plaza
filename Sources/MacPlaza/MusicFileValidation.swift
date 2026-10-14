import AudioToolbox
import Foundation

/// Inspect the container and read an audio packet without opening an output device.
/// Playback readiness belongs to playback, not to importing a valid recording.
enum MusicFileValidation {
    static func validate(_ url: URL) throws {
        var reference: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &reference) == noErr,
              let file = reference else { throw FFLError.message("This file is not a supported audio recording.") }
        defer { AudioFileClose(file) }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format) == noErr,
              format.mSampleRate.isFinite, format.mSampleRate > 0, format.mChannelsPerFrame > 0 else {
            throw FFLError.message("The recording has an invalid audio format.")
        }
        var packetSize: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyPacketSizeUpperBound, &size, &packetSize) == noErr,
              packetSize > 0, packetSize <= 1_048_576 else {
            throw FFLError.message("The recording contains no supported audio packets.")
        }
        var data = [UInt8](repeating: 0, count: Int(packetSize))
        var bytes = packetSize, packets: UInt32 = 1, description = AudioStreamPacketDescription()
        let status = data.withUnsafeMutableBytes {
            AudioFileReadPacketData(file, false, &bytes, &description, 0, &packets, $0.baseAddress!)
        }
        guard (status == noErr || status == kAudioFileEndOfFileError), packets == 1, bytes > 0 else {
            throw FFLError.message("The recording contains no readable audio data.")
        }
    }
}
