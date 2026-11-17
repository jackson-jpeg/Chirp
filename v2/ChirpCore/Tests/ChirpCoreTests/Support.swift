import Foundation
@testable import ChirpCore

func peer(_ n: UInt8) -> PeerID { PeerID(bytes: Data(repeating: n, count: 16))! }

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

func packet(_ kind: PacketKind = .audio, from origin: PeerID = peer(1), epoch: UInt32 = 1, seq: UInt32,
            channel: ChannelID = .nearby, payload: Data = Data([1, 2, 3])) -> Packet {
    Packet(kind: kind, origin: origin, epoch: epoch, sequence: seq, channel: channel, payload: payload)
}

func newIdentity() -> LocalIdentity { try! LocalIdentity.loadOrCreate(from: MemoryKeyStore()) }

/// Reference wrappers so a test can call a mutating method inside `#expect`.
final class RouterBox {
    var router: Router
    init(local: PeerID) { router = Router(local: local) }
    var blocked: Set<PeerID> { get { router.blocked } set { router.blocked = newValue } }
    func accept(_ p: Packet, now: Date) -> Router.Decision { router.accept(p, now: now) }
}

final class JitterBox {
    var buffer: JitterBuffer
    init(initialDepth: Int, maxDepth: Int) { buffer = JitterBuffer(initialDepth: initialDepth, maxDepth: maxDepth) }
    func push(_ d: Data, sequence: UInt32, from s: JitterBuffer.Speaker) { buffer.push(d, sequence: sequence, from: s) }
    func pull() -> Data? { buffer.pull() }
    var stats: JitterBuffer.Stats { buffer.stats }
    var count: Int { buffer.count }
}
