import AVFoundation
import Foundation

enum AudioTrimError: Error, Equatable {
    case unreadable
    case noAudioTrack
    case exportFailed
    case invalidWindow
}

enum AlarmLoudness {
    /// -1 dBFS. Alarm files must not reach full scale.
    static let peakCeiling: Float = 0.891250938
    /// -9 LUFS, as the mean square of samples in the -1...1 range.
    static let targetMeanSquare: Float = 0.12589254

    /// Raises a quiet clip toward -9 LUFS, but never past the peak ceiling.
    static func gain(peak: Float, meanSquare: Float) -> Float {
        guard peak > 0, meanSquare > 0 else { return 1 }
        let peakGain = peakCeiling / peak
        let loudnessGain = sqrt(targetMeanSquare / meanSquare)
        let chosen = min(peakGain, loudnessGain)
        guard chosen.isFinite, chosen > 0 else { return 1 }
        return chosen
    }
}

enum AudioTrimmer {
    static let durationTimeout: TimeInterval = 15

    /// Reads duration off the caller's actor. Zero, NaN, and a hung file provider all fail.
    static func duration(of url: URL) async throws -> TimeInterval {
        try await withThrowingTaskGroup(of: TimeInterval.self) { group in
            group.addTask {
                try await loadDuration(of: url)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(durationTimeout))
                throw AudioTrimError.unreadable
            }
            do {
                guard let seconds = try await group.next() else { throw AudioTrimError.unreadable }
                group.cancelAll()
                guard seconds.isFinite, seconds > 0 else { throw AudioTrimError.unreadable }
                return seconds
            } catch is CancellationError {
                group.cancelAll()
                throw CancellationError()
            } catch let error as AudioTrimError {
                group.cancelAll()
                throw error
            } catch {
                group.cancelAll()
                throw AudioTrimError.unreadable
            }
        }
    }

    private static func loadDuration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let time = try await asset.load(.duration)
        let seconds = time.seconds
        guard seconds.isFinite, seconds > 0 else { throw AudioTrimError.unreadable }
        return seconds
    }

    static func trim(source: URL, window: TrimWindow, destination: URL) async throws {
        let ext = source.pathExtension.lowercased()
        if ["wav", "caf", "aiff", "aif"].contains(ext) {
            try trimPCM(source: source, window: window, destination: destination)
        } else {
            try await trimCompressed(source: source, window: window, destination: destination)
        }
        try normalizeAlarmLevel(at: destination)
    }

    static func trimPCM(source: URL, window: TrimWindow, destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let rate = format.sampleRate
        guard rate > 0 else { throw AudioTrimError.unreadable }
        let assetDuration = Double(input.length) / rate
        guard let window = window.clamped(to: assetDuration) else { throw AudioTrimError.invalidWindow }
        let frames = AVAudioFrameCount(((window.end - window.start) * rate).rounded(.down))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw AudioTrimError.exportFailed
        }
        input.framePosition = AVAudioFramePosition((window.start * rate).rounded(.down))
        try input.read(into: buffer, frameCount: frames)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = try AVAudioFile(
            forWriting: destination,
            settings: outputSettings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        guard let converted = convert(buffer, to: output.processingFormat) else {
            throw AudioTrimError.exportFailed
        }
        try output.write(from: converted)
    }

    /// Rewrites a trimmed clip at alarm loudness. 16-bit PCM stays the on-disk format.
    static func normalizeAlarmLevel(at url: URL) throws {
        let buffer = try readFloatBuffer(at: url)
        guard let buffer else { return }
        guard let channels = buffer.floatChannelData else { throw AudioTrimError.exportFailed }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return }

        var peak: Float = 0
        var sum: Float = 0
        let sampleCount = channelCount * frameCount
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameCount {
                let sample = samples[frame]
                peak = max(peak, abs(sample))
                sum += sample * sample
            }
        }
        let gain = AlarmLoudness.gain(peak: peak, meanSquare: sum / Float(sampleCount))
        guard abs(gain - 1) > 0.01 else { return }
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameCount {
                let scaled = samples[frame] * gain
                samples[frame] = min(1, max(-1, scaled))
            }
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent("norm-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension.isEmpty ? "caf" : url.pathExtension)
        try writeNormalized(buffer, to: temporary, settings: outputSettings)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temporary, to: url)
    }

    private static func readFloatBuffer(at url: URL) throws -> AVAudioPCMBuffer? {
        let input = try AVAudioFile(forReading: url)
        guard input.length > 0, input.processingFormat.sampleRate > 0 else { return nil }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: input.processingFormat,
            frameCapacity: AVAudioFrameCount(input.length)
        ) else { throw AudioTrimError.exportFailed }
        try input.read(into: buffer)
        return buffer
    }

    private static func writeNormalized(
        _ buffer: AVAudioPCMBuffer,
        to url: URL,
        settings: [String: Any]
    ) throws {
        let output = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        guard let converted = convert(buffer, to: output.processingFormat) else {
            throw AudioTrimError.exportFailed
        }
        try output.write(from: converted)
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, (ratio * Double(buffer.frameLength)).rounded(.up)))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, statusOut in
            if consumed {
                statusOut.pointee = .endOfStream
                return nil
            }
            consumed = true
            statusOut.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return nil }
        return output
    }

    /// Imports MP3 and other compressed files as 16-bit mono CAF in `Library/Sounds`.
    private static func trimCompressed(source: URL, window: TrimWindow, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard let window = window.clamped(to: seconds) else { throw AudioTrimError.invalidWindow }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw AudioTrimError.noAudioTrack }
        let reader = try AVAssetReader(asset: asset)
        let start = CMTime(seconds: window.start, preferredTimescale: 44_100)
        let length = CMTime(seconds: window.duration, preferredTimescale: 44_100)
        reader.timeRange = CMTimeRange(start: start, duration: length)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioTrimError.exportFailed }
        reader.add(output)
        guard reader.startReading() else { throw AudioTrimError.exportFailed }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 1, interleaved: true) else {
            throw AudioTrimError.exportFailed
        }
        let file = try AVAudioFile(forWriting: destination, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        while let sample = output.copyNextSampleBuffer() {
            if let buffer = pcmBuffer(from: sample, format: format) {
                try file.write(from: buffer)
            }
        }
        if reader.status == .failed { throw AudioTrimError.exportFailed }
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer, length > 0 else { return nil }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        let frameCount = AVAudioFrameCount(length / bytesPerFrame)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let destination = buffer.int16ChannelData?.pointee else { return nil }
        dataPointer.withMemoryRebound(to: Int16.self, capacity: Int(frameCount)) { source in
            destination.update(from: source, count: Int(frameCount))
        }
        return buffer
    }
}
