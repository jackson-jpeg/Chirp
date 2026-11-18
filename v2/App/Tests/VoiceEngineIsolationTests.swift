import AVFoundation
import Foundation
import Speech
import Testing
@testable import Chirp

/// Regression for 2.0.0 (202611172139), which crashed the moment you held Talk.
///
/// TestFlight crash reports (three on 2026-11-18, iPhone 18,2, iOS 27.3):
/// EXC_BREAKPOINT in `dispatch_assert_queue_fail` <- `swift_task_isCurrentExecutor`
/// <- `closure #2 in VoiceEngine.startCapture()` <- `AVAudioNodeTap::CheckEmitBuffer`.
/// The microphone tap was written inside a `@MainActor` method, so Swift 6 made
/// it main-actor isolated and checked that at runtime; AVAudio calls taps on its
/// own realtime messenger queue, so the check trapped on the first buffer.
///
/// These call the real closures on a queue that is not main, as iOS does. With
/// the bug back, the process traps here and the test run fails.
@Suite("Callbacks iOS calls off the main queue")
struct VoiceEngineIsolationTests {
    @Test("The microphone tap runs on AVAudio's queue without trapping")
    func microphoneTapOffMain() async {
        let engine = VoiceEngine()
        nonisolated(unsafe) let tap = VoiceEngine.captureTap(for: engine)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        nonisolated(unsafe) let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        let queue = DispatchQueue(label: "test.avaudio.realtime-messenger", qos: .userInteractive)
        let ranOffMain = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            queue.async {
                tap(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
                done.resume(returning: !Thread.isMainThread)
            }
        }
        #expect(ranOffMain)
    }

    @Test("The speech permission answer arrives off main and reaches the main actor")
    func speechPermissionCallbackOffMain() async {
        let granted = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let handler = LiveCaptions.authorizationHandler { granted in
                #expect(Thread.isMainThread)
                done.resume(returning: granted)
            }
            DispatchQueue.global(qos: .userInitiated).async { handler(.authorized) }
        }
        #expect(granted)
    }
}
