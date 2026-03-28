import Foundation

protocol TransportProtocol: Sendable {
    func sendAudio(_ data: Data) async throws
    func sendControl(_ message: FloorControlMessage) async throws
    var audioPackets: AsyncStream<Data> { get }
    var controlMessages: AsyncStream<FloorControlMessage> { get }
    var connectedPeers: [ChirpPeer] { get async }
}
