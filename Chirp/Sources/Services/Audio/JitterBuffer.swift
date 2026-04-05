import AVFoundation
import Foundation
import OSLog

final class JitterBuffer: @unchecked Sendable {
    private struct Entry {
        let data: Data
        let sequenceNumber: UInt32
    }

    private let lock = NSLock()
    private var buffer: [Entry] = []
    private var lastPulledSequence: UInt32?
    private var isBuffering: Bool = true

    private let initialDepthFrames: Int
    private let maxDepthFrames: Int
    private let frameSizeBytes: Int

    private(set) var packetsReceived: UInt64 = 0
    private(set) var packetsLost: UInt64 = 0
    private(set) var packetsDroppedLate: UInt64 = 0

    var bufferedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    init(
        initialDepthMs: Int = Constants.JitterBuffer.initialDepthMs,
        maxDepthMs: Int = Constants.JitterBuffer.maxDepthMs
    ) {
        let frameDurationMs = Int(Constants.Opus.frameDuration * 1000)
        self.initialDepthFrames = initialDepthMs / frameDurationMs
        self.maxDepthFrames = maxDepthMs / frameDurationMs
        // Int16 mono, 320 samples per frame = 640 bytes
        self.frameSizeBytes = Constants.Opus.samplesPerFrame * MemoryLayout<Int16>.size

        Logger.audio.info(
            "JitterBuffer: initialDepth=\(self.initialDepthFrames) frames, maxDepth=\(self.maxDepthFrames) frames"
        )
    }

    func push(pcmBuffer: AVAudioPCMBuffer, sequenceNumber: UInt32) {
        let data = pcmBufferToData(pcmBuffer)

        lock.lock()
        defer { lock.unlock() }

        packetsReceived += 1

        // Drop late packets
        if let lastPulled = lastPulledSequence, Int32(bitPattern: sequenceNumber &- lastPulled) <= 0 {
            packetsDroppedLate += 1
            Logger.audio.debug("Dropped late packet seq=\(sequenceNumber), lastPulled=\(lastPulled)")
            return
        }

        // Insert in sequence order
        let insertIndex = buffer.firstIndex { $0.sequenceNumber > sequenceNumber } ?? buffer.endIndex

        // Check for duplicate
        if let prev = buffer.last(where: { $0.sequenceNumber == sequenceNumber }) {
            _ = prev // already have this packet
            return
        }

        buffer.insert(Entry(data: data, sequenceNumber: sequenceNumber), at: insertIndex)

        // Trim overflow: remove oldest frames beyond max depth
        while buffer.count > maxDepthFrames {
            buffer.removeFirst()
            Logger.audio.debug("JitterBuffer overflow, trimmed oldest frame")
        }
    }

    func pull(frameCount: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        // Still buffering until we reach initial depth
        if isBuffering {
            if buffer.count >= initialDepthFrames {
                isBuffering = false
            } else {
                return nil
            }
        }

        guard !buffer.isEmpty else {
            isBuffering = true
            return nil
        }

        var result = Data(capacity: frameCount * frameSizeBytes)

        for _ in 0 ..< frameCount {
            guard !buffer.isEmpty else { break }
            let entry = buffer.removeFirst()

            // Track lost packets
            if let lastSeq = lastPulledSequence {
                let gap = Int(entry.sequenceNumber) - Int(lastSeq) - 1
                if gap > 0 {
                    packetsLost += UInt64(gap)
                }
            }

            lastPulledSequence = entry.sequenceNumber
            result.append(entry.data)
        }

        return result.isEmpty ? nil : result
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        buffer.removeAll()
        lastPulledSequence = nil
        isBuffering = true
        packetsReceived = 0
        packetsLost = 0
        packetsDroppedLate = 0

        Logger.audio.info("JitterBuffer reset")
    }

    func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let int16Data = buffer.int16ChannelData else {
            return Data()
        }
        let frameLength = Int(buffer.frameLength)
        return Data(bytes: int16Data[0], count: frameLength * MemoryLayout<Int16>.size)
    }
}
