import XCTest
@testable import Chirp

final class TransportPreferenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset the static hysteresis state before each test.
        TransportPreference.currentAudioTransport = .both
    }

    // MARK: - Helpers

    /// Build a WALinkMetrics with the given voice latency (ms) and signal strength (dBm).
    private func makeMetrics(
        peerID: String = "peer-1",
        latencyMs: Double,
        signalDBm: Double = -50
    ) -> WALinkMetrics {
        let seconds = Int64(latencyMs / 1000)
        let attoseconds = Int64((latencyMs - Double(seconds) * 1000) * 1_000_000_000_000_000)
        return WALinkMetrics(
            peerID: peerID,
            deviceName: "Test",
            signalStrength: signalDBm,
            voiceLatency: Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
        )
    }

    /// Build a peer list with one MC peer and one WA peer so both transports are active.
    private func makeBothPeers() -> [ChirpPeer] {
        [
            ChirpPeer(id: "mc-1", name: "MC Peer", transportType: .multipeer),
            ChirpPeer(id: "wa-1", name: "WA Peer", transportType: .wifiAware)
        ]
    }

    // MARK: - Audio hysteresis tests

    func testSwitchToWifiAwareOnlyBelowLowThreshold() {
        // Latency 10ms is below the 15ms low threshold -> should switch to .wifiAwareOnly
        let metrics = ["peer-1": makeMetrics(latencyMs: 10)]
        let peers = makeBothPeers()

        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: metrics,
            peers: peers
        )

        XCTAssertEqual(choice, .wifiAwareOnly)
        XCTAssertEqual(TransportPreference.currentAudioTransport, .wifiAwareOnly)
    }

    func testStayOnBothAboveHighThreshold() {
        // Latency 30ms is above the 25ms high threshold -> should switch to .both
        let metrics = ["peer-1": makeMetrics(latencyMs: 30)]
        let peers = makeBothPeers()

        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: metrics,
            peers: peers
        )

        XCTAssertEqual(choice, .both)
        XCTAssertEqual(TransportPreference.currentAudioTransport, .both)
    }

    func testHysteresisKeepsCurrentInDeadBand() {
        let peers = makeBothPeers()

        // First, drive latency below 15ms to set currentAudioTransport = .wifiAwareOnly
        let lowMetrics = ["peer-1": makeMetrics(latencyMs: 10)]
        let firstChoice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: lowMetrics,
            peers: peers
        )
        XCTAssertEqual(firstChoice, .wifiAwareOnly)

        // Now test at 20ms (in the dead band 15-25ms) — should STAY on .wifiAwareOnly
        let midMetrics = ["peer-1": makeMetrics(latencyMs: 20)]
        let secondChoice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: midMetrics,
            peers: peers
        )
        XCTAssertEqual(secondChoice, .wifiAwareOnly, "Should stay on wifiAwareOnly in dead band")

        // Now drive latency above 25ms to switch to .both
        let highMetrics = ["peer-1": makeMetrics(latencyMs: 30)]
        let thirdChoice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: highMetrics,
            peers: peers
        )
        XCTAssertEqual(thirdChoice, .both)

        // Back into the dead band at 20ms — should STAY on .both
        let fourthChoice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: midMetrics,
            peers: peers
        )
        XCTAssertEqual(fourthChoice, .both, "Should stay on .both in dead band")
    }

    // MARK: - Edge cases

    func testWeakSignalFallsBackToBoth() {
        // Good latency but signal below -70 dBm threshold -> no qualifying peer
        let metrics = ["peer-1": makeMetrics(latencyMs: 5, signalDBm: -80)]
        let peers = makeBothPeers()

        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: metrics,
            peers: peers
        )

        XCTAssertEqual(choice, .both)
    }

    func testNoMetricsFallsBackToBoth() {
        let peers = makeBothPeers()

        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: nil,
            peers: peers
        )

        XCTAssertEqual(choice, .both)
    }

    func testEmptyMetricsFallsBackToBoth() {
        let peers = makeBothPeers()

        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: [:],
            peers: peers
        )

        XCTAssertEqual(choice, .both)
    }

    func testOnlyMCPeersReturnsMultipeerOnly() {
        let peers = [ChirpPeer(id: "mc-1", name: "MC Peer", transportType: .multipeer)]
        let metrics = ["peer-1": makeMetrics(latencyMs: 10)]

        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: metrics,
            peers: peers
        )

        XCTAssertEqual(choice, .multipeerOnly)
    }

    func testOnlyWAPeersReturnsWifiAwareOnly() {
        let peers = [ChirpPeer(id: "wa-1", name: "WA Peer", transportType: .wifiAware)]

        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: nil,
            peers: peers
        )

        XCTAssertEqual(choice, .wifiAwareOnly)
    }

    func testControlIntentAlwaysReturnsBoth() {
        let metrics = ["peer-1": makeMetrics(latencyMs: 5)]
        let peers = makeBothPeers()

        let choice = TransportPreference.preferredTransport(
            for: .control,
            wifiAwareMetrics: metrics,
            peers: peers
        )

        XCTAssertEqual(choice, .both, "Control messages always use both transports")
    }

    func testLatencyExactlyAtLowThresholdStaysInDeadBand() {
        let peers = makeBothPeers()

        // Start with .both (default), then check at exactly 15ms
        // 15ms is NOT < 15ms, so it falls into dead band -> stays .both
        let metrics = ["peer-1": makeMetrics(latencyMs: 15)]
        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: metrics,
            peers: peers
        )

        XCTAssertEqual(choice, .both, "Exactly 15ms is in the dead band, should keep current (.both)")
    }

    func testLatencyExactlyAtHighThresholdStaysInDeadBand() {
        let peers = makeBothPeers()

        // First set to .wifiAwareOnly
        let lowMetrics = ["peer-1": makeMetrics(latencyMs: 5)]
        _ = TransportPreference.preferredTransport(for: .audio, wifiAwareMetrics: lowMetrics, peers: peers)

        // Exactly 25ms is NOT > 25ms, so dead band -> stays .wifiAwareOnly
        let metrics = ["peer-1": makeMetrics(latencyMs: 25)]
        let choice = TransportPreference.preferredTransport(
            for: .audio,
            wifiAwareMetrics: metrics,
            peers: peers
        )

        XCTAssertEqual(choice, .wifiAwareOnly, "Exactly 25ms is in the dead band, should keep current (.wifiAwareOnly)")
    }
}
